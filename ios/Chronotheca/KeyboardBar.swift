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

    enum Ask: Equatable { case photo, camera, audio, files, place, map }

    /// Кто исполняет просьбы — оболочка приложения.
    static var ask: (Ask) -> Void = { _ in }
    /// Кто открывает разделы — оболочка приложения (P423).
    static var go: (Shell.Screen) -> Void = { _ in }

    /// Строка вложений и под ней строка разделов вдвое тоньше (P423):
    /// клавиатура закрывает нижнюю строку экрана — она поднимается над
    /// клавиатурой вместе со строкой вложений. Разделы не пропадают (P113).
    static let attachHeight: CGFloat = 36
    static let sectionsHeight: CGFloat = 18
    static let height: CGFloat = attachHeight + sectionsHeight
    /// Насколько проступает цвет дня у строки вложений: сквозь неё видно
    /// страницу — и над клавиатурой, и внизу страницы (P424).
    static let see: Double = 0.5
    /// Отступ строк от краёв экрана — бока скруглены (P424).
    static let inset: CGFloat = 6

    /// Какой день открыт: полоска над клавиатурой — в его цвет, как и
    /// полоска на странице (P297). Одна приставка на все поля, поэтому
    /// день ей сообщают, а не передают.
    final class Day: ObservableObject {
        @Published var date = DayStore.today()
    }
    static let day = Day()

    private static var host: UIHostingController<KeyboardBarView>?
    private static var holder: UIView?

    /// Одна приставка на все поля: видна она только у того, в котором пишут.
    static var view: UIView {
        if let holder { return holder }
        let made = UIHostingController(rootView: KeyboardBarView())
        // Без этого приставка отступает от собственного нижнего края, как
        // от клавиатуры под ней, — а клавиатура под ней и есть: остаётся
        // пустая полоса между приставкой и настоящей клавиатурой (P310).
        made.safeAreaRegions = []
        made.view.backgroundColor = .clear
        // Простая подложка, а не клавиатурная: строка вложений
        // полупрозрачная, сквозь неё видна страница (P423).
        let box = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width,
                                       height: height))
        box.backgroundColor = .clear
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
        VStack(spacing: 0) {
            attachments
                .frame(height: KeyboardBar.attachHeight)
            sections
                .frame(height: KeyboardBar.sectionsHeight)
        }
    }

    /// Разделы — одни названия, на том же крафте, что и внизу (P423).
    /// Пишут всегда на «Сегодня» — оно и выделено.
    private var sections: some View {
        HStack(spacing: 0) {
            name(T("Сегодня", "Today"), .today)
            name(T("Календарь", "Calendar"), .calendar)
            name(T("Карта", "Map"), .map)
            name(T("Поиск", "Search"), .search)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KraftPaper())
        // Над клавиатурой бока скруглены (P424); внизу экрана строка
        // прежняя.
        .clipShape(Capsule(style: .continuous))
        .padding(.horizontal, KeyboardBar.inset)
    }

    private func name(_ title: String, _ target: Shell.Screen) -> some View {
        Button { KeyboardBar.go(target) } label: {
            Text(title)
                .font(Look.sans(11.5, weight: target == .today ? .medium : .regular))
                .foregroundStyle(target == .today ? Look.accent : Look.kraftInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Строка вложений — полупрозрачная: сквозь неё видна страница (P423).
    private var attachments: some View {
        HStack(spacing: 0) {
            // Тот же порядок, что и в полоске без клавиатуры: камера
            // слева, дальше фото, аудио, файлы — у каждой кнопки своё
            // место, оно не должно меняться (P310).
            key("camera", T("камера", "camera")) { KeyboardBar.ask(.camera) }
            key("photo", T("фото", "photo")) { KeyboardBar.ask(.photo) }
            key("mic", T("аудио", "audio")) { KeyboardBar.ask(.audio) }
            key("doc", T("файлы", "files")) { KeyboardBar.ask(.files) }
            // «Место»: касание — где вы сейчас, долгое нажатие — карта (P381).
            BarFace(icon: "mappin.and.ellipse", name: T("место", "place"), tint: Look.stripInk, compact: true)
                .onTapGesture { KeyboardBar.ask(.place) }
                .onLongPressGesture(minimumDuration: 0.5) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    KeyboardBar.ask(.map)
                }
                .accessibilityAddTraits(.isButton)
            // Кнопки «убрать клавиатуру» нет (P424): её смахивают вниз.
        }
        .padding(.top, 4)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Полупрозрачная (P424): прежде под цветом дня лежало матовое
        // стекло — и строка выглядела сплошной.
        .background(DayStrip(date: day.date).opacity(KeyboardBar.see))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6))
        .padding(.horizontal, KeyboardBar.inset)
    }

    private func key(_ icon: String, _ name: String, act: @escaping () -> Void) -> some View {
        Button(action: act) { BarFace(icon: icon, name: name, tint: Look.stripInk, compact: true) }
            .buttonStyle(.plain)
    }
}

/// Приставка над клавиатурой у поля SwiftUI (P424).
///
/// У `TextField` своей приставки нет, а заголовок дня — он: курсор в
/// заголовке — и строки вложений и разделов не было. Метка кладётся фоном
/// поля, находит рядом настоящее поле UIKit и даёт ему ту же приставку,
/// что у записи.
struct KeyboardBarAttach: UIViewRepresentable {
    func makeUIView(context: Context) -> Finder { Finder() }
    func updateUIView(_ view: Finder, context: Context) {
        DispatchQueue.main.async { view.attach() }
    }

    final class Finder: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        func attach() {
            guard window != nil else { return }
            var level = superview
            for _ in 0..<4 {
                guard let here = level else { return }
                if let field = Self.field(in: here) {
                    guard field.inputAccessoryView !== KeyboardBar.view else { return }
                    field.inputAccessoryView = KeyboardBar.view
                    if field.isFirstResponder { field.reloadInputViews() }
                    return
                }
                level = here.superview
            }
        }

        private static func field(in view: UIView) -> UITextField? {
            if let field = view as? UITextField { return field }
            for sub in view.subviews {
                if let field = field(in: sub) { return field }
            }
            return nil
        }
    }
}
