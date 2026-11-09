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
        let showAlerts = navigating || !model.routes.isEmpty
        let cameras = showAlerts ? model.routeAlerts.filter(\.isCamera) : []
        let crossings = showAlerts ? model.routeAlerts.filter { !$0.isCamera } : []
        let instruction = model.coreState?.currentVisualInstruction
        let toManeuver = model.coreState?.currentProgress?.distanceToNextManeuver
        let walking = model.isWalking
        let parked = model.library.parkedCar
        let junction = navigating && !walking && model.settings.junctionView
            ? JunctionInfo.from(instruction, distance: toManeuver) : nil
        let lanes = navigating && !walking && model.settings.laneGuidance && junction == nil
            ? (instruction?.subContent?.laneInfo ?? instruction?.primaryContent.laneInfo) : nil

        DynamicallyOrientingNavigationView(
            styleURL: styleURL,
            camera: $model.camera,
            navigationCamera: model.navigationCamera,
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
            if !crossings.isEmpty {
                SymbolStyleLayer(
                    identifier: "rail-alerts",
                    source: ShapeSource(identifier: "rail-alerts-source") {
                        crossings.map { MLNPointFeature(coordinate: $0.coordinate) as MLNShape }
                    }
                )
                .iconImage(AlertIcon.railroad)
                .iconAllowsOverlap(true)
            }
            if !cameras.isEmpty {
                SymbolStyleLayer(
                    identifier: "camera-alerts",
                    source: ShapeSource(identifier: "camera-alerts-source") {
                        cameras.map { MLNPointFeature(coordinate: $0.coordinate) as MLNShape }
                    }
                )
                .iconImage(AlertIcon.camera)
                .iconAllowsOverlap(true)
            }
            if let parked, pin?.id != "parked-car" {
                SymbolStyleLayer(
                    identifier: "parked-car",
                    source: ShapeSource(identifier: "parked-car-source") {
                        MLNPointFeature(coordinate: parked.coordinate)
                    }
                )
                .iconImage(AlertIcon.parkedCar)
                .iconAllowsOverlap(true)
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
            speedLimit: model.settings.showSpeedLimit && !walking ? annotation.speedLimit : nil,
            speedLimitStyle: .mutcdStyle
        )
        .navigationFormatterCollection(
            FoundationFormatterCollection(distanceFormatter: Fmt.distanceFormatter(miles: model.settings.useMiles))
        )
        .navigationViewInnerGrid(
            topCenter: {
                if navigating {
                    VStack(spacing: 8) {
                        if let junction {
                            JunctionView(info: junction, useMiles: model.settings.useMiles)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else if let lanes, !lanes.isEmpty {
                            LaneGuidanceView(lanes: lanes)
                        }
                        if let alert = model.upcomingAlert {
                            AlertBanner(alert: alert, distance: model.upcomingAlertDistance, miles: model.settings.useMiles)
                        }
                    }
                    .animation(.snappy, value: junction?.signText)
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

/// Map icons for cameras and crossings.
enum AlertIcon {
    static let camera = badge("camera.fill", fill: .systemOrange)
    static let parkedCar = badge("car.fill", fill: .systemTeal)
    static let railroad = badge("train.side.front.car", fill: .systemYellow, glyph: .black)

    private static func badge(_ symbol: String, fill: UIColor, glyph: UIColor = .white) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            fill.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            if let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(glyph, renderingMode: .alwaysOriginal)
            {
                image.draw(at: CGPoint(x: (size.width - image.size.width) / 2, y: (size.height - image.size.height) / 2))
            }
        }
    }
}

/// "Speed camera ahead · 0.3 mi" under the turn banner.
struct AlertBanner: View {
    var alert: RouteAlert
    var distance: Double
    var miles: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: alert.isCamera ? "camera.fill" : "train.side.front.car")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(alert.isCamera ? .white : .black)
                .frame(width: 34, height: 34)
                .background(alert.isCamera ? Color.orange : Color.yellow, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title(miles: miles))
                    .font(.subheadline.weight(.bold))
                Text(Fmt.distance(distance, miles: miles))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}
