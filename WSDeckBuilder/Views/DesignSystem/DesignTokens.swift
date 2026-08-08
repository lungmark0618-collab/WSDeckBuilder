import SwiftUI

/// 全 App 共用的間距／圓角／陰影／按鈕層級，讓「舒適感」有一致的準則可循，
/// 不是每個畫面各自決定數字。
///
/// 跟 AppearanceSettings 分工：AppearanceSettings 管使用者可調的內容色
/// （文字色、背景、強調色），這裡管結構性的間距／圓角／陰影／按鈕樣式，
/// 兩者疊加使用——按鈕樣式一律讀 Color.accentColor，會自動跟著使用者選的
/// 強調色（不論是固定色還是跟著作品變色）。

// MARK: - 間距（8pt 網格）

enum Spacing {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
}

// MARK: - 圓角

enum Radius {
    /// 小徽章、色塊這類極小元件
    static let sharp: CGFloat = 4
    /// 卡片、按鈕、大多數容器的預設值——夠柔和又不會過度可愛
    static let mid: CGFloat = 14
    /// 短標籤、膠囊按鈕；長文字按鈕別用這個，兩端會擠出不自然的尖角
    static let pill: CGFloat = 999
}

// MARK: - 柔和陰影

/// 材質層次用的陰影，統一走這裡而不是每處各自指定顏色／模糊半徑，
/// 避免有的地方陰影死黑、有的地方又完全沒有層次。
enum ShadowLevel {
    /// 貼著背景的卡片、格子
    case card
    /// 浮起來的元件，如懸浮按鈕、彈出選單
    case floating

    fileprivate var color: Color {
        switch self {
        case .card: .black.opacity(0.14)
        case .floating: .black.opacity(0.22)
        }
    }
    fileprivate var radius: CGFloat { self == .card ? 7 : 14 }
    fileprivate var y: CGFloat { self == .card ? 3 : 6 }
}

extension View {
    func comfortShadow(_ level: ShadowLevel = .card) -> some View {
        shadow(color: level.color, radius: level.radius, x: 0, y: level.y)
    }
}

// MARK: - 按鈕層級

/// 實心：一個畫面只留給唯一的主要動作
struct FilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.mid, style: .continuous))
            .foregroundStyle(.white)
            .comfortShadow(.card)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 淡色：次要但仍重要的動作
struct TonalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: Radius.mid, style: .continuous))
            .foregroundStyle(Color.accentColor)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 外框：低風險或可逆的次要動作
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: Radius.mid, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1.3)
            }
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    static var filled: FilledButtonStyle { FilledButtonStyle() }
}
extension ButtonStyle where Self == TonalButtonStyle {
    static var tonal: TonalButtonStyle { TonalButtonStyle() }
}
extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}
