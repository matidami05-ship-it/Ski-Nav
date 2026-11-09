import Foundation
import Observation

/// Home, Work, saved places and recent destinations, kept on the phone.
@MainActor
@Observable
final class Library {
    static let shared = Library()

    private(set) var home: Place?
    private(set) var work: Place?
    private(set) var saved: [Place] = []
    private(set) var recents: [Place] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    private struct Stored: Codable {
        var home: Place?
        var work: Place?
        var saved: [Place]
        var recents: [Place]
    }

    private init() {
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            home = stored.home
            work = stored.work
            saved = stored.saved
            recents = stored.recents
        }
    }

    func setHome(_ place: Place?) {
        home = place.map { renamed($0, "Home") }
        save()
    }

    func setWork(_ place: Place?) {
        work = place.map { renamed($0, "Work") }
        save()
    }

    func isSaved(_ place: Place) -> Bool {
        saved.contains { $0.id == place.id }
    }

    func toggleSaved(_ place: Place) {
        if let i = saved.firstIndex(where: { $0.id == place.id }) {
            saved.remove(at: i)
        } else {
            saved.insert(place, at: 0)
        }
        save()
    }

    func removeSaved(at offsets: IndexSet) {
        saved.remove(atOffsets: offsets)
        save()
    }

    func addRecent(_ place: Place) {
        recents.removeAll { $0.id == place.id }
        recents.insert(place, at: 0)
        if recents.count > 20 { recents.removeLast(recents.count - 20) }
        save()
    }

    func clearRecents() {
        recents = []
        save()
    }

    private func renamed(_ place: Place, _ label: String) -> Place {
        var p = place
        if p.subtitle.isEmpty || p.id.hasPrefix("pin-") {
            p.subtitle = p.name
        } else if p.name != label {
            p.subtitle = "\(p.name) · \(p.subtitle)"
        }
        p.name = label
        p.id = "fav-\(label.lowercased())"
        return p
    }

    private func save() {
        let stored = Stored(home: home, work: work, saved: saved, recents: recents)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
