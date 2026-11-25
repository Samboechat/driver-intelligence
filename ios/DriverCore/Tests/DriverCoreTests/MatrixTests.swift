import XCTest
@testable import DriverCore

final class SorocabaZoneTests: XCTestCase {
    func z(_ s: String?) -> ZoneMatch { SorocabaZone.classify(s) }

    func testZonaQuente() {
        XCTAssertEqual(z("Av. Antônio Carlos Comitre, Parque Campolim, Sorocaba").kind, .hot)
        XCTAssertEqual(z("Shopping Iguatemi Esplanada").kind, .hot)
        XCTAssertEqual(z("Rua X, Alto da Boa Vista").kind, .hot)
        XCTAssertEqual(z("Jd. Emília, Sorocaba - SP").kind, .hot)
        XCTAssertEqual(z("Jardim do Mangal").kind, .hot)
    }

    func testPeriferia() {
        XCTAssertEqual(z("Rua Y, Éden, Sorocaba").kind, .periphery)
        XCTAssertEqual(z("Cajuru do Sul, Sorocaba").kind, .periphery)
        XCTAssertEqual(z("Centro, Votorantim - SP").kind, .periphery)
        XCTAssertEqual(z("Pq. São Bento").kind, .periphery)
        XCTAssertEqual(z("Av. Itavuvu, Zona Norte").kind, .periphery)
    }

    func testIntermunicipal() {
        XCTAssertEqual(z("Centro, Itu - SP"), ZoneMatch(kind: .intercity, name: "Itu", minimumFare: 128))
        XCTAssertEqual(z("Itu").minimumFare, 128)
        XCTAssertEqual(z("Rua das Flores, 10 - Centro, Salto").minimumFare, 168)
        XCTAssertEqual(z("Aeroporto de Viracopos").minimumFare, 360)
        XCTAssertEqual(z("Cambuí, Campinas").minimumFare, 360)
        XCTAssertEqual(z("Centro, Jundiaí").minimumFare, 380)
        XCTAssertEqual(z("Av. Paulista, São Paulo").minimumFare, 422)
        XCTAssertEqual(z("Aeroporto de Guarulhos, Guarulhos").minimumFare, 530)
        XCTAssertEqual(z("Centro, Itu, São Paulo").name, "Itu")
    }

    func testRuaComNomeDeCidadeNaoEIntermunicipal() {
        XCTAssertEqual(z("Avenida São Paulo, Além Ponte, Sorocaba").kind, .neutral)
        XCTAssertEqual(z("Av. São Paulo, 1200").kind, .neutral)
        XCTAssertEqual(z("Jardim São Paulo").kind, .neutral)
        XCTAssertEqual(z("Rua Itu, Centro").kind, .neutral)
        XCTAssertEqual(z("Avenida Itavuvu").kind, .neutral)
        XCTAssertEqual(z("Salto de Pirapora").kind, .neutral)
        XCTAssertEqual(z("Rua Campinas, Vila Hortência, Sorocaba").kind, .neutral)
        XCTAssertEqual(z(nil).kind, .neutral)
        XCTAssertEqual(z("   ").kind, .neutral)
    }
}

final class AcceptanceMatrixTests: XCTestCase {
    let ctx = AnalysisContext(useRealisticTime: false, matrix: MatrixConfig())

    /// Oferta com R$/km e R$/h escolhidos: total 10 km (busca 2 + viagem 8).
    func offer(perKm: Double, perHour: Double = 60, category: String? = "Comfort", pickup: Double = 2, trip: Double = 8,
               destination: String? = nil, rating: Double? = nil) -> OfferData {
        let fare = perKm * (pickup + trip)
        let minutes = fare / perHour * 60
        return OfferData(fare: fare, pickupDistanceKm: pickup, tripDistanceKm: trip, pickupTimeMin: minutes * 0.2,
                         tripTimeMin: minutes * 0.8, category: category, destination: destination, passengerRating: rating)
    }

    func cls(_ o: OfferData) -> Classification { OfferAnalyzer().analyze(offer: o, context: ctx).decision.classification }

    /// Sem o piso por minuto, para testar só a hora.
    func clsHour(_ o: OfferData) -> Classification {
        OfferAnalyzer().analyze(offer: o, context: AnalysisContext(useRealisticTime: false, matrix: MatrixConfig(minPerMinute: 0)))
            .decision.classification
    }

