import SwiftUI
import UIKit

/// Строка «Как прошло?»: название дела и ответ одной полосой текста.
///
/// Раньше название стояло слева, а ответ — справа от него отдельным полем,
/// и длинный ответ складывался в узкий столбик под самим собой. Теперь это
/// одна полоса, как строка в тетради: название дела, двоеточие и дальше
/// ответ, который, дойдя до края, продолжается с начала следующей строки
/// (решение P185).
///
/// Название — часть того же текста, но его не сотрёшь и не поправишь:
/// курсор за него не заходит, правка его не касается. Отвечать можно
/// только после двоеточия.
///
/// Поле одно и то же и на открытой странице, и на соседних: соседняя лишь
/// не правится. Иначе строки разошлись бы в переносах, и текст прыгал бы
/// на повороте страницы (P114).
struct AskLine: UIViewRepresentable {

    /// Название дела с двоеточием.
    let label: String
    @Binding var answer: String

    var editable = false
    /// Ввод перешёл сюда: поле берёт его на себя.
    var typing = false

    var onBegin: () -> Void = {}
    var onDone: () -> Void = {}
    /// Нажат «Ввод»: ввод переходит к следующему ответу или к записи.
    var onNext: () -> Void = {}

    static let size: CGFloat = DiaryView.size
    static let placeholder = "…"

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        view.allowsEditingTextAttributes = false
        view.isScrollEnabled = false
        view.returnKeyType = .default
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable
        view.isSelectable = editable
        context.coordinator.apply(to: view)

        if typing, editable, !view.isFirstResponder {
            view.becomeFirstResponder()
            view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let занято = uiView.sizeThatFits(CGSize(width: width,
                                                height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: занято.height.rounded(.up))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Вид

    /// Тот же засечный шрифт и та же подгонка под системный размер текста,
    /// что у записи ниже: строки «Как прошло?» и запись — одна тетрадь.
    static var font: UIFont {
        let base = UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
    }

    static func style(_ color: Color) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = UIFontMetrics(forTextStyle: .body).scaledValue(for: size * 0.24)
        return [.font: font, .foregroundColor: UIColor(color), .paragraphStyle: paragraph]
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AskLine
        private var clamping = false

        init(_ parent: AskLine) { self.parent = parent }

        /// Сколько знаков занимает название с пробелом за ним.
        var prefix: Int { ((parent.label + " ") as NSString).length }

        /// Собрать строку: бледное название, ответ чернилами, а у пустого
        /// ответа, пока в нём не пишут, — бледное многоточие.
        func styled(for view: UITextView) -> NSAttributedString {
            let out = NSMutableAttributedString(string: parent.label + " ",
                                                attributes: AskLine.style(Look.inkFaint))
            if parent.answer.isEmpty && !view.isFirstResponder {
                out.append(NSAttributedString(string: AskLine.placeholder,
                                              attributes: AskLine.style(Look.inkFaint)))
            } else {
                out.append(NSAttributedString(string: parent.answer,
                                              attributes: AskLine.style(Look.ink)))
            }
            return out
        }

        /// Переписать строку, не сдвинув курсор.
        func apply(to view: UITextView) {
            let wanted = styled(for: view)
            guard wanted != view.attributedText else { return }
            let было = view.selectedRange
            view.attributedText = wanted
            view.typingAttributes = AskLine.style(Look.ink)
            let длина = (view.text as NSString).length
            view.selectedRange = NSRange(location: min(max(было.location, prefix), длина),
                                         length: 0)
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            apply(to: view)   // многоточие уходит, как только начали писать
            view.selectedRange = NSRange(location: (view.text as NSString).length, length: 0)
            parent.onBegin()
        }

        func textViewDidEndEditing(_ view: UITextView) {
            apply(to: view)   // у пустого ответа снова многоточие
            parent.onDone()
        }

        func textViewDidChange(_ view: UITextView) {
            let всё = view.text as NSString
            parent.answer = всё.length > prefix ? всё.substring(from: prefix) : ""
            view.typingAttributes = AskLine.style(Look.ink)
        }

        /// Курсор за название не заходит: писать можно только после
        /// двоеточия.
        func textViewDidChangeSelection(_ view: UITextView) {
            guard !clamping, view.isFirstResponder else { return }
            let r = view.selectedRange
            guard r.location < prefix else { return }
            clamping = true
            let конец = r.location + r.length
            view.selectedRange = NSRange(location: prefix, length: max(0, конец - prefix))
            clamping = false
        }

        /// Название не правится. «Ввод» уводит дальше, а не рвёт ответ:
        /// в файле ответ — одна строка «- Дело: ответ» (P172, P180).
        /// Перевод строки, вставленный из буфера, становится пробелом.
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard range.location >= prefix else { return false }
            guard text.contains(where: \.isNewline) else { return true }
            if text.allSatisfy(\.isNewline) {
                parent.onNext()
                return false
            }
            let одной = String(text.map { $0.isNewline ? " " : $0 })
            if let target = Range(range, in: view.text) {
                view.text.replaceSubrange(target, with: одной)
                view.selectedRange = NSRange(location: range.location
                                             + (одной as NSString).length, length: 0)
                textViewDidChange(view)
                apply(to: view)
            }
            return false
        }
    }
}
