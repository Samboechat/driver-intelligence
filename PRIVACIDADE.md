# Privacidade e dados

## Princípios

- **Processamento local**: OCR com modelo ML Kit embarcado no APK. Nenhuma imagem ou texto sai do aparelho.
- **Sem imagens gravadas**: cada frame é lido em memória e descartado. O laboratório de OCR também não salva a imagem escolhida.
- **Sem integrações não autorizadas**: nenhuma API da Uber, nenhum serviço de acessibilidade, nenhuma chamada de rede feita pelo app. Observação: a biblioteca ML Kit do Google pode enviar métricas anônimas de uso da própria biblioteca, conforme os termos do Google — nunca imagens nem o texto das ofertas.
- **Backup automático desativado** (`allowBackup=false`).

## O que é armazenado e por quê

| Dado | Onde | Por quê |
|---|---|---|
| Veículos (nome, consumo, preço do combustível, custos por km) | Room `vehicles`, `vehicle_custom_costs` | Calcular custos e lucro |
| Ofertas analisadas (valor, distâncias, tempos, indicadores, classificação, confiança, categoria; origem/destino se exibidos) | Room `analyzed_offers` | Histórico de ofertas e estatística de aceitação |
| Corridas realizadas (registradas pelo motorista) | Room `trips` | Faturamento, lucro, estatísticas e CSV |
| Sessões do assistente (início/fim) | Room `work_sessions` | Tempo online e R$/h online |
| Preferências (metas, pesos, overlay, captura, tema) | DataStore `settings` | Personalização |

Não são coletados: nome do passageiro, telefone, localização GPS, conta da Uber, identificadores de publicidade.

## Retenção e exclusão

- Ajustes → Privacidade: remover ofertas não registradas com mais de 30 dias.
- Exclusão individual de ofertas e corridas no histórico.
- Exclusão total: *Configurações do Android → Apps → Driver Intelligence → Armazenamento → Limpar armazenamento*.

## Proteção local

Os dados ficam no armazenamento interno privado do app, inacessível a outros apps sem root. Não há dados financeiros sensíveis (cartão, conta bancária). Se o produto evoluir para sincronização em nuvem, será necessário consentimento explícito, criptografia em trânsito e política de privacidade publicada (LGPD).
