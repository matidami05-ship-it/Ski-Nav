@preconcurrency import CarPlay
import FerrostarCarPlayUI
import FerrostarCore
import FerrostarCoreFFI
import FerrostarMapLibreUI
import FerrostarSwiftUI
import Foundation
import MapKit
import MapLibreSwiftUI

/// Drives the CarPlay screen: a destinations list, route previews and the active trip.
/// Navigation itself is shared with the phone through AppModel.
@MainActor
@Observable
final class CarPlayModel: NSObject, @preconcurrency CPMapTemplateDelegate {
    let app: AppModel
    @ObservationIgnored private let interfaceController: CPInterfaceController
    @ObservationIgnored private var mapTemplate: CPMapTemplate?
    @ObservationIgnored private var session: CPNavigationSession?
    @ObservationIgnored private var previewing = false

    var camera: MapViewCamera = .trackUserLocation(zoom: 14)

    @ObservationIgnored private let formatters = FoundationFormatterCollection()

    init(app: AppModel, interfaceController: CPInterfaceController) {
        self.app = app
        self.interfaceController = interfaceController
        super.init()
    }

    private var units: MKDistanceFormatter.Units {
        app.settings.useMiles ? .imperial : .metric
    }

    func createTemplate() -> CPMapTemplate {
        let template = CPMapTemplate()
        template.mapDelegate = self
        mapTemplate = template
        updateTemplate()
        observeApp()
        return template
    }

    func disconnect() {
        session?.cancelTrip()
        session = nil
    }

    // MARK: Keeping CarPlay in step with the phone

    private func observeApp() {
        withObservationTracking {
            _ = app.screen
            _ = app.coreState
            _ = app.isMuted
        } onChange: {
            Task { @MainActor in
                self.syncWithApp()
                self.observeApp()
            }
        }
    }

    private func syncWithApp() {
        guard let mapTemplate else { return }
        switch app.screen {
        case .navigating:
            if session == nil, let route = app.core.route {
                // Navigation started on the phone: show it in the car too.
                mapTemplate.hideTripPreviews()
                let trip = trip(for: [route])
                session = mapTemplate.startNavigationSession(for: trip)
                camera = .automotiveNavigation(zoom: 15)
            }
            if let session, let state = app.coreState {
                if case .complete = state.tripState {
                    // Arrival handled by AppModel, which stops navigation shortly.
                } else {
                    state.updateEstimates(mapTemplate: mapTemplate, session: session, units: units)
                }
            }
        default:
            if let session {
                session.finishTrip()
                self.session = nil
                camera = .trackUserLocation(zoom: 14)
            }
        }
        updateTemplate()
    }

    // MARK: Template buttons

    private func updateTemplate() {
        guard let mapTemplate else { return }
        mapTemplate.automaticallyHidesNavigationBar = app.screen == .navigating

        if app.screen == .navigating {
            let end = CPBarButton(title: "End") { [weak self] _ in
                self?.app.stopNavigation()
            }
            mapTemplate.leadingNavigationBarButtons = []
            mapTemplate.trailingNavigationBarButtons = [end]
        } else {
            let destinations = CPBarButton(title: "Destinations") { [weak self] _ in
                self?.showDestinations()
            }
            mapTemplate.leadingNavigationBarButtons = [destinations]
            mapTemplate.trailingNavigationBarButtons = []
        }

        let cameraState: CameraControlState = if camera.isTrackingUserLocationWithCourse,
                                                 let overview = app.coreState?.routeOverviewCamera
        {
            .showRouteOverview { [weak self] in self?.camera = overview }
        } else {
            .showRecenter { [weak self] in
                guard let self else { return }
                self.camera = self.app.screen == .navigating ? .automotiveNavigation(zoom: 15) : .trackUserLocation(zoom: 14)
            }
        }

        mapTemplate.mapButtons = [
            app.screen == .navigating
                ? CarPlayMapButtons.toggleMute(app.isMuted) { [weak self] in self?.app.toggleMute() }
                : nil,
            CarPlayMapButtons.zoomIn { [weak self] in self?.camera.incrementZoom(by: 1) },
            CarPlayMapButtons.zoomOut { [weak self] in self?.camera.incrementZoom(by: -1) },
            CarPlayMapButtons.camera(cameraState),
        ].compactMap { $0 }
    }

