import FerrostarCoreFFI
import SwiftUI

/// What the junction view needs to know about the coming exit or fork.
struct JunctionInfo: Equatable {
    enum Side { case left, right, straight }

    var side: Side
    var lanes: [LaneInfo]
    var exitNumber: String?
    var signText: String
    var distance: Double // meters to the junction
    var isExit: Bool

    /// Highway exits, ramps and forks within about a mile get a junction view.
    static func from(_ instruction: VisualInstruction?, distance: Double?) -> JunctionInfo? {
        guard let instruction, let distance, distance > 15, distance < 1700 else { return nil }
        let primary = instruction.primaryContent
        let type = primary.maneuverType
        let exitNumber = primary.exitNumbers.first ?? instruction.subContent?.exitNumbers.first
        let highway = type == .offRamp || type == .fork || (type == .onRamp && exitNumber != nil) || exitNumber != nil
        guard highway else { return nil }

        let side: Side = switch primary.maneuverModifier {
        case .left, .slightLeft, .sharpLeft: .left
        case .right, .slightRight, .sharpRight: .right
        default: .straight
        }
        return JunctionInfo(
            side: side,
            lanes: instruction.subContent?.laneInfo ?? primary.laneInfo ?? [],
            exitNumber: exitNumber,
            signText: primary.text,
            distance: distance,
            isExit: type == .offRamp || exitNumber != nil
        )
    }
}

