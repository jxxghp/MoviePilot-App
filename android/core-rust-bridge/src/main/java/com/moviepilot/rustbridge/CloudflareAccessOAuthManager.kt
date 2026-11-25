package com.moviepilot.rustbridge

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.net.URI
import java.net.URLEncoder
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

@Serializable
data class CloudflareAccessSessionDto(
    val serverOrigin: String,
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresAtEpochMs: Long? = null,
    val clientId: String,
    val tokenEndpoint: String,
    val issuer: String = "",
) {
    fun needsRefresh(nowMs: Long = System.currentTimeMillis(), leewayMs: Long = 120_000L): Boolean {
        val exp = expiresAtEpochMs ?: return false
        return exp > 0L && nowMs + leewayMs >= exp
    }
}

/**
 * Android 端 Cloudflare Access Managed OAuth（RFC 9728 / RFC 8414 / RFC 7591 / RFC 7636 PKCE）管理器：
 * - 通过系统浏览器发起 OAuth 授权，经 `moviepilot://oauth/callback` 回流 `MainActivity`；
 * - 凭据按规范化源键加密保存在 `NativeSecretStore`（Android Keystore AES-256-GCM）；
 * - 同源请求自动合并 `Cookie: CF_Authorization=...` 与 `cf-access-token`，绝不覆盖 MoviePilot `Authorization: Bearer`。
 */
