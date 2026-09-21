import SwiftUI

/// Поиск по архиву.
///
/// Ищет по тому, что лежит в файлах: по заголовку дня, по тексту записи и по
/// названиям дел. В прототипе это был вид без начинки — здесь настоящий поиск,
/// потому что искать по своему архиву человек будет с первого же месяца.
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
                .foregroundStyle(.secondary)
            TextField("Поиск по словам", text: $query)
                .focused($typing)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Очистить")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
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
            return day.tasks.contains { $0.text.lowercased().contains(needle) }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(found) { day in
                    Button {
                        typing = false
                        store.go(to: day.date)
                        shell.tab = day.tasks.isEmpty ? .diary : .plan
                        shell.screen = .today
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(Ru.weekdayShort(day.date)) \(Ru.shortDate(day.date)) "
                                 + String(Calendar.current.component(.year, from: day.date)))
                                .font(.caption)
                                .foregroundStyle(Ru.dayColor(day.date))
                            Text(day.line)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if !day.tasks.isEmpty {
                                Text("дел: \(day.tasks.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 18).opacity(0.3)
                }
                Text("Найдено дней: \(found.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 16)
            }
        }
    }

    private func message(_ head: String, _ tail: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(head).font(.callout).foregroundStyle(.secondary)
            Text(tail).font(.footnote).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}
