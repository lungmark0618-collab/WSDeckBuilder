import SwiftData
import SwiftUI

/// 圖鑑分頁：搜尋 + 篩選 + 網格/清單切換（§4.3）
struct CardBrowserView: View {
    @Environment(CardDatabase.self) private var database
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @AppStorage("activeDeckUUID") private var activeDeckUUID: String = ""
    @AppStorage("browserUsesGrid") private var usesGrid = true

    @State private var query = SearchQuery()
    @State private var showFilter = false
    @State private var detailCard: Card?

    private var activeDeck: Deck? {
        decks.first { $0.uuid.uuidString == activeDeckUUID }
    }

    private var results: [Card] { database.search(query) }

    var body: some View {
        NavigationStack {
            Group {
                if usesGrid {
                    grid
                } else {
                    list
                }
            }
            .navigationTitle(database.sets.first { $0.titleCode == query.titleCode }?
                .titleNameZH ?? "圖鑑")
            .searchable(text: $query.keyword, prompt: "卡號、卡名、能力文字")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: query.hasActiveFilters
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    Button {
                        usesGrid.toggle()
                    } label: {
                        Image(systemName: usesGrid ? "list.bullet" : "square.grid.3x3")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                ActiveDeckPicker(decks: decks, activeDeckUUID: $activeDeckUUID)
            }
            .sheet(isPresented: $showFilter) {
                FilterSheet(query: $query)
            }
            .sheet(item: $detailCard) { card in
                CardDetailSheet(card: card, deck: activeDeck)
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                      spacing: 12) {
                ForEach(results) { card in
                    CardGridItemView(card: card, deck: activeDeck) {
                        detailCard = card
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var list: some View {
        List(results) { card in
            CardRowView(card: card, deck: activeDeck) {
                detailCard = card
            }
        }
        .listStyle(.plain)
    }
}
