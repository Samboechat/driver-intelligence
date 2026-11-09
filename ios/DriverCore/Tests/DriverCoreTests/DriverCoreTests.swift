import XCTest
@testable import DriverCore

final class FinancialTests: XCTestCase {
    func testExemploDaEspecificacao() {
        let r = FinancialEngine().calculate(OfferData(fare: 18.5, pickupDistanceKm: 1.2, tripDistanceKm: 9.3, pickupTimeMin: 4, tripTimeMin: 20), costs: .empty)
        XCTAssertEqual(r.totalDistanceKm!, 10.5, accuracy: 1e-9)
        XCTAssertEqual(r.revenuePerKm!, 18.5 / 10.5, accuracy: 1e-9)
        XCTAssertEqual(r.revenuePerHour!, 46.25, accuracy: 1e-9)
    }

    func testAntiDuplicidadeDeCombustivel() {
        let c = CostProfile(consumptionKmPerUnit: 10, energyPricePerUnit: 6, operationalCostPerKmOverride: 0.9, operationalCostIncludesFuel: true)
        let r = FinancialEngine().calculate(OfferData(fare: 20, pickupDistanceKm: 1, tripDistanceKm: 9, pickupTimeMin: 4, tripTimeMin: 16), costs: c)
        XCTAssertEqual(r.fuelCost!, 6, accuracy: 1e-9)
        XCTAssertEqual(r.totalCost!, 9, accuracy: 1e-9)
        XCTAssertEqual(r.operatingProfit!, 11, accuracy: 1e-9)
    }

    func testDivisaoPorZeroEValoresInvalidos() {
        let r = FinancialEngine().calculate(OfferData(fare: 10, pickupDistanceKm: 0, tripDistanceKm: 3, pickupTimeMin: 0, tripTimeMin: 0), costs: .empty)
        XCTAssertNil(r.revenuePerHour)
        let bad = FinancialEngine().calculate(OfferData(fare: -5, pickupDistanceKm: .nan, tripDistanceKm: .infinity), costs: .empty)
        XCTAssertNil(bad.grossRevenue)
        XCTAssertFalse(bad.hasEssentials)
    }

    func testValorJusto() {
        let r = FinancialEngine().calculate(OfferData(fare: 18.5, pickupDistanceKm: 1.2, tripDistanceKm: 9.3, pickupTimeMin: 4, tripTimeMin: 20), costs: CostProfile(consumptionKmPerUnit: 11, energyPricePerUnit: 6.2))
        let t = FareAdvisor.target(r, goals: Goals())!
        XCTAssertEqual(t.minimumFare, 21, accuracy: 1e-9)
        XCTAssertEqual(t.bindingGoal, "valor por km")
    }
}

final class DecisionTests: XCTestCase {
    let fuel = CostProfile(consumptionKmPerUnit: 11, energyPricePerUnit: 6.2)

    func testVerdeComJustificativa() {
        let r = FinancialEngine().calculate(OfferData(fare: 18.5, pickupDistanceKm: 1.2, tripDistanceKm: 9.3, pickupTimeMin: 4, tripTimeMin: 20), costs: fuel)
        let d = DecisionEngine().decide(r, goals: Goals())
        XCTAssertEqual(d.classification, .green)
        XCTAssertEqual(d.headline, "Boa rentabilidade: R$ 1,76/km e R$ 46,25/h.")
    }

    func testPrejuizoSempreVermelho() {
        let c = CostProfile(operationalCostPerKmOverride: 3, operationalCostIncludesFuel: true)
        let r = FinancialEngine().calculate(OfferData(fare: 25, pickupDistanceKm: 0.5, tripDistanceKm: 9.5, pickupTimeMin: 2, tripTimeMin: 15), costs: c)
        XCTAssertEqual(DecisionEngine().decide(r, goals: Goals(minRevenuePerKm: 1)).classification, .red)
    }

    func testCinzaSemDadosEssenciais() {
        let r = FinancialEngine().calculate(OfferData(fare: 18.5, tripDistanceKm: 9.3), costs: fuel)
        XCTAssertEqual(DecisionEngine().decide(r, goals: Goals()).classification, .gray)
    }

