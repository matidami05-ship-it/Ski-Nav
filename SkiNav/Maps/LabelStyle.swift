import Foundation

/// Street and place names restyled to look cleaner, closer to Apple Maps: a medium weight
/// font, sizes that grow smoothly as you zoom in, a little letter spacing, soft halos and
/// calmer colors. Works on both the offline (Protomaps) and online (OpenMapTiles) styles.
enum LabelStyle {
    private struct Palette {
        var minor: String
        var major: String
        var highway: String
        var halo: String
        var place: String
        var placeHalo: String
    }

    private static let day = Palette(minor: "#4a505a", major: "#2f343c", highway: "#262a31",
                                     halo: "rgba(255,255,255,0.96)",
                                     place: "#22262c", placeHalo: "rgba(255,255,255,0.95)")
    private static let night = Palette(minor: "#cfd5de", major: "#eef1f5", highway: "#ffffff",
                                       halo: "rgba(26,30,37,0.92)",
                                       place: "#f4f6f9", placeHalo: "rgba(26,30,37,0.9)")
    /// Over satellite photos labels need a dark outline whatever the time of day.
    private static let photo = Palette(minor: "#ffffff", major: "#ffffff", highway: "#ffffff",
                                       halo: "rgba(0,0,0,0.75)",
                                       place: "#ffffff", placeHalo: "rgba(0,0,0,0.75)")

    static func apply(_ style: inout [String: Any], dark: Bool, satellite: Bool) {
        guard var layers = style["layers"] as? [[String: Any]] else { return }
        let p = satellite ? photo : dark ? night : day

        for i in layers.indices {
            guard (layers[i]["type"] as? String) == "symbol",
                  let id = (layers[i]["id"] as? String)?.lowercased()
            else { continue }
            var layout = layers[i]["layout"] as? [String: Any] ?? [:]
            var paint = layers[i]["paint"] as? [String: Any] ?? [:]
            let sourceLayer = layers[i]["source-layer"] as? String ?? ""
            let alongLine = (layout["symbol-placement"] as? String) == "line"
            let hasIcon = layout["icon-image"] != nil
            let isShield = id.contains("shield") || id.contains("ref") || (hasIcon && alongLine)

            if alongLine, !isShield, ["roads", "transportation_name", "transportation"].contains(sourceLayer) {
                let kind = roadKind(id)
                layout["text-font"] = medium(layout["text-font"])
                layout["text-size"] = kind.size
                layout["text-letter-spacing"] = 0.04
                layout["text-max-angle"] = 28
                layout["text-padding"] = 6
                layout["symbol-spacing"] = 360
                layout["text-pitch-alignment"] = "viewport"
                layout["text-rotation-alignment"] = "map"
                paint["text-color"] = kind == .highway ? p.highway : kind == .major ? p.major : p.minor
                paint["text-halo-color"] = p.halo
                paint["text-halo-width"] = 1.8
                paint["text-halo-blur"] = 0.5
                // Fade in instead of popping in as you zoom.
                if kind == .minor {
                    paint["text-opacity"] = ["interpolate", ["linear"], ["zoom"], 12.5, 0, 13.5, 1] as [Any]
                }
            } else if isPlace(id, sourceLayer: sourceLayer), !alongLine {
                layout["text-font"] = medium(layout["text-font"])
                layout["text-letter-spacing"] = id.contains("city") || id.contains("town") ? 0.03 : 0.06
                if id.contains("neighbourhood") || id.contains("subplace") || id.contains("suburb") {
                    layout["text-transform"] = "uppercase"
                    layout["text-letter-spacing"] = 0.12
                    paint["text-color"] = dark && !satellite ? "#aab1bd" : satellite ? "#ffffff" : "#6b7280"
                } else {
                    paint["text-color"] = p.place
                }
                paint["text-halo-color"] = p.placeHalo
                paint["text-halo-width"] = 1.8
                paint["text-halo-blur"] = 0.5
            }

            layers[i]["layout"] = layout
            layers[i]["paint"] = paint
        }
        style["layers"] = layers
    }

    // MARK: Helpers

    private enum RoadKind {
        case minor, major, highway

        var size: Any {
            switch self {
            case .minor: ["interpolate", ["exponential", 1.4], ["zoom"], 13, 11, 15, 12.5, 17, 14.5, 19, 17] as [Any]
            case .major: ["interpolate", ["exponential", 1.4], ["zoom"], 10, 11, 14, 13, 17, 15.5, 19, 18] as [Any]
            case .highway: ["interpolate", ["exponential", 1.4], ["zoom"], 8, 11, 13, 13, 17, 16, 19, 18.5] as [Any]
            }
        }
    }

    private static func roadKind(_ id: String) -> RoadKind {
        if id.contains("motorway") || id.contains("highway-name-major") || id.contains("trunk") { return .highway }
        if id.contains("major") || id.contains("primary") || id.contains("secondary") { return .major }
        return .minor
    }

    private static func isPlace(_ id: String, sourceLayer: String) -> Bool {
        sourceLayer == "places" || sourceLayer == "place"
            || id.contains("city") || id.contains("town") || id.contains("village")
    }

    /// Medium weight where the font is available: the bundled offline fonts include it; the
    /// online glyph server only has Regular/Bold/Italic, so those stay as they are.
    private static func medium(_ font: Any?) -> Any? {
        guard let fonts = font as? [String] else { return font }
        return fonts.map { $0 == "NotoSans-Regular" ? "NotoSans-Medium" : $0 }
    }
}
