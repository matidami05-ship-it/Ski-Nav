import Foundation

/// Final touches applied to every map style:
/// - an invisible "anchor" layer just under the top block of labels, so the route line,
///   traffic and street detail always draw above every road (some styles put a label layer
///   early, which used to push the route underneath the roads);
/// - the Ski Nav night palette for the online (OpenMapTiles) map, matching the offline one.
enum StyleTweaks {
    static let anchorID = "ski-labels-anchor"

    /// Where overlays go: right after the last non-label layer.
    static func overlayIndex(_ layers: [[String: Any]]) -> Int {
        if let anchor = layers.firstIndex(where: { ($0["id"] as? String) == anchorID }) { return anchor }
        guard let last = layers.lastIndex(where: { ($0["type"] as? String) != "symbol" }) else { return 0 }
        return last + 1
    }

    static func addAnchor(_ style: inout [String: Any]) {
        guard var layers = style["layers"] as? [[String: Any]],
              !layers.contains(where: { ($0["id"] as? String) == anchorID })
        else { return }
        let at = overlayIndex(layers)
        layers.insert(["id": anchorID, "type": "background", "layout": ["visibility": "none"],
                       "paint": ["background-opacity": 0]], at: at)
        style["layers"] = layers
    }

    // MARK: Night palette for OpenMapTiles styles (the online map)

    private static let land = "#1f242b"
    private static let water = "#3c5f97"
    private static let casing = "#1a1e24"

    static func nightOnline(_ style: inout [String: Any]) {
        guard var layers = style["layers"] as? [[String: Any]] else { return }
        for i in layers.indices {
            var layer = layers[i]
            let id = (layer["id"] as? String ?? "").lowercased()
            let type = layer["type"] as? String ?? ""
            let sourceLayer = (layer["source-layer"] as? String ?? "").lowercased()
            var paint = layer["paint"] as? [String: Any] ?? [:]

            switch type {
            case "background":
                paint["background-color"] = land
            case "fill":
                if sourceLayer == "water" {
                    paint["fill-color"] = water
                } else if sourceLayer == "building" {
                    paint["fill-color"] = "#2d323b"
                    paint["fill-outline-color"] = "#3a404b"
                } else if ["wood", "forest", "grass", "park", "golf", "pitch", "cemetery"].contains(where: { id.contains($0) || sourceLayer.contains($0) }) {
                    paint["fill-color"] = "#24463d"
                } else if ["commercial", "retail", "industrial"].contains(where: { id.contains($0) }) {
                    paint["fill-color"] = "#3b2840"
                } else if sourceLayer.contains("land") || sourceLayer == "aeroway" {
                    paint["fill-color"] = "#232830"
                }
                paint.removeValue(forKey: "fill-pattern")
            case "fill-extrusion":
                paint["fill-extrusion-color"] = "#353b46"
            case "line":
                if sourceLayer == "waterway" {
                    paint["line-color"] = water
                } else if sourceLayer == "transportation" {
                    paint["line-color"] = roadColor(id)
                    if id.contains("casing") { paint["line-opacity"] = 1 }
                } else if sourceLayer == "boundary" {
                    paint["line-color"] = "#6b7385"
                }
            case "raster", "hillshade":
                paint["raster-opacity"] = type == "raster" ? 0.12 : nil
                if type == "hillshade" { paint["hillshade-shadow-color"] = "#11151a"; paint["hillshade-highlight-color"] = "#2a3038" }
            case "symbol":
                let text: String
                switch sourceLayer {
                case "transportation_name": text = "#e6e9ee"
                case "place": text = "#f4f6f9"
                case "water_name": text = "#a9c2e6"
                default: text = "#c9ced6"
                }
                paint["text-color"] = text
                paint["text-halo-color"] = land
                paint["text-halo-width"] = 1.4
            default:
                break
            }
            layer["paint"] = paint
            layers[i] = layer
        }
        style["layers"] = layers
    }

    /// Clear gray roads, brighter as they get bigger (AmiGO style).
    private static func roadColor(_ id: String) -> String {
        if id.contains("casing") || id.contains("subtle") { return casing }
        if id.contains("rail") || id.contains("transit") { return "#5f6673" }
        if id.contains("motorway") { return "#95a0b4" }
        if id.contains("trunk") || id.contains("primary") || id.contains("major") { return "#7f8a9e" }
        if id.contains("secondary") || id.contains("tertiary") { return "#7a8598" }
        if id.contains("path") || id.contains("track") || id.contains("pedestrian") { return "#4c5563" }
        return "#5f697a"
    }
}
