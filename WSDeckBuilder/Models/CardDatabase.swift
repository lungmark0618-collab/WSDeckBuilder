import Foundation
import Observation

/// 啟動時載入一次 Bundle 內 JSON，全 App 共用（唯讀）
@Observable
final class CardDatabase {
    private(set) var cards: [Card] = []
    /// 已載入的作品（依 Bundle 內 *_cards.json）
    private(set) var sets: [CardSetMeta] = []
    private(set) var loadError: String?

    private var cardIndex: [String: Card] = [:]         // 任一刷版卡號 → Card
    private var printingIndex: [String: Printing] = [:] // 刷版卡號 → Printing
    private var titleByCardID: [String: String] = [:]   // 卡片 → title_code
    private var relationIndex: [String: [CardRelation]] = [:]  // 卡片 → 關聯卡片
    /// 全部特徵（供 FilterSheet 列舉）
    private(set) var allTraits: [String] = []

    func load() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "json",
                                     subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("_cards.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            loadError = "找不到卡片資料檔（*_cards.json）"
            return
        }
        var all: [Card] = []
        for url in urls {
            do {
                let set = try JSONDecoder().decode(CardSet.self,
                                                   from: Data(contentsOf: url))
                sets.append(set.meta)
                for card in set.cards {
                    titleByCardID[card.id] = set.meta.titleCode
                }
                all.append(contentsOf: set.cards)
            } catch {
                loadError = "\(url.lastPathComponent) 載入失敗：\(error.localizedDescription)"
                return
            }
        }
        sets.sort { $0.titleCode < $1.titleCode }
        cards = sortCards(all)
        for card in cards {
            // 基礎卡號也建索引：SP 特典卡（如 -113）沒有同號普卡刷版
            cardIndex[card.id] = card
            for printing in card.printings {
                cardIndex[printing.id] = card
                printingIndex[printing.id] = printing
            }
        }
        allTraits = Array(Set(cards.flatMap(\.traitsZH))).sorted()
        buildRelations()
    }

    /// 能力文字中以「」指名的卡片（羈絆對象、CX 連動指定的 CX 等），
    /// 同時建立反向關聯（這張 CX 被哪些角色連動）
    private func buildRelations() {
        var byNameJP: [String: [Card]] = [:]
        for card in cards {
            byNameJP[card.nameJP, default: []].append(card)
        }
        var index: [String: [CardRelation]] = [:]

        for card in cards where !card.textJP.isEmpty {
            for line in card.textLinesJP {
                for name in Self.quotedNames(in: line) where name != card.nameJP {
                    guard let targets = byNameJP[name] else { continue }
                    let kind = CardRelation.Kind(line: line, target: targets[0])
                    for target in targets where target.id != card.id {
                        index[card.id, default: []]
                            .append(CardRelation(card: target, kind: kind))
                        index[target.id, default: []]
                            .append(CardRelation(card: card, kind: .referencedBy))
                    }
                }
            }
        }
        // 同一張卡可能被多行提到：每張只留最具體的關聯（羈絆 > CX連動 > 指名）
        for (id, relations) in index {
            var best: [String: CardRelation] = [:]
            for relation in relations {
                let existing = best[relation.card.id]
                if existing == nil || relation.kind.order < existing!.kind.order {
                    best[relation.card.id] = relation
                }
            }
            relationIndex[id] = best.values
                .sorted { ($0.kind.order, $0.card.id) < ($1.kind.order, $1.card.id) }
        }
    }

    private static func quotedNames(in line: String) -> [String] {
        var names: [String] = []
        var current: String?
        for character in line {
            if character == "「" {
                current = ""
            } else if character == "」" {
                if let name = current, !name.isEmpty { names.append(name) }
                current = nil
            } else if current != nil {
                current?.append(character)
            }
        }
        return names
    }

    func relations(for card: Card) -> [CardRelation] { relationIndex[card.id] ?? [] }

    func titleCode(of card: Card) -> String? { titleByCardID[card.id] }

    func cardCount(inTitle code: String) -> Int {
        titleByCardID.values.lazy.filter { $0 == code }.count
    }

    func card(forPrinting id: String) -> Card? { cardIndex[id] }
    func printing(id: String) -> Printing? { printingIndex[id] }

    /// 預設排序：作品 → 等級 → 顏色 → 卡號（CX 排最後）
    private func sortCards(_ cards: [Card]) -> [Card] {
        let colorOrder: [CardColor: Int] = [.yellow: 0, .green: 1, .red: 2, .blue: 3]
        return cards.sorted { a, b in
            let ta = titleByCardID[a.id] ?? "", tb = titleByCardID[b.id] ?? ""
            if ta != tb { return ta < tb }
            let la = a.level ?? 99, lb = b.level ?? 99
            if la != lb { return la < lb }
            let ca = colorOrder[a.color] ?? 9, cb = colorOrder[b.color] ?? 9
            if ca != cb { return ca < cb }
            return a.id < b.id
        }
    }

    /// §4.4.1：多個篩選條件之間是 AND，同一篩選內的多選是 OR
    func search(_ query: SearchQuery) -> [Card] {
        cards.filter { card in
            if let title = query.titleCode,
               titleByCardID[card.id] != title { return false }
            if !query.levels.isEmpty {
                guard let level = card.level, query.levels.contains(level) else { return false }
            }
            if !query.colors.isEmpty, !query.colors.contains(card.color) { return false }
            if !query.types.isEmpty, !query.types.contains(card.cardType) { return false }
            if !query.triggers.isEmpty {
                guard let trigger = card.trigger, query.triggers.contains(trigger) else { return false }
            }
            if !query.traits.isEmpty,
               !card.traitsZH.contains(where: { query.traits.contains($0) }) { return false }
            if let source = query.sourceOnly, card.source != source { return false }

            let keyword = query.keyword.trimmingCharacters(in: .whitespaces)
            guard !keyword.isEmpty else { return true }
            let lower = keyword.lowercased()
            let normalized = SearchQuery.normalizeCardNumber(keyword)
            if !normalized.isEmpty,
               card.printings.contains(where: {
                   SearchQuery.normalizeCardNumber($0.id).contains(normalized)
               }) { return true }
            return card.nameJP.lowercased().contains(lower)
                || card.nameZH.lowercased().contains(lower)
                || card.textJP.lowercased().contains(lower)
                || card.textZH.lowercased().contains(lower)
        }
    }
}
