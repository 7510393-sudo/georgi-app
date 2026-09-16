import SwiftUI
import UniformTypeIdentifiers

/// Экран «Сегодня»: две вкладки на одном дне.
///
/// Каркас. Здесь нет ни шторки, ни ленты, ни календаря — только то, что нужно,
/// чтобы проверить главное обещание: текст попадает в файл, файл лежит в папке
/// пользователя, и приложение читает его обратно.
struct TodayView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case plan = "План"
        case diary = "Дневник"
        var id: String { rawValue }
    }

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore

    @State private var tab: Tab = .plan
    @State private var picking = false
    @State private var peeking = false

    var body: some View {
        NavigationStack {
            Group {
                if vault.root == nil { welcome } else { day }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vault.root != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { picking = true } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("Сменить папку")
                    }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                vault.adopt(url)
                store.load()
            }
        }
        .sheet(isPresented: $peeking) { fileSheet }
    }

    // MARK: - Первый запуск

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Выберите папку")
                .font(.title2)

            Text("Записи будут лежать в ней обычными файлами. "
                 + "Папка ваша: приложение только пишет и читает, "
                 + "а распоряжаетесь ею вы. Удалите приложение — записи останутся.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Выбрать папку") { picking = true }
                .buttonStyle(.borderedProminent)

            if let problem = vault.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }

    // MARK: - День

    private var day: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            TextEditor(text: tab == .plan ? $store.plan : $store.diary)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)

            footer
        }
        .onChange(of: store.plan) { _, _ in store.save() }
        .onChange(of: store.diary) { _, _ in store.save() }
    }

    private var footer: some View {
        HStack {
            Button { store.move(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Предыдущий день")

            Spacer()

            Button("Файл на диске") { peeking = true }
                .font(.footnote)

            Spacer()

            Button { store.move(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Следующий день")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Проверка обещания

    private var fileSheet: some View {
        NavigationStack {
            ScrollView {
                Text(store.onDisk())
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Файл на диске")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { peeking = false }
                }
            }
        }
    }

    // MARK: - Заголовок

    private var title: String {
        let days = Calendar.current.dateComponents([.day],
                                                   from: DayStore.today(),
                                                   to: store.date).day ?? 0
        switch days {
        case 0:  return "Сегодня"
        case -1: return "Вчера"
        case -2: return "Позавчера"
        case 1:  return "Завтра"
        case 2:  return "Послезавтра"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.setLocalizedDateFormatFromTemplate("d MMMM")
            return f.string(from: store.date)
        }
    }
}
