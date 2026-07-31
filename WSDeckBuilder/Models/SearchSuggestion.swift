import Foundation

/// 搜尋建議：關鍵字疑似在指名某個作品時，提示可切換到該系列。
/// 只提供選項，不動使用者輸入的文字。
struct SearchSuggestion: Identifiable {
    enum Reason {
        /// 關鍵字就是作品名／卡號前綴的一部分
        case exact
        /// 拼錯但很接近（BDR → BRD）
        case typo(matched: String)
    }

    let titleCode: String
    let titleName: String
    let cardCount: Int
    let reason: Reason

    var id: String { titleCode }

    var isExact: Bool {
        if case .exact = reason { return true }
        return false
    }
}

enum FuzzyMatch {

    /// Damerau-Levenshtein 編輯距離：比 Levenshtein 多算「相鄰兩字互換」為 1 步，
    /// 打字最常見的錯誤（BRD → BDR）才會被判定成只差一點。
    static func distance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        var d = Array(repeating: Array(repeating: 0, count: t.count + 1),
                      count: s.count + 1)
        for i in 0...s.count { d[i][0] = i }
        for j in 0...t.count { d[0][j] = j }

        for i in 1...s.count {
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1,        // 刪除
                              d[i][j - 1] + 1,        // 插入
                              d[i - 1][j - 1] + cost) // 替換
                // 相鄰互換
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[s.count][t.count]
    }

    /// 長度越短容忍越低，免得 2 個字的關鍵字亂配到一堆作品
    static func isTypo(_ input: String, of target: String) -> Bool {
        let a = input.lowercased(), b = target.lowercased()
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }
        let tolerance = b.count <= 4 ? 1 : 2
        return distance(a, b) <= tolerance
    }
}
