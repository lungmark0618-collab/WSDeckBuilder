import SwiftData
import SwiftUI

/// 點卡片彈出：大圖 + 日中對照 + 刷版切換（§4.3）；
/// 關聯卡片（羈絆／CX連動指名）可直接推進去看
struct CardDetailSheet: View {
    let card: Card
    var deck: Deck?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CardDetailContent(card: card, deck: deck)
                .navigationDestination(for: Card.self) { related in
                    CardDetailContent(card: related, deck: deck)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

/// 詳情內容本體（可被 sheet 直接顯示，也可被 NavigationLink 推進）
struct CardDetailContent: View {
    let card: Card
    var deck: Deck?

    @Environment(CardDatabase.self) private var database
    @Environment(\.modelContext) private var context
    @State private var selectedPrintingID: String = ""

    private var selectedPrinting: Printing {
        card.printings.first { $0.id == selectedPrintingID } ?? card.defaultPrinting
    }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CardImageView(printing: selectedPrinting, cardName: card.nameZH,
                                  landscape: card.cardType == .climax,
                                  animatedFoil: true)
                        .frame(maxWidth: card.cardType == .climax ? 360 : 280)
                        .frame(maxWidth: .infinity)

                    if card.printings.count > 1 {
                        Picker("刷版", selection: $selectedPrintingID) {
                            ForEach(card.printings) { printing in
                                Text(printing.rarity).tag(printing.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    header
                    statsRow

                    if card.textZH.isEmpty {
                        Text("（無能力文字）")
                            .foregroundStyle(.secondary)
                    } else if card.textZH == card.textJP {
                        // 尚未翻譯的系列：只顯示一份日文，不重複
                        abilitySection(title: "卡片文字（日文）", lines: card.textLinesJP)
                        Label("此卡尚未翻譯，暫以日文顯示",
                              systemImage: "character.book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        abilitySection(title: "能力（繁中）", lines: card.textLinesZH)
                        abilitySection(title: "原文（日文）", lines: card.textLinesJP)
                        if card.translationStatus == .machine {
                            Label("此卡翻譯尚未人工校對",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    relationsSection

                    if let deck { deckControls(deck) }
                }
                .padding()
        }
        .navigationTitle(selectedPrinting.id)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedPrintingID = card.defaultPrinting.id }
    }

    // MARK: - 關聯卡片（羈絆／CX連動／被指名）

    @ViewBuilder
    private var relationsSection: some View {
        let relations = database.relations(for: card)
        if !relations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("關聯卡片").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(relations) { relation in
                            NavigationLink(value: relation.card) {
                                relationTile(relation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func relationTile(_ relation: CardRelation) -> some View {
        VStack(spacing: 4) {
            CardImageView(printing: relation.card.defaultPrinting,
                          cardName: relation.card.nameZH,
                          landscape: relation.card.cardType == .climax)
                .frame(width: relation.card.cardType == .climax ? 118 : 84)
            Label(relation.kind.label, systemImage: relation.kind.symbol)
                .font(.caption2)
                .foregroundStyle(relation.kind == .referencedBy ? .secondary : .primary)
            Text(relation.card.nameZH)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.nameZH).font(.title3.bold())
            Text(card.nameJP).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                tag(card.cardType.label)
                tag(card.color.label)
                tag(selectedPrinting.rarity)
                tag(card.source.label)
                ForEach(card.traitsZH, id: \.self) { trait in
                    tag("《\(trait)》")
                }
            }
            .font(.caption)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            stat("等級", card.level.map(String.init) ?? "-")
            stat("費用", card.cost.map(String.init) ?? "-")
            stat("攻擊力", card.power.map(String.init) ?? "-")
            stat("魂傷", card.soul.map(String.init) ?? "-")
            VStack(spacing: 2) {
                Text("判定").font(.caption2).foregroundStyle(.secondary)
                if let trigger = card.trigger {
                    TriggerIconView(trigger: trigger)
                        .frame(height: 20)
                } else {
                    Text("-").font(.callout.monospacedDigit().bold())
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity)
    }

    private func abilitySection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                CardTextRenderer.render(line)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func deckControls(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("加入「\(deck.name)」")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(card.printings) { printing in
                let count = deck.entry(forPrinting: printing.id)?.count ?? 0
                HStack {
                    Text(printing.rarity)
                        .font(.callout.bold())
                        .frame(width: 44, alignment: .leading)
                    Text(printing.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    CountStepper(count: count) { delta in
                        deck.adjust(printingID: printing.id, by: delta, context: context)
                    }
                }
            }
            let total = deck.count(of: card)
            if total > 0 {
                Text("合計 \(total) / \(DeckValidator.nameLimit) 上限")
                    .font(.caption)
                    .foregroundStyle(total > DeckValidator.nameLimit ? .red : .secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// ＋/－按鈕（44pt 觸控區，§4.4.2）
struct CountStepper: View {
    let count: Int
    let adjust: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { adjust(-1) } label: {
                Image(systemName: "minus.circle")
                    .frame(width: 44, height: 44)
            }
            .disabled(count == 0)
            Text("\(count)")
                .font(.body.monospacedDigit().bold())
                .frame(minWidth: 24)
            Button { adjust(+1) } label: {
                Image(systemName: "plus.circle")
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.borderless)
    }
}
