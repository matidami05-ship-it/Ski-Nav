import Foundation

/// Builds the map style the map view loads.
///
/// With an offline pack installed, the bundled Protomaps style is pointed at the pack's
/// .pmtiles file and the bundled fonts and icons, so the map needs no connection at all.
/// Without one, a free online style (OpenFreeMap) is used.
enum MapStyle {
    static let onlineLight = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
    static let onlineDark = URL(string: "https://tiles.openfreemap.org/styles/dark")!

    private static var cache: [String: URL] = [:]

    @MainActor
    static func url(pack: RegionPack?, dark: Bool, store: RegionStore) -> URL {
        guard let pack else { return dark ? onlineDark : onlineLight }
        let flavor = dark ? "dark" : "light"
        let key = "\(pack.id)-\(pack.version)-\(flavor)"
        if let cached = cache[key], FileManager.default.fileExists(atPath: cached.path) { return cached }

        guard let assets = Bundle.main.resourceURL?.appendingPathComponent("MapAssets", isDirectory: true),
              let template = try? String(
                  contentsOf: assets.appendingPathComponent("styles/\(flavor).json"), encoding: .utf8
              )
        else { return dark ? onlineDark : onlineLight }

        let style = template
            .replacingOccurrences(of: "{{PMTILES}}", with: trimmed(store.fileURL(pack, .map)))
            .replacingOccurrences(of: "{{GLYPHS}}", with: trimmed(assets.appendingPathComponent("fonts", isDirectory: true)))
            .replacingOccurrences(of: "{{SPRITES}}", with: trimmed(assets.appendingPathComponent("sprites", isDirectory: true)))

        let out = store.mapsDir.appendingPathComponent("style-\(key).json")
        do {
            try style.write(to: out, atomically: true, encoding: .utf8)
        } catch {
            return dark ? onlineDark : onlineLight
        }
        cache[key] = out
        return out
    }

    /// file:///path with no trailing slash.
    private static func trimmed(_ url: URL) -> String {
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
