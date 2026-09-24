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

    /// Просьба взять ввод на себя. Её подаёт «Ввод» в заголовке дня:
    /// заголовок дописан, дальше человек пишет запись, и тянуться к ней
    /// пальцем он не должен (решение P40).
    var startEditing: Binding<Bool> = .constant(false)

    var onFocus: () -> Void = {}

    /// Поле меряется по тексту и растёт вместе с ним.
    ///
    /// Так стоит запись дневника: страница едет целиком, а поле внутри
    /// себя ничего не прокручивает. В подробностях дела наоборот — поле
    /// занимает отведённую коробку и прокручивает текст в себе.
    var grows = false

    /// Сколько поле просит себе, даже когда текста в нём нет. Нужно только
    /// там, где поле меряется по тексту.
    var minHeight: CGFloat = 0

    /// Отметка времени в начале строки: «08:15 » и дальше текст.
    static let stamp = try! NSRegularExpression(pattern: #"^(\d{2}:\d{2})[  ]"#)

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        context.coordinator.view = view
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.spellCheckingType = .no
        // Вставлять в запись картинки и вложения нельзя: файл должен
        // читаться обычным текстовым редактором. Разрешённое оформление
        // порождает в тексте знак-заместитель, который виден как «OBJ»
        // в пунктирной рамке (решение P161).
        view.allowsEditingTextAttributes = false
        // Клавиатура уезжает движением пальца вниз по тексту.
        view.keyboardDismissMode = .interactive
        // Растущее поле не отбирает движение пальца у страницы: прокручивать
        // ему нечего, а пружинило бы оно вместо неё (решение P175).
        view.alwaysBounceVertical = !grows
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

        // Поле сверяется с записью без знаков-заместителей. Пока идёт
        // диктовка, система держит в поле свой временный знак; переписать
        // из-за него поле — вырвать знак у неё из рук, и он остаётся в
        // тексте «OBJ» (решение P197).
        if DiaryEditor.clean(view.text) != text || view.attributedText.length == 0 {
            let selection = view.selectedRange
            view.attributedText = Self.styled(text, size: size, serif: serif, stamped: stamped)
            view.typingAttributes = Self.body(size, serif: serif)
            view.selectedRange = selection.location <= (view.text as NSString).length
                ? selection
                : NSRange(location: (view.text as NSString).length, length: 0)
        } else {
            context.coordinator.restyle(view)
        }

        if startEditing.wrappedValue {
            // Сбрасываем просьбу до того, как поле возьмёт ввод: иначе
            // отметка времени, которую поставит `onFocus`, вызовет новое
            // обновление, и просьба сработает второй раз.
            DispatchQueue.main.async { startEditing.wrappedValue = false }
            view.becomeFirstResponder()
        }

        // Курсор переставляется только по просьбе — и только туда, куда
        // человек и так собирался писать (решение P137).
        if caretToEnd.wrappedValue {
            let end = NSRange(location: (view.text as NSString).length, length: 0)
            view.selectedRange = end
            view.typingAttributes = Self.body(size, serif: serif)
            view.scrollRangeToVisible(end)
            let попечитель = context.coordinator
            DispatchQueue.main.async {
                caretToEnd.wrappedValue = false
                попечитель.showCaret(animated: true)
            }
        }
    }

    /// Сколько места поле просит себе.
    ///
    /// Растущее поле просит ровно столько, сколько занял текст. Тогда
    /// страница дневника едет целиком: «Как прошло?» и заголовок уходят
    /// вверх вместе с записью, а не висят над ней, пока текст ползёт под
    /// ними (решение P175).
    ///
    /// Остальные поля меряются как обычно — по отведённой им коробке.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        guard grows, let width = proposal.width, width > 0 else { return nil }
        let занято = uiView.sizeThatFits(CGSize(width: width,
                                                height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minHeight, занято.height.rounded(.up)))
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

    /// Знак-заместитель вложения. Система ставит его туда, где в тексте
    /// было что-то не буквенное; в простом тексте он рисуется как «OBJ» в
    /// пунктирной рамке и попадает в файл записи, где ему совсем не место.
    ///
    /// Откуда он берётся, зависит от клавиатуры и способа ввода, поэтому
    /// перекрыт и источник (правка оформления запрещена), и следствие: знак
    /// убирается из текста, что бы его ни поставило (решение P161).
    static let placeholder: Character = "\u{FFFC}"

    static func clean(_ text: String) -> String {
        text.contains(placeholder) ? text.filter { $0 != placeholder } : text
    }

    static func styled(_ text: String, size: CGFloat,
                       serif: Bool, stamped: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString(string: clean(text),
                                            attributes: body(size, serif: serif))
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

        /// Поле, за которым присматривает этот попечитель.
        weak var view: UITextView?

        /// Верхняя кромка клавиатуры в окне. Пусто — клавиатуры нет.
        private var keyboardTop: CGFloat?

        init(_ parent: DiaryEditor) {
            self.parent = parent
            super.init()
            let вести = NotificationCenter.default
            вести.addObserver(self, selector: #selector(keyboardMoved(_:)),
                              name: UIResponder.keyboardWillChangeFrameNotification,
                              object: nil)
            вести.addObserver(self, selector: #selector(keyboardGone(_:)),
                              name: UIResponder.keyboardWillHideNotification,
                              object: nil)
        }

        func textViewDidBeginEditing(_ view: UITextView) {
            parent.onFocus()
            // Клавиатура могла подняться раньше — например, человек писал
            // заголовок дня и перешёл в запись. Тогда вестей о ней больше
            // не будет, и место надо освободить самому.
            DispatchQueue.main.async { [weak self] in self?.makeRoom(scroll: true) }
        }

        func textViewDidEndEditing(_ view: UITextView) {
            scrub()
            makeRoom(scroll: false)
        }

        /// Вычистить из поля знаки-заместители, оставив курсор на месте.
        ///
        /// Зовётся, когда поле отпускает ввод: диктовка к этому времени
        /// кончилась, и поле снова принадлежит нам (решение P197).
        func scrub() {
            guard let view else { return }
            let ns = view.text as NSString
            let знак = String(DiaryEditor.placeholder) as NSString
            var где = ns.range(of: знак as String, options: .backwards)
            guard где.location != NSNotFound else { return }
            var курсор = view.selectedRange
            view.textStorage.beginEditing()
            while где.location != NSNotFound {
                view.textStorage.deleteCharacters(in: где)
                if где.location < курсор.location { курсор.location -= где.length }
                где = (view.text as NSString).range(
                    of: знак as String, options: .backwards,
                    range: NSRange(location: 0, length: где.location))
            }
            view.textStorage.endEditing()
            view.selectedRange = NSRange(
                location: min(курсор.location, (view.text as NSString).length), length: 0)
            parent.text = view.text
            restyle(view)
        }

        // MARK: - Клавиатура

        @objc private func keyboardMoved(_ note: Notification) {
            guard let view, let window = view.window,
                  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                    as? CGRect
            else { return }
            keyboardTop = window.convert(frame, from: nil).minY
            makeRoom(scroll: true)
        }

        @objc private func keyboardGone(_ note: Notification) {
            keyboardTop = nil
            makeRoom(scroll: false)
        }

        /// Освободить место под клавиатурой и довести курсор до глаз.
        ///
        /// Приложение нарочно не отдаёт клавиатуре весь экран: шестерёнка и
        /// нижние разделы стоят на месте всегда (P113). Значит, поле само
        /// отмеряет, сколько его закрыто снизу, и на столько же отступает
        /// изнутри — после чего курсор доводится обычной прокруткой поля,
        /// той же, какой человек листает текст рукой.
        ///
        /// Отступает только то поле, в котором пишут: у соседних страниц
        /// поле точно такое же, и трогать их нельзя — разойдутся строки
        /// (P114). Решение P174.
        private func makeRoom(scroll: Bool) {
            guard let view, let window = view.window else { return }
            let место = view.convert(view.bounds, to: window)
            // Отступ изнутри нужен только полю в коробке: растущему поле
            // место под клавиатурой отводит сама страница.
            let закрыто = view.isFirstResponder && !parent.grows
                ? (keyboardTop.map { max(0, место.maxY - $0) } ?? 0)
                : 0
            if view.contentInset.bottom != закрыто {
                view.contentInset.bottom = закрыто
                view.verticalScrollIndicatorInsets.bottom = закрыто
            }
            guard scroll, view.isFirstResponder else { return }
            // Прокрутка — следующим оборотом: к этому времени и курсор
            // стоит на месте, и высота поля пересчитана.
            DispatchQueue.main.async { [weak self] in self?.showCaret(animated: true) }
        }

        /// Довести курсор до глаз.
        ///
        /// Сперва — прокруткой самого поля: так устроены подробности дела,
        /// где поле стоит в отведённой коробке. Если внутри прокручивать
        /// нечего — поле подобрало себе высоту по тексту, как в дневнике, —
        /// едет вся страница, ровно настолько, насколько курсор зашёл под
        /// клавиатуру (решение P175).
        func showCaret(animated: Bool) {
            guard let view, view.isFirstResponder, let window = view.window,
                  let top = keyboardTop, let end = view.selectedTextRange?.end
            else { return }
            view.scrollRangeToVisible(view.selectedRange)

            let курсор = view.convert(view.caretRect(for: end), to: window)
            let ниже = курсор.maxY + 16 - top
            guard ниже > 0, let страница = page(over: view) else { return }
            let предел = max(0, страница.contentSize.height
                             + страница.adjustedContentInset.bottom
                             - страница.bounds.height)
            let куда = min(страница.contentOffset.y + ниже, предел)
            guard куда > страница.contentOffset.y else { return }
            страница.setContentOffset(CGPoint(x: страница.contentOffset.x, y: куда),
                                      animated: animated)
        }

        /// Ближайшая прокрутка над полем — сама страница дневника.
        private func page(over view: UITextView) -> UIScrollView? {
            var выше = view.superview
            while let здесь = выше {
                if let scroll = здесь as? UIScrollView { return scroll }
                выше = здесь.superview
            }
            return nil
        }

        func textViewDidChange(_ view: UITextView) {
            parent.text = DiaryEditor.clean(view.text)
            restyle(view)
            // Строка прибавилась — курсор мог уйти под клавиатуру.
            DispatchQueue.main.async { [weak self] in self?.showCaret(animated: false) }
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
                parent.text = DiaryEditor.clean(view.text)
                restyle(view)
            }
            return false
        }

        /// Перекрасить отметки времени, не сдвинув курсор.
        ///
        /// Краска кладётся на тот же текст, а не заменяет его новым: замена
        /// выдёргивала у диктовки её временный знак, и в записи оставалось
        /// «OBJ» (решение P197). Заодно курсор и выделение не трогаются.
        func restyle(_ view: UITextView) {
            let text = view.text ?? ""
            let ns = text as NSString
            let всё = NSRange(location: 0, length: ns.length)
            let body = DiaryEditor.body(parent.size, serif: parent.serif)
            let storage = view.textStorage
            storage.beginEditing()
            storage.addAttributes(body, range: всё)
            // Отметка ищется в начале каждой строки — так же, как при
            // первой раскраске поля.
            var start = 0
            while parent.stamped, start < ns.length {
                let line = ns.lineRange(for: NSRange(location: start, length: 0))
                if let m = DiaryEditor.stamp.firstMatch(in: text, range: line),
                   m.numberOfRanges > 1 {
                    storage.addAttributes([
                        .font: UIFont.monospacedSystemFont(ofSize: parent.size * 0.84,
                                                           weight: .regular),
                        .foregroundColor: UIColor(Look.inkFaint),
                    ], range: m.range(at: 1))
                }
                guard line.length > 0 else { break }
                start = line.location + line.length
            }
            storage.endEditing()
            view.typingAttributes = body
        }
    }
}
