import SwiftUI

/// Вкладка «Дневник»: как прошло, заголовок дня и свободный текст.
///
/// Набрана засечным шрифтом на тёплой бумаге — в отличие от плана. Это разные
/// занятия: план разглядывают, дневник читают.
struct DiaryView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @State private var health: String?
    /// Превью из полоски, которое несут, и где палец (P380).
    @State private var stripCarry: Int?
    @State private var stripSpot: CGPoint = .zero

    /// На ступень крупнее прежних 15,5 и растёт с настройкой (P274).
    static var size: CGFloat { 16.5 * Prefs.textScale }
    static let leading: CGFloat = size * 0.24

    var body: some View {
        page
    }

    private var page: some View {
        DiaryPage(
            tasks: store.tasks,
            answer: { store.answers[$0] ?? "" },
            setAnswer: { store.answers[$0] = $1 },
            title: $store.diaryTitle,
            text: $store.diaryText,
            editable: store.canEditDiary,
            inCloud: store.away.contains(.diary),
            weather: store.weather,
            photos: store.photos.map(store.photoURL),
            photoLinks: store.photos,
            resolve: store.photoURL,
            onOpenPhoto: { shell.openedPhoto = .init(tab: .diary, index: $0) },
            onMovePhoto: { store.movePhoto(from: $0, to: $1, in: .diary) },
            // Брошенный в текст снимок отметку времени не ставит — это
            // знает само поле записи (P362).
            onFocusText: { store.stampIfNeeded() },
            onOpenInline: { link in
                shell.openedPhoto = .init(tab: .diary, index: -1,
                                          url: store.photoURL(link), link: link)
            },
            onOpenPoint: {
                store.noteLeaving(fromToday: true)
                shell.showPoint($0)
            },
            onCaret: { store.diaryCaret = $0 },
            onEditing: { store.diaryTyping = $0 },
            placeCaret: $store.caretRequest,
            // Снимок, отпущенный над полоской, возвращается в неё (P272).
            onReturnPhoto: { link in
                store.returnToStrip(link)
                shell.say(T("Снимок вернулся в полоску", "Photo moved back to the strip"))
            },
            // Точка из текста — в заголовок и обратно (P358).
            onPointToTitle: { line in
                store.diaryTitle = DiaryPage.title(Geo.stripped(store.diaryTitle),
                                                   keeping: store.diaryTitle + " " + line)
            },
            onPointFromTitle: { line in
                store.pointFromTitle(line)
            },
            undo: store.diaryBack.isEmpty || !store.canEditDiary ? nil : { store.undoDiary() },
            redo: store.diaryAhead.isEmpty || !store.canEditDiary ? nil : { store.redoDiary() },
            home: shell.freshStart,
            health: health,
            // Касание по строке «Здоровья» — она ложится в запись (P378).
            onHealth: store.canEditDiary ? { line in store.addHealthLine(line) } : nil,
            onStripCarry: { carryStrip($0, $1, $2) },
            stripCarried: stripCarry)
        // Взятое из полоски — над пальцем, в синей рамке (P380).
        .overlay {
            if let i = stripCarry, stripSpot != .zero, store.photos.indices.contains(i) {
                GeometryReader { g in
                    let o = g.frame(in: .global).origin
                    stripGhost(store.photos[i])
                        .position(x: stripSpot.x - o.x, y: stripSpot.y - o.y - 48)
                }
                .allowsHitTesting(false)
            }
        }
        .task(id: store.date) { health = await HealthDay.summary(for: store.date) }
        .onChange(of: store.diaryTitle) { _, _ in store.scheduleSave() }
        .onChange(of: store.answers) { _, _ in store.scheduleSave() }
        .onChange(of: store.diaryText) { _, _ in
            store.touchDiary()
            store.settlePhotos()
            store.scheduleSave()
        }
    }
}

extension DiaryView {

