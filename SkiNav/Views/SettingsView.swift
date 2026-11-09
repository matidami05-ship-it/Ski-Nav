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
                            Label("Offline Maps", systemImage: "arrow.down.circle.fill")
                            Spacer()
                            Text(model.regions.installed.isEmpty ? "None" : "\(model.regions.installed.count) downloaded")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Map") {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(MapAppearance.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Show speed limit", isOn: $settings.showSpeedLimit)
                    Picker("Units", selection: $settings.useMiles) {
                        Text("Miles").tag(true)
                        Text("Kilometers").tag(false)
                    }
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
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        Slider(value: $settings.speechRate, in: 0.42 ... 0.62) {
                            Text("Speaking speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill")
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill")
                        } onEditingChanged: { editing in
                            if !editing {
                                model.voice.rate = Float(settings.speechRate)
                                model.voice.speak(AVSpeechUtterance(string: "In a quarter mile, turn right onto Main Street."))
                            }
                        }
                    }
                    LabeledContent("Voice", value: VoiceSynthesizer.bestVoice()?.name ?? "Default")
                } header: {
                    Text("Voice")
                } footer: {
                    Text("For a more natural voice, download an Enhanced or Premium English voice in iPhone Settings › Accessibility › Spoken Content › Voices. Ski Nav uses the best one you have.")
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
