import SwiftUI

/// Обрез книги: торец стопки страниц вдоль правого края.
///
/// Тот самый, по которому с одного взгляда видно, что книга толстая.
/// Системный поворот страницы умеет поворачивать только один лист, толщины
/// ему не задать, — а толщина и есть главное в ощущении ежедневника.
/// Поэтому она берётся не из движения, а из самой страницы: обрез стоит на
/// месте всегда, и когда страница поворачивается, она поднимается с него и
/// открывает стопку под собой (решение P145).
///
/// Полоска рисуется штрихами разной силы: бумага в стопке лежит неровно, и
/// ровная заливка читается как полоса краски, а не как торец.
struct ForeEdge: View {

    /// Ширина обреза. Отнимается у содержимого страницы — поэтому узкая:
    /// намёк на толщину, а не полка.
    static let width: CGFloat = 9

    var body: some View {
        Canvas { ctx, size in
            // Подложка: к наружному краю темнее — туда падает меньше света.
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(
                        Gradient(colors: [Look.planBg, Look.foreEdge]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)))

            // Штрихи — края отдельных листов.
            var x: CGFloat = 0.6
            var i = 0
            while x < size.width {
                let сила = Self.strokes[i % Self.strokes.count]
                ctx.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: size.height)),
                         with: .color(Look.foreEdgeLine.opacity(сила)))
                x += Self.gaps[i % Self.gaps.count]
                i += 1
            }
        }
        .frame(width: Self.width)
        .overlay(alignment: .leading) {
            // Тень у самого корешка страницы: лист лежит на стопке, а не
            // врезан в неё.
            LinearGradient(colors: [Look.foreEdgeLine.opacity(0.22), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 2.5)
        }
        .accessibilityHidden(true)
    }

    /// Неровность стопки: заданная раз и навсегда, а не случайная. Случайная
    /// перерисовывалась бы при каждом обновлении, а ничто не должно
    /// двигаться само (P113).
    private static let strokes: [Double] = [0.30, 0.13, 0.42, 0.18, 0.26, 0.55,
                                            0.16, 0.34, 0.21, 0.47, 0.12, 0.38]
    private static let gaps: [CGFloat] = [1.1, 0.8, 1.4, 0.9, 1.2, 0.8, 1.3, 1.0]
}
