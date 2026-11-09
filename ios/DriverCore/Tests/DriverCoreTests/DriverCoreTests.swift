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

    // MARK: Falsos chamados

    func testNavegacaoEGanhosNaoSaoChamado() {
        // Corrida em andamento: valor na tela + distância da próxima manobra.
        XCTAssertFalse(parse("R$ 18,50\nEm 300 m vire à direita\nAv. Itavuvu\n12 min\n5,4 km").isOfferScreen)
        // Um valor e uma distância soltos não bastam.
        XCTAssertFalse(parse("Ganhos de hoje\nR$ 152,30\n8,9 km").isOfferScreen)
        // Só um par (indo buscar o passageiro).
        XCTAssertFalse(parse("Buscar Maria\n4 min (1,2 km)\nR$ 18,50").isOfferScreen)
        // Valor + dois pares sem nenhuma âncora do cartão.
        XCTAssertFalse(parse("R$ 18,50\n4 min (1,2 km)\n20 min (9,3 km)").isOfferScreen)
    }

    func testNossaNotificacaoNaoViraChamado() {
        let a = OfferAnalyzer().analyze(offer: OfferData(fare: 19.2, pickupDistanceKm: 1.2, tripDistanceKm: 7.7, pickupTimeMin: 4, tripTimeMin: 20,
                                                         category: "Comfort", destination: "Éden, Sorocaba", passengerRating: 4.9),
                                        context: AnalysisContext(matrix: MatrixConfig()))
        let c = NotificationFormatter.format(a, goals: Goals())
        let banner = [c.title, c.subtitle, c.body].joined(separator: "\n")
        XCTAssertFalse(parse(banner).isOfferScreen, banner)
        XCTAssertFalse(parse(banner).nearMiss, banner)
        // Formato antigo (ainda pode estar na Central de Notificações).
        XCTAssertFalse(parse("🟢R$ 19,20  🟢2,16/km  🟢48/h\nACEITAR · Lucro: R$ 14,75 (77%)\nUberX 24 min (8,9 km) · busca 1,2 km").isOfferScreen)
    }

    func testNotificacaoPorCimaDoCartaoNaoAtrapalha() {
        // Faixa da notificação no topo + cartão do Uber embaixo: lê só o cartão.
        func line(_ t: String, _ top: Int, _ h: Int = 50) -> OcrLine { OcrLine(t, box: Box(left: 60, top: top, right: 1000, bottom: top + h)) }
        let f = OcrFrame(lines: [
            line("O RECUSAR • R$ 9,80", 150),
            line("R$ 1,10/km • R$ 31/h • UberX", 205),
            line("X Km baixo: 1,10 • mínimo 1,85", 260),
            line("Lucro R$ 5,35 • Total 8,9 km em 24 min", 315),
            line("Comfort", 1100),
            line("R$ 23,40", 1180, 110),
            line("★ 4,95", 1320),
            line("5 min (1.8 km) de distância", 1420),
            line("Rua Aparecida, 300 - Jardim Santa Rosália", 1480),
            line("Viagem de 14 min (7.2 km)", 1600),
            line("Av. Gisele Constantino, 1850 - Parque", 1660),
            line("Campolim, Sorocaba - SP", 1715),
            line("Aceitar", 2300, 70),
        ], width: 1206, height: 2622)
        let r = parser.parse(f)
        XCTAssertTrue(r.isOfferScreen)
        XCTAssertEqual(r.offer.fare, 23.4)
        XCTAssertEqual(r.offer.pickupDistanceKm, 1.8)
        XCTAssertEqual(r.offer.tripDistanceKm, 7.2)
        XCTAssertEqual(r.offer.category, "Comfort")
        XCTAssertEqual(r.offer.passengerRating, 4.95)
        XCTAssertEqual(r.offer.destination, "Av. Gisele Constantino, 1850 - Parque\nCampolim, Sorocaba - SP")
        XCTAssertEqual(SorocabaZone.classify(r.offer.destination).kind, .hot)
        XCTAssertEqual(r.confidence, 1, accuracy: 1e-9)
    }

    func testProprioAppNaoEChamado() {
        let r = parse("Driver Intelligence\nÚltimo chamado\nUberX\nR$ 19,20\n4 min (1,2 km) de distância\nViagem: 20 min (7,7 km)\nInício\nPainel\nHistórico\nAjustes")
        XCTAssertFalse(r.isOfferScreen)
        XCTAssertTrue(r.ownApp)
    }

    func testRadarComVariasViagensNaoEChamado() {
        let r = parse("Radar de viagens\nUberX\nR$ 12,00\n4 min (1,2 km) de distância\nViagem de 10 min (4 km)\nComfort\nR$ 22,00\n6 min (2 km) de distância\nViagem de 18 min (9 km)\nUberX\nR$ 9,50\n3 min (1 km) de distância\nViagem de 8 min (3 km)")
        XCTAssertFalse(r.isOfferScreen)
    }

    // MARK: Leituras difíceis

    func testCartaoLidoPelaMetadeEQuaseChamado() {
        let r = parse("UberX\nR$ 18,50\n4 min (1,2 km) de distância\nRua das Flores\nAceitar")
        XCTAssertFalse(r.isOfferScreen)
        XCTAssertTrue(r.nearMiss)
    }

    func testCifraoSeparadoDoValor() {
        func line(_ t: String, _ left: Int, _ top: Int, _ h: Int = 50) -> OcrLine { OcrLine(t, box: Box(left: left, top: top, right: left + 400, bottom: top + h)) }
        let f = OcrFrame(lines: [
            line("99Pop", 60, 1000),
            line("12,40", 700, 990, 90),
            line("3 min (1,1 km)", 60, 1200),
            line("Rua A, Centro", 60, 1260),
            line("18 min (9,2 km)", 60, 1400),
            line("Rua B, Éden, Sorocaba", 60, 1460),
            line("Aceitar", 400, 2200, 70),
        ], width: 1206, height: 2622)
        let r = parser.parse(f)
        XCTAssertTrue(r.isOfferScreen)
        XCTAssertEqual(r.offer.fare, 12.4)
        XCTAssertEqual(r.offer.category, "99Pop")
        XCTAssertEqual(r.offer.destination, "Rua B, Éden, Sorocaba")
        XCTAssertLessThan(r.confidence, 0.85)
    }

    func testEnderecoEmDuasLinhasComCidade() {
        let r = parse("Comfort\nR$ 140,00\n5 min (2 km) de distância\nRua X, Campolim\nViagem de 40 min (38 km)\nRua das Flores, 120 - Centro,\nItu - SP, 13300-000\nAceitar")
        XCTAssertEqual(r.offer.origin, "Rua X, Campolim")
        XCTAssertEqual(SorocabaZone.classify(r.offer.destination).name, "Itu")
        XCTAssertEqual(SorocabaZone.classify("Praça da Sé - Sé, São\nPaulo - SP").name, "SP Capital")
        XCTAssertEqual(SorocabaZone.classify("Av. São Paulo, 500\nAlém Ponte").kind, .neutral)
    }

    func testFormatoComViagemNoFim() {
        let r = parse("UberX\nR$ 14,52\n★ 4,95\n7 minutos (2.4 km) de distância\nAv. Itavuvu, 1000\n15 minutos (8.1 km) de viagem\nRua Y, Centro\nAceitar")
        XCTAssertTrue(r.isOfferScreen)
        XCTAssertEqual(r.offer.pickupTimeMin, 7)
        XCTAssertEqual(r.offer.tripDistanceKm, 8.1)
        XCTAssertFalse(r.orderInferred)
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
        XCTAssertEqual(c.title, "🟢 RENTÁVEL · R$ 19,20")
        XCTAssertEqual(c.subtitle, "R$ 2,16/km · R$ 48/h · UberX")
        XCTAssertEqual(c.body, "Lucro R$ 14,18 · Total 8,9 km em 24 min")
    }

    func testTempoRealistaNaNotificacao() {
        var c2 = ctx
        c2.useRealisticTime = true
        let a = OfferAnalyzer().analyze(frame: .fromText("R$ 19,20\n4 min (1,2 km) de distância\nViagem: 20 min (7,7 km)"), context: c2)!
        XCTAssertTrue(NotificationFormatter.format(a, goals: c2.goals).body.contains("Total 8,9 km em ~28 min"))
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
