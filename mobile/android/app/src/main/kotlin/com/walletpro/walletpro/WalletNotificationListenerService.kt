package com.walletpro.walletpro

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class WalletNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val pkgName = sbn.packageName ?: return
        val postTime = sbn.postTime

        // Ignore notifications posted prior to 1st September 2026
        if (postTime < TransactionParser.HARDCODED_START_MILLIS) return

        // Filter relevant apps: Messaging, UPI & Banking apps
        if (!isFinancialOrMessagingApp(pkgName)) return

        try {
            val extras = sbn.notification?.extras ?: return
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
            val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

            val combinedText = buildString {
                if (title.isNotEmpty()) append("$title: ")
                if (bigText.isNotEmpty()) append(bigText) else append(text)
            }

            if (combinedText.isBlank()) return

            val parsed = TransactionParser.parse(combinedText, postTime)
            if (parsed != null) {
                Log.d(TAG, "Financial notification detected from $pkgName: amount=${parsed["amount"]}")

                val sourceId = "notif_${pkgName.replace(".", "_")}_$postTime"
                TransactionParser.sendToBackendAsync(applicationContext, combinedText, postTime, sourceId, parsed)

                // Broadcast locally so running Flutter app can refresh state instantly
                val updateIntent = Intent(SmsReceiver.ACTION_NEW_TRANSACTION).apply {
                    setPackage(packageName)
                    putExtra("sender", pkgName)
                    putExtra("timestamp", postTime)
                }
                sendBroadcast(updateIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error inspecting notification: ${e.message}", e)
        }
    }

    private fun isFinancialOrMessagingApp(packageName: String): Boolean {
        val lower = packageName.lowercase()

        // Exclude SMS apps: real-time incoming SMS is already handled natively by SmsReceiver
        if (lower.contains("messaging") || lower.contains("mms") || lower.endsWith(".mms")) {
            return false
        }

        return lower.contains("paisa") || // Google Pay
                lower.contains("phonepe") ||
                lower.contains("paytm") ||
                lower.contains("cred") ||
                lower.contains("bhim") ||
                lower.contains("upi") ||
                lower.contains("hdfc") ||
                lower.contains("icici") ||
                lower.contains("sbi") ||
                lower.contains("axis") ||
                lower.contains("kotak") ||
                lower.contains("bank")
    }

    companion object {
        private const val TAG = "WalletNotifListener"
    }
}
