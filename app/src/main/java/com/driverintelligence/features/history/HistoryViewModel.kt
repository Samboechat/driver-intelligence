package com.driverintelligence.features.history

import android.content.ContentResolver
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.domain.detection.OfferOutcome
import com.driverintelligence.domain.model.AnalyzedOffer
import com.driverintelligence.domain.model.Classification
import com.driverintelligence.domain.model.DataSource
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.util.Br
import com.driverintelligence.domain.util.Csv
import com.driverintelligence.features.common.fullDateTime
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

enum class HistoryTab(val label: String) { TRIPS("Corridas realizadas"), OFFERS("Ofertas analisadas") }
enum class PeriodFilter(val label: String, val days: Long?) { TODAY("Hoje", 1), WEEK("7 dias", 7), MONTH("30 dias", 30), ALL("Tudo", null) }
enum class SortOrder(val label: String) { RECENT("Mais recentes"), VALUE("Maior valor"), PER_KM("Maior R$/km"), PROFIT("Maior lucro") }

data class HistoryFilters(
    val tab: HistoryTab = HistoryTab.TRIPS,
    val period: PeriodFilter = PeriodFilter.WEEK,
    val classification: Classification? = null,
    val source: DataSource? = null,
    val outcome: OfferOutcome? = null,
    val query: String = "",
    val sort: SortOrder = SortOrder.RECENT,
)

data class HistorySummary(val count: Int, val revenue: Double, val profit: Double?, val km: Double, val perKm: Double?)

data class HistoryUiState(
    val filters: HistoryFilters = HistoryFilters(),
    val trips: List<Trip> = emptyList(),
    val offers: List<AnalyzedOffer> = emptyList(),
    val summary: HistorySummary = HistorySummary(0, 0.0, null, 0.0, null),
    val message: String? = null,
)

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val tripRepository: TripRepository,
    private val offerRepository: OfferRepository,
) : ViewModel() {

    private val filters = MutableStateFlow(HistoryFilters())
    private val message = MutableStateFlow<String?>(null)

    val state: StateFlow<HistoryUiState> = combine(filters, tripRepository.trips, offerRepository.all, message) { f, trips, offers, msg ->
        val from = f.period.days?.let { LocalDate.now().minusDays(it - 1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() } ?: Long.MIN_VALUE
        val q = f.query.trim().lowercase()
        fun matches(vararg fields: String?) = q.isEmpty() || fields.any { it?.lowercase()?.contains(q) == true }

        val t = trips.asSequence()
            .filter { it.startedAt >= from }
            .filter { f.classification == null || it.classification == f.classification }
            .filter { f.source == null || it.source == f.source }
            .filter { matches(it.category, it.origin, it.destination, it.notes, Br.money(it.fare)) }
            .sortedWith(
                when (f.sort) {
                    SortOrder.RECENT -> compareByDescending<Trip> { it.startedAt }
                    SortOrder.VALUE -> compareByDescending<Trip> { it.fare }
                    SortOrder.PER_KM -> compareByDescending<Trip> { it.revenuePerKm ?: Double.MIN_VALUE }
                    SortOrder.PROFIT -> compareByDescending<Trip> { it.estimatedProfit ?: -Double.MAX_VALUE }
                },
            ).toList()

        val o = offers.asSequence()
            .filter { it.detectedAt >= from }
            .filter { f.outcome == null || it.outcome == f.outcome }
            .filter { f.classification == null || it.classification == f.classification }
            .filter { f.source == null || it.source == f.source }
            .filter { matches(it.category, it.origin, it.destination, Br.money(it.fare)) }
            .sortedWith(
                when (f.sort) {
                    SortOrder.RECENT -> compareByDescending<AnalyzedOffer> { it.detectedAt }
                    SortOrder.VALUE -> compareByDescending<AnalyzedOffer> { it.fare ?: 0.0 }
                    SortOrder.PER_KM -> compareByDescending<AnalyzedOffer> { it.revenuePerKm ?: Double.MIN_VALUE }
                    SortOrder.PROFIT -> compareByDescending<AnalyzedOffer> { it.estimatedProfit ?: -Double.MAX_VALUE }
                },
            ).toList()

        val km = t.sumOf { it.totalKm ?: 0.0 }
        val revenueWithKm = t.filter { (it.totalKm ?: 0.0) > 0 }.sumOf { it.fare }
        val profits = t.mapNotNull { it.estimatedProfit }
        HistoryUiState(
            filters = f,
            trips = t,
            offers = o,
            summary = HistorySummary(
                count = if (f.tab == HistoryTab.TRIPS) t.size else o.size,
                revenue = t.sumOf { it.fare },
                profit = if (profits.isEmpty()) null else profits.sum(),
                km = km,
                perKm = if (km > 0) revenueWithKm / km else null,
            ),
            message = msg,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HistoryUiState())

    fun setFilters(transform: (HistoryFilters) -> HistoryFilters) = filters.update(transform)

    fun deleteTrip(id: Long) = viewModelScope.launch { tripRepository.delete(id) }

    fun deleteOffer(id: Long) = viewModelScope.launch { offerRepository.delete(id) }

    fun registerOffer(offer: AnalyzedOffer) = viewModelScope.launch {
        tripRepository.registerFromOffer(offer)
        message.value = "Oferta registrada como corrida realizada."
    }

    fun dismissMessage() {
        message.value = null
    }

    /** Exporta as corridas filtradas para CSV (separador ";", compatível com Excel pt-BR). */
    fun exportCsv(resolver: ContentResolver, uri: Uri) = viewModelScope.launch {
        val trips = state.value.trips
        val header = listOf(
            "id", "data_hora", "valor", "busca_km", "viagem_km", "total_km", "busca_min", "viagem_min", "total_min",
            "rs_por_km", "rs_por_hora", "combustivel", "custo_operacional", "custo_estimado", "lucro_estimado",
            "estimativa_parcial", "classificacao", "confianca_leitura", "origem_dados", "categoria", "origem", "destino", "observacoes",
        )
        fun n(v: Double?, d: Int = 2) = v?.let { Br.decimal(it, d) }
        val rows = trips.map { t ->
            listOf(
                t.id.toString(), fullDateTime(t.startedAt), n(t.fare), n(t.pickupKm, 1), n(t.tripKm, 1), n(t.totalKm, 1),
                n(t.pickupMin, 0), n(t.tripMin, 0), n(t.totalMin, 0), n(t.revenuePerKm), n(t.revenuePerHour),
                n(t.fuelCost), n(t.operationalCost), n(t.estimatedCost), n(t.estimatedProfit),
                if (t.costPartial) "sim" else "não", t.classification?.label, t.recognitionConfidence?.let { Br.percent(it) },
                t.source.label, t.category, t.origin, t.destination, t.notes,
            )
        }
        val result = runCatching {
            withContext(Dispatchers.IO) {
                resolver.openOutputStream(uri)?.use { out -> out.write(Csv.write(header, rows).toByteArray(Charsets.UTF_8)) }
                    ?: error("Não foi possível abrir o arquivo")
            }
        }
        message.value = if (result.isSuccess) "${trips.size} corrida(s) exportada(s)." else "Falha ao exportar: ${result.exceptionOrNull()?.message}"
    }
}
