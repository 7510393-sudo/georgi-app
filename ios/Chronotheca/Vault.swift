import Foundation

/// Папка пользователя.
///
/// Приложение в ней гость. Оно не владеет ни папкой, ни файлами и не хранит
/// ничего, что нельзя восстановить, прочитав папку заново. Единственное, что
/// живёт внутри приложения, — закладка на папку, чтобы не спрашивать дорогу
/// при каждом запуске. Удалите приложение — записи останутся.
final class Vault: ObservableObject {

    /// Подпапки главной папки. Имена собраны здесь, чтобы менять их в одном месте.
    enum Folder: String, CaseIterable {
        case diary     = "Дневник"
        case planner   = "Планировщик"
        case photos    = "Фотографии"
        case videos    = "Видео"
        case audio     = "Аудио"
        case documents = "Документы"
        case service   = "Служебное"
    }

    /// Имя папки, которую приложение заводит себе само.
    static let folderName = "Chronotheca"

    /// Метка, по которой приложение узнаёт свои архивы.
    ///
    /// Узнавать по имени подпапки нельзя: у человека может лежать своя папка
    /// «Дневник» с рукописями, и приложение начнёт писать в неё. Поэтому свой
    /// архив помечается собственным файлом, который никто другой не создаёт.
    static let markerPath = "Служебное/chronotheca.json"

    /// Папка, которую разрешил открывать человек. Доступ выдан именно ей.
    @Published private(set) var granted: URL?

    /// Папка, в которой лежат записи: либо сама разрешённая, либо наша внутри неё.
    @Published private(set) var root: URL?
    @Published private(set) var problem: String?

    /// Заполняется, если при запуске выяснилось, что папку переименовали или
    /// передвинули. Приложение идёт за ней следом, но человек должен об этом
    /// узнать — иначе он не поймёт, куда делись записи.
    @Published var moved: String?

    private static let bookmarkKey = "vault.root.bookmark"
    private static let subpathKey = "vault.root.subpath"
    private static let lastPathKey = "vault.root.lastPath"
    private static let previousBookmarkKey = "vault.root.bookmark.previous"
    private static let previousSubpathKey = "vault.root.subpath.previous"
    private static let previousPathKey = "vault.root.lastPath.previous"
    private var accessing: URL?

    /// Путь, который можно показать человеку. Длинный и некрасивый, зато
    /// по нему папку действительно найти в «Файлах».
    var displayPath: String { root?.path.removingPercentEncoding ?? root?.path ?? "" }

    init() {
        if Vault.isPreview { usePreviewFolder() } else { restore() }
    }

    // MARK: - Режим показа

    /// Запуск для снимков экрана: приложение берёт временную папку внутри
    /// собственной песочницы и немного содержимого, чтобы экран было видно.
    ///
    /// Включается только переменной окружения, которую выставляет сборка снимков.
    /// В руках человека этот путь недостижим: закладка не пишется, настоящая
    /// папка не трогается.
    static var isPreview: Bool {
        ProcessInfo.processInfo.environment["CHRONOTHECA_PREVIEW"] == "1"
    }

