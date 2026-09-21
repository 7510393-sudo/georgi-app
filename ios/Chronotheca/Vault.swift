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
        08:15 Проснулся раньше будильника, впервые за неделю. Туман над полем\
         такой плотный, что не видно второго ряда деревьев.

        23:40 В поликлинику так и не собрался. Зато глава дописана, и\
         кажется, что она вышла лучше первой.
        """)
        diary.set("дата", Vault.stamp(today))
        diary.set("заголовок", "Туман")
        write(diary.text, to: .diary, for: today)
    }

    // MARK: - Папка

    /// Пользователь выбрал папку в системном окне.
    func adopt(_ url: URL) {
        guard begin(url) else {
            problem = "Система не дала доступ к этой папке."
            return
        }
        do {
            let subpath = try chooseSubpath(in: url)
            let target = subpath.isEmpty ? url : url.appendingPathComponent(subpath)

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

    /// Куда класть записи внутри выбранного места.
    ///
    /// Если человек указал папку, где наши записи уже лежат, — работаем прямо
    /// в ней: он вернулся к своему архиву. Во всех остальных случаях заводим
    /// внутри свою папку, чтобы не рассыпать семь подпапок по чужому месту.
    /// Это важнее, чем кажется: без этого выбор «Документы» превращает
    /// документы в свалку, и найти потом ничего нельзя.
    private func chooseSubpath(in url: URL) throws -> String {
        if isOurs(url) { return "" }
        if isOurs(url.appendingPathComponent(Vault.folderName)) { return Vault.folderName }

        let nested = url.appendingPathComponent(Vault.folderName)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        return Vault.folderName
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
            return false
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

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
