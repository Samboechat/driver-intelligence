import Combine
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct HeatPoint: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool
    let day: Date
    let perHour: Double
    let net: Double
    let signal: Signal
}

/// Mapa de calor pessoal: onde começam e terminam os turnos mais lucrativos.
struct HeatmapView: View {
    let engine: FinanceEngine

    @AppStorage("privacyMode") private var privacy = false
    @State private var position: MapCameraPosition = .automatic
    @State private var filter = 0
    @State private var onlyProfitable = false

    private var points: [HeatPoint] {
        var result: [HeatPoint] = []
        for (index, summary) in engine.summaries.enumerated() {
            let day = engine.breakdowns[index]
            guard day.hours > 0 else { continue }
            let signal = engine.signal(perHour: day.grossPerHour)
            if onlyProfitable && signal != .green { continue }
            if filter != 2, let lat = summary.startLat, let lon = summary.startLon {
                result.append(HeatPoint(id: "s-\(summary.id.uuidString)",
                                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                        isStart: true, day: summary.day, perHour: day.netPerHour, net: day.net, signal: signal))
            }
            if filter != 1, let lat = summary.endLat, let lon = summary.endLon {
                result.append(HeatPoint(id: "e-\(summary.id.uuidString)",
                                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                        isStart: false, day: summary.day, perHour: day.netPerHour, net: day.net, signal: signal))
            }
        }
        return result
    }

    private func color(_ signal: Signal) -> Color {
        signal == .neutral ? Theme.muted : signal.color
    }

