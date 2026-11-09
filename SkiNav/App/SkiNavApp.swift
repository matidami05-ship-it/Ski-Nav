import SwiftUI

@main
struct SkiNavApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Set up early so tapping a "Time to leave" notification works even from a cold start.
        LeaveReminders.shared.activate()
    }

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
