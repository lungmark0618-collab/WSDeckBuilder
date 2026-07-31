import SwiftData
import SwiftUI

/// 圖鑑分頁：搜尋 + 篩選 + 網格/清單切換（§4.3）
struct CardBrowserView: View {
    @Environment(CardDatabase.self) private var database
    @Environment(AppearanceSettings.self) private var appearance
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @AppStorage("activeDeckUUID") private var activeDeckUUID: String = ""
    @AppStorage("browserUsesGrid") private var usesGrid = true

    @State private var query = SearchQuery()
    @State private var showFilter = false
    @State private var detailCard: Card?

    private var activeDeck: Deck? {
        decks.first { $0.uuid.uuidString == activeDeckUUID }
    }

    @Query private var collection: [CollectionEntry]

    private var results: [Card] {
        let found = database.search(query)
        guard query.ownership != .all else { return found }
        let index = CollectionStore.index(collection)
        return found.filter { card in
            let owned = CollectionStore.owned(of: card, in: index)
            return query.ownership == .owned ? owned > 0 : owned == 0
        }
    }

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
            // 大標題會在搜尋列上方留一整塊空白，卡圖比標題重要，改用 inline
            .navigationBarTitleDisplayMode(.inline)
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
                VStack(spacing: 0) {
                    ActiveDeckPicker(decks: decks, activeDeckUUID: $activeDeckUUID)
                    suggestionBar
                }
            }
            .sheet(isPresented: $showFilter) {
                FilterSheet(query: $query)
            }
            // 強調色跟著目前瀏覽的作品
            .onChange(of: query.titleCode, initial: true) {
                appearance.currentTitleCode = query.titleCode ?? ""
            }
            .sheet(item: $detailCard) { card in
                // 帶著搜尋結果進去，詳情頁就能左右滑看下一張
                CardDetailSheet(card: card, siblings: results, deck: activeDeck)
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search
                }
            }
        }
    }

    // MARK: - 搜尋建議（只給選項，不改使用者打的字）

    private var suggestions: [SearchSuggestion] {
        // 已經鎖定作品了就不用再建議切過去
        guard query.titleCode == nil else { return [] }
        return database.suggestions(for: query.keyword)
    }

    @ViewBuilder
    private var suggestionBar: some View {
        let items = suggestions
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            // 切到該作品，關鍵字清掉才看得到整個系列
                            withAnimation {
                                query.titleCode = item.titleCode
                                query.keyword = ""
                            }
                        } label: {
                            suggestionChip(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 7)
            }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func suggestionChip(_ item: SearchSuggestion) -> some View {
        HStack(spacing: 5) {
            switch item.reason {
            case .exact:
                Image(systemName: "square.stack.3d.up.fill")
                Text("看整個「\(item.titleName)」")
            case .typo(let matched):
                Image(systemName: "sparkle.magnifyingglass")
                // 只給代號看不出是哪部作品，兩個都寫
                Text(matched == item.titleName
                     ? "你是不是要找「\(item.titleName)」？"
                     : "你是不是要找「\(item.titleName)」\(matched)？")
            }
            Text("\(item.cardCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(item.isExact ? Color.accentColor.opacity(0.16)
                                 : Color(.tertiarySystemFill),
                    in: Capsule())
        .overlay {
            Capsule().strokeBorder(item.isExact ? Color.accentColor.opacity(0.4)
                                                : .clear, lineWidth: 1)
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
