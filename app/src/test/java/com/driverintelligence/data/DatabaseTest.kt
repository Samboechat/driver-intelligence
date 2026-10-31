package com.driverintelligence.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.driverintelligence.data.local.AppDatabase
import com.driverintelligence.data.repository.IntelligenceRepository
import com.driverintelligence.data.repository.OfferRepository
import com.driverintelligence.data.repository.TripRepository
import com.driverintelligence.data.repository.VehicleRepository
import com.driverintelligence.domain.detection.OfferOutcome
import com.driverintelligence.domain.detection.OutcomeSource
import com.driverintelligence.domain.detection.TripTimeline
import com.driverintelligence.domain.model.CostItem
import com.driverintelligence.domain.model.CostProfile
import com.driverintelligence.domain.model.CostSource
import com.driverintelligence.domain.model.CustomCost
import com.driverintelligence.domain.model.OfferData
import com.driverintelligence.domain.model.Trip
import com.driverintelligence.domain.model.Vehicle
import com.driverintelligence.domain.recognition.AnalysisContext
import com.driverintelligence.domain.recognition.OfferAnalyzer
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Persistência, edição, exclusão, duplicidade e recuperação — banco em memória via Robolectric. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DatabaseTest {

    private lateinit var db: AppDatabase
    private lateinit var vehicles: VehicleRepository
    private lateinit var trips: TripRepository
    private lateinit var offers: OfferRepository
    private lateinit var intelligence: IntelligenceRepository
    private val analyzer = OfferAnalyzer()

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).allowMainThreadQueries().build()
        vehicles = VehicleRepository(db.vehicleDao())
        trips = TripRepository(db.tripDao(), db.offerDao(), db.intelligenceDao())
        offers = OfferRepository(db.offerDao(), db.intelligenceDao())
        intelligence = IntelligenceRepository(db.intelligenceDao(), trips, db.offerDao())
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun veiculo_persisteComCustosERecupera() = runTest {
        val id = vehicles.save(
            Vehicle(
                name = "Onix 2022",
                consumptionCity = 11.0,
                energyPrice = 6.2,
                tires = CostItem(0.05, CostSource.CALCULATED),
                customCosts = listOf(CustomCost(label = "Lavagem", perKm = 0.01)),
            ),
        )
        val v = vehicles.get(id)!!
        assertEquals("Onix 2022", v.name)
        assertEquals(CostSource.CALCULATED, v.tires.source)
        assertEquals(1, v.customCosts.size)
        assertTrue("primeiro veículo vira ativo", v.isActive)
        assertEquals(id, vehicles.activeVehicle.first()!!.id)
    }

    @Test
    fun veiculo_trocaAtivoEExclusaoReatribui() = runTest {
        val a = vehicles.save(Vehicle(name = "A"))
        val b = vehicles.save(Vehicle(name = "B"))
        assertEquals(a, vehicles.activeVehicle.first()!!.id)
        vehicles.setActive(b)
        assertEquals(b, vehicles.activeVehicle.first()!!.id)
        vehicles.delete(b)
        assertEquals(a, vehicles.activeVehicle.first()!!.id)
    }

    @Test
    fun veiculo_edicaoSubstituiCustosPersonalizados() = runTest {
        val id = vehicles.save(Vehicle(name = "A", customCosts = listOf(CustomCost(label = "x", perKm = 0.1), CustomCost(label = "y", perKm = 0.2))))
        val v = vehicles.get(id)!!
        vehicles.save(v.copy(customCosts = listOf(CustomCost(label = "z", perKm = 0.3))))
        val edited = vehicles.get(id)!!
        assertEquals(listOf("z"), edited.customCosts.map { it.label })
    }

    @Test
    fun corrida_criarEditarExcluir() = runTest {
        val id = trips.save(Trip(startedAt = 1_000L, fare = 20.0, tripKm = 8.0))
        val t = trips.get(id)!!
        trips.save(t.copy(fare = 25.0, notes = "ajuste"))
        val edited = trips.get(id)!!
        assertEquals(25.0, edited.fare, 1e-9)
        assertEquals("ajuste", edited.notes)
        trips.delete(id)
        assertNull(trips.get(id))
        assertTrue(trips.trips.first().isEmpty())
    }

    @Test
    fun oferta_deduplicadaNaJanela() = runTest {
        val a = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), AnalysisContext(costs = CostProfile(11.0, 6.2)))
        val first = offers.record(a, null, now = 1_000_000L)
        val again = offers.record(a, null, now = 1_060_000L)
        val later = offers.record(a, null, now = 1_200_000L)
        assertNotNull(first)
        assertEquals(first, again)
        assertTrue(later != first)
        assertEquals(2, offers.all.first().size)
    }

    @Test
    fun oferta_semDadosEssenciaisNaoEhRegistrada() = runTest {
        val a = analyzer.analyzeManual(OfferData(fare = 18.5), AnalysisContext())
        assertNull(offers.record(a, null))
    }

    @Test
    fun oferta_registroComoCorridaEhIdempotente() = runTest {
        val a = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), AnalysisContext(costs = CostProfile(11.0, 6.2)))
        val offerId = offers.record(a, null)!!
        val offer = offers.get(offerId)!!
        val trip1 = trips.registerFromOffer(offer)
        val trip2 = trips.registerFromOffer(offers.get(offerId)!!)
        assertEquals(trip1, trip2)
        assertEquals(1, trips.trips.first().size)
        assertTrue(offers.get(offerId)!!.isRegistered)

        // Excluir a corrida desvincula a oferta (que continua como "analisada").
        trips.delete(trip1)
        assertFalse(offers.get(offerId)!!.isRegistered)
    }

    @Test
    fun retencao_removeSoOfertasAntigasNaoRegistradas() = runTest {
        val ctx = AnalysisContext(costs = CostProfile(11.0, 6.2))
        val old = analyzer.analyzeManual(OfferData(30.0, 1.0, 10.0, 3.0, 20.0), ctx)
        val recent = analyzer.analyzeManual(OfferData(31.0, 1.0, 10.0, 3.0, 20.0), ctx)
        val now = 100L * 86_400_000L
        offers.record(old, null, now = now - 40L * 86_400_000L)
        offers.record(recent, null, now = now)
        assertEquals(1, offers.purgeOlderThan(30, now))
        assertEquals(1, offers.all.first().size)
    }

    @Test
    fun resultadoDaOferta_aparecenaListagem() = runTest {
        val a = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), AnalysisContext())
        val id = offers.record(a, null)!!
        offers.setOutcome(id, OfferOutcome.REJECTED, OutcomeSource.DETECTED, 1L)
        assertEquals(OfferOutcome.REJECTED, offers.all.first().single().outcome)
        offers.setOutcome(id, OfferOutcome.ACCEPTED, OutcomeSource.MANUAL, 2L)
        val o = offers.all.first().single()
        assertEquals(OfferOutcome.ACCEPTED, o.outcome)
        assertEquals(OutcomeSource.MANUAL, o.outcomeSource)
    }

    @Test
    fun corridaAcompanhada_registraComTemposReaisEAlimentaAprendizado() = runTest {
        val ctx = AnalysisContext(costs = CostProfile(11.0, 6.2))
        val a = analyzer.analyzeManual(OfferData(18.5, 1.2, 9.3, 4.0, 20.0), ctx)
        val offerId = offers.record(a, null)!!
        val tl = TripTimeline(a, acceptedAt = 0, arrivedAt = 7 * 60_000L, startedAt = 9 * 60_000L, completedAt = 35 * 60_000L)
        val tripId = intelligence.saveCompletedTrip(tl, offerId, ctx, register = true)!!

        val t = trips.get(tripId)!!
        assertEquals(7.0, t.pickupMin!!, 1e-9)
        assertEquals(26.0, t.tripMin!!, 1e-9)
        assertEquals(33.0, t.totalMin!!, 1e-9)
        assertEquals(18.5 / (33.0 / 60.0), t.revenuePerHour!!, 1e-6)
        assertTrue(offers.get(offerId)!!.isRegistered)

        val sample = intelligence.samples.first().single()
        assertEquals(4.0, sample.offeredPickupMin!!, 1e-9)
        assertEquals(7.0, sample.actualPickupMin!!, 1e-9)

        // Mesma corrida de novo não duplica.
        assertEquals(tripId, intelligence.saveCompletedTrip(tl, offerId, ctx, register = true))
        assertEquals(1, trips.trips.first().size)

        // Excluir a corrida apaga os tempos medidos.
        trips.delete(tripId)
        assertTrue(intelligence.samples.first().isEmpty())
    }

    @Test
    fun migracao_1_para_2_preservaDadosECriaTabelasNovas() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "migracao-teste.db"
        context.deleteDatabase(name)
        // Monta um banco equivalente à v1: esquema atual sem as tabelas da v2 e user_version = 1.
        Room.databaseBuilder(context, AppDatabase::class.java, name).allowMainThreadQueries().build().also { v ->
            VehicleRepository(v.vehicleDao()).save(Vehicle(name = "Carro antigo", consumptionCity = 10.0))
            v.openHelper.writableDatabase.apply {
                execSQL("DROP TABLE offer_outcomes")
                execSQL("DROP TABLE trip_timings")
                version = 1
            }
            v.close()
        }
        val migrated = Room.databaseBuilder(context, AppDatabase::class.java, name)
            .addMigrations(*AppDatabase.MIGRATIONS)
            .allowMainThreadQueries()
            .build()
        // Abrir valida o esquema migrado contra as entidades (Room lança exceção se divergir).
        assertEquals("Carro antigo", VehicleRepository(migrated.vehicleDao()).vehicles.first().single().name)
        migrated.intelligenceDao().upsertOutcome(com.driverintelligence.data.local.OfferOutcomeEntity(1, "ACCEPTED", "MANUAL", 1))
        assertEquals(1, migrated.intelligenceDao().observeOutcomes().first().size)
        migrated.close()
        context.deleteDatabase(name)
    }
}
