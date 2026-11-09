import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @State private var showSearch = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            MapScreen(model: model, annotation: model.annotation)

            if model.screen != .navigating {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomPanel
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: model.screen)
        .sheet(isPresented: $showSearch) {
            SearchSheet(model: model, onPick: { place in
                showSearch = false
                model.select(place)
            }, onCategory: { category in
                showSearch = false
                model.showNearby(category)
            })
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .sheet(isPresented: $model.showTripPlanner) {
            TripPlannerSheet(model: model)
        }
        .sheet(isPresented: $model.showAlongRoute) {
            AlongRouteSheet(model: model)
        }
        .sheet(isPresented: $model.showDownloads) {
            NavigationStack { DownloadsView(model: model) }
        }
        .onAppear { model.start() }
        .onChange(of: model.regions.revision) { model.refreshRouting() }
        .onChange(of: model.settings.routingKey) { model.refreshRouting() }
        .onChange(of: model.settings.activeRegionID) { model.refreshRouting() }
        .onChange(of: model.settings.useOnlineWhenAvailable) { model.refreshRouting() }
        .onChange(of: model.regions.alertsRevision) { model.refreshRouting() }
        .onChange(of: model.regions.detailRevision) { model.refreshRouting() }
        .onChange(of: model.settings.speedCameraAlerts) { model.updateRouteAlerts() }
        .onChange(of: model.settings.railroadAlerts) { model.updateRouteAlerts() }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .top) {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .onTapGesture { model.errorMessage = nil }
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        if model.errorMessage == message { model.errorMessage = nil }
                    }
            }
            Spacer()
            VStack(spacing: 0) {
                MapButton(systemImage: "gearshape.fill") { showSettings = true }
                Divider().frame(width: 44)
                Button { model.toggle3D() } label: {
                    Text(model.settings.map3D ? "2D" : "3D")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .tint(.primary)
                Divider().frame(width: 44)
                MapButton(systemImage: "location.fill") { model.recenter() }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Bottom

    @ViewBuilder
    private var bottomPanel: some View {
        Group {
            switch model.screen {
            case .browse, .navigating:
                BrowsePanel(model: model, openSearch: { showSearch = true })
            case .place:
                if let place = model.selectedPlace {
                    PlaceCard(model: model, place: place)
                }
            case .routes:
                RoutesPanel(model: model)
            case .poi:
                POIPanel(model: model)
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct MapButton: View {
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .tint(.primary)
    }
}
