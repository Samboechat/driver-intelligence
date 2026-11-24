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

    private func finished(_ fx: [TrackerEffect]) -> TripTimeline? {
        for e in fx { if case let .finished(tl) = e { return tl } }
        return nil
    }

    private func cancelled(_ fx: [TrackerEffect]) -> Bool {
        fx.contains { if case .cancelled = $0 { return true }; return false }
    }

    /// Chamado aceito durante outra corrida (fila): vira a corrida seguinte, e não some.
    func testChamadoDaFilaViraProximaCorrida() {
        var t = TripTracker()
        var fx: [TrackerEffect] = []
        fx += t.handle(.observe(.offer, offer, 0))
        fx += t.handle(.observe(.onTrip, nil, 3))
        fx += t.handle(.observe(.onTrip, nil, 4))
        XCTAssertEqual(t.phase, .onTrip)
        // Novo chamado aparece por cima da viagem.
        fx += t.handle(.observe(.offer, other, 600))
        fx += t.handle(.observe(.offer, other, 603))
        fx += t.handle(.observe(.onTrip, nil, 606))
        XCTAssertEqual(t.queued?.fingerprint, other.fingerprint)
        fx += t.handle(.observe(.tripCompleted, nil, 1200))
        XCTAssertNotNil(finished(fx))
        XCTAssertEqual(t.phase, .none)
        // O Uber já vai direto para a busca do próximo passageiro.
        var next: [TrackerEffect] = []
        next += t.handle(.observe(.goingToPickup, nil, 1230))
        next += t.handle(.observe(.goingToPickup, nil, 1233))
        XCTAssertEqual(t.phase, .toPickup)
        XCTAssertTrue(next.contains(.outcome(other, .accepted, 1230)))
        XCTAssertNil(t.queued)
        next += t.handle(.observe(.onTrip, nil, 1500))
        next += t.handle(.observe(.onTrip, nil, 1503))
        next += t.handle(.observe(.tripCompleted, nil, 2700))
        XCTAssertEqual(finished(next)?.offer.fingerprint, other.fingerprint)
    }

    /// "Aceitei" na notificação durante uma corrida: guarda para a próxima em vez de ignorar.
    func testAceiteManualDuranteCorrida() {
        var t = TripTracker()
        _ = t.handle(.manualAccept(offer, 0))
        XCTAssertEqual(t.handle(.manualAccept(other, 300)), [.outcome(other, .accepted, 300)])
        XCTAssertEqual(t.timeline?.offer.fingerprint, offer.fingerprint)
        XCTAssertEqual(t.queued?.fingerprint, other.fingerprint)
    }

    /// Celular bloqueado / CarPlay: a viagem não aparece na tela, mas a corrida é registrada quando o Uber volta.
    func testViagemNaoVistaEhRegistrada() {
        var t = TripTracker()
        var fx: [TrackerEffect] = []
        fx += t.handle(.observe(.offer, offer, 0))
        fx += t.handle(.observe(.goingToPickup, nil, 3))
        fx += t.handle(.observe(.goingToPickup, nil, 4))
        // 40 minutos sem ver nada; volta em "procurando viagens".
        for i in 0..<3 { fx += t.handle(.observe(.onlineIdle, nil, 2400 + Double(i))) }
        guard let done = finished(fx) else { return XCTFail("corrida sumiu") }
        XCTAssertFalse(cancelled(fx))
        XCTAssertTrue(done.inferred)
        // Fim estimado pela previsão (~28 min com o ajuste de tempo real), não pela hora em que a tela voltou (40 min).
        XCTAssertEqual(done.totalMin!, done.predictedMin!, accuracy: 0.2)
        XCTAssertLessThan(done.totalMin!, 39)
        XCTAssertEqual(t.phase, .none)

        var t2 = TripTracker()
        var fx2: [TrackerEffect] = []
        fx2 += t2.handle(.observe(.offer, offer, 0))
        fx2 += t2.handle(.observe(.waitingPassenger, nil, 3))
        fx2 += t2.handle(.observe(.waitingPassenger, nil, 4))
        fx2 += t2.handle(.observe(.tripCompleted, nil, 1800))
        fx2 += t2.handle(.observe(.tripCompleted, nil, 1801))
        XCTAssertTrue(finished(fx2)?.inferred ?? false)
    }

    func testCanceladaPelaTela() {
        var t = TripTracker()
        var fx: [TrackerEffect] = []
        fx += t.handle(.observe(.offer, offer, 0))
        fx += t.handle(.observe(.goingToPickup, nil, 3))
        fx += t.handle(.observe(.goingToPickup, nil, 4))
        fx += t.handle(.observe(.tripCancelled, nil, 900))
        fx += t.handle(.observe(.tripCancelled, nil, 901))
        XCTAssertTrue(cancelled(fx))
        XCTAssertNil(finished(fx))
        XCTAssertEqual(ScreenClassifier.classify(.fromText("O usuário cancelou a viagem"), isOfferScreen: false), .tripCancelled)
    }

    /// A leitura reinicia no meio da corrida: ela continua de onde parou.
    func testRetomaDepoisDeReiniciar() {
        var t = TripTracker()
        _ = t.handle(.observe(.offer, offer, 0))
        _ = t.handle(.observe(.onTrip, nil, 3))
        _ = t.handle(.observe(.onTrip, nil, 4))
        guard let snap = t.snapshot() else { return XCTFail() }
        let data = try! JSONEncoder().encode(snap)
        let back = try! JSONDecoder().decode(TrackerSnapshot.self, from: data)

        var r = TripTracker()
        let fx = r.restore(back, now: 600) { OfferAnalyzer().analyze(offer: $0, context: AnalysisContext()) }
        XCTAssertEqual(r.phase, .onTrip)
        XCTAssertFalse(fx.isEmpty)
        let end = r.handle(.observe(.tripCompleted, nil, 1500))
        XCTAssertEqual(finished(end)?.actualTripMin ?? 0, 24.95, accuracy: 0.01)
        XCTAssertNil(r.snapshot())

        var old = TripTracker()
        XCTAssertTrue(old.restore(back, now: 6 * 3600) { OfferAnalyzer().analyze(offer: $0, context: AnalysisContext()) }.isEmpty)
        XCTAssertEqual(old.phase, .none)
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
