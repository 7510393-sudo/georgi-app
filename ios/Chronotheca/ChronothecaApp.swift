import SwiftUI

@main
struct ChronothecaApp: App {
    @StateObject private var vault: Vault
    @StateObject private var store: DayStore

    init() {
        let vault = Vault()
        _vault = StateObject(wrappedValue: vault)
        _store = StateObject(wrappedValue: DayStore(vault: vault))
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environmentObject(vault)
                .environmentObject(store)
        }
    }
}
