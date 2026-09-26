import SwiftUI
import UniformTypeIdentifiers

/// Оболочка приложения: шапка, вкладки, экран, нижние кнопки.
///
/// Порядок сверху вниз тот же, что в прототипе: имя экрана, день недели и
/// дата, «План / Дневник», сам экран, полоска вложений и три раздела внизу.
struct RootView: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    /// Карта ещё на плашке, пока та уезжает (P242).
    @State private var keepMap = false


    /// Человек должен увидеть полный путь до того, как что-то создано.
    private static func proposalText(_ p: Vault.Proposal) -> String {
        var out = "Записей здесь не нашлось. Приложение может завести новую папку:\n\n"
        out += p.path
        out += "\n\nЭто будет отдельный архив — прежние записи останутся там, где лежат."
        if p.insideArchive {
            out += "\n\nПохоже, вы зашли внутрь уже существующего архива. "
            out += "Тогда выберите не эту папку, а саму «\(Vault.folderName)» — "
            out += "или место, где она лежит."
        }
        return out
    }

    private static func transferText(_ t: Transfer.Offer) -> String {
        var out = "В прежней папке осталось записей: \(t.records).\n\n"
        out += t.fromPath
        out += "\n\nПеренести их сюда:\n\n"
        out += t.toPath
        out += "\n\nСначала делается копия, и только потом убирается "
        out += "прежний файл. Прервётся — ничего не пропадёт, перенос можно "
        out += "будет продолжить."
        return out
    }

    private static func reportText(_ r: Transfer.Report) -> String {
        var out = "Перенесено файлов: \(r.moved)."
        if r.kept > 0 {
            out += "\n\nОсталось в прежней папке: \(r.kept). "
            out += "За те же числа здесь уже есть записи, и приложение "
            out += "не стало решать за вас, какая из них важнее. Обе целы."
        }
        if r.failed > 0 {
            out += "\n\nНе удалось перенести: \(r.failed). "
            out += "Эти файлы остались на прежнем месте."
        }
        if r.kept == 0 && r.failed == 0 {
            out += " Прежняя папка осталась на месте, но записей в ней больше нет."
        } else {
            out += "\n\nПрежняя папка:\n\n" + r.fromPath
        }
        return out
    }

    private static let moved = """
        Вы её переименовали или передвинули. Приложение пошло за ней следом \
        и пишет теперь сюда:
        """

    var body: some View {
        Group {
            if vault.root == nil { WelcomeView() } else { app }
        }
        .fileImporter(isPresented: $shell.picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                vault.adopt(url)
                store.load()
                archive.reload()
                // Выбрав папку, человек хочет увидеть свои записи, а не тот
                // экран, с которого он ушёл за папкой (решение P170).
                shell.screen = .today
            }
        }
        .alert("Завести здесь новую папку?",
               isPresented: Binding(get: { vault.proposal != nil },
                                    set: { if !$0 { vault.declineProposal() } }),
               presenting: vault.proposal) { p in
            Button("Отмена", role: .cancel) { vault.declineProposal() }
            Button("Завести") { vault.acceptProposal() }
        } message: { p in
            Text(Self.proposalText(p))
        }
        .alert("Перенести записи?",
               isPresented: Binding(get: { vault.transfer != nil },
                                    set: { if !$0 { vault.declineTransfer() } }),
               presenting: vault.transfer) { _ in
            Button("Оставить", role: .cancel) { vault.declineTransfer() }
            Button("Перенести") {
                vault.moveRecords()
            }
        } message: { t in
            Text(Self.transferText(t))
        }
        .alert("Перенос закончен",
               isPresented: Binding(get: { vault.transferDone != nil },
                                    set: { if !$0 { vault.transferDone = nil } }),
               presenting: vault.transferDone) { _ in
            Button("Понятно") {
                vault.transferDone = nil
                store.load()
                archive.reload()
            }
        } message: { r in
            Text(Self.reportText(r))
        }
        .alert("Папка переехала",
               isPresented: Binding(get: { vault.moved != nil },
                                    set: { if !$0 { vault.moved = nil } })) {
            Button("Понятно") { vault.moved = nil }
        } message: {
            Text(Self.moved + "\n\n" + (vault.moved ?? ""))
        }
        // Запись поправили в другом месте, пока она была открыта здесь.
        // Ничего не затёрто: чужая правка на экране, своя — рядом в папке.
        // Человек должен знать, где её искать (решение P183).
        .alert("Запись изменилась в другом месте",
               isPresented: Binding(get: { store.conflict != nil },
                                    set: { if !$0 { store.conflict = nil } })) {
            Button("Понятно") { store.conflict = nil }
        } message: {
            Text(Self.conflictText(store.conflict ?? ""))
        }
    }

    static func conflictText(_ name: String) -> String {
        """
        Пока день был открыт здесь, его файл поправили в другом месте — \
        на Mac или на другом устройстве. На экране теперь та версия.

        Ваша правка не пропала: она лежит рядом, в той же папке, в файле \
        «\(name)». Откройте его в «Файлах» и перенесите нужное.
        """
    }

    private var app: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                canvas
                Rectangle().fill(Look.rule).frame(height: 1)
                tabbar
            }
            .background(Look.chrome.ignoresSafeArea())

            // Верхней строки больше нет: шестерёнка и три точки нарисованы
            // на уголках бумаги, торчащих сверху слева и справа, а имя дня
            // поднялось между ними (P229).
            corners

            if shell.showingMenu { MenuSticker() }
            if shell.showingSettings {
                SettingsSticker().frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let notice = shell.notice {
                toast(notice)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            // Перенос между памятью телефона и iCloud идёт минутами. Пока он
            // идёт, трогать записи нельзя: экран закрыт, и на нём видно, что
            // происходит и сколько осталось.
            if let m = vault.moving {
                MovingView(progress: m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Нижние разделы стоят на месте, что бы ни случилось: клавиатура их
        // не поднимает. Иначе значки пляшут по экрану и в них не попасть.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .tint(Look.accent)
        .onChange(of: shell.screen) { old, new in
            follow(from: old, to: new)
            if new == .map {
                keepMap = true
            } else if old == .map {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if shell.screen != .map { keepMap = false }
                }
            }
        }
        // Снимок во весь экран — один на всё приложение: открывают его и
        // из плана, и из дневника (P203).
        .fullScreenCover(item: $shell.openedPhoto) { opened in
            let links = store.links(opened.tab)
            AttachmentViewer(
                url: opened.url ?? (links.indices.contains(opened.index)
                    ? store.photoURL(links[opened.index]) : nil),
                onRemove: opened.url == nil && store.canEdit(opened.tab) ? {
                    store.removePhoto(at: opened.index, from: opened.tab)
                    shell.openedPhoto = nil
                    shell.say("Убрано со страницы. Сам файл остался в папке.")
                } : nil,
                // Снимок из текста можно вернуть в полоску (P216).
                onReturn: opened.link != nil && store.canEdit(opened.tab) ? {
                    if let link = opened.link { store.returnToStrip(link) }
                    shell.openedPhoto = nil
                } : nil,
                close: { shell.openedPhoto = nil })
        }
        .sheet(isPresented: $shell.showingFile) { FileSheet() }
        .sheet(item: $shell.roller) { RollerSheet(roller: $0) }
        .onAppear {
            // Опись архива нужна не только календарю и поиску: без неё
            // облачко «…помнишь?» не знает, есть ли что вспомнить, и не
            // появляется никогда. Читаем папку сразу при запуске.
            archive.reload()
            shell.openRequestedScreen(store)
        }
    }

    /// Область содержимого: шторка «Подробности» живёт только внутри неё.
    private var canvas: some View {
        ZStack(alignment: .trailing) {
            screen
            if shell.drawer != nil { DetailsDrawer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Шапка и нижние разделы лежат поверх страницы и прижимают её: обе
        // бросают на неё тень. Так видно, что они сверху, а страница под
        // ними — на любом экране (решение P192).
        .overlay(alignment: .bottom) { Shade(down: false) }
        .clipped()
    }

    // MARK: - Шапка

    /// Шестерёнка и три точки — на уголках бумаги, торчащих сверху: левый
    /// голубой, как бумажка настроек, правый желтоватый, как бумажка меню.
    /// У уголков тень — они лежат поверх страницы (P229). Меню у каждого
    /// экрана своё; кнопка не пропадает, что бы ни было открыто (P188).
    private var corners: some View {
        HStack(alignment: .top) {
            Button {
                shell.pullOut(settings: true)
            } label: {
                Corner(leading: true, paper: Look.note, edge: Look.noteEdge, icon: "gearshape",
                       tint: shell.showingSettings ? Look.accent : Look.inkSoft)
                    // Пока листок вытянут, его угол — это и есть уголок.
                    .opacity(shell.showingSettings ? 0 : 1)
            }
            .buttonStyle(.plain)
            // Уголок тянут вниз, и бумажка идёт за пальцем (P233).
            .simultaneousGesture(pull(\.showingSettings, \.settingsPull))
            .accessibilityLabel("Настройки")

            Spacer(minLength: 0)

            Button {
                shell.pullOut(settings: false)
            } label: {
                Corner(leading: false, paper: Look.sticker, edge: Look.stickerEdge, icon: "ellipsis",
                       tint: dotsLit ? Look.accent : Look.inkSoft)
                    .opacity(shell.showingMenu ? 0 : 1)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(pull(\.showingMenu, \.menuPull))
            .accessibilityLabel(dotsLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Бумажку вытягивают за уголок: она идёт за пальцем; отпустили,
    /// протянув заметно, — доезжает сама, иначе уезжает обратно (P233).
    private func pull(_ showing: ReferenceWritableKeyPath<Shell, Bool>,
                      _ amount: ReferenceWritableKeyPath<Shell, CGFloat?>) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    if !shell[keyPath: showing] { shell[keyPath: showing] = true }
                    shell[keyPath: amount] = max(0, 1 - max(0, drag.translation.height) / 420)
                }
            }
            .onEnded { drag in
                let settings = showing == \Shell.showingSettings
                if drag.translation.height > 90 || drag.predictedEndTranslation.height > 220 {
                    shell.pullOut(settings: settings)
                } else {
                    shell.tuckIn(settings: settings)
                }
            }
    }

    /// Точки горят, когда в меню включено что-то необычное: режим
    /// изменений на странице дня или поиск не по всему архиву.
    private var dotsLit: Bool {
        switch shell.screen {
        case .today:    return store.editing(shell.tab)
        case .calendar, .map: return false
        case .search:   return shell.scope != .all
        }
    }

    private var dotsLabel: String {
        switch shell.screen {
        case .today:    return "Меню страницы"
        case .calendar: return "Меню календаря"
        case .map:      return "Меню карты"
        case .search:   return "Меню поиска"
        }
    }

    // MARK: - Экран

    /// Книга и два вкладыша.
    ///
    /// «Сегодня» — сама книга, она лежит всегда. Календарь и поиск наезжают
    /// на неё сверху — оба, как кладут сверху вкладыш в бумажном
    /// ежедневнике. Поиск выезжал снизу, из-под книги: снизу вещи не
    /// приходят, туда их убирают (решения P146, P178).
    ///
    /// Вкладыши не появляются и не исчезают, а стоят за краем экрана и
    /// выезжают: собирать их заново в начале хода — значит уронить первые
    /// кадры, а ход должен быть гладким.
    private var screen: some View {
        GeometryReader { geo in
            ZStack {
                // Под плашкой книга не отзывается. Иначе движение вбок по
                // поиску доставалось перелистыванию дней, и человека
                // выбрасывало на «Сегодня» (решение P160).
                DayPages()
                    .allowsHitTesting(shell.screen == .today)
                panel(.calendar, from: .top, over: geo.size) { CalendarView() }
                // Карта — такая же плашка. Рисуется, только пока нужна:
                // иначе приложение спрашивало бы место при самом запуске.
                // Уходя, она остаётся на плашке, пока та не уедет за край, —
                // иначе плашка уезжала пустой и карта просто пропадала (P242).
                panel(.map, from: .top, over: geo.size) {
                    if shell.screen == .map || keepMap { MapScreen() } else { Color.clear }
                }
                panel(.search, from: .top, over: geo.size) { SearchView() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Вкладыш: лежит за краем экрана и выезжает на книгу.
    private func panel<V: View>(_ which: Shell.Screen, from edge: Edge,
                                over size: CGSize,
                                @ViewBuilder content: () -> V) -> some View {
        let on = shell.lowered == which
        // Плашка уезжает ровно на свою высоту — не дальше.
        //
        // Раньше её уводили заведомо далеко, на 1200 точек, и она проходила
        // вдвое больше, чем видно на экране: разгон и торможение хода
        // приходились на путь за краем. Оттого приход выглядел мягким, а
        // уход — резким: на экране оставалась только разгонная половина
        // (решение P181). Толщина торца прибавляется: он тоже должен уйти
        // за край.
        //
        // До первой раскладки высота нулевая. Если поверить ей, плашки
        // окажутся на книге и мигнут при запуске — а ничто не должно
        // двигаться само (P113), — поэтому до измерения уводим их далеко.
        //
        // Сверх торца — ещё и его тень: стоящая за краем плашка не должна
        // бросать тень на экран. Тень под шапкой рисуется нарочно, одна на
        // все экраны (решение P192).
        let away = (edge == .top ? -1 : 1)
            * (size.height > 0 ? size.height + BoardEdge.depth + BoardEdge.shade : 1200)
        return content()
            .frame(width: size.width, height: size.height)
            .background(Look.chrome)
            // Торец стоит с той стороны, которой плашка идёт вперёд, и
            // выступает за её край — то есть лежит на книге, а не на самой
            // плашке. На месте он уходит за край экрана и не виден: толщина
            // показывается движением, а стоящее не должно ничего занимать.
            .overlay(alignment: edge == .top ? .bottom : .top) {
                BoardEdge(fromTop: edge == .top)
                    .offset(y: edge == .top ? BoardEdge.depth : -BoardEdge.depth)
            }
            .offset(y: on ? 0 : away)
            // Уехавшая плашка не ловит касания: под ней живая книга.
            .allowsHitTesting(on)
    }

    // MARK: - Разделы

    private var tabbar: some View {
        HStack(spacing: 0) {
            // Сегодня, календарь, карта, поиск (P239). Глобус нарисован
            // автором (P248).
            section("сегодня", "Сегодня", .today)
            section("календарь", "Календарь", .calendar)
            section("карта", "Карта", .map)
            section("поиск", "Поиск", .search)
        }
        // На 5% тоньше, чем было, при книжке на 10% крупнее (P212).
        .padding(.top, 7)
        .padding(.bottom, 2)
        .background(Look.chrome)
    }

    private func scale(_ target: Shell.Screen) -> CGFloat {
        switch target {
        case .today:    return 1.10
        case .search:   return 1.05
        case .calendar, .map: return 1
        }
    }

    private func section(_ icon: String, _ name: String, _ target: Shell.Screen,
                         system: Bool = false) -> some View {
        let on = shell.screen == target
        return Button {
            store.prune()
            store.save()
            if target == .today {
                if shell.screen == .today && !store.isToday {
                    // Возвращаемся не мгновенно, а перелистнув страницы:
                    // дорога домой должна быть видна (решение P164).
                    shell.say("Вернулись на сегодня")
                    shell.goHome = true
                } else if !store.isToday {
                    store.go(to: DayStore.today())
                }
            } else {
                archive.reload()
            }
            open(target)
        } label: {
            VStack(spacing: 5) {
                // Значки нарисованы автором от руки и обведены в вектор:
                // ежедневник, раскрытый в начале, посередине и в конце.
                Group {
                    if system {
                        Image(systemName: icon).resizable().scaledToFit().padding(4)
                    } else {
                        Image(icon).renderingMode(.template).resizable().scaledToFit()
                    }
                }
                // Книжка на 10%, микроскоп на 5% крупнее прочих (P227).
                .frame(width: 35 * scale(target), height: 35 * scale(target))
                Text(name).font(Look.sans(11.5, weight: on ? .medium : .regular))
            }
            // Открытый раздел — на светлой подушке. Подушка выходит за
            // значок наружу и не меняет высоты полосы (P218).
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(on ? Look.accent.opacity(0.10) : .clear)
                    .padding(.horizontal, -16)
                    .padding(.vertical, -3))
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Look.accent : Look.inkSoft)
        }
    }

    /// Открыть раздел: плашка надвигается на книгу, книга остаётся на месте.
    ///
    /// Ход тяжёлый: долгое торможение без отскока. Так ведёт себя предмет с
    /// весом — его не бросают, он доезжает сам и гасит скорость о воздух.
    /// Быстрый ход читался бы как смена экрана, а не как движение вещи.
    private func open(_ target: Shell.Screen) {
        // Уходя на карту, запомнить, где был курсор: точка с карты ляжет
        // туда (P240).
        if target == .map, shell.screen != .map {
            store.noteLeaving(fromToday: shell.screen == .today)
        }
        if target != shell.screen { hideKeyboard() }
        shell.screen = target
    }

    /// Опустить или поднять плашку вслед за сменой экрана.
    ///
    /// С календаря на поиск и обратно — по очереди: сперва уходящая плашка
    /// почти целиком уезжает вверх, и только потом опускается новая.
    /// Разом они шли навстречу, и новая обгоняла уходящую (решение P202).
    private func follow(from old: Shell.Screen, to new: Shell.Screen) {
        let heavy = Animation.spring(response: 0.80, dampingFraction: 0.90)
        guard old != .today, new != .today, shell.lowered != .today else {
            withAnimation(heavy) { shell.lowered = new }
            return
        }
        withAnimation(.easeIn(duration: 0.34)) { shell.lowered = .today }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [shell] in
            // Пока уходила плашка, человек мог нажать ещё раз.
            guard shell.screen == new else { return }
            withAnimation(heavy) { shell.lowered = new }
        }
    }

    // MARK: - Сообщение

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Look.planBg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(Look.ink, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 80)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

/// Обводка закладки «Детали»: скруглена слева, открыта справа —
/// полоска выглядывает из-за правого края строки.
struct SideTabBorder: Shape {
    let radius: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
                 startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// Обводка закладки: верх и бока, без низа — чтобы выбранная вкладка
/// сливалась со своей страницей, как лист в картотеке.
struct TabBorder: Shape {
    let radius: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// Уголок стикера, наклеенного выше экрана: слева торчит правый нижний
/// угол голубого стикера, справа — левый нижний угол желтоватого. Стикер
/// наклеен ровно, по вертикали; у него тень — он лежит поверх страницы
/// (P229, P231, P236).
struct Corner: View {
    static let size: CGFloat = 58

    let leading: Bool
    let paper: Color
    let edge: Color
    let icon: String
    let tint: Color

    var body: some View {
        ZStack(alignment: leading ? .topLeading : .topTrailing) {
            CornerShape(leading: leading)
                .fill(paper)
                .shadow(color: .black.opacity(0.25), radius: 3, x: leading ? 1.5 : -1.5, y: 2.5)
            CornerShape(leading: leading)
                .stroke(edge, lineWidth: 0.8)
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)
                .padding(leading ? .leading : .trailing, 9)
                .padding(.top, 7)
        }
        .frame(width: Corner.size, height: Corner.size)
        .contentShape(CornerShape(leading: leading))
    }
}

/// Видимая часть стикера: от края экрана его нижняя сторона идёт вниз к
/// острому углу, от угла боковая сторона уходит вверх за край экрана.
struct CornerShape: Shape {
    let leading: Bool

    func path(in r: CGRect) -> Path {
        // Точки для левого уголка; правый — зеркально.
        // Стикер наклеен ровно, без наклона: видна его нижняя сторона и
        // боковая, угол между ними прямой (P236).
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.86, y: 0),              // боковая сторона уходит за верх
            CGPoint(x: 0.86, y: 0.80),           // прямой угол
            CGPoint(x: 0, y: 0.80),              // нижняя сторона уходит за край
        ]
        var p = Path()
        for (i, pt) in points.enumerated() {
            let x = leading ? r.minX + pt.x * r.width : r.maxX - pt.x * r.width
            let at = CGPoint(x: x, y: r.minY + pt.y * r.height)
            if i == 0 { p.move(to: at) } else { p.addLine(to: at) }
        }
        p.closeSubpath()
        return p
    }
}

/// Тень, которую неподвижная полоса кладёт на страницу под собой.
struct Shade: View {
    /// Полоса сверху — тень идёт вниз; снизу — вверх.
    let down: Bool

    var body: some View {
        LinearGradient(colors: [.black.opacity(0.13), .black.opacity(0)],
                       startPoint: down ? .top : .bottom,
                       endPoint: down ? .bottom : .top)
            .frame(height: 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
