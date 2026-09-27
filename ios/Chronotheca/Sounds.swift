import AVFoundation
import UIKit

/// Звуки приложения (P265, P267). Тихие и бумажные: шелест страницы,
/// шлепок листка, звон по окончании записи. Идут как звуки клавиатуры —
/// переключатель «без звука» на iPhone их глушит, музыку они не
/// прерывают. Выключаются в настройках.
enum Sounds {

    private static var cache: [String: Data] = [:]

    /// Плееры, которые ещё звучат: отпущенный плеер замолкает на полуслове.
    private static var playing: [AVAudioPlayer] = []

    static var on: Bool { !UserDefaults.standard.bool(forKey: Prefs.quiet) }

    /// Шелест перевёрнутой страницы. `rate` чуть меняет высоту: в вихре
    /// листы шуршат не одинаково.
    static func flip(volume: Float = 0.45, rate: Float = 1) {
        play("page-flip", volume: volume, rate: rate)
    }

    static func play(_ name: String, volume: Float = 0.45, rate: Float = 1) {
        guard on, let data = data(name) else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
        }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = volume
        player.enableRate = true
        player.rate = rate
        playing.removeAll { !$0.isPlaying }
        playing.append(player)
        player.play()
    }

    private static func data(_ name: String) -> Data? {
        if let known = cache[name] { return known }
        let found = Bundle.main.url(forResource: name, withExtension: "wav")
            .flatMap { try? Data(contentsOf: $0) }
        cache[name] = found
        return found
    }
}

/// Толчки в руку (P263, P267): у каждого движения свой.
enum Feel {
    /// Плашка ударилась кромкой о неподвижную строку — вверху или внизу.
    static func thud() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.75)
    }
    /// Лёгкое касание: шаг назад, точка легла в текст.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Щелчок колёсика и готового ответа.
    static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    /// Дело сделано.
    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    /// Бумажный листок лёг на место.
    static func paper() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
    }
}
