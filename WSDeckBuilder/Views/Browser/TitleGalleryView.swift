import SwiftUI

/// 圖鑑的第一層：先選作品，再看卡。
///
/// 3400 多張卡一次全攤開沒人找得到東西，而使用者心裡的第一個問題幾乎都是
/// 「我要看哪部作品」。搜尋列仍在最上面，但這裡打字是在篩「作品」清單本身
/// （含容錯），不會直接跳去卡片結果——選作品跟找卡片刻意分成兩段搜尋。
struct TitleGalleryView: View {
    let sets: [CardSetMeta]
    let totalCount: Int
    /// 目前是否正在用關鍵字篩選作品；篩完是空的時候才顯示「沒有符合的作品」
    var isFiltering: Bool = false

    /// 卡多的作品排前面——會反覆翻的就是那幾部，照代號排等於隨機順序
    private var ordered: [CardSetMeta] {
        sets.sorted { $0.cardCount > $1.cardCount }
    }

    var body: some View {
        ScrollView {
            if ordered.isEmpty, isFiltering {
                noMatchHint
                    .padding(.horizontal)
                    .padding(.top, Spacing.s32)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: Spacing.s12)],
                          spacing: Spacing.s12) {
                    ForEach(ordered, id: \.titleCode) { set in
                        NavigationLink(value: CatalogRoute.title(set.titleCode)) {
                            tile(set)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            allCardsRow
                .padding(.horizontal)
                .padding(.top, Spacing.s12)
        }
        .padding(.top, Spacing.s8)
        .padding(.bottom, Spacing.s8)
    }

    /// 篩不到符合的作品名稱時，還是留一條路到「不分作品瀏覽全部卡片」，
    /// 免得使用者以為卡表裡真的沒有這個東西
    private var noMatchHint: some View {
        VStack(spacing: Spacing.s8) {
            Image(systemName: "questionmark.folder")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("沒有符合的作品")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s24)
    }

    private func tile(_ set: CardSetMeta) -> some View {
        let color = TitlePalette.accent(for: set.titleCode)
        return VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(set.titleNameZH)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(set.titleNameJP)
                .font(.caption2)
                .lineLimit(1)
                .opacity(0.85)
            Spacer(minLength: Spacing.s4 + 2)
            HStack(alignment: .firstTextBaseline) {
                Text(set.titleCode)
                    .font(.caption2.monospaced())
                    .opacity(0.8)
                Spacer(minLength: Spacing.s4)
                Text("\(set.cardCount)")
                    .font(.caption.bold().monospacedDigit())
            }
        }
        .foregroundStyle(.white)
        // 卡片內距至少 16px——原本 12px 在小螢幕上文字幾乎貼著邊
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 108, alignment: .topLeading)
        .background {
            LinearGradient(colors: [color, color.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.mid, style: .continuous))
        // 讓色塊像「疊在背景上的卡片」而不是畫在背景裡的色塊
        .comfortShadow(.card)
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
            .padding(.horizontal, Spacing.s16)
            .padding(.vertical, Spacing.s12)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: Radius.mid, style: .continuous))
            .comfortShadow(.card)
        }
        .buttonStyle(.plain)
    }
}
