import SwiftUI

/// Apple-style map mode picker: Explore, Driving (traffic), Satellite, plus 3D options.
struct MapModesSheet: View {
    @Bindable var model: AppModel
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showKeySetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ForEach(MapMode.allCases) { mode in
                            modeCard(mode)
                        }
                    }

                    if !settings.hasTrafficKey {
                        Button { showKeySetup = true } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Turn on live traffic & satellite").font(.subheadline.weight(.semibold))
                                    Text("Needs a free TomTom key — takes about 2 minutes.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "car.rear.road.lane.dashed")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 0) {
                        Toggle("3D map when driving", isOn: Binding(
                            get: { settings.map3D },
                            set: { if $0 != settings.map3D { model.toggle3D() } }
                        ))
                        .padding(.vertical, 10)
                        Divider()
                        Toggle("3D buildings", isOn: $settings.buildings3D).padding(.vertical, 10)
                        Divider()
                        Toggle("Street detail (lanes, crosswalks)", isOn: $settings.streetDetail).padding(.vertical, 10)
                        if settings.hasTrafficKey {
                            Divider()
                            Toggle("Traffic while navigating", isOn: $settings.trafficWhileNavigating).padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    Text("© OpenStreetMap contributors · Protomaps\(settings.hasTrafficKey ? " · Traffic and imagery © TomTom" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Map Modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .sheet(isPresented: $showKeySetup) {
                NavigationStack { TrafficKeyView() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func modeCard(_ mode: MapMode) -> some View {
        let selected = settings.mapMode == mode
        let locked = mode != .explore && !settings.hasTrafficKey
        return Button {
            if locked { showKeySetup = true } else { settings.mapMode = mode }
        } label: {
            VStack(spacing: 8) {
                ModePreview(mode: mode)
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                    )
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .padding(5)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(5)
                        }
                    }
                Text(mode.label)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// Little drawn thumbnails like Apple's mode cards.
private struct ModePreview: View {
    var mode: MapMode

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bg: Color = mode == .satellite ? Color(red: 0.32, green: 0.38, blue: 0.27) : Color(red: 0.2, green: 0.24, blue: 0.29)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            if mode == .satellite {
                for i in 0 ..< 7 {
                    let r = CGRect(x: CGFloat(i * 23 % 90) / 90 * w, y: CGFloat(i * 37 % 80) / 80 * h, width: 22, height: 16)
                    ctx.fill(Path(r), with: .color(Color(white: 0.75, opacity: 0.55)))
                }
            } else {
                for i in 0 ..< 5 {
                    let r = CGRect(x: CGFloat(i) * w / 5 + 4, y: h * 0.12 + CGFloat(i % 2) * 18, width: 16, height: 12)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(Color(white: 0.45)))
                }
            }
            var road = Path()
            road.move(to: CGPoint(x: w * 0.1, y: h))
            road.addLine(to: CGPoint(x: w * 0.9, y: 0))
            ctx.stroke(road, with: .color(Color(white: mode == .satellite ? 0.85 : 0.5)), lineWidth: 12)
            if mode == .driving {
                var jam = Path()
                jam.move(to: CGPoint(x: w * 0.1, y: h))
                jam.addLine(to: CGPoint(x: w * 0.45, y: h * 0.56))
                ctx.stroke(jam, with: .color(.red), lineWidth: 6)
                var slow = Path()
                slow.move(to: CGPoint(x: w * 0.45, y: h * 0.56))
                slow.addLine(to: CGPoint(x: w * 0.9, y: 0))
                ctx.stroke(slow, with: .color(.orange), lineWidth: 6)
            } else {
                var dash = Path()
                dash.move(to: CGPoint(x: w * 0.1, y: h))
                dash.addLine(to: CGPoint(x: w * 0.9, y: 0))
                ctx.stroke(dash, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
            }
        }
    }
}

/// Step-by-step TomTom key setup with a check that the key works.
struct TrafficKeyView: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft = ""
    @State private var checking = false
    @State private var result: Bool?

    var body: some View {
        Form {
            Section {
                Label("Go to developer.tomtom.com and tap Register (free, no credit card).", systemImage: "1.circle.fill")
                Label("Open your Dashboard › API Keys and copy your key.", systemImage: "2.circle.fill")
                Label("Paste it below.", systemImage: "3.circle.fill")
                Button("Open developer.tomtom.com") { openURL(URL(string: "https://developer.tomtom.com/user/register")!) }
            } footer: {
                Text("The free plan covers far more than one person uses: live traffic tiles, incidents, traffic-aware arrival times and satellite imagery.")
            }

            Section("Your key") {
                TextField("TomTom API key", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                if let result {
                    Label(result ? "Key works — traffic is on." : "That key didn't work. Check it and try again.",
                          systemImage: result ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(result ? .green : .red)
                }
                Button {
                    checking = true
                    result = nil
                    let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        let ok = await TrafficService.validate(key: key)
                        checking = false
                        result = ok
                        if ok {
                            settings.tomtomKey = key
                            if settings.mapMode == .explore { settings.mapMode = .driving }
                        }
                    }
                } label: {
                    HStack {
                        Text("Save and Check")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            }

            if settings.hasTrafficKey {
                Section {
                    Button("Remove Key", role: .destructive) {
                        settings.tomtomKey = ""
                        settings.mapMode = .explore
                        draft = ""
                        result = nil
                    }
                }
            }
        }
        .navigationTitle("Live Traffic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear { draft = settings.tomtomKey }
    }
}
