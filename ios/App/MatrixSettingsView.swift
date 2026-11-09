import SwiftUI
import DriverCore

/// Ajustes da matriz de aceite: CPK, piso por hora, réguas por categoria, zonas e cidades.
struct MatrixSettingsView: View {
    @Binding var s: DriverSettings

    var body: some View {
        Form {
            Section {
                Toggle("Usar a matriz de aceite", isOn: $s.useMatrix)
            } footer: {
                Text("Ligada: cada chamado vira ACEITAR, AVALIAR ou RECUSAR pelas regras abaixo, e o lucro usa só o CPK. Desligada: volta a classificação por pontuação, com as metas e os custos do veículo.")
            }

            Section {
                NumberField(title: "Custo por km (CPK)", value: $s.matrix.costPerKm.optional, suffix: "R$")
                NumberField(title: "Piso por hora (recusar abaixo)", value: $s.matrix.hourFloor.optional, suffix: "R$")
                NumberField(title: "Ideal por hora", value: $s.matrix.hourIdeal.optional, suffix: "R$")
            } header: {
                Text("Custo e hora")
            } footer: {
                Text("Entre o piso e o ideal a corrida fica amarela. A hora usa o tempo realista (busca + viagem).")
            }

            ruleSection("Comfort / Black", $s.matrix.comfort)
            ruleSection("UberX / 99", $s.matrix.standard)

            Section {
                NumberField(title: "Viagem curta até", value: $s.matrix.shortTripKm.optional, suffix: "km")
                NumberField(title: "Viagem longa a partir de", value: $s.matrix.longTripKm.optional, suffix: "km")
            } header: {
                Text("Busca máxima")
            } footer: {
                Text("Viagens curtas usam a busca curta da categoria; longas, a busca longa; no meio, o limite sobe proporcionalmente.")
            }

            Section {
                KeywordsField(title: "Zona quente", list: $s.matrix.zones.hot)
                KeywordsField(title: "Periferia / km morto", list: $s.matrix.zones.periphery)
                NumberField(title: "Mínimo na periferia", value: $s.matrix.zones.peripheryMinPerKm.optional, suffix: "R$/km")
            } header: {
                Text("Bairros (Sorocaba)")
            } footer: {
                Text("Palavras separadas por vírgula, comparadas com o destino lido na tela (sem diferenciar acentos). Zona quente: o amarelo vira aceitar. Periferia: exige o mínimo acima e mostra o alerta \"\(s.matrix.zones.peripheryAlert)\".")
            }

            Section {
                ForEach(s.matrix.zones.intercity.indices, id: \.self) { i in
                    NumberField(title: s.matrix.zones.intercity[i].name, value: $s.matrix.zones.intercity[i].minimumFare.optional, suffix: "R$")
                }
            } header: {
                Text("Intermunicipal (valor mínimo)")
            } footer: {
                Text("Abaixo do mínimo da cidade a corrida é sempre RECUSAR, porque a volta é vazia. Atingindo o mínimo, o R$/km da categoria deixa de valer.")
            }

            Section {
                Button("Restaurar os valores originais", role: .destructive) { s.matrix = MatrixConfig() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Matriz de aceite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ruleSection(_ title: String, _ rule: Binding<CategoryRule>) -> some View {
        Section(title) {
            NumberField(title: "Aceitar a partir de", value: rule.acceptPerKm.optional, suffix: "R$/km")
            NumberField(title: "Amarelo a partir de", value: rule.yellowPerKm.optional, suffix: "R$/km")
            NumberField(title: "Busca máx. (curta)", value: rule.pickupShortKm.optional, suffix: "km")
            NumberField(title: "Busca máx. (longa)", value: rule.pickupLongKm.optional, suffix: "km")
            NumberField(title: "Nota mínima", value: rule.minRating.optional, suffix: "★")
        }
    }
}

/// Lista de palavras-chave editada como texto separado por vírgulas.
struct KeywordsField: View {
    var title: String
    @Binding var list: [String]
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField("bairro, outro bairro", text: $text, axis: .vertical)
                .font(.footnote)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: text) { new in
                    list = new.split(separator: ",")
                        .map { SorocabaZone.normalize(String($0)) }
                        .filter { !$0.isEmpty }
                }
        }
        .onAppear { text = list.joined(separator: ", ") }
    }
}
