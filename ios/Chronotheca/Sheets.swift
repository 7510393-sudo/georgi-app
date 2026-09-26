import SwiftUI

// MARK: - Меню страницы

/// Три точки: жёлтая бумажка, приклеенная к верхнему правому углу.
///
/// Точки есть на каждом экране, а бумажка у каждого своя: на странице дня —
/// действия с днём, на календаре и в поиске — то, чем управляют там.
/// Включать с календаря режим изменений дня нельзя: он управлял бы чужим
/// экраном (решения P169, P188).
struct MenuSticker: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    /// Вид календаря — чтобы звать домой к месяцу или к году.
    @AppStorage("calendar.kind") private var calendarKind = CalendarView.Kind.month.rawValue

    var body: some View {
        if shell.showingMap {
            mapMenu
        } else {
            switch shell.screen {
            case .today:    dayMenu
            case .calendar: calendarMenu
            case .search:   searchMenu
            }
        }
    }

    /// Меню карты: строки повторяют кнопки полоски — для тех, кто ищет
    /// действие в меню, а не внизу (P219).
    private var mapMenu: some View {
        Sticker(side: .trailing, title: "Меню карты", close: close) {
            StickerItem(title: "Открыть в навигаторе",
                        note: shell.mapPoint == nil ? "выберите точку" : "→") {
                close()
                guard let point = shell.mapPoint else {
                    return shell.say("Сначала выберите точку долгим нажатием на карту.")
                }
                MapActions.navigate(point)
            }
            StickerItem(title: "Скопировать координаты",
                        note: shell.mapPoint == nil ? "выберите точку" : "→") {
                close()
                guard let point = shell.mapPoint else {
                    return shell.say("Сначала выберите точку долгим нажатием на карту.")
                }
                MapActions.copy(point)
                shell.say("Скопировано: " + Geo.text(point.at))
            }
            StickerItem(title: "Поделиться точкой",
                        note: shell.mapPoint == nil ? "выберите точку" : "→") {
                close()
                guard let point = shell.mapPoint else {
                    return shell.say("Сначала выберите точку долгим нажатием на карту.")
                }
                MapActions.share(point)
            }
            StickerItem(title: "Схема / спутник",
                        note: shell.mapSatellite ? "спутник" : "схема",
                        active: shell.mapSatellite) {
                shell.mapSatellite.toggle()
                close()
            }
            StickerItem(title: "Вернуться к странице дня") {
                close()
                withAnimation(.easeOut(duration: 0.25)) { shell.showingMap = false }
            }
            StickerItem(title: "Все места списком") {
                close()
                shell.say("Список мест ещё не сделан.")
            }
        }
    }

    private var dayMenu: some View {
        Sticker(side: .trailing, title: "Меню страницы", close: close) {
            // Режим — той вкладки, на которой человек стоит (P211).
            StickerItem(title: "Режим изменений — " + shell.tab.rawValue.lowercased(),
                        note: store.editing(shell.tab) ? "включён" : "выключен",
                        active: store.editing(shell.tab)) {
                store.setEditing(shell.tab, !store.editing(shell.tab))
                close()
            }
            StickerItem(title: "Показать файл этого дня") {
                close()
                shell.showingFile = true
            }
            StickerItem(title: "Перенести дело на другой день") {
                close()
                shell.say("Перенос дела ещё не сделан.")
            }
            StickerItem(title: "Поделиться днём") {
                close()
                shell.say("«Поделиться днём» ещё не сделано.")
            }
            StickerItem(title: "Удалить день") {
                close()
                shell.say("Удаление дня ещё не сделано.")
            }
        }
    }

    private var calendarMenu: some View {
        let year = calendarKind == CalendarView.Kind.year.rawValue
        return Sticker(side: .trailing, title: "Меню календаря", close: close) {
            StickerItem(title: year ? "Вернуться к этому году"
                                    : "Вернуться к этому месяцу") {
                close()
                shell.calendarHome = true
            }
            StickerItem(title: "Поделиться месяцем") {
                close()
                shell.say("«Поделиться месяцем» ещё не сделано.")
            }
        }
    }

    /// Где искать. Выбранное отмечено, а не спрятано: все три строки стоят
    /// всегда, чтобы рука находила их на одном месте.
    private var searchMenu: some View {
        Sticker(side: .trailing, title: "Меню поиска", close: close) {
            scopeItem("Искать везде", .all)
            scopeItem("Только в дневнике", .diary)
            scopeItem("Только в плане", .plan)
            StickerItem(title: "Очистить поиск") {
                close()
                if shell.query.isEmpty {
                    shell.say("Строка поиска и так пуста.")
                } else {
                    shell.query = ""
                }
            }
        }
    }

    private func scopeItem(_ title: String, _ scope: Shell.Scope) -> some View {
        let on = shell.scope == scope
        return StickerItem(title: title, note: on ? "✓" : "", active: on) {
            shell.scope = scope
            close()
        }
    }

    private func close() {
        withAnimation(.tuck) { shell.showingMenu = false }
    }
}

