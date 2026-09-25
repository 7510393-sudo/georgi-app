import SwiftUI
import UIKit
import MapKit

/// Своя карта человека: его места с названиями и дни, где он был.
///
/// Открывается кнопкой «геоточка». Сама карта — Карты Apple со всеми их
/// жестами: двойное касание приближает, касание двумя пальцами отдаляет,
/// щипок, поворот (P217). Долгое нажатие ставит булавку и открывает
/// сверху панель «Точка» — название и что здесь было. Кнопка «Запомнить
/// точку» стоит там же, где «геоточка», и пишет точку в план или в
/// дневник — туда, откуда открыли карту (P213).
///
/// Своих серверов у приложения нет (P198). Места — файлы в папке «Места»,
/// по файлу на место.
struct MapScreen: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    @State private var places: [Place] = []
    /// Выбранная точка: поставленная долгим нажатием, нажатое место или
    /// точка из текста. Её и запомнит кнопка внизу.
    @State private var selected: Place?
    /// Что открыто сверху: панель названия или облачко места.
    @State private var panel: Panel?
    @State private var focus: MapFocus?
    @State private var locating = false
    @State private var asking = false

    enum Panel { case naming, cloud }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                NativeMap(places: places, days: days, selected: selected, focus: focus,
                          onLongPress: pick, onPlace: choose, onDay: openDay,
                          onSelected: { withAnimation { panel = .cloud } })
                if let selected, panel == .naming {
                    PointPanel(place: selected, cancel: cancel, done: name)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let selected, panel == .cloud {
                    PlaceCloud(place: selected,
                               edit: { withAnimation { panel = .naming } },
                               remove: selected.file == nil ? nil : { asking = true },
                               close: { withAnimation { panel = nil } })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: panel)
            bar
        }
        .background(Look.chrome)
        .confirmationDialog("Убрать «\(selected?.name ?? "")» с карты?", isPresented: $asking,
                            titleVisibility: .visible) {
            Button("Убрать", role: .destructive) { remove() }
        } message: {
            Text("Файл этого места будет удалён из папки «Места».")
        }
        .onAppear(perform: begin)
    }

    /// Название экрана — такое же, как у календаря и поиска. Шестерёнка,
    /// три точки и нижние разделы остаются на месте: карта открывается на
    /// странице, а не поверх всего приложения (P210).
    private var header: some View {
        ZStack {
            Text("Мои места")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Look.ink)
            HStack {
                Spacer()
                Button {
                    hideKeyboard()
                    withAnimation(.easeOut(duration: 0.25)) { shell.showingMap = false }
                } label: {
                    Text("Закрыть")
                        .font(Look.sans(14))
                        .foregroundStyle(Look.accent)
                }
                .padding(.trailing, 16)
            }
        }
        .padding(.top, DayPage.airAbove)
        .padding(.bottom, 10)
    }

    private var days: [MapDay] {
        let today = Vault.stamp(store.date)
        return archive.days.values.compactMap { day in
            day.place.map { MapDay(stamp: day.stamp, date: day.date, at: $0,
                                   today: day.stamp == today) }
        }
    }

    // MARK: - Нижняя полоска

    /// Полоска внизу — той же высоты и с теми же местами, что полоска
    /// вложений: «Запомнить точку» стоит ровно там, где «геоточка», и
    /// палец, открывший карту, попадает в неё не глядя (P213).
    private var bar: some View {
        let marked = store.place != nil
        return HStack(spacing: 0) {
            Button(action: markDay) {
                BarFace(icon: marked ? "mappin.circle.fill" : "mappin.circle",
                        name: marked ? "день тут" : "я здесь")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(marked ? "Переставить место дня сюда" : "Я здесь в этот день")
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            Button(action: remember) {
                if locating {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    BarFace(icon: "pin.fill", name: "запомнить точку", tint: Look.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(selected == nil ? "Запишет, где вы сейчас"
                                               : "Запишет выбранную точку")
        }
        .overlay {
            Text(hint)
                .font(Look.sans(11.5))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 90)
                .allowsHitTesting(false)
        }
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(Look.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(Look.rule).frame(height: 1)
        }
    }

    /// Подсказка посреди полоски: что запомнит кнопка справа.
    private var hint: String {
        guard let selected else { return "Долгое нажатие — выбрать точку" }
        return selected.name.isEmpty ? "Выбрана точка" : "Выбрано: " + selected.name
    }

    // MARK: - Действия

    /// Открыть карту: на точке из текста, на месте дня, иначе — где
    /// человек сейчас. Разрешение на место просится здесь, по его жесту.
    private func begin() {
        places = Places.all(in: vault)
        archive.reload()
        if let point = shell.mapFocus {
            shell.mapFocus = nil
            let known = places.first { near($0.coordinate, point.at) }
            selected = known ?? Place(name: point.title, coordinate: point.at)
            panel = .cloud
            focus = MapFocus(center: point.at, meters: 1500)
        } else if let at = store.placeCoordinate {
            focus = MapFocus(center: at, meters: 2000)
        } else {
            Locator.shared.current { location in
                guard let at = location?.coordinate else { return }
                focus = MapFocus(center: at, meters: 2000)
            }
        }
    }

    private func near(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 0.00002 && abs(a.longitude - b.longitude) < 0.00002
    }

    /// Долгое нажатие: булавка на месте пальца и панель «Точка» сверху.
    private func pick(_ at: CLLocationCoordinate2D) {
        selected = Place(name: "", coordinate: at)
        withAnimation { panel = .naming }
    }

    /// Нажали на своё место: оно выбрано, сверху — облачко о нём.
    private func choose(_ place: Place) {
        hideKeyboard()
        selected = place
        withAnimation { panel = .cloud }
    }

    private func cancel() {
        hideKeyboard()
        // Отмена у нового места убирает булавку; у записанного — только
        // закрывает правку.
        if selected?.file == nil { selected = nil }
        withAnimation { panel = nil }
    }

    /// «Готово»: с названием место ложится в папку «Места» и остаётся на
    /// карте; без названия — остаётся просто выбранной точкой.
    private func name(_ place: Place) {
        hideKeyboard()
        withAnimation { panel = nil }
        guard !place.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            selected = place
            return
        }
        guard let stored = Places.save(place, in: vault) else {
            selected = place
            return shell.say("Место не записалось. Проверьте папку в настройках.")
        }
        places.removeAll { $0.id == place.id || ($0.file != nil && $0.file == place.file) }
        places.append(stored)
        selected = stored
    }

    private func remove() {
        guard let place = selected else { return }
        Places.delete(place, in: vault)
        places.removeAll { $0.id == place.id }
        selected = nil
        withAnimation { panel = nil }
    }

    /// «Запомнить точку»: выбранную — или ту, где телефон сейчас. Пишется
    /// туда, откуда открыли карту: в план или в дневник на место курсора.
    private func remember() {
        let tab = shell.tab
        guard store.canEdit(tab) else { return shell.say(store.closedReason) }
        hideKeyboard()
        if let place = selected {
            return write(GeoPoint(title: place.name, at: place.coordinate), to: tab)
        }
        locating = true
        Locator.shared.current { location in
            locating = false
            guard let at = location?.coordinate else {
                return shell.say("Не удалось узнать, где вы. Проверьте, разрешено ли приложению место.")
            }
            write(GeoPoint(title: "", at: at), to: tab)
            if let location { store.noteWeather(at: location) }
        }
    }

    private func write(_ point: GeoPoint, to tab: Shell.Tab) {
        guard store.writePoint(point, to: tab) else { return shell.say(store.closedReason) }
        shell.say(tab == .diary ? "Точка записана в дневник" : "Точка записана в план")
        withAnimation(.easeOut(duration: 0.25)) { shell.showingMap = false }
    }

    /// Отметить, где человек в открытый день (P207).
    private func markDay() {
        guard store.canEditDiary else { return shell.say(store.closedReason) }
        locating = true
        Locator.shared.current { location in
            locating = false
            guard let at = location?.coordinate else {
                return shell.say("Не удалось узнать, где вы. Проверьте, разрешено ли приложению место.")
            }
            store.mark(at)
            if let location { store.noteWeather(at: location) }
            archive.reload()
            focus = MapFocus(center: at, meters: 1500)
            shell.say("Отмечено: здесь вы в этот день")
        }
    }

    private func openDay(_ date: Date) {
        store.go(to: date)
        shell.tab = .diary
        shell.screen = .today
        withAnimation(.easeOut(duration: 0.25)) { shell.showingMap = false }
    }
}

/// Куда повести карту. Новая просьба — новый `id`.
struct MapFocus: Equatable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let meters: CLLocationDistance

    static func == (a: MapFocus, b: MapFocus) -> Bool { a.id == b.id }
}

