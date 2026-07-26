import SwiftData
import SwiftUI

/// 網格單格：卡圖 + 張數徽章 + 增減按鈕（§4.3）
struct CardGridItemView: View {
    let card: Card
    var deck: Deck?
    var onTap: () -> Void

    @Environment(\.modelContext) private var context

    private var countInDeck: Int { deck?.count(of: card) ?? 0 }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onTap) {
                CardImageView(printing: card.defaultPrinting, cardName: card.nameZH,
                              landscape: card.cardType == .climax)
                    .overlay(alignment: .topTrailing) {
                        if countInDeck > 0 {
                            Text("\(countInDeck)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(countInDeck > DeckValidator.nameLimit
                                            ? Color.red : Color.accentColor,
                                            in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .buttonStyle(.plain)

            Text(card.nameZH)
                .font(.caption2)
                .lineLimit(1)

            if let deck {
                CountStepper(count: countInDeck) { delta in
                    // ＋預設加入普卡刷版；－從最後一個有牌的刷版扣（§4.4.2）
                    if delta > 0 {
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
