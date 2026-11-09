import AVFoundation
import FerrostarCore

/// Speaks turn instructions with the best English voice installed on the phone.
///
/// iOS ships basic voices; Enhanced and Premium voices (Settings › Accessibility ›
/// Spoken Content › Voices) sound much more natural and are used automatically.
final class VoiceSynthesizer: SpeechSynthesizer {
    private let synth = AVSpeechSynthesizer()
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestVoice()

    var isSpeaking: Bool { synth.isSpeaking }

    func speak(_ utterance: AVSpeechUtterance) {
        if let voice { utterance.voice = voice }
        utterance.rate = rate
        utterance.prefersAssistiveTechnologySettings = false
        synth.speak(utterance)
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        synth.stopSpeaking(at: boundary)
    }

    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let lang = Locale.preferredLanguages.first ?? "en-US"
        let prefix = lang.hasPrefix("en") ? lang : "en-US"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(prefix.prefix(2))) }
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = 0
            switch v.quality {
            case .premium: s += 300
            case .enhanced: s += 200
            default: s += 100
            }
            if v.language == prefix { s += 50 }
            if v.voiceTraits.contains(.isNoveltyVoice) { s -= 500 }
            if v.voiceTraits.contains(.isPersonalVoice) { s -= 50 }
            return s
        }
        return voices.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: prefix)
    }
}
