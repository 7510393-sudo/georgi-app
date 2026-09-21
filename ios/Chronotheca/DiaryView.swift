import SwiftUI

/// Вкладка «Дневник»: как прошло, заголовок дня и свободный текст.
///
/// Набрана засечным шрифтом на тёплой бумаге — в отличие от плана. Это разные
/// занятия: план разглядывают, дневник читают. Рука должна чувствовать разницу
/// раньше, чем глаз прочтёт заголовок вкладки.
struct DiaryView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    private enum Field: Hashable { case title, text, answer(String) }
    @FocusState private var focused: Field?

    /// Размеры из прототипа.
    private let size: CGFloat = 15.5
    private let leading: CGFloat = 15.5 * 0.7

    var body: some View {
        Group {
            if store.canEditDiary { page } else { closed }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Look.diaryBg)
    }

    private var closed: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Look.inkFaint)
            Text(store.closedReason)
                .font(Look.serif(size))
                .foregroundStyle(Look.inkSoft)
            Text("Дневник пишут о том, что было, а не о том, что будет.")
                .font(Look.serif(13.5))
                .foregroundStyle(Look.inkFaint)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !store.tasks.isEmpty { askBlock }
                titleField
                textField
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .onChange(of: store.diaryTitle) { _, _ in store.scheduleSave() }
        .onChange(of: store.answers) { _, _ in store.scheduleSave() }
        .onChange(of: store.date) { _, _ in focused = nil }
    }

    /// «Как прошло?» — три первых дела и строка ответа за каждым.
    ///
    /// Три, а не все (решение P30): список дел не должен превращаться в анкету.
    private var askBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Как прошло?")
                .font(Look.serif(size, weight: .semibold))
                .foregroundStyle(Look.ink)
                .padding(.bottom, 2)

            ForEach(store.tasks.filter { !$0.text.isEmpty }.prefix(3), id: \.id) { task in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // Название дела в одну строку с многоточием, и оно забирает
                    // ширину первым. Наоборот было нельзя: поле ответа тянется
                    // сколько дадут и сжимало вопрос до нуля — на экране
                    // оставались одни ответы без вопросов.
                    Text(task.text + ":")
                        .font(Look.serif(size))
                        .foregroundStyle(Look.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    TextField("…", text: Binding(
                        get: { store.answers[task.text] ?? "" },
                        set: { store.answers[task.text] = $0 }), axis: .vertical)
                        .font(Look.serif(size))
                        .foregroundStyle(Look.ink)
                        .focused($focused, equals: .answer(task.text))
                        .frame(minWidth: 70, alignment: .leading)
                }
                .lineSpacing(leading - size * 0.6)
                .padding(.vertical, 1)
            }
        }
        .padding(.bottom, 14)
    }

    private var titleField: some View {
        VStack(spacing: 0) {
            TextField("Заголовок дня", text: $store.diaryTitle)
                .font(Look.serif(19, weight: .semibold))
                .foregroundStyle(Look.ink)
                .focused($focused, equals: .title)
                .submitLabel(.next)
                .onSubmit { focused = .text }
                .padding(.bottom, 7)
            Rectangle().fill(Look.rule).frame(height: 1)
        }
        .padding(.top, 4)
    }

    /// Текст записи.
    ///
    /// Возвращаясь к дневнику больше чем через час, приложение само ставит
    /// новую отметку времени в начале строки. Так по записи видно, что день
    /// писался в несколько заходов, а не залпом вечером.
    private var textField: some View {
        ZStack(alignment: .topLeading) {
            if store.diaryText.isEmpty {
                Text(store.tasks.isEmpty ? "Что было сегодня…" : "И что ещё было в этот день…")
                    .font(Look.serif(size))
                    .foregroundStyle(Look.inkFaint)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $store.diaryText)
                .font(Look.serif(size))
                .foregroundStyle(Look.ink)
                .lineSpacing(leading - size * 0.6)
                .focused($focused, equals: .text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(.horizontal, -5)
        }
        .padding(.top, 16)
        .onChange(of: focused) { _, now in
            if now == .text { store.stampIfNeeded() }
        }
        .onChange(of: store.diaryText) { _, _ in
            store.touchDiary()
            store.scheduleSave()
        }
    }
}
