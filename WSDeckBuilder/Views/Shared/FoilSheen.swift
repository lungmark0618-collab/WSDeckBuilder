import SwiftUI

/// 燙金／簽名卡的視覺效果：彩虹光澤 + 掃過的高光
/// animated=false 用於網格（省電），true 用於詳情頁大圖
struct FoilSheen: View {
    var animated = false
    @State private var phase: CGFloat = -0.8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 靜態彩虹偏光
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .cyan.opacity(0.20), location: 0.25),
                        .init(color: .purple.opacity(0.16), location: 0.5),
                        .init(color: .yellow.opacity(0.20), location: 0.75),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.screen)

                if animated {
                    // 緩慢掃過的高光帶
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.45), .clear],
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.45)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * geo.size.width * 1.8)
                    .blendMode(.screen)
                    .onAppear {
                        withAnimation(.linear(duration: 2.8)
                            .repeatForever(autoreverses: false)) {
                            phase = 0.9
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}