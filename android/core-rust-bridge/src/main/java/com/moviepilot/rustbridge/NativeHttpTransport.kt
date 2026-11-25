package com.moviepilot.rustbridge

import com.moviepilot.rustcore.SseEventFfi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.Dispatcher
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/** 原生网络层响应快照。 */
data class NativeHttpResponse(
    val status: Int,
    val body: String,
    val headers: Map<String, String>,
)

/** 轻量线程安全内存 CookieJar：保存服务端同源短效资源 Cookie（如 MoviePilot 图片代理 Cookie）。 */
private class InMemoryCookieJar : CookieJar {
    private val store = ConcurrentHashMap<String, MutableList<Cookie>>()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        if (cookies.isEmpty()) return
        val list = store.computeIfAbsent(url.host) { mutableListOf() }
        synchronized(list) {
            cookies.forEach { incoming ->
                list.removeAll { it.name == incoming.name && it.path == incoming.path }
                if (incoming.expiresAt > System.currentTimeMillis()) {
                    list.add(incoming)
                }
            }
        }
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val list = store[url.host] ?: return emptyList()
        val now = System.currentTimeMillis()
        return synchronized(list) {
            list.removeAll { it.expiresAt <= now }
            list.filter { it.matches(url) }
        }
    }

    fun clear() {
        store.clear()
    }
}

/**
 * ADR-01 Android 原生网络传输实现：基于 OkHttp 完整尊重系统代理、VPN 与自签名证书选项，
 * 保存服务端短效资源 Cookie 供图片代理复用，并严格禁止携带认证头的跨源重定向。
 */
