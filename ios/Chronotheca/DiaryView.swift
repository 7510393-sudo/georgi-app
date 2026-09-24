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
            inCloud: store.away.contains(.diary),
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
    /// Файл дневника лежит в iCloud и ещё не скачан: страница пуста не
    /// потому, что день пуст (решение P182).
    var inCloud = false
    /// Возвращает `true`, если приложение поставило отметку времени: тогда
    /// курсор переезжает за неё.
    var onFocusText: () -> Bool = { false }

    private enum Field: Hashable { case title, answer(String) }
    @FocusState private var focused: Field?

    /// Поднимается ровно на один оборот — когда отметка времени поставлена.
    @State private var caretToEnd = false

    /// Поднимается по «Вводу» в заголовке: ввод переходит к тексту записи.
    @State private var toText = false

    /// Насколько клавиатура закрывает страницу снизу.
    @State private var keyboard: CGFloat = 0

    /// Где проходит строчка письма в строках «Как прошло?».
    ///
    /// Задана числом, одно и то же для названия дела и для ответа: пустое
    /// поле ввода и готовый текст сами по себе садятся на разную высоту, и
    /// ответ прыгал бы от первой буквы (то же, что в плане, — P171).
    @ScaledMetric(relativeTo: .body) private var askBaseline: CGFloat = 14

    private let size = DiaryView.size

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if inCloud {
                    Text("Запись этого дня ещё загружается из iCloud. Как только придёт, она появится здесь.")
                        .font(Look.serif(size - 1))
                        .foregroundStyle(Look.inkFaint)
                        .padding(.bottom, 12)
                }
                if !asked.isEmpty { askBlock }
                titleField
                textField
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            // Место под клавиатуру: без него страницу некуда поднять, и
            // последние строки записи остаются под ней (решение P175).
            .padding(.bottom, 20 + keyboard)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Look.diaryBg)
        .keyboardHeight($keyboard)
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
                .alignmentGuide(.firstTextBaseline) { _ in askBaseline }

            if editable, let setAnswer {
                TextField("…", text: Binding(
                    get: { answer(task.text) },
                    set: { typed in
                        // Ответ — одна строка файла: «- Дело: ответ».
                        // Перевод строки разорвал бы её, и хвост осел бы
                        // в свободном тексте записи (решение P172).
                        guard typed.contains(where: \.isNewline) else {
                            return setAnswer(task.text, typed)
                        }
                        setAnswer(task.text, typed.filter { !$0.isNewline })
                        focused = nil
                    }),
                    axis: .vertical)
                    .font(Look.serif(size))
                    .foregroundStyle(Look.ink)
                    .focused($focused, equals: .answer(task.text))
                    .textFieldStyle(.plain)
                    .alignmentGuide(.firstTextBaseline) { _ in askBaseline }
            } else {
                Text(answer(task.text).isEmpty ? "…" : answer(task.text))
                    .font(Look.serif(size))
                    .foregroundStyle(answer(task.text).isEmpty ? Look.inkFaint : Look.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alignmentGuide(.firstTextBaseline) { _ in askBaseline }
            }
        }
        // Пустая строка стоит ровно в строку, а исписанная растёт вниз —
        // и дела, стоящие ниже, отодвигаются, освобождая место. Раньше
        // высота была задана намертво, и ответ уезжал за край строки,
        // не переносясь (решение P175).
        .frame(minHeight: size * 1.7, alignment: .leading)
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
                    onFocus: { if onFocusText() { caretToEnd = true } },
                    grows: true, minHeight: 320)
            .padding(.top, 16)
    }
}
