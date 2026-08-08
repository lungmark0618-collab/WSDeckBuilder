import SwiftUI

/// 圖鑑分頁頂部：選擇「目前編輯中的牌組」，＋/－直接作用於該牌組（§4.3）
struct ActiveDeckPicker: View {
    let decks: [Deck]
    @Binding var activeDeckUUID: String

    private var activeDeck: Deck? {
        decks.first { $0.uuid.uuidString == activeDeckUUID }
    }

    var body: some View {
        HStack {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
            if decks.isEmpty {
                Text("到「牌組」分頁建立牌組後，可在此直接加卡")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Button("（不選擇牌組）") { activeDeckUUID = "" }
                    ForEach(decks) { deck in
                        Button {
                            activeDeckUUID = deck.uuid.uuidString
                        } label: {
                            if deck.uuid.uuidString == activeDeckUUID {
                                Label(deck.name, systemImage: "checkmark")
                            } else {
                                Text(deck.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeDeck.map { "編輯中：\($0.name)" } ?? "選擇要編輯的牌組")
                            .font(.subheadline)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
            }
            if !decks.isEmpty { Spacer(minLength: 0) }
        }
        .padding(.horizontal)
        .padding(.vertical, Spacing.s8)
        .background(.bar)
    }
}
