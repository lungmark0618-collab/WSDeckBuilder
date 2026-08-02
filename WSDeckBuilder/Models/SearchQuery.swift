import Foundation

struct SearchQuery: Equatable {
    var keyword: String = ""        // 比對卡號、日文名、中文名、能力文字
    var levels: Set<Int> = []       // 空 = 不篩選
    var colors: Set<CardColor> = []
    var types: Set<CardType> = []
    var triggers: Set<TriggerIcon> = []
    var traits: Set<String> = []
    var sourceOnly: CardSource? = nil
    var titleCode: String? = nil    // 作品篩選（nil = 全部）
    var ownership: OwnershipFilter = .all

    var hasActiveFilters: Bool {
        !levels.isEmpty || !colors.isEmpty || !types.isEmpty
            || !triggers.isEmpty || !traits.isEmpty || sourceOnly != nil
            || titleCode != nil || ownership != .all
    }

    /// 關鍵字以外的條件指紋，供畫面判斷該不該重算搜尋結果。
    /// 關鍵字另外走 debounce，所以刻意不含在裡面。
    var filterSignature: String {
        [levels.sorted().map(String.init).joined(separator: ","),
         colors.map(\.rawValue).sorted().joined(separator: ","),
         types.map(\.rawValue).sorted().joined(separator: ","),
         triggers.map(\.rawValue).sorted().joined(separator: ","),
         traits.sorted().joined(separator: ","),
         sourceOnly?.rawValue ?? "",
         titleCode ?? "",
         ownership.rawValue].joined(separator: "|")
    }

    /// 卡號比對忽略大小寫與 `/` `-`（輸入 w139075 也能命中 BRD/W139-075）
    static func normalizeCardNumber(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

enum OwnershipFilter: String, CaseIterable, Identifiable {
    case all, owned, missing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "全部"
        case .owned: "已擁有"
        case .missing: "未擁有"
        }
    }
}
