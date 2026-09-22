import SwiftUI

/// Переход между разделами: перелистывание толстого ежедневника.
///
/// Разделы лежат в книге по порядку: календарь в начале, «сегодня»
/// посередине, поиск в конце — ровно так, как нарисованы значки. Переходя
/// из раздела в раздел, человек не «переключает экран», а листает: столько
/// страниц, сколько между разделами, и в ту сторону, в какую полагается.
/// К началу книги — слева направо, к концу — справа налево (замысел автора,
/// решение P144).
///
/// Настоящих листов рисуется меньше, чем страниц в замысле: больше десятка
/// глаз всё равно не различает, а вот длительность и сторона различаются
/// хорошо — через раздел листается заметно дольше, чем в соседний.
struct PageTurn: View, Animatable {

    /// Назад — страницы идут слева направо, к началу книги.
    let back: Bool
    let sheets: Int
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Доля всего хода, которая достаётся одной странице. Остальное — разбег
    /// между ними: оттого они и идут веером, а не разом.
    private let span = 0.42

    var body: some View {
        ZStack {
            ForEach(Array(0..<sheets), id: \.self) { i in sheet(i) }
        }
        // Страницы летят — трогать их бессмысленно, а помешать они могут.
        .allowsHitTesting(false)
        .opacity(fade)
    }

    /// К концу хода стопка тает: иначе последняя страница ложится наглухо и
    /// раздел выскакивает из-под неё рывком.
    private var fade: Double {
        guard back, progress > 0.86 else { return 1 }
        return max(0, 1 - (progress - 0.86) / 0.14)
    }

    private func phase(_ i: Int) -> Double {
        guard sheets > 1 else { return min(max(progress, 0), 1) }
        let step = (1 - span) / Double(sheets - 1)
        return min(max((progress - Double(i) * step) / span, 0), 1)
    }

    private func sheet(_ i: Int) -> some View {
        let t = phase(i)
        // 0 — страница лежит справа, 1 — перевёрнута налево.
        let turned = back ? 1 - t : t
        let shade = turned < 0.5 ? turned * 0.2 : 0.1 + (1 - turned) * 0.1

        return Rectangle()
            .fill(Look.planBg)
            .overlay(Color.black.opacity(shade))
            // Обрез страницы: по нему стопка и читается стопкой.
            .overlay(alignment: .trailing) {
                Rectangle().fill(Look.rule).frame(width: 1)
            }
            .rotation3DEffect(.degrees(-180 * turned),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.5)
            // Перевёрнутая до конца страница ушла за корешок — её не видно.
            .opacity(turned > 0.995 ? 0 : 1)
            .zIndex(back ? Double(i) : Double(sheets - i))
    }
}

/// Сколько страниц и в какую сторону листать между разделами.
struct Turn: Equatable {

    let back: Bool
    let sheets: Int
    let duration: Double

    /// Порядок разделов в книге: календарь ближе к началу, поиск — к концу.
    private static func place(_ screen: Shell.Screen) -> Int {
        switch screen {
        case .calendar: 0
        case .today:    1
        case .search:   2
        }
    }

    /// `nil`, если листать некуда: раздел тот же самый.
    init?(from: Shell.Screen, to: Shell.Screen) {
        let here = Self.place(from), there = Self.place(to)
        guard here != there else { return nil }
        let steps = abs(there - here)
        back = there < here
        sheets = min(9 * steps, 16)
        duration = steps == 1 ? 0.52 : 0.76
    }
}
