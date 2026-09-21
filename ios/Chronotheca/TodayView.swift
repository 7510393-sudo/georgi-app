import SwiftUI
import UniformTypeIdentifiers

/// Экран «Сегодня»: две вкладки на одном дне.
///
/// Каркас. Здесь нет ни шторки, ни ленты, ни календаря — только то, что нужно,
/// чтобы проверить главное обещание: текст попадает в файл, файл лежит в папке
/// пользователя, и приложение читает его обратно.
struct TodayView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case plan = "План"
        case diary = "Дневник"
        var id: String { rawValue }
    }

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore

    @State private var tab: Tab = .plan
    @State private var picking = false
    @State private var peeking = false
    @State private var showingFolder = false
    @FocusState private var focused: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if vault.root == nil { welcome } else { day }
            }
            .navigationTitle(vault.root == nil ? "" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vault.root != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingFolder = true } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("Где лежат записи")
                    }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                vault.adopt(url)
                store.load()
            }
        }
        .sheet(isPresented: $peeking) { fileSheet }
        .sheet(isPresented: $showingFolder) { folderSheet }
        .alert("Папка переехала",
               isPresented: Binding(get: { vault.moved != nil },
                                    set: { if !$0 { vault.moved = nil } })) {
            Button("Понятно") { vault.moved = nil }
        } message: {
            Text("Вы её переименовали или передвинули. Приложение пошло за ней "
                 + "следом и пишет теперь сюда:\n\n" + (vault.moved ?? ""))
        }
    }

    // MARK: - Первый запуск

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Где хранить записи")
                .font(.title2)

            Text("Укажите место — приложение заведёт там свою папку «"
                 + Vault.folderName + "» и сложит записи в неё обычными файлами. "
                 + "Папка ваша: приложение только пишет и читает. "
                 + "Удалите приложение — записи останутся.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Выбрать место") { picking = true }
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

    // MARK: - День

    private var day: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if tab == .plan { planView } else { diaryView }

            footer
        }
        .onChange(of: store.planRows) { _, _ in store.save() }
        .onChange(of: store.diary) { _, _ in store.save() }
    }

    // MARK: - План

    private var planView: some View {
        List {
            ForEach($store.planRows) { $row in
                if row.isTask {
                    taskRow($row)
                } else if !(row.verbatim ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    // Строка, которую приложение не разбирает: показываем, но
                    // не трогаем. Человек должен видеть всё, что в его файле.
                    Text(row.verbatim ?? "")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .onDelete { store.planRows.remove(atOffsets: $0) }

            Button {
                let new = PlanRow.task("")
                store.planRows.append(new)
                focused = new.id
            } label: {
                Label("Дело", systemImage: "plus")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        // Прошедший день выцветает целиком — и сделанное, и несделанное.
        .opacity(store.isPast ? 0.55 : 1)
    }

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let time = row.wrappedValue.time {
                Text(time)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                TextField("", text: row.text, axis: .vertical)
                    .focused($focused, equals: row.wrappedValue.id)
                ForEach(row.wrappedValue.details, id: \.self) { detail in
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Сделанное затеняется, а не отмечается галочкой: долгое нажатие
        // вместо щелчка, чтобы нельзя было задеть случайно.
        .opacity(row.wrappedValue.done ? 0.4 : 1)
        .contentShape(Rectangle())
        .onLongPressGesture { row.wrappedValue.done.toggle() }
    }

    // MARK: - Дневник

    private var diaryView: some View {
        TextEditor(text: $store.diary)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack {
            Button { store.move(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Предыдущий день")

            Spacer()

            Button("Файл на диске") { peeking = true }
                .font(.footnote)

            Spacer()

            Button { store.move(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Следующий день")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Проверка обещания

    private var fileSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Папка")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    Button("Закрыть") { peeking = false }
                }
            }
        }
    }

    // MARK: - Где лежат записи

    private var folderSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Записи лежат здесь")
                        .font(.headline)
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
                        showingFolder = false
                        picking = true
                    }
                    Text("Прежние записи останутся там, где лежат сейчас: "
                         + "приложение их не переносит и не удаляет. "
                         + "Чтобы взять их с собой, перенесите папку сами в «Файлах» "
                         + "и укажите новое место здесь.")
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
                    Button("Закрыть") { showingFolder = false }
                }
            }
        }
    }

    // MARK: - Заголовок

    private var title: String {
        let days = Calendar.current.dateComponents([.day],
                                                   from: DayStore.today(),
                                                   to: store.date).day ?? 0
        switch days {
        case 0:  return "Сегодня"
        case -1: return "Вчера"
        case -2: return "Позавчера"
        case 1:  return "Завтра"
        case 2:  return "Послезавтра"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.setLocalizedDateFormatFromTemplate("d MMMM")
            return f.string(from: store.date)
        }
    }
}
