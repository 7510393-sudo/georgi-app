import SwiftUI
import UIKit

/// Перелистывание страницы, как в бумажной книге.
///
/// Тот же механизм, что в «Книгах» Apple: страница поднимается за пальцем,
/// загибается и ложится на соседнюю. Своими силами такое не нарисовать, да и
/// не нужно — система умеет это сама, и умеет правильно.
///
/// Содержимое задаётся смещением: 0 — нынешняя страница, −1 и +1 — соседние.
/// Перелистнув, человек оказывается на соседней, и она становится нулевой.
struct PageCurl<Content: View>: UIViewControllerRepresentable {

    let content: (Int) -> Content
    let onTurn: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pages = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        pages.dataSource = context.coordinator
        pages.delegate = context.coordinator
        pages.isDoubleSided = false
        pages.view.backgroundColor = UIColor(Look.chrome)
        pages.setViewControllers([context.coordinator.make(0)],
                                 direction: .forward, animated: false)

        // Страница переворачивается движением, а не касанием. Система сама
        // вешает на края экрана касания, которые листают: человек тыкает в
        // край — и день меняется без его намерения. Это нарушение главного
        // правила (P113), поэтому касания снимаем, тяга остаётся.
        for gesture in pages.gestureRecognizers where gesture is UITapGestureRecognizer {
            gesture.isEnabled = false
        }
        return pages
    }

    func updateUIViewController(_ pages: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(pages)
    }

    final class Host: UIHostingController<Content> {
        var offset = 0
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
                             UIPageViewControllerDelegate {
        var parent: PageCurl

        init(_ parent: PageCurl) { self.parent = parent }

        func make(_ offset: Int) -> Host {
            let host = Host(rootView: parent.content(offset))
            host.offset = offset
            host.view.backgroundColor = UIColor(Look.chrome)
            host.view.isOpaque = true
            // Страница не подбирается под клавиатуру: иначе весь экран —
            // вместе с неподвижными шестерёнкой и нижними разделами —
            // вздрагивает, едва человек ставит курсор.
            host.safeAreaRegions = .container
            return host
        }

        /// Перерисовать открытую страницу, не трогая соседние.
        func refresh(_ pages: UIPageViewController) {
            guard let current = pages.viewControllers?.first as? Host else { return }
            current.rootView = parent.content(current.offset)
        }

        func pageViewController(_ pages: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            (vc as? Host).map { make($0.offset - 1) }
        }

        func pageViewController(_ pages: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            (vc as? Host).map { make($0.offset + 1) }
        }

        func pageViewController(_ pages: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let current = pages.viewControllers?.first as? Host,
                  current.offset != 0
            else { return }

            parent.onTurn(current.offset)
            // Страница, на которой человек теперь стоит, становится нулевой:
            // иначе следующий поворот отсчитывался бы от старого места.
            pages.setViewControllers([make(0)], direction: .forward, animated: false)
        }
    }
}
