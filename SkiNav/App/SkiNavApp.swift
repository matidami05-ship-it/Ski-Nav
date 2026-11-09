import SwiftUI

@main
struct SkiNavApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(colorScheme)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                model.refreshRouting()
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
