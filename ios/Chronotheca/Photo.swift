import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Фотографии дня: как их класть в папку и как показывать.
///
/// Фотография — обычный файл в папке «Фотографии», запись дня ссылается на
/// него строкой. Ничего не встраивается в текст: запись остаётся простым
/// текстом, а снимок — снимком, который открывается чем угодно (P200).
enum Photo {

    /// Снимок как файл JPEG.
    ///
    /// JPEG кладётся как есть, без пережатия. Остальное (HEIC с iPhone)
    /// переводится в JPEG: его открывает любой компьютер, а HEIC — не всякий.
    /// Сведения снимка — где и когда он сделан — переносятся вместе с ним:
    /// из них потом берётся геометка дня.
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        if (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier {
            return data
        }
        let out = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(
                out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImageFromSource(target, source, 0, options)
        guard CGImageDestinationFinalize(target) else { return nil }
        return out as Data
    }

    /// Уменьшенные снимки, уже прочитанные с диска. Страница, которую
    /// перелистнули туда и обратно, не читает их заново и не мигает.
    static let cache = NSCache<NSString, UIImage>()

    /// Прочитать снимок уменьшенным до `side` точек по большей стороне.
    ///
    /// Через системного посредника: снимок мог уйти в iCloud, и посредник
    /// дождётся, пока он придёт. Читать надо в стороне от экрана.
    static func load(_ url: URL, side: CGFloat) -> UIImage? {
        var image: UIImage?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                guard let source = CGImageSourceCreateWithURL(real as CFURL, nil) else { return }
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: side * 3,
                ] as CFDictionary
                if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                    image = UIImage(cgImage: cg)
                }
            }
        return image
    }

    /// Снимок для показа: туман над полем. Нужен только снимкам экрана.
    static func sample() -> Data {
        let size = CGSize(width: 1200, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.80, green: 0.83, blue: 0.84, alpha: 1).cgColor,
                          UIColor(red: 0.47, green: 0.55, blue: 0.50, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
            }
            UIColor(white: 0.25, alpha: 0.55).setFill()
            for i in 0..<9 {
                let x = CGFloat(i) * 140 + 30
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: 560, width: 90, height: 180))
            }
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

/// Уменьшенный снимок в клетке.
///
/// Клетка всегда одного размера, пока снимок читается, — место под него
/// уже отведено, и ничего не сдвигается, когда он приходит (P113).
struct PhotoThumb: View {

    let url: URL?
    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        _image = State(initialValue: url.flatMap { Photo.cache.object(forKey: $0.path as NSString) })
    }

    var body: some View {
        Rectangle()
            .fill(Look.chrome)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(Look.inkFaint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .task(id: url) { await load() }
    }

    private func load() async {
        guard image == nil, let url else { return }
        let got = await Task.detached(priority: .userInitiated) {
            Photo.load(url, side: 160)
        }.value
        guard let got else { return }
        Photo.cache.setObject(got, forKey: url.path as NSString)
        image = got
    }
}

/// Фотографии дня — полоска внизу страницы, над кнопками вложений, как в
/// Diarium. У плана и у дневника она своя (решение P203).
///
/// Полоска не прокручивается вбок: движение пальца вбок листает день.
/// Сколько не поместилось — показывает последняя клетка «+N»; касание по
/// ней открывает первый из не поместившихся снимков.
///
/// В режиме изменений превью подсвечены — видно, что их можно взять.
struct PhotoStrip: View {

    let photos: [URL?]
    var glowing = false
    var onOpen: ((Int) -> Void)?
    /// Что понесёт палец, взяв превью: строку-ссылку на снимок. Задано —
    /// превью можно взять долгим нажатием и бросить в текст (P204).
    var drag: ((Int) -> String)?

    static let side: CGFloat = 54
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let fits = max(1, Int((geo.size.width + gap) / (Self.side + gap)))
            let shown = photos.count > fits ? fits - 1 : photos.count
            HStack(spacing: gap) {
                ForEach(0..<shown, id: \.self) { i in
                    cell(i)
                }
                if photos.count > shown {
                    more(photos.count - shown, from: shown)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.side)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func cell(_ i: Int) -> some View {
        PhotoThumb(url: photos[i])
            .frame(width: Self.side, height: Self.side)
            .overlay {
                if glowing {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Look.glow, lineWidth: 2)
                }
            }
            .shadow(color: glowing ? Look.glow.opacity(0.8) : .clear, radius: 6)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?(i) }
            .modifier(Carried(payload: glowing ? drag.map { $0(i) } : nil))
            .accessibilityLabel("Фотография \(i + 1)")
    }

    private func more(_ n: Int, from i: Int) -> some View {
        Text("+\(n)")
            .font(Look.sans(14, weight: .medium))
            .foregroundStyle(Look.inkSoft)
            .frame(width: Self.side, height: Self.side)
            .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .contentShape(Rectangle())
            .onTapGesture { onOpen?(i) }
            .accessibilityLabel("Ещё фотографий: \(n)")
    }
}

/// Превью, которое можно взять пальцем. Несёт строку-ссылку: поле записи
/// принимает её как текст и рисует на её месте снимок.
private struct Carried: ViewModifier {
    let payload: String?

    func body(content: Content) -> some View {
        if let payload {
            content.onDrag { NSItemProvider(object: ("\n" + payload) as NSString) }
        } else {
            content
        }
    }
}

/// Снимок во весь экран.
struct PhotoViewer: View {

    let url: URL?
    /// Убрать снимок из записи. Пусто — день закрыт для правки.
    var onRemove: (() -> Void)?
    let close: () -> Void

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var asking = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture()
                        .onChanged { scale = max(1, $0) }
                        .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scale = 1 } })
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) { bar }
        .task {
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) {
                Photo.load(url, side: 1400)
            }.value
        }
        .confirmationDialog("Убрать фотографию из записи?", isPresented: $asking,
                            titleVisibility: .visible) {
            Button("Убрать из записи", role: .destructive) { onRemove?() }
        } message: {
            Text("Файл останется в папке «Фотографии» — удалить его можно в «Файлах».")
        }
    }

    private var bar: some View {
        HStack {
            Button("Готово", action: close)
                .fontWeight(.semibold)
            Spacer()
            if let url {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
            if onRemove != nil {
                Button { asking = true } label: { Image(systemName: "trash") }
                    .padding(.leading, 18)
                    .accessibilityLabel("Убрать из записи")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }
}

/// Снимок, поставленный между делами плана, — своей строкой, того же
/// размера, что снимок в тексте дневника (P204, P205).
struct PlanPhotoLine: View {

    let url: URL?
    var onOpen: (() -> Void)?
    @State private var image: UIImage?

    static let height: CGFloat = DiaryEditor.photoSize.height + 16

    init(url: URL?, onOpen: (() -> Void)? = nil) {
        self.url = url
        self.onOpen = onOpen
        _image = State(initialValue: url.flatMap { Photo.cache.object(forKey: PhotoAttachment.key($0)) })
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(uiImage: image ?? PhotoAttachment.empty)
                .resizable()
                .frame(width: DiaryEditor.photoSize.width, height: DiaryEditor.photoSize.height)
                .contentShape(Rectangle())
                .onTapGesture { onOpen?() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .task(id: url) {
            guard image == nil, let url else { return }
            let got = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let raw = Photo.load(url, side: DiaryEditor.photoSize.width) else { return nil }
                return PhotoAttachment.frame(raw)
            }.value
            guard let got else { return }
            Photo.cache.setObject(got, forKey: PhotoAttachment.key(url))
            image = got
        }
        .accessibilityLabel("Фотография")
    }
}
