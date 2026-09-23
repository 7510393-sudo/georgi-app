import SwiftUI

/// Вкладка «Дневник»: как прошло, заголовок дня и свободный текст.
///
/// Набрана засечным шрифтом на тёплой бумаге — в отличие от плана. Это разные
/// занятия: план разглядывают, дневник читают.
struct DiaryView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    static let size: CGFloat = 15.5
    static let leading: CGFloat = size * 0.24

    var body: some View {
        DiaryPage(
            tasks: store.tasks,
            answer: { store.answers[$0] ?? "" },
            setAnswer: { store.answers[$0] = $1 },
            title: $store.diaryTitle,
            text: $store.diaryText,
            editable: store.canEditDiary,
            onFocusText: { store.stampIfNeeded() })
        .onChange(of: store.diaryTitle) { _, _ in store.scheduleSave() }
        .onChange(of: store.answers) { _, _ in store.scheduleSave() }
        .onChange(of: store.diaryText) { _, _ in
            store.touchDiary()
            store.scheduleSave()
        }
    }
}

/// Страница дневника.
///
/// Одна и та же и для открытого дня, и для соседних. Это не изящество, а
/// необходимость: стоит им разойтись хоть на строку — и при перелистывании
/// текст на открывающейся странице прыгает.
struct DiaryPage: View {

    let tasks: [PlanRow]
    let answer: (String) -> String
    var setAnswer: ((String, String) -> Void)?
    @Binding var title: String
    @Binding var text: String
    var editable = true
    /// Возвращает `true`, если приложение поставило отметку времени: тогда
    /// курсор переезжает за неё.
    var onFocusText: () -> Bool = { false }

    private enum Field: Hashable { case title, answer(String) }
    @FocusState private var focused: Field?

    /// Поднимается ровно на один оборот — когда отметка времени поставлена.
    @State private var caretToEnd = false

    /// Поднимается по «Вводу» в заголовке: ввод переходит к тексту записи.
    @State private var toText = false

    private let size = DiaryView.size

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !asked.isEmpty { askBlock }
                titleField
                textField
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Look.diaryBg)
    }

    private var asked: [PlanRow] {
        Array(tasks.filter { !$0.text.isEmpty }.prefix(3))
    }

    // MARK: - Как прошло

    /// Три первых дела, по строке на каждое (решение P30). Ответ пишется
    /// прямо в той же строке, за двоеточием, — строка не переносится и не
    /// переставляется, когда в неё ставят курсор.
    private var askBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Как прошло?")
                .font(Look.serif(size))
                .foregroundStyle(Look.inkFaint)
                .frame(height: size * 1.6, alignment: .leading)

            ForEach(asked, id: \.id) { task in
                askRow(task)
            }
        }
        .padding(.bottom, 12)
    }

    private func askRow(_ task: PlanRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(task.text + ":")
                .font(Look.serif(size))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if editable, let setAnswer {
                TextField("…", text: Binding(
                    get: { answer(task.text) },
                    set: { setAnswer(task.text, $0) }))
                    .font(Look.serif(size))
                    .foregroundStyle(Look.ink)
                    .focused($focused, equals: .answer(task.text))
                    .textFieldStyle(.plain)
            } else {
                Text(answer(task.text).isEmpty ? "…" : answer(task.text))
                    .font(Look.serif(size))
                    .foregroundStyle(answer(task.text).isEmpty ? Look.inkFaint : Look.ink)
                    .lineLimit(1)
            }
        }
        // Строка одной высоты всегда: и пустая, и заполненная, и с курсором.
        .frame(height: size * 1.7, alignment: .leading)
    }

    // MARK: - Заголовок

    private var titleField: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if title.isEmpty {
                    Text("Заголовок дня")
                        .font(Look.serif(16.5))
                        .foregroundStyle(Look.inkFaint)
                        .allowsHitTesting(false)
                }
                if editable {
                    TextField("", text: $title)
                        .font(Look.serif(16.5, weight: .semibold))
                        .foregroundStyle(Look.ink)
                        .focused($focused, equals: .title)
                        .submitLabel(.next)
                        // «Ввод» уводит из заголовка в текст записи, а не
                        // просто убирает клавиатуру (решение P40).
                        .onSubmit {
                            focused = nil
                            toText = true
                        }
                } else {
                    Text(title)
                        .font(Look.serif(16.5, weight: .semibold))
                        .foregroundStyle(Look.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Заголовок — подпись к дню, а не вывеска: место на странице
            // принадлежит записи (решение P162).
            .frame(height: 23, alignment: .leading)
            .padding(.bottom, 5)

            Rectangle().fill(Look.rule).frame(height: 1)
        }
        .padding(.top, 4)
    }

    // MARK: - Текст

    /// Поле записи — одно и то же и на открытой странице, и на соседних.
    /// Соседняя лишь не правится. Иначе рядом стоят два разных способа
    /// набрать текст, и строки на повороте расходятся (P114).
    private var textField: some View {
        DiaryEditor(text: $text, size: size, serif: true, stamped: true,
                    editable: editable, caretToEnd: $caretToEnd,
                    startEditing: $toText,
                    onFocus: { if onFocusText() { caretToEnd = true } })
            .frame(minHeight: 320)
            .padding(.top, 16)
    }
}