    // MARK: Destinations

    private func showDestinations() {
        let lib = app.library
        var favorites: [CPListItem] = []
        if let home = lib.home { favorites.append(item(home, symbol: "house.fill")) }
        if let work = lib.work { favorites.append(item(work, symbol: "briefcase.fill")) }
        favorites += lib.saved.prefix(8).map { item($0, symbol: "star.fill") }
        let recents = lib.recents.prefix(10).map { item($0, symbol: "clock.arrow.circlepath") }

        var sections: [CPListSection] = []
        if !favorites.isEmpty { sections.append(CPListSection(items: favorites, header: "Favorites", sectionIndexTitle: nil)) }
        if !recents.isEmpty { sections.append(CPListSection(items: Array(recents), header: "Recent", sectionIndexTitle: nil)) }

        let list = CPListTemplate(title: "Destinations", sections: sections)
        if sections.isEmpty {
            list.emptyViewTitleVariants = ["No saved places yet"]
            list.emptyViewSubtitleVariants = ["Save places or set Home and Work on your iPhone."]
        }
        interfaceController.pushTemplate(list, animated: true, completion: nil)
    }

    private func item(_ place: Place, symbol: String) -> CPListItem {
        let detail: String? = app.userLocation.map {
            Fmt.distance($0.distance(from: place.location), miles: app.settings.useMiles)
        }
        let item = CPListItem(text: place.name, detailText: [detail, place.subtitle.isEmpty ? nil : place.subtitle]
            .compactMap { $0 }.joined(separator: " · "),
            image: UIImage(systemName: symbol))
        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            Task { @MainActor in
                await self.app.directions(to: place)
                completion()
                self.interfaceController.popToRootTemplate(animated: true, completion: nil)
                self.previewRoutes(to: place)
            }
        }
        return item
    }

    private func trip(for routes: [Route]) -> CPTrip {
        let origin = MKMapItem.forCurrentLocation()
        let dest = app.destination ?? app.selectedPlace
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: dest?.coordinate
                ?? routes.first?.geometry.last?.clLocationCoordinate2D
                ?? kCLLocationCoordinate2DInvalid))
        destination.name = dest?.name
        return CPTrip.fromFerrostar(
            routes: routes,
            origin: origin,
            destination: destination,
            distanceFormatter: Fmt.distanceFormatter(miles: app.settings.useMiles),
            durationFormatter: formatters.durationFormatter
        )
    }

    private func previewRoutes(to place: Place) {
        guard let mapTemplate, !app.routes.isEmpty else {
            if let message = app.errorMessage { showAlert(message) }
            return
        }
        let text = CPTripPreviewTextConfiguration(
            startButtonTitle: "Go",
            additionalRoutesButtonTitle: "More Routes",
            overviewButtonTitle: "Overview"
        )
        previewing = true
        mapTemplate.showRouteChoicesPreview(for: trip(for: app.routes), textConfiguration: text)
    }

    private func showAlert(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true, completion: nil)
            },
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    // MARK: CPMapTemplateDelegate

    func mapTemplate(_: CPMapTemplate, selectedPreviewFor _: CPTrip, using routeChoice: CPRouteChoice) {
        guard let route = routeChoice.route,
              let index = app.routes.firstIndex(where: { $0.geometry == route.geometry })
        else { return }
        app.selectedRouteIndex = index
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        mapTemplate.hideTripPreviews()
        previewing = false
        guard let route = routeChoice.route ?? app.selectedRoute else { return }
        session = mapTemplate.startNavigationSession(for: trip)
        app.startNavigation(route: route)
        camera = .automotiveNavigation(zoom: 15)
        updateTemplate()
    }

    func mapTemplateDidCancelNavigation(_: CPMapTemplate) {
        session = nil
        app.stopNavigation()
    }
}