    func analyze(_ o: OfferData) -> OfferAnalysis { OfferAnalyzer().analyze(offer: o, context: ctx) }

    func testPisoPorMinuto() {
        // R$ 1,00/min: 20 reais em 20 minutos passa; em 21 minutos não.
        let ok = OfferData(fare: 25, pickupDistanceKm: 2, tripDistanceKm: 8, pickupTimeMin: 5, tripTimeMin: 20, category: "Comfort")
        XCTAssertEqual(analyze(ok).decision.classification, .green)
        XCTAssertEqual(analyze(ok).matrix?.perMinute ?? 0, 1.0, accuracy: 1e-9)
        var slow = ok
        slow.tripTimeMin = 21
        let a = analyze(slow)
        XCTAssertEqual(a.decision.classification, .red)
        XCTAssertTrue(a.matrix!.shortRefusals.contains { $0.hasPrefix("Minuto baixo") })
    }

    func testDinamicoReal() {
        // Sem o dinâmico: R$ 25 em 10 km e 20 min → passa em tudo. Os R$ 5 são lucro a mais.
        let o = OfferData(fare: 30, pickupDistanceKm: 2, tripDistanceKm: 8, pickupTimeMin: 4, tripTimeMin: 16,
                          category: "Comfort", surgeAmount: 5)
        let a = analyze(o)
        XCTAssertEqual(a.decision.classification, .green)
        let s = try! XCTUnwrap(a.matrix?.surge)
        XCTAssertTrue(s.real)
        XCTAssertEqual(s.baseFare, 25, accuracy: 1e-9)
        XCTAssertEqual(s.extraGain, 5, accuracy: 1e-9)
        XCTAssertNil(a.matrix?.alert)
    }

    func testDinamicoDeFachada() {
        // Total R$ 25 passa (2,50/km · 1,00/min), mas sem os R$ 6 de dinâmico seriam R$ 19 (1,90/km · 0,76/min).
        let o = OfferData(fare: 25, pickupDistanceKm: 2, tripDistanceKm: 8, pickupTimeMin: 5, tripTimeMin: 20,
                          category: "Comfort", destination: "Parque Campolim", surgeAmount: 6)
        let a = analyze(o)
        // Nem a zona quente aprova: o motorista precisa decidir.
        XCTAssertEqual(a.decision.classification, .yellow)
        let s = try! XCTUnwrap(a.matrix?.surge)
        XCTAssertFalse(s.real)
        XCTAssertEqual(s.baseFare, 19, accuracy: 1e-9)
        // Mínimo sem dinâmico = max(2,30 × 10 km, 1,00 × 25 min) = 25; justo = 25 + 6 = 31.
        XCTAssertEqual(s.minimumBase, 25, accuracy: 1e-9)
        XCTAssertEqual(s.fairFare, 31, accuracy: 1e-9)
        XCTAssertEqual(s.extraGain, 0, accuracy: 1e-9)
        XCTAssertEqual(a.matrix?.alert, "Dinâmico de fachada")
        XCTAssertTrue(a.matrix!.shortCautions.contains { $0.hasPrefix("Dinâmico de fachada") })
        let n = NotificationFormatter.format(a, goals: Goals())
        XCTAssertTrue(n.body.contains("⚡ Dinâmico de fachada"), n.body)
        XCTAssertTrue(n.body.contains("justo"))
    }

    func testDinamicoLidoErradoEhIgnorado() {
        var o = OfferData(fare: 30, pickupDistanceKm: 2, tripDistanceKm: 8, pickupTimeMin: 4, tripTimeMin: 16, category: "Comfort")
        o.surgeAmount = 30
        XCTAssertNil(analyze(o).matrix?.surge)
    }

    func testAjustesAntigosCarregam() throws {
        let old = #"{"costPerKm":0.6,"hourFloor":40,"hourIdeal":50,"shortTripKm":5,"longTripKm":20}"#
        let m = try JSONDecoder().decode(MatrixConfig.self, from: Data(old.utf8))
        XCTAssertEqual(m.costPerKm, 0.6)
        XCTAssertEqual(m.minPerMinute, 1.0)
        XCTAssertTrue(m.checkSurge)
        XCTAssertEqual(m.comfort, MatrixConfig().comfort)
    }

