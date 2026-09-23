import SwiftUI

// MARK: - Меню страницы

/// Три точки: жёлтая бумажка, приклеенная к верхнему правому углу.
struct MenuSticker: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    var body: some View {
        Sticker(side: .trailing, title: "Меню страницы", close: close) {
            StickerItem(title: "Режим изменений",
                        note: store.editing ? "включён" : "выключен",
                        active: store.editing) {
                store.editing.toggle()
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

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { shell.showingMenu = false }
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
            StickerItem(title: "Писать в другое место", edge: Look.noteEdge) {
                close()
                shell.picking = true
            }
            if vault.previousPath != nil {
                StickerItem(title: "Вернуться к прежней папке", edge: Look.noteEdge) {
                    close()
                    vault.goBack()
                }
            }
            StickerItem(title: "Чего ещё нет", note: undone ? "▾" : "▸",
                        edge: Look.noteEdge) {
                undone.toggle()
            }
            if undone { missing }
            version
        }
    }

    @State private var undone = false

    private var place: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ЗАПИСИ ЛЕЖАТ ЗДЕСЬ")
                .font(Look.sans(9))
                .tracking(0.6)
                .foregroundStyle(Look.inkFaint)
            Text(vault.displayPath)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Look.inkSoft)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Вложения: фото, аудио, файлы, геоточка")
            Text("Перенос записей при смене места")
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
        withAnimation(.easeOut(duration: 0.2)) { shell.showingSettings = false }
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

// MARK: - Барабан времени

/// Время дела и время напоминания крутятся одним и тем же барабаном.
///
/// Барабан не выезжает снизу отдельной шторкой, а встаёт на то место, где
/// стоят цифры: его выбранная строка ложится ровно на клетку, по которой
/// нажали, — цифра как будто вырастает в барабан там, где была. Страница
/// вокруг притеняется, но остаётся видна: это правка одной клетки, а не
/// отдельный экран (решение P173).
///
/// Выход «Убрать» — это отказ, а не пустое значение: дело останется без
/// часа, и это нормальное состояние дела (P49, P150).
struct RollerCard: View {

    private static let aboutBell = """
        Время запишется в файл, но телефон о нём пока не напомнит.
        """

    /// Высота барабана и отступ над ним. По ним считается, куда встать:
    /// выбранная строка барабана — ровно его середина.
    private static let wheel: CGFloat = 200
    private static let padTop: CGFloat = 10

    let roller: Shell.Roller

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @State private var picked = Date()
    @State private var shown = false
    @State private var keyboard: CGFloat = 0

    private var isBell: Bool { roller.kind == .bell }

