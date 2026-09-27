import AVFoundation
import UIKit

/// Звуки приложения (P265). Тихие и бумажные: шелест страницы, когда её
/// переворачивают. Идут как звуки клавиатуры — переключатель «без звука»
/// на iPhone их глушит, музыку они не прерывают. Выключаются в настройках.
enum Sounds {

    private static let flipData: Data? = Bundle.main
        .url(forResource: "page-flip", withExtension: "wav")
        .flatMap { try? Data(contentsOf: $0) }

    /// Плееры, которые ещё звучат: отпущенный плеер замолкает на полуслове.
    private static var playing: [AVAudioPlayer] = []

    static var on: Bool { !UserDefaults.standard.bool(forKey: Prefs.quiet) }

    /// Шелест перевёрнутой страницы. `rate` чуть меняет высоту: в вихре
    /// листы шуршат не одинаково.
    static func flip(volume: Float = 0.45, rate: Float = 1) {
        guard on, let flipData else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
        }
        guard let player = try? AVAudioPlayer(data: flipData) else { return }
        player.volume = volume
        player.enableRate = true
        player.rate = rate
        playing.removeAll { !$0.isPlaying }
        playing.append(player)
        player.play()
    }
}
