import SwiftUI
import UIKit
import LocalAuthentication

/// Настройки, которые меняют раз и надолго (P249). Хранятся в самом
/// телефоне, не в папке записей: это привычки человека, а не его записи.
enum Prefs {
    static let lock = "prefs.lock"
    static let hide = "prefs.hide"
    static let theme = "prefs.theme"            // "system", "light", "dark"
    static let boundary = "prefs.boundary"      // час границы суток, 0…6
    static let startTab = "prefs.startTab"      // "plan", "diary"
    static let navigator = "prefs.navigator"    // "apple", "google"
    static let quiet = "prefs.quiet"            // true — без звуков (P265)
    static let textSize = "prefs.textSize"      // −1…2, ступени размера (P274)
    static let font = "prefs.font"              // "georgia", "newyork", "system"

    /// Ступени размера текста записей: мельче, обычный, крупнее, ещё крупнее.
    static let textSteps: [(name: String, scale: CGFloat)] = [
        ("мельче", 0.92), ("обычный", 1), ("крупнее", 1.1), ("ещё крупнее", 1.2),
    ]

    static var textStep: Int {
        min(max(UserDefaults.standard.integer(forKey: textSize) + 1, 0), textSteps.count - 1)
    }

    static var textScale: CGFloat { textSteps[textStep].scale }

    /// Шрифты записи дневника: названия для настроек.
    static let fonts: [(key: String, name: String)] = [
        ("georgia", "Georgia"), ("newyork", "New York"), ("system", "Без засечек"),
    ]

    static var fontKey: String { UserDefaults.standard.string(forKey: font) ?? "georgia" }

    /// Шрифт записи для полей UIKit.
    static func serifUIFont(_ size: CGFloat) -> UIFont {
        switch fontKey {
        case "newyork":
            let plain = UIFont.systemFont(ofSize: size)
            return plain.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? plain
        case "system":
            return .systemFont(ofSize: size)
        default:
            return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        }
    }

    static var scheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: theme) {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// Граница суток из настроек — применить к расчёту «сегодня».
    static func applyBoundary() {
        let hour = UserDefaults.standard.object(forKey: boundary) as? Int ?? 4
        DayStore.boundaryHour = min(max(hour, 0), 6)
    }
}

/// Замок: пока он закрыт, страниц не видно (P249). Открывается Face ID,
/// Touch ID или кодом телефона — тем, что настроено в самом iPhone.
struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(Look.inkSoft)
            Text("Записи закрыты")
                .font(Look.serif(20, weight: .semibold))
                .foregroundStyle(Look.ink)
            Button(action: unlock) {
                Text("Открыть")
                    .font(Look.sans(16, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Look.accent.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Look.chrome.ignoresSafeArea())
        .onAppear(perform: unlock)
    }

    /// Спросить телефон, тот ли человек держит его в руках.
    static func check(reason: String, done: @escaping (Bool) -> Void) {
        let context = LAContext()
        var trouble: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &trouble) else {
            return done(false)
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

/// Системное окно «поделиться» — поверх того, что сейчас на экране.
enum Share {
    static func present(_ items: [Any]) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let shown = top.presentedViewController { top = shown }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}

/// Заголовок раздела на бумажке настроек.
struct StickerSection: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Look.sans(9.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(Look.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

/// Высота клавиатуры над низом экрана. Нужна полоске вложений, которая
/// стоит над клавиатурой, пока та открыта (P253).
final class KeyboardWatch: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    /// Верхний край клавиатуры на экране; без клавиатуры — низ экрана.
    @Published private(set) var top: CGFloat = UIScreen.main.bounds.maxY
    private var watching: [NSObjectProtocol] = []

    init() {
        let centre = NotificationCenter.default
        watching.append(centre.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                                           object: nil, queue: .main) { [weak self] note in
            self?.follow(note, hiding: false)
        })
        watching.append(centre.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                           object: nil, queue: .main) { [weak self] note in
            self?.follow(note, hiding: true)
        })
    }

    deinit { watching.forEach(NotificationCenter.default.removeObserver) }

    private func follow(_ note: Notification, hiding: Bool) {
        let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let screen = UIScreen.main.bounds
        let now = hiding ? 0 : max(0, screen.maxY - frame.minY)
        let time = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: time)) {
            height = now
            top = screen.maxY - now
        }
    }
}
