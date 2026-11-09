import CoreLocation
import Foundation
import MapKit

/// A place the user can see on the map or drive to.
struct Place: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var category: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    init(id: String = UUID().uuidString, name: String, subtitle: String,
         coordinate: CLLocationCoordinate2D, category: String? = nil)
    {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.category = category
    }

    init(mapItem: MKMapItem) {
        let mark = mapItem.placemark
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, mark.locality, mark.administrativeArea]
            .compactMap { $0 }
            .filter { $0 != mapItem.name }
        self.init(
            id: "apple-\(mark.coordinate.latitude),\(mark.coordinate.longitude)-\(mapItem.name ?? "")",
            name: mapItem.name ?? street,
            subtitle: parts.joined(separator: ", "),
            coordinate: mark.coordinate,
            category: mapItem.pointOfInterestCategory.map { Place.label(for: $0) }
        )
    }

    /// A dropped pin or a coordinate the user typed.
    static func pin(_ coordinate: CLLocationCoordinate2D, name: String = "Dropped Pin") -> Place {
        Place(
            id: "pin-\(coordinate.latitude),\(coordinate.longitude)",
            name: name,
            subtitle: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
            coordinate: coordinate
        )
    }

    var symbol: String {
        let c = (category ?? subtitle).lowercased()
        if c.contains("fuel") || c.contains("gas") { return "fuelpump.fill" }
        if c.contains("charging") { return "bolt.car.fill" }
        if c.contains("restaurant") || c.contains("fast food") || c.contains("food") { return "fork.knife" }
        if c.contains("cafe") || c.contains("coffee") { return "cup.and.saucer.fill" }
        if c.contains("bar") || c.contains("pub") { return "wineglass.fill" }
        if c.contains("hotel") || c.contains("motel") { return "bed.double.fill" }
        if c.contains("hospital") || c.contains("clinic") || c.contains("pharmacy") { return "cross.case.fill" }
        if c.contains("park") { return "tree.fill" }
        if c.contains("parking") { return "parkingsign" }
        if c.contains("school") || c.contains("college") || c.contains("university") { return "graduationcap.fill" }
        if c.contains("supermarket") || c.contains("grocery") || c.contains("shop") || c.contains("store") { return "cart.fill" }
        if c.contains("street") { return "road.lanes" }
        if c.contains("address") { return "house.fill" }
        if c.contains("city") || c.contains("town") || c.contains("village") || c.contains("hamlet") { return "building.2.fill" }
        if id.hasPrefix("pin-") { return "mappin" }
        return "mappin.circle.fill"
    }

    private static func label(for category: MKPointOfInterestCategory) -> String {
        category.rawValue
            .replacingOccurrences(of: "MKPOICategory", with: "")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }
}
