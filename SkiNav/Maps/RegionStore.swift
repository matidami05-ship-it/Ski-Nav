import CoreLocation
import Foundation
import Observation

/// One downloadable offline pack, as listed in regions.json on the "maps" release.
struct RegionPack: Codable, Identifiable, Hashable {
    struct PackFile: Codable, Hashable {
        var name: String
        var size: Int64
    }

    struct Files: Codable, Hashable {
        var map: PackFile
        var routing: PackFile
        var search: PackFile
        /// Speed cameras and railroad crossings. Small, and added to packs after the fact.
        var alerts: PackFile?
        var all: [PackFile] { [map, routing, search] + (alerts.map { [$0] } ?? []) }
    }

    var id: String
    var name: String
    var bbox: [Double] // minLon, minLat, maxLon, maxLat
    var version: String
    var files: Files

    var totalSize: Int64 { files.all.reduce(0) { $0 + $1.size } }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        guard bbox.count == 4 else { return false }
        return c.longitude >= bbox[0] && c.latitude >= bbox[1] && c.longitude <= bbox[2] && c.latitude <= bbox[3]
    }

    /// Smaller packs first, so the most specific pack wins when several contain a point.
    var area: Double {
        guard bbox.count == 4 else { return .infinity }
        return (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    }
}

enum PackFileKind: String, CaseIterable {
    case map, routing, search
}

/// Downloads, stores and picks the offline map packs.
@MainActor
@Observable
final class RegionStore {
    static let shared = RegionStore()

    static let releaseBase = "https://github.com/matidami05-ship-it/Ski-Nav/releases/download/maps/"

    private(set) var catalog: [RegionPack] = []
    private(set) var installed: [String: RegionPack] = [:]
    private(set) var progress: [String: Double] = [:]
    private(set) var catalogError: String?
    var downloadErrors: [String: String] = [:]
    private(set) var isLoadingCatalog = false
    /// Bumps whenever the set of installed packs changes, so the map and router reload.
    private(set) var revision = 0
    /// Bumps when a pack's road alerts file arrives.
    private(set) var alertsRevision = 0

    let mapsDir: URL

    @ObservationIgnored private var written: [String: [String: Int64]] = [:]
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let delegate: DownloadDelegate

