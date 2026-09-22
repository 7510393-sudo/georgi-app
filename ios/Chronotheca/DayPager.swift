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

    var body: some View {
        PageCurl { offset in
            DayPage(date: shift(offset), live: offset == 0)
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(shell)
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

    var body: some View {
        VStack(spacing: 0) {
            heading
            tabs
            content
            AttachBar()
        }
        .background(background)
    }

    private var background: Color {
        shell.tab == .diary ? Look.diaryBg : Ru.tint(date)
    }

    // MARK: - Шапка дня

    private var heading: some View {
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
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity)
        .background(Look.chrome)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
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
                .padding(.top, 9)
                .padding(.bottom, 10)
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
        PlanPage(rows: tasks, isPast: date < DayStore.today())
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
struct PlanPage: View {

    let rows: [PlanRow]
    let isPast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanHead(isPast: isPast, dimmed: isPast)

            if rows.isEmpty {
                empty
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    PlanRowLine(number: i + 1, row: row, faded: isPast)
                    Rectangle().fill(Look.ruleSoft).frame(height: 1)
                }
                stat
            }
            Spacer(minLength: 0)
        }
        .opacity(isPast ? 0.58 : 1)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("На этот день ничего не запланировано.")
            if !isPast { Text("Нажмите «+», чтобы вписать дело.") }
        }
        .font(Look.sans(14))
        .lineSpacing(5)
        .foregroundStyle(Look.inkFaint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 22)
    }

    private var stat: some View {
        Text("Запланировано \(rows.count) · сделано \(rows.filter(\.done).count)")
            .font(Look.mono(11.5))
            .tracking(0.35)
            .foregroundStyle(Look.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 20)
    }
}
