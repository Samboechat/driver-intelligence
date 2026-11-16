import SwiftUI

/// Aba "Mais": ferramentas, veículo, metas e exportação.
struct MoreView: View {
    let engine: FinanceEngine

    @AppStorage("privacyMode") private var privacy = false

    var body: some View {
        List {
            Section("Decisão rápida") {
                NavigationLink {
                    SimulatorView(engine: engine)
                } label: {
                    row("Simulador de corrida", "Vale a pena? Inclui retorno vazio", "plusminus.circle.fill", Theme.accent)
                }
                NavigationLink {
                    FuelView(engine: engine)
                } label: {
                    row("Calculadora Flex", "Etanol ou gasolina pelo consumo real", "fuelpump.fill", Theme.warning)
                }
            }
            Section("Custos e reservas") {
                NavigationLink {
                    VehicleSettingsView(vehicle: engine.vehicle)
                } label: {
                    row("Veículo", "\(engine.vehicle.mode.title) · fixo de \(Fmt.money(engine.vehicle.dailyFixedCost, hidden: privacy))/dia",
                        "car.fill", Theme.info)
                }
                NavigationLink {
                    VaultView(engine: engine)
                } label: {
                    row("Cofre e banco de folga", "Manutenção \(Fmt.money(engine.vaultBalance, hidden: privacy)) · Folga \(Fmt.money(engine.dayOffBalance, hidden: privacy))",
                        "lock.shield.fill", Theme.accent)
                }
                NavigationLink {
                    GoalsSettingsView(settings: engine.settings)
                } label: {
                    row("Metas e alertas", "Semáforo, meta semanal, cofre, fadiga", "target", Theme.danger)
                }
            }
            Section("Inteligência geográfica") {
                NavigationLink {
                    HeatmapView(engine: engine)
                } label: {
                    row("Mapa de calor pessoal", "Onde seus turnos mais lucrativos começam e terminam", "map.fill", Theme.warning)
                }
                NavigationLink {
                    ZonesView()
                } label: {
                    row("Zonas de baixa liquidez", "Alerta ao entrar em regiões de retorno vazio", "exclamationmark.triangle.fill", Theme.danger)
                }
            }
            Section("Dados") {
                NavigationLink {
                    ExportView(engine: engine)
                } label: {
                    row("Exportar e backup", "CSV, relatório PDF e backup JSON local", "square.and.arrow.up.fill", Theme.info)
                }
            }
            Section {
                Text(verbatim: "DriverPro ROI funciona 100% offline. Seus dados ficam apenas neste iPhone.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Mais")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 6)
    }
}
