import Foundation
import SwiftData

@Model
final class Deck {
    var uuid: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var note: String = ""
    @Relationship(deleteRule: .cascade, inverse: \DeckEntry.deck)
    var entries: [DeckEntry] = []

    init(name: String) {
        self.uuid = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.note = ""
        self.entries = []
    }

    var totalCount: Int { entries.reduce(0) { $0 + $1.count } }

    func entry(forPrinting id: String) -> DeckEntry? {
        entries.first { $0.printingID == id }
    }

    /// 該邏輯卡片（跨刷版）在牌組中的總張數
    func count(of card: Card) -> Int {
        let ids = Set(card.printings.map(\.id))
        return entries.filter { ids.contains($0.printingID) }.reduce(0) { $0 + $1.count }
    }

    /// 調整某刷版張數；歸零自動移除 entry（§4.4.2）。每次變更立即存檔。
    func adjust(printingID: String, by delta: Int, context: ModelContext) {
        updatedAt = .now
        if let entry = entry(forPrinting: printingID) {
            entry.count += delta
            if entry.count <= 0 {
                entries.removeAll { $0.printingID == printingID }
                context.delete(entry)
            }
        } else if delta > 0 {
            let entry = DeckEntry(printingID: printingID, count: delta)
            entries.append(entry)
        }
        try? context.save()
    }

    /// 轉換刷版：把 1 張 from 換成 to（§4.4.2 長按選單）
    func convert(from: String, to: String, context: ModelContext) {
        guard let source = entry(forPrinting: from), source.count > 0 else { return }
        adjust(printingID: from, by: -1, context: context)
        adjust(printingID: to, by: 1, context: context)
    }
}

/// 一筆 = 某張卡的某個刷版放了幾張；只存字串 ID，不存卡片內容
@Model
final class DeckEntry {
    var printingID: String = ""
    var count: Int = 0
    var deck: Deck?

    init(printingID: String, count: Int) {
        self.printingID = printingID
        self.count = count
    }
}
