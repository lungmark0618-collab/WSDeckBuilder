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
            } else if database.isLoading {
                // 蓋住空的分頁，不然開啟後會先看到一片空白才跳出卡片
                loadingScreen
            }
        }
    }

    private var loadingScreen: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("載入卡片資料…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
