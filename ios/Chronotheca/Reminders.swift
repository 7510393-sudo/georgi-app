import Foundation
import UserNotifications

/// Напоминания колокольчика (P260).
///
/// Колокольчик раньше только записывал время в файл — «(напомнить 08:30)»,
/// — а телефону ничего не передавалось, и в срок он молчал. Теперь по
/// каждому такому делу заводится обычное уведомление iPhone. Файл
/// остаётся главным: напоминания дня каждый раз расставляются заново по
/// тому, что в нём записано, — снял колокольчик в файле на Mac, и
/// напоминание тоже снимется, как только день откроют.
enum Reminders {

    /// В проверках уведомлений не трогаем: там нет приложения, которому
    /// их показывать.
    private static let testing = NSClassFromString("XCTestCase") != nil

    /// Спросить разрешение. Спрашивается, когда человек сам поставил
    /// колокольчик, — не раньше.
    static func ask(done: @escaping (Bool) -> Void = { _ in }) {
        guard !testing else { return done(true) }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { done(true) }
            case .denied:
                DispatchQueue.main.async { done(false) }
            default:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    DispatchQueue.main.async { done(ok) }
                }
            }
        }
    }

    /// Заново расставить напоминания дня: прежние снять, по файлу завести.
    static func sync(day: Date, rows: [PlanRow]) {
        guard !testing else { return }
        let center = UNUserNotificationCenter.current()
        let prefix = "bell." + Vault.stamp(day) + "."
        let now = Date()
        let wanted: [(String, UNNotificationRequest)] = rows.enumerated().compactMap { n, row in
            guard row.isTask, !row.done, let bell = row.bell,
                  let when = moment(bell, on: day), when > now else { return nil }
            let content = UNMutableNotificationContent()
            let title = Geo.stripped(row.text)
            content.title = title.isEmpty ? "Дело без названия" : title
            content.body = row.time.map { "Дело на \($0)" } ?? "Напоминание из плана"
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                        from: when)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = prefix + "\(n)"
            return (id, UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for (_, request) in wanted { center.add(request) }
        }
    }

    /// Когда звонить: час из колокольчика в этот день. Час раньше границы
    /// суток — это уже следующее утро по часам (граница — 4:00, P17).
    static func moment(_ hhmm: String, on day: Date) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
            return nil
        }
        let cal = Calendar.current
        var base = cal.startOfDay(for: day)
        if parts[0] < DayStore.boundaryHour {
            base = cal.date(byAdding: .day, value: 1, to: base) ?? base
        }
        return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base)
    }
}

/// Уведомление видно и тогда, когда приложение открыто: иначе iPhone
/// показывает его, только если приложение закрыто, — и напоминание,
/// пришедшее посреди записи, пропадало молча.
final class BellDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BellDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }
}
