import SwiftUI

/// Даты и цвета дней недели.
///
/// Цвет дня недели — из решений: он живёт в названии дня и лёгким оттенком
/// на всём экране. По оттенку день узнаётся раньше, чем прочитана дата.
enum Ru {

    // Имя осталось от времени, когда приложение было только русским; даты
    // теперь на языке приложения (P355).

    private static let ruMonths = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                   "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    private static let enMonths = ["January", "February", "March", "April", "May", "June",
                                   "July", "August", "September", "October", "November", "December"]
    private static let ruMonthNames = ["январь", "февраль", "март", "апрель", "май", "июнь",
                                       "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]

    /// Русский и английский — свои, выверенные; прочие языки (P369) —
    /// как их пишет сам iPhone.
    private static var own: Bool { Lang.code == "ru" || Lang.code == "en" }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Lang.locale
        return f
    }

    private static func pattern(_ template: String, _ date: Date) -> String {
        let f = formatter
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// Месяц в дате: «30 сентября» / «30 September».
    static var months: [String] {
        own ? (Lang.isRussian ? ruMonths : enMonths) : formatter.monthSymbols
    }
    /// Месяц сам по себе: «сентябрь» / «September».
    static var monthNames: [String] {
        own ? (Lang.isRussian ? ruMonthNames : enMonths) : formatter.standaloneMonthSymbols
    }

    /// Порядок как у `Calendar.component(.weekday)`: 1 — воскресенье.
    static var weekdays: [String] {
        guard own else { return formatter.standaloneWeekdaySymbols }
        return Lang.isRussian
            ? ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
            : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }
    static var weekdaysShort: [String] {
        guard own else { return formatter.shortStandaloneWeekdaySymbols.map(trimDot) }
        return Lang.isRussian ? ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
                              : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    }

    /// «So.» → «So»: в клетке календаря точка лишняя.
    private static func trimDot(_ s: String) -> String {
        s.hasSuffix(".") ? String(s.dropLast()) : s
    }

    /// Понедельник первым.
    static var weekHeader: [String] {
        guard own else {
            let short = weekdaysShort
            return Array(short[1...]) + [short[0]]
        }
        return Lang.isRussian ? ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
                              : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    }

    private static func index(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    static func weekday(_ date: Date) -> String { weekdays[index(date)] }
    static func weekdayShort(_ date: Date) -> String { weekdaysShort[index(date)] }

    /// «13 сентября 2026 г.»
    static func longDate(_ date: Date) -> String {
        guard own else { return pattern("dMMMMy", date) }
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        let tail = Lang.isRussian ? " г." : ""
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1]) \(c.year ?? 2026)" + tail
    }

    /// «13 сентября ’26» — год двумя цифрами, для строки под именем дня
    /// (P271).
    static func headDate(_ date: Date) -> String {
        guard own else { return pattern("dMMMMyy", date) }
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1]) ’\(String(format: "%02d", (c.year ?? 2026) % 100))"
    }

    /// «13 сентября»
    static func shortDate(_ date: Date) -> String {
        guard own else { return pattern("dMMMM", date) }
        let c = Calendar.current.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
    }

    static func monthTitle(_ date: Date) -> String {
        guard own else { return pattern("LLLLy", date) }
        let c = Calendar.current.dateComponents([.month, .year], from: date)
        return "\(monthNames[(c.month ?? 1) - 1].capitalized) \(c.year ?? 2026)"
    }

    // MARK: - Цвета

    /// Цвет названия дня недели.
    static func dayColor(_ date: Date) -> Color { dayColours[index(date)] }

    /// Цвет страницы дня — по тому, прошлое это, сегодня или будущее
    /// (P330; раньше было семь ступеней по удалённости, P245, — решили, что
    /// путают и раздражают, оставили три).
    ///
    /// Сегодня — тёплый абрикосовый. Прошлое — серо-голубое, будущее —
    /// шалфейно-зелёное, оба одним и тем же тоном для любой дальности. Все
    /// цвета светлые: текст читается с контрастом не ниже 12 к 1.
    static func tint(_ date: Date) -> Color {
        let cal = Calendar.current
        let n = cal.dateComponents([.day], from: DayStore.today(),
                                   to: cal.startOfDay(for: date)).day ?? 0
        // Будущее — того же цвета, что сегодня (P412): цвет «сегодня»
        // начинается сегодня и идёт дальше; прошлое — своим цветом.
        return n < 0 ? timeTints[0] : timeTints[1]
    }

    private static let timeTints: [Color] = [
        Color(light: 0xF1F2F5, dark: 0x181B21),   // прошлое, любое
        // Бледнее на 15% (P330; было 0xF8E2D0/0x30261E, менее насыщенный
        // цвет прежней шкалы, P321).
        Color(light: 0xF9E6D7, dark: 0x2F2620),   // сегодня
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
    /// На 30% насыщеннее прежнего 0x5E9BF0 (P374): контур поднятого дела,
    /// метки и правки виден сразу.
    static let glow      = Color(light: 0x2F7BEB, dark: 0x5C9EFF)
    /// Булавка точки на карте в тексте — заметная, красная, как булавка
    /// на картах (P358).
    static let pin       = Color(light: 0xD8433A, dark: 0xFF7A6E)

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
    /// Плашка дела (P413): желтоватая, как стикер, светлее у левого
    /// верхнего угла — свет падает оттуда.
    static let plateLight  = Color(light: 0xFFF9E3, dark: 0x3A3426)
    static let plateDark   = Color(light: 0xF4E7BC, dark: 0x2B261A)
    static let stickerEdge = Color(light: 0xE8DCAE, dark: 0x3D3520)
    static let note        = Color(light: 0xE9F1F8, dark: 0x1A2430)
    static let noteEdge    = Color(light: 0xC7DBEC, dark: 0x2C3A48)

    /// Крафт-картон нижней строки разделов (P297): обложка блокнота, одна
    /// во все дни. Значки на нём — тёмно-коричневыми чернилами.
    static let kraft     = Color(light: 0xCBB28C, dark: 0x3A3125)
    static let kraftInk  = Color(light: 0x3A2818, dark: 0xE6D6BA)
    static let kraftEdge = Color(light: 0x96805F, dark: 0x1E1912)
    /// Чернила строки вложений: тёплые тёмные, а не серые (P297).
    static let stripInk  = Color(light: 0x3A3530, dark: 0xD9D2C6)
    /// Бумага облачка «…а помнишь?» — белая (P298).
    static let cloudPaper = Color(light: 0xFFFFFF, dark: 0x2A2517)

    /// Засечный шрифт дневника. Literata в iOS нет, Georgia есть везде.
    /// Шрифт записи можно сменить в настройках (P274).
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch Prefs.fontKey {
        case "newyork": return .system(size: size, weight: weight, design: .serif)
        case "system":  return .system(size: size, weight: weight)
        default:        return .custom("Georgia", size: size).weight(weight)
        }
    }

    /// Моноширинный — для цифр: часы и номера должны стоять столбиком.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Насыщенный синий дат в поиске (P282).
    static let dateBlue = Color(light: 0x1D5BD8, dark: 0x6FA3FF)

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
