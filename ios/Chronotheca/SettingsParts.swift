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
        HStack(spacing: 8) {
            Text(title)
                .font(Look.serif(15.5, weight: .semibold))
                .foregroundStyle(Look.accent)
                .fixedSize()
            Rectangle().fill(Look.accent.opacity(0.3)).frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 2)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Look.noteEdge).frame(height: 1).padding(.horizontal, 14)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Look.sans(14.5))
                .foregroundStyle(Look.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(Look.sans(11.5))
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
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let (value, name) = options[i]
                let on = value == selection
                Button {
                    guard !on else { return }
                    Feel.tick()
                    selection = value
                } label: {
                    Text(name)
                        .font(Look.sans(12.5, weight: on ? .semibold : .regular))
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
                .font(Look.sans(12.5, weight: .semibold))
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
