import SwiftUI
import UIKit

/// Дорога домой: один поворот на всё расстояние.
///
/// Раньше дорога делилась на несколько поворотов, и они шли друг за другом:
/// система переворачивает по одному листу и ждёт, пока он ляжет. Человеку
/// оставалось смотреть, как они мелькают, и ждать, пока это кончится.
///
/// Поворот один, длится как обычный, а то, что вернулись издалека, видно
/// по толщине: с далёкого дня поднимается не лист, а пачка (P178).
func wayHome(_ distance: Int) -> [Int] {
    distance == 0 ? [] : [distance]
}

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

    /// Просьба перелистнуть самому: очередь шагов, по одному на поворот.
    ///
    /// Нужна кнопке «Сегодня» — возвращаясь с далёкого дня, человек должен
    /// увидеть дорогу назад, а не оказаться на месте мгновенно. Шаг может
    /// быть любой длины: поворот открывает сразу нужный день, а не соседний,
    /// поэтому дальняя дорога проходится за два-три поворота, а не за
    /// двадцать (решение P164).
    ///
    /// Очередь убывает после каждого поворота — и следующий поворот
    /// собирается уже по свежим данным, а не по тем, что были в начале.
    var plan: Binding<[Int]> = .constant([])

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
        context.coordinator.obey(pages)
    }

    final class Host: UIHostingController<Content> {
        var offset = 0
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource,
                             UIPageViewControllerDelegate {
        var parent: PageCurl

        /// Пока страница в воздухе, второго поворота не начинаем.
        private var busy = false

        init(_ parent: PageCurl) { self.parent = parent }

        /// Выполнить первый шаг очереди, если он есть.
        func obey(_ pages: UIPageViewController) {
            guard !busy, let step = parent.plan.wrappedValue.first, step != 0 else { return }
            busy = true
            let forward = step > 0
            let host = make(step)
            // Лист, который пойдёт вперёд, получает торец: при повороте
            // пальцем его нет — там переворачивают один лист, — а домой
            // возвращаются через пачку (решение P178).
            //
            // Вперёд поворачивается открытая страница, назад — та, что
            // возвращается из-под корешка: торец нужен тому листу, который
            // движется. Свободный край у обоих правый — корешок слева.
            let moving = forward ? pages.viewControllers?.first?.view : host.view
            let edge = moving.map { Coordinator.thicken($0) }

            pages.setViewControllers([host],
                                     direction: forward ? .forward : .reverse,
                                     animated: true) { [weak self] done in
                guard let self else { return }
                self.busy = false
                edge?.removeFromSuperview()
                guard done else { self.parent.plan.wrappedValue = []; return }
                // Страница, на которой человек оказался, становится нулевой —
                // та же перенумерация, что и после поворота пальцем (P131).
                host.offset = 0
                self.parent.onTurn(step)
                if !self.parent.plan.wrappedValue.isEmpty {
                    self.parent.plan.wrappedValue.removeFirst()
                }
            }
        }

        /// Торец пачки на свободном краю листа.
        ///
        /// Пачку не изобразить числом поворотов: система переворачивает по
        /// одному листу и ждёт, пока он ляжет, — три поворота подряд
        /// читаются как три отдельных, а не как один толстый. Поэтому
        /// толщина рисуется на самом листе: он поднимается вместе со своим
        /// торцом, и поворот выходит не дольше обычного, а весомее
        /// (решение P178).
        @discardableResult
        static func thicken(_ view: UIView) -> UIView {
            let ширина: CGFloat = 11
            let листов = 4
            let block = UIView(frame: CGRect(x: view.bounds.width - ширина, y: 0,
                                             width: ширина,
                                             height: view.bounds.height))
            block.autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
            block.backgroundColor = UIColor(Look.boardFace)
            block.isUserInteractionEnabled = false
            block.clipsToBounds = true

            let лист = ширина / CGFloat(листов)
            for i in 0..<листов {
                let leaf = UIView(frame: CGRect(x: CGFloat(i) * лист, y: 0,
                                                width: лист - 0.7,
                                                height: block.bounds.height))
                leaf.autoresizingMask = [.flexibleHeight]
                leaf.backgroundColor = UIColor(i == листов - 1 ? Look.boardDeep : Look.boardLit)
                block.addSubview(leaf)
            }
            view.addSubview(block)
            return block
        }

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
            // Страница, на которой человек теперь стоит, становится нулевой —
            // но подменять её новой нельзя: новая соберётся по старым данным
            // и мелькнёт чужим месяцем, пока не подоспеют свежие. Поэтому
            // просто перенумеровываем ту же самую: на экране ничего не
            // меняется, а соседи теперь считаются от неё (P113).
            current.offset = 0
        }
    }
}
