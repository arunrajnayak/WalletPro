package com.walletpro.walletpro

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isNullOrEmpty()) return

            val sender = messages[0].originatingAddress ?: "Unknown"
            val timestamp = messages[0].timestampMillis

            // Ignore messages prior to 1st September 2026
            if (timestamp < TransactionParser.HARDCODED_START_MILLIS) return

            val fullBody = StringBuilder()
            for (msg in messages) {
                fullBody.append(msg.messageBody)
            }
            val bodyText = fullBody.toString()

            val parsed = TransactionParser.parse(bodyText, timestamp)
            if (parsed != null) {
                Log.d(TAG, "Financial SMS detected in real-time from $sender: amount=${parsed["amount"]}")

                val sourceId = "sms_${sender.replace("+", "")}_$timestamp"
                TransactionParser.sendToBackendAsync(context, bodyText, timestamp, sourceId, parsed)

                // Broadcast locally so running Flutter app can refresh state instantly
                val updateIntent = Intent(ACTION_NEW_TRANSACTION).apply {
                    setPackage(context.packageName)
                    putExtra("sender", sender)
                    putExtra("timestamp", timestamp)
                }
                context.sendBroadcast(updateIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling incoming SMS: ${e.message}", e)
        }
    }

    companion object {
        private const val TAG = "SmsReceiver"
        const val ACTION_NEW_TRANSACTION = "com.walletpro.action.NEW_TRANSACTION"
    }
}
