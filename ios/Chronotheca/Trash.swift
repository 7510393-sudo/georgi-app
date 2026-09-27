import SwiftUI

/// Корзина дней (P295).
///
/// Убранный день не стирается: его файлы плана и дневника переезжают в
/// папку «Корзина» внутри папки записей — `Корзина/ГГГГ-ММ-ДД/Дневник/…`.
/// Их видно в «Файлах», их можно вернуть на место из настроек или удалить
/// навсегда. Снимки, голос и документы дня остаются в своих папках: вернули
/// день — ссылки на них снова работают.
enum Trash {

    static let folderName = "Корзина"

    struct Item: Identifiable {
        let stamp: String
        let date: Date
        let url: URL
        /// Первые слова записи или первое дело — чтобы узнать день.
        let preview: String
        var id: String { stamp }
    }

    private static let parts: [Vault.Folder] = [.planner, .diary]

    static func folder(_ vault: Vault) -> URL? {
        vault.root?.appendingPathComponent(folderName)
    }

    /// Убрать день в корзину. Уже лежит там такой же день — новый ляжет
    /// рядом под своим номером: ничего не затирается.
    @discardableResult
    static func put(_ date: Date, in vault: Vault) -> Bool {
        guard let base = folder(vault) else { return false }
        let stamp = Vault.stamp(date)
        let fm = FileManager.default
        var day = base.appendingPathComponent(stamp)
        var n = 2
        while fm.fileExists(atPath: day.path) {
            day = base.appendingPathComponent("\(stamp) (\(n))")
            n += 1
        }
        var moved = false
        for part in parts {
            guard let from = vault.file(part, for: date), fm.fileExists(atPath: from.path) else { continue }
            let dir = day.appendingPathComponent(part.rawValue)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if move(from, to: dir.appendingPathComponent(from.lastPathComponent)) { moved = true }
        }
        return moved
    }

    /// Что лежит в корзине — свежие дни сверху.
    static func items(in vault: Vault) -> [Item] {
        guard let base = folder(vault),
              let names = try? FileManager.default.contentsOfDirectory(atPath: base.path)
        else { return [] }
        return names.compactMap { name -> Item? in
            let stamp = String(name.prefix(10))
            guard let date = Vault.date(from: stamp) else { return nil }
            let url = base.appendingPathComponent(name)
            return Item(stamp: name, date: date, url: url, preview: preview(url, stamp: stamp))
        }
        .sorted { $0.stamp > $1.stamp }
    }

    /// Вернуть день на место. На его месте уже новая запись — не трогаем
    /// ни ту, ни другую и говорим об этом (P182: чужое не затирается).
    static func restore(_ item: Item, in vault: Vault) -> Bool {
        let fm = FileManager.default
        var pairs: [(URL, URL)] = []
        for part in parts {
            let from = item.url.appendingPathComponent(part.rawValue)
                .appendingPathComponent(String(item.stamp.prefix(10)) + ".md")
            guard fm.fileExists(atPath: from.path) else { continue }
            guard let to = vault.file(part, for: item.date) else { return false }
            if fm.fileExists(atPath: to.path) { return false }
            pairs.append((from, to))
        }
        for (from, to) in pairs {
            try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard move(from, to: to) else { return false }
        }
        try? fm.removeItem(at: item.url)
        return true
    }

    /// Удалить навсегда.
    static func purge(_ item: Item) {
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: item.url, options: .forDeleting, error: &trouble) { real in
                try? FileManager.default.removeItem(at: real)
            }
        if FileManager.default.fileExists(atPath: item.url.path) {
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    private static func preview(_ day: URL, stamp: String) -> String {
        for part in [Vault.Folder.diary, .planner] {
            let file = day.appendingPathComponent(part.rawValue).appendingPathComponent(stamp + ".md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let body = DayFile(text: text).body
            let words = body.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("![") }
            if let words { return String(words.prefix(80)) }
        }
        return "Пустой день"
    }

    private static func move(_ from: URL, to: URL) -> Bool {
        var done = false
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(writingItemAt: from, options: .forMoving,
                        writingItemAt: to, options: .forReplacing, error: &trouble) { a, b in
                done = (try? FileManager.default.moveItem(at: a, to: b)) != nil
            }
        if !done, FileManager.default.fileExists(atPath: from.path) {
            done = (try? FileManager.default.moveItem(at: from, to: to)) != nil
        }
        return done
    }
}

/// Корзина в настройках: убранные дни — вернуть или удалить навсегда.
struct TrashSheet: View {
    let vault: Vault
    let changed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [Trash.Item] = []
    @State private var doomed: Trash.Item?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("Корзина пуста. День убирают в корзину из меню страницы — три точки.")
                        .font(Look.sans(14))
                        .foregroundStyle(Look.inkSoft)
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Ru.weekday(item.date) + ", " + Ru.longDate(item.date))
                            .font(Look.sans(15, weight: .medium))
                        Text(item.preview)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(2)
                        HStack(spacing: 18) {
                            Button("Вернуть") {
                                if Trash.restore(item, in: vault) {
                                    Feel.done()
                                    reload()
                                    changed()
                                } else {
                                    note = "На место этого дня уже есть новая запись. Файл остался в корзине — перенесите нужное руками в «Файлах»."
                                }
                            }
                            Button("Удалить навсегда", role: .destructive) { doomed = item }
                        }
                        .buttonStyle(.borderless)
                        .font(Look.sans(14))
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Корзина")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .confirmationDialog("Удалить день навсегда?", isPresented: Binding(
                get: { doomed != nil }, set: { if !$0 { doomed = nil } }), titleVisibility: .visible) {
                Button("Удалить навсегда", role: .destructive) {
                    if let doomed { Trash.purge(doomed) }
                    doomed = nil
                    reload()
                }
            } message: {
                Text("Файлы плана и дневника этого дня будут стёрты. Снимки и голос дня останутся в своих папках.")
            }
            .alert("Не вернулось", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
                Button("Понятно") { note = nil }
            } message: {
                Text(note ?? "")
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { items = Trash.items(in: vault) }
}
