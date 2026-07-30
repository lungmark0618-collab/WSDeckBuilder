import XCTest
@testable import WSDeckBuilder

final class DeckValidatorTests: XCTestCase {

    private func makeCard(id: String, name: String,
                          type: CardType = .character) -> Card {
        let json = """
        {
          "id": "\(id)",
          "printings": [
            {"id": "\(id)", "rarity": "C",
             "image_url": "https://example.com/x.png", "is_foil": false}
          ],
          "name_jp": "\(name)", "name_zh": "\(name)",
          "card_type": "\(type.rawValue)", "color": "red",
          "level": 0, "cost": 0, "power": 1000, "soul": 1, "trigger": null,
          "traits_jp": [], "traits_zh": [],
          "text_jp": "", "text_zh": "", "text_lines_jp": [], "text_lines_zh": [],
          "translation_status": "reviewed", "source": "booster"
        }
        """
        return try! JSONDecoder().decode(Card.self, from: Data(json.utf8))
    }

    func testLegalDeck() {
        let character = makeCard(id: "T/X01-001", name: "A")
        let climax = makeCard(id: "T/X01-100", name: "CX", type: .climax)
        // 42 張角色（不同名，避開 4 張上限）+ 8 張 CX（兩種名各 4）
        var items: [DeckValidator.CountedCard] = []
        for index in 0..<14 {
            items.append(.init(card: makeCard(id: "T/X01-0\(index)", name: "角色\(index)"),
                               count: 3))
        }
        items.append(.init(card: makeCard(id: "T/X01-098", name: "CX甲", type: .climax),
                           count: 4))
        items.append(.init(card: makeCard(id: "T/X01-099", name: "CX乙", type: .climax),
                           count: 4))
        _ = character
        _ = climax
        let result = DeckValidator.validate(items)
        XCTAssertEqual(result.totalCount, 50)
        XCTAssertTrue(result.totalOK)
        XCTAssertTrue(result.climaxOK)
        XCTAssertTrue(result.namesOK)
        XCTAssertTrue(result.isLegal)
    }

    func testTotalCountViolation() {
        let items = [DeckValidator.CountedCard(card: makeCard(id: "T/X01-001", name: "A"),
                                               count: 4)]
        let result = DeckValidator.validate(items)
        XCTAssertEqual(result.totalCount, 4)
        XCTAssertFalse(result.totalOK)
        XCTAssertFalse(result.isLegal)
    }

    /// 三層概念：同名不同卡號（補充包 vs 預組）合計仍受 4 張上限
    func testSameNameAcrossDifferentCardIDs() {
        let booster = makeCard(id: "T/X01-013", name: "蒼の魔女 シェラザード")
        let trial = makeCard(id: "T/X01-T13", name: "蒼の魔女 シェラザード")
        let items = [
            DeckValidator.CountedCard(card: booster, count: 3),
            DeckValidator.CountedCard(card: trial, count: 2),
        ]
        let result = DeckValidator.validate(items)
        XCTAssertEqual(result.overLimitNames, ["蒼の魔女 シェラザード"])
        XCTAssertFalse(result.namesOK)
    }

    /// 刷版不獨立計算：nameCount 依卡名跨刷版加總
    func testNameCountAcrossPrintings() {
        let card = makeCard(id: "T/X01-001", name: "同名")
        let another = makeCard(id: "T/X01-002", name: "同名")
        let items = [
            DeckValidator.CountedCard(card: card, count: 2),
            DeckValidator.CountedCard(card: another, count: 2),
        ]
        XCTAssertEqual(DeckValidator.nameCount(of: card, in: items), 4)
        XCTAssertTrue(DeckValidator.validate(items).namesOK)
    }

    func testClimaxLimit() {
        let climax = makeCard(id: "T/X01-100", name: "CX甲", type: .climax)
        let items = [DeckValidator.CountedCard(card: climax, count: 4)]
        let result = DeckValidator.validate(items)
        XCTAssertEqual(result.climaxCount, 4)
        XCTAssertFalse(result.climaxOK)
    }
}

// MARK: - 匯入解析（§4.4.5）

final class DeckImporterTests: XCTestCase {

    func testParseExportedJSON() throws {
        let json = """
        {
          "entries": [
            {"count": 2, "printingID": "BRD/W139-075"},
            {"count": 1, "printingID": "BRD/W139-075S"}
          ],
          "exportedAt": "2026-07-30T00:00:00Z",
          "name": "8門 棕色塵埃",
          "note": "測試"
        }
        """
        let parsed = try DeckImporter.parse(json)
        XCTAssertEqual(parsed.name, "8門 棕色塵埃")
        XCTAssertEqual(parsed.note, "測試")
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertEqual(parsed.entries.first?.count, 2)
    }

    func testParseSimpleText() throws {
        let text = """
        【8門 棕色塵埃】
        Lv0 (26)
        4  BRD/W139-009  海灘的正義 米卡艾拉
        4  BRD/W139-027  異鄉兔女郎 潔妮絲
        CX (8)
        8  BRD/W139-098  盛夏的射手
        """
        let parsed = try DeckImporter.parse(text)
        XCTAssertEqual(parsed.name, "8門 棕色塵埃")
        XCTAssertEqual(parsed.entries.count, 3)
        XCTAssertEqual(parsed.entries.map(\.count), [4, 4, 8])
    }

    func testParseCollectorTextWithRarity() throws {
        let text = """
        【8門 棕色塵埃】收牌清單
        2  BRD/W139-075     RR   海灘天使 泰蕾莎
        1  BRD/W139-075S    SR   海灘天使 泰蕾莎
        """
        let parsed = try DeckImporter.parse(text)
        XCTAssertEqual(parsed.name, "8門 棕色塵埃")
        XCTAssertEqual(parsed.entries.count, 2)
        XCTAssertEqual(parsed.entries[1].printingID, "BRD/W139-075S")
    }

    func testParseShortageTextSkipsSummary() throws {
        let text = """
        【新牌組 1】缺卡清單
        缺1  BRD/W139-075     RR   海灘天使 泰蕾莎（已有1/2）
        —— 合計缺 1 張
        """
        let parsed = try DeckImporter.parse(text)
        XCTAssertEqual(parsed.entries.count, 1)
        XCTAssertEqual(parsed.entries[0].count, 1)
    }

    /// 各種常見寫法：4 / 4x / 4. / 4、/ 卡號在前
    func testParseLooseCountFormats() throws {
        let text = """
        4  BRD/W139-009
        4x BRD/W139-027
        2. BRD/W139-075S
        3、BRD/W139-098
        BRD/W139-100 x4
        """
        let parsed = try DeckImporter.parse(text)
        XCTAssertEqual(parsed.entries.count, 5)
        XCTAssertEqual(parsed.entries.map(\.count), [4, 4, 2, 3, 4])
        XCTAssertEqual(parsed.entries[4].printingID, "BRD/W139-100")
    }

    func testUnreadableTextThrows() {
        XCTAssertThrowsError(try DeckImporter.parse("這裡沒有任何卡號"))
    }

    func testUniqueNameAvoidsOverwrite() {
        XCTAssertEqual(DeckImporter.uniqueName("我的牌", existing: []), "我的牌")
        XCTAssertEqual(DeckImporter.uniqueName("我的牌", existing: ["我的牌"]), "我的牌 (2)")
        XCTAssertEqual(DeckImporter.uniqueName("我的牌", existing: ["我的牌", "我的牌 (2)"]),
                       "我的牌 (3)")
        XCTAssertEqual(DeckImporter.uniqueName("  ", existing: []), "匯入的牌組")
    }
}