/// День, в который человек отметил, где был.
struct MapDay {
    let stamp: String
    let date: Date
    let at: CLLocationCoordinate2D
    let today: Bool
}

/// Карты Apple как есть — с их жестами и кнопками (P217).
///
/// Прежняя карта была нарисована средствами SwiftUI, и у неё не работало
/// двойное касание: его перехватывал жест, ловивший место пальца. Здесь
/// жесты свои у карты, приложение добавляет только долгое нажатие.
struct NativeMap: UIViewRepresentable {

    var places: [Place]
    var days: [MapDay]
    var selected: Place?
    var focus: MapFocus?
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onPlace: (Place) -> Void
    var onDay: (Date) -> Void
    var onSelected: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = true
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)

        // «Где я» и компас — справа сверху, как в Картах.
        let track = MKUserTrackingButton(mapView: map)
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        track.backgroundColor = UIColor(Look.chrome).withAlphaComponent(0.92)
        track.layer.cornerRadius = 8
        track.clipsToBounds = true
        for control in [track, compass] as [UIView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            map.addSubview(control)
        }
        NSLayoutConstraint.activate([
            track.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            track.bottomAnchor.constraint(equalTo: map.bottomAnchor, constant: -28),
            compass.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            compass.bottomAnchor.constraint(equalTo: track.topAnchor, constant: -10),
        ])
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let keeper = context.coordinator
        keeper.parent = self
        keeper.sync(map)
        if let focus, focus != keeper.focused {
            keeper.focused = focus
            let region = MKCoordinateRegion(center: focus.center,
                                            latitudinalMeters: focus.meters,
                                            longitudinalMeters: focus.meters)
            map.setRegion(region, animated: keeper.shown)
        }
        keeper.shown = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMap
        var focused: MapFocus?
        var shown = false
        /// Что сейчас стоит на карте — чтобы не переставлять метки зря.
        private var drawn = ""

        init(_ parent: NativeMap) { self.parent = parent }

        func sync(_ map: MKMapView) {
            let draft = parent.selected.flatMap { $0.file == nil ? $0 : nil }
            var key = parent.places.map { "\($0.id)\($0.name)\($0.latitude)\($0.longitude)" }
                .joined(separator: "|")
            key += parent.days.map { "\($0.stamp)\($0.today)" }.joined(separator: "|")
            key += draft.map { "\($0.name)\($0.latitude)\($0.longitude)" } ?? "-"
            guard key != drawn else { return }
            drawn = key
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.addAnnotations(parent.days.map { DayMark($0) })
            map.addAnnotations(parent.places.map { PlaceMark($0) })
            if let draft { map.addAnnotation(DraftMark(draft)) }
        }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let at = map.convert(g.location(in: map), toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(at)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let mark as PlaceMark:
                let view = MKMarkerAnnotationView(annotation: mark, reuseIdentifier: "место")
                view.markerTintColor = UIColor(Look.accent)
                view.glyphImage = UIImage(systemName: "star.fill")
                view.titleVisibility = .visible
                view.displayPriority = .required
                return view
            case let mark as DraftMark:
                let view = MKMarkerAnnotationView(annotation: mark, reuseIdentifier: "точка")
                view.markerTintColor = .systemRed
                view.animatesWhenAdded = true
                view.titleVisibility = .visible
                view.displayPriority = .required
                return view
            case let mark as DayMark:
                let view = MKAnnotationView(annotation: mark, reuseIdentifier: "день")
                view.image = DayMark.dot(today: mark.day.today)
                view.displayPriority = .defaultHigh
                return view
            default:
                return nil
            }
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            switch annotation {
            case let mark as PlaceMark: parent.onPlace(mark.place)
            case let mark as DayMark: parent.onDay(mark.day.date)
            case is DraftMark: parent.onSelected()
            default: return
            }
            // Снять выбор сразу — чтобы ту же метку можно было нажать снова.
            map.deselectAnnotation(annotation, animated: false)
        }
    }
}

