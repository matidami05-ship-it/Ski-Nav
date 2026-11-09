import FerrostarCore
import FerrostarCoreFFI
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

/// Gray route line for the alternatives in the route preview.
struct AlternateRouteStyle: RouteStyle {
    let color: UIColor = .systemGray2
    let casingColor: UIColor? = .white
    let lineCap: LineCap = .round
    let lineJoin: LineJoin = .round
}

/// The full-screen map with Ferrostar's turn-by-turn overlay.
struct MapScreen: View {
    @Bindable var model: AppModel
    @ObservedObject var annotation: AnnotationPublisher<ValhallaExtendedOSRMAnnotation>
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        switch model.settings.appearance {
        case .automatic: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }

    var body: some View {
        let styleURL = MapStyle.url(pack: model.activePack, dark: isDark, store: model.regions)
        let navigating = model.screen == .navigating
        let alternates = navigating ? [] : model.routes.enumerated().filter { $0.offset != model.selectedRouteIndex }
        let preview = navigating ? nil : model.selectedRoute
        let pin = model.selectedPlace ?? model.destination

        DynamicallyOrientingNavigationView(
            styleURL: styleURL,
            camera: $model.camera,
            navigationState: model.coreState,
            isMuted: model.isMuted,
            onTapMute: { model.toggleMute() },
            onTapExit: { model.stopNavigation() }
        ) {
            for (index, route) in alternates {
                RouteStyleLayer(
                    polyline: MLNPolylineFeature(coordinates: route.geometry.map(\.clLocationCoordinate2D)),
                    identifier: "alt-route-\(index)",
                    style: AlternateRouteStyle()
                )
            }
            if let preview {
                RouteStyleLayer(
                    polyline: MLNPolylineFeature(coordinates: preview.geometry.map(\.clLocationCoordinate2D)),
                    identifier: "preview-route",
                    style: ActiveRouteStyle()
                )
            }
            if let pin {
                let source = ShapeSource(identifier: "pin-source") {
                    MLNPointFeature(coordinate: pin.coordinate)
                }
                CircleStyleLayer(identifier: "pin-halo", source: source)
                    .radius(16)
                    .color(.systemRed.withAlphaComponent(0.25))
                CircleStyleLayer(identifier: "pin-dot", source: source)
                    .radius(8)
                    .color(.systemRed)
                    .strokeWidth(3)
                    .strokeColor(.white)
            }
        }
        .unsafeMapViewControllerModifier { controller in
            controller.mapView.showsUserLocation = true
            controller.mapView.compassViewPosition = .topLeft
            controller.mapView.compassViewMargins = CGPoint(x: 16, y: 120)
        }
        .navigationSpeedLimit(
            speedLimit: model.settings.showSpeedLimit ? annotation.speedLimit : nil,
            speedLimitStyle: .mutcdStyle
        )
        .navigationFormatterCollection(
            FoundationFormatterCollection(distanceFormatter: Fmt.distanceFormatter(miles: model.settings.useMiles))
        )
        .navigationViewInnerGrid(
            topCenter: {
                if navigating {
                    if model.arrived {
                        NavigationUIBanner(severity: .info) {
                            Text("You’ve arrived\(model.destination.map { " at \($0.name)" } ?? "")")
                        }
                    } else if model.coreState?.isCalculatingNewRoute == true {
                        NavigationUIBanner(severity: .loading) {
                            Text("Finding a new route…")
                        }
                    }
                }
            }
        )
        .onLongPressMapGesture { context in
            if context.state == .began {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.dropPin(at: context.coordinate)
            }
        }
        .ignoresSafeArea()
    }
}
