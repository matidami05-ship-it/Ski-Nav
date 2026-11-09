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

    /// Predicted trip for a future time: give `arriveAt` (when to leave?) or `departAt`
    /// (when will I arrive?). Uses TomTom's historic and predicted traffic for that time.
    static func plan(geometry: [GeographicCoordinate], stops: [CLLocationCoordinate2D], key: String,
                     arriveAt: Date? = nil, departAt: Date? = nil) async -> (departure: Date, arrival: Date, delay: Double)?
    {
        guard !key.isEmpty, geometry.count >= 2, let first = geometry.first, let last = geometry.last else { return nil }
        var locations = [CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)]
        locations += stops.dropLast()
        locations.append(CLLocationCoordinate2D(latitude: last.lat, longitude: last.lng))
        let path = locations.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: ":")
        let step = max(1, geometry.count / 150)
        var points = stride(from: 0, to: geometry.count, by: step).map { geometry[$0] }
        if points.last != last { points.append(last) }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = .current
        var items = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "traffic", value: "true"),
            URLQueryItem(name: "routeRepresentation", value: "summaryOnly"),
            URLQueryItem(name: "travelMode", value: "car"),
        ]
        if let arriveAt { items.append(URLQueryItem(name: "arriveAt", value: iso.string(from: arriveAt))) }
        if let departAt { items.append(URLQueryItem(name: "departAt", value: iso.string(from: departAt))) }
        var components = URLComponents(string: "https://api.tomtom.com/routing/1/calculateRoute/\(path)/json")!
        components.queryItems = items
        // "+" in the time zone offset must be escaped in a query string.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "supportingPoints": points.map { ["latitude": $0.lat, "longitude": $0.lng] },
        ])
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let summary = (obj["routes"] as? [[String: Any]])?.first?["summary"] as? [String: Any],
              let depText = summary["departureTime"] as? String,
              let arrText = summary["arrivalTime"] as? String,
              let departure = iso.date(from: depText), let arrival = iso.date(from: arrText)
        else { return nil }
        let delay = (summary["trafficDelayInSeconds"] as? NSNumber)?.doubleValue ?? 0
        return (departure, arrival, delay)
    }

    /// A live incident (accident, roadwork, closure…) from TomTom.
    struct Incident {
        var category: Int
        var description: String
        var delay: Double
        var points: [CLLocationCoordinate2D]
    }

    /// Incidents inside a box (keep it under ~100 x 100 km). TomTom Incident Details API.
    static func incidents(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double, key: String,
                          language: String) async -> [Incident]
    {
        let fields = "{incidents{type,geometry{type,coordinates},properties{iconCategory,delay,events{description}}}}"
        var c = URLComponents(string: "https://api.tomtom.com/traffic/services/5/incidentDetails")!
        c.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "bbox", value: String(format: "%.5f,%.5f,%.5f,%.5f", minLon, minLat, maxLon, maxLat)),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "timeValidityFilter", value: "present"),
        ]
        guard let url = c.url,
              let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let list = obj["incidents"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { item in
            guard let props = item["properties"] as? [String: Any],
                  let geometry = item["geometry"] as? [String: Any]
            else { return nil }
            var points: [CLLocationCoordinate2D] = []
            if let coords = geometry["coordinates"] as? [[Double]] {
                points = coords.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil }
            } else if let c = geometry["coordinates"] as? [Double], c.count >= 2 {
                points = [CLLocationCoordinate2D(latitude: c[1], longitude: c[0])]
            }
            let events = props["events"] as? [[String: Any]] ?? []
            return Incident(
                category: (props["iconCategory"] as? NSNumber)?.intValue ?? 0,
                description: events.first?["description"] as? String ?? "",
                delay: (props["delay"] as? NSNumber)?.doubleValue ?? 0,
                points: points
            )
        }
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
