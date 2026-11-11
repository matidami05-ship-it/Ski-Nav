import AudioToolbox
import CoreLocation
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
            StartupCamera.seed(controller.mapView, at: model.userLocation?.coordinate, map3D: model.settings.map3D)
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
                        if let traffic = model.navTraffic, traffic.isNoticeable {
                            CompactBanner(
                                symbol: "car.2.fill",
                                tint: traffic.isHeavy ? .red : .orange,
                                title: "Traffic +\(Fmt.duration(traffic.delay))",
                                subtitle: "Arrive \(Fmt.arrival(after: traffic.travelTime))"
                            )
                        }
                        if let alert = model.upcomingAlert {
                            if case let .hazard(category, _) = alert.kind {
                                CompactBanner(
                                    symbol: alert.hazardSymbol,
                                    tint: category == 9 || category == 7 ? .orange : .red,
                                    title: RouteAlert.hazardLabel(category, polish: false),
                                    subtitle: Fmt.distance(model.upcomingAlertDistance, miles: model.settings.useMiles)
                                )
                            } else {
                                CompactBanner(
                                    symbol: alert.isCamera ? "camera.fill" : "train.side.front.car",
                                    tint: alert.isCamera ? .orange : .yellow,
                                    glyph: alert.isCamera ? .white : .black,
                                    title: alert.isCamera ? "Speed camera" : "Rail crossing",
                                    subtitle: Fmt.distance(model.upcomingAlertDistance, miles: model.settings.useMiles)
                                )
                            }
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
            midLeading: {
                if navigating && !walking {
                    SpeedBubble(speed: model.userLocation?.speed ?? -1,
                                limit: annotation.speedLimit,
                                miles: model.settings.useMiles,
                                warn: model.settings.speedingWarning,
                                tolerance: Double(model.settings.speedingTolerance))
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
        .navigationViewComponents(
            progressView: { state, onExit in
                AnyView(TripBar(state: state, miles: model.settings.useMiles, traffic: model.navTraffic,
                                hasTraffic: model.settings.hasTrafficKey, onExit: onExit))
            },
            instructionsView: { state, _, size in
                AnyView(TurnBanner(state: state, miles: model.settings.useMiles,
                                   lanes: lanes, junction: junction, size: size))
            }
        )
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

/// Current speed, like AmiGO: a white circle that turns red with a chime when you're over
/// the limit (plus your tolerance) for a few seconds.
struct SpeedBubble: View {
    var speed: Double // m/s, negative if unknown
    var limit: Measurement<UnitSpeed>?
    var miles: Bool
    var warn: Bool
    var tolerance: Double

    @State private var overSince: Date?
    @State private var lastChime: Date?

    private var shown: Int? {
        guard speed >= 0 else { return nil }
        return Int((miles ? speed * 2.23694 : speed * 3.6).rounded())
    }

    private var limitShown: Double? {
        limit.map { miles ? $0.converted(to: .milesPerHour).value : $0.converted(to: .kilometersPerHour).value }
    }

    private var speeding: Bool {
        guard warn, let shown, let limitShown, limitShown > 0 else { return false }
        return Double(shown) > limitShown + tolerance
    }

    var body: some View {
        if let shown {
            VStack(spacing: -2) {
                Text("\(shown)")
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                Text(miles ? "mph" : "km/h")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(speeding ? .white : .black)
            .frame(width: 62, height: 62)
            .background(Circle().fill(speeding ? Color.red : Color.white))
            .overlay(Circle().strokeBorder(speeding ? Color.white : Color.black.opacity(0.15), lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .scaleEffect(speeding ? 1.08 : 1)
            .animation(.spring(duration: 0.3), value: speeding)
            .onChange(of: speeding) { _, now in
                overSince = now ? Date() : nil
            }
            .onChange(of: shown) {
                // Chime once you've been over for 3 seconds, at most every 45 seconds.
                guard speeding, let since = overSince, Date().timeIntervalSince(since) > 3,
                      lastChime.map({ Date().timeIntervalSince($0) > 45 }) ?? true
                else { return }
                lastChime = Date()
                AudioServicesPlaySystemSound(1016)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            .accessibilityLabel("Speed \(shown) \(miles ? "miles" : "kilometers") per hour\(speeding ? ", over the limit" : "")")
        }
    }
}


/// The map view starts at 0°, 0° and then flies across the globe to the user once their
/// position comes in. Jump straight to the last known position instead (no animation),
/// keeping the follow mode so the camera still tracks the car from there.
@MainActor
enum StartupCamera {
    private static var done = false

    static func seed(_ mapView: MLNMapView, at coordinate: CLLocationCoordinate2D?, map3D: Bool) {
        guard !done, let coordinate else { return }
        done = true
        let center = mapView.centerCoordinate
        // Only if it's still at the default spot (it may already be on the user).
        guard abs(center.latitude) < 1, abs(center.longitude) < 1 else { return }
        let mode = mapView.userTrackingMode
        mapView.setCenter(coordinate, zoomLevel: map3D ? 17.2 : 14, animated: false)
        if map3D {
            let camera = mapView.camera
            camera.pitch = 58
            mapView.setCamera(camera, animated: false)
        }
        if mode != .none { mapView.setUserTrackingMode(mode, animated: false, completionHandler: nil) }
    }
}
