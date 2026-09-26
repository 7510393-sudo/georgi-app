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

    /// Цвет страницы дня — по тому, далеко ли он от сегодня (P245).
    ///
    /// Сегодня — тёплый абрикосовый, самый насыщенный. Прошлое остывает в
    /// серо-голубой, будущее — в шалфейный зелёный; вчера и завтра — ярче,
    /// позавчера и послезавтра — бледнее, дальше цвет не меняется. Так с
    /// одного взгляда видно, в прошлом человек или в будущем и далеко ли
    /// ушёл. Все цвета светлые: текст читается с контрастом не ниже 12 к 1.
    static func tint(_ date: Date) -> Color {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: DayStore.today(),
                                   to: cal.startOfDay(for: date)).day ?? 0
        switch n {
        case ...(-3): return timeTints[0]
        case -2:      return timeTints[1]
        case -1:      return timeTints[2]
        case 0:       return timeTints[3]
        case 1:       return timeTints[4]
        case 2:       return timeTints[5]
        default:      return timeTints[6]
        }
    }

    private static let timeTints: [Color] = [
        Color(light: 0xF1F2F5, dark: 0x181B21),   // три дня назад и раньше
        Color(light: 0xE9ECF3, dark: 0x1A1F28),   // позавчера
        Color(light: 0xDFE5F1, dark: 0x1D2432),   // вчера
        Color(light: 0xFFE2C9, dark: 0x33261B),   // сегодня
        Color(light: 0xE3EFDF, dark: 0x1B2A1D),   // завтра
        Color(light: 0xEBF2E7, dark: 0x1A231B),   // послезавтра
        Color(light: 0xF0F4ED, dark: 0x181E19),   // через три дня и дальше
    ]

    private static let dayColours: [Color] = [
        Color(light: 0xC06A22, dark: 0xE0A06A),   // вс
        Color(light: 0x2F5FA8, dark: 0x7FA6E0),   // пн
        Color(light: 0x2E7D57, dark: 0x6FBF95),   // вт
        Color(light: 0x8A6A12, dark: 0xD4AE55),   // ср
        Color(light: 0x6B4E9E, dark: 0xA88FD6),   // чт
        Color(light: 0xB0403A, dark: 0xE08B84),   // пт
        Color(light: 0x2C7E96, dark: 0x6FC0D6),   // сб
    ]

= [
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

/// Внешний вид: цвета и шрифты прототипа, числами из его же таблицы стилей.
///
/// Вынесено сюда, чтобы «как в прототипе» проверялось сравнением чисел,
/// а не на глаз. План набирается обычным шрифтом с моноширинными цифрами,
/// дневник — засечным на тёплой бумаге: это разные занятия, и рука должна
/// чувствовать разницу, не читая заголовка вкладки.
enum Look {

    static let ink       = Color(light: 0x1C2128, dark: 0xE8EBEE)
    static let inkSoft   = Color(light: 0x56606D, dark: 0xA3ACB7)
    static let inkFaint  = Color(light: 0xA2AAB4, dark: 0x69717C)
    static let rule      = Color(light: 0xE4E5E1, dark: 0x2A3037)
    static let ruleSoft  = Color(light: 0xEFEFEC, dark: 0x222830)
    static let accent    = Color(light: 0x2F4A6B, dark: 0x8FB3E8)
    static let chrome    = Color(light: 0xF4F4F1, dark: 0x191F26)
    static let planBg    = Color(light: 0xFDFDFB, dark: 0x14191F)
    /// Свет из-под превью в режиме изменений: их можно взять (P203).
    static let glow      = Color(light: 0x5E9BF0, dark: 0x7FB2FF)

    /// Торец плашки: светлая грань, лицо, глубина и тёмная грань.
    static let boardLit  = Color(light: 0xFCFAF4, dark: 0x3E4750)
    static let boardFace = Color(light: 0xE9E5DB, dark: 0x2B3239)
    static let boardDeep = Color(light: 0xCFC9BB, dark: 0x1B2127)
    static let boardDark = Color(light: 0xA9A296, dark: 0x0B0F14)

    static let diaryBg   = Color(light: 0xFAF5EC, dark: 0x1B1812)

    /// Бумага приклеенных записок. Жёлтая — меню страницы, голубая —
    /// настройки. Разный цвет, одна порода: канцелярские бумажки,
    /// приклеенные к верхнему краю.
    static let sticker     = Color(light: 0xFBF3D8, dark: 0x2A2517)
    static let stickerEdge = Color(light: 0xE8DCAE, dark: 0x3D3520)
    static let note        = Color(light: 0xE9F1F8, dark: 0x1A2430)
    static let noteEdge    = Color(light: 0xC7DBEC, dark: 0x2C3A48)

    /// Засечный шрифт дневника. Literata в iOS нет, Georgia есть везде.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Georgia", size: size).weight(weight)
    }

    /// Моноширинный — для цифр: часы и номера должны стоять столбиком.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