    func testFaixasComfort() {
        XCTAssertEqual(cls(offer(perKm: 2.30)), .green)
        XCTAssertEqual(cls(offer(perKm: 2.29)), .yellow)
        XCTAssertEqual(cls(offer(perKm: 2.00)), .yellow)
        XCTAssertEqual(cls(offer(perKm: 1.99)), .red)
    }

    func testFaixasUberX() {
        XCTAssertEqual(cls(offer(perKm: 2.10, category: "UberX")), .green)
        XCTAssertEqual(cls(offer(perKm: 2.09, category: "UberX")), .yellow)
        XCTAssertEqual(cls(offer(perKm: 1.85, category: "99Pop")), .yellow)
        XCTAssertEqual(cls(offer(perKm: 1.84, category: "UberX")), .red)
        // Sem categoria lida: régua do UberX/99.
        XCTAssertEqual(cls(offer(perKm: 2.10, category: nil)), .green)
    }

    func testPisoPorHora() {
        XCTAssertEqual(clsHour(offer(perKm: 2.50, perHour: 41.9)), .red)
        XCTAssertEqual(clsHour(offer(perKm: 2.50, perHour: 42)), .yellow)
        XCTAssertEqual(clsHour(offer(perKm: 2.50, perHour: 53.9)), .yellow)
        XCTAssertEqual(clsHour(offer(perKm: 2.50, perHour: 54)), .green)
    }

    func testBuscaMaxima() {
        let m = MatrixConfig()
        XCTAssertEqual(m.pickupLimitKm(.comfort, tripKm: 3), 5)
        XCTAssertEqual(m.pickupLimitKm(.comfort, tripKm: 20), 8)
        XCTAssertEqual(m.pickupLimitKm(.comfort, tripKm: 12.5), 6.5, accuracy: 1e-9)
        XCTAssertEqual(m.pickupLimitKm(.standard, tripKm: 4), 3)
        XCTAssertEqual(m.pickupLimitKm(.standard, tripKm: 40), 6)
        // Comfort curta: 5 km passa, 5,1 km recusa.
        XCTAssertEqual(cls(offer(perKm: 3, pickup: 5, trip: 5)), .green)
        XCTAssertEqual(cls(offer(perKm: 3, pickup: 5.1, trip: 5)), .red)
        // UberX curta: limite de 3 km.
        XCTAssertEqual(cls(offer(perKm: 3, category: "UberX", pickup: 3.1, trip: 5)), .red)
        // Longa: Comfort até 8 km, UberX até 6 km.
        XCTAssertEqual(cls(offer(perKm: 3, pickup: 8, trip: 25)), .green)
        XCTAssertEqual(cls(offer(perKm: 3, category: "UberX", pickup: 6.1, trip: 25)), .red)
    }

    func testNotaMinima() {
        XCTAssertEqual(cls(offer(perKm: 3, rating: 4.80)), .green)
        XCTAssertEqual(cls(offer(perKm: 3, rating: 4.79)), .red)
        XCTAssertEqual(cls(offer(perKm: 3, category: "UberX", rating: 4.84)), .red)
        XCTAssertEqual(cls(offer(perKm: 3, category: "UberX", rating: 4.85)), .green)
    }

    func testZonaQuenteAprovaAmarelo() {
        XCTAssertEqual(cls(offer(perKm: 2.10, destination: "Parque Campolim, Sorocaba")), .green)
        XCTAssertEqual(clsHour(offer(perKm: 2.50, perHour: 45, destination: "Mangal")), .green)
        // Mas não salva o que já era recusa.
        XCTAssertEqual(cls(offer(perKm: 1.95, destination: "Campolim")), .red)
        XCTAssertEqual(cls(offer(perKm: 2.50, perHour: 40, destination: "Campolim")), .red)
    }

