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

    @State private var kind: Kind = .month
    @State private var shown: Date = DayStore.today()
    @State private var selected: String? = Vault.stamp(DayStore.today())

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            nav

            ScrollView {
                switch kind {
                case .year:  yearGrid
                case .month: monthGrid
                case .list:  monthList
                }
            }
        }
        .onAppear { archive.reload() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                let dx = g.translation.width, dy = g.translation.height
                guard abs(dx) > 64, abs(dx) > abs(dy) * 1.6 else { return }
                shift(by: dx < 0 ? 1 : -1)
            }
        )
    }

    private func shift(by n: Int) {
        let unit: Calendar.Component = kind == .year ? .year : .month
        withAnimation(.easeOut(duration: 0.2)) {
            shown = cal.date(byAdding: unit, value: n, to: shown) ?? shown
        }
    }

    private var nav: some View {
        HStack {
            Button { shift(by: -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(kind == .year ? "Предыдущий год" : "Предыдущий месяц")
            Spacer()
            Text(kind == .year ? String(cal.component(.year, from: shown))
                               : Ru.monthTitle(shown))
                .font(.headline)
            Spacer()
            Button { shift(by: 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(kind == .year ? "Следующий год" : "Следующий месяц")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Год

    private var yearGrid: some View {
        let year = cal.component(.year, from: shown)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                         spacing: 16) {
            ForEach(1...12, id: \.self) { m in
                Button {
                    shown = cal.date(from: DateComponents(year: year, month: m, day: 1)) ?? shown
                    kind = .month
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Ru.monthNames[m - 1].capitalized)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
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
        let lead = (cal.component(.weekday, from: first) + 5) % 7      // понедельник первым
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let today = Vault.stamp(DayStore.today())

        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(11), spacing: 2), count: 7),
                         spacing: 2) {
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 11) }
            ForEach(1...count, id: \.self) { d in
                let stamp = String(format: "%04d-%02d-%02d", year, month, d)
                Text("\(d)")
                    .font(.system(size: 7))
                    .frame(width: 11, height: 11)
                    .foregroundStyle(stamp == today ? Color.white : .secondary)
                    .background(stamp == today ? Color.accentColor
                                : (archive.day(stamp)?.hasSomething == true
                                   ? Color.accentColor.opacity(0.18) : .clear),
                                in: Circle())
            }
        }
    }

    // MARK: - Месяц

    private var monthGrid: some View {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: shown)) ?? shown
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let today = Vault.stamp(DayStore.today())

        return VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(Array(Ru.weekHeader.enumerated()), id: \.offset) { i, name in
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(Ru.dayColor(dateOfWeekday(i)))
                }
                ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...count, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: first) ?? first
                    let stamp = Vault.stamp(date)
                    Button { pick(stamp, date) } label: {
                        VStack(spacing: 2) {
                            Text("\(d)")
                                .font(.callout)
                                .foregroundStyle(stamp == today ? Color.white : .primary)
                                .frame(width: 30, height: 30)
                                .background(stamp == today ? Color.accentColor
                                            : (stamp == selected
                                               ? Color.accentColor.opacity(0.16) : .clear),
                                            in: Circle())
                            Circle()
                                .fill(archive.tasks(stamp).isEmpty ? .clear : Color.accentColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Divider().padding(.vertical, 12)
            dayList
        }
        .padding(.bottom, 20)
    }

    private func dateOfWeekday(_ i: Int) -> Date {
        // Понедельник — первый столбец; берём любой понедельник и шагаем.
        let monday = cal.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? Date()
        return cal.date(byAdding: .day, value: i, to: monday) ?? monday
    }

    @ViewBuilder private var dayList: some View {
        if let stamp = selected, let date = Vault.date(from: stamp) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Ru.weekdayShort(date)) \(Ru.shortDate(date))")
                        .font(.footnote.weight(.medium))
                    Spacer()
                    Button("Открыть день →") { open(date) }
                        .font(.footnote)
                }
                let tasks = archive.tasks(stamp)
                if tasks.isEmpty {
                    Text("Дел на этот день нет.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(tasks) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(task.time ?? "--:--")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(task.text)
                                .font(.footnote)
                                .opacity(task.done ? 0.45 : 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        } else {
            Text("Нажмите дату, чтобы увидеть дела этого дня.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Список

    private var monthList: some View {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: shown)) ?? shown
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let today = Vault.stamp(DayStore.today())

        return LazyVStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let date = cal.date(byAdding: .day, value: i, to: first) ?? first
                let stamp = Vault.stamp(date)
                let tasks = archive.tasks(stamp)
                let open = stamp == selected

                Button { pick(stamp, date) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 1) {
                            Text("\(cal.component(.day, from: date))")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(stamp == today ? Color.accentColor : .primary)
                            Text(Ru.weekdayShort(date))
                                .font(.caption2)
                                .foregroundStyle(Ru.dayColor(date))
                        }
                        .frame(width: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            if tasks.isEmpty {
                                Text(open ? "Дел нет. Нажмите ещё раз, чтобы открыть день →" : "—")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ForEach(open ? tasks : Array(tasks.prefix(3))) { task in
                                    Text((task.time.map { $0 + "  " } ?? "") + task.text)
                                        .font(.footnote)
                                        .opacity(task.done ? 0.45 : 1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if !open && tasks.count > 3 {
                                    Text("ещё \(tasks.count - 3)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                if open {
                                    Text("Нажмите ещё раз, чтобы открыть день →")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(open ? Color.accentColor.opacity(0.08) : .clear)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 58).opacity(0.3)
            }
        }
        .padding(.bottom, 20)
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
