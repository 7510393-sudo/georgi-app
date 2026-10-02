import SwiftUI
import UIKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

/// Фотографии дня: как их класть в папку и как показывать.
///
/// Фотография — обычный файл в папке «Фотографии», запись дня ссылается на
/// него строкой. Ничего не встраивается в текст: запись остаётся простым
/// текстом, а снимок — снимком, который открывается чем угодно (P200).
enum Photo {

    /// Снимок как файл — в том формате, в котором его снял iPhone (P365):
    /// HEIC остаётся HEIC, JPEG — JPEG. Прежде всё перегонялось в JPEG, и
    /// снимок вырастал на 30–50% без всякой пользы.
    ///
    /// Сжатие — по настройке: «без сжатия» — файл как есть, байт в байт;
    /// «среднее» — 2560 точек по длинной стороне; «высокое» — 1600.
    /// Сведения снимка — где и когда он сделан — переносятся вместе с ним:
    /// из них потом берётся геометка дня. Возвращает данные и расширение.
    static func stored(from data: Data) -> (data: Data, ext: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let type = (CGImageSourceGetType(source) as String?) ?? UTType.jpeg.identifier
        let isJPEG = UTType(type)?.conforms(to: .jpeg) ?? false
        let side: CGFloat
        switch Prefs.squeezeKey {
        case "high":   side = 2560
        case "medium": side = 1600
        default:
            return (data, UTType(type)?.preferredFilenameExtension.map(Photo.ext) ?? "jpg")
        }
        // Уменьшенный снимок — тем же форматом. Снимок iPhone — HEIC;
        // снятый «как совместимый» — JPEG; прочее (снимки экрана в PNG) —
        // HEIC, родной формат iPhone. Не вышло записать HEIC — JPEG.
        if !isJPEG, let out = shrunk(source, side: side, as: .heic, quality: 0.7) {
            return (out, "heic")
        }
        let quality: CGFloat = side > 2000 ? 0.8 : 0.72
        guard let out = shrunk(source, side: side, as: .jpeg, quality: quality) else {
            return (data, UTType(type)?.preferredFilenameExtension.map(Photo.ext) ?? "jpg")
        }
        return (out, "jpg")
    }

    /// «jpeg» → «jpg»: привычнее и короче; остальное как есть.
    private static func ext(_ e: String) -> String { e.lowercased() == "jpeg" ? "jpg" : e.lowercased() }

