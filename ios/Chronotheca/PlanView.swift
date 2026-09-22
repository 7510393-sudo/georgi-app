import SwiftUI

/// Строка дела.
///
/// Одна и та же вещь рисует и открытую страницу, и соседние: разойдутся хоть
/// на точку — при перелистывании строки прыгнут. Правка включается ключами,
/// вид от этого не меняется.
struct PlanRowLine: View {

    let number: Int
    let row: PlanRow
    var faded = false
    var bellColor: Color = Look.inkFaint

    var text: Binding<String>?
    var focus: FocusState<UUID?>.Binding?
    var typing = false
    var editMode = false

    var onTime: (() -> Void)?
    var onBell: (() -> Void)?
    var onDetails: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Высота строки без подробностей. По ней считается перестановка.
    static let height: CGFloat = 54

    @State private var wobble: Double = -6

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            badge
            time
            bell
            title
            if editMode { tools }
            tab
        }
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.done ? 0.42 : 1)
    }

    // MARK: - Части строки

    /// Номер в выпуклом квадратике: за него дело берут и переставляют.
    private var badge: some View {
        Text("\(number)")
            .font(Look.mono(14))
            .foregroundStyle(Look.inkSoft)
            .frame(width: 26, height: 26)
            .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .shadow(color: .black.opacity(editMode ? 0.18 : 0.06),
                    radius: editMode ? 3 : 1, y: 1)
            // В режиме изменений квадратик подрагивает: видно, что дело
            // можно взять и переставить, и видно, что режим включён.
            .rotationEffect(.degrees(editMode ? wobble : 0))
            .animation(editMode
                       ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true)
                       : .default,
                       value: wobble)
            .onAppear { if editMode { wobble = 6 } }
            .onChange(of: editMode) { _, on in wobble = on ? 6 : 0 }
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
    }

    private var time: some View {
        Button { onTime?() } label: {
            Text(row.time ?? "--:--")
                .font(Look.mono(18.5))
                .tracking(row.time == nil ? 0.7 : 0)
                .foregroundStyle(row.time == nil || faded ? Look.inkFaint : Look.inkSoft)
                // Черта рисуется всегда, а не только там, где по ней можно
                // нажать: вид строки не должен зависеть от того, открытая
                // это страница или соседняя.
                .overlay(alignment: .bottom) {
                    Line().stroke(Look.inkFaint,
                                  style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                        .frame(height: 1)
                        .offset(y: 3)
                }
        }
        .buttonStyle(.plain)
        .disabled(onTime == nil)
    }

    private var bell: some View {
        Button { onBell?() } label: {
            Image(systemName: row.bell == nil ? "bell" : "bell.fill")
                .font(.system(size: 20))
                .foregroundStyle(row.bell == nil ? Look.inkFaint : bellColor)
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 11 }
        }
        .buttonStyle(.plain)
        .disabled(onBell == nil)
        .accessibilityLabel(row.bell.map { "Напомнить в \($0)" } ?? "Напоминание не назначено")
    }

    @ViewBuilder private var title: some View {
        if let text, let focus, typing || editMode {
            TextField("", text: text, axis: .vertical)
                .font(Look.sans(15))
                .focused(focus, equals: row.id)
                .submitLabel(.done)
        } else {
            Text(row.text.isEmpty ? "Без названия" : row.text)
                .font(Look.sans(15))
                .lineSpacing(3)
                .foregroundStyle(faded || row.text.isEmpty ? Look.inkFaint : Look.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tools: some View {
        HStack(spacing: 10) {
            Button { onUp?() } label: { Image(systemName: "chevron.up") }
                .accessibilityLabel("Выше")
            Button { onDown?() } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Ниже")
            Button { onDelete?() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Удалить")
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .foregroundStyle(Look.inkFaint)
    }

    /// Закладка «Детали» — корешок, выглядывающий из-за правого края.
    private var tab: some View {
        let filled = !row.details.isEmpty
        return Button { onDetails?() } label: {
            Text("›")
                .font(.system(size: 15))
                .foregroundStyle(filled ? Look.ink : Look.inkSoft)
                .frame(width: 39)
                .frame(maxHeight: .infinity)
                .background(filled ? Look.rule : Look.chrome)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7,
                                                  bottomLeadingRadius: 7))
                .overlay(SideTabBorder(radius: 7)
                    .stroke(filled ? Look.inkSoft : Look.inkFaint, lineWidth: 1))
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(onDetails == nil)
        .opacity(editMode ? 0.25 : 1)
        .accessibilityLabel("Подробности")
    }
}

/// Черта под временем: касанием по ней открывается ролик.
struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// Оправа списка дел: шапка, прокрутка и хвост под списком.
///
/// Открытая страница и соседние собираются из неё одинаково — вплоть до
/// прокрутки. Дважды они расходились по мелочи, и дважды текст прыгал при
/// перелистывании. Общая оправа — единственное, что это исключает (P114).
struct PlanScaffold<Content: View>: View {

    let isPast: Bool
    var dimmed = false
    var add: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            PlanHead(isPast: isPast, dimmed: dimmed, add: add)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

/// Шапка списка дел: «день закрыт» и кнопка «новое дело».
struct PlanHead: View {

    let isPast: Bool
    var dimmed = false
    var add: (() -> Void)?

    var body: some View {
        HStack {
            if isPast {
                Text("день закрыт")
                    .font(Look.mono(11))
                    .tracking(0.45)
                    .foregroundStyle(Look.inkFaint)
            }
            Spacer()
            Text("+")
                .font(.system(size: 21))
                .foregroundStyle(Look.accent)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Look.rule))
                .opacity(dimmed ? 0.3 : 1)
                .onTapGesture { add?() }
                .accessibilityLabel("Новое дело")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, isPast ? 12 : 6)
        .padding(.bottom, isPast ? 8 : 0)
    }
}

// MARK: - Открытая страница

/// Вкладка «План»: дела на день.
struct PlanView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    /// Строка, в которой сейчас правят текст. Отдельно от фокуса клавиатуры:
    /// если показывать поле только у строки в фокусе, в фокус не попасть.
    @State private var typingIn: UUID?
    @FocusState private var focused: UUID?

    /// Дело, которое сейчас тащат за номер, и на сколько оно сдвинуто.
    @State private var dragged: UUID?
    @State private var dragBy = 0

    var body: some View {
        VStack(spacing: 0) {
            if store.editing { banner }
            PlanScaffold(isPast: store.isPast, dimmed: !store.canEditPlan, add: add) {
                if store.tasks.isEmpty { PlanEmpty(isPast: store.isPast) } else { list }
                // Касание по пустому месту убирает клавиатуру и выходит из
                // режима изменений: выход должен быть там, куда рука тянется
                // сама, а не только в кнопке наверху.
                Color.clear
                    .frame(minHeight: 140)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        if store.editing {
                            withAnimation(.easeOut(duration: 0.2)) { store.editing = false }
                        }
                    }
            }
        }
        .onChange(of: focused) { _, now in
            if now == nil { typingIn = nil; store.save() }
        }
        .onChange(of: store.date) { _, _ in typingIn = nil; focused = nil }
        .opacity(store.isPast && !store.editing ? 0.58 : 1)
    }

    private func add() {
        guard let id = store.addTask() else { return shell.say(store.closedReason) }
        typingIn = id
        DispatchQueue.main.async { focused = id }
    }

    private var banner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Режим изменений: правка текста, порядок, удаление.")
                .font(Look.sans(12.5))
            Spacer(minLength: 0)
            Button("Выйти") { store.editing = false }
                .font(Look.sans(12.5))
                .underline()
        }
        .foregroundStyle(Look.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Look.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    @ViewBuilder private var list: some View {
        ForEach($store.planRows) { row in
            if row.wrappedValue.isTask {
                taskRow(row)
                Rectangle().fill(Look.ruleSoft).frame(height: 1)
            }
        }
        stat
    }

    private var stat: some View {
        PlanStat(planned: store.tasks.count, done: store.doneCount)
    }

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        let id = row.wrappedValue.id
        let shown = number(of: id) + (dragged == id ? dragBy : 0)

        return PlanRowLine(
            number: shown,
            row: row.wrappedValue,
            faded: store.isPast && !store.editing,
            bellColor: Ru.dayColor(store.date),
            text: row.text,
            focus: $focused,
            typing: typingIn == id,
            editMode: store.editing,
            onTime: { openRoller(id, .time) },
            onBell: { openRoller(id, .bell) },
            onDetails: { focused = nil; openDetails(id) },
            onUp: { store.move(id, by: -1) },
            onDown: { store.move(id, by: 1) },
            onDelete: { store.delete(id) })
            .offset(y: dragged == id ? CGFloat(dragBy) * PlanRowLine.height : 0)
            .zIndex(dragged == id ? 1 : 0)
            .background(store.editing ? Look.ruleSoft.opacity(0.5) : .clear)
            .contentShape(Rectangle())
            .highPriorityGesture(store.editing ? reorder(id) : nil)
            .onLongPressGesture(minimumDuration: 0.35) {
                guard !store.editing else { return }
                toggle(row)
            }
            .onTapGesture {
                if row.wrappedValue.text.isEmpty, store.canEditPlan {
                    typingIn = id
                    DispatchQueue.main.async { focused = id }
                    return
                }
                guard !store.editing, typingIn != id else { return }
                toggle(row)
            }
    }

    /// Перестановка дела: в режиме изменений дело тащат за номер, и номер на
    /// нём меняется по дороге — видно, куда оно встанет.
    private func reorder(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                dragged = id
                dragBy = Int((g.translation.height / PlanRowLine.height).rounded())
            }
            .onEnded { _ in
                let by = dragBy
                dragged = nil
                dragBy = 0
                guard by != 0 else { return }
                for _ in 0..<abs(by) { store.move(id, by: by > 0 ? 1 : -1) }
            }
    }

    private func openRoller(_ id: UUID, _ kind: Shell.Roller.Kind) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        shell.roller = .init(id: id, kind: kind)
    }

    private func openDetails(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.2)) { shell.drawer = id }
    }

    private func toggle(_ row: Binding<PlanRow>) {
        guard store.canEditPlan else {
            return shell.say("День закрыт. Отметить задним числом — через режим изменений.")
        }
        row.wrappedValue.done.toggle()
        store.save()
    }

    private func number(of id: UUID) -> Int {
        (store.tasks.firstIndex { $0.id == id } ?? 0) + 1
    }
}

extension View {
    /// Убрать клавиатуру. Поднявшуюся клавиатуру должно быть чем опустить,
    /// иначе экран заперт.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

/// Пустой день. Общий для открытой страницы и соседних.
struct PlanEmpty: View {
    let isPast: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("На этот день ничего не запланировано.")
            if !isPast { Text("Нажмите «+», чтобы вписать дело.") }
        }
        .font(Look.sans(14))
        .lineSpacing(5)
        .foregroundStyle(Look.inkFaint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 22)
    }
}

/// Счёт под списком. Тоже общий.
struct PlanStat: View {
    let planned: Int
    let done: Int

    var body: some View {
        Text("Запланировано \(planned) · сделано \(done)")
            .font(Look.mono(11.5))
            .tracking(0.35)
            .foregroundStyle(Look.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 20)
    }
}
