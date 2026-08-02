import PhotosUI
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
    @State private var showCreateAlert = false
    @State private var createName = ""
    @State private var showFileImporter = false
    @State private var showPasteSheet = false
    @State private var pastedText = ""
    @State private var importResult: DeckImporter.Result?
    @State private var importError: String?
    /// 從相簿挑的牌組圖片，掃圖上的 QR 匯入
    @State private var showPhotoPicker = false
    @State private var pickedImageItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                ForEach(decks) { deck in
                    ZStack {
                        // NavigationLink 的預設樣式會壓過自訂卡片，藏起來只留行為
                        NavigationLink(value: deck.uuid) { EmptyView() }
                            .opacity(0)
                        row(deck)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
            .listStyle(.plain)
            .navigationTitle("牌組")
            .navigationDestination(for: UUID.self) { uuid in
                if let deck = decks.first(where: { $0.uuid == uuid }) {
                    DeckDetailView(deck: deck)
                }
            }
            .toolbar {
                Menu {
                    Button {
                        createName = "新牌組 \(decks.count + 1)"
                        showCreateAlert = true
                    } label: {
                        Label("新增空牌組", systemImage: "plus")
                    }
                    Divider()
                    // PhotosPicker 直接放在 Menu 裡按了不會彈出，
                    // 要由選單設旗標、picker 掛在畫面上才會出現
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("掃牌組圖片匯入", systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("從檔案匯入", systemImage: "folder")
                    }
                    Button {
                        pastedText = ""
                        showPasteSheet = true
                    } label: {
                        Label("貼上牌表文字匯入", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.json, .plainText, .text]) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showPasteSheet) { pasteSheet }
            .photosPicker(isPresented: $showPhotoPicker,
                          selection: $pickedImageItem, matching: .images)
            .task(id: pickedImageItem) { await importPickedImage() }
            .alert("匯入完成", isPresented: .init(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } })) {
                Button("好") {}
            } message: {
                if let result = importResult {
                    Text(importMessage(result))
                }
            }
            .alert("匯入失敗", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } })) {
                Button("好") {}
            } message: {
                Text(importError ?? "")
            }
            .alert("新增牌組", isPresented: $showCreateAlert) {
                TextField("牌組名稱", text: $createName)
                Button("取消", role: .cancel) {}
                Button("建立") { addDeck(named: createName) }
            } message: {
                Text("建立後到「圖鑑」分頁選擇此牌組即可加卡，所有變更都會自動儲存")
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
                        try? context.save()
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
        let cover = deck.coverPrinting(database: database)
        let isActive = deck.uuid.uuidString == activeDeckUUID

        return HStack(spacing: 14) {
            // 封面：卡片本身就是最好的識別，給它足夠份量
            Group {
                if let cover {
                    CardImageView(printing: cover, cardName: deck.name)
                        .frame(width: 66)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                        .frame(width: 66, height: 92)
                        .overlay {
                            Image(systemName: "rectangle.stack")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 7, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(deck.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    if isActive {
                        Text("編輯中")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.9), in: Capsule())
                    }
                }

                // 作品名稱：多系列混用時一眼分辨這是哪副牌
                if let title = titleName(for: deck) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    statusChip("\(result.totalCount)/50", ok: result.totalOK)
                    statusChip("CX \(result.climaxCount)/8", ok: result.climaxOK)
                    if result.isLegal {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                    } else if !result.namesOK {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                    }
                }

                colorBar(for: deck, total: result.totalCount)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(14)
        .background {
            ZStack {
                // 底色先鋪滿，卡圖載入前後都不會露出空白
                Color(.secondarySystemBackground)
                CardArtBackdrop(printing: cover, blur: 22, opacity: 1, saturation: 2.1)
                // 文字那側壓深，右側留亮，白字讀得清楚又保得住卡面色調
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.62), location: 0),
                    .init(color: .black.opacity(0.45), location: 0.55),
                    .init(color: .black.opacity(0.22), location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.9)
                                       : .white.opacity(0.12),
                              lineWidth: isActive ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
    }

    /// 深色卡面上的狀態標籤：達標亮綠，未達標維持中性
    private func statusChip(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(ok ? .green : .white.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }
    }

    /// 牌組主要作品（取張數最多的），空牌組回傳 nil
    private func titleName(for deck: Deck) -> String? {
        var counts: [String: Int] = [:]
        for entry in deck.entries {
            if let card = database.card(forPrinting: entry.printingID),
               let code = database.titleCode(of: card) {
                counts[code, default: 0] += entry.count
            }
        }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let name = database.sets.first { $0.titleCode == top }?.titleNameZH
        // 跨作品混搭時標示出來，免得以為只有一個系列
        return counts.count > 1 ? name.map { "\($0) 等 \(counts.count) 個作品" } : name
    }

    /// 顏色比例條 + 進度感：底槽表示 50 張，填滿的部分才是已放的卡
    private func colorBar(for deck: Deck, total: Int) -> some View {
        var counts: [CardColor: Int] = [:]
        for entry in deck.entries {
            if let card = database.card(forPrinting: entry.printingID) {
                counts[card.color, default: 0] += entry.count
            }
        }
        let deckSize = max(DeckValidator.deckSize, 1)
        let filled = min(CGFloat(total) / CGFloat(deckSize), 1)
        let colorTotal = max(counts.values.reduce(0, +), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.35))
                HStack(spacing: 1.5) {
                    ForEach(CardColor.allCases) { color in
                        if let count = counts[color], count > 0 {
                            Capsule()
                                .fill(swiftUIColor(color).gradient)
                                .frame(width: max(geo.size.width * filled
                                       * CGFloat(count) / CGFloat(colorTotal) - 1.5, 2))
                        }
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
        }
        .frame(height: 7)
        .opacity(deck.entries.isEmpty ? 0 : 1)
    }

    private func swiftUIColor(_ color: CardColor) -> Color {
        switch color {
        case .yellow: .yellow
        case .green: .green
        case .red: .red
        case .blue: .blue
        }
    }

    // MARK: - 匯入

    private var pasteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("把匯出的牌表或 JSON 貼在這裡")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $pastedText)
                    .font(.callout.monospaced())
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 8))
                Text("支援本 App 匯出的 JSON、簡潔版牌表、收牌清單。純文字牌表會以普卡刷版匯入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("貼上匯入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showPasteSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("匯入") {
                        showPasteSheet = false
                        importText(pastedText)
                    }
                    .fontWeight(.bold)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            // 從「檔案」App 選來的檔案需要先取得存取權
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                importText(text)
            } catch {
                importError = "無法讀取檔案：\(error.localizedDescription)"
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func importPickedImage() async {
        guard let item = pickedImageItem else { return }
        defer { pickedImageItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                importError = "無法讀取這張圖片。"
                return
            }
            let parsed = try DeckImageImporter.parse(image: image)
            let result = try DeckImporter.createDeck(
                from: parsed, database: database,
                existingNames: decks.map(\.name), context: context)
            activeDeckUUID = result.deck.uuid.uuidString
            importResult = result
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importText(_ text: String) {
        do {
            let parsed = try DeckImporter.parse(text)
            let result = try DeckImporter.createDeck(
                from: parsed, database: database,
                existingNames: decks.map(\.name), context: context)
            activeDeckUUID = result.deck.uuid.uuidString
            importResult = result
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importMessage(_ result: DeckImporter.Result) -> String {
        var lines = ["已建立「\(result.deck.name)」",
                     "匯入 \(result.importedCards) 張（\(result.matchedKinds) 種）"]
        if !result.skipped.isEmpty {
            let shown = result.skipped.prefix(5).joined(separator: "、")
            lines.append("略過 \(result.skipped.count) 個查不到的卡號：\(shown)"
                         + (result.skipped.count > 5 ? "…" : ""))
        }
        return lines.joined(separator: "\n")
    }

    private func addDeck(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let deck = Deck(name: trimmed.isEmpty ? "新牌組 \(decks.count + 1)" : trimmed)
        context.insert(deck)
        try? context.save()
        activeDeckUUID = deck.uuid.uuidString
    }

    private func delete(_ deck: Deck) {
        if deck.uuid.uuidString == activeDeckUUID { activeDeckUUID = "" }
        context.delete(deck)
        try? context.save()
    }
}
