package com.moviepilot.rustbridge

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Android 端媒体服务器直连探测与网络指纹缓存中心：
 * - 通过 `ConnectivityManager.registerDefaultNetworkCallback` 监听网络切换自动递增 `networkEpoch` 并失效探测缓存；
 * - 并发探测 `server_lan` / `server_wan` 轻量端点（700ms 连接/读取超时），按 `(server, networkEpoch)` 缓存 5 分钟；
 * - 直连起播失败时记录 60 秒短时负缓存，避免切集重复踩坑；
 * - 缓存最近解析完成的 `PlaybackRoutePlanDto`，便于全局播放壳自动补全路由角标与多级降级队列。
 */
class PlaybackRouteResolver(context: Context) {
    private data class CachedProbe(
        val outcome: RouteProbeOutcomeDto,
        val expiresAtMs: Long,
    )

    private val probeTtlMs = 5L * 60L * 1000L
    private val negativeTtlMs = 60L * 1000L
    private val networkEpoch = AtomicInteger(0)
    private val probeCache = ConcurrentHashMap<String, CachedProbe>()
    private val failedRouteUntil = ConcurrentHashMap<String, Long>()
    private val recentPlanByUrl = ConcurrentHashMap<String, PlaybackRoutePlanDto>()

    private val strictProbeClient: OkHttpClient by lazy { buildProbeClient(allowSelfSignedTls = false) }
    private val insecureProbeClient: OkHttpClient by lazy { buildProbeClient(allowSelfSignedTls = true) }

    init {
        registerNetworkCallback(context)
    }

    private fun registerNetworkCallback(context: Context) {
        runCatching {
            val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return@runCatching
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = invalidateForNetworkChange()
                override fun onLost(network: Network) = invalidateForNetworkChange()
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    // 网络类型或 VPN 变更时刷新探测代际，避免沿用旧局域网结果
                    invalidateForNetworkChange()
                }
            })
        }
    }

    private fun invalidateForNetworkChange() {
        networkEpoch.incrementAndGet()
        probeCache.clear()
        failedRouteUntil.clear()
    }

    /** 将起播失败的直连路由记入 60 秒短时负缓存。 */
    fun markRouteFailed(server: String?, url: String) {
        val key = failureKey(server, url)
        failedRouteUntil[key] = System.currentTimeMillis() + negativeTtlMs
    }

    /** 记录最近解析结果，供全局播放入口补齐 `streamHeaders` / `activeRouteKind` / `fallbackRoutes`。 */
    fun rememberPlan(plan: PlaybackRoutePlanDto) {
        if (recentPlanByUrl.size >= 48) {
            recentPlanByUrl.clear()
        }
        recentPlanByUrl[plan.active.url] = plan
    }

    /** 按播放 URL 查询最近一次解析出的直连路由规划。 */
    fun lookupPlanForUrl(url: String): PlaybackRoutePlanDto? = recentPlanByUrl[url]

    /** 并发探测直连候选并通过共享 Rust 路由规划器生成主路由和有序降级队列。 */
    suspend fun resolve(
        server: String?,
        routes: List<PlaybackRouteDto>,
        preferStrmDirect: Boolean,
        preferServerDirect: Boolean,
        allowSelfSignedTls: Boolean,
    ): PlaybackRoutePlanDto? {
        val prefs = PlaybackRoutePreferenceDto(
            preferStrmDirect = preferStrmDirect,
            preferServerDirect = preferServerDirect,
        )
        val now = System.currentTimeMillis()
        val probes = mutableListOf<RouteProbeOutcomeDto>()
        val toProbe = LinkedHashSet<String>()

        if (preferServerDirect) {
            for (route in routes) {
                if (route.kind != "server_lan" && route.kind != "server_wan") continue
                val blockedUntil = failedRouteUntil[failureKey(server, route.url)] ?: 0L
                val probeUrl = route.probeUrl?.trim()?.takeIf { it.isNotBlank() }
                if (blockedUntil > now) {
                    probes += RouteProbeOutcomeDto(url = probeUrl ?: route.url, reachable = false, latencyMs = null)
                    continue
                }
                if (probeUrl == null) continue
                val cached = probeCache[probeCacheKey(server, probeUrl)]
                if (cached != null && cached.expiresAtMs > now) {
                    probes += cached.outcome
                } else {
                    toProbe += probeUrl
                }
            }
        }

        if (toProbe.isNotEmpty()) {
            val epochBefore = networkEpoch.get()
            val client = if (allowSelfSignedTls) insecureProbeClient else strictProbeClient
            val fresh = coroutineScope {
                toProbe.map { targetUrl ->
                    async(Dispatchers.IO) { probeSingle(client, targetUrl) }
                }.awaitAll()
            }
            if (epochBefore == networkEpoch.get()) {
                val expiresAt = System.currentTimeMillis() + probeTtlMs
                for (outcome in fresh) {
                    probeCache[probeCacheKey(server, outcome.url)] = CachedProbe(outcome, expiresAt)
                }
            }
            probes += fresh
        }

        val plan = RustCoreBridge.planPlaybackRoutes(routes, prefs, probes)
        if (plan != null) {
            rememberPlan(plan)
        }
        return plan
    }

    private suspend fun probeSingle(client: OkHttpClient, url: String): RouteProbeOutcomeDto =
        withContext(Dispatchers.IO) {
            val startedNs = System.nanoTime()
            runCatching {
                val req = Request.Builder().url(url).get().build()
                client.newCall(req).execute().use { resp ->
                    val ok = resp.code in 200..499 && resp.code != 404
                    val elapsedMs = ((System.nanoTime() - startedNs) / 1_000_000L).toInt().coerceAtLeast(1)
                    RouteProbeOutcomeDto(
                        url = url,
                        reachable = ok,
                        latencyMs = if (ok) elapsedMs else null,
                    )
                }
            }.getOrElse {
                RouteProbeOutcomeDto(url = url, reachable = false, latencyMs = null)
            }
        }

    private fun buildProbeClient(allowSelfSignedTls: Boolean): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(700, TimeUnit.MILLISECONDS)
            .readTimeout(700, TimeUnit.MILLISECONDS)
            .callTimeout(900, TimeUnit.MILLISECONDS)
            .followRedirects(false)
            .followSslRedirects(false)
        if (allowSelfSignedTls) {
            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val sslContext = SSLContext.getInstance("TLS").apply {
                init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
            }
            builder.sslSocketFactory(sslContext.socketFactory, trustManager)
            builder.hostnameVerifier { _, _ -> true }
        }
        return builder.build()
    }

    private fun probeCacheKey(server: String?, probeUrl: String): String =
        "${server.orEmpty()}|${networkEpoch.get()}|$probeUrl"

    private fun failureKey(server: String?, url: String): String =
        "${server.orEmpty()}|${networkEpoch.get()}|$url"
}
