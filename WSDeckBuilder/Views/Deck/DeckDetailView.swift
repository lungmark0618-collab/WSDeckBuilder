import SwiftData
import SwiftUI

/// 單一牌組編輯，依等級分組；卡表/統計切換（§4.3）
struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(CardDatabase.self) private var database
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .grid
    @State private var detailCard: Card?
    @State private var isEditing = false

    @Query private var collection: [CollectionEntry]

    private enum Mode: String, CaseIterable {
        case grid = "圖片"
        case list = "清單"
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
            case .grid: cardGrid
            case .list: cardList
            case .stats: DeckStatsView(items: countedItems)
            case .shortage: shortageList
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { exportMenu }
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
            CardDetailSheet(card: card, deck: deck)
        }
    }

    // MARK: - 規則驗證列（§4.4.3）

    private var validationHeader: some View {
        HStack(spacing: 14) {
            Label("\(validation.totalCount)/50",
                  systemImage: validation.totalOK ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(validation.totalOK ? .green : .red)
            Label("CX \(validation.climaxCount)/8",
                  systemImage: validation.climaxOK ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(validation.climaxOK ? .green : .red)
            if !validation.namesOK {
                Label("同名超過4張", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if validation.mixedTitles {
                Label("跨作品混搭", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
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
        let items = shortages
        let total = items.reduce(0) { $0 + $1.missing }
        return List {
            if items.isEmpty {
                ContentUnavailableView("這副牌都收齊了",
                                       systemImage: "checkmark.seal.fill",
                                       description: Text("牌組內每張卡的擁有數都足夠"))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            CardImageView(printing: item.printing,
                                          cardName: item.card.nameZH,
                                          landscape: item.card.cardType == .climax)
                                .frame(width: item.card.cardType == .climax ? 64 : 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.card.nameZH).font(.callout).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(item.printing.rarity).font(.caption2.bold())
                                    Text(item.printing.id).font(.caption2.monospaced())
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("缺 \(item.missing)")
                                    .font(.callout.monospacedDigit().bold())
                                    .foregroundStyle(.red)
                                Text("\(item.owned)/\(item.needed)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { detailCard = item.card }
                    }
                } header: {
                    Text("還缺 \(total) 張（共 \(items.count) 種）")
                } footer: {
                    Text("依「我的收藏」記錄計算。到卡片詳情頁的「我的收藏」可調整擁有張數。")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 匯出（§4.4.5，ShareLink）

    private var exportMenu: some View {
        Menu {
            ShareLink(item: DeckExporter.simpleText(deck: deck, database: database)) {
                Label("匯出牌表（簡潔版）", systemImage: "doc.plaintext")
            }
            ShareLink(item: DeckExporter.collectorText(deck: deck, database: database)) {
                Label("匯出收牌清單（含刷版）", systemImage: "list.bullet.rectangle")
            }
            ShareLink(item: CollectionStore.shortageText(deck: deck, shortages: shortages)) {
                Label("匯出缺卡清單", systemImage: "cart")
            }
            ShareLink(item: DeckExporter.json(deck: deck),
                      preview: SharePreview("\(deck.name).json")) {
                Label("匯出 JSON 備份", systemImage: "curlybraces")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
}
