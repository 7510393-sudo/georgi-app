import SwiftUI

/// Приклеенная бумажка.
///
/// Свешивается с верхнего края, закрывая часть экрана: из-под неё видно,
/// где человек остался. Не отдельная страница и не лист снизу — канцелярский
/// стикер, приклеенный к стенке. Меню страницы на жёлтой бумаге, настройки
/// на голубой; порода одна, чтобы рука узнавала их одинаково.
/// С какого края приклеена бумажка. Отдельно от самой бумажки: обводке
/// эта сторона тоже нужна, а через обобщённый тип она не проходит.
enum StickerSide { case leading, trailing }

struct Sticker<Content: View>: View {

    let side: StickerSide
    let title: String
    var paper: Color = Look.sticker
    var edge: Color = Look.stickerEdge
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: side == .trailing ? .topTrailing : .topLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            sheet
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            head
            content()
        }
        .frame(maxWidth: 262)
        .background(paper)
        .clipShape(shape)
        .overlay(StickerBorder(radius: 12, side: side).stroke(edge, lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
        .padding(side == .trailing ? .leading : .trailing, 60)
    }

    private var shape: UnevenRoundedRectangle {
        side == .trailing
            ? UnevenRoundedRectangle(bottomLeadingRadius: 12)
            : UnevenRoundedRectangle(bottomTrailingRadius: 12)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 8) {
            if side == .leading { closeButton }
            if side == .trailing { label; Spacer(minLength: 0); closeButton }
            else { Spacer(minLength: 0); label }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(edge).frame(height: 1)
        }
    }

    private var label: some View {
        Text(title.uppercased())
            .font(Look.sans(11.5))
            .tracking(1.15)
            .foregroundStyle(Look.inkFaint)
            .padding(.top, 22)
            .padding(.horizontal, 14)
    }

    private var closeButton: some View {
        Button(action: close) {
            Text("✕")
                .font(.system(size: 19))
                .foregroundStyle(Look.inkSoft)
                .frame(width: 44, height: 38)
        }
        .padding(.top, 12)
        .accessibilityLabel("Закрыть")
    }
}

/// Строка бумажки.
struct StickerItem: View {

    let title: String
    var note = "→"
    var active = false
    var edge: Color = Look.stickerEdge
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Look.sans(14, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Look.accent : Look.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(note)
                    .font(Look.sans(11.5))
                    .foregroundStyle(Look.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(edge).frame(height: 1)
        }
    }
}

/// Обводка бумажки: низ и внутренний бок. Сверху и со своего края она
/// приклеена — там обводки нет.
struct StickerBorder: Shape {

    let radius: CGFloat
    var side: StickerSide = .trailing

    func path(in r: CGRect) -> Path {
        var p = Path()
        if side == .trailing {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
            p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                     startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
            p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        return p
    }
}
