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

        var hasSomething: Bool { !tasks.isEmpty || !title.isEmpty || !text.isEmpty }

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

                for file in files where file.pathExtension == "md" {
                    let stamp = file.deletingPathExtension().lastPathComponent
                    guard let date = Vault.date(from: stamp) else { continue }
                    guard let data = try? Data(contentsOf: file),
                          let text = String(data: data, encoding: .utf8) else { continue }

                    let parsed = DayFile(text: text)
                    var day = found[stamp] ?? Day(stamp: stamp, date: date)
                    if folder == .planner {
                        day.tasks = Plan.rows(from: parsed.body).filter { $0.isTask }
                    } else {
                        day.title = parsed.value("заголовок") ?? ""
                        day.text = Diary(body: parsed.body).text
                    }
                    found[stamp] = day
                }
            }
        }

        days = found
        scanning = false
    }
}
