import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

/// Дело подняли долгим нажатием и ведут пальцем (P362): вверх-вниз —
/// переставить, влево — удалить, вправо — сделано, как в почте iPhone.
/// Ход пальца — от места, где дело подняли, по экрану.
enum Lift {
    case began
    case moved(CGSize)
    case ended(CGSize)
    case cancelled
}

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

    /// Долгое нажатие на дело — на текст или на номер — поднимает его, и
    /// дальше его ведут пальцем (P362). Отклик — сразу, как нажатие стало
    /// долгим, а не когда палец убрали (P361).
    var onLift: ((Lift) -> Void)?

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

    /// Дело сейчас держат за номер. Сбрасывается и тогда, когда жест
    /// оборвался сам, — тогда дело опускается на место.
    @GestureState private var holding = false
    /// Подъём уже объявлен — второй раз не объявлять.
    @State private var lifted = false

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
            tab
        }
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.done ? 0.42 : 1)
    }

    /// Долгое нажатие на номер и ход пальца после него (P362) — то же,
    /// что долгое нажатие на текст дела.
    private var lift: some Gesture {
        // Ход пальца меряется по экрану, а не по самому номеру: номер едет
        // вместе с делом, и мерка от него дёргала бы дело взад-вперёд —
        // строка дрожала и мерцала на ходу (решение P195).
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !lifted {
                    lifted = true
                    onLift?(.began)
                }
                if let drag { onLift?(.moved(drag.translation)) }
            }
            .onEnded { value in
                guard lifted, case .second(true, let drag) = value else { return }
                lifted = false
                onLift?(.ended(drag?.translation ?? .zero))
            }
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.gap) {
            badge
            time
            bell
        }
    }

    // MARK: - Части строки

    /// Номер в выпуклом квадратике: за него, как и за текст, дело берут
    /// долгим нажатием (P362).
    private var badge: some View {
        face
        // Номер — рукоять, а не текст: касание по нему не должно
        // ставить курсор в строку (решение P167).
        .contentShape(Rectangle())
        .onTapGesture { }
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
        .highPriorityGesture(onLift != nil ? lift : nil)
        // Жест оборвался сам (палец увела прокрутка) — дело опускается.
        .onChange(of: holding) { _, now in
            guard !now else { return }
            DispatchQueue.main.async {
                guard lifted else { return }
                lifted = false
                onLift?(.cancelled)
            }
        }
    }

    private var face: some View {
        Text("\(number)")
            .font(Look.mono(14))
            .foregroundStyle(Look.inkSoft)
            .frame(width: PlanRowLine.badgeWidth, height: PlanRowLine.badgeWidth)
            .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
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
                // Дело из серии — значок повтора у колокольчика (P359).
                .overlay(alignment: .bottomTrailing) {
                    if row.repeats != nil {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Look.accent)
                            .offset(x: 5, y: 3)
                    }
                }
                .frame(width: PlanRowLine.bellWidth, height: 38)
                .contentShape(Rectangle())
                // Площадка колокольчика вдвое выше квадратика номера, но
                // середины у них общие: иначе колокольчик висит чуть выше
                // номера, и вся голова строки выглядит нестройно.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 12 }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(onBell != nil)
        .accessibilityLabel(row.bell.map { T("Напомнить в \($0)", "Remind at \($0)") }
                                ?? T("Напоминание не назначено", "No reminder"))
    }

    /// Название — одно и то же поле и на открытой странице, и на соседних:
    /// соседняя лишь не правится. Строчка письма задана числом, одним и тем
    /// же, что бы ни было внутри (решение P171).
    private var title: some View {
        PlanTitle(text: text ?? .constant(row.text),
                  rowID: text == nil ? nil : row.id,
                  indent: Self.indent,
                  wrap: Self.wrap,
                  faded: faded,
                  editable: text != nil && typing,
                  typing: typing,
                  onDone: onDone,
                  onNext: onNext,
                  onLift: onLift)
            .alignmentGuide(.firstTextBaseline) { _ in PlanTitle.baseline }
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
        .accessibilityLabel(T("Подробности", "Details"))
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
    /// Шаг назад и вперёд (P261). Соседние страницы показывают те же
    /// кнопки, только погашенными.
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    /// Погода дня — слева в строке с «плюсом» (P277).
    var weather: String?

    /// Строка, в которую сейчас пишут: её и надо держать на виду.
    var watching: UUID?

    /// Фотографии плана — полоской внизу страницы (P203).
    var photos: [URL?] = []
    /// Под делами есть снимки — полоска видна и пустой: в неё их
    /// возвращают (P358). Соседние страницы считают то же самое, чтобы
    /// низ страницы не прыгал при перелистывании (P114).
    var takesBack = false
    var onOpenPhoto: ((Int) -> Void)?
    /// Что несёт палец, взяв превью из полоски (P205).
    var drag: ((Int) -> String)?
    var onMovePhoto: ((Int, Int) -> Void)?
    /// Снимок из-под дела отпустили над полоской — назад в неё (P358).
    var onTakePhoto: ((String) -> Void)?
    /// Приложение вернулось после паузы — список снова с самого верха
    /// (P346). Меняется — прокрутить вверх; у соседних страниц не меняется.
    var home = 0

    @ViewBuilder let content: () -> Content

    @State private var keyboard: CGFloat = 0

    private static var top: String { "план-верх" }

    var body: some View {
        VStack(spacing: 0) {
            PlanHead(isPast: isPast, dimmed: dimmed, add: add, undo: undo, redo: redo,
                     weather: weather)
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id(Self.top)
                        content()
                    }
                    // Место под клавиатуру. Без него строка, в которую
                    // пишут, уходит под неё, и человек не видит, что
                    // набирает (решение P166).
                    .padding(.bottom, keyboard)
                    .onChange(of: watching) { _, id in show(id, proxy) }
                    .onChange(of: keyboard) { _, _ in show(watching, proxy) }
                    .onChange(of: home) { _, _ in proxy.scrollTo(Self.top, anchor: .top) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Ход плавный и один: без него страница дёргалась, потому что
            // клавиатура и содержимое ехали вразнобой.
            .animation(.easeOut(duration: 0.25), value: keyboard)
            if !photos.isEmpty || takesBack {
                PhotoStrip(photos: photos, onOpen: onOpenPhoto,
                           drag: drag, onMove: onMovePhoto, onTake: onTakePhoto)
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
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    var weather: String?

    var body: some View {
        HStack(spacing: 8) {
            // Погода — слева, в пустом месте строки (P277).
            if let weather, Prefs.weatherOn {
                Label(Prefs.weatherText(weather), systemImage: "cloud.sun")
                    .font(Look.sans(12.5))
                    .foregroundStyle(Look.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if isPast {
                Text(T("день закрыт", "day closed"))
                    .font(Look.mono(11))
                    .tracking(0.45)
                    .foregroundStyle(Look.inkFaint)
            }
            Spacer()
            // Шаг назад и шаг вперёд — слева от «плюса» (P261).
            step("arrow.uturn.backward", undo, T("Шаг назад", "Undo"))
            step("arrow.uturn.forward", redo, T("Шаг вперёд", "Redo"))
            Text("+")
                .font(.system(size: 25))
                .foregroundStyle(Look.accent)
                .frame(width: StepButton.side, height: StepButton.side)
                .overlay(Circle().strokeBorder(Look.rule))
                .opacity(dimmed ? 0.3 : 1)
                .onTapGesture { add?() }
                .accessibilityLabel(T("Новое дело", "New task"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, isPast ? 12 : 6)
        .padding(.bottom, isPast ? 8 : 0)
    }

    private func step(_ icon: String, _ act: (() -> Void)?, _ name: String) -> some View {
        StepButton(icon: icon, act: act, name: name, dimmed: dimmed)
    }
}

/// Кружок «шаг назад» / «шаг вперёд» (P261). Тот же вид — и в дневнике,
/// в том же месте, что и в плане (P312).
struct StepButton: View {
    let icon: String
    let act: (() -> Void)?
    let name: String
    var dimmed = false

    /// Кружок и «плюс» рядом — на 20% крупнее прежних 34 (P356): в мелкий
    /// пальцем не попасть.
    static let side: CGFloat = 41

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Look.accent)
            .frame(width: Self.side, height: Self.side)
            .overlay(Circle().strokeBorder(Look.rule))
            .opacity(act == nil || dimmed ? 0.3 : 1)
            .contentShape(Circle())
            .onTapGesture {
                guard let act else { return }
                Feel.light()
                hideKeyboard()
                act()
            }
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
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
    /// Дело, поднятое долгим нажатием (P362): оно обведено синим и идёт
    /// за пальцем. Куда его ведут — решает первый заметный ход пальца.
    @State private var lifted: UUID?
    @State private var liftAxis: Axis?
    /// Насколько поднятое дело отведено вбок: влево — удалить, вправо —
    /// сделано.
    @State private var slide: CGFloat = 0
    /// Точка в плане, у которой после долгого нажатия виден крестик.
    @State private var armedLine: UUID?

    /// Сколько отвести дело вбок, чтобы отпущенное оно удалилось или
    /// отметилось.
    static let swipe: CGFloat = 90

    /// Дело, которое сейчас ведут вверх-вниз, и на сколько оно сдвинуто.
    @State private var dragged: UUID?
    @State private var dragBy = 0

    /// Сколько пальец прошёл от начала. Взятое дело идёт за пальцем
    /// вплотную, а расступаются соседи уже по целым строкам.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if store.editing(.plan) { EditBanner() }
            PlanScaffold(isPast: store.isPast, dimmed: !store.canEditPlan,
                         add: add,
                         undo: store.planBack.isEmpty || !store.canEditPlan ? nil : { store.undoPlan() },
                         redo: store.planAhead.isEmpty || !store.canEditPlan ? nil : { store.redoPlan() },
                         weather: store.weather,
                         watching: typingIn,
                         photos: store.planPhotos.map(store.photoURL),
                         takesBack: Plan.hasPhotoRows(store.planRows),
                         onOpenPhoto: { shell.openedPhoto = .init(tab: .plan, index: $0) },
                         // Снимок из полоски несут под любое дело долгим
                         // нажатием, без всякого режима (P358, P362).
                         drag: store.canEditPlan
                             ? { i in store.planPhotos.indices.contains(i)
                                 ? Diary.line(store.planPhotos[i]) : "" } : nil,
                         onMovePhoto: store.canEditPlan
                             ? { store.movePhoto(from: $0, to: $1, in: .plan) } : nil,
                         onTakePhoto: store.canEditPlan
                             ? { store.returnPlanPhoto($0) } : nil,
                         home: shell.freshStart) {
                if store.tasks.isEmpty {
                    PlanEmpty(isPast: store.isPast, inCloud: store.away.contains(.planner))
                } else {
                    list
                }
                // Касание по пустому месту убирает клавиатуру и крестик у
                // точки: выход должен быть там, куда рука тянется сама.
                Color.clear
                    .frame(minHeight: 140)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        withAnimation(.easeOut(duration: 0.15)) { armedLine = nil }
                    }
            }
        }
        // Точка в названии дела открывает карту, как точка строкой (P256).
        .environment(\.openPoint, { point in
            store.noteLeaving(fromToday: true)
            shell.showPoint(point)
        })
        .onChange(of: store.date) { _, _ in
            typingIn = nil
            armedLine = nil
        }
        .onChange(of: typingIn) { _, now in if now != nil { armedLine = nil } }
        // Дело из серии поправили или убирают — только здесь или дальше
        // тоже (P359).
        .modifier(SeriesQuestion())
        // Где курсор в плане — туда встанет точка с карты (P240).
        .onChange(of: typingIn) { _, now in store.planTyping = now }
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
                let id = row.wrappedValue.id
                PlanExtraLine(line: line, resolve: store.photoURL,
                              open: { url in
                                  shell.openedPhoto = .init(tab: .plan, index: 0, url: url)
                              },
                              openPoint: {
                                  store.noteLeaving(fromToday: true)
                                  shell.showPoint($0)
                              },
                              onMove: store.canEditPlan
                                  ? { store.moveLine(id, by: $0) } : nil,
                              onDelete: store.canEditPlan
                                  ? {
                                      armedLine = nil
                                      withAnimation(.easeOut(duration: 0.2)) { store.delete(id) }
                                  } : nil,
                              armed: armedLine == id,
                              onArm: { on in
                                  withAnimation(.easeOut(duration: 0.15)) { armedLine = on ? id : nil }
                              },
                              onInto: store.canEditPlan
                                  ? { spot in
                                      guard let task = PlanZones.task(at: spot) else { return false }
                                      store.putPointIntoTask(id, task: task)
                                      return true
                                  } : nil)
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
        let up = lifted == id

        return PlanRowLine(
            number: shown,
            row: row.wrappedValue,
            faded: store.isPast && !store.editing(.plan),
            bellColor: Ru.dayColor(store.date),
            text: row.text,
            typing: typingIn == id,
            onTime: { openRoller(id, .time) },
            onBell: { openRoller(id, .bell) },
            onDetails: { hideKeyboard(); openDetails(id) },
            onUp: { store.move(id, by: -1) },
            onDown: { store.move(id, by: 1) },
            onDelete: { store.delete(id) },
            // Правку кончила эта самая строка, а не соседняя, которой
            // только что отдали ввод: иначе курсор гас бы сразу после
            // перехода в следующее дело.
            onDone: {
                if typingIn == id { typingIn = nil }
                store.save()
                store.checkSeries(id)
            },
            onNext: { next(after: id) },
            onLift: { lift(row, $0) })
            // Поднятое дело обведено синим — тем же, что и всё, что можно
            // взять пальцем (P203, P362).
            .overlay {
                if up {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Look.glow, lineWidth: 2.5)
                        .shadow(color: Look.glow.opacity(0.7), radius: 5)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .allowsHitTesting(false)
                }
            }
            // Где дело на экране — на его середину бросают точку (P358).
            .background(GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { PlanZones.rows[id] = frame }
                    .onChange(of: frame) { _, now in PlanZones.rows[id] = now }
                    .onDisappear { PlanZones.rows[id] = nil }
            })
            // Снимок из полоски или из-под другого дела — под это дело, в
            // ряд с теми, что уже там (P358).
            .onDrop(of: store.canEditPlan ? [UTType.plainText] : [],
                    isTargeted: nil) { providers in
                PhotoDrop.read(providers) { store.putPlanPhoto($0, under: id) }
            }
            // Взятое дело идёт за пальцем, остальные расступаются по целым
            // строкам — так под ним открывается место, и видно, куда оно
            // встанет (решение P163). Вбок оно идёт только своё (P362).
            .id(id)
            .offset(x: up ? slide : 0,
                    y: dragged == id
                    ? dragOffset
                    : CGFloat(displaced(id)) * PlanRowLine.height)
            .animation(dragged == id ? nil : .easeOut(duration: 0.16),
                       value: displaced(id))
            .background { underneath(id, done: row.wrappedValue.done) }
            .shadow(color: .black.opacity(dragged == id ? 0.18 : 0),
                    radius: 8, y: 3)
            .zIndex(dragged == id || up ? 1 : 0)
            .contentShape(Rectangle())
            // Короткое нажатие ставит курсор в текст дела. Сделано —
            // сдвигом вправо после долгого нажатия (P362; прежде — самим
            // долгим нажатием, P156).
            .onTapGesture {
                armedLine = nil
                guard store.canEditPlan, typingIn != id else { return }
                typingIn = id
            }
    }

    /// Что открывается под делом, отведённым вбок: справа — красная
    /// корзина, слева — зелёная галочка (как в почте iPhone, P362).
    @ViewBuilder private func underneath(_ id: UUID, done: Bool) -> some View {
        if lifted == id, slide != 0 {
            let far = abs(slide) >= Self.swipe
            HStack(spacing: 0) {
                if slide > 0 {
                    Image(systemName: done ? "arrow.uturn.backward" : "checkmark")
                        .frame(width: slide)
                        .frame(maxHeight: .infinity)
                        .background(Color.green.opacity(far ? 0.85 : 0.4))
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Image(systemName: "trash")
                        .frame(width: -slide)
                        .frame(maxHeight: .infinity)
                        .background(Color.red.opacity(far ? 0.85 : 0.4))
                }
            }
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(.white)
            .allowsHitTesting(false)
        }
    }

    /// Дело подняли долгим нажатием и ведут (P362). Первый заметный ход
    /// пальца решает, куда: вверх-вниз — переставить, вбок — удалить или
    /// отметить. Дальше направление не меняется: дело, которое вели вниз,
    /// не удалится от случайного ухода пальца вбок.
    private func lift(_ row: Binding<PlanRow>, _ phase: Lift) {
        let id = row.wrappedValue.id
        switch phase {
        case .began:
            guard store.canEditPlan else { return shell.say(store.closedReason) }
            if typingIn != nil {
                hideKeyboard()
                typingIn = nil
            }
            Feel.lift()
            liftAxis = nil
            slide = 0
            armedLine = nil
            withAnimation(.easeOut(duration: 0.12)) { lifted = id }
        case .moved(let way):
            guard lifted == id else { return }
            if liftAxis == nil {
                if abs(way.width) > 14, abs(way.width) > abs(way.height) * 1.2 {
                    liftAxis = .horizontal
                } else if abs(way.height) > 10 {
                    liftAxis = .vertical
                }
            }
            switch liftAxis {
            case .vertical:
                dragged = id
                dragOffset = way.height
                dragBy = Int((way.height / PlanRowLine.height).rounded())
            case .horizontal:
                let was = abs(slide) >= Self.swipe
                slide = way.width
                // Порог пройден — щелчок: отпустить здесь значит сделать.
                if (abs(slide) >= Self.swipe) != was { Feel.tick() }
            case nil:
                break
            }
        case .ended, .cancelled:
            guard lifted == id else { return }
            let axis = liftAxis
            let by = slide
            let real: Bool
            if case .ended = phase { real = true } else { real = false }
            if axis == .vertical {
                drop(id)
                Feel.thud()
            }
            liftAxis = nil
            withAnimation(.easeOut(duration: 0.2)) {
                lifted = nil
                slide = 0
            }
            guard real, axis == .horizontal else { return }
            if by <= -Self.swipe {
                withAnimation(.easeOut(duration: 0.2)) { store.delete(id) }
                Feel.light()
            } else if by >= Self.swipe {
                toggle(row)
            }
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
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        row.wrappedValue.done.toggle()
        // Сделано — довольный толчок; снято — лёгкий (P267).
        if row.wrappedValue.done { Feel.done() } else { Feel.light() }
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
                Text(T("План этого дня ещё загружается из iCloud.", "This plan is still downloading from iCloud."))
                Text(T("Как только придёт, он появится здесь.", "It will appear here as soon as it arrives."))
            } else {
                Text(T("На этот день ничего не запланировано.", "Nothing planned for this day."))
                if !isPast { Text(T("Нажмите «+», чтобы вписать дело.", "Tap “+” to add a task.")) }
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
        Text(T("Запланировано \(planned) · сделано \(done)", "Planned \(planned) · done \(done)"))
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
    /// Строку цепляют долгим нажатием и тащат к нужному делу; она встаёт
    /// на столько строк, на сколько её протащили (P226, P241, P362).
    var onMove: ((Int) -> Void)?
    /// Крестик у точки — строка уходит из плана (P352). Запомненное место
    /// остаётся на карте: из плана уходит только ссылка на него.
    var onDelete: (() -> Void)?
    /// Точку подержали и отпустили, не сдвинув: она крупнее, у неё крестик
    /// (P362). Касание по ней — крестик убрать.
    var armed = false
    var onArm: ((Bool) -> Void)?
    /// Точку отпустили на середине дела — она уходит в его название
    /// (P358). Получает место пальца на экране; `true` — взяло.
    var onInto: ((CGPoint) -> Bool)?

    @State private var dragged: CGFloat = 0

    var body: some View {
        if Plan.isPhotoRow(line) {
            // Снимки под делом — в ряд; каждый несут пальцем под другое
            // дело или назад в полоску (P358, P362).
            PlanPhotoRow(links: Diary.links(in: line), resolve: resolve, open: open,
                         carry: onMove != nil)
            Rectangle().fill(Look.ruleSoft).frame(height: 1)
        } else if let point = Geo.point(in: line) {
            PlanPointLine(point: point, open: tapPoint, armed: armed, onDelete: onDelete)
                .modifier(Carry(on: onMove != nil, dragged: $dragged, move: onMove, into: onInto,
                                arm: onDelete == nil ? nil : onArm))
            Rectangle().fill(Look.ruleSoft).frame(height: 1)
        }
    }

    /// Касание по точке: с крестиком — убрать крестик, без него — карта.
    private var tapPoint: ((GeoPoint) -> Void)? {
        guard armed else { return openPoint }
        return { _ in onArm?(false) }
    }
}

/// Вопрос о деле из серии: только этот день или этот и все следующие
/// (P359). Отдельно от плана: его цепочка и так длинная.
private struct SeriesQuestion: ViewModifier {
    @EnvironmentObject private var store: DayStore

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: shown, titleVisibility: .visible,
                                   presenting: store.seriesAsk) { ask in
            Button(only(ask)) { store.answerSeries(ask, all: false) }
            if ask.delete {
                Button(all(ask), role: .destructive) { store.answerSeries(ask, all: true) }
            } else {
                Button(all(ask)) { store.answerSeries(ask, all: true) }
            }
            Button(T("Отмена", "Cancel"), role: .cancel) { cancel(ask) }
        }
    }

    private var title: String { T("Это повторяющееся дело", "This is a repeating task") }

    private var shown: Binding<Bool> {
        Binding(get: { store.seriesAsk != nil }, set: { if !$0 { store.seriesAsk = nil } })
    }

    private func only(_ ask: DayStore.SeriesAsk) -> String {
        ask.delete ? T("Удалить только в этот день", "Delete this day only")
                   : T("Изменить только этот день", "Change this day only")
    }

    private func all(_ ask: DayStore.SeriesAsk) -> String {
        ask.delete ? T("Удалить этот и все следующие", "Delete this and all following")
                   : T("Изменить этот и все следующие", "Change this and all following")
    }

    /// Правку уже не отменить — она остаётся только в этом дне.
    private func cancel(_ ask: DayStore.SeriesAsk) {
        if ask.delete { store.seriesAsk = nil } else { store.answerSeries(ask, all: false) }
    }
}

/// Где на экране строки дел открытой страницы — чтобы точку, отпущенную
/// на середине дела, положить в его название (P358).
enum PlanZones {
    static var rows: [UUID: CGRect] = [:]

    /// Дело, на середине которого палец: верхняя и нижняя четверть строки —
    /// это граница между делами, там точка встаёт своей строкой.
    static func task(at spot: CGPoint) -> UUID? {
        rows.first { _, frame in
            frame.insetBy(dx: 0, dy: frame.height * 0.25).contains(spot)
        }?.key
    }
}

/// Строку плана цепляют долгим нажатием и тащат вверх-вниз.
private struct Carry: ViewModifier {
    let on: Bool
    @Binding var dragged: CGFloat
    let move: ((Int) -> Void)?
    var into: ((CGPoint) -> Bool)? = nil
    /// Подержали и отпустили, не сдвинув, — показать крестик (P362).
    var arm: ((Bool) -> Void)? = nil

    /// Подъём уже отмечен толчком.
    @State private var lifted = false

    func body(content: Content) -> some View {
        if on {
            content
                .offset(y: dragged)
                .zIndex(dragged == 0 ? 0 : 1)
                .shadow(color: .black.opacity(dragged == 0 ? 0 : 0.18), radius: 8, y: 3)
                .gesture(LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if !lifted {
                            lifted = true
                            Feel.lift()
                        }
                        if let drag { dragged = drag.translation.height }
                    }
                    .onEnded { value in
                        lifted = false
                        guard case .second(true, let found) = value else { dragged = 0; return }
                        // Подержали, не сдвинув, — крупнее и с крестиком.
                        guard let drag = found,
                              abs(drag.translation.height) > 8 || abs(drag.translation.width) > 8
                        else {
                            dragged = 0
                            arm?(true)
                            return
                        }
                        arm?(false)
                        let steps = Int((drag.translation.height / PlanRowLine.height).rounded())
                        dragged = 0
                        // На середине дела — внутрь него, в название (P358).
                        if let into, into(drag.location) {
                            Feel.light()
                            return
                        }
                        if steps != 0 { move?(steps) }
                    })
                .accessibilityHint(T("Долгое нажатие — перетащить к другому делу", "Long press to drag next to another task"))
        } else {
            content
        }
    }
}

