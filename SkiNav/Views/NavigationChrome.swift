import FerrostarCore
import FerrostarCoreFFI
import FerrostarSwiftUI
import SwiftUI

/// TomTom AmiGO-style colors for the navigation screen.
enum NavColors {
    static let banner = Color(red: 0.19, green: 0.36, blue: 0.58)      // #305C94
    static let thenStrip = Color(red: 0.07, green: 0.20, blue: 0.37)   // #13335E
    static let tripBar = Color(red: 0.08, green: 0.11, blue: 0.15)     // #141C26
    static let exitButton = Color(red: 0.16, green: 0.21, blue: 0.27)
}

/// Full-width turn banner: big arrow, distance and street, with a "Then, in 250 ft ↰"
/// strip when the next turn comes right after.
struct TurnBanner: View {
    var state: NavigationState?
    var miles: Bool
    var lanes: [LaneInfo]?
    var junction: JunctionInfo?
    @Binding var size: CGSize

    var body: some View {
        let instruction = state?.currentVisualInstruction
        let distance = state?.currentProgress?.distanceToNextManeuver
        let next = nextManeuver

        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                if let type = instruction?.primaryContent.maneuverType {
                    ManeuverImage(maneuverType: type, maneuverModifier: instruction?.primaryContent.maneuverModifier)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let distance {
                        Text(Fmt.distance(distance, miles: miles))
                            .font(.system(size: 40, weight: .bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if let text = instruction?.primaryContent.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 22, weight: .semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    if let exits = instruction?.primaryContent.exitNumbers, !exits.isEmpty {
                        Text("Exit \(exits.joined(separator: ", "))")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.42, blue: 0.24), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(NavColors.banner)

            if let junction {
                JunctionView(info: junction, useMiles: miles)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(NavColors.thenStrip)
            } else if let lanes, !lanes.isEmpty {
                ViewThatFits(in: .horizontal) {
                    LaneGuidanceView(lanes: lanes, cell: 40)
                    LaneGuidanceView(lanes: lanes, cell: 30)
                    LaneGuidanceView(lanes: lanes, cell: 22)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(NavColors.thenStrip)
            } else if let next {
                HStack(spacing: 12) {
                    Text("Then, in \(Fmt.distance(next.distance, miles: miles))")
                        .font(.system(size: 19, weight: .semibold))
                    if let type = next.type {
                        ManeuverImage(maneuverType: type, maneuverModifier: next.modifier)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(NavColors.thenStrip)
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous))
        // Blue runs up under the status bar and out to both edges, like AmiGO.
        .background(alignment: .top) {
            NavColors.banner
                .frame(height: 400)
                .offset(y: -400)
        }
        .padding(.horizontal, -16)
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { size = geo.size }
                    .onChange(of: geo.size) { size = geo.size }
            }
        )
    }

    /// The turn after this one, if it comes soon (within half a mile).
    private var nextManeuver: (distance: Double, type: ManeuverType?, modifier: ManeuverModifier?)? {
        guard let steps = state?.remainingSteps, steps.count > 1 else { return nil }
        let following = steps[1]
        guard following.distance < 800, let v = following.visualInstructions.first else { return nil }
        // The next maneuver happens at the end of the step after the current one.
        return (following.distance, v.primaryContent.maneuverType, v.primaryContent.maneuverModifier)
    }
}

/// Bottom trip bar: 🏁 arrival time, then distance | time left | traffic, and the exit button.
struct TripBar: View {
    var state: NavigationState?
    var miles: Bool
    var traffic: TrafficInfo?
    var hasTraffic: Bool
    var onExit: (() -> Void)?

    var body: some View {
        if let progress = state?.currentProgress {
            let duration = traffic?.travelTime ?? progress.durationRemaining
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 22, weight: .semibold))
                        arrivalText(Date().addingTimeInterval(duration))
                    }
                    HStack(spacing: 10) {
                        Text(Fmt.distance(progress.distanceRemaining, miles: miles))
                        Divider().frame(height: 22).overlay(Color.white.opacity(0.4))
                        Text(clock(duration))
                        if hasTraffic {
                            Divider().frame(height: 22).overlay(Color.white.opacity(0.4))
                            Image(systemName: "car.2.fill")
                                .foregroundStyle(trafficColor)
                        }
                    }
                    .font(.system(size: 26, weight: .medium).monospacedDigit())
                }
                Spacer()
                if let onExit {
                    Button(action: onExit) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(NavColors.exitButton, in: Circle())
                    }
                    .accessibilityLabel("End route")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                    .fill(NavColors.tripBar)
                    .frame(height: 400) // reaches down under the home indicator
            }
            .padding(.horizontal, -16)
            .padding(.bottom, -16)
        }
    }

    private var trafficColor: Color {
        guard let traffic else { return .green }
        if traffic.isHeavy { return .red }
        if traffic.isNoticeable { return .orange }
        return .green
    }

    /// "6:25pm" with the am/pm smaller, like AmiGO.
    private func arrivalText(_ date: Date) -> some View {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        let p = DateFormatter()
        p.dateFormat = "a"
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(f.string(from: date)).font(.system(size: 40, weight: .bold).monospacedDigit())
            Text(p.string(from: date).lowercased()).font(.system(size: 28, weight: .semibold))
        }
    }

    /// "1:26 hr" / "24 min"
    private func clock(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return m >= 60 ? String(format: "%d:%02d hr", m / 60, m % 60) : "\(max(1, m)) min"
    }
}
