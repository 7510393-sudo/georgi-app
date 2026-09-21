import SwiftUI

/// Русские даты и цвета дней недели.
///
/// Цвет дня недели — из решений: он живёт в названии дня и лёгким оттенком
/// на всём экране. По оттенку день узнаётся раньше, чем прочитана дата.
enum Ru {

    static let months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                         "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    static let monthNames = ["январь", "февраль", "март", "апрель", "май", "июнь",
                             "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]

    /// Порядок как у `Calendar.component(.weekday)`: 1 — воскресенье.
    static let weekdays = ["воскресенье", "понедельник", "вторник", "среда",
                           "четверг", "пятница", "суббота"]
    static let weekdaysShort = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]

    /// Понедельник первым — как в русском календаре.
    static let weekHeader = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]

    private static func index(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    static func weekday(_ date: Date) -> String { weekdays[index(date)] }
    static func weekdayShort(_ date: Date) -> String { weekdaysShort[index(date)] }

    /// «13 сентября 2026 г.»
    static func longDate(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1]) \(c.year ?? 2026) г."
    }

    /// «13 сентября»
    static func shortDate(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
    }

    static func monthTitle(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .year], from: date)
        return "\(monthNames[(c.month ?? 1) - 1].capitalized) \(c.year ?? 2026)"
    }

    // MARK: - Цвета

    /// Цвет названия дня недели.
    static func dayColor(_ date: Date) -> Color { dayColours[index(date)] }

    /// Лёгкий оттенок всего экрана — свой у каждого дня недели.
    static func tint(_ date: Date) -> Color { dayTints[index(date)] }

    private static let dayColours: [Color] = [
        Color(light: 0xC06A22, dark: 0xE0A06A),   // вс
        Color(light: 0x2F5FA8, dark: 0x7FA6E0),   // пн
        Color(light: 0x2E7D57, dark: 0x6FBF95),   // вт
        Color(light: 0x8A6A12, dark: 0xD4AE55),   // ср
        Color(light: 0x6B4E9E, dark: 0xA88FD6),   // чт
        Color(light: 0xB0403A, dark: 0xE08B84),   // пт
        Color(light: 0x2C7E96, dark: 0x6FC0D6),   // сб
    ]

    private static let dayTints: [Color] = [
        Color(light: 0xFBEFE3, dark: 0x291F15),   // вс
        Color(light: 0xEAF0FA, dark: 0x182130),   // пн
        Color(light: 0xE9F3EC, dark: 0x15231B),   // вт
        Color(light: 0xF7F1DE, dark: 0x252015),   // ср
        Color(light: 0xF0EBF8, dark: 0x211B2C),   // чт
        Color(light: 0xFAECEA, dark: 0x2A1B1A),   // пт
        Color(light: 0xE6F2F6, dark: 0x132329),   // сб
    ]
}

extension Color {
    /// Цвет, у которого есть и дневной, и ночной вид.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >>  8) & 0xFF) / 255,
                  blue:  CGFloat( rgb        & 0xFF) / 255,
                  alpha: 1)
    }
}
