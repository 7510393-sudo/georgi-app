import SwiftUI

/// Страница дня: сверху план, ниже дневник — одним листом (P408).
///
/// Прежде это были две вкладки, и «как прошло» писали на одной, не видя
/// задуманного на другой. Теперь задуманное стоит над тем, что из него
/// вышло, и страница едет целиком: одна прокрутка на план и дневник.
///
/// Бумага двух сортов: под планом — в клетку, под дневником — гладкая
/// (P245). Граница — заголовок «Дневник».
///
/// Открытый день и соседние собираются из неё одинаково: стоит им
/// разойтись хоть на строку — и при перелистывании текст прыгает (P114).
struct DaySheet<Plan: View, Diary: View>: View {

    let date: Date
    /// Приложение открыли заново или вернулись после паузы (P346):
    /// меняется — страница встаёт на своё место. У соседних не меняется.
    var home = 0
    /// Куда встать: к концу записи дневника или к началу плана (P402).
    var toDiary = false
    /// Дневника у этого дня ещё нет — будущий день: заголовок бледный.
    var diaryOpen = true

    @ViewBuilder let plan: () -> Plan
    @ViewBuilder let diary: () -> Diary

    @State private var keyboard: CGFloat = 0

    private static var top: String { "страница-верх" }
    static var space: String { "лист" }

    var body: some View {
        GeometryReader { outer in
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            SheetHeading(title: T("План", "Plan"))
                                .id(Self.top)
                            plan()
                        }
                        // Под планом — клетка, она закрывает гладкую бумагу
                        // дневника, лежащую под всей страницей.
                        .background(Ru.tint(date).overlay(PageTexture(tab: .plan, space: Self.space)))
                        VStack(alignment: .leading, spacing: 0) {
                            SheetHeading(title: T("Дневник", "Diary"), faint: !diaryOpen)
                            diary()
                        }
                        // Короткая страница — низ дневника (погода, полоска)
                        // всё равно у нижнего края экрана.
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(minHeight: outer.size.height, alignment: .top)
                    .background(Ru.tint(date).overlay(PageTexture(tab: .diary, space: Self.space)))
                    // Клетка и волокно отсчитываются от самого листа, а не
                    // от экрана: тянешь план — клетка едет с текстом (P412).
                    .coordinateSpace(name: Self.space)
                    // Место под клавиатуру: без него строку, в которой пишут,
                    // некуда поднять (P166, P175).
                    .padding(.bottom, keyboard)
                    .onAppear { goHome(proxy) }
                    .onChange(of: home) { _, _ in goHome(proxy) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Ход плавный и один: клавиатура и страница едут вместе.
            .animation(.easeOut(duration: 0.25), value: keyboard)
        }
        .keyboardHeight($keyboard)
    }

    /// Встать на место — один раз на каждое открытие приложения: открыли
    /// «на дневнике» — к концу записи, «на плане» — к началу (P346, P402).
    private func goHome(_ proxy: ScrollViewProxy) {
        guard home > 0, home != SheetMemory.homed else { return }
        SheetMemory.homed = home
        let diary = toDiary && diaryOpen
        DispatchQueue.main.async {
            if diary {
                proxy.scrollTo(DiaryPage.end, anchor: .bottom)
            } else {
                proxy.scrollTo(Self.top, anchor: .top)
            }
        }
    }
}

/// Для какого открытия страница уже встала на место.
private enum SheetMemory {
    static var homed = -1
}

/// Заголовок части страницы — «План» или «Дневник» (P408): прописными, в
/// разрядку, как прежние корешки вкладок; на 15% крупнее и без черт по
/// бокам (P412).
struct SheetHeading: View {
    let title: String
    var faint = false

    var body: some View {
        Text(title.uppercased())
            .font(Look.sans(17.25, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(faint ? Look.inkFaint : Look.inkSoft)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}
