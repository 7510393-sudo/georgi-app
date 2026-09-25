import Foundation
import CoreLocation

/// Место на своей карте человека.
///
/// Каждое место — обычный файл в папке «Места»: название и координаты в
/// шапке, ниже — что человек о нём написал. Карта целиком складывается из
/// этих файлов и переживёт приложение: файл откроется любым редактором,
/// а координаты — любыми картами (решение P207).
///
///     ---
///     название: Мой дом в Петербурге
///     место: 59.93863, 30.31413
///     ---
///
///     Жил здесь с 2004 по 2011 год. Во дворе — липа.
struct Place: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var text: String = ""
    /// Имя файла, если место уже лежит в папке.
    var file: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(name: String, coordinate: CLLocationCoordinate2D, text: String = "", file: String? = nil) {
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.text = text
        self.file = file
    }

    /// Разобрать файл места. Без координат это не место — `nil`.
    init?(text: String, file: String) {
        let parsed = DayFile(text: text)
        guard let where_ = parsed.value("место").flatMap(Geo.parse) else { return nil }
        let fallback = (file as NSString).deletingPathExtension
        self.init(name: parsed.value("название") ?? fallback, coordinate: where_,
                  text: parsed.body, file: file)
    }

    /// Файл места таким, каким он ляжет в папку.
    var fileText: String {
        var out = DayFile(body: text.trimmingCharacters(in: .whitespacesAndNewlines))
        out.set("название", name)
        out.set("место", Geo.text(coordinate))
        return out.text
    }

    /// Имя файла по названию: без знаков, которые не любят файловые
    /// системы. Название в шапке остаётся каким его написали.
    static func fileName(for name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let clean = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? "Место" : clean) + ".md"
    }
}

/// Координаты словами — так, как они лежат в файлах.
enum Geo {
    /// Для шапки файла: «59.93863, 30.31413».
    static func text(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }

    /// Для текста записи: «geo:59.93863,30.31413» — так пишут координаты
    /// ссылкой, и её понимают Карты (решение P165).
    static func line(_ c: CLLocationCoordinate2D) -> String {
        String(format: "geo:%.5f,%.5f", c.latitude, c.longitude)
    }

    /// Обратно: принимает и «59.9, 30.3», и «geo:59.9,30.3».
    static func parse(_ s: String) -> CLLocationCoordinate2D? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("geo:") { t.removeFirst(4) }
        let parts = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// Все места человека — чтение и запись папки «Места».
enum Places {

    static func folder(_ vault: Vault) -> URL? {
        vault.root?.appendingPathComponent(Vault.Folder.places.rawValue)
    }

    static func all(in vault: Vault) -> [Place] {
        guard let folder = folder(vault),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".md") }.sorted().compactMap { name in
            let reading = Vault.reading(at: folder.appendingPathComponent(name))
            guard case .text(let text) = reading else { return nil }
            return Place(text: text, file: name)
        }
    }

    /// Записать место. Файл с таким названием уже есть и он не этого
    /// места — к имени прибавляется номер: чужое не затирается никогда.
    /// Переименованное место переезжает в новый файл, старый убирается.
    @discardableResult
    static func save(_ place: Place, in vault: Vault) -> Place? {
        guard let folder = folder(vault) else { return nil }
        var stored = place
        var name = Place.fileName(for: place.name)
        if name != place.file {
            var n = 2
            let base = (name as NSString).deletingPathExtension
            while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
                name = "\(base) \(n).md"
                n += 1
            }
        }
        guard Vault.write(place.fileText, to: folder.appendingPathComponent(name)) == nil
        else { return nil }
        if let old = place.file, old != name {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
        }
        stored.file = name
        return stored
    }

    static func delete(_ place: Place, in vault: Vault) {
        guard let folder = folder(vault), let file = place.file else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
    }
}

/// Где человек сейчас. Спрашивает телефон один раз на каждую просьбу.
///
/// Разрешение просится только тогда, когда человек сам нажал на геоточку:
/// место без его жеста приложение не узнаёт никогда (A9).
final class Locator: NSObject, CLLocationManagerDelegate {

    static let shared = Locator()

    private let manager = CLLocationManager()
    private var waiting: [(CLLocation?) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current(_ done: @escaping (CLLocation?) -> Void) {
        waiting.append(done)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard !waiting.isEmpty else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: finish(nil)
        default: break
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        let all = waiting
        waiting = []
        all.forEach { $0(location) }
    }
}