/// Своё место на карте.
final class PlaceMark: NSObject, MKAnnotation {
    let place: Place
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name }
    init(_ place: Place) { self.place = place }
}

/// Точка, выбранная долгим нажатием, пока у неё нет файла.
final class DraftMark: NSObject, MKAnnotation {
    let place: Place
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name.isEmpty ? "Точка" : place.name }
    init(_ place: Place) { self.place = place }
}

/// День, в который человек отметил, где был.
final class DayMark: NSObject, MKAnnotation {
    let day: MapDay
    var coordinate: CLLocationCoordinate2D { day.at }
    init(_ day: MapDay) { self.day = day }

    static func dot(today: Bool) -> UIImage {
        let side: CGFloat = 16
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            let box = CGRect(x: 2, y: 2, width: side - 4, height: side - 4)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: box).fill()
            UIColor(today ? Look.accent : Look.inkSoft).setFill()
            UIBezierPath(ovalIn: box.insetBy(dx: 2, dy: 2)).fill()
        }
    }
}

/// Панель «Точка» сверху карты: название и что здесь было. Полупрозрачная —
/// под ней видно, куда встала булавка; клавиатура открывается сразу (P213).
struct PointPanel: View {

    @State var place: Place
    let cancel: () -> Void
    let done: (Place) -> Void

