import SwiftUI
import MapKit
import DriverCore

// MARK: - Posição real dos polos (busca no mapa da Apple, uma vez)

/// Os polos do guia têm uma posição aproximada; na primeira abertura o app procura cada um no mapa da Apple
/// e guarda a posição exata. Sem internet, fica a aproximada.
final class HubLocator: ObservableObject {
    static let shared = HubLocator()
    @Published private(set) var hubs: [DemandHub] = DemandGuide.hubs
    private let key = "hubCoords.v1"
    private var running = false

    init() { apply(UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]) }

    private func apply(_ cache: [String: [Double]]) {
        hubs = DemandGuide.hubs.map { h in
            var h = h
            if let c = cache[h.id], c.count == 2 { h.lat = c[0]; h.lon = c[1] }
            return h
        }
    }

    func refine() {
        guard !running else { return }
        var cache = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        let missing = DemandGuide.hubs.filter { cache[$0.id] == nil }
        guard !missing.isEmpty else { return }
        running = true
        Task { @MainActor in
            for hub in missing {
                let req = MKLocalSearch.Request()
                req.naturalLanguageQuery = hub.query
                req.region = MKCoordinateRegion(center: .init(latitude: hub.lat, longitude: hub.lon),
                                                latitudinalMeters: 20_000, longitudinalMeters: 20_000)
                if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                    let c = item.placemark.coordinate
                    let off = CLLocation(latitude: c.latitude, longitude: c.longitude)
                        .distance(from: CLLocation(latitude: hub.lat, longitude: hub.lon))
                    // Resultado muito longe do esperado é outro lugar com o mesmo nome.
                    if off < 12_000 { cache[hub.id] = [c.latitude, c.longitude] }
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            UserDefaults.standard.set(cache, forKey: key)
            apply(cache)
            running = false
        }
    }
}

// MARK: - Tela

struct RegionMapTab: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            RegionMapView()
        } else {
            NavigationStack { GuideList(hubs: DemandGuide.hubs) }
        }
    }
}

extension HubAdvice.Verdict {
    var color: Color {
        switch self {
        case .here: return .blue
        case .go: return Palette.positive
        case .maybe: return Palette.warning
        case .skip: return .gray
        }
    }
}

func levelColor(_ l: Int) -> Color {
    switch l {
    case 3: return Palette.positive
    case 2: return Palette.warning
    case 1: return .gray
    default: return .gray.opacity(0.5)
    }
}

