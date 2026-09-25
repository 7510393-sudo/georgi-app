import SwiftUI
import UIKit
import PhotosUI

/// Дни листаются как страницы книги.
///
/// Вместе со страницей едет всё, что к этому дню относится: имя дня, день
/// недели, дата, вкладки и полоска вложений. Неподвижны только шестерёнка,
/// три точки и три раздела внизу — то, что принадлежит приложению, а не дню.
struct DayPages: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var archive: Archive

    @State private var plan: [Int] = []

    var body: some View {
        PageCurl(content: { offset in
            DayPage(date: shift(offset), live: offset == 0)
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(shell)
                .environmentObject(archive)
        }, onTurn: { step in
            hideKeyboard()
            store.move(by: step)
        }, plan: $plan)
        .onChange(of: shell.goHome) { _, want in
            guard want else { return }
            shell.goHome = false
            plan = DayPages.wayHome(from: store.date)
        }
    }

    /// Сколько дней до сегодняшнего и в какую сторону.
    static func wayHome(from date: Date, to home: Date = DayStore.today()) -> [Int] {
        let days = Calendar.current.dateComponents([.day], from: date, to: home).day ?? 0
        return Chronotheca.wayHome(days)
    }

    private func shift(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: store.date) ?? store.date
    }
}

/// Одна страница дня.
///
/// Открытый день (`live`) правится; соседние — только показываются, пока
/// едут. Правят тот день, на котором человек остановился.
struct DayPage: View {

    let date: Date
    let live: Bool

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var archive: Archive

    @State private var remembering = false

    /// Дни, чьи облачка уже прочитаны (решение P136).
    @AppStorage(Remembered.key) private var read = ""

    var body: some View {
        VStack(spacing: 0) {
            // Облачко лежит на шапке, а вкладки рисуются следом и накрывают
            // его низ. Оттого и видно, что это бумажка, подсунутая под
            // страницу, а не часть страницы (P140).
            heading
            tabs
            content
            AttachBar()
        }
        .background(background)
        .sheet(isPresented: $remembering, onDismiss: forget) {
            if let (day, ago) = archive.remembered(for: date) {
                RememberSheet(day: day, ago: ago, open: $remembering)
            }
        }
    }

    /// Облачко только на вкладке «Дневник» и только на открытом дне
    /// (решения P66–P69). На соседних страницах его нет: они лишь
    /// показываются, пока едут.
    @ViewBuilder private var cloud: some View {
        if live, shell.tab == .diary, archive.remembered(for: date) != nil,
           !Remembered.has(Vault.stamp(date), in: read) {
            // Облачко стоит на верхнем крае вкладки «Дневник», локоть
            // заходит на вкладку. Размер и место — доли ширины вкладки.
            // Правее и мельче, чем на эскизе: на телефоне слева дата, а
            // под локтем надпись вкладки, и накрывать нельзя ни то, ни
            // другое — самая глубокая точка локтя приходится правее
            // надписи (P206).
            GeometryReader { geo in
                let width = geo.size.width * 0.50
                let height = width / RememberCloud.ratio
                RememberCloud(date: date, width: width) { remembering = true }
                    .frame(width: width, height: height)
                    .offset(x: geo.size.width * 0.45, y: -height * 0.80)
            }
            .transition(.opacity)
        }
    }

    /// Листок прочитан — облачко уходит: оно своё дело сделало, а звать
    /// второй раз к той же записи нечестно, человек уже откликнулся (P136).
    /// Уходит не мигом, а угасая: резкое исчезновение читается как сбой.
    private func forget() {
        withAnimation(.easeOut(duration: 0.35)) {
            read = Remembered.adding(Vault.stamp(date), to: read)
        }
    }

    private var background: Color {
        shell.tab == .diary ? Look.diaryBg : Ru.tint(date)
    }

    // MARK: - Шапка дня

