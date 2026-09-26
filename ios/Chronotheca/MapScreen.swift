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
        ZStack(alignment: .top) {
            NativeMap(places: places, days: days, selected: selected, focus: focus,
                      satellite: shell.mapSatellite,
                      onLongPress: pick, onPlace: choose, onDay: openDay,
                      onSelected: { withAnimation { panel = .cloud } },
                      onTapEmpty: tapEmpty)
            if let selected, panel == .naming {
                // Новая булавка — новая панель: поля не должны
                // остаться от прежней точки.
                PointPanel(place: selected, cancel: cancel, done: name)
                    .id(selected.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let selected, panel == .cloud {
                PlaceCloud(place: selected, edit: { withAnimation { panel = .naming } })
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Закрыть карту — крестик слева сверху, под шестерёнкой.
                // Строки «Мои места / Закрыть» больше нет: карта занимает
                // всю страницу (P228).
                HStack {
                    Button {
                        hideKeyboard()
                        withAnimation(.easeOut(duration: 0.25)) { shell.showingMap = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Look.ink)
                            .frame(width: 40, height: 40)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    }
                    .accessibilityLabel("Закрыть карту")
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, Corner.size + 6)
            }
        }
        .animation(.easeOut(duration: 0.2), value: panel)
        .overlay(alignment: .bottom) { bar }
        .background(Look.chrome)
        .confirmationDialog("Удалить точку?", isPresented: $asking, titleVisibility: .visible) {
            Button("Удалить точку", role: .destructive) { remove() }
            Button("Оставить точку", role: .cancel) { }
        } message: {
            Text(selected?.file == nil ? "Булавка уйдёт с карты."
                 : "Файл этой точки будет удалён из папки «Места».")
        }
        .onAppear(perform: begin)
        .onChange(of: selected) { _, now in
            shell.mapPoint = now.map { GeoPoint(title: $0.name, at: $0.coordinate) }
        }
        .onDisappear { shell.mapPoint = nil }
    }

    private var days: [MapDay] {
        let today = Vault.stamp(store.date)
        return archive.days.values.compactMap { day in
            day.place.map { MapDay(stamp: day.stamp, date: day.date, at: $0,
                                   today: day.stamp == today) }
        }
    }

    // MARK: - Кнопки внизу

    /// Кнопки внизу — овальные, поверх карты, а не сплошной полосой: карту
    /// видно между ними (P228). Стоят на тех же местах, что кнопки полоски
    /// вложений: «Запомнить точку» — ровно там, где «геоточка» (P213).
    /// Корзина, «скопировать» и «в навигатор» бледнеют, пока точка не
    /// выбрана (P219).
    private var bar: some View {
        let point = selected != nil
        return HStack(spacing: 0) {
            Button { asking = true } label: {
                oval(BarFace(icon: "trash", name: "удалить",
                             tint: point ? Look.inkSoft : Look.inkFaint.opacity(0.6)))
            }
            .disabled(!point)
            Button {
                guard let selected else { return }
                MapActions.copy(selected)
                shell.say("Скопировано: " + Geo.text(selected.coordinate))
            } label: {
                oval(BarFace(icon: "doc.on.doc", name: "скопировать",
                             tint: point ? Look.inkSoft : Look.inkFaint.opacity(0.6)))
            }
            .disabled(!point)
            Button { if let selected { MapActions.navigate(selected) } } label: {
                oval(BarFace(icon: "arrow.triangle.turn.up.right.diamond", name: "в навигатор",
                             tint: point ? Look.accent : Look.inkFaint.opacity(0.6)))
            }
            .disabled(!point)
            Button(action: remember) {
                if locating {
                    oval(ProgressView().frame(maxWidth: .infinity))
                } else {
                    oval(BarFace(icon: "pin.fill", name: "запомнить точку", tint: Look.accent))
                }
            }
            .accessibilityHint(point ? "Запишет выбранную точку" : "Запишет, где вы сейчас")
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.bottom, 7)
    }

    /// Овал под кнопкой. Выходит за подпись и значок наружу и не меняет
    /// их места — кнопки стоят там же, где кнопки полоски вложений.
    private func oval<C: View>(_ face: C) -> some View {
        face.background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                .padding(.horizontal, 5)
                .padding(.vertical, -6))
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

    /// Касание по пустому месту карты: панель и облачко уходят, клавиатура
    /// опускается. Новая булавка без названия уходит вместе с панелью (P228).
    private func tapEmpty() {
        guard selected != nil || panel != nil else { return }
        hideKeyboard()
        if selected?.file == nil { selected = nil }
        if panel == .cloud { selected = nil }
        withAnimation { panel = nil }
    }

    private func cancel() {
        hideKeyboard()
        // Отмена у нового места убирает булавку; у записанного — только
        // закрывает правку.
        if selected?.file == nil { selected = nil }
        withAnimation { panel = nil }
    }

    /// «Готово»: точка ложится в папку «Места» и остаётся на карте. Не
    /// назвали — названием остаются координаты (P228).
    private func name(_ given: Place) {
        hideKeyboard()
        withAnimation { panel = nil }
        var place = given
        if place.name.trimmingCharacters(in: .whitespaces).isEmpty {
            place.name = Geo.text(place.coordinate)
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
        if place.file != nil { Places.delete(place, in: vault) }
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
            // Названием остались координаты — в текст они ляжут один раз.
            let title = place.name == Geo.text(place.coordinate) ? "" : place.name
            return write(GeoPoint(title: title, at: place.coordinate), to: tab)
        }
        locating = true
        Locator.shared.current { location in
            locating = false
            guard let at = location?.coordinate else {
                return shell.say("Не удалось узнать, где вы. Проверьте, разрешено ли приложению место.")
            }
            write(GeoPoint(title: "", at: at), to: tab, here: true)
            if let location { store.noteWeather(at: location) }
        }
    }

    private func write(_ point: GeoPoint, to tab: Shell.Tab, here: Bool = false) {
        guard store.writePoint(point, to: tab, here: here) else {
            return shell.say(store.closedReason)
        }
        shell.say(tab == .diary ? "Точка записана в дневник" : "Точка записана в план")
        withAnimation(.easeOut(duration: 0.25)) { shell.showingMap = false }
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
    /// Спутник вместо схемы — из меню карты (P222).
    var satellite = false
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onPlace: (Place) -> Void
    var onDay: (Date) -> Void
    var onSelected: () -> Void
    var onTapEmpty: () -> Void = {}

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

        // Касание по пустому месту — закрыть панель. Ждёт, не будет ли
        // второго касания: двойное касание остаётся приближением.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        let inner = (map.gestureRecognizers ?? [])
            + map.subviews.flatMap { $0.gestureRecognizers ?? [] }
        for case let double as UITapGestureRecognizer in inner where double.numberOfTapsRequired == 2 {
            tap.require(toFail: double)
        }
        map.addGestureRecognizer(tap)

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
            // Справа сверху, под уголком с тремя точками (P228).
            track.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            track.topAnchor.constraint(equalTo: map.topAnchor, constant: Corner.size + 6),
            compass.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            compass.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 10),
        ])
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let keeper = context.coordinator
        keeper.parent = self
        let kind: MKMapType = satellite ? .hybrid : .standard
        if map.mapType != kind { map.mapType = kind }
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

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeMap
        var focused: MapFocus?
        var shown = false
        /// Что сейчас стоит на карте — чтобы не переставлять метки зря.
        private var drawn = ""

        init(_ parent: NativeMap) { self.parent = parent }

        func sync(_ map: MKMapView) {
            let draft = parent.selected.flatMap { $0.file == nil ? $0 : nil }
            var key = parent.places.map { "\($0.id)\($0.name)\($0.mark)\($0.latitude)\($0.longitude)" }
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

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            // Касание по метке — это выбор метки, а не пустое место.
            var hit = map.hitTest(g.location(in: map), with: nil)
            while let view = hit {
                if view is MKAnnotationView { return }
                hit = view.superview
            }
            parent.onTapEmpty()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
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
                // Своя метка: спокойный кружок со значком и название на
                // светлой плашке — его не спутать с подписями самой карты
                // (P234).
                let view = MKAnnotationView(annotation: mark, reuseIdentifier: "место")
                let picture = PlaceLabel.draw(mark.place.name, symbol: Glyph.image(mark.place.mark))
                view.image = picture
                view.centerOffset = CGPoint(x: 0, y: picture.size.height / 2 - PlaceLabel.dot / 2)
                view.displayPriority = .required
                view.collisionMode = .rectangle
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

/// Метка своего места: кружок со значком, под ним — название на плашке.
enum PlaceLabel {
    static let dot: CGFloat = 24

    static func draw(_ name: String, symbol: String) -> UIImage {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Look.ink)]
        let text = (name as NSString)
        let wide = min(text.size(withAttributes: words).width, 150)
        let plate = CGSize(width: wide + 12, height: font.lineHeight + 6)
        let size = CGSize(width: max(dot, plate.width) + 4, height: dot + 3 + plate.height + 4)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let mid = size.width / 2
            let circle = CGRect(x: mid - dot / 2, y: 1, width: dot, height: dot)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                                    color: UIColor.black.withAlphaComponent(0.25).cgColor)
            UIColor(Look.inkSoft).setFill()
            UIBezierPath(ovalIn: circle).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.5
            ring.stroke()
            if let glyph = UIImage(systemName: symbol,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let g = glyph.size
                glyph.draw(in: CGRect(x: circle.midX - g.width / 2, y: circle.midY - g.height / 2,
                                      width: g.width, height: g.height))
            }
            let box = CGRect(x: mid - plate.width / 2, y: dot + 4, width: plate.width, height: plate.height)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                                    color: UIColor.black.withAlphaComponent(0.2).cgColor)
            UIColor(Look.sticker).withAlphaComponent(0.96).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 5).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            text.draw(with: CGRect(x: box.minX + 6, y: box.minY + 3, width: wide, height: font.lineHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                      attributes: words, context: nil)
        }
    }
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

