import SwiftUI
import UIKit
import MapKit

/// Своя карта человека: его места с названиями и дни, где он был.
///
/// Открывается кнопкой «геоточка». Название места видно всегда, прямо на
/// карте; касание по месту — облачко с тем, что человек о нём написал;
/// долгое нажатие на карту — новое место. Кнопка внизу отмечает, где
/// человек в открытый день (решение P207).
///
/// Карта — Карты Apple; своих серверов у приложения нет (P198). Места —
/// файлы в папке «Места», по файлу на место.
struct MapScreen: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    @State private var places: [Place] = []
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Место, которое сейчас заводят или правят.
    @State private var editing: Place?
    /// Место, чьё облачко открыто.
    @State private var opened: Place?
    @State private var locating = false
    /// Новое место, пока ему дают название: булавка стоит на карте сразу,
    /// чтобы было видно, что карта поняла палец (P210).
    @State private var draft: Place?
    /// Где палец коснулся карты последний раз — туда и встанет новое место.
    @State private var touch: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            header
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(days) { day in
                        Annotation(Ru.shortDate(day.date), coordinate: day.at, anchor: .center) {
                            DayDot(today: day.id == Vault.stamp(store.date))
                                .onTapGesture { openDay(day.date) }
                        }
                        .annotationTitles(.hidden)
                    }
                    ForEach(places) { place in
                        Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                            PlacePin(name: place.name)
                                .onTapGesture { opened = place }
                        }
                        .annotationTitles(.hidden)
                    }
                    ForEach(draft.map { [$0] } ?? []) { place in
                        Annotation("", coordinate: place.coordinate, anchor: .bottom) {
                            PlacePin(name: "Новое место")
                                .opacity(0.8)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                // Где палец — запоминается на каждом касании; долгое нажатие
                // ставит туда булавку сразу, с отдачей в палец, и открывает
                // название. Прежде булавка не появлялась, и было непонятно,
                // поняла ли карта палец (P210).
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { touch = $0.location })
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            guard let at = proxy.convert(touch, from: .local) else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let new = Place(name: "", coordinate: at)
                            draft = new
                            editing = new
                        })
            }
            .safeAreaInset(edge: .bottom) { here }
        }
        .background(Look.chrome)
        .sheet(item: $opened) { place in
            PlaceCloud(place: place) {
                opened = nil
                editing = place
            }
            .presentationDetents([.fraction(0.35), .medium])
        }
        .sheet(item: $editing, onDismiss: { draft = nil }) { place in
            PlaceEditor(place: place, save: save, remove: remove)
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

    /// Дни, в которые человек отметил, где был.
    private struct DayPoint: Identifiable {
        let id: String
        let date: Date
        let at: CLLocationCoordinate2D
    }

    private var days: [DayPoint] {
        archive.days.values.compactMap { day in
            day.place.map { DayPoint(id: day.stamp, date: day.date, at: $0) }
        }
    }

    /// Открыть карту: на дне, где место отмечено, — там; иначе — где
    /// человек сейчас. Разрешение на место просится здесь, по его жесту.
    private func begin() {
        places = Places.all(in: vault)
        archive.reload()
        if let at = store.placeCoordinate {
            camera = .region(MKCoordinateRegion(center: at, latitudinalMeters: 2000,
                                                longitudinalMeters: 2000))
        } else {
            Locator.shared.current { _ in }
        }
    }

    /// Кнопка внизу: отметить, где человек в открытый день.
    private var here: some View {
        let marked = store.place != nil
        return Button {
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
                withAnimation {
                    camera = .region(MKCoordinateRegion(center: at, latitudinalMeters: 1500,
                                                        longitudinalMeters: 1500))
                }
            }
        } label: {
            HStack(spacing: 8) {
                if locating { ProgressView() } else {
                    Image(systemName: marked ? "mappin.circle.fill" : "mappin.and.ellipse")
                }
                Text(marked ? "Переставить место дня сюда" : "Я здесь в этот день")
            }
            .font(Look.sans(15, weight: .medium))
            .foregroundStyle(Look.planBg)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Look.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
    }

    private func openDay(_ date: Date) {
        store.go(to: date)
        shell.tab = .diary
        shell.screen = .today
        shell.showingMap = false
    }

    private func save(_ place: Place) {
        editing = nil
        draft = nil
        guard let stored = Places.save(place, in: vault) else {
            return shell.say("Место не записалось. Проверьте папку в настройках.")
        }
        places.removeAll { $0.id == place.id || ($0.file != nil && $0.file == place.file) }
        places.append(stored)
    }

    private func remove(_ place: Place) {
        editing = nil
        Places.delete(place, in: vault)
        places.removeAll { $0.id == place.id }
    }
}

/// Метка места: булавка и название под ней — всегда на виду.
struct PlacePin: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white, Look.accent)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            Text(name)
                .font(Look.sans(12, weight: .semibold))
                .foregroundStyle(Look.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Look.sticker.opacity(0.95), in: RoundedRectangle(cornerRadius: 5))
        }
        .accessibilityLabel(name)
    }
}

/// Точка дня, в который человек отметил, где был.
struct DayDot: View {
    let today: Bool

    var body: some View {
        Circle()
            .fill(today ? Look.accent : Look.inkSoft)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

/// Облачко места: название и то, что человек о нём написал.
struct PlaceCloud: View {
    let place: Place
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(place.name)
                    .font(Look.serif(19, weight: .semibold))
                    .foregroundStyle(Look.ink)
                Spacer()
                Button("Изменить", action: edit)
                    .font(Look.sans(14))
            }
            ScrollView {
                Text(place.text.isEmpty ? "Здесь пока ничего не написано." : place.text)
                    .font(Look.serif(15.5))
                    .foregroundStyle(place.text.isEmpty ? Look.inkFaint : Look.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Дорога туда — в Картах; точку можно и скопировать (P210).
            HStack(spacing: 12) {
                Button {
                    PlaceActions.openInMaps(place.coordinate, name: place.name)
                } label: {
                    Label("Проложить путь", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                Spacer()
                Button {
                    PlaceActions.copy(place.coordinate)
                } label: {
                    Label("Скопировать точку", systemImage: "doc.on.doc")
                }
            }
            .font(Look.sans(14))
        }
        .padding(20)
        .background(Look.sticker)
    }
}

/// Завести или поправить место.
struct PlaceEditor: View {

    @State var place: Place
    let save: (Place) -> Void
    let remove: (Place) -> Void

    @State private var asking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Название на карте") {
                    TextField("Например, «Мой дом в Петербурге»", text: $place.name)
                }
                Section("Что здесь было") {
                    TextEditor(text: $place.text)
                        .frame(minHeight: 160)
                }
                if place.file != nil {
                    Section {
                        Button("Убрать место с карты", role: .destructive) { asking = true }
                    }
                }
            }
            .navigationTitle(place.file == nil ? "Новое место" : "Место")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { save(place) }
                        .fontWeight(.semibold)
                        .disabled(place.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Убрать «\(place.name)» с карты?", isPresented: $asking,
                                titleVisibility: .visible) {
                Button("Убрать", role: .destructive) { remove(place) }
            } message: {
                Text("Файл этого места будет удалён из папки «Места».")
            }
        }
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
