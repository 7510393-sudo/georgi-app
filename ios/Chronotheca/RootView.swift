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
        .alert("Папка переехала",
               isPresented: Binding(get: { vault.moved != nil },
                                    set: { if !$0 { vault.moved = nil } })) {
            Button("Понятно") { vault.moved = nil }
        } message: {
            Text("Вы её переименовали или передвинули. Приложение пошло за ней "
                 + "следом и пишет теперь сюда:\n\n" + (vault.moved ?? ""))
        }
    }

    private var app: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                appbar
                if shell.screen == .today {
                    subbar
                    tabs
                }
                screen
                if shell.screen == .today { attachbar }
                Rectangle().fill(Look.rule).frame(height: 1)
                tabbar
            }
            .background(background.ignoresSafeArea())

            if let notice = shell.notice { toast(notice) }
        }
        .tint(Look.accent)
        .sheet(isPresented: $shell.showingMenu) { MenuSheet() }
        .sheet(isPresented: $shell.showingFolder) { FolderSheet() }
        .sheet(isPresented: $shell.showingFile) { FileSheet() }
        .sheet(item: $shell.roller) { RollerSheet(roller: $0) }
        .onAppear { shell.openRequestedScreen(store) }
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
            Button { shell.showingFolder = true } label: {
                Image(systemName: "folder")
                    .font(.system(size: 18))
                    .foregroundStyle(Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .accessibilityLabel("Где лежат записи")

            Spacer(minLength: 0)

            Text(shell.screen == .today ? store.title : shell.screenName)
                .font(.system(size: 23, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Look.ink)

            Spacer(minLength: 0)

            Button { shell.showingMenu = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(store.editing ? Look.accent : Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .accessibilityLabel("Меню страницы")
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 2)
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
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Shell.Tab.allCases) { tab in tabButton(tab) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            Rectangle().fill(Look.rule).frame(height: 1)
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

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if shell.tab == .plan { PlanView() } else { DiaryView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Свайп листает дни, как в прототипе: горизонтальное движение
            // должно быть заметно длиннее вертикального, иначе это прокрутка.
            // Жест одновременный, а не обычный: иначе прокрутка списка и
            // текстовое поле забирают касание себе и лист не листается.
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { g in
                        guard shell.drawer == nil else { return }
                        let dx = g.translation.width, dy = g.translation.height
                        guard abs(dx) > 64, abs(dx) > abs(dy) * 1.6 else { return }
                        withAnimation(.easeOut(duration: 0.24)) {
                            store.move(by: dx < 0 ? 1 : -1)
                        }
                    }
            )

            if shell.drawer != nil { DetailsDrawer() }
        }
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
