import XCTest
@testable import DriverCore

final class OdometerTests: XCTestCase {
    /// Ponto a `meters` ao norte da origem (Sorocaba), no instante `t`.
    func p(_ meters: Double, _ t: TimeInterval, acc: Double = 5, east: Double = 0) -> GeoPoint {
        let lat = -23.5015 + meters / 111_320
        let lon = -47.4526 + east / (111_320 * cos(-23.5015 * .pi / 180))
        return GeoPoint(lat: lat, lon: lon, accuracy: acc, time: t)
    }

    func testSomaTrajetoReto() {
        var o = OdometerTracker()
        for i in 0...100 { o.add(p(Double(i) * 15, Double(i))) } // 15 m/s por 100 s
        XCTAssertEqual(o.meters, 1500, accuracy: 3)
        XCTAssertEqual(o.km, 1.5, accuracy: 0.003)
        XCTAssertEqual(o.lastMoveAt, 100)
    }

    func testCarroParadoNaoSoma() {
        var o = OdometerTracker()
        let jitter: [Double] = [0, 3, -4, 6, -2, 5, -6, 2, 0, 4]
        for (i, j) in jitter.enumerated() { o.add(p(j, Double(i) * 2, east: -j)) }
        XCTAssertEqual(o.meters, 0)
        XCTAssertNil(o.lastMoveAt)
    }

    func testIgnoraPosicaoImprecisaESaltos() {
        var o = OdometerTracker()
        o.add(p(0, 0))
        o.add(p(100, 10))
        XCTAssertEqual(o.add(p(5000, 11, acc: 200)), 0) // imprecisa
        XCTAssertEqual(o.add(p(9000, 12)), 0)           // 8,9 km em 2 s
        o.add(p(200, 20))
        XCTAssertEqual(o.meters, 200, accuracy: 1)
    }

    func testReferenciaErradaSeCorrigeSozinha() {
        var o = OdometerTracker()
        o.add(p(50_000, 0)) // primeira posição errada
        o.add(p(0, 1)); o.add(p(15, 2)); o.add(p(30, 3)) // três saltos seguidos → troca a referência
        o.add(p(45, 4)); o.add(p(60, 5))
        XCTAssertEqual(o.meters, 30, accuracy: 1)
    }

    func testBuracoDeSinal() {
        var o = OdometerTracker()
        o.add(p(0, 0))
        // 5 min sem sinal, 3 km adiante: soma a linha reta.
        XCTAssertEqual(o.add(p(3000, 300)), 3000, accuracy: 5)
        // 2 h sem sinal: recomeça sem somar.
        XCTAssertEqual(o.add(p(60_000, 300 + 7200)), 0)
        o.add(p(60_100, 300 + 7210))
        XCTAssertEqual(o.meters, 3100, accuracy: 6)
    }

    func testGuardaEVoltaIgual() throws {
        var o = OdometerTracker()
        o.add(p(0, 0)); o.add(p(500, 30))
        let back = try JSONDecoder().decode(OdometerTracker.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(back, o)
    }
}

final class DrivingCalculatorTests: XCTestCase {
    func testDetalhadoComKmMorto() {
        // 180 km rodados, 120 em corrida, R$ 320 em 9 h; 11 km/L a R$ 6,20; R$ 0,15/km de outros custos.
        let r = DrivingCalculator.calculate(DrivingInput(kmDriven: 180, paidKm: 120, revenue: 320, hours: 9,
                                                         consumptionKmPerLiter: 11, fuelPrice: 6.20, otherCostPerKm: 0.15))!
        XCTAssertTrue(r.detailed)
        XCTAssertEqual(r.fuelLiters!, 16.3636, accuracy: 1e-3)
        XCTAssertEqual(r.fuelCost!, 101.4545, accuracy: 1e-3)
        XCTAssertEqual(r.otherCost!, 27, accuracy: 1e-9)
        XCTAssertEqual(r.totalCost, 128.4545, accuracy: 1e-3)
        XCTAssertEqual(r.costPerKm, 0.7136, accuracy: 1e-3)
        XCTAssertEqual(r.profit, 191.5455, accuracy: 1e-3)
        XCTAssertEqual(r.revenuePerKm, 1.7778, accuracy: 1e-3)
        XCTAssertEqual(r.revenuePerPaidKm!, 2.6667, accuracy: 1e-3)
        XCTAssertEqual(r.deadKm!, 60, accuracy: 1e-9)
        XCTAssertEqual(r.deadShare!, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(r.breakEvenPerPaidKm!, 1.0705, accuracy: 1e-3)
        XCTAssertEqual(r.revenuePerHour!, 35.5556, accuracy: 1e-3)
        XCTAssertEqual(r.profitPerHour!, 21.2828, accuracy: 1e-3)
        XCTAssertEqual(r.margin!, 0.5986, accuracy: 1e-3)
    }

    func testSemConsumoUsaCpk() {
        let r = DrivingCalculator.calculate(DrivingInput(kmDriven: 200, revenue: 400, fallbackCostPerKm: 0.5))!
        XCTAssertFalse(r.detailed)
        XCTAssertNil(r.fuelCost)
        XCTAssertEqual(r.totalCost, 100)
        XCTAssertEqual(r.profit, 300)
        XCTAssertNil(r.deadKm)
        XCTAssertNil(r.revenuePerHour)
    }

    func testEntradasInvalidas() {
        XCTAssertNil(DrivingCalculator.calculate(DrivingInput(kmDriven: 0, revenue: 100)))
        XCTAssertNil(DrivingCalculator.calculate(DrivingInput(kmDriven: 50, revenue: -1)))
        // Km em corrida maior que o rodado (GPS perdeu trecho): km morto fica em zero, nunca negativo.
        let r = DrivingCalculator.calculate(DrivingInput(kmDriven: 50, paidKm: 80, revenue: 100))!
        XCTAssertEqual(r.deadKm, 0)
        // Prejuízo.
        let loss = DrivingCalculator.calculate(DrivingInput(kmDriven: 100, revenue: 30, fallbackCostPerKm: 0.5))!
        XCTAssertEqual(loss.profit, -20)
        XCTAssertEqual(loss.margin!, -2.0 / 3, accuracy: 1e-9)
    }

    func testConsumoReal() {
        XCTAssertEqual(DrivingCalculator.consumption(km: 412, liters: 36.5)!, 11.2877, accuracy: 1e-3)
        XCTAssertNil(DrivingCalculator.consumption(km: 0, liters: 30))
        XCTAssertNil(DrivingCalculator.consumption(km: 300, liters: 0))
    }

    func testTurnoPrefereOPainelAoGps() {
        XCTAssertEqual(Shift(start: Date(), odometerStart: 1000, odometerEnd: 1180, gpsKm: 171).kmDriven, 180)
        XCTAssertEqual(Shift(start: Date(), odometerStart: 1000, odometerEnd: 1180, gpsKm: 171).kmSource, "painel")
        XCTAssertEqual(Shift(start: Date(), gpsKm: 171).kmDriven, 171)
        XCTAssertEqual(Shift(start: Date(), gpsKm: 171).kmSource, "GPS")
        XCTAssertNil(Shift(start: Date(), gpsKm: 0.01).kmDriven)
        // Turnos antigos (sem os campos novos) continuam abrindo.
        let old = #"{"id":"a","start":0,"odometerStart":10,"odometerEnd":30}"#
        XCTAssertEqual(try JSONDecoder().decode(Shift.self, from: Data(old.utf8)).kmDriven, 20)
    }
}
