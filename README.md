# DriverPro ROI

Calculadora de ganhos reais e telemetria para motoristas de aplicativo (Uber e 99). App nativo iOS 17+, SwiftUI, SwiftData, 100% offline.

## Gerar o .ipa (GitHub Actions)

1. Suba esta pasta para um repositório no GitHub (branch `main`).
2. A cada push, o workflow `.github/workflows/build-ipa.yml` roda em `macos-latest`:
   instala o XcodeGen → gera o `DriverProROI.xcodeproj` → compila em Release sem assinatura → empacota `Payload/DriverProROI.app` em `DriverProROI.ipa`.
3. O `.ipa` fica disponível em dois lugares:
   - **Actions → execução → Artifacts → `DriverProROI-ipa`** (zip com o .ipa dentro);
   - **Releases → `driverpro-roi-latest`** (pushes na `main`, `master` ou `driverpro-roi`), com link fixo:
     `https://github.com/<usuario>/<repo>/releases/download/driverpro-roi-latest/DriverProROI.ipa`

> Em repositório **privado**, o link da release só baixa com você logado no GitHub. Abra no Safari do iPhone logado, baixe e use "Compartilhar → AltStore/SideStore".
> Em repositório **público**, o mesmo link pode ser colado direto no AltStore/SideStore ("+" → URL).

## Instalar no iPhone

- **AltStore / SideStore:** abra o `.ipa` pelo app (ou "Compartilhar → AltStore"). Ele reassina com seu Apple ID gratuito (renovação a cada 7 dias). O App Group dos widgets é ajustado automaticamente pela AltStore.
- **TrollStore:** abra o `.ipa` direto no TrollStore (assinatura ad-hoc já embutida).
- **Xcode:** `brew install xcodegen && xcodegen generate`, abra o projeto, escolha seu Team em *Signing & Capabilities* nos dois targets e rode no aparelho.

Depois de instalar: Ajustes → DriverPro ROI → Localização → **Sempre** (para contar km com a tela bloqueada) e permita notificações.

## Estrutura

```
project.yml                     XcodeGen (app + extensão de widgets)
.github/workflows/build-ipa.yml Build do .ipa a cada push
Shared/                         Código comum app/widgets (estado do turno, intents, tema, Live Activity)
DriverProWidgets/               Widgets pequeno/médio interativos + Live Activity/Dynamic Island
DriverProROI/
  App/                          Entrada do app e TabView
  Models/                       SwiftData: Shift, DailySummary, Expense, FuelEntry, cofre, zonas, cronograma, perfil, ajustes
  Services/                     GPS, turno, motor financeiro, OCR (Vision), notificações, Live Activity, exportação/backup
  ViewModels/                   Resumo diário e análises (MVVM)
  Intents/                      App Intents / Siri / Atalhos
  Views/                        Turno, Resumos/DRE, Análises, Cronograma, Ferramentas
```

## Mapa das 30 funcionalidades

| # | Funcionalidade | Onde |
|---|---|---|
| 1 | Lucro líquido real | `FinanceEngine` · Resumo do dia · DRE |
| 2 | Perfil híbrido alugado/próprio (franquia, IPVA, seguro, FIPE) | Mais → Veículo |
| 3 | Calculadora Flex com consumo real | Mais → Calculadora Flex |
| 4 | CPK dinâmico | Análises |
| 5 | Km vazio (deadhead) | Resumo (km em corrida) · Análises |
| 6 | Cofre virtual de reserva | Mais → Cofre e folga |
| 7 | Rentabilidade por categoria (gráficos) | Análises |
| 8 | Semáforo de meta R$/km e R$/h | Turno · Resumos · Análises |
| 9 | Simulador de viabilidade de corrida | Mais → Simulador |
| 10 | Termômetro de dinâmico/promoções | Análises |
| 11 | Perfil de corrida (ticket médio) | Análises |
| 12 | Alerta de queda de R$/hora | `ShiftManager` (notificação discreta) |
| 13 | Classificação de tempo (dirigindo/ocioso/pausa) | Turno · Análises |
| 14 | Mapa de calor pessoal | Mais → Mapa de calor |
| 15 | Replay do trajeto | Resumos → ícone de mapa |
| 16 | Auditoria de odômetro + calibração do GPS | Resumo do dia · Análises |
| 17 | Zonas de baixa liquidez | Mais → Zonas |
| 18 | Gestão de bateria do GPS (pausa / parado > 3 min) | `LocationService` |
| 19 | Meta semanal auto-ajustável | Turno · Análises |
| 20 | Barra "Pago o dia" | Turno |
| 21 | Banco de folga remunerada | Cofre e folga · Cronograma |
| 22 | Despesas de rua em 1 toque | Turno |
| 23 | DRE semanal/mensal/anual | Resumos → DRE |
| 24 | Projeção run-rate | Resumos → DRE (mensal) |
| 25 | Live Activity + Dynamic Island | `DriverProWidgets/ShiftLiveActivity.swift` |
| 26 | Widgets interativos | `DriverProWidgets/ShiftStatusWidget.swift` |
| 27 | Atalhos / Siri | `Intents/ShiftAppIntents.swift` |
| 28 | OCR de prints Uber/99 | Resumo do dia → Importar print |
| 29 | Monitor de fadiga 8h/10h/12h | Turno + notificações |
| 30 | Olho mágico + CSV/PDF | Ícone de olho no topo · Mais → Exportar |

## Automação por Bluetooth (Atalhos)

Atalhos → Automação → **Bluetooth** → escolha o rádio do carro → *Conectado* → ação **Iniciar turno** (DriverPro ROI) → "Executar imediatamente".
Para a desconexão, crie outra automação *Desconectado* com **Pedir para escolher do menu** → "Pausar turno" / "Encerrar turno".
