import Foundation
import Speech

/// Голосовая запись — в текст (P378). Распознаёт сам iPhone; где для
/// языка есть распознавание без сети, запись не уходит с телефона.
/// Сама запись остаётся — текст ложится рядом с ней.
enum Transcribe {

    /// Задача распознавания держится, пока идёт: иначе она обрывается.
    private static var running: SFSpeechRecognitionTask?

    /// Распознаватель на языке приложения: сперва с краем телефона
    /// («ru-RU», «en-GB»), потом любой с тем же языком.
    static func recognizer() -> SFSpeechRecognizer? {
        let code = Lang.code
        let phone = Locale.current
        if phone.language.languageCode?.identifier == code, let r = SFSpeechRecognizer(locale: phone) {
            return r
        }
        let found = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == code }
            .sorted { $0.identifier < $1.identifier }
        return found.first.flatMap(SFSpeechRecognizer.init(locale:)) ?? SFSpeechRecognizer()
    }

    /// Распознать файл. `done` — текст или что помешало, на главном потоке.
    static func run(_ url: URL, done: @escaping (String?, String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                return DispatchQueue.main.async {
                    done(nil, T("Нет разрешения на распознавание речи — его можно дать в Настройках iPhone.",
                                "No permission for speech recognition — you can allow it in iPhone Settings."))
                }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let local = Attachment.fetch(url) ?? url
                DispatchQueue.main.async {
                    guard let r = recognizer(), r.isAvailable else {
                        return done(nil, T("Распознавание речи для этого языка сейчас недоступно.",
                                           "Speech recognition for this language is not available right now."))
                    }
                    let request = SFSpeechURLRecognitionRequest(url: local)
                    request.shouldReportPartialResults = false
                    request.addsPunctuation = true
                    if r.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
                    running = r.recognitionTask(with: request) { result, error in
                        if let result, result.isFinal {
                            running = nil
                            let text = result.bestTranscription.formattedString
                            DispatchQueue.main.async {
                                text.isEmpty
                                    ? done(nil, T("Речи в записи не нашлось.", "No speech was found in the recording."))
                                    : done(text, nil)
                            }
                        } else if let error {
                            running = nil
                            DispatchQueue.main.async { done(nil, error.localizedDescription) }
                        }
                    }
                }
            }
        }
    }

    /// Распознаётся ли этот язык без сети — для честной строки под кнопкой.
    static var onPhone: Bool { recognizer()?.supportsOnDeviceRecognition ?? false }
}
