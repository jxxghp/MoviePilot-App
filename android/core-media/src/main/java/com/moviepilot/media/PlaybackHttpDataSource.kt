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
    private val SENSITIVE_HEADER_NAMES = setOf(
        "authorization",
        "cookie",
        "x-emby-token",
        "x-emby-authorization",
        "x-mediabrowser-token",
        "x-plex-token",
    )

    /** 判断候选请求地址是否与初始流源地址保持相同的 `scheme`、`host` 与有效端口。 */
    fun isSameOriginHostPort(originUrl: String, candidateUrl: String): Boolean {
        val origin = originUrl.toHttpUrlOrNull() ?: return false
        val candidate = candidateUrl.toHttpUrlOrNull() ?: return false
        return origin.scheme.equals(candidate.scheme, ignoreCase = true) &&
            origin.host.equals(candidate.host, ignoreCase = true) &&
            origin.port == candidate.port
    }

    /** 根据目标跳地址过滤请求头：跨源时彻底移除实例凭据及媒体服务器直连令牌头。 */
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

    /** 过滤外部播放器严禁接收的所有敏感凭据头（无论同源与否均剥离）。 */
    fun stripAllSensitiveHeaders(headers: Map<String, String>): Map<String, String> {
        if (headers.isEmpty()) return emptyMap()
        return headers.filterKeys { key -> key.lowercase() !in SENSITIVE_HEADER_NAMES }
    }

    /** 构建用于 Media3 与 MPV 本地环回转发代理共用的 TLS 感知、跨源 302 凭据隔离 `OkHttpClient`。 */
    fun createOkHttpClient(
        originUrl: String,
        headers: Map<String, String>,
        allowSelfSignedTls: Boolean,
        streamUrl: String = "",
        streamHeaders: Map<String, String> = emptyMap(),
        activeStreamProvider: (() -> Pair<String, Map<String, String>>)? = null,
    ): OkHttpClient {
        val originHttpUrl = originUrl.toHttpUrlOrNull()
        val clientBuilder = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .addNetworkInterceptor { chain ->
                val hopRequest = chain.request()
                val hopUrl = hopRequest.url
                val (currentStreamUrl, currentStreamHeaders) =
                    activeStreamProvider?.invoke() ?: (streamUrl to streamHeaders)
                val streamHttpUrl = currentStreamUrl.toHttpUrlOrNull()
                val sameOrigin = originHttpUrl != null &&
                    hopUrl.scheme.equals(originHttpUrl.scheme, ignoreCase = true) &&
                    hopUrl.host.equals(originHttpUrl.host, ignoreCase = true) &&
                    hopUrl.port == originHttpUrl.port
                val sameStreamOrigin = streamHttpUrl != null &&
                    hopUrl.scheme.equals(streamHttpUrl.scheme, ignoreCase = true) &&
                    hopUrl.host.equals(streamHttpUrl.host, ignoreCase = true) &&
                    hopUrl.port == streamHttpUrl.port
                val reqBuilder = hopRequest.newBuilder()
                // 先清理所有敏感凭据头，再按当前跳的严格同源关系重新注入，杜绝跨源 302 泄露直连令牌
                reqBuilder.removeHeader("Authorization")
                reqBuilder.removeHeader("Cookie")
                reqBuilder.removeHeader("X-Emby-Token")
                reqBuilder.removeHeader("X-Emby-Authorization")
                reqBuilder.removeHeader("X-MediaBrowser-Token")
                reqBuilder.removeHeader("X-Plex-Token")
                if (sameOrigin) {
                    headers.forEach { (k, v) ->
                        if (k.isNotBlank() && v.isNotBlank()) {
                            reqBuilder.header(k, v)
                        }
                    }
                } else {
                    headers.forEach { (k, v) ->
                        if (k.lowercase() !in SENSITIVE_HEADER_NAMES && k.isNotBlank() && v.isNotBlank()) {
                            reqBuilder.header(k, v)
                        }
                    }
                    currentStreamHeaders.forEach { (k, v) ->
                        val isSensitive = k.lowercase() in SENSITIVE_HEADER_NAMES
                        if (k.isNotBlank() && v.isNotBlank() && (!isSensitive || sameStreamOrigin)) {
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

        return clientBuilder.build()
    }

    /** 构建用于 Media3 播放器的 TLS 感知、同源凭据隔离与多级直连/降级请求头支持 `OkHttpDataSource.Factory`。 */
    @OptIn(UnstableApi::class)
    fun createFactory(
        originUrl: String,
        headers: Map<String, String>,
        allowSelfSignedTls: Boolean,
        streamUrl: String = "",
        streamHeaders: Map<String, String> = emptyMap(),
        activeStreamProvider: (() -> Pair<String, Map<String, String>>)? = null,
    ): OkHttpDataSource.Factory = OkHttpDataSource.Factory(
        createOkHttpClient(
            originUrl = originUrl,
            headers = headers,
            allowSelfSignedTls = allowSelfSignedTls,
            streamUrl = streamUrl,
            streamHeaders = streamHeaders,
            activeStreamProvider = activeStreamProvider,
        ),
    )
}
