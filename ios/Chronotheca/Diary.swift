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

    /// Фотографии дня — ссылки из записи на файлы в папке «Фотографии».
    ///
    /// В файле каждая стоит своей строкой в конце записи, обычной ссылкой
    /// разметки: `![](../../Фотографии/2026/2026-09-24_08.15.30.jpg)`. Её
    /// понимает любой редактор разметки — Obsidian покажет саму фотографию.
    /// В поле записи приложение этих строк не показывает: фотографии стоят
    /// над текстом картинками (решение P200).
    var photos: [String] = []

    init(answers: [String: String] = [:], text: String = "", photos: [String] = []) {
        self.answers = answers
        self.text = text
        self.photos = photos
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
            (text, photos) = Diary.split(body.trimmingCharacters(in: .newlines))
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
        (text, photos) = Diary.split(
            lines.joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    private static let picture = try! NSRegularExpression(
        pattern: #"^\s*!\[[^\]]*\]\((.+)\)\s*$"#)

    /// Отделить строки-фотографии от текста.
    ///
    /// Берутся только строки, в которых нет ничего, кроме ссылки на
    /// картинку: ссылка посреди фразы — часть того, что человек написал.
    static func split(_ text: String) -> (text: String, photos: [String]) {
        var kept: [String] = []
        var photos: [String] = []
        for line in text.components(separatedBy: "\n") {
            let ns = line as NSString
            if let m = picture.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                var link = ns.substring(with: m.range(at: 1))
                if link.hasPrefix("<"), link.hasSuffix(">") {
                    link = String(link.dropFirst().dropLast())
                }
                photos.append(link)
            } else {
                kept.append(line)
            }
        }
        guard !photos.isEmpty else { return (text, []) }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .newlines), photos)
    }

    /// Строка-фотография для файла. Путь с пробелом берётся в угловые
    /// скобки — так его читают редакторы разметки.
    static func line(_ link: String) -> String {
        link.contains(" ") ? "![](<\(link)>)" : "![](\(link))"
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
        if !photos.isEmpty {
            if !out.trimmingCharacters(in: .newlines).isEmpty { out += "\n\n" }
            out += photos.map(Diary.line).joined(separator: "\n")
        }
        return out.trimmingCharacters(in: .newlines)
    }
}
