import XCTest
@testable import DriverCore

final class TripTrackerTests: XCTestCase {
    let offer = OfferAnalyzer().analyze(offer: OfferData(fare: 18.5, pickupDistanceKm: 1.2, tripDistanceKm: 9.3, pickupTimeMin: 4, tripTimeMin: 20), context: AnalysisContext())
    let other = OfferAnalyzer().analyze(offer: OfferData(fare: 25, pickupDistanceKm: 2, tripDistanceKm: 12, pickupTimeMin: 6, tripTimeMin: 25), context: AnalysisContext())

    func testFluxoCompleto() {
        var t = TripTracker()
        var fx: [TrackerEffect] = []
        fx += t.handle(.observe(.offer, offer, 0))
        fx += t.handle(.observe(.goingToPickup, nil, 3))
        fx += t.handle(.observe(.goingToPickup, nil, 4))
        XCTAssertTrue(fx.contains(.outcome(offer, .accepted, 3)))
        XCTAssertEqual(t.phase, .toPickup)
        fx += t.handle(.observe(.waitingPassenger, nil, 3 + 7 * 60))
        fx += t.handle(.observe(.waitingPassenger, nil, 4 + 7 * 60))
        XCTAssertEqual(t.phase, .waiting)
        let start: TimeInterval = 3 + 9 * 60
        fx += t.handle(.observe(.onTrip, nil, start))
        fx += t.handle(.observe(.onTrip, nil, start + 1))
        fx += t.handle(.observe(.tripCompleted, nil, start + 26 * 60))
        guard case let .finished(done)? = fx.first(where: { if case .finished = $0 { return true }; return false }) else { return XCTFail("sem fim") }
        XCTAssertEqual(done.actualPickupMin!, 7, accuracy: 0.01)
        XCTAssertEqual(done.actualTripMin!, 26, accuracy: 0.01)
        XCTAssertEqual(t.phase, .none)
    }

    func testRecusaEIgnorada() {
        var t = TripTracker()
        _ = t.handle(.observe(.offer, offer, 0))
        _ = t.handle(.observe(.onlineIdle, nil, 3))
        XCTAssertEqual(t.handle(.observe(.onlineIdle, nil, 4)).first, .outcome(offer, .rejected, 4))

        var t2 = TripTracker()
        _ = t2.handle(.observe(.offer, offer, 0))
        _ = t2.handle(.observe(.offer, offer, 14))
        _ = t2.handle(.observe(.onlineIdle, nil, 15))
        XCTAssertEqual(t2.handle(.observe(.onlineIdle, nil, 16)).first, .outcome(offer, .expired, 16))
    }

    func testOutraOfertaEOfertaDuranteViagem() {
        var t = TripTracker()
        _ = t.handle(.observe(.offer, offer, 0))
        XCTAssertEqual(t.handle(.observe(.offer, other, 5)), [.outcome(offer, .rejected, 5)])

        var t2 = TripTracker()
        _ = t2.handle(.manualAccept(offer, 0))
        _ = t2.handle(.observe(.onTrip, nil, 1))
        _ = t2.handle(.observe(.onTrip, nil, 2))
        _ = t2.handle(.observe(.offer, other, 3))
        XCTAssertEqual(t2.phase, .onTrip)
    }

    func testCancelamentoEFimManual() {
        var t = TripTracker()
        _ = t.handle(.manualAccept(offer, 0))
        var fx: [TrackerEffect] = []
        for i in 0..<3 { fx += t.handle(.observe(.onlineIdle, nil, 60 + Double(i))) }
        XCTAssertTrue(fx.contains { if case .cancelled = $0 { return true }; return false })

        var t2 = TripTracker()
        _ = t2.handle(.manualAccept(offer, 0))
        let f = t2.handle(.manualFinish(20 * 60))
        guard case let .finished(done)? = f.first else { return XCTFail() }
        XCTAssertEqual(done.totalMin!, 20, accuracy: 0.01)
        XCTAssertTrue(done.manual)
    }

    func testClassificadorDeTelas() {
        func k(_ s: String) -> ScreenKind { ScreenClassifier.classify(.fromText(s), isOfferScreen: false) }
        XCTAssertEqual(k("Você está online\nProcurando viagens"), .onlineIdle)
        XCTAssertEqual(k("A caminho do passageiro\nCheguei"), .goingToPickup)
        XCTAssertEqual(k("Aguardando o passageiro\nIniciar viagem"), .waitingPassenger)
        XCTAssertEqual(k("Levando Maria\nFinalizar viagem"), .onTrip)
        XCTAssertEqual(k("Viagem concluída\nVocê ganhou R$ 18,50"), .tripCompleted)
        XCTAssertEqual(k("Configurações"), .unknown)
    }

    func testCalibracao() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        func at(_ day: Int, _ hour: Int) -> TimeInterval {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!.timeIntervalSince1970
        }
        XCTAssertFalse(TimeCalibration(samples: [], defaultPickup: 1.35, defaultTrip: 1.15).factors(hour: 8, calendar: cal).learned)
        let rush = (1...5).map { TimingSample(at: at($0, 18), offeredPickupMin: 4, actualPickupMin: 8, offeredTripMin: 20, actualTripMin: 28) }
        let calm = (6...15).map { TimingSample(at: at($0, 10), offeredPickupMin: 4, actualPickupMin: 4.8, offeredTripMin: 20, actualTripMin: 21) }
        let c = TimeCalibration(samples: rush + calm, defaultPickup: 1.35, defaultTrip: 1.15)
        XCTAssertEqual(c.factors(hour: 18, calendar: cal).pickup, 2, accuracy: 1e-9)
        XCTAssertEqual(c.factors(hour: 10, calendar: cal).pickup, 1.2, accuracy: 1e-9)
    }
}
