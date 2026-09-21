import SwiftUI

/// Вкладка «План»: дела на день.
struct PlanView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @FocusState private var focused: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if store.editing { banner }
            head
            if store.tasks.isEmpty { empty } else { list }
        }
        // Прошедший день выцветает целиком — и сделанное, и несделанное.
        .opacity(store.isPast && !store.editing ? 0.55 : 1)
    }

    // MARK: - Полоски сверху

    private var banner: some View {
        HStack {
            Text("Режим изменений: правка текста, порядок, удаление.")
                .font(.caption)
            Spacer()
            Button("Выйти") { store.editing = false }
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.14))
    }

    private var head: some View {
        HStack {
            Text(store.isPast ? "день закрыт" : "дела на день")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                guard let id = store.addTask() else {
                    return shell.say(store.closedReason)
                }
                // Курсор ставится следующим ходом: строки, в которую его
                // ставят, в этот миг ещё нет на экране.
                DispatchQueue.main.async { focused = id }
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
            }
            .accessibilityLabel("Новое дело")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("На этот день ничего не запланировано.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !store.isPast {
                Text("Нажмите «+», чтобы вписать дело.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach($store.planRows) { row in
                    if row.wrappedValue.isTask {
                        taskRow(row, number: number(of: row.wrappedValue.id))
                        Divider().padding(.leading, 52).opacity(0.35)
                    } else if !(row.wrappedValue.verbatim ?? "")
                                .trimmingCharacters(in: .whitespaces).isEmpty {
                        // Чужая строка в нашем файле: показываем как есть и не трогаем.
                        Text(row.wrappedValue.verbatim ?? "")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 18)
                    }
                }
                stat
            }
        }
    }

    private func number(of id: UUID) -> Int {
        (store.tasks.firstIndex { $0.id == id } ?? 0) + 1
    }

    private var stat: some View {
        Text("Запланировано \(store.tasks.count) · сделано \(store.doneCount)")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }

    // MARK: - Строка дела

    private func taskRow(_ row: Binding<PlanRow>, number: Int) -> some View {
        let id = row.wrappedValue.id
        let editable = store.canEditPlan

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Button {
                        guard editable else { return shell.say(store.closedReason) }
                        shell.roller = .init(id: id, kind: .time)
                    } label: {
                        Text(row.wrappedValue.time ?? "--:--")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(row.wrappedValue.time == nil
                                             ? AnyShapeStyle(.quaternary)
                                             : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)

                    Button {
                        guard editable else { return shell.say(store.closedReason) }
                        shell.roller = .init(id: id, kind: .bell)
                    } label: {
                        Image(systemName: row.wrappedValue.bell == nil ? "bell" : "bell.fill")
                            .font(.caption)
                            .foregroundStyle(row.wrappedValue.bell == nil
                                             ? AnyShapeStyle(.quaternary)
                                             : AnyShapeStyle(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.wrappedValue.bell.map { "Напомнить в \($0)" }
                                        ?? "Напоминание не назначено")

                    if store.editing || focused == id {
                        TextField("Дело", text: row.text, axis: .vertical)
                            .focused($focused, equals: id)
                    } else {
                        Text(row.wrappedValue.text.isEmpty ? "Дело" : row.wrappedValue.text)
                            .foregroundStyle(row.wrappedValue.text.isEmpty
                                             ? AnyShapeStyle(.tertiary)
                                             : AnyShapeStyle(.primary))
                            .strikethrough(false)
                    }
                }

                ForEach(Array(row.wrappedValue.details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if store.editing {
                HStack(spacing: 10) {
                    Button { store.move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel("Выше")
                    Button { store.move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Ниже")
                    Button { store.delete(id) } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Удалить")
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                focused = nil
                shell.drawer = id
            } label: {
                Image(systemName: row.wrappedValue.details.isEmpty
                      ? "chevron.right" : "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(row.wrappedValue.details.isEmpty
                                     ? AnyShapeStyle(.quaternary)
                                     : AnyShapeStyle(Color.accentColor))
                    .padding(.leading, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Подробности")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        // Сделанное затеняется, а не отмечается галочкой (решения P14, P15).
        .opacity(row.wrappedValue.done ? 0.42 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !store.editing, focused != id else { return }
            guard store.canEditPlan else {
                return shell.say("День закрыт. Отметить задним числом — через режим изменений.")
            }
            row.wrappedValue.done.toggle()
            store.save()
        }
    }
}
