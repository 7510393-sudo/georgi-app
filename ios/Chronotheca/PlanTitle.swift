import SwiftUI
import UIKit

/// Название дела: одна полоса текста во всю ширину строки.
///
/// Первая строка отступает вправо — под ней стоят номер, время и
/// колокольчик. Все остальные идут из-под времени, во всю ширину до
/// закладки. Иначе длинное название складывается в узкий столбик рядом с
/// двумя другими столбиками — времён и колокольчиков, — и страница читается
/// не строками, а колонками (решение P177).
///
/// Отступ первой строки задаётся числом и должен в точности равняться
/// ширине головы строки: номер, время и колокольчик стоят поверх него.
/// Поэтому ширина каждой из трёх частей задана намертво, а не меряется по
/// содержимому.
///
/// Поле одно и то же и на открытой странице, и на соседних: соседняя лишь
/// не правится. Два разных способа показать название разошлись бы в
/// переносах, и текст прыгал бы на повороте страницы (P114).
struct PlanTitle: UIViewRepresentable {

    @Binding var text: String

    /// Отступ первой строки — ширина головы строки.
    var indent: CGFloat
    /// Отступ остальных строк — из-под времени, правее номера.
    var wrap: CGFloat

    var faded = false
    /// Можно ли ставить курсор и править.
    var editable = false
    /// Правят именно эту строку: поле берёт ввод на себя.
    var typing = false

    /// Правка кончилась: «Ввод» нажат или клавиатура ушла.
    var onDone: () -> Void = {}

    static let placeholder = "Без названия"
    static let size: CGFloat = 15
    static let spacing: CGFloat = 3

    /// Где проходит строчка письма, считая от верха поля. По ней голова
    /// строки садится на первую строку названия (P171).
    static let baseline: CGFloat = 14

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        // Ни отступов, ни полей: строчка письма должна считаться от самого
        // верха поля, иначе голова строки сядет мимо.
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        // Вставлять в название картинки и вложения нельзя: в файле это
        // обычная строка (P161).
        view.allowsEditingTextAttributes = false
        // Поле меряется по тексту и не прокручивает в себе ничего: строка
        // плана растёт вниз вместе с названием.
        view.isScrollEnabled = false
        view.returnKeyType = .done
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable
        view.isSelectable = editable
        apply(to: view)

        if typing, !view.isFirstResponder {
            view.becomeFirstResponder()
            let end = NSRange(location: (view.text as NSString).length, length: 0)
            view.selectedRange = end
        }
        if !typing, view.isFirstResponder {
            view.resignFirstResponder()
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

    /// Что показываем: своё название, а у пустого дела, пока его не правят, —
    /// бледное «Без названия».
    private var shown: String {
        editable ? text : (text.isEmpty ? Self.placeholder : text)
    }

    private var ink: UIColor {
        UIColor(faded || text.isEmpty ? Look.inkFaint : Look.ink)
    }

    private var style: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = wrap
        paragraph.lineSpacing = Self.spacing
        return [
            .font: UIFont.systemFont(ofSize: Self.size),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
    }

    /// Переписать содержимое, не сдвинув курсор.
    private func apply(to view: UITextView) {
        let styled = NSAttributedString(string: shown, attributes: style)
        guard styled != view.attributedText else { return }
        let было = view.selectedRange
        view.attributedText = styled
        view.typingAttributes = style
        let длина = (view.text as NSString).length
        view.selectedRange = NSRange(location: min(было.location, длина), length: 0)
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlanTitle

        init(_ parent: PlanTitle) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) { parent.text = view.text }

        func textViewDidEndEditing(_ view: UITextView) { parent.onDone() }

        /// В названии не бывает перевода строки.
        ///
        /// В файле дело занимает ровно строку: перевод разорвал бы его
        /// надвое, и хвост осел бы отдельной непонятой строкой вместе с
        /// напоминанием. Поэтому «Ввод» заканчивает правку — как и обещает
        /// надпись на клавише, — а вставленный из буфера перевод строки
        /// становится пробелом (решение P172).
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text.contains(where: \.isNewline) else { return true }
            if text.allSatisfy(\.isNewline) {
                view.resignFirstResponder()
                return false
            }
            let одной = String(text.map { $0.isNewline ? " " : $0 })
            if let target = Range(range, in: view.text) {
                view.text.replaceSubrange(target, with: одной)
                view.selectedRange = NSRange(location: range.location
                                             + (одной as NSString).length, length: 0)
                parent.text = view.text
            }
            return false
        }
    }
}