// MARK: - Настройки

/// Шестерёнка: голубая бумажка, приклеенная к верхнему левому углу.
///
/// Та же порода, что и меню страницы: рука узнаёт их одинаково, а цвет
/// говорит, к чему бумажка относится — к дню или ко всему приложению.
struct SettingsSticker: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    var body: some View {
        Sticker(side: .leading, title: "Настройки",
                paper: Look.note, edge: Look.noteEdge, width: 300, close: close) {
            place
            StickerItem(title: "Открыть папку в «Файлах»", edge: Look.noteEdge) {
                close()
                if let link = vault.filesLink { openURL(link) }
            }
            // Три места вместо одного окна выбора (P223): своя папка на
            // телефоне — одним касанием; своя папка человека — через окно.
            StickerItem(title: "Писать в другое место", edge: Look.noteEdge) {
                choosingPlace = true
            }
            if let before = vault.previousFriendly {
                StickerItem(title: "Вернуться к прежней папке", edge: Look.noteEdge) {
                    close()
                    vault.goBack()
                }
                // Куда именно вернёмся — видно до нажатия, а не после.
                Text(before)
                    .font(Look.sans(11.5))
                    .foregroundStyle(Look.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, -4)
                    .padding(.bottom, 9)
            }
            StickerItem(title: "Чего ещё нет", note: undone ? "▾" : "▸",
                        edge: Look.noteEdge) {
                undone.toggle()
            }
            if undone { missing }
            // Погода в записях — от Погоды Apple; её условия положено
            // показывать там, где приложение показывает погоду (P208).
            StickerItem(title: "Погода — Погода Apple", note: "условия",
                        edge: Look.noteEdge) {
                openURL(WeatherNote.legal)
            }
            version
        }
        .confirmationDialog("Где хранить записи", isPresented: $choosingPlace,
                            titleVisibility: .visible) {
            if !vault.onPhone {
                Button("На этом iPhone") {
                    close()
                    vault.usePhone()
                    store.load()
                    archive.reload()
                    shell.screen = .today
                }
            }
            Button("В свою папку — iCloud Drive и другие…") {
                close()
                shell.picking = true
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("На iPhone — папка «Chronotheca» в «Файлах» → «На iPhone». Удалите приложение — "
                 + "iPhone удалит и её, поэтому для надёжности лучше своя папка в iCloud Drive: "
                 + "там записи переживут и приложение, и телефон. Записи, что уже есть, "
                 + "приложение предложит перенести.")
        }
    }

    @State private var undone = false
    @State private var choosingPlace = false
    @EnvironmentObject private var store: DayStore

    @EnvironmentObject private var archive: Archive
    @Environment(\.openURL) private var openURL

