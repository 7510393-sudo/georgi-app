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

    /// Где лежит снимок, на который ссылается строка `![](…)`. Задано —
    /// значит поле рисует такие строки картинками (решение P204).
    var resolve: ((String) -> URL?)?

    /// Касание по снимку в тексте — открыть его (P216). Пусто — снимки не
    /// открываются: так на соседних страницах.
    var onOpenPhoto: ((String) -> Void)?
    /// Касание по точке в тексте — открыть карту на ней (P213).
    var onOpenPoint: ((GeoPoint) -> Void)?
    /// Курсор переставлен: где он теперь, отступом в тексте записи. Туда
    /// встанет точка с карты (P213).
    var onCaret: ((Int) -> Void)?
    /// Режим изменений: снимок или точку в тексте можно взять долгим
    /// нажатием и перенести в другое место записи (P226).
    var moving = false
    /// Поле взяло ввод или отпустило его (P240).
    var onEditing: ((Bool) -> Void)?
    /// Просьба поставить курсор сюда — отступом в тексте записи. Её подаёт
    /// геоточка, вписанная посреди набора: писать дальше — за точкой (P253).
    var placeCaret: Binding<Int?> = .constant(nil)

    /// Отметка времени в начале строки: «08:15 » и дальше текст.
    /// В прошедший день за временем идёт дата, когда писали:
    /// «08:15 25.09.26 » (P227, P232).
    static let stamp = try! NSRegularExpression(
        pattern: #"^(\d{2}:\d{2}(?: \d{2}\.\d{2}\.\d{2})?)[  ]"#)

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        // Превью из полоски бросают прямо в текст (решение P204).
        view.textDropDelegate = context.coordinator
        context.coordinator.view = view
        // Касание по снимку или точке в тексте открывает их, а не ставит
        // курсор рядом (P213, P216).
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        let carry = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.carried(_:)))
        carry.minimumPressDuration = 0.25
        carry.delegate = context.coordinator
        view.addGestureRecognizer(carry)
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
        context.coordinator.parent = self
        view.isEditable = editable
        view.isSelectable = editable
        context.coordinator.resolve = resolve

        // Поле сверяется с записью без знаков-заместителей. Пока идёт
        // диктовка, система держит в поле свой временный знак; переписать
        // из-за него поле — вырвать знак у неё из рук, и он остаётся в
        // тексте «OBJ» (решение P197).
        // Режим изменений включили или выключили — точки перерисовываются
        // со свечением или без (P241).
        if DiaryEditor.plain(view.attributedText) != text || view.attributedText.length == 0
            || context.coordinator.drawnMoving != moving {
            context.coordinator.drawnMoving = moving
            let selection = view.selectedRange
            view.attributedText = Self.styled(text, size: size, serif: serif, stamped: stamped,
                                              resolve: resolve, glowing: moving)
            view.typingAttributes = Self.body(size, serif: serif)
            view.selectedRange = selection.location <= (view.text as NSString).length
                ? selection
                : NSRange(location: (view.text as NSString).length, length: 0)
            context.coordinator.loadPhotos()
        } else {
            context.coordinator.restyle(view)
        }

        if let at = placeCaret.wrappedValue {
            if view.isFirstResponder {
                let spot = Self.viewOffset(plain: at, in: view.attributedText)
                view.selectedRange = NSRange(location: spot, length: 0)
                view.typingAttributes = Self.body(size, serif: serif)
            }
            DispatchQueue.main.async { placeCaret.wrappedValue = nil }
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

    static func styled(_ text: String, size: CGFloat, serif: Bool, stamped: Bool,
                       resolve: ((String) -> URL?)? = nil,
                       glowing: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString(string: clean(text),
                                            attributes: body(size, serif: serif))
        defer { if let resolve { placePhotos(in: out, resolve: resolve, glowing: glowing) } }
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
            if let place = placeRange(in: ns, line: lineRange) {
                out.addAttributes(placeLook(size), range: place)
            }
            if lineRange.length == 0 { break }
            start = lineRange.location + lineRange.length
            if start >= ns.length { break }
        }
        return out
    }

    // MARK: - Место в тексте

    /// Строка `geo:широта,долгота` — место, вписанное долгим нажатием на
    /// геоточку. Служебная, как отметка времени: бледнее и моноширинная
    /// (P165, P207).
    static func placeRange(in ns: NSString, line: NSRange) -> NSRange? {
        let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
        guard content.hasPrefix("geo:"), Geo.parse(content) != nil else { return nil }
        return NSRange(location: line.location, length: (content as NSString).length)
    }

    static func placeLook(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.monospacedSystemFont(ofSize: size * 0.8, weight: .regular),
         .foregroundColor: UIColor(Look.accent)]
    }

    // MARK: - Снимки в тексте

    /// Метка снимка в поле: на экране — картинка, в файле — строка-ссылка.
    static let photoKey = NSAttributedString.Key("chronotheca.photo")

    /// Размер снимка в тексте. Задан числом: картинка, пришедшая с диска
    /// позже текста, встаёт в уже отведённое место и ничего не сдвигает
    /// (P113).
    static let photoSize = CGSize(width: 192, height: 128)

    /// Текст поля таким, каким он ляжет в файл: снимки — обратно строками
    /// `![](…)`, чужие знаки-заместители — вон (P161, P204).
    static func plain(_ s: NSAttributedString) -> String {
        let ns = s.string as NSString
        var out = ""
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attributes, range, _ in
            if let link = attributes[photoKey] as? String {
                out += Array(repeating: Diary.line(link), count: range.length)
                    .joined(separator: "\n")
            } else if let line = attributes[lineKey] as? String {
                out += Array(repeating: line, count: range.length)
                    .joined(separator: "\n")
            } else {
                out += clean(ns.substring(with: range))
            }
        }
        return out
    }

    /// Где в поле то место записи, что стоит в файле на отступе `plain`.
    /// Снимок и точка в поле — один знак, а в файле — целая строка.
    static func viewOffset(plain target: Int, in s: NSAttributedString) -> Int {
        let ns = s.string as NSString
        var seen = 0
        var found = s.length
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attributes, range, stop in
            var line: String?
            if let link = attributes[photoKey] as? String { line = Diary.line(link) }
            if let l = attributes[lineKey] as? String { line = l }
            if let line {
                let each = (line as NSString).length
                for k in 0..<range.length {
                    if seen >= target { found = range.location + k; stop.pointee = true; return }
                    seen += each + (k < range.length - 1 ? 1 : 0)
                }
            } else {
                let piece = (clean(ns.substring(with: range)) as NSString).length
                if seen + piece >= target {
                    let inside = piece == range.length ? target - seen : range.length
                    found = range.location + max(0, min(inside, range.length))
                    stop.pointee = true
                    return
                }
                seen += piece
            }
        }
        return found
    }

    /// Метка точки в поле: на экране — кнопочка, в файле — та же строка,
    /// что была (P213).
    static let lineKey = NSAttributedString.Key("chronotheca.line")

    /// Заменить строки-ссылки на картинки.
    static func placePhotos(in out: NSMutableAttributedString,
                            resolve: (String) -> URL?, glowing: Bool = false) {
        let ns = out.string as NSString
        var found: [(NSRange, String, GeoPoint?)] = []
        var start = 0
        while start < ns.length {
            let line = ns.lineRange(for: NSRange(location: start, length: 0))
            let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
            let range = NSRange(location: line.location, length: (content as NSString).length)
            if let link = Diary.picture(in: content), Diary.kind(of: link) == .photo {
                found.append((range, link, nil))
            } else if let point = Geo.point(in: content) {
                found.append((range, content, point))
            }
            guard line.length > 0 else { break }
            start = line.location + line.length
        }
        for (range, link, point) in found.reversed() {
            let attachment: NSTextAttachment
            if let point {
                attachment = PointChip(point: point, glowing: glowing)
            } else {
                attachment = PhotoAttachment(link: link, url: resolve(link))
            }
            let piece = NSMutableAttributedString(attachment: attachment)
            let whole = NSRange(location: 0, length: piece.length)
            piece.addAttributes(out.attributes(at: range.location, effectiveRange: nil),
                                range: whole)
            piece.addAttribute(point == nil ? photoKey : lineKey, value: link, range: whole)
            out.replaceCharacters(in: range, with: piece)
        }
    }

    /// Есть ли в поле строка-ссылка, ещё не ставшая картинкой: её только
    /// что бросили в текст или вписали руками.
    static func hasLoosePicture(_ text: String) -> Bool {
        guard text.contains("![") || text.contains("geo:") else { return false }
        return text.components(separatedBy: "\n").contains {
            (Diary.picture(in: $0).map { Diary.kind(of: $0) == .photo } ?? false)
                || Geo.point(in: $0) != nil
        }
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate, UITextDropDelegate,
                             UIGestureRecognizerDelegate {
        fileprivate var parent: DiaryEditor

        /// Где лежат снимки — обновляется с каждым обновлением поля.
        var resolve: ((String) -> URL?)?
        /// Нарисованы ли точки со свечением режима изменений.
        var drawnMoving = false

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
            parent.onEditing?(true)
            parent.onFocus()
            // Клавиатура могла подняться раньше — например, человек писал
            // заголовок дня и перешёл в запись. Тогда вестей о ней больше
            // не будет, и место надо освободить самому.
            DispatchQueue.main.async { [weak self] in self?.makeRoom(scroll: true) }
        }

        func textViewDidEndEditing(_ view: UITextView) {
            parent.onEditing?(false)
            scrub()
            makeRoom(scroll: false)
        }

        /// Вычистить из поля знаки-заместители, оставив курсор на месте.
        ///
        /// Зовётся, когда поле отпускает ввод: диктовка к этому времени
        /// кончилась, и поле снова принадлежит нам (решение P197).
        func scrub() {
            guard let view else { return }
            let storage = view.textStorage
            let ns = storage.string as NSString
            var курсор = view.selectedRange
            var i = ns.length - 1
            var changed = false
            storage.beginEditing()
            while i >= 0 {
                // Свои снимки не трогаем: это картинки на месте строк-ссылок.
                if ns.character(at: i) == 0xFFFC,
                   storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) == nil,
                   storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) == nil {
                    storage.deleteCharacters(in: NSRange(location: i, length: 1))
                    if i < курсор.location { курсор.location -= 1 }
                    changed = true
                }
                i -= 1
            }
            storage.endEditing()
            guard changed else { return }
            view.selectedRange = NSRange(
                location: min(курсор.location, storage.length), length: 0)
            parent.text = DiaryEditor.plain(storage)
            restyle(view)
        }

        // MARK: - Касание по снимку и точке

        /// Что оказалось под пальцем в начале касания, и когда.
        private var pressed: (photo: String?, point: GeoPoint?)?
        private var pressedAt = Date.distantPast

        /// Снимок или точка под пальцем.
        private func hit(_ at: CGPoint, in view: UITextView) -> (photo: String?, point: GeoPoint?)? {
            guard let position = view.closestPosition(to: at) else { return nil }
            let storage = view.textStorage
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            for i in [offset, offset - 1] where i >= 0 && i < storage.length {
                guard storage.attribute(.attachment, at: i, effectiveRange: nil) != nil,
                      let start = view.position(from: view.beginningOfDocument, offset: i),
                      let end = view.position(from: start, offset: 1),
                      let range = view.textRange(from: start, to: end),
                      view.firstRect(for: range).insetBy(dx: -4, dy: -4).contains(at)
                else { continue }
                if let link = storage.attribute(DiaryEditor.photoKey, at: i,
                                                effectiveRange: nil) as? String {
                    guard parent.onOpenPhoto != nil else { return nil }
                    return (photo: link, point: nil)
                }
                if let line = storage.attribute(DiaryEditor.lineKey, at: i,
                                                effectiveRange: nil) as? String,
                   let point = Geo.point(in: line) {
                    guard parent.onOpenPoint != nil else { return nil }
                    return (photo: nil, point: point)
                }
            }
            return nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if g is UILongPressGestureRecognizer {
                guard parent.moving, let view else { return false }
                taken = attachment(at: touch.location(in: view), in: view)
                return taken != nil
            }
            guard let view, parent.onOpenPhoto != nil || parent.onOpenPoint != nil else {
                return false
            }
            pressed = hit(touch.location(in: view), in: view)
            pressedAt = Date()
            return pressed != nil
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(g is UILongPressGestureRecognizer)
        }

        // MARK: - Перенос снимка и точки по тексту (P226)

        /// Место в тексте поля, где лежит взятое.
        private var taken: Int?
        /// Картинка взятого, которая идёт за пальцем.
        private var ghost: UIImageView?

        /// Снимок или точка под пальцем — их место в тексте поля.
        private func attachment(at at: CGPoint, in view: UITextView) -> Int? {
            guard let position = view.closestPosition(to: at) else { return nil }
            let storage = view.textStorage
            let offset = view.offset(from: view.beginningOfDocument, to: position)
            for i in [offset, offset - 1] where i >= 0 && i < storage.length {
                guard storage.attribute(.attachment, at: i, effectiveRange: nil) != nil,
                      storage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) != nil
                        || storage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) != nil,
                      let start = view.position(from: view.beginningOfDocument, offset: i),
                      let end = view.position(from: start, offset: 1),
                      let range = view.textRange(from: start, to: end),
                      view.firstRect(for: range).insetBy(dx: -4, dy: -4).contains(at)
                else { continue }
                return i
            }
            return nil
        }

        @objc func carried(_ g: UILongPressGestureRecognizer) {
            guard let view, let i = taken else { return }
            let at = g.location(in: view)
            switch g.state {
            case .began:
                // Прочие жесты поля — лупа, выделение — отпускают палец.
                for other in view.gestureRecognizers ?? [] where other !== g && other.isEnabled {
                    other.isEnabled = false
                    other.isEnabled = true
                }
                let picture = (view.textStorage.attribute(.attachment, at: i, effectiveRange: nil)
                               as? NSTextAttachment)?.image
                let shadow = UIImageView(image: picture)
                shadow.alpha = 0.85
                shadow.layer.shadowOpacity = 0.3
                shadow.layer.shadowRadius = 8
                shadow.center = at
                view.addSubview(shadow)
                ghost = shadow
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .changed:
                ghost?.center = at
            case .ended:
                ghost?.removeFromSuperview()
                ghost = nil
                taken = nil
                if let position = view.closestPosition(to: at) {
                    move(from: i, to: view.offset(from: view.beginningOfDocument, to: position),
                         in: view)
                }
            default:
                ghost?.removeFromSuperview()
                ghost = nil
                taken = nil
            }
        }

        /// Переставить строку снимка или точки: она встаёт своей строкой в
        /// конец абзаца, над которым её отпустили, — как превью из полоски
        /// (P204). Правится текст записи, а поле перерисовывается по нему.
        private func move(from i: Int, to drop: Int, in view: UITextView) {
            let storage = view.textStorage
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(drop, ns.length), length: 0))
            var j = para.location + para.length
            if j > para.location, ns.character(at: j - 1) == 10 { j -= 1 }
            guard j != i, j != i + 1 else { return }

            func plainLength(_ upTo: Int) -> Int {
                (DiaryEditor.plain(storage.attributedSubstring(
                    from: NSRange(location: 0, length: upTo))) as NSString).length
            }
            let piece = DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: i, length: 1)))
            let text = DiaryEditor.plain(storage) as NSString
            var cut = NSRange(location: plainLength(i), length: (piece as NSString).length)
            var target = plainLength(j)
            // Строка уходит вместе со своим переводом строки.
            if cut.location + cut.length < text.length,
               text.character(at: cut.location + cut.length) == 10 {
                cut.length += 1
            } else if cut.location > 0, text.character(at: cut.location - 1) == 10 {
                cut.location -= 1
                cut.length += 1
            }
            if target >= cut.location + cut.length {
                target -= cut.length
            } else if target > cut.location {
                target = cut.location
            }
            let rest = text.replacingCharacters(in: cut, with: "") as NSString
            target = min(target, rest.length)
            let result = rest.replacingCharacters(in: NSRange(location: target, length: 0),
                                                  with: (target == 0 ? "" : "\n") + piece
                                                      + (target == 0 && rest.length > 0 ? "\n" : ""))
            view.attributedText = DiaryEditor.styled(result, size: parent.size, serif: parent.serif,
                                                     stamped: parent.stamped, resolve: resolve,
                                                     glowing: parent.moving)
            view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            loadPhotos()
            parent.text = result
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            // Метка касания не снимается здесь: поле может спросить
            // разрешения писать уже после этого — и должно получить отказ.
            guard g.state == .ended, let got = pressed else { return }
            if let link = got.photo { parent.onOpenPhoto?(link) }
            if let point = got.point { parent.onOpenPoint?(point) }
        }

        /// Касание пришлось на снимок или точку — клавиатура не нужна:
        /// человек открывает, а не пишет. Иначе заодно ставилась бы
        /// отметка времени.
        func textViewShouldBeginEditing(_ view: UITextView) -> Bool {
            !(pressed != nil && Date().timeIntervalSince(pressedAt) < 1.5)
        }

        /// Курсор переставлен — запомнить, где он в тексте записи.
        func textViewDidChangeSelection(_ view: UITextView) {
            guard let report = parent.onCaret else { return }
            let at = min(view.selectedRange.location, view.textStorage.length)
            let before = view.textStorage.attributedSubstring(from: NSRange(location: 0, length: at))
            report((DiaryEditor.plain(before) as NSString).length)
        }

        // MARK: - Снимки

        /// Прочитать с диска картинки снимков, которые пока стоят пустыми
        /// клетками, и поставить их на место.
        func loadPhotos() {
            guard let view else { return }
            let storage = view.textStorage
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                guard let photo = value as? PhotoAttachment, !photo.loaded,
                      let url = photo.url else { return }
                photo.loaded = true
                Task.detached(priority: .userInitiated) {
                    guard let got = Photo.load(url, side: DiaryEditor.photoSize.width) else { return }
                    let framed = PhotoAttachment.frame(got)
                    await MainActor.run { [weak view] in
                        Photo.cache.setObject(framed, forKey: PhotoAttachment.key(url))
                        photo.image = framed
                        guard let view else { return }
                        let storage = view.textStorage
                        storage.enumerateAttribute(.attachment,
                                                   in: NSRange(location: 0, length: storage.length)) { v, r, stop in
                            guard (v as? PhotoAttachment) === photo else { return }
                            // Та же вложенная картинка кладётся заново — и поле
                            // перерисовывает её клетку.
                            storage.beginEditing()
                            storage.addAttribute(.attachment, value: photo, range: r)
                            storage.endEditing()
                            stop.pointee = true
                        }
                    }
                }
            }
        }

        /// Куда встанет брошенное превью: в конец абзаца, над которым его
        /// отпустили. Снимок стоит своей строкой и не рвёт фразу пополам.
        func textDroppableView(_ droppable: UIView & UITextDroppable,
                               positionForDrop drop: UITextDropRequest) -> UITextPosition {
            guard let view = droppable as? UITextView else { return drop.dropPosition }
            let ns = view.text as NSString
            let at = min(view.offset(from: view.beginningOfDocument, to: drop.dropPosition),
                         ns.length)
            let para = ns.paragraphRange(for: NSRange(location: at, length: 0))
            var end = para.location + para.length
            if end > para.location, ns.character(at: end - 1) == 10 { end -= 1 }
            return view.position(from: view.beginningOfDocument, offset: end) ?? drop.dropPosition
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
            let now = DiaryEditor.plain(view.attributedText)
            parent.text = now
            if resolve != nil, DiaryEditor.hasLoosePicture(view.text) {
                // Строку-ссылку только что бросили или вписали — рисуем её
                // картинкой. Курсор остаётся примерно там, где был.
                let at = view.selectedRange.location
                view.attributedText = DiaryEditor.styled(now, size: parent.size,
                                                         serif: parent.serif,
                                                         stamped: parent.stamped,
                                                         resolve: resolve,
                                                         glowing: parent.moving)
                view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
                view.selectedRange = NSRange(location: min(at, view.textStorage.length), length: 0)
                loadPhotos()
            } else {
                restyle(view)
            }
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
                  line.range(of: #"^\d{2}:\d{2}( \d{2}\.\d{2}\.\d{2})?[  ]+$"#,
                             options: .regularExpression) != nil
            else { return true }

            let upper = String(first).uppercased() + String(text.dropFirst())
            // Правка — в самом тексте поля, а не заменой всего текста:
            // иначе снимки в нём превратились бы в знаки-заместители.
            view.textStorage.replaceCharacters(in: range, with: upper)
            let after = range.location + (upper as NSString).length
            view.selectedRange = NSRange(location: after, length: 0)
            parent.text = DiaryEditor.plain(view.attributedText)
            restyle(view)
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
                if let place = DiaryEditor.placeRange(in: ns, line: line) {
                    storage.addAttributes(DiaryEditor.placeLook(parent.size), range: place)
                }
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

/// Точка в тексте записи: кнопочка с названием и координатами, бледная,
/// как отметка времени (P213).
final class PointChip: NSTextAttachment {

    init(point: GeoPoint, glowing: Bool = false) {
        super.init(data: nil, ofType: nil)
        let picture = PointChip.draw(point.label, glowing: glowing)
        image = picture
        bounds = CGRect(origin: CGPoint(x: 0, y: glowing ? -12 : -7), size: picture.size)
    }

    required init?(coder: NSCoder) { nil }

    /// В режиме изменений точка светится, как превью снимков (P241).
    static func draw(_ label: String, glowing: Bool = false) -> UIImage {
        let font = UIFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let ink = UIColor(Look.inkFaint)
        let words = [NSAttributedString.Key.font: font, .foregroundColor: ink]
        let pin = UIImage(systemName: "mappin.and.ellipse",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))?
            .withTintColor(ink, renderingMode: .alwaysOriginal)
        let wide = min((label as NSString).size(withAttributes: words).width, 250)
        let chip = CGSize(width: 10 + 14 + 5 + wide + 10, height: 24)
        let pad: CGFloat = glowing ? 5 : 0
        let size = CGSize(width: chip.width + pad * 2, height: chip.height + pad * 2)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let box = CGRect(x: pad, y: pad, width: chip.width, height: chip.height)
                .insetBy(dx: 0.5, dy: 0.5)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 12)
            if glowing {
                ctx.cgContext.setShadow(offset: .zero, blur: 5, color: UIColor(Look.glow).cgColor)
            }
            UIColor(Look.chrome).setFill()
            shape.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(glowing ? Look.glow : Look.rule).setStroke()
            shape.lineWidth = glowing ? 2 : 1
            shape.stroke()
            pin?.draw(in: CGRect(x: pad + 10, y: pad + 5, width: 14, height: 14))
            (label as NSString).draw(
                with: CGRect(x: pad + 29, y: (size.height - font.lineHeight) / 2,
                             width: wide, height: font.lineHeight),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: words, context: nil)
        }
    }
}

