# Arquitetura

## Visão geral

Clean Architecture + MVVM em um único módulo Gradle, com separação por pacotes. Tudo o que é regra de negócio fica em `domain/`, que **não importa nada do Android** — por isso pode ser compilado e testado na JVM pura (foi assim que os 96 testes do núcleo rodaram).

```
            ┌──────────────── features (Compose + ViewModels Hilt) ────────────────┐
            │  Início · Histórico · Estatísticas · Veículos · Ajustes · Manual · Lab │
            └───────────────▲───────────────────────────────────────▲──────────────┘
                            │ StateFlow                              │
┌─────────── capture ───────┴────────┐                 ┌──────── data ──────────────┐
│ CaptureService (FGS mediaProjection)│◄── contexto ───│ Repositórios               │
│ ScreenCaptureEngine (VirtualDisplay)│    de análise  │ Room · DataStore           │
│ AssistantController (estado global) │──── registro ─►│                            │
└───────┬───────────────▲─────────────┘                 └────────────────────────────┘
        │ frame          │ efeitos
┌───────▼──────┐  ┌──────┴────────────── domain (Kotlin puro) ──────────────────────┐
│ recognition  │  │ OfferTextParser → OfferValidator → FinancialEngine → DecisionEngine│
│ ML Kit OCR   │─►│ OfferAnalyzer (orquestra)   OfferStateMachine (ciclo de vida)      │
│ Preprocessor │  │ AnalyticsEngine   OverlayLogic   Br/Csv                            │
└──────────────┘  └───────────────────────────────────────────────────────────────────┘
        ▲
┌───────┴──────┐
│ overlay      │  OverlayController (WindowManager) + OverlayContent (Compose)
└──────────────┘
```

Por que um módulo só (e não multi-módulo)? Sem poder compilar no ambiente de desenvolvimento, cada módulo extra é mais configuração Gradle sem verificação. A fronteira já existe: `domain/` não depende de Android e pode virar um módulo `:core:domain` (plugin `kotlin("jvm")`) movendo a pasta.

## Pipeline de um frame

1. **Captura** — `ScreenCaptureEngine` mantém um `VirtualDisplay` → `ImageReader`. O leitor descarta frames enquanto ninguém pede; quando o loop solicita, o próximo frame novo é convertido num bitmap reutilizado. Isso dá *backpressure* natural: nunca há mais de um frame em processamento.
2. **Tela protegida** — frame quase todo preto por 3 vezes seguidas → overlay avisa e sugere inserção manual.
3. **Máscara do overlay** — o retângulo da janela flutuante (coordenadas de tela × escala do frame, com margem) é pintado de preto antes do OCR. O parser ainda ignora linhas com o cabeçalho do próprio app.
4. **Pré-processamento** — recorte opcional (metade inferior) e realce de contraste opcional (escala de cinza + contraste 1,6×).
5. **OCR** — ML Kit Text Recognition (latino), modelo embarcado. Linhas com caixas delimitadoras.
6. **Extração** — `OfferTextParser`: normaliza números (`18,50`, `1.234,56`, `8.4`), corrige O→0/l→1 colados a dígitos, encontra valores monetários e pares "tempo (distância)", rotula busca/viagem pelo contexto ("de distância", "Viagem"), separa dinâmico/bônus, escolhe o valor da corrida pela altura do texto e proximidade dos pares.
7. **Validação** — `OfferValidator`: faixas plausíveis, velocidade média coerente, R$/km plausível, campos ausentes. Reduz a confiança; leitura inconsistente vira CINZA.
8. **Cálculo** — `FinancialEngine` (abaixo).
9. **Classificação** — `DecisionEngine` (abaixo).
10. **Ciclo de vida** — `OfferStateMachine.reduce(estado, evento) → (novo estado, efeitos)`.
11. **Efeitos** — exibir/atualizar overlay, "lendo…", limpar, registrar *oferta analisada* (deduplicada), erro.

### Máquina de estados

| Fase | Quando |
|---|---|
| IDLE | sem oferta na tela |
| SCREEN_DETECTED | tela de oferta, mas sem dados essenciais |
| OFFER_DETECTED | oferta legível aguardando confirmação (confiança < 85% precisa de 2 frames iguais) |
| EXTRACTING / VALIDATING / CALCULATING | fases transitórias do processamento de um frame (diagnóstico) |
| DISPLAYING | oferta exibida; frames iguais não geram atualização |
| OFFER_CHANGED | outra oferta substituiu a exibida |
| OFFER_DISMISSED | 2 frames seguidos sem oferta |
| ERROR | falha de processamento (exibida uma vez; recupera no próximo frame válido) |

