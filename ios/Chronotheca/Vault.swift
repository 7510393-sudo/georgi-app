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

    @Published private(set) var root: URL?
    @Published private(set) var problem: String?

    private static let bookmarkKey = "vault.root.bookmark"
    private var accessing: URL?

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
            UserDefaults.standard.set(try url.bookmarkData(), forKey: Vault.bookmarkKey)
            try makeTree(in: url)
            root = url
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Vault.bookmarkKey)
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        root = nil
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
                problem = "Папка больше недоступна. Выберите её заново."
                return
            }
            root = url
            if stale, let fresh = try? url.bookmarkData() {
                UserDefaults.standard.set(fresh, forKey: Vault.bookmarkKey)
            }
        } catch {
            problem = "Не удалось открыть прежнюю папку. Выберите её заново."
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

    private func makeTree(in url: URL) throws {
        for folder in Folder.allCases {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(folder.rawValue),
                withIntermediateDirectories: true)
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
