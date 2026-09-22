import SwiftUI
import UIKit

/// Переход между разделами: тот же поворот страницы, что и между днями.
///
/// Разделы лежат в книге по порядку: календарь в начале, «сегодня»
/// посередине, поиск в конце — ровно так, как нарисованы значки. Переходя из
/// раздела в раздел, человек не «переключает экран», а поворачивает
/// страницу: к концу книги — справа налево, к началу — обратным ходом
/// (замысел автора, решение P144).
///
/// Поворот тот же самый, что на экране «Сегодня», и сделан тем же: своими
/// силами такое не нарисовать, а система умеет и умеет правильно. Здесь
/// страницу не тянут пальцем — раздел выбирают кнопкой внизу, — поэтому
/// собственные жесты сняты: под ними живёт свой поворот, между днями.
struct SectionCurl<Content: View>: UIViewControllerRepresentable {

    let screen: Shell.Screen
    let content: (Shell.Screen) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pages = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        pages.delegate = context.coordinator
        pages.isDoubleSided = false
        pages.view.backgroundColor = UIColor(Look.chrome)

        for gesture in pages.gestureRecognizers { gesture.isEnabled = false }

        context.coordinator.shown = screen
        pages.setViewControllers([context.coordinator.make(screen)],
                                 direction: .forward, animated: false)
        return pages
    }

    func updateUIViewController(_ pages: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.show(screen, in: pages)
    }

    final class Coordinator: NSObject, UIPageViewControllerDelegate {

        var parent: SectionCurl
        var shown: Shell.Screen?

        /// Пока страница в воздухе, второго поворота не начинаем: два
        /// поворота внахлёст система доводит до чужого раздела.
        private var turning = false

        init(_ parent: SectionCurl) { self.parent = parent }

        func make(_ screen: Shell.Screen) -> UIHostingController<Content> {
            let host = UIHostingController(rootView: parent.content(screen))
            host.view.backgroundColor = UIColor(Look.chrome)
            host.view.isOpaque = true
            // Страница не подбирается под клавиатуру: иначе весь экран
            // вздрагивает, едва человек ставит курсор (P113).
            host.safeAreaRegions = .container
            return host
        }

        func show(_ screen: Shell.Screen, in pages: UIPageViewController) {
            guard let current = pages.viewControllers?.first
                    as? UIHostingController<Content> else { return }

            if shown == screen {
                // Раздел тот же — просто обновить содержимое страницы.
                current.rootView = parent.content(screen)
                return
            }
            guard !turning else { return }

            let forward = screen.place > (shown?.place ?? screen.place)
            shown = screen
            turning = true
            pages.setViewControllers([make(screen)],
                                     direction: forward ? .forward : .reverse,
                                     animated: true) { [weak self] _ in
                self?.turning = false
            }
        }
    }
}
