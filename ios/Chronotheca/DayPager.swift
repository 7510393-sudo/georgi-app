import SwiftUI

/// Листалка дней: три страницы подряд, средняя — открытый день.
///
/// Сделана настоящим постраничным листанием, а не сменой содержимого с
/// переходом. Переход я уже писал дважды, и оба раза его не было видно:
/// проверить движение снимком экрана нельзя, а на слово верить нечего.
/// Здесь движение делает сама система — страница идёт за пальцем и
/// доезжает сама, и не двигаться она не может.
struct DayPager: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            SideDay(date: shift(-1)).tag(0)
            DayScreen().tag(1)
            SideDay(date: shift(1)).tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: page) { _, now in
            guard now != 1 else { return }
            hideKeyboard()
            store.move(by: now - 1)
            // Каретка возвращается в середину без движения: человек уже
            // доехал до соседнего дня, и он теперь средний.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { page = 1 }
        }
        .onChange(of: shell.tab) { _, _ in page = 1 }
    }

    private func shift(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: store.date) ?? store.date
    }
}

/// Соседний день — только чтобы его было видно, пока он едет.
///
/// Читается прямо из файлов и не правится: правят только тот день, на
/// котором человек остановился.
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
        .background(shell.tab == .diary ? Look.diaryBg : Ru.tint(date))
        .onAppear(perform: load)
        .onChange(of: date) { _, _ in load() }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(date < DayStore.today() ? "день закрыт" : "дела на день")
                .font(Look.mono(11))
                .tracking(0.45)
                .foregroundStyle(Look.inkFaint)
                .padding(.leading, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

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
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)")
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
                    Rectangle().fill(Look.ruleSoft).frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(date < DayStore.today() ? 0.58 : 1)
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