    /// Снимок, уменьшенный по длинной стороне (меньший не растягивается),
    /// со сведениями оригинала. Поворот уже применён — в сведениях он
    /// сбрасывается, иначе снимок повернулся бы дважды.
    private static func shrunk(_ source: CGImageSource, side: CGFloat, as type: UTType,
                               quality: CGFloat) -> Data? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: side] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let out = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(
                out, type.identifier as CFString, 1, nil)
        else { return nil }
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        props[kCGImagePropertyPixelWidth] = nil
        props[kCGImagePropertyPixelHeight] = nil
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(target, image, props as CFDictionary)
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

    /// Первый кадр видео, уменьшенный до `side` точек (P214).
    static func poster(_ url: URL, side: CGFloat) async -> UIImage? {
        guard let ready = await Task.detached(operation: { Attachment.fetch(url) }).value
        else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: ready))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side * 3, height: side * 3)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame)
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
    /// Видео: вместо снимка — его первый кадр и знак «играть» (P214).
    var video = false
    @State private var image: UIImage?

    init(url: URL?, video: Bool = false) {
        self.url = url
        self.video = video
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
                    Image(systemName: video ? "video" : "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(Look.inkFaint)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .task(id: url) { await load() }
    }

    private func load() async {
        guard image == nil, let url else { return }
        let got: UIImage?
        if video {
            got = await Photo.poster(url, side: 160)
        } else {
            got = await Task.detached(priority: .userInitiated) {
                Photo.load(url, side: 280)
            }.value
        }
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
/// Превью берут долгим нажатием, без всякого режима (P362).
struct PhotoStrip: View {

    let photos: [URL?]
    var onOpen: ((Int) -> Void)?
    /// Что понесёт палец, взяв превью: строку-ссылку на снимок. Задано —
    /// превью можно взять долгим нажатием и бросить в текст (P204).
    var drag: ((Int) -> String)?
    /// Переставить превью в полоске — перетаскиванием вбок (P210).
    var onMove: ((Int, Int) -> Void)?
    /// Снимок принесли сюда из-под дела в плане — вернуть его в полоску
    /// (P358). Пусто — полоска чужих снимков не принимает.
    var onTake: ((String) -> Void)? = nil

    /// Превью, которое сейчас несут, — по нему соседи расступаются.
    @State private var carrying: Int?

    /// На 10% крупнее прежних 54 и вплотную, без промежутков (P275).
    static let side: CGFloat = 60
    private let gap: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let fits = max(1, Int((geo.size.width + gap) / (Self.side + gap)))
            let shown = photos.count > fits ? fits - 1 : photos.count
            HStack(spacing: gap) {
                ForEach(0..<shown, id: \.self) { i in
                    cell(i)
                }
                if photos.isEmpty {
                    Text(T("Сюда — вернуть снимок вниз", "Drop here to move a photo back down"))
                        .font(Look.sans(12))
                        .foregroundStyle(Look.inkFaint)
                        .frame(height: Self.side)
                }
                if photos.count > shown {
                    more(photos.count - shown, from: shown)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            // Мимо превью — на пустое место полоски — тоже можно вернуть
            // снимок из-под дела (P358).
            .onDrop(of: onTake != nil ? [UTType.plainText] : [], isTargeted: nil) { providers in
                guard let onTake else { return false }
                return PhotoDrop.read(providers, onTake)
            }
        }
        .frame(height: Self.side)
        .onChange(of: photos.count) { _, _ in carrying = nil }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func kind(_ i: Int) -> Diary.Kind {
        photos[i].map { Diary.kind(of: $0.lastPathComponent) } ?? .photo
    }

    /// Снимок — уменьшенной картинкой; голос и документ — плиткой с
    /// значком и расширением (P209).
    @ViewBuilder private func face(_ i: Int) -> some View {
        switch kind(i) {
        case .photo:
            PhotoThumb(url: photos[i])
        case .video:
            PhotoThumb(url: photos[i], video: true)
        case .audio:
            FileTile(icon: "waveform", label: T("голос", "voice"))
        case .file:
            FileTile(icon: "doc.text",
                     label: photos[i].map { $0.pathExtension.lowercased() } ?? T("файл", "file"))
        }
    }

    private func cell(_ i: Int) -> some View {
        face(i)
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?(i) }
            // Бросить в текст можно только снимок: голос и документ
            // остаются в полоске (P204, P209).
            .modifier(Carried(
                on: onMove != nil || (drag != nil && kind(i) == .photo),
                text: kind(i) == .photo ? drag.map { $0(i) } : nil,
                start: { carrying = i }))
            .onDrop(of: onMove != nil || onTake != nil ? [UTType.plainText, Carried.strip] : [],
                    delegate: StripDrop(index: i, carrying: $carrying, move: onMove, take: onTake))
            .accessibilityLabel(kind(i) == .photo ? T("Фотография \(i + 1)", "Photo \(i + 1)")
                                : kind(i) == .video ? T("Видео", "Video")
                                : kind(i) == .audio ? T("Голосовая запись", "Voice note") : T("Файл", "File"))
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
            .accessibilityLabel(T("Ещё фотографий: \(n)", "More photos: \(n)"))
    }
}

/// Плитка голоса или документа в полоске.
struct FileTile: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18))
            Text(label).font(Look.sans(9.5)).lineLimit(1)
        }
        .foregroundStyle(Look.inkSoft)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
    }
}

/// Превью, которое можно взять пальцем. Несёт строку-ссылку: поле записи
/// принимает её как текст и рисует на её месте снимок.
///
/// Снимок несёт строку-ссылку как текст: поле записи принимает её и рисует
/// снимок на её месте (P204). Голос и документ несут только свою метку:
/// в текст их не бросить, только переставить в полоске (P209, P210).
struct Carried: ViewModifier {
    let on: Bool
    let text: String?
    let start: () -> Void

