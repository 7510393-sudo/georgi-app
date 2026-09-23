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

    /// Нажали по цифрам или по колокольчику. Передаётся и место клетки:
    /// барабан встаёт на неё, а не выезжает снизу (решение P173).
    var onTime: ((CGRect) -> Void)?
    var onBell: ((CGRect) -> Void)?
    var onDetails: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Высота строки без подробностей. По ней считается перестановка.
    static let height: CGFloat = 54

    @State private var wobble: Double = -6

    /// Где проходит строчка названия — считая от верха его площадки.
    ///
    /// Пустое поле ввода и готовый текст сами по себе садятся на разную
    /// высоту: заведёшь дело — название стоит на полстроки ниже времени и
    /// колокольчика, наберёшь первую букву — подскакивает. Поэтому строчка
    /// задаётся числом, одним и тем же для обоих видов: что бы ни было
    /// внутри, строка не шелохнётся (решение P171).
    @ScaledMetric(relativeTo: .body) private var titleBaseline: CGFloat = 14

    /// Где на странице стоят цифры и колокольчик.
    @State private var spot = RowSpot()

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

    // MARK: - Подрагивание номера

    private func startWobble() {
        wobble = -6
        withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
            wobble = 6
        }
    }

    /// Повторяющийся ход сам не гаснет: его надо снять мгновенным ходом, а
    /// не просто задать новое значение. Иначе номера дрожали до тех пор,
    /// пока страницу не перелистнут (решение P157).
    private func stopWobble() {
        withAnimation(.linear(duration: 0)) { wobble = 0 }
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
            // Номер — рукоять, а не текст: касание по нему не должно
            // ставить курсор в строку (решение P167).
            .contentShape(Rectangle())
            .onTapGesture { }
            .onAppear { if editMode { startWobble() } }
            .onChange(of: editMode) { _, on in on ? startWobble() : stopWobble() }
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
    }

    private var time: some View {
        Button { onTime?(spot.time) } label: {
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
        // Не .disabled: система рисует выключенную кнопку бледнее, и время
        // на соседней странице выцветало, а после поворота «загоралось».
        // Вид не должен зависеть от того, можно ли нажать (P130).
        .allowsHitTesting(onTime != nil)
        .spotted { spot.time = $0 }
    }

    private var bell: some View {
        Button { onBell?(spot.bell) } label: {
            Image(systemName: row.bell == nil ? "bell" : "bell.fill")
                .font(.system(size: 20))
                .foregroundStyle(row.bell == nil ? Look.inkFaint : bellColor)
                .frame(width: 40, height: 38)
                .contentShape(Rectangle())
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 11 }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(onBell != nil)
        .spotted { spot.bell = $0 }
        .accessibilityLabel(row.bell.map { "Напомнить в \($0)" } ?? "Напоминание не назначено")
    }

    @ViewBuilder private var title: some View {
        if let text, let focus, typing || editMode {
            TextField("", text: text, axis: .vertical)
                .font(Look.sans(15))
                .focused(focus, equals: row.id)
                .submitLabel(.done)
                .alignmentGuide(.firstTextBaseline) { _ in titleBaseline }
        } else {
            Text(row.text.isEmpty ? "Без названия" : row.text)
                .font(Look.sans(15))
                .lineSpacing(3)
                .foregroundStyle(faded || row.text.isEmpty ? Look.inkFaint : Look.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .alignmentGuide(.firstTextBaseline) { _ in titleBaseline }
        }
    }

    /// В режиме изменений — только крестик.
    ///
    /// Стрелки вверх-вниз убраны: они повторяли то, что и так делается
    /// перетаскиванием за номер. Крестик вдвое крупнее прежнего — в мелкий
    /// пальцем не попасть (решение P158).
    private var tools: some View {
        HStack(spacing: 10) {
            Button { onDelete?() } label: {
                Image(systemName: "xmark")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить")
        }
        .font(.system(size: 17))
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
        .allowsHitTesting(onDetails != nil)
        .opacity(editMode ? 0.25 : 1)
        .accessibilityLabel("Подробности")
    }
}

/// Ящик для замера: где на странице стоят цифры и колокольчик.
///
/// Ссылочный нарочно. Запись в него не считается изменением вида, поэтому
/// прокрутка не перерисовывает каждую строку на каждом кадре — а замер
/// нужен всего один раз, в тот миг, когда по клетке нажали (решение P173).
final class RowSpot {
    var time: CGRect = .zero
    var bell: CGRect = .zero
}

extension View {
    /// Запоминать, где эта вещь стоит на странице плана.
    func spotted(_ keep: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { place -> Color in
                keep(place.frame(in: .named(Plan.space)))
                return Color.clear
            }
        }
    }
}

/// Черта конца недели: прямая, у которой концы загнуты вверх.
///
/// Так она выглядела в прототипе: там это был нижний край скруглённой рамки
/// строки, и загиб получался сам собой. Здесь его приходится рисовать
/// нарочно — но без него неделя не отбивается, а просто подчёркивается.
struct WeekEnd: Shape {

    /// Насколько концы уходят вверх. Чуть-чуть: это намёк, а не скоба.
    var rise: CGFloat = 6

    func path(in r: CGRect) -> Path {
        var p = Path()
        let низ = r.maxY
        p.move(to: CGPoint(x: r.minX, y: низ - rise))
        p.addQuadCurve(to: CGPoint(x: r.minX + rise, y: низ),
                       control: CGPoint(x: r.minX, y: низ))
        p.addLine(to: CGPoint(x: r.maxX - rise, y: низ))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: низ - rise),
                       control: CGPoint(x: r.maxX, y: низ))
        return p
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

    /// Строка, в которую сейчас пишут: её и надо держать на виду.
    var watching: UUID?

    @ViewBuilder let content: () -> Content

    @State private var keyboard: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            PlanHead(isPast: isPast, dimmed: dimmed, add: add)
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content()
                    }
                    // Место под клавиатуру. Без него строка, в которую
                    // пишут, уходит под неё, и человек не видит, что
                    // набирает (решение P166).
                    .padding(.bottom, keyboard)
                    .onChange(of: watching) { _, id in show(id, proxy) }
                    .onChange(of: keyboard) { _, _ in show(watching, proxy) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Ход плавный и один: без него страница дёргалась, потому что
            // клавиатура и содержимое ехали вразнобой.
            .animation(.easeOut(duration: 0.25), value: keyboard)
        }
        .keyboardHeight($keyboard)
    }

    /// Довести строку до глаз. С задержкой в один оборот: пока клавиатура
    /// не встала на место, высота ещё не та, и прокрутка уедет не туда.
    private func show(_ id: UUID?, _ proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
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

    /// Сколько пальец прошёл от начала. Взятое дело идёт за пальцем
    /// вплотную, а расступаются соседи уже по целым строкам.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if store.editing { banner }
            PlanScaffold(isPast: store.isPast, dimmed: !store.canEditPlan,
                         add: add, watching: typingIn) {
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
        .opacity(store.isPast && !store.editing ? 0.58 : 1)
        // Строки замеряются в этой системе координат, барабан в ней же и
        // ставится: замеряет строка, а ставит страница, и считать они
        // должны одинаково (решение P173).
        .coordinateSpace(name: Plan.space)
        .overlay {
            if let r = shell.roller {
                RollerCard(roller: r).transition(.opacity)
            }
        }
        .onChange(of: focused) { _, now in
            if now == nil { typingIn = nil; store.save() }
        }
        .onChange(of: store.date) { _, _ in
            typingIn = nil
            focused = nil
            // Перелистнули день — барабану не на что вставать: дела, чьё
            // время крутили, на этой странице уже нет.
            shell.roller = nil
        }
        // Ушли на «Дневник» — барабан уходит со страницей. Иначе он
        // остался бы висеть незакрытым, а книга — незалистываемой.
        .onDisappear { shell.roller = nil }
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

    /// Название дела — всегда одна строка.
    ///
    /// В файле дело занимает ровно строку. Перевод строки разорвал бы его
    /// надвое: хвост осел бы отдельной непонятой строкой, а напоминание
    /// уехало бы вместе с ним. Поэтому «Ввод» в названии не переводит
    /// строку, а заканчивает правку — как и обещает надпись на клавише
    /// (решение P172). Длинное название переносится по словам само.
    private func name(_ row: Binding<PlanRow>) -> Binding<String> {
        Binding(get: { row.wrappedValue.text },
                set: { typed in
                    guard typed.contains(where: \.isNewline) else {
                        row.text.wrappedValue = typed
                        return
                    }
                    row.text.wrappedValue = typed.filter { !$0.isNewline }
                    focused = nil
                })
    }

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        let id = row.wrappedValue.id
        let shown = number(of: id) + (dragged == id ? carried : displaced(id))

        return PlanRowLine(
            number: shown,
            row: row.wrappedValue,
            faded: store.isPast && !store.editing,
            bellColor: Ru.dayColor(store.date),
            text: name(row),
            focus: $focused,
            typing: typingIn == id,
            editMode: store.editing,
            onTime: { at in openRoller(id, .time, at: at) },
            onBell: { at in openRoller(id, .bell, at: at) },
            onDetails: { focused = nil; openDetails(id) },
            onUp: { store.move(id, by: -1) },
            onDown: { store.move(id, by: 1) },
            onDelete: { store.delete(id) })
            // Взятое дело идёт за пальцем, остальные расступаются по целым
            // строкам — так под ним открывается место, и видно, куда оно
            // встанет (решение P163).
            .id(id)
            .offset(y: dragged == id
                    ? dragOffset
                    : CGFloat(displaced(id)) * PlanRowLine.height)
            .animation(dragged == id ? nil : .easeOut(duration: 0.16),
                       value: displaced(id))
            .shadow(color: .black.opacity(dragged == id ? 0.18 : 0),
                    radius: 8, y: 3)
            .zIndex(dragged == id ? 1 : 0)
            .background(store.editing ? Look.ruleSoft.opacity(0.5) : .clear)
            .contentShape(Rectangle())
            .highPriorityGesture(store.editing ? reorder(id) : nil)
            .onLongPressGesture(minimumDuration: 0.35) {
                guard !store.editing else { return }
                toggle(row)
            }
            // Короткое нажатие ставит курсор в текст дела, длинное затеняет
            // выполненное. Раньше короткое делало и то и другое: человек
            // тянулся поправить слово, а дело гасло (решение P156).
            .onTapGesture {
                guard store.canEditPlan, !store.editing, typingIn != id else { return }
                typingIn = id
                DispatchQueue.main.async { focused = id }
            }
    }

    /// Перестановка дела: в режиме изменений дело тащат за номер, и номер на
    /// нём меняется по дороге — видно, куда оно встанет.
    private func reorder(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                dragged = id
                dragOffset = g.translation.height
                dragBy = Int((g.translation.height / PlanRowLine.height).rounded())
            }
            .onEnded { _ in
                let by = dragBy
                dragged = nil
                dragBy = 0
                dragOffset = 0
                guard by != 0 else { return }
                for _ in 0..<abs(by) { store.move(id, by: by > 0 ? 1 : -1) }
            }
    }

    private func openRoller(_ id: UUID, _ kind: Shell.Roller.Kind, at: CGRect) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        withAnimation(.easeOut(duration: 0.16)) {
            shell.roller = .init(id: id, kind: kind, at: at)
        }
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

    /// Куда встанет взятое дело: столько строк оно пройдёт на самом деле.
    /// За края списка вынести его нельзя, поэтому ход подрезан.
    private var carried: Int {
        guard let dragged,
              let from = store.tasks.firstIndex(where: { $0.id == dragged })
        else { return 0 }
        let to = min(max(from + dragBy, 0), store.tasks.count - 1)
        return to - from
    }

    /// На сколько строк отодвигается соседнее дело, пока над ним проносят
    /// другое. Место под взятым делом должно освобождаться: иначе человек
    /// отпускает его поверх чужой строки и не понимает, куда оно встанет.
    private func displaced(_ id: UUID) -> Int {
        guard let dragged, dragged != id,
              let from = store.tasks.firstIndex(where: { $0.id == dragged }),
              let mine = store.tasks.firstIndex(where: { $0.id == id })
        else { return 0 }
        let to = min(max(from + dragBy, 0), store.tasks.count - 1)
        if to > from, mine > from, mine <= to { return -1 }
        if to < from, mine < from, mine >= to { return 1 }
        return 0
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
