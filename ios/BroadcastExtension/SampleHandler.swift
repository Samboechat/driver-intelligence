import ReplayKit
import Vision
import CoreMedia
import CoreImage
import UserNotifications
import DriverCore

/**
 * Extensão "Transmitir tela": recebe os quadros da tela enquanto o motorista usa o app de corrida,
 * lê o texto no próprio iPhone (Vision), analisa o chamado e avisa por notificação.
 *
 *  - só vira chamado o cartão completo (valor + busca + viagem + botão/rótulos); a nossa própria
 *    notificação e o nosso próprio app, que também aparecem na gravação, são ignorados;
 *  - classifica pela matriz de aceite (categoria, busca, nota, piso por hora e zonas de Sorocaba);
 *  - conversa com o app pelo canal `Bridge`, que funciona mesmo sem App Group (ESign);
 *  - entende se o chamado foi aceito, recusado ou ignorado e mede o tempo real da corrida;
 *  - só se o motorista ligar nos Ajustes: guarda um print (JPEG reduzido) de cada chamado.
 *    Com os prints desligados (padrão), cada quadro é lido na memória e descartado.
 *
 * Limite do iOS: extensões de transmissão têm ~50 MB de memória. Por isso há um quadro por vez,
 * no máximo ~1,5 leitura por segundo, e o contexto de imagem só é criado se os prints estiverem ligados.
 */
final class SampleHandler: RPBroadcastSampleHandler {

    private let analyzer = OfferAnalyzer()
    private let queue = DispatchQueue(label: "di.ocr", qos: .userInitiated)
    private lazy var ciContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    private var gate = NotificationGate()
    private var tracker = TripTracker()
    private var settings = SharedStore.settings
    private var context = SharedStore.settings.context
    private var factors = SharedStore.currentFactors(SharedStore.settings)
    private var busy = false
    private var lastProcessed: CFAbsoluteTime = 0
    private var lastSettingsLoad: CFAbsoluteTime = 0
    private var lastStatusSave: CFAbsoluteTime = 0
    private var lastCommandId = SharedStore.command?.id
    private var status = BroadcastStatus()
    /// Últimos chamados vistos (para o botão "Aceitei" da notificação).
    private var recentOffers: [String: OfferAnalysis] = [:]
    private var lastOffer: OfferAnalysis?
    /// Print atual de cada chamado (nome do arquivo) e a confiança com que foi tirado.
    private var shots: [String: (name: String, confidence: Double)] = [:]

    private let minInterval: CFAbsoluteTime = 0.65

    // Canal com o app
    private var timer: DispatchSourceTimer?
    private var inboxStamp: [Bridge.Key: TimeInterval] = [:]
    /// Há chamados/corridas novos para publicar.
    private var dirty = true
    private var lastPulse: CFAbsoluteTime = 0
    private var startedAt = Date()

    // Dynamic Island
    private var live: RideActivityAttributes.ContentState?
    private var liveShowingOffer = false
    private var lastOfferSeen: CFAbsoluteTime = 0
    private let liveOfferHold: CFAbsoluteTime = 20

    // Diagnóstico: cartões que ficaram pela metade
    private var missStreak = 0
    private var lastMissText = ""

    // MARK: Ciclo da transmissão

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
        queue.sync {
            reloadSettings()
            status = BroadcastStatus(running: true, startedAt: startedAt)
            SharedStore.status = status
            live = .searching(offersToday: 0)
            SharedStore.liveState = live
            publish()
            fetchInbox()
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1.5, repeating: 3)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t

