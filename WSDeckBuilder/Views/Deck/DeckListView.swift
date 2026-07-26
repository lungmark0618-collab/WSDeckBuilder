import SwiftData
import SwiftUI

/// 牌組分頁：牌組列表、新增/刪除/重新命名（§4.3）
struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Environment(CardDatabase.self) private var database
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @AppStorage("activeDeckUUID") private var activeDeckUUID: String = ""

    @State private var renamingDeck: Deck?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(decks) { deck in
                    NavigationLink(value: deck.uuid) {
                        row(deck)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(deck)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                        Button {
                            renamingDeck = deck
                            newName = deck.name
                        } label: {
                            Label("重新命名", systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle("牌組")
            .navigationDestination(for: UUID.self) { uuid in
                if let deck = decks.first(where: { $0.uuid == uuid }) {
                    DeckDetailView(deck: deck)
                }
            }
            .toolbar {
                Button {
                    addDeck()
                } label: {
                    Image(systemName: "plus")
                }
            }
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView("還沒有牌組",
                                           systemImage: "square.stack.3d.up.slash",
                                           description: Text("點右上角＋建立第一副牌組"))
                }
            }
            .alert("重新命名", isPresented: .init(
                get: { renamingDeck != nil },
                set: { if !$0 { renamingDeck = nil } })) {
                TextField("牌組名稱", text: $newName)
                Button("取消", role: .cancel) {}
                Button("確定") {
                    if let deck = renamingDeck, !newName.isEmpty {
                        deck.name = newName
                        deck.updatedAt = .now
                    }
                }
            }
        }
    }

    private func row(_ deck: Deck) -> some View {
        let items = deck.entries.compactMap { entry in
            database.card(forPrinting: entry.printingID)
                .map { DeckValidator.CountedCard(card: $0, count: entry.count) }
        }
        let result = DeckValidator.validate(items)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(deck.name).font(.headline)
                if deck.uuid.uuidString == activeDeckUUID {
                    Text("編輯中")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Text("\(result.totalCount)/50")
                    .foregroundStyle(result.totalOK ? .green : .red)
                Text("CX \(result.climaxCount)/8")
                    .foregroundStyle(result.climaxOK ? .green : .red)
                if result.isLegal {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            .font(.caption.monospacedDigit())
        }
    }

    private func addDeck() {
        let deck = Deck(name: "新牌組 \(decks.count + 1)")
        context.insert(deck)
        activeDeckUUID = deck.uuid.uuidString
    }

    private func delete(_ deck: Deck) {
        if deck.uuid.uuidString == activeDeckUUID { activeDeckUUID = "" }
        context.delete(deck)
    }
}