/// Панель новой точки сверху карты: название и что здесь было.
/// Полупрозрачная — под ней видно, куда встала булавка; клавиатура
/// открывается сразу. В поле названия бледно стоят координаты: не назвали —
/// они и останутся названием. «Отмена» — внизу слева, «Готово» — внизу
/// справа (P213, P228).
struct PointPanel: View {

    @State var place: Place
    let cancel: () -> Void
    let done: (Place) -> Void

    private enum Field { case name, text }
    @FocusState private var focused: Field?

    var body: some View {
        VStack(spacing: 8) {
            TextField(Geo.text(place.coordinate), text: $place.name)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .text }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Look.planBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            // Каким значком отметить точку (P234).
            HStack(spacing: 0) {
                ForEach(Glyph.all.indices, id: \.self) { i in
                    let glyph = Glyph.all[i]
                    Button {
                        place.mark = glyph.name
                    } label: {
                        Image(systemName: glyph.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(place.mark == glyph.name ? .white : Look.inkSoft)
                            .frame(width: 32, height: 32)
                            .background(place.mark == glyph.name ? Look.inkSoft : Look.planBg.opacity(0.85),
                                        in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Значок: " + glyph.name)
                }
            }
            // Не выше шести строк; длиннее — прокручивается внутри.
            TextField("Что здесь было", text: $place.text, axis: .vertical)
                .focused($focused, equals: .text)
                .lineLimit(1...6)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Look.planBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Отмена", action: cancel)
                Spacer()
                Button("Готово") { done(place) }.fontWeight(.semibold)
            }
            .font(Look.sans(15))
            .padding(.horizontal, 4)
        }
        .font(Look.sans(15))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.top, Corner.size + 2)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .name }
        }
    }
}

