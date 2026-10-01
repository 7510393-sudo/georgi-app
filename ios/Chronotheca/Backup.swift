import SwiftUI
import UniformTypeIdentifiers

/// Резервная копия архива (P368): вторая папка с теми же записями, снимками
/// и видео — в другом месте, которое человек выбрал сам: флешка, Google
/// Диск, OneDrive, Dropbox.
///
/// Копия делается только кнопкой — приложение само ничего не копирует
/// (главный принцип: всё под рукой человека). Копируется только новое и
/// изменённое; в копии ничего не стирается, даже если в архиве запись
/// удалили, — так копия спасает и от собственной ошибки. Архив копия не
/// трогает: его только читают.
enum Backup {

    static let folderName = "Chronotheca Backup"

    private static let bookmarkKey = "backup.bookmark"
    private static let pathKey = "backup.path"
    private static let lastKey = "backup.last"
    private static let sizeKey = "backup.size"
    private static let sinceKey = "backup.since"
    private static let laterKey = "backup.later"

    // MARK: - Что помним

    /// Когда была последняя копия.
    static var last: Date? {
        let t = UserDefaults.standard.double(forKey: lastKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Сколько весил архив в день последней копии.
    static var sizeAtLast: Int64 { Int64(UserDefaults.standard.double(forKey: sizeKey)) }

    /// Куда копируем — для показа человеку.
    static var placeName: String? { UserDefaults.standard.string(forKey: pathKey) }

    /// Запомнить место копии. Папку человек выбрал в системном окне —
    /// доступ к ней сохраняется закладкой, как к самому архиву.
    static func choose(_ url: URL) -> String? {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData() else {
            return T("Система не дала запомнить эту папку.", "The system did not let the app remember this folder.")
        }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(Vault.friendly(url.path.removingPercentEncoding ?? url.path),
                                  forKey: pathKey)
        return nil
    }

    private static func place() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                           bookmarkDataIsStale: &stale)
        if let url, stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: - Где нельзя

    /// Почему в это место копию класть не стоит; `nil` — можно.
    static func trouble(with dest: URL, archive root: URL) -> String? {
        let a = root.standardizedFileURL.resolvingSymlinksInPath().path
        let b = dest.standardizedFileURL.resolvingSymlinksInPath().path
        if b == a || b.hasPrefix(a + "/") || a.hasPrefix(b + "/") {
            return T("Это та же папка, что и архив, или папка внутри него. Копия должна лежать в другом месте.",
                     "This is the archive folder itself or a folder inside it. The backup must be somewhere else.")
        }
        return nil
    }

    /// Архив и копия в одном iCloud: копия не защитит от беды с iCloud и
    /// займёт там вдвое больше места.
    static func sameCloud(_ dest: URL, archive root: URL) -> Bool {
        let cloud = "com~apple~CloudDocs"
        return dest.path.contains(cloud) && root.path.contains(cloud)
    }

    // MARK: - Копирование

    struct Report {
        var copied = 0
        var same = 0
        /// Файлы, которые ещё не скачаны из iCloud, — их не скопировать.
        var away = 0
        var failed = 0
    }

    /// Скопировать архив в выбранное место. Работает в стороне от главного
    /// потока; `step` — сколько файлов из скольких пройдено.
    static func run(archive root: URL, size: Int64,
                    step: @escaping (Int, Int) -> Void) -> Result<Report, BackupError> {
        guard let dest = place() else { return .failure(.noPlace) }
        let opened = dest.startAccessingSecurityScopedResource()
        defer { if opened { dest.stopAccessingSecurityScopedResource() } }
        if let t = trouble(with: dest, archive: root) { return .failure(.text(t)) }

        let fm = FileManager.default
        let target = dest.appendingPathComponent(folderName)
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            return .failure(.text(T("Не удалось завести папку копии: ", "Could not make the backup folder: ")
                                  + error.localizedDescription))
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
                                      .ubiquitousItemDownloadingStatusKey]
        var files: [URL] = []
        if let walk = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles]) {
            for case let url as URL in walk {
                let v = try? url.resourceValues(forKeys: Set(keys))
                if v?.isDirectory == true { continue }
                files.append(url)
            }
        }

        let head = root.standardizedFileURL.path
        var report = Report()
        for (i, url) in files.enumerated() {
            defer { step(i + 1, files.count) }
            let v = try? url.resourceValues(forKeys: Set(keys))
            // Не скачанный из iCloud файл — пустышка: копировать нечего.
            if let status = v?.ubiquitousItemDownloadingStatus, status != .current {
                report.away += 1
                continue
            }
            let rel = String(url.standardizedFileURL.path.dropFirst(head.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let copy = target.appendingPathComponent(rel)
            let c = try? copy.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if let c, c.fileSize == v?.fileSize,
               let mine = v?.contentModificationDate, let theirs = c.contentModificationDate,
               theirs >= mine {
                report.same += 1
                continue
            }
            do {
                try fm.createDirectory(at: copy.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                // Меняется только файл в папке копии — на свежий из архива.
                if fm.fileExists(atPath: copy.path) {
                    _ = try fm.replaceItemAt(copy, withItemAt: tempCopy(of: url))
                } else {
                    try fm.copyItem(at: url, to: copy)
                }
                report.copied += 1
            } catch {
                report.failed += 1
            }
        }

        let d = UserDefaults.standard
        d.set(Date().timeIntervalSince1970, forKey: lastKey)
        d.set(Double(size), forKey: sizeKey)
        d.removeObject(forKey: laterKey)
        return .success(report)
    }

    private static func tempCopy(of url: URL) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: tmp)
        return tmp
    }

    enum BackupError: Error {
        case noPlace
        case text(String)

        var text: String {
            switch self {
            case .noPlace: return T("Сначала выберите, куда копировать.", "First choose where to copy.")
            case .text(let t): return t
            }
        }
    }

    // MARK: - Напоминание

    /// Сколько весит архив — вместе со снимками, голосом и видео.
    static func size(of root: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .isDirectoryKey]
        if let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in walk {
                guard let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
                total += Int64(v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static let gigabyte: Int64 = 1_000_000_000

    /// Пора ли напомнить — и что сказать. Два правила, что раньше (P368):
    /// с прошлой копии добавился гигабайт — или прошёл месяц, а архив за
    /// это время вырос. Нажали «Позже» — три дня не спрашиваем.
    static func reminder(size: Int64, now: Date = Date()) -> String? {
        let d = UserDefaults.standard
        if d.double(forKey: sinceKey) == 0 { d.set(now.timeIntervalSince1970, forKey: sinceKey) }
        let later = d.double(forKey: laterKey)
        if later > 0, now.timeIntervalSince1970 - later < 3 * 86_400 { return nil }
        let start = last ?? Date(timeIntervalSince1970: d.double(forKey: sinceKey))
        let grew = size - sizeAtLast
        let days = now.timeIntervalSince(start) / 86_400
        let bytes = ByteCountFormatter.string(fromByteCount: max(grew, 0), countStyle: .file)
        if grew >= gigabyte {
            return T("С прошлой копии добавилось \(bytes).", "\(bytes) added since the last backup.")
        }
        if days >= 30, grew > 0 {
            return last == nil
                ? T("Копии записей ещё нет — сделайте её, это несколько минут.",
                    "There is no backup of your entries yet — making one takes a few minutes.")
                : T("Последней копии больше месяца; с тех пор добавилось \(bytes).",
                    "The last backup is over a month old; \(bytes) added since.")
        }
        return nil
    }

    /// Забыть всё о копиях — для проверок.
    static func reset() {
        for key in [bookmarkKey, pathKey, lastKey, sizeKey, sinceKey, laterKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func later() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: laterKey)
    }

    /// «12 дней назад · с тех пор +340 МБ» или «ни разу».
    static func summary(size: Int64?) -> String {
        guard let last else { return T("ещё ни разу", "never yet") }
        let days = Int(Date().timeIntervalSince(last) / 86_400)
        var out = days == 0 ? T("сегодня", "today") : T("\(days) дн. назад", "\(days) days ago")
        if let size, size > sizeAtLast {
            out += T(" · с тех пор +", " · since then +")
                + ByteCountFormatter.string(fromByteCount: size - sizeAtLast, countStyle: .file)
        }
        return out
    }
}

/// Окно резервной копии: что это, куда, и одна кнопка «Скопировать».
/// Каждый шаг — нажатием человека, и перед ним сказано, что будет.
struct BackupSheet: View {

    @EnvironmentObject private var vault: Vault
    @Environment(\.dismiss) private var dismiss

    @State private var choosing = false
    @State private var placeName = Backup.placeName
    @State private var warning: String?
    @State private var progress: (Int, Int)?
    @State private var result: String?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(T("Копия — это вторая папка с теми же записями, снимками и видео, но в другом месте: "
                           + "на флешке или в другом облаке (Google Диск, OneDrive, Dropbox). Случится что-то "
                           + "с телефоном или iCloud — записи останутся там.",
                           "A backup is a second folder with the same entries, photos and videos, kept somewhere "
                           + "else: on a USB stick or in another cloud (Google Drive, OneDrive, Dropbox). If "
                           + "something happens to your phone or iCloud, your entries stay there."))
                    Text(T("Копируется только новое и изменённое. В копии ничего не стирается, даже если "
                           + "запись удалили здесь. Сами записи копия не трогает.",
                           "Only new and changed files are copied. Nothing is ever deleted from the backup, "
                           + "even if you delete an entry here. Your entries themselves are left untouched."))
                        .foregroundStyle(Look.inkSoft)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Куда копировать", "Where to copy")).font(Look.sans(13, weight: .semibold))
                        Text(placeName ?? T("ещё не выбрано", "not chosen yet"))
                            .foregroundStyle(placeName == nil ? Look.inkFaint : Look.ink)
                        Button(placeName == nil ? T("Выбрать место…", "Choose a place…")
                                                : T("Выбрать другое место…", "Choose another place…")) {
                            choosing = true
                        }
                        .buttonStyle(.bordered)
                        if let warning {
                            Text(warning).font(Look.sans(13)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Последняя копия: ", "Last backup: ") + Backup.summary(size: nil))
                            .foregroundStyle(Look.inkSoft)
                        Button {
                            copy()
                        } label: {
                            Text(T("Скопировать сейчас", "Copy now")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(placeName == nil || progress != nil)
                    }

                    if let p = progress {
                        ProgressView(value: Double(p.0), total: Double(max(p.1, 1)))
                        Text(T("Скопировано файлов: \(p.0) из \(p.1)", "Files: \(p.0) of \(p.1)"))
                            .font(Look.sans(13)).foregroundStyle(Look.inkSoft)
                    }
                    if let result {
                        Text(result).font(Look.sans(14, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let problem {
                        Text(problem).font(Look.sans(14)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(Look.sans(15))
                .padding(20)
            }
            .navigationTitle(T("Резервная копия", "Backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { dismiss() }.disabled(progress != nil)
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { picked in
                guard case .success(let url) = picked else { return }
                pick(url)
            }
        }
        .interactiveDismissDisabled(progress != nil)
    }

    private func pick(_ url: URL) {
        problem = nil
        result = nil
        if let root = vault.root, let t = Backup.trouble(with: url, archive: root) {
            problem = t
            return
        }
        if let t = Backup.choose(url) {
            problem = t
            return
        }
        placeName = Backup.placeName
        warning = vault.root.map { Backup.sameCloud(url, archive: $0) } == true
            ? T("Это тот же iCloud, где лежат записи: от беды с iCloud такая копия не спасёт и займёт там "
                + "вдвое больше места. Лучше флешка или другое облако.",
                "This is the same iCloud your entries are in: such a backup will not help if something "
                + "happens to iCloud, and it takes twice the space there. A USB stick or another cloud is better.")
            : nil
    }

    private func copy() {
        guard let root = vault.root else { return }
        problem = nil
        result = nil
        progress = (0, 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let size = Backup.size(of: root)
            let outcome = Backup.run(archive: root, size: size) { done, all in
                DispatchQueue.main.async { progress = (done, all) }
            }
            DispatchQueue.main.async {
                progress = nil
                switch outcome {
                case .failure(let e):
                    problem = e.text
                case .success(let r):
                    Feel.done()
                    var text = r.copied == 0
                        ? T("Готово: копия и так свежая.", "Done: the backup was already up to date.")
                        : T("Готово: скопировано файлов — \(r.copied).", "Done: \(r.copied) files copied.")
                    if r.away > 0 {
                        text += T(" Ещё в iCloud и не скопированы: \(r.away) — откройте их или повторите позже.",
                                  " Still in iCloud and not copied: \(r.away) — try again later.")
                    }
                    if r.failed > 0 {
                        text += T(" Не скопировались: \(r.failed).", " Could not copy: \(r.failed).")
                    }
                    result = text
                }
            }
        }
    }
}

/// Напоминание о копии (P368): при возвращении в приложение, не чаще раза в
/// три дня после «Позже». Окно с двумя кнопками — само ничего не копирует.
struct BackupReminder: ViewModifier {
    @EnvironmentObject private var vault: Vault
    @Environment(\.scenePhase) private var phase

    @State private var message: String?
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, now in if now == .active { check() } }
            .onAppear(perform: check)
            .alert(T("Пора сделать резервную копию", "Time to make a backup"),
                   isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(T("Сделать копию", "Make a backup")) {
                    message = nil
                    showing = true
                }
                Button(T("Позже", "Later"), role: .cancel) {
                    Backup.later()
                    message = nil
                }
            } message: {
                Text((message ?? "") + T(" Копия ляжет туда, куда вы скажете; приложение само ничего не копирует.",
                                         " It goes wherever you choose; the app never copies anything by itself."))
            }
            .sheet(isPresented: $showing) { BackupSheet().environmentObject(vault) }
    }

    private func check() {
        guard !Vault.isPreview, let root = vault.root else { return }
        DispatchQueue.global(qos: .utility).async {
            let say = Backup.reminder(size: Backup.size(of: root))
            DispatchQueue.main.async { if let say { message = say } }
        }
    }
}
