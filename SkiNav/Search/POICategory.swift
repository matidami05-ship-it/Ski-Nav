import MapKit
import SwiftUI

/// Kinds of places you can browse nearby or along the route.
enum POICategory: String, CaseIterable, Identifiable {
    case gas, ev, food, coffee, groceries, parking, hotels, atm, pharmacy, hospital, carWash, bars

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gas: "Gas"
        case .ev: "EV Charging"
        case .food: "Food"
        case .coffee: "Coffee"
        case .groceries: "Groceries"
        case .parking: "Parking"
        case .hotels: "Hotels"
        case .atm: "ATMs & Banks"
        case .pharmacy: "Pharmacy"
        case .hospital: "Hospitals"
        case .carWash: "Car Wash"
        case .bars: "Bars"
        }
    }

    var symbol: String {
        switch self {
        case .gas: "fuelpump.fill"
        case .ev: "bolt.car.fill"
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .groceries: "cart.fill"
        case .parking: "parkingsign"
        case .hotels: "bed.double.fill"
        case .atm: "dollarsign.circle.fill"
        case .pharmacy: "pills.fill"
        case .hospital: "cross.case.fill"
        case .carWash: "car.side.rear.and.collision.and.car.side.front"
        case .bars: "wineglass.fill"
        }
    }

    var color: Color {
        switch self {
        case .gas: .blue
        case .ev: .green
        case .food, .coffee, .bars: .orange
        case .groceries: .yellow
        case .parking: .indigo
        case .hotels: .purple
        case .atm: .mint
        case .pharmacy, .hospital: .red
        case .carWash: .cyan
        }
    }

    var uiColor: UIColor { UIColor(color) }

    /// The OpenStreetMap types as they appear in the offline database's detail column.
    var osmTypes: [String] {
        switch self {
        case .gas: ["Fuel"]
        case .ev: ["Charging station"]
        case .food: ["Restaurant", "Fast food", "Food court"]
        case .coffee: ["Cafe", "Coffee"]
        case .groceries: ["Supermarket", "Convenience", "Grocery", "Greengrocer"]
        case .parking: ["Parking"]
        case .hotels: ["Hotel", "Motel", "Guest house"]
        case .atm: ["Atm", "Bank"]
        case .pharmacy: ["Pharmacy", "Chemist"]
        case .hospital: ["Hospital", "Clinic", "Doctors"]
        case .carWash: ["Car wash"]
        case .bars: ["Bar", "Pub", "Biergarten"]
        }
    }

    /// Apple's categories, for online results.
    var appleCategories: [MKPointOfInterestCategory] {
        switch self {
        case .gas: [.gasStation]
        case .ev: [.evCharger]
        case .food: [.restaurant]
        case .coffee: [.cafe, .bakery]
        case .groceries: [.foodMarket]
        case .parking: [.parking]
        case .hotels: [.hotel]
        case .atm: [.atm, .bank]
        case .pharmacy: [.pharmacy]
        case .hospital: [.hospital]
        case .carWash: []
        case .bars: [.nightlife, .brewery, .winery]
        }
    }

    /// The handful shown as quick buttons; the rest are under "More".
    static let quick: [POICategory] = [.gas, .food, .coffee, .ev, .groceries, .parking]
}
