package com.driverintelligence.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.driverintelligence.MainActivity
import com.driverintelligence.R

object CaptureNotifications {
    const val CHANNEL_ID = "capture"
    const val NOTIFICATION_ID = 41

    fun createChannel(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_capture),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.notification_channel_capture_desc)
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    fun build(context: Context, paused: Boolean, detail: String? = null): Notification {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        fun service(action: String, code: Int) = PendingIntent.getService(
            context,
            code,
            Intent(context, CaptureService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val toggle = if (paused) {
            NotificationCompat.Action(R.drawable.ic_play, context.getString(R.string.action_resume), service(CaptureService.ACTION_RESUME, 2))
        } else {
            NotificationCompat.Action(R.drawable.ic_pause, context.getString(R.string.action_pause), service(CaptureService.ACTION_PAUSE, 1))
        }
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bolt)
            .setContentTitle(context.getString(if (paused) R.string.notification_title_paused else R.string.notification_title_running))
            .setContentText(detail ?: context.getString(R.string.notification_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(toggle)
            .addAction(NotificationCompat.Action(R.drawable.ic_minimize, context.getString(R.string.action_stop), service(CaptureService.ACTION_STOP, 3)))
            .build()
    }
}
