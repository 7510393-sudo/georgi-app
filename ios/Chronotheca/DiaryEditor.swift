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

    /// Пустое место под текстом внутри самого поля: касание туда ставит
    /// курсор в конец записи — открыл, коснулся, пишешь (P346).
    var room: CGFloat = 0

    /// Где лежит снимок, на который ссылается строка `![](…)`. Задано —
    /// значит поле рисует такие строки картинками (решение P204).
    var resolve: ((String) -> URL?)?

    /// Касание по снимку в тексте — открыть его (P216). Пусто — снимки не
    /// открываются: так на соседних страницах.
    var onOpenPhoto: ((String) -> Void)?
    /// Снимок из текста отпустили над полоской внизу — вернуть его туда
    /// (P272). Пусто — возвращать некуда.
    var onReturnPhoto: ((String) -> Void)?
    /// Касание по точке в тексте — открыть карту на ней (P213).
    var onOpenPoint: ((GeoPoint) -> Void)?
    /// Точку из текста отпустили над заголовком дня — она переходит туда
    /// (P358). Строка точки, как в файле.
    var onPointToTitle: ((String) -> Void)?

    /// Где на экране заголовок дня открытой страницы — туда можно бросить
    /// точку из текста (P358). Пусто — заголовка не видно.
    static var titleZone: CGRect = .null
    /// Курсор переставлен: где он теперь, отступом в тексте записи. Туда
    /// встанет точка с карты (P213).
    var onCaret: ((Int) -> Void)?
    /// Снимок или точку в тексте можно взять долгим нажатием и перенести
    /// в другое место записи (P226) — без всякого режима (P362). Вид от
    /// этого не меняется: соседняя страница рисуется так же (P114).
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
        // Полоска вложений — приставкой к клавиатуре, только у записи
        // дня (P279). Подробности дела живут в своём окне.
        if grows { view.inputAccessoryView = KeyboardBar.view }
        // Превью из полоски бросают прямо в текст (решение P204).
        view.textDropDelegate = context.coordinator
        // Своё перетаскивание поля выключено (P374): оно перехватывало
        // долгое нажатие на снимок или точку, поднимало свою копию и, не
        // найдя, куда её положить, возвращало назад. Переносит только своё
        // долгое нажатие — с раздвиганием текста.
        view.textDragInteraction?.isEnabled = false
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

    /// Поле записи открытого дня — в него несут из полоски (P380).
    static weak var active: Coordinator?

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if editable && grows { DiaryEditor.active = context.coordinator }
        view.isEditable = editable
        view.isSelectable = editable
        context.coordinator.resolve = resolve

        // Поле сверяется с записью без знаков-заместителей. Пока идёт
        // диктовка, система держит в поле свой временный знак; переписать
        // из-за него поле — вырвать знак у неё из рук, и он остаётся в
        // тексте «OBJ» (решение P197).
        if context.coordinator.previewing {
            // Идёт перенос — в поле показано, как ляжет взятое; запись
            // поменяется, когда палец отпустят.
        } else if DiaryEditor.plain(view.attributedText) != text || view.attributedText.length == 0 {
            let selection = view.selectedRange
            view.attributedText = Self.styled(text, size: size, serif: serif, stamped: stamped,
                                              resolve: resolve)
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
            // Сбрасываем просьбу сразу. Фокус берём не здесь же, а на
            // следующем обороте: `becomeFirstResponder` внутри этого же
            // прохода перерисовки зовёт `onFocus` (он ставит отметку
            // времени) прямо сейчас, но запись обновится только со
            // следующим проходом — а он поверх свежего текста восстановит
            // старое, ещё безвременное место курсора. Вне прохода перерисовки
            // отметка и перевод курсора в конец успевают попасть в один и
            // тот же, уже свежий проход (P302).
            startEditing.wrappedValue = false
            DispatchQueue.main.async { view.becomeFirstResponder() }
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
        return CGSize(width: width,
                      height: max(minHeight, занято.height.rounded(.up) + room))
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
            ? Prefs.serifUIFont(size)
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
    /// Снимок в тексте — в пять строк дневника высотой и столько же в
    /// ширину (P383; прежде — как превью в поиске, 86, P348). Тот же
    /// размер — у снимков под делами плана и в полоске внизу страницы.
    static let photoSize = CGSize(width: 114, height: 114)

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
                // Точкой становится только сама кнопочка. Буква, набранная
                // вплотную за ней, могла унаследовать метку, — она остаётся
                // буквой (P256).
                var chips = 0
                for ch in ns.substring(with: range) {
                    if ch == placeholder {
                        out += (chips > 0 ? "\n" : "") + line
                        chips += 1
                    } else {
                        out += String(ch)
                        chips = 0
                    }
                }
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
            let row = Diary.pictures(in: content)
            if let link = Diary.picture(in: content), Diary.kind(of: link) == .photo {
                found.append((range, link, nil))
            } else if Diary.picture(in: content) != nil {
                // Голос, видео, документ своей строкой — кнопочкой с
                // именем, как точка (P377). В файле — та же строка.
                found.append((range, content, nil))
            } else if row.count > 1 {
                // Несколько снимков в одной строке — рядом, через пробел
                // (P348). Каждый — своей картинкой, пробел остаётся.
                for piece in row where Diary.kind(of: piece.link) == .photo {
                    found.append((NSRange(location: line.location + piece.range.location,
                                          length: piece.range.length), piece.link, nil))
                }
            } else if let point = Geo.point(in: content) {
                found.append((range, content, point))
            } else if content.contains("geo:") {
                // Точка посреди строки — тоже кнопочка (P256).
                for (r, point) in Geo.points(inText: content) {
                    found.append((NSRange(location: line.location + r.location, length: r.length),
                                  (content as NSString).substring(with: r), point))
                }
            }
            // Снимок посреди фразы — тоже картинка, а не буквы (P357): так
            // он мог лечь при переносе, и выглядеть набором цифр не должен.
            if Diary.picture(in: content) == nil, row.count < 2 {
                for piece in Diary.anywhere(in: content) where Diary.kind(of: piece.link) == .photo {
                    found.append((NSRange(location: line.location + piece.range.location,
                                          length: piece.range.length), piece.link, nil))
                }
            }
            guard line.length > 0 else { break }
            start = line.location + line.length
        }
        // С конца к началу: замена не сдвигает того, что ещё впереди.
        for (range, link, point) in found.sorted(by: { $0.0.location < $1.0.location }).reversed() {
            let attachment: NSTextAttachment
            let file = point == nil && Diary.picture(in: link).map { Diary.kind(of: $0) != .photo } == true
            if let point {
                attachment = PointChip(mini: point, glowing: glowing)
            } else if file, let inner = Diary.picture(in: link) {
                attachment = FileChip(link: inner)
            } else {
                attachment = PhotoAttachment(link: link, url: resolve(link))
            }
            let piece = NSMutableAttributedString(attachment: attachment)
            let whole = NSRange(location: 0, length: piece.length)
            piece.addAttributes(out.attributes(at: range.location, effectiveRange: nil),
                                range: whole)
            piece.addAttribute(point == nil && !file ? photoKey : lineKey, value: link, range: whole)
            out.replaceCharacters(in: range, with: piece)
        }
    }

    /// Снимок из полоски бросили на строку, где уже стоят снимки, — он
    /// встаёт рядом с ними в ту же строку, а не новой строкой под ними
    /// (P348). `was` — запись до броска; `nil` — ставить рядом не с чем.
    static func besideDropped(_ now: String, was: String) -> String? {
        let old = was.components(separatedBy: "\n")
        var new = now.components(separatedBy: "\n")
        guard new.count == old.count + 1 else { return nil }
        var k = 0
        while k < old.count, new[k] == old[k] { k += 1 }
        guard k > 0, k < new.count,
              let one = Diary.picture(in: new[k]), Diary.kind(of: one) == .photo
        else { return nil }
        let row = Diary.links(in: new[k - 1])
        guard !row.isEmpty, row.allSatisfy({ Diary.kind(of: $0) == .photo }) else { return nil }
        new[k - 1] = new[k - 1].trimmingCharacters(in: .whitespaces) + " "
            + new[k].trimmingCharacters(in: .whitespaces)
        new.remove(at: k)
        return new.joined(separator: "\n")
    }

    private static let fileLink = try! NSRegularExpression(
        pattern: #"(?<!!)\[[^\]\n]*\]\((<[^>\n]+>|[^)\s]+)\)"#)

    /// Ссылка на голос, видео или документ посреди строки — на свою строку.
    /// `nil` — таких нет.
    static func ownLine(_ text: String) -> String? {
        guard text.contains("](") else { return nil }
        var changed = false
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let ns = line as NSString
            guard Diary.picture(in: line) == nil else { out.append(line); continue }
            let found = fileLink.matches(in: line, range: NSRange(location: 0, length: ns.length))
                .filter { m in
                    var link = ns.substring(with: m.range(at: 1))
                    if link.hasPrefix("<") { link = String(link.dropFirst().dropLast()) }
                    return !link.contains("://") && !link.hasPrefix("geo:")
                        && Diary.kind(of: link) != .photo
                }
            guard !found.isEmpty else { out.append(line); continue }
            changed = true
            var from = 0
            for m in found {
                let before = ns.substring(with: NSRange(location: from, length: m.range.location - from))
                    .trimmingCharacters(in: .whitespaces)
                if !before.isEmpty { out.append(before) }
                out.append(ns.substring(with: m.range))
                from = NSMaxRange(m.range)
            }
            let rest = ns.substring(from: from).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { out.append(rest) }
        }
        return changed ? out.joined(separator: "\n") : nil
    }

    /// Поставить вложение своей строкой за абзацем, где `drop` (в тексте
    /// записи); снимок к снимкам — рядом в ту же строку (P348, P380).
    /// Возвращает текст и где стоит вложение.
    static func putting(_ piece: String, at drop: Int, into text: String) -> (String, Int) {
        let ns = text as NSString
        guard ns.length > 0 else { return (piece, 0) }
        let spot = min(max(drop, 0), ns.length)
        let para = ns.paragraphRange(for: NSRange(location: min(spot, ns.length - 1), length: 0))
        var j = para.location + para.length
        if j > para.location, ns.character(at: j - 1) == 10 { j -= 1 }
        let above = ns.substring(with: NSRange(location: para.location, length: j - para.location))
            .trimmingCharacters(in: .whitespaces)
        if above.isEmpty {
            let out = ns.replacingCharacters(in: NSRange(location: para.location,
                                                         length: j - para.location), with: piece)
            return (out, para.location)
        }
        let isPhoto = { (s: String) in
            !Diary.links(in: s).isEmpty && Diary.links(in: s).allSatisfy { Diary.kind(of: $0) == .photo }
        }
        let lead = isPhoto(piece) && isPhoto(above) ? " " : "\n"
        let out = ns.replacingCharacters(in: NSRange(location: j, length: 0), with: lead + piece)
        return (out, j + (lead as NSString).length)
    }

    /// Есть ли в поле строка-ссылка, ещё не ставшая картинкой: её только
    /// что бросили в текст или вписали руками.
    static func hasLoosePicture(_ text: String) -> Bool {
        guard text.contains("![") || text.contains("geo:") || text.contains("](") else { return false }
        return text.components(separatedBy: "\n").contains {
            Diary.picture(in: $0) != nil
                || Diary.pictures(in: $0).contains { Diary.kind(of: $0.link) == .photo }
                || Diary.anywhere(in: $0).contains { Diary.kind(of: $0.link) == .photo }
                || Geo.point(in: $0) != nil
                // Посреди строки — когда точка дописана: за ней пробел или
                // она в скобках с названием. Иначе кнопочкой стали бы
                // цифры, которые ещё набирают (P256).
                || $0.range(of: #"\]\(geo:[^)\s]+\)|geo:-?\d+(\.\d+)?,\s?-?\d+(\.\d+)?\s"#,
                            options: .regularExpression) != nil
        }
    }

    // MARK: - Поведение

    final class Coordinator: NSObject, UITextViewDelegate, UITextDropDelegate,
                             UIGestureRecognizerDelegate {
        fileprivate var parent: DiaryEditor

        /// Где лежат снимки — обновляется с каждым обновлением поля.
        var resolve: ((String) -> URL?)?
        /// До какого мига поле, взявшее ввод, не ставит отметку времени:
        /// в запись принесли снимок или переставили точку, а не пишут
        /// дальше (прежде это делал режим изменений, P362).
        private var quietUntil = Date.distantPast

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
            if Date() > quietUntil { parent.onFocus() }
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
                // Голос или файл в тексте — открыть, как из полоски (P377).
                if let line = storage.attribute(DiaryEditor.lineKey, at: i,
                                                effectiveRange: nil) as? String,
                   let link = Diary.picture(in: line) {
                    guard parent.onOpenPhoto != nil else { return nil }
                    return (photo: link, point: nil)
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
        private var ghost: UIView?

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

        /// Взятое идёт над пальцем, а не под ним: иначе палец закрывает его
        /// целиком и тащить приходится вслепую (P349). Ложится оно тоже туда,
        /// где видно, — над пальцем.
        private static let lift: CGFloat = 48

        /// Тонкая синяя черта там, куда ляжет взятое (P358): палец и
        /// поднятая над ним картинка не дают увидеть место точно.
        private var mark: UIView?

        /// Взята точка, а не снимок.
        private func takenIsPoint(_ view: UITextView) -> Bool {
            guard let i = taken else { return false }
            return takenIsPoint(at: i, in: view)
        }

        private func takenIsPoint(at i: Int, in view: UITextView) -> Bool {
            guard i < view.textStorage.length else { return false }
            guard let line = view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                        effectiveRange: nil) as? String
            else { return false }
            return Geo.point(in: line) != nil
                && view.textStorage.attribute(DiaryEditor.photoKey, at: i, effectiveRange: nil) == nil
        }

        // MARK: - Крестик у точки (P362)

        /// Покрывало поверх окна: на нём точка крупнее и крестик. Касание
        /// мимо крестика — покрывало уходит, и всё как было.
        private var cover: UIView?

        /// Показать точку крупнее, с крестиком «удалить» на углу — как
        /// значок на экране «Домой», когда его подержали.
        private func arm(_ i: Int, in view: UITextView) {
            guard let window = view.window,
                  let line = view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                        effectiveRange: nil) as? String,
                  let picture = (view.textStorage.attribute(.attachment, at: i, effectiveRange: nil)
                                 as? NSTextAttachment)?.image,
                  let start = view.position(from: view.beginningOfDocument, offset: i),
                  let end = view.position(from: start, offset: 1),
                  let range = view.textRange(from: start, to: end)
            else { return }
            disarm()
            Feel.light()
            let place = view.convert(view.firstRect(for: range), to: window)
            let veil = UIControl(frame: window.bounds)
            veil.backgroundColor = UIColor.black.withAlphaComponent(0.06)
            veil.addTarget(self, action: #selector(disarm), for: .touchDown)
            // Строка точки — в тонкой синей рамке во всю ширину текста (P380).
            let field = view.convert(view.bounds, to: window)
            let row = UIView(frame: CGRect(x: field.minX - 6, y: place.minY - 10,
                                           width: field.width + 12, height: place.height + 20))
            row.layer.borderColor = UIColor(Look.glow).cgColor
            row.layer.borderWidth = 1.5
            row.layer.cornerRadius = 9
            row.backgroundColor = UIColor(Look.planBg).withAlphaComponent(0.55)
            row.isUserInteractionEnabled = false
            veil.addSubview(row)
            let chip = UIImageView(image: picture)
            chip.center = CGPoint(x: place.midX, y: place.midY)
            // Синяя кромка — та же, что у поднятого дела (P374).
            chip.layer.borderColor = UIColor(Look.glow).cgColor
            chip.layer.borderWidth = 2
            chip.layer.cornerRadius = picture.size.height / 2
            chip.layer.shadowOpacity = 0.25
            chip.layer.shadowRadius = 6
            chip.layer.shadowOffset = CGSize(width: 0, height: 2)
            veil.addSubview(chip)
            let grow: CGFloat = 1.4
            let cross = UIButton(type: .custom)
            // Крестик вдвое крупнее прежнего — его видно и пальцем не
            // промахнуться (P380).
            let symbol = UIImage(systemName: "xmark.circle.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)
                                     .applying(UIImage.SymbolConfiguration(
                                        paletteColors: [.white, UIColor(Look.pin)])))
            cross.setImage(symbol, for: .normal)
            cross.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
            cross.center = CGPoint(x: min(place.midX + picture.size.width * grow / 2 + 22, field.maxX - 10),
                                   y: place.midY)
            cross.accessibilityLabel = T("Удалить точку", "Delete place")
            cross.addAction(UIAction { [weak self, weak view] _ in
                guard let self, let view else { return }
                self.disarm()
                // Удаляется та самая точка, если она ещё на своём месте.
                guard i < view.textStorage.length,
                      view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                 effectiveRange: nil) as? String == line
                else { return }
                Feel.light()
                self.remove(at: i, in: view)
            }, for: .touchUpInside)
            cross.alpha = 0
            veil.addSubview(cross)
            window.addSubview(veil)
            cover = veil
            UIView.animate(withDuration: 0.15) {
                chip.transform = CGAffineTransform(scaleX: grow, y: grow)
                cross.alpha = 1
            }
        }

        @objc private func disarm() {
            cover?.removeFromSuperview()
            cover = nil
        }

        /// Точка над заголовком дня — отпустить здесь значит перенести её в
        /// заголовок (P358).
        private func overTitle(_ g: UIGestureRecognizer, in view: UITextView) -> Bool {
            guard takenIsPoint(view), let window = view.window,
                  !DiaryEditor.titleZone.isNull else { return false }
            let spot = g.location(in: window)
            let lifted = CGPoint(x: spot.x, y: spot.y - Self.lift)
            return DiaryEditor.titleZone.insetBy(dx: -8, dy: -10).contains(lifted)
        }

        /// Показать, куда ляжет взятое: точка — ровно в место под картинкой,
        /// снимок — в конец абзаца под ней.
        private func showMark(at at: CGPoint, in view: UITextView, hidden: Bool) {
            guard !hidden, let window = view.window, let position = view.closestPosition(to: at)
            else { mark?.isHidden = true; return }
            var spot = position
            do {
                let ns = view.textStorage.string as NSString
                let offset = min(view.offset(from: view.beginningOfDocument, to: position), ns.length)
                let para = ns.paragraphRange(for: NSRange(location: offset, length: 0))
                var end = para.location + para.length
                if end > para.location, ns.character(at: end - 1) == 10 { end -= 1 }
                spot = view.position(from: view.beginningOfDocument, offset: end) ?? position
            }
            let rect = view.convert(view.caretRect(for: spot), to: window)
            let bar = mark ?? {
                let v = UIView()
                v.backgroundColor = UIColor(Look.glow)
                v.layer.cornerRadius = 1.5
                v.isUserInteractionEnabled = false
                window.addSubview(v)
                self.mark = v
                return v
            }()
            bar.isHidden = false
            bar.frame = CGRect(x: rect.minX - 1.5, y: rect.minY - 2, width: 3, height: rect.height + 4)
        }

        /// Палец со взятым снимком ниже страницы — над полоской превью:
        /// отпустить здесь значит вернуть снимок вниз (P272, P349).
        private func overStrip(_ g: UIGestureRecognizer, in view: UITextView) -> Bool {
            guard let window = view.window, let page = page(over: view),
                  view.textStorage.attribute(DiaryEditor.photoKey, at: taken ?? 0,
                                             effectiveRange: nil) != nil
            else { return false }
            // Считается сам палец, а не поднятая над ним картинка: её край
            // уже над полоской, когда палец ещё на странице.
            return g.location(in: window).y > page.convert(page.bounds, to: window).maxY - 24
        }

        /// Где палец взял снимок или точку — в окне.
        private var takenAt: CGPoint = .zero
        /// Когда отпустили долгое нажатие — касание в тот же миг не считается.
        private var heldEnded = Date.distantPast
        /// Идёт перенос: в поле уже показано, как ляжет взятое (P374).
        fileprivate(set) var previewing = false
        /// Поле до переноса — чтобы вернуть его, если перенос отменили.
        private var before: NSAttributedString?
        /// Где взятое стоит сейчас — в показанном поле.
        private var now: Int?
        /// Над пальцем едет строка, а не картинка (точка, голос, файл).
        private var ghostLine = false
        /// Запись, как она станет после переноса.
        private var result: String?

        @objc func carried(_ g: UILongPressGestureRecognizer) {
            guard let view, let i = taken else { return }
            let finger = g.location(in: view)
            let at = CGPoint(x: finger.x, y: finger.y - Self.lift)
            quietUntil = Date().addingTimeInterval(1.5)
            switch g.state {
            case .began:
                takenAt = g.location(in: nil)
                disarm()
                // Прочие жесты поля — лупа, выделение — отпускают палец.
                for other in view.gestureRecognizers ?? [] where other !== g && other.isEnabled {
                    other.isEnabled = false
                    other.isEnabled = true
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                // Точка — сразу крупнее и с крестиком, ещё под пальцем
                // (P374): «удалить» видно, не отпуская. Повели — крестик
                // уходит, точка идёт за пальцем.
                if takenIsPoint(at: i, in: view) { arm(i, in: view) } else { lift(i, g, in: view) }
            case .changed:
                let spot = g.location(in: nil)
                if ghost == nil {
                    guard hypot(spot.x - takenAt.x, spot.y - takenAt.y) >= 10 else { return }
                    disarm()
                    lift(i, g, in: view)
                }
                let local = g.location(in: ghost?.superview ?? view)
                ghost?.center = CGPoint(x: ghostLine ? (ghost?.center.x ?? local.x) : local.x,
                                        y: local.y - Self.lift)
                // Над полоской снимок бледнеет — видно, что отпустить здесь
                // значит вернуть его вниз; над заголовком — то же для точки.
                let away = overStrip(g, in: view) || overTitle(g, in: view)
                ghost?.alpha = away ? 0.5 : 0.9
                if away { restore(view) } else { preview(at, in: view) }
            case .ended:
                heldEnded = Date()
                let back = overStrip(g, in: view)
                let up = overTitle(g, in: view)
                let moved = ghost != nil
                ghost?.removeFromSuperview()
                ghost = nil
                mark?.removeFromSuperview()
                mark = nil
                // Подержали и отпустили, не сдвинув: точка так и стоит
                // крупнее, с крестиком; снимок — на месте.
                guard moved else {
                    taken = nil
                    return
                }
                let done = result
                restore(view)
                taken = nil
                // Точку отпустили над заголовком дня — она уходит туда (P358).
                if up, let line = view.textStorage.attribute(DiaryEditor.lineKey, at: i,
                                                             effectiveRange: nil) as? String,
                   Geo.point(in: line) != nil,
                   let toTitle = parent.onPointToTitle {
                    remove(at: i, in: view)
                    Feel.light()
                    toTitle(line)
                    return
                }
                // Отпустили ниже страницы, над полоской превью — снимок
                // возвращается туда, откуда его взяли (P272).
                if back, let link = (view.textStorage.attribute(DiaryEditor.photoKey, at: i,
                                                                effectiveRange: nil) as? String)
                    ?? (view.textStorage.attribute(DiaryEditor.lineKey, at: i, effectiveRange: nil) as? String)
                        .flatMap(Diary.picture(in:)),
                   let giveBack = parent.onReturnPhoto {
                    Feel.light()
                    giveBack(link)
                    return
                }
                // Встаёт туда, где его только что показывали.
                if let done {
                    Feel.light()
                    show(done, in: view)
                    parent.text = done
                }
            default:
                heldEnded = Date()
                ghost?.removeFromSuperview()
                ghost = nil
                mark?.removeFromSuperview()
                mark = nil
                restore(view)
                taken = nil
            }
        }

        /// Поднять взятое над пальцем — с синей кромкой (P374).
        private func lift(_ i: Int, _ g: UIGestureRecognizer, in view: UITextView) {
            let picture = (view.textStorage.attribute(.attachment, at: i, effectiveRange: nil)
                           as? NSTextAttachment)?.image
            let shadow = UIImageView(image: picture)
            shadow.alpha = 0.9
            shadow.layer.shadowOpacity = 0.3
            shadow.layer.shadowRadius = 8
            shadow.layer.borderColor = UIColor(Look.glow).cgColor
            shadow.layer.borderWidth = 2.6
            shadow.layer.cornerRadius = min(8, (picture?.size.height ?? 0) / 2)
            // Точка — маленькая кнопочка: над пальцем она крупнее, чтобы
            // её было видно (P349).
            let small = (picture?.size.height ?? 0) < 40
            shadow.transform = CGAffineTransform(scaleX: small ? 1.8 : 1.1, y: small ? 1.8 : 1.1)
            // Тень снимка — поверх всего окна: её можно донести и до
            // полоски внизу, за край страницы (P272).
            let host: UIView = view.window ?? view
            let spot = g.location(in: host)
            if small {
                // Точка, голос, файл — строкой (P380): над пальцем едет вся
                // строка в синей рамке, во всю ширину текста.
                let field = view.convert(view.bounds, to: host)
                let size = picture?.size ?? .zero
                let row = UIView(frame: CGRect(x: 0, y: 0, width: field.width + 12, height: size.height * 1.3 + 16))
                row.backgroundColor = UIColor(Look.planBg).withAlphaComponent(0.95)
                row.layer.borderColor = UIColor(Look.glow).cgColor
                row.layer.borderWidth = 2
                row.layer.cornerRadius = 9
                row.layer.shadowOpacity = 0.25
                row.layer.shadowRadius = 8
                let chip = UIImageView(image: picture)
                chip.frame = CGRect(x: 6, y: 8, width: size.width * 1.3, height: size.height * 1.3)
                row.addSubview(chip)
                row.center = CGPoint(x: field.midX, y: spot.y - Self.lift)
                host.addSubview(row)
                ghost = row
                ghostLine = true
            } else {
                shadow.center = CGPoint(x: spot.x, y: spot.y - Self.lift)
                host.addSubview(shadow)
                ghost = shadow
                ghostLine = false
            }
            before = view.attributedText.copy() as? NSAttributedString
            now = i
            result = nil
            previewing = true
        }

        /// Показать в поле, как ляжет взятое, если отпустить палец здесь:
        /// текст раздвигается, строки расходятся (P374).
        private func preview(_ at: CGPoint, in view: UITextView) {
            guard let current = now, let position = view.closestPosition(to: at) else { return }
            let drop = view.offset(from: view.beginningOfDocument, to: position)
            guard let next = placed(from: current, to: drop, in: view.textStorage),
                  next.0 != result
            else { return }
            result = next.0
            show(next.0, in: view)
            now = DiaryEditor.viewOffset(plain: next.1, in: view.attributedText)
        }

        // MARK: - Из полоски в текст (P380)

        /// Снимок, голос или файл из полоски несут над полем: текст
        /// расступается там, куда он ляжет. `false` — палец не над полем.
        @discardableResult
        func carryIn(_ piece: String, at global: CGPoint) -> Bool {
            guard let view, let window = view.window else { return false }
            let local = view.convert(global, from: window)
            guard view.bounds.insetBy(dx: -10, dy: -30).contains(local) else {
                carryOut()
                return false
            }
            let at = CGPoint(x: local.x, y: local.y - Self.lift)
            quietUntil = Date().addingTimeInterval(1.5)
            if result == nil {
                guard let position = view.closestPosition(to: at) else { return true }
                let drop = min(view.offset(from: view.beginningOfDocument, to: position),
                               view.textStorage.length)
                let plainDrop = (DiaryEditor.plain(view.attributedText.attributedSubstring(
                    from: NSRange(location: 0, length: drop))) as NSString).length
                before = view.attributedText.copy() as? NSAttributedString
                previewing = true
                let next = DiaryEditor.putting(piece, at: plainDrop,
                                               into: DiaryEditor.plain(view.attributedText))
                result = next.0
                show(next.0, in: view)
                now = DiaryEditor.viewOffset(plain: next.1, in: view.attributedText)
            } else {
                preview(at, in: view)
            }
            return true
        }

        /// Палец ушёл с поля — текст, каким был.
        func carryOut() {
            guard let view, previewing, taken == nil else { return }
            restore(view)
        }

        /// Отпустили над полем — вложение встаёт туда, где его показывали.
        @discardableResult
        func carryEnd() -> Bool {
            guard let view, previewing, taken == nil, let done = result else {
                carryOut()
                return false
            }
            restore(view)
            show(done, in: view)
            parent.text = done
            return true
        }

        /// Вернуть поле, каким оно было до переноса.
        private func restore(_ view: UITextView) {
            if let before, result != nil {
                view.attributedText = before
                view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
                loadPhotos()
            }
            before = nil
            result = nil
            now = taken
            previewing = false
        }

        private func show(_ text: String, in view: UITextView) {
            view.attributedText = DiaryEditor.styled(text, size: parent.size, serif: parent.serif,
                                                     stamped: parent.stamped, resolve: resolve)
            view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            loadPhotos()
        }

        /// Убрать точку из текста — вместе с пробелом рядом, а если она
        /// стояла своей строкой — с этой строкой (P358).
        private func remove(at i: Int, in view: UITextView) {
            let storage = view.textStorage
            let start = (DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: 0, length: i))) as NSString).length
            let piece = DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: i, length: 1)))
            let text = DiaryEditor.plain(storage) as NSString
            var cut = NSRange(location: start, length: (piece as NSString).length)
            let after = NSMaxRange(cut) < text.length ? text.character(at: NSMaxRange(cut)) : 10
            let before = cut.location > 0 ? text.character(at: cut.location - 1) : 10
            if after == 32 || (after == 10 && before == 10 && NSMaxRange(cut) < text.length) {
                cut.length += 1
            } else if before == 32 || before == 10 && cut.location > 0 {
                cut.location -= 1
                cut.length += 1
            }
            let result = text.replacingCharacters(in: cut, with: "")
            view.attributedText = DiaryEditor.styled(result, size: parent.size, serif: parent.serif,
                                                     stamped: parent.stamped, resolve: resolve)
            view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            loadPhotos()
            parent.text = result
        }

        /// Куда ляжет снимок или точка, если отпустить их здесь: запись после
        /// переноса и где в ней (в буквах записи) стоит взятое. `nil` — с
        /// места не сдвинется.
        ///
        /// Точка — значок в строке: встаёт ровно туда, где отпустили, посреди
        /// текста (P259). Снимок встаёт своей строкой в конец абзаца — или
        /// рядом со снимками, если над ними (P204, P348, P357).
        private func placed(from i: Int, to drop: Int,
                            in storage: NSAttributedString) -> (String, Int)? {
            let ns = storage.string as NSString
            guard i < storage.length else { return nil }
            func plainLength(_ upTo: Int) -> Int {
                (DiaryEditor.plain(storage.attributedSubstring(
                    from: NSRange(location: 0, length: upTo))) as NSString).length
            }
            let piece = DiaryEditor.plain(storage.attributedSubstring(
                from: NSRange(location: i, length: 1)))
            let text = DiaryEditor.plain(storage) as NSString

            // Точка, как и снимок, встаёт только своей строкой (P380): строку
            // текста она больше не рвёт.
            let para = ns.paragraphRange(for: NSRange(location: min(drop, ns.length), length: 0))
            var j = para.location + para.length
            if j > para.location, ns.character(at: j - 1) == 10 { j -= 1 }
            guard j != i, j != i + 1 else { return nil }
            var cut = NSRange(location: plainLength(i), length: (piece as NSString).length)
            var target = plainLength(j)
            let after = NSMaxRange(cut) < text.length ? text.character(at: NSMaxRange(cut)) : 10
            let before = cut.location > 0 ? text.character(at: cut.location - 1) : 10
            // Снимок из ряда (P348) уходит со своим пробелом, ряд остаётся
            // строкой; одинокий снимок — со своим переводом строки.
            if before == 32 {
                cut.location -= 1
                cut.length += 1
            } else if after == 32 {
                cut.length += 1
            } else if NSMaxRange(cut) < text.length, after == 10 {
                cut.length += 1
            } else if cut.location > 0, before == 10 {
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
            // Отпустили над строкой, где уже стоят снимки, — встаёт рядом с
            // ними, в ту же строку, а не новой строкой под ними (P348).
            let above = target > 0
                ? rest.substring(with: rest.lineRange(for: NSRange(location: target - 1, length: 0)))
                    .trimmingCharacters(in: .newlines)
                : ""
            let pieceIsPhoto = !Diary.links(in: piece).isEmpty
                && Diary.links(in: piece).allSatisfy { Diary.kind(of: $0) == .photo }
            let beside = pieceIsPhoto && !Diary.links(in: above).isEmpty
                && Diary.links(in: above).allSatisfy { Diary.kind(of: $0) == .photo }
            let lead = target == 0 ? "" : (beside ? " " : "\n")
            let out = rest.replacingCharacters(in: NSRange(location: target, length: 0),
                                               with: lead + piece
                                                   + (target == 0 && rest.length > 0 ? "\n" : ""))
            return (out, target + (lead as NSString).length)
        }

        // Долгое нажатие на снимок или точку iPhone сам превращал в меню
        // «Скопировать изображение / Сохранить в Фото» (P380) — его нет:
        // у вложений в записи свои касание и долгое нажатие.
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem,
                      defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? { nil }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? { nil }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            // Метка касания не снимается здесь: поле может спросить
            // разрешения писать уже после этого — и должно получить отказ.
            guard g.state == .ended, let got = pressed else { return }
            // Это было долгое нажатие, а не касание: точка с крестиком
            // остаётся на экране, карта не открывается (P374).
            guard Date().timeIntervalSince(heldEnded) > 0.4, taken == nil, cover == nil else { return }
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
            if view.typingAttributes[DiaryEditor.lineKey] != nil
                || view.typingAttributes[DiaryEditor.photoKey] != nil {
                view.typingAttributes = DiaryEditor.body(parent.size, serif: parent.serif)
            }
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
                    guard let got = Photo.load(url, side: 280) else { return }
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
            // Полоска вложений — часть клавиатуры (P279): верх клавиатуры
            // уже её верх.
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

        /// Текст записи перед броском снимка из полоски — по нему видно,
        /// куда снимок лёг (P348).
        private var dropBefore: String?

        func textDroppableView(_ droppable: UIView & UITextDroppable,
                               willPerformDrop drop: UITextDropRequest) {
            dropBefore = parent.text
            quietUntil = Date().addingTimeInterval(1.5)
        }

        func textViewDidChange(_ view: UITextView) {
            var now = DiaryEditor.plain(view.attributedText)
            var merged = false
            if let was = dropBefore {
                dropBefore = nil
                if let beside = DiaryEditor.besideDropped(now, was: was) {
                    now = beside
                    merged = true
                }
                // Голос или файл бросили посреди фразы — он встаёт своей
                // строкой: кнопочкой он бывает только так (P377).
                if let own = DiaryEditor.ownLine(now) {
                    now = own
                    merged = true
                }
            }
            parent.text = now
            if resolve != nil, merged || DiaryEditor.hasLoosePicture(view.text) {
                // Строку-ссылку только что бросили или вписали — рисуем её
                // картинкой. Курсор остаётся примерно там, где был.
                let at = view.selectedRange.location
                view.attributedText = DiaryEditor.styled(now, size: parent.size,
                                                         serif: parent.serif,
                                                         stamped: parent.stamped,
                                                         resolve: resolve)
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

    /// `small` — для строки дела в плане: кнопочка не выше букв названия,
    /// иначе строка раздаётся и номер со временем съезжают с неё (P256).
    init(point: GeoPoint, glowing: Bool = false, small: Bool = false) {
        super.init(data: nil, ofType: nil)
        let picture = PointChip.draw(point.label, glowing: glowing, small: small)
        image = picture
        let drop: CGFloat = small ? -4 : (glowing ? -12 : -7)
        bounds = CGRect(origin: CGPoint(x: 0, y: drop), size: picture.size)
    }

    /// Точка в тексте — значок шириной в знак-два, прямо в строке (P259).
    /// Название и координаты — на карте, куда ведёт касание.
    init(mini point: GeoPoint, glowing: Bool = false) {
        super.init(data: nil, ofType: nil)
        let picture = PointChip.mark(glowing: glowing, title: point.title)
        image = picture
        let pad: CGFloat = glowing ? 3 : 0
        bounds = CGRect(origin: CGPoint(x: 0, y: -5 - pad), size: picture.size)
        accessibilityLabel = T("Точка на карте: ", "Place on the map: ") + point.label
    }

    /// Булавка; у точки с названием — и название рядом (P284). Красная
    /// булавка на светло-красной подложке с красной кромкой — точку видно в
    /// тексте сразу (P358).
    static func mark(glowing: Bool, title: String = "") -> UIImage {
        let pad: CGFloat = glowing ? 3 : 0
        let red = UIColor(Look.pin)
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font,
                                                     .foregroundColor: UIColor(Look.ink)]
        // Точка без названия подписана «Место» (P380): одна булавка в
        // строке не читалась как запись.
        let given = title.trimmingCharacters(in: .whitespaces)
        let name = given.isEmpty ? T("Место", "Place") : given
        let wide = min(ceil((name as NSString).size(withAttributes: words).width), 180)
        let chip = CGSize(width: name.isEmpty ? 24 : 24 + wide + 8, height: 21)
        let size = CGSize(width: chip.width + pad * 2, height: chip.height + pad * 2)
        let pin = UIImage(systemName: "mappin.circle.fill",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.5,
                                                                         weight: .semibold))?
            .withTintColor(red, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let box = CGRect(x: pad, y: pad, width: chip.width, height: chip.height)
                .insetBy(dx: 0.6, dy: 0.6)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 7)
            if glowing {
                ctx.cgContext.setShadow(offset: .zero, blur: 4, color: UIColor(Look.glow).cgColor)
            }
            UIColor(Look.planBg).setFill()
            shape.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            red.withAlphaComponent(0.13).setFill()
            shape.fill()
            (glowing ? UIColor(Look.glow) : red.withAlphaComponent(0.75)).setStroke()
            shape.lineWidth = glowing ? 1.6 : 1.2
            shape.stroke()
            if let pin {
                let s = pin.size
                pin.draw(in: CGRect(x: pad + (24 - s.width) / 2,
                                    y: pad + (chip.height - s.height) / 2,
                                    width: s.width, height: s.height))
            }
            if !name.isEmpty {
                (name as NSString).draw(
                    with: CGRect(x: pad + 22, y: pad + (chip.height - font.lineHeight) / 2,
                                 width: wide, height: font.lineHeight),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: words, context: nil)
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    /// В режиме изменений точка светится, как превью снимков (P241).
    static func draw(_ label: String, glowing: Bool = false, small: Bool = false) -> UIImage {
        let font = UIFont.monospacedSystemFont(ofSize: small ? 11 : 12.5, weight: .regular)
        let ink = UIColor(Look.inkFaint)
        let words = [NSAttributedString.Key.font: font, .foregroundColor: ink]
        let pin = UIImage(systemName: "mappin.and.ellipse",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))?
            .withTintColor(ink, renderingMode: .alwaysOriginal)
        let wide = min((label as NSString).size(withAttributes: words).width, 250)
        let pinSide: CGFloat = small ? 11 : 14
        let chip = CGSize(width: 10 + pinSide + 5 + wide + 10, height: small ? 18 : 24)
        let pad: CGFloat = glowing && !small ? 5 : 0
        let size = CGSize(width: chip.width + pad * 2, height: chip.height + pad * 2)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let box = CGRect(x: pad, y: pad, width: chip.width, height: chip.height)
                .insetBy(dx: 0.5, dy: 0.5)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: chip.height / 2)
            if glowing {
                ctx.cgContext.setShadow(offset: .zero, blur: 5, color: UIColor(Look.glow).cgColor)
            }
            UIColor(Look.chrome).setFill()
            shape.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(glowing ? Look.glow : Look.rule).setStroke()
            shape.lineWidth = glowing ? 2 : 1
            shape.stroke()
            pin?.draw(in: CGRect(x: pad + 10, y: pad + (chip.height - pinSide) / 2,
                                 width: pinSide, height: pinSide))
            (label as NSString).draw(
                with: CGRect(x: pad + 15 + pinSide, y: (size.height - font.lineHeight) / 2,
                             width: wide, height: font.lineHeight),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: words, context: nil)
        }
    }
}

