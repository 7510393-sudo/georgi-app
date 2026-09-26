import XCTest
import CoreLocation
@testable import Chronotheca

/// Места своей карты — обычные файлы, и координаты в них читаются
/// обратно без потерь (решение P207).
final class PlaceTests: XCTestCase {

    func testМестоТудаИОбратно() {
        let дом = Place(name: "Мой дом в Петербурге",
                        coordinate: CLLocationCoordinate2D(latitude: 59.93863, longitude: 30.31413),
                        text: "Жил здесь с 2004 по 2011 год.")
        let файл = дом.fileText
        XCTAssertTrue(файл.contains("название: Мой дом в Петербурге"))
        XCTAssertTrue(файл.contains("место: 59.93863, 30.31413"))
        let обратно = Place(text: файл, file: "Мой дом в Петербурге.md")
        XCTAssertEqual(обратно?.name, "Мой дом в Петербурге")
        XCTAssertEqual(обратно?.text, "Жил здесь с 2004 по 2011 год.")
        XCTAssertEqual(обратно?.latitude ?? 0, 59.93863, accuracy: 0.000001)
        XCTAssertEqual(обратно?.longitude ?? 0, 30.31413, accuracy: 0.000001)
    }

    func testБезКоординатНеМесто() {
        XCTAssertNil(Place(text: "Просто заметка", file: "заметка.md"))
    }

    func testИмяФайлаБезОпасныхЗнаков() {
        XCTAssertEqual(Place.fileName(for: "Дача: у озера / летом"), "Дача- у озера - летом.md")
        XCTAssertEqual(Place.fileName(for: "   "), "Место.md")
    }

    func testКоординатыСловами() {
        let c = CLLocationCoordinate2D(latitude: 54.3211, longitude: -2.7456)
        XCTAssertEqual(Geo.line(c), "geo:54.32110,-2.74560")
        XCTAssertEqual(Geo.parse("geo:54.32110,-2.74560")?.longitude ?? 0, -2.7456, accuracy: 0.00001)
        XCTAssertEqual(Geo.parse("54.3, 20")?.latitude ?? 0, 54.3, accuracy: 0.00001)
        XCTAssertNil(Geo.parse("geo:200,10"))
        XCTAssertNil(Geo.parse("не место"))
    }

    /// Точка в тексте дня: с названием — ссылкой, без — просто `geo:` (P213).
    func testТочкаВТекстеТудаИОбратно() {
        let c = CLLocationCoordinate2D(latitude: 59.93863, longitude: 30.31413)
        let строка = Geo.pointLine(GeoPoint(title: "Дом [старый]", at: c))
        XCTAssertEqual(строка, "[Дом (старый)](geo:59.93863,30.31413)")
        let обратно = Geo.point(in: строка)
        XCTAssertEqual(обратно?.title, "Дом (старый)")
        XCTAssertEqual(обратно?.at.latitude ?? 0, 59.93863, accuracy: 0.000001)
        XCTAssertEqual(Geo.pointLine(GeoPoint(title: " ", at: c)), "geo:59.93863,30.31413")
        XCTAssertEqual(Geo.point(in: "geo:59.93863,30.31413")?.title, "")
        XCTAssertNil(Geo.point(in: "[Дом](../../Фотографии/2026/x.jpg)"))
        XCTAssertNil(Geo.point(in: "Были у [Дом](geo:1,2) вечером"))
        // Точка — не вложение: она остаётся в тексте, а не уходит в полоску.
        XCTAssertNil(Diary.picture(in: строка))
        let запись = Diary(body: "Гуляли.\n\n" + строка)
        XCTAssertEqual(запись.photos, [])
        XCTAssertTrue(запись.text.hasSuffix(строка))
    }

    /// Точка с карты встаёт туда, где стоял курсор, своей строкой (P213).
    func testТочкаВстаётНаМестоКурсора() {
        let (посреди, курсор) = DayStore.insert("geo:1.00000,2.00000",
                                                into: "Утром туман. Днём солнце.", at: 12)
        XCTAssertEqual(посреди, "Утром туман.\ngeo:1.00000,2.00000\n Днём солнце.")
        XCTAssertEqual(курсор, ("Утром туман.\ngeo:1.00000,2.00000" as NSString).length)
        let (вКонце, _) = DayStore.insert("geo:1.00000,2.00000", into: "Туман.\n", at: nil)
        XCTAssertEqual(вКонце, "Туман.\ngeo:1.00000,2.00000")
        let (сНачала, _) = DayStore.insert("geo:1.00000,2.00000", into: "", at: 0)
        XCTAssertEqual(сНачала, "geo:1.00000,2.00000")
    }

    /// Значок места лежит в шапке файла словом и читается обратно; чужое
    /// слово — обычная точка (P234).
    func testЗначокМестаВФайле() {
        var дача = Place(name: "Дача", coordinate: CLLocationCoordinate2D(latitude: 55, longitude: 37))
        дача.mark = "дом"
        let файл = дача.fileText
        XCTAssertTrue(файл.contains("значок: дом"))
        XCTAssertEqual(Place(text: файл, file: "Дача.md")?.mark, "дом")
        let чужое = файл.replacingOccurrences(of: "значок: дом", with: "значок: ракета")
        XCTAssertEqual(Place(text: чужое, file: "Дача.md")?.mark, Glyph.standard)
    }
}
