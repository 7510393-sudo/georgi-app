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
    @Binding var open: Bool

    var body: some View {
        Button { open = true } label: {
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

/// Листок с записью того же числа год назад.
struct RememberSheet: View {

    let day: Archive.Day
    let years: Int
    @Binding var open: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(heading)
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

    private var heading: String {
        years > 0
            ? (years == 1 ? "ГОД НАЗАД" : "\(years) ГОДА НАЗАД")
            : "МЕСЯЦ НАЗАД"
    }
}

extension Archive {
    /// Что вспомнить в этот день: та же дата год назад, а пока года записей
    /// нет — месяц назад. Пустой день не вспоминается: показывать нечего.
    func remembered(for date: Date) -> (day: Day, years: Int)? {
        let cal = Calendar.current
        for years in [1, 2, 3, 4, 5] {
            guard let then = cal.date(byAdding: .year, value: -years, to: date) else { continue }
            if let day = self.day(Vault.stamp(then)), !day.text.isEmpty {
                return (day, years)
            }
        }
        guard let month = cal.date(byAdding: .month, value: -1, to: date),
              let day = self.day(Vault.stamp(month)), !day.text.isEmpty
        else { return nil }
        return (day, 0)
    }
}
