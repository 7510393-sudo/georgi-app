import Foundation

/// Строка плана.
///
/// Это может быть дело — тогда у него есть состояние, необязательное время,
/// текст и строки подробностей. А может быть что угодно другое: заголовок,
/// пустая строка, заметка, дописанная человеком в текстовом редакторе.
///
/// Всё, чего приложение не понимает, хранится в `verbatim` и возвращается
/// в файл нетронутым и на своём месте. Это не мелочь, а прямое следствие
/// обещания: файл принадлежит человеку, а не программе, и программа не
/// имеет права съесть то, чего не поняла.
struct PlanRow: Identifiable, Equatable {
    let id = UUID()

    /// Непустое — значит строка не разобрана и сохраняется как есть.
    var verbatim: String?

    var done = false
    var time: String?

    /// Время напоминания. Живёт в конце строки словами — «(напомнить 08:30)», —
    /// чтобы в текстовом редакторе было понятно, что это, без объяснений.
    var bell: String?

    var text = ""
    var details: [String] = []

    var isTask: Bool { verbatim == nil }

    static func task(time: String? = nil, bell: String? = nil, _ text: String) -> PlanRow {
        PlanRow(verbatim: nil, done: false, time: time, bell: bell, text: text, details: [])
    }

    static func verbatim(_ line: String) -> PlanRow {
        PlanRow(verbatim: line)
    }

    static func == (a: PlanRow, b: PlanRow) -> Bool {
        a.verbatim == b.verbatim && a.done == b.done && a.time == b.time
            && a.bell == b.bell && a.text == b.text && a.details == b.details
    }
}

enum Plan {

    /// Отступ строк подробностей. Он же служит признаком при разборе.
    static let indent = "      "

    // MARK: - Разбор

    static func rows(from body: String) -> [PlanRow] {
        var rows: [PlanRow] = []

        for line in body.components(separatedBy: .newlines) {
            if let task = parseTask(line) {
                rows.append(task)
                continue
            }
            // Строка с отступом сразу после дела — его подробности.
            if !line.trimmingCharacters(in: .whitespaces).isEmpty,
               line.hasPrefix(" "),
               let last = rows.indices.last,
               rows[last].isTask {
                rows[last].details.append(
                    String(line.drop(while: { $0 == " " || $0 == "\t" })))
                continue
            }
            rows.append(.verbatim(line))
        }

        // Хвостовые пустые строки — наши же, при сборке добавится перевод.
        while let last = rows.last, last.verbatim?.isEmpty == true {
            rows.removeLast()
        }
        return rows
    }

    private static func parseTask(_ line: String) -> PlanRow? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("- [") else { return nil }

        let afterBracket = trimmed.dropFirst(3)
        guard let mark = afterBracket.first,
              afterBracket.dropFirst().first == "]" else { return nil }
        let done: Bool
        switch mark {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }

        var rest = String(afterBracket.dropFirst(2))
        if rest.hasPrefix(" ") { rest.removeFirst() }

        var time: String?
        if rest.count >= 5 {
            let candidate = String(rest.prefix(5))
            if isTime(candidate) {
                time = candidate
                rest = String(rest.dropFirst(5))
                if rest.hasPrefix(" ") { rest.removeFirst() }
            }
        }

        var bell: String?
        if let range = rest.range(of: #"\s*\(напомнить (\d{2}:\d{2})\)$"#,
                                  options: .regularExpression) {
            let inside = String(rest[range])
            if let t = inside.range(of: #"\d{2}:\d{2}"#, options: .regularExpression),
               isTime(String(inside[t])) {
                bell = String(inside[t])
                rest.removeSubrange(range)
            }
        }

        return PlanRow(verbatim: nil, done: done, time: time, bell: bell,
                       text: rest, details: [])
    }

    private static func isTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    // MARK: - Сборка

    static func body(from rows: [PlanRow]) -> String {
        var out = ""
        for row in rows {
            if let verbatim = row.verbatim {
                out += verbatim + "\n"
                continue
            }
            out += row.done ? "- [x] " : "- [ ] "
            if let time = row.time { out += time + " " }
            out += row.text
            if let bell = row.bell { out += " (напомнить \(bell))" }
            out += "\n"
            for detail in row.details {
                out += indent + detail + "\n"
            }
        }
        while out.hasSuffix("\n\n") { out.removeLast() }
        if out.hasSuffix("\n") { out.removeLast() }
        return out
    }
}
