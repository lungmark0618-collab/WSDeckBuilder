import SwiftUI

/// 燙金／簽名卡的視覺效果，依稀有度使用不同箔紋（對照實卡加工）：
///   softHolo/glossHolo 淡・光澤 holo（R／RR／CX）
///   linear   細密斜紋（SR）、grainy 顆粒箔（RRR）
///   vertical 直向稜鏡條紋（SP 簽名卡）
///   faceted  三角碎冰紋（SSP/SEC）
///   radial   放射狀光芒（各作品特殊稀有度）
///
/// interactive=true（詳情頁）時接陀螺儀，傾斜手機就會變色；
/// false（網格）時用固定角度的靜態版本，不耗電。
struct FoilSheen: View {
    var style: FoilStyle = .linear
    var interactive = false

    @State private var motion = MotionManager.shared
    @State private var idlePhase: CGFloat = 0

    /// −1…1 的光源位移；沒有陀螺儀時退回緩慢自動擺盪
    private var shift: CGSize {
        guard interactive else { return CGSize(width: -0.25, height: 0.15) }
        if motion.isAvailable {
            return CGSize(width: motion.roll, height: motion.pitch)
        }
        return CGSize(width: sin(idlePhase), height: cos(idlePhase) * 0.6)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                pattern(size: size)
                rainbow(size: size)
                specular(size: size)
                if style.hasGoldSignature { goldSignature(size: size) }
            }
            .compositingGroup()
            .opacity(style.intensity)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard interactive else { return }
            motion.subscribe()
            if !motion.isAvailable {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: true)) {
                    idlePhase = .pi
                }
            }
        }
        .onDisappear { if interactive { motion.unsubscribe() } }
    }

    // MARK: - 1. 箔紋（依稀有度）

    @ViewBuilder
    private func pattern(size: CGSize) -> some View {
        switch style {
        case .none:
            EmptyView()
        case .faceted:
            facetPattern.blendMode(.softLight)
        case .vertical:
            verticalPattern.blendMode(.softLight)
        case .radial:
            radialPattern.blendMode(.softLight)
        case .grainy:
            grainyPattern.blendMode(.softLight)
        case .linear:
            linearPattern.blendMode(.softLight)
        case .glossHolo:
            glossPattern.blendMode(.softLight)
        case .confetti:
            confettiPattern.blendMode(.plusLighter)
        }
    }

    /// 三角碎冰紋（SSP）
    private var facetPattern: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 20260729)
            let step = max(size.width / 7, 18)
            var row = -step
            var rowIndex = 0
            while row < size.height + step {
                var column = -step
                while column < size.width + step {
                    let origin = CGPoint(
                        x: column + CGFloat(rng.next()) * step * 0.5,
                        y: row + CGFloat(rng.next()) * step * 0.5
                            + (rowIndex % 2 == 0 ? 0 : step / 2))
                    for triangle in 0..<2 {
                        var path = Path()
                        if triangle == 0 {
                            path.move(to: origin)
                            path.addLine(to: CGPoint(x: origin.x + step, y: origin.y))
                            path.addLine(to: CGPoint(x: origin.x, y: origin.y + step))
                        } else {
                            path.move(to: CGPoint(x: origin.x + step, y: origin.y))
                            path.addLine(to: CGPoint(x: origin.x + step, y: origin.y + step))
                            path.addLine(to: CGPoint(x: origin.x, y: origin.y + step))
                        }
                        path.closeSubpath()
                        context.fill(path,
                                     with: .color(.white.opacity(0.03 + CGFloat(rng.next()) * 0.09)))
                    }
                    column += step
                }
                row += step
                rowIndex += 1
            }
        }
    }

    /// 直向稜鏡條紋（SP 簽名卡）
    private var verticalPattern: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 4242)
            var x: CGFloat = 0
            while x < size.width {
                let width = 3 + CGFloat(rng.next()) * 9
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(rect),
                             with: .color(.white.opacity(0.02 + CGFloat(rng.next()) * 0.10)))
                x += width
            }
        }
    }

    /// 放射狀光芒（特殊稀有度）
    private var radialPattern: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 777)
            let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let radius = max(size.width, size.height) * 1.3
            let rayCount = 44
            for index in 0..<rayCount {
                let start = Double(index) / Double(rayCount) * 2 * .pi
                let sweep = (0.6 + rng.next() * 1.2) * .pi / Double(rayCount)
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius,
                            startAngle: .radians(start),
                            endAngle: .radians(start + sweep), clockwise: false)
                path.closeSubpath()
                context.fill(path,
                             with: .color(.white.opacity(0.02 + CGFloat(rng.next()) * 0.07)))
            }
        }
    }

    /// 彩色亮片散點（R 卡：整面散布大小不一的圓點，各自反射不同顏色）
    private var confettiPattern: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 31337)
            let hues: [Color] = [
                Color(red: 0.45, green: 1.00, blue: 0.60),   // 綠
                Color(red: 0.40, green: 0.90, blue: 1.00),   // 青
                Color(red: 1.00, green: 0.55, blue: 0.85),   // 粉
                Color(red: 1.00, green: 0.95, blue: 0.50),   // 黃
                Color(red: 0.85, green: 0.80, blue: 1.00),   // 紫
                Color(red: 1.00, green: 1.00, blue: 1.00),   // 銀白
            ]
            let count = Int(size.width * size.height / 260)
            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let diameter = 1.6 + CGFloat(rng.next()) * 3.4
                let color = hues[Int(rng.next() * Double(hues.count)) % hues.count]
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y,
                                           width: diameter,
                                           height: diameter * (0.7 + CGFloat(rng.next()) * 0.6))),
                    with: .color(color.opacity(0.28 + CGFloat(rng.next()) * 0.40)))
            }
        }
    }

    /// 顆粒感特殊箔（RRR 的ザラつき加工）
    private var grainyPattern: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 9091)
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let point = CGPoint(x: CGFloat(rng.next()) * size.width,
                                    y: CGFloat(rng.next()) * size.height)
                let radius = 0.6 + CGFloat(rng.next()) * 1.4
                let rect = CGRect(x: point.x, y: point.y,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(.white.opacity(0.05 + CGFloat(rng.next()) * 0.16)))
            }
        }
    }

    /// 光澤 holo（RR／CX）：柔和的大面積光暈，不做細紋
    private var glossPattern: some View {
        RadialGradient(
            colors: [.white.opacity(0.10), .white.opacity(0.03), .clear],
            center: .init(x: 0.35, y: 0.30),
            startRadius: 0, endRadius: 320)
    }

    /// 細密斜紋（SR 等一般箔押）
    private var linearPattern: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 1357)
            let spacing: CGFloat = 5
            var offset = -size.height
            while offset < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height * 0.4, y: size.height))
                context.stroke(path,
                               with: .color(.white.opacity(0.03 + CGFloat(rng.next()) * 0.06)),
                               lineWidth: 1.5)
                offset += spacing
            }
        }
    }

    // MARK: - 2. 彩虹光帶（隨傾斜移動）

    private func rainbow(size: CGSize) -> some View {
        let offset = shift
        // 直紋卡的彩虹也走直向，與箔紋一致
        let vertical = style == .vertical
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: Color(red: 0.20, green: 0.95, blue: 0.90).opacity(0.30), location: 0.14),
                .init(color: .clear, location: 0.24),
                .init(color: Color(red: 0.55, green: 1.00, blue: 0.40).opacity(0.30), location: 0.34),
                .init(color: Color(red: 1.00, green: 0.95, blue: 0.25).opacity(0.30), location: 0.46),
                .init(color: Color(red: 1.00, green: 0.50, blue: 0.30).opacity(0.30), location: 0.57),
                .init(color: .clear, location: 0.64),
                .init(color: Color(red: 1.00, green: 0.35, blue: 0.75).opacity(0.30), location: 0.74),
                .init(color: Color(red: 0.50, green: 0.40, blue: 1.00).opacity(0.30), location: 0.86),
                .init(color: .clear, location: 1.00),
            ],
            startPoint: vertical
                ? UnitPoint(x: -0.4 + offset.width * 0.75, y: 0.5)
                : UnitPoint(x: -0.4 + offset.width * 0.55, y: -0.1 + offset.height * 0.35),
            endPoint: vertical
                ? UnitPoint(x: 1.4 + offset.width * 0.75, y: 0.5)
                : UnitPoint(x: 1.4 + offset.width * 0.55, y: 1.1 + offset.height * 0.35))
        .blendMode(.overlay)
        .opacity(0.55)
        .animation(.easeOut(duration: 0.12), value: offset)
    }

    // MARK: - 3. 鏡面高光

    private func specular(size: CGSize) -> some View {
        let offset = shift
        return LinearGradient(
            colors: [.clear, .white.opacity(0.22), .clear],
            startPoint: .top, endPoint: .bottom)
        .frame(width: size.width * 2.2, height: size.height * 0.22)
        .rotationEffect(.degrees(style == .vertical ? -78 : -24))
        .offset(x: offset.width * size.width * 0.35,
                y: offset.height * size.height * 0.55)
        .frame(width: size.width, height: size.height)
        .clipped()
        .blendMode(.screen)
        .animation(.easeOut(duration: 0.12), value: offset)
    }

    // MARK: - 4. 金色簽名箔（簽名卡專有的暖金光澤）

    private func goldSignature(size: CGSize) -> some View {
        let offset = shift
        return RadialGradient(
            colors: [Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.30),
                     Color(red: 1.0, green: 0.65, blue: 0.15).opacity(0.14),
                     .clear],
            center: UnitPoint(x: 0.5 + offset.width * 0.28,
                              y: 0.55 + offset.height * 0.18),
            startRadius: 0,
            endRadius: max(size.width, size.height) * 0.55)
        .blendMode(.screen)
        .animation(.easeOut(duration: 0.12), value: offset)
    }
}

/// 固定種子的亂數，讓箔紋每次繪製都一樣（不會閃爍）
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0…1
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 10_000) / 10_000
    }
}
