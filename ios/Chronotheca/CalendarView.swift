import SwiftUI

/// Календарь: год, месяц и список месяца.
///
/// Первое касание даты разворачивает дела этого дня, второе открывает день.
/// Так можно заглянуть в дату, не теряя места, где стоишь.
struct CalendarView: View {

    enum Kind: String, CaseIterable, Identifiable {
        case year = "Год", month = "Месяц", list = "Список"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    /// Вид запоминается между заходами: человек, оставивший «Список»,
    /// возвращается в «Список», а не в чужой ему «Месяц».
    @AppStorage("calendar.kind") private var stored = Kind.month.rawValue
    private var kind: Kind { Kind(rawValue: stored) ?? .month }
    @State private var shown: Date = DayStore.today()
    @State private var selected: String? = Vault.stamp(DayStore.today())

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            Text("Календарь")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Look.ink)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                ForEach(Kind.allCases) { k in
                    Button { stored = k.rawValue } label: {
                        Text(k.rawValue)
                            .font(Look.sans(13))
                            .foregroundStyle(kind == k ? Look.planBg : Look.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(kind == k ? Look.accent : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(kind == k ? Look.accent : Look.rule))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            PageCurl { offset in
                page(at: step(offset), current: offset == 0)
                    .environmentObject(store)
                    .environmentObject(archive)
                    .environmentObject(shell)
            } onTurn: { step in
                shown = shift(shown, by: step)
                // Бегунок снимается: дело выбранного дня к новому месяцу
                // отношения не имеет и висеть под ним не должно.
                selected = nil
            }
        }
        .onAppear { archive.reload() }
    }

    /// Страница календаря целиком: название, сетка и список дел под ней.
    ///
    /// Название едет вместе со страницей — оно к ней и относится. А список
    /// дел показывается только на той странице, на которой человек стоит:
    /// на соседнем месяце дела сегодняшнего дня — чужие.
    private func page(at date: Date, current: Bool) -> some View {
        VStack(spacing: 0) {
            nav(for: date)
            ScrollView {
                VStack(spacing: 0) {
                    switch kind {
                    case .year:  yearGrid(of: date)
                    case .month: monthGrid(of: date, current: current)
                    case .list:  monthList(of: date)
                    }
                }
            }
        }
        .background(Look.planBg)
    }

    private func step(_ offset: Int) -> Date { shift(shown, by: offset) }

    private func shift(_ date: Date, by n: Int) -> Date {
        let unit: Calendar.Component = kind == .year ? .year : .month
        return cal.date(byAdding: unit, value: n, to: date) ?? date
    }

    private func nav(for date: Date) -> some View {
        let toward = towardToday(from: date)
        return HStack {
            arrow("‹", lit: toward < 0, label: kind == .year ? "Предыдущий год"
                                                            : "Предыдущий месяц") {
                shown = shift(shown, by: -1)
                selected = nil
            }
            Spacer()
            Text(kind == .year ? String(cal.component(.year, from: date))
                               : Ru.monthTitle(date))
                .font(Look.sans(16, weight: .semibold))
                .foregroundStyle(Look.ink)
            Spacer()
            arrow("›", lit: toward > 0, label: kind == .year ? "Следующий год"
                                                            : "Следующий месяц") {
                shown = shift(shown, by: 1)
                selected = nil
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    /// Стрелка. Та, что смотрит в сторону сегодняшнего месяца, горит:
    /// уйдя на июнь, человек видит, что «сейчас» — справа, и не гадает,
    /// в какую сторону возвращаться.
    private func arrow(_ sign: String, lit: Bool, label: String,
                       act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(sign)
                .font(.system(size: 22, weight: lit ? .semibold : .regular))
                .foregroundStyle(lit ? Look.accent : Look.inkFaint)
                .frame(width: 34, height: 30)
                .background(lit ? Look.accent.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(lit ? label + ", к сегодняшнему дню" : label)
    }

    /// В какой стороне сегодняшний месяц: −1 слева, +1 справа, 0 — мы на нём.
    private func towardToday(from date: Date) -> Int {
        let here = period(date), now = period(DayStore.today())
        if here < now { return 1 }
        if here > now { return -1 }
        return 0
    }

    private func period(_ date: Date) -> Date {
        let parts: Set<Calendar.Component> = kind == .year ? [.year] : [.year, .month]
        return cal.date(from: cal.dateComponents(parts, from: date)) ?? date
    }

    // MARK: - Год

    private func yearGrid(of date: Date) -> some View {
        let year = cal.component(.year, from: date)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                         spacing: 16) {
            ForEach(1...12, id: \.self) { m in
                Button {
                    shown = cal.date(from: DateComponents(year: year, month: m, day: 1)) ?? shown
                    stored = Kind.month.rawValue
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Ru.monthNames[m - 1].capitalized)
                            .font(Look.sans(11, weight: .medium))
                            .foregroundStyle(Look.ink)
                        miniMonth(year: year, month: m)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }

    private func miniMonth(year: Int, month: Int) -> some View {
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let cells = MonthGrid.cells(of: first, calendar: cal)
        let today = Vault.stamp(DayStore.today())

        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(11), spacing: 2), count: 7),
                         spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let stamp = Vault.stamp(day)
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 7))
                        .frame(width: 11, height: 11)
                        .foregroundStyle(stamp == today ? Color.white : Look.inkFaint)
                        .background(stamp == today ? Look.accent
                                    : (archive.day(stamp)?.hasSomething == true
                                       ? Look.accent.opacity(0.18) : .clear),
                                    in: Circle())
                } else {
                    Color.clear.frame(height: 11)
                }
            }
        }
    }

    // MARK: - Месяц

    /// Сетка на пятую часть плотнее прежней: место внизу нужнее списку дел,
    /// ради которого в календарь и заходят.
    private func monthGrid(of date: Date, current: Bool) -> some View {
        let cells = MonthGrid.cells(of: date, calendar: cal)
        let today = Vault.stamp(DayStore.today())

        return VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                      spacing: 4) {
                ForEach(Array(Ru.weekHeader.enumerated()), id: \.offset) { i, name in
                    Text(name.uppercased())
                        .font(Look.sans(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Ru.dayColor(dateOfWeekday(i)))
                        .padding(.bottom, 3)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day, today: today) } else { Color.clear.frame(height: 32) }
                }
            }
            .padding(.horizontal, 10)

            Rectangle().fill(Look.rule).frame(height: 1).padding(.vertical, 10)
            if current { dayList }
        }
        .padding(.bottom, 20)
    }

    /// Клетка дня. Сегодняшний обведён, выбранный залит: «сегодня» и «то, на
    /// что я смотрю» должны различаться с одного взгляда.
    private func cell(_ date: Date, today: String) -> some View {
        let stamp = Vault.stamp(date)
        let isToday = stamp == today
        let isSelected = stamp == selected

        // Сегодняшний день залит — он есть всегда и ни от чего не зависит.
        // Выбранный обведён лёгким ободком: внимание можно переставить, и
        // оно не должно выглядеть весомее самого дня.
        return Button { pick(stamp, date) } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: date))")
                    .font(Look.sans(14))
                    .foregroundStyle(isToday ? Look.planBg : Look.ink)
                dots(count: archive.tasks(stamp).count, light: isToday)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isToday ? Look.accent : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected && !isToday ? Look.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Точек столько, сколько дел, но не больше трёх: по ним видно,
    /// насколько день занят, не открывая его.
    private func dots(count: Int, light: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle()
                    .fill(light ? Look.planBg : Look.inkFaint)
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(height: 3.5)
    }

    private func dateOfWeekday(_ i: Int) -> Date {
        let monday = cal.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? Date()
        return cal.date(byAdding: .day, value: i, to: monday) ?? monday
    }

    @ViewBuilder private var dayList: some View {
        if let stamp = selected, let date = Vault.date(from: stamp) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Ru.weekdayShort(date)) \(Ru.shortDate(date))")
                        .font(Look.sans(13, weight: .medium))
                        .foregroundStyle(Look.ink)
                    Spacer()
                    Button("Открыть день →") { open(date) }
                        .font(Look.sans(13))
                        .foregroundStyle(Look.accent)
                }
                let tasks = archive.tasks(stamp)
                if tasks.isEmpty {
                    Text("Дел на этот день нет.")
                        .font(Look.sans(13))
                        .foregroundStyle(Look.inkFaint)
                } else {
                    ForEach(tasks) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(task.time ?? "--:--")
                                .font(Look.mono(12))
                                .foregroundStyle(Look.inkFaint)
                            Text(task.text)
                                .font(Look.sans(13))
                                .foregroundStyle(Look.ink)
                                .opacity(task.done ? 0.45 : 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        } else {
            Text("Нажмите дату, чтобы увидеть дела этого дня.")
                .font(Look.sans(13))
                .foregroundStyle(Look.inkFaint)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Список

    private func monthList(of date: Date) -> some View {
        let cells = MonthGrid.cells(of: date, calendar: cal).compactMap { $0 }
        let today = Vault.stamp(DayStore.today())

        return LazyVStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                row(day, today: today)
                weekRule(after: day)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }

    private func row(_ date: Date, today: String) -> some View {
        let stamp = Vault.stamp(date)
        let tasks = archive.tasks(stamp)
        let open = stamp == selected

        return Button { pick(stamp, date) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 1) {
                    Text("\(cal.component(.day, from: date))")
                        .font(Look.mono(15))
                        .foregroundStyle(stamp == today ? Look.accent : Look.ink)
                    Text(Ru.weekdayShort(date))
                        .font(Look.sans(10))
                        .foregroundStyle(Ru.dayColor(date))
                }
                .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    if tasks.isEmpty {
                        Text(open ? "Дел нет. Нажмите ещё раз, чтобы открыть день →" : "—")
                            .font(Look.sans(13))
                            .foregroundStyle(Look.inkFaint)
                    } else {
                        ForEach(open ? tasks : Array(tasks.prefix(3))) { task in
                            Text((task.time.map { $0 + "  " } ?? "") + task.text)
                                .font(Look.sans(13))
                                .foregroundStyle(Look.ink)
                                .opacity(task.done ? 0.45 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !open && tasks.count > 3 {
                            Text("ещё \(tasks.count - 3)")
                                .font(Look.sans(11))
                                .foregroundStyle(Look.inkFaint)
                        }
                        if open {
                            Text("Нажмите ещё раз, чтобы открыть день →")
                                .font(Look.sans(11))
                                .foregroundStyle(Look.inkFaint)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(open ? Look.ruleSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Разделение недель: воскресенье отбивается жирной чертой — это конец
    /// недели; пятница тонкой — за ней начинаются выходные. Так месяц
    /// читается ритмом, а не сплошным столбцом.
    @ViewBuilder private func weekRule(after date: Date) -> some View {
        let weekday = cal.component(.weekday, from: date)
        if weekday == 1 {
            Rectangle().fill(Look.inkFaint).frame(height: 2)
        } else if weekday == 6 {
            Rectangle().fill(Look.inkFaint).opacity(0.55).frame(height: 1)
        } else {
            Rectangle().fill(Look.ruleSoft).frame(height: 1)
        }
    }

    // MARK: - Касания

    private func pick(_ stamp: String, _ date: Date) {
        if selected == stamp { open(date) } else { selected = stamp }
    }

    private func open(_ date: Date) {
        store.go(to: date)
        shell.tab = .plan
        shell.screen = .today
    }
}
