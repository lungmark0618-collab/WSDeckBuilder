import Foundation

struct SearchQuery: Equatable {
    var keyword: String = ""        // 比對卡號、日文名、中文名、能力文字
    var levels: Set<Int> = []       // 空 = 不篩選
    var colors: Set<CardColor> = []
    var types: Set<CardType> = []
    var triggers: Set<TriggerIcon> = []
    var traits: Set<String> = []
    var sourceOnly: CardSource? = nil

    var hasActiveFilters: Bool {
        !levels.isEmpty || !colors.isEmpty || !types.isEmpty
            || !triggers.isEmpty || !traits.isEmpty || sourceOnly != nil
    }

    /// 卡號比對忽略大小寫與 `/` `-`（輸入 w139075 也能命中 BRD/W139-075）
    static func normalizeCardNumber(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}
