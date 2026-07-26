import SwiftData
import SwiftUI

/// 單一牌組編輯，依等級分組；卡表/統計切換（§4.3）
struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(CardDatabase.self) private var database
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .list
    @State private var detailCard: Card?

    private enum Mode: String, CaseIterable {
        case list = "卡表"
        case stats = "統計"
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
            case .list: cardList
            case .stats: DeckStatsView(items: countedItems)
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { exportMenu }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    deck.updatedAt = .now
                    try? context.save()
                    dismiss()
                }
                .fontWeight(.bold)
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
            Spacer()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
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
                                                                  in: countedItems)) {
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

    // MARK: - 匯出（§4.4.5，ShareLink）

    private var exportMenu: some View {
        Menu {
            ShareLink(item: DeckExporter.simpleText(deck: deck, database: database)) {
                Label("匯出牌表（簡潔版）", systemImage: "doc.plaintext")
            }
            ShareLink(item: DeckExporter.collectorText(deck: deck, database: database)) {
                Label("匯出收牌清單（含刷版）", systemImage: "list.bullet.rectangle")
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
