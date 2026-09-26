import XCTest
import CoreLocation
@testable import Chronotheca

/// Правила дня: куда можно писать, а куда нельзя.
///
/// Это не украшение интерфейса, а обещание: план не переписывают задним
/// числом, а дневник не пишут наперёд. Проверяем на настоящих файлах во
/// временной папке — как в жизни.
final class DayStoreTests: XCTestCase {

    private var folder: URL!
    private var vault: Vault!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("день-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        vault = Vault()
        vault.adopt(folder)
        // Приложение больше не заводит папку само (P97) — соглашаемся за
        // человека, как он сделал бы в окне вопроса.
        XCTAssertNotNil(vault.proposal, "в пустом месте должно быть предложение")
        vault.acceptProposal()
        XCTAssertNil(vault.problem, "папка не открылась: \(vault.problem ?? "")")
        XCTAssertNotNil(vault.root)
    }

    override func tearDown() {
        vault.forget()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func store(_ shift: Int) -> DayStore {
        let date = Calendar.current.date(byAdding: .day, value: shift, to: DayStore.today())!
        return DayStore(vault: vault, date: date)
    }

    func testПланПрошедшегоДняЗакрыт() {
        let вчера = store(-1)
        XCTAssertTrue(вчера.isPast)
        XCTAssertFalse(вчера.canEditPlan)
        XCTAssertTrue(вчера.closedReason.contains("День закрыт"))
    }

    func testПланБудущегоДняОткрыт() {
        // Ради этого планировщик и нужен: дела заводят заранее.
        let завтра = store(1)
        XCTAssertTrue(завтра.canEditPlan)
        XCTAssertTrue(store(0).canEditPlan)
    }

    func testДневникПишетсяЗаднимЧислом() {
        // Решение P63: вчерашнее дописывают и через неделю.
        XCTAssertTrue(store(-1).canEditDiary)
        XCTAssertTrue(store(-30).canEditDiary)
    }

    func testДневникБудущегоДняЗакрыт() {
        let завтра = store(1)
        XCTAssertFalse(завтра.canEditDiary)
        XCTAssertTrue(завтра.closedReason.contains("не наступил"))
    }

    func testЗаголовкиБлижнихДней() {
        XCTAssertEqual(store(0).title, "Сегодня")
        XCTAssertEqual(store(-1).title, "Вчера")
        XCTAssertEqual(store(-2).title, "Позавчера")
        XCTAssertEqual(store(1).title, "Завтра")
        XCTAssertEqual(store(2).title, "Послезавтра")
    }

    func testПустойДеньНеОставляетФайлов() {
        // Пролистывание недели вперёд не должно засевать чужую папку
        // пустыми файлами: папка не наша.
        let день = store(3)
        день.save()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vault.file(.planner, for: день.date)!.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vault.file(.diary, for: день.date)!.path))
    }

    func testНаписанноеПереживаетУходИВозврат() {
        let день = store(0)
        день.planRows = [.task(time: "09:00", "Отвезти документы")]
        день.diaryText = "Был туман."
        день.save()

        день.move(by: 1)          // ушли на завтра
        день.move(by: -1)         // вернулись
        XCTAssertEqual(день.planRows.count, 1)
        XCTAssertEqual(день.planRows.first?.text, "Отвезти документы")
        XCTAssertEqual(день.planRows.first?.time, "09:00")
        XCTAssertEqual(день.diaryText, "Был туман.")
    }
}

extension DayStoreTests {

    func testРежимИзмененийОткрываетПрошедшийДень() {
        let вчера = store(-1)
        XCTAssertFalse(вчера.canEditPlan)
        // Режим дневника план не открывает: у каждой вкладки свой (P211).
        вчера.setEditing(.diary, true)
        XCTAssertFalse(вчера.canEditPlan)
        вчера.setEditing(.plan, true)
        XCTAssertTrue(вчера.canEditPlan)
        // Уход со дня гасит режим: его нельзя забыть включённым.
        вчера.move(by: -1)
        XCTAssertFalse(вчера.editing(.plan))
        XCTAssertFalse(вчера.editing(.diary))
    }

    func testЗаголовокИОтветыЛожатсяВФайлДневника() {
        let день = store(0)
        день.planRows = [.task("Позвонить в поликлинику")]
        день.diaryTitle = "Туман"
        день.answers = ["Позвонить в поликлинику": "так и не собрался"]
        день.diaryText = "08:15 Проснулся раньше будильника."
        день.save()

        let на_диске = день.onDisk()
        XCTAssertTrue(на_диске.contains("заголовок: Туман"))
        XCTAssertTrue(на_диске.contains("## Как прошло?"))
        XCTAssertTrue(на_диске.contains("- Позвонить в поликлинику: так и не собрался"))

        день.move(by: 1)
        день.move(by: -1)
        XCTAssertEqual(день.diaryTitle, "Туман")
        XCTAssertEqual(день.answers["Позвонить в поликлинику"], "так и не собрался")
        XCTAssertEqual(день.diaryText, "08:15 Проснулся раньше будильника.")
    }

