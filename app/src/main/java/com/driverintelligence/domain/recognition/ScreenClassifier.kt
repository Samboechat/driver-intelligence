package com.driverintelligence.domain.recognition

/** O que o app de corrida está mostrando agora. */
enum class ScreenKind(val label: String) {
    OFFER("Oferta"),
    GOING_TO_PICKUP("Indo buscar o passageiro"),
    WAITING_PASSENGER("Aguardando o passageiro"),
    ON_TRIP("Em viagem"),
    TRIP_COMPLETED("Viagem concluída"),
    ONLINE_IDLE("Online, procurando viagens"),
    OFFLINE("Offline"),
    UNKNOWN("Outra tela"),
}

/**
 * Identifica a tela do app de corrida pelo texto lido (português e inglês).
 * As palavras-chave cobrem os textos mais comuns do Uber Driver; telas não reconhecidas
 * viram UNKNOWN e nunca disparam transições sozinhas.
 */
object ScreenClassifier {

    private val COMPLETED = listOf(
        "viagem concluida", "corrida concluida", "viagem finalizada", "corrida finalizada", "entrega concluida",
        "avalie o passageiro", "avalie sua viagem", "avaliar passageiro", "como foi a viagem", "voce ganhou",
        "trip complete", "rate your rider", "rate rider", "you earned",
    )
    private val ON_TRIP = listOf(
        "finalizar viagem", "finalizar corrida", "concluir viagem", "concluir corrida", "encerrar viagem",
        "deixando o passageiro", "levando ", "a caminho do destino", "rumo ao destino", "desembarque",
        "end trip", "complete trip", "dropping off",
    )
    private val WAITING = listOf(
        "iniciar viagem", "iniciar corrida", "deslize para iniciar", "aguardando o passageiro", "aguardando passageiro",
        "voce chegou", "chegou ao local", "esperando o passageiro", "tempo de espera",
        "start trip", "swipe to start", "waiting for", "you have arrived",
    )
    private val TO_PICKUP = listOf(
        "a caminho do passageiro", "a caminho do embarque", "indo buscar", "buscar o passageiro",
        "ir ate o passageiro", "local de embarque", "cheguei", "chegando ao embarque", "embarque em",
        "picking up", "en route to pickup", "pickup at",
    )
    private val OFFLINE = listOf("voce esta offline", "voce esta desconectado", "ficar online", "you're offline", "you are offline", "go online")
    private val IDLE = listOf(
        "procurando viagens", "procurando corridas", "buscando viagens", "voce esta online", "aguardando solicitacoes",
        "finding trips", "you're online", "you are online", "looking for trips",
    )

    fun classify(frame: OcrFrame, isOfferScreen: Boolean): ScreenKind {
        if (isOfferScreen) return ScreenKind.OFFER
        val text = " " + OfferTextParser.normalize(frame.lines.joinToString(" ") { it.text }) + " "
        fun has(list: List<String>) = list.any { text.contains(it) }
        return when {
            has(COMPLETED) -> ScreenKind.TRIP_COMPLETED
            has(ON_TRIP) -> ScreenKind.ON_TRIP
            has(WAITING) -> ScreenKind.WAITING_PASSENGER
            has(TO_PICKUP) -> ScreenKind.GOING_TO_PICKUP
            has(OFFLINE) -> ScreenKind.OFFLINE
            has(IDLE) -> ScreenKind.ONLINE_IDLE
            else -> ScreenKind.UNKNOWN
        }
    }
}