    /// Шапка дня: соседние дни названы, а стрелка в сторону сегодняшнего
    /// горит. Уйдя на неделю назад, человек видит, что «сейчас» — справа,
    /// и не гадает, в какую сторону возвращаться (то же правило, что в
    /// календаре, P127).
    private var heading: some View {
        VStack(spacing: 2) {
            // Соседние дни стоят на одной строке с нынешним, а не над и под
            // ним: иначе взгляд скачет вверх-вниз и всякий раз перестраивается
            // с крупного на мелкое. Строка задана ростом жёстко, чтобы шапка
            // была одной высоты на любой странице (P113).
            HStack(spacing: 0) {
                side(-1)
                Text(live ? store.title : DayPage.title(for: date))
                    .font(.system(size: 23, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                side(1)
            }
            .frame(height: DayPage.headLine)

            Text(Ru.weekday(date))
                .font(Look.sans(12.5))
                .tracking(0.75)
                .foregroundStyle(Ru.dayColor(date))
            Text(Ru.longDate(date))
                .font(Look.sans(15))
                .foregroundStyle(Look.inkSoft)
        }
        .padding(.horizontal, 6)
        // Над названием — воздух: когда под шапкой легла тень, название
        // казалось прижатым к ней (решение P192).
        .padding(.top, DayPage.airAbove)
        // Отступ до вкладок держит шапка, а не вкладки: тогда её нижний край
        // совпадает с верхним краем вкладки, и облачко уходит именно за
        // вкладку, а не за пустую полоску над ней.
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Look.chrome)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    /// Высота строки заголовка. Одна на всех страницах: шапка не должна
    /// менять рост от того, горит стрелка или нет (P113).
    static let headLine: CGFloat = 31

    /// Имя соседнего дня, а рядом с ним — стрелка.
    ///
    /// Стрелка стоит в промежутке между именами, с той стороны, куда ведёт:
    /// слово снаружи, стрелка внутри. Имя на треть мельче нынешнего дня и
    /// бледное — соседний день предлагается, а не зовёт.
    ///
    /// Горит та стрелка, что показывает дорогу к сегодняшнему дню (P127).
    /// Размер у обеих одинаковый: разным он менял бы рост строки.
    private func side(_ step: Int) -> some View {
        let lit = toward == step
        let sign = step < 0 ? "‹" : "›"
        let word = Text(neighbour(step))
            .font(Look.sans(15.5))
            .foregroundStyle(Look.inkFaint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        let arrow = Text(sign)
            .font(.system(size: 21, weight: lit ? .bold : .regular))
            .foregroundStyle(lit ? Look.accent : Look.inkFaint)
            .frame(width: 25, height: DayPage.headLine - 4)
            .background(lit ? Look.accent.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))

        return HStack(spacing: 2) {
            if step < 0 {
                Spacer(minLength: 0)
                word
                arrow
            } else {
                arrow
                word
                Spacer(minLength: 0)
            }
        }
        .frame(width: 108)
        .contentShape(Rectangle())
        // Дорога домой одна, какой кнопкой её ни начинай (решение P168).
        .onLongPressGesture(minimumDuration: 0.4) {
            guard live, lit else { return }
            hideKeyboard()
            shell.say("Вернулись на сегодня")
            shell.goHome = true
        } onPressingChanged: { _ in }
        .onTapGesture {
            guard live else { return }
            hideKeyboard()
            store.move(by: step)
        }
        .accessibilityLabel(lit ? neighbour(step) + ". Долгое нажатие — на сегодня"
                                : neighbour(step))
    }

    /// В какой стороне сегодняшний день: −1 слева, +1 справа, 0 — мы на нём.
    private var toward: Int {
        let today = DayStore.today()
        if date < today { return 1 }
        if date > today { return -1 }
        return 0
    }

    /// Как зовут соседний день. Дальше послезавтра имён нет — там просто
    /// прошлое и будущее.
    private func neighbour(_ step: Int) -> String {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: step, to: date) else { return "" }
        let n = cal.dateComponents([.day], from: DayStore.today(), to: day).day ?? 0
        switch n {
        case -2: return "позавчера"
        case -1: return "вчера"
        case  0: return "сегодня"
        case  1: return "завтра"
        case  2: return "послезавтра"
        default: return step < 0 ? "прошлое" : "будущее"
        }
    }

    /// Воздух над названием экрана. Один на всех трёх экранах, чтобы
    /// название не прыгало по высоте при переходе между ними.
    static let airAbove: CGFloat = 12

    static func title(for date: Date) -> String {
        let n = Calendar.current.dateComponents([.day], from: DayStore.today(), to: date).day ?? 0
        switch n {
        case -2: return "Позавчера"
        case -1: return "Вчера"
        case  0: return "Сегодня"
        case  1: return "Завтра"
        case  2: return "Послезавтра"
        default: return Ru.weekday(date).capitalized
        }
    }

    // MARK: - Вкладки

    private var tabs: some View {
        HStack(spacing: 6) {
            tab(.plan)
            // Облачко лежит поверх вкладки: вкладки рисуются после шапки,
            // и то, что выше края, ложится на шапку, а локоть — на вкладку.
            tab(.diary).overlay(alignment: .topLeading) { cloud }
        }
        .padding(.horizontal, 12)
        .background(Look.chrome)
    }

    private func tab(_ which: Shell.Tab) -> some View {
        let on = shell.tab == which
        let page = which == .diary ? Look.diaryBg : Ru.tint(date)
        return Button {
            guard live else { return }
            store.prune()
            store.save()
            shell.tab = which
        } label: {
            Text(which.rawValue.uppercased())
                .font(Look.sans(13, weight: on ? .semibold : .regular))
                .tracking(1.56)
                .foregroundStyle(on ? Look.ink : Look.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 11)
                .background(page)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10,
                                                  topTrailingRadius: 10))
                .overlay(TabBorder(radius: 10).stroke(Look.rule, lineWidth: 1))
        }
        .offset(y: on ? 1 : 0)
        .zIndex(on ? 1 : 0)
    }

    // MARK: - Содержимое

    @ViewBuilder private var content: some View {
        if shell.probingSide {
            // Только для снимков: страница, нарисованная соседским способом,
            // но в той же оправе. Два снимка ложатся друг на друга, и всякое
            // расхождение видно сразу, а не на ощупь при перелистывании.
            SideDay(date: date)
        } else if live {
            Group {
                if shell.tab == .plan { PlanView() } else { DiaryView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SideDay(date: date)
        }
    }
}

/// Полоска вложений. Едет вместе со страницей: вложения принадлежат дню.
struct AttachBar: View {

    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore

    @State private var choosing = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var recording = false
    @State private var browsing = false

    var body: some View {
        HStack(spacing: 0) {
            item("photo", "фото", ready: true) { choosePhotos() }
            item("waveform", "аудио", ready: true) { open { recording = true } }
            item("doc", "файлы", ready: true) { open { browsing = true } }
            // Касание — своя карта мест; долгое нажатие — вписать, где
            // человек сейчас, строкой в текст записи (P165, P207).
            item("mappin.and.ellipse", "геоточка", ready: true,
                 hold: writePlace) { shell.showingMap = true }
        }
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(Look.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Look.rule).frame(height: 1)
        }
        // Системное окно галереи: приложению не нужно разрешение на всю
        // галерею — оно получает только те снимки, которые выбрал человек.
        .photosPicker(isPresented: $choosing, selection: $picked,
                      maxSelectionCount: 10, matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            take(items)
        }
        .sheet(isPresented: $recording) {
            Recorder(done: keepVoice) { recording = false }
                .presentationDetents([.height(360)])
        }
        .sheet(isPresented: $browsing) {
            DocumentPicker(pick: keepFiles)
        }
    }

    /// Вложение кладётся туда, где человек стоит, — в план или в дневник
    /// (P203). В закрытый день — нельзя, и об этом говорится.
    private func open(_ show: () -> Void) {
        guard store.canEdit(shell.tab) else { return shell.say(store.closedReason) }
        show()
    }

    /// Голос готов: файл — в «Аудио», ссылка — в файл дня (P209).
    private func keepVoice(_ url: URL) {
        recording = false
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              store.addAttachment(data, to: .audio, name: Vault.moment(store.date) + ".m4a",
                                  tab: shell.tab)
        else { return shell.say("Запись не сохранилась.") }
        shell.say("Голос положен в папку «Аудио»")
    }

    /// Документы выбраны: копии — в «Документы» под своими именами (P209).
    private func keepFiles(_ urls: [URL]) {
        browsing = false
        guard !urls.isEmpty else { return }
        var kept = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if store.addAttachment(data, to: .documents, name: url.lastPathComponent,
                                   tab: shell.tab) { kept += 1 }
        }
        shell.say(kept == urls.count ? "Положено в папку «Документы»: \(kept)"
                                     : "Не удалось положить файлов: \(urls.count - kept)")
    }

    private func item(_ icon: String, _ name: String, ready: Bool = false,
                      hold: (() -> Void)? = nil,
                      act: @escaping () -> Void) -> some View {
        let face = VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 17))
            Text(name.uppercased()).font(Look.sans(9)).tracking(0.45)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(ready ? Look.inkSoft : Look.inkFaint)
        .contentShape(Rectangle())
        return Group {
            if let hold {
                // У кнопки два жеста: касание и долгое нажатие. Обычная
                // кнопка сработала бы и после долгого — поэтому жесты свои.
                face
                    .onTapGesture(perform: act)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        hold()
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Долгое нажатие — вписать место в запись")
            } else {
                Button(action: act) { face }
            }
        }
    }

    /// Вписать, где человек сейчас, — на ту вкладку, где он стоит: в
    /// текст дневника или строкой в план (P210).
    private func writePlace() {
        let tab = shell.tab
        guard store.canEdit(tab) else { return shell.say(store.closedReason) }
        shell.say("Узнаю, где вы…")
        Locator.shared.current { location in
            guard let at = location?.coordinate else {
                return shell.say("Не удалось узнать, где вы. Проверьте, разрешено ли приложению место.")
            }
            switch tab {
            case .diary: store.writePlace(at)
            case .plan: store.writePlanPlace(at)
            }
            if let location { store.noteWeather(at: location) }
            shell.say(tab == .diary ? "Место вписано в запись" : "Место вписано в план")
        }
    }

    /// Фото кладутся туда, где человек стоит: на вкладке плана — в план,
    /// в дневнике — в дневник (решение P203).
    private func choosePhotos() {
        guard store.canEdit(shell.tab) else { return shell.say(store.closedReason) }
        choosing = true
    }

    /// Положить выбранные снимки в папку и показать их в дневнике дня.
    @MainActor
    private func take(_ items: [PhotosPickerItem]) {
        Task {
            let tab = shell.tab
            var added = 0
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                if store.addPhoto(data, to: tab) { added += 1 }
            }
            if added == items.count {
                shell.say(added == 1 ? "Фотография положена в папку «Фотографии»"
                                     : "Фотографий положено в папку: \(added)")
            } else {
                shell.say("Не удалось положить фотографий: \(items.count - added)")
            }
        }
    }
}

