package com.moviepilot.app

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URI
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** 持久化匿名安装标识与 24 小时节流时间戳的轻量存储接口（便于单测注入内存实现）。 */
interface UsageReportStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun getLong(key: String): Long
    fun putLong(key: String, value: Long)
}

internal class SharedPrefsUsageReportStore(
    private val prefs: SharedPreferences,
) : UsageReportStore {
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun getLong(key: String): Long = prefs.getLong(key, 0L)
    override fun putLong(key: String, value: Long) {
        prefs.edit().putLong(key, value).apply()
    }
}

/**
 * Android 匿名安装版本统计上报器（1:1 对齐 iOS `UsageReporting`）：
 * - 仅在管理员所连接实例明确开启 `USAGE_STATISTIC_SHARE` 时调用；
 * - 使用与实例地址、账号、Token、推送标识完全隔离的随机 UUID 与独立无 Cookie HTTP 客户端；
 * - 按“统计服务 + 版本号”每 24 小时最多成功上报一次，失败不写节流标记，版本升级立即重报。
 */
class AppUsageReporter(
    private val store: UsageReportStore,
    private val sender: suspend (endpointUrl: String, payloadJson: String) -> Boolean = ::defaultPostUsageReport,
) {
    private val sending = AtomicBoolean(false)

    suspend fun report(
        enabled: Boolean,
        host: String,
        version: String,
        nowMs: Long = System.currentTimeMillis(),
    ): Boolean {
        if (!enabled) return false
        val cleanVersion = version.trim()
        if (cleanVersion.isEmpty()) return false
        val normalizedBase = normalizeHttpsBase(host) ?: return false
        val successKey = "moviepilot.usage.success.$normalizedBase.$cleanVersion"
        val previousMs = store.getLong(successKey)
        if (previousMs > 0L && nowMs >= previousMs && (nowMs - previousMs) < THROTTLE_WINDOW_MS) {
            return false
        }
        if (!sending.compareAndSet(false, true)) {
            return false
        }
        return try {
            val installationId = store.getString(INSTALLATION_ID_KEY)
                ?.takeIf { it.isNotBlank() }
                ?: UUID.randomUUID().toString().also { store.putString(INSTALLATION_ID_KEY, it) }
            val endpointUrl = "$normalizedBase/usage/android/report"
            val escapedVersion = cleanVersion.replace("\\", "\\\\").replace("\"", "\\\"")
            val payload = """{"installation_id":"$installationId","version":"$escapedVersion"}"""
            val ok = runCatching { sender(endpointUrl, payload) }.getOrDefault(false)
            if (ok) {
                store.putLong(successKey, nowMs)
            }
            ok
        } finally {
            sending.set(false)
        }
    }

    companion object {
        private const val PREF_NAME = "mp_usage_reporting_v1"
        private const val INSTALLATION_ID_KEY = "moviepilot.usage.installation"
        internal const val THROTTLE_WINDOW_MS = 86_400_000L

        @Volatile
        private var cachedInstance: AppUsageReporter? = null

        private val isolatedClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(15, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .followRedirects(false)
                .followSslRedirects(false)
                .build()
        }

        private val jsonParser = Json { ignoreUnknownKeys = true; isLenient = true }

        fun forContext(context: Context): AppUsageReporter {
            return cachedInstance ?: synchronized(this) {
                cachedInstance ?: AppUsageReporter(
                    store = SharedPrefsUsageReportStore(
                        context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE),
                    ),
                ).also { cachedInstance = it }
            }
        }

        /** 仅接受无内嵌凭据、无 query/fragment 的纯 HTTPS 统计服务基础地址。 */
        internal fun normalizeHttpsBase(rawHost: String): String? {
            val trimmed = rawHost.trim()
            if (trimmed.isEmpty()) return null
            val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
            if (!uri.scheme.equals("https", ignoreCase = true)) return null
            val host = uri.host?.takeIf { it.isNotBlank() } ?: return null
            if (!uri.rawUserInfo.isNullOrEmpty()) return null
            if (uri.rawQuery != null || uri.rawFragment != null) return null
            val portPart = if (uri.port in 1..65535 && uri.port != 443) ":${uri.port}" else ""
            val cleanPath = (uri.rawPath ?: "").trimEnd('/')
            return "https://${host.lowercase()}$portPart$cleanPath"
        }

        private suspend fun defaultPostUsageReport(endpointUrl: String, payloadJson: String): Boolean =
            withContext(Dispatchers.IO) {
                val request = Request.Builder()
                    .url(endpointUrl)
                    .header("Content-Type", "application/json")
                    .post(payloadJson.toRequestBody("application/json; charset=utf-8".toMediaType()))
                    .build()
                isolatedClient.newCall(request).execute().use { response ->
                    if (response.code != 200) return@withContext false
                    val bodyText = response.body?.string().orEmpty()
                    val code = runCatching {
                        jsonParser.parseToJsonElement(bodyText).jsonObject["code"]?.jsonPrimitive?.intOrNull
                    }.getOrNull()
                    code == 0
                }
            }
    }
}
