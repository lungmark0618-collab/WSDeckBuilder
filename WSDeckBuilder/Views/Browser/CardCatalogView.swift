import SwiftData
import SwiftUI

/// 圖鑑這一層要看的東西
enum CatalogRoute: Hashable {
    /// 最上層：沒在找東西時顯示作品選單
    case root
    /// 鎖定單一作品
    case title(String)
    /// 不分作品的全部卡片
    case allCards
}

/// 圖鑑的內容頁：搜尋 + 篩選 + 網格/清單（§4.3）
///
/// 三種進法共用同一個畫面，差別只在「有沒有鎖定作品」與「閒置時顯不顯示作品選單」，
/// 拆成三個 View 會讓搜尋、篩選、加牌那套狀態複製三份。
struct CardCatalogView: View {
    let route: CatalogRoute

    @Environment(CardDatabase.self) private var database
    @Environment(AppearanceSettings.self) private var appearance
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Query private var collection: [CollectionEntry]
    @AppStorage("activeDeckUUID") private var activeDeckUUID: String = ""
    @AppStorage("browserUsesGrid") private var usesGrid = true

    @State private var query: SearchQuery
    @State private var showFilter = false
    @State private var showDeckQuickView = false
    @State private var detailCard: Card?
    /// 套用建議時也會清空關鍵字，別把它誤判成使用者按了清除鈕
    @State private var isApplyingSuggestion = false
    /// 搜尋結果。SwiftUI 每次重算 body 都會讀它，所以不能是 computed property——
    /// 那等於每個畫格更新都全表掃一次 3000 多張卡。
    @State private var results: [Card] = []

    init(route: CatalogRoute) {
        self.route = route
        var initial = SearchQuery()
        if case .title(let code) = route { initial.titleCode = code }
        _query = State(initialValue: initial)
    }

    /// 這一層綁死的作品。使用者不能在畫面裡把它換掉，換了標題就對不上內容
    private var pinnedTitle: String? {
        if case .title(let code) = route { return code }
        return nil
    }

    /// 只有最上層、而且使用者還沒開始找東西時才顯示作品選單
    private var showsGallery: Bool {
        route == .root && query.keyword.isEmpty && !query.hasActiveFilters
    }

    private var activeDeck: Deck? {
        decks.first { $0.uuid.uuidString == activeDeckUUID }
    }

    private func recomputeResults() {
        // 選單狀態下不需要結果，省下一次 3400 張的全表掃描
        guard !showsGallery else { results = []; return }
        let found = database.search(query)
        guard query.ownership != .all else { results = found; return }
        let index = CollectionStore.index(collection)
        results = found.filter { card in
            let owned = CollectionStore.owned(of: card, in: index)
            return query.ownership == .owned ? owned > 0 : owned == 0
        }
    }

    /// 清空條件時保留這一層鎖定的作品，否則按「清除」會整個跳出這部作品
    private func resetQuery() {
        var fresh = SearchQuery()
        fresh.titleCode = pinnedTitle
        query = fresh
    }

