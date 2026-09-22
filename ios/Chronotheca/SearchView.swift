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

    @State private var query = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Поиск")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Look.ink)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)
            field
            if archive.newestFirst.isEmpty {
                message("Пока нечего искать.",
                        "Напишите первую запись — и она найдётся здесь.")
            } else if found.isEmpty {
                message("Ничего не нашлось.", "По запросу «\(query)» записей нет.")
            } else {
                list
            }
        }
        .onAppear { archive.reload() }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkFaint)
            TextField("Поиск по словам", text: $query)
                .focused($typing)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
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

    private var found: [Archive.Day] {
        let days = archive.newestFirst
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return days }
        return days.filter { day in
            if day.title.lowercased().contains(needle) { return true }
            if day.text.lowercased().contains(needle) { return true }
            if day.answers.values.contains(where: { $0.lowercased().contains(needle) }) {
                return true
            }
            return day.tasks.contains { $0.text.lowercased().contains(needle) }
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
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ day: Archive.Day) -> some View {
        Button {
            typing = false
            store.go(to: day.date)
            shell.tab = day.text.isEmpty && !day.tasks.isEmpty ? .plan : .diary
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
                        Text(day.text)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(day.title.isEmpty ? 4 : 3)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
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
