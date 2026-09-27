import SwiftUI
import Photos

/// Последние снимки галереи — рядом над полоской вложений, как в Diarium
/// (P273). Касание кладёт снимок в день; первая плитка «Все фото»
/// открывает обычное окно галереи — там же видео и поиск.
///
/// Разрешение смотреть галерею спрашивается, когда ряд открыли впервые.
/// Не дали — ряд говорит, где разрешить, а «Все фото» работает и без
/// него: то окно не просит доступа ко всей галерее.
struct GalleryRow: View {

    let add: (PHAsset) -> Void
    let more: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Снимки, уже положенные в этот раз, — отмечены галочкой.
    @State private var taken: Set<String> = []

    static let height: CGFloat = PhotoStrip.side + 16

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
                        .onTapGesture {
                            guard !taken.contains(asset.localIdentifier) else { return }
                            taken.insert(asset.localIdentifier)
                            Feel.light()
                            add(asset)
                        }
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
    }

    private func load() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 60
        let found = PHAsset.fetchAssets(with: .image, options: options)
        var list: [PHAsset] = []
        found.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
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
