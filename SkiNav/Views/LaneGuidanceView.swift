import FerrostarCoreFFI
import SwiftUI

/// Lane arrows under the turn banner. The lanes you should be in are bright.
struct LaneGuidanceView: View {
    var lanes: [LaneInfo]
    var cell: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(lanes.enumerated()), id: \.offset) { index, lane in
                if index > 0 {
                    LaneDivider()
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 2, height: cell * 0.85)
                }
                LaneCell(lane: lane, size: cell)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let good = lanes.enumerated().filter(\.element.active).map { "\($0.offset + 1)" }
        return good.isEmpty ? "Lane guidance" : "Use lane \(good.joined(separator: " or ")) of \(lanes.count)"
    }

    static func symbol(for direction: String) -> String {
        switch direction.lowercased() {
        case "left": "arrow.turn.up.left"
        case "slight left": "arrow.up.left"
        case "sharp left": "arrow.turn.left.down"
        case "right": "arrow.turn.up.right"
        case "slight right": "arrow.up.right"
        case "sharp right": "arrow.turn.right.down"
        case "uturn": "arrow.uturn.down"
        default: "arrow.up"
        }
    }
}

private struct LaneDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

private struct LaneCell: View {
    var lane: LaneInfo
    var size: CGFloat = 40

    var body: some View {
        let directions = lane.directions.isEmpty ? ["straight"] : lane.directions
        let main = lane.active ? (lane.activeDirection ?? directions[0]) : directions[0]
        ZStack {
            if lane.active {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.35))
            }
            if !lane.active && directions.count > 1 {
                // A lane allowing several moves, e.g. straight + right.
                ZStack {
                    ForEach(directions.prefix(3), id: \.self) { d in
                        Image(systemName: LaneGuidanceView.symbol(for: d))
                    }
                }
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
            } else {
                Image(systemName: LaneGuidanceView.symbol(for: main))
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundStyle(lane.active ? Color.white : Color.white.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
    }
}
