import SwiftUI

/// 3D 傾斜視差：卡片隨裝置傾斜立體轉動，並帶動陰影與邊緣反光。
/// 與燙金光澤共用同一個陀螺儀來源，兩者會同步。
struct CardTilt: ViewModifier {
    /// 最大傾角（度）
    var maxAngle: Double = 9

    @State private var motion = MotionManager.shared

    func body(content: Content) -> some View {
        let roll = motion.isAvailable ? motion.roll : 0
        let pitch = motion.isAvailable ? motion.pitch : 0

        content
            // 邊緣反光：亮面順著傾斜方向跑，強化「有厚度」的感覺
            .overlay {
                LinearGradient(
                    colors: [.white.opacity(0.22), .clear, .black.opacity(0.14)],
                    startPoint: UnitPoint(x: 0.5 - roll * 0.5, y: 0.5 - pitch * 0.5),
                    endPoint: UnitPoint(x: 0.5 + roll * 0.5, y: 0.5 + pitch * 0.5))
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(-pitch * maxAngle),
                              axis: (x: 1, y: 0, z: 0),
                              perspective: 0.55)
            .rotation3DEffect(.degrees(roll * maxAngle),
                              axis: (x: 0, y: 1, z: 0),
                              perspective: 0.55)
            // 陰影往傾斜的反方向移動，像卡片被光源照著
            .shadow(color: .black.opacity(0.28),
                    radius: 12,
                    x: -roll * 12,
                    y: 8 + pitch * 10)
            .animation(.easeOut(duration: 0.12), value: roll)
            .animation(.easeOut(duration: 0.12), value: pitch)
            .onAppear { motion.subscribe() }
            .onDisappear { motion.unsubscribe() }
    }
}

extension View {
    /// 詳情頁大圖用：隨裝置傾斜的 3D 視差
    func cardTilt(maxAngle: Double = 9) -> some View {
        modifier(CardTilt(maxAngle: maxAngle))
    }
}
