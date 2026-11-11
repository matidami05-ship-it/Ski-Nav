import AVFoundation
import FerrostarCore
import FerrostarCoreFFI

/// Speaks turn instructions.
///
/// - With an Azure key: natural neural voices. Every instruction of the route is recorded
///   when navigation starts, so it keeps talking without signal.
/// - Otherwise (or if a recording isn't available): the best iPhone voice for the language.
///   Enhanced and Premium voices (Settings › Accessibility › Spoken Content › Voices) are
///   used automatically.
/// In Polish, US street names are said with English pronunciation.
final class VoiceSynthesizer: NSObject, SpeechSynthesizer, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var fetching = 0
    private let lock = NSLock()

    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    /// Current settings, refreshed when navigation starts.
    struct Config {
        var language = "en-US"
        var englishStreetNames = true
        var azure = false
        var azureKey = ""
        var azureRegion = "eastus"
        var azureVoice = "en-US-AvaNeural"
    }

    var config = Config()
    /// Street names on the current route, so they can be pronounced in English.
    var streetNames: [String] = []

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool {
        lock.lock(); defer { lock.unlock() }
        return synth.isSpeaking || fetching > 0 || (player?.isPlaying ?? false)
    }

    func speak(_ utterance: AVSpeechUtterance) {
        speak(text: utterance.speechString)
    }

    func speak(text: String) {
        let segments = SpeechText.segments(text, language: config.language, streetNames: streetNames,
                                           englishNames: config.englishStreetNames)
        guard config.azure else {
            speakOnDevice(segments)
            return
        }
        let ssml = AzureTTS.ssml(segments, voice: config.azureVoice, language: config.language)
        if let cached = AzureTTS.cachedAudio(ssml), play(cached) { return }

        lock.lock(); fetching += 1; lock.unlock()
        let cfg = config
        Task {
            // Short timeout: a late instruction is worse than a robotic one.
            let url = await AzureTTS.audio(ssml, key: cfg.azureKey, region: cfg.azureRegion, timeout: 2.5)
            await MainActor.run {
                self.lock.lock(); self.fetching -= 1; self.lock.unlock()
                if let url, self.play(url) { return }
                self.speakOnDevice(segments)
            }
        }
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        player?.stop()
        player = nil
        return synth.stopSpeaking(at: boundary)
    }

    // MARK: Recorded (Azure) audio

    private func play(_ url: URL) -> Bool {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        player?.stop()
        p.delegate = self
        p.prepareToPlay()
        player = p
        return p.play()
    }

    /// Records every instruction of the route in the background so it plays instantly and
    /// works offline later.
    func prefetch(_ route: Route, extraPhrases: [String] = []) {
        guard config.azure else { return }
        let cfg = config
        let names = streetNames
        let texts = Array(Set(route.steps.flatMap { $0.spokenInstructions.map(\.text) } + extraPhrases))
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for text in texts {
                    if running >= 4 { _ = await group.next(); running -= 1 }
                    let segments = SpeechText.segments(text, language: cfg.language, streetNames: names,
                                                       englishNames: cfg.englishStreetNames)
                    let ssml = AzureTTS.ssml(segments, voice: cfg.azureVoice, language: cfg.language)
                    group.addTask { _ = await AzureTTS.audio(ssml, key: cfg.azureKey, region: cfg.azureRegion, timeout: 15) }
                    running += 1
                }
            }
            AzureTTS.trimCache()
        }
    }

    // MARK: iPhone voices

    private func speakOnDevice(_ segments: [SpeechSegment]) {
        for segment in segments {
            let u = AVSpeechUtterance(string: segment.text)
            u.voice = Self.bestVoice(language: segment.language)
            u.rate = rate
            u.preUtteranceDelay = 0
            u.postUtteranceDelay = 0
            u.prefersAssistiveTechnologySettings = false
            synth.speak(u)
        }
    }

    private static var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    /// The most natural installed voice for a language (Premium > Enhanced > default).
    static func bestVoice(language: String = Locale.preferredLanguages.first ?? "en-US") -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] { return cached }
        let prefix = String(language.prefix(2))
        // A voice the user picked in Settings wins, as long as it's still installed.
        if let id = chosenVoiceID(language: language), let chosen = AVSpeechSynthesisVoice(identifier: id) {
            voiceCache[language] = chosen
            return chosen
        }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium: s += 300
            case .enhanced: s += 200
            default: s += 100
            }
            if v.language == language { s += 50 }
            if v.voiceTraits.contains(.isNoveltyVoice) { s -= 500 }
            if v.voiceTraits.contains(.isPersonalVoice) { s -= 50 }
            return s
        }
        let best = voices.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: language)
        if let best { voiceCache[language] = best }
        return best
    }

    static func resetVoiceCache() { voiceCache = [:] }

    // MARK: Picking a voice

    private static let chosenKey = "deviceVoices"

    /// The voice picked for a language ("en", "pl"…), or nil for automatic.
    static func chosenVoiceID(language: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: chosenKey) as? [String: String])?[String(language.prefix(2))]
    }

    static func setChosenVoice(_ id: String?, language: String) {
        var all = UserDefaults.standard.dictionary(forKey: chosenKey) as? [String: String] ?? [:]
        all[String(language.prefix(2))] = id
        UserDefaults.standard.set(all, forKey: chosenKey)
        resetVoiceCache()
    }

    /// Every installed voice for a language: best quality first, then the exact region, then by name.
    static func installedVoices(language: String) -> [AVSpeechSynthesisVoice] {
        let prefix = String(language.prefix(2))
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            if v.voiceTraits.contains(.isNoveltyVoice) { return 0 }
            switch v.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted {
                if rank($0) != rank($1) { return rank($0) > rank($1) }
                if ($0.language == language) != ($1.language == language) { return $0.language == language }
                return $0.name < $1.name
            }
    }

    static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        if v.voiceTraits.contains(.isNoveltyVoice) { return "Fun" }
        switch v.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Compact"
        }
    }

    /// "Zosia (Enhanced)" — what the iPhone will use.
    static func describeBestVoice(language: String) -> (name: String, natural: Bool) {
        resetVoiceCache()
        guard let v = bestVoice(language: language) else { return ("None installed", false) }
        let q = v.quality == .premium ? "Premium" : v.quality == .enhanced ? "Enhanced" : "Default"
        return ("\(v.name) (\(q))", v.quality != .default)
    }
}

/// The app's own spoken phrases (alerts), in the guidance language.
enum Phrases {
    static func text(_ key: String, language: String) -> String {
        let polish = language.hasPrefix("pl")
        switch key {
        case "camera": return polish ? "Uwaga, fotoradar." : "Speed camera ahead."
        case "railroad": return polish ? "Uwaga, przejazd kolejowy." : "Railroad crossing ahead."
        case "traffic": return polish ? "Uwaga, korek na trasie." : "Heavy traffic ahead."
        case "sample": return polish
            ? "Za pół mili skręć w prawo w Main Street. Następnie trzymaj się lewej strony."
            : "In half a mile, turn right onto Main Street. Then keep left."
        case "streetSample": return "Main Street. Lake Geneva Boulevard. Wells Street."
        default: return key
        }
    }
}
