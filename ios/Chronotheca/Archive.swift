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
                    let reading = Vault.reading(at: file, coordinated: false)
                    if reading == .away {
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
        scanning = false
    }
}
