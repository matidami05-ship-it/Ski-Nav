import SwiftUI

/// Plan a trip with several stops: add, drag to reorder, optimize the order, then go.
struct TripPlannerSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [Place] = []
    @State private var addingStop = false
    @State private var optimizing = false
    @State private var editMode: EditMode = .active

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        marker(systemImage: "location.fill", color: .blue)
                        Text("My Location").font(.body.weight(.semibold))
                    }
                } header: {
                    Text("Start")
                }

                Section {
                    ForEach(Array(draft.enumerated()), id: \.element.id) { index, stop in
                        HStack(spacing: 12) {
                            numberMarker(index + 1, last: index == draft.count - 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name).font(.body.weight(.semibold)).lineLimit(1)
                                if !stop.subtitle.isEmpty {
                                    Text(stop.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if draft == model.stops, model.stopETAs.indices.contains(index) {
                                Text(Fmt.arrival(after: model.stopETAs[index]))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { draft.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.remove(atOffsets: $0) }

                    Button {
                        addingStop = true
                    } label: {
                        Label("Add Stop", systemImage: "plus.circle.fill")
                    }
                    .disabled(draft.count >= 15)
                } header: {
                    Text("Stops")
                } footer: {
                    Text(draft.count < 2
                        ? "Add places, then drag ≡ to reorder. The last stop is your destination."
                        : "Drag ≡ to reorder. The last stop is your destination.")
                }

                if draft.count >= 2 {
                    Section {
                        Button {
                            optimize(keepLast: true)
                        } label: {
                            Label("Fastest order, same destination", systemImage: "wand.and.stars")
                        }
                        Button {
                            optimize(keepLast: false)
                        } label: {
                            Label("Fastest order, any destination", systemImage: "arrow.triangle.swap")
                        }
                    } header: {
                        Text("Optimize")
                    } footer: {
                        if optimizing {
                            Text("Working out drive times…")
                        } else {
                            Text("Uses real \(model.isWalking ? "walking" : "driving") times between every stop.")
                        }
                    }
                    .disabled(optimizing)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Plan Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !draft.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") { draft = [] }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.setStops(draft)
                    dismiss()
                    Task { await model.planRoute() }
                } label: {
                    Text(draft.count > 1 ? "Get Directions · \(draft.count) Stops" : "Get Directions")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(draft.isEmpty)
                .padding()
                .background(.bar)
            }
            .sheet(isPresented: $addingStop) {
                SearchSheet(model: model) { place in
                    addingStop = false
                    // New stops go before the destination.
                    if draft.count >= 1 { draft.insert(place, at: draft.count - 1) } else { draft.append(place) }
                }
            }
        }
        .onAppear { draft = model.stops }
    }

    private func optimize(keepLast: Bool) {
        optimizing = true
        Task {
            model.setStops(draft)
            await model.optimizeStops(keepLastFixed: keepLast)
            withAnimation { draft = model.stops }
            optimizing = false
        }
    }

    private func marker(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color.gradient, in: Circle())
    }

    private func numberMarker(_ n: Int, last: Bool) -> some View {
        Text("\(n)")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background((last ? Color.red : Color.indigo).gradient, in: Circle())
    }
}
