import Foundation

/// Язык приложения (P355): английский или русский, по умолчанию английский.
///
/// Выбирается в настройках, а не языком телефона: человек может держать
/// телефон на одном языке, а дневник вести на другом. Сменили — приложение
/// перерисовывается целиком (`ChronothecaApp`).
enum Lang {
    static let key = "prefs.language"

    static var isRussian: Bool { UserDefaults.standard.string(forKey: key) == "ru" }

    /// Название языка для строки настроек — на нём самом.
    static var name: String { isRussian ? "Русский" : "English" }

    static func toggle() {
        UserDefaults.standard.set(isRussian ? "en" : "ru", forKey: key)
    }
}

/// Надпись на языке приложения. Обе стоят рядом, в том месте кода, где
/// надпись показывается: так их легче держать в согласии, чем в отдельной
/// таблице, и вставки вроде «\(n)» работают в обеих как есть.
func T(_ ru: String, _ en: String) -> String { Lang.isRussian ? ru : en }
