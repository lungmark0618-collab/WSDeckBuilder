import SwiftUI

/// 目前牌組內容的縮圖列，貼在卡片結果正上方——不用再去角落找一行小字，
/// 加卡的同時餘光就能看到已經放了哪些。點整列拉出 ActiveDeckQuickView
/// 看完整清單、調整張數（Android 版先做的功能，這裡補齊）。
struct ActiveDeckStripView: View {
    let deck: Deck
    @Environment(CardDatabase.self) private var database
    var onTap: () -> Void

    private var items: [DeckExporter.CardCount] {
        DeckExporter.groupByCard(deck: deck, database: database)
    }

    var body: some View {
        if !items.isEmpty {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    HStack(spacing: Spacing.s4) {
                        Text(deck.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: Spacing.s8)
                        Text("\(deck.totalCount)/50")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(deck.totalCount == 50 ? .green : .secondary)
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s8) {
                            ForEach(items, id: \.card.id) { item in
                                thumbnail(for: item)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Spacing.s8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func thumbnail(for item: DeckExporter.CardCount) -> some View {
        // 牌組中實際放的刷版優先顯示縮圖，沒有才退回普卡
        let printing = item.card.printings.first {
            (deck.entry(forPrinting: $0.id)?.count ?? 0) > 0
        } ?? item.card.defaultPrinting
        return CardImageView(printing: printing, cardName: item.card.nameZH,
                              landscape: item.card.cardType == .climax)
            .frame(width: item.card.cardType == .climax ? 62 : 44)
            .overlay(alignment: .bottomTrailing) {
                Text("\(item.count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(2)
            }
            .comfortShadow(.card)
    }
}