    var body: some View {
        let items = points
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("Pontos", selection: $filter) {
                    Text("Todos").tag(0)
                    Text("Inícios").tag(1)
                    Text("Encerramentos").tag(2)
                }
                .pickerStyle(.segmented)
                Toggle("Só turnos acima da meta de R$/hora", isOn: $onlyProfitable)
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if items.isEmpty {
                ContentUnavailableView(
                    "Sem pontos ainda",
                    systemImage: "map",
                    description: Text("O mapa é construído com os locais de início e fim dos turnos registrados pelo GPS.")
                )
            } else {
                Map(position: $position) {
                    ForEach(items) { point in
                        MapCircle(center: point.coordinate, radius: 700)
                            .foregroundStyle(color(point.signal).opacity(0.22))
                            .stroke(color(point.signal).opacity(0.8), lineWidth: 1)
                        Annotation(Fmt.date(point.day, "dd/MM"), coordinate: point.coordinate) {
                            VStack(spacing: 0) {
                                Image(systemName: point.isStart ? "play.circle.fill" : "stop.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(color(point.signal))
                                Text(privacy ? "••" : "\(Fmt.brl(point.perHour))/h")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 4)
                                    .background(Color.black.opacity(0.7), in: Capsule())
                            }
                        }
                    }
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                HStack(spacing: 14) {
                    LegendItem(color: Theme.accent, label: "Acima da meta", value: "")
                    LegendItem(color: Theme.warning, label: "Na margem", value: "")
                    LegendItem(color: Theme.danger, label: "Abaixo", value: "")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .screenBackground()
        .navigationTitle("Mapa de calor")
        .navigationBarTitleDisplayMode(.inline)
        .privacyToolbar()
    }
}

/// Replay do trajeto do dia (breadcrumbs) com início, pausas e encerramento.
struct RouteReplayView: View {
    let day: Date

    @Query(sort: \Shift.startedAt) private var shifts: [Shift]
    @State private var position: MapCameraPosition = .automatic
    @State private var progress = 1.0
    @State private var playing = false

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var dayShifts: [Shift] {
        shifts.filter { Calendar.br.isDate($0.day, inSameDayAs: day) }
    }

    var body: some View {
        let selected = dayShifts
        let route = selected.flatMap { $0.route }
        let pauses = selected.flatMap { $0.pauses }.filter { $0.lat != nil && $0.lon != nil }
        let coordinates = route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let lastIndex = max(0, coordinates.count - 1)
        let index = min(lastIndex, Int((progress * Double(lastIndex)).rounded()))
        let travelled = coordinates.isEmpty ? [] : Array(coordinates[0...index])
        let totalKm = selected.reduce(0) { $0 + $1.gpsKm }

        return VStack(spacing: 0) {
            if coordinates.count < 2 {
                ContentUnavailableView(
                    "Sem trajeto neste dia",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("O trajeto é gravado quando o turno roda com o GPS ativo.")
                )
            } else {
                Map(position: $position) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(Theme.muted.opacity(0.6), lineWidth: 4)
                    MapPolyline(coordinates: travelled)
                        .stroke(Theme.accent, lineWidth: 5)
                    Marker("Início", systemImage: "play.fill", coordinate: coordinates[0])
                        .tint(Theme.accent)
                    Marker("Encerramento", systemImage: "flag.checkered", coordinate: coordinates[lastIndex])
                        .tint(Theme.danger)
                    ForEach(pauses) { pause in
                        Marker("Pausa \(Fmt.date(pause.start, "HH:mm"))", systemImage: "pause.fill",
                               coordinate: CLLocationCoordinate2D(latitude: pause.lat ?? 0, longitude: pause.lon ?? 0))
                            .tint(Theme.warning)
                    }
                    Annotation("", coordinate: coordinates[index]) {
                        Image(systemName: "car.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.white, Theme.info)
                    }
                }

                VStack(spacing: 10) {
                    HStack {
                        Text(Fmt.date(route[index].t, "HH:mm"))
                            .font(.headline)
                            .monospacedDigit()
                        Spacer()
                        Text("\(Int((route[index].speed * 3.6).rounded())) km/h")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(Fmt.km(totalKm)) no dia")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 12) {
                        Button {
                            if progress >= 1 { progress = 0 }
                            playing.toggle()
                        } label: {
                            Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                        }
                        Slider(value: $progress, in: 0...1)
                    }
                }
                .padding(16)
                .background(Theme.card)
            }
        }
        .screenBackground()
        .navigationTitle("Trajeto de \(Fmt.date(day, "dd/MM"))")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in
            guard playing else { return }
            progress = min(1, progress + 0.004)
            if progress >= 1 { playing = false }
        }
    }
}

/// Zonas de baixa liquidez: toque no mapa para marcar; alerta ao entrar no perímetro.
struct ZonesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LowLiquidityZone.name) private var zones: [LowLiquidityZone]
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var draft: ZoneDraft?

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $position) {
                    ForEach(zones) { zone in
                        MapCircle(center: zone.coordinate, radius: zone.radius)
                            .foregroundStyle(Theme.danger.opacity(zone.isEnabled ? 0.25 : 0.08))
                            .stroke(Theme.danger.opacity(0.8), lineWidth: 1)
                        Marker(zone.name, systemImage: "exclamationmark.triangle.fill", coordinate: zone.coordinate)
                            .tint(Theme.danger)
                    }
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        draft = ZoneDraft(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    }
                }
            }
            .frame(minHeight: 280)

            List {
                Section {
                    Button {
                        if let coordinate = ShiftManager.shared.lastCoordinate {
                            draft = ZoneDraft(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        } else {
                            ShiftManager.shared.requestLocationAccess()
                        }
                    } label: {
                        Label("Marcar minha posição atual", systemImage: "location.fill")
                    }
                } footer: {
                    Text("Toque no mapa para marcar um bairro ou região com histórico ruim de retorno vazio. Com o turno rodando, você é avisado ao entrar no perímetro.")
                }
                Section("Zonas marcadas") {
                    if zones.isEmpty {
                        Text("Nenhuma zona marcada.")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(zones) { zone in
                        Toggle(isOn: Binding(
                            get: { zone.isEnabled },
                            set: { enabled in
                                zone.isEnabled = enabled
                                try? context.save()
                                ShiftManager.shared.reloadConfig()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.name)
                                Text("Raio de \(Int(zone.radius)) m")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(zones[index])
                        }
                        try? context.save()
                        ShiftManager.shared.reloadConfig()
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .screenBackground()
        .navigationTitle("Zonas de baixa liquidez")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { item in
            ZoneEditorSheet(draft: item)
        }
    }
}

struct ZoneDraft: Identifiable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
}

struct ZoneEditorSheet: View {
    let draft: ZoneDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var radius = 800.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome da região (bairro, cidade)", text: $name)
                VStack(alignment: .leading) {
                    Text("Raio do alerta: \(Int(radius)) m")
                    Slider(value: $radius, in: 300...5000, step: 100)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Nova zona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let title = name.trimmingCharacters(in: .whitespaces)
                        context.insert(LowLiquidityZone(name: title.isEmpty ? "Zona marcada" : title,
                                                        lat: draft.latitude, lon: draft.longitude, radius: radius))
                        try? context.save()
                        ShiftManager.shared.reloadConfig()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
