import XCTest
@testable import DriverCore

final class DailyPaceTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
    }

    func testTurnoDaNoitePassaDaMeiaNoite() {
        let plan = DailyPlan(workdays: 6, endHour: 3, dayStartHour: 6)
        // 01:30 de quarta ainda é o dia de trabalho de terça.
        XCTAssertEqual(DailyPace.workdayStart(d(2026, 11, 25, 1, 30), plan: plan, calendar: cal), d(2026, 11, 24, 6))
        XCTAssertEqual(DailyPace.shiftEnd(d(2026, 11, 24, 20), plan: plan, calendar: cal), d(2026, 11, 25, 3))
        let entries = [(d(2026, 11, 24, 21), 30.0), (d(2026, 11, 25, 0, 30), 20.0), (d(2026, 11, 24, 5), 99.0)]
        XCTAssertEqual(DailyPace.earned(entries, now: d(2026, 11, 25, 1), plan: plan, calendar: cal), 50)

        let s = DailyPace.status(earned: 170, now: d(2026, 11, 24, 22), plan: plan, weekly: WeeklyGoal(revenue: 2820, hoursOnline: 56), calendar: cal)
        XCTAssertEqual(s.goal, 470, accuracy: 1e-9)
        XCTAssertEqual(s.hoursLeft, 5, accuracy: 1e-9)
        XCTAssertEqual(s.neededPerHour!, 60, accuracy: 1e-9)
        // Passou do fim do turno: não dá para calcular o ritmo.
        XCTAssertNil(DailyPace.status(earned: 170, now: d(2026, 11, 25, 4), plan: plan, weekly: WeeklyGoal(), calendar: cal).neededPerHour)
    }

    func testMetaFixaEAjustesAntigos() throws {
        XCTAssertEqual(DailyPlan(goal: 400).dailyGoal(weekly: WeeklyGoal()), 400)
        let p = try JSONDecoder().decode(DailyPlan.self, from: Data(#"{"goal":350}"#.utf8))
        XCTAssertEqual(p.endHour, 3)
        XCTAssertEqual(p.goal, 350)
    }
}

final class DemandGuideTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()
    func d(_ day: Int, _ h: Int, _ min: Int = 0) -> Date {
        // Novembro de 2026: dia 21 é sábado, 22 domingo, 23 segunda.
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: min))!
    }
    func hub(_ id: String) -> DemandHub { DemandGuide.hubs.first { $0.id == id }! }

    func testJanelas() {
        XCTAssertEqual(DemandGuide.level(hub("iguatemi"), at: d(21, 22, 10), calendar: cal).0, 3)
        // Sexta 19h–03h: sábado 01h ainda conta.
        XCTAssertEqual(DemandGuide.level(hub("campolim"), at: d(21, 1), calendar: cal).0, 3)
        XCTAssertEqual(DemandGuide.level(hub("centro"), at: d(22, 15), calendar: cal).0, 0)
        XCTAssertEqual(DemandGuide.level(hub("uniso"), at: d(23, 22, 30), calendar: cal).0, 3)
        let next = DemandGuide.nextPeak(hub("uniso"), after: d(23, 20), calendar: cal)
        XCTAssertEqual(next?.at, d(23, 22, 15))
    }

    func testRankingPesaDistancia() {
        let campolim = GeoPoint(lat: -23.5317, lon: -47.4680, accuracy: 0, time: 0)
        let list = DemandGuide.advice(at: d(21, 22), from: campolim, calendar: cal)
        XCTAssertEqual(list.first { $0.hub.id == "campolim" }?.verdict, .here)
        // Sábado 22h perto do Iguatemi: vale ir. Éden (longe, periferia): não vale.
        XCTAssertEqual(list.first { $0.hub.id == "iguatemi" }?.verdict, .go)
        XCTAssertEqual(list.first { $0.hub.id == "eden" }?.verdict, .skip)
        XCTAssertTrue(DemandGuide.hubs.allSatisfy { !$0.windows.isEmpty })
    }

    func testHistoricoProprioEntraNaConta() {
        let h = hub("centro")
        let samples = (0..<6).map { i in
            HubSample(date: d(22, 15).addingTimeInterval(Double(-7 * 86400 * i)), lat: h.lat, lon: h.lon, perKm: 2.6, green: true)
        }
        let own = DemandGuide.own(h, at: d(22, 15), samples: samples, acceptPerKm: 2.3, calendar: cal)
        XCTAssertEqual(own?.count, 6)
        XCTAssertGreaterThan(own!.level, 2)
    }

    func testPrevisaoDoDestino() {
        XCTAssertEqual(DemandGuide.hub(matching: "Av. Antônio Carlos Comitre, 500 - Parque Campolim")?.id, "campolim")
        XCTAssertEqual(DemandGuide.hub(matching: "Shopping Iguatemi Esplanada, Votorantim")?.id, "iguatemi")
        XCTAssertNil(DemandGuide.hub(matching: "Rua Qualquer, 10"))
        // Sábado 22h10 no Iguatemi: alta → 20% acima do ideal.
        let o = DemandGuide.outlook("Iguatemi Esplanada", at: d(21, 22, 10), hourFloor: 42, hourIdeal: 54, calendar: cal)!
        XCTAssertEqual(o.level, 3)
        XCTAssertEqual(o.perHour, 64.8, accuracy: 1e-9)
        XCTAssertEqual(o.short, "Iguatemi Esplanada · Alta · ~R$ 65/h")
        let zn = DemandGuide.outlook("Vitória Régia, Sorocaba", at: d(23, 15), hourFloor: 42, hourIdeal: 54, calendar: cal)!
        XCTAssertTrue(zn.periphery)
        XCTAssertTrue(zn.short.contains("volta vazia"))
    }
}
