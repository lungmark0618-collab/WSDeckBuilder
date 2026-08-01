import Observation
import SwiftUI

/// 外觀個人化設定：字體大小／粗細／文字色／背景色／強調色
@Observable
final class AppearanceSettings {
    static let shared = AppearanceSettings()

    // MARK: - 字體

    /// 字級（對應系統 Dynamic Type，會等比放大所有文字）
    var textSize: TextSize {
        didSet { store(textSize.rawValue, "ap.textSize") }
    }

    /// 字重
    var textWeight: TextWeight {
        didSet { store(textWeight.rawValue, "ap.textWeight") }
    }

    // MARK: - 顏色

    var textTone: TextTone {
        didSet { store(textTone.rawValue, "ap.textTone") }
    }

    var background: BackgroundStyle {
        didSet { store(background.rawValue, "ap.background") }
    }

    /// 強調色來源：跟著作品，或固定一色
    var accentMode: AccentMode {
        didSet { store(accentMode.rawValue, "ap.accentMode") }
    }

    /// accentMode == .fixed 時使用
    var fixedAccent: AccentPreset {
        didSet { store(fixedAccent.rawValue, "ap.fixedAccent") }
    }

    // MARK: - 語言

    /// 卡片詳情是否同時顯示日文原文；關閉時只留繁中
    var showJapanese: Bool {
        didSet { UserDefaults.standard.set(showJapanese, forKey: "ap.showJapanese") }
    }

    /// 目前瀏覽的作品（由圖鑑設定，供 .followTitle 使用）
    var currentTitleCode: String = ""

    private init() {
        let defaults = UserDefaults.standard
        // 預設只顯示中文；沒存過的話 bool(forKey:) 回 false，正好是我們要的預設值
        showJapanese = defaults.bool(forKey: "ap.showJapanese")
        textSize = TextSize(rawValue: defaults.string(forKey: "ap.textSize") ?? "") ?? .standard
        textWeight = TextWeight(rawValue: defaults.string(forKey: "ap.textWeight") ?? "") ?? .regular
        textTone = TextTone(rawValue: defaults.string(forKey: "ap.textTone") ?? "") ?? .standard
        background = BackgroundStyle(rawValue: defaults.string(forKey: "ap.background") ?? "") ?? .system
        accentMode = AccentMode(rawValue: defaults.string(forKey: "ap.accentMode") ?? "") ?? .followTitle
        fixedAccent = AccentPreset(rawValue: defaults.string(forKey: "ap.fixedAccent") ?? "") ?? .rose
    }

    private func store(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - 求值

    var accentColor: Color {
        switch accentMode {
        case .fixed: fixedAccent.color
        case .followTitle: TitlePalette.accent(for: currentTitleCode)
        }
    }

    var backgroundColor: Color? { background.color }
    var colorScheme: ColorScheme? { background.colorScheme }
    var textColor: Color? { textTone.color }
    var dynamicTypeSize: DynamicTypeSize { textSize.dynamicType }
    var fontWeight: Font.Weight? { textWeight.weight }
}

// MARK: - 選項

enum TextSize: String, CaseIterable, Identifiable {
    case compact, small, standard, large, huge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: "最小"
        case .small: "小"
        case .standard: "標準"
        case .large: "大"
        case .huge: "最大"
        }
    }
    var dynamicType: DynamicTypeSize {
        switch self {
        case .compact: .xSmall
        case .small: .small
        case .standard: .large
        case .large: .xLarge
        case .huge: .xxxLarge
        }
    }
}

enum TextWeight: String, CaseIterable, Identifiable {
    case light, regular, medium, bold
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "細"
        case .regular: "標準"
        case .medium: "中黑"
        case .bold: "粗"
        }
    }
    var weight: Font.Weight? {
        switch self {
        case .light: .light
        case .regular: nil       // 用各元件原本的字重
        case .medium: .medium
        case .bold: .semibold
        }
    }
}