    /// Превью из полоски несут (P380): над полем записи текст расступается
    /// там, куда оно ляжет; над полоской — встанет на место соседа.
    fileprivate func carryStrip(_ i: Int, _ phase: Lift, _ spot: CGPoint) {
        guard store.canEditDiary, store.photos.indices.contains(i) else { return }
        let line = Diary.line(store.photos[i])
        let overStrip = StripZones.strip.map { spot.y >= $0.minY - 8 } ?? false
        switch phase {
        case .began:
            Feel.lift()
            stripCarry = i
            stripSpot = spot
        case .moved:
            stripSpot = spot
            if overStrip {
                DiaryEditor.active?.carryOut()
            } else {
                DiaryEditor.active?.carryIn(line, at: CGPoint(x: spot.x, y: spot.y))
            }
        case .ended:
            if overStrip || spot == .zero {
                DiaryEditor.active?.carryOut()
                if let to = StripZones.nearest(to: spot, count: store.photos.count), to != i, spot != .zero {
                    store.movePhoto(from: i, to: to, in: .diary)
                    Feel.light()
                }
            } else if DiaryEditor.active?.carryEnd() == true {
                Feel.thud()
            }
            stripCarry = nil
            stripSpot = .zero
        case .cancelled:
            DiaryEditor.active?.carryOut()
            stripCarry = nil
            stripSpot = .zero
        }
    }

