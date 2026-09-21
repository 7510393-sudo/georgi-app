import SwiftUI

/// Вкладка «План»: дела на день.
///
/// Размеры взяты из прототипа: номер и время моноширинные и крупнее текста
/// дела — по ним глаз бежит вниз по столбцу, не читая названий.
struct PlanView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    /// Строка, в которой сейчас правят текст.
    ///
    /// Отдельно от фокуса клавиатуры, и это не мелочь: если показывать поле
    /// ввода только у строки, которая уже в фокусе, то в фокус не попасть —
    /// поля ещё нет. Клавиатура не открывалась именно из-за этого.
    @State private var typingIn: UUID?
    @FocusState private var focused: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if store.editing { banner }
            head
            if store.tasks.isEmpty { empty } else { list }
        }
        .onChange(of: focused) { _, now in
            if now == nil { typingIn = nil; store.save() }
        }
        .onChange(of: store.date) { _, _ in typingIn = nil; focused = nil }
        // Прошедший день выцветает целиком — и сделанное, и несделанное.
        .opacity(store.isPast && !store.editing ? 0.58 : 1)
    }

    // MARK: - Полоски сверху

    private var banner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Режим изменений: правка текста, порядок, удаление.")
                .font(Look.sans(12.5))
            Spacer(minLength: 0)
            Button("Выйти") { store.editing = false }
                .font(Look.sans(12.5))
                .underline()
        }
        .foregroundStyle(Look.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Look.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var head: some View {
        HStack {
            Text(store.isPast ? "день закрыт" : "дела на день")
                .font(Look.mono(11))
                .tracking(0.45)
                .foregroundStyle(Look.inkFaint)
            Spacer()
            Button {
                guard let id = store.addTask() else {
                    return shell.say(store.closedReason)
                }
                typingIn = id
                // Курсор ставится следующим ходом: поля, в которое его
                // ставят, в этот миг ещё нет на экране.
                DispatchQueue.main.async { focused = id }
            } label: {
                Text("+")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Look.accent)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(Look.rule))
            }
            .opacity(store.canEditPlan ? 1 : 0.3)
            .accessibilityLabel("Новое дело")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Spacer()
            Text("На этот день ничего не запланировано.")
            if !store.isPast { Text("Нажмите «+», чтобы вписать дело.") }
            Spacer()
        }
        .font(Look.sans(14))
        .lineSpacing(5)
        .foregroundStyle(Look.inkFaint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach($store.planRows) { row in
                    if row.wrappedValue.isTask {
                        taskRow(row)
                        Rectangle().fill(Look.ruleSoft).frame(height: 1)
                    } else if !(row.wrappedValue.verbatim ?? "")
                                .trimmingCharacters(in: .whitespaces).isEmpty {
                        // Чужая строка в нашем файле: показываем как есть и не трогаем.
                        Text(row.wrappedValue.verbatim ?? "")
                            .font(Look.sans(14))
                            .foregroundStyle(Look.inkFaint)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 14)
                    }
                }
                stat
                // Пустое место под списком: касание по нему убирает клавиатуру.
                Color.clear
                    .frame(minHeight: 120)
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var stat: some View {
        Text("Запланировано \(store.tasks.count) · сделано \(store.doneCount)")
            .font(Look.mono(11.5))
            .tracking(0.35)
            .foregroundStyle(Look.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 20)
    }

    // MARK: - Строка дела

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        let id = row.wrappedValue.id
        let task = row.wrappedValue
        let faded = task.done || (store.isPast && !store.editing)

        return HStack(alignment: .top, spacing: 8) {
            Text("\(number(of: id))")
                .font(Look.mono(18))
                .foregroundStyle(Look.inkFaint)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Button {
                        guard store.canEditPlan else { return shell.say(store.closedReason) }
                        shell.roller = .init(id: id, kind: .time)
                    } label: {
                        Text(task.time ?? "--:--")
                            .font(Look.mono(18.5))
                            .tracking(task.time == nil ? 0.7 : 0)
                            .foregroundStyle(faded ? Look.inkFaint : Look.inkSoft)
                            .opacity(task.time == nil ? 0.6 : 1)
                            .overlay(alignment: .bottom) {
                                if store.canEditPlan {
                                    Line().stroke(Look.inkFaint,
                                                  style: StrokeStyle(lineWidth: 1, dash: [1.5, 2]))
                                        .frame(height: 1)
                                        .offset(y: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 7)

                    Button {
                        guard store.canEditPlan else { return shell.say(store.closedReason) }
                        shell.roller = .init(id: id, kind: .bell)
                    } label: {
                        Image(systemName: task.bell == nil ? "bell" : "bell.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(task.bell == nil
                                             ? Look.inkFaint : Ru.dayColor(store.date))
                            .opacity(task.bell == nil ? (faded ? 0.3 : 0.6) : 1)
                            // Площадка под палец: значок маленький, попадать
                            // в него надо большим пальцем на ходу.
                            .frame(width: 40, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 2)
                    .accessibilityLabel(task.bell.map { "Напомнить в \($0)" }
                                        ?? "Напоминание не назначено")

                    if typingIn == id || store.editing {
                        TextField("", text: row.text, axis: .vertical)
                            .font(Look.sans(15))
                            .focused($focused, equals: id)
                            .submitLabel(.done)
                    } else {
                        Text(task.text.isEmpty ? "Без названия" : task.text)
                            .font(Look.sans(15))
                            .lineSpacing(3)
                            .foregroundStyle(faded || task.text.isEmpty
                                             ? Look.inkFaint : Look.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            // Касание по самому тексту ставит в него курсор:
                            // написанное дело надо уметь поправить, не заходя
                            // в режим изменений. Отметить сделанным — касанием
                            // по остальной строке.
                            .onTapGesture {
                                guard store.canEditPlan else {
                                    return shell.say(store.closedReason)
                                }
                                typingIn = id
                                DispatchQueue.main.async { focused = id }
                            }
                    }
                }

                ForEach(Array(task.details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(Look.sans(13))
                        .foregroundStyle(Look.inkFaint)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if store.editing {
                VStack(spacing: 3) {
                    Button { store.move(id, by: -1) } label: { Image(systemName: "chevron.up") }
                        .accessibilityLabel("Выше")
                    Button { store.move(id, by: 1) } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Ниже")
                    Button { store.delete(id) } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Удалить")
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(Look.inkFaint)
                .padding(.trailing, 2)
            }

            detailTab(id: id, filled: !task.details.isEmpty)
        }
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(store.editing
                    ? LinearGradient(colors: [.clear, Look.ruleSoft],
                                     startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [.clear, .clear],
                                     startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
        .onTapGesture {
            if task.text.isEmpty, store.canEditPlan {
                typingIn = id
                DispatchQueue.main.async { focused = id }
                return
            }
            guard !store.editing, typingIn != id else { return }
            guard store.canEditPlan else {
                return shell.say("День закрыт. Отметить задним числом — через режим изменений.")
            }
            row.wrappedValue.done.toggle()
            store.save()
        }
    }

    /// Закладка «Детали» — выглядывает из-за правого края строки, как в прототипе.
    private func detailTab(id: UUID, filled: Bool) -> some View {
        Button {
            focused = nil
            withAnimation(.easeOut(duration: 0.2)) { shell.drawer = id }
        } label: {
            Text("›")
                .font(.system(size: 13))
                .foregroundStyle(filled ? Look.inkSoft : Look.inkFaint)
                .frame(width: 23)
                .frame(maxHeight: .infinity)
                .background(filled ? Look.rule : Look.chrome)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6,
                                                  bottomLeadingRadius: 6))
                .overlay(SideTabBorder(radius: 6)
                    .stroke(filled ? Look.inkFaint : Look.rule, lineWidth: 1))
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .opacity(store.editing ? 0.25 : 1)
        .accessibilityLabel("Подробности")
    }

    private func number(of id: UUID) -> Int {
        (store.tasks.firstIndex { $0.id == id } ?? 0) + 1
    }
}

/// Черта под временем: касанием по ней открывается ролик.
struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

extension View {
    /// Убрать клавиатуру. Нужна везде, где человек может закончить писать:
    /// поднявшуюся клавиатуру должно быть чем опустить, иначе экран заперт.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
