import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// 把牌組畫成一張圖分享，圖上帶 QR 讓對方掃回牌組（§4.4.5 延伸）
enum DeckImageExporter {

    // MARK: - 可攜載荷

    /// 圖片裡帶的牌組資料。刻意用純文字而非 JSON：
    /// QR 的容量有限，而且掃出來的內容人眼可讀，出事時看得出哪裡壞掉。
    ///
    ///     WSD1|牌組名|BD/W54-001:4;BD/W54-002:3
    enum Payload {
        static let prefix = "WSD1"

        static func encode(deck: Deck) -> String {
            let entries = deck.entries
                .sorted { $0.printingID < $1.printingID }
                .map { "\($0.printingID):\($0.count)" }
                .joined(separator: ";")
            // 牌組名可能含分隔字元，換掉以免解析時被切斷
            let safeName = deck.name
                .replacingOccurrences(of: "|", with: "／")
                .replacingOccurrences(of: "\n", with: " ")
            return "\(prefix)|\(safeName)|\(entries)"
        }

        /// 回傳 nil 表示不是本 App 的載荷，交給其他解析器去試
        static func decode(_ text: String) -> DeckImporter.Parsed? {
            let parts = text.split(separator: "|", maxSplits: 2,
                                   omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == prefix else { return nil }
            var parsed = DeckImporter.Parsed(name: String(parts[1]))
            for chunk in parts[2].split(separator: ";") {
                let kv = chunk.split(separator: ":")
                guard kv.count == 2, let count = Int(kv[1]) else { continue }
                parsed.entries.append((String(kv[0]), count))
            }
            return parsed.entries.isEmpty ? nil : parsed
        }
    }

    // MARK: - QR

    /// 錯誤更正用 M：容得下這種長度的載荷，被裁到或反光時也還讀得回來
    static func qrImage(from text: String, scale: CGFloat = 8) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: .init(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 出圖

    /// 回傳暫存 PNG 的位置，交給 ShareLink
    @MainActor
    static func imageFile(deck: Deck, database: CardDatabase,
                          images: [String: UIImage]) -> URL? {
        let view = DeckImageSheet(deck: deck, database: database, images: images,
                                  qr: qrImage(from: Payload.encode(deck: deck)))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.uiImage,
              let data = image.pngData() else { return nil }
        let safeName = deck.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "deck" : safeName).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// 匯出圖的版面：標題 + 依等級分組的卡圖 + 右下角 QR
private struct DeckImageSheet: View {
    let deck: Deck
    let database: CardDatabase
    /// 刷版卡號 → 已快取的卡圖。沒有的就畫佔位，不在出圖時連網
    let images: [String: UIImage]
    let qr: UIImage?

    private var grouped: [DeckExporter.CardCount] {
        DeckExporter.groupByCard(deck: deck, database: database)
    }

    /// 欄數跟著卡種數走。固定 8 欄的話，只有幾種卡的牌組右半邊會空一大片
    private var columnCount: Int { min(8, max(4, grouped.count)) }
    private var sheetWidth: CGFloat {
        CGFloat(columnCount) * 96 + CGFloat(columnCount - 1) * 8 + 48
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8),
                                     count: columnCount),
                      alignment: .leading, spacing: 8) {
                ForEach(grouped, id: \.card.id) { item in
                    tile(item)
                }
            }
            footer
        }
        .padding(24)
        .frame(width: sheetWidth)
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(deck.name).font(.title2.bold())
            Spacer()
            Text("\(deck.totalCount) 張")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private static let cardWidth: CGFloat = 96
    private static let portraitHeight: CGFloat = 133

    private func tile(_ item: DeckExporter.CardCount) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .bottomTrailing) {
                art(item)
                // 張數不跟著旋轉，永遠正著貼在格子右下角
                Text("×\(item.count)")
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(3)
            }
            .frame(width: Self.cardWidth, height: Self.portraitHeight)
            Text(item.card.id)
                .font(.system(size: 7).monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// CX 是橫向卡。照原方向縮到同寬會比旁邊矮一截，改成轉 90° 填滿同一格，
    /// 尺寸就跟其他卡一致，看起來也像牌桌上橫置的樣子。
    private func art(_ item: DeckExporter.CardCount) -> some View {
        let isClimax = item.card.cardType == .climax
        let w = isClimax ? Self.portraitHeight : Self.cardWidth
        let h = isClimax ? Self.cardWidth : Self.portraitHeight

        return Group {
            if let image = images[item.card.defaultPrinting.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(.secondarySystemBackground))
                    .overlay {
                        Text(item.card.nameZH)
                            .font(.system(size: 7))
                            .lineLimit(3)
                            .padding(2)
                    }
            }
        }
        .frame(width: w, height: h)
        .clipped()
        .rotationEffect(.degrees(isClimax ? 90 : 0))
        // 轉完再宣告佔位，格線才對得齊
        .frame(width: Self.cardWidth, height: Self.portraitHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("用 WSDeckBuilder 掃這個 QR 就能匯入這副牌組")
                    .font(.caption)
                if !deck.note.isEmpty {
                    Text(deck.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 110, height: 110)
            }
        }
    }
}