/// A drawn, perspective view of the junction ahead: the road, its lanes, the exit ramp,
/// the lanes to use highlighted with arrows, and an overhead sign.
struct JunctionView: View {
    var info: JunctionInfo
    var useMiles: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Canvas { ctx, size in draw(&ctx, size) }
            Text(Fmt.distance(info.distance, miles: useMiles))
                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(8)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityLabel("Junction ahead: \(info.exitNumber.map { "exit \($0), " } ?? "")\(info.signText)")
    }

    // MARK: Drawing

    private var night: Bool { scheme == .dark }

    /// Which lanes to use, counted from the left of the screen.
    private var laneCount: Int {
        max(2, min(6, info.lanes.isEmpty ? 3 : info.lanes.count))
    }

    private var activeLanes: Set<Int> {
        if !info.lanes.isEmpty, info.lanes.contains(where: \.active) {
            return Set(info.lanes.enumerated().filter(\.element.active).map(\.offset).filter { $0 < laneCount })
        }
        switch info.side {
        case .right: return [laneCount - 1]
        case .left: return [0]
        case .straight: return Set(0 ..< laneCount)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let horizon = h * 0.36
        let mirror = info.side == .left
        // Work in "right exit" space and mirror for left exits.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mirror ? w - x : x, y: y) }

        // Sky and ground.
        let sky = night
            ? Gradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.12), Color(red: 0.10, green: 0.14, blue: 0.27)])
            : Gradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.93), Color(red: 0.73, green: 0.86, blue: 0.98)])
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        let ground = night
            ? Gradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.08), Color(red: 0.03, green: 0.06, blue: 0.04)])
            : Gradient(colors: [Color(red: 0.55, green: 0.72, blue: 0.42), Color(red: 0.36, green: 0.55, blue: 0.29)])
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(ground, startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

        // Main road: wide at the bottom, narrowing toward the vanishing point.
        let n = CGFloat(laneCount)
        let hasRamp = info.side != .straight
        let center = hasRamp ? w * 0.44 : w * 0.5
        let bottomHalf = min(w * 0.40, 46 * n)
        let topHalf = bottomHalf * 0.07
        let bl = center - bottomHalf, br = center + bottomHalf
        let tl = w * 0.5 - topHalf + (center - w * 0.5) * 0.3, tr = tl + 2 * topHalf
        func x(_ f: CGFloat, _ y: CGFloat) -> CGFloat { // f = 0…1 across the road at height y
            let t = (h - y) / (h - horizon)
            let l = bl + (tl - bl) * t, r = br + (tr - br) * t
            return l + (r - l) * f
        }
        let asphalt = night ? Color(white: 0.17) : Color(white: 0.33)
        var road = Path()
        road.move(to: p(bl, h)); road.addLine(to: p(tl, horizon)); road.addLine(to: p(tr, horizon)); road.addLine(to: p(br, h))
        road.closeSubpath()
        ctx.fill(road, with: .color(asphalt))

        // Exit ramp splitting off to the side.
        let goreY = h * 0.60
        if hasRamp {
            var ramp = Path()
            ramp.move(to: p(br - (br - bl) / n * 0.2, h))
            ramp.addQuadCurve(to: p(w + 30, horizon + 26), control: p(br + w * 0.10, h * 0.62))
            ramp.addLine(to: p(w + 30, horizon + 10))
            ramp.addQuadCurve(to: p(x(1, goreY), goreY), control: p(x(1, goreY) + w * 0.12, horizon + 18))
            ramp.closeSubpath()
            ctx.fill(ramp, with: .color(asphalt))
            // Painted gore (the chevron triangle where the ramp splits).
            var gore = Path()
            gore.move(to: p(x(1, goreY), goreY))
            gore.addLine(to: p(x(1, h * 0.80) + 8, h * 0.80))
            gore.addLine(to: p(x(1, h * 0.80) + 30, h * 0.80))
            gore.closeSubpath()
            ctx.fill(gore, with: .color(.white.opacity(0.75)))
        }

        // Lanes to use, tinted.
        let tint = Color(red: 0.13, green: 0.55, blue: 1.0)
        for i in activeLanes {
            let li = CGFloat(mirror ? laneCount - 1 - i : i)
            var lane = Path()
            lane.move(to: p(x(li / n, h), h))
            lane.addLine(to: p(x(li / n, horizon + 4), horizon + 4))
            lane.addLine(to: p(x((li + 1) / n, horizon + 4), horizon + 4))
            lane.addLine(to: p(x((li + 1) / n, h), h))
            lane.closeSubpath()
            ctx.fill(lane, with: .color(tint.opacity(0.28)))
        }

        // Edge lines and dashed lane lines.
        var lines: [(CGFloat, Bool)] = [(0, false), (1, false)]
        for k in 1 ..< laneCount { lines.append((CGFloat(k) / n, true)) }
        for (f, dashed) in lines {
            var line = Path()
            line.move(to: p(x(f, h), h))
            line.addLine(to: p(x(f, horizon + 2), horizon + 2))
            let style = StrokeStyle(lineWidth: dashed ? 2.5 : 3.5, lineCap: .butt,
                                    dash: dashed ? [22, 18] : [])
            ctx.stroke(line, with: .color(dashed ? .white.opacity(0.85) : (f == 0 ? .yellow : .white)), style: style)
        }

        // Arrows on the lanes to use, curving into the ramp for exit lanes.
        for i in activeLanes {
            let li = CGFloat(mirror ? laneCount - 1 - i : i)
            let start = CGPoint(x: x((li + 0.5) / n, h - 8), y: h - 8)
            let mid = CGPoint(x: x((li + 0.5) / n, h * 0.68), y: h * 0.68)
            var arrow = Path()
            let end: CGPoint
            if hasRamp {
                end = CGPoint(x: x(1, goreY) + w * 0.13, y: horizon + 30)
                arrow.move(to: p(start.x, start.y))
                arrow.addLine(to: p(mid.x, mid.y))
                arrow.addQuadCurve(to: p(end.x, end.y), control: p(mid.x + 4, goreY - 10))
            } else {
                end = CGPoint(x: x((li + 0.5) / n, horizon + 26), y: horizon + 26)
                arrow.move(to: p(start.x, start.y))
                arrow.addLine(to: p(end.x, end.y))
            }
            ctx.stroke(arrow, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 17, lineCap: .round, lineJoin: .round))
            ctx.stroke(arrow, with: .color(tint), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            // Arrowhead pointing along the last bit of the path.
            let before = arrow.trimmedPath(from: 0.9, to: 0.92).boundingRect.center
            let tip = p(end.x, end.y)
            let angle = atan2(tip.y - before.y, tip.x - before.x)
            var head = Path()
            head.move(to: CGPoint(x: tip.x + cos(angle) * 14, y: tip.y + sin(angle) * 14))
            head.addLine(to: CGPoint(x: tip.x + cos(angle + 2.4) * 16, y: tip.y + sin(angle + 2.4) * 16))
            head.addLine(to: CGPoint(x: tip.x + cos(angle - 2.4) * 16, y: tip.y + sin(angle - 2.4) * 16))
            head.closeSubpath()
            ctx.fill(head, with: .color(tint))
        }

        drawSign(&ctx, w: w, horizon: horizon, mirror: mirror, hasRamp: hasRamp)
    }

    /// Green overhead highway sign on a gantry.
    private func drawSign(_ ctx: inout GraphicsContext, w: CGFloat, horizon: CGFloat, mirror: Bool, hasRamp: Bool) {
        let signW = min(w * 0.56, 260), signH: CGFloat = 58
        var signX = hasRamp ? w * 0.70 - signW / 2 : w * 0.5 - signW / 2
        if mirror && hasRamp { signX = w - signX - signW }
        let signY: CGFloat = 12
        let green = Color(red: 0.0, green: 0.42, blue: 0.24)

        // Gantry posts and beam.
        let postColor = Color(white: night ? 0.45 : 0.62)
        ctx.fill(Path(CGRect(x: 10, y: signY + 20, width: w - 20, height: 5)), with: .color(postColor))
        ctx.fill(Path(CGRect(x: 10, y: signY + 20, width: 5, height: horizon - signY + 6)), with: .color(postColor))
        ctx.fill(Path(CGRect(x: w - 15, y: signY + 20, width: 5, height: horizon - signY + 6)), with: .color(postColor))

        let rect = CGRect(x: signX, y: signY, width: signW, height: signH)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(green))
        ctx.stroke(Path(roundedRect: rect.insetBy(dx: 2.5, dy: 2.5), cornerRadius: 5),
                   with: .color(.white), lineWidth: 1.5)

        // Exit number tab.
        if let exit = info.exitNumber {
            let tab = CGRect(x: mirror ? rect.minX + 6 : rect.maxX - 70, y: rect.minY - 14, width: 64, height: 18)
            ctx.fill(Path(roundedRect: tab, cornerRadius: 4), with: .color(green))
            ctx.stroke(Path(roundedRect: tab.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 3), with: .color(.white), lineWidth: 1)
            ctx.draw(Text("EXIT \(exit)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white),
                     at: CGPoint(x: tab.midX, y: tab.midY))
        }

        let arrowSymbol = switch info.side {
        case .right: "arrow.up.right"
        case .left: "arrow.up.left"
        case .straight: "arrow.up"
        }
        ctx.draw(Text(Image(systemName: arrowSymbol)).font(.system(size: 18, weight: .black)).foregroundStyle(.white),
                 at: CGPoint(x: mirror ? rect.maxX - 18 : rect.minX + 18, y: rect.midY))
        let text = Text(info.signText)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
        ctx.draw(text, in: rect.insetBy(dx: 34, dy: 8))
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
