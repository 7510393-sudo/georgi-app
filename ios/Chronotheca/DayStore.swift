import Foundation

/// Один день: файл плана и файл дневника.
///
/// Держит ровно то, что сейчас на экране, и ничего сверх того. Уходя со дня,
/// пишет на диск; приходя на день — читает с диска. Никакой своей копии данных.
final class DayStore: ObservableObject {

    /// День в прошлом: план такого дня выцветает целиком (решение P16),
    /// а дневник остаётся контрастным в любом возрасте.
    var isPast: Bool { date < DayStore.today() }

    /// День ещё не наступил.
    var isFuture: Bool { date > DayStore.today() }

    /// План живёт вперёд: на сегодня и на любой будущий день дела заводятся
    /// свободно — ради этого планировщик и нужен. Прошедший день закрыт:
    /// задним числом план не переписывают.
    var canEditPlan: Bool { !isPast }

    /// Дневник живёт назад: вчерашнее дописывают и через неделю (решение P63).
    /// А вот дня, который ещё не наступил, в дневнике не бывает.
    var canEditDiary: Bool { !isFuture }

    /// Почему в этот день писать нельзя — теми же словами, что в прототипе.
    var closedReason: String {
        isPast ? "День закрыт. Прошедший день не пополняется."
               : "Этот день ещё не наступил."
    }

    /// Заголовок дня: ближние дни зовутся по имени, дальние — днём недели.
    var title: String {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: DayStore.today(), to: date).day ?? 0
        switch n {
        case -2: return "Позавчера"
        case -1: return "Вчера"
        case  0: return "Сегодня"
        case  1: return "Завтра"
        case  2: return "Послезавтра"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = abs(n) < 7 ? "EEEE" : "d MMMM"
            return f.string(from: date).capitalized
        }
    }

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

    private var pendingSave: Task<Void, Never>?

    /// Запись не на каждую букву: иначе файл в iCloud переписывается
    /// десятки раз в минуту. Полсекунды тишины — и день на диске.
    @MainActor func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard vault.root != nil else { return }
        write(Plan.body(from: planRows), to: .planner)
        write(diary, to: .diary)
    }

    /// Пустой день не оставляет следов: файл заводится, только когда в нём
    /// что-то есть. Иначе пролистывание недели вперёд засеяло бы папку
    /// десятком пустых файлов — а папка не наша, чтобы её засорять.
    private func write(_ body: String, to folder: Vault.Folder) {
        let empty = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && vault.read(folder, for: date).isEmpty { return }
        var f = DayFile(body: body)
        f.set("дата", Vault.stamp(date))
        vault.write(f.text, to: folder, for: date)
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
