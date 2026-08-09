import XCTest
@testable import WSDeckBuilder

final class CardSearchTests: XCTestCase {

    private var database: CardDatabase!

    // load() 是 @MainActor async（解 JSON 丟到背景做，見 CardDatabase），
    // 所以 setUp 也得是 async 才等得到它完成
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        database = CardDatabase()
        // 測試 target 以 app 為 host，可直接讀 app bundle 內的卡表
        await database.load()
    }

    func testDataLoads() {
        XCTAssertNil(database.loadError)
        XCTAssertFalse(database.cards.isEmpty)
        XCTAssertTrue(database.sets.contains { $0.titleCode == "BRD/W139" })
        // 對照實際打包進去的檔案數，而不是寫死數字——寫死的話每收錄一部作品
        // 就得改測試，而真正要防的是「有卡表檔沒被載進來」
        XCTAssertEqual(database.sets.count, CardDatabase.dataFileURLs().count,
                       "\(database.sets.map(\.titleCode))")
    }

    func testTitleFilter() {
        var query = SearchQuery()
        query.titleCode = "BRD/W139"
        let results = database.search(query)
        // 依作品篩選應該正好拿到該作品的全部卡片
        let meta = database.sets.first { $0.titleCode == "BRD/W139" }
        XCTAssertEqual(results.count, meta?.cardCount)
        XCTAssertTrue(results.allSatisfy { $0.id.hasPrefix("BRD/") })
    }

    func testEveryCardHasChineseName() {
        for card in database.cards {
            XCTAssertFalse(card.nameZH.isEmpty, "\(card.id) 缺中文卡名")
        }
    }

    func testPrintingIndexCoversAllPrintings() {
        for card in database.cards {
            for printing in card.printings {
                XCTAssertEqual(database.card(forPrinting: printing.id)?.id, card.id)
                XCTAssertEqual(database.printing(id: printing.id)?.id, printing.id)
            }
        }
    }

    func testNormalizedCardNumberSearch() {
        // 忽略大小寫與斜線（§4.4.1）：輸入 w139075 也能找到 BRD/W139-075
        var query = SearchQuery()
        query.keyword = "w139075"
        let results = database.search(query)
        XCTAssertTrue(results.contains { $0.id == "BRD/W139-075" },
                      "找到的是：\(results.map(\.id))")
    }

    /// 只記得作品代號和末三碼也要找得到（不必背出中間的 /W91-）
    func testLooseCardNumberSearch() {
        let id = "HOL/W91-005"
        for keyword in ["hol 005", "hol005", "HOL 5", "hol/w91-005", "005"] {
            XCTAssertTrue(
                SearchQuery.looselyMatchesCardNumber(query: keyword, cardID: id),
                "「\(keyword)」應該要命中 \(id)")
        }
    }

    /// 依序比對：段落順序對不上就不該命中，否則等於亂猜
    func testLooseCardNumberRejectsWrongOrderAndMismatch() {
        let id = "HOL/W91-005"
        XCTAssertFalse(SearchQuery.looselyMatchesCardNumber(query: "005 hol", cardID: id))
        XCTAssertFalse(SearchQuery.looselyMatchesCardNumber(query: "hol 006", cardID: id))
        XCTAssertFalse(SearchQuery.looselyMatchesCardNumber(query: "brd 005", cardID: id))
        // 純文字沒有數字段，交給全文搜尋而不是卡號比對
        XCTAssertFalse(SearchQuery.looselyMatchesCardNumber(query: "hol", cardID: id))
    }

    /// 實際跑一次搜尋，確認寬鬆卡號真的接進 search()
    func testLooseCardNumberSearchInDatabase() {
        var query = SearchQuery()
        query.titleCode = "BRD/W139"
        query.keyword = "brd 075"
        let results = database.search(query)
        XCTAssertTrue(results.contains { $0.id == "BRD/W139-075" },
                      "找到的是：\(results.map(\.id))")
    }

    func testChineseNameSearch() {
        var query = SearchQuery()
        query.keyword = "泰蕾莎"
        let results = database.search(query)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.nameZH.contains("泰蕾莎") })
    }

    func testLevelAndColorFilterCombination() {
        var query = SearchQuery()
        query.levels = [0]
        query.colors = [.yellow]
        let results = database.search(query)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.level == 0 && $0.color == .yellow })
    }

    func testClimaxHasNoLevelButHasColor() {
        let climaxes = database.cards.filter { $0.cardType == .climax }
        XCTAssertFalse(climaxes.isEmpty)
        XCTAssertTrue(climaxes.allSatisfy { $0.level == nil })
    }

    func testTriggerFilter() {
        var query = SearchQuery()
        query.triggers = [.gate]
        let results = database.search(query)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.trigger == .gate })
    }

    func testDefaultPrintingBelongsToBaseCardNumber() {
        // 注意：SP 特典卡（如 -113）只有燙金刷版，不存在無字綴普卡，
        // 因此 printings[0] 可能是 -113S；只要求以基礎卡號開頭且排序最短優先
        for card in database.cards {
            XCTAssertTrue(card.defaultPrinting.id.hasPrefix(card.id),
                          "\(card.id) 的 printings[0] 是 \(card.defaultPrinting.id)")
            let shortest = card.printings.map(\.id.count).min()
            XCTAssertEqual(card.defaultPrinting.id.count, shortest,
                           "\(card.id) 的 printings[0] 應為最接近普卡的刷版")
        }
    }

    func testSearchResultsSortedByLevelWithinTitle() {
        // 全域排序為作品 → 等級；單一作品內等級應遞增
        var query = SearchQuery()
        query.titleCode = "BRD/W139"
        let results = database.search(query)
        let levels = results.map { $0.level ?? 99 }
        XCTAssertEqual(levels, levels.sorted())
    }
}
