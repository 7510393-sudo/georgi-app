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
                paper: Look.note, edge: Look.noteEdge, close: close) {
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

    private var isBell: Bool { roller.kind == .bell }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker("", selection: $picked, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                if isBell {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(isBell ? "Без напоминания" : "Без времени") { apply(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { apply(Clock.text(picked)) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let i = store.index(of: roller.id) else { return }
                let current = isBell ? store.planRows[i].bell : store.planRows[i].time
                picked = Clock.date(current) ?? Date()
            }
        }
        .presentationDetents([.height(isBell ? 340 : 290)])
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
