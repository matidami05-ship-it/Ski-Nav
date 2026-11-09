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
    }

    /// Anything that changes how routes are calculated.
    var routingKey: String {
        "\(useMiles)-\(avoidTolls)-\(avoidHighways)-\(avoidFerries)"
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
            ],
        ]
    }
}
