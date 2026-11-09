import CryptoKit
import Foundation

/// A piece of an instruction and the language to pronounce it in, e.g.
/// [("Za pół mili skręć w prawo w ", pl-PL), ("Main Street", en-US), (".", pl-PL)].
struct SpeechSegment: Equatable {
    var text: String
    var language: String
}

enum SpeechText {
    /// Splits text so known street names (US, English) are spoken in English inside
    /// instructions in another language.
    static func segments(_ text: String, language: String, streetNames: [String], englishNames: Bool) -> [SpeechSegment] {
        guard englishNames, !language.hasPrefix("en"), !streetNames.isEmpty else {
            return [SpeechSegment(text: text, language: language)]
        }
        // Longest names first so "North Main Street" wins over "Main Street".
        let names = streetNames.filter { $0.count > 2 }.sorted { $0.count > $1.count }
        var result: [SpeechSegment] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            var best: (Range<Substring.Index>, String)?
            for name in names {
                if let r = rest.range(of: name, options: .caseInsensitive),
                   best == nil || r.lowerBound < best!.0.lowerBound
                {
                    best = (r, name)
                }
            }
            guard let (range, _) = best else {
                result.append(SpeechSegment(text: String(rest), language: language))
                break
            }
            if range.lowerBound > rest.startIndex {
                result.append(SpeechSegment(text: String(rest[rest.startIndex ..< range.lowerBound]), language: language))
            }
            result.append(SpeechSegment(text: String(rest[range]), language: "en-US"))
            rest = rest[range.upperBound...]
        }
        return result.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty || $0.language == language }
    }
}

/// Microsoft Azure neural text to speech (very natural voices, free tier 500K characters a
/// month). Audio is cached on the phone so repeated and pre-fetched instructions play
/// instantly and keep working without signal.
enum AzureTTS {
    struct Voice: Identifiable, Hashable {
        var id: String
        var label: String
        var multilingual: Bool
    }

    static let polishVoices: [Voice] = [
        Voice(id: "pl-PL-ZofiaNeural", label: "Zofia (Polish, female)", multilingual: false),
        Voice(id: "pl-PL-MarekNeural", label: "Marek (Polish, male)", multilingual: false),
        Voice(id: "pl-PL-AgnieszkaNeural", label: "Agnieszka (Polish, female)", multilingual: false),
        Voice(id: "en-US-AvaMultilingualNeural", label: "Ava (bilingual, female)", multilingual: true),
        Voice(id: "en-US-AndrewMultilingualNeural", label: "Andrew (bilingual, male)", multilingual: true),
    ]

    static let englishVoices: [Voice] = [
        Voice(id: "en-US-AvaNeural", label: "Ava (female)", multilingual: false),
        Voice(id: "en-US-AndrewNeural", label: "Andrew (male)", multilingual: false),
        Voice(id: "en-US-JennyNeural", label: "Jenny (female)", multilingual: false),
        Voice(id: "en-US-GuyNeural", label: "Guy (male)", multilingual: false),
    ]

    static func voices(for language: String) -> [Voice] {
        language.hasPrefix("pl") ? polishVoices : englishVoices
    }

    static func voice(_ id: String) -> Voice? {
        (polishVoices + englishVoices).first { $0.id == id }
    }

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func ssml(_ segments: [SpeechSegment], voice: String, language: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let multilingual = voice.contains("Multilingual")
        let body: String
        if multilingual {
            // Bilingual voices switch language mid-sentence, so street names sound English.
            body = segments.map { "<lang xml:lang=\"\($0.language)\">\(esc($0.text))</lang>" }.joined()
        } else if voice.hasPrefix("pl-PL"), segments.contains(where: { $0.language != language }) {
            // A Polish voice can't switch language; slow down a touch on the English names.
            body = segments.map { $0.language == language ? esc($0.text) : "<prosody rate=\"-8%\">\(esc($0.text))</prosody>" }.joined()
        } else {
            body = esc(segments.map(\.text).joined())
        }
        return """
        <speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="https://www.w3.org/2001/mstts" xml:lang="\(language)">\
        <voice name="\(voice)"><prosody rate="+4%">\(body)</prosody></voice></speak>
        """
    }

    private static func cacheURL(_ ssml: String) -> URL {
        let hash = SHA256.hash(data: Data(ssml.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(hash + ".mp3")
    }

    static func cachedAudio(_ ssml: String) -> URL? {
        let url = cacheURL(ssml)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Fetches (or returns cached) audio for the SSML. nil on any failure.
    static func audio(_ ssml: String, key: String, region: String, timeout: TimeInterval = 4) async -> URL? {
        if let cached = cachedAudio(ssml) { return cached }
        guard !key.isEmpty,
              let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-96kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("SkiNav", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(ssml.utf8)
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200, result.0.count > 500
        else { return nil }
        let dest = cacheURL(ssml)
        try? result.0.write(to: dest, options: .atomic)
        return dest
    }

    /// Checks a key and region with a short phrase.
    static func validate(key: String, region: String, voice: String, language: String) async -> Bool {
        let s = ssml([SpeechSegment(text: language.hasPrefix("pl") ? "Test." : "Test.", language: language)],
                     voice: voice, language: language)
        return await audio(s, key: key, region: region, timeout: 10) != nil
    }

    /// Drops old cached audio (keeps the cache under ~200 MB).
    static func trimCache() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey])
        else { return }
        var total = 0
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast
            return a > b
        }
        for f in sorted {
            total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if total > 200_000_000 { try? fm.removeItem(at: f) }
        }
    }
}
