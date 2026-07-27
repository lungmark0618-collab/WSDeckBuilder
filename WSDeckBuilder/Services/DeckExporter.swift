import Foundation

/// 匯出純文字／JSON（§4.4.5）
enum DeckExporter {

    /// 簡潔版：貼論壇用，不分刷版
    static func simpleText(deck: Deck, database: CardDatabase) -> String {
        var lines = ["【\(deck.name)】"]
        let grouped = groupByCard(deck: deck, database: database)
        for (levelLabel, items) in byLevel(grouped) {
            let count = items.reduce(0) { $0 + $1.count }
            lines.append("\(levelLabel) (\(count))")
            for item in items {
                lines.append("\(item.count)  \(item.card.id)  \(item.card.nameZH)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 收牌版：列出刷版，去卡店對照用
    static func collectorText(deck: Deck, database: CardDatabase) -> String {
        var lines = ["【\(deck.name)】收牌清單"]
        let sorted = deck.entries.sorted { $0.printingID < $1.printingID }
        for entry in sorted {
            guard let card = database.card(forPrinting: entry.printingID),
                  let printing = database.printing(id: entry.printingID) else { continue }
            let paddedID = entry.printingID.padding(toLength: 16, withPad: " ", startingAt: 0)
            let paddedRarity = printing.rarity.padding(toLength: 4, withPad: " ", startingAt: 0)
            lines.append("\(entry.count)  \(paddedID) \(paddedRarity) \(card.nameZH)")
        }
        return lines.joined(separator: "\n")
    }

    /// 完整 JSON（含刷版），供備份與跨機器搬移
    static func json(deck: Deck) -> String {
        struct Export: Codable {
            let name: String
            let note: String
            let exportedAt: String
            let entries: [Entry]
            struct Entry: Codable {
                let printingID: String
                let count: Int
            }
        }
        let export = Export(
            name: deck.name,
            note: deck.note,
            exportedAt: ISO8601DateFormatter().string(from: .now),
            entries: deck.entries
                .sorted { $0.printingID < $1.printingID }
                .map { .init(printingID: $0.printingID, count: $0.count) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(export)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: - Helpers

    struct CardCount {
        let card: Card
        let count: Int
    }

    static func groupByCard(deck: Deck, database: CardDatabase) -> [CardCount] {
        // 直接保留 Card 物件，不可用基礎卡號回查——SP 特典卡沒有同號刷版會漏算
        var counts: [String: Int] = [:]
        var cardsByID: [String: Card] = [:]
        for entry in deck.entries {
            guard let card = database.card(forPrinting: entry.printingID) else { continue }
            counts[card.id, default: 0] += entry.count
            cardsByID[card.id] = card
        }
        return counts.compactMap { id, count in
            cardsByID[id].map { CardCount(card: $0, count: count) }
        }.sorted { $0.card.id < $1.card.id }
    }

    private static func byLevel(_ items: [CardCount]) -> [(String, [CardCount])] {
        var result: [(String, [CardCount])] = []
        for level in 0...3 {
            let matched = items.filter { $0.card.level == level && $0.card.cardType != .climax }
            if !matched.isEmpty { result.append(("Lv\(level)", matched)) }
        }
        let climax = items.filter { $0.card.cardType == .climax }
        if !climax.isEmpty { result.append(("CX", climax)) }
        return result
    }
}
