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

    // MARK: - Написанное не пропадает

    func testОтветБезСвоегоДелаНеВыбрасывается() {
        // Человек написал ответ, потом переименовал дело. Ответ остаётся:
        // написанное не исчезает оттого, что приложению неудобно.
        let d = Diary(answers: ["Отвезти документы": "всё получилось"], text: "Туман.")
        let body = d.body(order: ["Отвезти бумаги"])
        XCTAssertTrue(body.contains("всё получилось"), "ответ пропал:\n" + body)

        let назад = Diary(body: body)
        XCTAssertEqual(назад.answers["Отвезти документы"], "всё получилось")
        XCTAssertEqual(назад.text, "Туман.")
    }

    func testДвоеточиеВОтветеНеЛомаетРазбор() {
        // «сделал в 10:30» — самый обычный ответ.
        let d = Diary(answers: ["Позвонить": "сделал в 10:30"], text: "")
        let назад = Diary(body: d.body(order: ["Позвонить"]))
        XCTAssertEqual(назад.answers["Позвонить"], "сделал в 10:30")
        XCTAssertNil(назад.answers["Позвонить: сделал в 10"])
    }

    func testДвоеточиеВНазванииДелаРазбираетсяПоСписку() {
        let дело = "Позвонить в 10:00 врачу"
        let d = Diary(answers: [дело: "не собрался"], text: "")
        let назад = Diary(body: d.body(order: [дело]), known: [дело])
        XCTAssertEqual(назад.answers[дело], "не собрался")
    }

    func testОтветыПереживаютНесколькоЗаписейПодряд() {
        // Так выглядит день: написали ответ, переименовали дело, снова
        // сохранили. После трёх оборотов должно уцелеть всё.
        var d = Diary(answers: ["Первое": "да", "Второе": "нет"], text: "Запись.")
        for order in [["Первое", "Второе"], ["Первое"], []] {
            d = Diary(body: d.body(order: order))
        }
        XCTAssertEqual(d.answers["Первое"], "да")
        XCTAssertEqual(d.answers["Второе"], "нет")
        XCTAssertEqual(d.text, "Запись.")
    }

    // MARK: - Начало записи для поиска

    func testПустыеСтрокиВНаходкуНеПопадают() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(),
                              text: "08:15 Туман над полем.\n\n23:40 Глава дописана.")
        XCTAssertEqual(day.preview, "08:15 Туман над полем.\n23:40 Глава дописана.")
    }

    func testСтрокаИзОднихПробеловТожеПустая() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(),
                              text: "Первая\n   \n\nВторая")
        XCTAssertEqual(day.preview, "Первая\nВторая")
    }

    func testЗаписьБезПустыхСтрокНеМеняется() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(),
                              text: "Первая\nВторая")
        XCTAssertEqual(day.preview, "Первая\nВторая")
    }

    func testПустаяЗаписьДаётПустоеНачало() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(), text: "\n\n  \n")
        XCTAssertEqual(day.preview, "")
    }

    func testНапоминаниеЖивётВСтрокеДела() {
        let rows = Plan.rows(from: "- [ ] 09:00 Отвезти документы (напомнить 08:30)")
        XCTAssertEqual(rows.first?.text, "Отвезти документы")
        XCTAssertEqual(rows.first?.bell, "08:30")
        XCTAssertEqual(Plan.body(from: rows),
                       "- [ ] 09:00 Отвезти документы (напомнить 08:30)")
    }

    // MARK: - Фотографии (P200)

    func testФотографияОтделяетсяОтТекста() {
        let d = Diary(body: """
        08:15 Туман над полем.

        ![](../../Фотографии/2026/2026-09-24_08.15.30.jpg)
        """)
        XCTAssertEqual(d.text, "08:15 Туман над полем.")
        XCTAssertEqual(d.photos, ["../../Фотографии/2026/2026-09-24_08.15.30.jpg"])
    }

    func testФотографииВстаютВКонецЗаписи() {
        let d = Diary(answers: ["Отвезти документы": "всё получилось"],
                      text: "08:15 Туман.",
                      photos: ["../../Фотографии/2026/a.jpg", "../../Фотографии/2026/b.jpg"])
        let body = d.body(order: ["Отвезти документы"])
        XCTAssertTrue(body.hasSuffix("""
        08:15 Туман.

        ![](../../Фотографии/2026/a.jpg)
        ![](../../Фотографии/2026/b.jpg)
        """))
        XCTAssertEqual(Diary(body: body, known: ["Отвезти документы"]), d)
    }

    func testСсылкаПосредиФразыОстаётсяТекстом() {
        let body = "Вот снимок ![](a.jpg) — смотри."
        let d = Diary(body: body)
        XCTAssertEqual(d.text, body)
        XCTAssertTrue(d.photos.isEmpty)
    }

    func testПутьСПробеломВУгловыхСкобках() {
        let d = Diary(body: "![](<../../Фотографии/2026/мой снимок.jpg>)")
        XCTAssertEqual(d.photos, ["../../Фотографии/2026/мой снимок.jpg"])
        XCTAssertEqual(d.body(order: []), "![](<../../Фотографии/2026/мой снимок.jpg>)")
    }

    func testДеньТолькоСФотографией() {
        let d = Diary(photos: ["../../Фотографии/2026/a.jpg"])
        XCTAssertEqual(d.body(order: []), "![](../../Фотографии/2026/a.jpg)")
    }

    func testФотографияПосредиТекстаОстаётсяНаМесте() {
        let body = """
        08:15 Туман.
        ![](../../Фотографии/2026/a.jpg)
        23:40 Глава дописана.

        ![](../../Фотографии/2026/b.jpg)
        """
        let d = Diary(body: body)
        XCTAssertEqual(d.photos, ["../../Фотографии/2026/b.jpg"])
        XCTAssertTrue(d.text.contains("![](../../Фотографии/2026/a.jpg)"))
        XCTAssertEqual(d.body(order: []), body)
    }
}
