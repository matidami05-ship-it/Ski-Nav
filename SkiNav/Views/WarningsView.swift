import SwiftUI

/// Warnings, like TomTom AmiGO: cameras, traffic, hazards and speeding.
struct WarningsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.speedCameraAlerts) {
                    row("Cameras", "Warnings for speed cameras on your route")
                }
                Toggle(isOn: $settings.railroadAlerts) {
                    row("Railroad crossings", "A heads-up before every crossing on your route")
                }
            }
            Section {
                Toggle(isOn: $settings.trafficWarnings) {
                    row("Traffic", "Warnings for traffic jams and delays ahead")
                }
                Toggle(isOn: $settings.hazardWarnings) {
                    row("Hazards", "Warnings for accidents, roadwork, closures and obstacles ahead")
                }
            } footer: {
                if !settings.hasTrafficKey {
                    Text("Traffic and hazard warnings need live traffic (Settings › Live Traffic & Satellite).")
                }
            }
            Section {
                Toggle(isOn: $settings.speedingWarning) {
                    row("Speeding", "Warns you when you're driving too fast")
                }
                if settings.speedingWarning {
                    Picker("Warn when over the limit by", selection: $settings.speedingTolerance) {
                        Text("Any amount").tag(0)
                        ForEach([3, 5, 7, 10], id: \.self) { n in
                            Text("\(n) \(settings.useMiles ? "mph" : "km/h")").tag(n)
                        }
                    }
                }
            } footer: {
                Text("Your speed shows on the left while driving and turns red with a chime when you're over the posted limit.")
            }
        }
        .navigationTitle("Warnings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.body.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Map & display: live traffic layers.
struct MapDisplayView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.trafficIncidents) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Traffic incidents").font(.body.weight(.semibold))
                        Text("Displays live traffic jams, construction and closed roads including delay time")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Toggle(isOn: $settings.trafficFlow) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Traffic flow").font(.body.weight(.semibold))
                        Text("Colored lines are displayed to indicate live traffic speed")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Toggle(isOn: $settings.trafficWhileNavigating) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Traffic while navigating").font(.body.weight(.semibold))
                        Text("Show traffic during a route even in Explore mode")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                if !settings.hasTrafficKey {
                    Text("Needs live traffic (Settings › Live Traffic & Satellite).")
                }
            }
            Section {
                Toggle("3D buildings", isOn: $settings.buildings3D)
                Toggle("Street detail (lanes, crosswalks)", isOn: $settings.streetDetail)
                Toggle("Lane guidance", isOn: $settings.laneGuidance)
                Toggle("3D junction view at exits", isOn: $settings.junctionView)
                Toggle("Show speed limit", isOn: $settings.showSpeedLimit)
            }
        }
        .navigationTitle("Map & display")
        .navigationBarTitleDisplayMode(.inline)
    }
}
