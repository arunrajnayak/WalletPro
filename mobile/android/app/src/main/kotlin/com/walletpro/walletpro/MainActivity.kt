package com.walletpro.walletpro

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val SMS_CHANNEL = "com.walletpro/sms"
    private val NOTIF_CHANNEL = "com.walletpro/notifications"
    private val UPDATES_CHANNEL = "com.walletpro/updates"
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

        // 4. In-App Updates Method Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATES_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    try {
                        val pInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        val versionName = pInfo.versionName ?: "1.0.0"
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pInfo.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "versionName" to versionName,
                            "versionCode" to versionCode
                        ))
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.localizedMessage, null)
                    }
                }
                "getUpdateDirectory" -> {
                    try {
                        val baseDir = getExternalFilesDir(null) ?: cacheDir
                        val updateDir = File(baseDir, "updates")
                        if (!updateDir.exists()) {
                            updateDir.mkdirs()
                        }
                        result.success(updateDir.absolutePath)
                    } catch (e: Exception) {
                        result.error("DIR_ERROR", e.localizedMessage, null)
                    }
                }
                "canInstallUnknownApps" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.localizedMessage, null)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "filePath cannot be empty", null)
                        return@setMethodCallHandler
                    }
                    val apkFile = File(filePath)
                    if (!apkFile.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        return@setMethodCallHandler
                    }

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            val manageIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(manageIntent)
                            result.success(mapOf("status" to "permission_needed"))
                            return@setMethodCallHandler
                        }

                        val contentUri = FileProvider.getUriForFile(
                            this@MainActivity,
                            "${packageName}.fileprovider",
                            apkFile
                        )

                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(installIntent)
                        result.success(mapOf("status" to "installing"))
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.localizedMessage, null)
                    }
                }
                "showUpdateNotification" -> {
                    val version = call.argument<String>("version") ?: "New Version"
                    val notes = call.argument<String>("notes") ?: ""
                    showUpdateNotification(version, notes)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showUpdateNotification(version: String, notes: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "walletpro_updates"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "App Updates",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for new WalletPro app updates"
                enableLights(true)
                enableVibration(true)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("route", "/settings")
            putExtra("show_update_dialog", true)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            3001,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val cleanNotes = notes.lines().take(3).joinToString("\n").trim()

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("WalletPro $version Available")
            .setContentText("A new version is available. Tap to view and install.")
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                if (cleanNotes.isNotBlank()) "WalletPro $version is ready to install:\n$cleanNotes\n\nTap to download and update."
                else "WalletPro $version is available. Tap to download and install the latest update."
            ))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify(3001, notification)
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
