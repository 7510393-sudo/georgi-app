import SwiftUI
import UniformTypeIdentifiers

/// Экран «Сегодня»: две вкладки на одном дне.
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
    @State private var showingMenu = false

    /// Дело, чья шторка «Детали» открыта. Пусто — шторка закрыта.
    @State private var openDetails: UUID?
    /// Дело, которому назначают время.
    @State private var settingTime: UUID?
    @State private var pickedTime = Date()

    @State private var notice: String?
    @FocusState private var focused: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if vault.root == nil { welcome } else { day }
            }
            .navigationTitle(vault.root == nil ? "" : store.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vault.root != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingMenu = true } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Ещё")
                    }
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
        .sheet(isPresented: $showingMenu) { menuSheet }
        .sheet(item: Binding(get: { settingTime.map { Ident(id: $0) } },
                             set: { settingTime = $0?.id })) { item in
            timeSheet(for: item.id)
        }
        .alert("Папка переехала",
               isPresented: Binding(get: { vault.moved != nil },
                                    set: { if !$0 { vault.moved = nil } })) {
            Button("Понятно") { vault.moved = nil }
        } message: {
            Text("Вы её переименовали или передвинули. Приложение пошло за ней "
                 + "следом и пишет теперь сюда:\n\n" + (vault.moved ?? ""))
        }
        .overlay(alignment: .bottom) { toast }
    }

    private struct Ident: Identifiable { let id: UUID }

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
        ZStack(alignment: .trailing) {
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
            .contentShape(Rectangle())
            // Свайп листает дни, как в прототипе: горизонтальное движение
            // должно быть заметно длиннее вертикального, иначе это прокрутка.
            // Жест одновременный, а не обычный: иначе прокрутка списка и
            // текстовое поле забирают касание себе и лист не листается.
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { g in
                        guard openDetails == nil else { return }
                        let dx = g.translation.width, dy = g.translation.height
                        guard abs(dx) > 64, abs(dx) > abs(dy) * 1.6 else { return }
                        focused = nil
                        withAnimation(.easeOut(duration: 0.22)) {
                            store.move(by: dx < 0 ? 1 : -1)
                        }
                    }
            )

            if openDetails != nil { detailsDrawer }
        }
        .onChange(of: store.planRows) { _, _ in store.scheduleSave() }
        .onChange(of: store.diary) { _, _ in store.scheduleSave() }
        .onChange(of: tab) { _, _ in store.save() }
    }

    // MARK: - План

    private var planView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach($store.planRows) { $row in
                    if row.isTask {
                        taskRow($row)
                    } else if !(row.verbatim ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(row.verbatim ?? "")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 20)
                    }
                }

                if store.canEditPlan {
                    Button {
                        let new = PlanRow.task("")
                        store.planRows.append(new)
                        // Курсор ставится следующим ходом: строки, в которую
                        // его ставят, в этот миг ещё нет на экране.
                        DispatchQueue.main.async { focused = new.id }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                            Text("Дело")
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                    }
                } else {
                    Text(store.closedReason)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 6)
        }
        // Прошедший день выцветает целиком — и сделанное, и несделанное.
        .opacity(store.isPast ? 0.55 : 1)
    }

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                guard store.canEditPlan else { return say(store.closedReason) }
                pickedTime = Self.date(from: row.wrappedValue.time) ?? Date()
                settingTime = row.wrappedValue.id
            } label: {
                Text(row.wrappedValue.time ?? "––:––")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(row.wrappedValue.time == nil ? .quaternary : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                TextField("Дело", text: row.text, axis: .vertical)
                    .focused($focused, equals: row.wrappedValue.id)
                    .disabled(!store.canEditPlan)
                ForEach(Array(row.wrappedValue.details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                openDetails = row.wrappedValue.id
            } label: {
                Image(systemName: row.wrappedValue.details.isEmpty
                      ? "ellipsis" : "text.alignleft")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Детали дела")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 20)
        // Сделанное затеняется, а не отмечается галочкой: долгое нажатие
        // вместо щелчка, чтобы нельзя было задеть случайно.
        .opacity(row.wrappedValue.done ? 0.4 : 1)
        .contentShape(Rectangle())
        .onLongPressGesture {
            guard store.canEditPlan else { return say(store.closedReason) }
            row.wrappedValue.done.toggle()
        }
    }

    // MARK: - Дневник

    private var diaryView: some View {
        Group {
            if store.canEditDiary {
                TextEditor(text: $store.diary)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Text(store.closedReason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Шторка «Детали»

    private var detailsDrawer: some View {
        let index = openDetails.flatMap { id in store.planRows.firstIndex { $0.id == id } }
        return HStack(spacing: 0) {
            Color.black.opacity(0.12)
                .onTapGesture { openDetails = nil }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Детали")
                        .font(.headline)
                    Spacer()
                    Button {
                        openDetails = nil
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Закрыть детали")
                }
                if let index {
                    Text(store.planRows[index].text.isEmpty
                         ? "Без названия" : store.planRows[index].text)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    TextEditor(text: Binding(
                        get: { store.planRows[index].details.joined(separator: "\n") },
                        set: { store.planRows[index].details =
                                $0.isEmpty ? [] : $0.components(separatedBy: "\n") }))
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .disabled(!store.canEditPlan)
                        .frame(maxHeight: .infinity)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 280)
            .background(Color(.systemBackground))
            .shadow(radius: 8)
        }
        .transition(.move(edge: .trailing))
    }

    // MARK: - Подвал

    private var footer: some View {
        HStack {
            Button { withAnimation { store.move(by: -1) } } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Предыдущий день")

            Spacer()

            Button("Файл на диске") { peeking = true }
                .font(.footnote)

            Spacer()

            Button { withAnimation { store.move(by: 1) } } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Следующий день")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Листки

    private func timeSheet(for id: UUID) -> some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $pickedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                Spacer()
            }
            .padding()
            .navigationTitle("Время")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Без времени") {
                        if let i = store.planRows.firstIndex(where: { $0.id == id }) {
                            store.planRows[i].time = nil
                        }
                        settingTime = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        if let i = store.planRows.firstIndex(where: { $0.id == id }) {
                            store.planRows[i].time = Self.text(from: pickedTime)
                        }
                        settingTime = nil
                    }
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    private var menuSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button("Где лежат записи") {
                        showingMenu = false
                        showingFolder = true
                    }
                    Button("Файл на диске") {
                        showingMenu = false
                        peeking = true
                    }
                }
                Section("Ещё не сделано") {
                    Text("Календарь: месяц, год, список").foregroundStyle(.tertiary)
                    Text("Поиск по записям").foregroundStyle(.tertiary)
                    Text("Лента и вложения").foregroundStyle(.tertiary)
                    Text("Напоминание о деле").foregroundStyle(.tertiary)
                    Text("Заголовок дня и «Как прошло?»").foregroundStyle(.tertiary)
                    Text("Режим изменений для закрытого дня").foregroundStyle(.tertiary)
                    Text("Ночной вид и настройки").foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Ещё")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { showingMenu = false }
                }
            }
        }
    }

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

    // MARK: - Сообщение

    private var toast: some View {
        Group {
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.bottom, 70)
                    .transition(.opacity)
            }
        }
    }

    private func say(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation { notice = nil }
        }
    }

    // MARK: - Время

    private static func date(from text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        guard let t = f.date(from: text) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(bySettingHour: c.hour ?? 0,
                                     minute: c.minute ?? 0, second: 0, of: Date())
    }

    private static func text(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
