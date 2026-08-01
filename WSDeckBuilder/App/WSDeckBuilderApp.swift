import SwiftData
import SwiftUI

@main
struct WSDeckBuilderApp: App {
    @State private var database = CardDatabase()
    @State private var appearance = AppearanceSettings.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(database)
                .environment(appearance)
                .appAppearance(appearance)
                .task { await database.load() }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await ImageCache.shared.handleMemoryWarning() }
                }
        }
        .modelContainer(for: [Deck.self, DeckEntry.self, CollectionEntry.self])
    }
}
