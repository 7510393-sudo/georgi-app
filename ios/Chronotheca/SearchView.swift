import SwiftUI

/// Поиск по архиву.
///
/// Ищет по тому, что лежит в файлах: по заголовку дня, по тексту записи, по
/// названиям дел и по ответам «Как прошло?». Показывает при этом только
/// заголовок и текст: ответы — служебная часть записи, в выдаче от них
/// рябит. Но если искомое слово нашлось именно в них, день всё равно
/// попадает в список — иначе поиск лгал бы.
struct SearchView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var vault: Vault

    /// Строка поиска лежит в оболочке: её очищает и меню поиска.
    private var query: String { shell.query }
    @FocusState private var typing: Bool

    /// Насколько клавиатура закрывает список находок.
    @State private var keyboard: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("Поиск")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Look.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, DayPage.airAbove)
                .padding(.bottom, 10)
            field
            if archive.newestFirst.isEmpty {
                message("Пока нечего искать.",
                        "Напишите первую запись — и она найдётся здесь.")
            } else if found.isEmpty {
                message("Ничего не нашлось.", "По запросу «\(query)» \(whereNot)записей нет.")
            } else {
                list
            }
        }
        .onAppear { archive.reload() }
        .keyboardHeight($keyboard)
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkFaint)
            TextField(prompt, text: $shell.query)
                .focused($typing)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { shell.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Look.inkFaint)
                    .accessibilityLabel("Очистить")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// Где ищем — видно прямо в строке поиска, а не только в меню: иначе,
    /// выбрав «только в плане» и забыв об этом, человек решит, что запись
    /// пропала.
    private var prompt: String {
        switch shell.scope {
        case .all:   return "Поиск по словам"
        case .diary: return "Поиск в дневнике"
        case .plan:  return "Поиск в плане"
        }
    }

    private var whereNot: String {
        switch shell.scope {
        case .all:   return ""
        case .diary: return "в дневнике "
        case .plan:  return "в плане "
        }
    }

    /// Ответы «Как прошло?» — часть дневника: их пишут там, а не в плане.
    private var found: [Archive.Day] {
        let days = archive.newestFirst.filter(kept)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return days }
        let scope = shell.scope
        return days.filter { day in
            if scope != .plan {
                if day.title.lowercased().contains(needle) { return true }
                if day.text.lowercased().contains(needle) { return true }
                if day.answers.values.contains(where: { $0.lowercased().contains(needle) }) {
                    return true
                }
            }
            if scope != .diary {
                return day.tasks.contains { $0.text.lowercased().contains(needle) }
            }
            return false
        }
    }

    /// Подходит ли день под «что искать» из меню поиска (P249).
    private func kept(_ day: Archive.Day) -> Bool {
        let kinds = day.attachments.map { Diary.kind(of: $0) }
        switch shell.find {
        case .all:   return true
        case .photo: return kinds.contains(.photo)
        case .video: return kinds.contains(.video)
        case .audio: return kinds.contains(.audio)
        case .file:  return kinds.contains(.file)
        case .place:
            return day.place != nil || day.text.contains("geo:")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(found) { day in
                    row(day)
                    Rectangle().fill(Look.ruleSoft).frame(height: 1).padding(.leading, 18)
                }
            }
            // Место под клавиатуру. Без него последние находки лежат под
            // ней и не достаются прокруткой: список кончается там, где
            // начинается клавиатура (решение P174).
            .padding(.bottom, keyboard)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeOut(duration: 0.25), value: keyboard)
    }

    private func row(_ day: Archive.Day) -> some View {
        Button {
            typing = false
            store.go(to: day.date)
            // Искали в плане — туда и открываем: там нашлось искомое.
            shell.tab = shell.scope == .plan || (day.text.isEmpty && !day.tasks.isEmpty)
                ? .plan : .diary
            shell.screen = .today
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // Год, месяц, число — в этом порядке: при поиске по архиву
                    // сначала выбирают время, а не день недели. День недели
                    // виден на самой записи, когда до неё дойдут.
                    Text(Search.stamp(day.date))
                        .font(Look.mono(11.5))
                        .tracking(0.3)
                        .foregroundStyle(Look.inkFaint)

                    if !day.title.isEmpty {
                        Text(day.title)
                            .font(Look.serif(15, weight: .semibold))
                            .foregroundStyle(Look.ink)
                            .lineLimit(1)
                    }
                    if !day.text.isEmpty {
                        Text(day.preview)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(day.title.isEmpty ? 4 : 3)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if let cover = day.cover { preview(cover, of: day) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    /// Превью справа от находки: снимок, кадр видео, голос или документ
    /// (P215).
    @ViewBuilder private func preview(_ link: String, of day: Archive.Day) -> some View {
        let url = vault.mediaURL(link, for: day.date)
        Group {
            switch Diary.kind(of: link) {
            case .photo: PhotoThumb(url: url)
            case .video: PhotoThumb(url: url, video: true)
            case .audio: FileTile(icon: "waveform", label: "голос")
            case .file:  FileTile(icon: "doc.text",
                                  label: (link as NSString).pathExtension.lowercased())
            }
        }
        .frame(width: 52, height: 52)
        .padding(.top, 2)
    }

    private func message(_ head: String, _ tail: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(head).font(Look.sans(15)).foregroundStyle(Look.inkSoft)
            Text(tail).font(Look.sans(13)).foregroundStyle(Look.inkFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}

enum Search {
    /// «2026 сентябрь 22» — от крупного к мелкому, как ищут в архиве.
    static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return "\(c.year ?? 2026)  \(Ru.monthNames[(c.month ?? 1) - 1])  \(c.day ?? 1)"
    }
}
