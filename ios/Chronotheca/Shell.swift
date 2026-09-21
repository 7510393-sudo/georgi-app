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
    @Published var showingFolder = false
    @Published var showingFile = false
    @Published var picking = false

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

    var screenName: String {
        switch screen {
        case .today: return ""
        case .calendar: return "Календарь"
        case .search: return "Поиск"
        }
    }
}
