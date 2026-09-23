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
    }

    private var app: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                appbar
                canvas
                Rectangle().fill(Look.rule).frame(height: 1)
                tabbar
            }
            .background(Look.chrome.ignoresSafeArea())

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
        .clipped()
    }

    // MARK: - Шапка

    /// Только то, что принадлежит приложению, а не дню: настройки и меню
    /// страницы. Имя дня, дата и вкладки уехали внутрь страницы — они
    /// перелистываются вместе с ней.
    private var appbar: some View {
        HStack {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { shell.showingSettings = true }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19))
                    .foregroundStyle(shell.showingSettings ? Look.accent : Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .accessibilityLabel("Настройки")

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { shell.showingMenu = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(store.editing ? Look.accent : Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .accessibilityLabel("Меню страницы")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(Look.chrome)
    }

    // MARK: - Экран

    /// Книга и два вкладыша.
    ///
    /// «Сегодня» — сама книга, она лежит всегда. Календарь наезжает на неё
    /// сверху, поиск — снизу: так их и достают из бумажного ежедневника, и
    /// так у каждого раздела своё постоянное направление — через несколько
    /// дней рука помнит его без подсказки (решение P146).
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
                panel(.search, from: .bottom, over: geo.size) { SearchView() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Вкладыш: лежит за краем экрана и выезжает на книгу.
    private func panel<V: View>(_ which: Shell.Screen, from edge: Edge,
                                over size: CGSize,
                                @ViewBuilder content: () -> V) -> some View {
        let on = shell.screen == which
        // До первой раскладки высота нулевая. Если поверить ей, плашки
        // окажутся на книге и мигнут при запуске — а ничто не должно
        // двигаться само (P113). Поэтому до измерения уводим их заведомо
        // далеко. Толщина торца прибавляется: он тоже должен уйти за край.
        let away = (edge == .top ? -1 : 1) * max(size.height + BoardEdge.depth, 1200)
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
            section("календарь", "Календарь", .calendar)
            section("сегодня", "Сегодня", .today)
            section("поиск", "Поиск", .search)
        }
        .padding(.top, 11)
        .padding(.bottom, 4)
        .background(Look.chrome)
    }

    private func section(_ icon: String, _ name: String, _ target: Shell.Screen) -> some View {
        let on = shell.screen == target
        return Button {
            store.prune()
            store.save()
            if target == .today {
                if shell.screen == .today && !store.isToday { shell.say("Вернулись на сегодня") }
                store.go(to: DayStore.today())
            } else {
                archive.reload()
            }
            open(target)
        } label: {
            VStack(spacing: 5) {
                // Значки нарисованы автором от руки и обведены в вектор:
                // ежедневник, раскрытый в начале, посередине и в конце.
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                Text(name).font(Look.sans(11.5, weight: on ? .medium : .regular))
            }
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
        if target != shell.screen { hideKeyboard() }
        withAnimation(.spring(response: 0.80, dampingFraction: 0.90)) {
            shell.screen = target
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
