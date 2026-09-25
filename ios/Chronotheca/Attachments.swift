import SwiftUI
import UIKit
import AVFoundation
import QuickLook
import UniformTypeIdentifiers

// MARK: - Голос

/// Запись голоса. Одна большая кнопка: нажал — пишет, нажал ещё раз —
/// готово. Запись ложится файлом в «Аудио», ссылкой — в файл дня (P209).
struct Recorder: View {

    /// Готовая запись — временный файл; положить его в папку — забота
    /// того, кто позвал.
    let done: (URL) -> Void
    let cancel: () -> Void

    @State private var recorder: AVAudioRecorder?
    @State private var started: Date?
    @State private var denied = false

    var body: some View {
        VStack(spacing: 22) {
            Text(started == nil ? "Голосовая запись" : "Идёт запись")
                .font(Look.sans(17, weight: .semibold))
                .foregroundStyle(Look.ink)

            TimelineView(.periodic(from: .now, by: 0.5)) { clock in
                Text(Recorder.clock(started.map { clock.date.timeIntervalSince($0) } ?? 0))
                    .font(Look.mono(34))
                    .foregroundStyle(started == nil ? Look.inkFaint : Look.ink)
            }

            Button(action: toggle) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.12)).frame(width: 96, height: 96)
                    if started == nil {
                        Circle().fill(Color.red).frame(width: 64, height: 64)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color.red)
                            .frame(width: 34, height: 34)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(started == nil ? "Начать запись" : "Закончить запись")

            if denied {
                Text("Приложению не разрешён микрофон. Разрешить можно в Настройках iPhone → Chronotheca.")
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("Отмена") {
                recorder?.stop()
                recorder?.deleteRecording()
                cancel()
            }
            .font(Look.sans(15))
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.chrome)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func toggle() {
        if let recorder, started != nil {
            recorder.stop()
            try? AVAudioSession.sharedInstance().setActive(false)
            started = nil
            done(recorder.url)
            return
        }
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { denied = true; return }
                begin()
            }
        }
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record() else { return }
            recorder = r
            started = Date()
        } catch {
            denied = true
        }
    }
}

/// Прослушать голосовую запись.
struct AudioPlayerView: View {

    let url: URL?

    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Look.inkSoft)
            Text(url.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? "")
                .font(Look.mono(13))
                .foregroundStyle(Look.inkSoft)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let length = player?.duration ?? 0
                let at = player?.currentTime ?? 0
                VStack(spacing: 6) {
                    ProgressView(value: length > 0 ? at / length : 0)
                        .tint(Look.accent)
                    HStack {
                        Text(Recorder.clock(at))
                        Spacer()
                        Text(Recorder.clock(length))
                    }
                    .font(Look.mono(12))
                    .foregroundStyle(Look.inkFaint)
                }
                .padding(.horizontal, 32)
                .onChange(of: player?.isPlaying ?? false) { _, now in playing = now }
            }
            Button {
                guard let player else { return }
                if player.isPlaying { player.pause() } else { player.play() }
                playing = player.isPlaying
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Look.accent)
            }
            .buttonStyle(.plain)
            if failed {
                Text("Запись не открылась — возможно, она ещё не скачана из iCloud.")
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
            }
        }
        .task {
            guard let url else { return }
            let data = await Task.detached { Attachment.read(url) }.value
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            guard let data, let p = try? AVAudioPlayer(data: data) else { failed = true; return }
            p.prepareToPlay()
            player = p
        }
        .onDisappear { player?.stop() }
    }
}

// MARK: - Документы

/// Системное окно выбора файлов. Файл копируется: приложению не нужен
/// доступ к чужой папке — только к самому документу, и только в эту минуту.
struct DocumentPicker: UIViewControllerRepresentable {

    let pick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(pick: pick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let pick: ([URL]) -> Void
        init(pick: @escaping ([URL]) -> Void) { self.pick = pick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) { pick(urls) }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { pick([]) }
    }
}

/// Показ документа — системный, тот же, что в «Файлах».
struct QuickLookView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return preview
    }

    func updateUIViewController(_ preview: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

// MARK: - Общее

enum Attachment {

    /// Прочитать вложение через системного посредника — он дождётся, пока
    /// файл придёт из iCloud.
    static func read(_ url: URL) -> Data? {
        var data: Data?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                data = try? Data(contentsOf: real)
            }
        return data
    }

    /// Скачать вложение, если оно в iCloud, и вернуть путь к нему.
    static func fetch(_ url: URL) -> URL? {
        var ready: URL?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                ready = FileManager.default.fileExists(atPath: real.path) ? url : nil
            }
        return ready
    }
}

/// Вложение во весь экран: снимок, голос или документ.
struct AttachmentViewer: View {

    let url: URL?
    var onRemove: (() -> Void)?
    let close: () -> Void

    @State private var ready: URL?
    @State private var asking = false

    var body: some View {
        switch url.map({ Diary.kind(of: $0.lastPathComponent) }) ?? .photo {
        case .photo:
            PhotoViewer(url: url, onRemove: onRemove, close: close)
        case .audio:
            framed { AudioPlayerView(url: url) }
        case .file:
            framed {
                if let ready { QuickLookView(url: ready) } else { ProgressView() }
            }
            .task {
                guard let url else { return }
                ready = await Task.detached { Attachment.fetch(url) }.value
            }
        }
    }

    private func framed<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        NavigationStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Look.chrome)
                .navigationTitle(url?.lastPathComponent ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Готово", action: close).fontWeight(.semibold)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 18) {
                            if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                            if onRemove != nil {
                                Button { asking = true } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Убрать со страницы")
                            }
                        }
                    }
                }
                .confirmationDialog("Убрать со страницы?", isPresented: $asking,
                                    titleVisibility: .visible) {
                    Button("Убрать", role: .destructive) { onRemove?() }
                } message: {
                    Text("Сам файл останется в папке — удалить его можно в «Файлах».")
                }
        }
    }
}
