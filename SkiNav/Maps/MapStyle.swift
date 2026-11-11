import Foundation

/// Builds the map style the map view loads.
///
/// With an offline pack installed, the bundled Protomaps style is pointed at the pack's
/// .pmtiles file and the bundled fonts and icons, so the map needs no connection at all.
/// Without one, a free online style (OpenFreeMap) is used. On top of either come the
/// optional extras: 3D buildings, street detail, live traffic and satellite imagery.
enum MapStyle {
    static let onlineLight = URL(string: "https://tiles.openfreemap.org/styles/liberty")!
    static let onlineDark = URL(string: "https://tiles.openfreemap.org/styles/dark")!

    private static var cache: [String: URL] = [:]

    @MainActor
    static func url(pack: RegionPack?, dark: Bool, store: RegionStore, navigating: Bool = false) -> URL {
        let settings = AppSettings.shared
        let flavor = dark ? "dark" : "light"
        let key = settings.tomtomKey.trimmingCharacters(in: .whitespaces)
        let satellite = !key.isEmpty && settings.mapMode == .satellite
        let traffic = !key.isEmpty && (settings.mapMode != .explore || (navigating && settings.trafficWhileNavigating))
            && (settings.trafficFlow || settings.trafficIncidents)
        let detail = pack.flatMap { settings.streetDetail ? store.detailURL($0) : nil }
        let buildings = settings.buildings3D && pack != nil

        let cacheKey = [
            pack.map { "\($0.id)-\($0.version)" } ?? "online", flavor, "v4",
            detail != nil ? "d" : "", buildings ? "b" : "", traffic ? "t" : "", satellite ? "s" : "",
            settings.trafficFlow ? "f" : "", settings.trafficIncidents ? "i" : "",
            String(key.utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 100_000),
        ].joined(separator: "-")
        if let cached = cache[cacheKey], FileManager.default.fileExists(atPath: cached.path) { return cached }

        let fallback = dark ? onlineDark : onlineLight
        guard var text = template(pack: pack, flavor: flavor, store: store) else { return fallback }

        if let data = text.data(using: .utf8),
           var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        {
            if pack == nil, dark {
                StyleTweaks.nightOnline(&json) // offline styles already use the night palette
            }
            LabelStyle.apply(&json, dark: dark, satellite: satellite)
            if detail != nil || buildings {
                StreetDetailStyle.apply(to: &json, detailURL: detail.map(trimmed), dark: dark, buildings: buildings)
            }
            if traffic || satellite {
                TrafficStyle.apply(to: &json, key: key, traffic: traffic, satellite: satellite, dark: dark,
                                   flow: settings.trafficFlow, incidents: settings.trafficIncidents)
            }
            // Last, so the route line (drawn just under this) sits above traffic and roads.
            StyleTweaks.addAnchor(&json)
            if let out = try? JSONSerialization.data(withJSONObject: json),
               let s = String(data: out, encoding: .utf8)
            {
                text = s
            }
        }

        let out = store.mapsDir.appendingPathComponent("style-\(cacheKey).json")
        do {
            try text.write(to: out, atomically: true, encoding: .utf8)
        } catch {
            return fallback
        }
        cache[cacheKey] = out
        return out
    }

    /// The style JSON before extras: the bundled offline style filled in, or a saved copy of
    /// the online style.
    @MainActor
    private static func template(pack: RegionPack?, flavor: String, store: RegionStore) -> String? {
        guard let pack else {
            return try? String(contentsOf: onlineCopy(flavor, store: store), encoding: .utf8)
        }
        guard let assets = Bundle.main.resourceURL?.appendingPathComponent("MapAssets", isDirectory: true),
              let template = try? String(
                  contentsOf: assets.appendingPathComponent("styles/\(flavor).json"), encoding: .utf8
              )
        else { return nil }
        return template
            .replacingOccurrences(of: "{{PMTILES}}", with: trimmed(store.fileURL(pack, .map)))
            .replacingOccurrences(of: "{{GLYPHS}}", with: trimmed(assets.appendingPathComponent("fonts", isDirectory: true)))
            .replacingOccurrences(of: "{{SPRITES}}", with: trimmed(assets.appendingPathComponent("sprites", isDirectory: true)))
    }

    @MainActor
    private static func onlineCopy(_ flavor: String, store: RegionStore) -> URL {
        store.mapsDir.appendingPathComponent("online-\(flavor)-liberty.json")
    }

    /// Keep a copy of the online styles so traffic and satellite can be added to them too
    /// before any offline map is downloaded.
    @MainActor
    static func saveOnlineStyles(store: RegionStore) async {
        // The detailed "liberty" style for both; at night it's recolored to the Ski Nav palette.
        for (flavor, url) in [("light", onlineLight), ("dark", onlineLight)] {
            let dest = onlineCopy(flavor, store: store)
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            if let result = try? await URLSession.shared.data(from: url),
               (result.1 as? HTTPURLResponse)?.statusCode == 200,
               (try? JSONSerialization.jsonObject(with: result.0)) != nil
            {
                try? result.0.write(to: dest, options: .atomic)
            }
        }
    }

    /// file:///path with no trailing slash.
    private static func trimmed(_ url: URL) -> String {
        var s = url.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
