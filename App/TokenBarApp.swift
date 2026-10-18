import SwiftUI

@main
struct TokenBarApp: App {
    @StateObject private var store = QuotaStore.shared

    var body: some Scene {
        WindowGroup {
            DashboardView(store: store)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "tokenbar", url.host == "refresh" else { return }
                    Task { await store.refreshAll() }
                }
        }
    }
}