    private enum Field { case name, text }
    @FocusState private var focused: Field?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Отмена", action: cancel)
                Spacer()
                Text("Точка").font(Look.sans(16, weight: .semibold)).foregroundStyle(Look.ink)
                Spacer()
                Button("Готово") { done(place) }.fontWeight(.semibold)
            }
            .font(Look.sans(15))
            TextField("Название", text: $place.name)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .text }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Look.planBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            TextField("Что здесь было", text: $place.text, axis: .vertical)
                .focused($focused, equals: .text)
                .lineLimit(1...5)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Look.planBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            Text(Geo.text(place.coordinate))
                .font(Look.mono(11.5))
                .foregroundStyle(Look.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Look.sans(15))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .name }
        }
    }
}

/// Облачко выбранной точки сверху карты: название, что человек о ней
/// написал, дорога туда и координаты (P210, P213).
struct PlaceCloud: View {
    let place: Place
    let edit: () -> Void
    var remove: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(place.name.isEmpty ? "Точка" : place.name)
                    .font(Look.serif(18, weight: .semibold))
                    .foregroundStyle(Look.ink)
                    .lineLimit(2)
                Spacer()
                Button(place.file == nil ? "Назвать" : "Изменить", action: edit)
                    .font(Look.sans(14))
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Look.inkFaint)
                }
                .padding(.leading, 6)
                .accessibilityLabel("Закрыть")
            }
            if !place.text.isEmpty {
                Text(place.text)
                    .font(Look.serif(15))
                    .foregroundStyle(Look.ink)
                    .lineLimit(5)
            }
            Text(Geo.text(place.coordinate))
                .font(Look.mono(11.5))
                .foregroundStyle(Look.inkFaint)
            HStack(spacing: 14) {
                Button {
                    PlaceActions.openInMaps(place.coordinate, name: place.name)
                } label: {
                    Label("Проложить путь", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                Button {
                    PlaceActions.copy(place.coordinate)
                } label: {
                    Label("Скопировать", systemImage: "doc.on.doc")
                }
                Spacer()
                if let remove {
                    Button(action: remove) { Image(systemName: "trash") }
                        .accessibilityLabel("Убрать с карты")
                }
            }
            .font(Look.sans(14))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

/// Что можно сделать с точкой: открыть в Картах, скопировать.
enum PlaceActions {

    /// Открыть в Картах Apple с дорогой до точки.
    static func openInMaps(_ c: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:
                                            MKLaunchOptionsDirectionsModeDefault])
    }

    /// Скопировать точку словами «59.93863, 30.31413» — их понимает любой
    /// навигатор и любые карты.
    static func copy(_ c: CLLocationCoordinate2D) {
        UIPasteboard.general.string = Geo.text(c)
    }
}
