import SwiftUI

/// Подсказки для первого знакомства (P427).
///
/// Самое нужное в приложении спрятано в жестах: касание по номеру дела,
/// долгое нажатие, перенос снимка в текст, уголки сверху. Сам человек их
/// не найдёт. Поэтому при первых встречах с экраном на нём появляется
/// жёлтый стикер — по одному за раз, пока человек не скажет «понятно».
/// Показанные помнятся; все разом выключаются и включаются снова в
/// настройках.
///
/// Помнит их телефон, а не папка: это удобство приложения, а не запись
/// человека, и в архив оно не пишется.
final class Hints: ObservableObject {

    struct Hint: Equatable {
        let id: String
        let screen: Shell.Screen
        let title: String
        let text: String
    }

    static let shared = Hints()

    /// По порядку: сначала то, без чего не начать.
    static var all: [Hint] {
        [
            Hint(id: "pages", screen: .today,
                 title: T("Листайте дни", "Turn the days"),
                 text: T("Проведите пальцем вбок — вчера и завтра. «Сегодня» внизу вернёт к сегодняшнему дню.",
                         "Swipe sideways for yesterday and tomorrow. “Today” at the bottom brings you back.")),
            Hint(id: "sheet", screen: .today,
                 title: T("План и дневник — одна страница", "Plan and diary on one page"),
                 text: T("Сверху — дела на день, ниже — дневник. Прокрутите вниз, чтобы писать.",
                         "Tasks for the day on top, the diary below. Scroll down to write.")),
            Hint(id: "tasks", screen: .today,
                 title: T("Дела", "Tasks"),
                 text: T("Коснитесь номера — дело сделано. Подержите дело и ведите: вверх-вниз — переставить, вправо — на другой день, влево — удалить.",
                         "Tap the number to mark a task done. Hold a task and drag: up or down to reorder, right to move it to another day, left to delete.")),
            Hint(id: "attach", screen: .today,
                 title: T("Снимки, голос, файлы", "Photos, voice, files"),
                 text: T("Строка внизу страницы и над клавиатурой: камера, фото, голос, файлы. Снимок из полоски можно пальцем перенести прямо в текст.",
                         "The strip at the bottom of the page and above the keyboard: camera, photos, voice, files. Drag a photo from the strip straight into your text.")),
            Hint(id: "corners", screen: .today,
                 title: T("Уголки сверху", "The top corners"),
                 text: T("Слева — настройки, справа — меню страницы. Коснитесь уголка или потяните его вниз.",
                         "Left: settings. Right: the page menu. Touch a corner or pull it down.")),
            Hint(id: "files", screen: .today,
                 title: T("Записи — ваши файлы", "Your entries are your files"),
                 text: T("Всё лежит обычными файлами в папке, которую вы выбрали. Их видно в «Файлах»; удалите приложение — записи останутся.",
                         "Everything is kept as plain files in the folder you chose. You can see them in Files; delete the app and your entries stay.")),
            Hint(id: "map", screen: .map,
                 title: T("Свои места", "Your places"),
                 text: T("Подержите палец на карте — встанет точка. Её можно назвать, выбрать значок и записать в день.",
                         "Hold your finger on the map to drop a pin. Name it, pick an icon and add it to the day.")),
            Hint(id: "search", screen: .search,
                 title: T("Где искать", "Where to search"),
                 text: T("Три точки справа сверху — искать только в плане или в дневнике, только снимки, видео, голос, файлы или места.",
                         "The three dots at top right: search only the plan or the diary, or only photos, video, voice, files or places.")),
        ]
    }

    private static let seenKey = "hints.seen"
    private static let offKey = "hints.off"

    @Published private(set) var seen: Set<String>
    @Published private(set) var off: Bool
    /// Что на экране сейчас.
    @Published var shown: Hint?

    private init() {
        let d = UserDefaults.standard
        seen = Set(d.stringArray(forKey: Self.seenKey) ?? [])
        off = d.bool(forKey: Self.offKey)
    }

