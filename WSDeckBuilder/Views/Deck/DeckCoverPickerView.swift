import SwiftData
import SwiftUI

/// 從牌組裡挑一張刷版當封面（§4.3）；不選則沿用自動封面
struct DeckCoverPickerView: View {
    @Bindable var deck: Deck
    @Environment(CardDatabase.self) private var database
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private struct Tile: Identifiable {
        let card: Card
        let printing: Printing
        let count: Int
        var id: String { printing.id }
    }

    /// 牌組中實際放了的刷版，依等級→卡號排序
    private var tiles: [Tile] {
        deck.entries
            .filter { $0.count > 0 }
            .compactMap { entry -> Tile? in
                guard let card = database.card(forPrinting: entry.printingID),
                      let printing = database.printing(id: entry.printingID) else { return nil }
                return Tile(card: card, printing: printing, count: entry.count)
            }
            .sorted {
                let l0 = $0.card.cardType == .climax ? 99 : ($0.card.level ?? 0)
                let l1 = $1.card.cardType == .climax ? 99 : ($1.card.level ?? 0)
                return (l0, $0.printing.id) < (l1, $1.printing.id)
            }
    }

    /// 目前生效的封面（含自動挑選的結果）
    private var activePrintingID: String? {
        deck.coverPrinting(database: database)?.id
    }

    private var isAuto: Bool { deck.coverPrintingID.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)],
                          spacing: 14) {
                    ForEach(tiles) { tile in
                        tileView(tile)
                    }
                }
                .padding()
            }
            .overlay {
                if tiles.isEmpty {
                    ContentUnavailableView("牌組是空的",
                                           systemImage: "rectangle.stack.badge.plus",
                                           description: Text("先加入卡片才能選擇封面"))
                }
            }
            .navigationTitle("選擇封面")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { hintBar }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("自動選擇") { setCover(nil) }
                        .disabled(isAuto)
                }
            }
        }
    }

    private var hintBar: some View {
        HStack(spacing: 6) {
            Image(systemName: isAuto ? "wand.and.stars" : "checkmark.seal.fill")
                .foregroundStyle(isAuto ? .secondary : Color.accentColor)
            Text(isAuto ? "目前為自動封面（牌組中等級最高的一張）"
                        : "目前為手動指定的封面")
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func tileView(_ tile: Tile) -> some View {
        let isSelected = tile.printing.id == activePrintingID

        return Button {
            setCover(tile.printing.id)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    CardImageView(printing: tile.printing,
                                  cardName: tile.card.nameZH,
                                  landscape: tile.card.cardType == .climax)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isSelected ? Color.accentColor : .clear,
                                              lineWidth: 3)
                        }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(4)
                    }
                }
                Text(tile.card.nameZH)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(tile.printing.rarity)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// nil = 恢復自動封面
    private func setCover(_ printingID: String?) {
        deck.coverPrintingID = printingID ?? ""
        deck.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
