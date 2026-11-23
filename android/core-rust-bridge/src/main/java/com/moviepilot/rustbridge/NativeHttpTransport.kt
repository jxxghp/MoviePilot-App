package com.moviepilot.rustbridge

import com.moviepilot.rustcore.SseEventFfi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.SecureRandom
import java.security.cert.X509Certificate
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

/**
 * ADR-01 Android 原生网络传输实现：基于 OkHttp 完整尊重系统代理、VPN 与自签名证书选项，
 * 并严格禁止携带认证头的跨源重定向。
 */
class NativeHttpTransport(
    private val allowSelfSignedTls: () -> Boolean = { false },
) {
    private val defaultClient: OkHttpClient = buildClient(trustAll = false)
    private val selfSignedClient: OkHttpClient by lazy { buildClient(trustAll = true) }

    private fun client(): OkHttpClient =
        if (allowSelfSignedTls()) selfSignedClient else defaultClient

    private fun buildClient(trustAll: Boolean): OkHttpClient {
        val builder = OkHttpClient.Builder()
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
            NativeHttpResponse(
                status = resp.code,
                body = resp.body?.string().orEmpty(),
                headers = headersMap,
            )
        }
    }

    /** 建立 SSE 流式通道，逐块喂入 Rust `NativeSseParser` 并以 Kotlin `Flow` 向下游分发事件帧。 */
    fun streamSse(
        url: String,
        token: String?,
        bodyJson: String? = null,
    ): Flow<SseEventFfi> = flow {
        val reqBuilder = Request.Builder()
            .url(url)
            .header("Accept", "text/event-stream")
        if (!token.isNullOrBlank()) {
            reqBuilder.header("Authorization", "Bearer $token")
        }
        if (bodyJson != null) {
            reqBuilder.post(bodyJson.toRequestBody("application/json; charset=utf-8".toMediaType()))
        } else {
            reqBuilder.get()
        }
        val streamClient = client().newBuilder().readTimeout(0, TimeUnit.SECONDS).build()
        val parser = RustCoreBridge.createSseParser()
        streamClient.newCall(reqBuilder.build()).execute().use { resp ->
            val source = resp.body?.source() ?: return@use
            val buffer = ByteArray(4096)
            while (!source.exhausted()) {
                val read = source.read(buffer)
                if (read <= 0) break
                val chunk = String(buffer, 0, read, Charsets.UTF_8)
                for (ev in parser.pushChunk(chunk)) {
                    emit(ev)
                }
            }
            for (ev in parser.finish()) {
                emit(ev)
            }
        }
    }.flowOn(Dispatchers.IO)
}
