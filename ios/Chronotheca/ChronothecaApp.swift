import SwiftUI

@main
struct ChronothecaApp: App {
    @StateObject private var vault: Vault
    @StateObject private var store: DayStore
    @StateObject private var archive: Archive
    @StateObject private var shell = Shell()

    init() {
        let vault = Vault()
        _vault = StateObject(wrappedValue: vault)
        _store = StateObject(wrappedValue: DayStore(vault: vault))
        _archive = StateObject(wrappedValue: Archive(vault: vault))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(archive)
                .environmentObject(shell)
        }
    }
}
