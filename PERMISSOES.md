# Guia de permissões

O app explica cada permissão antes de pedir (tela *Permissões*, também exibida no primeiro uso). Nada é pedido em bloco. Funciona no Android 10 ou superior.

| # | Permissão | Por quê | Como é concedida | Obrigatória? |
|---|---|---|---|---|
| 1 | Sobrepor a outros apps (`SYSTEM_ALERT_WINDOW`) | Exibir a janela de análise por cima do Uber Driver | Tela do sistema "Exibir sobre outros apps" — botão *Autorizar* | Sim, para o overlay |
| 2 | Notificações (`POST_NOTIFICATIONS`, Android 13+) | O serviço de captura precisa de notificação; por ela você pausa/encerra | Diálogo do sistema | Recomendada |
| 3 | Captura de tela (MediaProjection) | Ler o texto da oferta | Diálogo do sistema **a cada início** do assistente. Escolha "tela inteira" | Sim, para leitura automática |
| 4 | Serviço em primeiro plano (`FOREGROUND_SERVICE_MEDIA_PROJECTION`) | Manter a leitura ativa enquanto o Uber está aberto | Automática (declarada no manifesto) | Sim |
| 5 | Otimização de bateria | Alguns fabricantes encerram apps em segundo plano | Abre a lista do sistema; o app **não** usa a permissão restrita de pedir isenção | Opcional |

Sem a permissão 1 ou 3, o app continua útil: análise manual, histórico, estatísticas e veículos funcionam normalmente.

## O que o app NÃO faz

- Não usa serviço de acessibilidade.
- Não simula toques, não aceita nem recusa corridas.
- Não usa root nem APIs privadas da Uber.
- Não envia capturas para servidores.

## Comportamentos do sistema que você pode ver

- **Ícone/chip de "compartilhando tela"** na barra de status enquanto o assistente está ativo (Android 14+). Tocar nele e parar o compartilhamento encerra a captura; o overlay mostra "Captura interrompida" com o botão *Retomar*.
- **Tela bloqueada** (Android 15+): o sistema pode encerrar a captura. Toque em *Retomar* no overlay.
- **Tela preta na leitura**: o app exibido bloqueia capturas. O overlay avisa e oferece inserção manual.
