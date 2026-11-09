import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        DownloadsView(model: model)
                    } label: {
                        HStack {
                            Label("Download Maps", systemImage: "arrow.down.circle.fill")
                            Spacer()
                            Text(model.regions.installed.isEmpty ? "None" : "\(model.regions.installed.count) downloaded")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        TrafficKeyView()
                    } label: {
                        HStack {
                            Label("Live Traffic & Satellite", systemImage: "car.rear.road.lane.dashed")
                            Spacer()
                            Text(settings.hasTrafficKey ? "On" : "Set up").foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        MapDisplayView()
                    } label: {
                        Label("Map & display", systemImage: "map")
                    }
                    NavigationLink {
                        WarningsView()
                    } label: {
                        Label("Warnings", systemImage: "exclamationmark.triangle")
                    }
                }

                Section("Map") {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(MapAppearance.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("3D map when driving", isOn: Binding(
                        get: { settings.map3D },
                        set: { if $0 != settings.map3D { model.toggle3D() } }
                    ))
                    Toggle("3D buildings", isOn: $settings.buildings3D)
                    Toggle("Street detail", isOn: $settings.streetDetail)
                    Toggle("Show speed limit", isOn: $settings.showSpeedLimit)
                    Picker("Units", selection: $settings.useMiles) {
                        Text("Miles").tag(true)
                        Text("Kilometers").tag(false)
                    }
                }

                Section {
                    Toggle("Lane guidance", isOn: $settings.laneGuidance)
                    Toggle("3D junction view at exits", isOn: $settings.junctionView)
                    Toggle("Speed camera alerts", isOn: $settings.speedCameraAlerts)
                    Toggle("Railroad crossing alerts", isOn: $settings.railroadAlerts)
                } header: {
                    Text("Driving")
                } footer: {
                    Text("Lanes, cameras and crossings come from OpenStreetMap and work offline. Wisconsin doesn’t allow speed cameras, so you’ll mostly see them in Illinois.")
                }

                Section {
                    Toggle("Save parking spot automatically", isOn: $settings.autoSaveParking)
                } header: {
                    Text("Parking")
                } footer: {
                    Text("Saves where your car is when you arrive at a destination or unplug from CarPlay. You can also tap Park Here anytime.")
                }

                Section {
                    Toggle("Street view on places", isOn: $settings.streetView)
                } footer: {
                    Text("Apple Look Around imagery. Needs a connection.")
                }

                Section {
                    Toggle("Avoid tolls", isOn: $settings.avoidTolls)
                    Toggle("Avoid highways", isOn: $settings.avoidHighways)
                    Toggle("Avoid ferries", isOn: $settings.avoidFerries)
                } header: {
                    Text("Routes")
                }

                Section {
                    Toggle("Voice guidance", isOn: Binding(
                        get: { !settings.voiceMuted },
                        set: { on in
                            if model.isMuted == on { model.toggleMute() }
                            settings.voiceMuted = !on
                        }
                    ))
                    NavigationLink {
                        VoiceSettingsView(model: model)
                    } label: {
                        HStack {
                            Label("Voice & Language", systemImage: "waveform")
                            Spacer()
                            Text("\(settings.guidanceLanguage.label) · \(settings.useAzureVoice ? "Natural" : "iPhone")")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Voice")
                }

                Section {
                    Toggle("Use internet when available", isOn: $settings.useOnlineWhenAvailable)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Adds Apple’s business search when you have signal, and routes online to places outside your downloaded maps. Everything else always works offline.")
                }

                Section("About") {
                    LabeledContent("Routing", value: model.routingMode.label)
                    LabeledContent("Map data", value: "© OpenStreetMap contributors")
                    LabeledContent("Basemap", value: "Protomaps")
                    LabeledContent("Navigation", value: "Ferrostar · Valhalla")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
