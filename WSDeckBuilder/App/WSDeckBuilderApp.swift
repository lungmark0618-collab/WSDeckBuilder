import SwiftData
import SwiftUI

@main
struct WSDeckBuilderApp: App {
    @State private var database = CardDatabase()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(database)
                .onAppear {
                    if database.cards.isEmpty { database.load() }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    Task { await ImageCache.shared.handleMemoryWarning() }
                }
        }
        .modelContainer(for: [Deck.self, DeckEntry.self])
    }
}
