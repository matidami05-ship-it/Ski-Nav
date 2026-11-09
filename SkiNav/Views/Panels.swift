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
                    if let car = model.library.parkedCar {
                        ShortcutChip(title: "Parked Car", subtitle: eta(car.place), systemImage: "car.fill", tint: .teal) {
                            model.select(car.place)
                        }
                    } else {
                        ShortcutChip(title: "Park Here", subtitle: "Save spot", systemImage: "parkingsign", tint: .teal) {
                            model.saveParking()
                        }
                    }
                    ShortcutChip(title: "Home", subtitle: model.library.home == nil ? "Add" : eta(model.library.home),
                                 systemImage: "house.fill", tint: .blue) {
                        if let home = model.library.home { model.drive(to: home) } else { openSearch() }
                    }
                    ShortcutChip(title: "Work", subtitle: model.library.work == nil ? "Add" : eta(model.library.work),
                                 systemImage: "briefcase.fill", tint: .brown) {
                        if let work = model.library.work { model.drive(to: work) } else { openSearch() }
                    }
                    ShortcutChip(title: "Plan Trip", subtitle: "Multiple stops", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill", tint: .indigo) {
                        model.showTripPlanner = true
                    }
                    ForEach(model.library.saved.prefix(6)) { place in
                        ShortcutChip(title: place.name, subtitle: eta(place), systemImage: "star.fill", tint: .orange) {
                            model.select(place)
                        }
                    }
                }
            }

            CategoryRow(model: model)

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
                    .background((place.id == "parked-car" ? Color.teal : Color.red).gradient, in: Circle())
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

            if place.id == "parked-car", let note = model.library.parkedCar?.note {
                Label(note, systemImage: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.settings.streetView {
                LookAroundSection(coordinate: place.coordinate)
            }

            if place.id == "parked-car" {
                parkedButtons
            } else {
                placeButtons
            }
        }
        .alert("Parking note", isPresented: $editingNote) {
            TextField("Level 3, row B", text: $noteText)
            Button("Save") { model.library.updateParkedNote(noteText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A reminder of where you parked.")
        }
    }

    @State private var editingNote = false
    @State private var noteText = ""

    private var parkedButtons: some View {
        HStack(spacing: 10) {
            Button {
                model.walkToCar()
            } label: {
                Label("Walk Here", systemImage: "figure.walk")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(.teal)

            Button {
                noteText = model.library.parkedCar?.note ?? ""
                editingNote = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.headline)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))

            Button(role: .destructive) {
                model.library.clearParkedCar()
                model.closePlace()
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
    }

    private var placeButtons: some View {
            HStack(spacing: 10) {
                Button {
                    model.drive(to: place)
                } label: {
                    Label(model.isWalking ? "Walk" : "Directions",
                          systemImage: model.isWalking ? "figure.walk" : "arrow.triangle.turn.up.right.diamond.fill")
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
                    Button("Add to Trip", systemImage: "plus.circle") {
                        model.addStop(place)
                        model.showTripPlanner = true
                    }
                    Button("Save as Parking Spot", systemImage: "parkingsign") {
                        model.saveParking(at: place.coordinate)
                        model.select(model.library.parkedCar?.place ?? place)
                    }
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
    @State private var showTimePlan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.stops.count > 1
                        ? "Trip · \(model.stops.count) stops"
                        : "To \(model.selectedPlace?.name ?? "destination")")
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
                Button { model.showTripPlanner = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add or edit stops")
                CloseButton {
                    if model.stops.count > 1 { model.closePlace() }
                    else if let place = model.selectedPlace { model.select(place) } else { model.closePlace() }
                }
            }

            if model.stops.count > 1 {
                stopsSummary
            }

            Picker("Travel mode", selection: Binding(
                get: { settings.travelMode },
                set: { model.setTravelMode($0) }
            )) {
                ForEach(TravelMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if showOptions {
                VStack(spacing: 4) {
                    if settings.travelMode == .driving {
                        Toggle("Avoid tolls", isOn: $settings.avoidTolls)
                        Toggle("Avoid highways", isOn: $settings.avoidHighways)
                    }
                    Toggle("Avoid ferries", isOn: $settings.avoidFerries)
                }
                .font(.subheadline)
                .onChange(of: model.settings.routingKey) {
                    // Options changed: the engine is rebuilt (RootView), then routes recalculate.
                    if !model.stops.isEmpty {
                        Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            await model.planRoute()
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

                HStack(spacing: 10) {
                    Button {
                        showTimePlan = true
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: LeaveReminders.shared.pending == nil ? "clock" : "bell.badge.fill")
                                .font(.headline)
                            Text("Leave").font(.caption2.weight(.semibold))
                        }
                        .frame(width: 60, height: 52)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .disabled(model.selectedRoute == nil)
                    .accessibilityLabel("Plan when to leave")

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
                .sheet(isPresented: $showTimePlan) {
                    TimePlanSheet(model: model)
                }
            }
        }
    }

    private func trafficColor(_ info: TrafficInfo?) -> Color? {
        guard let info else { return nil }
        if info.isHeavy { return .red }
        if info.isNoticeable { return .orange }
        return nil
    }

    /// "1 Kwik Trip 2:14 PM → 2 Home 2:40 PM", scrollable.
    private var stopsSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.stops.enumerated()), id: \.offset) { index, stop in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 5) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(index == model.stops.count - 1 ? Color.red : Color.indigo, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stop.name).font(.caption.weight(.semibold)).lineLimit(1)
                            if model.stopETAs.indices.contains(index) {
                                Text(Fmt.arrival(after: model.stopETAs[index]))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onTapGesture { model.showTripPlanner = true }
                }
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Fmt.duration(model.routeTraffic[index]?.travelTime ?? route.duration))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(trafficColor(model.routeTraffic[index]) ?? (selected ? Color.accentColor : .primary))
                        if let traffic = model.routeTraffic[index] {
                            Text(traffic.isNoticeable ? "+\(Fmt.duration(traffic.delay)) traffic" : "light traffic")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(trafficColor(traffic) ?? .green)
                        }
                    }
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
                    Text(Fmt.arrival(after: model.routeTraffic[index]?.travelTime ?? route.duration))
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

// MARK: Points of interest

/// Quick category buttons: Gas, Food, Coffee… plus More.
struct CategoryRow: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(POICategory.quick) { category in
                categoryButton(category)
            }
            Menu {
                ForEach(POICategory.allCases.filter { !POICategory.quick.contains($0) }) { category in
                    Button(category.label, systemImage: category.symbol) { model.showNearby(category) }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: Circle())
                    Text("More").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .tint(.primary)
        }
    }

    private func categoryButton(_ category: POICategory) -> some View {
        Button { model.showNearby(category) } label: {
            VStack(spacing: 4) {
                Image(systemName: category.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(category.color.gradient, in: Circle())
                Text(category == .ev ? "EV" : category.label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct POIPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let category = model.poiCategory {
                    Label(category.label + " Nearby", systemImage: category.symbol)
                        .font(.headline)
                        .foregroundStyle(category.color)
                }
                Spacer()
                CloseButton { model.closePOI() }
            }
            if model.isLoadingPOI {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else if model.poiResults.isEmpty {
                Text(model.search.hasOfflineDatabase
                    ? "Nothing found nearby."
                    : "Nothing found. Download a map for offline results.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.poiResults) { result in
                            POIRow(result: result, miles: model.settings.useMiles) {
                                model.select(result.place)
                            }
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }
}

struct POIRow: View {
    var result: POIResult
    var miles: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: result.place.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.place.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if !result.place.subtitle.isEmpty {
                        Text(result.place.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.offRoute == nil ? Fmt.distance(result.distance, miles: miles)
                        : "in " + Fmt.distance(result.distance, miles: miles))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    if let off = result.offRoute {
                        Text(off < 60 ? "on route" : Fmt.distance(off, miles: miles) + " off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
