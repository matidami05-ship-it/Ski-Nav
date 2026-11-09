import CoreLocation
import Foundation
import MapKit
import Network
import Observation

/// Watches whether the phone currently has an internet connection.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity"))
    }
}

/// Search box logic: offline results from the downloaded pack, plus Apple's results when online.
@MainActor
@Observable
final class PlaceSearch {
    var query = "" {
        didSet { schedule() }
    }

    private(set) var results: [Place] = []
    private(set) var isSearching = false
    private(set) var usedOnline = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var offlineDB: OfflineSearchDB?
    @ObservationIgnored private var offlineDBPath: String?
    @ObservationIgnored var nearProvider: () -> CLLocationCoordinate2D? = { nil }

    func useOfflineDatabase(_ url: URL?) {
        guard url?.path != offlineDBPath else { return }
        offlineDBPath = url?.path
        offlineDB = url.flatMap { OfflineSearchDB(url: $0) }
        schedule()
    }

    var hasOfflineDatabase: Bool { offlineDB != nil }
    var database: OfflineSearchDB? { offlineDB }

    func clear() {
        query = ""
        results = []
    }

    private func schedule() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            let found = await self.run(text)
            guard !Task.isCancelled else { return }
            self.results = found
            self.isSearching = false
        }
    }

    private func run(_ text: String) async -> [Place] {
        let near = nearProvider()

        // "43.07, -89.40" style coordinates.
        if let coordinate = Self.parseCoordinate(text) {
            return [Place.pin(coordinate, name: "Coordinates")]
        }

        let db = offlineDB
        async let offline: [Place] = Task.detached(priority: .userInitiated) {
            db?.search(text, near: near) ?? []
        }.value

        var online: [Place] = []
        let wantOnline = Connectivity.shared.isOnline && AppSettings.shared.useOnlineWhenAvailable
        if wantOnline {
            online = await Self.appleSearch(text, near: near)
        }
        usedOnline = !online.isEmpty

        let local = await offline
        // Apple's results first (better business data), then offline ones that aren't duplicates.
        var merged = online
        for p in local where !merged.contains(where: { Self.same($0, p) }) {
            merged.append(p)
        }
        return Array(merged.prefix(30))
    }

    private static func same(_ a: Place, _ b: Place) -> Bool {
        a.name.caseInsensitiveCompare(b.name) == .orderedSame && a.location.distance(from: b.location) < 250
    }

    private static func appleSearch(_ text: String, near: CLLocationCoordinate2D?) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let near {
            request.region = MKCoordinateRegion(center: near, latitudinalMeters: 80000, longitudinalMeters: 80000)
        }
        do {
            let response = try await withThrowingTaskGroup(of: MKLocalSearch.Response.self) { group in
                group.addTask { try await MKLocalSearch(request: request).start() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                    throw URLError(.timedOut)
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            return response.mapItems.prefix(15).map(Place.init(mapItem:))
        } catch {
            return []
        }
    }

    static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    /// Find what's at a coordinate (for dropped pins).
    static func describe(_ coordinate: CLLocationCoordinate2D) async -> Place {
        let pin = Place.pin(coordinate)
        guard Connectivity.shared.isOnline else { return pin }
        let geocoder = CLGeocoder()
        guard let mark = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ).first else { return pin }
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        var place = pin
        if !street.isEmpty { place.name = street }
        place.subtitle = [mark.locality, mark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        return place
    }
}
