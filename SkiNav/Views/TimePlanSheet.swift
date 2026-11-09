import SwiftUI

/// "Arrive by" / "Leave at": when to leave to get there on time, or when you'll arrive.
struct TimePlanSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case arriveBy = "Arrive By"
        case leaveAt = "Leave At"
        var id: String { rawValue }
    }

    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .arriveBy
    @State private var time: Date = TimePlanSheet.defaultTime()
    @State private var buffer = 0
    @State private var result: (departure: Date, arrival: Date, delay: Double, predicted: Bool)?
    @State private var loading = false
    @State private var reminderMessage: String?
    private let reminders = LeaveReminders.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Plan", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    DatePicker(mode == .arriveBy ? "Arrive by" : "Leave at", selection: $time,
                               in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    if mode == .arriveBy {
                        Picker("Extra time", selection: $buffer) {
                            Text("None").tag(0)
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                    }
                } header: {
                    Text("To \(model.stops.last?.name ?? model.selectedPlace?.name ?? "destination")")
                }

                Section {
                    if loading {
                        HStack { ProgressView(); Text("Checking traffic for that time…").foregroundStyle(.secondary) }
                    } else if let result {
                        resultView(result)
                    }
                } footer: {
                    if let result, !result.predicted {
                        Text(model.settings.hasTrafficKey
                            ? "Couldn’t get traffic for that time, so this uses normal drive time."
                            : "Uses normal drive time. Set up Live Traffic in Settings for predicted traffic.")
                    }
                }

                if mode == .arriveBy, let result, result.departure > Date() {
                    Section {
                        if let pending = reminders.pending {
                            Label("Reminder set for \(pending.leaveAt.formatted(date: .abbreviated, time: .shortened))",
                                  systemImage: "bell.badge.fill")
                            Button("Cancel Reminder", role: .destructive) { reminders.cancel() }
                        } else {
                            Button {
                                Task { await remind(result) }
                            } label: {
                                Label("Remind Me When to Leave", systemImage: "bell.fill")
                            }
                        }
                        if let reminderMessage {
                            Text(reminderMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("You'll get a heads-up 10 minutes before and again when it's time to go. Tap it for directions.")
                    }
                }
            }
            .navigationTitle("Plan Your Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: "\(mode.rawValue)-\(time.timeIntervalSince1970)-\(buffer)") {
                try? await Task.sleep(nanoseconds: 350_000_000) // wait for the picker to settle
                await calculate()
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func resultView(_ r: (departure: Date, arrival: Date, delay: Double, predicted: Bool)) -> some View {
        let travel = r.arrival.timeIntervalSince(r.departure)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(mode == .arriveBy ? "Leave by" : "Arrive at")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text((mode == .arriveBy ? r.departure : r.arrival).formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(mode == .arriveBy && r.departure < Date() ? Color.red : Color.accentColor)
            }
            if mode == .arriveBy, r.departure < Date() {
                Label("That's already passed — leave now and you'll arrive around \(Date().addingTimeInterval(travel).formatted(date: .omitted, time: .shortened)).",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if mode == .arriveBy, r.departure.timeIntervalSinceNow < 3600 {
                Text("That's \(Fmt.duration(r.departure.timeIntervalSinceNow)) from now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(Fmt.duration(travel) + " drive", systemImage: "car.fill")
                Spacer()
                if r.predicted {
                    Text(r.delay >= 120 ? "+\(Fmt.duration(r.delay)) traffic expected" : "Light traffic expected")
                        .foregroundStyle(r.delay >= 600 ? .red : r.delay >= 120 ? .orange : .green)
                }
            }
            .font(.subheadline)
            if buffer > 0, mode == .arriveBy {
                Text("Includes \(buffer) min extra time.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func calculate() async {
        guard let route = model.selectedRoute else { return }
        loading = true
        defer { loading = false }
        let extra = TimeInterval(mode == .arriveBy ? buffer * 60 : 0)
        let target = mode == .arriveBy ? time.addingTimeInterval(-extra) : time
        let key = model.settings.tomtomKey.trimmingCharacters(in: .whitespaces)

        if !key.isEmpty, Connectivity.shared.isOnline, !model.isWalking,
           let p = await TrafficService.plan(geometry: route.geometry, stops: model.stops.map(\.coordinate), key: key,
                                             arriveAt: mode == .arriveBy ? target : nil,
                                             departAt: mode == .leaveAt ? target : nil)
        {
            result = (p.departure, p.arrival, p.delay, true)
            return
        }
        // No traffic data: normal drive time.
        let duration = route.duration
        if mode == .arriveBy {
            result = (target.addingTimeInterval(-duration), target, 0, false)
        } else {
            result = (time, time.addingTimeInterval(duration), 0, false)
        }
    }

    private func remind(_ r: (departure: Date, arrival: Date, delay: Double, predicted: Bool)) async {
        let travel = Fmt.duration(r.arrival.timeIntervalSince(r.departure)) + (r.predicted ? " with traffic" : "")
        let ok = await reminders.schedule(leaveAt: r.departure, arriveAt: time, stops: model.stops, travelText: travel)
        reminderMessage = ok ? nil : "Notifications are off for Ski Nav. Turn them on in iPhone Settings › Notifications."
    }

    private static func defaultTime() -> Date {
        // Next quarter hour, an hour from now.
        let t = Date().addingTimeInterval(3600)
        let minutes = Calendar.current.component(.minute, from: t)
        let rounded = Calendar.current.date(byAdding: .minute, value: (15 - minutes % 15) % 15, to: t) ?? t
        return Calendar.current.date(bySetting: .second, value: 0, of: rounded) ?? rounded
    }
}