    func testTempoRealistaMudaAClassificacao() {
        let a = OfferAnalyzer()
        let offer = OfferData(fare: 18.5, pickupDistanceKm: 1.2, tripDistanceKm: 9.3, pickupTimeMin: 4, tripTimeMin: 20)
        let semAjuste = a.analyze(offer: offer, context: AnalysisContext(costs: fuel, useRealisticTime: false))
        XCTAssertEqual(semAjuste.decision.classification, .green)
        let comAjuste = a.analyze(offer: offer, context: AnalysisContext(costs: fuel, pickupTimeFactor: 2.5, tripTimeFactor: 1.6))
        XCTAssertEqual(comAjuste.realistic!.totalTimeMin!, 42, accuracy: 1e-9)
        XCTAssertNotEqual(comAjuste.decision.classification, .green)
    }
}

final class ParserTests: XCTestCase {
    let parser = OfferTextParser()
    func parse(_ s: String) -> ParseResult { parser.parse(.fromText(s)) }

    func testNumeros() {
        XCTAssertEqual(NumberNormalizer.parse("18,50"), 18.5)
        XCTAssertEqual(NumberNormalizer.parse("1.234,56"), 1234.56)
        XCTAssertEqual(NumberNormalizer.parse("1,234.56"), 1234.56)
        XCTAssertEqual(NumberNormalizer.parse("1.234", thousandsHint: true), 1234)
        XCTAssertNil(NumberNormalizer.parse("abc"))
        XCTAssertEqual(NumberNormalizer.fixDigitConfusions("R$ 1O,5O").0, "R$ 10,50")
        XCTAssertEqual(NumberNormalizer.fixDigitConfusions("Inclui Dinâmico").1, 0)
    }

    func testCartaoPadrao() {
        let r = parse("UberX\nR$ 18,50\n★ 4,92\n4 min (1,2 km) de distância\nRua das Flores, 120 - Centro\nViagem: 20 min (9,3 km)\nAv. Paulista, 1000 - Bela Vista\nAceitar")
        XCTAssertEqual(r.offer.fare, 18.5)
        XCTAssertEqual(r.offer.pickupDistanceKm, 1.2)
        XCTAssertEqual(r.offer.pickupTimeMin, 4)
        XCTAssertEqual(r.offer.tripDistanceKm, 9.3)
        XCTAssertEqual(r.offer.tripTimeMin, 20)
        XCTAssertEqual(r.offer.category, "UberX")
        XCTAssertEqual(r.offer.passengerRating, 4.92)
        XCTAssertEqual(r.offer.origin, "Rua das Flores, 120 - Centro")
        XCTAssertEqual(r.offer.destination, "Av. Paulista, 1000 - Bela Vista")
        XCTAssertTrue(r.isOfferScreen)
        XCTAssertEqual(r.confidence, 1, accuracy: 1e-9)
    }

    func testQuebrasDeLinha() {
        let r = parse("R$ 18,50\n4 min (1,2 km)\nde distância\nViagem\n20 min\n(9,3 km)\nAceitar")
        XCTAssertEqual(r.offer.pickupDistanceKm, 1.2)
        XCTAssertEqual(r.offer.tripDistanceKm, 9.3)
        XCTAssertEqual(r.offer.tripTimeMin, 20)
        XCTAssertFalse(r.orderInferred)
    }

    func testValorDoDiaNaoConfunde() {
        let r = parse("R$ 152,30\nUberX\nR$ 18,50\n4 min (1,2 km) de distância\nViagem: 20 min (9,3 km)")
        XCTAssertEqual(r.offer.fare, 18.5)
    }

    func testGeometria() {
        let f = OcrFrame(lines: [
            OcrLine("R$ 152,30", box: Box(left: 400, top: 80, right: 680, bottom: 130)),
            OcrLine("R$ 18,50", box: Box(left: 80, top: 1500, right: 600, bottom: 1640)),
            OcrLine("4 min (1,2 km) de distância", box: Box(left: 80, top: 1700, right: 900, bottom: 1760)),
            OcrLine("Viagem: 20 min (9,3 km)", box: Box(left: 80, top: 1860, right: 900, bottom: 1920)),
        ], width: 1080, height: 2400)
        XCTAssertEqual(parser.parse(f).offer.fare, 18.5)
    }

