import Foundation
import UIKit

/// Live traffic (TomTom flow + incidents) and satellite imagery layers, added to the map
/// style JSON. These need a connection; with no signal the tiles simply don't load and the
/// offline map shows as usual.
enum TrafficStyle {
    static func flowTiles(key: String) -> String {
        "https://api.tomtom.com/traffic/map/4/tile/flow/relative/{z}/{x}/{y}.pbf?key=\(key)"
    }

    static func incidentTiles(key: String) -> String {
        "https://api.tomtom.com/traffic/map/4/tile/incidents/{z}/{x}/{y}.pbf?key=\(key)"
    }

    static func satelliteTiles(key: String) -> String {
        "https://api.tomtom.com/map/1/tile/sat/main/{z}/{x}/{y}.jpg?key=\(key)"
    }

    // Incident icon names (registered on the map with `images`).
    static let incidentAccident = "ski-inc-accident"
    static let incidentClosed = "ski-inc-closed"
    static let incidentLane = "ski-inc-lane"
    static let incidentWorks = "ski-inc-works"
    static let incidentJam = "ski-inc-jam"
    static let incidentHazard = "ski-inc-hazard"

    static func apply(to style: inout [String: Any], key: String, traffic: Bool, satellite: Bool, dark: Bool) {
        guard var layers = style["layers"] as? [[String: Any]] else { return }
        var sources = style["sources"] as? [String: Any] ?? [:]

        if satellite {
            sources["ski-satellite"] = [
                "type": "raster", "tiles": [satelliteTiles(key: key)], "tileSize": 256, "maxzoom": 19,
                "attribution": "Imagery © TomTom",
            ]
            // Under the roads and labels, over the land and water fills.
            let roadsAt = layers.firstIndex { layer in
                let sl = layer["source-layer"] as? String
                return sl == "roads" || sl == "transportation" || sl == "buildings" || sl == "building"
            } ?? layers.firstIndex { ($0["type"] as? String) == "symbol" } ?? layers.count
            layers.insert([
                "id": "ski-satellite", "type": "raster", "source": "ski-satellite",
                "paint": ["raster-opacity": 1, "raster-fade-duration": 150],
            ], at: roadsAt)
        }

        if traffic {
            sources["ski-traffic"] = ["type": "vector", "tiles": [flowTiles(key: key)], "maxzoom": 18,
                                      "attribution": "Traffic © TomTom"]
            sources["ski-incidents"] = ["type": "vector", "tiles": [incidentTiles(key: key)], "maxzoom": 18]

            let level: Any = ["get", "traffic_level"]
            let oneSide: Any = ["==", ["get", "traffic_road_coverage"], "one_side"]
            let closed: Any = ["has", "road_closure"]
            let major: Any = ["match", ["get", "road_type"],
                              ["Motorway", "International road", "Major road", "Secondary road"], true, false]
            // Red below 40 % of normal speed, orange below 75 %, green otherwise (only on bigger roads).
            let color: Any = ["case",
                              closed, dark ? "#ff3b30" : "#8b0000",
                              ["<", level, 0.4], "#e5312c",
                              ["<", level, 0.75], "#f5a623",
                              "#30c158"]
            let filter: Any = ["any", closed, ["<", level, 0.75], major]
            let width: Any = ["interpolate", ["linear"], ["zoom"], 9, 1.5, 13, 3, 16, 5.5, 19, 9]
            // Two-way roads get a line per direction; shift each to its own side.
            let offset: Any = ["interpolate", ["linear"], ["zoom"],
                               9, ["case", oneSide, 1.2, 0],
                               13, ["case", oneSide, 2.5, 0],
                               16, ["case", oneSide, 4.5, 0],
                               19, ["case", oneSide, 9, 0]]

            let labelsAt = layers.firstIndex { ($0["type"] as? String) == "symbol" } ?? layers.count
            layers.insert(contentsOf: [
                [
                    "id": "ski-traffic-casing", "type": "line", "source": "ski-traffic",
                    "source-layer": "Traffic flow", "filter": filter,
                    "layout": ["line-cap": "round", "line-join": "round"],
                    "paint": ["line-color": dark ? "#000000" : "#ffffff", "line-opacity": 0.55,
                              "line-width": ["interpolate", ["linear"], ["zoom"], 9, 2.5, 13, 4.5, 16, 7.5, 19, 12],
                              "line-offset": offset],
                ],
                [
                    "id": "ski-traffic", "type": "line", "source": "ski-traffic",
                    "source-layer": "Traffic flow", "filter": filter,
                    "layout": ["line-cap": "round", "line-join": "round"],
                    "paint": ["line-color": color, "line-width": width, "line-offset": offset,
                              "line-opacity": ["interpolate", ["linear"], ["zoom"], 8, 0.6, 12, 0.95]],
                ],
                [
                    "id": "ski-closures", "type": "line", "source": "ski-traffic",
                    "source-layer": "Traffic flow", "filter": closed,
                    "paint": ["line-color": "#ffffff", "line-width": width, "line-dasharray": [0.6, 1.4],
                              "line-offset": offset],
                ],
            ] as [[String: Any]], at: labelsAt)

            // Incident icons go above the labels so they're never hidden.
            layers.append([
                "id": "ski-incidents", "type": "symbol", "source": "ski-incidents",
                "source-layer": "Traffic incident POI", "minzoom": 9,
                "layout": [
                    "icon-image": ["match", ["get", "icon_category"],
                                   1, incidentAccident,
                                   8, incidentClosed,
                                   7, incidentLane,
                                   9, incidentWorks,
                                   6, incidentJam,
                                   incidentHazard],
                    "icon-size": ["interpolate", ["linear"], ["zoom"], 9, 0.6, 14, 0.9, 17, 1.0],
                    "icon-allow-overlap": false,
                    "symbol-sort-key": ["*", -1, ["coalesce", ["get", "magnitude"], 0]],
                ],
            ])
        }

        style["sources"] = sources
        style["layers"] = layers
    }

    // MARK: Icons

    static let images: [String: UIImage] = [
        incidentAccident: badge("car.side.rear.and.collision.and.car.side.front", fill: .systemRed),
        incidentClosed: badge("nosign", fill: UIColor(red: 0.65, green: 0.0, blue: 0.0, alpha: 1)),
        incidentLane: badge("arrow.triangle.merge", fill: .systemOrange),
        incidentWorks: badge("cone.fill", fill: .systemOrange),
        incidentJam: badge("car.2.fill", fill: .systemRed),
        incidentHazard: badge("exclamationmark.triangle.fill", fill: .systemYellow, glyph: .black),
    ]

    private static func badge(_ symbol: String, fill: UIColor, glyph: UIColor = .white) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
            fill.setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), cornerRadius: 6).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            if let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(glyph, renderingMode: .alwaysOriginal)
            {
                image.draw(at: CGPoint(x: (size.width - image.size.width) / 2, y: (size.height - image.size.height) / 2))
            }
        }
    }
}
