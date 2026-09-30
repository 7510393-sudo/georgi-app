import SwiftUI
import Photos
import UIKit

/// Снимки галереи, сделанные в этот день, — рядом над полоской вложений,
/// как в Diarium (P273, P344). Касание открывает снимок во весь экран:
/// «Добавить» справа кладёт его в день, «Отменить» слева — назад к ряду
/// (P344). Первая плитка «Все фото» открывает обычное окно галереи — там
/// же видео, поиск и снимки других дней.
///
/// Разрешение смотреть галерею спрашивается, когда ряд открыли впервые.
/// Не дали — ряд говорит, где разрешить, а «Все фото» работает и без
/// него: то окно не просит доступа ко всей галерее.
struct GalleryRow: View {

    /// День страницы: в ряду — снимки, сделанные в этот день, по той же
    /// границе суток, что и у самого приложения.
    var day: Date = DayStore.today()
    let add: (PHAsset) -> Void
    let more: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var loaded = false
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Снимки, уже положенные в этот раз, — отмечены галочкой, чтобы не
    /// положить дважды.
    @State private var taken: Set<String> = []
    /// Снимок, открытый во весь экран.
    @State private var looking: Looked?

    struct Looked: Identifiable {
        let asset: PHAsset
        var id: String { asset.localIdentifier }
    }

    static let height: CGFloat = PhotoStrip.side + 16

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Button(action: more) {
                    VStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17))
                        Text("все фото").font(Look.sans(9.5))
                    }
                    .foregroundStyle(Look.accent)
                    .frame(width: PhotoStrip.side, height: PhotoStrip.side)
                    .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
                }
                .buttonStyle(.plain)
                if status == .denied || status == .restricted {
                    Text("Галерея закрыта для приложения: Настройки iPhone → Хронотека → Фото")
                        .font(Look.sans(12))
                        .foregroundStyle(Look.inkSoft)
                        .frame(width: 230, alignment: .leading)
                } else if loaded && assets.isEmpty {
                    Text("За этот день снимков в галерее нет. Другие — в «все фото».")
                        .font(Look.sans(12))
                        .foregroundStyle(Look.inkSoft)
                        .frame(width: 230, alignment: .leading)
                        .padding(.leading, 10)
                }
                ForEach(assets, id: \.localIdentifier) { asset in
                    GalleryThumb(asset: asset)
                        .overlay(alignment: .topTrailing) {
                            if taken.contains(asset.localIdentifier) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white, Look.accent)
                                    .padding(3)
                            }
                        }
                        .onTapGesture { looking = Looked(asset: asset) }
                        .accessibilityLabel("Снимок из галереи")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: Self.height)
        .background(Look.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Look.rule).frame(height: 1) }
        .task { await load() }
        .fullScreenCover(item: $looking) { looked in
            GalleryPreview(asset: looked.asset,
                           already: taken.contains(looked.id),
                           cancel: { looking = nil },
                           add: {
                               taken.insert(looked.id)
                               Feel.light()
                               add(looked.asset)
                               looking = nil
                           })
        }
    }

    private func load() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        // Сутки дня — с той же границы, что у приложения: снимок в час ночи
        // принадлежит ещё вчерашнему дню (P17).
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: DayStore.boundaryHour,
                             to: cal.startOfDay(for: day)) ?? day
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 120
        let found = PHAsset.fetchAssets(with: .image, options: options)
        var list: [PHAsset] = []
        found.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
        loaded = true
    }

    /// Снимок целиком — чтобы положить его в папку как есть (A6: только
    /// оригинал). Из iCloud докачивается.
    static func data(of asset: PHAsset, done: @escaping (Data?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            DispatchQueue.main.async { done(data) }
        }
    }
}

/// Уменьшенный снимок из галереи.
struct GalleryThumb: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Look.chrome
            }
        }
        .frame(width: PhotoStrip.side, height: PhotoStrip.side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onAppear {
            guard image == nil else { return }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: CGSize(width: 160, height: 160),
                                                  contentMode: .aspectFill,
                                                  options: options) { got, _ in
                if let got { image = got }
            }
        }
    }
}

/// Снимок из ряда галереи во весь экран: рассмотреть, прежде чем класть в
/// день (P344). Внизу слева — «Отменить», справа — «Добавить»: палец
/// сам решает, без галочек.
struct GalleryPreview: View {
    let asset: PHAsset
    /// Снимок уже положен в этот раз — второй раз не кладётся.
    let already: Bool
    let cancel: () -> Void
    let add: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea(edges: .horizontal)
            } else {
                ProgressView().tint(.white)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: cancel) {
                    Text("Отменить")
                        .font(Look.sans(17))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                Spacer()
                Button(action: add) {
                    Text(already ? "Уже добавлен" : "Добавить")
                        .font(Look.sans(17, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(already ? Color.white.opacity(0.14) : Look.glow, in: Capsule())
                }
                .disabled(already)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear(perform: load)
    }

    private func load() {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        let scale = UIScreen.main.scale
        let size = CGSize(width: UIScreen.main.bounds.width * scale,
                          height: UIScreen.main.bounds.height * scale)
        PHImageManager.default().requestImage(for: asset, targetSize: size,
                                              contentMode: .aspectFit,
                                              options: options) { got, _ in
            if let got { image = got }
        }
    }
}

/// Камера iPhone — снимок сразу в день (P289). Снимок ложится в папку
/// «Фотографии» так же, как выбранный из галереи.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            done(image?.jpegData(compressionQuality: 0.92))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil)
        }
    }
}
