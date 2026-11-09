import CoreLocation
import FerrostarCoreFFI
import MapKit

/// A point of interest with how far it is: from you, or ahead along your route.
struct POIResult: Identifiable, Hashable {
    var place: Place
    /// Meters from you (nearby) or meters ahead along the route.
    var distance: Double
    /// Meters off the route, for along-route results.
    var offRoute: Double?
    var id: String { place.id }
}

/// Finds gas stations, food, charging and so on, offline from the downloaded pack and
/// from Apple when there is signal.
enum POIFinder {
    static func nearby(_ category: POICategory, around center: CLLocationCoordinate2D,
                       database: OfflineSearchDB?, online: Bool) async -> [POIResult]
    {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let dLat = 0.15, dLon = 0.15 / max(0.2, cos(center.latitude * .pi / 180))
        let offline: [Place] = await Task.detached(priority: .userInitiated) {
            database?.places(ofTypes: category.osmTypes,
                             minLat: center.latitude - dLat, maxLat: center.latitude + dLat,
                             minLon: center.longitude - dLon, maxLon: center.longitude + dLon) ?? []
        }.value

        var places = offline
        if online, !category.appleCategories.isEmpty {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: 8000)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: category.appleCategories)
            if let response = try? await MKLocalSearch(request: request).start() {
                for item in response.mapItems {
                    let p = Place(mapItem: item)
                    if !places.contains(where: { same($0, p) }) { places.append(p) }
                }
            }
        }

        return places
            .map { POIResult(place: $0, distance: here.distance(from: $0.location)) }
            .sorted { $0.distance < $1.distance }
            .prefix(40)
            .map { $0 }
    }

    /// Places a short detour off the route ahead, nearest first along the way.
    static func alongRoute(_ category: POICategory, geometry: [GeographicCoordinate], traveled: Double,
                           database: OfflineSearchDB?, maxOffRoute: Double = 1200) async -> [POIResult]
    {
        guard let database, geometry.count > 1 else { return [] }
        return await Task.detached(priority: .userInitiated) {
            // Sample the route about every 150 m, remembering distance from the start.
            var samples: [(lat: Double, lon: Double, along: Double)] = []
            var along = 0.0
            var last = geometry[0]
            samples.append((last.lat, last.lng, 0))
            for c in geometry.dropFirst() {
                along += approxMeters(last.lat, last.lng, c.lat, c.lng)
                last = c
                if along - (samples.last?.along ?? 0) >= 150 { samples.append((c.lat, c.lng, along)) }
            }
            if let end = geometry.last { samples.append((end.lat, end.lng, along)) }

            // Only look at the part of the route still ahead (up to 200 km).
            let ahead = samples.filter { $0.along >= traveled - 200 && $0.along <= traveled + 200_000 }
            guard !ahead.isEmpty else { return [] }
            let pad = 0.012
            let minLat = ahead.map(\.lat).min()! - pad, maxLat = ahead.map(\.lat).max()! + pad
            let minLon = ahead.map(\.lon).min()! - pad * 1.4, maxLon = ahead.map(\.lon).max()! + pad * 1.4

            let candidates = database.places(ofTypes: category.osmTypes, minLat: minLat, maxLat: maxLat,
                                             minLon: minLon, maxLon: maxLon, limit: 5000)
            var results: [POIResult] = []
            for place in candidates {
                var best = Double.infinity, bestAlong = 0.0
                for s in ahead {
                    let d = approxMeters(s.lat, s.lon, place.latitude, place.longitude)
                    if d < best { best = d; bestAlong = s.along }
                }
                if best <= maxOffRoute, bestAlong > traveled {
                    results.append(POIResult(place: place, distance: bestAlong - traveled, offRoute: best))
                }
            }
            return Array(results.sorted { $0.distance < $1.distance }.prefix(40))
        }.value
    }

    private static func same(_ a: Place, _ b: Place) -> Bool {
        a.location.distance(from: b.location) < 120
            && (a.name.localizedCaseInsensitiveContains(b.name) || b.name.localizedCaseInsensitiveContains(a.name))
    }

    static func approxMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let x = (lon2 - lon1) * cos((lat1 + lat2) / 2 * .pi / 180) * 111_320
        let y = (lat2 - lat1) * 111_320
        return (x * x + y * y).squareRoot()
    }
}
