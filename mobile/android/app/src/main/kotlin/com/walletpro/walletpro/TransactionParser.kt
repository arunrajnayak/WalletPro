package com.walletpro.walletpro

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.regex.Pattern

object TransactionParser {
    private const val TAG = "TransactionParser"
    // Hardcoded start date: September 1, 2026 00:00:00 UTC (1788220800000L)
    const val HARDCODED_START_MILLIS = 1788220800000L

    private val AMOUNT_REGEX = Pattern.compile("(?:Rs\\.?|INR|₹)\\s*([\\d,]+\\.?\\d*)", Pattern.CASE_INSENSITIVE)
    private val TYPE_REGEX = Pattern.compile("\\b(debited|credited|spent|withdrawn|transferred|deposited|sent|received|paid)\\b", Pattern.CASE_INSENSITIVE)
    private val ACCOUNT_REGEX = Pattern.compile("(?:A\\/c|Acct|Card|a\\/c|account)\\s*(?:no\\.?|ending)?\\s*[*xX]*([0-9]{3,5})", Pattern.CASE_INSENSITIVE)
    private val UPI_REGEX = Pattern.compile("(?:UPI\\s*(?:Ref|ref)(?:\\s*(?:No|no)\\.?)?|Ref\\s*(?:No|no)\\.?|UTR)[\\s:\\.\\-]*([0-9]{6,16})", Pattern.CASE_INSENSITIVE)
    private val MERCHANT_REGEX = Pattern.compile("(?:to\\s+vpa|to|at)\\s+([A-Za-z0-9\\s\\.\\&\\*\\-]+?)(?:\\s+(?:on|via|UPI|Ref|avl|bal|using|date|\\.|\\,)|$)", Pattern.CASE_INSENSITIVE)

    fun parse(text: String, dateMillis: Long): Map<String, Any?>? {
        if (dateMillis < HARDCODED_START_MILLIS) {
            return null
        }

        val amountMatcher = AMOUNT_REGEX.matcher(text)
        val typeMatcher = TYPE_REGEX.matcher(text)

        if (!amountMatcher.find() || !typeMatcher.find()) {
            return null
        }

        val rawAmount = amountMatcher.group(1)?.replace(",", "") ?: return null
        val amount = rawAmount.toDoubleOrNull() ?: return null
        if (amount <= 0) return null

        val matchedType = typeMatcher.group(1)?.lowercase(Locale.ROOT) ?: ""
        val isCredit = matchedType in listOf("credited", "deposited", "added", "received")
        val transactionType = if (isCredit) "income" else "expense"

        val accountMatcher = ACCOUNT_REGEX.matcher(text)
        val accountLast4 = if (accountMatcher.find()) accountMatcher.group(1) else null

        val upiMatcher = UPI_REGEX.matcher(text)
        val referenceNumber = if (upiMatcher.find()) upiMatcher.group(1) else null

        val merchantMatcher = MERCHANT_REGEX.matcher(text)
        val counterParty = if (merchantMatcher.find()) merchantMatcher.group(1)?.trim() else null

        val isoDateFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val isoDate = isoDateFormatter.format(Date(dateMillis))

        return mapOf(
            "amount" to amount,
            "transactionType" to transactionType,
            "accountLast4" to accountLast4,
            "referenceNumber" to referenceNumber,
            "counterParty" to counterParty,
            "transactionDate" to isoDate,
            "rawText" to text
        )
    }

    /**
     * Posts parsed transaction directly to backend in background thread
     */
    fun sendToBackendAsync(
        context: Context,
        rawText: String,
        dateMillis: Long,
        sourceId: String?,
        parsed: Map<String, Any?>
    ) {
        Thread {
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val baseUrl = prefs.getString("flutter.backend_base_url", null)
                    ?: "https://walletpro-api.vercel.app" // fallback production API if set
                val apiKey = prefs.getString("flutter.api_key", null)

                val isoDateFormatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val isoDate = isoDateFormatter.format(Date(dateMillis))

                val parsedWithSource = parsed.toMutableMap().apply {
                    if (!sourceId.isNullOrEmpty()) {
                        put("sourceId", sourceId)
                    }
                }

                val payload = JSONObject().apply {
                    put("text", rawText)
                    put("date", isoDate)
                    put("source", "sms")
                    put("parsedData", JSONObject(parsedWithSource))
                }

                val url = URL("$baseUrl/api/suggestions")
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 8000
                    readTimeout = 8000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    if (!apiKey.isNullOrEmpty()) {
                        setRequestProperty("x-api-key", apiKey)
                    }
                }

                OutputStreamWriter(conn.outputStream).use { writer ->
                    writer.write(payload.toString())
                    writer.flush()
                }

                val responseCode = conn.responseCode
                Log.d(TAG, "Sent transaction to backend: HTTP $responseCode")

                // If created, increment pending count in local prefs for 4-hour reminder
                if (responseCode == 201) {
                    val currentCount = prefs.getLong("flutter.pending_count", 0L)
                    prefs.edit().putLong("flutter.pending_count", currentCount + 1).apply()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send transaction to backend: ${e.message}")
            }
        }.start()
    }
}