/// Голос, видео или документ в тексте записи (P377) — кнопочка со значком
/// и именем файла, как точка. Касание открывает, долгое нажатие несёт.
final class FileChip: NSTextAttachment {

    init(link: String) {
        super.init(data: nil, ofType: nil)
        let picture = FileChip.draw(link)
        image = picture
        bounds = CGRect(origin: CGPoint(x: 0, y: -5), size: picture.size)
        accessibilityLabel = FileChip.name(link)
    }

    required init?(coder: NSCoder) { nil }

    static func name(_ link: String) -> String {
        ((link as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func draw(_ link: String) -> UIImage {
        let icon: String
        switch Diary.kind(of: link) {
        case .audio: icon = "waveform"
        case .video: icon = "film"
        default: icon = "doc"
        }
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Look.ink)]
        let name = Self.name(link)
        let wide = min(ceil((name as NSString).size(withAttributes: words).width), 180)
        let size = CGSize(width: 26 + wide + 9, height: 21)
        let tint = UIColor(Look.accent)
        let glyph = UIImage(systemName: icon,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let shape = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.6, dy: 0.6),
                                     cornerRadius: 7)
            UIColor(Look.planBg).setFill()
            shape.fill()
            tint.withAlphaComponent(0.1).setFill()
            shape.fill()
            tint.withAlphaComponent(0.7).setStroke()
            shape.lineWidth = 1.2
            shape.stroke()
            if let glyph {
                let s = glyph.size
                glyph.draw(in: CGRect(x: (26 - s.width) / 2, y: (size.height - s.height) / 2,
                                      width: s.width, height: s.height))
            }
            (name as NSString).draw(
                with: CGRect(x: 24, y: (size.height - font.lineHeight) / 2, width: wide, height: font.lineHeight),
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
        UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
    }

    /// Снимок, обрезанный по клетке и со скруглёнными углами.
    static func frame(_ image: UIImage) -> UIImage {
        let size = DiaryEditor.photoSize
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: box, cornerRadius: 6).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2,
                                  width: w, height: h))
        }
    }
}
