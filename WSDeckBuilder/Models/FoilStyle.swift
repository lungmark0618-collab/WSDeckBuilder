import Foundation

/// 依稀有度區分的箔紋樣式，對照實卡加工。
/// 依據日文卡查資料：R 為「ホロ加工」、RR 為「光沢のあるホロ加工」、
/// RRR 為「特殊ホロ加工＋ザラつき加工」（顆粒感）、SP/SSP 為簽名＋平行加工。
enum FoilStyle: Equatable {
    case none        // C / U / N / TD：無加工
    case confetti    // R：彩色亮片散點（實卡確認）
    case glossHolo   // RR / CX：帶光澤的 holo
    case linear      // SR：細密斜向箔紋
    case grainy      // RRR：顆粒感（ザラつき）特殊箔
    case radial      // 各作品特殊稀有度：放射狀光芒
    case vertical    // SP：直向稜鏡條紋（簽名卡）
    case faceted     // SSP / SEC：三角碎冰紋，最華麗

    /// 是否為簽名卡（額外疊金色簽名箔）
    var hasGoldSignature: Bool {
        switch self {
        case .vertical, .faceted: true
        default: false
        }
    }

    /// 整體強度倍率（越高階越華麗）
    var intensity: Double {
        switch self {
        case .none: 0
        case .confetti: 0.85
        case .glossHolo: 0.60
        case .linear: 0.78
        case .grainy: 0.88
        case .radial: 0.95
        case .vertical: 1.05
        case .faceted: 1.15
        }
    }

    var label: String {
        switch self {
        case .none: "無加工"
        case .confetti: "亮片箔"
        case .glossHolo: "光澤 holo"
        case .linear: "箔紋"
        case .grainy: "顆粒箔"
        case .radial: "放射箔"
        case .vertical: "簽名箔"
        case .faceted: "碎冰箔"
        }
    }

    static func forRarity(_ rarity: String) -> FoilStyle {
        switch rarity.uppercased() {
        // 三角碎冰紋：最高階簽名／機密卡
        case "SSP", "SEC", "SEC+", "CSMR":
            .faceted
        // 直向稜鏡條紋：簽名卡
        case "SP", "TDSP", "SBR":
            .vertical
        // 放射狀：各作品特殊稀有度與 CX 特殊版
        case "CR", "BDR", "OLR", "OFR", "AGR", "KBR", "HLP", "HR", "HRR", "XR":
            .radial
        // 顆粒感特殊箔
        case "RRR", "RRR+":
            .grainy
        // 細密斜紋
        case "SR", "PR+":
            .linear
        // 光澤 holo：RR 與 CX 卡
        case "RR", "CC":
            .glossHolo
        // 彩色亮片散點
        case "R":
            .confetti
        // C / U / N / TD / TDP / HC / HU / PR：無加工
        default:
            .none
        }
    }
}
