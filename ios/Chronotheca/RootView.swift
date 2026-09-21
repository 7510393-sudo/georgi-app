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
                Divider().opacity(0.4)
                screen
                if shell.screen == .today { attachbar }
                Divider().opacity(0.4)
                tabbar
            }
            .background(background.ignoresSafeArea())

            if let notice = shell.notice { toast(notice) }
        }
        .sheet(isPresented: $shell.showingMenu) { MenuSheet() }
        .sheet(isPresented: $shell.showingFolder) { FolderSheet() }
        .sheet(isPresented: $shell.showingFile) { FileSheet() }
        .sheet(item: $shell.roller) { RollerSheet(roller: $0) }
    }

    /// Оттенок дня недели — только на экране дня. В календаре и поиске он
    /// был бы враньём: там не один день, а много.
    private var background: Color {
        shell.screen == .today ? Ru.tint(store.date) : Color(.systemGroupedBackground)
    }

    // MARK: - Шапка

    private var appbar: some View {
        HStack {
            Button { shell.showingFolder = true } label: {
                Image(systemName: "folder")
            }
            .accessibilityLabel("Где лежат записи")

            Spacer()

            Text(shell.screen == .today ? store.title : shell.screenName)
                .font(.headline)

            Spacer()

            Button { shell.showingMenu = true } label: {
                Image(systemName: "ellipsis")
                    .padding(6)
                    .background(store.editing ? Color.accentColor.opacity(0.18) : .clear,
                                in: Circle())
            }
            .accessibilityLabel("Меню страницы")
        }
        .font(.title3)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// День недели своим цветом и полная дата под ним — чтобы не гадать,
    /// какое сегодня число, и видеть, куда тебя занесло листание.
    private var subbar: some View {
        VStack(spacing: 1) {
            Text(Ru.weekday(store.date))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Ru.dayColor(store.date))
            Text(Ru.longDate(store.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    private var tabs: some View {
        Picker("", selection: $shell.tab) {
            ForEach(Shell.Tab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onChange(of: shell.tab) { _, _ in
            store.prune()
            store.save()
        }
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
        .padding(.vertical, 7)
    }

    private func attach(_ icon: String, _ name: String) -> some View {
        Button {
            shell.say("Вложения ещё не сделаны — следующий срез работы.")
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.footnote)
                Text(name).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Разделы

    private var tabbar: some View {
        HStack(spacing: 0) {
            section("calendar", "Календарь", .calendar)
            section("sun.max", "Сегодня", .today)
            section("magnifyingglass", "Поиск", .search)
        }
        .padding(.top, 7)
        .padding(.bottom, 2)
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
            VStack(spacing: 3) {
                Image(systemName: icon).font(.callout)
                Text(name).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Color.accentColor : .secondary)
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
