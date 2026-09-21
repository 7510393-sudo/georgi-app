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
    var isToday: Bool { date == DayStore.today() }

    /// План живёт вперёд: на сегодня и на любой будущий день дела заводятся
    /// свободно — ради этого планировщик и нужен. Прошедший день закрыт:
    /// задним числом план не переписывают, кроме как в режиме изменений.
    var canEditPlan: Bool { !isPast || editing }

    /// Дневник живёт назад: вчерашнее дописывают и через неделю (решение P63).
    /// А вот дня, который ещё не наступил, в дневнике не бывает.
    var canEditDiary: Bool { !isFuture }

    /// Режим изменений: открывает прошедший день для правки, меняет порядок
    /// дел и позволяет удалять. Включается вручную в меню страницы и гаснет
    /// при уходе со дня — чтобы нельзя было забыть его включённым.
    @Published var editing = false

    /// Почему в этот день писать нельзя.
    var closedReason: String {
        isPast ? "День закрыт. Изменения — через режим изменений."
               : "Этот день ещё не наступил."
    }

    /// Заголовок дня: ближние дни зовутся по имени, дальние — днём недели.
    var title: String {
        let n = Calendar.current.dateComponents([.day], from: DayStore.today(), to: date).day ?? 0
        switch n {
        case -2: return "Позавчера"
        case -1: return "Вчера"
        case  0: return "Сегодня"
        case  1: return "Завтра"
        case  2: return "Послезавтра"
        default: return Ru.weekday(date).capitalized
        }
    }

    /// Граница суток: до этого часа день считается вчерашним (решение P17).
    static var boundaryHour = 4

    /// Через столько без правки дневник ставит новую отметку времени.
    static let stampGap: TimeInterval = 60 * 60

    @Published var date: Date
    @Published var planRows: [PlanRow] = []
    @Published var diaryTitle: String = ""
    @Published var diaryText: String = ""
    @Published var answers: [String: String] = [:]

    /// Когда дневник правили в последний раз. Лежит в шапке файла, чтобы
    /// отметка времени вела себя одинаково и после перезапуска приложения.
    private var lastEdit: Date?

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

    // MARK: - Дела

    /// Дела дня — без строк, которые приложение не разбирало.
    var tasks: [PlanRow] { planRows.filter { $0.isTask } }
    var doneCount: Int { tasks.filter { $0.done }.count }

    func index(of id: UUID) -> Int? { planRows.firstIndex { $0.id == id } }

    func addTask() -> UUID? {
        guard canEditPlan else { return nil }
        let row = PlanRow.task("")
        planRows.append(row)
        return row.id
    }

    func delete(_ id: UUID) {
        guard canEditPlan, let i = index(of: id) else { return }
        planRows.remove(at: i)
        save()
    }

    /// Переставить дело выше или ниже соседнего дела.
    func move(_ id: UUID, by step: Int) {
        guard canEditPlan, let i = index(of: id) else { return }
        var j = i + step
        while j >= 0 && j < planRows.count && !planRows[j].isTask { j += step }
        guard j >= 0, j < planRows.count else { return }
        planRows.swapAt(i, j)
        save()
    }

    // MARK: - Дни

    func go(to newDate: Date) {
        prune()
        save()
        editing = false
        date = Calendar.current.startOfDay(for: newDate)
        load()
    }

    func move(by days: Int) {
        go(to: Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Пустые дела убираются только при уходе со дня: иначе новое дело
    /// исчезает, едва человек коснулся другого места на экране.
    func prune() {
        planRows.removeAll { $0.isTask && $0.text.trimmingCharacters(in: .whitespaces).isEmpty
                             && $0.details.isEmpty }
    }

    // MARK: - Отметка времени в дневнике

    /// Нужна ли новая отметка времени перед тем, как человек начнёт писать.
    ///
    /// Нужна, если запись пуста или к ней не возвращались больше часа. Смысл
    /// отметок — показать, что день писался в несколько заходов, а не залпом.
    func stampIfNeeded() {
        guard canEditDiary else { return }
        let body = diaryText.replacingOccurrences(of: "\\s+$", with: "",
                                                  options: .regularExpression)
        let stale = lastEdit.map { Date().timeIntervalSince($0) > DayStore.stampGap } ?? true
        guard body.isEmpty || stale else { return }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        diaryText = (body.isEmpty ? "" : body + "\n\n") + f.string(from: Date()) + " "
        lastEdit = Date()
        save()
    }

    func touchDiary() { lastEdit = Date() }

    // MARK: - Диск

    func load() {
        planRows = Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body)

        let file = DayFile(text: vault.read(.diary, for: date))
        let diary = Diary(body: file.body)
        diaryTitle = file.value("заголовок") ?? ""
        diaryText = diary.text
        answers = diary.answers
        lastEdit = file.value("правлено").flatMap(DayStore.moment(from:))
    }

    private var pendingSave: DispatchWorkItem?

    /// Запись не на каждую букву: иначе файл в iCloud переписывается
    /// десятки раз в минуту. Полсекунды тишины — и день на диске.
    func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard vault.root != nil else { return }

        var plan = DayFile(body: Plan.body(from: planRows))
        plan.set("дата", Vault.stamp(date))
        write(plan, to: .planner, keep: false)

        let order = tasks.map(\.text)
        var diary = DayFile(body: Diary(answers: answers, text: diaryText).body(order: order))
        diary.set("дата", Vault.stamp(date))
        if !diaryTitle.isEmpty { diary.set("заголовок", diaryTitle) }
        if let lastEdit { diary.set("правлено", DayStore.moment(lastEdit)) }
        // Заголовок дня — это уже запись, даже если под ним пока нет ни строчки.
        write(diary, to: .diary, keep: !diaryTitle.isEmpty)
    }

    /// Пустой день не оставляет следов: файл заводится, только когда в нём
    /// что-то есть. Иначе пролистывание недели вперёд засеяло бы папку
    /// десятком пустых файлов — а папка не наша, чтобы её засорять.
    ///
    /// `keep` — для того, что живёт в шапке, а не в тексте: день, у которого
    /// есть только заголовок, всё равно записан человеком и пропасть не должен.
    private func write(_ file: DayFile, to folder: Vault.Folder, keep: Bool) {
        let empty = file.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && !keep && vault.read(folder, for: date).isEmpty { return }
        vault.write(file.text, to: folder, for: date)
    }

    /// То, что действительно лежит на диске — а не то, что помнит приложение.
    /// Нужно, чтобы проверять обещание: файлы источник, приложение только окно.
    func onDisk() -> String {
        let p = vault.read(.planner, for: date)
        let d = vault.read(.diary, for: date)
        return "\(Vault.Folder.planner.rawValue)\n\n\(p.isEmpty ? "(файла нет)\n" : p)\n"
             + "\(Vault.Folder.diary.rawValue)\n\n\(d.isEmpty ? "(файла нет)\n" : d)"
    }

    // MARK: - Мгновения

    private static let momentFormat = "yyyy-MM-dd'T'HH:mm"

    static func moment(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = momentFormat
        return f.string(from: date)
    }

    static func moment(from text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = momentFormat
        return f.date(from: text)
    }
}