    func testОписьВидитТоЧтоНаписано() {
        let день = store(0)
        день.planRows = [.task(time: "09:00", "Отвезти документы")]
        день.diaryTitle = "Туман"
        день.save()

        let опись = Archive(vault: vault)
        опись.reload()
        let стамп = Vault.stamp(день.date)
        XCTAssertEqual(опись.tasks(стамп).count, 1)
        XCTAssertEqual(опись.day(стамп)?.title, "Туман")
        XCTAssertEqual(опись.newestFirst.count, 1)
    }
}

extension DayStoreTests {

    func testДеньСОднимЗаголовкомНеПропадает() {
        // Заголовок — это уже запись. Проверка «день пустой» однажды смотрела
        // только на текст и молча выбрасывала такой день.
        let день = store(0)
        день.diaryTitle = "Туман"
        день.save()

        день.move(by: 1)
        день.move(by: -1)
        XCTAssertEqual(день.diaryTitle, "Туман")
    }
}

extension DayStoreTests {

    func testПапкаВнутриАрхиваНеПлодитВторойАрхив() {
        // Человек, ищущий свою папку, заходит внутрь неё. Заводить там второй
        // архив — значит разорвать записи надвое. Именно это однажды и вышло.
        let внутри = vault.root!.appendingPathComponent(Vault.Folder.diary.rawValue)
        let корень = vault.root!
        let другой = Vault()
        другой.forget()
        другой.adopt(внутри)

        XCTAssertNil(другой.proposal, "предлагать заводить папку здесь нельзя")
        XCTAssertEqual(другой.root?.standardizedFileURL, корень.standardizedFileURL,
                       "должен найтись тот же архив, а не новый")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: внутри.appendingPathComponent(Vault.folderName).path),
            "внутри «Дневника» не должно появиться новой папки")
        другой.forget()
    }

    func testНоваяПапкаНеЗаводитсяБезСогласия() {
        let пустое = FileManager.default.temporaryDirectory
            .appendingPathComponent("пусто-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: пустое, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: пустое) }

        // Начинаем с чистого листа: проверки делят одну память настроек,
        // и закладка соседней проверки подхватилась бы при запуске.
        let v = Vault()
        v.forget()
        v.adopt(пустое)

        XCTAssertNotNil(v.proposal, "должно быть предложение, а не молчаливое создание")
        XCTAssertNil(v.root, "до согласия ничего не выбрано")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: пустое.appendingPathComponent(Vault.folderName).path),
            "до согласия ничего не создано")

        v.acceptProposal()
        XCTAssertNotNil(v.root)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: пустое.appendingPathComponent(Vault.folderName).path))
        v.forget()
    }

    /// Первое «где я сейчас» становится местом дня; дальше место дня не
    /// переставляется само, а точка с чужим местом его не трогает (P221).
    func testТочкаГдеЯСтановитсяМестомДня() {
        let день = store(0)
        let дом = CLLocationCoordinate2D(latitude: 54.3211, longitude: -2.7456)
        let чужое = CLLocationCoordinate2D(latitude: 59.9, longitude: 30.3)
        день.writePoint(GeoPoint(title: "Петербург", at: чужое), to: .diary)
        XCTAssertNil(день.place)
        день.writePoint(GeoPoint(title: "", at: дом), to: .diary, here: true)
        XCTAssertEqual(день.place, "54.32110, -2.74560")
        день.writePoint(GeoPoint(title: "", at: чужое), to: .diary, here: true)
        XCTAssertEqual(день.place, "54.32110, -2.74560")
    }

    /// Точку в плане переставляют между делами; скрытые строки файла
    /// остаются на месте (P226).
    func testТочкаПереставляетсяМеждуДелами() {
        let день = store(0)
        день.planRows = [.task("Первое"), .task("Второе"),
                         .verbatim("[Дом](geo:54.32110,-2.74560)"), .verbatim("")]
        let точка = день.planRows[2].id
        день.moveLine(точка, by: -2)
        XCTAssertEqual(день.planRows.map { $0.verbatim ?? $0.text },
                       ["[Дом](geo:54.32110,-2.74560)", "Первое", "Второе", ""])
        день.moveLine(точка, by: 1)
        XCTAssertEqual(день.planRows.map { $0.verbatim ?? $0.text },
                       ["Первое", "[Дом](geo:54.32110,-2.74560)", "Второе", ""])
    }

    /// Дописывая вчерашний день, человек видит, когда дописал: к времени
    /// встаёт короткая дата (P227). В сегодняшнем — только время.
    func testВПрошедшийДеньОтметкаСДатой() {
        let вчера = store(-1)
        XCTAssertTrue(вчера.stampIfNeeded())
        XCTAssertNotNil(вчера.diaryText.range(
            of: #"^\d{2}\.\d{2}\.\d{2} \d{2}:\d{2} $"#, options: .regularExpression))
        let сегодня = store(0)
        XCTAssertTrue(сегодня.stampIfNeeded())
        XCTAssertNotNil(сегодня.diaryText.range(
            of: #"^\d{2}:\d{2} $"#, options: .regularExpression))
        let строка = "25.09.26 08:15 Дописал"
        XCTAssertEqual(DiaryEditor.stamp.firstMatch(
            in: строка, range: NSRange(location: 0, length: (строка as NSString).length))?
            .numberOfRanges, 2)
    }
}