    var body: some View {
        Group {
            if showsGallery {
                TitleGalleryView(sets: database.sets, totalCount: database.cards.count)
            } else if usesGrid {
                grid
            } else {
                list
            }
        }
        .navigationTitle(screenTitle)
        // 大標題會在搜尋列上方留一整塊空白，卡圖比標題重要，改用 inline
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query.keyword, prompt: searchPrompt)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: query.hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                if !showsGallery {
                    Button {
                        usesGrid.toggle()
                    } label: {
                        Image(systemName: usesGrid ? "list.bullet" : "square.grid.3x3")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // 作品選單上沒有卡可以加，這排東西只會擋掉版面
            if !showsGallery {
                VStack(spacing: 0) {
                    ActiveDeckPicker(decks: decks, activeDeckUUID: $activeDeckUUID)
                    activeFilterBar
                    suggestionBar
                    if let activeDeck {
                        ActiveDeckStripView(deck: activeDeck) { showDeckQuickView = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(query: $query, lockedTitle: pinnedTitle != nil)
        }
        .sheet(isPresented: $showDeckQuickView) {
            if let activeDeck {
                ActiveDeckQuickView(deck: activeDeck)
            }
        }
        // 強調色跟著目前瀏覽的作品
        .onChange(of: query.titleCode, initial: true) {
            appearance.currentTitleCode = query.titleCode ?? ""
        }
        // 搜尋欄的清除鈕只會清關鍵字，但使用者的意思是「重來」，
        // 篩選（多半是點建議帶上的）留著會讓結果看起來還是不對
        .onChange(of: query.keyword) { old, new in
            guard !isApplyingSuggestion else {
                isApplyingSuggestion = false
                return
            }
            if !old.isEmpty, new.isEmpty, hasVisibleFilters {
                withAnimation { resetQuery() }
            }
        }
        // 打字時每個字都重搜會頓；停一下再搜，中途的輸入直接作廢。
        // task(id:) 會在 id 變動時取消上一個任務，正好是我們要的行為。
        .task(id: query.keyword) {
            if !query.keyword.isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            recomputeResults()
        }
        // 篩選、持有狀態、資料載入完成都要重算，但這些不需要延遲
        .onChange(of: query.filterSignature) { recomputeResults() }
        .onChange(of: collection) { recomputeResults() }
        .onChange(of: database.cards.count) { recomputeResults() }
        .sheet(item: $detailCard) { card in
            // 帶著搜尋結果進去，詳情頁就能左右滑看下一張
            CardDetailSheet(card: card, siblings: results, deck: activeDeck)
        }
        .overlay {
            if !showsGallery, results.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private var screenTitle: String {
        switch route {
        case .root:
            "圖鑑"
        case .title(let code):
            database.sets.first { $0.titleCode == code }?.titleNameZH ?? code
        case .allCards:
            "全部卡片"
        }
    }

    private var searchPrompt: String {
        pinnedTitle == nil ? "卡號、卡名、能力文字" : "在這部作品裡搜尋"
    }

    // MARK: - 作用中的篩選（讓人知道結果為何被縮小，並能一鍵解除）

    /// 鎖定的作品不算，那是這一層的前提而不是使用者加的條件——
    /// 標題已經寫著作品名了，再列一次只是雜訊
    private var hasVisibleFilters: Bool {
        query.hasActiveFilters && !filterSummary.isEmpty
    }

    @ViewBuilder
    private var activeFilterBar: some View {
        if hasVisibleFilters {
            HStack(spacing: Spacing.s8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.tint)
                Text(filterSummary)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s4)
                Button {
                    withAnimation { resetQuery() }
                } label: {
                    Label("清除", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, Spacing.s8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let code = query.titleCode, code != pinnedTitle {
            parts.append(database.sets.first { $0.titleCode == code }?.titleNameZH ?? code)
        }
        if !query.levels.isEmpty {
            parts.append("Lv" + query.levels.sorted().map(String.init).joined(separator: "/"))
        }
        if !query.colors.isEmpty {
            parts.append(query.colors.map(\.label).joined(separator: "/"))
        }
        if !query.types.isEmpty {
            parts.append(query.types.map(\.label).joined(separator: "/"))
        }
        if !query.triggers.isEmpty { parts.append("判定×\(query.triggers.count)") }
        if !query.traits.isEmpty {
            parts.append(query.traits.sorted().joined(separator: "/"))
        }
        if let source = query.sourceOnly { parts.append(source.label) }
        if query.ownership != .all { parts.append(query.ownership.label) }
        return parts.joined(separator: " · ")
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
                HStack(spacing: Spacing.s8) {
                    ForEach(items) { item in
                        Button {
                            // 切到該作品，關鍵字清掉才看得到整個系列
                            isApplyingSuggestion = true
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
                .padding(.vertical, Spacing.s8)
            }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func suggestionChip(_ item: SearchSuggestion) -> some View {
        HStack(spacing: Spacing.s4 + 1) {
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
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.s12)],
                      spacing: Spacing.s16) {
                ForEach(results) { card in
                    CardGridItemView(card: card, deck: activeDeck) {
                        detailCard = card
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, Spacing.s8)
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
