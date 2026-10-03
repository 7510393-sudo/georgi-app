import SwiftUI

/// Дело, которое переносят на другой день (P383).
struct MovingTask: Identifiable, Equatable {
    let id: UUID
    let title: String
}

/// Листок «На другой день» (P383, P387): дело отвели вправо и отпустили —
/// сверху свешивается жёлтый листок той же породы, что меню страницы (это
/// тоже про день). На нём частые ответы одним касанием и месяц той же
/// сеткой и в тех же цветах, что раздел «Календарь». Прежде здесь был
/// системный экран снизу с календарём iOS — он выпадал из бумажного вида.
///
/// Ничего не переносится, пока человек не выбрал день: крестик или касание
/// мимо листка оставляют дело на месте.
struct MoveDaySticker: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    let task: MovingTask

    /// Какой месяц показан.
    @State private var month = Date()
    /// Выбранный в сетке день — переносится только по кнопке под сеткой.
    @State private var chosen: Date?

    private var cal: Calendar { Prefs.calendar }

    var body: some View {
        Sticker(side: .trailing, title: T("На другой день", "To another day"),
                width: min(340, UIScreen.main.bounds.width - 40), close: close) {
            VStack(alignment: .leading, spacing: 10) {
                if !task.title.isEmpty {
                    Text("«\(task.title)»")
                        .font(Look.serif(15))
                        .foregroundStyle(Look.inkSoft)
                        .lineLimit(2)
                }
                Flow(spacing: 6) {
                    ForEach(quick, id: \.0) { item in
                        NoteButton(title: item.0) { move(to: item.1) }
                    }
                }
                monthHead
                grid
                NoteButton(title: chosen.map { T("Перенести на ", "Move to ") + Ru.shortDate($0) }
                                  ?? T("Выберите день", "Choose a day"),
                           main: chosen != nil) {
                    if let chosen { move(to: chosen) }
                }
                .opacity(chosen == nil ? 0.5 : 1)
                .disabled(chosen == nil)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .onAppear {
            month = store.date < DayStore.today() ? DayStore.today() : store.date
        }
    }

    // MARK: - Месяц

    private var monthHead: some View {
        HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 30)
            }
            Spacer()
            Text(Ru.monthTitle(month))
                .font(Look.serif(17, weight: .semibold))
                .foregroundStyle(Look.ink)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 30)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Look.accent)
        .padding(.top, 4)
    }

    private var grid: some View {
        let cells = MonthGrid.cells(of: month, calendar: cal, firstWeekday: cal.firstWeekday)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                         spacing: 3) {
            ForEach(Array(header.enumerated()), id: \.offset) { _, name in
                Text(name.uppercased())
                    .font(Look.sans(9.5, weight: .semibold))
                    .foregroundStyle(Look.inkFaint)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day { cell(day) } else { Color.clear.frame(height: 30) }
            }
        }
    }

    /// Клетка дня — того же цвета, что в «Календаре»; сегодняшний — крупнее
    /// и жирнее, день самого дела обведён пунктиром и не нажимается,
    /// выбранный — синим ободком.
    private func cell(_ day: Date) -> some View {
        let isToday = cal.isDate(day, inSameDayAs: DayStore.today())
        let isFrom = cal.isDate(day, inSameDayAs: store.date)
        let isChosen = chosen.map { cal.isDate($0, inSameDayAs: day) } ?? false
        return Button {
            Feel.tick()
            chosen = day
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(Look.sans(isToday ? 16 : 13.5, weight: isToday ? .bold : .medium))
                .foregroundStyle(Look.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(tint(day), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isChosen {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Look.accent, lineWidth: 2)
                    } else if isFrom {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Look.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isFrom)
    }

    private var header: [String] {
        cal.firstWeekday == 1 ? [Ru.weekHeader.last ?? ""] + Array(Ru.weekHeader.dropLast()) : Ru.weekHeader
    }

    /// Цвет клетки — как выбрано для «Календаря» в настройках (P290).
    private func tint(_ date: Date) -> Color {
        switch UserDefaults.standard.string(forKey: Prefs.calendarTint) ?? "distance" {
        case "weekday": return Ru.dayColor(date).opacity(0.14)
        case "none":    return Look.planBg
        default:        return Ru.tint(date)
        }
    }

    private func shift(_ by: Int) {
        Feel.light()
        month = cal.date(byAdding: .month, value: by, to: month) ?? month
    }

    // MARK: - Перенос

    /// Частые ответы: сегодня (если дело не сегодняшнее), завтра,
    /// послезавтра, через неделю — от сегодняшнего дня.
    private var quick: [(String, Date)] {
        let today = DayStore.today()
        func plus(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today) ?? today }
        let list = [(T("Сегодня", "Today"), today),
                    (T("Завтра", "Tomorrow"), plus(1)),
                    (T("Послезавтра", "Day after tomorrow"), plus(2)),
                    (T("Через неделю", "In a week"), plus(7))]
        return list.filter { !cal.isDate($0.1, inSameDayAs: store.date) }
    }

    private func move(to day: Date) {
        var gone = false
        withAnimation(.easeOut(duration: 0.2)) { gone = store.moveTask(task.id, to: day) }
        if gone {
            Feel.thud()
            shell.say(T("Дело перенесено на ", "Task moved to ") + Ru.shortDate(day))
        } else {
            shell.say(T("Не вышло перенести: файл того дня ещё не скачан из iCloud или его меняют в другом месте. Попробуйте ещё раз.",
                        "Could not move the task: that day’s file is not downloaded from iCloud yet or is being changed elsewhere. Try again."))
        }
        close()
    }

    private func close() {
        withAnimation(.tuck) { shell.movingTask = nil }
    }
}
