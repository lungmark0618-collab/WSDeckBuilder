import SwiftUI

struct RootTabView: View {
    @Environment(CardDatabase.self) private var database

    var body: some View {
        TabView {
            CardBrowserView()
                .tabItem { Label("圖鑑", systemImage: "magnifyingglass") }
            DeckListView()
                .tabItem { Label("牌組", systemImage: "books.vertical") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
        .overlay {
            if let error = database.loadError {
                ContentUnavailableView("資料載入失敗",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error))
                .background(.background)
            }
        }
    }
}
