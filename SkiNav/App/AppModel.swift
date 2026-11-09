import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import FerrostarMapLibreUI
import Foundation
import MapLibre
import MapLibreSwiftUI
import Observation
import AVFoundation
import UIKit

/// How routes are being calculated right now.
enum RoutingMode: Equatable {
    case offline(String) // pack name
    case online
    case unavailable

    var label: String {
        switch self {
        case let .offline(name): "Offline · \(name)"
        case .online: "Online routing"
        case .unavailable: "No map downloaded"
        }
    }
}

enum Screen: Equatable {
    case browse
    case place
    case routes
    case navigating
}

/// The app's state: the map, the selected place, routes and the navigation session.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    /// Public Valhalla server run by FOSSGIS (openstreetmap.de), used only when no offline pack covers the trip.
    static let onlineRoutingURL = "https://valhalla1.openstreetmap.de/route"

    let settings = AppSettings.shared
    let regions = RegionStore.shared
    let library = Library.shared
    let search = PlaceSearch()
    let locationProvider: CoreLocationProvider
    @ObservationIgnored let voice: VoiceSynthesizer

    private(set) var core: FerrostarCore
    private(set) var annotation: AnnotationPublisher<ValhallaExtendedOSRMAnnotation>
    private(set) var routingMode: RoutingMode = .unavailable
    private(set) var activePack: RegionPack?

    var camera: MapViewCamera = .trackUserLocation(zoom: 14)
    var screen: Screen = .browse
    var selectedPlace: Place?
    private(set) var routes: [Route] = []
    var selectedRouteIndex = 0 {
        didSet { if oldValue != selectedRouteIndex { updateRouteAlerts() } }
    }
    private(set) var coreState: NavigationState?
    private(set) var isMuted = false
    private(set) var isLoadingRoutes = false
    var errorMessage: String?
    private(set) var userLocation: CLLocation?
    private(set) var destination: Place?
    private(set) var arrived = false
    var showDownloads = false

    /// Speed cameras and railroad crossings on the route being previewed or driven.
    private(set) var routeAlerts: [RouteAlert] = []
    /// The next alert within warning distance while navigating, and how far away it is.
    private(set) var upcomingAlert: RouteAlert?
    private(set) var upcomingAlertDistance: Double = 0

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var coreCancellables = Set<AnyCancellable>()
    @ObservationIgnored private var builtKey = ""
    @ObservationIgnored private var alertIndex: RoadAlertIndex?
    @ObservationIgnored private var alertIndexKey = ""
    @ObservationIgnored private var announcedAlerts = Set<String>()
    @ObservationIgnored private var alertTask: Task<Void, Never>?

    private init() {
        let location = CoreLocationProvider(activityType: .automotiveNavigation, allowBackgroundLocationUpdates: true)
        let voice = VoiceSynthesizer()
        locationProvider = location
        self.voice = voice
        let built = Self.makeCore(
            pack: nil, settings: AppSettings.shared, regions: RegionStore.shared,
            locationProvider: location, voice: voice
        )
        core = built.core
        annotation = built.annotation
        routingMode = built.mode
        isMuted = AppSettings.shared.voiceMuted

        locationProvider.$lastLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self, let location else { return }
                let first = self.userLocation == nil
                self.userLocation = location.clLocation
                if first { self.refreshRouting() }
            }
            .store(in: &cancellables)

        search.nearProvider = { [weak self] in
            MainActor.assumeIsolated { self?.userLocation?.coordinate }
        }
        bindCore()
    }

    /// Called once the UI is up.
    func start() {
        locationProvider.startUpdating()
        refreshRouting()
        Task { await regions.refreshCatalog() }
    }

    // MARK: Routing engine

    struct BuiltCore {
        var core: FerrostarCore
        var annotation: AnnotationPublisher<ValhallaExtendedOSRMAnnotation>
        var mode: RoutingMode
    }

    static var navigationConfig: SwiftNavigationControllerConfig {
        SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(100.0),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 30,
                distanceAfterEndOfStep: 5,
                minimumHorizontalAccuracy: 32
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(
                distance: 25,
                minimumHorizontalAccuracy: 32
            ),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 45),
            snappedLocationCourseFiltering: .snapToRoute
        )
    }

    private static func makeCore(
        pack: RegionPack?,
        settings: AppSettings,
        regions: RegionStore,
        locationProvider: CoreLocationProvider,
        voice: VoiceSynthesizer
    ) -> BuiltCore {
        let annotation = AnnotationPublisher<ValhallaExtendedOSRMAnnotation>.valhallaExtendedOSRM()
        voice.rate = Float(settings.speechRate)
        let speech = SpokenInstructionObserver(synthesizer: voice, isMuted: settings.voiceMuted)
        let options = settings.routeOptions

        if let pack,
           let provider = try? OfflineRouteProvider(routingTar: regions.fileURL(pack, .routing), options: options)
        {
            let core = FerrostarCore(
                customRouteProvider: provider,
                locationProvider: locationProvider,
                navigationControllerConfig: navigationConfig,
                annotation: annotation,
                spokenInstructionObserver: speech
            )
            return BuiltCore(core: core, annotation: annotation, mode: .offline(pack.name))
        }

        let online = (try? WellKnownRouteProvider.valhalla(endpointUrl: onlineRoutingURL, profile: "auto")
            .withJsonOptions(options: options))
            ?? .valhalla(endpointUrl: onlineRoutingURL, profile: "auto")
        let core: FerrostarCore
        do {
            core = try FerrostarCore(
                wellKnownRouteProvider: online,
                locationProvider: locationProvider,
                navigationControllerConfig: navigationConfig,
                annotation: annotation,
                spokenInstructionObserver: speech
            )
        } catch {
            // Should not happen; fall back to an adapter built by hand.
            let adapter = try! RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: online)
            core = FerrostarCore(
                routeAdapter: adapter,
                locationProvider: locationProvider,
                navigationControllerConfig: navigationConfig,
                annotation: annotation,
                spokenInstructionObserver: speech
            )
        }
        return BuiltCore(core: core, annotation: annotation, mode: settings.useOnlineWhenAvailable ? .online : .unavailable)
    }

    /// Rebuild the routing engine when the offline pack or route preferences change.
    func refreshRouting() {
        let pack = regions.activePack(near: userLocation?.coordinate)
        activePack = pack
        search.useOfflineDatabase(pack.map { regions.fileURL($0, .search) })
        loadAlertIndex(pack)

        let key = "\(pack?.id ?? "-")|\(pack?.version ?? "-")|\(settings.routingKey)|\(settings.useOnlineWhenAvailable)|\(regions.revision)"
        guard key != builtKey, screen != .navigating else { return }
        builtKey = key

        let built = Self.makeCore(pack: pack, settings: settings, regions: regions,
                                  locationProvider: locationProvider, voice: voice)
        core.stopNavigation()
        core = built.core
        annotation = built.annotation
        routingMode = built.mode
        bindCore()
        locationProvider.startUpdating()
    }

    private func loadAlertIndex(_ pack: RegionPack?) {
        let url = pack.flatMap { regions.alertsURL($0) }
        let key = "\(url?.path ?? "-")|\(regions.alertsRevision)"
        guard key != alertIndexKey else { return }
        alertIndexKey = key
        alertIndex = nil
        guard let url else { return }
        Task.detached(priority: .utility) {
            let index = RoadAlertIndex(url: url)
            await MainActor.run {
                self.alertIndex = index
                self.updateRouteAlerts()
            }
        }
    }

    /// Find the cameras and crossings on the route shown on the map.
    func updateRouteAlerts() {
        alertTask?.cancel()
        let route = screen == .navigating ? core.route : selectedRoute
        guard let route, let index = alertIndex,
              settings.speedCameraAlerts || settings.railroadAlerts
        else {
            routeAlerts = []
            return
        }
        let cameras = settings.speedCameraAlerts, crossings = settings.railroadAlerts
        let geometry = route.geometry
        alertTask = Task {
            let found = await Task.detached(priority: .userInitiated) {
                index.alerts(along: geometry, cameras: cameras, crossings: crossings)
            }.value
            if !Task.isCancelled { routeAlerts = found }
        }
    }

    private func updateUpcomingAlert(_ state: NavigationState) {
        guard let route = core.route, let progress = state.currentProgress, !routeAlerts.isEmpty else {
            upcomingAlert = nil
            return
        }
        let traveled = route.distance - progress.distanceRemaining
        let next = routeAlerts.first { alert in
            let ahead = alert.distanceAlong - traveled
            return ahead > -15 && ahead <= alert.warnDistance
        }
        upcomingAlert = next
        upcomingAlertDistance = next.map { max(0, $0.distanceAlong - traveled) } ?? 0
        if let next, !announcedAlerts.contains(next.id) {
            announcedAlerts.insert(next.id)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if !isMuted {
                voice.speak(AVSpeechUtterance(string: next.spoken))
            }
        }
    }

    private func bindCore() {
        coreCancellables.removeAll()
        core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &coreCancellables)
        core.$route
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // New route after a reroute: find its alerts.
                guard let self, self.screen == .navigating else { return }
                Task { @MainActor in self.updateRouteAlerts() }
            }
            .store(in: &coreCancellables)
        core.spokenInstructionObserver.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in self?.isMuted = muted }
            .store(in: &coreCancellables)
    }

    private func handle(_ state: NavigationState?) {
        coreState = state
        guard screen == .navigating, let state else { return }
        updateUpcomingAlert(state)
        if case .complete = state.tripState, !arrived {
            arrived = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if self.arrived { self.stopNavigation() }
            }
        }
    }

    // MARK: Places

    func select(_ place: Place) {
        selectedPlace = place
        screen = .place
        routes = []
        camera = .center(place.coordinate, zoom: 15)
    }

    func dropPin(at coordinate: CLLocationCoordinate2D) {
        guard screen != .navigating else { return }
        let pin = Place.pin(coordinate)
        select(pin)
        Task {
            let described = await PlaceSearch.describe(coordinate)
            if selectedPlace?.id == pin.id { selectedPlace = described }
        }
    }

    func closePlace() {
        selectedPlace = nil
        routes = []
        screen = .browse
        recenter()
    }

    func recenter() {
        camera = .trackUserLocation(zoom: 15)
    }

    // MARK: Directions

    func directions(to place: Place) async {
        guard let here = userLocation ?? locationProvider.lastLocation?.clLocation else {
            errorMessage = "Waiting for your location…"
            return
        }
        selectedPlace = place
        screen = .routes
        routes = []
        selectedRouteIndex = 0
        isLoadingRoutes = true
        errorMessage = nil
        defer { isLoadingRoutes = false }

        let waypoints = [Waypoint(coordinate: GeographicCoordinate(cl: place.coordinate), kind: .break)]
        do {
            var found: [Route]
            do {
                found = try await core.getRoutes(initialLocation: here.userLocation, waypoints: waypoints)
            } catch {
                // Destination outside the downloaded map: try online if there's signal.
                guard case .offline = routingMode,
                      settings.useOnlineWhenAvailable, Connectivity.shared.isOnline
                else { throw error }
                found = try await Self.onlineRoutes(from: here, waypoints: waypoints, options: settings.routeOptions)
            }
            guard screen == .routes, selectedPlace?.id == place.id else { return }
            guard !found.isEmpty else { throw RoutingError.engine("No route found.") }
            routes = found
            fitCamera(to: found)
            updateRouteAlerts()
        } catch {
            errorMessage = error.localizedDescription
            if routes.isEmpty { screen = .place }
        }
    }

    private static func onlineRoutes(from here: CLLocation, waypoints: [Waypoint], options: [String: Any]) async throws -> [Route] {
        let provider = try WellKnownRouteProvider.valhalla(endpointUrl: onlineRoutingURL, profile: "auto")
            .withJsonOptions(options: options)
        let adapter = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: provider)
        guard case let .httpPost(url, headers, body) = try adapter.generateRequest(
            userLocation: here.userLocation, waypoints: waypoints
        ), let endpoint = URL(string: url) else { throw RoutingError.badRequest }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try adapter.parseResponse(response: data)
    }

    private func fitCamera(to routes: [Route]) {
        let coords = routes.flatMap(\.geometry)
        guard let first = coords.first else { return }
        var minLat = first.lat, maxLat = first.lat, minLng = first.lng, maxLng = first.lng
        for c in coords {
            minLat = min(minLat, c.lat); maxLat = max(maxLat, c.lat)
            minLng = min(minLng, c.lng); maxLng = max(maxLng, c.lng)
        }
        camera = .boundingBox(
            MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng)
            ),
            edgePadding: UIEdgeInsets(top: 110, left: 50, bottom: 340, right: 50)
        )
    }

    var selectedRoute: Route? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil
    }

    // MARK: Navigation

    func startNavigation(route: Route? = nil) {
        guard let route = route ?? selectedRoute else { return }
        do {
            arrived = false
            try core.startNavigation(route: route)
            destination = selectedPlace
            if let place = selectedPlace { library.addRecent(place) }
            screen = .navigating
            announcedAlerts = []
            updateRouteAlerts()
            camera = .automotiveNavigation()
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopNavigation() {
        arrived = false
        core.stopNavigation()
        UIApplication.shared.isIdleTimerDisabled = false
        screen = .browse
        routes = []
        selectedPlace = nil
        destination = nil
        routeAlerts = []
        upcomingAlert = nil
        locationProvider.startUpdating()
        recenter()
        refreshRouting()
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
        settings.voiceMuted = core.spokenInstructionObserver.isMuted
    }

    /// One-tap drive to a saved place.
    func drive(to place: Place) {
        Task { await directions(to: place) }
    }
}
