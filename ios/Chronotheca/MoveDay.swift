import SwiftUI

/// Дело, которое переносят на другой день (P383).
struct MovingTask: Identifiable {
    let id: UUID
}

/// Окно «Перенести на другой день» — открывается, когда дело отвели
/// вправо и отпустили (P383). Сверху — частые ответы одним касанием,
/// ниже — календарь на любой день. Ничего не переносится, пока человек не
/// выбрал день: «Отмена» оставляет дело на месте.
struct MoveDaySheet: View {

    /// День, с которого переносят.
    let from: Date
    let pick: (Date) -> Void
    let cancel: () -> Void

    @State private var day: Date

    init(from: Date, pick: @escaping (Date) -> Void, cancel: @escaping () -> Void) {
        self.from = from
        self.pick = pick
        self.cancel = cancel
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // В календаре сразу стоит завтра — или сегодня, если дело
        // переносят из прошлого.
        let start = from < today ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
        _day = State(initialValue: cal.isDate(start, inSameDayAs: from)
                     ? (cal.date(byAdding: .day, value: 1, to: start) ?? start) : start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Flow(spacing: 8) {
                        ForEach(quick, id: \.0) { item in
                            NoteButton(title: item.0) { pick(item.1) }
                        }
                    }
                    DatePicker("", selection: $day, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.calendar, Prefs.calendar)
                        .environment(\.locale, Lang.locale)
                        .tint(Look.accent)
                    NoteButton(title: T("Перенести на ", "Move to ") + Ru.longDate(day), main: true) {
                        pick(day)
                    }
                    .opacity(same(day) ? 0.4 : 1)
                    .disabled(same(day))
                }
                .padding(16)
            }
            .background(Look.note)
            .navigationTitle(T("На другой день", "To another day"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(T("Отмена", "Cancel"), action: cancel)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Частые ответы: сегодня (если дело не сегодняшнее), завтра,
    /// послезавтра, через неделю — от сегодняшнего дня.
    private var quick: [(String, Date)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func plus(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today) ?? today }
        let list = [(T("Сегодня", "Today"), today),
                    (T("Завтра", "Tomorrow"), plus(1)),
                    (T("Послезавтра", "Day after tomorrow"), plus(2)),
                    (T("Через неделю", "In a week"), plus(7))]
        return list.filter { !same($0.1) }
    }

    private func same(_ d: Date) -> Bool { Calendar.current.isDate(d, inSameDayAs: from) }
}
