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

    /// 把字串切成「連續字母」與「連續數字」兩種片段：
    /// `HOL/W91-005` → `["hol", "w", "91", "005"]`、`hol 005` → `["hol", "005"]`。
    /// 分隔符號一律當成邊界丟掉，所以空白、`/`、`-` 打不打都一樣。
    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsDigit: Bool?
        for ch in s.lowercased() {
            guard ch.isLetter || ch.isNumber else {
                if !current.isEmpty { tokens.append(current) }
                current = ""
                currentIsDigit = nil
                continue
            }
            let isDigit = ch.isNumber
            if isDigit != currentIsDigit, !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            currentIsDigit = isDigit
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// 卡號寬鬆比對：只記得「hol 005」也要找得到 HOL/W91-005，
    /// 不必逼使用者背出中間的 `/W91-`。
    ///
    /// 規則是「查詢的每一段都要在卡號裡**依序**找到」——字母段比前綴、
    /// 數字段比數值（`005` == `5`，沒人會記得補零）。因此 `hol005`、
    /// `hol 005`、`005`、`hol/w91-005` 都會命中同一張。
    static func looselyMatchesCardNumber(query: String, cardID: String) -> Bool {
        let queryTokens = tokenize(query)
        // 沒有數字就不是在找卡號（多半是卡名或能力文字），交給全文搜尋處理，
        // 否則單打「hol」會被這裡攔下來變成只比卡號
        guard queryTokens.contains(where: { $0.allSatisfy(\.isNumber) }) else { return false }

        let idTokens = tokenize(cardID)
        var index = 0
        for token in queryTokens {
            var matched = false
            while index < idTokens.count {
                let candidate = idTokens[index]
                index += 1
                if tokenMatches(token, candidate) { matched = true; break }
            }
            if !matched { return false }
        }
        return true
    }

    private static func tokenMatches(_ token: String, _ candidate: String) -> Bool {
        let tokenIsDigits = token.allSatisfy(\.isNumber)
        let candidateIsDigits = candidate.allSatisfy(\.isNumber)
        guard tokenIsDigits == candidateIsDigits else { return false }
        // 數字比數值：005 與 5 是同一張；字母比前綴：打 hol 就夠，不用打完整
        if tokenIsDigits { return Int(token) == Int(candidate) }
        return candidate.hasPrefix(token)
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