    /// Где лежат записи и сколько их — словами «Файлов», а полный путь
    /// мелко под ним. Число файлов отвечает на главный вопрос «мои записи
    /// на месте?», даже когда iCloud их ещё не отдал (решения P189, P190).
    private var place: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ЗАПИСИ ЛЕЖАТ ЗДЕСЬ")
                .font(Look.sans(9))
                .tracking(0.6)
                .foregroundStyle(Look.inkFaint)
            Text(vault.friendlyPath)
                .font(Look.sans(14, weight: .medium))
                .foregroundStyle(Look.ink)
                .lineLimit(3)
            Text(count)
                .font(Look.sans(11.5))
                .foregroundStyle(Look.inkSoft)
            if let parent = vault.nestedIn {
                Text("Похоже, это папка внутри архива, а не сам архив. Прежние "
                     + "записи, скорее всего, лежат уровнем выше — в «\(parent)». "
                     + "Нажмите «Писать в другое место» и выберите саму «\(parent)»: "
                     + "приложение узнает архив и предложит перенести туда то, "
                     + "что записано здесь.")
                    .font(Look.sans(11.5))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            Text(vault.displayPath)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Look.inkFaint)
                .textSelection(.enabled)
                .lineLimit(4)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var count: String {
        var out = "Файлов с записями: \(archive.files)"
        if archive.awayFiles > 0 {
            out += " · ещё в iCloud: \(archive.awayFiles)"
            out += archive.fetching ? ", скачиваются" : ""
        }
        return out
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Видео и снимок с камеры")
            Text("Напоминания на телефон")
            Text("Замок и ночной вид")
        }
        .font(Look.sans(12))
        .foregroundStyle(Look.inkFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var version: some View {
        HStack {
            Text("Версия")
                .font(Look.sans(12))
                .foregroundStyle(Look.inkFaint)
            Spacer()
            Text(Build.label)
                .font(Look.mono(12))
                .foregroundStyle(Look.inkSoft)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(Look.noteEdge).frame(height: 1)
        }
    }

    private func close() {
        withAnimation(.tuck) { shell.showingSettings = false }
    }
}

/// Номер сборки на виду.
///
/// Без него нельзя ответить на вопрос «а это новая версия или старая?» —
/// ни мне по журналам сборки, ни человеку с телефоном в руках.
enum Build {
    static var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Ролик времени

/// Время дела и время напоминания крутятся одним и тем же роликом.
/// Выход «Без времени» — это отказ, а не пустое значение: дело останется
/// без часа, и это нормальное состояние дела.
struct RollerSheet: View {

    private static let aboutBell = """
        Напоминания ещё не приходят — время записывается в файл, \
        но телефон о нём пока не сообщает.
        """

    let roller: Shell.Roller

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @State private var picked = Date()
    /// Готовый ответ, нажатый последним.
    @State private var chosen: String?

    private var isBell: Bool { roller.kind == .bell }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TimeWheel(time: $picked)
                if isBell {
                    presets
                    Text(Self.aboutBell)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .navigationTitle(isBell ? "Напоминание" : "Время дела")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // «Отмена» не просто закрывает, а снимает назначенное: дело
                // остаётся без часа, напоминание — снятым. Иначе отказаться
                // от времени было бы нечем (решения P49, P150).
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { apply(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { apply(Clock.text(picked)) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let i = store.index(of: roller.id) else { return }
                let row = store.planRows[i]
                let current = isBell ? row.bell : row.time
                set(Clock.date(current) ?? start(row))
            }
        }
        .presentationDetents([.height(isBell ? 392 : 290)])
    }

    /// Поставить ролик. Всегда через подгонку к шагу: ролик с шагом в пять
    /// минут всё равно округлит, и лучше, чтобы приложение и ролик считали
    /// одинаково, чем расходились молча.
    private func set(_ date: Date) { picked = Clock.snap(date) }

    /// Время дела, если оно назначено: от него считаются напоминания.
    private var eventTime: Date? {
        guard let i = store.index(of: roller.id) else { return nil }
        return Clock.date(store.planRows[i].time)
    }

    /// Готовые ответы для напоминания.
    ///
    /// Почти все напоминания ставят на одно из трёх: незадолго до дела,
    /// за час до дела или с утра. Крутить ради этого барабан — лишняя
    /// работа на каждом деле (решение P152).
    ///
    /// Готовый ответ не закрывает ролик, а ставит на нужное место барабан:
    /// человек видит, что выбралось, и может поправить. Одно касание мимо
    /// не должно молча назначать напоминание.
    private var presets: some View {
        HStack(spacing: 8) {
            preset("за 10 минут", eventTime?.addingTimeInterval(-600))
            preset("за 1 час", eventTime?.addingTimeInterval(-3600))
            preset("в 9 утра", Clock.at(9))
        }
    }

    /// Готовый ответ. Бледный и неотзывчивый, когда считать не от чего:
    /// у дела ещё нет времени, и «за час до» не от чего отсчитать.
    ///
    /// Первое нажатие ставит ролик на это время — можно подкрутить.
    /// Второе нажатие на тот же ответ, пока ролик стоит на нём, значит
    /// «вот это и надо»: время записывается, и ролик закрывается сам
    /// (решение P194).
    private func preset(_ title: String, _ value: Date?) -> some View {
        let ready = value != nil
        return Button {
            guard let value else { return }
            if chosen == title, picked == Clock.snap(value) {
                apply(Clock.text(picked))
                return
            }
            chosen = title
            set(value)
        } label: {
            Text(title)
                .font(Look.sans(13))
                .foregroundStyle(ready ? Look.accent : Look.inkFaint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Look.chrome, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    ready ? Look.accent.opacity(0.35) : Look.rule))
        }
        .buttonStyle(.plain)
        // Не .disabled: система рисует выключенную кнопку бледнее поверх
        // заданного цвета, и бледность сложилась бы дважды (P141).
        .allowsHitTesting(ready)
    }

