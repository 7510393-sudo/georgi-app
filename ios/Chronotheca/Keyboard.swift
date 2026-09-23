import SwiftUI
import UIKit

/// Насколько клавиатура закрывает экран снизу.
///
/// Приложение не отдаёт клавиатуре весь экран: шестерёнка, три точки и три
/// раздела внизу стоят на месте всегда (P113). Поднимается только то, в чём
/// пишут, и ровно на столько, сколько закрыто.
struct KeyboardHeight: ViewModifier {

    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect ?? .zero
                let screen = UIScreen.main.bounds.height
                // Нижняя безопасная полоса телефона уже учтена отступами:
                // не вычесть её — и остаётся пустое поле шириной в палец.
                let safe = UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
                    .first ?? 0
                height = max(0, screen - frame.origin.y - safe)
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                height = 0
            }
    }
}

extension View {
    func keyboardHeight(_ height: Binding<CGFloat>) -> some View {
        modifier(KeyboardHeight(height: height))
    }
}
