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

    /// Правка кончилась: клавиатура ушла.
    var onDone: () -> Void = {}

    /// Нажат «Ввод»: ввод переходит к делу ниже.
    var onNext: () -> Void = {}

    static let placeholder = "Без названия"
    static let size: CGFloat = 15
    static let spacing: CGFloat = 3

    /// Насколько вторая строка названия отступает от первой сверх обычного.
    ///
    /// Первая строка стоит рядом с номером, временем и колокольчиком, а
    /// вторая начинается под ними. Без зазора она прилипала к пунктиру
    /// времени, и «нотариусу» читалось как подпись к «09:00» (решение P186).
    static let clearance: CGFloat = 5

    /// Где проходит строчка письма, считая от верха поля. По ней голова
    /// строки садится на первую строку названия (P171).
    static let baseline: CGFloat = 14

    func makeUIView(context: Context) -> UITextView {
        // Старая раскладка текста, а не новая: только в ней можно дать
        // отдельный зазор после первой строки (P186).
        let view = TitleView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.layoutManager.delegate = context.coordinator
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
        // Обычный «Ввод» со стрелкой, а не синее «Готово» с галочкой:
        // клавиша уводит на строку ниже, как ей и положено (решение P180).
        view.returnKeyType = .default
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        (view as? TitleView)?.indent = indent
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
        // Расстояние между строками задаёт попечитель раскладки — у первой
        // строки оно своё. Здесь ноль, чтобы оно не сложилось дважды.
        paragraph.lineSpacing = 0
        return [
            .font: UIFont.systemFont(ofSize: Self.size),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
    }

    /// Переписать содержимое, не сдвинув курсор.
    private func apply(to view: UITextView) {
        let styled = NSAttributedString(string: shown, attributes: style)
        // Оформление набора ставится всегда, даже когда текст не менялся:
        // у пустого поля только по нему и видно, где начинать строку.
        view.typingAttributes = style
        guard styled != view.attributedText else { return }
        let было = view.selectedRange
        view.attributedText = styled
        view.typingAttributes = style
        let длина = (view.text as NSString).length
        view.selectedRange = NSRange(location: min(было.location, длина), length: 0)
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate, NSLayoutManagerDelegate {
        var parent: PlanTitle

        init(_ parent: PlanTitle) { self.parent = parent }

        /// После первой строки — зазор, если за ней есть вторая: вторая
        /// начинается под головой строки и не должна к ней прилипать.
        /// Одиночное название строку не удлиняет (решение P186).
        func layoutManager(_ layoutManager: NSLayoutManager,
                           lineSpacingAfterGlyphAt glyphIndex: Int,
                           withProposedLineFragmentRect rect: CGRect) -> CGFloat {
            let первая = rect.minY < 1
            let дальше = glyphIndex + 1 < layoutManager.numberOfGlyphs
            return первая && дальше ? PlanTitle.spacing + PlanTitle.clearance : PlanTitle.spacing
        }

        func textViewDidChange(_ view: UITextView) { parent.text = view.text }

        func textViewDidEndEditing(_ view: UITextView) { parent.onDone() }

        /// В названии не бывает перевода строки.
        ///
        /// В файле дело занимает ровно строку: перевод разорвал бы его
        /// надвое, и хвост осел бы отдельной непонятой строкой вместе с
        /// напоминанием. Но клавиша «Ввод» и не должна ничего рвать — она
        /// уводит на строку ниже, к следующему делу (P180). Вставленный из
        /// буфера перевод строки становится пробелом (решение P172).
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
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
                parent.text = view.text
            }
            return false
        }
    }
}

/// Поле названия, у которого курсор пустой строки стоит там, где начнётся
/// текст, а не под номером.
///
/// Пока в поле ни буквы, отступу первой строки не к чему приложиться, и
/// курсор вставал у самого левого края — под номером, временем и
/// колокольчиком. Человек заводил дело и не видел, где печатать
/// (решение P193).
final class TitleView: UITextView {
    var indent: CGFloat = 0

    override func caretRect(for position: UITextPosition) -> CGRect {
        var r = super.caretRect(for: position)
        if text.isEmpty, r.minX < indent { r.origin.x = indent }
        return r
    }
}
