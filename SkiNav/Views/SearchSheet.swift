import CoreLocation
import SwiftUI

struct SearchSheet: View {
    @Bindable var model: AppModel
    var onPick: (Place) -> Void
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private var search: PlaceSearch { model.search }

    var body: some View {
        NavigationStack {
            List {
                if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else {
                    results
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { searchField }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search places or addresses", text: Bindable(search).query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    if let first = search.results.first { pick(first) }
                }
            if search.isSearching {
                ProgressView().controlSize(.small)
            } else if !search.query.isEmpty {
                Button { search.clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var suggestions: some View {
        Section {
            favoriteRow(model.library.home, title: "Home", systemImage: "house.fill", tint: .blue)
            favoriteRow(model.library.work, title: "Work", systemImage: "briefcase.fill", tint: .brown)
        }
        if !model.library.saved.isEmpty {
            Section("Saved") {
                ForEach(model.library.saved) { place in
                    row(place, systemImage: "star.fill", tint: .orange)
                }
                .onDelete { model.library.removeSaved(at: $0) }
            }
        }
        if !model.library.recents.isEmpty {
            Section {
                ForEach(model.library.recents) { place in
                    row(place, systemImage: "clock.arrow.circlepath", tint: .gray)
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { model.library.clearRecents() }
                        .font(.caption)
                }
            }
        }
        Section {
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }

    private var footer: String {
        if !search.hasOfflineDatabase {
            return "Download a map to search offline. Long-press the map to drop a pin anywhere."
        }
        return "Searching works offline with your downloaded map. Long-press the map to drop a pin anywhere."
    }

    @ViewBuilder
    private func favoriteRow(_ place: Place?, title: String, systemImage: String, tint: Color) -> some View {
        if let place {
            row(place, systemImage: systemImage, tint: tint)
        } else {
            HStack(spacing: 12) {
                icon(systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text("Search for a place, then tap ⋯ › Set as \(title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if search.results.isEmpty && !search.isSearching {
            ContentUnavailableView.search(text: search.query)
        } else {
            Section {
                ForEach(search.results) { place in
                    row(place, systemImage: place.symbol, tint: .red)
                }
            } footer: {
                if !Connectivity.shared.isOnline {
                    Text("Offline · results from your downloaded map")
                }
            }
        }
    }

    private func row(_ place: Place, systemImage: String, tint: Color) -> some View {
        Button { pick(place) } label: {
            HStack(spacing: 12) {
                icon(systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let here = model.userLocation {
                    Text(Fmt.distance(here.distance(from: place.location), miles: model.settings.useMiles))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func icon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint.gradient, in: Circle())
    }

    private func pick(_ place: Place) {
        search.clear()
        onPick(place)
    }
}
