import Foundation
import SwiftData

/// 匯入牌組（§4.4.5）：支援匯出的 JSON，以及匯出的兩種純文字格式
enum DeckImporter {

    struct Parsed {
        var name: String
        var note: String = ""
        /// 刷版卡號 → 張數
        var entries: [(printingID: String, count: Int)] = []
    }

    struct Result {
        let deck: Deck
        let importedCards: Int      // 實際加入的張數
        let matchedKinds: Int       // 對得上的卡種數
        let skipped: [String]       // 資料庫查不到的卡號
    }

    enum ImportError: LocalizedError {
        case unreadable
        case noCards

        var errorDescription: String? {
            switch self {
            case .unreadable: "檔案格式無法辨識。請使用本 App 匯出的 JSON 或牌表文字。"
            case .noCards: "內容裡找不到任何卡號。"
            }
        }
    }

    // MARK: - 解析

    /// 匯出的 JSON 格式
    private struct ExportedDeck: Decodable {
        let name: String
        let note: String?
        let entries: [Entry]
        struct Entry: Decodable {
            let printingID: String
            let count: Int
        }
    }

    static func parse(_ text: String) throws -> Parsed {
        if let parsed = parseJSON(text) { return parsed }
        if let parsed = parseText(text) { return parsed }
        throw ImportError.unreadable
    }

    private static func parseJSON(_ text: String) -> Parsed? {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ExportedDeck.self, from: data)
        else { return nil }
        var parsed = Parsed(name: decoded.name, note: decoded.note ?? "")
        parsed.entries = decoded.entries.map { ($0.printingID, $0.count) }
        return parsed
    }

    /// 純文字牌表：抓「張數 + 卡號」的行，順帶抓【】裡的牌組名
    private static func parseText(_ text: String) -> Parsed? {
        let namePattern = try! NSRegularExpression(pattern: "【([^】]+)】")
        // 張數與卡號之間容許常見寫法：`4 BRD/…`、`4x BRD/…`、`4. BRD/…`、`4、BRD/…`
        // 也接受卡號在前、張數在後：`BRD/W139-009 x4`
        let entryPattern = try! NSRegularExpression(
            pattern: #"^\s*(?:缺)?(\d+)\s*[.、,xX×*]?\s*([A-Za-z0-9]+/[A-Za-z0-9]+-[A-Za-z0-9]+)"#)
        let reversePattern = try! NSRegularExpression(
            pattern: #"([A-Za-z0-9]+/[A-Za-z0-9]+-[A-Za-z0-9]+)\s*[xX×*]\s*(\d+)"#)

        var name = "匯入的牌組"
        var entries: [(String, Int)] = []

        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            if entries.isEmpty, name == "匯入的牌組",
               let match = namePattern.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line) {
                // 去掉「收牌清單」「缺卡清單」等後綴
                name = String(line[nameRange])
                    .replacingOccurrences(of: "收牌清單", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if let match = entryPattern.firstMatch(in: line, range: range),
               let countRange = Range(match.range(at: 1), in: line),
               let idRange = Range(match.range(at: 2), in: line),
               let count = Int(line[countRange]) {
                entries.append((String(line[idRange]), count))
            } else if let match = reversePattern.firstMatch(in: line, range: range),
                      let idRange = Range(match.range(at: 1), in: line),
                      let countRange = Range(match.range(at: 2), in: line),
                      let count = Int(line[countRange]) {
                entries.append((String(line[idRange]), count))
            }
        }
        guard !entries.isEmpty else { return nil }
        var parsed = Parsed(name: name)
        parsed.entries = entries
        return parsed
    }

    // MARK: - 建立牌組

    /// 把解析結果寫進資料庫；查不到的卡號回報但不中斷
    static func createDeck(from parsed: Parsed, database: CardDatabase,
                           existingNames: [String],
                           context: ModelContext) throws -> Result {
        var merged: [String: Int] = [:]
        var skipped: [String] = []

        for entry in parsed.entries where entry.count > 0 {
            // 精確刷版優先；純文字匯出的基礎卡號則落到該卡的普卡刷版
            if database.printing(id: entry.printingID) != nil {
                merged[entry.printingID, default: 0] += entry.count
            } else if let card = database.card(forPrinting: entry.printingID) {
                merged[card.defaultPrinting.id, default: 0] += entry.count
            } else {
                skipped.append(entry.printingID)
            }
        }
        guard !merged.isEmpty else { throw ImportError.noCards }

        let deck = Deck(name: uniqueName(parsed.name, existing: existingNames))
        deck.note = parsed.note
        context.insert(deck)
        for (printingID, count) in merged.sorted(by: { $0.key < $1.key }) {
            let entry = DeckEntry(printingID: printingID, count: count)
            deck.entries.append(entry)
        }
        deck.updatedAt = .now
        try context.save()

        return Result(deck: deck,
                      importedCards: merged.values.reduce(0, +),
                      matchedKinds: merged.count,
                      skipped: Array(Set(skipped)).sorted())
    }

    /// 同名時加上「(2)」「(3)」，不覆蓋既有牌組
    static func uniqueName(_ name: String, existing: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespaces)
        let trimmed = base.isEmpty ? "匯入的牌組" : base
        guard existing.contains(trimmed) else { return trimmed }
        var index = 2
        while existing.contains("\(trimmed) (\(index))") { index += 1 }
        return "\(trimmed) (\(index))"
    }
}
