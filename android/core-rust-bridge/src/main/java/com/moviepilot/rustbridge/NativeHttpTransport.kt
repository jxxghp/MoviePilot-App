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
    @Volatile var authFailureHandlerProvider: ((requestUrl: String, token: String) -> (() -> Unit)?)? = null,
    @Volatile var cfAccessTokenProvider: ((requestUrl: String) -> String?)? = null,
) {
    private val cookieJar = InMemoryCookieJar()
    private val defaultClient: OkHttpClient = buildClient(trustAll = false)
    private val selfSignedClient: OkHttpClient by lazy { buildClient(trustAll = true) }

    private fun client(): OkHttpClient =
        if (allowSelfSignedTls()) selfSignedClient else defaultClient

    /**
     * 仅为已授权同源请求合并 `Cookie: CF_Authorization=...`（保留 `resource_token`）与 `cf-access-token`；
     * 绝不触碰 `Authorization: Bearer`。
     */
    private fun applyCloudflareAccessHeaders(
        reqBuilder: Request.Builder,
        requestUrl: String,
        explicitCookieHeader: String? = null,
    ) {
        val cfToken = cfAccessTokenProvider?.invoke(requestUrl)?.trim().orEmpty()
        if (cfToken.isEmpty()) return
        val jarCookie = requestUrl.toHttpUrlOrNull()?.let { parsed ->
            cookieJar.loadForRequest(parsed).joinToString("; ") { "${it.name}=${it.value}" }
        }.orEmpty()
        val baseCookie = listOfNotNull(
            jarCookie.takeIf { it.isNotEmpty() },
            explicitCookieHeader?.takeIf { it.isNotBlank() },
        ).joinToString("; ")
        val merged = RustCoreBridge.mergeCloudflareAccessCookie(baseCookie, cfToken)
        if (merged.isNotEmpty()) {
            reqBuilder.header("Cookie", merged)
        }
        reqBuilder.header("cf-access-token", cfToken)
    }

    /** 只通知发起请求时捕获的会话，不能用返回响应时的新会话处理旧 401。 */
    private fun notifyAuthDecision(handler: (() -> Unit)?, status: Int, body: String): String {
        val decision = RustCoreBridge.classifyAuthStatus(status, body)
        if (decision == "logout") handler?.invoke()
        return decision
    }

    /** 发请求前固定失效处理器，登录或实例切换后由仓库判定是否仍有权注销。 */
    private fun authFailureHandler(url: String, token: String?): (() -> Unit)? =
        token?.takeIf { it.isNotBlank() }?.let { authFailureHandlerProvider?.invoke(url, it) }

    /** 释放当前会话短效资源 Cookie。 */
    fun clearCookies() {
        cookieJar.clear()
    }

    /** 导出当前同源内存 Cookie 列表（供 Media3 播放请求与 Vue 插件隔离容器复用，不跨源泄漏）。 */
    fun exportCookieHeader(rawUrl: String): String {
        val parsed = rawUrl.toHttpUrlOrNull() ?: return ""
        val base = cookieJar.loadForRequest(parsed).joinToString("; ") { "${it.name}=${it.value}" }
        val cfToken = cfAccessTokenProvider?.invoke(rawUrl)?.trim().orEmpty()
        return if (cfToken.isNotEmpty()) RustCoreBridge.mergeCloudflareAccessCookie(base, cfToken) else base
    }

    /** 导出单条 `Set-Cookie` 格式字符串列表（供 WebView `CookieManager.setCookie` 逐条写入）。 */
    fun exportSetCookieEntries(rawUrl: String): List<String> {
        val parsed = rawUrl.toHttpUrlOrNull() ?: return emptyList()
        val entries = cookieJar.loadForRequest(parsed).map { c ->
            "${c.name}=${c.value}; Path=${c.path.ifBlank { "/" }}"
        }.toMutableList()
        val cfToken = cfAccessTokenProvider?.invoke(rawUrl)?.trim().orEmpty()
        if (cfToken.isNotEmpty()) {
            entries.removeAll { it.startsWith("CF_Authorization=", ignoreCase = true) }
            entries.add("CF_Authorization=$cfToken; Path=/")
        }
        return entries
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
        val onAuthFailure = authFailureHandler(url, token)
        val reqBuilder = Request.Builder().url(url)
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        applyCloudflareAccessHeaders(reqBuilder, url)
        val reqBody = body?.toRequestBody(contentType.toMediaType())
        when (method.uppercase()) {
            "POST" -> reqBuilder.post(reqBody ?: "".toRequestBody(contentType.toMediaType()))
            else -> reqBuilder.get()
        }
        val dlClient = client().newBuilder().readTimeout(120, TimeUnit.SECONDS).build()
        dlClient.newCall(reqBuilder.build()).execute().use { resp ->
            if (!resp.isSuccessful) {
                val errBody = resp.body?.string().orEmpty()
                notifyAuthDecision(onAuthFailure, resp.code, errBody)
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

    /**
     * 构造专供 Coil 复用的同源鉴权高并发图片加载 OkHttpClient（绝不向第三方域名泄漏 Bearer 令牌）：
     * - 同源图片端点收到 401（短效资源 Cookie 未预热或已过期）时自动请求一次 `/api/v1/media/source` 续签并重试；
     * - 同源 `/plugin_icon/<file>` 在直连后端端口或前端静态目录缺失（404 / SPA HTML 回退）时，对齐 iOS 回退官方插件仓库图标，并在直连受限时继续复用后端代理；
     * - 未开启全局图片缓存时的公开外链直连若因手机网络受限失败，自动回退一次服务端代理（`/api/v1/system/img/1?cache=false`）。
     */
    fun buildImageClient(
        serverUrlProvider: () -> String?,
        tokenProvider: () -> String?,
        externalFallbackUrlProvider: ((externalUrl: String) -> String?)? = null,
        pluginIconFallbackUrlProvider: ((encodedFileName: String) -> String?)? = { encodedFileName ->
            "https://raw.githubusercontent.com/jxxghp/MoviePilot-Plugins/main/icons/$encodedFileName"
        },
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
                if (isSameOrigin) {
                    val firstResp = chain.proceed(original)
                    val isImageEndpoint = reqUrl.contains("/api/v1/system/img/") || reqUrl.contains("/api/v1/system/cache/image")
                    if (firstResp.code == 401 && isImageEndpoint && !server.isNullOrBlank() && !token.isNullOrBlank()) {
                        firstResp.close()
                        primeMediaSourceCookie(server, token)
                        return@addInterceptor chain.proceed(original)
                    }
                    val isHtmlSpaFallback = firstResp.isSuccessful &&
                        firstResp.header("Content-Type")?.lowercase()?.contains("text/html") == true
                    if (firstResp.code == 404 || isHtmlSpaFallback) {
                        val encodedIconName = extractSameOriginPluginIconEncodedName(server!!, original.url)
                        val fallbackExternalUrl = encodedIconName?.let { pluginIconFallbackUrlProvider?.invoke(it) }
                        if (!fallbackExternalUrl.isNullOrBlank()) {
                            firstResp.close()
                            val externalReq = original.newBuilder().url(fallbackExternalUrl).build()
                            return@addInterceptor executeExternalWithProxyFallback(
                                chain = chain,
                                request = externalReq,
                                reqUrl = fallbackExternalUrl,
                                server = server,
                                token = token,
                                externalFallbackUrlProvider = externalFallbackUrlProvider,
                                skipProxyOnNotFound = true,
                            )
                        }
                    }
                    return@addInterceptor firstResp
                }

                executeExternalWithProxyFallback(
                    chain = chain,
                    request = original,
                    reqUrl = reqUrl,
                    server = server,
                    token = token,
                    externalFallbackUrlProvider = externalFallbackUrlProvider,
                    skipProxyOnNotFound = false,
                )
            }
            // 网络拦截器每一跳执行；应用拦截器只执行首跳，无法隔离重定向凭据。
            .addNetworkInterceptor { chain ->
                val original = chain.request()
                val reqUrl = original.url.toString()
                val server = serverUrlProvider()
                val token = tokenProvider()
                val isSameOrigin = !server.isNullOrBlank() && RustCoreBridge.containsUrl(server, reqUrl)
                val nextReq = if (isSameOrigin) {
                    val rb = original.newBuilder()
                    if (!token.isNullOrBlank()) {
                        rb.header("Authorization", "Bearer $token")
                    }
                    applyCloudflareAccessHeaders(rb, reqUrl, original.header("Cookie"))
                    rb.build()
                } else {
                    original.newBuilder()
                        .removeHeader("Authorization")
                        .removeHeader("Cookie")
                        .removeHeader("cf-access-token")
                        .removeHeader("CF-Access-Client-Id")
                        .removeHeader("CF-Access-Client-Secret")
                        .build()
                }
                chain.proceed(nextReq)
            }
            .build()
    }

    /** 预热或续签同源短效媒体资源 Cookie（供 `/api/v1/system/img/` 与 `/system/cache/image` 401 自动重试使用）。 */
    private fun primeMediaSourceCookie(server: String, token: String) {
        runCatching {
            val primeUrl = "${server.trimEnd('/')}/api/v1/media/source"
            val primeBuilder = Request.Builder()
                .url(primeUrl)
                .header("Authorization", "Bearer $token")
                .header("Accept", "application/json")
            applyCloudflareAccessHeaders(primeBuilder, primeUrl)
            client().newCall(primeBuilder.build()).execute().close()
        }
    }

    /** 执行外部图片直连，失败时按配置回退至当前实例的服务端图片代理接口。 */
    private fun executeExternalWithProxyFallback(
        chain: okhttp3.Interceptor.Chain,
        request: Request,
        reqUrl: String,
        server: String?,
        token: String?,
        externalFallbackUrlProvider: ((externalUrl: String) -> String?)?,
        skipProxyOnNotFound: Boolean,
    ): okhttp3.Response {
        fun retryViaProxy(): okhttp3.Response {
            val fallbackUrl = externalFallbackUrlProvider?.invoke(reqUrl)
                ?: "${server!!.trimEnd('/')}/api/v1/system/img/1?imgurl=${java.net.URLEncoder.encode(reqUrl, "UTF-8")}&cache=false"
            val fallbackReq = request.newBuilder().url(fallbackUrl).build()
            val retryResp = chain.proceed(fallbackReq)
            if (retryResp.code == 401 && !server.isNullOrBlank() && !token.isNullOrBlank()) {
                retryResp.close()
                primeMediaSourceCookie(server, token)
                return chain.proceed(fallbackReq)
            }
            return retryResp
        }
        return try {
            val directResp = chain.proceed(request)
            if (
                directResp.isSuccessful ||
                (skipProxyOnNotFound && directResp.code == 404) ||
                server.isNullOrBlank() ||
                token.isNullOrBlank()
            ) {
                directResp
            } else {
                directResp.close()
                retryViaProxy()
            }
        } catch (ioe: java.io.IOException) {
            if (server.isNullOrBlank() || token.isNullOrBlank()) throw ioe
            retryViaProxy()
        }
    }

    /** 从同源 `/plugin_icon/<file>` 请求中提取合法单段编码文件名，供前端静态目录缺失时安全回退官方插件图标仓库。 */
    private fun extractSameOriginPluginIconEncodedName(server: String, url: HttpUrl): String? {
        if (url.encodedQuery != null || url.encodedFragment != null) return null
        val serverUrl = server.trimEnd('/').toHttpUrlOrNull() ?: return null
        if (
            !url.scheme.equals(serverUrl.scheme, ignoreCase = true) ||
            !url.host.equals(serverUrl.host, ignoreCase = true) ||
            url.port != serverUrl.port
        ) {
            return null
        }
        val baseSegments = serverUrl.encodedPathSegments.filter { it.isNotEmpty() }
        val reqSegments = url.encodedPathSegments.filter { it.isNotEmpty() }
        if (reqSegments.size != baseSegments.size + 2) return null
        for (i in baseSegments.indices) {
            if (reqSegments[i] != baseSegments[i]) return null
        }
        if (reqSegments[baseSegments.size] != "plugin_icon") return null
        val encodedName = reqSegments[baseSegments.size + 1]
        val decodedName = runCatching {
            java.net.URLDecoder.decode(encodedName.replace("+", "%2B"), "UTF-8")
        }.getOrNull() ?: return null
        if (MoviePilotRepository.extractSafePluginIconFileName(decodedName) == null) return null
        return encodedName
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
        val onAuthFailure = authFailureHandler(url, token)
        val reqBuilder = Request.Builder().url(url)
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        extraHeaders.forEach { (k, v) -> reqBuilder.header(k, v) }
        applyCloudflareAccessHeaders(reqBuilder, url, extraHeaders.entries.firstOrNull { it.key.equals("Cookie", ignoreCase = true) }?.value)
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
            notifyAuthDecision(onAuthFailure, resp.code, bodyText)
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
        val onAuthFailure = authFailureHandler(url, token)
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
        applyCloudflareAccessHeaders(reqBuilder, url)
        client().newBuilder().readTimeout(60, TimeUnit.SECONDS).writeTimeout(60, TimeUnit.SECONDS).build()
            .newCall(reqBuilder.build()).execute().use { resp ->
                val headersMap = resp.headers.names().associateWith { resp.headers[it].orEmpty() }
                val bodyText = resp.body?.string().orEmpty()
                notifyAuthDecision(onAuthFailure, resp.code, bodyText)
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
        val onAuthFailure = authFailureHandler(url, token)
        val reqBuilder = Request.Builder()
            .url(url)
            .header("Accept", "text/event-stream")
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        extraHeaders.forEach { (k, v) -> reqBuilder.header(k, v) }
        applyCloudflareAccessHeaders(reqBuilder, url, extraHeaders.entries.firstOrNull { it.key.equals("Cookie", ignoreCase = true) }?.value)
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
                val decision = notifyAuthDecision(onAuthFailure, resp.code, errBody)
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
