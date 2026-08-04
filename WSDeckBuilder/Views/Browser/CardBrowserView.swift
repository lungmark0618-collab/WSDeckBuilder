import SwiftUI

/// 圖鑑分頁的外殼。內容全在 `CardCatalogView`，這裡只負責導覽堆疊：
/// 作品選單 → 單一作品（或不分作品的全部卡片）。
struct CardBrowserView: View {
    var body: some View {
        NavigationStack {
            CardCatalogView(route: .root)
                // 只在根層宣告一次；被推進去的畫面裡沒有 NavigationLink
                .navigationDestination(for: CatalogRoute.self) { route in
                    CardCatalogView(route: route)
                }
        }
    }
}
