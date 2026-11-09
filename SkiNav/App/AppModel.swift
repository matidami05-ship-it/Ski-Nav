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
    case poi
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

    var camera: MapViewCamera = AppSettings.shared.map3D
        ? .trackUserLocationWithCourse(zoom: 17.2, pitch: 58, pitchRange: .fixed(58))
        : .trackUserLocation(zoom: 14)
    var screen: Screen = .browse
    var selectedPlace: Place?
    private(set) var routes: [Route] = []
    var selectedRouteIndex = 0 {
        didSet { if oldValue != selectedRouteIndex { updateRouteAlerts(); updateStopETAs() } }
    }
    private(set) var coreState: NavigationState?
    private(set) var isMuted = false
    private(set) var isLoadingRoutes = false
    var errorMessage: String?
    private(set) var userLocation: CLLocation?
    private(set) var destination: Place?
    private(set) var arrived = false
    var showDownloads = false
    var showTripPlanner = false
    var showAlongRoute = false

    /// The trip: stops in order, the last one is the destination.
    private(set) var stops: [Place] = []
    /// Seconds from the start to each stop on the selected route.
    private(set) var stopETAs: [Double] = []

    /// Points of interest being browsed.
    private(set) var poiCategory: POICategory?
    private(set) var poiResults: [POIResult] = []
    private(set) var isLoadingPOI = false

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

    static func navigationConfig(_ mode: TravelMode) -> SwiftNavigationControllerConfig {
        let walking = mode == .walking
        return SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(walking ? 25.0 : 100.0),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: walking ? 10 : 30,
                distanceAfterEndOfStep: walking ? 3 : 5,
                minimumHorizontalAccuracy: 32
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(
                distance: walking ? 12 : 25,
                minimumHorizontalAccuracy: 32
            ),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25,
                                                     maxAcceptableDeviation: walking ? 35 : 45),
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
        let mode = settings.travelMode
        let config = navigationConfig(mode)
        locationProvider.activityType = mode == .walking ? .otherNavigation : .automotiveNavigation

        if let pack,
           let provider = try? OfflineRouteProvider(routingTar: regions.fileURL(pack, .routing),
                                                    profile: mode.profile, options: options)
        {
            let core = FerrostarCore(
                customRouteProvider: provider,
                locationProvider: locationProvider,
                navigationControllerConfig: config,
                annotation: annotation,
                spokenInstructionObserver: speech
            )
            return BuiltCore(core: core, annotation: annotation, mode: .offline(pack.name))
        }

        let online = (try? WellKnownRouteProvider.valhalla(endpointUrl: onlineRoutingURL, profile: mode.profile)
            .withJsonOptions(options: options))
            ?? .valhalla(endpointUrl: onlineRoutingURL, profile: mode.profile)
        let core: FerrostarCore
        do {
            core = try FerrostarCore(
                wellKnownRouteProvider: online,
                locationProvider: locationProvider,
                navigationControllerConfig: config,
                annotation: annotation,
                spokenInstructionObserver: speech
            )
        } catch {
            // Should not happen; fall back to an adapter built by hand.
            let adapter = try! RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: online)
            core = FerrostarCore(
                routeAdapter: adapter,
                locationProvider: locationProvider,
                navigationControllerConfig: config,
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
        guard let route, let index = alertIndex, !isWalking,
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
            if !isWalking, settings.autoSaveParking {
                saveParking()
            }
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
        stops = []
        if poiCategory != nil, !poiResults.isEmpty {
            screen = .poi // back to the list of results
        } else {
            screen = .browse
            recenter()
        }
    }

    func recenter() {
        camera = screen == .navigating ? navigationCamera : browseCamera
    }

    // MARK: Directions

    func directions(to place: Place) async {
        stops = [place]
        await planRoute()
    }

    /// Routes from here through every stop, in order.
    func planRoute() async {
        guard let here = userLocation ?? locationProvider.lastLocation?.clLocation else {
            errorMessage = "Waiting for your location…"
            return
        }
        guard let final = stops.last else { return }
        let planned = stops.map(\.id)
        selectedPlace = final
        screen = .routes
        routes = []
        stopETAs = []
        selectedRouteIndex = 0
        isLoadingRoutes = true
        errorMessage = nil
        defer { isLoadingRoutes = false }

        let waypoints = stops.map { Waypoint(coordinate: GeographicCoordinate(cl: $0.coordinate), kind: .break) }
        do {
            var found: [Route]
            do {
                found = try await core.getRoutes(initialLocation: here.userLocation, waypoints: waypoints)
            } catch {
                // Destination outside the downloaded map: try online if there's signal.
                guard case .offline = routingMode,
                      settings.useOnlineWhenAvailable, Connectivity.shared.isOnline
                else { throw error }
                found = try await Self.onlineRoutes(from: here, waypoints: waypoints,
                                                    profile: settings.travelMode.profile, options: settings.routeOptions)
            }
            guard screen == .routes, stops.map(\.id) == planned else { return }
            guard !found.isEmpty else { throw RoutingError.engine("No route found.") }
            routes = found
            fitCamera(to: found)
            updateRouteAlerts()
            updateStopETAs()
        } catch {
            errorMessage = error.localizedDescription
            if routes.isEmpty { screen = stops.count > 1 ? .routes : .place }
        }
    }

    // MARK: Trip planner

    /// Add a stop. During route preview it goes before the final destination.
    func addStop(_ place: Place) {
        guard stops.count < 15 else {
            errorMessage = "A trip can have up to 15 stops."
            return
        }
        if stops.isEmpty || screen != .routes {
            stops.append(place)
        } else {
            stops.insert(place, at: stops.count - 1)
        }
    }

    func setStops(_ newStops: [Place]) {
        stops = newStops
    }

    func removeStop(at offsets: IndexSet) {
        stops.remove(atOffsets: offsets)
    }

    /// Reorder stops for the shortest total travel time, using real drive (or walk) times.
    func optimizeStops(keepLastFixed: Bool) async {
        guard stops.count >= 2, let here = userLocation else { return }
        let points = [here.coordinate] + stops.map(\.coordinate)
        let times = await travelTimes(points)
        let order = TripOptimizer.bestOrder(times: times, keepLastFixed: keepLastFixed)
        guard order.count == stops.count else { return }
        stops = order.map { stops[$0 - 1] }
    }

    private func travelTimes(_ points: [CLLocationCoordinate2D]) async -> [[Double]] {
        let locations = points.map { ["lat": $0.latitude, "lon": $0.longitude] }
        let body: [String: Any] = ["sources": locations, "targets": locations,
                                   "costing": settings.travelMode.profile]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8)
        else { return TripOptimizer.straightLineTimes(points) }

        if let pack = activePack,
           let response = try? await OfflineRouteProvider.matrix(routingTar: regions.fileURL(pack, .routing), json: json),
           let times = TripOptimizer.parseMatrix(response, count: points.count)
        {
            return times
        }
        if Connectivity.shared.isOnline, let url = URL(string: "https://valhalla1.openstreetmap.de/sources_to_targets") {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let result = try? await URLSession.shared.data(for: request),
               let text = String(data: result.0, encoding: .utf8),
               let times = TripOptimizer.parseMatrix(text, count: points.count)
            {
                return times
            }
        }
        return TripOptimizer.straightLineTimes(points)
    }

    /// Seconds from the start to each stop on the selected route.
    private func updateStopETAs() {
        guard let route = selectedRoute else { stopETAs = []; return }
        var etas: [Double] = []
        var elapsed = 0.0
        for step in route.steps {
            elapsed += step.duration
            // Each leg ends with a zero-length "arrive" step.
            if step.distance < 1, step.duration < 1 { etas.append(elapsed) }
        }
        if etas.count != stops.count {
            // Couldn't find the legs: spread by straight-line share as a rough guide.
            etas = stops.indices.map { i in route.duration * Double(i + 1) / Double(max(stops.count, 1)) }
        }
        stopETAs = etas
    }

    // MARK: Points of interest

    func showNearby(_ category: POICategory) {
        guard let here = userLocation?.coordinate else {
            errorMessage = "Waiting for your location…"
            return
        }
        poiCategory = category
        poiResults = []
        isLoadingPOI = true
        selectedPlace = nil
        routes = []
        screen = .poi
        let db = search.database
        let online = Connectivity.shared.isOnline && settings.useOnlineWhenAvailable
        Task {
            let found = await POIFinder.nearby(category, around: here, database: db, online: online)
            guard poiCategory == category, screen == .poi || screen == .place else { return }
            poiResults = found
            isLoadingPOI = false
            fitCamera(points: [here] + found.prefix(12).map(\.place.coordinate))
        }
    }

    /// Search for a category ahead on the route while driving.
    func findAlongRoute(_ category: POICategory) async -> [POIResult] {
        guard let route = core.route else { return [] }
        let traveled = route.distance - (coreState?.currentProgress?.distanceRemaining ?? route.distance)
        return await POIFinder.alongRoute(category, geometry: route.geometry, traveled: traveled,
                                          database: search.database,
                                          maxOffRoute: isWalking ? 300 : 1200)
    }

    func closePOI() {
        poiCategory = nil
        poiResults = []
        screen = .browse
        recenter()
    }

    /// Stop somewhere on the way and then continue to the remaining stops.
    func addStopWhileNavigating(_ place: Place) async {
        guard screen == .navigating, let here = userLocation else { return }
        let remaining = coreState?.remainingWaypoints ?? stops.map {
            Waypoint(coordinate: GeographicCoordinate(cl: $0.coordinate), kind: .break)
        }
        let waypoints = [Waypoint(coordinate: GeographicCoordinate(cl: place.coordinate), kind: .break)] + remaining
        do {
            let found = try await core.getRoutes(initialLocation: here.userLocation, waypoints: waypoints)
            guard let route = found.first else { throw RoutingError.engine("No route found.") }
            let done = max(0, stops.count - remaining.count)
            stops.insert(place, at: min(done, stops.count))
            try core.startNavigation(route: route)
            announcedAlerts = []
            updateRouteAlerts()
            camera = navigationCamera
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fitCamera(points: [CLLocationCoordinate2D]) {
        guard let first = points.first, points.count > 1 else { return }
        var minLat = first.latitude, maxLat = first.latitude, minLng = first.longitude, maxLng = first.longitude
        for c in points {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        camera = .boundingBox(
            MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLng),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng)
            ),
            edgePadding: UIEdgeInsets(top: 110, left: 50, bottom: 380, right: 50)
        )
    }

    private static func onlineRoutes(from here: CLLocation, waypoints: [Waypoint], profile: String,
                                     options: [String: Any]) async throws -> [Route]
    {
        let provider = try WellKnownRouteProvider.valhalla(endpointUrl: onlineRoutingURL, profile: profile)
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
            destination = stops.last ?? selectedPlace
            if let place = destination { library.addRecent(place) }
            poiCategory = nil
            poiResults = []
            screen = .navigating
            announcedAlerts = []
            updateRouteAlerts()
            camera = navigationCamera
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The follow-me camera for the current travel mode.
    var navigationCamera: MapViewCamera {
        settings.travelMode == .walking
            ? .navigation(activity: .pedestrian)
            : .automotiveNavigation(zoom: 17.6, pitch: 58)
    }

    /// The camera while just driving around with the map open: 3D (tilted, turning with
    /// you) or a flat north-up view.
    var browseCamera: MapViewCamera {
        settings.map3D
            ? .trackUserLocationWithCourse(zoom: 17.2, pitch: 58, pitchRange: .fixed(58))
            : .trackUserLocation(zoom: 15)
    }

    func toggle3D() {
        settings.map3D.toggle()
        if screen == .browse { camera = browseCamera }
    }

    var isWalking: Bool { settings.travelMode == .walking }

    /// Switch between driving and walking and recalculate the routes on screen.
    func setTravelMode(_ mode: TravelMode) {
        guard mode != settings.travelMode, screen != .navigating else { return }
        settings.travelMode = mode
        refreshRouting()
        if screen == .routes, !stops.isEmpty {
            Task { await planRoute() }
        }
    }

    // MARK: Parking

    /// Remember where the car is. Uses the current location unless a coordinate is given.
    func saveParking(at coordinate: CLLocationCoordinate2D? = nil, note: String? = nil) {
        guard let c = coordinate ?? userLocation?.coordinate else {
            errorMessage = "Waiting for your location…"
            return
        }
        library.setParkedCar(at: c, note: note)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            let described = await PlaceSearch.describe(c)
            if described.name != "Dropped Pin" || !described.subtitle.isEmpty {
                library.updateParkedAddress(described.name == "Dropped Pin" ? described.subtitle : described.name)
            }
        }
    }

    /// Walking directions back to the car.
    func walkToCar() {
        guard let car = library.parkedCar?.place else { return }
        if settings.travelMode != .walking {
            settings.travelMode = .walking
            refreshRouting()
        }
        selectedPlace = car
        Task { await directions(to: car) }
    }

    func stopNavigation() {
        arrived = false
        core.stopNavigation()
        UIApplication.shared.isIdleTimerDisabled = false
        screen = .browse
        routes = []
        selectedPlace = nil
        destination = nil
        stops = []
        stopETAs = []
        routeAlerts = []
        upcomingAlert = nil
        locationProvider.startUpdating()
        // Walking is usually a one-off (back to the car); next trip defaults to driving.
        if settings.travelMode == .walking { settings.travelMode = .driving }
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