    func testPeriferiaExige220EAlerta() {
        let ok = OfferAnalyzer().analyze(offer: offer(perKm: 2.20, category: "UberX", destination: "Éden, Sorocaba"), context: ctx)
        XCTAssertEqual(ok.decision.classification, .green)
        XCTAssertEqual(ok.matrix?.alert, "Volta Vazia - Ligar Direcionamento")
        // UberX a 2,15 seria verde em outro bairro; na periferia recusa.
        XCTAssertEqual(cls(offer(perKm: 2.15, category: "UberX")), .green)
        XCTAssertEqual(cls(offer(perKm: 2.15, category: "UberX", destination: "Cajuru")), .red)
        // Comfort a 2,25 na periferia: passa do mínimo da zona, mas segue amarela pela régua da categoria.
        XCTAssertEqual(cls(offer(perKm: 2.25, destination: "Votorantim")), .yellow)
    }

    func testIntermunicipal() {
        func inter(_ fare: Double, _ dest: String, trip: Double = 90) -> Classification {
            cls(OfferData(fare: fare, pickupDistanceKm: 2, tripDistanceKm: trip, pickupTimeMin: 5, tripTimeMin: 70, category: "Comfort", destination: dest))
        }
        XCTAssertEqual(inter(127.99, "Centro, Itu", trip: 35), .red)
        XCTAssertEqual(inter(128, "Centro, Itu", trip: 35), .green)
        XCTAssertEqual(inter(167, "Salto - SP", trip: 40), .red)
        XCTAssertEqual(inter(168, "Salto - SP", trip: 40), .green)
        XCTAssertEqual(inter(359, "Aeroporto de Viracopos"), .red)
        XCTAssertEqual(inter(360, "Campinas"), .green)
        XCTAssertEqual(inter(379, "Jundiaí"), .red)
        XCTAssertEqual(inter(380, "Jundiaí"), .green)
        XCTAssertEqual(inter(421, "São Paulo"), .red)
        XCTAssertEqual(inter(422, "São Paulo"), .green)
        XCTAssertEqual(inter(529, "Guarulhos", trip: 110), .red)
        XCTAssertEqual(inter(530, "Guarulhos", trip: 110), .green)
        // Mesmo pagando bem por km, abaixo do mínimo da cidade recusa.
        XCTAssertEqual(inter(120, "Itu", trip: 30), .red)
    }

    func testLucroUsaCpkDe50Centavos() {
        let a = OfferAnalyzer().analyze(offer: offer(perKm: 2.30), context: ctx)
        XCTAssertEqual(a.financial.totalCost!, 5, accuracy: 1e-9)
        XCTAssertEqual(a.financial.operatingProfit!, 18, accuracy: 1e-9)
    }

    func testNotificacaoMostraVereditoEAlerta() {
        let a = OfferAnalyzer().analyze(offer: offer(perKm: 2.20, category: "UberX", destination: "Éden"), context: ctx)
        let n = NotificationFormatter.format(a, goals: Goals())
        XCTAssertEqual(n.title, "🟢 ACEITAR · Lucro R$ 17,00")
        XCTAssertEqual(n.subtitle, "R$ 22,00 · 2,20/km · 1,00/min · R$ 60/h")
        XCTAssertTrue(n.body.contains("⚠️ Volta Vazia - Ligar Direcionamento"), n.body)

        // Recusa: só o motivo principal, para a notificação ficar curta.
        let r = OfferAnalyzer().analyze(offer: offer(perKm: 1.5, pickup: 6, trip: 4, rating: 4.7), context: ctx)
        let rn = NotificationFormatter.format(r, goals: Goals())
        XCTAssertEqual(rn.title, "🔴 RECUSAR · Lucro R$ 10,00")
        XCTAssertTrue(rn.body.hasPrefix("✖︎ Km baixo: 1,50 · mínimo 2,00\n"), rn.body)
        XCTAssertFalse(rn.body.contains("Busca longa"))

        let y = OfferAnalyzer().analyze(offer: offer(perKm: 2.10), context: ctx)
        let yn = NotificationFormatter.format(y, goals: Goals())
        XCTAssertEqual(yn.title, "🟡 AVALIAR · Lucro R$ 16,00")
        XCTAssertTrue(yn.body.hasPrefix("• Km na faixa amarela: 2,10 · ideal 2,30"), yn.body)
    }

