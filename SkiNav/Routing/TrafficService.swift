import CoreLocation
import FerrostarCoreFFI
import Foundation

/// Live traffic for a route we already have: TomTom times the exact same roads (our route
/// is sent as "supporting points") with current traffic.
struct TrafficInfo: Equatable {
    /// Travel time with today's traffic, in seconds.
    var travelTime: Double
    /// Extra time because of traffic, in seconds.
    var delay: Double
    var checked: Date

    var isHeavy: Bool { delay >= 600 }
    var isNoticeable: Bool { delay >= 120 }
}

enum TrafficService {
    /// `geometry` is the route (or what's left of it); `stops` are the places to arrive at in order.
    static func check(geometry: [GeographicCoordinate], stops: [CLLocationCoordinate2D], key: String) async -> TrafficInfo? {
        guard !key.isEmpty, geometry.count >= 2, let first = geometry.first, let last = geometry.last else { return nil }

        // Locations: start, intermediate stops, end.
        var locations = [CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)]
        locations += stops.dropLast()
        locations.append(CLLocationCoordinate2D(latitude: last.lat, longitude: last.lng))
        let path = locations.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: ":")

        // Thin the line to at most ~150 points, keeping the start and end.
        let step = max(1, geometry.count / 150)
        var points = stride(from: 0, to: geometry.count, by: step).map { geometry[$0] }
        if points.last != last { points.append(last) }

        var components = URLComponents(string: "https://api.tomtom.com/routing/1/calculateRoute/\(path)/json")!
        components.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "traffic", value: "true"),
            URLQueryItem(name: "routeRepresentation", value: "summaryOnly"),
            URLQueryItem(name: "computeTravelTimeFor", value: "all"),
            URLQueryItem(name: "travelMode", value: "car"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "supportingPoints": points.map { ["latitude": $0.lat, "longitude": $0.lng] },
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let routes = obj["routes"] as? [[String: Any]],
              let summary = routes.first?["summary"] as? [String: Any],
              let travel = (summary["travelTimeInSeconds"] as? NSNumber)?.doubleValue
        else { return nil }
        let delay = (summary["trafficDelayInSeconds"] as? NSNumber)?.doubleValue ?? 0
        return TrafficInfo(travelTime: travel, delay: max(0, delay), checked: Date())
    }

    /// Checks that a key works (one tiny traffic tile).
    static func validate(key: String) async -> Bool {
        guard let url = URL(string: TrafficStyle.flowTiles(key: key)
            .replacingOccurrences(of: "{z}/{x}/{y}", with: "0/0/0"))
        else { return false }
        guard let result = try? await URLSession.shared.data(from: url) else { return false }
        return (result.1 as? HTTPURLResponse)?.statusCode == 200
    }
}
