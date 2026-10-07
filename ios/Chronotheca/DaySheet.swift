import SwiftUI
import UIKit

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
    /// Просьба встать на план или на дневник (P424): меняется — страница
    /// встаёт. Перелистнули назад, глядя в дневник, — новая страница
    /// открывается на дневнике; вперёд и из календаря — на плане.
    var land = 0
    var landDiary = false
    /// Больше половины окна занял дневник — или снова план (P424).
    var onDiary: ((Bool) -> Void)?
    /// Что сидит над заголовком «Дневник» — облачко «…помнишь?» открытого
    /// дня (P436). У соседних страниц нет.
    var diaryMark: AnyView? = nil

    @ViewBuilder let plan: () -> Plan
    @ViewBuilder let diary: () -> Diary

    @State private var keyboard: CGFloat = 0

    private static var top: String { "страница-верх" }
    private static var diaryTop: String { "страница-дневник" }
    static var space: String { "лист" }
    private static var window: String { "окно-листа" }
    /// Строка вложений лежит поверх низа страницы, полупрозрачная (P424):
    /// столько места под концом записи, чтобы её можно было поднять из-под
    /// строки.
    static var stripRoom: CGFloat { 36 }

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
                                .id(Self.diaryTop)
                                // Облачко «…помнишь?» сидит над заголовком,
                                // у правого края (P436): низом на его верху.
                                .overlay(alignment: .topTrailing) {
                                    if let diaryMark {
                                        diaryMark.alignmentGuide(.top) { $0[.bottom] - 6 }
                                    }
                                }
                                .zIndex(1)
                            diary()
                        }
                        .background {
                            if onDiary != nil {
                                GeometryReader { g in
                                    Color.clear.preference(key: DiaryShare.self,
                                                           value: g.frame(in: .named(Self.window)).minY)
                                }
                            }
                        }
                        // Страница открыта на дневнике — дневник не короче
                        // окна: иначе на коротком дне листать некуда, и план
                        // остаётся сверху, хотя должен уйти за верхний край
                        // (P426). Соседняя страница считает так же (P114).
                        .frame(minHeight: landDiary && diaryOpen
                               ? max(0, outer.size.height - Self.stripRoom) : nil,
                               alignment: .top)
                        // Короткая страница — низ дневника (погода, полоска)
                        // всё равно у нижнего края экрана.
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    // Место под строкой вложений — всегда, и с клавиатурой
                    // (P432): прежде оно пропадало, пока клавиатура открыта,
                    // и возвращалось скачком, когда она уходила, — низ
                    // страницы прыгал на эти 36 точек (около 6 мм) вниз и
                    // обратно (видео автора).
                    .padding(.bottom, Self.stripRoom)
                    .frame(minHeight: outer.size.height, alignment: .top)
                    .background(Ru.tint(date).overlay(PageTexture(tab: .diary, space: Self.space)))
                    // Клетка и волокно отсчитываются от самого листа, а не
                    // от экрана: тянешь план — клетка едет с текстом (P412).
                    .coordinateSpace(name: Self.space)
                    // Место под клавиатуру: без него строку, в которой пишут,
                    // некуда поднять (P166, P175). Ровно столько, сколько
                    // клавиатура закрывает саму страницу: прежде отводилась
                    // вся её высота, хотя низ экрана и так занят разделами, —
                    // и страница, поднятая до конца, висела над клавиатурой
                    // с зазором в несколько строк (P413).
                    // Строка вложений уже дала своё место — его не считаем
                    // дважды: над клавиатурой без зазора, как прежде (P413).
                    .padding(.bottom, max(0, covered(outer) - Self.stripRoom))
                    .onAppear {
                        goHome(proxy)
                        settle(proxy, fresh: true)
                    }
                    .onChange(of: home) { _, _ in goHome(proxy) }
                    .onChange(of: land) { _, _ in settle(proxy, fresh: false) }
                }
            }
            .coordinateSpace(name: Self.window)
            .onPreferenceChange(DiaryShare.self) { top in
                onDiary?(top < (outer.size.height - Self.stripRoom) / 2)
            }
            .scrollDismissesKeyboard(.interactively)
            // Ход плавный и один: клавиатура и страница едут вместе.
            .animation(.easeOut(duration: 0.25), value: keyboard)
        }
        .keyboardHeight($keyboard)
    }

    /// Сколько страницы закрыто клавиатурой вместе с полоской вложений над
    /// ней.
    private func covered(_ outer: GeometryProxy) -> CGFloat {
        guard keyboard > 0 else { return 0 }
        let safe = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
        let top = UIScreen.main.bounds.height - keyboard - safe
        return max(0, outer.frame(in: .global).maxY - top)
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

    /// Встать на план или на дневник по просьбе (P424). Новая страница
    /// встаёт по просьбе один раз; соседняя, у которой своей просьбы нет
    /// (`land == 0`), — сразу туда, куда встанет открытая.
    private func settle(_ proxy: ScrollViewProxy, fresh: Bool) {
        if fresh {
            if land > 0 {
                guard land != SheetMemory.landed else { return }
            } else if !landDiary {
                return
            }
        }
        if land > 0 { SheetMemory.landed = land }
        let diary = landDiary && diaryOpen
        DispatchQueue.main.async {
            proxy.scrollTo(diary ? Self.diaryTop : Self.top, anchor: .top)
        }
    }
}

/// Где верх дневника в окне — по нему видно, что занимает экран (P424).
private struct DiaryShare: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Для какого открытия страница уже встала на место.
private enum SheetMemory {
    static var homed = -1
    static var landed = -1
}

/// Заголовок части страницы — «План» или «Дневник» (P408): прописными, в
/// разрядку, как прежние корешки вкладок; на 15% крупнее и без черт по
/// бокам (P412), и ещё на 30% (P424). Ростом ровно в две клетки листа
/// (P413).
struct SheetHeading: View {
    let title: String
    var faint = false

    var body: some View {
        Text(title.uppercased())
            .font(Look.sans(22.4, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(faint ? Look.inkFaint : Look.inkSoft)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: GridSnap.cell * 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Строка плана — целое число клеток листа (P413): высота округляется до
/// клеток вверх (недобор в три точки прощается — его съедают поля), а
/// содержимое стоит посередине. Клетка листа отсчитывается от верха плана,
/// и так промежутки между плашками ложатся ровно на её линии.
struct GridSnap: Layout {
    static let cell: CGFloat = PageTexture.cell

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: Self.snap(size.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard let child = subviews.first else { return }
        let size = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                    proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }

    static func snap(_ h: CGFloat) -> CGFloat {
        guard h > 0.5 else { return 0 }
        return max(1, ((h - 3) / cell).rounded(.up)) * cell
    }
}
