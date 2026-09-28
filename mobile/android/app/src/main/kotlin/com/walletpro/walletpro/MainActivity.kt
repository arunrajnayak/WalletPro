package com.walletpro.walletpro

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val SMS_CHANNEL = "com.walletpro/sms"
    private val NOTIF_CHANNEL = "com.walletpro/notifications"
    private val SMS_PERMISSION_REQ_CODE = 201
    private val POST_NOTIF_PERMISSION_REQ_CODE = 202

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPostNotifResult: MethodChannel.Result? = null

    private var transactionReceiver: BroadcastReceiver? = null
    private var notifMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ensure 4-hour review reminder alarm is scheduled
        ReviewReminderReceiver.scheduleAlarm(this)

        // 1. SMS Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSmsPermission" -> {
                    val hasPerm = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_SMS
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(hasPerm)
                }
                "requestSmsPermission" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
                            SMS_PERMISSION_REQ_CODE
                        )
                    }
                }
                "readInbox" -> {
                    val sinceMillis = (call.argument<Number>("sinceMillis"))?.toLong() ?: 0L
                    val limit = (call.argument<Number>("limit"))?.toInt() ?: 300

                    try {
                        val messages = readSmsMessages(sinceMillis, limit)
                        result.success(messages)
                    } catch (e: Exception) {
                        result.error("READ_SMS_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. Notifications & Reminders Method Channel
        notifMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "updatePendingCount" -> {
                        val count = (call.argument<Number>("count"))?.toLong() ?: 0L
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        prefs.edit().putLong("flutter.pending_count", count).apply()
                        result.success(true)
                    }
                    "scheduleReviewReminder" -> {
                        ReviewReminderReceiver.scheduleAlarm(this@MainActivity)
                        result.success(true)
                    }
                    "isNotificationListenerEnabled" -> {
                        val enabledPackages = NotificationManagerCompat.getEnabledListenerPackages(this@MainActivity)
                        result.success(enabledPackages.contains(packageName))
                    }
                    "openNotificationListenerSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_OPEN_FAILED", e.localizedMessage, null)
                        }
                    }
                    "requestPostNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            if (ContextCompat.checkSelfPermission(this@MainActivity, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                                result.success(true)
                            } else {
                                pendingPostNotifResult = result
                                ActivityCompat.requestPermissions(
                                    this@MainActivity,
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    POST_NOTIF_PERMISSION_REQ_CODE
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    "getInitialRoute" -> {
                        val route = intent?.getStringExtra("route")
                        result.success(route)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // 3. Register local broadcast receiver for real-time transactions
        transactionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == SmsReceiver.ACTION_NEW_TRANSACTION) {
                    val sender = intent.getStringExtra("sender") ?: ""
                    notifMethodChannel?.invokeMethod("onNewTransactionReceived", mapOf("sender" to sender))
                }
            }
        }
        val filter = IntentFilter(SmsReceiver.ACTION_NEW_TRANSACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(transactionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(transactionReceiver, filter)
        }
    }

    override fun onDestroy() {
        transactionReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    private fun readSmsMessages(sinceMillis: Long, limit: Int): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("_id", "address", "body", "date")

        val selection = if (sinceMillis > 0) "date >= ?" else null
        val selectionArgs = if (sinceMillis > 0) arrayOf(sinceMillis.toString()) else null

        val cursor = contentResolver.query(
            uri,
            projection,
            selection,
            selectionArgs,
            "date DESC"
        )

        cursor?.use {
            val idCol = it.getColumnIndex("_id")
            val bodyCol = it.getColumnIndex("body")
            val dateCol = it.getColumnIndex("date")
            val addrCol = it.getColumnIndex("address")

            var count = 0
            while (it.moveToNext() && count < limit) {
                val id = if (idCol >= 0) it.getString(idCol) ?: "" else ""
                val body = if (bodyCol >= 0) it.getString(bodyCol) ?: "" else ""
                val date = if (dateCol >= 0) it.getLong(dateCol) else 0L
                val address = if (addrCol >= 0) it.getString(addrCol) ?: "" else ""

                if (body.isNotBlank()) {
                    list.add(
                        mapOf(
                            "id" to id,
                            "body" to body,
                            "date" to date,
                            "sender" to address
                        )
                    )
                    count++
                }
            }
        }
        return list
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        } else if (requestCode == POST_NOTIF_PERMISSION_REQ_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPostNotifResult?.success(granted)
            pendingPostNotifResult = null
        }
    }
}
