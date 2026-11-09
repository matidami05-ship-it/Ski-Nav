import MapKit
import SwiftUI

/// Apple Look Around (street-level imagery) for a place. Tap it to go full screen and look
/// around. Needs a connection; Apple has imagery for most cities and main roads.
struct LookAroundSection: View {
    var coordinate: CLLocationCoordinate2D
    @State private var scene: MKLookAroundScene?
    @State private var loaded = false

    var body: some View {
        Group {
            if let scene {
                LookAroundPreview(initialScene: scene, allowsNavigation: true, badgePosition: .bottomTrailing)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if !loaded {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 150)
                    .overlay {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading street view…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
            } else {
                Label(
                    Connectivity.shared.isOnline ? "No street view at this spot" : "Street view needs a connection",
                    systemImage: "binoculars"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            scene = nil
            loaded = false
            if Connectivity.shared.isOnline {
                scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene
            }
            loaded = true
        }
    }
}
