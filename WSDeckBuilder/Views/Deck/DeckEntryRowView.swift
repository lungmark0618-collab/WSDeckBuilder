import SwiftData
import SwiftUI

/// 單列：總張數 + 可展開的刷版明細（§4.4.2）
struct DeckEntryRowView: View {
    let deck: Deck
    let card: Card
    /// 同名（跨卡號、跨刷版）合計，供 4 張上限標紅
    let totalForName: Int
    /// false = 純瀏覽（隱藏＋/－與刪除）
    var editable = true
    var onTap: () -> Void

    @Environment(\.modelContext) private var context
    @State private var expanded = false

    private var overLimit: Bool { totalForName > DeckValidator.nameLimit }
    private var cardTotal: Int { deck.count(of: card) }

    /// 未展開時的小標籤，如 RR×2 SR×1
    private var raritySummary: String {
        card.printings.compactMap { printing in
            let count = deck.entry(forPrinting: printing.id)?.count ?? 0
            return count > 0 ? "\(printing.rarity)×\(count)" : nil
        }.joined(separator: " ")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            printingRows
        } label: {
            label
        }
        .swipeActions(edge: .trailing) {
            if editable {
                Button(role: .destructive) {
                    for printing in card.printings {
                        if let entry = deck.entry(forPrinting: printing.id) {
                            deck.adjust(printingID: printing.id, by: -entry.count,
                                        context: context)
                        }
                    }
                } label: {
                    Label("移除", systemImage: "trash")
                }
            }
        }
    }

    private var label: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.nameZH)
                        .font(.callout)
                        .foregroundStyle(overLimit ? .red : .primary)
                    Text(raritySummary.isEmpty ? card.id : raritySummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("×\(cardTotal)")
                    .font(.body.monospacedDigit().bold())
                    .foregroundStyle(overLimit ? .red : .primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var printingRows: some View {
        ForEach(card.printings) { printing in
            let count = deck.entry(forPrinting: printing.id)?.count ?? 0
            HStack {
                Text(printing.rarity)
                    .font(.caption.bold())
                    .frame(width: 40, alignment: .leading)
                Text(printing.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if editable {
                    CountStepper(count: count) { delta in
                        deck.adjust(printingID: printing.id, by: delta, context: context)
                    }
                } else {
                    Text("×\(count)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(count > 0 ? .primary : .tertiary)
                }
            }
            // 長按轉換刷版：1 張直接換稀有度，免一減一加（§4.4.2）
            .contextMenu {
                if editable, count > 0, card.printings.count > 1 {
                    ForEach(card.printings.filter { $0.id != printing.id }) { target in
                        Button("轉換 1 張為 \(target.rarity)（\(target.id)）") {
                            deck.convert(from: printing.id, to: target.id, context: context)
                        }
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 16))
    }
}