    /// Следующая непоказанная подсказка этого экрана.
    func next(for screen: Shell.Screen) -> Hint? {
        guard !off else { return nil }
        return Self.all.first { $0.screen == screen && !seen.contains($0.id) }
    }

    /// «3 из 6» — сколько подсказок у этого экрана и какая по счёту.
    func place(of hint: Hint) -> (Int, Int) {
        let same = Self.all.filter { $0.screen == hint.screen }
        return ((same.firstIndex(of: hint) ?? 0) + 1, same.count)
    }

    func done(_ hint: Hint) {
        seen.insert(hint.id)
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
        shown = nil
    }

    func turnOff() {
        off = true
        UserDefaults.standard.set(true, forKey: Self.offKey)
        shown = nil
    }

    /// Из настроек: показать всё сначала.
    func startOver() {
        seen = []
        off = false
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
        UserDefaults.standard.set(false, forKey: Self.offKey)
    }

    /// Для снимков экрана: первая подсказка, как её увидят при первом запуске.
    func showFirstForPreview() {
        shown = Self.all.first
    }
}

/// Жёлтый стикер с подсказкой — приклеен полоской скотча, чуть наискось.
struct HintSticker: View {

    @ObservedObject var hints: Hints
    let hint: Hints.Hint

    var body: some View {
        let (n, total) = hints.place(of: hint)
        VStack(alignment: .leading, spacing: 8) {
            Text(hint.title)
                .font(Look.serif(17, weight: .semibold))
                .foregroundStyle(Look.ink)
            Text(hint.text)
                .font(Look.sans(14.5))
                .foregroundStyle(Look.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(T("Больше не показывать", "Don’t show tips")) {
                    withAnimation(.easeOut(duration: 0.2)) { hints.turnOff() }
                }
                .font(Look.sans(12.5))
                .foregroundStyle(Look.inkFaint)
                Spacer(minLength: 4)
                if total > 1 {
                    Text(T("\(n) из \(total)", "\(n) of \(total)"))
                        .font(Look.mono(11.5))
                        .foregroundStyle(Look.inkFaint)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { hints.done(hint) }
                } label: {
                    Text(n < total ? T("Дальше", "Next") : T("Понятно", "Got it"))
                        .font(Look.sans(14, weight: .semibold))
                        .foregroundStyle(Look.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Look.accent.opacity(0.6), lineWidth: 1.2))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Look.sticker)
        .overlay(Rectangle().strokeBorder(Look.stickerEdge, lineWidth: 1))
        // Полоска скотча сверху.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6))
                .frame(width: 74, height: 18)
                .rotationEffect(.degrees(-3))
                .offset(y: -9)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        .rotationEffect(.degrees(-1.5))
        .accessibilityElement(children: .contain)
    }
}

/// Слой подсказок поверх приложения. Подсказка появляется, только когда
/// экран спокоен: не открыты меню, настройки, листок переноса и клавиатура.
struct HintLayer: View {

    @ObservedObject private var hints = Hints.shared
    let screen: Shell.Screen
    let quiet: Bool

    var body: some View {
        ZStack {
            if let hint = hints.shown {
                // Касание мимо стикера — то же «понятно»: подсказка не
                // держит человека.
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { hints.done(hint) }
                    }
                HintSticker(hints: hints, hint: hint)
                    .padding(.horizontal, 28)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(hints.shown != nil)
        // Ушли на другой экран — его подсказка убирается, не считаясь
        // прочитанной: покажется, когда вернутся.
        .onChange(of: screen) { _, now in
            if let shown = hints.shown, shown.screen != now, !Vault.isPreview {
                hints.shown = nil
            }
        }
        .task(id: "\(screen)|\(quiet)|\(hints.shown?.id ?? "")|\(hints.seen.count)|\(hints.off)") {
            await pick()
        }
    }

    /// Подождать, пока экран откроется и успокоится, — и показать следующую.
    @MainActor private func pick() async {
        guard hints.shown == nil, !Vault.isPreview else { return }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled, quiet, hints.shown == nil,
              let next = hints.next(for: screen) else { return }
        withAnimation(.easeOut(duration: 0.25)) { hints.shown = next }
    }
}
