import XCTest
@testable import WSDeckBuilder

final class CardSearchTests: XCTestCase {

    private var database: CardDatabase!

    override func setUp() {
        super.setUp()
        database = CardDatabase()
        // 測試 target 以 app 為 host，可直接讀 app bundle 的 brd_cards.json
        database.load()
    }

    func testDataLoads() {
        XCTAssertNil(database.loadError)
        XCTAssertFalse(database.cards.isEmpty)
        XCTAssertEqual(database.meta?.titleCode, "BRD/W139")
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

    func testSearchResultsSortedByLevel() {
        let results = database.search(SearchQuery())
        let levels = results.map { $0.level ?? 99 }
        XCTAssertEqual(levels, levels.sorted())
    }
}
