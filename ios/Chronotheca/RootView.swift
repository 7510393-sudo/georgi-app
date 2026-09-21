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
                if shell.screen == .today {
                    subbar
                    tabs
                } else {
                    Rectangle().fill(Look.rule).frame(height: 1)
                }
                canvas
                if shell.screen == .today { attachbar }
                Rectangle().fill(Look.rule).frame(height: 1)
                tabbar
            }
            .background(background.ignoresSafeArea())

            if shell.showingMenu { MenuSticker() }
            if let notice = shell.notice {
                toast(notice).frame(maxWidth: .infinity, maxHeight: .infinity,
                                    alignment: .bottom)
            }
        }
        // Нижние полоски стоят на месте, что бы ни случилось: клавиатура их
        // не поднимает. Иначе значки пляшут по экрану и в них не попасть.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .tint(Look.accent)
        .sheet(isPresented: $shell.showingSettings) { SettingsSheet() }
        .sheet(isPresented: $shell.showingFile) { FileSheet() }
        .sheet(item: $shell.roller) { RollerSheet(roller: $0) }
        .onAppear { shell.openRequestedScreen(store) }
    }

    /// Область содержимого: шторка «Подробности» живёт только внутри неё —
    /// она не закрывает ни вкладки, ни нижние кнопки.
    private var canvas: some View {
        ZStack(alignment: .trailing) {
            screen
            if shell.drawer != nil { DetailsDrawer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Оттенок дня недели — только на экране дня. В календаре и поиске он
    /// был бы враньём: там не один день, а много.
    private var background: Color {
        guard shell.screen == .today else { return Look.planBg }
        return shell.tab == .diary ? Look.diaryBg : Ru.tint(store.date)
    }

    // MARK: - Шапка

    private var appbar: some View {
        HStack {
            Button { shell.showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19))
                    .foregroundStyle(Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .accessibilityLabel("Настройки")

            Spacer(minLength: 0)

            Text(shell.screen == .today ? store.title : shell.screenName)
                .font(.system(size: 23, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Look.ink)

            Spacer(minLength: 0)

            Button { withAnimation(.easeOut(duration: 0.2)) { shell.showingMenu = true } } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(store.editing ? Look.accent : Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .accessibilityLabel("Меню страницы")
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .background(Look.chrome)
    }

    /// День недели своим цветом и полная дата под ним — чтобы не гадать,
    /// какое сегодня число, и видеть, куда тебя занесло листание.
    private var subbar: some View {
        VStack(spacing: 2) {
            Text(Ru.weekday(store.date))
                .font(Look.sans(12.5))
                .tracking(0.75)
                .foregroundStyle(Ru.dayColor(store.date))
            Text(Ru.longDate(store.date))
                .font(Look.sans(15))
                .foregroundStyle(Look.inkSoft)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
        .background(Look.chrome)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Shell.Tab.allCases) { tab in tabButton(tab) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
        }
        .background(Look.chrome)
    }

    private func tabButton(_ tab: Shell.Tab) -> some View {
        let on = shell.tab == tab
        let page = tab == .diary ? Look.diaryBg : Ru.tint(store.date)
        return Button {
            store.prune()
            store.save()
            shell.tab = tab
        } label: {
            Text(tab.rawValue.uppercased())
                .font(Look.sans(13, weight: on ? .semibold : .regular))
                .tracking(1.56)
                .foregroundStyle(on ? Look.ink : Look.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 9)
                .padding(.bottom, 10)
                .background(page)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10,
                                                  topTrailingRadius: 10))
                .overlay(TabBorder(radius: 10).stroke(Look.rule, lineWidth: 1))
        }
        .offset(y: on ? 1 : 0)
        .zIndex(on ? 1 : 0)
    }

    // MARK: - Экран

    @ViewBuilder private var screen: some View {
        switch shell.screen {
        case .today:    DayScreen()
        case .calendar: CalendarView()
        case .search:   SearchView()
        }
    }

    // MARK: - Вложения

    private var attachbar: some View {
        HStack(spacing: 0) {
            attach("photo", "фото")
            attach("waveform", "аудио")
            attach("doc", "файлы")
            attach("mappin.and.ellipse", "геоточка")
        }
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(Look.chrome)
    }

    private func attach(_ icon: String, _ name: String) -> some View {
        Button {
            shell.say("Вложения ещё не сделаны — следующий срез работы.")
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17))
                Text(name.uppercased())
                    .font(Look.sans(9))
                    .tracking(0.45)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Look.inkFaint)
        }
    }

    // MARK: - Разделы

    private var tabbar: some View {
        HStack(spacing: 0) {
            section("calendar", "Календарь", .calendar)
            section("sun.max", "Сегодня", .today)
            section("magnifyingglass", "Поиск", .search)
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
            if target == .today && shell.screen == .today && !store.isToday {
                store.go(to: DayStore.today())
                shell.say("Вернулись на сегодня")
            } else if target == .today {
                store.go(to: DayStore.today())
            }
            if target != .today { archive.reload() }
            withAnimation(.easeOut(duration: 0.18)) { shell.screen = target }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 20))
                Text(name)
                    .font(Look.sans(10, weight: on ? .medium : .regular))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Look.accent : Look.inkSoft)
        }
    }

    // MARK: - Сообщение

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.84), in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 92)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

/// Экран дня: две вкладки на одном дне и общий для них свайп.
struct DayScreen: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    /// Куда уехал прошлый день: влево (к завтрашнему) или вправо (к вчерашнему).
    @State private var direction = 1

    var body: some View {
        Group {
            if shell.tab == .plan { PlanView() } else { DiaryView() }
        }
        // День уезжает, на его место встаёт соседний. Без этого листание
        // выглядит подменой содержимого, а не переходом — а весь смысл в том,
        // что дни лежат рядом, как страницы.
        .id(store.date)
        .transition(.asymmetric(
            insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // Свайп листает дни, как в прототипе: горизонтальное движение должно
        // быть заметно длиннее вертикального, иначе это прокрутка. Жест
        // одновременный, иначе прокрутка списка забирает касание себе.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { g in
                    guard shell.drawer == nil else { return }
                    let dx = g.translation.width, dy = g.translation.height
                    guard abs(dx) > 64, abs(dx) > abs(dy) * 1.6 else { return }
                    go(by: dx < 0 ? 1 : -1)
                }
        )
    }

    private func go(by step: Int) {
        direction = step
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        withAnimation(.easeOut(duration: 0.28)) { store.move(by: step) }
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
