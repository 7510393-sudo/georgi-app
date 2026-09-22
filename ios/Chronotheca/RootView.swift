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

    @ViewBuilder private var screen: some View {
        switch shell.screen {
        case .today:
            // Снимок для сличения: соседняя страница, но неподвижная.
            if shell.probingSide { SideDay(date: store.date) } else { DayPages() }
        case .calendar: CalendarView()
        case .search:   SearchView()
        }
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
            shell.screen = target
        } label: {
            VStack(spacing: 5) {
                // Значки нарисованы автором от руки и обведены в вектор:
                // ежедневник, раскрытый в начале, посередине и в конце.
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 27, height: 27)
                Text(name).font(Look.sans(11.5, weight: on ? .medium : .regular))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Look.accent : Look.inkSoft)
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
