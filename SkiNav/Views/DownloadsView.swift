import SwiftUI

struct DownloadsView: View {
    @Bindable var model: AppModel
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete: RegionPack?
    @State private var query = ""

    private var nearYou: [RegionPack] {
        guard let here = model.userLocation?.coordinate else { return [] }
        return store.catalog.filter { $0.contains(here) }.sorted { $0.area < $1.area }
    }

    private var allPacks: [RegionPack] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = store.catalog.sorted { $0.name < $1.name }
        return q.isEmpty ? sorted : sorted.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var store: RegionStore { model.regions }

    var body: some View {
        List {
            if !store.installed.isEmpty {
                Section {
                    ForEach(store.installedPacks) { pack in
                        installedRow(pack)
                        detailRow(pack)
                    }
                } header: {
                    Text("On this iPhone")
                } footer: {
                    Text("Downloaded maps work with no signal: the map, search, and turn-by-turn directions.")
                }
            }

            if query.isEmpty, !nearYou.isEmpty {
                Section("Near You") {
                    ForEach(nearYou) { pack in
                        availableRow(pack)
                    }
                }
            }

            Section {
                if store.catalog.isEmpty {
                    if store.isLoadingCatalog {
                        HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                    } else {
                        Text(store.catalogError ?? "No maps available yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(allPacks) { pack in
                    availableRow(pack)
                }
            } header: {
                Text("All States")
            } footer: {
                Text("Each state includes the map, offline search, driving and walking directions, and road alerts. Downloads keep going in the background; Wi-Fi recommended. Maps are rebuilt monthly from OpenStreetMap. Trips crossing a state line route online when there's signal, or download a combined pack like Wisconsin + Illinois.")
            }
        }
        .navigationTitle("Download Maps")
        .searchable(text: $query, prompt: "Search states")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshCatalog() }
        .task { await store.refreshCatalog() }
        .toolbar {
            if model.showDownloads {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "Delete \(confirmDelete?.name ?? "map")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pack = confirmDelete { store.delete(pack.id) }
            }
        } message: {
            Text("You can download it again later.")
        }
    }

    private func installedRow(_ pack: RegionPack) -> some View {
        let isActive = model.activePack?.id == pack.id
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "map.fill")
                .font(.title2)
                .foregroundStyle(isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name).font(.body.weight(.semibold))
                Text("\(Fmt.bytes(pack.totalSize)) · updated \(pack.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isActive {
                    Text("In use").font(.caption.weight(.semibold)).foregroundStyle(.green)
                }
            }
            Spacer()
            if store.updateAvailable(pack.id), let latest = store.catalog.first(where: { $0.id == pack.id }) {
                Button("Update") { store.download(latest) }
                    .buttonStyle(.bordered)
                    .disabled(store.isDownloading(pack.id))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            settings.activeRegionID = pack.id
        }
        .swipeActions {
            Button("Delete", role: .destructive) { confirmDelete = pack }
        }
        .contextMenu {
            Button("Use This Map", systemImage: "checkmark") { settings.activeRegionID = pack.id }
            Button("Pick Automatically", systemImage: "location") { settings.activeRegionID = nil }
            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = pack }
        }
    }

    /// Optional 3D street detail for an installed pack: lanes, crosswalks, sidewalks, rail.
    @ViewBuilder
    private func detailRow(_ pack: RegionPack) -> some View {
        let offered = store.detailAvailable(pack.id)
        let have = store.detailURL(pack) != nil
        if offered != nil || have || store.detailProgress[pack.id] != nil {
            HStack(spacing: 12) {
                Image(systemName: "view.3d")
                    .font(.title3)
                    .foregroundStyle(have ? Color.green : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("3D street detail").font(.subheadline.weight(.semibold))
                    Text(have ? "Lane markings, crosswalks, sidewalks, rail · \(Fmt.bytes(pack.files.detail?.size ?? 0))"
                        : "Lane markings, crosswalks, sidewalks, rail · \(Fmt.bytes(offered?.size ?? 0))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let progress = store.detailProgress[pack.id] {
                    ProgressView(value: progress).frame(width: 60)
                } else if offered != nil {
                    Button {
                        store.downloadDetail(pack.id)
                    } label: {
                        Image(systemName: "icloud.and.arrow.down").font(.title3)
                    }
                    .buttonStyle(.borderless)
                } else if have {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 20)
            .swipeActions {
                if have {
                    Button("Remove", role: .destructive) { store.deleteDetail(pack.id) }
                }
            }
        }
    }

    @ViewBuilder
    private func availableRow(_ pack: RegionPack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name).font(.body.weight(.semibold))
                    Text("\(Fmt.bytes(pack.totalSize)) · \(pack.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let progress = store.progress[pack.id] {
                    Button {
                        store.cancel(pack.id)
                    } label: {
                        ZStack {
                            Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
                            Circle().trim(from: 0, to: progress)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "stop.fill").font(.system(size: 9))
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                } else if store.installed[pack.id]?.version == pack.version {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                } else {
                    Button {
                        store.download(pack)
                    } label: {
                        Image(systemName: "icloud.and.arrow.down").font(.title3)
                    }
                    .buttonStyle(.borderless)
                }
            }
            if let progress = store.progress[pack.id] {
                Text("Downloading… \(Int(progress * 100))% of \(Fmt.bytes(pack.totalSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = store.downloadErrors[pack.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}
