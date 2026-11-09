import AVFoundation
import SwiftUI

/// Guidance language (English / Polski) and the voice: iPhone voices, or natural Azure
/// neural voices with offline recording of each route.
struct VoiceSettingsView: View {
    @Bindable var model: AppModel
    @Bindable private var settings = AppSettings.shared
    @State private var checking = false
    @State private var keyResult: Bool?
    @State private var deviceVoice = ("", false)

    private var language: String { settings.guidanceLanguage.rawValue }

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $settings.guidanceLanguage) {
                    ForEach(GuidanceLanguage.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.guidanceLanguage) {
                    // Pick a matching natural voice for the new language.
                    let voices = AzureTTS.voices(for: language)
                    if !voices.contains(where: { $0.id == settings.azureVoice }) {
                        settings.azureVoice = voices[0].id
                    }
                    deviceVoice = VoiceSynthesizer.describeBestVoice(language: language)
                }
                if settings.guidanceLanguage == .polish {
                    Toggle("Say street names in English", isOn: $settings.englishStreetNames)
                }
                Picker("Units", selection: $settings.useMiles) {
                    Text(settings.guidanceLanguage == .polish ? "Mile" : "Miles").tag(true)
                    Text(settings.guidanceLanguage == .polish ? "Kilometry" : "Kilometers").tag(false)
                }
            } header: {
                Text("Guidance")
            } footer: {
                Text(settings.guidanceLanguage == .polish
                    ? "Every turn, with street names and distances, spoken and shown in Polish: „Za pół mili skręć w prawo w Main Street.” US street names keep their English pronunciation."
                    : "Every turn, with street names and distances.")
            }

            Section {
                Picker("Voice", selection: $settings.voiceEngine) {
                    ForEach(VoiceEngine.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Voice")
            } footer: {
                Text(settings.voiceEngine == .azure
                    ? "Microsoft neural voices sound like a real person. Your route's instructions are recorded when you start, so the voice keeps working without signal. Falls back to the iPhone voice if needed."
                    : "Works offline. For a more natural sound, download an Enhanced or Premium voice: iPhone Settings › Accessibility › Spoken Content › Voices › \(settings.guidanceLanguage == .polish ? "Polish › Zosia" : "English").")
            }

            if settings.voiceEngine == .azure {
                Section {
                    Picker("Voice", selection: $settings.azureVoice) {
                        ForEach(AzureTTS.voices(for: language)) { v in Text(v.label).tag(v.id) }
                    }
                    SecureField("Azure Speech key", text: $settings.azureKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Region (e.g. eastus)", text: $settings.azureRegion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        checking = true
                        keyResult = nil
                        Task {
                            keyResult = await AzureTTS.validate(
                                key: settings.azureKey.trimmingCharacters(in: .whitespaces),
                                region: settings.azureRegion.trimmingCharacters(in: .whitespaces),
                                voice: settings.azureVoice, language: language)
                            checking = false
                        }
                    } label: {
                        HStack {
                            Text("Check Key")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(settings.azureKey.isEmpty || checking)
                    if let keyResult {
                        Label(keyResult ? "Working" : "Didn't work — check the key and region.",
                              systemImage: keyResult ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(keyResult ? .green : .red)
                    }
                } header: {
                    Text("Natural voice")
                } footer: {
                    Text("Free: in the Azure portal create a Speech resource with the Free (F0) tier — 500,000 characters a month, about 200+ drives. Copy Key 1 and the Region from Keys and Endpoint. (Azure sign-up asks for a card to verify you; the free tier isn't charged.)")
                }
                Section {
                    Link("Open Azure Portal", destination: URL(string: "https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices")!)
                }
            } else {
                Section("iPhone voice") {
                    LabeledContent("Using", value: deviceVoice.0)
                    if !deviceVoice.1 {
                        Label("Download an Enhanced voice for a much more natural sound.", systemImage: "arrow.down.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Speaking speed")
                    Slider(value: $settings.speechRate, in: 0.42 ... 0.62) {
                        Text("Speaking speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise.fill")
                    } maximumValueLabel: {
                        Image(systemName: "hare.fill")
                    }
                }
                Button {
                    playSample()
                } label: {
                    Label("Play Sample", systemImage: "play.circle.fill")
                }
            } footer: {
                if settings.voiceEngine == .azure {
                    Text("Speed applies to the iPhone voice; natural voices use their own pacing.")
                }
            }
        }
        .navigationTitle("Voice & Language")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { deviceVoice = VoiceSynthesizer.describeBestVoice(language: language) }
    }

    private func playSample() {
        let voice = model.voice
        voice.config = AppModel.voiceConfig(settings)
        voice.rate = Float(settings.speechRate)
        voice.streetNames = ["Main Street"]
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        voice.speak(text: Phrases.text("sample", language: language))
    }
}
