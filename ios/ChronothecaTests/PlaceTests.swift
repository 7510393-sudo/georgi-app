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
}
