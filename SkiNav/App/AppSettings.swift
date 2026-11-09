import Foundation
import Observation

enum MapAppearance: String, CaseIterable, Identifiable {
    case automatic, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Day"
        case .dark: "Night"
        }
    }
}

enum TravelMode: String, CaseIterable, Identifiable {
    case driving, walking
    var id: String { rawValue }
    var label: String { self == .driving ? "Drive" : "Walk" }
    var symbol: String { self == .driving ? "car.fill" : "figure.walk" }
    /// Valhalla costing model.
    var profile: String { self == .driving ? "auto" : "pedestrian" }
}

/// Apple-style map modes.
enum MapMode: String, CaseIterable, Identifiable {
    case explore, driving, satellite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .explore: "Explore"
        case .driving: "Driving"
        case .satellite: "Satellite"
        }
    }
}

/// User preferences, saved in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var useMiles: Bool { didSet { defaults.set(useMiles, forKey: "useMiles") } }
    var avoidTolls: Bool { didSet { defaults.set(avoidTolls, forKey: "avoidTolls") } }
    var avoidHighways: Bool { didSet { defaults.set(avoidHighways, forKey: "avoidHighways") } }
    var avoidFerries: Bool { didSet { defaults.set(avoidFerries, forKey: "avoidFerries") } }
    var appearance: MapAppearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var voiceMuted: Bool { didSet { defaults.set(voiceMuted, forKey: "voiceMuted") } }
    var speechRate: Double { didSet { defaults.set(speechRate, forKey: "speechRate") } }
    var showSpeedLimit: Bool { didSet { defaults.set(showSpeedLimit, forKey: "showSpeedLimit") } }
    /// Use online search and online routing when there is signal and no offline map covers the trip.
    var useOnlineWhenAvailable: Bool { didSet { defaults.set(useOnlineWhenAvailable, forKey: "useOnline") } }
    var speedCameraAlerts: Bool { didSet { defaults.set(speedCameraAlerts, forKey: "speedCameraAlerts") } }
    var railroadAlerts: Bool { didSet { defaults.set(railroadAlerts, forKey: "railroadAlerts") } }
    var laneGuidance: Bool { didSet { defaults.set(laneGuidance, forKey: "laneGuidance") } }
    var streetView: Bool { didSet { defaults.set(streetView, forKey: "streetView") } }
    var junctionView: Bool { didSet { defaults.set(junctionView, forKey: "junctionView") } }
    var mapMode: MapMode { didSet { defaults.set(mapMode.rawValue, forKey: "mapMode") } }
    /// Free key from developer.tomtom.com, for live traffic and satellite imagery.
    var tomtomKey: String { didSet { defaults.set(tomtomKey, forKey: "tomtomKey") } }
    /// Show traffic while navigating even in Explore mode, like Apple Maps.
    var trafficWhileNavigating: Bool { didSet { defaults.set(trafficWhileNavigating, forKey: "trafficNav") } }
    var buildings3D: Bool { didSet { defaults.set(buildings3D, forKey: "buildings3D") } }
    var streetDetail: Bool { didSet { defaults.set(streetDetail, forKey: "streetDetail") } }
    /// Free-driving map tilted in 3D and turning with you.
    var map3D: Bool { didSet { defaults.set(map3D, forKey: "map3D") } }
    var travelMode: TravelMode { didSet { defaults.set(travelMode.rawValue, forKey: "travelMode") } }
    /// Save where the car is when CarPlay disconnects.
    var autoSaveParking: Bool { didSet { defaults.set(autoSaveParking, forKey: "autoSaveParking") } }
    var activeRegionID: String? { didSet { defaults.set(activeRegionID, forKey: "activeRegionID") } }

    private init() {
        defaults.register(defaults: [
            "useMiles": Locale.current.measurementSystem != .metric,
            "avoidTolls": false,
            "avoidHighways": false,
            "avoidFerries": false,
            "appearance": MapAppearance.automatic.rawValue,
            "voiceMuted": false,
            "speechRate": 0.52,
            "showSpeedLimit": true,
            "useOnline": true,
            "speedCameraAlerts": true,
            "railroadAlerts": true,
            "laneGuidance": true,
            "junctionView": true,
            "streetView": true,
            "travelMode": TravelMode.driving.rawValue,
            "autoSaveParking": true,
            "buildings3D": true,
            "mapMode": MapMode.explore.rawValue,
            "tomtomKey": "",
            "trafficNav": true,
            "streetDetail": true,
            "map3D": false,
        ])
        useMiles = defaults.bool(forKey: "useMiles")
        avoidTolls = defaults.bool(forKey: "avoidTolls")
        avoidHighways = defaults.bool(forKey: "avoidHighways")
        avoidFerries = defaults.bool(forKey: "avoidFerries")
        appearance = MapAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .automatic
        voiceMuted = defaults.bool(forKey: "voiceMuted")
        speechRate = defaults.double(forKey: "speechRate")
        showSpeedLimit = defaults.bool(forKey: "showSpeedLimit")
        useOnlineWhenAvailable = defaults.bool(forKey: "useOnline")
        activeRegionID = defaults.string(forKey: "activeRegionID")
        speedCameraAlerts = defaults.bool(forKey: "speedCameraAlerts")
        railroadAlerts = defaults.bool(forKey: "railroadAlerts")
        laneGuidance = defaults.bool(forKey: "laneGuidance")
        junctionView = defaults.bool(forKey: "junctionView")
        streetView = defaults.bool(forKey: "streetView")
        travelMode = TravelMode(rawValue: defaults.string(forKey: "travelMode") ?? "") ?? .driving
        autoSaveParking = defaults.bool(forKey: "autoSaveParking")
        buildings3D = defaults.bool(forKey: "buildings3D")
        mapMode = MapMode(rawValue: defaults.string(forKey: "mapMode") ?? "") ?? .explore
        tomtomKey = defaults.string(forKey: "tomtomKey") ?? ""
        trafficWhileNavigating = defaults.bool(forKey: "trafficNav")
        streetDetail = defaults.bool(forKey: "streetDetail")
        map3D = defaults.bool(forKey: "map3D")
    }

    var hasTrafficKey: Bool { !tomtomKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Anything that changes how routes are calculated.
    var routingKey: String {
        "\(travelMode.rawValue)-\(useMiles)-\(avoidTolls)-\(avoidHighways)-\(avoidFerries)"
    }

    /// Valhalla request options.
    var routeOptions: [String: Any] {
        [
            "units": useMiles ? "miles" : "kilometers",
            "alternates": 2,
            "costing_options": [
                "auto": [
                    "use_tolls": avoidTolls ? 0.0 : 0.5,
                    "use_highways": avoidHighways ? 0.0 : 1.0,
                    "use_ferry": avoidFerries ? 0.0 : 0.5,
                ],
                "pedestrian": [
                    "use_ferry": avoidFerries ? 0.0 : 0.5,
                    "walkway_factor": 0.9,
                    "sidewalk_factor": 0.9,
                ],
            ],
        ]
    }
}
