import Foundation

/// Тело записи дневника: ответы «Как прошло?» и свободный текст.
///
/// Ответы лежат в том же файле, над текстом, под заголовком — так их видно
/// и в обычном текстовом редакторе, без приложения. Привязаны они к названию
/// дела, а не к его номеру: переставили дела местами — ответы остались при
/// своих делах.
///
/// Всё, что не разобрано, остаётся текстом и возвращается в файл как есть.
struct Diary: Equatable {

    static let heading = "## Как прошло?"

    /// Название дела → ответ.
    var answers: [String: String] = [:]
    var text: String = ""

    init(answers: [String: String] = [:], text: String = "") {
        self.answers = answers
        self.text = text
    }

    init(body: String) {
        var lines = body.components(separatedBy: .newlines)

        // Заголовок ищем только в самом начале: ниже по тексту такая же
        // строка — часть записи человека, и трогать её нельзя.
        var i = 0
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        guard i < lines.count,
              lines[i].trimmingCharacters(in: .whitespaces) == Diary.heading else {
            text = body.trimmingCharacters(in: .newlines)
            return
        }

        lines.removeFirst(i + 1)
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { lines.removeFirst(); continue }
            guard trimmed.hasPrefix("- "), let colon = trimmed.lastIndex(of: ":") else { break }
            let task = String(trimmed.dropFirst(2)[..<colon]).trimmingCharacters(in: .whitespaces)
            let answer = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if !task.isEmpty { answers[task] = answer }
            lines.removeFirst()
        }
        text = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// Собрать обратно. Порядок ответов задаётся списком дел, чтобы файл не
    /// перетасовывался при каждой записи.
    func body(order: [String]) -> String {
        let kept = order.filter { (answers[$0] ?? "").isEmpty == false }
        var out = ""
        if !kept.isEmpty {
            out += Diary.heading + "\n\n"
            for task in kept { out += "- \(task): \(answers[task] ?? "")\n" }
            out += "\n"
        }
        out += text
        return out.trimmingCharacters(in: .newlines)
    }
}