    /// Своя метка превью из полоски — её понимает только сама полоска.
    static let strip = UTType(importedAs: "com.kobiashvili.diary.strip")

    func body(content: Content) -> some View {
        if on {
            content.onDrag {
                start()
                // Толчок в тот миг, когда снимок оторвался от места (P358).
                Feel.light()
                if let text { return NSItemProvider(object: ("\n" + text) as NSString) }
                let item = NSItemProvider()
                item.registerDataRepresentation(forTypeIdentifier: Carried.strip.identifier,
                                                visibility: .ownProcess) { done in
                    done(Data(), nil)
                    return nil
                }
                return item
            }
        } else {
            content
        }
    }
}

/// Превью несут вдоль полоски: соседи расступаются, превью встаёт туда,
/// где его отпустили (P210). Снимок, принесённый не из полоски, — из-под
/// дела в плане — возвращается в неё (P358).
private struct StripDrop: DropDelegate {
    let index: Int
    @Binding var carrying: Int?
    let move: ((Int, Int) -> Void)?
    var take: ((String) -> Void)? = nil

    func dropEntered(info: DropInfo) {
        guard let from = carrying, from != index else { return }
        withAnimation(.easeOut(duration: 0.18)) { move?(from, index) }
        carrying = index
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        let ours = carrying != nil
        carrying = nil
        guard !ours, let take else { return true }
        return PhotoDrop.read(info.itemProviders(for: [UTType.plainText]), take)
    }
}

/// Строка-ссылка снимка, которую принёс палец, — из системного переноса.
enum PhotoDrop {
    /// Прочитать первую ссылку на снимок и отдать её. `false` — нечего.
    static func read(_ providers: [NSItemProvider], _ take: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) })
        else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let text = (item as? NSString).map({ $0 as String }),
                  let link = Diary.anywhere(in: text).first?.link
            else { return }
            DispatchQueue.main.async {
                Feel.light()
                take(link)
            }
        }
        return true
    }
}

/// Снимки под делом в плане — в ряд, а не столбиком (P358). В режиме
/// изменений каждый можно взять пальцем и унести под другое дело или
/// назад в полоску внизу.
struct PlanPhotoRow: View {
    let links: [String]
    var resolve: ((String) -> URL?)?
    var open: ((URL?) -> Void)?
    /// Снимок несут пальцем под другое дело или назад в полоску (P377):
    /// своим жестом, а не системным перетаскиванием, — чтобы строки
    /// расступались там, куда он встанет. Ход и место пальца на экране.
    var onCarry: ((String, Lift, CGPoint) -> Void)?
    /// Снимок, который сейчас несут, — на своём месте он бледный.
    var carried: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(links, id: \.self) { link in
                    PlanPhotoThumb(url: resolve?(link)) { open?(resolve?(link)) }
                        .opacity(carried == link ? 0.25 : 1)
                        .modifier(ThumbCarry(report: report(link)))
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollDisabled(links.count < 4 || carried != nil)
        .frame(height: PlanPhotoLine.height)
    }
    private func report(_ link: String) -> ((Lift, CGPoint) -> Void)? {
        guard let onCarry else { return nil }
        return { phase, spot in onCarry(link, phase, spot) }
    }
}

/// Снимок под делом берут долгим нажатием и ведут (P377). Сам он остаётся
/// на месте — за пальцем идёт его копия, нарисованная планом поверх всего.
struct ThumbCarry: ViewModifier {
    let report: ((Lift, CGPoint) -> Void)?

    @State private var lifted = false
    @GestureState private var holding = false

    func body(content: Content) -> some View {
        if let report {
            content
                .gesture(LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .updating($holding) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if !lifted {
                            lifted = true
                            report(.began, drag?.location ?? .zero)
                        }
                        if let drag { report(.moved(drag.translation), drag.location) }
                    }
                    .onEnded { value in
                        guard lifted else { return }
                        lifted = false
                        var spot = CGPoint.zero
                        if case .second(true, let drag) = value, let drag { spot = drag.location }
                        report(.ended(.zero), spot)
                    })
                .onChange(of: holding) { _, now in
                    guard !now else { return }
                    DispatchQueue.main.async {
                        guard lifted else { return }
                        lifted = false
                        report(.cancelled, .zero)
                    }
                }
        } else {
            content
        }
    }
}