        Notifier.postInfo(
            "Leitura ligada",
            settings.saveScreenshots
                ? "Abra o Uber Driver. Cada chamado chega como notificação e o print vai para o álbum."
                : "Abra o Uber Driver. Cada chamado chega como notificação. Nenhuma imagem da tela é guardada.",
            id: "status"
        )
    }

    override func broadcastPaused() {
        queue.async {
            self.status.running = false
            self.publish()
        }
    }

    override func broadcastResumed() {
        queue.async {
            self.status.running = true
            self.publish()
        }
    }

    override func broadcastFinished() {
        timer?.cancel()
        timer = nil
        queue.sync {
            status.running = false
            status.tripPhase = nil
            status.screen = nil
            live = nil
            SharedStore.liveState = nil
            publish()
        }
        if #available(iOS 16.2, *) { LiveActivityController.end() }
        Notifier.postInfo("Leitura desligada",
                          "\(status.offersNotified) chamado(s) analisado(s) nesta sessão.",
                          id: "status")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard !busy, now - lastProcessed >= minInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        lastProcessed = now
        let orientation = Self.orientation(of: sampleBuffer)

        queue.async { [weak self] in
            guard let self else { return }
            autoreleasepool { self.process(pixelBuffer, orientation: orientation, at: now) }
            self.busy = false
        }
    }

    private func reloadSettings() {
        settings = SharedStore.settings
        factors = SharedStore.currentFactors(settings)
        context = settings.context(factors: factors)
    }

    // MARK: Canal com o app

    /// A cada 3 s (mesmo com a tela parada): recebe ajustes e comandos, e manda o sinal de vida.
    private func tick() {
        fetchInbox()
        let now = CFAbsoluteTimeGetCurrent()
        if liveShowingOffer, now - lastOfferSeen > liveOfferHold {
            liveShowingOffer = false
            pushLive(.searching(offersToday: status.offersNotified))
        }
        if dirty {
            publish()
        } else if now - lastPulse >= 6 {
            SharedStore.status = status
            Bridge.pulse(status: status, live: live)
            lastPulse = now
        }
    }

    /// Estado completo (chamados, corridas, tempos) + sinal de vida.
    private func publish() {
        SharedStore.status = status
        Bridge.publish(status: status, live: live)
        Bridge.pulse(status: status, live: live)
        lastPulse = CFAbsoluteTimeGetCurrent()
        dirty = false
    }

    private func fetchInbox() {
        Bridge.read { [weak self] boxes in
            guard let self else { return }
            let settingsBox = boxes[.settings]
            let commandBox = boxes[.command]
            let newSettings = Bridge.value(DriverSettings.self, from: settingsBox)
            let newCommand = Bridge.value(AppCommand.self, from: commandBox)
            self.queue.async {
                if let s = newSettings, let at = settingsBox?.at, at > (self.inboxStamp[.settings] ?? 0) {
                    self.inboxStamp[.settings] = at
                    if s != self.settings {
                        SharedStore.settings = s // fica guardado para a próxima vez que a leitura for ligada
                        self.reloadSettings()
                    }
                }
                if let c = newCommand, let at = commandBox?.at, at > (self.inboxStamp[.command] ?? 0) {
                    self.inboxStamp[.command] = at
                    self.handle(c)
                }
                // Caminho do App Group, quando ele existe.
                if let c = SharedStore.command { self.handle(c) }
            }
        }
    }

    private func handle(_ cmd: AppCommand) {
        guard cmd.id != lastCommandId else { return }
        lastCommandId = cmd.id
        // Comandos antigos (de antes desta gravação) não valem.
        guard cmd.at >= startedAt.addingTimeInterval(-5), Date().timeIntervalSince(cmd.at) < 6 * 3600 else { return }
        let t = Date().timeIntervalSince1970
        switch cmd.action {
        case .accept:
            if let offer = cmd.fingerprint.flatMap({ recentOffers[$0] }) ?? lastOffer {
                apply(tracker.handle(.manualAccept(offer, cmd.at.timeIntervalSince1970)))
            }
        case .finish:
            apply(tracker.handle(.manualFinish(t)))
        case .reset:
            apply(tracker.handle(.reset))
            clearTripStatus()
        case .resetLearning:
            SharedStore.samples = []
            reloadSettings()
        }
        dirty = true
    }

    // MARK: Quadro

    private func process(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, at now: CFAbsoluteTime) {
        if now - lastSettingsLoad > 5 {
            reloadSettings()
            lastSettingsLoad = now
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        let frame: OcrFrame
        do {
            frame = try recognize(pixelBuffer, orientation: orientation)
        } catch {
            status.lastError = error.localizedDescription
            return
        }
        status.framesAnalyzed += 1
        status.lastFrameAt = Date()
        status.lastOcrMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)

        let read = analyzer.read(frame: frame, context: context)
        let analysis = read.analysis
        if let analysis {
            missStreak = 0
            lastOffer = analysis
            if let fp = analysis.fingerprint {
                recentOffers[fp] = analysis
                if recentOffers.count > 12 { recentOffers = [fp: analysis] }
            }
            lastOfferSeen = now
            handleOffer(analysis, pixelBuffer: pixelBuffer, orientation: orientation, at: now)
        } else if read.parse.nearMiss {
            noteMiss(read.parse.cleanedText)
        } else {
            missStreak = 0
        }

        // A nossa própria tela não diz nada sobre o que o app de corrida está fazendo.
        if !read.parse.ownApp {
            let kind = ScreenClassifier.classify(frame, isOfferScreen: analysis != nil)
            status.screen = kind.rawValue
            if settings.autoTrack {
                apply(tracker.handle(.observe(kind, analysis, Date().timeIntervalSince1970)))
            }
        }

        if now - lastStatusSave > 2 {
            SharedStore.status = status
            lastStatusSave = now
        }
    }

    /// Cartão que parece chamado mas ficou sem valor ou distâncias por ~3 s: guarda o texto para diagnóstico.
    private func noteMiss(_ text: String) {
        missStreak += 1
        guard missStreak == 4, settings.keepReadDiagnostics else { return }
        let trimmed = String(text.prefix(1200))
        guard trimmed != lastMissText else { return }
        lastMissText = trimmed
        status.missed = (status.missed ?? 0) + 1
        var m = SharedStore.misses
        m.insert(ReadMiss(text: trimmed), at: 0)
        SharedStore.misses = m
        dirty = true
    }

    private func handleOffer(_ analysis: OfferAnalysis, pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, at now: CFAbsoluteTime) {
        guard analysis.decision.classification != .gray || settings.notifyIncomplete else { return }
        let decision = gate.offer(analysis, at: now)
        let fp: String
        switch decision {
        case .notify(let f), .update(let f): fp = f
        case .none: return
        }

        // Print do chamado (só com a opção ligada): na primeira leitura e de novo se a leitura melhorar.
        var shotURL: URL?
        if settings.saveScreenshots {
            let previous = shots[fp]
            if previous == nil || analysis.confidence > previous!.confidence + 0.05 {
                let name = previous?.name ?? Self.fileName(fp)
                if let data = jpeg(pixelBuffer, orientation: orientation) {
                    let url = SharedStore.screenshotURL(name)
                    if (try? data.write(to: url, options: .atomic)) != nil {
                        shots[fp] = (name, analysis.confidence)
                        if previous == nil { status.screenshotsSaved += 1 }
                        shotURL = url
                    }
                }
            } else {
                shotURL = SharedStore.screenshotURL(previous!.name)
            }
        }

        // Histórico (do lado da extensão) — a notificação leva uma cópia para o app.
        var record = OfferRecord(analysis, screenshot: shots[fp]?.name)
        switch decision {
        case .notify:
            SharedStore.append(record)
            status.offersNotified += 1
        case .update:
            var h = SharedStore.history
            if let i = h.firstIndex(where: { $0.fingerprint == fp }) {
                let keep = h[i]
                record = OfferRecord(analysis, date: keep.date, screenshot: shots[fp]?.name ?? keep.screenshot)
                record.id = keep.id
                record.outcome = keep.outcome
                h[i] = record
                SharedStore.history = h
            }
        case .none:
            break
        }

        Notifier.post(analysis, settings: settings, identifier: "offer-\(fp)",
                      screenshot: settings.attachScreenshot ? shotURL : nil, record: record)

        liveShowingOffer = true
        pushLive(.init(
            phase: .offer,
            verdict: analysis.matrix?.label ?? analysis.decision.classification.shortLabel,
            classification: analysis.decision.classification.rawValue,
            fare: analysis.offer.fare,
            perKm: analysis.financial.revenuePerKm,
            perHour: analysis.basis.revenuePerHour,
            category: analysis.offer.category,
            alert: analysis.matrix?.alert,
            offersToday: status.offersNotified
        ))
        publish()

        // Tenta já gravar no Fotos; se a extensão não tiver acesso, o app grava ao ser aberto.
        if let name = shots[fp]?.name, PhotoAlbum.canAdd, !SharedStore.savedToPhotos.contains(name) {
            if case .notify = decision { DispatchQueue.global(qos: .utility).async { PhotoAlbum.save([name]) } }
        }
    }

    // MARK: Corrida

    private func clearTripStatus() {
        status.tripPhase = TripPhase.none.rawValue
        status.tripAcceptedAt = nil
        status.tripFare = nil
        status.tripPredictedMin = nil
    }

    private func apply(_ effects: [TrackerEffect]) {
        guard !effects.isEmpty else { return }
        for e in effects {
            switch e {
            case let .outcome(offer, outcome, _):
                SharedStore.setOutcome(fingerprint: offer.fingerprint, outcome)
                if outcome == .accepted {
                    if let fp = offer.fingerprint {
                        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["offer-\(fp)"])
                    }
                    if settings.notifyTripSummary {
                        let predicted = offer.realistic?.totalTimeMin ?? offer.financial.totalTimeMin
                        Notifier.postInfo("🚗 Corrida aceita · \(Br.money(offer.offer.fare))",
                                          "Acompanhando o tempo real. Previsão: ~\(Br.minutes(predicted)).",
                                          id: "trip-now", category: Notifier.tripCategory)
                    }
                }
            case let .phase(p, timeline):
                status.tripPhase = p.rawValue
                if let tl = timeline {
                    status.tripAcceptedAt = Date(timeIntervalSince1970: tl.acceptedAt)
                    status.tripFare = tl.offer.offer.fare
                    status.tripPredictedMin = tl.offer.realistic?.totalTimeMin ?? tl.offer.financial.totalTimeMin
                } else if p == .none || p == .offer {
                    status.tripAcceptedAt = nil
                    status.tripFare = nil
                    status.tripPredictedMin = nil
                }
            case let .finished(tl):
                finish(tl)
            case .cancelled:
                clearTripStatus()
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["trip-now"])
                Notifier.postInfo("Corrida cancelada", "A corrida aceita foi encerrada antes de começar.", id: "trip-now")
            }
        }
        dirty = true
    }

    private func finish(_ tl: TripTimeline) {
        let a = tl.offer
        let o = a.offer
        // Registra o tempo real para o app aprender o fator de correção.
        if !tl.manual || tl.actualTripMin != nil {
            var s = SharedStore.samples
            s.append(TimingSample(at: tl.acceptedAt, offeredPickupMin: o.pickupTimeMin, actualPickupMin: tl.actualPickupMin,
                                  offeredTripMin: o.tripTimeMin, actualTripMin: tl.actualTripMin))
            SharedStore.samples = s
        }

        // Reavalia com os tempos medidos.
        var real = o
        if let p = tl.actualPickupMin, let tr = tl.actualTripMin {
            real.pickupTimeMin = p
            real.tripTimeMin = tr
        } else if let total = tl.totalMin {
            real.pickupTimeMin = 0
            real.tripTimeMin = total
        }
        var ctx = context
        ctx.useRealisticTime = false
        let measured = analyzer.analyze(offer: real, context: ctx)

        let total = tl.totalMin
        let record = TripRecord(
            id: (a.fingerprint ?? UUID().uuidString) + "@" + String(Int(tl.acceptedAt)),
            acceptedAt: Date(timeIntervalSince1970: tl.acceptedAt),
            completedAt: Date(timeIntervalSince1970: tl.completedAt ?? Date().timeIntervalSince1970),
            fare: o.fare,
            category: o.category,
            totalKm: a.financial.totalDistanceKm,
            offeredMin: a.financial.totalTimeMin,
            predictedMin: a.realistic?.totalTimeMin,
            actualPickupMin: tl.actualPickupMin,
            actualTripMin: tl.actualTripMin,
            totalMin: total,
            cost: a.financial.totalCost,
            profit: a.financial.operatingProfit,
            revenuePerHour: o.fare.flatMap { f in total.flatMap { $0 > 0.5 ? f / ($0 / 60) : nil } },
            classification: measured.decision.classification.rawValue,
            manual: tl.manual,
            screenshot: a.fingerprint.flatMap { shots[$0]?.name } ?? SharedStore.screenshotFor(fingerprint: a.fingerprint)
        )
        if settings.autoRegisterTrips {
            var trips = SharedStore.trips
            trips.removeAll { $0.id == record.id }
            trips.insert(record, at: 0)
            SharedStore.trips = trips
        }
        reloadSettings()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["trip-now"])
        if settings.notifyTripSummary {
            Notifier.postTripSummary(record, factors: factors, sound: settings.notifySound)
        }
        clearTripStatus()
    }

    // MARK: Dynamic Island

    /// Guarda o estado para o app e tenta atualizar a Atividade ao Vivo aberta por ele.
    /// Experimental: o iOS pode não entregar a atualização vinda da extensão; a notificação é o canal principal.
    private func pushLive(_ state: RideActivityAttributes.ContentState) {
        live = state
        SharedStore.liveState = state
        guard settings.liveActivity else { return }
        if #available(iOS 16.2, *) { LiveActivityController.update(state) }
    }

    // MARK: Imagem

    private static func fileName(_ fp: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let safe = fp.replacingOccurrences(of: "|", with: "_")
        return "chamado-\(df.string(from: Date()))-\(safe).jpg"
    }

    /// Print reduzido (~60%) em JPEG, para caber no limite de memória da extensão.
    private func jpeg(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let scale = min(1, 760 / max(image.extent.width, 1))
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return ciContext.jpegRepresentation(of: image, colorSpace: space, options: [quality: 0.72])
    }

    /// Texto da tela com posição de cada linha (em pixels, origem no topo).
    private func recognize(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> OcrFrame {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = settings.fastRecognition ? .fast : .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["pt-BR", "en-US"]
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])

        let rotated = orientation == .left || orientation == .right || orientation == .leftMirrored || orientation == .rightMirrored
        let w = rotated ? CVPixelBufferGetHeight(pixelBuffer) : CVPixelBufferGetWidth(pixelBuffer)
        let h = rotated ? CVPixelBufferGetWidth(pixelBuffer) : CVPixelBufferGetHeight(pixelBuffer)

        let lines: [OcrLine] = (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let b = obs.boundingBox // normalizado, origem embaixo à esquerda
            let box = Box(
                left: Int(b.minX * CGFloat(w)),
                top: Int((1 - b.maxY) * CGFloat(h)),
                right: Int(b.maxX * CGFloat(w)),
                bottom: Int((1 - b.minY) * CGFloat(h))
            )
            return OcrLine(text, box: box)
        }
        return OcrFrame(lines: lines, width: w, height: h)
    }

    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let raw = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let o = CGImagePropertyOrientation(rawValue: raw.uint32Value) else { return .up }
        return o
    }
}
