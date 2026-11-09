import CoreLocation
import FerrostarCoreFFI
import Foundation

/// A speed camera or railroad crossing that lies on the current route.
struct RouteAlert: Identifiable, Hashable {
    enum Kind: Hashable {
        case speedCamera(limitKmh: Int?)
        case railroadCrossing
        /// Live incident from traffic data: TomTom icon category and its description.
        case hazard(category: Int, text: String)
    }

    var kind: Kind
    var coordinate: CLLocationCoordinate2D
    /// Meters from the start of the route.
    var distanceAlong: Double

    var id: String {
        let prefix = switch kind {
        case .speedCamera: "cam"
        case .railroadCrossing: "rail"
        case let .hazard(category, _): "haz\(category)"
        }
        return String(format: "%@-%.5f,%.5f", prefix, coordinate.latitude, coordinate.longitude)
    }

    var isHazard: Bool {
        if case .hazard = kind { return true }
        return false
    }

    var isCamera: Bool {
        if case .speedCamera = kind { return true }
        return false
    }

    /// How far ahead to warn.
    var warnDistance: Double { isHazard ? 2400 : isCamera ? 600 : 400 }

    func title(miles: Bool) -> String {
        switch kind {
        case let .speedCamera(limit):
            guard let limit, limit > 0 else { return "Speed camera ahead" }
            let shown = miles ? Int((Double(limit) / 1.609344).rounded()) : limit
            return "Speed camera ahead · \(shown) \(miles ? "mph" : "km/h")"
        case .railroadCrossing:
            return "Railroad crossing ahead"
        case let .hazard(category, _):
            return Self.hazardLabel(category, polish: false)
        }
    }

    static func hazardLabel(_ category: Int, polish: Bool) -> String {
        switch category {
        case 1: polish ? "Wypadek" : "Accident"
        case 2: polish ? "Mgła" : "Fog"
        case 3: polish ? "Niebezpieczeństwo" : "Danger"
        case 5: polish ? "Oblodzenie" : "Ice"
        case 6: polish ? "Korek" : "Traffic jam"
        case 7: polish ? "Zamknięty pas" : "Lane closed"
        case 8: polish ? "Droga zamknięta" : "Road closed"
        case 9: polish ? "Roboty drogowe" : "Roadwork"
        case 10: polish ? "Silny wiatr" : "Strong wind"
        case 11: polish ? "Zalanie" : "Flooding"
        case 14: polish ? "Zepsuty pojazd" : "Broken-down vehicle"
        default: polish ? "Utrudnienie" : "Hazard"
        }
    }

    var hazardSymbol: String {
        guard case let .hazard(category, _) = kind else { return symbol }
        switch category {
        case 1: return "car.side.rear.and.collision.and.car.side.front"
        case 8: return "nosign"
        case 7: return "arrow.triangle.merge"
        case 9: return "cone.fill"
        case 6: return "car.2.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    var spoken: String {
        isCamera ? "Speed camera ahead." : "Railroad crossing ahead."
    }

    var symbol: String { isCamera ? "camera.fill" : "tram.fill" }

    static func == (a: RouteAlert, b: RouteAlert) -> Bool { a.id == b.id && a.distanceAlong == b.distanceAlong }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// All speed cameras and railroad crossings of one offline pack, indexed by location.
final class RoadAlertIndex: @unchecked Sendable {
    private struct Point {
        var lat: Double
        var lon: Double
        var camera: Bool
        var limitKmh: Int
        var direction: Int // degrees, -1 if unknown
    }

    private struct FileFormat: Decodable {
        var cameras: [[Double]]
        var crossings: [[Double]]
    }

    private var points: [Point] = []
    private var grid: [Int64: [Int]] = [:]
    private static let cell = 0.01 // about 1 km

    let cameraCount: Int
    let crossingCount: Int

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FileFormat.self, from: data)
        else { return nil }
        for c in file.cameras where c.count >= 2 {
            points.append(Point(lat: c[0], lon: c[1], camera: true,
                                limitKmh: c.count > 2 ? Int(c[2]) : 0,
                                direction: c.count > 3 ? Int(c[3]) : -1))
        }
        for c in file.crossings where c.count >= 2 {
            points.append(Point(lat: c[0], lon: c[1], camera: false, limitKmh: 0, direction: -1))
        }
        cameraCount = file.cameras.count
        crossingCount = file.crossings.count
        for (i, p) in points.enumerated() {
            grid[Self.key(Int(floor(p.lat / Self.cell)), Int(floor(p.lon / Self.cell))), default: []].append(i)
        }
    }

    private static func key(_ y: Int, _ x: Int) -> Int64 { Int64(y) << 32 | Int64(UInt32(bitPattern: Int32(x))) }

    /// Alerts the route actually drives over, in the order they come.
    func alerts(along geometry: [GeographicCoordinate], cameras: Bool, crossings: Bool) -> [RouteAlert] {
        guard geometry.count > 1, cameras || crossings else { return [] }
        var best: [Int: RouteAlert] = [:]
        var traveled = 0.0

        for i in 0 ..< geometry.count - 1 {
            let a = geometry[i], b = geometry[i + 1]
            // Local flat projection in meters around a.
            let mPerLat = 111_320.0
            let mPerLon = 111_320.0 * cos(a.lat * .pi / 180)
            let bx = (b.lng - a.lng) * mPerLon, by = (b.lat - a.lat) * mPerLat
            let segLen = (bx * bx + by * by).squareRoot()
            defer { traveled += segLen }
            guard segLen > 0.5 else { continue }
            let bearing = (atan2(bx, by) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

            let y0 = Int(floor((min(a.lat, b.lat) - 0.0005) / Self.cell)), y1 = Int(floor((max(a.lat, b.lat) + 0.0005) / Self.cell))
            let x0 = Int(floor((min(a.lng, b.lng) - 0.0007) / Self.cell)), x1 = Int(floor((max(a.lng, b.lng) + 0.0007) / Self.cell))
            for y in y0 ... y1 {
                for x in x0 ... x1 {
                    for idx in grid[Self.key(y, x)] ?? [] where best[idx] == nil {
                        let p = points[idx]
                        if p.camera ? !cameras : !crossings { continue }
                        let px = (p.lon - a.lng) * mPerLon, py = (p.lat - a.lat) * mPerLat
                        let t = max(0, min(1, (px * bx + py * by) / (segLen * segLen)))
                        let dx = px - t * bx, dy = py - t * by
                        let off = (dx * dx + dy * dy).squareRoot()
                        // Crossings sit on the road; cameras stand beside it.
                        guard off <= (p.camera ? 35 : 15) else { continue }
                        if p.camera, p.direction >= 0 {
                            let diff = abs(((Double(p.direction) - bearing) + 540).truncatingRemainder(dividingBy: 360) - 180)
                            if diff > 60 { continue } // camera faces the other way
                        }
                        best[idx] = RouteAlert(
                            kind: p.camera ? .speedCamera(limitKmh: p.limitKmh > 0 ? p.limitKmh : nil) : .railroadCrossing,
                            coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                            distanceAlong: traveled + t * segLen
                        )
                    }
                }
            }
        }

        // Multi-track crossings are several points a few meters apart: keep the first.
        var result: [RouteAlert] = []
        for alert in best.values.sorted(by: { $0.distanceAlong < $1.distanceAlong }) {
            if let last = result.last(where: { $0.isCamera == alert.isCamera }),
               alert.distanceAlong - last.distanceAlong < 60 { continue }
            result.append(alert)
        }
        return result
    }
}