    /// Откуда начинает ролик, когда время ещё не назначено.
    ///
    /// Для дела — ближайший следующий круглый час: в 22:49 предлагается
    /// 23:00. Ставить ролик на «сейчас» незачем — дело не назначают на
    /// минуту, которая уже идёт, и человеку пришлось бы крутить вперёд от
    /// бесполезного места.
    ///
    /// Для напоминания — за час до дела: напоминают заранее, иначе незачем
    /// напоминать. А если у дела времени ещё нет, отсчитывать не от чего —
    /// ролик встаёт на полночь (решение P149).
    private func start(_ row: PlanRow) -> Date {
        guard isBell else { return Clock.nextHour() }
        guard let time = Clock.date(row.time) else { return Clock.midnight() }
        return time.addingTimeInterval(-3600)
    }

    private func apply(_ value: String?) {
        if let i = store.index(of: roller.id) {
            if isBell { store.planRows[i].bell = value } else { store.planRows[i].time = value }
            store.save()
        }
        shell.roller = nil
    }
}

enum Clock {
    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }

    static func text(_ date: Date) -> String { formatter.string(from: date) }

    static func date(_ text: String?) -> Date? {
        guard let text, let t = formatter.date(from: text) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0,
                                     second: 0, of: Date())
    }

    /// Ближайший следующий круглый час. Ровно в час — он сам: в 23:00
    /// предлагать полночь было бы странно.
    ///
    /// После 23:00 круглый час приходится на следующие сутки, но ролик
    /// показывает только часы и минуты — для него это просто 00:00.
    static func nextHour(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: now)
        let minute = c.minute ?? 0
        let hour = (minute == 0 ? (c.hour ?? 0) : (c.hour ?? 0) + 1) % 24
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }

    /// Полночь — для ролика, которому не от чего отсчитывать.
    static func midnight(_ now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now)
    }

    /// Такой-то час ровно.
    static func at(_ hour: Int, _ now: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }

    /// Подогнать к шагу ролика: минуты вниз до кратных шагу.
    ///
    /// Вниз, а не к ближайшему: назначенное на 14:37 дело безопаснее
    /// сдвинуть на 14:35, чем на 14:40 — раньше можно, позже нельзя.
    static func snap(_ date: Date, step: Int = 5) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: date)
        let minute = ((c.minute ?? 0) / step) * step
        return cal.date(bySettingHour: c.hour ?? 0, minute: minute,
                        second: 0, of: date) ?? date
    }
}

// MARK: - Подробности

