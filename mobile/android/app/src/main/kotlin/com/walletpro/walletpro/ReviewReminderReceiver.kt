package com.walletpro.walletpro

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import java.util.concurrent.TimeUnit

class ReviewReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        if (action == Intent.ACTION_BOOT_COMPLETED || action == ACTION_CHECK_REVIEWS) {
            checkAndNotify(context)
            // Ensure next alarm is scheduled
            scheduleAlarm(context)
        }
    }

    private fun checkAndNotify(context: Context) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // Flutter SharedPreferences stores integers as Long or Int with 'flutter.' prefix
        val pendingCount = try {
            prefs.getLong("flutter.pending_count", -1L).takeIf { it >= 0 }?.toInt()
                ?: prefs.getInt("flutter.pending_count", 0)
        } catch (_: Exception) {
            try {
                prefs.getInt("flutter.pending_count", 0)
            } catch (_: Exception) {
                0
            }
        }

        if (pendingCount > 0) {
            showReminderNotification(context, pendingCount)
        }
    }

    private fun showReminderNotification(context: Context, pendingCount: Int) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Create Notification Channel for Android 8.0+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Review Reminders",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Periodic reminders for unreviewed transactions"
                enableLights(true)
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("route", "/review")
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            REQUEST_CODE_NOTIFICATION,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val transactionText = if (pendingCount == 1) "1 transaction" else "$pendingCount transactions"

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("WalletPro: Pending Reviews")
            .setContentText("You have $transactionText waiting for your review.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("You have $transactionText waiting for your review. Tap to categorize and sync to BudgetBakers Wallet."))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    companion object {
        const val ACTION_CHECK_REVIEWS = "com.walletpro.action.CHECK_REVIEWS"
        private const val CHANNEL_ID = "walletpro_reviews"
        private const val NOTIFICATION_ID = 1001
        private const val REQUEST_CODE_ALARM = 2001
        private const val REQUEST_CODE_NOTIFICATION = 2002
        private val INTERVAL_MILLIS = TimeUnit.HOURS.toMillis(4)

        fun scheduleAlarm(context: Context, intervalMillis: Long = INTERVAL_MILLIS) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, ReviewReminderReceiver::class.java).apply {
                action = ACTION_CHECK_REVIEWS
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                REQUEST_CODE_ALARM,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val triggerTime = SystemClock.elapsedRealtime() + intervalMillis

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    pendingIntent
                )
            } else {
                alarmManager.setInexactRepeating(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    triggerTime,
                    intervalMillis,
                    pendingIntent
                )
            }
        }
    }
}
