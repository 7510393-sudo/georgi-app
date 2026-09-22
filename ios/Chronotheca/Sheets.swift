import SwiftUI

// MARK: - Меню страницы

/// Три точки: листок, приклеенный к верхнему правому углу.
///
/// Не отдельная страница (решение: меню не должно уводить с экрана) и не
/// лист снизу: оно свешивается сверху справа, закрывая часть экрана, и
/// из-под него видно, где ты остался. Цвет бумажный, чтобы читалось как
/// приклеенная записка, а не как часть приложения.
struct MenuSticker: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { close() }
            sheet
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            head
            items
        }
        .frame(maxWidth: 262)
        .background(Look.sticker)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12))
        .overlay(StickerBorder(radius: 12).stroke(Look.stickerEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
        .padding(.leading, 60)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("МЕНЮ СТРАНИЦЫ")
                .font(Look.sans(11.5))
                .tracking(1.15)
                .foregroundStyle(Look.inkFaint)
                .padding(.top, 22)
                .padding(.leading, 14)
            Spacer(minLength: 0)
            Button { close() } label: {
                Text("✕")
                    .font(.system(size: 19))
                    .foregroundStyle(Look.inkSoft)
                    .frame(width: 44, height: 38)
            }
            .padding(.top, 12)
            .accessibilityLabel("Закрыть")
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Look.stickerEdge).frame(height: 1)
        }
    }

    @ViewBuilder private var items: some View {
        item("Режим изменений",
             note: store.editing ? "включён" : "выключен",
             active: store.editing) {
            store.editing.toggle()
            close()
        }
        item("Показать файл этого дня", note: "→") {
            close()
            shell.showingFile = true
        }
        item("Перенести дело на другой день", note: "→") {
            close()
            shell.say("Перенос дела ещё не сделан.")
        }
        item("Поделиться днём", note: "→") {
            close()
            shell.say("«Поделиться днём» ещё не сделано.")
        }
        item("Удалить день", note: "→") {
            close()
            shell.say("Удаление дня ещё не сделано.")
        }
    }

    private func item(_ title: String, note: String,
                      active: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Look.sans(14, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Look.accent : Look.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(note)
                    .font(Look.sans(11.5))
                    .foregroundStyle(Look.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(Look.stickerEdge).frame(height: 1)
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { shell.showingMenu = false }
    }
}

/// Обводка стикера: низ и левый бок, сверху и справа он приклеен к углу.
struct StickerBorder: Shape {
    let radius: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
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

struct SettingsSheet: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    /// Длинные объяснения — готовыми строками, а не склейкой в разметке:
    /// склеенные плюсами куски Swift разбирает мучительно долго и однажды
    /// отказался собирать приложение целиком.
    private static let aboutFolder = """
        Откройте «Файлы» и найдите эту папку — там всё, что вы написали, \
        обычными файлами. Приложение можно удалить, записи останутся.

        Прежние записи останутся там, где лежат сейчас: приложение их не \
        переносит и не удаляет. Чтобы взять их с собой, перенесите папку \
        сами в «Файлах» и укажите новое место здесь.
        """

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(vault.displayPath)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    Button("Писать в другое место") {
                        shell.showingSettings = false
                        shell.picking = true
                    }
                    if let previous = vault.previousPath {
                        VStack(alignment: .leading, spacing: 4) {
                            Button("Вернуться к прежней папке") { vault.goBack() }
                            Text(previous)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                } header: {
                    Text("Где лежат записи")
                } footer: {
                    Text(Self.aboutFolder)
                }

                Section("Ещё не сделано") {
                    Text("Вложения: фото, аудио, файлы, геоточка").foregroundStyle(.tertiary)
                    Text("Перенос записей при смене места").foregroundStyle(.tertiary)
                    Text("«…а помнишь?» — запись год назад").foregroundStyle(.tertiary)
                    Text("Напоминания на телефон").foregroundStyle(.tertiary)
                    Text("Замок и ночной вид").foregroundStyle(.tertiary)
                }

                Section("Сборка") {
                    HStack {
                        Text("Версия")
                        Spacer()
                        Text(Build.label)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { shell.showingSettings = false }
                }
            }
        }
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
