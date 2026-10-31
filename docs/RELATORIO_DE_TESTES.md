# Relatório de testes

Data da execução: 30/10/2026. Este relatório separa com precisão o que **foi executado** do que **foi escrito e ainda não foi executado**.

## Ambiente de desenvolvimento (auditoria)

| Item | Resultado |
|---|---|
| JDK | OpenJDK 21 disponível |
| Gradle | 8.14.3 local (wrapper gerado com ele) |
| Kotlin | compilador 2.0.21 disponível |
| Google Maven / Maven Central / Gradle Plugin Portal | **bloqueados pela rede do ambiente** |
| Android SDK (plataformas, build-tools) | **indisponível** (dl.google.com bloqueado) |

Consequência: o núcleo em Kotlin puro foi compilado e testado; o APK não pôde ser gerado neste ambiente. O workflow do GitHub Actions gera o APK e roda o restante dos testes.

## 1. Executados — núcleo de domínio (JVM)

Compilados com `kotlinc 2.0.21` e executados com `JUnit 4.13.2` (`org.junit.runner.JUnitCore`).

**Resultado: 96 testes, 96 aprovados, 0 falhas.**

| Classe | Testes | Cobre |
|---|---:|---|
| FinancialEngineTest | 20 | exemplo da especificação (R$ 1,76/km, R$ 46,25/h), corrida curta e longa, valor baixo, busca elevada, tempo elevado, combustível caro, custo operacional único com/sem combustível (anti-duplicidade), flag ignorada sem valor único, custos personalizados, dados incompletos, sem tempos, divisão por zero (tempo e distância), consumo zero, valores inválidos (negativo/NaN/infinito), sem custos, retorno vazio (% / fixo / sem custos / desativado / inválido) |
| DecisionEngineTest | 13 | curva de pontuação, verde com justificativa exata, vermelho, mensagem "distância de busca elevada e lucro estimado abaixo da sua meta", prejuízo sempre vermelho, lucro mínimo e distância máxima rebaixam verde, cinza por dados ausentes e por confiança baixa, renormalização sem tempos, pesos mudam o resultado (não usa indicador isolado), pesos zerados, metas dinâmicas |
| OfferTextParserTest | 16 | cartão padrão BR (valor, busca, viagem, categoria, nota, endereços), quebras de linha no meio dos pares, ponto decimal e "R $", inglês com milhas, metros e horas, valor do dia no topo não confundido, desempate por geometria, dinâmico/bônus, R$/km exibido, correção O→0/l→1 com penalidade, oferta parcialmente visível, tela sem oferta, pares sem rótulo (ordem deduzida), distância antes do tempo, linhas do próprio overlay ignoradas, categorias |
| NumberNormalizerTest | 6 | formatos BR e internacionais, milhar ambíguo, espaços e inválidos, correção de confusões, palavras preservadas |
| OfferValidatorAndAnalyzerTest | 10 | válida, incompleta, fora da faixa, velocidade incoerente, R$/km improvável, fluxo texto → classificação, leitura inconsistente vira cinza, tela sem oferta, impressão digital estável/distinta, entrada manual |
| OfferStateMachineTest | 12 | ocioso, alta confiança imediata, confirmação em 2 frames, sem atualização repetida, melhoria de confiança, oferta mudou, dispensa após 2 frames (tolera 1), leitura parcial mantém exibição, "lendo" sem piscar, deduplicação por janela, erro único + recuperação, reset |
| AnalyticsEngineTest | 9 | resumo do período, lucro parcial, tempo online recortado, período vazio, série diária com dias zerados, séries semanal/mensal, por horário e dia da semana, melhores horários exigem amostra mínima, progresso de meta |
| VehicleTest | 4 | consumo por modo, fallback sinalizado, só custos configurados entram, calculadora custo ÷ km |
| UtilAndOverlayLogicTest | 6 | formatação pt-BR, CSV (separador, aspas, injeção de fórmula), modos do overlay, arraste limitado à tela, posição após rotação, escala do retângulo de máscara |

Correções feitas durante a execução (falhas reais encontradas e resolvidas): nota do passageiro capturava o valor da linha anterior; "l,2" não era corrigido para "1,2"; expectativa errada no teste de escala do retângulo.

## 2. Escritos, NÃO executados neste ambiente

| Suíte | Testes | Como executar |
|---|---:|---|
| DatabaseTest (Robolectric, Room em memória): persistência de veículo com custos, troca e reatribuição do ativo, edição de custos, criar/editar/excluir corrida, deduplicação de oferta, oferta sem dados não registrada, registro como corrida idempotente e desvinculação, retenção | 8 | `./gradlew testDebugUnitTest` (roda no GitHub Actions) |
| SyntheticOfferOcrTest (instrumentado, ML Kit real): resoluções 1080/720/540 px, tema claro/escuro, baixo contraste | 4 | `./gradlew connectedDebugAndroidTest` ou workflow com "instrumented" |

## 3. Não coberto por testes automatizados

- **Compilação da camada Android** (serviço, captura, overlay, telas Compose): revisada manualmente, não compilada aqui.
- **Overlay** (arrastar, minimizar, expandir, permissão revogada, interrupção da projeção, rotação): a lógica pura está testada (`OverlayLogic`); o comportamento real exige aparelho.
- **Leitura de ofertas reais do Uber Driver**: depende de capturas reais. Use o Laboratório de OCR e transforme cada caso em teste no `OfferTextParserTest`.
- **Migração de banco**: o esquema está na versão 1; não há migração a testar ainda. O processo para a v2 está documentado em `AppDatabase`.

## Checklist de aceitação em aparelho

1. [ ] App instala e abre
2. [ ] Veículo cadastrado e definido como ativo
3. [ ] Captura autorizada; notificação do serviço visível
4. [ ] Overlay aparece sobre o Uber Driver
5. [ ] Oferta reconhecida em ~2 s; valores conferem com a tela
6. [ ] Classificação coerente com as metas
7. [ ] Overlay arrasta, minimiza, expande, pausa e fecha
8. [ ] "Aceitei — registrar corrida" cria a corrida no histórico
9. [ ] Dashboard e estatísticas refletem os registros
10. [ ] Exportação CSV abre corretamente no Excel/Planilhas
