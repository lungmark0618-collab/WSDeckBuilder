import SwiftData
import SwiftUI

/// 清單模式的單列（文字為主，§4.3）
struct CardRowView: View {
    let card: Card
    var deck: Deck?
    var onTap: () -> Void

    @Environment(\.modelContext) private var context

    private var countInDeck: Int { deck?.count(of: card) ?? 0 }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    colorBar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.nameZH)
                            .font(.callout)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(card.id)
                                .font(.caption2.monospaced())
                            Text(summary)
                                .font(.caption2)
                            if let trigger = card.trigger {
                                TriggerIconView(trigger: trigger, size: 13)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let deck {
                CountStepper(count: countInDeck) { delta in
                    if delta > 0 {
                        deck.adjust(printingID: card.defaultPrinting.id, by: 1, context: context)
                    } else {
                        for printing in card.printings.reversed()
                        where (deck.entry(forPrinting: printing.id)?.count ?? 0) > 0 {
                            deck.adjust(printingID: printing.id, by: -1, context: context)
                            break
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        switch card.cardType {
        case .character:
            "Lv\(card.level ?? 0)/費\(card.cost ?? 0)/\(card.power.map(String.init) ?? "-")/魂\(card.soul.map(String.init) ?? "-")"
        case .event:
            "事件 Lv\(card.level ?? 0)/費\(card.cost ?? 0)"
        case .climax:
            "CX"
        }
    }

    private var colorBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4, height: 36)
    }

    private var color: Color {
        switch card.color {
        case .yellow: .yellow
        case .green: .green
        case .red: .red
        case .blue: .blue
        }
    }
}
