import SwiftUI
import Charts
import DriverCore

/// Cartão da meta do dia: quanto entrou, quanto falta e o R$/h necessário até o fim do turno.
struct TodayPaceCard: View {
    var settings: DriverSettings
    var trips: [TripRecord]
    var now: Date

    var body: some View {
        let p = PaceNow.status(settings, trips: trips, now: now)
        Card {
            HStack {
                Text("Meta de hoje").font(.headline)
                Spacer()
                Text("até \(p.shiftEnd.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Br.money(p.earned)).font(.system(size: 30, weight: .bold).monospacedDigit())
                Text("de \(Br.money(p.goal))").foregroundStyle(.secondary)
            }
            ProgressView(value: p.progress).tint(p.reached ? Palette.positive : Palette.warning)
            if p.reached {
                Label("Meta batida. O que entrar agora é extra.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.positive)
            } else if let need = p.neededPerHour {
                HStack {
                    Stat(title: "Falta", value: Br.money(p.remaining))
                    Stat(title: "Precisa por hora", value: "R$ \(Br.decimal(need, 0))",
                         color: need > settings.matrix.hourIdeal ? Palette.warning : Palette.positive)
                    Stat(title: "Horas restantes", value: Br.decimal(p.hoursLeft, 1))
                }
            } else {
                Text("O horário do turno já passou. Falta \(Br.money(p.remaining)) para a meta de hoje.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// Melhores horários pelo seu histórico: quantos chamados chegam e quanto pagam em cada hora, por dia da semana.
struct BestHoursView: View {
    @State private var history = SharedStore.history
    @State private var weekday = 0
    private let names = ["Todos", "Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]

    struct Bucket: Identifiable {
        var hour: Int
        var count: Int
        var avgPerKm: Double?
        var greenShare: Double
        var id: Int { hour }
    }

    private var buckets: [Bucket] {
        let cal = Calendar.current
        let list = history.filter { weekday == 0 || cal.component(.weekday, from: $0.date) == weekday }
        return (0..<24).map { h in
            let inHour = list.filter { cal.component(.hour, from: $0.date) == h }
            let km = inHour.compactMap(\.revenuePerKm)
            return Bucket(hour: h, count: inHour.count, avgPerKm: km.isEmpty ? nil : km.reduce(0, +) / Double(km.count),
                          greenShare: inHour.isEmpty ? 0 : Double(inHour.filter { $0.cls == .green }.count) / Double(inHour.count))
        }
    }

    var body: some View {
        let b = buckets
        let accept = SharedStore.settings.matrix.comfort.acceptPerKm
        let best = b.filter { $0.count >= 3 }.sorted { ($0.greenShare, $0.avgPerKm ?? 0) > ($1.greenShare, $1.avgPerKm ?? 0) }.prefix(3)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Dia", selection: $weekday) {
                    ForEach(0..<8, id: \.self) { Text(names[$0]).tag($0) }
                }
                .pickerStyle(.segmented)

                Card {
                    Text("Chamados por hora").font(.headline)
                    Chart(b) { x in
                        BarMark(x: .value("Hora", x.hour), y: .value("Chamados", x.count))
                            .foregroundStyle(x.greenShare >= 0.5 ? Palette.positive : (x.greenShare >= 0.25 ? Palette.warning : Color.gray))
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis { AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0)h") } } }
                    .frame(height: 170)
                    Text("Verde: metade ou mais dos chamados daquela hora era para aceitar.").font(.caption).foregroundStyle(.secondary)
                }

                Card {
                    Text("R$/km médio por hora").font(.headline)
                    Chart {
                        ForEach(b.filter { $0.avgPerKm != nil }) { x in
                            LineMark(x: .value("Hora", x.hour), y: .value("R$/km", x.avgPerKm!))
                            PointMark(x: .value("Hora", x.hour), y: .value("R$/km", x.avgPerKm!))
                        }
                        RuleMark(y: .value("Aceitar", accept))
                            .foregroundStyle(Palette.positive.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartXScale(domain: 0...23)
                    .frame(height: 170)
                    Text("Tracejado: R$ \(Br.decimal(accept))/km, a régua de aceite do Comfort.").font(.caption).foregroundStyle(.secondary)
                }

                Card {
                    Text("Seus melhores horários").font(.headline)
                    if best.isEmpty {
                        Text("Ainda há poucos chamados. Com uns dias de uso, aparecem aqui os horários que mais pagam para você.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(best)) { x in
                        HStack {
                            Text(String(format: "%02d:00–%02d:00", x.hour, (x.hour + 1) % 24)).font(.subheadline.monospacedDigit().weight(.semibold))
                            Spacer()
                            Text("\(x.count) chamados · \(Br.percent(x.greenShare)) p/ aceitar · \(Br.decimal(x.avgPerKm))/km")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Melhores horários")
        .navigationBarTitleDisplayMode(.inline)
    }
}
