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
    var canEditPlan: Bool { (!isPast || editing) && !away.contains(.planner) }

    /// Дневник живёт назад: вчерашнее дописывают и через неделю (решение P63).
    /// А вот дня, который ещё не наступил, в дневнике не бывает.
    var canEditDiary: Bool { !isFuture && !away.contains(.diary) }

    /// Файлы дня, которые лежат, но не прочитались — чаще всего ещё не
    /// скачаны из iCloud. Писать в такой день нельзя: пустая страница на
    /// экране не значит пустой файл на диске (решение P182).
    @Published private(set) var away: Set<Vault.Folder> = []

    /// Запись изменили в другом месте, пока она была открыта здесь, и правки
    /// оказались с обеих сторон. Своя правка положена рядом; человеку надо
    /// сказать, где она (решение P183).
    @Published var conflict: String?

    /// Режим изменений: открывает прошедший день для правки, меняет порядок
    /// дел и позволяет удалять. Включается вручную в меню страницы и гаснет
    /// при уходе со дня — чтобы нельзя было забыть его включённым.
    @Published var editing = false

    /// Почему в этот день писать нельзя.
    var closedReason: String {
        if !away.isEmpty {
            return "Запись ещё загружается из iCloud. Как только придёт — её можно будет править."
        }
        return isPast ? "День закрыт. Изменения — через режим изменений."
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
    /// Ссылки на фотографии дня, как они записаны в файле (P200).
    @Published var photos: [String] = []
    /// Фотографии плана — свои, отдельно от дневника (P203).
    @Published var planPhotos: [String] = []

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
        retries = 0
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
    ///
    /// Возвращает `true`, если отметка поставлена: тогда курсор надо
    /// перенести за неё — писать человек будет там (решение P137).
    @discardableResult
    func stampIfNeeded() -> Bool {
        guard canEditDiary else { return false }
        let body = diaryText.replacingOccurrences(of: "\\s+$", with: "",
                                                  options: .regularExpression)
        let stale = lastEdit.map { Date().timeIntervalSince($0) > DayStore.stampGap } ?? true
        guard body.isEmpty || stale else { return false }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        diaryText = (body.isEmpty ? "" : body + "\n\n") + f.string(from: Date()) + " "
        lastEdit = Date()
        save()
        return true
    }

    func touchDiary() { lastEdit = Date() }

    /// Положить фотографию в папку и сослаться на неё из файла дня — плана
    /// или дневника, смотря на какой вкладке её положили.
    ///
    /// Правила те же, что у правки вкладки: в закрытый день, в будущий
    /// дневник и в день, который ещё не скачан из iCloud, её не положить
    /// (P182, P200, P203).
    @discardableResult
    func addPhoto(_ data: Data, to tab: Shell.Tab) -> Bool {
        guard canEdit(tab), let link = vault.addPhoto(data, for: date) else { return false }
        switch tab {
        case .diary:
            photos.append(link)
            touchDiary()
        case .plan:
            planPhotos.append(link)
        }
        save()
        return true
    }

    /// Убрать фотографию из файла дня. Сам снимок остаётся в папке:
    /// удалять файлы человека приложение не берётся — это делают в «Файлах».
    func removePhoto(at index: Int, from tab: Shell.Tab) {
        guard canEdit(tab) else { return }
        switch tab {
        case .diary:
            guard photos.indices.contains(index) else { return }
            photos.remove(at: index)
            touchDiary()
        case .plan:
            guard planPhotos.indices.contains(index) else { return }
            planPhotos.remove(at: index)
        }
        save()
    }

    /// Снимок, брошенный из полоски в текст, уходит из полоски: он теперь
    /// стоит на своём месте в записи, и дважды его показывать незачем (P204).
    func settlePhotos() {
        guard !photos.isEmpty, diaryText.contains("![") else { return }
        let placed = photos.filter { diaryText.contains(Diary.line($0)) }
        guard !placed.isEmpty else { return }
        photos.removeAll { placed.contains($0) }
    }

    func links(_ tab: Shell.Tab) -> [String] { tab == .diary ? photos : planPhotos }

    func canEdit(_ tab: Shell.Tab) -> Bool { tab == .diary ? canEditDiary : canEditPlan }

    /// Где лежит фотография дня.
    func photoURL(_ link: String) -> URL? { vault.mediaURL(link, for: date) }

    // MARK: - Диск

    // Что лежало на диске, когда день читали или писали в последний раз, и
    // как приложение тогда же видело этот день. По первому узнаётся чужая
    // правка, по второму — своя (решения P182, P183).
    private var seen: [Vault.Folder: String] = [:]
    private var mine: [Vault.Folder: String] = [:]
    private var retries = 0

    func load() {
        let plan = vault.reading(.planner, for: date)
        let diaryFile = vault.reading(.diary, for: date)
        var gone: Set<Vault.Folder> = []
        if plan == .away { gone.insert(.planner) }
        if diaryFile == .away { gone.insert(.diary) }
        away = gone

        (planRows, planPhotos) = Plan.splitPhotos(Plan.rows(from: DayFile(text: plan.text).body))

        let file = DayFile(text: diaryFile.text)
        // План читается первым, поэтому названия дел уже известны — по ним
        // ответы «Как прошло?» разбираются без догадок (P155).
        let diary = Diary(body: file.body, known: planRows.map(\.text))
        diaryTitle = file.value("заголовок") ?? ""
        diaryText = diary.text
        answers = diary.answers
        photos = diary.photos
        lastEdit = file.value("правлено").flatMap(DayStore.moment(from:))

        seen = [.planner: plan.text, .diary: diaryFile.text]
        mine = [.planner: planFile().text, .diary: diaryFileNow().text]
        if away.isEmpty { retries = 0 } else { waitForCloud() }
    }

    /// Сверить открытый день с диском.
    ///
    /// Зовётся, когда человек возвращается в приложение, и пока запись
    /// докачивается из iCloud. Сначала своё — записать, потом чужое —
    /// перечитать: так своя правка не пропадёт, а чужая не затрётся.
    func refresh() {
        guard vault.root != nil else { return }
        save()
        let stale = [Vault.Folder.planner, .diary].contains { folder in
            let now = vault.reading(folder, for: date)
            if now == .away { return false }
            return away.contains(folder) || now.text != (seen[folder] ?? "")
        }
        if stale { load() } else if !away.isEmpty { waitForCloud() }
    }

    /// Пока файл дня едет из iCloud, заглядывать за ним каждые две секунды.
    private func waitForCloud() {
        guard retries < 60 else { return }
        retries += 1
        let day = date
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.date == day, !self.away.isEmpty else { return }
            self.refresh()
        }
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
        // Оба файла собираются до записи: если один из них изменили в другом
        // месте и день придётся перечитать, правка во втором не должна
        // пропасть вместе с перечитыванием.
        let plan = planFile()
        let diary = diaryFileNow()
        let a = write(plan, to: .planner, keep: false)
        // Заголовок дня — это уже запись, даже если под ним пока нет ни строчки.
        let b = write(diary, to: .diary, keep: !diaryTitle.isEmpty)
        if a || b { load() }
    }

    /// Человек вернулся в приложение: сверить день с диском заново.
    func comeBack() {
        retries = 0
        refresh()
    }

    /// План дня таким, каким он ляжет в файл.
    private func planFile() -> DayFile {
        var plan = DayFile(body: Plan.body(from: planRows, photos: planPhotos))
        plan.set("дата", Vault.stamp(date))
        return plan
    }

    /// Дневник дня таким, каким он ляжет в файл.
    private func diaryFileNow() -> DayFile {
        let order = tasks.map(\.text)
        var diary = DayFile(body: Diary(answers: answers, text: diaryText,
                                     photos: photos).body(order: order))
        diary.set("дата", Vault.stamp(date))
        if !diaryTitle.isEmpty { diary.set("заголовок", diaryTitle) }
        if let lastEdit { diary.set("правлено", DayStore.moment(lastEdit)) }
        return diary
    }

    /// Записать день — но никогда не поверх того, чего приложение не видело.
    ///
    /// Три правила, и каждое закрывает свою дыру:
    ///
    /// 1. Файл не прочитался (ещё в iCloud) — не пишем вовсе. Пустая
    ///    страница на экране не значит пустой файл на диске (P182).
    /// 2. Файл изменили в другом месте, пока он был открыт здесь, — не
    ///    затираем. Своей правки нет — перечитываем чужую; есть — кладём
    ///    свою рядом и перечитываем чужую (P183).
    /// 3. Ничего не менялось — не переписываем: лишняя запись в iCloud
    ///    плодит версии и столкновения.
    ///
    /// Пустой день не оставляет следов: файл заводится, только когда в нём
    /// что-то есть. Иначе пролистывание недели вперёд засеяло бы папку
    /// десятком пустых файлов — а папка не наша, чтобы её засорять.
    ///
    /// `keep` — для того, что живёт в шапке, а не в тексте: день, у которого
    /// есть только заголовок, всё равно записан человеком и пропасть не должен.
    ///
    /// Возвращает `true`, если на диске оказалось не то, что приложение
    /// видело, и день надо перечитать.
    @discardableResult
    private func write(_ file: DayFile, to folder: Vault.Folder, keep: Bool) -> Bool {
        guard !away.contains(folder) else { return false }
        let ours = file.text
        guard ours != mine[folder] else { return false }

        let now = vault.reading(folder, for: date)
        if now == .away {
            away.insert(folder)
            waitForCloud()
            return false
        }
        if now.text != (seen[folder] ?? "") {
            // Та же правка пришла с другой стороны — делить нечего.
            if now.text == ours {
                seen[folder] = ours
                mine[folder] = ours
                return false
            }
            // Своя правка кладётся рядом. Не легла — день не перечитываем,
            // иначе она пропадёт: пусть остаётся на экране до следующей попытки.
            guard let name = vault.writeAside(ours, folder: folder, for: date) else {
                return false
            }
            conflict = name
            return true
        }

        let empty = file.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && !keep && now.text.isEmpty { return false }
        vault.write(ours, to: folder, for: date)
        if vault.problem == nil {
            seen[folder] = ours
            mine[folder] = ours
        }
        return false
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
