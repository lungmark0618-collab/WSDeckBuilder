import Foundation

/// WS Neo-Standard 建構規則檢查（§4.4.3）。純函式，好測試。
struct DeckValidator {

    struct Result {
        var totalCount: Int
        var climaxCount: Int
        /// 同名超過 4 張的卡名（依 nameJP 分組，跨刷版、跨卡號）
        var overLimitNames: [String]

        var totalOK: Bool { totalCount == 50 }
        var climaxOK: Bool { climaxCount == 8 }
        var namesOK: Bool { overLimitNames.isEmpty }
        var isLegal: Bool { totalOK && climaxOK && namesOK }
    }

    /// 展開後的一筆：卡片 + 張數（呼叫端負責把 printingID 解析成 Card）
    struct CountedCard {
        let card: Card
        let count: Int
    }

    static let deckSize = 50
    static let climaxLimit = 8
    static let nameLimit = 4

    static func validate(_ items: [CountedCard]) -> Result {
        let total = items.reduce(0) { $0 + $1.count }
        let climax = items.filter { $0.card.cardType == .climax }.reduce(0) { $0 + $1.count }

        // ⚠ 三層概念：刷版不獨立計算；4 張上限依「卡名」分組，
        //   因為存在不同基礎卡號但同名的卡（補充包與預組重複收錄）
        var byName: [String: Int] = [:]
        for item in items {
            byName[item.card.nameJP, default: 0] += item.count
        }
        let over = byName.filter { $0.value > nameLimit }.keys.sorted()

        return Result(totalCount: total, climaxCount: climax, overLimitNames: Array(over))
    }

    /// 某一張卡（依卡名跨刷版）目前是否已達上限
    static func nameCount(of card: Card, in items: [CountedCard]) -> Int {
        items.filter { $0.card.nameJP == card.nameJP }.reduce(0) { $0 + $1.count }
    }
}
