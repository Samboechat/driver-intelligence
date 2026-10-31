package com.driverintelligence.features.ocrlab

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.driverintelligence.data.repository.AnalysisContextProvider
import com.driverintelligence.designsystem.Banner
import com.driverintelligence.designsystem.DiCard
import com.driverintelligence.designsystem.DiTextField
import com.driverintelligence.designsystem.DiTheme
import com.driverintelligence.designsystem.InfoRow
import com.driverintelligence.designsystem.PrimaryButton
import com.driverintelligence.designsystem.SecondaryButton
import com.driverintelligence.domain.model.CaptureRegion
import com.driverintelligence.domain.recognition.FrameAnalysis
import com.driverintelligence.domain.recognition.OcrFrame
import com.driverintelligence.domain.recognition.OfferAnalyzer
import com.driverintelligence.domain.recognition.OfferTextParser
import com.driverintelligence.domain.recognition.ParseResult
import com.driverintelligence.domain.util.Br
import com.driverintelligence.features.common.AnalysisCard
import com.driverintelligence.features.common.ScreenList
import com.driverintelligence.recognition.ImagePreprocessor
import com.driverintelligence.recognition.OcrEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

data class OcrLabState(
    val pasted: String = "",
    val running: Boolean = false,
    val lines: List<String> = emptyList(),
    val parse: ParseResult? = null,
    val frame: FrameAnalysis? = null,
    val ocrMs: Long? = null,
    val imageSize: String? = null,
    val error: String? = null,
)

/**
 * Laboratório para validar o reconhecimento com capturas reais de ofertas (fornecidas pelo motorista)
 * ou texto colado — sem precisar estar dirigindo.
 */
@HiltViewModel
class OcrLabViewModel @Inject constructor(
    private val ocr: OcrEngine,
    private val analyzer: OfferAnalyzer,
    private val contextProvider: AnalysisContextProvider,
) : ViewModel() {
    private val _state = MutableStateFlow(OcrLabState())
    val state: StateFlow<OcrLabState> = _state.asStateFlow()
    private val parser = OfferTextParser()
    private val preprocessor = ImagePreprocessor()

    fun setPasted(text: String) = _state.update { it.copy(pasted = text) }

    fun analyzeText() = viewModelScope.launch {
        val frame = OcrFrame.fromText(_state.value.pasted)
        show(frame, ocrMs = null, size = null)
    }

    fun analyzeImage(resolver: ContentResolver, uri: Uri, enhance: Boolean) = viewModelScope.launch {
        _state.update { it.copy(running = true, error = null) }
        try {
            val bitmap = withContext(Dispatchers.IO) { decode(resolver, uri) }
            val prepared = withContext(Dispatchers.Default) { preprocessor.prepare(bitmap, CaptureRegion.FULL, null, enhance) }
            val t0 = SystemClock.elapsedRealtime()
            val frame = ocr.recognize(prepared.bitmap)
            show(frame, SystemClock.elapsedRealtime() - t0, "${bitmap.width}×${bitmap.height}")
        } catch (e: Exception) {
            _state.update { it.copy(running = false, error = "Não foi possível ler a imagem: ${e.message}") }
        }
    }

    private suspend fun show(frame: OcrFrame, ocrMs: Long?, size: String?) {
        val ctx = contextProvider.context.first()
        val parse = parser.parse(frame)
        val analysis = analyzer.analyzeFrame(frame, ctx)
        _state.update {
            it.copy(running = false, lines = frame.lines.map { l -> l.text }, parse = parse, frame = analysis, ocrMs = ocrMs, imageSize = size, error = null)
        }
    }

    private fun decode(resolver: ContentResolver, uri: Uri): Bitmap {
        val source = ImageDecoder.createSource(resolver, uri)
        return ImageDecoder.decodeBitmap(source) { decoder, _, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = true
        }
    }

    override fun onCleared() {
        ocr.close()
        preprocessor.release()
    }
}