    func testDinamicoEMilhasEMetros() {
        let r = parse("R$ 21,50\n+R$ 3,00\nInclui R$ 2,50 de dinâmico\n3 min (800 m) de distância\nViagem: 1 h 05 min (48,2 km)")
        XCTAssertEqual(r.offer.fare, 21.5)
        XCTAssertEqual(r.offer.surgeAmount, 3)
        XCTAssertEqual(r.offer.pickupDistanceKm!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(r.offer.tripTimeMin, 65)
        let en = parse("$18.50\n4 mins (1.2 mi) away\n20 min (9.3 mi) trip\nAccept")
        XCTAssertEqual(en.offer.tripDistanceKm!, 9.3 * 1.609344, accuracy: 1e-9)
    }

    func testDistanciaAntesDoTempoEOrdemDeduzida() {
        let r = parse("R$ 18,50\n1,2 km · 4 min de distância\nViagem: 9,3 km · 20 min")
        XCTAssertEqual(r.offer.pickupTimeMin, 4)
        XCTAssertEqual(r.offer.tripTimeMin, 20)
        let u = parse("R$ 18,50\n4 min (1,2 km)\n20 min (9,3 km)")
        XCTAssertTrue(u.orderInferred)
        XCTAssertEqual(u.offer.tripDistanceKm, 9.3)
    }

    func testTelaSemOferta() {
        XCTAssertFalse(parse("Você está online\nProcurando viagens\nR$ 152,30").isOfferScreen)
    }

    func testConfusoesDeOcr() {
        let r = parse("R$ 1O,5O\n4 min (l,2 km) de distância\nViagem: 20 min (9,3 km)")
        XCTAssertEqual(r.offer.fare, 10.5)
        XCTAssertEqual(r.offer.pickupDistanceKm, 1.2)
        XCTAssertEqual(r.ocrCorrections, 3)
    }
}

final class NotificationTests: XCTestCase {
    let ctx = AnalysisContext(costs: CostProfile(consumptionKmPerUnit: 11, energyPricePerUnit: 6.2), useRealisticTime: false)

    func testFormatoDaNotificacao() {
        let a = OfferAnalyzer().analyze(frame: .fromText("UberX\nR$ 19,20\n4 min (1,2 km) de distância\nViagem: 20 min (7,7 km)"), context: ctx)!
        let c = NotificationFormatter.format(a, goals: ctx.goals)
        XCTAssertEqual(c.title, "🟢R$ 19,20  🟢2,16/km  🟢48/h")
        XCTAssertTrue(c.body.hasPrefix("RENTÁVEL · Lucro: R$ 14,18 (74%)"), c.body)
        XCTAssertTrue(c.body.contains("UberX 24 min (8,9 km) · busca 1,2 km"), c.body)
    }

    func testTempoRealistaNaNotificacao() {
        var c2 = ctx
        c2.useRealisticTime = true
        let a = OfferAnalyzer().analyze(frame: .fromText("R$ 19,20\n4 min (1,2 km) de distância\nViagem: 20 min (7,7 km)"), context: c2)!
        XCTAssertTrue(NotificationFormatter.format(a, goals: c2.goals).body.contains("24 min → ~28 min real"))
    }

    func testPortaoNaoRepeteEConfirmaLeituraFraca() {
        var gate = NotificationGate()
        let a = OfferAnalyzer().analyze(offer: OfferData(fare: 18.5, pickupDistanceKm: 1.2, tripDistanceKm: 9.3, pickupTimeMin: 4, tripTimeMin: 20), context: ctx)
        XCTAssertEqual(gate.offer(a, at: 0), .notify(fingerprint: a.fingerprint!))
        XCTAssertEqual(gate.offer(a, at: 1), .none)
        XCTAssertEqual(gate.offer(a, at: 200), .notify(fingerprint: a.fingerprint!))

        var weak = a
        weak.fingerprint = "outra"
        weak.confidence = 0.7
        XCTAssertEqual(gate.offer(weak, at: 300), .none)
        XCTAssertEqual(gate.offer(weak, at: 301), .notify(fingerprint: "outra"))
        weak.confidence = 0.9
        XCTAssertEqual(gate.offer(weak, at: 302), .update(fingerprint: "outra"))
    }

    func testFormatacaoBrasileira() {
        XCTAssertEqual(Br.money(1234.5), "R$ 1.234,50")
        XCTAssertEqual(Br.money(-2.3), "−R$ 2,30")
        XCTAssertEqual(Br.minutes(65), "1 h 05 min")
        XCTAssertEqual(Br.km(8.94), "8,9 km")
    }
}