/// Соседний день — только чтобы его было видно, пока он едет.
///
/// Рисует ровно те же страницы, что и открытый день, только без правки.
/// Иначе при повороте содержимое перескакивает: человек видел одно, а
/// получил другое.
struct SideDay: View {

    let date: Date

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    @State private var rows: [PlanRow] = []
    @State private var title = ""
    @State private var text = ""
    @State private var answers: [String: String] = [:]
    @State private var photos: [String] = []
    @State private var planPhotos: [String] = []
    @State private var weather: String?

    var body: some View {
        Group {
            if shell.tab == .plan { plan } else { diary }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
    }

    private var tasks: [PlanRow] { rows.filter { $0.isTask } }

    private var plan: some View {
        PlanPage(rows: rows, isPast: date < DayStore.today(),
                 bellColor: Ru.dayColor(date),
                 photos: planPhotos.map { vault.mediaURL($0, for: date) },
                 resolve: { [vault, date] in vault.mediaURL($0, for: date) })
    }

    private var diary: some View {
        DiaryPage(tasks: tasks,
                  answer: { answers[$0] ?? "" },
                  title: .constant(title),
                  text: .constant(text),
                  editable: false,
                  weather: weather,
                  photos: photos.map { vault.mediaURL($0, for: date) },
                  resolve: { [vault, date] in vault.mediaURL($0, for: date) })
    }

    private func load() {
        (rows, planPhotos) = Plan.splitPhotos(
            Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body))
        let file = DayFile(text: vault.read(.diary, for: date))
        let diary = Diary(body: file.body)
        title = file.value("заголовок") ?? ""
        text = diary.text
        answers = diary.answers
        photos = diary.photos
        weather = file.value("погода")
    }
}

