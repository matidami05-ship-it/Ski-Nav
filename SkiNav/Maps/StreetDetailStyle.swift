import Foundation
import UIKit

/// Map layers for the detailed 3D look: extruded buildings, and (with the street detail
/// download) real lane markings, crosswalks, sidewalks, railroad tracks and signal icons.
///
/// Sizes are given in meters and converted to screen points per zoom level, so lane lines
/// sit where the lanes really are as you zoom in.
enum StreetDetailStyle {
    static let iconRailroad = "ski-rr"
    static let iconSignal = "ski-signal"
    static let iconStop = "ski-stop"

    // MARK: Helpers

    /// Points per meter at zoom 16 and 22 (around 43°N; close enough for the US Midwest).
    private static let ptPerMeterZ16 = 1.147
    private static let ptPerMeterZ22 = 73.4

    /// Meters (a number or a feature expression) to screen points, scaling with zoom.
    private static func meters(_ m: Any) -> Any {
        ["interpolate", ["exponential", 2], ["zoom"],
         16, ["*", m, ptPerMeterZ16],
         22, ["*", m, ptPerMeterZ22]]
    }

    /// A constant real-world width, with a minimum so it stays visible zoomed out.
    private static func width(_ m: Double, min: Double = 0.5) -> Any {
        ["interpolate", ["exponential", 2], ["zoom"],
         16, Swift.max(min, m * ptPerMeterZ16),
         22, m * ptPerMeterZ22]
    }

    private static let fw: Any = ["get", "fw"]
    private static let bw: Any = ["get", "bw"]
    private static let ow: Any = ["get", "ow"]
    private static let laneW: Any = ["get", "w"]
    private static let lanes: Any = ["max", ["+", ["get", "fw"], ["get", "bw"]], 1]

    private static func line(_ id: String, layer: String, filter: Any, color: Any, width: Any,
                             offset: Any? = nil, dash: [Double]? = nil, opacity: Any = 1,
                             minzoom: Double = 16) -> [String: Any]
    {
        var paint: [String: Any] = ["line-color": color, "line-width": width, "line-opacity": opacity]
        if let offset { paint["line-offset"] = offset }
        if let dash { paint["line-dasharray"] = dash }
        return [
            "id": id, "type": "line", "source": "detail", "source-layer": layer,
            "minzoom": minzoom, "filter": filter,
            "layout": ["line-cap": dash == nil ? "round" : "butt", "line-join": "round"],
            "paint": paint,
        ]
    }

    /// Fade in between zoom 16 and 16.8.
    private static let fadeIn: Any = ["interpolate", ["linear"], ["zoom"], 16, 0, 16.8, 1]

    // MARK: Layers

    static func buildingLayer(dark: Bool) -> [String: Any] {
        [
            "id": "ski-buildings-3d", "type": "fill-extrusion", "source": "protomaps",
            "source-layer": "buildings", "minzoom": 14.5,
            "paint": [
                "fill-extrusion-color": dark ? "#353b46" : "#dcd8d2",
                "fill-extrusion-height": ["interpolate", ["linear"], ["zoom"],
                                          14.5, 0, 15.5, ["coalesce", ["get", "height"], 8]],
                "fill-extrusion-base": ["coalesce", ["get", "min_height"], 0],
                "fill-extrusion-opacity": 0.88,
                "fill-extrusion-vertical-gradient": true,
            ],
        ]
    }