class NativeHttpTransport(
    private val allowSelfSignedTls: () -> Boolean = { false },
    @Volatile var onAuthClassified: ((decision: String, status: Int, body: String) -> Unit)? = null,
) {
    private val cookieJar = InMemoryCookieJar()
    private val defaultClient: OkHttpClient = buildClient(trustAll = false)
    private val selfSignedClient: OkHttpClient by lazy { buildClient(trustAll = true) }

    private fun client(): OkHttpClient =
        if (allowSelfSignedTls()) selfSignedClient else defaultClient

    private fun notifyAuthDecision(token: String?, status: Int, body: String): String {
        val decision = RustCoreBridge.classifyAuthStatus(status, body)
        if (!token.isNullOrBlank() && decision != "valid") {
            onAuthClassified?.invoke(decision, status, body)
        }
        return decision
    }

    fun clearCookies() {
        cookieJar.clear()
    }

    /** 导出当前同源内存 Cookie 列表（供 Media3 播放请求与 Vue 插件隔离容器复用，不跨源泄漏）。 */
    fun exportCookieHeader(rawUrl: String): String {
        val parsed = rawUrl.toHttpUrlOrNull() ?: return ""
        return cookieJar.loadForRequest(parsed).joinToString("; ") { "${it.name}=${it.value}" }
    }

    /** 导出单条 `Set-Cookie` 格式字符串列表（供 WebView `CookieManager.setCookie` 逐条写入）。 */
    fun exportSetCookieEntries(rawUrl: String): List<String> {
        val parsed = rawUrl.toHttpUrlOrNull() ?: return emptyList()
        return cookieJar.loadForRequest(parsed).map { c ->
            "${c.name}=${c.value}; Path=${c.path.ifBlank { "/" }}"
        }
    }

    /** 流式下载大体积媒体文件至受管缓存文件，避免 OOM，供存储文件原生直放。 */
    suspend fun downloadToFile(
        url: String,
        method: String = "POST",
        token: String? = null,
        body: String? = null,
        destFile: File,
        contentType: String = "application/json; charset=utf-8",
    ): Boolean = withContext(Dispatchers.IO) {
        val reqBuilder = Request.Builder().url(url)
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        val reqBody = body?.toRequestBody(contentType.toMediaType())
        when (method.uppercase()) {
            "POST" -> reqBuilder.post(reqBody ?: "".toRequestBody(contentType.toMediaType()))
            else -> reqBuilder.get()
        }
        val dlClient = client().newBuilder().readTimeout(120, TimeUnit.SECONDS).build()
        dlClient.newCall(reqBuilder.build()).execute().use { resp ->
            if (!resp.isSuccessful) {
                val errBody = resp.body?.string().orEmpty()
                notifyAuthDecision(token, resp.code, errBody)
                return@use false
            }
            val stream = resp.body?.byteStream() ?: return@use false
            destFile.parentFile?.mkdirs()
            destFile.outputStream().use { out ->
                stream.copyTo(out, bufferSize = 32 * 1024)
            }
            destFile.length() > 0L
        }
    }

    /** 构造专供 Coil 复用的同源鉴权高并发图片加载 OkHttpClient（绝不向第三方域名泄漏 Bearer 令牌）。 */
    fun buildImageClient(
        serverUrlProvider: () -> String?,
        tokenProvider: () -> String?,
    ): OkHttpClient {
        val imageDispatcher = Dispatcher().apply {
            maxRequests = 48
            maxRequestsPerHost = 16
        }
        return client().newBuilder()
            .dispatcher(imageDispatcher)
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(25, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .addInterceptor { chain ->
                val original = chain.request()
                val reqUrl = original.url.toString()
                val server = serverUrlProvider()
                val token = tokenProvider()
                val isSameOrigin = !server.isNullOrBlank() && RustCoreBridge.containsUrl(server, reqUrl)
                val nextReq = if (isSameOrigin && !token.isNullOrBlank()) {
                    original.newBuilder().header("Authorization", "Bearer $token").build()
                } else {
                    original
                }
                chain.proceed(nextReq)
            }
            .build()
    }

    private fun buildClient(trustAll: Boolean): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            // 严格对齐安全红线：禁止自动跟随可能泄漏凭据的重定向
            .followRedirects(false)
            .followSslRedirects(false)

        if (trustAll) {
            val tm = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val ssl = SSLContext.getInstance("TLS").apply {
                init(null, arrayOf<TrustManager>(tm), SecureRandom())
            }
            builder.sslSocketFactory(ssl.socketFactory, tm)
            builder.hostnameVerifier { _, _ -> true }
        }
        return builder.build()
    }

    /** 执行常规 REST JSON/Form 请求。 */
    suspend fun execute(
        url: String,
        method: String = "GET",
        token: String? = null,
        body: String? = null,
        contentType: String = "application/json; charset=utf-8",
        extraHeaders: Map<String, String> = emptyMap(),
    ): NativeHttpResponse = withContext(Dispatchers.IO) {
        val reqBuilder = Request.Builder().url(url)
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        extraHeaders.forEach { (k, v) -> reqBuilder.header(k, v) }
        val requestBody = body?.toRequestBody(contentType.toMediaType())
        when (method.uppercase()) {
            "GET" -> reqBuilder.get()
            "POST" -> reqBuilder.post(requestBody ?: "".toRequestBody(contentType.toMediaType()))
            "PUT" -> reqBuilder.put(requestBody ?: "".toRequestBody(contentType.toMediaType()))
            "DELETE" -> if (requestBody != null) reqBuilder.delete(requestBody) else reqBuilder.delete()
            "PATCH" -> reqBuilder.patch(requestBody ?: "".toRequestBody(contentType.toMediaType()))
            else -> reqBuilder.method(method.uppercase(), requestBody)
        }
        client().newCall(reqBuilder.build()).execute().use { resp ->
            val headersMap = resp.headers.names().associateWith { resp.headers[it].orEmpty() }
            val bodyText = resp.body?.string().orEmpty()
            notifyAuthDecision(token, resp.code, bodyText)
            NativeHttpResponse(
                status = resp.code,
                body = bodyText,
                headers = headersMap,
            )
        }
    }

    /** 执行 Multipart 文件/图片/语音上传请求。 */
    suspend fun uploadMultipart(
        url: String,
        token: String?,
        fieldName: String,
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        formFields: Map<String, String> = emptyMap(),
    ): NativeHttpResponse = withContext(Dispatchers.IO) {
        val bodyBuilder = okhttp3.MultipartBody.Builder()
            .setType(okhttp3.MultipartBody.FORM)
        formFields.forEach { (k, v) -> bodyBuilder.addFormDataPart(k, v) }
        bodyBuilder.addFormDataPart(
            fieldName,
            fileName,
            bytes.toRequestBody(mimeType.toMediaType()),
        )
        val reqBuilder = Request.Builder()
            .url(url)
            .post(bodyBuilder.build())
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        client().newBuilder().readTimeout(60, TimeUnit.SECONDS).writeTimeout(60, TimeUnit.SECONDS).build()
            .newCall(reqBuilder.build()).execute().use { resp ->
                val headersMap = resp.headers.names().associateWith { resp.headers[it].orEmpty() }
                val bodyText = resp.body?.string().orEmpty()
                notifyAuthDecision(token, resp.code, bodyText)
                NativeHttpResponse(
                    status = resp.code,
                    body = bodyText,
                    headers = headersMap,
                )
            }
    }

    /**
     * 建立 SSE 流式通道，使用 UTF-8 字符流按行解码避免多字节中文字符跨块截断为 U+FFFD，
     * 并在非 2xx 响应时触发 Rust 认证态分类后以 Kotlin `Flow` 向下游分发事件帧。
     */
    fun streamSse(
        url: String,
        token: String?,
        bodyJson: String? = null,
        extraHeaders: Map<String, String> = emptyMap(),
    ): Flow<SseEventFfi> = flow {
        val reqBuilder = Request.Builder()
            .url(url)
            .header("Accept", "text/event-stream")
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        extraHeaders.forEach { (k, v) -> reqBuilder.header(k, v) }
        if (bodyJson != null) {
            reqBuilder.post(bodyJson.toRequestBody("application/json; charset=utf-8".toMediaType()))
        } else {
            reqBuilder.get()
        }
        val streamClient = client().newBuilder().readTimeout(0, TimeUnit.SECONDS).build()
        val parser = RustCoreBridge.createSseParser()
        streamClient.newCall(reqBuilder.build()).execute().use { resp ->
            if (!resp.isSuccessful) {
                val errBody = resp.body?.string().orEmpty()
                val decision = notifyAuthDecision(token, resp.code, errBody)
                throw IllegalStateException(
                    if (decision == "logout") "登录状态已过期" else "SSE 流式连接失败 (HTTP ${resp.code})",
                )
            }
            val bodyStream = resp.body?.byteStream() ?: return@use
            BufferedReader(InputStreamReader(bodyStream, Charsets.UTF_8)).use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    for (ev in parser.pushChunk("$line\n")) {
                        emit(ev)
                    }
                }
            }
            for (ev in parser.finish()) {
                emit(ev)
            }
        }
    }.flowOn(Dispatchers.IO)
}
