import ReplayKit
import Vision
import CoreMedia
import DriverCore

/**
 * Extensão "Transmitir tela": recebe os quadros da tela enquanto o motorista usa o app de corrida,
 * lê o texto no próprio iPhone (Vision), analisa a oferta e avisa por notificação.
 *
 * Limite do iOS: extensões de transmissão têm ~50 MB de memória. Por isso:
 *  - um quadro por vez (os demais são descartados enquanto o anterior é lido);
 *  - no máximo ~1,5 leitura por segundo;
 *  - objetos do Vision recriados dentro de autoreleasepool a cada quadro.
 * Nenhuma imagem é salva ou enviada para fora do aparelho.
 */
final class SampleHandler: RPBroadcastSampleHandler {

    private let analyzer = OfferAnalyzer()
    private let queue = DispatchQueue(label: "di.ocr", qos: .userInitiated)
    private var gate = NotificationGate()
    private var settings = SharedStore.settings
    private var busy = false
    private var lastProcessed: CFAbsoluteTime = 0
    private var lastSettingsLoad: CFAbsoluteTime = 0
    private var lastStatusSave: CFAbsoluteTime = 0
    private var status = BroadcastStatus()

    private let minInterval: CFAbsoluteTime = 0.65

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        settings = SharedStore.settings
        status = BroadcastStatus(running: true, startedAt: Date())
        SharedStore.status = status
        Notifier.postInfo(
            "Driver Intelligence ativo",
            SharedStore.isShared
                ? "Abra o app de corrida. As análises chegam aqui em cerca de 2 segundos."
                : "Ajustes do app não acessíveis (grupo do app indisponível); usando valores padrão.",
            id: "status"
        )
    }

    override func broadcastPaused() {
        status.running = false
        SharedStore.status = status
    }

    override func broadcastResumed() {
        status.running = true
        SharedStore.status = status
    }

    override func broadcastFinished() {
        status.running = false
        SharedStore.status = status
        Notifier.postInfo("Driver Intelligence desligado", "A leitura de ofertas foi encerrada.", id: "status")
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

    private func process(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, at now: CFAbsoluteTime) {
        if now - lastSettingsLoad > 5 {
            settings = SharedStore.settings
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

        if let analysis = analyzer.analyze(frame: frame, context: settings.context) {
            if analysis.decision.classification != .gray || settings.notifyIncomplete {
                switch gate.offer(analysis, at: now) {
                case .notify(let fp):
                    Notifier.post(analysis, settings: settings, identifier: "offer-\(fp)")
                    SharedStore.append(OfferRecord(analysis))
                    status.offersNotified += 1
                case .update(let fp):
                    Notifier.post(analysis, settings: settings, identifier: "offer-\(fp)")
                case .none:
                    break
                }
            }
        }
        if now - lastStatusSave > 2 {
            SharedStore.status = status
            lastStatusSave = now
        }
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
