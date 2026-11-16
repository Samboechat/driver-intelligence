import Foundation
import SwiftData

/// Persistência 100% local (SwiftData) e dados iniciais.
@MainActor
enum Store {
    static let container: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Shift.self,
            DailySummary.self,
            Expense.self,
            FuelEntry.self,
            VaultMovement.self,
            DayOff.self,
            LowLiquidityZone.self,
            ScheduleBlock.self,
            VehicleProfile.self,
            AppSettings.self
        ])
        do {
            let disk = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .none, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [disk])
        } catch {
            do {
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Não foi possível criar o banco de dados local: \(error)")
            }
        }
    }

    /// Garante que perfil do veículo, ajustes e cronograma padrão existam.
    static func bootstrap() {
        let context = container.mainContext
        _ = vehicle(context)
        _ = settings(context)
        let blocks = (try? context.fetch(FetchDescriptor<ScheduleBlock>())) ?? []
        if blocks.isEmpty {
            ScheduleSeeder.seed(into: context)
        }
        try? context.save()
    }

    static func vehicle(_ context: ModelContext) -> VehicleProfile {
        if let existing = (try? context.fetch(FetchDescriptor<VehicleProfile>()))?.first {
            return existing
        }
        let created = VehicleProfile()
        context.insert(created)
        return created
    }

    static func settings(_ context: ModelContext) -> AppSettings {
        if let existing = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first {
            return existing
        }
        let created = AppSettings()
        context.insert(created)
        return created
    }

    static func workWeekdays(_ blocks: [ScheduleBlock]) -> Set<Int> {
        Set(blocks.filter { $0.isEnabled && $0.kind == .work }.map { $0.weekday })
    }

    /// Motor financeiro montado direto do banco (usado fora das views).
    static func engine(_ context: ModelContext) -> FinanceEngine {
        let summaries = (try? context.fetch(FetchDescriptor<DailySummary>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let fuel = (try? context.fetch(FetchDescriptor<FuelEntry>())) ?? []
        let dayOffs = (try? context.fetch(FetchDescriptor<DayOff>())) ?? []
        let movements = (try? context.fetch(FetchDescriptor<VaultMovement>())) ?? []
        let blocks = (try? context.fetch(FetchDescriptor<ScheduleBlock>())) ?? []
        return FinanceEngine(
            summaries: summaries,
            expenses: expenses,
            fuelEntries: fuel,
            vehicle: vehicle(context),
            settings: settings(context),
            dayOffs: dayOffs,
            movements: movements,
            workWeekdays: workWeekdays(blocks)
        )
    }
}

/// Cronograma semanal pré-configurado (estratégia de dois picos).
enum ScheduleSeeder {
    static func seed(into context: ModelContext) {
        for weekday in 2...6 {
            context.insert(ScheduleBlock(
                weekday: weekday, startMinute: 3 * 60 + 30, endMinute: 8 * 60 + 30,
                title: "Madrugada Executiva & Conexões",
                focus: "Aeroportos, rodoviárias, turnos industriais e abertura do fluxo corporativo/escolar. Trânsito livre, alta velocidade média, menor consumo e mais Comfort.",
                kind: .work))
            context.insert(ScheduleBlock(
                weekday: weekday, startMinute: 8 * 60 + 30, endMinute: 16 * 60 + 30,
                title: "Pausa Estratégica",
                focus: "Descanso, sono, alimentação, abastecimento e limpeza do carro. Evita o trânsito travado do meio-dia e a baixa demanda da tarde.",
                kind: .rest))
            context.insert(ScheduleBlock(
                weekday: weekday, startMinute: 11 * 60 + 30, endMinute: 13 * 60 + 30,
                title: "Janela Extra Almoço",
                focus: "Ative apenas em dias de chuva ou tarifa dinâmica.",
                kind: .optional, isEnabled: false))
            context.insert(ScheduleBlock(
                weekday: weekday, startMinute: 16 * 60 + 30, endMinute: 21 * 60,
                title: "Pico Vespertino & Retorno",
                focus: "Saída de escritórios, faculdades e centros comerciais com alta demanda e multiplicadores dinâmicos.",
                kind: .work))
        }
        context.insert(ScheduleBlock(
            weekday: 7, startMinute: 7 * 60, endMinute: 12 * 60,
            title: "Manhã Comercial & Lazer",
            focus: "Deslocamentos fluidos para comércio, rodoviárias e compromissos matinais.",
            kind: .work))
        context.insert(ScheduleBlock(
            weekday: 7, startMinute: 18 * 60, endMinute: 2 * 60,
            title: "Esquenta & Madrugada Noturna",
            focus: "Restaurantes, bares, shows e eventos. Pico de tarifa dinâmica e gorjetas.",
            kind: .work))
        context.insert(ScheduleBlock(
            weekday: 1, startMinute: 15 * 60, endMinute: 22 * 60,
            title: "Retorno de Fim de Semana",
            focus: "Shoppings, parques, rodoviárias e retorno de viagens.",
            kind: .work))
    }
}
