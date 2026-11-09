# Driver Intelligence

Assistente financeiro para motoristas de aplicativo (Android). Lê a oferta de corrida exibida no Uber Driver, calcula a rentabilidade e mostra o resultado numa **janela flutuante** — em cerca de dois segundos após o reconhecimento. A decisão de aceitar é sempre do motorista: o app **nunca toca na tela**.

```
Captura (MediaProjection) → máscara do overlay → OCR local (ML Kit) → extração → validação
   → motor financeiro → classificação → máquina de estados → overlay → registro (oferta analisada)
```

## O que está implementado

| Área | Situação |
|---|---|
| Motor financeiro (R$/km, R$/h, combustível, custo operacional, lucro, margem, eficiência, retorno vazio, regra anti-duplicidade de combustível) | Implementado e testado (20 testes) |
| Classificação VERDE/AMARELO/VERMELHO/CINZA com pesos ajustáveis e justificativa | Implementado e testado (13 testes) |
| Parser de OCR (R$, km, m, mi, min, h, quebras de linha, confusões O→0, dinâmico, ordem invertida, geometria) | Implementado e testado (16 + 6 testes) |
| Validação, confiança e impressão digital da oferta | Implementado e testado (10 testes) |
| Máquina de estados da oferta (detecção, confirmação, mudança, dispensa, deduplicação) | Implementado e testado (12 testes) |
| Estatísticas (dia, semana, mês, horário, dia da semana, metas, amostra mínima) | Implementado e testado (9 testes) |
| Captura de tela (MediaProjection + serviço em primeiro plano, regras do Android 14+) | Implementado — requer teste em aparelho |
| OCR com ML Kit (modelo embarcado, 100% local) | Implementado — teste instrumentado sintético incluso |
| Overlay flutuante (arrastar, minimizar, expandir, pausar, fechar, transparência, posição salva, máscara no OCR) | Implementado — requer teste em aparelho |
| Dashboard, histórico (busca, filtros, ordenação, edição, exclusão, CSV), estatísticas, veículos, metas, critérios, permissões, laboratório de OCR | Implementado |
| Banco Room + DataStore | Implementado — testes Robolectric inclusos (8) |

## Inteligência de corrida

- **Tempo realista:** o app compara o tempo que a oferta promete com o tempo real das corridas que você fez e aprende o atraso típico (mediana, com recorte por horário de pico). Cada oferta mostra "App diz 24 min · na prática ~32 min" e a classificação usa o tempo realista.
- **Aceite e recusa detectados:** pela tela seguinte à oferta (busca do passageiro = aceita; volta para "procurando viagens" = recusada; ficou até o fim = ignorada). Botões Aceitei/Recusei corrigem quando a leitura falhar.
- **Corrida ao vivo:** relógio desde o aceite, previsão, alerta de atraso, R$/h caindo em tempo real, etapas busca/espera/viagem.
- **Resumo automático:** ao concluir, registra a corrida com os tempos reais e mostra real × prometido.
- **Comparativo:** "R$/km melhor que X% das suas últimas ofertas" e valor justo para cumprir suas metas.
- **Estatísticas de decisões:** taxa de aceite, boas ofertas que passaram, ruins aceitas e quanto cada app erra no tempo.

As telas pós-aceite são reconhecidas por palavras-chave comuns do Uber Driver ("Cheguei", "Iniciar viagem", "Finalizar viagem", "Viagem concluída"...). Se o seu app usar outros textos, a detecção automática falha e os botões do overlay continuam funcionando.

## Limitações reais (leia antes de usar)

1. **Compilação**: este código foi escrito num ambiente sem acesso ao Google Maven/SDK Android. O núcleo em Kotlin puro (motor financeiro, parser, estados, estatísticas) foi **compilado e testado de verdade** (96 testes). A camada Android foi revisada, mas **ainda não foi compilada**: o primeiro build (GitHub Actions ou Android Studio) pode apontar erros pontuais a corrigir. Ver [docs/RELATORIO_DE_TESTES.md](docs/RELATORIO_DE_TESTES.md).
2. **Tela protegida**: se o Uber Driver marcar a tela de oferta como protegida (`FLAG_SECURE`), o Android entrega a captura preta. O app detecta isso, avisa no overlay e oferece inserção manual. Não há como contornar sem violar as regras do sistema — e não tentamos.
3. **Layout da Uber**: o parser procura padrões (valor, "4 min (1,2 km)", "Viagem", "de distância"), não posições fixas, mas mudanças grandes de layout podem exigir ajuste. Use o **Laboratório de OCR** com prints reais para validar.
4. **Consentimento a cada início**: o Android 14+ exige autorizar a captura toda vez que o assistente é iniciado. É regra do sistema.
5. **Toques sobre o overlay**: a janela só ocupa a área do cartão e não bloqueia o resto da tela. Se algum botão do Uber ficar embaixo dela, arraste ou minimize.