    func testNotificacaoComMetaEPrecoBase() {
        // 10 km, 25 min, R$ 25. Custo 0,50/km → preço base R$ 5; meta precisa R$ 60/h → R$ 25 nesta corrida.
        let o = OfferData(fare: 25, pickupDistanceKm: 2, tripDistanceKm: 8, pickupTimeMin: 5, tripTimeMin: 20, category: "Comfort")
        let a = OfferAnalyzer().analyze(offer: o, context: ctx)
        let pace = PaceStatus(goal: 470, earned: 170, shiftEnd: Date().addingTimeInterval(5 * 3600), hoursLeft: 5)
        let e = OfferEconomics.of(a, costPerKm: 0.5, neededPerHour: pace.neededPerHour, hourFloor: 42)
        XCTAssertEqual(e.breakEven!, 5, accuracy: 1e-9)
        XCTAssertEqual(e.profit!, 20, accuracy: 1e-9)
        XCTAssertEqual(e.goalFare!, 25, accuracy: 1e-9)
        XCTAssertEqual(e.meetsGoal, true)
        let n = NotificationFormatter.format(a, goals: Goals(), econ: e, pace: pace)
        XCTAssertEqual(n.title, "🟢 ACEITAR · Lucro R$ 20,00")
        XCTAssertTrue(n.body.contains("Sem prejuízo R$ 5,00 · Meta R$ 25,00 ✓"), n.body)
        XCTAssertTrue(n.body.contains("Hoje R$ 170,00 de R$ 470,00 · precisa R$ 60/h até"), n.body)
        XCTAssertLessThanOrEqual(n.body.split(separator: "\n").count, 3)

        // Meta já batida: o valor da meta usa o piso por hora.
        let done = PaceStatus(goal: 470, earned: 500, shiftEnd: Date(), hoursLeft: 1)
        XCTAssertEqual(OfferEconomics.of(a, costPerKm: 0.5, neededPerHour: done.neededPerHour, hourFloor: 42).goalFare!, 17.5, accuracy: 1e-9)
        XCTAssertTrue(NotificationFormatter.format(a, goals: Goals(), pace: done).body.contains("🎯 Meta do dia batida"))
    }

    func testSemMatrizContinuaComoAntes() {
        let a = OfferAnalyzer().analyze(offer: offer(perKm: 2.30), context: AnalysisContext())
        XCTAssertNil(a.matrix)
    }

    func testDadosIncompletosFicamCinza() {
        let a = OfferAnalyzer().analyze(offer: OfferData(fare: 20, tripDistanceKm: 8), context: ctx)
        XCTAssertEqual(a.decision.classification, .gray)
        XCTAssertNil(a.matrix)
    }
}

final class WeekMathTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testSemanaComecaNaSegunda() {
        // 9/11/2026 é segunda; 15/11/2026 é domingo.
        let w = WeekMath.week(containing: date(2026, 11, 15, 23), calendar: cal)
        XCTAssertEqual(w.start, date(2026, 11, 9))
        XCTAssertEqual(w.end, date(2026, 11, 16))
        XCTAssertEqual(WeekMath.week(containing: date(2026, 11, 9, 0), calendar: cal).start, date(2026, 11, 9))
    }

    func testHorasOnlineCortamNaViradaDaSemana() {
        let w = WeekMath.week(containing: date(2026, 11, 10), calendar: cal)
        let shifts = [
            Shift(start: date(2026, 11, 8, 20), end: date(2026, 11, 9, 4)),   // 4 h dentro da semana
            Shift(start: date(2026, 11, 10, 18), end: date(2026, 11, 11, 2)), // 8 h
            Shift(start: date(2026, 11, 12, 18)),                             // aberto: 3 h até "agora"
        ]
        XCTAssertEqual(WeekMath.hoursOnline(shifts, in: w, now: date(2026, 11, 12, 21)), 15, accuracy: 1e-9)
    }

    func testHodometro() {
        XCTAssertEqual(Shift(start: Date(), odometerStart: 12000, odometerEnd: 12185.5).kmDriven!, 185.5, accuracy: 1e-9)
        XCTAssertNil(Shift(start: Date(), odometerStart: 12000, odometerEnd: 11000).kmDriven)
        XCTAssertNil(Shift(start: Date(), odometerStart: 12000).kmDriven)
        XCTAssertEqual(WeekMath.progress(1410, of: 2820), 0.5)
        XCTAssertEqual(WeekMath.progress(5000, of: 2820), 1)
        XCTAssertEqual(WeekMath.progress(10, of: 0), 0)
    }
}