/// Шторка справа: адрес, дорога, стоимость, с кем.
///
/// Размеры прототипа: ширина 324 или 88 % экрана — что меньше; отступ 15
/// сверху и снизу, чтобы шторка не упиралась в края вкладки; скруглена
/// слева, справа уходит за край. Она не закрывает ни вкладки, ни нижние
/// кнопки — человек видит, где находится, и выходит касанием мимо.
struct DetailsDrawer: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @State private var keyboard: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.14)
                .contentShape(Rectangle())
                .onTapGesture { close() }
            panel
        }
        .transition(.move(edge: .trailing))
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect ?? .zero
            let screen = UIScreen.main.bounds.height
            // Нижняя безопасная полоса телефона уже учтена в отступах шторки:
            // не вычесть её — и между клавиатурой и шторкой остаётся пустое
            // поле шириной в палец.
            let safe = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
                .first ?? 0
            keyboard = max(0, screen - frame.origin.y - safe)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard = 0
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            if let i = index { body(at: i) }
        }
        .frame(maxWidth: 324)
        .background(Look.chrome)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))
        .overlay(SideTabBorder(radius: 12).stroke(Look.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 17, x: -8)
        .padding(.leading, 40)
        .padding(.top, 15)
        // Шторка поднимается над клавиатурой, а не прячет под ней строку,
        // которую человек как раз набирает.
        .padding(.bottom, max(15, keyboard - 16))
        .animation(.easeOut(duration: 0.22), value: keyboard)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("ПОДРОБНОСТИ")
                .font(Look.sans(12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Look.inkFaint)
                .padding(.top, 4)
            Spacer(minLength: 0)
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 4)
    }

    private var closeButton: some View {
        Button { close() } label: {
            Text("✕")
                .font(.system(size: 17))
                .foregroundStyle(Look.inkSoft)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
        }
        .accessibilityLabel("Закрыть")
    }

    @ViewBuilder private func body(at i: Int) -> some View {
        Text(store.planRows[i].text.isEmpty ? "Без названия" : store.planRows[i].text)
            .font(Look.sans(14.5))
            .foregroundStyle(Look.ink)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

        editor(at: i)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

        if !store.canEditPlan {
            Text(store.closedReason)
                .font(Look.sans(11.5))
                .foregroundStyle(Look.inkFaint)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    private func editor(at i: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if store.planRows[i].details.isEmpty {
                Text("Адрес, дорога, стоимость, с кем…")
                    .font(Look.sans(14.5))
                    .foregroundStyle(Look.inkFaint)
                    .padding(.horizontal, 11)
                    .padding(.top, 19)
                    .allowsHitTesting(false)
            }
            // Снимки в подробностях рисуются картинками, как в дневнике (P205).
            DiaryEditor(text: details(at: i), size: 14.5,
                        serif: false, stamped: false, resolve: store.photoURL)
                .padding(.horizontal, 6)
                .disabled(!store.canEditPlan)
        }
        .background(Look.planBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Look.rule))
    }

    private func details(at i: Int) -> Binding<String> {
        Binding(
            get: { store.planRows[i].details.joined(separator: "\n") },
            set: { text in
                store.planRows[i].details =
                    text.isEmpty ? [] : text.components(separatedBy: "\n")
            })
    }

    private var index: Int? { shell.drawer.flatMap(store.index(of:)) }

    private func close() {
        hideKeyboard()
        store.save()
        withAnimation(.easeOut(duration: 0.26)) { shell.drawer = nil }
    }
}

// MARK: - Файл на диске

struct FileSheet: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Папка").font(.caption).foregroundStyle(.secondary)
                        Text(vault.displayPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Divider()
                    Text(store.onDisk())
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Файл на диске")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { shell.showingFile = false }
                }
            }
        }
    }
}

// MARK: - Первый запуск

struct WelcomeView: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive

    private static let invitation = """
        Записи ложатся обычными файлами в папку «\(Vault.folderName)». Папка ваша: \
        приложение только пишет и читает, и её всегда видно в «Файлах».
        """

    var body: some View {
        ScrollView {
        VStack(spacing: 18) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Где хранить записи").font(.title2)

            Text(Self.invitation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Два пути (P223). Одним касанием — своя папка приложения на
            // телефоне. Через окно выбора — своя папка человека: в iCloud
            // Drive она переживёт и приложение, и телефон.
            Button {
                vault.usePhone()
                store.load()
                archive.reload()
            } label: {
                Text("Хранить на этом iPhone").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Одно касание. Папка «\(Vault.folderName)» будет видна в «Файлах» → «На iPhone». "
                 + "Удалите приложение — iPhone удалит и её.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                shell.picking = true
            } label: {
                Text("Выбрать свою папку…").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            // Первые шаги по порядку. Системное окно выбора папки незнакомо
            // многим, и без подсказки человек не знает, куда в нём нажать
            // (решение P190).
            VStack(alignment: .leading, spacing: 8) {
                step(1, "В окне выберите «iCloud Drive» — записи будут и на Маке и "
                        + "переживут удаление приложения.")
                step(2, "Нажмите «Открыть» вверху справа. Приложение предложит "
                        + "завести там папку «\(Vault.folderName)».")
                step(3, "Уже есть папка с записями — зайдите в неё и нажмите "
                        + "«Открыть»: приложение узнает свой архив.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let problem = vault.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").monospacedDigit().fontWeight(.semibold)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
