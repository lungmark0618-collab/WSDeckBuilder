import Foundation
import Observation

/// 啟動時載入一次 Bundle 內 JSON，全 App 共用（唯讀）
@Observable
final class CardDatabase {
    private(set) var cards: [Card] = []
    /// 已載入的作品（依 Bundle 內 *_cards.json）
    private(set) var sets: [CardSetMeta] = []
    private(set) var loadError: String?
    /// 正在解 JSON、建索引；UI 拿來顯示載入畫面
    private(set) var isLoading = false

    private var cardIndex: [String: Card] = [:]         // 任一刷版卡號 → Card
    private var printingIndex: [String: Printing] = [:] // 刷版卡號 → Printing
    private var titleByCardID: [String: String] = [:]   // 卡片 → title_code
    private var relationIndex: [String: [CardRelation]] = [:]  // 卡片 → 關聯卡片
    /// 全部特徵（供 FilterSheet 列舉）
    private(set) var allTraits: [String] = []

    /// 解碼與建索引的產物。全部是值型別，可以在背景執行緒算完再整包交給主執行緒。
    private struct Snapshot {
        var cards: [Card] = []
        var sets: [CardSetMeta] = []
        var cardIndex: [String: Card] = [:]
        var printingIndex: [String: Printing] = [:]
        var titleByCardID: [String: String] = [:]
        var relationIndex: [String: [CardRelation]] = [:]
        var allTraits: [String] = []
    }

    /// 六百多萬位元組的 JSON 在主執行緒解會卡住畫面數秒，丟到背景做。
    @MainActor
    func load() async {
        guard !isLoading, cards.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let work = Task.detached(priority: .userInitiated) { Self.buildSnapshot() }
        switch await work.value {
        case .success(let snapshot):
            cards = snapshot.cards
            sets = snapshot.sets
            cardIndex = snapshot.cardIndex
            printingIndex = snapshot.printingIndex
            titleByCardID = snapshot.titleByCardID
            relationIndex = snapshot.relationIndex
            allTraits = snapshot.allTraits
        case .failure(let message):
            loadError = message
        }
    }

    /// 背景解碼的結果；失敗只需要一句給使用者看的訊息，不必包成 Error
    private enum LoadOutcome {
        case success(Snapshot)
        case failure(String)
    }

    private static func buildSnapshot() -> LoadOutcome {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "json",
                                     subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix("_cards.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else {
            return .failure("找不到卡片資料檔（*_cards.json）")
        }
        var snapshot = Snapshot()
        var all: [Card] = []
        for url in urls {
            do {
                let set = try JSONDecoder().decode(CardSet.self,
                                                   from: Data(contentsOf: url))
                snapshot.sets.append(set.meta)
                for card in set.cards {
                    snapshot.titleByCardID[card.id] = set.meta.titleCode
                }
                all.append(contentsOf: set.cards)
            } catch {
                return .failure("\(url.lastPathComponent) 載入失敗："
                                + error.localizedDescription)
            }
        }
        snapshot.sets.sort { $0.titleCode < $1.titleCode }
        snapshot.cards = sortCards(all, titleByCardID: snapshot.titleByCardID)
        for card in snapshot.cards {
            // 基礎卡號也建索引：SP 特典卡（如 -113）沒有同號普卡刷版
            snapshot.cardIndex[card.id] = card
            for printing in card.printings {
                snapshot.cardIndex[printing.id] = card
                snapshot.printingIndex[printing.id] = printing
            }
        }
        snapshot.allTraits = Array(Set(snapshot.cards.flatMap(\.traitsZH))).sorted()
        snapshot.relationIndex = buildRelations(snapshot.cards)
        return .success(snapshot)
    }