enum TextTone: String, CaseIterable, Identifiable {
    case standard, warm, cool, highContrast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: "系統"
        case .warm: "暖白"
        case .cool: "冷灰"
        case .highContrast: "高對比"
        }
    }
    var color: Color? {
        switch self {
        case .standard: nil
        case .warm: Color(red: 0.36, green: 0.30, blue: 0.24)
        case .cool: Color(red: 0.28, green: 0.32, blue: 0.38)
        case .highContrast: Color.primary
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case system, light, dark, pureBlack, paper, midnight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "跟隨系統"
        case .light: "淺色"
        case .dark: "深色"
        case .pureBlack: "純黑"
        case .paper: "米紙"
        case .midnight: "深海藍"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light, .paper: .light
        case .dark, .pureBlack, .midnight: .dark
        }
    }
    /// nil 表示使用系統預設背景
    var color: Color? {
        switch self {
        case .system, .light, .dark: nil
        case .pureBlack: .black
        case .paper: Color(red: 0.96, green: 0.94, blue: 0.88)
        case .midnight: Color(red: 0.06, green: 0.09, blue: 0.16)
        }
    }
}

enum AccentMode: String, CaseIterable, Identifiable {
    case followTitle, fixed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .followTitle: "跟著作品"
        case .fixed: "固定一色"
        }
    }
}

enum AccentPreset: String, CaseIterable, Identifiable {
    case rose, crimson, amber, emerald, azure, violet, graphite
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rose: "玫瑰"
        case .crimson: "緋紅"
        case .amber: "琥珀"
        case .emerald: "翡翠"
        case .azure: "天藍"
        case .violet: "紫羅蘭"
        case .graphite: "石墨"
        }
    }
    var color: Color {
        switch self {
        case .rose: Color(red: 0.85, green: 0.35, blue: 0.60)
        case .crimson: Color(red: 0.82, green: 0.18, blue: 0.25)
        case .amber: Color(red: 0.90, green: 0.60, blue: 0.15)
        case .emerald: Color(red: 0.15, green: 0.65, blue: 0.45)
        case .azure: Color(red: 0.15, green: 0.50, blue: 0.85)
        case .violet: Color(red: 0.48, green: 0.35, blue: 0.80)
        case .graphite: Color(red: 0.40, green: 0.42, blue: 0.46)
        }
    }
}

/// 各作品的代表色
enum TitlePalette {
    static func accent(for titleCode: String) -> Color {
        switch titleCode.uppercased() {
        case "BRD/W139": Color(red: 0.72, green: 0.50, blue: 0.22)   // 棕色塵埃：土黃
        case "NIK":      Color(red: 0.85, green: 0.20, blue: 0.28)   // 妮姬：紅
        case "OVL":      Color(red: 0.45, green: 0.25, blue: 0.65)   // OVERLORD：暗紫
        case "SFN":      Color(red: 0.30, green: 0.60, blue: 0.50)   // 芙莉蓮：青綠
        case "BTR":      Color(red: 0.90, green: 0.45, blue: 0.20)   // 孤獨搖滾：橘
        case "CSM":      Color(red: 0.80, green: 0.30, blue: 0.20)   // 鏈鋸人：鏽紅
        case "HOL":      Color(red: 0.20, green: 0.60, blue: 0.85)   // hololive：天藍
        case "UMA":      Color(red: 0.25, green: 0.55, blue: 0.35)   // 賽馬娘：草綠
        case "BD/W125":  Color(red: 0.35, green: 0.45, blue: 0.75)   // MyGO：靛藍
        default:         Color(red: 0.85, green: 0.35, blue: 0.60)
        }
    }
}

// MARK: - 套用

extension View {
    /// 把外觀設定套到整個 App
    func appAppearance(_ settings: AppearanceSettings) -> some View {
        self
            .dynamicTypeSize(settings.dynamicTypeSize)
            .fontWeight(settings.fontWeight)
            .foregroundStyle(settings.textColor ?? .primary)
            .tint(settings.accentColor)
            .preferredColorScheme(settings.colorScheme)
            .background {
                if let color = settings.backgroundColor {
                    color.ignoresSafeArea()
                }
            }
    }
}
