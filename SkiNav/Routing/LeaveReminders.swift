import Foundation
import Observation
import UserNotifications

/// "Time to leave" notifications. Tapping one opens directions to the place.
@MainActor
@Observable
final class LeaveReminders: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = LeaveReminders()

    struct Reminder: Codable, Equatable {
        var id: String
        var leaveAt: Date
        var arriveAt: Date
        var stops: [Place]
        var destinationName: String { stops.last?.name ?? "your destination" }
    }

    private(set) var pending: Reminder?

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "leaveReminder"),
           let r = try? JSONDecoder().decode(Reminder.self, from: data), r.leaveAt > Date()
        {
            pending = r
        }
    }

    /// Call at launch so taps on notifications reach us.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Schedules the reminder (and a heads-up 10 minutes earlier). Returns false if
    /// notifications aren't allowed.
    func schedule(leaveAt: Date, arriveAt: Date, stops: [Place], travelText: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        cancel()

        let reminder = Reminder(id: UUID().uuidString, leaveAt: leaveAt, arriveAt: arriveAt, stops: stops)
        let payload = (try? JSONEncoder().encode(stops)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let arrive = arriveAt.formatted(date: .omitted, time: .shortened)

        func add(_ suffix: String, at date: Date, title: String, body: String) async {
            guard date > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.userInfo = ["stops": payload]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let request = UNNotificationRequest(
                identifier: reminder.id + suffix, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
        await add("-soon", at: leaveAt.addingTimeInterval(-600),
                  title: "Leave in 10 minutes",
                  body: "For \(reminder.destinationName) by \(arrive) · \(travelText)")
        await add("-now", at: leaveAt,
                  title: "Time to leave for \(reminder.destinationName)",
                  body: "\(travelText) · arrive by \(arrive). Tap for directions.")

        pending = reminder
        if let data = try? JSONEncoder().encode(reminder) {
            UserDefaults.standard.set(data, forKey: "leaveReminder")
        }
        return true
    }

    func cancel() {
        if let id = pending?.id {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id + "-soon", id + "-now"])
        }
        pending = nil
        UserDefaults.standard.removeObject(forKey: "leaveReminder")
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .sound]
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["stops"] as? String,
              let stops = try? JSONDecoder().decode([Place].self, from: Data(text.utf8)), !stops.isEmpty
        else { return }
        if response.notification.request.identifier.hasSuffix("-now") {
            pending = nil
            UserDefaults.standard.removeObject(forKey: "leaveReminder")
        }
        let model = AppModel.shared
        model.start()
        // Give location a few seconds to arrive after a cold start.
        for _ in 0 ..< 20 where model.userLocation == nil {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        model.setStops(stops)
        await model.planRoute()
    }
}