    @ViewBuilder fileprivate func stripGhost(_ link: String) -> some View {
        Group {
            if Diary.kind(of: link) == .photo {
                PlanPhotoThumb(url: store.photoURL(link))
            } else {
                Image(uiImage: FileChip.draw(link)).scaleEffect(1.3)
                    .padding(10)
                    .background(Look.planBg, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.glow, lineWidth: 2.6))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
}

/// Страница дневника.
///
/// Одна и та же и для открытого дня, и для соседних. Это не изящество, а
/// необходимость: стоит им разойтись хоть на строку — и при перелистывании
/// текст на открывающейся странице прыгает.
struct DiaryPage: View {

    let tasks: [PlanRow]
    let answer: (String) -> String
    var setAnswer: ((String, String) -> Void)?
    @Binding var title: String
    @Binding var text: String
    var editable = true
    /// Файл дневника лежит в iCloud и ещё не скачан: страница пуста не
    /// потому, что день пуст (решение P182).
    var inCloud = false
    /// Погода, когда отмечено место: бледной строкой над страницей (P208).
    var weather: String?
    /// Фотографии дня. Стоят над текстом, под заголовком (P200).
    var photos: [URL?] = []
    /// Строки-ссылки тех же снимков: их несёт палец из полоски в текст.
    var photoLinks: [String] = []
    /// Где лежат снимки, стоящие посреди текста (P204).
    var resolve: ((String) -> URL?)?
    var onOpenPhoto: ((Int) -> Void)?
    var onMovePhoto: ((Int, Int) -> Void)?
    /// Возвращает `true`, если приложение поставило отметку времени: тогда
    /// курсор переезжает за неё.
    var onFocusText: () -> Bool = { false }
    /// Касание по снимку посреди текста (P216) и по точке (P213).
    var onOpenInline: ((String) -> Void)?
    var onOpenPoint: ((GeoPoint) -> Void)?
    var onCaret: ((Int) -> Void)?
    var onEditing: ((Bool) -> Void)?
    var placeCaret: Binding<Int?> = .constant(nil)
    var onReturnPhoto: ((String) -> Void)?
    /// Точку перенесли из текста в заголовок дня — и обратно (P358).
    var onPointToTitle: ((String) -> Void)?
    var onPointFromTitle: ((String) -> Void)?
    /// Шаг назад и вперёд (P261) — там же, где в плане (P312).
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    /// Приложение открыли заново или вернулись после паузы — запись
    /// прокручивается к концу, под ней пять пустых строк: коснулся — и
    /// пишешь (P346). У соседних страниц не меняется.
    var home = 0
    /// День из «Здоровья» (P378) — слева в верхней строке, где пусто.
    var health: String? = nil
    var onHealth: ((String) -> Void)? = nil
    /// Превью из полоски несут своим жестом — в текст или на место соседа
    /// в полоске (P380).
    var onStripCarry: ((Int, Lift, CGPoint) -> Void)? = nil
    var stripCarried: Int? = nil

    /// Для какого открытия запись уже прокручена к концу.
    private static var homed = -1
    private static var end: String { "дневник-конец" }

    private enum Field: Hashable { case title }
    @FocusState private var focused: Field?

    /// Дело, на которое сейчас отвечают в «Как прошло?».
    @State private var askingAt: String?

    /// Поднимается ровно на один оборот — когда отметка времени поставлена.
    @State private var caretToEnd = false

    /// Поднимается по «Вводу» в заголовке: ввод переходит к тексту записи.
    @State private var toText = false

    /// Точка заголовка, у которой сейчас крестик (P362).
    @State private var armedPoint: String?

    /// Насколько клавиатура закрывает страницу снизу.
    @State private var keyboard: CGFloat = 0

    private let size = DiaryView.size

    var body: some View {
        VStack(spacing: 0) {
            head
            page
            // Фотографии дневника — полоской внизу, над кнопками вложений,
            // как в Diarium; прокрутке страницы они не мешают (P203).
            if !photos.isEmpty {
                PhotoStrip(photos: photos, onOpen: onOpenPhoto,
                           drag: editable && photoLinks.count == photos.count
                               ? { Diary.line(photoLinks[$0]) } : nil,
                           onMove: editable ? onMovePhoto : nil,
                           anyKind: true,
                           onCarry: editable ? onStripCarry : nil,
                           carried: stripCarried)
                    .background(GeometryReader { geo in
                        let frame = geo.frame(in: .global)
                        Color.clear
                            .onAppear { if editable { StripZones.strip = frame } }
                            .onChange(of: frame) { _, now in if editable { StripZones.strip = now } }
                    })
            }
        }
    }

    /// Шаг назад / вперёд — в том же месте, что и над списком дел в плане
    /// (P312): строка не уезжает со страницей, что бы та ни листала.
    private var head: some View {
        HStack(spacing: 8) {
            // Высота строки задана кнопками шага — строка «Здоровья»,
            // пришедшая позже, ничего не сдвигает (P113).
            // Погода и «Здоровье» — в той же строке, слева, где было пусто
            // (P380); вдвоём — друг под другом, высоту строки задают кнопки.
            VStack(alignment: .leading, spacing: 2) {
                if let weather, Prefs.weatherOn {
                    Label(Prefs.weatherText(weather), systemImage: "cloud.sun")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if let health {
                    Label(health, systemImage: "heart")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentShape(Rectangle())
                        .onTapGesture { onHealth?(health) }
                        .accessibilityHint(T("Касание — записать в дневник", "Tap to add to the diary"))
                }
            }
            .font(Look.sans(12))
            .foregroundStyle(Look.inkFaint)
            Spacer()
            StepButton(icon: "arrow.uturn.backward", act: undo, name: T("Шаг назад", "Undo"))
            StepButton(icon: "arrow.uturn.forward", act: redo, name: T("Шаг вперёд", "Redo"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 6)
    }

    private var page: some View {
        ScrollView {
          ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if inCloud {
                    Text(T("Запись этого дня ещё загружается из iCloud. Как только придёт, она появится здесь.",
                   "This day is still downloading from iCloud. It will appear here as soon as it arrives."))
                        .font(Look.serif(size - 1))
                        .foregroundStyle(Look.inkFaint)
                        .padding(.bottom, 12)
                }
                // «Как прошло?» можно выключить в настройках (P290).
                if Prefs.askOn, !asked.isEmpty { askBlock }
                titleField
                textField
                Color.clear.frame(height: 1).id(Self.end)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            // Место под клавиатуру: без него страницу некуда поднять, и
            // последние строки записи остаются под ней (решение P175).
            .padding(.bottom, 20 + keyboard)
            .onAppear { goHome(proxy) }
            .onChange(of: home) { _, _ in goHome(proxy) }
          }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
        .keyboardHeight($keyboard)
    }

    /// Прокрутить к концу записи — один раз на каждое открытие
    /// приложения (P346). Соседние страницы (`home == 0`) не трогаются.
    private func goHome(_ proxy: ScrollViewProxy) {
        guard home > 0, home != Self.homed else { return }
        Self.homed = home
        DispatchQueue.main.async { proxy.scrollTo(Self.end, anchor: .bottom) }
    }

    private var asked: [PlanRow] {
        Array(tasks.filter { !$0.text.isEmpty }.prefix(3))
    }

    // MARK: - Как прошло

    /// Три первых дела, по строке на каждое (решение P30). Ответ пишется
    /// прямо в той же строке, за двоеточием, и, дойдя до края, продолжается
    /// с начала следующей — во всю ширину, как в тетради (решение P185).
    private var askBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(T("Как прошло?", "How did it go?"))
                .font(Look.serif(size))
                .foregroundStyle(Look.inkFaint)
                .frame(height: size * 1.6, alignment: .leading)

            ForEach(asked, id: \.id) { task in
                askRow(task)
            }
        }
        .padding(.bottom, 12)
    }

    private func askRow(_ task: PlanRow) -> some View {
        AskLine(label: Geo.stripped(task.text) + ":",
                answer: Binding(get: { answer(task.text) },
                                set: { setAnswer?(task.text, $0) }),
                editable: editable && setAnswer != nil,
                typing: askingAt == task.text,
                onBegin: { askingAt = task.text },
                onDone: { if askingAt == task.text { askingAt = nil } },
                onNext: { next(after: task.text) })
            // Пустая строка стоит ровно в строку, а исписанная растёт вниз —
            // и дела, стоящие ниже, отодвигаются, освобождая место (P175).
            .frame(minHeight: size * 1.7, alignment: .leading)
    }

    /// «Ввод» в ответе: к следующему делу, а после последнего — к
    /// заголовку дня. Страница идёт сверху вниз, и «Ввод» ведёт по ней в
    /// том же порядке: ответы, заголовок, запись. Прежде последний ответ
    /// уводил прямо в запись, мимо заголовка (решение P196, уточняет P185).
    private func next(after task: String) {
        let дела = asked.map(\.text)
        if let i = дела.firstIndex(of: task), i + 1 < дела.count {
            askingAt = дела[i + 1]
        } else {
            askingAt = nil
            // Ввод уходит из поля ответа, и только потом заголовок его
            // принимает: иначе два поля перетягивают клавиатуру.
            DispatchQueue.main.async { focused = .title }
        }
    }

    // MARK: - Заголовок

    /// Слова заголовка — без точек: точки стоят за ними значками (P358).
    private var titleWords: Binding<String> {
        Binding(get: { Geo.stripped(title) },
                set: { title = DiaryPage.title($0, keeping: title) })
    }

    /// Заголовок без одной точки — той, что удаляют крестиком (P362).
    static func without(_ line: String, in title: String) -> String {
        guard let r = title.range(of: line) else { return title }
        var out = title
        out.removeSubrange(r)
        return out
    }

    /// Новые слова заголовка, а точки — прежние, за словами.
    static func title(_ words: String, keeping old: String) -> String {
        let ns = old as NSString
        let points = Geo.points(inText: old).map { ns.substring(with: $0.range) }
        let head = words.trimmingCharacters(in: .whitespaces)
        return ([head] + points).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var titleField: some View {
        let points = Geo.points(inText: title)
        let ns = title as NSString
        return VStack(spacing: 0) {
          HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                if title.isEmpty {
                    Text(T("Заголовок дня", "Title of the day"))
                        .font(Look.serif(16.5))
                        .foregroundStyle(Look.inkFaint)
                        .allowsHitTesting(false)
                }
                if editable {
                    TextField("", text: titleWords)
                        .font(Look.serif(16.5, weight: .semibold))
                        .foregroundStyle(Look.ink)
                        .focused($focused, equals: .title)
                        // Заголовок взяли в руки — просьба «перейти в
                        // запись», если вдруг висит, снимается (P389).
                        .onChange(of: focused) { _, now in
                            if now == .title { toText = false }
                        }
                        .submitLabel(.next)
                        // «Ввод» уводит из заголовка в текст записи, а не
                        // просто убирает клавиатуру (решение P40).
                        .onSubmit {
                            focused = nil
                            toText = true
                        }
                } else {
                    Text(Geo.stripped(title))
                        .font(Look.serif(16.5, weight: .semibold))
                        .foregroundStyle(Look.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Точки в заголовке — значками за словами (P358). Касание — на
            // карту; подержать и потянуть вниз — назад в текст; подержать и
            // отпустить — крупнее и с крестиком «удалить» (P362).
            ForEach(points.indices, id: \.self) { k in
                let line = ns.substring(with: points[k].range)
                TitlePoint(point: points[k].point,
                           armed: armedPoint == line,
                           open: { onOpenPoint?(points[k].point) },
                           arm: editable ? { on in
                               withAnimation(.easeOut(duration: 0.15)) { armedPoint = on ? line : nil }
                           } : nil,
                           down: editable ? { onPointFromTitle?(line) } : nil,
                           delete: editable ? {
                               armedPoint = nil
                               title = DiaryPage.title(Geo.stripped(title),
                                                       keeping: DiaryPage.without(line, in: title))
                           } : nil)
            }
          }
            // Заголовок — подпись к дню, а не вывеска: место на странице
            // принадлежит записи (решение P162).
            .frame(height: 23, alignment: .leading)
            // Где заголовок на экране — туда бросают точку из текста (P358).
            .background(GeometryReader { geo in
                let zone = geo.frame(in: .global)
                Color.clear
                    .onAppear { if editable { DiaryEditor.titleZone = zone } }
                    .onChange(of: zone) { _, now in if editable { DiaryEditor.titleZone = now } }
            })
            .padding(.bottom, 5)

            Rectangle().fill(Look.rule).frame(height: 1)
        }
        .padding(.top, 4)
    }

    // MARK: - Текст

    /// Поле записи — одно и то же и на открытой странице, и на соседних.
    /// Соседняя лишь не правится. Иначе рядом стоят два разных способа
    /// набрать текст, и строки на повороте расходятся (P114).
    private var textField: some View {
        DiaryEditor(text: $text, size: size, serif: true, stamped: true,
                    editable: editable, caretToEnd: $caretToEnd,
                    startEditing: $toText,
                    onFocus: { if onFocusText() { caretToEnd = true } },
                    // Под записью всегда пять пустых строк — место, куда
                    // коснуться, чтобы продолжить (P346).
                    grows: true, minHeight: 320, room: size * 1.5 * 5, resolve: resolve,
                    onOpenPhoto: onOpenInline, onReturnPhoto: onReturnPhoto,
                    onOpenPoint: onOpenPoint, onPointToTitle: onPointToTitle, onCaret: onCaret,
                    moving: editable, onEditing: onEditing,
                    placeCaret: placeCaret)
            // Вдвое меньше, чем было: пробел между заголовком и записью не
            // должен отнимать место у страницы (P311).
            .padding(.top, 8)
    }
}

/// Точка в заголовке дня (P358, P362): касание — карта; подержать и
/// потянуть вниз — назад в текст записи; подержать и отпустить — крупнее и
/// с крестиком «удалить».
private struct TitlePoint: View {
    let point: GeoPoint
    var armed = false
    var open: () -> Void
    var arm: ((Bool) -> Void)?
    var down: (() -> Void)?
    var delete: (() -> Void)?

    @State private var lifted = false
    @State private var drop: CGFloat = 0

    var body: some View {
        PointChipView(point: point)
            .scaleEffect(armed ? 1.3 : 1)
            .offset(y: drop)
            .overlay(alignment: .topTrailing) {
                if armed, let delete {
                    DeleteBadge(action: delete)
                        .offset(x: PointChipView.width(point) * 0.15 + 13, y: -18)
                }
            }
            .zIndex(armed || drop != 0 ? 1 : 0)
            .contentShape(Capsule())
            .onTapGesture {
                if armed { arm?(false) } else { open() }
            }
            .gesture(arm == nil ? nil : hold)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(T("Точка на карте: ", "Place on the map: ") + point.label)
    }

    private var hold: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !lifted {
                    lifted = true
                    Feel.lift()
                }
                if let drag { drop = max(0, drag.translation.height) }
            }
            .onEnded { value in
                lifted = false
                let way = drop
                withAnimation(.easeOut(duration: 0.15)) { drop = 0 }
                guard case .second(true, _) = value else { return }
                // Потянули вниз, под черту заголовка, — назад в текст.
                if way > 24 {
                    arm?(false)
                    Feel.light()
                    down?()
                } else {
                    arm?(true)
                }
            }
    }
}
