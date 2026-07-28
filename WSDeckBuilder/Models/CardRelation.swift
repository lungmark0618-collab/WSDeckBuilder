import Foundation

/// 卡片之間的指名關聯：能力文字裡以「」提到的卡
struct CardRelation: Identifiable, Hashable {
    let card: Card
    let kind: Kind

    var id: String { card.id + kind.rawValue }

    enum Kind: String, Hashable {
        case cxCombo        // 【CX連動】指定的 CX
        case bond           // 絆／羈絆的對象
        case change         // 變身（チェンジ）的對象
        case named          // 其他以卡名指名的卡
        case referencedBy   // 反向：這張卡被誰指名

        var label: String {
            switch self {
            case .cxCombo: "CX連動"
            case .bond: "羈絆"
            case .change: "變身"
            case .named: "指名"
            case .referencedBy: "被指名"
            }
        }

        var symbol: String {
            switch self {
            case .cxCombo: "bolt.fill"
            case .bond: "link"
            case .change: "arrow.triangle.2.circlepath"
            case .named: "text.quote"
            case .referencedBy: "arrow.uturn.left"
            }
        }

        /// 數字越小越具體；同一張卡被多行提到時取最具體的
        var order: Int {
            switch self {
            case .bond: 0
            case .cxCombo: 1
            case .change: 2
            case .named: 3
            case .referencedBy: 4
            }
        }

        /// 依該行文字的上下文判斷關聯種類
        init(line: String, target: Card) {
            if line.contains("絆") {
                self = .bond
            } else if line.contains("チェンジ") || line.contains("變身") {
                self = .change
            } else if target.cardType == .climax
                        || line.contains("CXコンボ") || line.contains("CX連動")
                        || line.contains("CX置場") {
                self = .cxCombo
            } else {
                self = .named
            }
        }
    }
}
