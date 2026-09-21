import XCTest
@testable import Chronotheca

/// Дневник: ответы «Как прошло?» и текст живут в одном файле и не портят
/// друг друга. Главное правило то же, что у плана: чужое — не трогаем.
final class DiaryTests: XCTestCase {

    func testТекстБезОтветовОстаётсяТекстом() {
        let d = Diary(body: "08:15 Туман над полем.\n\n23:40 Глава дописана.")
        XCTAssertTrue(d.answers.isEmpty)
        XCTAssertEqual(d.text, "08:15 Туман над полем.\n\n23:40 Глава дописана.")
    }

    func testОтветыОтделяютсяОтТекста() {
        let d = Diary(body: """
        ## Как прошло?

        - Отвезти документы: всё получилось
        - Позвонить в поликлинику: не собрался

        08:15 Туман над полем.
        """)
        XCTAssertEqual(d.answers["Отвезти документы"], "всё получилось")
        XCTAssertEqual(d.answers["Позвонить в поликлинику"], "не собрался")
        XCTAssertEqual(d.text, "08:15 Туман над полем.")
    }

    func testТудаИОбратноБезПотерь() {
        let order = ["Отвезти документы", "Позвонить в поликлинику"]
        let d = Diary(answers: ["Отвезти документы": "всё получилось",
                                "Позвонить в поликлинику": "не собрался"],
                      text: "08:15 Туман над полем.")
        XCTAssertEqual(Diary(body: d.body(order: order)), d)
    }

    func testПустыеОтветыВФайлНеПопадают() {
        let d = Diary(answers: ["Отвезти документы": ""], text: "Текст.")
        XCTAssertEqual(d.body(order: ["Отвезти документы"]), "Текст.")
    }

    func testЗаголовокНижеПоТекстуНеСчитаетсяНашим() {
        // Такая же строка в середине записи — часть текста человека.
        let body = "Сегодня думал вот о чём.\n\n## Как прошло?\n\n- всё странно"
        let d = Diary(body: body)
        XCTAssertTrue(d.answers.isEmpty)
        XCTAssertEqual(d.text, body)
    }

    func testНапоминаниеЖивётВСтрокеДела() {
        let rows = Plan.rows(from: "- [ ] 09:00 Отвезти документы (напомнить 08:30)")
        XCTAssertEqual(rows.first?.text, "Отвезти документы")
        XCTAssertEqual(rows.first?.bell, "08:30")
        XCTAssertEqual(Plan.body(from: rows),
                       "- [ ] 09:00 Отвезти документы (напомнить 08:30)")
    }
}
