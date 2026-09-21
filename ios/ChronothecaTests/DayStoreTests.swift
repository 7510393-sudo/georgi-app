import XCTest
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
        XCTAssertNil(vault.problem, "папка не открылась: \(vault.problem ?? "")")
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
        день.diary = "Был туман."
        день.save()

        день.move(by: 1)          // ушли на завтра
        день.move(by: -1)         // вернулись
        XCTAssertEqual(день.planRows.count, 1)
        XCTAssertEqual(день.planRows.first?.text, "Отвезти документы")
        XCTAssertEqual(день.planRows.first?.time, "09:00")
        XCTAssertEqual(день.diary, "Был туман.")
    }
}