/// Список дел без правки — для соседних страниц.
///
/// Та же оправа и те же строки, что у открытой страницы. Ничего своего.
struct PlanPage: View {

    let rows: [PlanRow]
    let isPast: Bool
    /// Цвет дня недели: колокольчик красится им и на соседних страницах,
    /// иначе он бледнеет на просвет и вспыхивает после поворота.
    var bellColor: Color = Look.inkFaint
    var photos: [URL?] = []
    /// Где лежат снимки, поставленные между делами (P205).
    var resolve: ((String) -> URL?)?

    private var tasks: [PlanRow] { rows.filter(\.isTask) }

    var body: some View {
        PlanScaffold(isPast: isPast, dimmed: isPast, photos: photos) {
            if tasks.isEmpty {
                PlanEmpty(isPast: isPast)
            } else {
                // Дела и снимки между ними — в том же порядке, что и на
                // открытой странице; прочие строки файла не рисуются.
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if row.isTask {
                        PlanRowLine(number: rows[..<i].filter(\.isTask).count + 1,
                                    row: row, faded: isPast, bellColor: bellColor)
                        Rectangle().fill(Look.ruleSoft).frame(height: 1)
                    } else if let line = row.verbatim {
                        PlanExtraLine(line: line, resolve: resolve)
                    }
                }
                PlanStat(planned: tasks.count, done: tasks.filter(\.done).count)
            }
        }
        .opacity(isPast ? 0.58 : 1)
    }
}