/// Точка в плане — та же кнопочка, что в дневнике: булавка и название, без
/// координат (P345); касание открывает карту на ней (P213). Подержали —
/// крупнее и с крестиком «удалить», как значок на экране «Домой» (P362).
struct PlanPointLine: View {
    let point: GeoPoint
    var open: ((GeoPoint) -> Void)?
    var armed = false
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            PointChipView(point: point)
                .scaleEffect(armed ? 1.3 : 1, anchor: .leading)
                .overlay(alignment: .topTrailing) {
                    if armed, let onDelete {
                        DeleteBadge(action: onDelete)
                            // Значок вырос на треть — крестик стоит на его
                            // углу, а не на прежнем.
                            .offset(x: PointChipView.width(point) * 0.3 + 13, y: -18)
                    }
                }
                .contentShape(Capsule())
                .onTapGesture { open?(point) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(T("Точка на карте: ", "Place on the map: ") + point.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

/// Крестик «удалить» на углу поднятой точки (P362): красный кружок с белым
/// крестом — его видно на любой бумаге.
struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Look.pin)
                .font(.system(size: 22))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Удалить", "Delete"))
    }
}

/// Кнопочка точки для SwiftUI — нарисована тем же кодом, что в тексте
/// дневника, чтобы не расходилась с ним.
struct PointChipView: View {
    let point: GeoPoint

    /// Ширина кнопочки — по ней крестик встаёт на угол.
    static func width(_ point: GeoPoint) -> CGFloat {
        PointChip.mark(glowing: false, title: point.title).size.width
    }

    var body: some View {
        // Как в тексте дневника: булавка, у точки с названием — и название,
        // без координат; координаты — на карте, куда ведёт касание (P345).
        let picture = PointChip.mark(glowing: false, title: point.title)
        Image(uiImage: picture)
            .frame(width: picture.size.width, height: picture.size.height)
    }
}

/// Надпись над прошедшим днём плана, открытым для правки (P362): что
/// сейчас можно и как выйти.
struct EditBanner: View {

    @EnvironmentObject private var store: DayStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(T("Прошедший день открыт для правки.", "This past day is open for editing."))
                .font(Look.sans(12.5))
            Spacer(minLength: 0)
            Button(T("Выйти", "Done")) {
                withAnimation(.easeOut(duration: 0.2)) { store.setEditing(.plan, false) }
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
