import SwiftUI

/// 燙金／簽名卡的視覺效果，模擬實卡的稜鏡箔：
/// 1) 持續存在的碎面稜鏡紋理（不是掃過就沒了）
/// 2) 大面積彩虹光帶，隨傾斜移動
/// 3) 沿角度移動的鏡面高光
///
/// interactive=true（詳情頁）時接陀螺儀，傾斜手機就會變色；
/// false（網格）時用固定角度的靜態版本，不耗電。
struct FoilSheen: View {
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
                facets(size: size)
                rainbow(size: size)
                specular(size: size)
            }
            .compositingGroup()
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

    // MARK: - 1. 碎面稜鏡紋理（實卡背景那層三角切面）

    private func facets(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            var generator = SeededRandom(seed: 20260729)
            let step = max(canvasSize.width / 7, 18)
            var row = -step
            var rowIndex = 0
            while row < canvasSize.height + step {
                var column = -step
                while column < canvasSize.width + step {
                    // 每格切成兩個三角，亮度隨機但穩定
                    let jitterX = CGFloat(generator.next()) * step * 0.5
                    let jitterY = CGFloat(generator.next()) * step * 0.5
                    let origin = CGPoint(x: column + jitterX,
                                         y: row + jitterY + (rowIndex % 2 == 0 ? 0 : step / 2))
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
                        let brightness = 0.03 + CGFloat(generator.next()) * 0.09
                        context.fill(path, with: .color(.white.opacity(brightness)))
                    }
                    column += step
                }
                row += step
                rowIndex += 1
            }
        }
        .blendMode(.softLight)
    }

    // MARK: - 2. 彩虹光帶（大面積、隨傾斜移動）

    private func rainbow(size: CGSize) -> some View {
        let offset = shift
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
            startPoint: UnitPoint(x: -0.4 + offset.width * 0.55,
                                  y: -0.1 + offset.height * 0.35),
            endPoint: UnitPoint(x: 1.4 + offset.width * 0.55,
                                y: 1.1 + offset.height * 0.35))
        .blendMode(.overlay)
        .opacity(0.55)
        .animation(.easeOut(duration: 0.12), value: offset)
    }

    // MARK: - 3. 鏡面高光（順著傾斜跑的亮帶）

    private func specular(size: CGSize) -> some View {
        let offset = shift
        return LinearGradient(
            colors: [.clear, .white.opacity(0.22), .clear],
            startPoint: .top, endPoint: .bottom)
        .frame(width: size.width * 2.2, height: size.height * 0.22)
        .rotationEffect(.degrees(-24))
        .offset(x: offset.width * size.width * 0.35,
                y: offset.height * size.height * 0.55)
        .frame(width: size.width, height: size.height)
        .clipped()
        .blendMode(.screen)
        .animation(.easeOut(duration: 0.12), value: offset)
    }
}

/// 固定種子的亂數，讓碎面紋理每次繪製都一樣（不會閃爍）
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// 0…1
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 10_000) / 10_000
    }
}