/// Облачко выбранной точки сверху карты: название и что о ней написано —
/// и больше ничего. Дорога, копия и корзина — кнопками внизу (P228).
/// Клавиатура не открывается: точку смотрят, а не правят.
struct PlaceCloud: View {
    let place: Place
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(place.name.isEmpty ? Geo.text(place.coordinate) : place.name)
                    .font(Look.serif(17, weight: .semibold))
                    .foregroundStyle(Look.ink)
                    .lineLimit(2)
                Spacer()
                Button(place.file == nil ? "Назвать" : "Изменить", action: edit)
                    .font(Look.sans(14))
            }
            if !place.text.isEmpty {
                // Не выше шести строк; длиннее — прокручивается пальцем.
                ViewThatFits(in: .vertical) {
                    words
                    ScrollView { words }.frame(height: 6 * 20)
                }
                .frame(maxHeight: 6 * 20)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.top, Corner.size + 2)
    }

    private var words: some View {
        Text(place.text)
            .font(Look.serif(15))
            .foregroundStyle(Look.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Действия с выбранной точкой — общие для полоски карты и её меню.
enum MapActions {
    static func navigate(_ place: Place) {
        PlaceActions.openInMaps(place.coordinate, name: place.name)
    }

    static func navigate(_ point: GeoPoint) {
        PlaceActions.openInMaps(point.at, name: point.title)
    }

    static func copy(_ place: Place) { PlaceActions.copy(place.coordinate) }
    static func copy(_ point: GeoPoint) { PlaceActions.copy(point.at) }

    /// Поделиться точкой: название, координаты и ссылка на Карты — её
    /// откроет любой iPhone, а на других телефонах — браузер (P222).
    static func share(_ point: GeoPoint) {
        var words = point.title.isEmpty ? "" : point.title + "\n"
        words += Geo.text(point.at)
        var link = URLComponents(string: "https://maps.apple.com/")
        link?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.5f,%.5f",
                                                  point.at.latitude, point.at.longitude)),
            URLQueryItem(name: "q", value: point.title.isEmpty ? "Точка" : point.title),
        ]
        var items: [Any] = [words]
        if let url = link?.url { items.append(url) }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let shown = top.presentedViewController { top = shown }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
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
