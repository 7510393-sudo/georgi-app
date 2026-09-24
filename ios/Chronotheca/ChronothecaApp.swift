import SwiftUI

@main
struct ChronothecaApp: App {
    @StateObject private var vault: Vault
    @StateObject private var store: DayStore
    @StateObject private var archive: Archive
    @StateObject private var shell = Shell()
    @Environment(\.scenePhase) private var phase

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
        .onChange(of: phase) { _, now in
            switch now {
            // Уходя с экрана — записать сразу. Запись идёт через полсекунды
            // после последней буквы, и смахнутое приложение этих полсекунд
            // может не дождаться: последние слова пропадали (решение P184).
            case .inactive, .background:
                store.save()
            // Вернувшись — сверить день с диском: пока приложение стояло,
            // запись могли поправить на Mac или на другом устройстве, и
            // старая копия не должна лечь поверх новой (P183).
            case .active:
                store.comeBack()
                archive.reload()
            @unknown default:
                break
            }
        }
    }
}
