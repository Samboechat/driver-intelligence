package com.driverintelligence.capture

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.driverintelligence.permissions.Permissions

/**
 * Activity transparente que solicita o consentimento do sistema para captura de tela.
 * O consentimento é pedido a cada início (exigência do Android 14+: o token é de uso único).
 */
class CaptureConsentActivity : ComponentActivity() {

    private val launcher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val data = result.data
        if (result.resultCode == Activity.RESULT_OK && data != null) {
            val intent = Intent(this, CaptureService::class.java)
                .setAction(CaptureService.ACTION_START)
                .putExtra(CaptureService.EXTRA_RESULT_CODE, result.resultCode)
                .putExtra(CaptureService.EXTRA_RESULT_DATA, data)
            ContextCompat.startForegroundService(this, intent)
        } else {
            Toast.makeText(this, "Captura não autorizada. Você ainda pode analisar ofertas manualmente.", Toast.LENGTH_LONG).show()
        }
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "Autorize a sobreposição para exibir a análise sobre o Uber Driver.", Toast.LENGTH_LONG).show()
            startActivity(Permissions.overlaySettingsIntent(this))
            finish()
            return
        }
        if (savedInstanceState != null) return
        val mpm = getSystemService(MediaProjectionManager::class.java)
        val captureIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Tela inteira: o overlay é mascarado antes do OCR e a leitura não depende de escolher o app certo.
            mpm.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            mpm.createScreenCaptureIntent()
        }
        launcher.launch(captureIntent)
    }
}
