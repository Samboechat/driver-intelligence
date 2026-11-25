import SwiftUI
import MapKit
import DriverCore

// MARK: - Áreas de Sorocaba e região

/// Área desenhada no mapa. As posições são aproximadas (centro do bairro/cidade + raio).
struct MapArea: Identifiable {
    enum Kind { case hot, periphery, intercity }
    var id: String { name }
    var name: String
    var kind: Kind
    var lat: Double
    var lon: Double
    var radius: Double
    var minimumFare: Double? = nil

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var color: Color {
        switch kind {
        case .hot: return Palette.positive
        case .periphery: return Palette.warning
        case .intercity: return .blue
        }
    }

    var label: String {
        switch kind {
        case .hot: return "Zona quente"
        case .periphery: return "Periferia · volta vazia"
        case .intercity: return "Intermunicipal · mínimo \(Br.money(minimumFare))"
        }
    }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) <= radius
    }

    static let sorocaba: [MapArea] = [
        // Zonas quentes (aprovam o amarelo)
        MapArea(name: "Campolim", kind: .hot, lat: -23.5317, lon: -47.4680, radius: 1300),
        MapArea(name: "Iguatemi", kind: .hot, lat: -23.5378, lon: -47.4590, radius: 700),
        MapArea(name: "Alto da Boa Vista", kind: .hot, lat: -23.5190, lon: -47.4740, radius: 900),
        MapArea(name: "Mangal", kind: .hot, lat: -23.5240, lon: -47.4560, radius: 800),
        MapArea(name: "Jardim Emília", kind: .hot, lat: -23.5080, lon: -47.4700, radius: 700),
        // Periferia (mínimo R$ 2,20/km e alerta de volta vazia)
        MapArea(name: "Zona Norte", kind: .periphery, lat: -23.4580, lon: -47.4560, radius: 3200),
        MapArea(name: "Éden", kind: .periphery, lat: -23.4180, lon: -47.4200, radius: 2000),
        MapArea(name: "Cajuru", kind: .periphery, lat: -23.5250, lon: -47.5150, radius: 1800),
        MapArea(name: "Votorantim", kind: .periphery, lat: -23.5460, lon: -47.4380, radius: 2800),
        // Cidades da região (valor mínimo para aceitar)
        MapArea(name: "Itu", kind: .intercity, lat: -23.2640, lon: -47.2990, radius: 4500, minimumFare: 128),
        MapArea(name: "Salto", kind: .intercity, lat: -23.2000, lon: -47.2870, radius: 3500, minimumFare: 168),
        MapArea(name: "Viracopos", kind: .intercity, lat: -23.0074, lon: -47.1345, radius: 2500, minimumFare: 360),
    ]

    /// Sorocaba e região: o mapa não sai daqui.
    static let bounds = MKCoordinateRegion(
        center: .init(latitude: -23.40, longitude: -47.40),
        span: .init(latitudeDelta: 0.95, longitudeDelta: 0.95)
    )
    static let start = MKCoordinateRegion(
        center: .init(latitude: -23.5015, longitude: -47.4526),
        span: .init(latitudeDelta: 0.16, longitudeDelta: 0.16)
    )
}

// MARK: - Chamados com posição

struct MapOffer: Identifiable {
    var record: OfferRecord
    var coordinate: CLLocationCoordinate2D
    var id: String { record.id }
}

/// Faixas de horário para o filtro.
enum DayBand: Int, CaseIterable, Identifiable {
    case all, morning, afternoon, night, dawn
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .all: return "Todos"
        case .morning: return "Manhã"
        case .afternoon: return "Tarde"
        case .night: return "Noite"
        case .dawn: return "Madrug."
        }
    }
    func contains(_ d: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: d)
        switch self {
        case .all: return true
        case .morning: return (6..<12).contains(h)
        case .afternoon: return (12..<18).contains(h)
        case .night: return (18..<24).contains(h)
        case .dawn: return (0..<6).contains(h)
        }
    }
}

// MARK: - Tela

struct RegionMapTab: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            RegionMapView()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "map").font(.largeTitle)
                Text("O mapa precisa do iOS 17 ou mais novo.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background.ignoresSafeArea())
        }
    }
}

@available(iOS 17.0, *)
struct RegionMapView: View {
    @State private var camera: MapCameraPosition = .region(MapArea.start)
    @State private var offers: [MapOffer] = []
    @State private var days = 7
    @State private var band = DayBand.all
    @State private var showZones = true
    @State private var selectedOffer: String?
    @State private var selectedArea: MapArea?
    @StateObject private var gps = LocationService.shared