struct PlanPhotoThumb: View {
    let url: URL?
    var onOpen: (() -> Void)?
    @State private var image: UIImage?

    init(url: URL?, onOpen: (() -> Void)? = nil) {
        self.url = url
        self.onOpen = onOpen
        _image = State(initialValue: url.flatMap { Photo.cache.object(forKey: PhotoAttachment.key($0)) })
    }

    var body: some View {
        Image(uiImage: image ?? PhotoAttachment.empty)
            .resizable()
            .frame(width: DiaryEditor.photoSize.width, height: DiaryEditor.photoSize.height)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
            .task(id: url) {
                guard image == nil, let url else { return }
                let got = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let raw = Photo.load(url, side: 280) else { return nil }
                    return PhotoAttachment.frame(raw)
                }.value
                guard let got else { return }
                Photo.cache.setObject(got, forKey: PhotoAttachment.key(url))
                image = got
            }
            .accessibilityLabel(T("Фотография", "Photo"))
    }
}

/// Снимок во весь экран.
struct PhotoViewer: View {

    let url: URL?
    /// Убрать снимок из записи; `true` — и удалить файл в корзину (P371).
    /// Пусто — день закрыт для правки.
    var onRemove: ((Bool) -> Void)?
    /// Вернуть снимок из текста в полоску внизу (P216).
    var onReturn: (() -> Void)?
    let close: () -> Void
    /// Листнули вбок: +1 — следующий снимок, −1 — прежний (P278).
    var onSwipe: ((Int) -> Void)?

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var asking = false
    /// Насколько снимок стянут пальцем вниз (P270).
    @State private var pulled: CGSize = .zero
    /// Насколько снимок сдвинут вбок, пока его листают (P278).
    @State private var slid: CGFloat = 0
    /// Куда пошёл палец: решается по первому движению.
    @State private var sideways: Bool?

    /// Как далеко стянут: 0 — на месте, 1 — почти ушёл.
    private var gone: CGFloat { min(1, max(0, pulled.height) / 420) }

    var body: some View {
        ZStack {
            // Фон светлеет, пока снимок тянут вниз: под ним видна страница,
            // как в «Фото» Apple.
            Color.black.opacity(1 - gone).ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale * (1 - gone * 0.3))
                    .offset(x: pulled.width * 0.6 + slid, y: max(0, pulled.height))
                    .gesture(MagnificationGesture()
                        .onChanged { scale = max(1, $0) }
                        .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scale = 1 } })
                    .simultaneousGesture(swipeDown)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) { bar.opacity(pulled == .zero ? 1 : 0) }
        // Под снимком — страница: её видно, пока снимок стягивают.
        .presentationBackground(.clear)
        .task {
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) {
                Photo.load(url, side: 1400)
            }.value
        }
        .modifier(RemoveQuestion(asking: $asking, act: onRemove))
    }


    /// Свайп вниз убирает снимок, как в «Фото» Apple (P270): потянул
    /// и отпустил — снимок уходит; не дотянул — возвращается на место.
    /// Увеличенный снимок не стягивается: там палец двигает картинку.
    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard scale == 1 else { return }
                // Куда пошёл палец — решается один раз: вбок листают
                // снимки, вниз — убирают (P278, P270). Одним жестом, чтобы
                // один не перехватывал другой.
                if sideways == nil {
                    sideways = abs(v.translation.width) > abs(v.translation.height)
                }
                if sideways == true {
                    guard onSwipe != nil else { return }
                    slid = v.translation.width
                } else if v.translation.height > 0 || pulled != .zero {
                    pulled = v.translation
                }
            }
            .onEnded { v in
                defer { sideways = nil }
                guard scale == 1 else { return }
                if sideways == true, let onSwipe {
                    let far = abs(slid) > 70 || abs(v.predictedEndTranslation.width) > 220
                    if far {
                        let step = slid < 0 ? 1 : -1
                        slid = 0
                        onSwipe(step)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { slid = 0 }
                    }
                    return
                }
                guard pulled != .zero else { return }
                if pulled.height > 110 || v.predictedEndTranslation.height > 280 {
                    Feel.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        pulled = CGSize(width: pulled.width, height: UIScreen.main.bounds.height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        var still = Transaction()
                        still.disablesAnimations = true
                        withTransaction(still) { close() }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { pulled = .zero }
                }
            }
    }

    private var bar: some View {
        HStack {
            Button(T("Готово", "Done"), action: close)
                .fontWeight(.semibold)
            Spacer()
            if let url {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
            if let onReturn {
                Button(action: onReturn) {
                    Label(T("В полоску", "To the strip"), systemImage: "arrow.down.to.line")
                        .font(.system(size: 15))
                }
                .padding(.leading, 18)
                .accessibilityLabel(T("Вернуть в полоску внизу страницы", "Move back to the strip at the bottom"))
            }
            if onRemove != nil {
                Button { asking = true } label: { Image(systemName: "trash") }
                    .padding(.leading, 18)
                    .accessibilityLabel(T("Убрать из записи", "Remove from entry"))
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
                guard let raw = Photo.load(url, side: 280) else { return nil }
                return PhotoAttachment.frame(raw)
            }.value
            guard let got else { return }
            Photo.cache.setObject(got, forKey: PhotoAttachment.key(url))
            image = got
        }
        .accessibilityLabel(T("Фотография", "Photo"))
    }
}