    static func detailLayers(dark: Bool) -> [[String: Any]] {
        let asphalt = dark ? "#4b525e" : "#b8bdc5"
        let marking = dark ? "#e6e6e6" : "#ffffff"
        let yellow = dark ? "#e0b84a" : "#f2c230"
        let sidewalk = dark ? "#3a3f48" : "#e4e1da"
        let curb = dark ? "#5c5f66" : "#cfcac0"
        let notTunnel: Any = ["!=", ["get", "t"], 1]
        let twoWay: Any = ["==", ow, 0]
        let oneWay: Any = ["==", ow, 1]
        let major: Any = ["match", ["get", "c"],
                          ["motorway", "trunk", "primary", "secondary", "tertiary",
                           "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"],
                          true, false]
        let highway: Any = ["match", ["get", "c"],
                            ["motorway", "trunk", "primary", "secondary",
                             "motorway_link", "trunk_link", "primary_link", "secondary_link"],
                            true, false]

        var layers: [[String: Any]] = []

        // Sidewalks and paths under everything else.
        layers.append(line("ski-sidewalk-curb", layer: "paths", filter: ["==", ["get", "k"], "sidewalk"],
                           color: curb, width: width(2.3, min: 1), opacity: fadeIn))
        layers.append(line("ski-sidewalk", layer: "paths", filter: ["==", ["get", "k"], "sidewalk"],
                           color: sidewalk, width: width(1.8, min: 0.8), opacity: fadeIn))
        layers.append(line("ski-path", layer: "paths",
                           filter: ["match", ["get", "k"], ["path", "cycleway", "steps"], true, false],
                           color: dark ? "#6b6e74" : "#c9b99a", width: width(1.2, min: 0.6),
                           dash: [2, 1], opacity: fadeIn))

        // Road surface sized to the real number of lanes.
        let surfaceOffset: Any = ["case", twoWay, ["*", ["/", ["-", fw, bw], 2], laneW], 0]
        let surfaceWidth: Any = ["+", ["*", lanes, laneW], 0.8]
        layers.append(line("ski-road-surface", layer: "roads", filter: notTunnel, color: asphalt,
                           width: meters(surfaceWidth), offset: meters(surfaceOffset), opacity: fadeIn))

        // Edge lines on bigger roads.
        let rightEdge: Any = ["case", twoWay, ["-", ["*", fw, laneW], 0.2],
                              ["-", ["/", ["*", lanes, laneW], 2], 0.2]]
        let leftEdge: Any = ["case", twoWay, ["+", ["*", ["*", bw, -1], laneW], 0.2],
                             ["+", ["/", ["*", ["*", lanes, laneW], -1], 2], 0.2]]
        let edgeFilter: Any = ["all", notTunnel, highway]
        layers.append(line("ski-edge-right", layer: "roads", filter: edgeFilter, color: marking,
                           width: width(0.15), offset: meters(rightEdge), minzoom: 16.5))
        layers.append(line("ski-edge-left", layer: "roads", filter: edgeFilter, color: ["case", oneWay, yellow, marking] as [Any],
                           width: width(0.15), offset: meters(leftEdge), minzoom: 16.5))

        // Double yellow center line on two-way roads.
        let centerFilter: Any = ["all", notTunnel, major, twoWay, [">", fw, 0], [">", bw, 0]]
        for (i, side) in [0.13, -0.13].enumerated() {
            layers.append(line("ski-center-\(i)", layer: "roads", filter: centerFilter, color: yellow,
                               width: width(0.12), offset: meters(side), minzoom: 16.5))
        }

        // Dashed white lines between lanes going the same way.
        for k in 1 ... 5 {
            let kd = Double(k)
            // One-way: lanes centered on the line. Two-way: right-hand lanes.
            let rightFilter: Any = ["all", notTunnel,
                                    ["any", ["all", oneWay, [">", lanes, kd]], ["all", twoWay, [">", fw, kd]]]]
            let rightOffset: Any = ["case", oneWay, ["*", ["-", kd, ["/", lanes, 2]], laneW], ["*", kd, laneW]]
            layers.append(line("ski-lane-r\(k)", layer: "roads", filter: rightFilter, color: marking,
                               width: width(0.13), offset: meters(rightOffset), dash: [22, 66], minzoom: 16.5))
            let leftFilter: Any = ["all", notTunnel, twoWay, [">", bw, kd]]
            layers.append(line("ski-lane-l\(k)", layer: "roads", filter: leftFilter, color: marking,
                               width: width(0.13), offset: meters(["*", -kd, laneW]), dash: [22, 66], minzoom: 16.5))
        }

        // Zebra crosswalks: a wide dashed white line gives stripes across the road.
        layers.append(line("ski-crosswalk", layer: "paths", filter: ["==", ["get", "k"], "crossing"],
                           color: marking, width: width(3.0, min: 1.2), dash: [0.2, 0.25], opacity: fadeIn))

        // Railroad: ties, then the two rails.
        layers.append(line("ski-rail-ties", layer: "rail", filter: true, color: dark ? "#5a4a3c" : "#8a7560",
                           width: width(2.6, min: 1.2), dash: [0.22, 0.5], opacity: fadeIn))
        for (i, side) in [0.72, -0.72].enumerated() {
            layers.append(line("ski-rail-\(i)", layer: "rail", filter: true, color: dark ? "#9aa0a8" : "#5b6068",
                               width: width(0.15, min: 0.6), offset: meters(side), opacity: fadeIn))
        }

        // Icons: railroad crossings, traffic lights, stop signs.
        func icon(_ id: String, kind: String, image: String, minzoom: Double) -> [String: Any] {
            [
                "id": id, "type": "symbol", "source": "detail", "source-layer": "points", "minzoom": minzoom,
                "filter": ["==", ["get", "k"], kind],
                "layout": [
                    "icon-image": image,
                    "icon-size": ["interpolate", ["linear"], ["zoom"], minzoom, 0.55, 19, 1.0],
                    "icon-allow-overlap": kind == "level_crossing",
                    "icon-anchor": "bottom",
                ],
            ]
        }
        layers.append(icon("ski-icon-rr", kind: "level_crossing", image: iconRailroad, minzoom: 15.5))
        layers.append(icon("ski-icon-signal", kind: "traffic_signals", image: iconSignal, minzoom: 16.5))
        layers.append(icon("ski-icon-stop", kind: "stop", image: iconStop, minzoom: 17))
        return layers
    }

