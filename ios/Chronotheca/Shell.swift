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

    /// Какая плашка сейчас опущена на книгу. Идёт за `screen`, но не сразу:
    /// при смене календаря на поиск сперва уходит одна плашка, потом
    /// опускается другая (решение P202).
    @Published var lowered: Screen = .today
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

    /// Снимок, открытый во весь экран: с какой вкладки и который по счёту.
    struct OpenedPhoto: Identifiable {
        let tab: Tab
        let index: Int
        /// Снимок, стоящий посреди страницы, а не в полоске: открывается
        /// прямо по месту, без «убрать» (P205).
        var url: URL? = nil
        /// Строка-ссылка снимка из текста: по ней он возвращается в
        /// полоску (P216).
        var link: String? = nil
        var id: String { tab.rawValue + String(index) + (url?.path ?? "") }
    }
    @Published var openedPhoto: OpenedPhoto?

    @Published var showingMenu = false
    /// Своя карта мест — за кнопкой «геоточка» (P207).
    @Published var showingMap = false
    /// Точка, на которой открыть карту: её нажали в тексте дня (P213).
    @Published var mapFocus: GeoPoint?
    /// Точка, выбранная сейчас на карте. По ней работают «в навигатор» и
    /// «скопировать» — и в полоске карты, и в её меню (P219).
    @Published var mapPoint: GeoPoint?
    /// Карта снимком со спутника, а не схемой (P222).
    @Published var mapSatellite = false

    /// Открыть карту на точке из текста.
    func showPoint(_ point: GeoPoint) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        mapFocus = point
        withAnimation(.easeOut(duration: 0.25)) { showingMap = true }
    }
    @Published var showingSettings = false
    @Published var showingFile = false
    @Published var picking = false

    /// Только для снимков: показать вместо открытой страницы ту же страницу,
    /// нарисованную соседским способом. Так две росписи можно сличить
    /// пиксель в пиксель, а не рассуждать о них по памяти.
    @Published var probingSide = false

    /// Просьба вернуться на сегодняшний день, перелистнув страницы.
    /// Поднимается кнопкой «Сегодня» внизу; выполняет её сама книга.
    @Published var goHome = false

    /// Просьба календарю вернуться к нынешнему месяцу или году, перелистнув
    /// страницы. Поднимается из меню календаря; выполняет сам календарь.
    @Published var calendarHome = false

    /// Где искать: везде, только в дневнике или только в плане.
    enum Scope { case all, diary, plan }

    /// Строка поиска и где искать живут здесь, а не в самом поиске: их
    /// меняет и меню поиска, а оно лежит поверх всего приложения.
    @Published var query = ""
    @Published var scope: Scope = .all

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
        case "calendar-menu": screen = .calendar; showingMenu = true
        case "search-menu":   screen = .search; showingMenu = true
        case "settings":  showingSettings = true
        case "remember":  tab = .diary
        case "details":   drawer = store.tasks.first?.id
        case "past":      store.move(by: -1)
        case "editing":   store.setEditing(.plan, true)
        case "future":    store.move(by: 1); tab = .diary
        case "side":      probingSide = true
        case "list":
            // Вид календаря запоминается в настройках — оттуда его и берём.
            UserDefaults.standard.set(CalendarView.Kind.list.rawValue, forKey: "calendar.kind")
            screen = .calendar
        default: break
        }
        // Для снимков плашка стоит на месте сразу, без хода.
        lowered = screen
    }

}
