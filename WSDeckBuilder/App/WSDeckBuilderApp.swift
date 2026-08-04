import SwiftData
import SwiftUI

@main
struct WSDeckBuilderApp: App {
    @State private var database = CardDatabase()
    @State private var appearance = AppearanceSettings.shared
    @State private var updater = DataUpdater()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(database)
                .environment(appearance)
                .environment(updater)
                .appAppearance(appearance)
                .task {
                    await database.load()
                    // 查更新絕不擋開場：卡表載完、畫面已經能用了才在背景問一次
                    await updater.checkSilently(against: database)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await ImageCache.shared.handleMemoryWarning() }
                }
        }
        .modelContainer(for: [Deck.self, DeckEntry.self, CollectionEntry.self])
    }
}