    var body: some View {
        GeometryReader { page in
            let box = place(on: page.size)
            ZStack(alignment: .topLeading) {
                // Касание мимо — согласие, а не отказ: барабан всё время
                // на виду, и человек уходит от него с тем, что видел.
                Color.black.opacity(shown ? 0.16 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { apply(Clock.text(picked)) }
                card
                    .frame(width: box.width, height: box.height)
                    .scaleEffect(shown ? 1 : 0.94, anchor: .topLeading)
                    .opacity(shown ? 1 : 0)
                    .offset(x: box.minX, y: box.minY)
            }
        }
        .keyboardHeight($keyboard)
        .onAppear {
            if let i = store.index(of: roller.id) {
                let row = store.planRows[i]
                set(Clock.date(isBell ? row.bell : row.time) ?? start(row))
            }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { shown = true }
        }
    }

    // MARK: - Где встать

    /// Место карточки на странице.
    ///
    /// По высоте — так, чтобы середина барабана легла на клетку. По
    /// ширине — от левого края клетки, чтобы цифры барабана оказались над
    /// цифрами дела. У краёв страницы и над клавиатурой карточка
    /// придвигается внутрь: лучше сдвинуться, чем уехать за край.
    private func place(on page: CGSize) -> CGRect {
        let wide = min(isBell ? 330 : 300, page.width - 24)
        let tall = Self.padTop + Self.wheel + (isBell ? 78 : 0) + 44
        // Ниже этой черты карточку не опускаем: под ней клавиатура.
        let низ = max(8, page.height - keyboard - tall - 8)

        guard roller.at != .zero else {
            return CGRect(x: (page.width - wide) / 2,
                          y: min(max(8, (page.height - tall) / 2), низ),
                          width: wide, height: tall)
        }
        let x = min(max(12, roller.at.minX - 18), max(12, page.width - wide - 12))
        let y = min(max(8, roller.at.midY - (Self.padTop + Self.wheel / 2)), низ)
        return CGRect(x: x, y: y, width: wide, height: tall)
    }

    // MARK: - Сама карточка

    private var card: some View {
        VStack(spacing: 6) {
            TimeWheel(time: $picked)
                .frame(height: Self.wheel)
            if isBell {
                presets
                Text(Self.aboutBell)
                    .font(.caption)
                    .foregroundStyle(Look.inkFaint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            strip
        }
        .padding(.top, Self.padTop)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .background(Look.planBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Look.rule))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    }

    /// Две надписи внизу: снять назначенное и согласиться.
    ///
    /// Прежде слева стояла «Отмена», но она не отменяла, а снимала время, —
    /// в шторке это ещё читалось, а у карточки, которая закрывается
    /// касанием мимо, слово начало бы врать (решение P173).
    private var strip: some View {
        HStack {
            Button("Убрать") { apply(nil) }
                .font(Look.sans(14))
                .foregroundStyle(Look.inkSoft)
            Spacer()
            Button("Готово") { apply(Clock.text(picked)) }
                .font(Look.sans(14, weight: .semibold))
                .foregroundStyle(Look.accent)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .frame(height: 30)
    }

    /// Готовые ответы для напоминания.
    ///
    /// Почти все напоминания ставят на одно из трёх: незадолго до дела,
    /// за час до дела или с утра. Крутить ради этого барабан — лишняя
    /// работа на каждом деле (решение P152).
    ///
    /// Готовый ответ не закрывает барабан, а ставит его на нужное место:
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
    private func preset(_ title: String, _ value: Date?) -> some View {
        let ready = value != nil
        return Button {
            if let value { set(value) }
        } label: {
            Text(title)
                .font(Look.sans(13))
                .foregroundStyle(ready ? Look.accent : Look.inkFaint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Look.chrome, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    ready ? Look.accent.opacity(0.35) : Look.rule))
        }
        .buttonStyle(.plain)
        // Не .disabled: система рисует выключенную кнопку бледнее поверх
        // заданного цвета, и бледность сложилась бы дважды (P141).
        .allowsHitTesting(ready)
    }

    // MARK: - Что показывать и что записать

    /// Поставить барабан. Всегда через подгонку к шагу: барабан с шагом в
    /// пять минут всё равно округлит, и лучше, чтобы приложение и барабан
    /// считали одинаково, чем расходились молча.
    private func set(_ date: Date) { picked = Clock.snap(date) }

    /// Время дела, если оно назначено: от него считаются напоминания.
    private var eventTime: Date? {
        guard let i = store.index(of: roller.id) else { return nil }
        return Clock.date(store.planRows[i].time)
    }

    /// Откуда начинает барабан, когда время ещё не назначено.
    ///
    /// Для дела — ближайший следующий круглый час: в 22:49 предлагается
    /// 23:00. Ставить барабан на «сейчас» незачем — дело не назначают на
    /// минуту, которая уже идёт, и человеку пришлось бы крутить вперёд от
    /// бесполезного места.
    ///
    /// Для напоминания — за час до дела: напоминают заранее, иначе незачем
    /// напоминать. А если у дела времени ещё нет, отсчитывать не от чего —
    /// барабан встаёт на полночь (решение P149).
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
        withAnimation(.easeOut(duration: 0.16)) { shell.roller = nil }
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
            DiaryEditor(text: details(at: i), size: 14.5,
                        serif: false, stamped: false)
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

    private static let invitation = """
        Укажите место — приложение заведёт там свою папку «\(Vault.folderName)» \
        и сложит записи в неё обычными файлами. Папка ваша: приложение только \
        пишет и читает. Удалите приложение — записи останутся.
        """

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Где хранить записи").font(.title2)

            Text(Self.invitation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Выбрать место") { shell.picking = true }
                .buttonStyle(.borderedProminent)

            if let problem = vault.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}
