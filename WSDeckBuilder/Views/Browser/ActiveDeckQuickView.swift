import SwiftData
import SwiftUI

/// 圖鑑加卡加到一半，不離開圖鑑就能看到目前牌組放了哪些卡、直接調整（Android 版先做的功能，這裡補齊）。
/// 卡表邏輯跟 DeckDetailView 同款但簡化：不含設封面的長按選單，那是牌組管理才需要的操作。
struct ActiveDeckQuickView: View {
    let deck: Deck
    @Environment(CardDatabase.self) private var database
    @Environment(\.dismiss) private var dismiss
    @AppStorage("deckUsesGrid") private var usesGrid = true
    @State private var detailCard: Card?

    private struct LevelSection {
        let title: String
        let count: Int
        let items: [DeckExporter.CardCount]
    }

    private struct PrintingTile {
        let card: Card
        let printing: Printing
    }

    private var countedItems: [DeckValidator.CountedCard] {
        DeckExporter.groupByCard(deck: deck, database: database)
            .map { DeckValidator.CountedCard(card: $0.card, count: $0.count) }
    }

    private var sections: [LevelSection] {
        let grouped = DeckExporter.groupByCard(deck: deck, database: database)
        var result: [LevelSection] = []
        for level in 0...3 {
            let items = grouped.filter { $0.card.level == level && $0.card.cardType != .climax }
            if !items.isEmpty {
                result.append(.init(title: "Lv\(level)",
                                    count: items.reduce(0) { $0 + $1.count },
                                    items: items))
            }
        }
        let climax = grouped.filter { $0.card.cardType == .climax }
        if !climax.isEmpty {
            result.append(.init(title: "CX",
                                count: climax.reduce(0) { $0 + $1.count },
                                items: climax))
        }
        return result
    }

    /// 把每張卡展開成「牌組中有放的刷版」各一格
    private func printingTiles(for section: LevelSection) -> [PrintingTile] {
        section.items.flatMap { item in
            item.card.printings.compactMap { printing in
                (deck.entry(forPrinting: printing.id)?.count ?? 0) > 0
                    ? PrintingTile(card: item.card, printing: printing)
                    : nil
            }
        }
    }

    private var orderedCards: [Card] {
        sections.flatMap { $0.items.map(\.card) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if deck.entries.isEmpty {
                    ContentUnavailableView("牌組是空的",
                                           systemImage: "rectangle.stack.badge.plus",
                                           description: Text("到圖鑑選卡加進來"))
                } else if usesGrid {
                    grid
                } else {
                    list
                }
            }
            .navigationTitle(deck.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(deck.totalCount)/50")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(deck.totalCount == 50 ? .green : .secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { usesGrid.toggle() }
                    } label: {
                        Image(systemName: usesGrid ? "list.bullet" : "square.grid.3x3")
                    }
                    .accessibilityLabel(usesGrid ? "改為清單顯示" : "改為圖片顯示")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $detailCard) { card in
                CardDetailSheet(card: card, siblings: orderedCards, deck: deck)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s8, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.s12)],
                                  spacing: Spacing.s16) {
                            ForEach(printingTiles(for: section), id: \.printing.id) { tile in
                                CardGridItemView(card: tile.card, deck: deck,
                                                 printing: tile.printing) {
                                    detailCard = tile.card
                                }
                            }
                        }
                        .padding(.horizontal)
                    } header: {
                        Text("\(section.title) (\(section.count))")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .background(.bar)
                    }
                }
            }
            .padding(.bottom, Spacing.s8)
        }
    }

    private var list: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section("\(section.title) (\(section.count))") {
                    ForEach(section.items, id: \.card.id) { item in
                        DeckEntryRowView(
                            deck: deck,
                            card: item.card,
                            totalForName: DeckValidator.nameCount(of: item.card,
                                                                  in: countedItems)) {
                            detailCard = item.card
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
