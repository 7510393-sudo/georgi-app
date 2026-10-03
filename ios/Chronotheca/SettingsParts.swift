import SwiftUI

// Детали настроек в духе тетради на голубой записке (P367).
//
// Кнопок три вида, и они различаются на глаз:
// — кружки-выбор: видны все варианты, выбранный закрашен синим;
// — «Открыть ›»: открывает окно или листок, сама ничего не меняет;
// — одна главная кнопка (резервная копия): закрашена целиком.
// Нажимается только кнопка — название строки не меняет ничего. Прежде
// касание по строке молча перебирало варианты по кругу, и не было видно,
// что ещё бывает и что сейчас изменится.

/// Заголовок раздела: синим засечным, с чертой до края — как в тетради.
struct NoteSection: View {
    let title: String

    var body: some View {
        // Заголовок раздела — крупнее и без черты до края (P381): разделы
        // отделены воздухом и плашками строк, а не линиями.
        Text(title)
            .font(Look.serif(19, weight: .semibold))
            .foregroundStyle(Look.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

/// Строка настроек: название (и мелко — пояснение) и кнопки. Помещаются
/// в одну линию — стоят в линию; нет — кнопки уходят под название.
struct NoteRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var detailColor: Color = Look.inkSoft
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 4)
                trailing()
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Каждая строка — своя плашка, без линий под ней (P381).
        .background(Look.planBg.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Look.noteEdge.opacity(0.6), lineWidth: 0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Look.sans(16))
                .foregroundStyle(Look.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Look.sans(12.5))
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Кружки-выбор: все варианты на виду, выбранный закрашен.
struct Choice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        // Не помещаются в строку — переходят на следующую, а не уходят за
        // край записки (P383).
        Flow(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let (value, name) = options[i]
                let on = value == selection
                Button {
                    guard !on else { return }
                    Feel.tick()
                    selection = value
                } label: {
                    Text(name)
                        .font(Look.sans(13.5, weight: on ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Look.note : Look.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(on ? Look.accent : Color.clear))
                        .overlay(Capsule().strokeBorder(Look.accent, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// «Открыть ›» и главная кнопка.
struct NoteButton: View {
    let title: String
    var main = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Look.sans(13.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(main ? Look.note : Look.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(Capsule().fill(main ? Look.accent : Look.planBg))
                .overlay(Capsule().strokeBorder(main ? Look.accent : Look.noteEdge, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Кнопки в ряд; не помещаются — переходят на следующую строку (P383).
/// Прежде длинные русские варианты («как iPhone», «без сжатия») стояли
/// одной строкой и уходили за край записки.
struct Flow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let wide = rows.map(\.width).max() ?? 0
        let high = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: wide, height: high)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                  proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let need = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, need > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
