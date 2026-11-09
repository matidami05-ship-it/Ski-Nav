import CarPlay
import FerrostarCarPlayUI
import FerrostarCore
import FerrostarMapLibreUI
import FerrostarSwiftUI
import MapLibreSwiftUI
import SwiftUI
import UIKit

/// The map the car screen shows behind CarPlay's own buttons.
struct CarMapView: View {
    @Bindable var car: CarPlayModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let app = car.app
        let dark: Bool = switch app.settings.appearance {
        case .automatic: colorScheme == .dark
        case .light: false
        case .dark: true
        }
        CarPlayNavigationView(
            styleURL: MapStyle.url(pack: app.activePack, dark: dark, store: app.regions),
            camera: $car.camera,
            navigationCamera: .automotiveNavigation(zoom: 15),
            navigationState: app.coreState
        )
        .navigationFormatterCollection(
            FoundationFormatterCollection(distanceFormatter: Fmt.distanceFormatter(miles: app.settings.useMiles))
        )
        .navigationMapViewContentInset(landscape: { proxy in
            .landscape(within: proxy, verticalPct: 0.7, horizontalPct: 0.95)
        })
    }
}

final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    private var car: CarPlayModel?

    func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        MainActor.assumeIsolated {
            let app = AppModel.shared
            app.start()
            let car = CarPlayModel(app: app, interfaceController: interfaceController)
            self.car = car

            window.rootViewController = UIHostingController(rootView: CarMapView(car: car))
            window.makeKeyAndVisible()

            let template = car.createTemplate()
            interfaceController.setRootTemplate(template, animated: true, completion: nil)
        }
    }

    func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didDisconnect _: CPInterfaceController,
        from window: CPWindow
    ) {
        MainActor.assumeIsolated {
            // Leaving the car: remember where it's parked.
            if AppSettings.shared.autoSaveParking {
                AppModel.shared.saveParking()
            }
            car?.disconnect()
            car = nil
            window.isHidden = true
        }
    }
}
