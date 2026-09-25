import SwiftUI
import UIKit
import CoreLocation

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
    var typing = false
    var editMode = false

    var onTime: (() -> Void)?
    var onBell: (() -> Void)?
    var onDetails: (() -> Void)?
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Правка названия кончилась.
    var onDone: () -> Void = {}
    /// «Ввод» в названии: ввод переходит к делу ниже.
    var onNext: () -> Void = {}

    /// Дело тащат за номер: сколько пальец прошёл и когда отпустили.
    /// Только за номер: текст — это текст, его читают и правят, а не
    /// двигают (решение P179).
    var onGrab: ((CGFloat) -> Void)?
    var onDrop: (() -> Void)?

    /// Высота строки без подробностей. По ней считается перестановка.
    static let height: CGFloat = 54

    // MARK: - Мера строки
    //
    // Ширины головы заданы числами, а не меряются по содержимому: ровно на
    // ширину головы отступает первая строка названия, и разойдись они хоть
    // на точку — название наползёт на колокольчик или отскочит от него.

    static let badgeWidth: CGFloat = 26
    static let timeWidth: CGFloat = 64
    static let bellWidth: CGFloat = 40
    static let gap: CGFloat = 8

    /// Голова строки: номер, время, колокольчик.
    static let headWidth = badgeWidth + gap + timeWidth + gap + bellWidth

    /// Отступ первой строки названия: за головой, через просвет.
    static let indent = headWidth + gap

    /// Откуда идут строки ниже первой: из-под времени, правее номера.
    /// Номера остаются столбиком — за них дело берут, — а название
    /// занимает всю остальную ширину (решение P177).
    static let wrap = badgeWidth + gap

    /// Насколько площадка колокольчика выступает над квадратиком номера.
    ///
    /// На столько же поджимается закладка: её верх должен совпадать с
    /// верхом строки, а верх строки — это номер, а не пустое поле вокруг
    /// колокольчика. Прежде здесь стояла тройка, взятая на глаз, и закладки
    /// сходились со строками лишь приблизительно (решение P177).
    static let bellRise: CGFloat = 6

    /// Дело сейчас держат за номер.
    @State private var holding = false

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            // Голова стоит поверх отступа первой строки названия, а не
            // рядом с ним: тогда вторая и третья строки идут во всю ширину,
            // а не складываются в столбик (решение P177).
            ZStack(alignment: Alignment(horizontal: .leading,
                                        vertical: .firstTextBaseline)) {
                title
                head
            }
            if editMode { tools }
            tab
        }
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.done ? 0.42 : 1)
    }

    /// Тяга за номер. Отклик в палец на взятии и на отпускании: рука
    /// узнаёт, что дело поднято, не глядя на экран.
    private var grab: some Gesture {
        // Ход пальца меряется по экрану, а не по самому номеру: номер едет
        // вместе с делом, и мерка от него дёргала бы дело взад-вперёд —
        // строка дрожала и мерцала на ходу (решение P195).
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { сдвиг in
                if !holding {
                    holding = true
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
                onGrab?(сдвиг.translation.height)
            }
            .onEnded { _ in
                holding = false
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onDrop?()
            }
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.gap) {
            badge
            time
            bell
        }
    }

    // MARK: - Подрагивание номера

    /// Наклон номера в эту минуту. Считается по часам, а не заводится
    /// бесконечным ходом: заведённый ход не всегда гас, и номера дрожали и
    /// после выхода из режима изменений. Вне режима наклон — ноль, и
    /// часы стоят (решения P157, P195).
    private func tilt(_ now: Date) -> Double {
        guard editMode else { return 0 }
        return 6 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi / 0.26)
    }

    // MARK: - Части строки

    /// Номер в выпуклом квадратике: за него дело берут и переставляют.
    private var badge: some View {
        TimelineView(.animation(paused: !editMode)) { clock in
            face.rotationEffect(.degrees(tilt(clock.date)))
        }
        // Номер — рукоять, а не текст: касание по нему не должно
        // ставить курсор в строку (решение P167).
        .contentShape(Rectangle())
        .onTapGesture { }
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
        // Тащат только за номер. Он для этого и дрожит: дрожит — значит
        // его можно взять (решение P179).
        .highPriorityGesture(editMode && onGrab != nil ? grab : nil)
    }

    private var face: some View {
        Text("\(number)")
            .font(Look.mono(14))
            .foregroundStyle(Look.inkSoft)
            .frame(width: PlanRowLine.badgeWidth, height: PlanRowLine.badgeWidth)
            .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .shadow(color: .black.opacity(editMode ? 0.18 : 0.06),
                    radius: editMode ? 3 : 1, y: 1)
            // В режиме изменений квадратик подрагивает: видно, что дело
            // можно взять и переставить, и видно, что режим включён.
    }

    private var time: some View {
        Button { onTime?() } label: {
            Text(row.time ?? "--:--")
                .font(Look.mono(18.5))
                .tracking(row.time == nil ? 0.7 : 0)
                // Время — всегда одна строка. «--:--» с разрядкой не
                // умещалось в отведённую ширину и переносилось надвое:
                // на странице оставался висеть один прочерк.
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
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
                // Ширина задана числом: по ней считается отступ названия,
                // и она не должна зависеть от того, назначено время или нет.
                .frame(width: PlanRowLine.timeWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        // Не .disabled: система рисует выключенную кнопку бледнее, и время
        // на соседней странице выцветало, а после поворота «загоралось».
        // Вид не должен зависеть от того, можно ли нажать (P130).
        .allowsHitTesting(onTime != nil)
    }

    private var bell: some View {
        Button { onBell?() } label: {
            Image(systemName: row.bell == nil ? "bell" : "bell.fill")
                .font(.system(size: 20))
                .foregroundStyle(row.bell == nil ? Look.inkFaint : bellColor)
                .frame(width: PlanRowLine.bellWidth, height: 38)
                .contentShape(Rectangle())
                // Площадка колокольчика вдвое выше квадратика номера, но
                // середины у них общие: иначе колокольчик висит чуть выше
                // номера, и вся голова строки выглядит нестройно.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 12 }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(onBell != nil)
        .accessibilityLabel(row.bell.map { "Напомнить в \($0)" } ?? "Напоминание не назначено")
    }

    /// Название — одно и то же поле и на открытой странице, и на соседних:
    /// соседняя лишь не правится. Строчка письма задана числом, одним и тем
    /// же, что бы ни было внутри (решение P171).
    private var title: some View {
        PlanTitle(text: text ?? .constant(row.text),
                  indent: Self.indent,
                  wrap: Self.wrap,
                  faded: faded,
                  editable: text != nil && (typing || editMode),
                  typing: typing,
                  onDone: onDone,
                  onNext: onNext)
            .alignmentGuide(.firstTextBaseline) { _ in PlanTitle.baseline }
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
                .padding(.vertical, PlanRowLine.bellRise)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(onDetails != nil)
        .opacity(editMode ? 0.25 : 1)
        .accessibilityLabel("Подробности")
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

    /// Фотографии плана — полоской внизу страницы (P203).
    var photos: [URL?] = []
    var glowing = false
    var onOpenPhoto: ((Int) -> Void)?
    /// Что несёт палец, взяв превью из полоски (P205).
    var drag: ((Int) -> String)?
    var onMovePhoto: ((Int, Int) -> Void)?

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
            if !photos.isEmpty {
                PhotoStrip(photos: photos, glowing: glowing, onOpen: onOpenPhoto,
                           drag: drag, onMove: onMovePhoto)
            }
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

    /// Строка, в которой сейчас правят название. Одна на всю страницу:
    /// поле само берёт ввод, когда строка названа, и само отдаёт его,
    /// когда клавиатура уходит.
    @State private var typingIn: UUID?

    /// Дело, которое сейчас тащат за номер, и на сколько оно сдвинуто.
    @State private var dragged: UUID?
    @State private var dragBy = 0

    /// Сколько пальец прошёл от начала. Взятое дело идёт за пальцем
    /// вплотную, а расступаются соседи уже по целым строкам.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if store.editing(.plan) { EditBanner(tab: .plan) }
            PlanScaffold(isPast: store.isPast, dimmed: !store.canEditPlan,
                         add: add, watching: typingIn,
                         photos: store.planPhotos.map(store.photoURL),
                         glowing: store.editing(.plan),
                         onOpenPhoto: { shell.openedPhoto = .init(tab: .plan, index: $0) },
                         // Снимки плана к делам не носят — только
                         // переставляют вдоль полоски (P210).
                         onMovePhoto: store.editing(.plan) && store.canEditPlan
                             ? { store.movePhoto(from: $0, to: $1, in: .plan) } : nil) {
                if store.tasks.isEmpty {
                    PlanEmpty(isPast: store.isPast, inCloud: store.away.contains(.planner))
                } else {
                    list
                }
                // Касание по пустому месту убирает клавиатуру и выходит из
                // режима изменений: выход должен быть там, куда рука тянется
                // сама, а не только в кнопке наверху.
                Color.clear
                    .frame(minHeight: 140)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        if store.editing(.plan) {
                            withAnimation(.easeOut(duration: 0.2)) { store.setEditing(.plan, false) }
                        }
                    }
            }
        }
        .onChange(of: store.date) { _, _ in typingIn = nil }
        .opacity(store.isPast && !store.editing(.plan) ? 0.58 : 1)
    }

    private func add() {
        guard let id = store.addTask() else { return shell.say(store.closedReason) }
        typingIn = id
    }

    @ViewBuilder private var list: some View {
        ForEach($store.planRows) { row in
            if row.wrappedValue.isTask {
                taskRow(row)
                Rectangle().fill(Look.ruleSoft).frame(height: 1)
            } else if let line = row.wrappedValue.verbatim {
                PlanExtraLine(line: line, resolve: store.photoURL,
                              open: { url in
                                  shell.openedPhoto = .init(tab: .plan, index: 0, url: url)
                              },
                              openPoint: { shell.showPoint($0) })
            }
        }
        stat
    }

    private var stat: some View {
        PlanStat(planned: store.tasks.count, done: store.doneCount)
    }

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        let id = row.wrappedValue.id
        let shown = number(of: id) + (dragged == id ? carried : displaced(id))

        return PlanRowLine(
            number: shown,
            row: row.wrappedValue,
            faded: store.isPast && !store.editing(.plan),
            bellColor: Ru.dayColor(store.date),
            text: row.text,
            typing: typingIn == id,
            editMode: store.editing(.plan),
            onTime: { openRoller(id, .time) },
            onBell: { openRoller(id, .bell) },
            onDetails: { hideKeyboard(); openDetails(id) },
            onUp: { store.move(id, by: -1) },
            onDown: { store.move(id, by: 1) },
            onDelete: { store.delete(id) },
            // Правку кончила эта самая строка, а не соседняя, которой
            // только что отдали ввод: иначе курсор гас бы сразу после
            // перехода в следующее дело.
            onDone: { if typingIn == id { typingIn = nil }; store.save() },
            onNext: { next(after: id) },
            onGrab: { сдвиг in
                dragged = id
                dragOffset = сдвиг
                dragBy = Int((сдвиг / PlanRowLine.height).rounded())
            },
            onDrop: { drop(id) })
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
            .background(store.editing(.plan) ? Look.ruleSoft.opacity(0.5) : .clear)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35) {
                guard !store.editing(.plan) else { return }
                toggle(row)
            }
            // Короткое нажатие ставит курсор в текст дела, длинное затеняет
            // выполненное. Раньше короткое делало и то и другое: человек
            // тянулся поправить слово, а дело гасло (решение P156).
            .onTapGesture {
                guard store.canEditPlan, !store.editing(.plan), typingIn != id else { return }
                typingIn = id
            }
    }

    /// Дело отпустили: оно встаёт туда, куда его донесли.
    private func drop(_ id: UUID) {
        let by = dragBy
        dragged = nil
        dragBy = 0
        dragOffset = 0
        guard by != 0 else { return }
        for _ in 0..<abs(by) { store.move(id, by: by > 0 ? 1 : -1) }
    }

    /// «Ввод» в названии: ввод переходит к делу ниже.
    ///
    /// Клавиша «Ввод» уводит на строку ниже, к следующему делу. У
    /// последнего дела правка кончается: новое дело заводится только
    /// плюсом. Дело, которое завелось само от «Ввода», — это движение
    /// помимо воли человека (решение P193, уточняет P180).
    private func next(after id: UUID) {
        let дела = store.tasks
        guard let i = дела.firstIndex(where: { $0.id == id }) else { return }
        if i + 1 < дела.count {
            typingIn = дела[i + 1].id
            return
        }
        typingIn = nil
    }

    private func openRoller(_ id: UUID, _ kind: Shell.Roller.Kind) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        // Ролик встаёт на место клавиатуры, а не поверх неё: два разных
        // способа ввода разом на экране не помещаются, и человеку пришлось
        // бы сперва убирать клавиатуру самому (решение P176).
        hideKeyboard()
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
    /// Файл плана лежит в iCloud и ещё не скачан. Пустая страница здесь
    /// не значит пустой день — так и надо сказать (решение P182).
    var inCloud = false

    var body: some View {
        VStack(spacing: 4) {
            if inCloud {
                Text("План этого дня ещё загружается из iCloud.")
                Text("Как только придёт, он появится здесь.")
            } else {
                Text("На этот день ничего не запланировано.")
                if !isPast { Text("Нажмите «+», чтобы вписать дело.") }
            }
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

/// Строка плана, которая не дело: снимок, поставленный между делами в
/// прежних сборках, или точка с карты. Прочие строки файла не рисуются,
/// но в файле остаются (P210, P213).
struct PlanExtraLine: View {
    let line: String
    var resolve: ((String) -> URL?)?
    var open: ((URL?) -> Void)?
    /// Касание по точке — карта на ней. Пусто — на соседних страницах.
    var openPoint: ((GeoPoint) -> Void)?

    var body: some View {
        if let link = Diary.picture(in: line), Diary.kind(of: link) == .photo {
            PlanPhotoLine(url: resolve?(link)) { open?(resolve?(link)) }
            Rectangle().fill(Look.ruleSoft).frame(height: 1)
        } else if let point = Geo.point(in: line) {
            PlanPointLine(point: point, open: openPoint)
            Rectangle().fill(Look.ruleSoft).frame(height: 1)
        }
    }
}

/// Точка в плане — та же кнопочка, что в дневнике: название и координаты
/// бледным цветом; касание открывает карту на ней (P213).
struct PlanPointLine: View {
    let point: GeoPoint
    var open: ((GeoPoint) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            PointChipView(point: point)
                .contentShape(Capsule())
                .onTapGesture { open?(point) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Точка на карте: " + point.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

/// Кнопочка точки для SwiftUI — нарисована тем же кодом, что в тексте
/// дневника, чтобы не расходилась с ним.
struct PointChipView: View {
    let point: GeoPoint

    var body: some View {
        let picture = PointChip.draw(point.label)
        Image(uiImage: picture)
            .frame(width: picture.size.width, height: picture.size.height)
    }
}

/// Надпись над страницей в режиме изменений: что сейчас можно и как выйти.
/// Своя у каждой вкладки (P211).
struct EditBanner: View {

    let tab: Shell.Tab

    @EnvironmentObject private var store: DayStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tab == .plan ? "Режим изменений: правка текста, порядок, удаление."
                              : "Режим изменений: снимки можно брать и переносить.")
                .font(Look.sans(12.5))
            Spacer(minLength: 0)
            Button("Выйти") {
                withAnimation(.easeOut(duration: 0.2)) { store.setEditing(tab, false) }
            }
            .font(Look.sans(12.5, weight: .semibold))
            .underline()
        }
        .foregroundStyle(Look.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Look.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Look.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