## Como gerar o APK

**Opção A — GitHub (sem instalar nada):** suba o projeto para um repositório. O workflow `.github/workflows/android.yml` roda os testes e publica os APKs em *Actions → execução → Artifacts → driver-intelligence-apks*.

**Opção B — Android Studio:** abra a pasta, aguarde o Gradle sincronizar e use *Build → Build APK(s)*. Ou no terminal:

```bash
./gradlew testDebugUnitTest     # testes unitários
./gradlew assembleDebug         # app/build/outputs/apk/debug/app-debug.apk
```

Detalhes em [docs/INSTALACAO.md](docs/INSTALACAO.md).

## Estrutura

```
app/src/main/java/com/driverintelligence/
├── domain/            Kotlin puro (sem Android) — testável na JVM
│   ├── model/         ofertas, custos, metas, veículos, registros
│   ├── financial/     FinancialEngine, DecisionEngine
│   ├── recognition/   NumberNormalizer, OfferTextParser, OfferValidator, OfferAnalyzer
│   ├── detection/     OfferStateMachine
│   ├── analytics/     AnalyticsEngine
│   ├── overlay/       regras puras da janela (modos, geometria)
│   └── util/          formatação pt-BR, CSV
├── data/              Room (entidades, DAOs, mapeadores), DataStore, repositórios
├── capture/           CaptureService, ScreenCaptureEngine, consentimento, notificação
├── recognition/       ML Kit OCR, pré-processamento de imagem
├── overlay/           janela flutuante (WindowManager + Compose)
├── designsystem/      tema, componentes, gráficos em Canvas
├── features/          telas: início, histórico, estatísticas, veículos, ajustes, permissões, manual, laboratório OCR
├── permissions/       verificação e atalhos de permissões
└── di/                Hilt
```

## Documentação

- [Arquitetura e decisões técnicas](docs/ARQUITETURA.md)
- [Guia de permissões](docs/PERMISSOES.md)
- [Instalação e compilação](docs/INSTALACAO.md)
- [Privacidade e dados armazenados](docs/PRIVACIDADE.md)
- [Relatório de testes](docs/RELATORIO_DE_TESTES.md)

## iPhone (pasta `ios/`)

Versão iOS 0.3, instalada por IPA (ESign/AltStore). A leitura usa a transmissão de tela do iOS e o resultado chega por notificação.

- **Matriz de aceite** (`DriverCore/AcceptanceMatrix.swift`): ACEITAR / AVALIAR / RECUSAR por categoria.
  R$/km = valor ÷ (busca + viagem). CPK R$ 0,50. Piso R$ 42/h (recusa abaixo), ideal R$ 54/h.
  Comfort: aceita ≥ 2,30 · amarelo 2,00–2,29 · busca 5–8 km · nota ≥ 4,80.
  UberX/99: aceita ≥ 2,10 · amarelo 1,85–2,09 · busca 3–6 km · nota ≥ 4,85.
  A busca máxima cresce da curta (viagem até 5 km) à longa (20 km ou mais).
- **Zonas de Sorocaba** (`DriverCore/SorocabaZone.swift`): zona quente aprova o amarelo; periferia exige R$ 2,20/km e
  mostra "Volta Vazia - Ligar Direcionamento"; intermunicipal recusa abaixo do mínimo da cidade
  (Itu 128 · Salto 168 · Campinas/Viracopos 360 · Jundiaí 380 · SP Capital 422 · Guarulhos 530).
  Tudo editável em Ajustes › Matriz de aceite.
- **Painel**: meta da semana (R$ 2.820 e 56 h online), turno com hodômetro (km rodados, km morto, R$/km real) e decisões do dia.
- **Privacidade**: cada quadro é lido na memória e descartado. Prints são opcionais e começam desligados.
- **Dynamic Island** (experimental): aberta pelo app; a atualização em segundo plano depende do iOS.

Testes do núcleo: `cd ios/DriverCore && swift test`. O IPA sai do workflow `iOS` (GitHub Actions), sem assinatura.
