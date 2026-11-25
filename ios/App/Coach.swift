import AVFoundation
import DriverCore

/**
 * Ajudas durante o turno, rodando no app (que fica acordado em segundo plano pelo GPS):
 *  - fala o veredito de cada chamado novo (sai pelo som do carro / CarPlay);
 *  - avisa quando a meta do dia é batida e quando falta uma hora para o fim do turno.
 */
final class Coach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Coach()

    private let synth = AVSpeechSynthesizer()
    private var lastSpoken: String?
    private let defaults = UserDefaults.standard

    override init() {
        super.init()
        synth.delegate = self
    }

    func check(settings: DriverSettings, now: Date) {
        announce(settings: settings, now: now)
        goals(settings: settings, now: now)
    }

    // MARK: Voz

    private func announce(settings: DriverSettings, now: Date) {
        guard let r = SharedStore.history.first else { return }
        guard let last = lastSpoken else { lastSpoken = r.id; return }
        guard r.id != last else { return }
        lastSpoken = r.id
        guard settings.voiceAnnounce, now.timeIntervalSince(r.date) < 30 else { return }
        speak(Self.phrase(r))
    }

    static func phrase(_ r: OfferRecord) -> String {
        var parts: [String] = []
        switch r.cls {
        case .green: parts.append("Aceitar")
        case .yellow: parts.append("Avaliar")
        case .red: parts.append("Recusar")
        case .gray: parts.append("Conferir")
        }
        if let p = r.profit { parts.append("lucro de \(Int(p.rounded())) reais") }
        if let k = r.revenuePerKm {
            let reais = Int(k)
            let cents = Int(((k - Double(reais)) * 100).rounded())
            parts.append(cents == 0 ? "\(reais) reais o quilômetro" : "\(reais) e \(cents) o quilômetro")
        }
        if r.surgeReal == false { parts.append("dinâmico de fachada") }
        if r.cls == .red, let reason = r.reasons?.first?.split(separator: ":").first { parts.append(String(reason)) }
        return parts.joined(separator: ", ") + "."
    }

    private func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        u.rate = 0.52
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Meta do dia

    private func goals(settings: DriverSettings, now: Date) {
        guard settings.goalAlerts else { return }
        let pace = PaceNow.status(settings, now: now)
        guard pace.earned > 0 else { return }
        let day = String(Int(DailyPace.workdayStart(now, plan: settings.plan).timeIntervalSince1970))
        if pace.reached {
            guard defaults.string(forKey: "coach.goal") != day else { return }
            defaults.set(day, forKey: "coach.goal")
            Notifier.postInfo("🎯 Meta do dia batida", "\(Br.money(pace.earned)) em corridas hoje. O que entrar agora é extra.",
                              id: "goal", sound: true)
        } else if pace.hoursLeft > 0.5, pace.hoursLeft <= 1, let need = pace.neededPerHour {
            guard defaults.string(forKey: "coach.final") != day else { return }
            defaults.set(day, forKey: "coach.final")
            Notifier.postInfo("⏱️ Última hora do turno", "Faltam \(Br.money(pace.remaining)) para a meta: precisa de R$ \(Br.decimal(need, 0))/h até o fim.",
                              id: "goal", sound: true)
        }
    }
}
