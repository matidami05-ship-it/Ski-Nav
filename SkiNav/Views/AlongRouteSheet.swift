import SwiftUI

/// While navigating: find gas, food, charging… ahead on the route and add it as a stop.
struct AlongRouteSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var category: POICategory = .gas
    @State private var results: [POIResult] = []
    @State private var loading = false
    @State private var adding: POIResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(POICategory.allCases) { c in
                            Button {
                                category = c
                            } label: {
                                Label(c.label, systemImage: c.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(category == c ? .white : .primary)
                                    .background(category == c ? c.color : Color(.tertiarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                List {
                    if loading {
                        HStack { ProgressView(); Text("Looking ahead on your route…").foregroundStyle(.secondary) }
                    } else if results.isEmpty {
                        Text(model.search.hasOfflineDatabase
                            ? "No \(category.label.lowercased()) found near your route ahead."
                            : "Download a map to search along your route.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        POIRow(result: result, miles: model.settings.useMiles) {
                            adding = result
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Along Your Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                adding.map { "Add \($0.place.name) as a stop?" } ?? "",
                isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } }),
                titleVisibility: .visible
            ) {
                Button("Add Stop") {
                    if let place = adding?.place {
                        dismiss()
                        Task { await model.addStopWhileNavigating(place) }
                    }
                }
            } message: {
                if let result = adding {
                    Text("Ski Nav will route you there, then on to the rest of your trip. It's \(Fmt.distance(result.distance, miles: model.settings.useMiles)) ahead.")
                }
            }
            .task(id: category) {
                loading = true
                results = await model.findAlongRoute(category)
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}
