package com.moviepilot.pluginhost.runtime

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.HapticFeedbackConstants
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.moviepilot.pluginhost.VuePluginConfirmation
import com.moviepilot.pluginhost.VuePluginSessionPayload
import com.moviepilot.pluginhost.VuePluginSheetAction
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

data class AndroidPluginToast(
    val id: Long = System.nanoTime(),
    val level: String,
    val message: String,
)

/**
 * Android 端 `moviepilot.pluginHost` v2 双向桥接宿主：
 * 暴露 `window.__mpAndroidPluginHostV2.postMessage(json)`，严格对齐 `{ protocol, major: 2, type, payload }`
 * 与 `bridge.response` 协议，原生侧代发鉴权 `api.request`，彻底消除 WebView 内 Bearer Token 存储。
 */
class AndroidPluginHostBridgeV2(
    private val appContext: Context,
) {
    companion object {
        const val JS_INTERFACE_NAME = "__mpAndroidPluginHostV2"
        const val PROTOCOL = "moviepilot.pluginHost"
        const val PROTOCOL_MAJOR = 2
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val inFlightCalls = ConcurrentHashMap<String, Call>()

    private val okHttp = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .writeTimeout(35, TimeUnit.SECONDS)
        .followRedirects(false)
        .build()

    @Volatile
    var webView: WebView? = null

    @Volatile
    private var activeSession: VuePluginSessionPayload? = null

    val nativeCapabilities: AndroidPluginNativeCapabilities = AndroidPluginNativeCapabilities(
        appContext = appContext,
        okHttp = okHttp,
        executor = executor,
        sessionProvider = { activeSession },
        sendResponse = { requestId, ok, data, errorCode, errorStatus, errorMessage ->
            if (ok) {
                sendToWeb(
                    type = "bridge.response",
                    payload = buildJsonObject {
                        put("requestId", requestId)
                        put("ok", true)
                        put("data", data ?: JsonObject(emptyMap()))
                    },
                )
            } else {
                sendApiError(requestId, errorStatus, errorCode ?: "NATIVE_ERROR", errorMessage ?: "Native capability failed")
            }
        },
        sendDeviceEvent = { event, data ->
            sendToWeb(
                type = "device.event",
                payload = buildJsonObject {
                    put("event", event)
                    put("data", data)
                },
            )
        },
    )

    var onShellReady: (() -> Unit)? = null
    var onPluginMounted: ((mountId: String, title: String) -> Unit)? = null
    var onPluginError: ((stage: String, message: String, recoverable: Boolean) -> Unit)? = null
    var onPluginClose: (() -> Unit)? = null
    var onHeaderUpdate: ((title: String, actions: List<VuePluginSheetAction>) -> Unit)? = null
    var onToast: ((AndroidPluginToast) -> Unit)? = null
    var onConfirm: ((VuePluginConfirmation) -> Unit)? = null
    var onOpenRoute: ((path: String) -> Unit)? = null

    fun updateSession(session: VuePluginSessionPayload?) {
        activeSession = session
    }

    fun clearCallbacks() {
        onShellReady = null
        onPluginMounted = null
        onPluginError = null
        onPluginClose = null
        onHeaderUpdate = null
        onToast = null
        onConfirm = null
        onOpenRoute = null
    }

    fun abortAllInFlightRequests() {
        val calls = inFlightCalls.values.toList()
        inFlightCalls.clear()
        calls.forEach { runCatching { it.cancel() } }
    }

    fun cleanupNativeCapabilities() {
        nativeCapabilities.cleanup()
    }

    // MARK: Host -> Web

    fun sendToWeb(type: String, payload: JsonObject = JsonObject(emptyMap())) {
        val envelope = buildJsonObject {
            put("protocol", PROTOCOL)
            put("major", PROTOCOL_MAJOR)
            put("type", type)
            put("payload", payload)
        }.toString()
        val script = "window.__mpPluginHostReceive && window.__mpPluginHostReceive($envelope);"
        mainHandler.post {
            webView?.evaluateJavascript(script, null)
        }
    }

    fun sendVisualTokens(tokens: AndroidPluginVisualTokens) {
        sendToWeb(
            type = "theme.update",
            payload = buildJsonObject { put("visualTokens", tokens.toJsonObject()) },
        )
    }

    fun sendLocale(locale: String) {
        sendToWeb(type = "locale.update", payload = buildJsonObject { put("locale", locale) })
    }

    fun sendHostAction(actionId: String) {
        sendToWeb(type = "host.action", payload = buildJsonObject { put("actionId", actionId) })
    }

    fun sendConfirmResult(id: String, confirmed: Boolean) {
        sendToWeb(
            type = "bridge.response",
            payload = buildJsonObject {
                put("requestId", id)
                put("ok", true)
                put("data", buildJsonObject { put("confirmed", confirmed) })
            },
        )
    }

    fun sendUnmount() {
        sendToWeb(type = "plugin.unmount")
    }

    fun sendNavBack() {
        sendToWeb(type = "nav.back")
    }

    // MARK: Web -> Host

    @JavascriptInterface
    fun postMessage(rawJson: String) {
        val envelope = runCatching { json.parseToJsonElement(rawJson).jsonObject }.getOrNull() ?: return
        if (envelope["protocol"]?.strOrNull() != PROTOCOL) return
        val type = envelope["type"]?.strOrNull() ?: return
        val payload = (envelope["payload"] as? JsonObject) ?: JsonObject(emptyMap())

        when (type) {
            "shell.ready" -> mainHandler.post { onShellReady?.invoke() }
            "plugin.mounted" -> {
                val mid = payload["mountId"]?.strOrNull().orEmpty()
                val title = payload["title"]?.strOrNull().orEmpty()
                mainHandler.post { onPluginMounted?.invoke(mid, title) }
            }
            "plugin.error" -> {
                val stage = payload["stage"]?.strOrNull() ?: "load"
                val msg = payload["message"]?.strOrNull() ?: "插件加载失败"
                val rec = (payload["recoverable"] as? JsonPrimitive)?.booleanOrNull ?: true
                mainHandler.post { onPluginError?.invoke(stage, msg, rec) }
            }
            "plugin.close" -> mainHandler.post { onPluginClose?.invoke() }
            "api.request" -> {
                val reqId = payload["requestId"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: return
                executor.execute { executeApiRequest(reqId, payload) }
            }
            "api.abort" -> {
                val targetId = payload["requestId"]?.strOrNull() ?: return
                inFlightCalls.remove(targetId)?.cancel()
            }
            "ui.toast" -> {
                val level = payload["level"]?.strOrNull() ?: "info"
                val msg = payload["message"]?.strOrNull().orEmpty()
                if (msg.isNotBlank()) {
                    mainHandler.post { onToast?.invoke(AndroidPluginToast(level = level, message = msg)) }
                }
            }
            "ui.confirm" -> {
                val confirmId = payload["requestId"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: return
                val item = VuePluginConfirmation(
                    id = confirmId,
                    title = payload["title"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: "请确认",
                    message = payload["message"]?.strOrNull().orEmpty(),
                    confirmText = payload["confirmText"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: "确定",
                    cancelText = payload["cancelText"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: "取消",
                    destructive = (payload["destructive"] as? JsonPrimitive)?.booleanOrNull ?: false,
                )
                mainHandler.post {
                    val handler = onConfirm
                    if (handler != null) handler(item) else sendConfirmResult(confirmId, false)
                }
            }
            "ui.header" -> {
                val title = payload["title"]?.strOrNull().orEmpty()
                val rawActions = (payload["actions"] as? JsonArray).orEmpty()
                val actions = rawActions.mapNotNull { el ->
                    val obj = el as? JsonObject ?: return@mapNotNull null
                    val aid = obj["id"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                    VuePluginSheetAction(
                        id = aid,
                        title = obj["label"]?.strOrNull() ?: obj["title"]?.strOrNull() ?: aid,
                        icon = obj["icon"]?.strOrNull(),
                        enabled = !((obj["disabled"] as? JsonPrimitive)?.booleanOrNull ?: false),
                    )
                }
                mainHandler.post { onHeaderUpdate?.invoke(title, actions) }
            }
            "nav.openRoute" -> {
                val route = payload["deepLink"]?.strOrNull() ?: payload["path"]?.strOrNull().orEmpty()
                if (route.isNotBlank()) {
                    mainHandler.post { onOpenRoute?.invoke(route) }
                }
            }
            "nav.openExternal" -> {
                val raw = payload["url"]?.strOrNull().orEmpty()
                if (raw.startsWith("http://", ignoreCase = true) || raw.startsWith("https://", ignoreCase = true)) {
                    mainHandler.post {
                        runCatching {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(raw)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            appContext.startActivity(intent)
                        }
                    }
                }
            }
            "device.haptic" -> {
                val style = payload["style"]?.strOrNull() ?: "light"
                mainHandler.post {
                    val constant = when (style) {
                        "heavy", "error" -> HapticFeedbackConstants.LONG_PRESS
                        else -> HapticFeedbackConstants.KEYBOARD_TAP
                    }
                    webView?.performHapticFeedback(constant)
                }
            }
            "device.clipboard" -> {
                val text = payload["text"]?.strOrNull() ?: return
                val reqId = payload["requestId"]?.strOrNull().orEmpty()
                mainHandler.post {
                    val cm = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                    cm?.setPrimaryClip(ClipData.newPlainText("MoviePilot", text))
                    if (reqId.isNotBlank()) {
                        sendToWeb(
                            type = "bridge.response",
                            payload = buildJsonObject {
                                put("requestId", reqId)
                                put("ok", true)
                                put("data", buildJsonObject { put("copied", true) })
                            },
                        )
                    }
                }
            }
            else -> {
                val reqId = payload["requestId"]?.strOrNull().orEmpty()
                nativeCapabilities.handle(type, reqId, payload)
            }
        }
    }

    private fun executeApiRequest(requestId: String, payload: JsonObject) {
        val rawPath = payload["path"]?.strOrNull()
        if (rawPath.isNullOrBlank()) {
            sendApiError(requestId, 400, "INVALID_PATH", "Missing request path")
            return
        }
        val normalizedPath = RustCoreBridge.validatePluginApiPath(rawPath)
        if (normalizedPath == null) {
            sendApiError(requestId, 403, "FORBIDDEN_PATH", "Blocked unsafe API path")
            return
        }
        val session = activeSession
        if (session == null) {
            sendApiError(requestId, 401, "NO_SESSION", "No active session")
            return
        }
        val method = (payload["method"]?.strOrNull() ?: "GET").uppercase()
        if (method !in setOf("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD")) {
            sendApiError(requestId, 405, "METHOD_NOT_ALLOWED", "Unsupported HTTP method")
            return
        }

        val url = buildFullApiUrl(session.serverUrl.trimEnd('/'), normalizedPath, payload["query"] as? JsonObject)
        val reqBuilder = Request.Builder().url(url)
        val customHeaders = payload["headers"] as? JsonObject
        var explicitContentType: String? = null
        customHeaders?.forEach { (k, v) ->
            val lower = k.lowercase()
            if (lower != "authorization" && lower != "cookie" && lower != "host") {
                val value = v.strOrNull().orEmpty()
                if (lower == "content-type") explicitContentType = value
                reqBuilder.header(k, value)
            }
        }
        reqBuilder.header("Authorization", "Bearer ${session.authToken}")
        reqBuilder.header("X-MoviePilot-Locale", "zh-CN")
        val cookieHeader = session.originCookies
            .mapNotNull { it.substringBefore(';').trim().takeIf(String::isNotEmpty) }
            .joinToString("; ")
        if (cookieHeader.isNotEmpty()) {
            reqBuilder.header("Cookie", cookieHeader)
        }

        val body: RequestBody? = buildRequestBody(method, payload, explicitContentType)
        reqBuilder.method(method, body)

        val timeoutMs = ((payload["timeoutMs"] as? JsonPrimitive)?.doubleOrNull ?: 30_000.0)
            .toLong().coerceIn(3_000L, 120_000L)
        val client = if (timeoutMs != 35_000L) {
            okHttp.newBuilder().readTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
        } else {
            okHttp
        }
        val call = client.newCall(reqBuilder.build())
        inFlightCalls[requestId] = call
        val responseType = payload["responseType"]?.strOrNull() ?: "json"

        try {
            call.execute().use { resp ->
                val data = resp.body?.bytes() ?: ByteArray(0)
                val headersObj = buildJsonObject {
                    for (i in 0 until resp.headers.size) {
                        val name = resp.headers.name(i).lowercase()
                        if (name == "set-cookie" || name == "authorization") continue
                        put(name, resp.headers.value(i))
                    }
                }
                val (encoding, bodyEl) = decodeResponseBody(data, responseType)
                if (resp.isSuccessful) {
                    sendToWeb(
                        type = "bridge.response",
                        payload = buildJsonObject {
                            put("requestId", requestId)
                            put("ok", true)
                            put(
                                "data",
                                buildJsonObject {
                                    put("status", resp.code)
                                    put("headers", headersObj)
                                    put("bodyEncoding", encoding)
                                    put("body", bodyEl)
                                },
                            )
                        },
                    )
                } else {
                    val errMsg = (bodyEl as? JsonObject)?.get("message")?.strOrNull()
                        ?: (bodyEl as? JsonObject)?.get("detail")?.strOrNull()
                        ?: "HTTP ${resp.code}"
                    sendToWeb(
                        type = "bridge.response",
                        payload = buildJsonObject {
                            put("requestId", requestId)
                            put("ok", false)
                            put(
                                "error",
                                buildJsonObject {
                                    put("code", "HTTP_${resp.code}")
                                    put("status", resp.code)
                                    put("message", errMsg)
                                    put("data", bodyEl)
                                },
                            )
                        },
                    )
                }
            }
        } catch (e: Exception) {
            if (!call.isCanceled()) {
                sendApiError(requestId, 0, "NETWORK_ERROR", e.message ?: "Network error")
            }
        } finally {
            inFlightCalls.remove(requestId)
        }
    }

    private fun buildRequestBody(
        method: String,
        payload: JsonObject,
        explicitContentType: String?,
    ): RequestBody? {
        if (method == "GET" || method == "HEAD") return null
        val encoding = payload["bodyEncoding"]?.strOrNull().orEmpty()
        return when (encoding) {
            "json" -> {
                val raw = payload["body"]?.let { el ->
                    if (el is JsonPrimitive && el.isString) el.content else el.toString()
                } ?: "{}"
                raw.toRequestBody((explicitContentType ?: "application/json; charset=utf-8").toMediaTypeOrNull())
            }
            "text" -> {
                val raw = payload["body"]?.strOrNull().orEmpty()
                raw.toRequestBody((explicitContentType ?: "text/plain; charset=utf-8").toMediaTypeOrNull())
            }
            "base64" -> {
                val b64 = payload["body"]?.strOrNull().orEmpty()
                val bytes = runCatching { Base64.decode(b64, Base64.DEFAULT) }.getOrDefault(ByteArray(0))
                bytes.toRequestBody((explicitContentType ?: "application/octet-stream").toMediaTypeOrNull())
            }
            "multipart" -> {
                val parts = (payload["body"] as? JsonArray).orEmpty()
                val mb = MultipartBody.Builder().setType(MultipartBody.FORM)
                parts.forEach { el ->
                    val obj = el as? JsonObject ?: return@forEach
                    val name = obj["name"]?.strOrNull() ?: return@forEach
                    val b64 = obj["base64"]?.strOrNull()
                    if (b64 != null) {
                        val filename = obj["filename"]?.strOrNull() ?: "upload.bin"
                        val ct = obj["contentType"]?.strOrNull() ?: "application/octet-stream"
                        val bytes = runCatching { Base64.decode(b64, Base64.DEFAULT) }.getOrDefault(ByteArray(0))
                        mb.addFormDataPart(name, filename, bytes.toRequestBody(ct.toMediaTypeOrNull()))
                    } else {
                        mb.addFormDataPart(name, obj["value"]?.strOrNull().orEmpty())
                    }
                }
                mb.build()
            }
            else -> ByteArray(0).toRequestBody(null)
        }
    }

    private fun decodeResponseBody(data: ByteArray, responseType: String): Pair<String, JsonElement> {
        if (responseType == "blob" || responseType == "arraybuffer") {
            return "base64" to JsonPrimitive(Base64.encodeToString(data, Base64.NO_WRAP))
        }
        val text = String(data, Charsets.UTF_8)
        if (responseType == "text") {
            return "text" to JsonPrimitive(text)
        }
        if (data.isEmpty()) return "json" to JsonNull
        val parsed = runCatching { json.parseToJsonElement(text) }.getOrNull()
        return if (parsed != null) "json" to parsed else "text" to JsonPrimitive(text)
    }

    private fun buildFullApiUrl(origin: String, normalizedPath: String, extraQuery: JsonObject?): String {
        if (extraQuery == null || extraQuery.isEmpty()) return "$origin$normalizedPath"
        val pairs = mutableListOf<String>()
        for ((k, v) in extraQuery) {
            if (v is JsonNull) continue
            val ek = URLEncoder.encode(k, "UTF-8")
            when (v) {
                is JsonArray -> v.jsonArray.forEach { item ->
                    pairs += "$ek=${URLEncoder.encode(item.strOrNull().orEmpty(), "UTF-8")}"
                }
                else -> pairs += "$ek=${URLEncoder.encode(v.strOrNull().orEmpty(), "UTF-8")}"
            }
        }
        if (pairs.isEmpty()) return "$origin$normalizedPath"
        val sep = if ('?' in normalizedPath) "&" else "?"
        return "$origin$normalizedPath$sep${pairs.joinToString("&")}"
    }

    private fun sendApiError(requestId: String, status: Int, code: String, message: String) {
        sendToWeb(
            type = "bridge.response",
            payload = buildJsonObject {
                put("requestId", requestId)
                put("ok", false)
                put(
                    "error",
                    buildJsonObject {
                        put("code", code)
                        put("status", status)
                        put("message", message)
                    },
                )
            },
        )
    }

    private fun JsonElement.strOrNull(): String? = when (this) {
        is JsonNull -> null
        is JsonPrimitive -> content.takeIf { it != "null" }
        else -> toString()
    }
}