    /// 能力文字中以「」指名的卡片（羈絆對象、CX 連動指定的 CX 等），
    /// 同時建立反向關聯（這張 CX 被哪些角色連動）
    private static func buildRelations(_ cards: [Card]) -> [String: [CardRelation]] {
        var byNameJP: [String: [Card]] = [:]
        for card in cards {
            byNameJP[card.nameJP, default: []].append(card)
        }
        var index: [String: [CardRelation]] = [:]

        for card in cards where !card.textJP.isEmpty {
            for line in card.textLinesJP {
                for name in quotedNames(in: line) where name != card.nameJP {
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
        var result: [String: [CardRelation]] = [:]
        for (id, relations) in index {
            var best: [String: CardRelation] = [:]
            for relation in relations {
                let existing = best[relation.card.id]
                if existing == nil || relation.kind.order < existing!.kind.order {
                    best[relation.card.id] = relation
                }
            }
            result[id] = best.values
                .sorted { ($0.kind.order, $0.card.id) < ($1.kind.order, $1.card.id) }
        }
        return result
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
    private static func sortCards(_ cards: [Card],
                                  titleByCardID: [String: String]) -> [Card] {
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

    /// 關鍵字指名的作品（卡片本身不含作品名，得另外比對 meta）
    func titleCodes(matching keyword: String) -> Set<String> {
        let lower = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        // 太短會配到一堆作品，反而干擾一般的卡名搜尋
        guard lower.count >= 2 else { return [] }
        var codes: Set<String> = []
        for set in sets {
            // titleCode 可能是 "BRD/W139"，使用者只會打前綴 "BRD"
            let prefix = set.titleCode.split(separator: "/").first.map(String.init)
                ?? set.titleCode
            if set.titleNameZH.lowercased().contains(lower)
                || set.titleNameJP.lowercased().contains(lower)
                || prefix.lowercased().hasPrefix(lower)
                || set.titleCode.lowercased().hasPrefix(lower) {
                codes.insert(set.titleCode)
            }
        }
        return codes
    }

    /// 疑似在找某個作品時給的選項；打錯字也照原樣保留使用者的輸入
    func suggestions(for keyword: String) -> [SearchSuggestion] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let exact = titleCodes(matching: trimmed)

        var result: [SearchSuggestion] = []
        for set in sets {
            let prefix = set.titleCode.split(separator: "/").first.map(String.init)
                ?? set.titleCode
            let reason: SearchSuggestion.Reason?
            if exact.contains(set.titleCode) {
                reason = .exact
            } else if FuzzyMatch.isTypo(trimmed, of: prefix) {
                reason = .typo(matched: prefix)
            } else if FuzzyMatch.isTypo(trimmed, of: set.titleNameZH) {
                reason = .typo(matched: set.titleNameZH)
            } else {
                reason = nil
            }
            guard let reason else { continue }
            result.append(SearchSuggestion(titleCode: set.titleCode,
                                           titleName: set.titleNameZH,
                                           cardCount: cardCount(inTitle: set.titleCode),
                                           reason: reason))
        }
        // 精確的排前面，其次卡多的作品
        return result.sorted { a, b in
            let ea = a.isExact ? 0 : 1, eb = b.isExact ? 0 : 1
            if ea != eb { return ea < eb }
            return a.cardCount > b.cardCount
        }
    }

    /// §4.4.1：多個篩選條件之間是 AND，同一篩選內的多選是 OR
    func search(_ query: SearchQuery) -> [Card] {
        let keywordTitles = titleCodes(
            matching: query.keyword.trimmingCharacters(in: .whitespaces))
        return cards.filter { card in
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
            // 打作品名（「棕色塵埃2」）時卡名比不到，改讓整個系列命中
            if !keywordTitles.isEmpty,
               keywordTitles.contains(titleByCardID[card.id] ?? "") { return true }
            let lower = keyword.lowercased()
            let normalized = SearchQuery.normalizeCardNumber(keyword)
            if !normalized.isEmpty,
               card.printings.contains(where: {
                   SearchQuery.normalizeCardNumber($0.id).contains(normalized)
               }) { return true }
            // searchBlob 是載入時就算好的小寫全文；這裡再 lowercased() 等於
            // 每按一次鍵就把整個資料庫的卡名與能力文字重新配置一遍
            return card.searchBlob.contains(lower)
        }
    }
}
