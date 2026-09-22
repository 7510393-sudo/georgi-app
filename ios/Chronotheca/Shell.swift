import SwiftUI

/// Что сейчас на экране и что поверх него.
///
/// Отдельно от данных: здесь нет ничего, что стоило бы записать в файл.
/// Закроется приложение — потеряется только то, на какой вкладке человек был,
/// и это не потеря.
final class Shell: ObservableObject {

    enum Screen { case today, calendar, search }

    enum Tab: String, CaseIterable, Identifiable {
        case plan = "План"
        case diary = "Дневник"
        var id: String { rawValue }
    }

    @Published var screen: Screen = .today
    @Published var tab: Tab = .plan

    /// Дело, чья шторка «Подробности» открыта.
    @Published var drawer: UUID?

    /// Дело, которому крутят время, и что именно крутят.
    @Published var roller: Roller?

    struct Roller: Identifiable {
        enum Kind { case time, bell }
        let id: UUID
        let kind: Kind
    }

    @Published var showingMenu = false
    @Published var showingSettings = false
    @Published var showingFile = false
    @Published var picking = false

    /// Только для снимков: показать вместо открытой страницы ту же страницу,
    /// нарисованную соседским способом. Так две росписи можно сличить
    /// пиксель в пиксель, а не рассуждать о них по памяти.
    @Published var probingSide = false

    @Published var notice: String?
    private var hiding: DispatchWorkItem?

    /// Сказать человеку, почему ничего не произошло.
    ///
    /// Молчаливый отказ — худшее, что может сделать приложение: человек решает,
    /// что сломалось оно, хотя оно просто не даёт нарушить правило.
    func say(_ text: String) {
        hiding?.cancel()
        withAnimation { notice = text }
        let item = DispatchWorkItem { [weak self] in
            withAnimation { self?.notice = nil }
        }
        hiding = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3, execute: item)
    }

    /// Открыть экран, названный в переменной окружения, — для снимков.
    ///
    /// Нужно, чтобы у каждой сборки был снимок каждого экрана, а не одного.
    /// Иначе про интерфейс приходится рассуждать по памяти, а память врёт.
    func openRequestedScreen(_ store: DayStore) {
        guard Vault.isPreview,
              let name = ProcessInfo.processInfo.environment["CHRONOTHECA_SCREEN"]
        else { return }
        switch name {
        case "diary":     tab = .diary
        case "calendar":  screen = .calendar
        case "search":    screen = .search
        case "menu":      showingMenu = true
        case "settings":  showingSettings = true
        case "remember":  tab = .diary
        case "details":   drawer = store.tasks.first?.id
        case "past":      store.move(by: -1)
        case "editing":   store.editing = true
        case "future":    store.move(by: 1); tab = .diary
        case "side":      probingSide = true
        case "list":
            // Вид календаря запоминается в настройках — оттуда его и берём.
            UserDefaults.standard.set(CalendarView.Kind.list.rawValue, forKey: "calendar.kind")
            screen = .calendar
        default: break
        }
    }

}
