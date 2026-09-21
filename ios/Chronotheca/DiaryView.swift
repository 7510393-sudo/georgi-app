import SwiftUI

/// Вкладка «Дневник»: как прошло, заголовок дня и свободный текст.
struct DiaryView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    private enum Field: Hashable { case title, text, answer(String) }
    @FocusState private var focused: Field?

    var body: some View {
        if store.canEditDiary { page } else { closed }
    }

    private var closed: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.closedReason)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Дневник пишут о том, что было, а не о том, что будет.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.tasks.isEmpty { askBlock }

                TextField("Заголовок дня", text: $store.diaryTitle)
                    .font(.title3.weight(.medium))
                    .focused($focused, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focused = .text }
                    .padding(.horizontal, 18)

                diaryEditor
            }
            .padding(.vertical, 12)
        }
        .onChange(of: store.diaryTitle) { _, _ in store.scheduleSave() }
        .onChange(of: store.answers) { _, _ in store.scheduleSave() }
    }

    /// «Как прошло?» — три первых дела и строка ответа под каждым.
    ///
    /// Три, а не все (решение P30): список дел не должен превращаться в анкету.
    private var askBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Как прошло?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(store.tasks.filter { !$0.text.isEmpty }.prefix(3), id: \.id) { task in
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("…", text: Binding(
                        get: { store.answers[task.text] ?? "" },
                        set: { store.answers[task.text] = $0 }), axis: .vertical)
                        .font(.callout)
                        .focused($focused, equals: .answer(task.text))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
    }

    /// Текст записи.
    ///
    /// Возвращаясь к дневнику больше чем через час, приложение само ставит
    /// новую отметку времени в начале строки. Так по записи видно, что день
    /// писался в несколько заходов, а не залпом вечером.
    private var diaryEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.diaryText.isEmpty {
                Text(store.tasks.isEmpty ? "Что было сегодня…" : "И что ещё было в этот день…")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 23)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $store.diaryText)
                .focused($focused, equals: .text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(.horizontal, 14)
        }
        .onChange(of: focused) { _, now in
            if now == .text { store.stampIfNeeded() }
        }
        .onChange(of: store.diaryText) { _, _ in
            store.touchDiary()
            store.scheduleSave()
        }
    }
}