Identidade da oferta: `centavos | busca(100 m) | viagem(100 m) | minutos da viagem`. Mesma impressão digital em até 2 min não é registrada de novo.

## Motor financeiro

```
distância total = busca + viagem          tempo total = busca + viagem
R$/km = valor ÷ distância total           R$/h = valor ÷ (tempo total ÷ 60)
combustível = (distância total ÷ consumo) × preço
custo operacional = distância total × custo operacional por km
lucro operacional = valor − combustível − custo operacional
```

- **Anti-duplicidade**: se o motorista informa um *custo operacional único* marcado como "inclui combustível", o combustível é mostrado mas não descontado de novo. A marcação é ignorada para custos itemizados (que nunca incluem combustível).
- **Terminologia separada**: faturamento bruto, receita após combustível, lucro operacional estimado. **Lucro líquido não é calculado por corrida** (depende de custos fixos e impostos).
- **Estimativa parcial**: qualquer custo não configurado (combustível, manutenção, pneus, óleo, depreciação) marca o resultado como parcial.
- **Retorno vazio**: cenário opcional (% da viagem ou km fixos), exibido à parte; nunca altera o lucro da corrida.
- **Robustez**: valores negativos, NaN, infinito, consumo zero e divisões por zero viram "indisponível", nunca números falsos.

## Classificação

Cada indicador recebe nota 0..1 contra a meta do motorista (60% da meta → 0; meta → 0,7; 125% → 1,0). Indicadores: R$/km, lucro/km, R$/h, lucro/h, tempo de busca, distância improdutiva, peso dos custos. Nota final = média ponderada dos disponíveis (pesos ajustáveis e renormalizados).

- VERDE ≥ 0,70 · AMARELO ≥ 0,45 · VERMELHO abaixo (limites ajustáveis)
- Lucro ≤ 0 → sempre VERMELHO. Lucro abaixo do mínimo por corrida ou distância total acima do limite → no máximo AMARELO.
- CINZA: faltam valor ou distâncias, ou a confiança da leitura está abaixo do mínimo (60% padrão).

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| MediaProjection + OCR, sem AccessibilityService | Exigência do projeto e da política do Google Play; não automatiza nada |
| Captura de tela inteira (`createConfigForDefaultDisplay` no Android 14+) | Comportamento consistente da máscara do overlay; não depende do motorista escolher o app certo |
| Um VirtualDisplay por token, `resize()` na rotação | Android 14+ proíbe recriar a partir do mesmo token |
| Callback da projeção registrado antes do VirtualDisplay | Obrigatório no Android 14+ |
| `startForeground(tipo mediaProjection)` antes de `getMediaProjection` | Obrigatório no Android 14+ |
| `START_NOT_STICKY` | O token não sobrevive à morte do processo; reiniciar sozinho falharia |
| Janela `TYPE_APPLICATION_OVERLAY`, `NOT_FOCUSABLE` + `NOT_TOUCH_MODAL` | Só captura toques sobre o cartão; o resto vai para o Uber |
| WindowContext (Android 11+) para WindowManager | Uso correto de serviço visual a partir de um Service |
| Posição salva como fração da tela | Sobrevive a rotação e mudanças de resolução |
| Gráficos em Canvas próprio | Sem biblioteca extra; identidade visual própria |
| Fonte do sistema com algarismos tabulares | Sem baixar fontes; números não "pulam" ao atualizar |
| Versões: AGP 8.7.3, Kotlin 2.0.21, KSP 2.0.21-1.0.28, Compose BOM 2024.12.01, Hilt 2.52, Room 2.6.1, ML Kit 16.0.1 | Combinação estável e amplamente usada — escolhida para maximizar a chance de o primeiro build passar sem poder compilar aqui. Atualizar depois (ver INSTALACAO.md) |
| targetSdk 35 | Suficiente para instalação direta; para publicar na Play Store em 2026 será preciso subir para o nível exigido |

## Desempenho e bateria

- Intervalo adaptativo: 600 ms com atividade de oferta, 1200 ms em espera (ajustáveis).
- Nenhum processamento com a tela apagada ou com a análise pausada.
- Frames só chegam quando a tela muda; tela parada = zero OCR.
- Bitmaps reutilizados; recortes/realces liberados após o uso; OOM capturado com pausa de 2 s.
- OCR e análise fora da thread principal; overlay atualizado só quando a oferta muda.
