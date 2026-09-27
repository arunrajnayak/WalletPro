package com.walletpro.walletpro

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class TransactionNotificationService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val packageName = sbn?.packageName
        if (packageName == "com.google.android.apps.messaging") {
            val extras = sbn.notification.extras
            val text = extras.getCharSequence("android.text").toString()
            Log.d("WalletPro", "SMS Received: $text")
            // Send to Flutter via EventChannel/MethodChannel
        }
    }
}