@Composable
fun OcrLabScreen(onBack: () -> Unit, vm: OcrLabViewModel = hiltViewModel()) {
    val s by vm.state.collectAsStateWithLifecycle()
    val c = DiTheme.colors
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) vm.analyzeImage(context.contentResolver, uri, enhance = false)
    }
    val pickerEnhanced = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) vm.analyzeImage(context.contentResolver, uri, enhance = true)
    }

    ScreenList(title = "Laboratório de OCR", subtitle = "Teste com capturas reais de ofertas", onBack = onBack) {
        item {
            DiCard {
                Text(
                    "Tire um print de uma oferta no Uber Driver e selecione aqui. O mesmo pipeline do assistente é executado: OCR local → extração → validação → cálculo → classificação.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.textSecondary,
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton(
                    if (s.running) "Lendo…" else "Escolher captura de tela",
                    { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    Modifier.fillMaxWidth(),
                    enabled = !s.running,
                )
                Spacer(Modifier.height(8.dp))
                SecondaryButton(
                    "Escolher com realce de contraste",
                    { pickerEnhanced.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    Modifier.fillMaxWidth(),
                    enabled = !s.running,
                )
            }
        }
        item {
            DiCard {
                Text("Ou cole o texto de uma oferta", style = MaterialTheme.typography.titleSmall, color = c.textPrimary)
                Spacer(Modifier.height(8.dp))
                DiTextField("Texto", s.pasted, vm::setPasted, singleLine = false)
                Spacer(Modifier.height(8.dp))
                SecondaryButton("Analisar texto", { vm.analyzeText() }, Modifier.fillMaxWidth(), enabled = s.pasted.isNotBlank())
            }
        }
        s.error?.let { e -> item { Banner(e, c.negative) } }
        s.parse?.let { p ->
            item {
                DiCard {
                    Text("Extração", style = MaterialTheme.typography.titleMedium, color = c.textPrimary)
                    s.ocrMs?.let { InfoRow("Tempo de OCR", "$it ms", note = s.imageSize) }
                    InfoRow("Tela de oferta detectada", if (p.isOfferScreen) "sim" else "não", valueColor = if (p.isOfferScreen) c.positive else c.warning)
                    InfoRow("Confiança da leitura", Br.percent(p.confidence), valueColor = if (p.confidence >= 0.6) c.positive else c.warning)
                    InfoRow("Valor", Br.money(p.offer.fare))
                    InfoRow("Busca", "${Br.km(p.offer.pickupDistanceKm)} · ${Br.minutes(p.offer.pickupTimeMin)}")
                    InfoRow("Viagem", "${Br.km(p.offer.tripDistanceKm)} · ${Br.minutes(p.offer.tripTimeMin)}")
                    InfoRow("Categoria", p.offer.category ?: Br.DASH)
                    p.offer.surgeAmount?.let { InfoRow("Dinâmico/bônus", Br.money(it)) }
                    p.offer.origin?.let { InfoRow("Origem", it) }
                    p.offer.destination?.let { InfoRow("Destino", it) }
                    p.notes.forEach { n -> Text("• $n", style = MaterialTheme.typography.bodySmall, color = c.textTertiary) }
                    s.frame?.analysis?.validation?.issues?.filter { !it.message.startsWith("Não identificado") }?.forEach { i ->
                        Text("⚠ ${i.message}", style = MaterialTheme.typography.bodySmall, color = c.warning)
                    }
                }
            }
        }
        s.frame?.analysis?.let { a -> item { AnalysisCard(a) } }
        if (s.lines.isNotEmpty()) {
            item {
                DiCard {
                    Text("Texto reconhecido (${s.lines.size} linhas)", style = MaterialTheme.typography.titleSmall, color = c.textSecondary)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        s.lines.joinToString("\n"),
                        style = TextStyle(fontFamily = FontFamily.Monospace, fontSize = 12.sp, lineHeight = 16.sp, color = c.textPrimary),
                    )
                }
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                Text("Nenhuma imagem é salva. A captura escolhida é lida em memória e descartada.", style = MaterialTheme.typography.bodySmall, color = c.textTertiary)
            }
        }
    }
}
