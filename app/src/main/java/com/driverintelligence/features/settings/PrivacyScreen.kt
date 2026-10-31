package com.driverintelligence.features.settings

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.features.common.ScreenList

@Composable
fun PrivacyScreen(onBack: () -> Unit, vm: SettingsViewModel = hiltViewModel()) {
    val c = DiTheme.colors
    val message by vm.message.collectAsStateWithLifecycle()
    ScreenList(title = "Privacidade e dados", onBack = onBack) {
        item {
            Group("Como a leitura funciona") {
                Bullet("A tela é capturada apenas enquanto o assistente está ativo e com a sua autorização explícita (o Android pede a cada início).")
                Bullet("O reconhecimento de texto roda no próprio aparelho (ML Kit com modelo embarcado). Nenhuma imagem sai do celular.")
                Bullet("Imagens de tela nunca são gravadas. Cada frame é descartado logo após a leitura.")
                Bullet("O app não usa APIs privadas da Uber, não usa serviço de acessibilidade e nunca toca na tela: não aceita nem recusa corridas.")
            }
        }
        item {
            Group("O que é armazenado (somente neste aparelho)") {
                Bullet("Veículos: consumo, preço do combustível e custos por km que você informou.")
                Bullet("Ofertas analisadas: valores, distâncias, tempos, indicadores calculados, classificação e confiança da leitura. Endereços aparecem apenas se exibidos na oferta.")
                Bullet("Corridas realizadas: as que você registrou, com os mesmos indicadores e observações.")
                Bullet("Sessões do assistente: horários de início e fim, para calcular o tempo online.")
                Bullet("Preferências: metas, critérios, posição e aparência da janela flutuante.")
                Bullet("Backup automático do Android está desativado para estes dados.")
            }
        }
        item {
            Group("Controle dos dados") {
                Text("Ofertas não registradas como corrida podem ser removidas periodicamente.", style = MaterialTheme.typography.bodySmall, color = c.textSecondary)
                SecondaryButton("Remover ofertas com mais de 30 dias", { vm.purgeOffers(30) }, Modifier.fillMaxWidth())
                Text("Para apagar tudo, use \"Limpar armazenamento\" nas informações do app no Android.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
            }
        }
        message?.let { m -> item { Banner(m, c.positive) } }
    }
}

@Composable
private fun Bullet(text: String) {
    val c = DiTheme.colors
    Text("•  $text", style = MaterialTheme.typography.bodyMedium, color = c.textSecondary)
}
