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
    private val TYPE_REGEX = Pattern.compile(
        "\\b(debited|credited|spent|withdrawn|transferred|deposited|sent|received|paid|payment|order\\s+placed|order\\s+confirmed|placed|refund(?:ed|\\s+processed|\\s+initiated|\\s+of)?|cashback(?:\\s+received|\\s+credited)?|added|recharge\\s+successful|bill\\s+payment(?:\\s+successful)?)\\b",
        Pattern.CASE_INSENSITIVE
    )
    private val ACCOUNT_REGEX = Pattern.compile("(?:A\\/c|Acct|Card|a\\/c|account|ending\\s*in)\\s*(?:no\\.?|ending)?\\s*[*xX]*([0-9]{3,5})", Pattern.CASE_INSENSITIVE)
    private val UPI_REGEX = Pattern.compile("(?:UPI\\s*(?:Ref|ref)(?:\\s*(?:No|no)\\.?)?|Ref(?:\\s*(?:No|no)\\.?)?|UTR)[\\s:\\.\\-]*([0-9]{6,16})", Pattern.CASE_INSENSITIVE)
    private val AMAZON_ORDER_REGEX = Pattern.compile("(?:order\\s*(?:#|no\\.?|id)?\\s*|#\\s*)([0-9]{3}-[0-9]{7}-[0-9]{7})", Pattern.CASE_INSENSITIVE)
    private val MERCHANT_REGEX = Pattern.compile(
        "(?:to\\s+vpa|to|at|from)\\s+([A-Za-z0-9\\s\\.\\&\\*\\-]+?)(?:\\s+(?:on|via|using|for|with|UPI|Ref|avl|bal|date|limit|\\.|\\,)|$)",
        Pattern.CASE_INSENSITIVE
    )
    private val ORDER_ITEM_REGEX = Pattern.compile(
        "(?:order\\s+placed(?::|\\s+for)?|order\\s+of)\\s*(?:Rs\\.?|INR|₹)?\\s*[\\d,]+\\.?\\d*\\s+(?:for|of)\\s+([^\\.\\n,]+)",
        Pattern.CASE_INSENSITIVE
    )

    // Strict Anti-Spam / Promotional & Logistics filters
    private val SPAM_PROMO_REGEX = Pattern.compile(
        "\\b(deal|deals|discount|flat\\s*(?:rs\\.?|inr|₹)|win\\b|chance\\s+to\\s+win|up\\s+to\\s*(?:rs\\.?|inr|₹)|offer|offers|coupon|coupons|price\\s+drop|save\\s*(?:rs\\.?|inr|₹)|cashback\\s+on\\b|quiz|jackpot|lightning\\s+deal)\\b",
        Pattern.CASE_INSENSITIVE
    )
    private val CART_WISHLIST_REGEX = Pattern.compile(
        "\\b(items?\\s+in\\s+your\\s+cart|complete\\s+your\\s+(?:order|purchase)|continue\\s+shopping|wishlist|buy\\s+again|recommended\\s+for\\s+you)\\b",
        Pattern.CASE_INSENSITIVE
    )
    private val LOGISTICS_REGEX = Pattern.compile(
        "\\b(delivered\\b|dispatched\\b|shipped\\b|out\\s+for\\s+delivery|arriving\\s+(?:today|tomorrow|by)|track\\s+your\\s+package|handed\\s+to\\s+resident|delivery\\s+attempted|package\\s+arrived|rate\\s+your|review\\s+your|how\\s+was|share\\s+your\\s+feedback)\\b",
        Pattern.CASE_INSENSITIVE
    )

    fun parse(text: String, dateMillis: Long): Map<String, Any?>? {
        if (dateMillis < HARDCODED_START_MILLIS) {
            return null
        }

        // Filter out promotional marketing, cart reminders, and shipping/delivery alerts
        if (SPAM_PROMO_REGEX.matcher(text).find() ||
            CART_WISHLIST_REGEX.matcher(text).find() ||
            LOGISTICS_REGEX.matcher(text).find()) {
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
        val isCredit = matchedType in listOf("credited", "deposited", "added", "received", "refunded", "inward") ||
                matchedType.startsWith("cashback") ||
                matchedType.startsWith("refund")
        val transactionType = if (isCredit) "income" else "expense"

        val accountMatcher = ACCOUNT_REGEX.matcher(text)
        val accountLast4 = if (accountMatcher.find()) accountMatcher.group(1) else null

        val upiMatcher = UPI_REGEX.matcher(text)
        val amazonOrderMatcher = AMAZON_ORDER_REGEX.matcher(text)
        val referenceNumber = when {
            upiMatcher.find() -> upiMatcher.group(1)
            amazonOrderMatcher.find() -> amazonOrderMatcher.group(1)
            else -> null
        }

        val lowerText = text.lowercase(Locale.ROOT)
        val isAmazonText = lowerText.contains("amazon")

        val merchantMatcher = MERCHANT_REGEX.matcher(text)
        var counterParty = if (merchantMatcher.find()) merchantMatcher.group(1)?.trim() else null
        var note: String? = null

        // Amazon-specific merchant, note, and counterparty heuristics
        if (isAmazonText) {
            val orderItemMatcher = ORDER_ITEM_REGEX.matcher(text)
            if (orderItemMatcher.find()) {
                val rawItem = orderItemMatcher.group(1)?.trim() ?: ""
                val cleanItem = rawItem.replace(Regex("(?i)\\s+(?:has\\s+been\\s+placed|is\\s+confirmed|placed|confirmed)$"), "").trim()
                if (cleanItem.isNotEmpty()) {
                    note = "Order: $cleanItem"
                }
            }

            if (lowerText.contains("order placed") || lowerText.contains("order confirmed") || lowerText.contains("your order of")) {
                counterParty = "Amazon"
            } else if (lowerText.contains("cashback")) {
                counterParty = "Amazon Pay Cashback"
            } else if (lowerText.contains("refund")) {
                counterParty = "Amazon Refund"
            } else if (lowerText.contains("bill payment")) {
                val billerMatch = Pattern.compile("(?:for|to)\\s+([A-Za-z0-9\\s\\-]+?)(?:\\s+(?:bill|successful)|$)", Pattern.CASE_INSENSITIVE).matcher(text)
                counterParty = if (billerMatch.find()) billerMatch.group(1)?.trim() else "Amazon Pay Bill Payment"
                note = "Bill Payment: $counterParty"
            } else if (lowerText.contains("recharge")) {
                val mobileMatch = Pattern.compile("(?:for|mobile)\\s*([0-9]{10})", Pattern.CASE_INSENSITIVE).matcher(text)
                val target = if (mobileMatch.find()) mobileMatch.group(1) else null
                counterParty = "Amazon Pay Recharge"
                note = if (target != null) "Recharge: $target" else "Mobile Recharge"
            }
        }

        if (counterParty != null && (counterParty.equals("vpa", ignoreCase = true) || counterParty.equals("amazon pay upi", ignoreCase = true))) {
            counterParty = if (isAmazonText) "Amazon" else null
        }

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
            "note" to note,
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
