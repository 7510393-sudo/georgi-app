import SwiftUI
import UIKit

/// Полоска вложений над клавиатурой — частью самой клавиатуры (P279).
///
/// Раньше она стояла отдельно и догоняла клавиатуру по её сообщениям.
/// Когда клавиатуру смахивали пальцем, сообщений нет до самого конца —
/// и полоска висела на месте, пока клавиатура уже уехала. Приставка к
/// клавиатуре ездит с ней сама, как её собственная строка.
///
/// Кнопки только просят: окна выбора открывает полоска открытой
/// страницы — она на своём месте в окне, ей их и показывать.
enum KeyboardBar {

    enum Ask: Equatable { case photo, camera, audio, files }

    /// Кто исполняет просьбы — оболочка приложения.
    static var ask: (Ask) -> Void = { _ in }

    static let height: CGFloat = 36

    /// Какой день открыт: полоска над клавиатурой — в его цвет, как и
    /// полоска на странице (P297). Одна приставка на все поля, поэтому
    /// день ей сообщают, а не передают.
    final class Day: ObservableObject {
        @Published var date = DayStore.today()
    }
    static let day = Day()

    private static var host: UIHostingController<KeyboardBarView>?
    private static var holder: UIInputView?

    /// Одна приставка на все поля: видна она только у того, в котором пишут.
    static var view: UIView {
        if let holder { return holder }
        let made = UIHostingController(rootView: KeyboardBarView())
        made.view.backgroundColor = .clear
        let box = UIInputView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                            height: height),
                              inputViewStyle: .default)
        box.allowsSelfSizing = false
        made.view.frame = box.bounds
        made.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(made.view)
        host = made
        holder = box
        return box
    }
}

struct KeyboardBarView: View {
    @ObservedObject private var day = KeyboardBar.day

    var body: some View {
        HStack(spacing: 0) {
            key("photo", "фото") { KeyboardBar.ask(.photo) }
            key("camera", "камера") { KeyboardBar.ask(.camera) }
            key("waveform", "аудио") { KeyboardBar.ask(.audio) }
            key("doc", "файлы") { KeyboardBar.ask(.files) }
            key("keyboard.chevron.compact.down", "убрать") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DayStrip(date: day.date))
        .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1) }
    }

    private func key(_ icon: String, _ name: String, act: @escaping () -> Void) -> some View {
        Button(action: act) { BarFace(icon: icon, name: name, tint: Look.stripInk, compact: true) }
            .buttonStyle(.plain)
    }
}
