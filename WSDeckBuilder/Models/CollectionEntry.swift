import Foundation
import SwiftData

/// 我的收藏：某個刷版實際擁有幾張
@Model
final class CollectionEntry {
    @Attribute(.unique) var printingID: String = ""
    var ownedCount: Int = 0
    var updatedAt: Date = Date()

    init(printingID: String, ownedCount: Int) {
        self.printingID = printingID
        self.ownedCount = ownedCount
        self.updatedAt = .now
    }
}

/// 收藏查詢與異動的工具（純函式，方便測試）
enum CollectionStore {

    /// 由 @Query 取得的清單建索引
    static func index(_ entries: [CollectionEntry]) -> [String: Int] {
        var result: [String: Int] = [:]
        for entry in entries where entry.ownedCount > 0 {
            result[entry.printingID] = entry.ownedCount
        }
        return result
    }

    /// 某張卡跨刷版的擁有總數
    static func owned(of card: Card, in index: [String: Int]) -> Int {
        card.printings.reduce(0) { $0 + (index[$1.id] ?? 0) }
    }

    /// 調整擁有張數；歸零即刪除該筆
    static func adjust(printingID: String, by delta: Int,
                       entries: [CollectionEntry], context: ModelContext) {
        if let entry = entries.first(where: { $0.printingID == printingID }) {
            entry.ownedCount = max(0, entry.ownedCount + delta)
            entry.updatedAt = .now
            if entry.ownedCount == 0 { context.delete(entry) }
        } else if delta > 0 {
            context.insert(CollectionEntry(printingID: printingID, ownedCount: delta))
        }
        try? context.save()
    }

    /// 牌組缺卡：每個刷版還差幾張
    struct Shortage: Identifiable {
        let printing: Printing
        let card: Card
        let needed: Int
        let owned: Int
        var missing: Int { max(0, needed - owned) }
        var id: String { printing.id }
    }

    static func shortages(deck: Deck, database: CardDatabase,
                          index: [String: Int]) -> [Shortage] {
        deck.entries.compactMap { entry -> Shortage? in
            guard let card = database.card(forPrinting: entry.printingID),
                  let printing = database.printing(id: entry.printingID) else { return nil }
            let shortage = Shortage(printing: printing, card: card,
                                    needed: entry.count,
                                    owned: index[entry.printingID] ?? 0)
            return shortage.missing > 0 ? shortage : nil
        }
        .sorted { $0.printing.id < $1.printing.id }
    }

    /// 缺卡清單文字（去卡店對照用）
    static func shortageText(deck: Deck, shortages: [Shortage]) -> String {
        guard !shortages.isEmpty else { return "【\(deck.name)】缺卡清單\n（沒有缺卡，全部齊了）" }
        var lines = ["【\(deck.name)】缺卡清單"]
        for item in shortages {
            let paddedID = item.printing.id.padding(toLength: 16, withPad: " ", startingAt: 0)
            let paddedRarity = item.printing.rarity.padding(toLength: 4, withPad: " ", startingAt: 0)
            lines.append("缺\(item.missing)  \(paddedID) \(paddedRarity) \(item.card.nameZH)"
                         + (item.owned > 0 ? "（已有\(item.owned)/\(item.needed)）" : ""))
        }
        lines.append("—— 合計缺 \(shortages.reduce(0) { $0 + $1.missing }) 張")
        return lines.joined(separator: "\n")
    }
}
