import SwiftUI

/// Облачко «…помнишь?».
///
/// Выглядывает из-под вкладки «Дневник» на три четверти, шириной примерно
/// в половину вкладки. Негромкое: это не напоминание и не требование, а
/// предложение вернуться к своей же записи (решения P66–P69).
///
/// Если записи за то же число год назад нет — облачка нет вовсе. Пока года
/// записей не накопилось, вспоминается месяц назад.
struct RememberCloud: View {

    let date: Date
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Text("…помнишь?")
                .font(Look.sans(12.5))
                .tracking(0.4)
                .foregroundStyle(Look.inkFaint)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(Look.sticker.opacity(0.92))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14,
                                                  bottomTrailingRadius: 14))
                .overlay(
                    UnevenRoundedRectangle(bottomLeadingRadius: 14,
                                           bottomTrailingRadius: 14)
                        .strokeBorder(Look.stickerEdge, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Прочитанные напоминания.
///
/// Облачко, на которое нажали, больше не зовёт: оно своё дело сделало,
/// а висеть и дальше — значит требовать внимания впустую (решение P136).
///
/// Помечается день, на котором облачко висело: у каждого дня своё
/// воспоминание, и завтрашнее облачко позовёт к другой записи.
enum Remembered {

    /// Ключ для `@AppStorage`: метки дней через пробел. Простая строка
    /// переживает и перезапуск, и обновление приложения.
    static let key = "remember.read"

    /// Дальше не помним: список не должен расти без края.
    private static let limit = 400

    static func has(_ stamp: String, in list: String) -> Bool {
        list.split(separator: " ").contains { $0 == stamp }
    }

    static func adding(_ stamp: String, to list: String) -> String {
        guard !has(stamp, in: list) else { return list }
        var stamps = list.split(separator: " ").map(String.init)
        stamps.append(stamp)
        if stamps.count > limit { stamps.removeFirst(stamps.count - limit) }
        return stamps.joined(separator: " ")
    }
}

/// Листок с записью того же числа год назад.
struct RememberSheet: View {

    let day: Archive.Day
    let ago: Ago
    @Binding var open: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ago.title)
                        .font(Look.sans(12.5))
                        .tracking(0.6)
                        .foregroundStyle(Look.inkFaint)

                    if !day.title.isEmpty {
                        Text(day.title)
                            .font(Look.serif(19, weight: .semibold))
                            .foregroundStyle(Look.ink)
                    }
                    Text(day.text)
                        .font(Look.serif(DiaryView.size))
                        .foregroundStyle(Look.ink)
                        .lineSpacing(DiaryView.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(Look.diaryBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { open = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension Archive {

    /// Что вспомнить в этот день.
    ///
    /// Сначала ищется тот же день год назад — это самое ценное: год спустя
    /// запись читается как чужая. Нет года — месяц. Нет месяца — неделя.
    /// Пустой день не вспоминается: показывать нечего (решение P67).
    func remembered(for date: Date) -> (day: Day, ago: Ago)? {
        let cal = Calendar.current
        var tries: [(Ago, Date)] = []

        for years in 1...5 {
            if let then = cal.date(byAdding: .year, value: -years, to: date) {
                tries.append((.years(years), then))
            }
        }
        if let month = cal.date(byAdding: .month, value: -1, to: date) {
            tries.append((.month, month))
        }
        if let week = cal.date(byAdding: .day, value: -7, to: date) {
            tries.append((.week, week))
        }

        for (ago, when) in tries {
            if let day = self.day(Vault.stamp(when)), !day.text.isEmpty {
                return (day, ago)
            }
        }
        return nil
    }
}

/// Насколько давно. Отдельно, чтобы подпись на листке была человеческой.
enum Ago {
    case years(Int), month, week

    var title: String {
        switch self {
        case .years(1): return "ГОД НАЗАД"
        case .years(let n) where n < 5: return "\(n) ГОДА НАЗАД"
        case .years(let n): return "\(n) ЛЕТ НАЗАД"
        case .month: return "МЕСЯЦ НАЗАД"
        case .week: return "НЕДЕЛЮ НАЗАД"
        }
    }
}
