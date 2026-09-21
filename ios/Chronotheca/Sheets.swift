import SwiftUI

// MARK: - Меню страницы

/// Три точки: то, что относится к этому дню, а не ко всему приложению.
struct MenuSheet: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.editing.toggle()
                        shell.showingMenu = false
                    } label: {
                        HStack {
                            Text("Режим изменений")
                            Spacer()
                            Text(store.editing ? "включён" : "выключен")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("В режиме изменений можно править текст дела, менять порядок "
                         + "и удалять — в том числе в прошедшем дне. Обычные действия "
                         + "— отметить дело сделанным — доступны и без него, одним касанием.")
                }

                Section {
                    Button("Показать файл этого дня") {
                        shell.showingMenu = false
                        shell.showingFile = true
                    }
                    Button("Где лежат записи") {
                        shell.showingMenu = false
                        shell.showingFolder = true
                    }
                }

                Section("Ещё не сделано") {
                    Text("Вложения: фото, аудио, файлы, геоточка").foregroundStyle(.tertiary)
                    Text("Перенести дело на другой день").foregroundStyle(.tertiary)
                    Text("Поделиться днём").foregroundStyle(.tertiary)
                    Text("Удалить день").foregroundStyle(.tertiary)
                    Text("«…а помнишь?» — запись год назад").foregroundStyle(.tertiary)
                    Text("Перенос записей при смене места").foregroundStyle(.tertiary)
                    Text("Настройки и замок").foregroundStyle(.tertiary)
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
            .navigationTitle("Меню страницы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { shell.showingMenu = false }
                }
            }
        }
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
                    Text("Напоминания ещё не приходят — время записывается в файл, "
                         + "но телефон о нём пока не сообщает.")
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
/// Она не закрывает вкладки и нижние кнопки — человек видит, где находится,
/// и выходит оттуда касанием мимо, а не поиском крестика.
struct DetailsDrawer: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @FocusState private var typing: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.14)
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Подробности").font(.headline)
                    Spacer()
                    Button { close() } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Закрыть")
                }

                if let i = index {
                    Text(store.planRows[i].text.isEmpty
                         ? "Без названия" : store.planRows[i].text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    ZStack(alignment: .topLeading) {
                        if store.planRows[i].details.isEmpty {
                            Text("Адрес, дорога, стоимость, с кем…")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: Binding(
                            get: { store.planRows[i].details.joined(separator: "\n") },
                            set: { text in
                                store.planRows[i].details =
                                    text.isEmpty ? [] : text.components(separatedBy: "\n")
                            }))
                            .font(.callout)
                            .focused($typing)
                            .scrollContentBackground(.hidden)
                            .disabled(!store.canEditPlan)
                    }
                    .frame(maxHeight: .infinity)

                    if !store.canEditPlan {
                        Text(store.closedReason)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .frame(width: 286)
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.16), radius: 10, x: -2)
        }
        .transition(.move(edge: .trailing))
    }

    private var index: Int? { shell.drawer.flatMap(store.index(of:)) }

    private func close() {
        typing = false
        store.save()
        withAnimation(.easeOut(duration: 0.2)) { shell.drawer = nil }
    }
}

// MARK: - Папка

struct FolderSheet: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Записи лежат здесь").font(.headline)
                    Text(vault.displayPath)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                Text("Откройте «Файлы» и найдите эту папку — там всё, что вы написали, "
                     + "обычными файлами. Приложение можно удалить, записи останутся.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Button("Писать в другое место") {
                        shell.showingFolder = false
                        shell.picking = true
                    }
                    Text("Прежние записи останутся там, где лежат сейчас: приложение "
                         + "их не переносит и не удаляет. Чтобы взять их с собой, "
                         + "перенесите папку сами в «Файлах» и укажите новое место здесь.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Папка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { shell.showingFolder = false }
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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Где хранить записи").font(.title2)

            Text("Укажите место — приложение заведёт там свою папку «"
                 + Vault.folderName + "» и сложит записи в неё обычными файлами. "
                 + "Папка ваша: приложение только пишет и читает. "
                 + "Удалите приложение — записи останутся.")
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
