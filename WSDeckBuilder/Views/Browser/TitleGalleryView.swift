import SwiftUI

/// 圖鑑的第一層：先選作品，再看卡。
///
/// 3400 多張卡一次全攤開沒人找得到東西，而使用者心裡的第一個問題幾乎都是
/// 「我要看哪部作品」。搜尋列仍在最上面，想跳過這一層就直接打字。
struct TitleGalleryView: View {
    let sets: [CardSetMeta]
    let totalCount: Int

    /// 卡多的作品排前面——會反覆翻的就是那幾部，照代號排等於隨機順序
    private var ordered: [CardSetMeta] {
        sets.sorted { $0.cardCount > $1.cardCount }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)],
                      spacing: 12) {
                ForEach(ordered, id: \.titleCode) { set in
                    NavigationLink(value: CatalogRoute.title(set.titleCode)) {
                        tile(set)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            allCardsRow
                .padding(.horizontal)
                .padding(.top, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func tile(_ set: CardSetMeta) -> some View {
        let color = TitlePalette.accent(for: set.titleCode)
        return VStack(alignment: .leading, spacing: 3) {
            Text(set.titleNameZH)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(set.titleNameJP)
                .font(.caption2)
                .lineLimit(1)
                .opacity(0.85)
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline) {
                Text(set.titleCode)
                    .font(.caption2.monospaced())
                    .opacity(0.8)
                Spacer(minLength: 4)
                Text("\(set.cardCount)")
                    .font(.caption.bold().monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 104, alignment: .topLeading)
        .background {
            LinearGradient(colors: [color, color.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 不分作品瀏覽仍留一條路，只是不擺在最上面搶走「先選作品」的主線
    private var allCardsRow: some View {
        NavigationLink(value: CatalogRoute.allCards) {
            HStack {
                Image(systemName: "square.stack.3d.up")
                Text("不分作品瀏覽全部卡片")
                Spacer()
                Text("\(totalCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
