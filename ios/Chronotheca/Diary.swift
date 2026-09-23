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

    /// Разобрать тело записи.
    ///
    /// `known` — настоящие названия дел этого дня. Без них строку приходится
    /// делить по двоеточию наугад, а двоеточие бывает и в названии дела
    /// («Позвонить в 10:00»), и в ответе («сделал в 10:30»). Со списком дел
    /// гадать не нужно: название узнаётся целиком (решение P155).
    init(body: String, known: [String] = []) {
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
            guard trimmed.hasPrefix("- ") else { break }
            let rest = String(trimmed.dropFirst(2))

            // Сначала ищем настоящее название дела. Нашлось — делим по нему,
            // и никакие двоеточия внутри не мешают.
            if let task = known.first(where: { !$0.isEmpty && rest.hasPrefix($0 + ":") }) {
                answers[task] = String(rest.dropFirst(task.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
                continue
            }

            // Не нашлось — делим по первому двоеточию: название стоит первым,
            // и всё, что за ним, принадлежит ответу.
            guard let colon = rest.firstIndex(of: ":") else { break }
            let task = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
            let answer = String(rest[rest.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if !task.isEmpty { answers[task] = answer }
            lines.removeFirst()
        }
        text = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// Собрать обратно. Порядок ответов задаётся списком дел, чтобы файл не
    /// перетасовывался при каждой записи.
    ///
    /// Ответы, у которых дела в списке не нашлось, **не выбрасываются**, а
    /// дописываются следом. Раньше выбрасывались — и человек терял
    /// написанное, стоило переименовать дело или удалить его. Написанное
    /// человеком не исчезает оттого, что приложению неудобно (решение P155).
    func body(order: [String]) -> String {
        let written = answers.filter { !$0.value.isEmpty }.keys
        let kept = order.filter { (answers[$0] ?? "").isEmpty == false }
            + written.filter { !order.contains($0) }.sorted()
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
