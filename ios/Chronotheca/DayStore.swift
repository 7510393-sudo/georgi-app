import Foundation

/// Один день: файл плана и файл дневника.
///
/// Держит ровно то, что сейчас на экране, и ничего сверх того. Уходя со дня,
/// пишет на диск; приходя на день — читает с диска. Никакой своей копии данных.
final class DayStore: ObservableObject {

    /// День в прошлом: план такого дня выцветает целиком (решение P16),
    /// а дневник остаётся контрастным в любом возрасте.
    var isPast: Bool { date < DayStore.today() }

    /// Граница суток: до этого часа день считается вчерашним (решение P17).
    static var boundaryHour = 4

    @Published var date: Date
    @Published var planRows: [PlanRow] = []
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
        // Пустые дела убираются только при уходе со дня: иначе новое дело
        // исчезает, едва человек коснулся другого места на экране.
        planRows.removeAll { $0.isTask && $0.text.trimmingCharacters(in: .whitespaces).isEmpty
                             && $0.details.isEmpty }
        save()
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
        load()
    }

    func load() {
        planRows = Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body)
        diary = DayFile(text: vault.read(.diary, for: date)).body
    }

    func save() {
        guard vault.root != nil else { return }

        var p = DayFile(body: Plan.body(from: planRows))
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
