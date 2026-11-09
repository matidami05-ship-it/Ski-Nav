import FerrostarCore
import FerrostarCoreFFI
import FerrostarMapLibreUI
import MapLibre
import MapLibreSwiftDSL
import CoreLocation
import UIKit

/// A wide, Apple Maps-style route: solid bright blue over a darker blue edge, wide enough to
/// cover the road it follows. Driven-over parts are gray; alternates in the preview are a
/// softer blue-gray.
struct RouteLine: StyleLayerCollection {
    enum Kind {
        case active, travelled, alternate
    }

    var polyline: MLNPolyline
    var identifier: String
    var kind: Kind = .active

    private var colors: (fill: UIColor, edge: UIColor) {
        switch kind {
        case .active:
            (UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1), UIColor(red: 0.0, green: 0.27, blue: 0.68, alpha: 1))
        case .travelled:
            (UIColor(white: 0.62, alpha: 0.9), UIColor(white: 0.38, alpha: 0.9))
        case .alternate:
            (UIColor(red: 0.55, green: 0.70, blue: 0.92, alpha: 0.95), UIColor(red: 0.30, green: 0.42, blue: 0.62, alpha: 0.95))
        }
    }

    var layers: [StyleLayerDefinition] {
        let source = ShapeSource(identifier: "\(identifier)-source") {
            polyline
        }
        let scale: Double = kind == .alternate ? 0.8 : 1.0
        return [
            LineStyleLayer(identifier: "\(identifier)-edge", source: source)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(colors.edge)
                .lineWidth(interpolatedBy: .zoomLevel,
                           curveType: .exponential,
                           parameters: NSExpression(forConstantValue: 1.5),
                           stops: NSExpression(forConstantValue: [
                               10: 6 * scale, 13: 10 * scale, 15: 16 * scale, 17: 28 * scale, 19: 52 * scale, 21: 90 * scale,
                           ]))
                .renderBelow(.symbols),
            LineStyleLayer(identifier: "\(identifier)-fill", source: source)
                .lineCap(.round)
                .lineJoin(.round)
                .lineColor(colors.fill)
                .lineWidth(interpolatedBy: .zoomLevel,
                           curveType: .exponential,
                           parameters: NSExpression(forConstantValue: 1.5),
                           stops: NSExpression(forConstantValue: [
                               10: 4 * scale, 13: 7 * scale, 15: 12 * scale, 17: 22 * scale, 19: 44 * scale, 21: 78 * scale,
                           ]))
                .renderBelow(.symbols),
        ]
    }
}

extension RouteLine {
    /// Splits a route at the point closest to `location` into the part already driven and
    /// the part still ahead.
    static func split(_ geometry: [GeographicCoordinate], at location: CLLocationCoordinate2D?)
        -> (travelled: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D])
    {
        let coords = geometry.map(\.clLocationCoordinate2D)
        guard let location, coords.count > 1 else { return ([], coords) }
        var best = 0, bestD = Double.infinity
        for (i, c) in coords.enumerated() {
            let dx = (c.longitude - location.longitude) * cos(location.latitude * .pi / 180)
            let dy = c.latitude - location.latitude
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = i }
        }
        let travelled = Array(coords[...best]) + [location]
        let remaining = [location] + Array(coords[min(best + 1, coords.count - 1)...])
        return (travelled.count > 1 ? travelled : [], remaining)
    }
}