/// Снимок в тексте записи.
///
/// Помнит свою строку-ссылку: по ней поле возвращает в файл ту же строку,
/// какая там и была (решение P204).
final class PhotoAttachment: NSTextAttachment {

    let link: String
    let url: URL?
    /// Картинку уже прочитали или читают — второй раз не надо.
    var loaded = false

    init(link: String, url: URL?) {
        self.link = link
        self.url = url
        super.init(data: nil, ofType: nil)
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: DiaryEditor.photoSize)
        if let url, let cached = Photo.cache.object(forKey: PhotoAttachment.key(url)) {
            image = cached
            loaded = true
        } else {
            image = PhotoAttachment.empty
        }
    }

    required init?(coder: NSCoder) { nil }

    static func key(_ url: URL) -> NSString { ("в тексте:" + url.path) as NSString }

    /// Пустая клетка, пока картинка идёт с диска.
    static let empty: UIImage = UIGraphicsImageRenderer(size: DiaryEditor.photoSize).image { _ in
        let box = CGRect(origin: .zero, size: DiaryEditor.photoSize)
        UIColor(Look.chrome).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 8).fill()
    }

    /// Снимок, обрезанный по клетке и со скруглёнными углами.
    static func frame(_ image: UIImage) -> UIImage {
        let size = DiaryEditor.photoSize
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: box, cornerRadius: 8).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2,
                                  width: w, height: h))
        }
    }
}
