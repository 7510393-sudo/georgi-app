import XCTest
@testable import Chronotheca

/// Дорога домой: сколько поворотов и какой длины.
///
/// Правило простое: человек должен увидеть, что возвращается издалека, но
/// ждать недолго. Значит, не больше трёх поворотов — и сумма шагов ровно
/// равна расстоянию, иначе он окажется не дома (решение P164).
final class WayHomeTests: XCTestCase {

    func testДомаДорогиНет() {
        XCTAssertEqual(wayHome(0), [])
    }

    func testСоседнийДеньОдинПоворот() {
        XCTAssertEqual(wayHome(1), [1])
        XCTAssertEqual(wayHome(-1), [-1])
    }

    func testДваДняДваПоворота() {
        XCTAssertEqual(wayHome(2), [1, 1])
    }

    func testДальшеТрёхПоворотовНеБывает() {
        for расстояние in [3, 7, 10, 40, 365, -3, -7, -10, -40, -365] {
            XCTAssertLessThanOrEqual(wayHome(расстояние).count, 3,
                                     "расстояние \(расстояние)")
        }
    }

    func testСуммаШаговРавнаРасстоянию() {
        // Главная проверка: иначе человек окажется не дома.
        for расстояние in (-400...400) {
            XCTAssertEqual(wayHome(расстояние).reduce(0, +), расстояние,
                           "расстояние \(расстояние)")
        }
    }

    func testВсеШагиВОднуСторону() {
        for расстояние in [10, 40, 365, -10, -40, -365] {
            let знак = расстояние > 0 ? 1 : -1
            for шаг in wayHome(расстояние) {
                XCTAssertEqual(шаг > 0 ? 1 : -1, знак,
                               "шаг \(шаг) идёт не в ту сторону")
            }
        }
    }

    func testПустыхШаговНет() {
        for расстояние in (-50...50) {
            XCTAssertFalse(wayHome(расстояние).contains(0))
        }
    }

    func testДорогаОтДняКСегодня() {
        let вчера = Calendar.current.date(byAdding: .day, value: -1,
                                          to: DayStore.today())!
        XCTAssertEqual(DayPages.wayHome(from: вчера), [1])
        XCTAssertEqual(DayPages.wayHome(from: DayStore.today()), [])
    }
}
