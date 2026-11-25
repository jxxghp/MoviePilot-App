package com.moviepilot.media

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * 音视频流媒体安全传输工厂：
 * 1. 基于 `OkHttpDataSource.Factory` 支持 HTTP/HTTPS/HLS/DASH 流式拉取与连接池复用；
 * 2. 尊重实例自签名证书开关（`allowSelfSignedTls`）；
 * 3. 通过网络层拦截器（`addNetworkInterceptor`）在每一跳校验 `host` 与 `port` 同源性，
 *    仅在同源请求上注入 `Authorization` / `Cookie` 等鉴权头，跨源 302 重定向至外部 CDN 时自动剥离敏感凭据。
 */
object PlaybackHttpDataSource {
    private val SENSITIVE_HEADER_NAMES = setOf("authorization", "cookie")

    /** 判断候选请求地址是否与初始流源地址保持相同的 `host` 与有效端口。 */
    fun isSameOriginHostPort(originUrl: String, candidateUrl: String): Boolean {
        val origin = originUrl.toHttpUrlOrNull() ?: return false
        val candidate = candidateUrl.toHttpUrlOrNull() ?: return false
        return origin.host.equals(candidate.host, ignoreCase = true) && origin.port == candidate.port
    }

    /** 根据目标跳地址过滤请求头：跨源时彻底移除 `Authorization` 与 `Cookie`。 */
    fun filterHeadersForTarget(
        originUrl: String,
        targetUrl: String,
        headers: Map<String, String>,
    ): Map<String, String> {
        if (headers.isEmpty()) return emptyMap()
        return if (isSameOriginHostPort(originUrl, targetUrl)) {
            headers
        } else {
            headers.filterKeys { key -> key.lowercase() !in SENSITIVE_HEADER_NAMES }
        }
    }

    /** 构建用于 Media3 播放器的 TLS 感知、同源凭据隔离与外部 STRM 自定义请求头支持 `OkHttpDataSource.Factory`。 */
    @OptIn(UnstableApi::class)
    fun createFactory(
        originUrl: String,
        headers: Map<String, String>,
        allowSelfSignedTls: Boolean,
        streamUrl: String = "",
        streamHeaders: Map<String, String> = emptyMap(),
    ): OkHttpDataSource.Factory {
        val originHttpUrl = originUrl.toHttpUrlOrNull()
        val streamHttpUrl = streamUrl.toHttpUrlOrNull()
        val clientBuilder = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .addNetworkInterceptor { chain ->
                val hopRequest = chain.request()
                val hopUrl = hopRequest.url
                val sameHostPort = originHttpUrl != null &&
                    hopUrl.host.equals(originHttpUrl.host, ignoreCase = true) &&
                    hopUrl.port == originHttpUrl.port
                val sameStreamHostPort = streamHttpUrl != null &&
                    hopUrl.host.equals(streamHttpUrl.host, ignoreCase = true) &&
                    hopUrl.port == streamHttpUrl.port
                val reqBuilder = hopRequest.newBuilder()
                if (sameHostPort) {
                    headers.forEach { (k, v) ->
                        if (k.isNotBlank() && v.isNotBlank()) {
                            reqBuilder.header(k, v)
                        }
                    }
                } else {
                    reqBuilder.removeHeader("Authorization")
                    reqBuilder.removeHeader("Cookie")
                    headers.forEach { (k, v) ->
                        if (k.lowercase() !in SENSITIVE_HEADER_NAMES && k.isNotBlank() && v.isNotBlank()) {
                            reqBuilder.header(k, v)
                        }
                    }
                    streamHeaders.forEach { (k, v) ->
                        val isSensitive = k.lowercase() in SENSITIVE_HEADER_NAMES
                        if (k.isNotBlank() && v.isNotBlank() && (!isSensitive || sameStreamHostPort)) {
                            reqBuilder.header(k, v)
                        }
                    }
                }
                chain.proceed(reqBuilder.build())
            }

        if (allowSelfSignedTls) {
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val sslContext = SSLContext.getInstance("TLS").apply {
                init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
            }
            clientBuilder.sslSocketFactory(sslContext.socketFactory, trustManager)
            clientBuilder.hostnameVerifier { _, _ -> true }
        }

        return OkHttpDataSource.Factory(clientBuilder.build())
    }
}
