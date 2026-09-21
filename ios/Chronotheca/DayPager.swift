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
struct SideDay: View {

    let date: Date

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    @State private var rows: [PlanRow] = []
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        Group {
            if shell.tab == .plan { plan } else { diary }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 0) {
            if date < DayStore.today() {
                Text("день закрыт")
                    .font(Look.mono(11))
                    .tracking(0.45)
                    .foregroundStyle(Look.inkFaint)
                    .padding(.leading, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            } else {
                Color.clear.frame(height: 20)
            }

            if rows.isEmpty {
                Text("На этот день ничего не запланировано.")
                    .font(Look.sans(14))
                    .foregroundStyle(Look.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.horizontal, 22)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    line(i + 1, row)
                    Rectangle().fill(Look.ruleSoft).frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(date < DayStore.today() ? 0.58 : 1)
    }

    private func line(_ number: Int, _ row: PlanRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(Look.mono(18))
                .foregroundStyle(Look.inkFaint)
                .frame(width: 28, alignment: .trailing)
            Text(row.time ?? "--:--")
                .font(Look.mono(18.5))
                .foregroundStyle(Look.inkSoft)
            Text(row.text)
                .font(Look.sans(15))
                .foregroundStyle(Look.ink)
            Spacer(minLength: 0)
        }
        .opacity(row.done ? 0.42 : 1)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
    }

    private var diary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(Look.serif(19, weight: .semibold))
                    .foregroundStyle(Look.ink)
            }
            Text(text.isEmpty ? "Записи нет." : text)
                .font(Look.serif(15.5))
                .foregroundStyle(text.isEmpty ? Look.inkFaint : Look.ink)
                .lineSpacing(15.5 * 0.24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func load() {
        rows = Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body)
            .filter { $0.isTask }
        let file = DayFile(text: vault.read(.diary, for: date))
        title = file.value("заголовок") ?? ""
        text = Diary(body: file.body).text
    }
}
