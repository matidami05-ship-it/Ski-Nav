import FerrostarCoreFFI
import Foundation
import MapKit

/// Text helpers shared by the screens.
enum Fmt {
    static func distance(_ meters: Double, miles: Bool) -> String {
        let f = MKDistanceFormatter()
        f.units = miles ? .imperial : .metric
        f.unitStyle = .abbreviated
        return f.string(fromDistance: meters)
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return m == 0 ? "\(h) hr" : "\(h) hr \(m) min" }
        return "\(max(1, m)) min"
    }

    static func arrival(after seconds: Double) -> String {
        Date().addingTimeInterval(seconds).formatted(date: .omitted, time: .shortened)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func distanceFormatter(miles: Bool) -> MKDistanceFormatter {
        let f = MKDistanceFormatter()
        f.units = miles ? .imperial : .metric
        f.unitStyle = .abbreviated
        return f
    }
}

extension Route {
    var duration: Double { steps.reduce(0) { $0 + $1.duration } }

    /// The road the route spends the most distance on, for "via I-43".
    var mainRoad: String? {
        var byRoad: [String: Double] = [:]
        for step in steps {
            guard let name = step.roadName, !name.isEmpty else { continue }
            byRoad[name, default: 0] += step.distance
        }
        return byRoad.max { $0.value < $1.value }?.key
    }
}
