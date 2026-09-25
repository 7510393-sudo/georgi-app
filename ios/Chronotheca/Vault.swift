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
        /// Места своей карты — по файлу на место (P207).
        case places    = "Места"
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
    /// Где лежат записи: «phone» — своя папка приложения на телефоне,
    /// иначе — папка, выбранная человеком (P223).
    private static let placeKey = "vault.place"
    private static let previousPlaceKey = "vault.place.previous"

    /// Записи лежат в своей папке приложения на этом iPhone.
    var onPhone: Bool { UserDefaults.standard.string(forKey: Vault.placeKey) == "phone" }

    /// Своя папка приложения. Её видно в «Файлах» → «На iPhone».
    static var phoneFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var accessing: URL?

    /// Путь, который можно показать человеку. Длинный и некрасивый, зато
    /// по нему папку действительно найти в «Файлах».
    var displayPath: String { root?.path.removingPercentEncoding ?? root?.path ?? "" }

    /// Путь словами «Файлов»: «iCloud Drive › Chronotheca», «На iPhone ›
    /// Chronotheca». Полный путь с «/private/var/mobile/…» ничего не говорит
    /// человеку, а так папку находят, открыв «Файлы» (решение P190).
    var friendlyPath: String { Vault.friendly(displayPath) }

    /// Записи пишутся в папку, названную как наша подпапка, — «Видео»,
    /// «Дневник». Почти наверняка это промах на ступеньку: архив лежит
    /// уровнем выше. Возвращает имя папки уровнем выше (P201).
    var nestedIn: String? {
        guard let root, Folder(rawValue: root.lastPathComponent) != nil else { return nil }
        return root.deletingLastPathComponent().lastPathComponent
    }

    /// Прежнее место словами «Файлов».
    var previousFriendly: String? { previousPath.map(Vault.friendly) }

    static func friendly(_ path: String) -> String {
        // Своя папка приложения на телефоне: в «Файлах» она лежит в «На
        // iPhone» под именем приложения (P223).
        if path.contains("/Data/Application/"), let r = path.range(of: "/Documents") {
            let tail = path[r.upperBound...].split(separator: "/").map(String.init)
            return (["На iPhone", Vault.folderName] + tail).joined(separator: " › ")
        }
        let places: [(String, String)] = [
            ("/Mobile Documents/com~apple~CloudDocs", "iCloud Drive"),
            ("/File Provider Storage", "На iPhone"),
        ]
        for (marker, name) in places {
            if let r = path.range(of: marker) {
                let tail = path[r.upperBound...].split(separator: "/").map(String.init)
                return ([name] + tail).joined(separator: " › ")
            }
        }
        // Папка другого приложения в iCloud: «…/Mobile Documents/iCloud~md~obsidian/…».
        if let r = path.range(of: "/Mobile Documents/") {
            let tail = path[r.upperBound...].split(separator: "/").dropFirst().map(String.init)
            return (["iCloud Drive"] + tail).joined(separator: " › ")
        }
        let tail = path.split(separator: "/").suffix(2).map(String.init)
        return tail.joined(separator: " › ")
    }

    /// Ссылка, которая открывает папку прямо в «Файлах».
    ///
    /// Держится на приёме, который Apple не описывала в бумагах, но который
    /// работает давно. Перестанет — остаётся путь, показанный словами.
    var filesLink: URL? {
        guard let root else { return nil }
        let path = root.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? root.path
        return URL(string: "shareddocuments://" + path)
    }

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
        // Фотографии — чтобы на снимке было видно, как они стоят: одна
        // посреди текста, другая в полоске внизу (P203, P204).
        if let link = addPhoto(Photo.sample(), for: today) {
            diary.body = diary.body.replacingOccurrences(
                of: "\n\n23:40", with: "\n\n" + Diary.line(link) + "\n\n23:40")
        }
        if let link = addPhoto(Photo.sample(), for: today) {
            diary.body += "\n\n" + Diary.line(link)
        }
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

        // Тот же день год назад — чтобы облачко «…помнишь?» было видно
        // в работе, а не только на словах.
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: today) ?? today
        var old = DayFile(body: """
        07:40 Первый по-настоящему холодный день. Иней на перилах, и\
         видно дыхание.

        21:15 Перебирал бумаги, нашёл письмо, о котором забыл. Читал дважды.
        """)
        old.set("дата", Vault.stamp(lastYear))
        old.set("заголовок", "Иней на перилах")
        write(old.text, to: .diary, for: lastYear)
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

    /// Предложение перенести записи из прежней папки, ход переноса и отчёт.
    @Published var transfer: Transfer.Offer?
    @Published var moving: Transfer.Progress?
    @Published var transferDone: Transfer.Report?

    /// Папка, из которой человек только что ушёл, и сколько в ней записей.
    /// Считается до смены доступа: после неё прежняя папка уже закрыта, и
    /// заглянуть в неё будет нечем.
    private var leaving: (root: URL, records: Int)?

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
        // Прежнюю папку пересчитываем, пока доступ к ней ещё открыт.
        let before = root.map { (root: $0, records: Transfer.records(in: $0)) }
        guard begin(url) else {
            problem = "Система не дала доступ к этой папке."
            return
        }
        leaving = before
        if let found = findVault(from: url) {
            use(granted: url, target: found)
            return
        }
        // Своё место человек выбрал сам — после согласия завести папку
        // запишется, что это его папка, а не наша на телефоне.
        proposal = Proposal(granted: url, target: url.appendingPathComponent(Vault.folderName))
    }

    /// Хранить записи в своей папке приложения на этом iPhone (P223).
    ///
    /// Одно касание, без системного окна: папку заводит само приложение, и
    /// её видно в «Файлах» → «На iPhone» → «Chronotheca». Если записи
    /// лежали в другом месте, приложение предложит их перенести — тем же
    /// переносом «копия, проверка, удаление» (P147).
    func usePhone() {
        let before = root.map { (root: $0, records: Transfer.records(in: $0)) }
        // Записи лежат прямо в папке приложения: в «Файлах» это «На iPhone ›
        // Chronotheca», без второй «Chronotheca» внутри.
        let home = Vault.phoneFolder
        _ = begin(home)
        leaving = before
        use(granted: home, target: home)
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

    func declineProposal() {
        proposal = nil
        leaving = nil
    }

    /// Где здесь наш архив.
    ///
    /// Смотрим в самом месте, на уровень ниже — и вверх по родителям. Вверх
    /// важнее всего: человек, ищущий свою папку, легко заходит внутрь неё, и
    /// завести там второй архив — значит разорвать записи надвое.
    private func findVault(from url: URL) -> URL? {
        // Выбрали папку, названную как наша подпапка — «Видео», «Дневник», —
        // а уровнем выше лежит архив: значит, промахнулись на ступеньку.
        // Так 24.09 записи оказались в «Хронотека › Видео» (решение P201).
        if Folder(rawValue: url.lastPathComponent) != nil {
            let parent = url.deletingLastPathComponent()
            if isOurs(parent) { return parent }
        }
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
                defaults.set(defaults.string(forKey: Vault.placeKey) ?? "folder",
                             forKey: Vault.previousPlaceKey)
            }

            let subpath = target.path.hasPrefix(url.path)
                ? String(target.path.dropFirst(url.path.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : ""

            UserDefaults.standard.set(try url.bookmarkData(), forKey: Vault.bookmarkKey)
            UserDefaults.standard.set(subpath, forKey: Vault.subpathKey)
            UserDefaults.standard.set(target.path, forKey: Vault.lastPathKey)
            UserDefaults.standard.set(url == Vault.phoneFolder ? "phone" : "folder",
                                      forKey: Vault.placeKey)

            try makeTree(in: target)
            granted = url
            root = target
            problem = nil
            offerTransfer(to: target)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Позвать перенести записи, если человек ушёл из непустой папки.
    ///
    /// Молча оставлять записи позади нельзя: человек сменил место, считая,
    /// что дневник переезжает вместе с ним. Молча переносить — тоже: это его
    /// файлы, и решает он.
    private func offerTransfer(to target: URL) {
        guard let leaving else { return }
        self.leaving = nil
        guard leaving.records > 0,
              leaving.root.standardizedFileURL != target.standardizedFileURL
        else { return }
        transfer = Transfer.Offer(
            fromPath: leaving.root.path.removingPercentEncoding ?? leaving.root.path,
            toPath: target.path.removingPercentEncoding ?? target.path,
            records: leaving.records)
    }

    func declineTransfer() { transfer = nil }

    /// Перенести записи из прежней папки в нынешнюю.
    ///
    /// Прежняя папка открывается отдельно и на время переноса: доступ к ней
    /// уже снят, а без него из неё нечего и читать.
    func moveRecords() {
        transfer = nil
        guard let to = root else { return }

        let defaults = UserDefaults.standard
        var stale = false
        var found: URL?
        if defaults.string(forKey: Vault.previousPlaceKey) == "phone" {
            found = Vault.phoneFolder
        } else if let data = defaults.data(forKey: Vault.previousBookmarkKey) {
            found = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                             bookmarkDataIsStale: &stale)
        }
        guard let grantedOld = found else {
            problem = "Прежняя папка больше недоступна. Записи в ней целы."
            return
        }
        let subpath = defaults.string(forKey: Vault.previousSubpathKey) ?? ""
        let from = subpath.isEmpty ? grantedOld : grantedOld.appendingPathComponent(subpath)

        let opened = grantedOld.startAccessingSecurityScopedResource()
        let files = Transfer.contents(of: from)
        guard !files.isEmpty else {
            if opened { grantedOld.stopAccessingSecurityScopedResource() }
            return
        }
        moving = Transfer.Progress(done: 0, total: files.count)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = Transfer.move(files, from: from, to: to) { done in
                DispatchQueue.main.async { self?.moving?.done = done }
            }
            if opened { grantedOld.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                self?.moving = nil
                self?.transferDone = report
            }
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
        if UserDefaults.standard.string(forKey: Vault.previousPlaceKey) == "phone" {
            return usePhone()
        }
        guard let data = UserDefaults.standard.data(forKey: Vault.previousBookmarkKey) else {
            return
        }
        // Записи, сделанные на нынешнем месте, не бросаются: как и при
        // выборе новой папки, человеку предложат взять их с собой (P201).
        let before = root.map { (root: $0, records: Transfer.records(in: $0)) }
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
            leaving = before
            use(granted: url, target: target)
        } catch {
            problem = error.localizedDescription
        }
    }

    func forget() {
        for key in [Vault.bookmarkKey, Vault.subpathKey, Vault.lastPathKey,
                    Vault.previousBookmarkKey, Vault.previousSubpathKey,
                    Vault.previousPathKey, Vault.placeKey, Vault.previousPlaceKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        proposal = nil
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        root = nil
        granted = nil
    }

    private func restore() {
        // Своя папка на телефоне ищется заново при каждом запуске: путь к
        // песочнице приложения меняется после обновлений, закладка на неё
        // не нужна (P223).
        if onPhone {
            let home = Vault.phoneFolder
            do {
                try makeTree(in: home)
                granted = home
                root = home
                UserDefaults.standard.set(home.path, forKey: Vault.lastPathKey)
            } catch {
                problem = error.localizedDescription
            }
            return
        }
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
        // Метка могла уйти в iCloud или потеряться при копировании. Тогда
        // архив узнаётся по самим записям: в «Дневнике» или «Планировщике»
        // лежат папки по годам (P201).
        for folder in [Folder.diary, .planner] {
            let years = (try? fm.contentsOfDirectory(
                atPath: url.appendingPathComponent(folder.rawValue).path)) ?? []
            if years.contains(where: { $0.count == 4 && Int($0) != nil }) { return true }
        }
        // «Места» появились позже прочих: старые архивы без них — тоже наши.
        return Folder.allCases.filter { $0 != .places }.allSatisfy {
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

    /// Что удалось прочитать из файла дня.
    ///
    /// Три ответа, а не два. Раньше «файла нет» и «файл не прочитался»
    /// выглядели одинаково — пустой строкой. А это разные вещи: пустой день
    /// можно писать, а файл, который лежит в iCloud и ещё не скачан на
    /// телефон, — нельзя. Человек видел пустую страницу, писал заново, и
    /// приложение затирало настоящую запись (решение P182).
    enum Reading: Equatable {
        /// Файла нет — день чистый, писать можно.
        case none
        /// Файл прочитан.
        case text(String)
        /// Файл есть, но прочитать его не удалось: он ещё в iCloud или не
        /// читается как текст. Писать поверх нельзя — там может лежать
        /// запись, которую мы просто не видим.
        case away

        var text: String {
            if case .text(let t) = self { return t }
            return ""
        }
    }

    func reading(_ folder: Folder, for date: Date) -> Reading {
        guard let url = file(folder, for: date) else { return .none }
        return Vault.reading(at: url)
    }

    /// Прочитать файл, не приняв недоступный за пустой.
    ///
    /// Порядок важен, и он выучен на ошибке. В сборке 58 приложение сперва
    /// спрашивало у iCloud, скачан ли файл, и только потом читало. На
    /// телефоне с папкой в iCloud Drive этот вопрос не получал внятного
    /// ответа — и все дни разом объявлялись «ещё в облаке»: записи пропали
    /// с экрана, хотя лежали на месте (решение P187).
    ///
    /// Теперь сперва читаем так, как читали всегда, — напрямую; это
    /// проверено на телефоне. Не вышло — через системного посредника, он
    /// умеет дождаться чужой записи. Не вышло и так — файл есть, но не
    /// читается: просим iCloud его скачать и писать поверх не даём.
    ///
    /// `coordinated` — пробовать ли посредника. Для одного дня да; для описи
    /// всего архива дорого.
    static func reading(at url: URL, coordinated: Bool = true) -> Reading {
        let fm = FileManager.default
        // Старый способ iCloud: вместо выгруженного файла лежит невидимая
        // заглушка «.ИМЯ.md.icloud», а самого файла нет.
        let stub = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".icloud")
        guard fm.fileExists(atPath: url.path) else {
            guard fm.fileExists(atPath: stub.path) else { return .none }
            try? fm.startDownloadingUbiquitousItem(at: url)
            return .away
        }

        if let text = text(of: url) { return .text(text) }

        if coordinated {
            var got: String?
            var trouble: NSError?
            NSFileCoordinator(filePresenter: nil)
                .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                    got = text(of: real)
                }
            if let got { return .text(got) }
        }

        try? fm.startDownloadingUbiquitousItem(at: url)
        return .away
    }

    private static func text(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Текст файла для показа — там, где писать не будут: соседние
    /// страницы, сверка с диском. Недоступный файл показывается пустым.
    func read(_ folder: Folder, for date: Date) -> String {
        reading(folder, for: date).text
    }

    func write(_ text: String, to folder: Folder, for date: Date) {
        guard let url = file(folder, for: date) else { return }
        problem = Vault.write(text, to: url)
    }

    /// Записать через системного посредника: iCloud в эту минуту может
    /// сам менять файл, и запись мимо посредника с ним сталкивается.
    /// Возвращает описание беды или `nil`, если всё записалось.
    @discardableResult
    static func write(_ text: String, to url: URL) -> String? {
        write(data: Data(text.utf8), to: url)
    }

    /// То же для любого файла — фотографии, голоса, документа.
    @discardableResult
    static func write(data: Data, to url: URL) -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch {
            return error.localizedDescription
        }
        var wrote = false
        var failure: Error?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: url, options: .forReplacing, error: &trouble) { real in
                do { try data.write(to: real, options: .atomic); wrote = true }
                catch { failure = error }
            }
        if wrote { return nil }
        if let failure { return failure.localizedDescription }
        // Посредник отказал, не дав даже попробовать, — пишем напрямую, как
        // писали всегда: запись дня важнее вежливости к iCloud (P187).
        do {
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Положить вторую версию дня рядом с первой.
    ///
    /// Нужна, когда файл изменили в другом месте — на Mac, на втором
    /// устройстве, — пока он был открыт здесь, и правки есть с обеих
    /// сторон. Затирать нельзя ни ту, ни другую: чужая остаётся в файле
    /// дня, своя ложится рядом, под именем, которое видно в «Файлах» и не
    /// путается с самим днём (решение P183).
    ///
    /// Возвращает имя положенного файла.
    func writeAside(_ text: String, folder: Folder, for date: Date) -> String? {
        guard let url = file(folder, for: date) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH.mm.ss"
        let name = Vault.stamp(date) + " — вторая версия " + f.string(from: Date()) + ".md"
        let aside = url.deletingLastPathComponent().appendingPathComponent(name)
        if let trouble = Vault.write(text, to: aside) {
            problem = trouble
            return nil
        }
        return name
    }

    // MARK: - Вложения

    /// Положить фотографию дня в папку «Фотографии» и вернуть ссылку на неё
    /// из записи дня.
    ///
    /// Фотография — отдельный файл, по годам, с датой дня и временем в
    /// имени: `Фотографии/2026/2026-09-24_08.15.30.jpg`. Без пробелов —
    /// тогда ссылку понимает любой редактор разметки. Файл с таким именем
    /// уже есть — к имени прибавляется номер: чужое не затирается никогда
    /// (решение P200).
    func addPhoto(_ data: Data, for date: Date) -> String? {
        guard let jpeg = Photo.jpeg(from: data) else {
            problem = "Эту фотографию не удалось прочитать."
            return nil
        }
        return addAttachment(jpeg, to: .photos, name: Vault.moment(date) + ".jpg", for: date)
    }

    /// Имя вложения по дню и нынешнему времени: «2026-09-25_21.40.05».
    static func moment(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH.mm.ss"
        return Vault.stamp(date) + "_" + f.string(from: Date())
    }

    /// Положить вложение дня в его папку по годам и вернуть ссылку на него
    /// из файла дня.
    ///
    /// Голос — в «Аудио», документ — в «Документы» под своим именем. Файл с
    /// таким именем уже есть — к имени прибавляется номер: чужое не
    /// затирается никогда (P200, P209).
    func addAttachment(_ data: Data, to kind: Folder, name: String, for date: Date) -> String? {
        guard let root else { return nil }
        let year = String(Vault.stamp(date).prefix(4))
        let folder = root.appendingPathComponent(kind.rawValue).appendingPathComponent(year)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        if let trouble = Vault.write(data: data, to: url) {
            problem = trouble
            return nil
        }
        return "../../" + kind.rawValue + "/" + year + "/" + url.lastPathComponent
    }

    /// Где лежит вложение, на которое ссылается запись дня.
    ///
    /// Ссылка считается от файла дня — так же, как её поймёт Obsidian или
    /// любой другой редактор, открывший этот файл.
    func mediaURL(_ link: String, for date: Date) -> URL? {
        guard !link.contains("://"), let day = file(.diary, for: date) else { return nil }
        let clean = link.removingPercentEncoding ?? link
        return day.deletingLastPathComponent()
            .appendingPathComponent(clean).standardizedFileURL
    }

    /// Обратно из имени файла в дату. Имя файла — это и есть дата записи:
    /// по нему архив читается даже без приложения.
    static func date(from stamp: String) -> Date? {
        // Ровно ГГГГ-ММ-ДД и ничего сверх: «2026-09-24 — вторая версия»
        // лежит рядом с днём, но днём не является (P183).
        guard stamp.count == 10 else { return nil }
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
