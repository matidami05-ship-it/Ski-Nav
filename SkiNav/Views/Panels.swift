import CoreLocation
import FerrostarCoreFFI
import SwiftUI

// MARK: Browse

struct BrowsePanel: View {
    @Bindable var model: AppModel
    var openSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: openSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("Where to?")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.title3)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ShortcutChip(title: "Home", subtitle: model.library.home == nil ? "Add" : eta(model.library.home),
                                 systemImage: "house.fill", tint: .blue) {
                        if let home = model.library.home { model.drive(to: home) } else { openSearch() }
                    }
                    ShortcutChip(title: "Work", subtitle: model.library.work == nil ? "Add" : eta(model.library.work),
                                 systemImage: "briefcase.fill", tint: .brown) {
                        if let work = model.library.work { model.drive(to: work) } else { openSearch() }
                    }
                    ForEach(model.library.saved.prefix(6)) { place in
                        ShortcutChip(title: place.name, subtitle: eta(place), systemImage: "star.fill", tint: .orange) {
                            model.select(place)
                        }
                    }
                }
            }

            statusRow
        }
    }

    private func eta(_ place: Place?) -> String {
        guard let place, let here = model.userLocation else { return "" }
        return Fmt.distance(here.distance(from: place.location), miles: model.settings.useMiles)
    }

    private var statusRow: some View {
        Button { model.showDownloads = true } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(model.routingMode.label)
                    .font(.footnote.weight(.medium))
                Spacer()
                if let progress = model.regions.progress.values.first {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if case .offline = model.routingMode {
                    EmptyView()
                } else {
                    Text("Download maps")
                        .font(.footnote.weight(.semibold))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch model.routingMode {
        case .offline: "checkmark.icloud.fill"
        case .online: "antenna.radiowaves.left.and.right"
        case .unavailable: "exclamationmark.icloud.fill"
        }
    }

    private var color: Color {
        switch model.routingMode {
        case .offline: .green
        case .online: .blue
        case .unavailable: .orange
        }
    }
}

struct ShortcutChip: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Place

struct PlaceCard: View {
    @Bindable var model: AppModel
    var place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: place.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.red.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                CloseButton { model.closePlace() }
            }

            if model.settings.streetView {
                LookAroundSection(coordinate: place.coordinate)
            }

            HStack(spacing: 10) {
                Button {
                    model.drive(to: place)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))

                Button {
                    model.library.toggleSaved(place)
                } label: {
                    Image(systemName: model.library.isSaved(place) ? "star.fill" : "star")
                        .font(.headline)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.orange)

                Menu {
                    Button("Set as Home", systemImage: "house") { model.library.setHome(place) }
                    Button("Set as Work", systemImage: "briefcase") { model.library.setWork(place) }
                    Button("Copy Coordinates", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = String(format: "%.6f, %.6f", place.latitude, place.longitude)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let here = model.userLocation {
            parts.append(Fmt.distance(here.distance(from: place.location), miles: model.settings.useMiles))
        }
        if !place.subtitle.isEmpty { parts.append(place.subtitle) }
        return parts.joined(separator: " · ")
    }
}

struct CloseButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Routes

struct RoutesPanel: View {
    @Bindable var model: AppModel
    @Bindable private var settings = AppSettings.shared
    @State private var showOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To \(model.selectedPlace?.name ?? "destination")")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.routingMode.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showOptions.toggle() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                CloseButton {
                    if let place = model.selectedPlace { model.select(place) } else { model.closePlace() }
                }
            }

            if showOptions {
                VStack(spacing: 4) {
                    Toggle("Avoid tolls", isOn: $settings.avoidTolls)
                    Toggle("Avoid highways", isOn: $settings.avoidHighways)
                    Toggle("Avoid ferries", isOn: $settings.avoidFerries)
                }
                .font(.subheadline)
                .onChange(of: model.settings.routingKey) {
                    // Options changed: the engine is rebuilt (RootView), then routes recalculate.
                    if let place = model.selectedPlace {
                        Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            await model.directions(to: place)
                        }
                    }
                }
            }

            if model.isLoadingRoutes {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding routes…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.routes.enumerated()), id: \.offset) { index, route in
                        routeRow(route, index: index)
                    }
                }

                Button {
                    model.startNavigation()
                } label: {
                    Text("Go")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .tint(.green)
                .disabled(model.selectedRoute == nil)
            }
        }
    }

    private func routeRow(_ route: Route, index: Int) -> some View {
        let selected = index == model.selectedRouteIndex
        return Button {
            model.selectedRouteIndex = index
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.duration(route.duration))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    Text([
                        Fmt.distance(route.distance, miles: model.settings.useMiles),
                        route.mainRoad.map { "via \($0)" },
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Arrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Fmt.arrival(after: route.duration))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
