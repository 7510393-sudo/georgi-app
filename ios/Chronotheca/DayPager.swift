import SwiftUI

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

    var body: some View {
        PageCurl { offset in
            DayPage(date: shift(offset), live: offset == 0)
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(shell)
                .environmentObject(archive)
        } onTurn: { step in
            hideKeyboard()
            store.move(by: step)
        }
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

    var body: some View {
        VStack(spacing: 0) {
            heading
            tabs
            content
                // Облачко выглядывает из-под вкладки на три четверти.
                .overlay(alignment: .top) { cloud }
            AttachBar()
        }
        .background(background)
        .sheet(isPresented: $remembering) {
            if let (day, ago) = archive.remembered(for: date) {
                RememberSheet(day: day, ago: ago, open: $remembering)
            }
        }
    }

    /// Облачко только на вкладке «Дневник» и только на открытом дне
    /// (решения P66–P69). На соседних страницах его нет: они лишь
    /// показываются, пока едут.
    @ViewBuilder private var cloud: some View {
        if live, shell.tab == .diary, archive.remembered(for: date) != nil {
            // Облачко висит под своей вкладкой — под «Дневником», а не
            // посередине: оно относится к дневнику, а не к экрану вообще.
            // Вкладки делят ширину поровну, поэтому и здесь две половины.
            HStack(spacing: 0) {
                Color.clear.frame(maxWidth: .infinity)
                RememberCloud(date: date, open: $remembering)
                    .frame(maxWidth: .infinity)
            }
            .offset(y: -8)
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
        HStack(alignment: .center, spacing: 0) {
            side(-1)
            VStack(spacing: 2) {
                Text(live ? store.title : DayPage.title(for: date))
                    .font(.system(size: 23, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Look.ink)
                Text(Ru.weekday(date))
                    .font(Look.sans(12.5))
                    .tracking(0.75)
                    .foregroundStyle(Ru.dayColor(date))
                Text(Ru.longDate(date))
                    .font(Look.sans(15))
                    .foregroundStyle(Look.inkSoft)
            }
            .frame(maxWidth: .infinity)
            side(1)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
        .background(Look.chrome)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    /// Стрелка со словом: слева — вчерашний день, справа — завтрашний.
    /// Горит та, что показывает дорогу к сегодняшнему.
    private func side(_ step: Int) -> some View {
        let lit = toward == step
        let sign = step < 0 ? "‹" : "›"
        return VStack(spacing: 1) {
            Text(sign)
                .font(.system(size: 20, weight: lit ? .semibold : .regular))
                .foregroundStyle(lit ? Look.accent : Look.inkFaint)
            Text(neighbour(step))
                .font(Look.sans(9.5))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 62)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            guard live, lit else { return }
            store.go(to: DayStore.today())
            shell.say("Вернулись на сегодня")
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
            tab(.diary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
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
        if live {
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

    var body: some View {
        HStack(spacing: 0) {
            item("photo", "фото")
            item("waveform", "аудио")
            item("doc", "файлы")
            item("mappin.and.ellipse", "геоточка")
        }
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(Look.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Look.rule).frame(height: 1)
        }
    }

    private func item(_ icon: String, _ name: String) -> some View {
        Button {
            shell.say("Вложения ещё не сделаны — следующий срез работы.")
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17))
                Text(name.uppercased()).font(Look.sans(9)).tracking(0.45)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Look.inkFaint)
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

    var body: some View {
        Group {
            if shell.tab == .plan { plan } else { diary }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
    }

    private var tasks: [PlanRow] { rows.filter { $0.isTask } }

    private var plan: some View {
        PlanPage(rows: tasks, isPast: date < DayStore.today(),
                 bellColor: Ru.dayColor(date))
    }

    private var diary: some View {
        DiaryPage(tasks: tasks,
                  answer: { answers[$0] ?? "" },
                  title: .constant(title),
                  text: .constant(text),
                  editable: false)
    }

    private func load() {
        rows = Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body)
        let file = DayFile(text: vault.read(.diary, for: date))
        let diary = Diary(body: file.body)
        title = file.value("заголовок") ?? ""
        text = diary.text
        answers = diary.answers
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

    var body: some View {
        PlanScaffold(isPast: isPast, dimmed: isPast) {
            if rows.isEmpty {
                PlanEmpty(isPast: isPast)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    PlanRowLine(number: i + 1, row: row, faded: isPast,
                                bellColor: bellColor)
                    Rectangle().fill(Look.ruleSoft).frame(height: 1)
                }
                PlanStat(planned: rows.count, done: rows.filter(\.done).count)
            }
        }
        .opacity(isPast ? 0.58 : 1)
    }
}
