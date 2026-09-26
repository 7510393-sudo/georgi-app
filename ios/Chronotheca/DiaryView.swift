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
        VStack(spacing: 0) {
            if store.editing(.diary) { EditBanner(tab: .diary) }
            page
        }
    }

    private var page: some View {
        DiaryPage(
            tasks: store.tasks,
            answer: { store.answers[$0] ?? "" },
            setAnswer: { store.answers[$0] = $1 },
            title: $store.diaryTitle,
            text: $store.diaryText,
            editable: store.canEditDiary,
            inCloud: store.away.contains(.diary),
            weather: store.weather,
            photos: store.photos.map(store.photoURL),
            photoLinks: store.photos,
            resolve: store.photoURL,
            glowing: store.editing(.diary),
            onOpenPhoto: { shell.openedPhoto = .init(tab: .diary, index: $0) },
            onMovePhoto: { store.movePhoto(from: $0, to: $1, in: .diary) },
            // В режиме изменений запись переставляют, а не продолжают:
            // отметка времени тогда ни к чему. Иначе брошенный в текст
            // снимок заодно ставил бы в конец записи новое время.
            onFocusText: { store.editing(.diary) ? false : store.stampIfNeeded() },
            onOpenInline: { link in
                shell.openedPhoto = .init(tab: .diary, index: -1,
                                          url: store.photoURL(link), link: link)
            },
            onOpenPoint: {
                store.noteLeaving(fromToday: true)
                shell.showPoint($0)
            },
            onCaret: { store.diaryCaret = $0 },
            onEditing: { store.diaryTyping = $0 })
        .onChange(of: store.diaryTitle) { _, _ in store.scheduleSave() }
        .onChange(of: store.answers) { _, _ in store.scheduleSave() }
        .onChange(of: store.diaryText) { _, _ in
            store.touchDiary()
            store.settlePhotos()
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
    /// Погода, когда отмечено место: бледной строкой над страницей (P208).
    var weather: String?
    /// Фотографии дня. Стоят над текстом, под заголовком (P200).
    var photos: [URL?] = []
    /// Строки-ссылки тех же снимков: их несёт палец из полоски в текст.
    var photoLinks: [String] = []
    /// Где лежат снимки, стоящие посреди текста (P204).
    var resolve: ((String) -> URL?)?
    /// Режим изменений: превью подсвечены, их можно взять (P203).
    var glowing = false
    var onOpenPhoto: ((Int) -> Void)?
    var onMovePhoto: ((Int, Int) -> Void)?
    /// Возвращает `true`, если приложение поставило отметку времени: тогда
    /// курсор переезжает за неё.
    var onFocusText: () -> Bool = { false }
    /// Касание по снимку посреди текста (P216) и по точке (P213).
    var onOpenInline: ((String) -> Void)?
    var onOpenPoint: ((GeoPoint) -> Void)?
    var onCaret: ((Int) -> Void)?
    var onEditing: ((Bool) -> Void)?

    private enum Field: Hashable { case title }
    @FocusState private var focused: Field?

    /// Дело, на которое сейчас отвечают в «Как прошло?».
    @State private var askingAt: String?

    /// Поднимается ровно на один оборот — когда отметка времени поставлена.
    @State private var caretToEnd = false

    /// Поднимается по «Вводу» в заголовке: ввод переходит к тексту записи.
    @State private var toText = false

    /// Насколько клавиатура закрывает страницу снизу.
    @State private var keyboard: CGFloat = 0

    private let size = DiaryView.size

    var body: some View {
        VStack(spacing: 0) {
            page
            // Фотографии дневника — полоской внизу, над кнопками вложений,
            // как в Diarium; прокрутке страницы они не мешают (P203).
            if !photos.isEmpty {
                PhotoStrip(photos: photos, glowing: glowing, onOpen: onOpenPhoto,
                           drag: editable && photoLinks.count == photos.count
                               ? { Diary.line(photoLinks[$0]) } : nil,
                           onMove: editable ? onMovePhoto : nil)
                    .background(Color.clear)
            }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if inCloud {
                    Text("Запись этого дня ещё загружается из iCloud. Как только придёт, она появится здесь.")
                        .font(Look.serif(size - 1))
                        .foregroundStyle(Look.inkFaint)
                        .padding(.bottom, 12)
                }
                if let weather {
                    Label(weather, systemImage: "cloud.sun")
                        .font(Look.sans(12.5))
                        .foregroundStyle(Look.inkFaint)
                        .padding(.bottom, 10)
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
        .background(Color.clear)
        .keyboardHeight($keyboard)
    }

    private var asked: [PlanRow] {
        Array(tasks.filter { !$0.text.isEmpty }.prefix(3))
    }

    // MARK: - Как прошло

    /// Три первых дела, по строке на каждое (решение P30). Ответ пишется
    /// прямо в той же строке, за двоеточием, и, дойдя до края, продолжается
    /// с начала следующей — во всю ширину, как в тетради (решение P185).
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
        AskLine(label: task.text + ":",
                answer: Binding(get: { answer(task.text) },
                                set: { setAnswer?(task.text, $0) }),
                editable: editable && setAnswer != nil,
                typing: askingAt == task.text,
                onBegin: { askingAt = task.text },
                onDone: { if askingAt == task.text { askingAt = nil } },
                onNext: { next(after: task.text) })
            // Пустая строка стоит ровно в строку, а исписанная растёт вниз —
            // и дела, стоящие ниже, отодвигаются, освобождая место (P175).
            .frame(minHeight: size * 1.7, alignment: .leading)
    }

    /// «Ввод» в ответе: к следующему делу, а после последнего — к
    /// заголовку дня. Страница идёт сверху вниз, и «Ввод» ведёт по ней в
    /// том же порядке: ответы, заголовок, запись. Прежде последний ответ
    /// уводил прямо в запись, мимо заголовка (решение P196, уточняет P185).
    private func next(after task: String) {
        let дела = asked.map(\.text)
        if let i = дела.firstIndex(of: task), i + 1 < дела.count {
            askingAt = дела[i + 1]
        } else {
            askingAt = nil
            // Ввод уходит из поля ответа, и только потом заголовок его
            // принимает: иначе два поля перетягивают клавиатуру.
            DispatchQueue.main.async { focused = .title }
        }
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
                    grows: true, minHeight: 320, resolve: resolve,
                    onOpenPhoto: onOpenInline, onOpenPoint: onOpenPoint, onCaret: onCaret,
                    moving: glowing && editable, onEditing: onEditing)
            .padding(.top, 16)
    }
}
