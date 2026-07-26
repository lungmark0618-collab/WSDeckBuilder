import Foundation

/// 邏輯上的「一張卡」：同名同文字，可能有多種刷版（§3.2 一卡多刷）
struct Card: Codable, Identifiable, Hashable {
    let id: String                  // 基礎卡號 "BRD/W139-075"
    let printings: [Printing]       // 所有刷版，[0] 為普卡
    let nameJP: String
    let nameZH: String
    let cardType: CardType
    let color: CardColor
    let level: Int?                 // CX 為 nil
    let cost: Int?                  // CX 為 nil
    let power: Int?                 // 事件/CX 為 nil
    let soul: Int?
    let trigger: TriggerIcon?
    let traitsJP: [String]
    let traitsZH: [String]
    let textJP: String
    let textZH: String
    let textLinesJP: [String]
    let textLinesZH: [String]
    let translationStatus: TranslationStatus
    let source: CardSource

    var defaultPrinting: Printing { printings[0] }

    enum CodingKeys: String, CodingKey {
        case id, printings, level, cost, power, soul, trigger, source
        case nameJP = "name_jp"
        case nameZH = "name_zh"
        case cardType = "card_type"
        case color
        case traitsJP = "traits_jp"
        case traitsZH = "traits_zh"
        case textJP = "text_jp"
        case textZH = "text_zh"
        case textLinesJP = "text_lines_jp"
        case textLinesZH = "text_lines_zh"
        case translationStatus = "translation_status"
    }
}

/// 同一張卡的某個刷版（稀有度不同、圖不同、文字相同）
struct Printing: Codable, Identifiable, Hashable {
    let id: String              // "BRD/W139-075" / "-075S" / "-075SSP"
    let rarity: String          // "RR" / "SR" / "SSP"
    let imageURL: URL
    let isFoil: Bool

    enum CodingKeys: String, CodingKey {
        case id, rarity
        case imageURL = "image_url"
        case isFoil = "is_foil"
    }

    /// 卡號中的 `/` 無法用於檔名（§4.4.6）
    var cacheFileName: String {
        id.replacingOccurrences(of: "/", with: "_") + ".png"
    }
}

enum CardType: String, Codable, CaseIterable, Identifiable {
    case character, event, climax
    var id: String { rawValue }
    var label: String {
        switch self {
        case .character: "角色"
        case .event: "事件"
        case .climax: "CX"
        }
    }
}

enum CardColor: String, Codable, CaseIterable, Identifiable {
    case yellow, green, red, blue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .yellow: "黃"
        case .green: "綠"
        case .red: "紅"
        case .blue: "藍"
        }
    }
}

enum TriggerIcon: String, Codable, CaseIterable, Identifiable {
    case soul, soul2, gate, treasure, comeback
    case draw, pool, shot, standby, choice
    var id: String { rawValue }
    /// 台灣圈子慣用單字標籤（§3.4）
    var label: String {
        switch self {
        case .soul: "魂"
        case .soul2: "雙魂"
        case .gate: "城門"
        case .treasure: "寶"
        case .comeback: "木門"
        case .draw: "本"
        case .pool: "金"
        case .shot: "槍"
        case .standby: "開機"
        case .choice: "箭頭"
        }
    }
}

enum TranslationStatus: String, Codable {
    case machine, reviewed, manual
}

enum CardSource: String, Codable, CaseIterable, Identifiable {
    case booster
    case trialDeck = "trial_deck"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .booster: "補充包"
        case .trialDeck: "預組"
        }
    }
}

struct CardSet: Codable {
    let meta: CardSetMeta
    let cards: [Card]
}

struct CardSetMeta: Codable {
    let titleCode: String
    let titleNameJP: String
    let titleNameZH: String
    let cardCount: Int

    enum CodingKeys: String, CodingKey {
        case titleCode = "title_code"
        case titleNameJP = "title_name_jp"
        case titleNameZH = "title_name_zh"
        case cardCount = "card_count"
    }
}
