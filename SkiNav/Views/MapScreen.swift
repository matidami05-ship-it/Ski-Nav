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
        let styleURL = MapStyle.url(pack: model.activePack, dark: isDark, store: model.regions,
                                    navigating: model.screen == .navigating)
        let navigating = model.screen == .navigating
        let alternates = navigating ? [] : model.routes.enumerated().filter { $0.offset != model.selectedRouteIndex }
        let preview = navigating ? nil : model.selectedRoute
        let pin = model.selectedPlace ?? model.destination
        let poiPlaces = model.screen == .poi || (model.screen == .place && model.poiCategory != nil)
            ? model.poiResults.map(\.place) : []
        let tripStops = model.stops.count > 1 ? Array(model.stops.dropLast()) : []
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
                RouteLine(
                    polyline: MLNPolylineFeature(coordinates: route.geometry.map(\.clLocationCoordinate2D)),
                    identifier: "alt-route-\(index)",
                    kind: .alternate
                )
            }
            if let preview {
                RouteLine(
                    polyline: MLNPolylineFeature(coordinates: preview.geometry.map(\.clLocationCoordinate2D)),
                    identifier: "preview-route"
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
            if let category = model.poiCategory, !poiPlaces.isEmpty {
                SymbolStyleLayer(
                    identifier: "poi-results",
                    source: ShapeSource(identifier: "poi-results-source") {
                        poiPlaces.map { MLNPointFeature(coordinate: $0.coordinate) as MLNShape }
                    }
                )
                .iconImage(AlertIcon.poi(category))
                .iconAllowsOverlap(true)
            }
            for (index, stop) in tripStops.enumerated() {
                let stopSource = ShapeSource(identifier: "stop-\(index)-source") {
                    MLNPointFeature(coordinate: stop.coordinate)
                }
                SymbolStyleLayer(identifier: "stop-\(index)-label", source: stopSource)
                    .iconImage(AlertIcon.number(index + 1))
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
        .navigationMapViewRouteOverlay { state in
            // Wide blue route ahead, gray behind you.
            if let state {
                let parts = RouteLine.split(state.routeGeometry,
                                            at: state.preferredUserLocation?.clLocation.coordinate)
                if parts.travelled.count > 1 {
                    RouteLine(polyline: MLNPolylineFeature(coordinates: parts.travelled),
                              identifier: "nav-travelled", kind: .travelled)
                }
                if parts.remaining.count > 1 {
                    RouteLine(polyline: MLNPolylineFeature(coordinates: parts.remaining),
                              identifier: "nav-remaining")
                }
            }
        }
        .unsafeMapViewControllerModifier { controller in
            controller.mapView.showsUserLocation = true
            // Icons used by the 3D street detail layers.
            if let style = controller.mapView.style {
                for (name, image) in StreetDetailStyle.images.merging(TrafficStyle.images, uniquingKeysWith: { a, _ in a })
                    where style.image(forName: name) == nil
                {
                    style.setImage(image, forName: name)
                }
            }
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
                    VStack(spacing: 6) {
                        if junction == nil, let lanes, !lanes.isEmpty {
                            ViewThatFits(in: .horizontal) {
                                LaneGuidanceView(lanes: lanes, cell: 40)
                                LaneGuidanceView(lanes: lanes, cell: 30)
                                LaneGuidanceView(lanes: lanes, cell: 22)
                            }
                        }
                        if let traffic = model.navTraffic, traffic.isNoticeable {
                            CompactBanner(
                                symbol: "car.2.fill",
                                tint: traffic.isHeavy ? .red : .orange,
                                title: "Traffic +\(Fmt.duration(traffic.delay))",
                                subtitle: "Arrive \(Fmt.arrival(after: traffic.travelTime))"
                            )
                        }
                        if let alert = model.upcomingAlert {
                            CompactBanner(
                                symbol: alert.isCamera ? "camera.fill" : "train.side.front.car",
                                tint: alert.isCamera ? .orange : .yellow,
                                glyph: alert.isCamera ? .white : .black,
                                title: alert.isCamera ? "Speed camera" : "Rail crossing",
                                subtitle: Fmt.distance(model.upcomingAlertDistance, miles: model.settings.useMiles)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
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
            },
            bottomLeading: {
                if navigating {
                    Button {
                        model.showAlongRoute = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .tint(.primary)
                    .accessibilityLabel("Find along route")
                }
            }
        )
        .overlay(alignment: .top) {
            if let junction {
                JunctionView(info: junction, useMiles: model.settings.useMiles)
                    .padding(.horizontal, 16)
                    .padding(.top, 84) // just below the turn banner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: junction?.signText)
        .onLongPressMapGesture { context in
            if context.state == .began {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.dropPin(at: context.coordinate)
            }
        }
    }
}

/// Map icons for cameras and crossings.
enum AlertIcon {
    static let camera = badge("camera.fill", fill: .systemOrange)
    static let parkedCar = badge("car.fill", fill: .systemTeal)

    /// Numbered trip stop marker (drawn as an image so no map fonts are needed).
    static func number(_ n: Int) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            UIColor.systemIndigo.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 2.5, dy: 2.5)).fill()
            let text = "\(n)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            let t = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - t.width) / 2, y: (size.height - t.height) / 2), withAttributes: attrs)
        }
    }

    private static var poiCache: [POICategory: UIImage] = [:]
    static func poi(_ category: POICategory) -> UIImage {
        if let cached = poiCache[category] { return cached }
        let image = badge(category.symbol, fill: category.uiColor)
        poiCache[category] = image
        return image
    }
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

/// A small two-line notice that fits beside the map buttons:
/// [icon] Traffic +4 min
///        Arrive 6:35 PM
struct CompactBanner: View {
    var symbol: String
    var tint: Color
    var glyph: Color = .white
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: 28, height: 28)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: 220, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
    }
}