    private var shown: [MapOffer] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return offers.filter { $0.record.date >= since && band.contains($0.record.date) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                map
                VStack(spacing: 8) {
                    if let id = selectedOffer, let o = shown.first(where: { $0.id == id }) {
                        offerCard(o.record)
                    } else if let a = selectedArea {
                        areaCard(a)
                    }
                    summaryBar
                }
                .padding(12)
            }
            .navigationTitle("Mapa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { withAnimation { camera = .region(MapArea.start) } } label: { Image(systemName: "scope") }
                }
                ToolbarItem(placement: .navigationBarTrailing) { filterMenu }
            }
            .onAppear(perform: load)
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in load() }
        }
    }

    private var map: some View {
        Map(position: $camera, bounds: MapCameraBounds(centerCoordinateBounds: MapArea.bounds,
                                                        minimumDistance: 1200, maximumDistance: 140_000),
            selection: $selectedOffer) {
            UserAnnotation()
            if showZones {
                ForEach(MapArea.sorocaba) { a in
                    MapCircle(center: a.coordinate, radius: a.radius)
                        .foregroundStyle(a.color.opacity(0.18))
                        .stroke(a.color.opacity(0.7), lineWidth: 1.5)
                    Annotation(a.name, coordinate: a.coordinate, anchor: .center) {
                        Button { selectedOffer = nil; selectedArea = a } label: {
                            Image(systemName: a.kind == .hot ? "flame.fill" : (a.kind == .periphery ? "arrow.uturn.backward" : "signpost.right.fill"))
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(a.color))
                        }
                    }
                    .annotationTitles(.visible)
                }
            }
            ForEach(shown) { o in
                Marker(Br.money(o.record.fare), systemImage: o.record.surge != nil ? "bolt.fill" : "car.fill",
                       coordinate: o.coordinate)
                    .tint(o.record.cls.color)
                    .tag(o.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onChange(of: selectedOffer) { _, v in if v != nil { selectedArea = nil } }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Período", selection: $days) {
                Text("Hoje").tag(1)
                Text("7 dias").tag(7)
                Text("30 dias").tag(30)
                Text("Tudo").tag(3650)
            }
            Picker("Horário", selection: $band) {
                ForEach(DayBand.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Mostrar zonas", isOn: $showZones)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: Cartões

    private var summaryBar: some View {
        let list = shown
        let green = list.filter { $0.record.cls == .green }.count
        let perKm = list.compactMap(\.record.revenuePerKm)
        let avg = perKm.isEmpty ? nil : perKm.reduce(0, +) / Double(perKm.count)
        return HStack(spacing: 14) {
            stat("\(list.count)", "chamados")
            stat("\(green)", "p/ aceitar", Palette.positive)
            stat(Br.decimal(avg), "R$/km médio")
            Spacer()
            Text(band == .all ? periodLabel : "\(periodLabel) · \(band.label)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if offers.isEmpty {
                Text(gps.authorized
                     ? "Os chamados aparecem aqui conforme chegam (onde o carro estava)."
                     : "Permita a localização nos Ajustes para marcar os chamados no mapa.")
                    .font(.caption).multilineTextAlignment(.center)
                    .padding(12).frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var periodLabel: String {
        switch days {
        case 1: return "Hoje"
        case 7: return "7 dias"
        case 30: return "30 dias"
        default: return "Tudo"
        }
    }

    private func stat(_ v: String, _ t: String, _ c: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(c)
            Text(t).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func offerCard(_ r: OfferRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(r.date, format: .dateTime.weekday(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { selectedOffer = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            VerdictBlock(record: r)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func areaCard(_ a: MapArea) -> some View {
        let inside = shown.filter { a.contains($0.coordinate) }
        let perKm = inside.compactMap(\.record.revenuePerKm)
        let perHour = inside.compactMap(\.record.revenuePerHour)
        let avgKm = perKm.isEmpty ? nil : perKm.reduce(0, +) / Double(perKm.count)
        let avgH = perHour.isEmpty ? nil : perHour.reduce(0, +) / Double(perHour.count)
        let green = inside.filter { $0.record.cls == .green }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(a.color).frame(width: 10, height: 10)
                Text(a.name).font(.headline)
                Spacer()
                Button { selectedArea = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            Text(a.label).font(.caption).foregroundStyle(a.color)
            if inside.isEmpty {
                Text("Nenhum chamado recebido aqui no período.").font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    stat("\(inside.count)", "chamados")
                    stat(inside.isEmpty ? "—" : Br.percent(Double(green) / Double(inside.count)), "p/ aceitar", Palette.positive)
                    stat(Br.decimal(avgKm), "R$/km")
                    stat(Br.decimal(avgH, 0), "R$/h")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func load() {
        let geo = SharedStore.offerGeo
        offers = SharedStore.history.compactMap { r in
            guard let p = geo[r.id], p.count >= 2 else { return nil }
            return MapOffer(record: r, coordinate: .init(latitude: p[0], longitude: p[1]))
        }
    }
}
