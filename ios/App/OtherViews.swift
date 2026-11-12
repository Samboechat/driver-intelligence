import SwiftUI
import DriverCore

// MARK: - Simular (análise manual)

struct SimulatorView: View {
    @State private var fare: Double? = nil
    @State private var pickupKm: Double? = nil
    @State private var pickupMin: Double? = nil
    @State private var tripKm: Double? = nil
    @State private var tripMin: Double? = nil
    @State private var comfort = true
    @State private var destination = ""
    @State private var rating: Double? = nil
    @Environment(\.dismiss) private var dismiss

    private var analysis: OfferAnalysis? {
        guard fare != nil || tripKm != nil else { return nil }
        return OfferAnalyzer().analyze(
            offer: OfferData(fare: fare, pickupDistanceKm: pickupKm, tripDistanceKm: tripKm, pickupTimeMin: pickupMin, tripTimeMin: tripMin,
                             category: comfort ? "Comfort" : "UberX", destination: destination.isEmpty ? nil : destination, passengerRating: rating),
            context: SharedStore.settings.context
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Oferta") {
                    NumberField(title: "Valor", value: $fare, suffix: "R$")
                    NumberField(title: "Até o passageiro", value: $pickupKm, suffix: "km")
                    NumberField(title: "Tempo de busca", value: $pickupMin, suffix: "min")
                    NumberField(title: "Viagem", value: $tripKm, suffix: "km")
                    NumberField(title: "Tempo de viagem", value: $tripMin, suffix: "min")
                }
                Section("Matriz de aceite") {
                    Picker("Categoria", selection: $comfort) {
                        Text("Comfort").tag(true)
                        Text("UberX / 99").tag(false)
                    }
                    .pickerStyle(.segmented)
                    TextField("Destino (bairro, cidade)", text: $destination)
                        .autocorrectionDisabled()
                    NumberField(title: "Nota do passageiro", value: $rating, suffix: "★")
                }
                if let a = analysis {
                    Section("Resultado") { AnalysisSummary(a: a) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Simular oferta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Fechar") { dismiss() } }
            }
        }
    }
}

struct AnalysisSummary: View {
    var a: OfferAnalysis