    private func usePreviewFolder() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Показ")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try makeTree(in: url)
            granted = url
            root = url
            seedPreview()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func seedPreview() {
        let today = Date()

        var plan = DayFile(body: """
        - [ ] 09:00 Отвезти документы нотариусу
              Малая Бронная 12, второй этаж. Взять оригинал доверенности.
        - [ ] Позвонить в поликлинику
        - [ ] 15:00 Дописать вторую главу
        - [ ] Забрать посылку до восьми
        """)
        plan.set("дата", Vault.stamp(today))
        write(plan.text, to: .planner, for: today)

        var diary = DayFile(body: """
        ## Как прошло?

        - Отвезти документы нотариусу: всё получилось, доверенность приняли
        - Позвонить в поликлинику: так и не собрался

        08:15 Проснулся раньше будильника, впервые за неделю. Туман над полем\
         такой плотный, что не видно второго ряда деревьев.

        23:40 В поликлинику так и не собрался. Зато глава дописана, и\
         кажется, что она вышла лучше первой.
        """)
        diary.set("дата", Vault.stamp(today))
        diary.set("заголовок", "Туман")
        write(diary.text, to: .diary, for: today)

        // Вчерашний день нужен для снимка прошедшего: без него не видно,
        // как выцветает закрытый план и как остаётся контрастным дневник.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        var past = DayFile(body: """
        - [x] 08:30 Забрать справку в банке
        - [x] Отменить подписку
        - [ ] 19:00 Зайти к Анне (напомнить 18:30)
              Второй подъезд, код 42. Забрать книги.
        """)
        past.set("дата", Vault.stamp(yesterday))
        write(past.text, to: .planner, for: yesterday)

        var pastDiary = DayFile(body: """
        09:10 Справку дали без очереди — редкий день.

        22:05 У Анны просидели до одиннадцати. Книги так и не забрал.
        """)
        pastDiary.set("дата", Vault.stamp(yesterday))
        pastDiary.set("заголовок", "Справка и книги")
        write(pastDiary.text, to: .diary, for: yesterday)
    }

    // MARK: - Папка

    /// Предложение завести новую папку. Заполняется, когда в выбранном месте
    /// архива не нашлось.
    ///
    /// Само приложение новую папку не заводит. Однажды оно заводило — и завело
    /// второй архив внутри первого, потому что человек стоял внутри своего же
    /// архива. Записи разъехались по двум папкам молча. Больше так нельзя:
    /// решение завести папку принимает человек, увидев полный путь.
    @Published var proposal: Proposal?

    struct Proposal: Identifiable {
        let id = UUID()
        let granted: URL
        let target: URL

        /// Похоже, что выбрана папка внутри архива.
        var insideArchive: Bool {
            Folder.allCases.contains { $0.rawValue == granted.lastPathComponent }
        }

        var path: String { target.path.removingPercentEncoding ?? target.path }
    }

    /// Пользователь выбрал папку в системном окне.
    func adopt(_ url: URL) {
        guard begin(url) else {
            problem = "Система не дала доступ к этой папке."
            return
        }
        if let found = findVault(from: url) {
            use(granted: url, target: found)
            return
        }
        proposal = Proposal(granted: url, target: url.appendingPathComponent(Vault.folderName))
    }

    /// Человек согласился завести новую папку.
    func acceptProposal() {
        guard let p = proposal else { return }
        proposal = nil
        do {
            try FileManager.default.createDirectory(at: p.target,
                                                    withIntermediateDirectories: true)
            use(granted: p.granted, target: p.target)
        } catch {
            problem = error.localizedDescription
        }
    }

    func declineProposal() { proposal = nil }

    /// Где здесь наш архив.
    ///
    /// Смотрим в самом месте, на уровень ниже — и вверх по родителям. Вверх
    /// важнее всего: человек, ищущий свою папку, легко заходит внутрь неё, и
    /// завести там второй архив — значит разорвать записи надвое.
    private func findVault(from url: URL) -> URL? {
        if isOurs(url) { return url }

        let nested = url.appendingPathComponent(Vault.folderName)
        if isOurs(nested) { return nested }

        var parent = url.deletingLastPathComponent()
        for _ in 0..<8 {
            guard parent.path.count > 1 else { break }
            if isOurs(parent) { return parent }
            parent = parent.deletingLastPathComponent()
        }
        return nil
    }

    private func use(granted url: URL, target: URL) {
        do {
            // Прежнее место запоминается целиком: ошибочный выбор должно быть
            // чем отменить, не разыскивая папку заново.
            if let old = UserDefaults.standard.data(forKey: Vault.bookmarkKey) {
                let defaults = UserDefaults.standard
                defaults.set(old, forKey: Vault.previousBookmarkKey)
                defaults.set(defaults.string(forKey: Vault.subpathKey) ?? "",
                             forKey: Vault.previousSubpathKey)
                defaults.set(defaults.string(forKey: Vault.lastPathKey) ?? "",
                             forKey: Vault.previousPathKey)
            }

            let subpath = target.path.hasPrefix(url.path)
                ? String(target.path.dropFirst(url.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : ""

            UserDefaults.standard.set(try url.bookmarkData(), forKey: Vault.bookmarkKey)
            UserDefaults.standard.set(subpath, forKey: Vault.subpathKey)
            UserDefaults.standard.set(target.path, forKey: Vault.lastPathKey)

            try makeTree(in: target)
            granted = url
            root = target
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Прежнее место, если оно было. Показывается в настройках.
    var previousPath: String? {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: Vault.previousBookmarkKey) != nil,
              let path = defaults.string(forKey: Vault.previousPathKey),
              !path.isEmpty, path != root?.path
        else { return nil }
        return path.removingPercentEncoding ?? path
    }

    /// Вернуться к прежнему месту. Ошибочный выбор — обычное дело, и он
    /// не должен стоить человеку архива.
    func goBack() {
        guard let data = UserDefaults.standard.data(forKey: Vault.previousBookmarkKey) else {
            return
        }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard begin(url) else {
                problem = "Прежняя папка больше недоступна."
                return
            }
            let subpath = UserDefaults.standard.string(forKey: Vault.previousSubpathKey) ?? ""
            let target = subpath.isEmpty ? url : url.appendingPathComponent(subpath)
            use(granted: url, target: target)
        } catch {
            problem = error.localizedDescription
        }
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Vault.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Vault.subpathKey)
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        root = nil
        granted = nil
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Vault.bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: [],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale)
            guard begin(url) else {
                problem = "Папка, в которую приложение писало, больше недоступна — "
                        + "чаще всего это значит, что её перенесли между памятью "
                        + "телефона и iCloud. Записи целы: они лежат там, куда вы "
                        + "их перенесли. Укажите это место заново, и приложение "
                        + "узнает свой архив."
                return
            }
            let subpath = UserDefaults.standard.string(forKey: Vault.subpathKey) ?? ""
            granted = url
            root = subpath.isEmpty ? url : url.appendingPathComponent(subpath)

            if stale {
                // Закладка устарела: папку переименовали или передвинули.
                // Система нашла её по новому месту — обновляем закладку
                // и говорим об этом вслух.
                if let fresh = try? url.bookmarkData() {
                    UserDefaults.standard.set(fresh, forKey: Vault.bookmarkKey)
                }
                let previous = UserDefaults.standard.string(forKey: Vault.lastPathKey)
                if let previous, previous != root?.path {
                    moved = root?.path
                }
            }
            UserDefaults.standard.set(root?.path, forKey: Vault.lastPathKey)
        } catch {
            problem = "Не удалось открыть прежнюю папку. Записи в ней целы — "
                    + "укажите это место заново."
        }
    }

    private func begin(_ url: URL) -> Bool {
        if accessing == url { return true }
        accessing?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            accessing = nil
            // Не всякая доступная папка охраняется: своя песочница приложения
            // открыта и без разрешения. Отказ системы — ещё не отказ в доступе,
            // проверяем делом.
            return FileManager.default.isWritableFile(atPath: url.path)
        }
        accessing = url
        return true
    }

    /// Наш ли это архив.
    ///
    /// Главный признак — метка. Запасной: все семь подпапок на месте разом.
    /// Одно совпадение имени архивом не считается, случайных совпадений сразу
    /// по семи именам не бывает, а метку кладём при первой же записи.
    private func isOurs(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appendingPathComponent(Vault.markerPath).path) {
            return true
        }
        return Folder.allCases.allSatisfy {
            fm.fileExists(atPath: url.appendingPathComponent($0.rawValue).path)
        }
    }

    private func makeTree(in url: URL) throws {
        let fm = FileManager.default
        for folder in Folder.allCases {
            try fm.createDirectory(at: url.appendingPathComponent(folder.rawValue),
                                   withIntermediateDirectories: true)
        }

        let marker = url.appendingPathComponent(Vault.markerPath)
        if !fm.fileExists(atPath: marker.path) {
            let json = """
            {
              "приложение": "Chronotheca",
              "версия формата": 1,
              "заведено": "\(Vault.stamp(Date()))"
            }
            """
            try Data(json.utf8).write(to: marker, options: .atomic)
        }

        // Записка тому, кто найдёт эту папку через много лет.
        let note = url.appendingPathComponent("Служебное/Что это за папка.txt")
        if !fm.fileExists(atPath: note.path) {
            let text = """
            Это архив дневника и планировщика.

            Всё, что здесь лежит, — обычные файлы. Записи в папках «Дневник» и
            «Планировщик» — простой текст: их можно открыть любым текстовым
            редактором, на любом устройстве, без всякой программы. Фотографии,
            видео, аудио и документы лежат как есть, в своих папках.

            Приложение, которое их писало, называется Chronotheca. Оно ничего
            не прячет и ничем не владеет: удалите его — всё это останется.

            Папку можно переносить, копировать и переименовывать. Чтобы
            приложение снова её нашло, укажите ей это место заново.
            """
            try Data(text.utf8).write(to: note, options: .atomic)
        }
    }

    // MARK: - Файлы

    /// <папка>/<раздел>/<год>/<ГГГГ-ММ-ДД>.md
    func file(_ folder: Folder, for date: Date) -> URL? {
        guard let root else { return nil }
        let stamp = Vault.stamp(date)
        return root
            .appendingPathComponent(folder.rawValue)
            .appendingPathComponent(String(stamp.prefix(4)))
            .appendingPathComponent(stamp + ".md")
    }

    func read(_ folder: Folder, for date: Date) -> String {
        guard let url = file(folder, for: date),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    func write(_ text: String, to folder: Folder, for date: Date) {
        guard let url = file(folder, for: date) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Обратно из имени файла в дату. Имя файла — это и есть дата записи:
    /// по нему архив читается даже без приложения.
    static func date(from stamp: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        guard let d = f.date(from: stamp) else { return nil }
        return Calendar.current.startOfDay(for: d)
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
