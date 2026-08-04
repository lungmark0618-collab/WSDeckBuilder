import Foundation

/// 邏輯上的「一張卡」：同名同文字，可能有多種刷版（§3.2 一卡多刷）
struct Card: Decodable, Identifiable, Hashable {
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
    let textJP: String
    let textZH: String
    let translationStatus: TranslationStatus
    let source: CardSource

    // MARK: - 解碼時衍生（不進 JSON，省下三成檔案大小）

    /// 能力文字逐行。就是 textJP 以換行切開，不必存第二份
    let textLinesJP: [String]
    let textLinesZH: [String]
    /// 特徵刻意不翻譯（要跟卡面一致），中文欄位永遠等於日文
    var traitsZH: [String] { traitsJP }
    /// 搜尋用的小寫全文。每次比對再 lowercased() 會重複配置整個資料庫的字串
    let searchBlob: String

    var defaultPrinting: Printing { printings[0] }

    enum CodingKeys: String, CodingKey {
        case id, printings, level, cost, power, soul, trigger, source
        case nameJP = "name_jp"
        case nameZH = "name_zh"
        case cardType = "card_type"
        case color
        case traitsJP = "traits_jp"
        case textJP = "text_jp"
        case textZH = "text_zh"
        case translationStatus = "translation_status"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        printings = try c.decode([Printing].self, forKey: .printings)
        nameJP = try c.decode(String.self, forKey: .nameJP)
        nameZH = try c.decode(String.self, forKey: .nameZH)
        cardType = try c.decode(CardType.self, forKey: .cardType)
        color = try c.decode(CardColor.self, forKey: .color)
        level = try c.decodeIfPresent(Int.self, forKey: .level)
        cost = try c.decodeIfPresent(Int.self, forKey: .cost)
        power = try c.decodeIfPresent(Int.self, forKey: .power)
        soul = try c.decodeIfPresent(Int.self, forKey: .soul)
        trigger = try c.decodeIfPresent(TriggerIcon.self, forKey: .trigger)
        traitsJP = try c.decode([String].self, forKey: .traitsJP)
        textJP = try c.decode(String.self, forKey: .textJP)
        textZH = try c.decode(String.self, forKey: .textZH)
        translationStatus = try c.decode(TranslationStatus.self, forKey: .translationStatus)
        source = try c.decode(CardSource.self, forKey: .source)

        textLinesJP = textJP.isEmpty ? [] : textJP.components(separatedBy: "\n")
        textLinesZH = textZH.isEmpty ? [] : textZH.components(separatedBy: "\n")
        searchBlob = [nameJP, nameZH, textJP, textZH]
            .joined(separator: "\n")
            .lowercased()
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

    /// 依稀有度決定箔紋樣式；資料未標示為平行卡時不套用
    var foilStyle: FoilStyle {
        let style = FoilStyle.forRarity(rarity)
        if case .none = style { return isFoil ? .linear : .none }
        return style
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
    /// 官方卡面圖示（Assets 內，抓自官網 _partimages）；nil 表示無圖示退回文字
    var iconName: String? {
        switch self {
        case .soul, .soul2: "trigger_soul"
        case .gate: "trigger_gate"
        case .treasure: "trigger_treasure"
        case .comeback: "trigger_salvage"
        case .draw: "trigger_draw"
        case .pool: nil
        case .shot: "trigger_shot"
        case .standby: "trigger_standby"
        case .choice: "trigger_focus"
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

struct CardSet: Decodable {
    let meta: CardSetMeta
    let cards: [Card]
}

struct CardSetMeta: Codable {
    let titleCode: String
    let titleNameJP: String
    let titleNameZH: String
    let cardCount: Int
    /// 單調遞增，線上更新就比這個數字（§4.4.8）。
    /// 舊卡表沒有這個欄位，當作 1
    let dataVersion: Int

    enum CodingKeys: String, CodingKey {
        case titleCode = "title_code"
        case titleNameJP = "title_name_jp"
        case titleNameZH = "title_name_zh"
        case cardCount = "card_count"
        case dataVersion = "data_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titleCode = try c.decode(String.self, forKey: .titleCode)
        titleNameJP = try c.decode(String.self, forKey: .titleNameJP)
        titleNameZH = try c.decode(String.self, forKey: .titleNameZH)
        cardCount = try c.decode(Int.self, forKey: .cardCount)
        dataVersion = try c.decodeIfPresent(Int.self, forKey: .dataVersion) ?? 1
    }
}