@available(iOS 17.0, *)
struct RegionMapView: View {
    @StateObject private var locator = HubLocator.shared
    @ObservedObject private var gps = LocationService.shared
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: .init(latitude: -23.5015, longitude: -47.4526), span: .init(latitudeDelta: 0.17, longitudeDelta: 0.17)))
    @State private var useNow = true
    @State private var chosen = Date()
    @State private var now = Date()
    @State private var selected: String?
    @State private var showOffers = false
    @State private var expanded = false

    private var at: Date { useNow ? now : chosen }
    private var settings: DriverSettings { SharedStore.settings }

    private var here: GeoPoint? {
        gps.lastLocation.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, accuracy: 0, time: 0) }
    }

    private var samples: [HubSample] {
        let geo = SharedStore.offerGeo
        return SharedStore.history.compactMap { r in
            guard let p = geo[r.id], p.count >= 2 else { return nil }
            return HubSample(date: r.date, lat: p[0], lon: p[1], perKm: r.revenuePerKm, green: r.cls == .green)
        }
    }

    private func advice() -> [HubAdvice] {
        let s = settings
        let rule = s.comfortDriver ? s.matrix.comfort : s.matrix.standard
        return DemandGuide.advice(at: at, from: useNow ? here : nil, samples: samples, comfortDriver: s.comfortDriver,
                                  acceptPerKm: rule.acceptPerKm, costPerKm: s.matrix.costPerKm, hubs: locator.hubs)
    }

    var body: some View {
        let list = advice()
        NavigationStack {
            ZStack(alignment: .bottom) {
                map(list)
                panel(list).padding(10)
            }
            .navigationTitle("Onde rodar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Toggle("Mostrar meus chamados", isOn: $showOffers)
                        NavigationLink("Guia completo por dia e horário") { GuideList(hubs: locator.hubs) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .navigationBarTrailing) { timePicker }
            }
            .onAppear { locator.refine(); now = Date() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        }
    }

    private var timePicker: some View {
        HStack(spacing: 6) {
            if useNow {
                Button("Agora ▾") { chosen = now; useNow = false }.font(.subheadline.weight(.semibold))
            } else {
                DatePicker("", selection: $chosen, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "pt_BR"))
                Button { useNow = true } label: { Image(systemName: "arrow.uturn.backward.circle") }
            }
        }
    }

    private func map(_ list: [HubAdvice]) -> some View {
        let geo = SharedStore.offerGeo
        let offers = showOffers ? Array(SharedStore.history.prefix(300).filter { geo[$0.id] != nil }) : []
        return Map(position: $camera,
                   bounds: MapCameraBounds(centerCoordinateBounds: MKCoordinateRegion(
                    center: .init(latitude: -23.48, longitude: -47.45), span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5)),
                                           minimumDistance: 1500, maximumDistance: 80_000),
                   selection: $selected) {
            UserAnnotation()
            ForEach(list) { a in
                MapCircle(center: .init(latitude: a.hub.lat, longitude: a.hub.lon), radius: a.hub.radiusKm * 1000)
                    .foregroundStyle(levelColor(a.level).opacity(a.level >= 2 ? 0.28 : 0.12))
                    .stroke(levelColor(a.level), lineWidth: a.level >= 2 ? 2 : 1)
                Marker(a.hub.name, systemImage: icon(a.hub), coordinate: .init(latitude: a.hub.lat, longitude: a.hub.lon))
                    .tint(levelColor(a.level))
                    .tag(a.id)
            }
            ForEach(offers) { r in
                if let p = geo[r.id], p.count >= 2 {
                    Annotation("", coordinate: .init(latitude: p[0], longitude: p[1])) {
                        Circle().fill(r.cls.color).frame(width: 9, height: 9).overlay(Circle().stroke(.white, lineWidth: 1))
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass() }
    }

    private func icon(_ h: DemandHub) -> String {
        switch h.id {
        case "iguatemi", "ciane", "cidade", "sorocabashopping": return "bag.fill"
        case "uniso", "facens", "ufscar": return "graduationcap.fill"
        case "unimed", "santacasa", "regional": return "cross.case.fill"
        case "rodoviaria": return "bus.fill"
        case "eden": return "building.2.fill"
        default: return h.comfort == 2 ? "star.fill" : "house.fill"
        }
    }

    // MARK: Painel

    @ViewBuilder private func panel(_ list: [HubAdvice]) -> some View {
        if let id = selected, let a = list.first(where: { $0.id == id }) {
            HubCard(a: a) { selected = nil }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(useNow ? "Melhores agora" : "Melhores em \(at.formatted(.dateTime.weekday(.wide).hour().minute().locale(Locale(identifier: "pt_BR"))))")
                        .font(.headline)
                    Spacer()
                    Button(expanded ? "Menos" : "Mais") { withAnimation { expanded.toggle() } }.font(.caption)
                }
                ForEach(Array(list.prefix(expanded ? 8 : 3))) { a in
                    Button { selected = a.id } label: { AdviceRow(a: a) }.buttonStyle(.plain)
                }
                if useNow && here == nil {
                    Text("Ligue a localização para o app pesar a distância até cada região.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct AdviceRow: View {
    var a: HubAdvice
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(levelColor(a.level)).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.hub.name).font(.subheadline.weight(.semibold))
                    if a.hub.comfort == 2 { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.warning) }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(a.verdict.label).font(.caption.weight(.heavy)).foregroundStyle(a.verdict.color)
                if let d = a.distanceKm { Text("\(Br.decimal(d, 1)) km").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if let w = a.window { return "\(DemandGuide.levelLabel(a.level)) · \(w.why)" }
        if let n = a.nextPeak { return "Melhora às \(n.at.formatted(date: .omitted, time: .shortened)): \(n.window.why)" }
        return "Sem movimento previsto"
    }
}

struct HubCard: View {
    var a: HubAdvice
    var close: () -> Void

    var body: some View {
        let wd = Calendar.current.component(.weekday, from: a.arrival)
        let wins = DemandGuide.windows(a.hub, weekday: wd)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(a.hub.name).font(.headline)
                Text(a.verdict.label).font(.caption.weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(a.verdict.color.opacity(0.2))).foregroundStyle(a.verdict.color)
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
            HStack(spacing: 14) {
                stat(a.levelLabel, "demanda", levelColor(a.level))
                stat(["Baixo", "Médio", "Alto"][min(2, max(0, a.hub.comfort))], "perfil Comfort")
                if let d = a.distanceKm { stat("\(Br.decimal(d, 1)) km", "chega \(a.arrival.formatted(date: .omitted, time: .shortened))") }
                if let c = a.tripCost { stat(Br.money(c), "custo p/ ir") }
            }
            if let own = a.own {
                Text("Seu histórico aqui neste horário: \(own.count) chamados · \(Br.percent(own.greenShare)) para aceitar · \(Br.decimal(own.avgPerKm))/km")
                    .font(.caption.weight(.medium)).foregroundStyle(Palette.positive)
            }
            if let note = a.hub.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            if a.hub.periphery {
                Label("Periferia: corrida que termina aqui volta vazia.", systemImage: "arrow.uturn.backward")
                    .font(.caption).foregroundStyle(Palette.warning)
            }
            if !wins.isEmpty {
                Text("Horários neste dia").font(.caption.weight(.semibold)).padding(.top, 2)
                ForEach(Array(wins.enumerated()), id: \.offset) { _, w in
                    HStack(spacing: 6) {
                        Circle().fill(levelColor(w.level)).frame(width: 7, height: 7)
                        Text(w.hours).font(.caption.monospacedDigit().weight(w == a.window ? .bold : .regular))
                        Text(w.why).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Text(a.hub.places.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ v: String, _ t: String, _ c: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(c)
            Text(t).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Guia completo: todas as regiões, com os horários de cada dia da semana.
struct GuideList: View {
    var hubs: [DemandHub]
    @State private var weekday = Calendar.current.component(.weekday, from: Date())
    private let names = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]

    var body: some View {
        List {
            Section {
                Picker("Dia", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(names[$0 - 1]).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Estimativa pelos polos que geram corrida: shoppings, faculdades, hospitais, rodoviária, bares, fábricas e bairros de perfil Comfort. Quando você tem 4 ou mais chamados numa região e horário, o mapa mistura com o seu histórico real.")
            }
            ForEach(hubs) { h in
                Section {
                    let wins = DemandGuide.windows(h, weekday: weekday)
                    if wins.isEmpty {
                        Text("Sem horário forte neste dia").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(wins.enumerated()), id: \.offset) { _, w in
                        HStack {
                            Circle().fill(levelColor(w.level)).frame(width: 8, height: 8)
                            Text(w.hours).font(.subheadline.monospacedDigit())
                            Text(w.why).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text(DemandGuide.levelLabel(w.level)).font(.caption.weight(.bold)).foregroundStyle(levelColor(w.level))
                        }
                    }
                    Text(h.places.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Text(h.name)
                        if h.comfort == 2 { Image(systemName: "star.fill").foregroundStyle(Palette.warning) }
                        if h.periphery { Text("· periferia").foregroundStyle(Palette.warning) }
                    }
                }
            }
        }
        .navigationTitle("Guia de regiões")
    }
}