class CloudflareAccessOAuthManager(
    private val secretStore: NativeSecretStore,
    private val transport: NativeHttpTransport,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val memoryCache = ConcurrentHashMap<String, CloudflareAccessSessionDto>()

    companion object {
        const val REDIRECT_URI = "moviepilot://oauth/callback"

        @Volatile
        private var pendingCallback: CompletableDeferred<String>? = null

        /** 由 `MainActivity.handleIntent` 在收到 `moviepilot://oauth/callback?...` 时调用。 */
        fun handleCallbackUri(rawUri: String): Boolean {
            val deferred = pendingCallback ?: return false
            return deferred.complete(rawUri)
        }

        /** 取消尚未完成的浏览器回调等待。 */
        fun cancelPending() {
            pendingCallback?.cancel()
            pendingCallback = null
        }

        /** 计算用于同源隔离存储与查询的规范化源键 `scheme://host[:port]`。 */
        fun normalizedOriginKey(rawUrl: String): String? {
            val uri = runCatching { URI(rawUrl.trim()) }.getOrNull() ?: return null
            val scheme = uri.scheme?.lowercase() ?: return null
            if (scheme != "http" && scheme != "https") return null
            val host = uri.host?.lowercase()?.takeIf { it.isNotBlank() } ?: return null
            val defaultPort = if (scheme == "https") 443 else 80
            val port = if (uri.port > 0) uri.port else defaultPort
            return if (port == defaultPort) "$scheme://$host" else "$scheme://$host:$port"
        }
    }

    /** 读取指定实例源的已保存 Cloudflare Access 会话。 */
    fun loadSession(serverUrl: String): CloudflareAccessSessionDto? {
        val origin = normalizedOriginKey(serverUrl) ?: return null
        memoryCache[origin]?.let { return it }
        val raw = secretStore.loadCloudflareSessionJson(origin) ?: return null
        val decoded = runCatching { json.decodeFromString<CloudflareAccessSessionDto>(raw) }.getOrNull()
        if (decoded != null && decoded.accessToken.isNotBlank()) {
            memoryCache[origin] = decoded
            return decoded
        }
        return null
    }

    /** 是否已为指定服务器保存有效的 Cloudflare Access 令牌。 */
    fun hasSession(serverUrl: String): Boolean = !loadSession(serverUrl)?.accessToken.isNullOrBlank()

    /** 仅当 `requestUrl` 对应源已保存 CF Access 会话时返回令牌，天然遵守同源边界。 */
    fun accessTokenForUrl(requestUrl: String): String? =
        loadSession(requestUrl)?.accessToken?.trim()?.takeIf { it.isNotEmpty() }

    /** 清除指定服务器的 Cloudflare Access 授权。 */
    fun clearSession(serverUrl: String) {
        val origin = normalizedOriginKey(serverUrl) ?: return
        memoryCache.remove(origin)
        secretStore.clearCloudflareSession(origin)
    }

    /** 若当前服务器的 CF Access 令牌临近过期且有 `refresh_token`，静默刷新并重新加密落盘。 */
    suspend fun refreshIfNeeded(serverUrl: String) = withContext(Dispatchers.IO) {
        val existing = loadSession(serverUrl) ?: return@withContext
        if (!existing.needsRefresh()) return@withContext
        val refreshToken = existing.refreshToken?.takeIf { it.isNotBlank() } ?: return@withContext
        val form = formEncode(
            "grant_type" to "refresh_token",
            "refresh_token" to refreshToken,
            "client_id" to existing.clientId,
        )
        val resp = runCatching {
            transport.execute(
                url = existing.tokenEndpoint,
                method = "POST",
                body = form,
                contentType = "application/x-www-form-urlencoded",
            )
        }.getOrNull() ?: return@withContext
        if (resp.status !in 200..299) return@withContext
        val obj = runCatching { json.parseToJsonElement(resp.body) as? JsonObject }.getOrNull() ?: return@withContext
        val newAccess = (obj["access_token"] as? JsonPrimitive)?.content?.trim().orEmpty()
        if (newAccess.isEmpty()) return@withContext
        val newRefresh = (obj["refresh_token"] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() }
            ?: existing.refreshToken
        val expiresIn = (obj["expires_in"] as? JsonPrimitive)?.longOrNull
        val updated = existing.copy(
            accessToken = newAccess,
            refreshToken = newRefresh,
            expiresAtEpochMs = expiresIn?.let { System.currentTimeMillis() + it * 1000L },
        )
        persistSession(updated)
    }

    /** 执行完整 Cloudflare Access Managed OAuth 认证。 */
    suspend fun authenticate(
        serverUrl: String,
        launchBrowser: (authorizeUrl: String) -> Unit,
    ): Result<CloudflareAccessSessionDto> = runCatching {
        val normalized = RustCoreBridge.normalizeAddress(serverUrl).getOrThrow()
        val origin = normalizedOriginKey(normalized) ?: error("服务地址无效")

        val hintUrl = probeResourceMetadataHint(normalized)
        val serverMeta = discoverServerMetadata(normalized, hintUrl)
        val existing = loadSession(normalized)
        val clientId = if (existing != null && existing.issuer == serverMeta.issuer && existing.clientId.isNotBlank()) {
            existing.clientId
        } else {
            val regEndpoint = serverMeta.registrationEndpoint
                ?: error("Cloudflare Access 未提供动态客户端注册端点，请检查 OAuth 应用配置")
            registerDynamicClient(regEndpoint)
        }

        val entropy = ByteArray(24).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val pkce = RustCoreBridge.generatePkcePair(entropy)
        val authorizeUrl = RustCoreBridge.buildOAuthAuthorizeUrl(
            authorizationEndpoint = serverMeta.authorizationEndpoint,
            clientId = clientId,
            redirectUri = REDIRECT_URI,
            codeChallenge = pkce.codeChallenge,
            state = pkce.state,
        ).getOrThrow()

        val deferred = CompletableDeferred<String>()
        pendingCallback?.cancel()
        pendingCallback = deferred
        try {
            withContext(Dispatchers.Main) {
                launchBrowser(authorizeUrl)
            }
            val callbackUri = withTimeout(5 * 60 * 1000L) {
                deferred.await()
            }
            val parsed = RustCoreBridge.parseOAuthCallbackUrl(callbackUri, pkce.state)
            if (!parsed.valid || parsed.code.isNullOrBlank()) {
                val detail = parsed.errorDescription ?: parsed.error ?: "回调校验失败，请重试"
                error(detail)
            }
            val session = exchangeCodeForToken(
                origin = origin,
                serverMeta = serverMeta,
                clientId = clientId,
                code = parsed.code,
                codeVerifier = pkce.codeVerifier,
            )
            persistSession(session)
            session
        } finally {
            if (pendingCallback === deferred) {
                pendingCallback = null
            }
        }
    }

    private fun persistSession(session: CloudflareAccessSessionDto) {
        memoryCache[session.serverOrigin] = session
        secretStore.saveCloudflareSessionJson(session.serverOrigin, json.encodeToString(session))
    }

    private suspend fun probeResourceMetadataHint(serverUrl: String): String? = withContext(Dispatchers.IO) {
        val probeUrl = runCatching {
            RustCoreBridge.buildEndpointUrl(serverUrl, listOf("system", "setup-status"))
        }.getOrNull() ?: return@withContext null
        val resp = runCatching { transport.execute(url = probeUrl, method = "GET") }.getOrNull()
            ?: return@withContext null
        val challenge = RustCoreBridge.detectCloudflareChallenge(resp.status, resp.headers, resp.body, probeUrl)
        challenge.resourceMetadataUrl
    }

    private suspend fun discoverServerMetadata(
        serverUrl: String,
        hintUrl: String?,
    ): OAuthServerMetadataDto = withContext(Dispatchers.IO) {
        val candidates = RustCoreBridge.buildOAuthDiscoveryUrls(serverUrl, hintUrl)
        val authServerUrls = mutableListOf<String>()

        for (candidate in candidates) {
            val resp = runCatching { transport.execute(url = candidate, method = "GET") }.getOrNull() ?: continue
            if (resp.status !in 200..299) continue
            RustCoreBridge.parseOAuthServerMetadata(resp.body).getOrNull()?.let { return@withContext it }
            RustCoreBridge.parseProtectedResourceMetadata(resp.body).getOrNull()?.forEach { url ->
                if (url !in authServerUrls) authServerUrls.add(url)
            }
        }

        for (asUrl in authServerUrls) {
            val resp = runCatching { transport.execute(url = asUrl, method = "GET") }.getOrNull() ?: continue
            if (resp.status !in 200..299) continue
            RustCoreBridge.parseOAuthServerMetadata(resp.body).getOrNull()?.let { return@withContext it }
        }

        error("未能发现 Cloudflare Access OAuth 元数据，请确认服务已开启 Cloudflare Access OAuth")
    }

    private suspend fun registerDynamicClient(endpoint: String): String = withContext(Dispatchers.IO) {
        val payload = """
            {
              "client_name": "MoviePilot Android",
              "redirect_uris": ["$REDIRECT_URI"],
              "grant_types": ["authorization_code", "refresh_token"],
              "response_types": ["code"],
              "token_endpoint_auth_method": "none"
            }
        """.trimIndent()
        val resp = transport.execute(
            url = endpoint,
            method = "POST",
            body = payload,
            contentType = "application/json; charset=utf-8",
        )
        if (resp.status !in 200..299) error("Cloudflare Access 客户端注册失败（HTTP ${resp.status}）")
        val obj = runCatching { json.parseToJsonElement(resp.body) as? JsonObject }.getOrNull()
        val clientId = (obj?.get("client_id") as? JsonPrimitive)?.content?.trim().orEmpty()
        if (clientId.isEmpty()) error("Cloudflare Access 注册响应缺少 client_id")
        clientId
    }

    private suspend fun exchangeCodeForToken(
        origin: String,
        serverMeta: OAuthServerMetadataDto,
        clientId: String,
        code: String,
        codeVerifier: String,
    ): CloudflareAccessSessionDto = withContext(Dispatchers.IO) {
        val form = formEncode(
            "grant_type" to "authorization_code",
            "code" to code,
            "redirect_uri" to REDIRECT_URI,
            "client_id" to clientId,
            "code_verifier" to codeVerifier,
        )
        val resp = transport.execute(
            url = serverMeta.tokenEndpoint,
            method = "POST",
            body = form,
            contentType = "application/x-www-form-urlencoded",
        )
        if (resp.status !in 200..299) error("换取 Cloudflare Access 令牌失败（HTTP ${resp.status}）")
        val obj = runCatching { json.parseToJsonElement(resp.body) as? JsonObject }.getOrNull()
        val accessToken = (obj?.get("access_token") as? JsonPrimitive)?.content?.trim().orEmpty()
        if (accessToken.isEmpty()) error("Cloudflare Access 未返回有效 access_token")
        val refreshToken = (obj?.get("refresh_token") as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() }
        val expiresIn = (obj?.get("expires_in") as? JsonPrimitive)?.longOrNull
        CloudflareAccessSessionDto(
            serverOrigin = origin,
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAtEpochMs = expiresIn?.let { System.currentTimeMillis() + it * 1000L },
            clientId = clientId,
            tokenEndpoint = serverMeta.tokenEndpoint,
            issuer = serverMeta.issuer,
        )
    }

    private fun formEncode(vararg pairs: Pair<String, String>): String =
        pairs.joinToString("&") { (k, v) ->
            "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
        }
}
