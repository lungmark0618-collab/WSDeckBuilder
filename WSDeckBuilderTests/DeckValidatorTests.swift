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
