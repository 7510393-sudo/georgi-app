import Foundation

/// Опись папки: какие дни в ней вообще есть и что в них.
///
/// Календарю и поиску нужно знать про весь архив, а не про один день. Опись
/// собирается чтением папки, а не хранится отдельно: единственный источник
/// правды — файлы. Пересобрать её можно в любой момент, ничего не потеряв.
final class Archive: ObservableObject {

    struct Day: Identifiable {
        var id: String { stamp }
        let stamp: String          // ГГГГ-ММ-ДД
        let date: Date
        var tasks: [PlanRow] = []
        var title: String = ""
        var text: String = ""
        var answers: [String: String] = [:]

        /// Файл дня лежит в iCloud и ещё не скачан. День есть, хотя
        /// прочитать его пока нечем (решение P182).
        var inCloud = false

        var hasSomething: Bool {
            inCloud || !tasks.isEmpty || !title.isEmpty || !text.isEmpty
        }

        /// Начало записи для поиска — без пустых строк.
        ///
        /// В находке под датой умещается три-четыре строки, и отдавать одну
        /// из них пустому месту расточительно: в списке находок важно, что
        /// написано, а не как запись разбита на куски.
        var preview: String {
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        /// Строка, которой день представляется в поиске.
        var line: String {
            if !title.isEmpty { return title }
            if !text.isEmpty { return text.replacingOccurrences(of: "\n", with: " ") }
            return tasks.first(where: { $0.isTask })?.text ?? ""
        }
    }

    @Published private(set) var days: [String: Day] = [:]
    @Published private(set) var scanning = false

    /// Сколько файлов лежит в папке и сколько из них ещё не на телефоне.
    /// Показывается в настройках: человек должен видеть, что записи на
    /// месте, даже когда iCloud их пока не отдал.
    @Published private(set) var files = 0
    @Published private(set) var awayFiles = 0

    /// Идёт ли докачка выгруженных файлов.
    @Published private(set) var fetching = false
    private var fetchRounds = 0

    private let vault: Vault

    init(vault: Vault) { self.vault = vault }

    func day(_ stamp: String) -> Day? { days[stamp] }
    func tasks(_ stamp: String) -> [PlanRow] { days[stamp]?.tasks.filter { $0.isTask } ?? [] }

    /// Дни с записями, от новых к старым.
    var newestFirst: [Day] {
        days.values.filter { $0.hasSomething }.sorted { $0.stamp > $1.stamp }
    }

    func reload() {
        guard let root = vault.root else { days = [:]; return }
        scanning = true
        var found: [String: Day] = [:]
        var listed = 0
        var away: [URL] = []

        for folder in [Vault.Folder.planner, .diary] {
            let base = root.appendingPathComponent(folder.rawValue)
            guard let years = try? FileManager.default.contentsOfDirectory(
                    at: base, includingPropertiesForKeys: nil) else { continue }

            for year in years {
                guard let files = try? FileManager.default.contentsOfDirectory(
                        at: year, includingPropertiesForKeys: nil) else { continue }

                for listed in files {
                    // Выгруженный в iCloud файл лежит невидимой заглушкой
                    // «.ГГГГ-ММ-ДД.md.icloud». Раньше такие дни молча выпадали
                    // из календаря и поиска — будто их не было (решение P182).
                    var name = listed.lastPathComponent
                    if name.hasPrefix("."), name.hasSuffix(".md.icloud") {
                        name = String(name.dropFirst().dropLast(".icloud".count))
                    }
                    guard name.hasSuffix(".md") else { continue }
                    let stamp = String(name.dropLast(".md".count))
                    guard let date = Vault.date(from: stamp) else { continue }
                    let file = year.appendingPathComponent(name)

                    var day = found[stamp] ?? Day(stamp: stamp, date: date)
                    listed += 1
                    let reading = Vault.reading(at: file, coordinated: false)
                    if reading == .away {
                        away.append(file)
                        day.inCloud = true
                        found[stamp] = day
                        continue
                    }
                    guard case .text(let text) = reading else { continue }

                    let parsed = DayFile(text: text)
                    if folder == .planner {
                        day.tasks = Plan.rows(from: parsed.body).filter { $0.isTask }
                    } else {
                        let diary = Diary(body: parsed.body)
                        day.title = parsed.value("заголовок") ?? ""
                        day.text = diary.text
                        day.answers = diary.answers
                    }
                    found[stamp] = day
                }
            }
        }

        days = found
        files = listed
        awayFiles = away.count
        scanning = false
        if away.isEmpty { fetchRounds = 0 } else { fetch(away) }
    }

    /// Докачать выгруженные файлы и перечитать опись.
    ///
    /// iCloud убирает с телефона давние файлы, чтобы освободить место: в
    /// папке они видны, а прочитать их напрямую нельзя. Раньше календарь и
    /// поиск только просили iCloud скачать такой файл и больше к нему не
    /// возвращались — старые записи так и стояли пустыми. Теперь каждый
    /// файл читается через системного посредника: он дожидается, пока файл
    /// придёт, — и опись собирается заново (решение P189).
    ///
    /// Идёт в стороне от экрана: докачка может длиться минутами, а
    /// приложение в это время должно отвечать.
    private func fetch(_ urls: [URL]) {
        guard !fetching, fetchRounds < 5 else { return }
        fetching = true
        fetchRounds += 1
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for url in urls {
                var trouble: NSError?
                NSFileCoordinator(filePresenter: nil)
                    .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                        _ = try? Data(contentsOf: real)
                    }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                self.reload()
            }
        }
    }
}