/// Вложения полоски во весь экран — листаются вбок (P278): влево —
/// следующее в полоске, вправо — прежнее. Жест один с «убрать вниз», в
/// самом просмотре снимка: общий листатель перехватывал бы то одно, то
/// другое. Видео, голос и документ вбок не листаются — там свои жесты.
struct StripViewer: View {
    let count: Int
    let url: (Int) -> URL?
    var remove: ((Int, Bool) -> Void)?
    let close: () -> Void

    @State private var index: Int
    @State private var forward = true

    init(count: Int, start: Int, url: @escaping (Int) -> URL?,
         remove: ((Int, Bool) -> Void)?, close: @escaping () -> Void) {
        self.count = count
        self.url = url
        self.remove = remove
        self.close = close
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            AttachmentViewer(url: url(index),
                             onRemove: remove.map { r in { r(index, $0) } },
                             onReturn: nil,
                             close: close,
                             onSwipe: step)
                .id(index)
                .transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading),
                    removal: .move(edge: forward ? .leading : .trailing)))
        }
        .presentationBackground(.clear)
    }

    private func step(_ by: Int) {
        let next = index + by
        guard (0..<count).contains(next) else { return Feel.light() }
        forward = by > 0
        Feel.tick()
        withAnimation(.easeOut(duration: 0.22)) { index = next }
    }
}

/// Удаление вложения (P371): убрать только со страницы или удалить и сам
/// файл — в корзину на 30 дней. Одно окно на снимки, видео, голос и
/// документы.
struct RemoveQuestion: ViewModifier {
    @Binding var asking: Bool
    let act: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        content.confirmationDialog(T("Что сделать с файлом?", "What should happen to the file?"),
                                   isPresented: $asking, titleVisibility: .visible) {
            Button(T("Убрать со страницы", "Remove from the page")) { act?(false) }
            Button(T("Удалить из хранилища", "Delete from storage"), role: .destructive) { act?(true) }
            Button(T("Отмена", "Cancel"), role: .cancel) { }
        } message: {
            Text(T("«Убрать со страницы» — файл останется в папке. «Удалить из хранилища» — файл уйдёт в корзину на 30 дней: вернуть его можно в Настройки → Корзина, потом он сотрётся насовсем.",
                   "“Remove from the page” keeps the file in the folder. “Delete from storage” moves it to the trash for 30 days: you can restore it in Settings → Trash; after that it is erased for good."))
        }
    }
}
