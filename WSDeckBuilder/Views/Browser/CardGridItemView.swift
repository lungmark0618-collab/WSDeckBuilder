import SwiftData
import SwiftUI

/// 網格單格：卡圖 + 張數徽章 + 增減按鈕（§4.3）
struct CardGridItemView: View {
    let card: Card
    var deck: Deck?
    /// 指定刷版：顯示該刷版的卡圖與張數（牌組畫面依刷版分格用）；
    /// nil = 顯示普卡圖與跨刷版總張數（圖鑑用）
    var printing: Printing? = nil
    /// false = 純瀏覽（隱藏＋/－，徽章照顯示）
    var editable = true
    var onTap: () -> Void

    @Environment(\.modelContext) private var context

    private var displayPrinting: Printing { printing ?? card.defaultPrinting }

    private var badgeCount: Int {
        if let printing, let deck {
            return deck.entry(forPrinting: printing.id)?.count ?? 0
        }
        return deck?.count(of: card) ?? 0
    }

    /// 超量標紅一律看同卡跨刷版總數
    private var isOverLimit: Bool {
        (deck?.count(of: card) ?? 0) > DeckValidator.nameLimit
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTap) {
                CardImageView(printing: displayPrinting, cardName: card.nameZH,
                              landscape: card.cardType == .climax)
                    .overlay(alignment: .topTrailing) {
                        if badgeCount > 0 {
                            Text("\(badgeCount)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(isOverLimit ? Color.red : Color.accentColor,
                                            in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)

            Text(printing == nil ? card.nameZH
                 : "\(displayPrinting.rarity)  \(card.nameZH)")
                .font(.caption2)
                .lineLimit(1)

            if let deck, editable {
                CountStepper(count: badgeCount) { delta in
                    if let printing {
                        // 指定刷版：直接增減該刷版
                        deck.adjust(printingID: printing.id, by: delta, context: context)
                    } else if delta > 0 {
                        // ＋預設加入普卡刷版；－從最後一個有牌的刷版扣（§4.4.2）
                        deck.adjust(printingID: card.defaultPrinting.id, by: 1, context: context)
                    } else {
                        removeOne(from: deck)
                    }
                }
                .frame(height: 32)
            }
        }
    }

    private func removeOne(from deck: Deck) {
        for printing in card.printings.reversed() {
            if let entry = deck.entry(forPrinting: printing.id), entry.count > 0 {
                deck.adjust(printingID: printing.id, by: -1, context: context)
                return
            }
        }
    }
}