    /// Adds the 3D layers to a style JSON (as parsed by JSONSerialization).
    static func apply(to style: inout [String: Any], detailURL: String?, dark: Bool, buildings: Bool) {
        guard var layers = style["layers"] as? [[String: Any]] else { return }
        // Everything goes under the labels.
        let labelsAt = layers.firstIndex { ($0["type"] as? String) == "symbol" } ?? layers.count
        var insert: [[String: Any]] = []
        if let detailURL {
            var sources = style["sources"] as? [String: Any] ?? [:]
            sources["detail"] = ["type": "vector", "url": "pmtiles://\(detailURL)", "minzoom": 16, "maxzoom": 16]
            style["sources"] = sources
            insert += detailLayers(dark: dark)
        }
        if buildings { insert.append(buildingLayer(dark: dark)) }
        layers.insert(contentsOf: insert, at: labelsAt)
        style["layers"] = layers
    }

    // MARK: Icons

    /// Images the icon layers use; added to the map style once it loads.
    static let images: [String: UIImage] = [
        iconRailroad: crossbuck(),
        iconSignal: trafficLight(),
        iconStop: stopSign(),
    ]

    private static func crossbuck() -> UIImage {
        let size = CGSize(width: 34, height: 40)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            // Post
            c.setFillColor(UIColor.darkGray.cgColor)
            c.fill(CGRect(x: 15.5, y: 16, width: 3, height: 24))
            // Two crossed white boards with black outline.
            for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
                c.saveGState()
                c.translateBy(x: 17, y: 15)
                c.rotate(by: angle)
                let board = CGRect(x: -16, y: -3.5, width: 32, height: 7)
                c.setFillColor(UIColor.white.cgColor)
                c.fill(board)
                c.setStrokeColor(UIColor.black.cgColor)
                c.setLineWidth(1.2)
                c.stroke(board)
                c.restoreGState()
            }
        }
    }

    private static func trafficLight() -> UIImage {
        let size = CGSize(width: 16, height: 36)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 14, height: 34), cornerRadius: 4).cgPath)
            c.fillPath()
            for (i, color) in [UIColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                c.setFillColor(color.cgColor)
                c.fillEllipse(in: CGRect(x: 3.5, y: 4 + CGFloat(i) * 10.3, width: 9, height: 9))
            }
        }
    }

    private static func stopSign() -> UIImage {
        let size = CGSize(width: 26, height: 26)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            let r: CGFloat = 12.5
            for i in 0 ..< 8 {
                let a = CGFloat(i) * .pi / 4 + .pi / 8
                let p = CGPoint(x: 13 + r * cos(a), y: 13 + r * sin(a))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.close()
            UIColor.white.setFill(); path.fill()
            let inner = UIBezierPath()
            for i in 0 ..< 8 {
                let a = CGFloat(i) * .pi / 4 + .pi / 8
                let p = CGPoint(x: 13 + (r - 1.6) * cos(a), y: 13 + (r - 1.6) * sin(a))
                if i == 0 { inner.move(to: p) } else { inner.addLine(to: p) }
            }
            inner.close()
            UIColor(red: 0.8, green: 0.05, blue: 0.08, alpha: 1).setFill(); inner.fill()
            let text = "STOP" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7.5, weight: .black), .foregroundColor: UIColor.white,
            ]
            let t = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: 13 - t.width / 2, y: 13 - t.height / 2), withAttributes: attrs)
        }
    }
}
