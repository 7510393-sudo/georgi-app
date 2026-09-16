import Foundation

/// Один день: файл плана и файл дневника.
///
/// Держит ровно то, что сейчас на экране, и ничего сверх того. Уходя со дня,
/// пишет на диск; приходя на день — читает с диска. Никакой своей копии данных.
final class DayStore: ObservableObject {

    /// Граница суток: до этого часа день считается вчерашним (решение P17).
    static var boundaryHour = 4

    @Published var date: Date
    @Published var plan: String = ""
    @Published var diary: String = ""

    private let vault: Vault

    init(vault: Vault, date: Date = DayStore.today()) {
        self.vault = vault
        self.date = date
        load()
    }

    static func today(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let shifted = cal.component(.hour, from: now) < boundaryHour
            ? cal.date(byAdding: .day, value: -1, to: now) ?? now
            : now
        return cal.startOfDay(for: shifted)
    }

    func move(by days: Int) {
        save()
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        load()
    }

    func load() {
        plan = DayFile(text: vault.read(.planner, for: date)).body
        diary = DayFile(text: vault.read(.diary, for: date)).body
    }

    func save() {
        guard vault.root != nil else { return }

        var p = DayFile(body: plan)
        p.set("дата", Vault.stamp(date))
        vault.write(p.text, to: .planner, for: date)

        var d = DayFile(body: diary)
        d.set("дата", Vault.stamp(date))
        vault.write(d.text, to: .diary, for: date)
    }

    /// То, что действительно лежит на диске — а не то, что помнит приложение.
    /// Нужно, чтобы проверять обещание: файлы источник, приложение только окно.
    func onDisk() -> String {
        let p = vault.read(.planner, for: date)
        let d = vault.read(.diary, for: date)
        return "\(Vault.Folder.planner.rawValue)\n\n\(p.isEmpty ? "(файла нет)\n" : p)\n"
             + "\(Vault.Folder.diary.rawValue)\n\n\(d.isEmpty ? "(файла нет)\n" : d)"
    }
}
