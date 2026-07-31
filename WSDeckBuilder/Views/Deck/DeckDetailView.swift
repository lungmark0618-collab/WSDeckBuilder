import SwiftData
import SwiftUI

/// 單一牌組編輯，依等級分組；卡表／統計／缺卡切換，卡表可切圖片或清單（§4.3）
struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(CardDatabase.self) private var database
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .cards
    @State private var detailCard: Card?
    @State private var isEditing = false
    @State private var isPickingCover = false
    /// 缺卡頁是否連已收齊的一起顯示
    @State private var showCollected = false
    /// 卡表的顯示方式（與圖鑑分頁各自記憶）
    @AppStorage("deckUsesGrid") private var usesGrid = true

    @Query private var collection: [CollectionEntry]

    private enum Mode: String, CaseIterable {
        case cards = "卡表"
        case stats = "統計"
        case shortage = "缺卡"
    }

    private var shortages: [CollectionStore.Shortage] {
        CollectionStore.shortages(deck: deck, database: database,
                                  index: CollectionStore.index(collection))
    }

    private var countedItems: [DeckValidator.CountedCard] {
        DeckExporter.groupByCard(deck: deck, database: database)
            .map { DeckValidator.CountedCard(card: $0.card, count: $0.count) }
    }

    private var validation: DeckValidator.Result {
        DeckValidator.validate(countedItems)
    }

    var body: some View {
        VStack(spacing: 0) {
            validationHeader
            Picker("模式", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)

            switch mode {
            case .cards:
                if usesGrid { cardGrid } else { cardList }
            case .stats: DeckStatsView(items: countedItems)
            case .shortage: shortageList
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 卡表模式才需要切換圖片／清單
            if mode == .cards {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { usesGrid.toggle() }
                    } label: {
                        Image(systemName: usesGrid ? "list.bullet" : "square.grid.3x3")
                    }
                    .accessibilityLabel(usesGrid ? "改為清單顯示" : "改為圖片顯示")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { actionMenu }
            ToolbarItem(placement: .confirmationAction) {
                if isEditing {
                    Button("完成") {
                        deck.updatedAt = .now
                        try? context.save()
                        withAnimation { isEditing = false }
                    }
                    .fontWeight(.bold)
                } else {
                    Button("編輯") {
                        withAnimation { isEditing = true }
                    }
                }
            }
        }
        .sheet(item: $detailCard) { card in
            // 依畫面上的分區順序帶入，滑動順序才跟看到的一致
            CardDetailSheet(card: card, siblings: orderedCards, deck: deck)
        }
        .sheet(isPresented: $isPickingCover) {
            DeckCoverPickerView(deck: deck)
        }
    }

    // MARK: - 規則驗證列（§4.4.3）

    private var validationHeader: some View {
        HStack(spacing: 8) {
            ruleChip("\(validation.totalCount)/50", ok: validation.totalOK)
            ruleChip("CX \(validation.climaxCount)/8", ok: validation.climaxOK)
            if !validation.namesOK {
                ruleChip("同名超過4張", ok: false, symbol: "exclamationmark.triangle.fill")
            }
            if validation.mixedTitles {
                ruleChip("跨作品混搭", ok: false, symbol: "exclamationmark.triangle.fill",
                         tint: .orange)
            }
            Spacer(minLength: 0)
            if validation.isLegal {
                Label("符合規則", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 9)
        .background {
            ZStack {
                Color(.secondarySystemBackground)
                CardArtBackdrop(printing: deck.coverPrinting(database: database),
                                blur: 20, opacity: 1, saturation: 2.0)
                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.4)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
    }

    /// 深色背景上的規則標籤
    private func ruleChip(_ text: String, ok: Bool,
                          symbol: String? = nil, tint: Color = .red) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.caption2)
            }
            Text(text)
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(ok ? .green : (symbol == nil ? .white : tint))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.black.opacity(0.32), in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    // MARK: - 圖片網格（依等級分區，含張數徽章與快速增減）

    private var cardGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                                  spacing: 12) {
                            // 依刷版分格：1 SR + 3 R 就顯示 SR 與 R 各一格
                            ForEach(printingTiles(for: section), id: \.printing.id) { tile in
                                CardGridItemView(card: tile.card, deck: deck,
                                                 printing: tile.printing,
                                                 editable: isEditing) {
                                    detailCard = tile.card
                                }
                                .contextMenu {
                                    Button {
                                        deck.coverPrintingID = tile.printing.id
                                        deck.updatedAt = .now
                                        try? context.save()
                                    } label: {
                                        Label("設為牌組封面", systemImage: "photo.badge.checkmark")
                                    }
                                    if !deck.coverPrintingID.isEmpty {
                                        Button {
                                            deck.coverPrintingID = ""
                                            try? context.save()
                                        } label: {
                                            Label("恢復自動封面", systemImage: "arrow.uturn.backward")
                                        }
                                    }
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
            .padding(.bottom, 8)
        }
        .overlay {
            if deck.entries.isEmpty {
                ContentUnavailableView("牌組是空的",
                                       systemImage: "rectangle.stack.badge.plus",
                                       description: Text("到「圖鑑」分頁選擇此牌組後按＋加卡"))
            }
        }
    }

    // MARK: - 卡表

    private var cardList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section("\(section.title) (\(section.count))") {
                    ForEach(section.items, id: \.card.id) { item in
                        DeckEntryRowView(
                            deck: deck,
                            card: item.card,
                            totalForName: DeckValidator.nameCount(of: item.card,
                                                                  in: countedItems),
                            editable: isEditing) {
                            detailCard = item.card
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if deck.entries.isEmpty {
                ContentUnavailableView("牌組是空的",
                                       systemImage: "rectangle.stack.badge.plus",
                                       description: Text("到「圖鑑」分頁選擇此牌組後按＋加卡"))
            }
        }
    }

    private struct LevelSection {
        let title: String
        let count: Int
        let items: [DeckExporter.CardCount]
    }

    private struct PrintingTile {
        let card: Card
        let printing: Printing
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

    /// 卡表分區攤平成一串，供詳情頁左右滑動
    private var orderedCards: [Card] {
        sections.flatMap { $0.items.map(\.card) }
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

    // MARK: - 缺卡清單（對照「我的收藏」算出還要收哪些）

    private var shortageList: some View {
        // 收齊的卡會從缺卡清單消失，開著這個才改得回來（例如標錯了）
        let items = showCollected ? allTrackedItems : shortages
        let total = shortages.reduce(0) { $0 + $1.missing }
        return List {
            if items.isEmpty {
                ContentUnavailableView("這副牌都收齊了",
                                       systemImage: "checkmark.seal.fill",
                                       description: Text("牌組內每張卡的擁有數都足夠"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(items) { item in
                        shortageRow(item)
                    }
                } header: {
                    HStack {
                        Text(total > 0 ? "還缺 \(total) 張（共 \(shortages.count) 種）"
                                       : "都收齊了")
                        Spacer()
                        Button(showCollected ? "只看缺的" : "顯示全部") {
                            withAnimation { showCollected.toggle() }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                } footer: {
                    Text("直接在這裡按＋標記入手，或往左滑一次收齊整組。數量記在「我的收藏」，"
                         + "其他牌組共用。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            if mode == .shortage, !shortages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("全部收齊") { fillAll() }
                        .font(.caption)
                }
            }
        }
    }

    /// 牌組內每個刷版的收藏進度（含已收齊的），供「顯示全部」使用
    private var allTrackedItems: [CollectionStore.Shortage] {
        let index = CollectionStore.index(collection)
        return deck.entries
            .compactMap { entry -> CollectionStore.Shortage? in
                guard let card = database.card(forPrinting: entry.printingID),
                      let printing = database.printing(id: entry.printingID) else { return nil }
                return CollectionStore.Shortage(printing: printing, card: card,
                                                needed: entry.count,
                                                owned: index[entry.printingID] ?? 0)
            }
            .sorted { $0.printing.id < $1.printing.id }
    }

    private func shortageRow(_ item: CollectionStore.Shortage) -> some View {
        let done = item.missing == 0
        return HStack(spacing: 10) {
            CardImageView(printing: item.printing,
                          cardName: item.card.nameZH,
                          landscape: item.card.cardType == .climax)
                .frame(width: item.card.cardType == .climax ? 60 : 42)
                .opacity(done ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.card.nameZH)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(done ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(item.printing.rarity).font(.caption2.bold())
                    Text(item.printing.id).font(.caption2.monospaced())
                }
                .foregroundStyle(.secondary)
                if done {
                    Label("已收齊", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("還缺 \(item.missing)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 4)

            // 就地加減，不用再進詳情頁
            VStack(spacing: 2) {
                CountStepper(count: item.owned) { delta in
                    CollectionStore.adjust(printingID: item.printing.id, by: delta,
                                           entries: collection, context: context)
                }
                Text("\(item.owned)/\(item.needed)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { detailCard = item.card }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !done {
                Button {
                    fill(item)
                } label: {
                    Label("一次收齊", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
    }

    /// 把某張補到牌組需要的張數
    private func fill(_ item: CollectionStore.Shortage) {
        guard item.missing > 0 else { return }
        CollectionStore.adjust(printingID: item.printing.id, by: item.missing,
                               entries: collection, context: context)
    }

    private func fillAll() {
        for item in shortages { fill(item) }
    }

    // MARK: - 牌組操作＋匯出（§4.4.5，ShareLink）

    private var actionMenu: some View {
        Menu {
            Section {
                Button {
                    isPickingCover = true
                } label: {
                    Label("選擇封面", systemImage: "photo.badge.checkmark")
                }
                .disabled(deck.entries.isEmpty)
            }
            Section("匯出") {
                ShareLink(item: DeckExporter.simpleText(deck: deck, database: database)) {
                    Label("匯出牌表（簡潔版）", systemImage: "doc.plaintext")
                }
                ShareLink(item: DeckExporter.collectorText(deck: deck, database: database)) {
                    Label("匯出收牌清單（含刷版）", systemImage: "list.bullet.rectangle")
                }
                ShareLink(item: CollectionStore.shortageText(deck: deck, shortages: shortages)) {
                    Label("匯出缺卡清單", systemImage: "cart")
                }
                if let url = DeckExporter.jsonFile(deck: deck) {
                    ShareLink(item: url,
                              preview: SharePreview("\(deck.name).json")) {
                        Label("匯出 JSON 備份（可再匯入）", systemImage: "curlybraces")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