    var body: some View {
        let f = a.financial
        let d = a.decision
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Br.money(f.grossRevenue)).font(.system(size: 30, weight: .bold).monospacedDigit())
                Spacer()
                Pill(text: a.matrix?.label ?? d.classification.shortLabel, color: d.classification.color)
            }
            Text(d.headline).font(.subheadline).foregroundStyle(d.classification == .gray ? .secondary : d.classification.color)
            if let mv = a.matrix {
                if let alert = mv.alert { Text("⚠️ \(alert)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.warning) }
                Text("\(mv.rideClass.label) · \(mv.zone.kind.label) · busca máx. \(Br.km(mv.pickupLimitKm))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Stat(title: "R$/km", value: Br.decimal(f.revenuePerKm))
                Stat(title: a.realistic != nil ? "R$/h real" : "R$/h", value: Br.decimal(a.basis.revenuePerHour, 0))
                Stat(title: "Lucro", value: Br.money(f.operatingProfit), color: (f.operatingProfit ?? 0) > 0 ? Palette.positive : Palette.negative)
            }
            if let real = a.realistic?.totalTimeMin, let shown = f.totalTimeMin {
                Text("App diz \(Br.minutes(shown)) · na prática ~\(Br.minutes(real))").font(.footnote).foregroundStyle(.secondary)
            }
            if let t = a.fareTarget, let gap = t.gap {
                Text(gap >= 0 ? "\(Br.money(gap)) acima do mínimo para aceitar" : "Valor justo: \(Br.money(t.minimumFare)) · faltam \(Br.money(-gap))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(gap >= 0 ? Palette.positive : Palette.warning)
            }
            if f.isCostEstimatePartial, a.matrix == nil {
                Text("Estimativa parcial: configure os custos do carro em Ajustes.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Histórico

struct HistoryView: View {
    @State private var history = SharedStore.history
    @State private var trips = SharedStore.trips
    @State private var mode = 0
    @State private var filter = 0
    @State private var confirmClear = false
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    /// 0 = todos · 1 = aceitar · 2 = avaliar · 3 = recusar · 4 = os que eu aceitei
    private var shown: [OfferRecord] {
        switch filter {
        case 1: return history.filter { $0.cls == .green }
        case 2: return history.filter { $0.cls == .yellow }
        case 3: return history.filter { $0.cls == .red }
        case 4: return history.filter { $0.result == .accepted }
        default: return history
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $mode) {
                    Text("Chamados").tag(0)
                    Text("Corridas feitas").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if mode == 0 {
                    if history.isEmpty {
                        Text("Cada chamado lido com a leitura ligada fica guardado aqui, com o veredito e o motivo.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Filtro", selection: $filter) {
                            Text("Todos").tag(0)
                            Text("Aceitar").tag(1)
                            Text("Avaliar").tag(2)
                            Text("Recusar").tag(3)
                            Text("Fiz").tag(4)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        if shown.isEmpty { Text("Nenhum chamado neste filtro.").foregroundStyle(.secondary) }
                    }
                    ForEach(grouped(shown, \.date), id: \.0) { day, items in
                        Section {
                            ForEach(items) { r in
                                NavigationLink { CaptureDetail(record: r) } label: { OfferRow(record: r) }
                            }
                        } header: {
                            HStack {
                                Text(day)
                                Spacer()
                                Text("\(items.count) chamado(s)")
                            }
                        }
                    }
                } else {
                    if trips.isEmpty {
                        Text("Corridas aceitas e concluídas aparecem aqui, com o tempo real de cada uma.").foregroundStyle(.secondary)
                    }
                    ForEach(grouped(trips, \.completedAt), id: \.0) { day, items in
                        Section {
                            ForEach(items) { TripRow(trip: $0) }
                                .onDelete { idx in
                                    let ids = idx.map { items[$0].id }
                                    trips.removeAll { ids.contains($0.id) }
                                    SharedStore.deletedTrips += ids
                                    SharedStore.trips = trips
                                }
                        } header: {
                            HStack {
                                Text(day)
                                Spacer()
                                Text(Br.money(items.compactMap(\.fare).reduce(0, +)))
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Histórico")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !history.isEmpty || !trips.isEmpty {
                        ShareLink(item: csvFile()) { Label("Exportar", systemImage: "square.and.arrow.up") }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !history.isEmpty || !trips.isEmpty {
                        Button("Limpar", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Apagar o histórico?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Apagar chamados", role: .destructive) {
                    SharedStore.historyClearedAt = Date()
                    SharedStore.history = []
                    history = []
                }
                Button("Apagar corridas feitas", role: .destructive) {
                    SharedStore.tripsClearedAt = Date()
                    SharedStore.trips = []
                    trips = []
                }
            } message: {
                Text("Os prints já enviados ao app Fotos continuam no álbum.")
            }
            .refreshable { Bridge.pull { _ in DispatchQueue.main.async { reload() } } }
            .onAppear(perform: reload)
            .onReceive(timer) { _ in reload() }
        }
    }

    private func reload() {
        let h = SharedStore.history
        let t = SharedStore.trips
        if h != history { history = h }
        if t != trips { trips = t }
    }

    private func csvFile() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("driver-intelligence-\(df.string(from: Date())).csv")
        try? SharedStore.csv().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func grouped<T: Identifiable>(_ items: [T], _ date: KeyPath<T, Date>) -> [(String, [T])] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEE, d 'de' MMMM"
        var out: [(String, [T])] = []
        for r in items {
            let key = f.string(from: r[keyPath: date]).capitalized
            if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1.append(r) } else { out.append((key, [r])) }
        }
        return out
    }
}

struct TripRow: View {
    var trip: TripRecord
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(trip.cls.color).frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Br.money(trip.fare)).font(.headline.monospacedDigit())
                Text([trip.category, Br.km(trip.totalKm), "real \(Br.minutes(trip.totalMin))", trip.offeredMin.map { "app \(Br.minutes($0))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Br.perHour(trip.revenuePerHour)).font(.subheadline.monospacedDigit()).foregroundStyle(trip.cls.color)
                Text(trip.acceptedAt, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @State private var s = SharedStore.settings
    @ObservedObject private var gps = LocationService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        MatrixSettingsView(s: $s)
                    } label: {
                        HStack {
                            Text("Matriz de aceite")
                            Spacer()
                            Text(s.useMatrix ? "Ligada · CPK \(Br.money(s.matrix.costPerKm))" : "Desligada").foregroundStyle(.secondary)
                        }
                    }
                    NumberField(title: "Meta da semana", value: $s.weeklyGoal.revenue.optional, suffix: "R$")
                    NumberField(title: "Horas online na semana", value: $s.weeklyGoal.hoursOnline.optional, suffix: "h")
                } header: {
                    Text("Regras e metas")
                } footer: {
                    Text(s.useMatrix
                         ? "Com a matriz ligada, as seções Veículo e Metas por corrida abaixo ficam sem efeito na classificação."
                         : "Com a matriz desligada, a classificação usa as metas por corrida e os custos do veículo abaixo.")
                }
                Section {
                    NumberField(title: "Consumo", value: $s.consumptionKmPerLiter, suffix: "km/L")
                    NumberField(title: "Preço do combustível", value: $s.fuelPrice, suffix: "R$/L")
                    NumberField(title: "Outros custos", value: $s.otherCostPerKm, suffix: "R$/km")
                } header: {
                    Text("Veículo")
                } footer: {
                    Text("Outros custos: manutenção, pneus, óleo, depreciação… somados por km. Sem eles, o lucro é marcado como estimativa parcial.")
                }
                Section {
                    NumberField(title: "Custo total por km", value: $s.operationalCostOverride, suffix: "R$/km")
                    Toggle("Esse valor já inclui combustível", isOn: $s.overrideIncludesFuel)
                } header: {
                    Text("Avançado (opcional)")
                } footer: {
                    Text("Se você já sabe seu custo total por km, informe aqui. Ele substitui \"Outros custos\" e evita descontar o combustível duas vezes.")
                }
                Section("Metas por corrida") {
                    NumberField(title: "Valor mínimo por km", value: $s.minRevenuePerKm.optional, suffix: "R$")
                    NumberField(title: "Valor mínimo por hora", value: $s.minRevenuePerHour.optional, suffix: "R$")
                    NumberField(title: "Lucro mínimo por km", value: $s.minProfitPerKm.optional, suffix: "R$")
                    NumberField(title: "Lucro mínimo por hora", value: $s.minProfitPerHour.optional, suffix: "R$")
                    NumberField(title: "Lucro mínimo por corrida", value: $s.minProfitPerTrip, suffix: "R$")
                    NumberField(title: "Busca máxima", value: $s.maxPickupMinutes.optional, suffix: "min")
                }
                Section {
                    Toggle("Usar tempo realista", isOn: $s.useRealisticTime)
                    Stepper("Busca: +\(Int(((s.pickupTimeFactor - 1) * 100).rounded()))%", value: $s.pickupTimeFactor, in: 1...2.5, step: 0.05)
                    Stepper("Viagem: +\(Int(((s.tripTimeFactor - 1) * 100).rounded()))%", value: $s.tripTimeFactor, in: 1...2, step: 0.05)
                } header: {
                    Text("Tempo realista")
                } footer: {
                    Text("Os apps costumam mostrar menos minutos do que a corrida leva. A análise usa o tempo corrigido por esses percentuais.")
                }
                Section {
                    Toggle("Som nas notificações", isOn: $s.notifySound)
                    Toggle("Um som para cada veredito", isOn: $s.verdictSounds).disabled(!s.notifySound)
                    Button("Enviar notificações de exemplo") { Notifier.sendTest(settings: s) }
                } header: {
                    Text("Notificações")
                } footer: {
                    Text("Com um som para cada veredito dá para saber se é aceitar, avaliar ou recusar sem olhar para a tela. O exemplo envia uma de aceitar e, em seguida, uma de recusar.")
                }
                Section {
                    Toggle("Avisar leituras incompletas", isOn: $s.notifyIncomplete)
                    Toggle("Leitura rápida (economiza bateria)", isOn: $s.fastRecognition)
                    NavigationLink("Diagnóstico da leitura") { DiagnosticsView() }
                } header: {
                    Text("Leitura da tela")
                } footer: {
                    Text("Leitura rápida gasta menos bateria, mas erra mais números. Se algum chamado não for lido, o Diagnóstico mostra o que o app enxergou.")
                }
                Section {
                    Toggle("Salvar print de cada chamado", isOn: $s.saveScreenshots)
                    Toggle("Mostrar o print na notificação", isOn: $s.attachScreenshot)
                } header: {
                    Text("Prints")
                } footer: {
                    Text("Desligado (padrão): cada quadro é lido na memória e descartado; nenhuma imagem da tela é guardada. Ligado: os prints vão para o álbum \"Driver Intelligence\" do app Fotos e aparece a aba Prints.")
                }
                Section {
                    Toggle("Dynamic Island", isOn: $s.liveActivity)
                    Toggle("Expandir a ilha a cada chamado", isOn: $s.islandAlert).disabled(!s.liveActivity)
                    Toggle("GPS do turno", isOn: $s.gpsTracking)
                    Toggle("Abrir o turno ao ligar a leitura", isOn: $s.autoShift)
                    if s.gpsTracking, !gps.authorized {
                        Button(gps.canAsk ? "Permitir localização" : "Localização negada. Abrir Ajustes") {
                            if gps.canAsk { gps.requestPermission() } else { Permissions.shared.openAppSettings() }
                        }
                    }
                } header: {
                    Text("Dynamic Island e GPS")
                } footer: {
                    Text("A ilha mostra R$/km e R$/h de cada chamado, na cor do veredito. Ela é aberta pelo app e só recebe os chamados enquanto o app está acordado; é o GPS do turno que mantém o app acordado com o Uber na frente, além de contar os km rodados. Com o turno automático, o turno fecha sozinho com a leitura desligada e o carro parado há 20 minutos.")
                }
                Section {
                    NumberField(title: "Meta diária", value: $s.dailyGoal, suffix: "R$")
                    Toggle("Detectar aceite e recusa", isOn: $s.autoTrack)
                    Toggle("Registrar corridas concluídas", isOn: $s.autoRegisterTrips)
                    Toggle("Resumo ao fim de cada corrida", isOn: $s.notifyTripSummary)
                    Button("Recomeçar o aprendizado de tempo", role: .destructive) {
                        SharedStore.samples = []
                        Bridge.send(AppCommand(action: .resetLearning))
                    }
                } header: {
                    Text("Corridas")
                } footer: {
                    Text("O app mede quanto cada corrida aceita realmente demora e, depois de 5 corridas, passa a corrigir o tempo das ofertas pelo seu histórico em cada horário.")
                }
                Section {
                    Text("Processamento 100% no iPhone. As análises ficam só no aparelho e nada é enviado para a internet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Ajustes")
            .onChange(of: s) { new in
                SharedStore.settings = new
                Bridge.publishSettings(new)
                AppSync.shared.pull()
                if new.saveScreenshots, PhotoAlbum.notDetermined { Task { await Permissions.shared.requestPhotos() } }
            }
        }
    }
}