    private init() {
        // Library/SkiNavMaps has no spaces in its path, which keeps map file URLs simple.
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        mapsDir = lib.appendingPathComponent("SkiNavMaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: mapsDir, withIntermediateDirectories: true)

        let delegate = DownloadDelegate()
        self.delegate = delegate
        let config = URLSessionConfiguration.background(withIdentifier: "com.matidami05.skinav.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = mapsDir
        try? dir.setResourceValues(values)

        loadInstalled()
        if let data = try? Data(contentsOf: catalogCacheURL),
           let cached = try? JSONDecoder().decode([RegionPack].self, from: data)
        {
            catalog = cached
        }

        delegate.onProgress = { [weak self] region, file, bytes in
            Task { @MainActor in self?.updateProgress(region: region, file: file, bytes: bytes) }
        }
        delegate.onFileReady = { [weak self] region in
            Task { @MainActor in self?.finishIfComplete(region: region) }
        }
        delegate.onError = { [weak self] region, message in
            Task { @MainActor in self?.fail(region: region, message: message) }
        }
        // Reconnect to downloads that kept going while the app was closed.
        session.getAllTasks { tasks in
            let regions = Set(tasks.compactMap { DownloadDelegate.parse($0.taskDescription)?.region })
            Task { @MainActor in
                for r in regions where self.progress[r] == nil { self.progress[r] = 0 }
            }
        }
    }

    // MARK: Catalog

    private var catalogCacheURL: URL { mapsDir.appendingPathComponent("catalog.json") }

    func refreshCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let url = URL(string: Self.releaseBase + "regions.json")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                catalogError = "No offline maps are published yet. Run the “Build offline maps” workflow on GitHub (and make sure the repo is public)."
                return
            }
            let packs = try JSONDecoder().decode([RegionPack].self, from: data)
            catalog = packs
            catalogError = nil
            try? data.write(to: catalogCacheURL, options: .atomic)
            await ensureAlerts()
        } catch {
            if catalog.isEmpty {
                catalogError = "Couldn’t load the list of maps. Check your connection and try again."
            }
        }
    }

    func updateAvailable(_ id: String) -> Bool {
        guard let have = installed[id], let latest = catalog.first(where: { $0.id == id }) else { return false }
        return latest.version != have.version
    }

    // MARK: Installed packs

    private func regionDir(_ id: String) -> URL { mapsDir.appendingPathComponent(id, isDirectory: true) }
    private func stagingDir(_ id: String) -> URL { regionDir(id).appendingPathComponent("staging", isDirectory: true) }

    func fileURL(_ pack: RegionPack, _ kind: PackFileKind) -> URL {
        let file: RegionPack.PackFile = switch kind {
        case .map: pack.files.map
        case .routing: pack.files.routing
        case .search: pack.files.search
        }
        return regionDir(pack.id).appendingPathComponent(file.name)
    }

    func alertsURL(_ pack: RegionPack) -> URL? {
        guard let file = pack.files.alerts else { return nil }
        let url = regionDir(pack.id).appendingPathComponent(file.name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Packs downloaded before road alerts existed (or with an older alerts file) get just
    /// the small alerts file, without re-downloading the map.
    func ensureAlerts() async {
        for (id, have) in installed {
            guard let latest = catalog.first(where: { $0.id == id })?.files.alerts else { continue }
            let local = regionDir(id).appendingPathComponent(latest.name)
            let localSize = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? nil
            if have.files.alerts == latest, localSize == latest.size { continue }
            guard let url = URL(string: Self.releaseBase + latest.name),
                  let result = try? await URLSession.shared.download(from: url),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200
            else { continue }
            let tmp = result.0
            try? FileManager.default.removeItem(at: local)
            guard (try? FileManager.default.moveItem(at: tmp, to: local)) != nil else { continue }
            var pack = have
            pack.files.alerts = latest
            installed[id] = pack
            if let data = try? JSONEncoder().encode(pack) {
                try? data.write(to: regionDir(id).appendingPathComponent("pack.json"), options: .atomic)
            }
            alertsRevision += 1
        }
    }

    private func loadInstalled() {
        var found: [String: RegionPack] = [:]
        let dirs = (try? FileManager.default.contentsOfDirectory(at: mapsDir, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let info = dir.appendingPathComponent("pack.json")
            guard let data = try? Data(contentsOf: info),
                  let pack = try? JSONDecoder().decode(RegionPack.self, from: data)
            else { continue }
            let complete = PackFileKind.allCases.allSatisfy {
                FileManager.default.fileExists(atPath: fileURL(pack, $0).path)
            }
            if complete { found[pack.id] = pack }
        }
        installed = found
    }

    var installedPacks: [RegionPack] {
        installed.values.sorted { $0.name < $1.name }
    }

    /// The pack used for the map, routing and search. Follows the user's choice, else the
    /// smallest pack around their location, else any pack.
    func activePack(near coordinate: CLLocationCoordinate2D?) -> RegionPack? {
        if let id = AppSettings.shared.activeRegionID, let pack = installed[id] { return pack }
        let packs = installed.values.sorted { $0.area < $1.area }
        if let coordinate, let inside = packs.first(where: { $0.contains(coordinate) }) { return inside }
        return packs.first
    }

    func delete(_ id: String) {
        cancel(id)
        try? FileManager.default.removeItem(at: regionDir(id))
        installed[id] = nil
        if AppSettings.shared.activeRegionID == id { AppSettings.shared.activeRegionID = nil }
        revision += 1
    }

    // MARK: Downloading

    func isDownloading(_ id: String) -> Bool { progress[id] != nil }

    func download(_ pack: RegionPack) {
        guard !isDownloading(pack.id) else { return }
        downloadErrors[pack.id] = nil
        let staging = stagingDir(pack.id)
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(pack) {
            try? data.write(to: staging.appendingPathComponent("pack.json"))
        }
        progress[pack.id] = 0
        written[pack.id] = [:]
        for file in pack.files.all {
            let url = URL(string: Self.releaseBase + file.name)!
            let task = session.downloadTask(with: url)
            task.taskDescription = "\(pack.id)|\(file.name)"
            task.countOfBytesClientExpectsToReceive = file.size
            task.resume()
        }
    }

    func cancel(_ id: String) {
        session.getAllTasks { tasks in
            for task in tasks where DownloadDelegate.parse(task.taskDescription)?.region == id {
                task.cancel()
            }
        }
        progress[id] = nil
        written[id] = nil
        try? FileManager.default.removeItem(at: stagingDir(id))
    }

    private func pendingPack(_ id: String) -> RegionPack? {
        let url = stagingDir(id).appendingPathComponent("pack.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RegionPack.self, from: data)
    }

    private func updateProgress(region: String, file: String, bytes: Int64) {
        guard let pack = pendingPack(region) ?? catalog.first(where: { $0.id == region }) else { return }
        written[region, default: [:]][file] = bytes
        let done = written[region, default: [:]].values.reduce(0, +)
        progress[region] = min(0.999, Double(done) / Double(max(pack.totalSize, 1)))
    }

    private func finishIfComplete(region: String) {
        guard let pack = pendingPack(region) else { return }
        let staging = stagingDir(region)
        let ready = pack.files.all.allSatisfy {
            FileManager.default.fileExists(atPath: staging.appendingPathComponent($0.name).path)
        }
        guard ready else { return }

        let fm = FileManager.default
        let dir = regionDir(region)
        for file in pack.files.all {
            let dest = dir.appendingPathComponent(file.name)
            try? fm.removeItem(at: dest)
            try? fm.moveItem(at: staging.appendingPathComponent(file.name), to: dest)
        }
        let info = dir.appendingPathComponent("pack.json")
        try? fm.removeItem(at: info)
        try? fm.moveItem(at: staging.appendingPathComponent("pack.json"), to: info)
        try? fm.removeItem(at: staging)

        progress[region] = nil
        written[region] = nil
        installed[region] = pack
        revision += 1
    }

    private func fail(region: String, message: String) {
        guard progress[region] != nil else { return }
        cancel(region)
        downloadErrors[region] = message
    }
}

/// URLSession callbacks for the background download session. Runs off the main thread.
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((String, String, Int64) -> Void)?
    var onFileReady: ((String) -> Void)?
    var onError: ((String, String) -> Void)?

    static func parse(_ description: String?) -> (region: String, file: String)? {
        guard let parts = description?.split(separator: "|"), parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private var mapsDir: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkiNavMaps", isDirectory: true)
    }

    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64)
    {
        guard let info = Self.parse(downloadTask.taskDescription) else { return }
        onProgress?(info.region, info.file, totalBytesWritten)
    }

    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let info = Self.parse(downloadTask.taskDescription) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            onError?(info.region, "Download failed (HTTP \(http.statusCode)). Is the Ski-Nav repo public?")
            return
        }
        let staging = mapsDir.appendingPathComponent(info.region).appendingPathComponent("staging")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let dest = staging.appendingPathComponent(info.file)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            onFileReady?(info.region)
        } catch {
            onError?(info.region, "Couldn’t save the map: \(error.localizedDescription)")
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let info = Self.parse(task.taskDescription) else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        onError?(info.region, error.localizedDescription)
    }
}
