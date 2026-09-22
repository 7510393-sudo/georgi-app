import SwiftUI
import UIKit

/// Поле записи дневника.
///
/// Обычного текстового поля здесь мало по двум причинам, и обе — решения,
/// а не украшения. Отметка времени в начале строки должна быть бледнее и
/// мельче текста: она служебная, читать надо не её. И первая буква после
/// отметки должна вставать заглавной — человек начинает предложение, а не
/// продолжает строку.
///
/// Оба правила живут здесь, а не в разметке, потому что внутри одного поля
/// разным кускам текста нужен разный вид.
struct DiaryEditor: UIViewRepresentable {

    @Binding var text: String
    var size: CGFloat = 15.5
    /// Засечный — для дневника, обычный — для подробностей дела.
    var serif = true
    /// Отметки времени бледнее и мельче. В подробностях они ни к чему.
    var stamped = true
    /// Соседние страницы показывают то же поле, только без правки: иначе
    /// рядом стоят два разных способа набрать текст, и строки на повороте
    /// расходятся (P114).
    var editable = true
    /// Просьба поставить курсор в конец текста при ближайшем обновлении.
    /// Её подаёт отметка времени: её ставит приложение, а писать после неё
    /// человеку — и тянуться до конца предыдущего куска он не должен.
    var caretToEnd: Binding<Bool> = .constant(false)
    var onFocus: () -> Void = {}

    /// Отметка времени в начале строки: «08:15 » и дальше текст.
    static let stamp = try! NSRegularExpression(pattern: #"^(\d{2}:\d{2})[  ]"#)

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        // Клавиатура уезжает движением пальца вниз по тексту.
        view.keyboardDismissMode = .interactive
        view.alwaysBounceVertical = true
        view.scrollsToTop = false
        view.isEditable = editable
        view.isSelectable = editable
        // Прокрутка включена всегда, даже там, где не правят. Без прокрутки
        // поле само подбирает себе высоту, и строки ложатся не так, как в
        // таком же поле рядом: на повороте страницы текст перескакивает из
        // одной строки в две. Одинаковое поле — одинаковые строки (P114).
        view.isScrollEnabled = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.isEditable = editable
        view.isSelectable = editable

        if view.text != text || view.attributedText.length == 0 {
            let selection = view.selectedRange
            view.attributedText = Self.styled(text, size: size, serif: serif, stamped: stamped)
            view.typingAttributes = Self.body(size, serif: serif)
            view.selectedRange = selection.location <= (view.text as NSString).length
                ? selection
                : NSRange(location: (view.text as NSString).length, length: 0)
        } else {
            context.coordinator.restyle(view)
        }

        // Курсор переставляется только по просьбе — и только туда, куда
        // человек и так собирался писать (решение P137).
        if caretToEnd.wrappedValue {
            let end = NSRange(location: (view.text as NSString).length, length: 0)
            view.selectedRange = end
            view.typingAttributes = Self.body(size, serif: serif)
            view.scrollRangeToVisible(end)
            DispatchQueue.main.async { caretToEnd.wrappedValue = false }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Вид

    static func body(_ size: CGFloat, serif: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: size * 0.24)
        // Размер подгоняется под системную настройку текста — ровно так же,
        // как это делает обычный текст на соседней странице. Без этого после
        // поворота страницы текст «мельчает»: рядом стояли два разных шрифта.
        let base = serif
            ? (UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size))
            : UIFont.systemFont(ofSize: size)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        return [
            .font: font,
            .foregroundColor: UIColor(Look.ink),
            .paragraphStyle: paragraph,
        ]
    }

    static func styled(_ text: String, size: CGFloat,
                       serif: Bool, stamped: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: body(size, serif: serif))
        guard stamped else { return out }
        let ns = text as NSString
        var start = 0
        while start <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: start, length: 0))
            if let m = stamp.firstMatch(in: text, range: lineRange), m.numberOfRanges > 1 {
                out.addAttributes([
                    .font: UIFont.monospacedSystemFont(ofSize: size * 0.84, weight: .regular),
                    .foregroundColor: UIColor(Look.inkFaint),
                ], range: m.range(at: 1))
            }
            if lineRange.length == 0 { break }
            start = lineRange.location + lineRange.length
            if start >= ns.length { break }
        }
        return out
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: DiaryEditor

        init(_ parent: DiaryEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ view: UITextView) { parent.onFocus() }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            restyle(view)
        }

        /// Первая буква строки после отметки времени набирается заглавной.
        ///
        /// Не только при наборе: диктовка вставляет целую фразу разом, и её
        /// первая буква должна вести себя так же.
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard parent.stamped,
                  let first = text.first, first.isLowercase else { return true }
            let before = (view.text as NSString).substring(to: range.location)
            guard let line = before.components(separatedBy: .newlines).last,
                  line.range(of: #"^\d{2}:\d{2}[  ]+$"#, options: .regularExpression) != nil
            else { return true }

            let upper = String(first).uppercased() + String(text.dropFirst())
            if let target = Range(range, in: view.text) {
                view.text.replaceSubrange(target, with: upper)
                let after = range.location + (upper as NSString).length
                view.selectedRange = NSRange(location: after, length: 0)
                parent.text = view.text
                restyle(view)
            }
            return false
        }

        /// Перекрасить отметки времени, не сдвинув курсор.
        func restyle(_ view: UITextView) {
            let selection = view.selectedRange
            let styled = DiaryEditor.styled(view.text, size: parent.size,
                                            serif: parent.serif, stamped: parent.stamped)
            guard styled != view.attributedText else { return }
            view.attributedText = styled
            view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            view.selectedRange = selection
        }
    }
}
