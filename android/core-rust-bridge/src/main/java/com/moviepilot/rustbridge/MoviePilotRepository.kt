package com.moviepilot.rustbridge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import com.moviepilot.rustcore.PermissionsFfi
import com.moviepilot.rustcore.SseEventFfi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlin.math.roundToInt

/** 已启用插件可绑定的桌面小组件目录描述项（兼容 `/api/v1/plugin/widgets/meta` 与仪表盘兜底）。 */
data class PluginWidgetMetaDto(
    val pluginId: String,
    val pluginName: String,
    val widgetKey: String = "",
    val name: String,
    val description: String = "",
    val kind: String = "metrics",
    val source: String = "widget",
    val hasPage: Boolean = false,
)

/** 设置中心摘要快照缓存（二次进入设置页零等待秒开）。 */
data class SettingsSummarySnapshot(
    val stats: DashboardStatsDto,
    val activeSitesCount: Int = 0,
    val usersCount: Int = 1,
    val mediaServersCount: Int = 0,
    val notificationsCount: Int = 0,
    val authorizedCount: Int = 0,
)

/** 登录请求结果（支持正常登录、MFA/OTP 二次挑战与错误提示）。 */
sealed interface LoginOutcome {
    data class Success(val identity: UserIdentity) : LoginOutcome
    data class OtpRequired(val message: String) : LoginOutcome
    data class Failure(val message: String, val canceled: Boolean = false) : LoginOutcome
}

/** 认证会话状态机（与 iOS NativeSessionState 对齐）。 */
sealed interface SessionState {
    data object Unconnected : SessionState
    data class NeedsLogin(val serverUrl: String, val notice: String? = null) : SessionState
    data class Authenticated(
        val serverUrl: String,
        val token: String,
        val identity: UserIdentity,
        val permissions: PermissionsFfi,
    ) : SessionState
}

/**
 * MoviePilot V3 全业务仓库：
 * - 所有 URL 构造、JWT 过期校验、401/403 判别、RBAC 权限计算与 9 维站点资源筛选均通过 RustCoreBridge；
 * - 底层传输通过 Android 原生 OkHttp（ADR-01 + 资源 CookieJar），凭据通过 Android Keystore（ADR-02）；
 * - 所有 JSON 字段访问均采用 JsonNull 免疫扩展（asObj / asArr / asPrim），杜绝后端空字段引发崩溃。
 */
class MoviePilotRepository(context: Context) {
    private val appContext = context.applicationContext
    val secretStore = NativeSecretStore(appContext)
    val transport = NativeHttpTransport(allowSelfSignedTls = { secretStore.allowSelfSignedTls })
    val cloudflareOAuth = CloudflareAccessOAuthManager(secretStore, transport)
    val playbackProgressReporter = PlaybackProgressReporter(appContext)
    val playbackRouteResolver = PlaybackRouteResolver(appContext)
    val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    private val sessionLock = Any()
    private var sessionGeneration = 0L
    private val _session = MutableStateFlow<SessionState>(SessionState.Unconnected)
    val session: StateFlow<SessionState> = _session.asStateFlow()

    private val _savedServers = MutableStateFlow(secretStore.loadServers())
    val savedServers: StateFlow<List<SavedServerEntry>> = _savedServers.asStateFlow()

    private val siteIconCache = ConcurrentHashMap<Int, String>()
    private val mediaLogoCache = ConcurrentHashMap<String, String>()
    private val multiRatingsCache = ConcurrentHashMap<String, List<MediaRatingBadgeDto>>()
    private val resourceRawCache = ConcurrentHashMap<String, JsonObject>()
    @Volatile
    private var resourceCookiePrimed = false
    @Volatile
    var globalImageConfig: GlobalImageConfigSnapshot = GlobalImageConfigSnapshot()
        private set

    /** 发现页、探索页、订阅页、工作台与仪表盘的内存会话缓存（切 Tab 与详情返回时零重拉、保留滚动位置）。 */
    @Volatile
    var cachedDiscover: DiscoverSessionSnapshot? = null
    val cachedExplore = ConcurrentHashMap<String, ExploreSessionSnapshot>()
    @Volatile
    var cachedSubscriptions: List<SubscribeItemDto>? = null
    @Volatile
    var cachedDashboard: DashboardSessionSnapshot? = null
    @Volatile
    var cachedWorkspace: WorkspaceSessionSnapshot? = null
    @Volatile
    var cachedSettingsSummary: SettingsSummarySnapshot? = null
    @Volatile
    var cachedInstalledPlugins: List<PluginItemDto>? = null
    @Volatile
    var cachedMarketPlugins: List<PluginItemDto>? = null

    /** 清空当前会话内存数据缓存（在登出、切换实例或遗忘实例时调用）。 */
    fun clearSessionCaches() {
        cachedDiscover = null
        cachedExplore.clear()
        cachedSubscriptions = null
        cachedDashboard = null
        cachedWorkspace = null
        cachedSettingsSummary = null
        cachedInstalledPlugins = null
        cachedMarketPlugins = null
        siteIconCache.clear()
        mediaLogoCache.clear()
        multiRatingsCache.clear()
        resourceRawCache.clear()
    }

    init {
        transport.cfAccessTokenProvider = { requestUrl ->
            cloudflareOAuth.accessTokenForUrl(requestUrl)
        }
        transport.authFailureHandlerProvider = ::captureAuthFailureHandler
        restoreSessionIfPossible()
    }

    /** 使用不可变用户 ID 隔离播放桶；恢复会话时可从已验证令牌的 sub 读取，未知身份不补报。 */
    fun playbackStorageKey(auth: SessionState.Authenticated): String? = runCatching {
        val accountID = if (auth.identity.id > 0) auth.identity.id.toString() else {
            val claims = String(java.util.Base64.getUrlDecoder().decode(auth.token.split('.')[1]), Charsets.UTF_8)
            json.parseToJsonElement(claims).asObj()?.str("sub") ?: return null
        }
        PlaybackQueueScope.storageKey(auth.serverUrl, accountID)
    }.getOrNull()

    /** 序列化会话替换并递增代次，包含同实例重新登录，旧请求不得注销新代次。 */
    private fun setSession(next: SessionState, advancesGeneration: Boolean = true) = synchronized(sessionLock) {
        if (advancesGeneration) sessionGeneration++
        _session.value = next
    }

    /** 在请求发出前捕获实例、令牌和会话代次，响应只可使原始会话失效。 */
    private fun captureAuthFailureHandler(url: String, token: String): (() -> Unit)? = synchronized(sessionLock) {
        val auth = _session.value as? SessionState.Authenticated ?: return@synchronized null
        if (auth.token != token || !RustCoreBridge.containsUrl(auth.serverUrl, url)) return@synchronized null
        val generation = sessionGeneration
        val handler: () -> Unit = {
            synchronized(sessionLock) {
                if (generation == sessionGeneration) logout("登录状态已过期，请重新登录")
            }
        }
        handler
    }

    /** 从 JWT Payload 提取签发时的 `level`（用于重启恢复与 `/user/current` 未返回该字段时回退）。 */
    private fun parseJwtLevel(token: String): Int? {
        val parts = token.split('.')
        if (parts.size != 3) return null
        return runCatching {
            val payload = parts[1].replace('-', '+').replace('_', '/')
            val padded = payload + "=".repeat((4 - payload.length % 4) % 4)
            val decoded = android.util.Base64.decode(padded, android.util.Base64.DEFAULT)
            val obj = json.parseToJsonElement(String(decoded, Charsets.UTF_8)).asObj()
            obj?.int("level")?.takeIf { it >= 0 }
        }.getOrNull()
    }

    /** 启动时尝试恢复上次已连接的实例与有效会话；若 JWT 已过期则安全退回登录页。 */
    private fun restoreSessionIfPossible() {
        val activeUrl = secretStore.activeServerUrl() ?: return
        globalImageConfig = secretStore.loadGlobalImageConfig(activeUrl) ?: GlobalImageConfigSnapshot()
        val token = secretStore.loadToken(activeUrl)
        if (!token.isNullOrBlank() && secretStore.keepLogin) {
            val claims = RustCoreBridge.decodeJwt(token)
            if (!claims.isExpired) {
                val perms = RustCoreBridge.evaluatePermissions("{}", claims.superUser)
                setSession(SessionState.Authenticated(
                    serverUrl = activeUrl,
                    token = token,
                    identity = UserIdentity(
                        name = claims.userName ?: "admin",
                        isSuperuser = claims.superUser,
                        level = parseJwtLevel(token) ?: 1,
                    ),
                    permissions = perms,
                ))
                return
            } else {
                secretStore.clearToken(activeUrl)
            }
        }
        setSession(SessionState.NeedsLogin(activeUrl))
    }

    /** 恢复会话后异步刷新 `/user/current`（拿真实头像与权限）、同步全局图片配置并预热短效资源 Cookie。 */
    suspend fun hydrateAuthenticatedSession() {
        val auth = _session.value as? SessionState.Authenticated ?: return
        refreshGlobalImageSettings(auth.serverUrl)
        primeResourceCookie()
        val meResp = authedRequest(listOf("user", "current")).getOrNull() ?: return
        if (meResp.status in 200..299) {
            val dataObj = extractObject(meResp.body) ?: return
            val isSu = dataObj.bool("is_superuser") ?: auth.identity.isSuperuser
            val refreshed = auth.identity.copy(
                id = dataObj.int("id") ?: auth.identity.id,
                name = dataObj.str("name") ?: auth.identity.name,
                email = dataObj.str("email") ?: auth.identity.email,
                isSuperuser = isSu,
                isActive = dataObj.bool("is_active") ?: true,
                isOtp = dataObj.bool("is_otp") ?: false,
                level = dataObj.int("level") ?: parseJwtLevel(auth.token) ?: auth.identity.level,
                avatar = dataObj.str("avatar") ?: auth.identity.avatar,
            )
            val perms = RustCoreBridge.evaluatePermissions(
                dataObj["permissions"]?.toString() ?: "{}",
                isSu,
            )
            synchronized(sessionLock) {
                // 只刷新发起 hydration 的会话，旧响应不能重新装回已切走的实例。
                if (_session.value === auth) setSession(auth.copy(identity = refreshed, permissions = perms), advancesGeneration = false)
            }
        }
    }

    /** 触发 `/api/v1/media/source` 换取 MoviePilot 短效同源图片代理 Cookie（与 iOS `APIClient.requestImage` 一致）。 */
    suspend fun primeResourceCookie() {
        if (resourceCookiePrimed) return
        val resp = authedRequest(listOf("media", "source")).getOrNull()
        if (resp != null && resp.status in 200..299) {
            resourceCookiePrimed = true
        }
    }

    /** 校验并连接 MoviePilot 服务地址，持久化至已保存服务列表。 */
    fun connectServer(rawUrl: String): Result<String> {
        val normalized = RustCoreBridge.normalizeAddress(rawUrl)
            .getOrElse { return Result.failure(it) }
        val hostTitle = normalized.substringAfter("://").substringBefore("/").substringBefore(":")
        secretStore.upsertServer(
            SavedServerEntry(
                id = normalized.hashCode().toString(),
                name = hostTitle.ifBlank { normalized },
                url = normalized,
                lastUsedEpochMs = System.currentTimeMillis(),
            ),
        )
        secretStore.setActiveServerUrl(normalized)
        _savedServers.value = secretStore.loadServers()
        clearSessionCaches()
        setSession(SessionState.NeedsLogin(normalized))
        return Result.success(normalized)
    }

    /** 切换到指定历史实例。 */
    fun selectSavedServer(entry: SavedServerEntry) {
        secretStore.setActiveServerUrl(entry.url)
        globalImageConfig = secretStore.loadGlobalImageConfig(entry.url) ?: GlobalImageConfigSnapshot()
        resourceCookiePrimed = false
        clearSessionCaches()
        val existingToken = secretStore.loadToken(entry.url)
        if (!existingToken.isNullOrBlank() && !RustCoreBridge.decodeJwt(existingToken).isExpired) {
            val claims = RustCoreBridge.decodeJwt(existingToken)
            setSession(SessionState.Authenticated(
                serverUrl = entry.url,
                token = existingToken,
                identity = UserIdentity(
                    name = entry.username.ifBlank { claims.userName ?: "admin" },
                    isSuperuser = claims.superUser,
                    level = parseJwtLevel(existingToken) ?: 1,
                ),
                permissions = RustCoreBridge.evaluatePermissions("{}", claims.superUser),
            ))
        } else {
            setSession(SessionState.NeedsLogin(entry.url))
        }
    }

    /** 返回实例连接页并废弃前一会话的失效回调。 */
    fun openServerConnection() {
        setSession(SessionState.Unconnected)
    }

    /** 忘记实例；若正处于该实例，则同时清理当前会话与缓存。 */
    fun forgetServer(url: String) {
        cloudflareOAuth.clearSession(url)
        secretStore.forgetServer(url)
        _savedServers.value = secretStore.loadServers()
        if ((_session.value as? SessionState.NeedsLogin)?.serverUrl == url ||
            (_session.value as? SessionState.Authenticated)?.serverUrl == url
        ) {
            clearSessionCaches()
            setSession(SessionState.Unconnected)
        }
    }

    /** 执行账号密码（及可选 OTP 二次验证码）登录。 */
    suspend fun login(
        serverUrl: String,
        username: String,
        password: String,
        otpPassword: String = "",
    ): LoginOutcome {
        val url = runCatching {
            RustCoreBridge.buildEndpointUrl(serverUrl, listOf("login", "access-token"))
        }.getOrElse { return LoginOutcome.Failure("服务地址无效：${it.message}") }

        val form = buildString {
            append("username=").append(URLEncoder.encode(username.trim(), "UTF-8"))
            append("&password=").append(URLEncoder.encode(password, "UTF-8"))
            append("&otp_password=").append(URLEncoder.encode(otpPassword.trim(), "UTF-8"))
        }
        cloudflareOAuth.refreshIfNeeded(serverUrl)
        val resp = runCatching {
            transport.execute(
                url = url,
                method = "POST",
                body = form,
                contentType = "application/x-www-form-urlencoded",
            )
        }.getOrElse { return LoginOutcome.Failure("无法连接到服务：${it.message ?: "网络异常"}") }

        val cfChallenge = RustCoreBridge.detectCloudflareChallenge(resp.status, resp.headers, resp.body, url)
        if (cfChallenge.isChallenge) {
            return LoginOutcome.Failure("检测到 Cloudflare Access 网关拦截，请先点击下方「通过 Cloudflare Access 认证」")
        }

        val root = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        if (resp.status == 401) {
            val mfa = root?.get("data").asObj()?.get("mfa_methods").asArr()
            if (mfa != null && mfa.isNotEmpty()) {
                return LoginOutcome.OtpRequired("该账号已启用动态口令（OTP），请输入 6 位验证码")
            }
            val msg = root?.str("detail") ?: root?.str("message") ?: "用户名、密码或验证码错误"
            return LoginOutcome.Failure(msg)
        }
        if (resp.status !in 200..299 || root == null) {
            return LoginOutcome.Failure("登录失败（HTTP ${resp.status}）")
        }

        val token = root.str("access_token") ?: root["data"].asObj()?.str("access_token")
        if (token.isNullOrBlank()) {
            return LoginOutcome.Failure("服务端未返回有效访问令牌")
        }

        val superUser = root.bool("super_user") ?: false
        val userName = root.str("user_name") ?: username.trim()
        val userLevel = root.int("level") ?: root["data"].asObj()?.int("level") ?: 1
        val avatar = root.str("avatar")
        val permsJson = root["permissions"]?.toString() ?: "{}"

        val identityResp = runCatching {
            val meUrl = RustCoreBridge.buildEndpointUrl(serverUrl, listOf("user", "current"))
            transport.execute(url = meUrl, method = "GET", token = token)
        }.getOrNull()

        var identity = UserIdentity(name = userName, isSuperuser = superUser, level = userLevel, avatar = avatar)
        var permissions = RustCoreBridge.evaluatePermissions(permsJson, superUser)

        if (identityResp != null && identityResp.status == 200) {
            val dataObj = extractObject(identityResp.body)
            if (dataObj != null) {
                val isSu = dataObj.bool("is_superuser") ?: superUser
                identity = UserIdentity(
                    id = dataObj.int("id") ?: 0,
                    name = dataObj.str("name") ?: userName,
                    email = dataObj.str("email") ?: "",
                    isSuperuser = isSu,
                    isActive = dataObj.bool("is_active") ?: true,
                    isOtp = dataObj.bool("is_otp") ?: false,
                    level = dataObj.int("level") ?: userLevel,
                    avatar = dataObj.str("avatar") ?: avatar,
                )
                permissions = RustCoreBridge.evaluatePermissions(
                    dataObj["permissions"]?.toString() ?: permsJson,
                    isSu,
                )
            }
        }

        if (secretStore.keepLogin) {
            secretStore.saveToken(serverUrl, token)
        }
        if (secretStore.rememberCredentials) {
            secretStore.saveCredentials(serverUrl, username.trim(), password)
        }
        secretStore.upsertServer(
            SavedServerEntry(
                id = serverUrl.hashCode().toString(),
                name = serverUrl.substringAfter("://").substringBefore("/").substringBefore(":"),
                url = serverUrl,
                username = identity.name,
                lastUsedEpochMs = System.currentTimeMillis(),
            ),
        )
        _savedServers.value = secretStore.loadServers()
        resourceCookiePrimed = false
        globalImageConfig = secretStore.loadGlobalImageConfig(serverUrl) ?: GlobalImageConfigSnapshot()
        refreshGlobalImageSettings(serverUrl)
        setSession(SessionState.Authenticated(serverUrl, token, identity, permissions))
        primeResourceCookie()
        return LoginOutcome.Success(identity)
    }

    /** 探测目标实例是否已启用系统通行密钥认证（`GET /api/v1/auth/providers`）。 */
    suspend fun probePasskeyEnabled(serverUrl: String): Boolean {
        val cleanUrl = RustCoreBridge.normalizeAddress(serverUrl).getOrNull() ?: return false
        cloudflareOAuth.refreshIfNeeded(cleanUrl)
        val url = runCatching {
            RustCoreBridge.buildEndpointUrl(cleanUrl, listOf("auth", "providers"))
        }.getOrNull() ?: return false
        val resp = runCatching {
            transport.execute(url = url, method = "GET", token = null)
        }.getOrNull() ?: return false
        if (resp.status != 200 || resp.body.isBlank()) return false
        return RustCoreBridge.parsePasskeyProviderEnabled(resp.body)
    }

    /** 使用系统浏览器完成 `moviepilot.passkey` v1 通行密钥认证并激活实例会话。 */
    suspend fun loginWithPasskey(
        serverUrl: String,
        username: String = "",
        launchBrowser: (authorizeUrl: String) -> Unit,
    ): LoginOutcome {
        val cleanUrl = RustCoreBridge.normalizeAddress(serverUrl).getOrElse {
            return LoginOutcome.Failure("服务地址无效：${it.message}")
        }
        if (!RustCoreBridge.isPasskeySecureOrigin(cleanUrl)) {
            return LoginOutcome.Failure("当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。")
        }
        cloudflareOAuth.refreshIfNeeded(cleanUrl)

        val markerUrl = "${cleanUrl.trimEnd('/')}/native-passkey.json"
        val markerResp = runCatching {
            transport.execute(url = markerUrl, method = "GET", token = null)
        }.getOrElse {
            return LoginOutcome.Failure("无法连接到服务：${it.message ?: "网络异常"}")
        }
        if (RustCoreBridge.detectCloudflareChallenge(markerResp.status, markerResp.headers, markerResp.body, markerUrl).isChallenge) {
            return LoginOutcome.Failure("检测到 Cloudflare Access 网关拦截，请先完成 Cloudflare Access 认证")
        }
        if (markerResp.status != 200 || !RustCoreBridge.supportsPasskeyFrontendMarker(markerResp.body)) {
            return LoginOutcome.Failure("请更新实例的前端资源后，再使用 App 通行密钥登录。")
        }

        val startUrl = runCatching {
            RustCoreBridge.buildEndpointUrl(cleanUrl, listOf("mfa", "passkey", "authenticate", "start"))
        }.getOrElse {
            return LoginOutcome.Failure("未能完成通行密钥验证，请重新尝试。")
        }
        val trimmedUser = username.trim()
        val startBodyJson = if (trimmedUser.isNotEmpty()) {
            buildJsonObject { put("username", trimmedUser) }.toString()
        } else {
            "{}"
        }
        val startResp = runCatching {
            transport.execute(
                url = startUrl,
                method = "POST",
                body = startBodyJson,
                contentType = "application/json",
            )
        }.getOrElse {
            return LoginOutcome.Failure("无法连接到服务：${it.message ?: "网络异常"}")
        }
        if (RustCoreBridge.detectCloudflareChallenge(startResp.status, startResp.headers, startResp.body, startUrl).isChallenge) {
            return LoginOutcome.Failure("检测到 Cloudflare Access 网关拦截，请先完成 Cloudflare Access 认证")
        }
        if (startResp.status !in 200..299) {
            return LoginOutcome.Failure("未能完成通行密钥验证，请重新尝试。")
        }

        val stateHex = PasskeyAuthManager.generateStateHex32()
        val prepared = RustCoreBridge.preparePasskeyRequest(startResp.body, cleanUrl, stateHex).getOrElse { err ->
            val msg = when (err.message) {
                "unsupported" -> "当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。"
                "invalid" -> "通行密钥验证结果无效，请重新尝试。"
                else -> "未能完成通行密钥验证，请重新尝试。"
            }
            return LoginOutcome.Failure(msg)
        }

        val callbackUri = PasskeyAuthManager.awaitBrowserCallback(
            authorizeUrl = prepared.authorizationUrl,
            timeoutSecs = prepared.timeoutSecs,
            launchBrowser = launchBrowser,
        ).getOrElse { err ->
            if (err is PasskeyCanceledException || err.message == "canceled") {
                return LoginOutcome.Failure("", canceled = true)
            }
            val msg = if (err.message == "expired") {
                "通行密钥验证已过期，请重新尝试。"
            } else {
                "未能完成通行密钥验证，请重新尝试。"
            }
            return LoginOutcome.Failure(msg)
        }

        val verified = RustCoreBridge.verifyPasskeyCallback(
            callbackUrl = callbackUri,
            serverUrl = cleanUrl,
            expectedState = prepared.state,
            expectedChallenge = prepared.challenge,
            transactionToken = prepared.transactionToken,
        )
        if (!verified.ok || verified.finishBodyJson.isNullOrBlank()) {
            if (verified.errorCode == "canceled") {
                return LoginOutcome.Failure("", canceled = true)
            }
            return LoginOutcome.Failure(verified.errorMessageZh ?: "未能完成通行密钥验证，请重新尝试。")
        }

        val finishUrl = runCatching {
            RustCoreBridge.buildEndpointUrl(cleanUrl, listOf("mfa", "passkey", "authenticate", "finish"))
        }.getOrElse {
            return LoginOutcome.Failure("未能完成通行密钥验证，请重新尝试。")
        }
        val finishResp = runCatching {
            transport.execute(
                url = finishUrl,
                method = "POST",
                body = verified.finishBodyJson,
                contentType = "application/json",
            )
        }.getOrElse {
            return LoginOutcome.Failure("无法连接到服务：${it.message ?: "网络异常"}")
        }
        if (finishResp.status !in 200..299) {
            return LoginOutcome.Failure("未能完成通行密钥验证，请重新尝试。")
        }

        val root = runCatching { json.parseToJsonElement(finishResp.body).asObj() }.getOrNull()
            ?: return LoginOutcome.Failure("未能完成通行密钥验证，请重新尝试。")
        val payloadObj = root["data"].asObj() ?: root
        val token = payloadObj.str("access_token") ?: root.str("access_token")
        if (token.isNullOrBlank()) {
            return LoginOutcome.Failure("未能完成通行密钥验证，请重新尝试。")
        }

        val superUser = payloadObj.bool("super_user") ?: root.bool("super_user") ?: false
        val userName = payloadObj.str("user_name") ?: root.str("user_name") ?: trimmedUser
        val userLevel = payloadObj.int("level") ?: root.int("level") ?: 1
        val avatar = payloadObj.str("avatar") ?: root.str("avatar")
        val permsJson = payloadObj["permissions"]?.toString() ?: root["permissions"]?.toString() ?: "{}"

        val identityResp = runCatching {
            val meUrl = RustCoreBridge.buildEndpointUrl(cleanUrl, listOf("user", "current"))
            transport.execute(url = meUrl, method = "GET", token = token)
        }.getOrNull()

        var identity = UserIdentity(name = userName, isSuperuser = superUser, level = userLevel, avatar = avatar)
        var permissions = RustCoreBridge.evaluatePermissions(permsJson, superUser)

        if (identityResp != null && identityResp.status == 200) {
            val dataObj = extractObject(identityResp.body)
            if (dataObj != null) {
                val isSu = dataObj.bool("is_superuser") ?: superUser
                identity = UserIdentity(
                    id = dataObj.int("id") ?: 0,
                    name = dataObj.str("name") ?: userName,
                    email = dataObj.str("email") ?: "",
                    isSuperuser = isSu,
                    isActive = dataObj.bool("is_active") ?: true,
                    isOtp = dataObj.bool("is_otp") ?: false,
                    level = dataObj.int("level") ?: userLevel,
                    avatar = dataObj.str("avatar") ?: avatar,
                )
                permissions = RustCoreBridge.evaluatePermissions(
                    dataObj["permissions"]?.toString() ?: permsJson,
                    isSu,
                )
            }
        }

        if (secretStore.keepLogin) {
            secretStore.saveToken(cleanUrl, token)
        }
        secretStore.upsertServer(
            SavedServerEntry(
                id = cleanUrl.hashCode().toString(),
                name = cleanUrl.substringAfter("://").substringBefore("/").substringBefore(":"),
                url = cleanUrl,
                username = identity.name,
                lastUsedEpochMs = System.currentTimeMillis(),
            ),
        )
        _savedServers.value = secretStore.loadServers()
        resourceCookiePrimed = false
        globalImageConfig = secretStore.loadGlobalImageConfig(cleanUrl) ?: GlobalImageConfigSnapshot()
        refreshGlobalImageSettings(cleanUrl)
        setSession(SessionState.Authenticated(cleanUrl, token, identity, permissions))
        primeResourceCookie()
        return LoginOutcome.Success(identity)
    }

    /** 显式退出当前会话并使其在途响应的失效处理器全部过期。 */
    fun logout(notice: String? = null) {
        transport.clearCookies()
        resourceCookiePrimed = false
        clearSessionCaches()
        runCatching {
            appContext.getSharedPreferences("mp_agent_state_v3", Context.MODE_PRIVATE).edit().clear().apply()
        }
        val current = _session.value
        val url = when (current) {
            is SessionState.Authenticated -> current.serverUrl
            is SessionState.NeedsLogin -> current.serverUrl
            SessionState.Unconnected -> null
        }
        if (url != null) {
            secretStore.clearToken(url)
            setSession(SessionState.NeedsLogin(url, notice))
        } else {
            setSession(SessionState.Unconnected)
        }
    }

    /** 统一带认证请求执行器：经 Rust 判定 401/令牌失效 403 自动清缓存退登录。 */
    suspend fun authedRequest(
        segments: List<String>,
        method: String = "GET",
        query: List<Pair<String, String>> = emptyList(),
        body: String? = null,
        trailingSlash: Boolean = false,
        extraHeaders: Map<String, String> = emptyMap(),
        expectedSession: SessionState.Authenticated? = null,
    ): Result<NativeHttpResponse> {
        val current = _session.value as? SessionState.Authenticated
            ?: return Result.failure(IllegalStateException("未登录"))
        val auth = expectedSession ?: current
        if (current.serverUrl != auth.serverUrl || current.token != auth.token) {
            return Result.failure(IllegalStateException("请求所属会话已切换"))
        }
        val url = if (segments.any { seg -> seg.any { it.code > 127 || it == ' ' } }) {
            // 含中文或空格路径段（如 `/tmdb/credits/{id}/电视剧` 或 `/account-bindings/My Emby`）直接单次 UTF-8 百分号编码
            val base = auth.serverUrl.trimEnd('/')
            val encodedPath = segments.joinToString("/") { seg ->
                URLEncoder.encode(seg, "UTF-8").replace("+", "%20")
            }
            val qs = if (query.isEmpty()) "" else "?" + query.joinToString("&") { (k, v) ->
                "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
            }
            "$base/api/v1/$encodedPath${if (trailingSlash) "/" else ""}$qs"
        } else {
            runCatching {
                RustCoreBridge.buildEndpointUrl(auth.serverUrl, segments, query, trailingSlash)
            }.getOrElse { return Result.failure(it) }
        }
        val onAuthFailure = captureAuthFailureHandler(url, auth.token)
        val resp = runCatching {
            transport.execute(
                url = url,
                method = method,
                token = auth.token,
                body = body,
                extraHeaders = extraHeaders,
            )
        }.getOrElse { return Result.failure(it) }

        if (RustCoreBridge.classifyAuthStatus(resp.status, resp.body) == "logout") {
            onAuthFailure?.invoke()
            return Result.failure(IllegalStateException("登录状态已过期"))
        }
        return Result.success(resp)
    }

    /**
     * 从 `/api/v1/system/global?token=moviepilot` 同步当前实例的全局图片缓存开关与自定义图源域名。
     * 该接口使用固定查询令牌，不携带主登录态，避免旧版后端或网关异常误触发会话注销。
     */
    suspend fun refreshGlobalImageSettings(targetServerUrl: String? = null): GlobalImageConfigSnapshot {
        val urlBase = targetServerUrl
            ?: (_session.value as? SessionState.Authenticated)?.serverUrl
            ?: (_session.value as? SessionState.NeedsLogin)?.serverUrl
            ?: return globalImageConfig
        val endpoint = runCatching {
            RustCoreBridge.buildEndpointUrl(
                urlBase,
                listOf("system", "global"),
                listOf("token" to "moviepilot"),
            )
        }.getOrNull() ?: return globalImageConfig
        val resp = runCatching {
            transport.execute(url = endpoint, method = "GET", token = null)
        }.getOrNull() ?: return globalImageConfig
        if (resp.status !in 200..299) return globalImageConfig
        val data = extractObject(resp.body) ?: return globalImageConfig
        val prev = globalImageConfig
        val updated = GlobalImageConfigSnapshot(
            globalImageCache = data.bool("GLOBAL_IMAGE_CACHE") ?: prev.globalImageCache,
            tmdbImageDomain = normalizeTmdbDomain(data.str("TMDB_IMAGE_DOMAIN") ?: prev.tmdbImageDomain),
            bangumiProxyEnable = data.bool("BANGUMI_PROXY_ENABLE") ?: prev.bangumiProxyEnable,
            bangumiImageDomain = (data.str("BANGUMI_IMAGE_DOMAIN") ?: prev.bangumiImageDomain).trim(),
        )
        globalImageConfig = updated
        secretStore.saveGlobalImageConfig(urlBase, updated)
        if (updated != prev) {
            cachedDiscover = null
            cachedExplore.clear()
            siteIconCache.clear()
            mediaLogoCache.clear()
        }
        return updated
    }

    /**
     * 解析图片展示地址，严格对齐 Web `imageUtils.ts`（`getDisplayImageUrl` / `getProxyImageUrl`）：
     * - `GLOBAL_IMAGE_CACHE == true`：所有外部图片统一走服务端 `/api/v1/system/cache/image`（或带参数的 `/system/img/{1|0}`），复用服务端代理与磁盘缓存；
     * - `GLOBAL_IMAGE_CACHE == false`：豆瓣、媒体服务器、内网及启用代理的 Bangumi 走对应 `/system/img/{0|1}?cache=false`，其余公开 HTTPS 图源优先客户端直连，失败时由 `NativeHttpTransport.buildImageClient` 自动回退服务端 `/system/img/1?cache=false`。
     */
    fun resolveImageUrl(raw: String?, maxWidth: Int? = null, useCookies: Boolean = false): String? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim()
        if (trimmed.equals("null", ignoreCase = true) || trimmed.equals("none", ignoreCase = true)) return null
        if (trimmed.startsWith("data:image/")) return trimmed
        val auth = _session.value as? SessionState.Authenticated
        if (trimmed.startsWith("/api/")) {
            return if (auth != null) "${auth.serverUrl.trimEnd('/')}$trimmed" else trimmed
        }
        val cfg = globalImageConfig
        val tmdbDomain = normalizeTmdbDomain(cfg.tmdbImageDomain)
        val sizeBucket = when {
            maxWidth != null && maxWidth <= 500 -> "w500"
            maxWidth != null && maxWidth <= 800 -> "w780"
            maxWidth != null -> "w1280"
            else -> "w500"
        }
        val candidate = when {
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> rewriteTmdbUrl(trimmed, tmdbDomain, sizeBucket)
            trimmed.startsWith("/") && !trimmed.contains("..") -> "https://$tmdbDomain/t/p/$sizeBucket$trimmed"
            else -> return null
        }
        if (auth == null) return candidate
        val base = auth.serverUrl.trimEnd('/')
        if (candidate.startsWith("$base/api/")) return candidate

        val isBangumi = isBangumiImageUrl(candidate)
        if (isBangumi && cfg.bangumiProxyEnable) {
            val proxiedBangumi = buildBangumiImageProxyUrl(candidate, cfg.bangumiImageDomain)
            val encoded = URLEncoder.encode(proxiedBangumi, "UTF-8")
            val cacheParam = if (cfg.globalImageCache) "&cache=true" else "&cache=false"
            return "$base/api/v1/system/img/1?imgurl=$encoded$cacheParam"
        }

        val serverHost = runCatching { java.net.URI(base).host }.getOrNull()
        val isMediaServer = isMediaServerImageUrl(candidate)
        val isDouban = isDoubanImageUrl(candidate)
        val isInternal = isInternalOrSameHostUrl(candidate, serverHost)
        val isPlainHttp = candidate.startsWith("http://", ignoreCase = true)

        if (useCookies || isMediaServer || isDouban || isInternal || isPlainHttp) {
            if (cfg.globalImageCache && !useCookies && !isMediaServer && maxWidth == null) {
                val encoded = URLEncoder.encode(candidate, "UTF-8")
                return "$base/api/v1/system/cache/image?url=$encoded"
            }
            val encoded = URLEncoder.encode(candidate, "UTF-8")
            val cacheValue = if (cfg.globalImageCache) "true" else "false"
            val widthQuery = if (maxWidth != null) "&maxWidth=$maxWidth" else ""
            val cookieQuery = if (useCookies) "&use_cookies=true" else ""
            return "$base/api/v1/system/img/0?imgurl=$encoded&cache=$cacheValue$widthQuery$cookieQuery"
        }

        if (cfg.globalImageCache) {
            val encoded = URLEncoder.encode(candidate, "UTF-8")
            return "$base/api/v1/system/cache/image?url=$encoded"
        }

        return candidate
    }

    /**
     * 解析插件图标地址（对齐 Web `PluginCard.vue` / `PluginAppCard.vue` 与 iOS `NativePluginIconView`）：
     * - `data:image/`、`http://`、`https://` 与 `/api/...` 沿用通用图片代理与缓存策略；
     * - 合法裸文件名及可选 `plugin_icon/` 相对路径解析为同源 `{serverUrl}/plugin_icon/{encoded}`，
     *   若直连后端端口或前端静态目录缺失，则由 `NativeHttpTransport.buildImageClient` 自动回退官方插件仓库图标；
     * - 空值、无扩展名、路径分隔符及 `..` 一律返回 `null` 回退默认插件图标。
     */
    fun resolvePluginIconUrl(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val trimmed = raw.trim()
        if (trimmed.equals("null", ignoreCase = true) || trimmed.equals("none", ignoreCase = true)) return null
        if (
            trimmed.startsWith("data:image/") ||
            trimmed.startsWith("http://") ||
            trimmed.startsWith("https://") ||
            trimmed.startsWith("/api/")
        ) {
            return resolveImageUrl(trimmed)
        }
        val fileName = extractSafePluginIconFileName(trimmed) ?: return null
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val encoded = URLEncoder.encode(fileName, "UTF-8").replace("+", "%20")
        return "${auth.serverUrl.trimEnd('/')}/plugin_icon/$encoded"
    }

    /** 为公开外链构造服务端代理回退地址（保持当前全局缓存开关，外部图源启用 `proxy=1`）。 */
    fun buildExternalImageFallbackUrl(externalUrl: String): String? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val base = auth.serverUrl.trimEnd('/')
        val cfg = globalImageConfig
        if (cfg.globalImageCache) {
            return "$base/api/v1/system/cache/image?url=${URLEncoder.encode(externalUrl, "UTF-8")}"
        }
        val serverHost = runCatching { java.net.URI(base).host }.getOrNull()
        val proxyFlag = if (isDoubanImageUrl(externalUrl) || isInternalOrSameHostUrl(externalUrl, serverHost)) 0 else 1
        return "$base/api/v1/system/img/$proxyFlag?imgurl=${URLEncoder.encode(externalUrl, "UTF-8")}&cache=false"
    }

    private fun normalizeTmdbDomain(raw: String?): String {
        var s = raw?.trim().orEmpty()
        if (s.startsWith("https://", ignoreCase = true)) s = s.substring(8)
        else if (s.startsWith("http://", ignoreCase = true)) s = s.substring(7)
        s = s.trimEnd('/')
        val slash = s.indexOf('/')
        if (slash >= 0) s = s.substring(0, slash)
        return s.ifEmpty { "image.tmdb.org" }
    }

    private fun rewriteTmdbUrl(url: String, tmdbDomain: String, sizeBucket: String): String {
        val uri = runCatching { java.net.URI(url) }.getOrNull() ?: return url
        val host = uri.host?.lowercase() ?: return url
        if (host != "image.tmdb.org" && host != tmdbDomain.substringBefore(':').lowercase()) {
            return url
        }
        val rawPath = uri.rawPath.orEmpty()
        val nextPath = if (rawPath.startsWith("/t/p/original/")) {
            "/t/p/$sizeBucket/" + rawPath.removePrefix("/t/p/original/")
        } else {
            rawPath
        }
        val scheme = uri.scheme ?: "https"
        val queryPart = uri.rawQuery?.takeIf { it.isNotEmpty() }?.let { "?$it" }.orEmpty()
        return "$scheme://$tmdbDomain$nextPath$queryPart"
    }

    private fun isBangumiImageUrl(url: String): Boolean {
        val host = runCatching { java.net.URI(url).host?.lowercase()?.trimEnd('.') }.getOrNull() ?: return false
        if (host == "bgm.tv" || host == "bangumi.tv" || host == "bangumi.lol") return true
        return host.endsWith(".bgm.tv") || host.endsWith(".bangumi.tv") || host.endsWith(".bangumi.lol")
    }

    private fun isDoubanImageUrl(url: String): Boolean {
        val host = runCatching { java.net.URI(url).host?.lowercase()?.trimEnd('.') }.getOrNull() ?: return false
        return host == "doubanio.com" || host.endsWith(".doubanio.com")
    }

    private fun isMediaServerImageUrl(url: String): Boolean {
        val path = runCatching { java.net.URI(url).rawPath }.getOrNull() ?: return false
        if (Regex("/Items/[^/]+/Images/(?:Primary|Backdrop|Thumb)(?:/\\d+)?$", RegexOption.IGNORE_CASE).containsMatchIn(path)) {
            return true
        }
        val lower = path.lowercase()
        return lower.contains("/library/metadata/") || lower.contains("/photo/:/transcode")
    }

    private fun isInternalOrSameHostUrl(url: String, serverHost: String?): Boolean {
        val host = runCatching { java.net.URI(url).host?.lowercase()?.trim('[', ']') }.getOrNull() ?: return false
        if (!serverHost.isNullOrBlank() && host == serverHost.lowercase().trim('[', ']')) return true
        if (host == "localhost" || host == "::1" || host.endsWith(".local") || host.endsWith(".lan")) return true
        val parts = host.split('.')
        if (parts.size == 4 && parts.all { it.toIntOrNull() in 0..255 }) {
            val a = parts[0].toInt()
            val b = parts[1].toInt()
            if (a == 10 || a == 127) return true
            if (a == 192 && b == 168) return true
            if (a == 172 && b in 16..31) return true
            if (a == 169 && b == 254) return true
        }
        return false
    }

    private fun buildBangumiImageProxyUrl(imageUrl: String, baseUrl: String): String {
        if (!isBangumiImageUrl(imageUrl)) return imageUrl
        val rawBase = baseUrl.trim()
        if (rawBase.isEmpty()) return imageUrl
        val candidate = if ("://" in rawBase) rawBase else "https://$rawBase"
        val proxyUri = runCatching { java.net.URI(candidate) }.getOrNull() ?: return imageUrl
        val scheme = proxyUri.scheme?.lowercase() ?: return imageUrl
        if ((scheme != "http" && scheme != "https") || proxyUri.host.isNullOrBlank() || proxyUri.rawFragment != null) {
            return imageUrl
        }
        if (!proxyUri.rawQuery.isNullOrEmpty()) {
            val encoded = URLEncoder.encode(imageUrl, "UTF-8").replace("+", "%20")
            return "$candidate$encoded"
        }
        val normalizedBase = candidate.trimEnd('/')
        if (rawBase.endsWith("/")) {
            val sourceUri = runCatching { java.net.URI(imageUrl) }.getOrNull() ?: return imageUrl
            if (sourceUri.host.equals(proxyUri.host, ignoreCase = true)) return imageUrl
            val queryPart = sourceUri.rawQuery?.takeIf { it.isNotEmpty() }?.let { "?$it" }.orEmpty()
            return "$normalizedBase${sourceUri.rawPath.orEmpty()}$queryPart"
        }
        return "$normalizedBase/$imageUrl"
    }

    // ==================== 发现 / 探索 / 搜索 / 详情 / 音乐 ====================

    suspend fun fetchDiscoverTrending(page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("recommend", "tmdb_trending"), listOf("page" to page.toString()))

    suspend fun fetchDoubanShowing(page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("recommend", "douban_showing"), listOf("page" to page.toString()))

    suspend fun fetchDoubanTop250(page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("recommend", "douban_top250"), listOf("page" to page.toString()))

    suspend fun fetchExplore(
        source: String,
        page: Int = 1,
        genre: String? = null,
        sort: String? = null,
        language: String? = null,
        doubanTag: String? = null,
        bangumiCat: String? = null,
    ): List<MediaCardItem> {
        val query = mutableListOf("page" to page.toString())
        when (source) {
            "tmdb_movies", "tmdb_tvs" -> {
                val mappedSort = when (sort) {
                    "最新" -> if (source == "tmdb_tvs") "first_air_date.desc" else "release_date.desc"
                    "高分" -> "vote_average.desc"
                    else -> "popularity.desc"
                }
                query += "sort_by" to mappedSort
                val genreId = TMDB_GENRE_LABEL_TO_ID[genre]
                if (!genreId.isNullOrBlank()) query += "with_genres" to genreId
                val langCode = TMDB_LANG_LABEL_TO_CODE[language]
                if (!langCode.isNullOrBlank()) query += "with_original_language" to langCode
            }
            "douban_movies", "douban_tvs" -> {
                val mappedSort = when (sort) {
                    "最新" -> "R"
                    "高分" -> "S"
                    else -> "U"
                }
                query += "sort" to mappedSort
                if (!doubanTag.isNullOrBlank() && doubanTag != "全部") {
                    query += "tags" to doubanTag
                }
            }
            "bangumi" -> {
                query += "type" to "2"
                query += "count" to "30"
                val mappedSort = when (sort) {
                    "高分" -> "rank"
                    "最新" -> "date"
                    else -> "heat"
                }
                query += "sort" to mappedSort
                if (!bangumiCat.isNullOrBlank()) query += "cat" to bangumiCat
            }
        }
        return fetchMediaList(listOf("discover", source), query)
    }

    /** 拉取后端已启用的媒体搜索数据源目录（`GET /api/v1/media/source`）。 */
    suspend fun fetchMediaSearchSources(): List<MediaSearchSourceDto> {
        val resp = authedRequest(listOf("media", "source")).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        resourceCookiePrimed = true
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val src = obj.str("media_source")?.trim()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val name = obj.str("name")?.trim()?.takeIf { it.isNotBlank() } ?: src
            val types = obj["media_types"].asArr()
                ?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s != "null" && s.isNotBlank() } }
                ?.takeIf { it.isNotEmpty() }
                ?: listOf("电影", "电视剧")
            MediaSearchSourceDto(id = src, name = name, mediaTypes = types)
        }.sortedBy { it.displayName.lowercase() }
    }

    /**
     * 全局多域媒体检索：
     * - `library` 调用 `GET /api/v1/mediaserver/search`（支持 `type` 类型筛选）；
     * - 其余分类调用 `GET /api/v1/media/search`（支持重复传入多个 `media_source` 实现多选来源筛选）。
     */
    suspend fun searchMedia(
        keyword: String,
        kind: String = "media",
        page: Int = 1,
        sources: Collection<String> = emptyList(),
        libraryTypes: Collection<String> = emptyList(),
    ): List<MediaCardItem> {
        val cleanKw = keyword.trim()
        if (cleanKw.isBlank()) return emptyList()
        if (kind == "library") {
            val query = buildList {
                add("keyword" to cleanKw)
                add("limit" to "40")
                libraryTypes.filter { it.isNotBlank() }.forEach { add("type" to it) }
            }
            val resp = authedRequest(listOf("mediaserver", "search"), query = query).getOrNull() ?: return emptyList()
            if (resp.status !in 200..299) return emptyList()
            return extractArray(resp.body).mapNotNull { el ->
                parseMediaCard(el)?.let { parsed ->
                    val obj = el.asObj()
                    val fallbackItemId = parsed.serverItemId
                        ?: obj?.str("item_id")?.takeIf { it.isNotBlank() }
                        ?: obj?.str("id")?.takeIf { it.isNotBlank() }
                    parsed.copy(
                        inLibrary = true,
                        serverItemId = fallbackItemId,
                    )
                }
            }
        }
        val query = buildList {
            add("title" to cleanKw)
            add("type" to kind)
            add("page" to page.toString())
            add("count" to "20")
            sources.map { it.trim() }.filter { it.isNotBlank() }.distinct().sorted().forEach { src ->
                add("media_source" to src)
            }
        }
        return fetchMediaList(listOf("media", "search"), query)
    }

    /** 拉取 `/api/v1/media/{id}?media_source=...&type_name=...` 完整媒体详情（含透明片名 Logo、时长、分季、分级等）。 */
    suspend fun fetchMediaDetail(item: MediaCardItem): MediaCardItem? {
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        ) ?: return null
        val (src, lookupId) = identity
        val typeName = canonicalMediaType(item.type)
        val resp = authedRequest(
            segments = listOf("media", lookupId),
            query = listOf("media_source" to src, "type_name" to typeName),
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val parsed = parseMediaCard(obj) ?: return null
        if (!parsed.logoPath.isNullOrBlank()) {
            mediaLogoCache["$src:$lookupId"] = parsed.logoPath
        }
        return parsed.copy(
            season = parsed.season ?: item.season,
            serverItemId = item.serverItemId ?: parsed.serverItemId,
            serverName = item.serverName ?: parsed.serverName,
            serverType = item.serverType ?: parsed.serverType,
        )
    }

    /** 为发现页 Hero 异步补拉透明片名 Logo（带内存缓存，与 iOS `hydrateHeroLogos` 一致）。 */
    suspend fun fetchHeroLogo(item: MediaCardItem): String? {
        if (!item.logoPath.isNullOrBlank()) return item.logoPath
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        ) ?: return null
        val key = "${identity.first}:${identity.second}"
        mediaLogoCache[key]?.let { return it }
        return fetchMediaDetail(item)?.logoPath
    }

    /** 基于手头已有评分构造零延迟初始多元评分微标列表。 */
    fun seedRatingsForCard(
        item: MediaCardItem,
        criticRating: Double = 0.0,
        serverRatings: List<MediaRatingBadgeDto> = emptyList(),
    ): List<MediaRatingBadgeDto> {
        val bySrc = LinkedHashMap<String, String>()
        serverRatings.forEach { badge ->
            val norm = normalizeRatingSourceKey(badge.source)
            if (badge.label.isNotBlank() && norm != null && !bySrc.containsKey(norm)) {
                bySrc[norm] = badge.label
            }
        }
        if (!bySrc.containsKey("rottentomatoes") && criticRating > 0.0) {
            bySrc["rottentomatoes"] = "${criticRating.roundToInt().coerceIn(1, 100)}%"
        }
        if (item.voteAverage > 0.0) {
            val norm = normalizeRatingSourceKey(item.source) ?: "community"
            bySrc.putIfAbsent(norm, String.format(java.util.Locale.US, "%.1f", item.voteAverage.coerceAtMost(10.0)))
        }
        return orderRatingBadges(bySrc)
    }

    private fun normalizeRatingSourceKey(raw: String?): String? = when (raw?.trim()?.lowercase()) {
        "imdb" -> "imdb"
        "themoviedb", "tmdb" -> "tmdb"
        "rottentomatoes", "rotten_tomatoes", "rt", "critic" -> "rottentomatoes"
        "douban", "douban_movie" -> "douban"
        "bangumi", "bgm" -> "bangumi"
        "anilist" -> "anilist"
        "community" -> "community"
        else -> null
    }

    private fun orderRatingBadges(map: Map<String, String>): List<MediaRatingBadgeDto> {
        val order = listOf("imdb", "tmdb", "rottentomatoes", "douban", "bangumi", "anilist")
        val out = mutableListOf<MediaRatingBadgeDto>()
        for (src in order) {
            val label = map[src]
            if (!label.isNullOrBlank()) out += MediaRatingBadgeDto(src, label)
        }
        val hasNamedTenScale = out.any { it.source != "rottentomatoes" }
        if (!hasNamedTenScale) {
            map["community"]?.takeIf { it.isNotBlank() }?.let { out.add(0, MediaRatingBadgeDto("community", it)) }
        }
        return out
    }

    /**
     * 异步并发聚合免配置多元评分（IMDb / TMDB / 烂番茄影评新鲜度 / 豆瓣 / Bangumi），带会话级内存缓存。
     */
    suspend fun fetchMultiSourceRatings(
        item: MediaCardItem,
        criticRating: Double = 0.0,
        serverRatings: List<MediaRatingBadgeDto> = emptyList(),
        serverItemId: String? = null,
        serverName: String? = null,
    ): List<MediaRatingBadgeDto> {
        val typeName = canonicalMediaType(item.type)
        val cacheKey = buildString {
            append(typeName).append('|')
            append(item.tmdbId?.let { "tmdb:$it" } ?: item.imdbId?.takeIf { it.isNotBlank() }?.let { "imdb:$it" }
                ?: item.doubanId?.takeIf { it.isNotBlank() }?.let { "douban:$it" } ?: item.resolvedId)
        }
        multiRatingsCache[cacheKey]?.takeIf { it.isNotEmpty() }?.let { return it }

        val scores = LinkedHashMap<String, String>()
        seedRatingsForCard(item, criticRating, serverRatings).forEach { scores[it.source] = it.label }

        var tmdbId = item.tmdbId?.toString()
            ?: (if (item.source.equals("themoviedb", true) || item.source.equals("tmdb", true)) item.mediaId?.substringAfterLast(':') else null)
        var imdbId = item.imdbId?.takeIf { it.isNotBlank() }
            ?: (if (item.source.equals("imdb", true)) item.mediaId?.substringAfterLast(':') else null)
        var doubanId = item.doubanId?.takeIf { it.isNotBlank() }
            ?: (if (item.source.equals("douban", true)) item.mediaId?.substringAfterLast(':') else null)
        val bangumiId = item.bangumiId?.toString()
            ?: (if (item.source.equals("bangumi", true)) item.mediaId?.substringAfterLast(':') else null)
        var title = item.title.trim()
        var year = item.year.trim()
        var genres = item.genres

        if (!tmdbId.isNullOrBlank() && (!scores.containsKey("tmdb") || imdbId.isNullOrBlank())) {
            val resp = authedRequest(
                segments = listOf("media", tmdbId),
                query = listOf("media_source" to "themoviedb", "type_name" to typeName),
            ).getOrNull()
            val obj = if (resp != null && resp.status in 200..299) extractObject(resp.body) else null
            if (obj != null) {
                val v = obj.dbl("vote_average") ?: 0.0
                if (v > 0.0 && !scores.containsKey("tmdb")) {
                    scores["tmdb"] = String.format(java.util.Locale.US, "%.1f", v.coerceAtMost(10.0))
                }
                if (imdbId.isNullOrBlank()) imdbId = obj.str("imdb_id")?.takeIf { it.isNotBlank() }
                if (doubanId.isNullOrBlank()) doubanId = obj.str("douban_id")?.takeIf { it.isNotBlank() }
                if (title.isBlank()) title = obj.str("title").orEmpty()
                if (year.isBlank()) year = obj.str("year").orEmpty()
                if (genres.isEmpty()) genres = parseMediaCard(obj)?.genres.orEmpty()
            }
        }

        val isAnime = item.source.equals("bangumi", true) || item.source.equals("anilist", true) ||
            genres.any { it.contains("动画") || it.equals("Animation", true) }

        coroutineScope {
            val imdbDef = async {
                val id = imdbId?.trim()
                if (!scores.containsKey("imdb") && !id.isNullOrBlank() && id.startsWith("tt", true)) {
                    val r = authedRequest(
                        segments = listOf("media", id),
                        query = listOf("media_source" to "imdb", "type_name" to typeName),
                    ).getOrNull()
                    val v = if (r != null && r.status in 200..299) extractObject(r.body)?.dbl("vote_average") ?: 0.0 else 0.0
                    if (v > 0.0) String.format(java.util.Locale.US, "%.1f", v.coerceAtMost(10.0)) else null
                } else null
            }
            val doubanDef = async {
                if (scores.containsKey("douban")) return@async null
                val id = doubanId?.trim()
                if (!id.isNullOrBlank() && id != "0") {
                    val r = authedRequest(
                        segments = listOf("media", id),
                        query = listOf("media_source" to "douban", "type_name" to typeName),
                    ).getOrNull()
                    val v = if (r != null && r.status in 200..299) extractObject(r.body)?.dbl("vote_average") ?: 0.0 else 0.0
                    return@async if (v > 0.0) String.format(java.util.Locale.US, "%.1f", v.coerceAtMost(10.0)) else null
                }
                if (title.isBlank()) return@async null
                recognizeRatingBySource(title, year, typeName, "douban")
            }
            val bangumiDef = async {
                if (scores.containsKey("bangumi")) return@async null
                val id = bangumiId?.trim()
                if (!id.isNullOrBlank() && id != "0") {
                    val r = authedRequest(
                        segments = listOf("media", id),
                        query = listOf("media_source" to "bangumi", "type_name" to typeName),
                    ).getOrNull()
                    val v = if (r != null && r.status in 200..299) extractObject(r.body)?.dbl("vote_average") ?: 0.0 else 0.0
                    return@async if (v > 0.0) String.format(java.util.Locale.US, "%.1f", v.coerceAtMost(10.0)) else null
                }
                if (!isAnime || title.isBlank()) return@async null
                recognizeRatingBySource(title, year, typeName, "bangumi")
            }
            val srvDef = async {
                val sid = serverItemId?.trim()
                if (!scores.containsKey("rottentomatoes") && !sid.isNullOrBlank()) {
                    fetchMediaServerItemDetail(sid, serverName, enrichMetadata = false)
                } else null
            }

            imdbDef.await()?.let { scores.putIfAbsent("imdb", it) }
            doubanDef.await()?.let { scores.putIfAbsent("douban", it) }
            bangumiDef.await()?.let { scores.putIfAbsent("bangumi", it) }
            srvDef.await()?.let { srv ->
                srv.ratings.forEach { b ->
                    normalizeRatingSourceKey(b.source)?.let { k -> if (b.label.isNotBlank()) scores.putIfAbsent(k, b.label) }
                }
                if (srv.criticRating > 0.0) {
                    scores.putIfAbsent("rottentomatoes", "${srv.criticRating.roundToInt().coerceIn(1, 100)}%")
                }
            }
        }

        val ordered = orderRatingBadges(scores)
        if (ordered.isNotEmpty()) {
            multiRatingsCache[cacheKey] = ordered
        }
        return ordered
    }

    private suspend fun recognizeRatingBySource(
        title: String,
        year: String,
        expectedType: String,
        mediaSource: String,
    ): String? {
        val queryTitle = if (year.length >= 4) "$title ${year.take(4)}" else title
        val resp = authedRequest(
            segments = listOf("media", "recognize"),
            query = listOf("title" to queryTitle, "media_source" to mediaSource),
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val media = extractObject(resp.body)?.get("media_info").asObj() ?: return null
        val vote = media.dbl("vote_average") ?: 0.0
        if (vote <= 0.0) return null
        val gotType = media.str("type")?.let { canonicalMediaType(it) }
        if (!gotType.isNullOrBlank() && gotType != expectedType) return null
        val reqY = year.take(4).toIntOrNull()
        val gotY = media.str("year")?.take(4)?.toIntOrNull()
        if (reqY != null && gotY != null && kotlin.math.abs(reqY - gotY) > 1) return null
        return String.format(java.util.Locale.US, "%.1f", vote.coerceAtMost(10.0))
    }

    /** 拉取影视演职员列表（自动路由 TMDB / 豆瓣 / Bangumi）。 */
    suspend fun fetchMediaCredits(item: MediaCardItem): List<MediaPersonDto> {
        val typeName = canonicalMediaType(item.type)
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val segs = when {
            identity?.first == "douban" -> listOf("douban", "credits", identity.second, typeName)
            identity?.first == "bangumi" -> listOf("bangumi", "credits", identity.second)
            item.tmdbId != null -> listOf("tmdb", "credits", item.tmdbId.toString(), typeName)
            identity?.first == "themoviedb" -> listOf("tmdb", "credits", identity.second, typeName)
            !item.doubanId.isNullOrBlank() -> listOf("douban", "credits", item.doubanId, typeName)
            else -> return emptyList()
        }
        val resp = authedRequest(segs).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val name = obj.str("name") ?: obj.str("title") ?: return@mapNotNull null
            MediaPersonDto(
                id = obj.str("id") ?: "",
                name = name,
                character = obj.str("character") ?: obj.str("roles") ?: obj.str("job") ?: "",
                department = obj.str("known_for_department") ?: "",
                profilePath = resolveImageUrl(obj.str("profile_path") ?: obj.str("avatar") ?: obj.str("image"), maxWidth = 300),
                source = if (segs.first() == "douban") "douban" else "themoviedb",
            )
        }
    }

    /** 拉取电视剧分季列表（`/api/v1/tmdb/seasons/{tmdb_id}`）。 */
    suspend fun fetchMediaSeasons(tmdbId: Int): List<MediaSeasonDto> {
        val resp = authedRequest(listOf("tmdb", "seasons", tmdbId.toString())).getOrNull() ?: return emptyList()
        return parseSeasonArray(resp.body)
    }

    /** 按任意数据源身份拉取剧集全部季信息（优先 TMDB，回落 `/api/v1/media/seasons`）。 */
    suspend fun fetchMediaSeasonsForItem(item: MediaCardItem): List<MediaSeasonDto> {
        item.tmdbId?.takeIf { it > 0 }?.let { tid ->
            val tmdbList = fetchMediaSeasons(tid)
            if (tmdbList.isNotEmpty()) return tmdbList
        }
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val query = buildList {
            if (identity != null) {
                add("media_source" to identity.first)
                add("media_id" to identity.second)
            } else if (item.title.isNotBlank()) {
                add("title" to item.title)
                if (item.year.isNotBlank()) add("year" to item.year)
            }
        }
        if (query.isEmpty()) return emptyList()
        val resp = authedRequest(listOf("media", "seasons"), query = query).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return parseSeasonArray(resp.body)
    }

    private fun parseSeasonArray(rawBody: String?): List<MediaSeasonDto> {
        return extractArray(rawBody).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val num = obj.int("season_number") ?: return@mapNotNull null
            if (num < 0) return@mapNotNull null
            val defaultName = if (num == 0) "特别篇" else "第 $num 季"
            MediaSeasonDto(
                seasonNumber = num,
                name = obj.str("name")?.takeIf { it.isNotBlank() } ?: defaultName,
                overview = obj.str("overview") ?: "",
                airDate = obj.str("air_date") ?: "",
                episodeCount = obj.int("episode_count") ?: 0,
                posterPath = resolveImageUrl(obj.str("poster_path"), maxWidth = 400),
                voteAverage = obj.dbl("vote_average") ?: 0.0,
            )
        }.sortedWith(compareBy<MediaSeasonDto> { it.seasonNumber == 0 }.thenBy { it.seasonNumber })
    }

    /** 拉取电视剧单季分集列表（`/api/v1/tmdb/{tmdb_id}/{season}`）。 */
    suspend fun fetchSeasonEpisodes(tmdbId: Int, seasonNumber: Int): List<MediaEpisodeDto> {
        val resp = authedRequest(listOf("tmdb", tmdbId.toString(), seasonNumber.toString())).getOrNull() ?: return emptyList()
        return parseEpisodeArray(resp.body)
    }

    /** 智能拉取单季分集元数据（优先 TMDB，回落已入库条目的 `/api/v1/mediaserver/episode-metadata`）。 */
    suspend fun fetchSeasonEpisodesSmart(
        item: MediaCardItem,
        seasonNumber: Int,
        seriesItemId: String? = null,
        server: String? = null,
    ): List<MediaEpisodeDto> {
        val tmdbId = item.tmdbId ?: item.mediaId?.removePrefix("tmdb:")?.toIntOrNull()
        if (tmdbId != null && tmdbId > 0) {
            val eps = fetchSeasonEpisodes(tmdbId, seasonNumber)
            if (eps.isNotEmpty()) return eps
        }
        val sid = seriesItemId?.trim().orEmpty()
        if (sid.isNotEmpty()) {
            val q = buildList {
                add("itemid" to sid)
                add("season" to seasonNumber.toString())
                if (!server.isNullOrBlank()) add("server" to server)
            }
            val resp = authedRequest(listOf("mediaserver", "episode-metadata"), query = q).getOrNull()
            if (resp != null && resp.status in 200..299) {
                val parsed = parseEpisodeArray(resp.body)
                if (parsed.isNotEmpty()) return parsed
            }
        }
        return emptyList()
    }

    private fun parseEpisodeArray(rawBody: String?): List<MediaEpisodeDto> {
        return extractArray(rawBody).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            MediaEpisodeDto(
                episodeNumber = obj.int("episode_number") ?: return@mapNotNull null,
                name = obj.str("name") ?: "",
                overview = obj.str("overview") ?: "",
                airDate = obj.str("air_date") ?: "",
                runtime = obj.int("runtime"),
                stillPath = resolveImageUrl(obj.str("still_path"), maxWidth = 600),
                voteAverage = obj.dbl("vote_average") ?: 0.0,
            )
        }.sortedBy { it.episodeNumber }
    }

    /** 查询已入库电视剧各季可播放单集映射（`GET /api/v1/mediaserver/episodes?itemid=...`）。 */
    suspend fun fetchPlayableSeriesEpisodes(
        seriesItemId: String,
        server: String? = null,
    ): Map<Int, Map<Int, String>> {
        val sid = seriesItemId.trim()
        if (sid.isEmpty()) return emptyMap()
        val q = buildList {
            add("itemid" to sid)
            if (!server.isNullOrBlank()) add("server" to server)
        }
        val resp = authedRequest(listOf("mediaserver", "episodes"), query = q).getOrNull() ?: return emptyMap()
        if (resp.status !in 200..299) return emptyMap()
        val dataObj = extractObject(resp.body) ?: return emptyMap()
        val result = mutableMapOf<Int, Map<Int, String>>()
        dataObj.forEach { (sKey, epMapEl) ->
            val sNum = sKey.toIntOrNull() ?: return@forEach
            val epObj = epMapEl.asObj() ?: return@forEach
            val inner = mutableMapOf<Int, String>()
            epObj.forEach { (eKey, idEl) ->
                val eNum = eKey.toIntOrNull() ?: return@forEach
                val epId = idEl.asPrim()?.content?.takeIf { it.isNotBlank() && it != "null" } ?: return@forEach
                inner[eNum] = epId
            }
            if (inner.isNotEmpty()) result[sNum] = inner
        }
        return result
    }

    /** 查询指定单季的可播放单集映射（`GET /api/v1/mediaserver/episodes/{itemid}/{season}`）。 */
    suspend fun fetchPlayableSeasonEpisodes(
        seriesItemId: String,
        seasonNumber: Int,
        server: String? = null,
    ): Map<Int, String> {
        val sid = seriesItemId.trim()
        if (sid.isEmpty()) return emptyMap()
        val q = if (!server.isNullOrBlank()) listOf("server" to server) else emptyList()
        val resp = authedRequest(
            segments = listOf("mediaserver", "episodes", sid, seasonNumber.toString()),
            query = q,
        ).getOrNull() ?: return emptyMap()
        if (resp.status !in 200..299) return emptyMap()
        val dataObj = extractObject(resp.body) ?: return emptyMap()
        val inner = mutableMapOf<Int, String>()
        dataObj.forEach { (eKey, idEl) ->
            val eNum = eKey.toIntOrNull() ?: return@forEach
            val epId = idEl.asPrim()?.content?.takeIf { it.isNotBlank() && it != "null" } ?: return@forEach
            inner[eNum] = epId
        }
        return inner
    }

    /** 查询远程媒体服务器已入库的季集编号集合（`POST /api/v1/mediaserver/exists_remote`）。 */
    suspend fun fetchRemoteExistingEpisodes(
        item: MediaCardItem,
        season: Int? = null,
    ): Map<Int, Set<Int>> {
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val payload = mutableMapOf<String, JsonElement>(
            "type" to JsonPrimitive("电视剧"),
            "title" to JsonPrimitive(item.title),
        )
        if (item.year.isNotBlank()) payload["year"] = JsonPrimitive(item.year)
        if (season != null) payload["season"] = JsonPrimitive(season)
        if (identity != null) {
            payload["media_source"] = JsonPrimitive(identity.first)
            payload["media_id"] = JsonPrimitive(identity.second)
        }
        item.tmdbId?.takeIf { it > 0 }?.let { payload["tmdbid"] = JsonPrimitive(it) }
        val resp = authedRequest(
            segments = listOf("mediaserver", "exists_remote"),
            method = "POST",
            body = JsonObject(payload).toString(),
        ).getOrNull() ?: return emptyMap()
        if (resp.status !in 200..299) return emptyMap()
        val dataObj = extractObject(resp.body) ?: return emptyMap()
        val out = mutableMapOf<Int, Set<Int>>()
        dataObj.forEach { (sKey, arrEl) ->
            val sNum = sKey.toIntOrNull() ?: return@forEach
            val eps = arrEl.asArr()?.mapNotNull { it.asPrim()?.intOrNull }?.toSet().orEmpty()
            if (eps.isNotEmpty()) out[sNum] = eps
        }
        return out
    }

    /** 拉取人物详情与代表作。 */
    suspend fun fetchPersonDetail(person: MediaPersonDto): Pair<MediaPersonDto, List<MediaCardItem>> {
        val prefix = if (person.source == "douban") "douban" else "tmdb"
        if (person.id.isBlank()) return person to emptyList()
        val detailObj = extractObject(authedRequest(listOf(prefix, "person", person.id)).getOrNull()?.body)
        val enriched = if (detailObj != null) {
            person.copy(
                name = detailObj.str("name") ?: person.name,
                biography = detailObj.str("biography") ?: detailObj.str("summary") ?: person.biography,
                birthday = detailObj.str("birthday") ?: person.birthday,
                placeOfBirth = detailObj.str("place_of_birth") ?: person.placeOfBirth,
                department = detailObj.str("known_for_department") ?: person.department,
                profilePath = resolveImageUrl(detailObj.str("profile_path") ?: detailObj.str("avatar"), maxWidth = 400) ?: person.profilePath,
            )
        } else person
        val credits = fetchMediaList(listOf(prefix, "person", "credits", person.id), listOf("page" to "1"))
        return enriched to credits
    }

    /** 拉取音乐发现四大榜单（豆瓣音乐 / 本周榜单 / 热门专辑 / 近期新发）。 */
    suspend fun fetchMusicFeed(feed: String, page: Int = 1): List<MusicAlbumDto> {
        val (segments, query) = buildMusicFeedEndpoint(feed, page)
        val resp = authedRequest(segments, query = query).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        val fallbackSource = if (feed == "popular" || feed == "latest") "musicbrainz" else "douban"
        return extractArray(resp.body).mapNotNull { el ->
            parseMusicAlbumObj(el.asObj(), fallbackSource = fallbackSource)
        }
    }

    private fun parseMusicAlbumObj(obj: JsonObject?, fallbackSource: String = "musicbrainz"): MusicAlbumDto? {
        if (obj == null) return null
        val title = obj.str("title") ?: obj.str("name") ?: return null
        val artistsList = obj["artists"].asArr()?.mapNotNull {
            it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" }
        }.orEmpty()
        val artistIdsList = obj["artist_ids"].asArr()?.mapNotNull {
            it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" }
        }.orEmpty()
        val primaryId = obj.str("media_id") ?: obj.str("douban_id") ?: obj.str("id") ?: obj.str("album_id") ?: title
        val albumLookup = obj.str("album_id")?.takeIf { it.isNotBlank() } ?: primaryId
        val rawYear = obj.str("year") ?: obj.int("year")?.toString() ?: obj.str("release_date")?.take(4) ?: ""
        return MusicAlbumDto(
            id = primaryId,
            albumId = albumLookup,
            releaseId = obj.str("musicbrainz_release_id")?.takeIf { it.isNotBlank() },
            title = title,
            artist = obj.str("artist") ?: artistsList.firstOrNull() ?: obj.str("author") ?: obj.str("subtitle") ?: obj.str("original_title") ?: "",
            artistId = artistIdsList.firstOrNull() ?: obj.str("artist_id")?.takeIf { it.isNotBlank() },
            year = rawYear,
            albumType = obj.str("album_type").orEmpty(),
            totalTracks = obj.int("total_tracks") ?: 0,
            coverUrl = resolveImageUrl(obj.str("cover_url") ?: obj.str("poster_path") ?: obj.str("cover") ?: obj.str("image"), maxWidth = 500),
            source = obj.str("media_source")?.takeIf { it.isNotBlank() } ?: fallbackSource,
            voteAverage = obj.dbl("rating")?.takeIf { it > 0.0 } ?: obj.dbl("vote_average") ?: 0.0,
            overview = obj.str("overview") ?: "",
        )
    }

    /** 拉取音乐专辑完整详情与分碟曲目清单（`GET /api/v1/music/album/{id}?media_source=...`）。 */
    suspend fun fetchMusicAlbumDetail(
        albumId: String,
        source: String,
        releaseId: String? = null,
    ): MusicAlbumDetailDto? {
        val cleanId = albumId.trim()
        if (cleanId.isEmpty()) return null
        val resolvedSource = source.ifBlank { "musicbrainz" }
        val query = buildList {
            add("media_source" to resolvedSource)
            if (!releaseId.isNullOrBlank()) {
                add("musicbrainz_release_id" to releaseId)
            }
        }
        val resp = authedRequest(listOf("music", "album", cleanId), query = query).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val artists = obj["artists"].asArr()?.mapNotNull {
            it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" }
        }.orEmpty()
        val artistIds = obj["artist_ids"].asArr()?.mapNotNull {
            it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" }
        }.orEmpty()
        val primaryArtist = obj.str("artist") ?: artists.firstOrNull().orEmpty()
        val tracks = obj["tracks"].asArr().orEmpty().mapIndexedNotNull { idx, trEl ->
            val tr = trEl.asObj() ?: return@mapIndexedNotNull null
            val trTitle = tr.str("title") ?: tr.str("name") ?: return@mapIndexedNotNull null
            val trArtists = tr["artists"].asArr()?.mapNotNull {
                it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" }
            }.orEmpty()
            MusicTrackDto(
                id = tr.str("media_id") ?: tr.str("id") ?: "$cleanId-${idx + 1}",
                title = trTitle,
                artist = tr.str("artist") ?: trArtists.firstOrNull() ?: primaryArtist,
                discNumber = (tr.int("disc_number") ?: tr.int("medium_number") ?: 1).coerceAtLeast(1),
                trackNumber = tr.int("track_number") ?: (idx + 1),
                durationSeconds = (tr.int("duration") ?: ((tr.lng("duration_ms") ?: 0L) / 1000L).toInt()).coerceAtLeast(0),
            )
        }
        return MusicAlbumDetailDto(
            id = obj.str("media_id") ?: obj.str("album_id") ?: cleanId,
            title = obj.str("title") ?: obj.str("name").orEmpty(),
            artist = primaryArtist,
            artists = artists,
            artistIds = artistIds,
            albumType = obj.str("album_type").orEmpty(),
            year = obj.str("year") ?: obj.int("year")?.toString() ?: obj.str("release_date")?.take(4).orEmpty(),
            totalTracks = obj.int("total_tracks") ?: tracks.size,
            coverUrl = resolveImageUrl(obj.str("cover_url") ?: obj.str("poster_path") ?: obj.str("cover") ?: obj.str("image"), maxWidth = 600),
            overview = obj.str("overview").orEmpty(),
            source = obj.str("media_source")?.takeIf { it.isNotBlank() } ?: resolvedSource,
            tracks = tracks,
        )
    }

    /** 并发拉取音乐艺人资料及其专辑作品网格（`GET /api/v1/music/artist/{id}` + `/albums`）。 */
    suspend fun fetchMusicArtistDetail(
        artistId: String,
        source: String,
        fallbackName: String = "",
    ): MusicArtistDetailDto? = coroutineScope {
        val cleanId = artistId.trim()
        if (cleanId.isEmpty()) return@coroutineScope null
        val resolvedSource = source.ifBlank { "musicbrainz" }
        val q = listOf("media_source" to resolvedSource)
        val infoDeferred = async {
            authedRequest(listOf("music", "artist", cleanId), query = q).getOrNull()
        }
        val albumsDeferred = async {
            authedRequest(listOf("music", "artist", cleanId, "albums"), query = q).getOrNull()
        }
        val infoResp = infoDeferred.await()
        val albumsResp = albumsDeferred.await()
        val infoObj = if (infoResp != null && infoResp.status in 200..299) extractObject(infoResp.body) else null
        val parsedAlbums = if (albumsResp != null && albumsResp.status in 200..299) {
            val seen = HashSet<String>()
            extractArray(albumsResp.body).mapNotNull { el ->
                parseMusicAlbumObj(el.asObj(), fallbackSource = resolvedSource)
            }.filter { seen.add("${it.source}|${it.id}|${it.title}") }
        } else {
            emptyList()
        }
        if (infoObj == null && parsedAlbums.isEmpty()) return@coroutineScope null
        MusicArtistDetailDto(
            id = cleanId,
            name = infoObj?.str("name") ?: infoObj?.str("title") ?: fallbackName,
            country = infoObj?.str("country").orEmpty(),
            area = infoObj?.str("area").orEmpty(),
            lifeSpan = infoObj?.str("life_span").orEmpty(),
            imageUrl = resolveImageUrl(infoObj?.str("image_url") ?: infoObj?.str("poster_path") ?: infoObj?.str("image"), maxWidth = 480),
            overview = infoObj?.str("overview").orEmpty(),
            source = resolvedSource,
            albums = parsedAlbums,
        )
    }

    /** 查询指定音乐专辑是否处于已订阅状态（`POST /api/v1/media/status`）。 */
    suspend fun checkMusicAlbumSubscribed(mediaSource: String, mediaId: String): Boolean {
        if (mediaId.isBlank()) return false
        val body = """[{"media_source":"${esc(mediaSource.ifBlank { "musicbrainz" })}","media_id":"${esc(mediaId)}","mtype":"音乐"}]"""
        val resp = authedRequest(listOf("media", "status"), method = "POST", body = body).getOrNull() ?: return false
        if (resp.status !in 200..299) return false
        val first = extractArray(resp.body).firstOrNull()?.asObj() ?: return false
        return first.bool("subscribed") ?: false
    }

    /** 提交音乐专辑订阅（`POST /api/v1/subscribe/`）。 */
    suspend fun subscribeMusicAlbum(
        title: String,
        mediaSource: String,
        mediaId: String,
        year: String = "",
        totalTracks: Int = 0,
    ): Pair<Boolean, String> {
        if (mediaId.isBlank()) return false to "专辑缺少有效媒体标识"
        val fields = mutableListOf(
            """"name":"${esc(title)}"""",
            """"type":"音乐"""",
            """"music_type":"album"""",
            """"media_source":"${esc(mediaSource.ifBlank { "musicbrainz" })}"""",
            """"media_id":"${esc(mediaId)}"""",
        )
        if (year.isNotBlank()) fields += """"year":"${esc(year)}""""
        if (totalTracks > 0) fields += """"total_tracks":$totalTracks"""
        val resp = authedRequest(
            segments = listOf("subscribe"),
            method = "POST",
            body = "{${fields.joinToString(",")}}",
            trailingSlash = true,
        ).getOrNull() ?: return false to "网络请求失败"
        val msg = extractObject(resp.body)?.str("message")
            ?: if (resp.status in 200..299) "已添加专辑订阅" else "添加音乐订阅失败 (HTTP ${resp.status})"
        return (resp.status in 200..299) to msg
    }

    /** 取消音乐专辑订阅（`DELETE /api/v1/subscribe/media/{mediaId}`）。 */
    suspend fun unsubscribeMusicAlbum(mediaSource: String, mediaId: String): Pair<Boolean, String> {
        if (mediaId.isBlank()) return false to "专辑缺少有效媒体标识"
        val resp = authedRequest(
            segments = listOf("subscribe", "media", mediaId),
            method = "DELETE",
            query = listOf(
                "media_source" to mediaSource.ifBlank { "musicbrainz" },
                "mtype" to "音乐",
            ),
        ).getOrNull() ?: return false to "网络请求失败"
        val msg = extractObject(resp.body)?.str("message")
            ?: if (resp.status in 200..299) "已取消专辑订阅" else "取消音乐订阅失败 (HTTP ${resp.status})"
        return (resp.status in 200..299) to msg
    }

    /** 拉取所有已启用媒体服务器的真实「继续观看」列表（聚合多媒体服务器，精确还原小数进度百分比）。 */
    suspend fun fetchContinueWatching(): List<ContinueWatchingItem> {
        val configs = fetchMediaServers().filter { it.enabled }
        val servers = if (configs.isNotEmpty()) {
            configs.map { it.name to it.type }
        } else {
            listOf("Emby" to "emby", "Jellyfin" to "jellyfin", "Plex" to "plex")
        }
        val result = mutableListOf<ContinueWatchingItem>()
        for ((srv, srvType) in servers) {
            val resp = authedRequest(listOf("mediaserver", "playing"), query = listOf("server" to srv)).getOrNull()
            val arr = extractArray(resp?.body)
            arr.forEach { el ->
                val obj = el.asObj() ?: return@forEach
                result += ContinueWatchingItem(
                    id = obj.str("id") ?: obj.str("item_id") ?: "",
                    title = obj.str("title") ?: obj.str("name") ?: "",
                    subtitle = obj.str("subtitle") ?: obj.str("episode_title") ?: "",
                    image = resolveImageUrl(obj.str("image") ?: obj.str("backdrop_path"), maxWidth = 720),
                    percent = (obj.dbl("percent") ?: 0.0).roundToInt().coerceIn(0, 100),
                    server = obj.str("server") ?: srv,
                    serverType = obj.str("server_type")?.takeIf { it.isNotBlank() } ?: srvType,
                    type = obj.str("type") ?: "电视剧",
                    link = obj.str("link"),
                )
            }
        }
        return result.distinctBy { "${it.server}:${it.id}:${it.title}" }
    }

    /** 拉取所有已启用媒体服务器的「最近入库」列表（聚合多媒体服务器，保留 `serverItemId` 与 `serverName` 供直达媒体库详情页）。 */
    suspend fun fetchMediaServerLatest(): List<MediaCardItem> {
        val configs = fetchMediaServers().filter { it.enabled }
        val servers = if (configs.isNotEmpty()) {
            configs.map { it.name to it.type }
        } else {
            listOf("Emby" to "emby", "Jellyfin" to "jellyfin", "Plex" to "plex")
        }
        val result = mutableListOf<MediaCardItem>()
        for ((srv, srvType) in servers) {
            val resp = authedRequest(listOf("mediaserver", "latest"), query = listOf("server" to srv)).getOrNull()
            val arr = extractArray(resp?.body)
            arr.forEach { el ->
                val obj = el.asObj() ?: return@forEach
                val title = obj.str("title") ?: return@forEach
                val itemId = obj.str("item_id") ?: obj.str("id")
                val serverName = obj.str("server") ?: srv
                val serverType = obj.str("server_type")?.takeIf { it.isNotBlank() } ?: srvType
                val useCookies = obj.bool("use_cookies") == true
                result += MediaCardItem(
                    title = title,
                    year = obj.str("year") ?: obj.str("subtitle")?.take(4) ?: "",
                    type = canonicalMediaType(obj.str("type")),
                    overview = obj.str("subtitle") ?: "",
                    posterPath = resolveImageUrl(obj.str("image"), maxWidth = 450, useCookies = useCookies),
                    backdropPath = resolveImageUrl(obj.str("image"), maxWidth = 900, useCookies = useCookies),
                    mediaId = itemId,
                    serverItemId = itemId,
                    serverName = serverName,
                    serverType = serverType,
                    source = serverName,
                    inLibrary = true,
                    rawJson = obj.toString(),
                )
            }
        }
        return result.distinctBy { "${it.serverName ?: it.source}:${it.serverItemId ?: it.resolvedId}" }
    }

    private suspend fun fetchMediaList(segments: List<String>, query: List<Pair<String, String>>): List<MediaCardItem> {
        val resp = authedRequest(segments, query = query).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { parseMediaCard(it) }
    }

    private fun parseMediaCard(el: JsonElement): MediaCardItem? {
        val obj = el.asObj() ?: return null
        val title = obj.str("title") ?: obj.str("name") ?: obj.str("share_title") ?: return null
        val explicitGenres = obj["genres"].asArr()?.mapNotNull { g ->
            when (g) {
                is JsonPrimitive -> g.content.takeIf { it != "null" && it.isNotBlank() }
                is JsonObject -> g.str("name")
                else -> null
            }
        }.orEmpty()
        val mappedGenreIds = obj["genre_ids"].asArr()?.mapNotNull { gid ->
            gid.asPrim()?.intOrNull?.let { TMDB_GENRE_ID_TO_ZH[it] }
        }.orEmpty()
        val genres = explicitGenres.ifEmpty { mappedGenreIds }

        val tmdbId = obj.int("tmdb_id") ?: obj.int("tmdbid") ?: obj.str("tmdb_id")?.toIntOrNull()
        val doubanId = obj.str("douban_id") ?: obj.str("doubanid")
        val bangumiId = obj.int("bangumi_id") ?: obj.int("bangumiid") ?: obj.str("bangumi_id")?.toIntOrNull()
        val imdbId = obj.str("imdb_id") ?: obj.str("imdbid")
        val tvdbId = obj.str("tvdb_id") ?: obj.str("tvdbid") ?: obj.int("tvdb_id")?.toString()
        val rawMediaId = obj.str("media_id") ?: obj.str("id")
        val rawSrc = obj.str("media_source") ?: obj.str("source")
        val canonicalIdentity = normalizeCanonicalMediaIdentity(
            source = rawSrc,
            mediaId = rawMediaId,
            tmdbId = tmdbId,
            doubanId = doubanId,
            bangumiId = bangumiId,
            imdbId = imdbId,
            tvdbId = tvdbId,
        )
        val src = canonicalIdentity?.first ?: normalizeMediaSource(rawSrc) ?: rawSrc ?: "themoviedb"
        val cleanMediaId = canonicalIdentity?.second ?: rawMediaId
        val cachedLogo = mediaLogoCache["$src:${tmdbId ?: cleanMediaId}"]
        val serverName = obj.str("server")?.takeIf { it.isNotBlank() }
        val serverItemId = obj.str("item_id")?.takeIf { it.isNotBlank() }
            ?: (if (serverName != null) obj.str("id")?.takeIf { it.isNotBlank() } else null)

        return MediaCardItem(
            title = title,
            year = obj.str("year") ?: obj.str("release_date")?.take(4) ?: obj.str("first_air_date")?.take(4) ?: "",
            type = canonicalMediaType(obj.str("type") ?: obj.str("media_type") ?: obj.str("item_type")),
            overview = obj.str("overview") ?: obj.str("description") ?: "",
            posterPath = resolveImageUrl(obj.str("poster_path") ?: obj.str("poster") ?: obj.str("image"), maxWidth = 500),
            backdropPath = resolveImageUrl(obj.str("backdrop_path") ?: obj.str("backdrop"), maxWidth = 1080),
            voteAverage = obj.dbl("vote_average") ?: obj.dbl("vote") ?: obj.dbl("rating") ?: 0.0,
            source = src,
            tmdbId = tmdbId ?: (if (src == "themoviedb") cleanMediaId?.toIntOrNull() else null),
            doubanId = doubanId ?: (if (src == "douban") cleanMediaId else null),
            bangumiId = bangumiId ?: (if (src == "bangumi") cleanMediaId?.toIntOrNull() else null),
            imdbId = imdbId,
            tvdbId = tvdbId,
            mediaIdPrefix = obj.str("mediaid_prefix"),
            mediaId = cleanMediaId,
            season = obj.int("season") ?: obj.int("season_number"),
            serverItemId = serverItemId,
            serverName = serverName,
            serverType = obj.str("server_type")?.takeIf { it.isNotBlank() },
            logoPath = resolveImageUrl(obj.str("logo_path"), maxWidth = 720) ?: cachedLogo,
            genres = genres,
            runtime = obj.int("runtime"),
            numberOfSeasons = obj.int("number_of_seasons") ?: obj.int("season_count"),
            contentRating = obj.str("content_rating") ?: obj.str("official_rating"),
            releaseDate = obj.str("release_date") ?: obj.str("first_air_date") ?: obj.str("premiere_date"),
            inLibrary = obj.bool("in_library") ?: (serverItemId != null),
            subtitle = obj.str("artist")
                ?: obj["artists"].asArr()?.firstOrNull()?.asPrim()?.content?.takeIf { it != "null" && it.isNotBlank() }
                ?: obj.str("subtitle"),
            popularityCount = obj.int("count") ?: 0,
            shareUser = obj.str("share_user"),
            shareComment = obj.str("share_comment"),
            rawJson = obj.toString(),
        )
    }

    // ==================== 社区勋章 ====================

    /** 获取 `/api/v1/github/community` 原始 JSON（供 `:core-medal3d` 直接解码 `CommunityProfile`）。 */
    suspend fun fetchCommunityProfileJson(refresh: Boolean = false): String? {
        val query = if (refresh) listOf("refresh" to "true") else emptyList()
        val resp = authedRequest(listOf("github", "community"), query = query).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        return obj.toString()
    }

    // ==================== 订阅 / 日历 / 社区 ====================

    private fun parseSubscribeItem(obj: JsonObject): SubscribeItemDto? {
        val name = obj.str("name") ?: return null
        val rawSrc = obj.str("media_source") ?: "themoviedb"
        val rawMediaId = obj.str("media_id") ?: obj.int("tmdbid")?.toString() ?: ""
        val normIdentity = normalizeCanonicalMediaIdentity(source = rawSrc, mediaId = rawMediaId)
        return SubscribeItemDto(
            id = obj.int("id") ?: 0,
            name = name,
            year = obj.str("year") ?: "",
            type = canonicalMediaType(obj.str("type")),
            season = obj.int("season"),
            poster = resolveImageUrl(obj.str("poster"), maxWidth = 400),
            backdrop = resolveImageUrl(obj.str("backdrop"), maxWidth = 900),
            vote = obj.dbl("vote") ?: 0.0,
            state = obj.str("state") ?: "R",
            totalEpisode = obj.int("total_episode") ?: 0,
            lackEpisode = obj.int("lack_episode") ?: 0,
            mediaSource = normIdentity?.first ?: normalizeMediaSource(rawSrc) ?: rawSrc,
            mediaId = normIdentity?.second ?: rawMediaId,
            quality = obj.str("quality") ?: "",
            resolution = obj.str("resolution") ?: "",
            effect = obj.str("effect") ?: "",
            audioQuality = obj.str("audio_quality") ?: "",
            audioFormat = obj.str("audio_format") ?: "",
            minBitrate = obj.int("min_bitrate") ?: 0,
            minBitDepth = obj.int("min_bit_depth") ?: 0,
            minSampleRate = obj.int("min_sample_rate") ?: 0,
            bestVersion = (obj.int("best_version") ?: 0) == 1 || obj.bool("best_version") == true,
            bestVersionFull = (obj.int("best_version_full") ?: 0) == 1 || obj.bool("best_version_full") == true,
            sites = obj["sites"].asArr()?.mapNotNull { it.asPrim()?.intOrNull } ?: emptyList(),
            filterGroups = obj["filter_groups"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s != "null" } } ?: emptyList(),
            searchImdbId = (obj.int("search_imdbid") ?: 0) == 1 || obj.bool("search_imdbid") == true,
            searchInterval = obj.int("search_interval"),
            keyword = obj.str("keyword") ?: "",
            savePath = obj.str("save_path") ?: "",
            include = obj.str("include") ?: "",
            exclude = obj.str("exclude") ?: "",
            mediaCategory = obj.str("media_category") ?: "",
            customWords = obj.str("custom_words") ?: "",
            date = obj.str("date") ?: "",
            username = obj.str("username") ?: "",
            description = obj.str("description") ?: "",
            startEpisode = obj.int("start_episode"),
            downloader = obj.str("downloader") ?: "",
            episodeGroup = obj.str("episode_group") ?: "",
            rawJson = obj.toString(),
        )
    }

    suspend fun fetchSubscriptions(forceRefresh: Boolean = true): List<SubscribeItemDto> {
        if (!forceRefresh) {
            cachedSubscriptions?.let { return it }
        }
        val resp = authedRequest(listOf("subscribe"), trailingSlash = true).getOrNull() ?: return cachedSubscriptions ?: emptyList()
        if (resp.status !in 200..299) return cachedSubscriptions ?: emptyList()
        val parsed = extractArray(resp.body).mapNotNull { el ->
            el.asObj()?.let(::parseSubscribeItem)
        }
        cachedSubscriptions = parsed
        return parsed
    }

    /** 拉取订阅关联的下载与入库文件详情（`GET /api/v1/subscribe/files/{subscribe_id}`）。 */
    suspend fun fetchSubscribeFilesInfo(subscribeId: Int): SubscribeFilesInfoDto? {
        if (subscribeId <= 0) return null
        val resp = authedRequest(listOf("subscribe", "files", subscribeId.toString())).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val rootObj = extractObject(resp.body) ?: return null
        val sub = rootObj["subscribe"].asObj()?.let(::parseSubscribeItem)
        val episodesObj = rootObj["episodes"].asObj()
        val groups = episodesObj?.entries?.mapNotNull { (keyStr, valEl) ->
            val epObj = valEl.asObj() ?: return@mapNotNull null
            val epKey = keyStr.trim().toIntOrNull() ?: 0
            val downloads = epObj["download"].asArr().orEmpty().mapNotNull { dEl ->
                val dObj = dEl.asObj() ?: return@mapNotNull null
                SubscribeDownloadFileDto(
                    torrentTitle = dObj.str("torrent_title").orEmpty(),
                    siteName = dObj.str("site_name").orEmpty(),
                    downloader = dObj.str("downloader").orEmpty(),
                    hash = dObj.str("hash").orEmpty(),
                    filePath = dObj.str("file_path").orEmpty(),
                )
            }
            val libraries = epObj["library"].asArr().orEmpty().mapNotNull { lEl ->
                val lObj = lEl.asObj() ?: return@mapNotNull null
                SubscribeLibraryFileDto(
                    storage = lObj.str("storage")?.ifBlank { "local" } ?: "local",
                    filePath = lObj.str("file_path").orEmpty(),
                    server = lObj.str("server")?.takeIf { it.isNotBlank() },
                    serverType = lObj.str("server_type")?.takeIf { it.isNotBlank() },
                    itemid = lObj.str("itemid")?.takeIf { it.isNotBlank() } ?: lObj.str("item_id")?.takeIf { it.isNotBlank() },
                )
            }
            SubscribeEpisodeFileGroupDto(
                episodeKey = epKey,
                title = epObj.str("title").orEmpty(),
                description = epObj.str("description").orEmpty(),
                backdrop = resolveImageUrl(epObj.str("backdrop"), maxWidth = 780),
                download = downloads,
                library = libraries,
            )
        }.orEmpty().sortedBy { it.episodeKey }
        return SubscribeFilesInfoDto(subscribe = sub, episodes = groups)
    }

    suspend fun fetchSubscribePopular(stype: String = "电影", page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("subscribe", "popular"), listOf("stype" to stype, "page" to page.toString()))

    suspend fun fetchSubscribeShares(page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("subscribe", "shares"), listOf("page" to page.toString()))

    /** 分页拉取已完成订阅历史（`GET /api/v1/subscribe/history/{mtype}?page=&count=`）。 */
    suspend fun fetchSubscribeHistory(
        mtype: String = "电影",
        page: Int = 1,
        count: Int = 30,
    ): Result<List<SubscribeItemDto>> {
        val normalizedType = mtype.trim().ifBlank { "电影" }
        val resp = authedRequest(
            segments = listOf("subscribe", "history", normalizedType),
            query = listOf("page" to page.coerceAtLeast(1).toString(), "count" to count.coerceAtLeast(1).toString()),
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException("HTTP ${resp.status}"))
        }
        val parsed = extractArray(resp.body).mapNotNull { el ->
            el.asObj()?.let(::parseSubscribeItem)
        }
        return Result.success(parsed)
    }

    /** 删除单条订阅历史记录（`DELETE /api/v1/subscribe/history/{history_id}`）。 */
    suspend fun deleteSubscribeHistory(historyId: Int): Boolean {
        if (historyId <= 0) return false
        val resp = authedRequest(
            segments = listOf("subscribe", "history", historyId.toString()),
            method = "DELETE",
        ).getOrNull() ?: return false
        return resp.status in 200..299 &&
            (runCatching { json.parseToJsonElement(resp.body).asObj()?.bool("success") }.getOrNull() != false)
    }

    /** 从订阅历史记录重新发起订阅（`POST /api/v1/subscribe/`），完整保留原规则字段并刷新订阅缓存。 */
    suspend fun reSubscribeFromHistory(item: SubscribeItemDto, fallbackType: String = "电影"): Pair<Boolean, String> {
        val baseMap = runCatching {
            if (item.rawJson.isNotBlank()) json.parseToJsonElement(item.rawJson).asObj()?.toMutableMap() else null
        }.getOrNull() ?: mutableMapOf()

        val canonicalType = canonicalMediaType(item.type.ifBlank { fallbackType })
        val isTv = isTvType(canonicalType)
        val rawTmdbId = baseMap["tmdbid"]?.asPrim()?.intOrNull
        val rawDoubanId = baseMap["doubanid"]?.asPrim()?.content?.takeIf { it.isNotBlank() && it != "null" }
        val rawBangumiId = baseMap["bangumiid"]?.asPrim()?.intOrNull
        val identity = normalizeCanonicalMediaIdentity(
            source = item.mediaSource,
            mediaId = item.mediaId,
            tmdbId = rawTmdbId,
            doubanId = rawDoubanId,
            bangumiId = rawBangumiId,
        )

        listOf(
            "id", "tmdbid", "poster", "backdrop", "vote", "description", "lack_episode",
            "completed_episode", "completed_tracks", "note", "state", "last_update",
            "username", "current_priority", "episode_priority", "date",
            "current_audio_format", "current_bitrate", "current_bit_depth", "current_sample_rate",
            "classification_rule_id", "classification_policy_revision", "classification_source",
            "execution_status", "last_search",
        ).forEach { baseMap.remove(it) }

        val rawSearchInterval = baseMap["search_interval"]?.asPrim()?.intOrNull ?: item.searchInterval
        if (rawSearchInterval == null || rawSearchInterval <= 0) {
            baseMap.remove("search_interval")
        }

        baseMap["name"] = JsonPrimitive(item.name)
        baseMap["type"] = JsonPrimitive(canonicalType)
        if (item.year.isNotBlank()) {
            baseMap["year"] = JsonPrimitive(item.year.trim())
        }
        if (isTv && (item.season ?: 0) > 0) {
            baseMap["season"] = JsonPrimitive(item.season ?: 1)
        } else if (!isTv) {
            baseMap.remove("season")
        }
        if (identity != null) {
            baseMap["media_source"] = JsonPrimitive(identity.first)
            baseMap["media_id"] = JsonPrimitive(identity.second)
        } else {
            baseMap.remove("media_source")
            baseMap.remove("media_id")
        }

        val resp = authedRequest(
            segments = listOf("subscribe"),
            method = "POST",
            body = JsonObject(baseMap).toString(),
            trailingSlash = true,
        ).getOrNull() ?: return false to "网络请求失败"
        val rootObj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = resp.status in 200..299 && rootObj?.bool("success") == true
        if (ok) cachedSubscriptions = null
        val msg = rootObj?.str("message")?.takeIf { it.isNotBlank() }
            ?: if (ok) "已重新订阅「${item.name}」" else "重新订阅失败（HTTP ${resp.status}）"
        return ok to msg
    }

    /** 按页面日期窗口分页读取日历；参数错误不能回退成截断的 TMDB 订阅聚合。 */
    suspend fun fetchSubscribeCalendar(
        start: java.time.LocalDate = java.time.LocalDate.now(),
        end: java.time.LocalDate = start.plusDays(31),
    ): List<CalendarEntryDto> {
        require(java.time.temporal.ChronoUnit.DAYS.between(start, end) in 1..93) { "日历窗口须为 1–93 天" }
        val subscriptions = fetchSubscriptions(forceRefresh = false).associateBy { it.id }
        val result = mutableListOf<CalendarEntryDto>()
        var page = 1
        var consumed = 0
        do {
            val resp = authedRequest(listOf("subscribe", "calendar"), query = listOf(
                "start" to start.toString(), "end" to end.toString(), "page" to page.toString(), "count" to "200",
            )).getOrThrow()
            check(resp.status in 200..299) { "加载日历失败（HTTP ${resp.status}）" }
            val root = extractObject(resp.body) ?: error("日历响应格式无效")
            val events = root["items"].asArr() ?: error("日历响应缺少 items")
            for (value in events) {
                val event = value.asObj() ?: continue
                val sub = event["subscribe"].asObj() ?: continue
                val id = sub.int("id") ?: continue
                val details = subscriptions[id]
                val media = normalizeCanonicalMediaIdentity(details?.mediaSource, details?.mediaId)
                val date = event.str("date").orEmpty()
                val episodes = event["episodes"].asArr().orEmpty()
                // 电影没有分集，仍需保留其上映日历项。
                val rows = if (episodes.isEmpty()) listOf<JsonElement?>(null) else episodes
                for (episode in rows) {
                    val ep = episode.asObj()
                    result += CalendarEntryDto(
                        id = "${id}_${date}_${ep?.int("episode_number") ?: 0}", subscribeId = id,
                        title = sub.str("name").orEmpty(), year = sub.str("year").orEmpty(),
                        type = sub.str("type") ?: "电视剧", season = sub.int("season"),
                        episode = ep?.int("episode_number"), episodeTitle = ep?.str("name").orEmpty(),
                        airDate = date, poster = resolveImageUrl(sub.str("poster"), maxWidth = 400),
                        source = media?.first ?: details?.mediaSource ?: "themoviedb", mediaId = media?.second,
                        tmdbId = media?.takeIf { it.first == "themoviedb" }?.second?.toIntOrNull(),
                        doubanId = media?.takeIf { it.first == "douban" }?.second,
                        bangumiId = media?.takeIf { it.first == "bangumi" }?.second?.toIntOrNull(),
                    )
                }
            }
            consumed += events.size
            page++
            val total = root.int("total") ?: error("日历响应缺少 total")
        } while (events.isNotEmpty() && consumed < total)
        return result
    }

    /** 复用社区订阅分享（`POST /api/v1/subscribe/fork`）。 */
    suspend fun forkSubscribeShare(share: MediaCardItem): Pair<Boolean, String> {
        val bodyJson = share.rawJson.takeIf { it.isNotBlank() } ?: run {
            val m = mutableMapOf<String, JsonElement>(
                "share_title" to JsonPrimitive(share.title),
                "name" to JsonPrimitive(share.title),
                "year" to JsonPrimitive(share.year),
                "type" to JsonPrimitive(share.type),
            )
            share.tmdbId?.let { m["tmdbid"] = JsonPrimitive(it) }
            share.doubanId?.let { m["doubanid"] = JsonPrimitive(it) }
            share.bangumiId?.let { m["bangumiid"] = JsonPrimitive(it) }
            share.mediaId?.toIntOrNull()?.let { m["id"] = JsonPrimitive(it) }
            JsonObject(m).toString()
        }
        val resp = authedRequest(
            segments = listOf("subscribe", "fork"),
            method = "POST",
            body = bodyJson,
        ).getOrNull() ?: return false to "网络请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        if (ok) cachedSubscriptions = null
        val msg = obj?.str("message") ?: if (ok) "已复用订阅《${share.title}》" else "复用订阅失败（HTTP ${resp.status}）"
        return ok to msg
    }

    /** 查询媒体真实订阅状态（遵循 V3 规范发送无前缀 `media_id` + 必填 `media_source`，结合 `POST /api/v1/media/status` 与已订阅列表）。 */
    suspend fun checkMediaSubscribed(item: MediaCardItem, season: Int? = item.season): Pair<Boolean, Set<Int>> {
        val status = checkMediaInLibraryStatus(item, season)
        val subscribedSeasons = status.subscribedSeasons.keys.toMutableSet()
        var directSubscribed = status.subscribed

        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val mtype = canonicalMediaType(item.type)
        val isTv = isTvType(mtype)
        if (!directSubscribed && identity != null) {
            val q = buildList {
                add("media_source" to identity.first)
                add("mtype" to mtype)
                if (isTv && season != null) add("season" to season.toString())
                if (item.title.isNotBlank()) add("title" to item.title)
                if (item.year.isNotBlank()) add("year" to item.year)
            }
            val resp = authedRequest(listOf("subscribe", "media", identity.second), query = q).getOrNull()
            if (resp != null && resp.status in 200..299) {
                val obj = extractObject(resp.body)
                val subId = obj?.int("id") ?: 0
                if (subId > 0) {
                    directSubscribed = true
                    obj?.int("season")?.let { subscribedSeasons += it }
                }
            }
        }
        if (isTv && season != null && season in subscribedSeasons) {
            directSubscribed = true
        }
        return directSubscribed to subscribedSeasons
    }

    /**
     * 批量契约查询媒体本地入库状态、订阅状态与可直放条目 ID：
     * 严格发送 JSON 数组 `[{"media_source": ..., "media_id": ..., "mtype": ...}]` 到 `POST /api/v1/media/status`。
     */
    suspend fun checkMediaInLibraryStatus(item: MediaCardItem, season: Int? = item.season): MediaLibraryStatusDto {
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val mtype = canonicalMediaType(item.type)
        val isTv = isTvType(mtype)
        val queryMap = mutableMapOf<String, JsonElement>(
            "mtype" to JsonPrimitive(mtype),
        )
        if (identity != null) {
            queryMap["media_source"] = JsonPrimitive(identity.first)
            queryMap["media_id"] = JsonPrimitive(identity.second)
        }
        if (item.title.isNotBlank()) queryMap["title"] = JsonPrimitive(item.title)
        if (item.year.isNotBlank()) queryMap["year"] = JsonPrimitive(item.year)
        if (isTv && season != null) queryMap["season"] = JsonPrimitive(season)

        var inLib = item.inLibrary
        var server = item.serverName.orEmpty()
        var serverType = item.serverType.orEmpty()
        var itemId = item.serverItemId.orEmpty()
        var subscribed = false
        val subscribedSeasonsMap = mutableMapOf<Int, String>()
        val seasonsEpisodesMap = mutableMapOf<Int, List<Int>>()

        val resp = authedRequest(
            segments = listOf("media", "status"),
            method = "POST",
            body = JsonArray(listOf(JsonObject(queryMap))).toString(),
        ).getOrNull()
        if (resp != null && resp.status in 200..299) {
            val statusObj = extractArray(resp.body).firstOrNull()?.asObj() ?: extractObject(resp.body)
            if (statusObj != null) {
                val resItemId = statusObj.str("item_id") ?: statusObj.str("itemid").orEmpty()
                val resServer = statusObj.str("server").orEmpty()
                if (resItemId.isNotBlank()) {
                    itemId = resItemId
                    inLib = true
                }
                if (resServer.isNotBlank()) {
                    server = resServer
                }
                subscribed = statusObj.bool("subscribed") ?: false
                statusObj["seasons"].asObj()?.forEach { (k, v) ->
                    val sNum = k.toIntOrNull() ?: return@forEach
                    when (v) {
                        is JsonPrimitive -> {
                            val mode = v.content.takeIf { it != "null" && it.isNotBlank() } ?: "normal"
                            subscribedSeasonsMap[sNum] = mode
                        }
                        is JsonArray -> {
                            val eps = v.mapNotNull { it.asPrim()?.intOrNull }
                            seasonsEpisodesMap[sNum] = eps
                        }
                        else -> Unit
                    }
                }
            }
        }

        // 结合本地缓存订阅列表补充已订阅季与对应 subscribeId（用于直达订阅文件详情弹窗）
        var matchedSubId: Int? = null
        val seasonSubIds = mutableMapOf<Int, Int>()
        val allSubs = fetchSubscriptions(forceRefresh = false)
        allSubs.forEach { sub ->
            val subIdentity = normalizeCanonicalMediaIdentity(sub.mediaSource, sub.mediaId)
            val sameIdentity = identity != null && subIdentity != null &&
                identity.first == subIdentity.first && identity.second == subIdentity.second
            val sameTmdb = item.tmdbId != null && (
                sub.mediaId == item.tmdbId.toString() ||
                    sub.rawJson.contains("\"tmdbid\":${item.tmdbId}")
                )
            val sameTitle = isTvType(sub.type) == isTv &&
                sub.name == item.title &&
                (item.year.isBlank() || sub.year.isBlank() || sub.year == item.year)
            if (sameIdentity || sameTmdb || sameTitle) {
                if (isTv) {
                    val sNum = sub.season ?: 1
                    subscribedSeasonsMap.putIfAbsent(sNum, if (sub.bestVersion) "best_version" else "normal")
                    if (sub.id > 0) seasonSubIds[sNum] = sub.id
                    if (season == null || season == sNum) {
                        subscribed = true
                        if (sub.id > 0) matchedSubId = sub.id
                    }
                } else {
                    subscribed = true
                    if (sub.id > 0) matchedSubId = sub.id
                }
            }
        }

        // 若 `POST /api/v1/media/status` 未命中或服务端为旧版本，回退调用规范 `GET /api/v1/subscribe/media/{rawMediaId}?media_source=...`
        if (identity != null && (!subscribed || (matchedSubId == null && subscribed))) {
            val q = buildList {
                add("media_source" to identity.first)
                add("mtype" to mtype)
                if (isTv && season != null) add("season" to season.toString())
                if (item.title.isNotBlank()) add("title" to item.title)
                if (item.year.isNotBlank()) add("year" to item.year)
            }
            val subResp = authedRequest(listOf("subscribe", "media", identity.second), query = q).getOrNull()
            if (subResp != null && subResp.status in 200..299) {
                val subObj = extractObject(subResp.body)
                val subId = subObj?.int("id") ?: 0
                if (subId > 0) {
                    subscribed = true
                    matchedSubId = subId
                    val sNum = subObj?.int("season") ?: season
                    if (isTv && sNum != null) {
                        subscribedSeasonsMap.putIfAbsent(sNum, "normal")
                        seasonSubIds[sNum] = subId
                    }
                }
            }
        }

        // 电视剧已入库时尽力查询各季已入库集号（供详情页单集卡片展示「已入库」角标）
        if (isTv && inLib && seasonsEpisodesMap.isEmpty() && identity != null) {
            val existsBody = mutableMapOf<String, JsonElement>(
                "type" to JsonPrimitive("电视剧"),
                "title" to JsonPrimitive(item.title),
                "media_source" to JsonPrimitive(identity.first),
                "media_id" to JsonPrimitive(identity.second),
            )
            if (item.year.isNotBlank()) existsBody["year"] = JsonPrimitive(item.year)
            val existsResp = authedRequest(
                segments = listOf("mediaserver", "exists_remote"),
                method = "POST",
                body = JsonObject(existsBody).toString(),
            ).getOrNull()
            if (existsResp != null && existsResp.status in 200..299) {
                extractObject(existsResp.body)?.forEach { (k, v) ->
                    val sNum = k.toIntOrNull() ?: return@forEach
                    val eps = v.asArr()?.mapNotNull { it.asPrim()?.intOrNull }.orEmpty()
                    if (eps.isNotEmpty()) seasonsEpisodesMap[sNum] = eps
                }
            }
        }

        // 补充媒体服务器类型与缺失 itemId 定位
        val mediaServers = fetchMediaServers().filter { it.enabled }
        if (server.isNotBlank() && serverType.isBlank()) {
            serverType = mediaServers.firstOrNull { it.name.equals(server, ignoreCase = true) }?.type.orEmpty()
        }
        if (itemId.isBlank() && !item.mediaId.isNullOrBlank() && mediaServers.any { it.name.equals(item.source, ignoreCase = true) }) {
            val matchedSrv = mediaServers.first { it.name.equals(item.source, ignoreCase = true) }
            inLib = true
            server = matchedSrv.name
            serverType = matchedSrv.type
            itemId = item.mediaId
        } else if (itemId.isBlank() && inLib && item.title.isNotBlank() && mediaServers.isNotEmpty()) {
            for (srv in mediaServers) {
                val page = fetchMediaServerBrowse(server = srv.name, keyword = item.title, limit = 6)
                val hit = page.items.firstOrNull { cand ->
                    (item.tmdbId != null && cand.tmdbId == item.tmdbId) ||
                        (cand.title.equals(item.title, ignoreCase = true) && (item.year.isBlank() || cand.year.isBlank() || cand.year == item.year))
                }
                if (hit != null) {
                    inLib = true
                    server = hit.server.ifBlank { srv.name }
                    serverType = hit.serverType.ifBlank { srv.type }
                    itemId = hit.itemId
                    break
                }
            }
        }
        return MediaLibraryStatusDto(
            inLibrary = inLib,
            server = server,
            serverType = serverType,
            itemId = itemId,
            subscribed = subscribed || (isTv && season != null && season in subscribedSeasonsMap),
            subscribedSeasons = subscribedSeasonsMap,
            subscribeId = matchedSubId ?: (if (isTv && season != null) seasonSubIds[season] else null),
            seasonSubscribeIds = seasonSubIds,
            existingEpisodesBySeason = seasonsEpisodesMap,
        )
    }

    suspend fun toggleSubscriptionState(id: Int, targetState: String): Boolean {
        val resp = authedRequest(
            segments = listOf("subscribe", "status", id.toString()),
            method = "PUT",
            query = listOf("state" to targetState),
        ).getOrNull()
        val ok = resp != null && resp.status in 200..299 &&
            (runCatching { json.parseToJsonElement(resp.body).asObj()?.bool("success") }.getOrNull() != false)
        if (ok) cachedSubscriptions = null
        return ok
    }

    /** 创建或更新订阅，返回 `(是否成功, 服务端提示文案, 订阅ID)`。 */
    suspend fun createOrUpdateSubscriptionFull(
        item: SubscribeItemDto,
        isUpdate: Boolean = false,
    ): Triple<Boolean, String, Int?> {
        val baseMap = runCatching {
            if (isUpdate && item.rawJson.isNotBlank()) json.parseToJsonElement(item.rawJson).asObj()?.toMutableMap() else null
        }.getOrNull() ?: mutableMapOf()

        val canonicalType = canonicalMediaType(item.type)
        val isTv = isTvType(canonicalType)
        val identity = normalizeCanonicalMediaIdentity(source = item.mediaSource, mediaId = item.mediaId)

        if (isUpdate && item.id > 0) {
            baseMap["id"] = JsonPrimitive(item.id)
        } else {
            baseMap.remove("id")
        }
        // 移除服务端禁止公共写入的只读字段及旧版 tmdbid 冗余键
        listOf(
            "tmdbid", "poster", "backdrop", "vote", "description", "lack_episode",
            "completed_episode", "completed_tracks", "note", "state", "last_update",
            "username", "current_priority", "episode_priority", "date", "execution_status", "last_search",
        ).forEach { baseMap.remove(it) }

        baseMap["name"] = JsonPrimitive(item.name)
        baseMap["year"] = JsonPrimitive(item.year.trim())
        baseMap["type"] = JsonPrimitive(canonicalType)
        if (isTv) {
            if (item.season != null) {
                baseMap["season"] = JsonPrimitive(item.season)
            } else {
                baseMap["season"] = kotlinx.serialization.json.JsonNull
            }
        } else {
            baseMap.remove("season")
        }
        if (identity != null) {
            baseMap["media_source"] = JsonPrimitive(identity.first)
            baseMap["media_id"] = JsonPrimitive(identity.second)
        } else {
            baseMap.remove("media_source")
            baseMap.remove("media_id")
        }
        baseMap["total_episode"] = JsonPrimitive(item.totalEpisode)
        baseMap["start_episode"] = JsonPrimitive(item.startEpisode ?: 0)
        baseMap["quality"] = JsonPrimitive(normalizeSubscribeFilterOption("quality", item.quality))
        baseMap["resolution"] = JsonPrimitive(normalizeSubscribeFilterOption("resolution", item.resolution))
        baseMap["effect"] = JsonPrimitive(normalizeSubscribeFilterOption("effect", item.effect))
        if (canonicalType == "音乐") {
            baseMap["audio_quality"] = if (item.audioQuality.isBlank()) kotlinx.serialization.json.JsonNull else JsonPrimitive(item.audioQuality)
            baseMap["audio_format"] = if (item.audioFormat.isBlank()) kotlinx.serialization.json.JsonNull else JsonPrimitive(item.audioFormat)
            baseMap["min_bitrate"] = if (item.minBitrate > 0) JsonPrimitive(item.minBitrate) else kotlinx.serialization.json.JsonNull
            baseMap["min_bit_depth"] = if (item.minBitDepth > 0) JsonPrimitive(item.minBitDepth) else kotlinx.serialization.json.JsonNull
            baseMap["min_sample_rate"] = if (item.minSampleRate > 0) JsonPrimitive(item.minSampleRate) else kotlinx.serialization.json.JsonNull
        }
        baseMap["best_version"] = JsonPrimitive(if (item.bestVersion) 1 else 0)
        baseMap["best_version_full"] = JsonPrimitive(if (item.bestVersion && item.bestVersionFull) 1 else 0)
        baseMap["sites"] = JsonArray(item.sites.map { JsonPrimitive(it) })
        baseMap["filter_groups"] = JsonArray(item.filterGroups.map { JsonPrimitive(it) })
        baseMap["search_imdbid"] = JsonPrimitive(if (item.searchImdbId) 1 else 0)
        if (item.searchInterval != null && item.searchInterval > 0) {
            baseMap["search_interval"] = JsonPrimitive(item.searchInterval)
        } else {
            baseMap["search_interval"] = kotlinx.serialization.json.JsonNull
        }
        baseMap["keyword"] = JsonPrimitive(item.keyword)
        baseMap["save_path"] = JsonPrimitive(item.savePath)
        baseMap["downloader"] = JsonPrimitive(item.downloader)
        baseMap["episode_group"] = JsonPrimitive(item.episodeGroup)
        baseMap["include"] = JsonPrimitive(item.include)
        baseMap["exclude"] = JsonPrimitive(item.exclude)
        baseMap["media_category"] = JsonPrimitive(item.mediaCategory)
        baseMap["custom_words"] = JsonPrimitive(item.customWords)

        val resp = authedRequest(
            segments = listOf("subscribe"),
            method = if (isUpdate) "PUT" else "POST",
            body = JsonObject(baseMap).toString(),
            trailingSlash = true,
        ).getOrNull() ?: return Triple(false, "网络请求失败", null)
        val rootObj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = resp.status in 200..299 && rootObj?.bool("success") == true
        val createdId = rootObj?.get("data").asObj()?.int("id") ?: item.id.takeIf { it > 0 }
        if (ok) cachedSubscriptions = null
        val msg = rootObj?.str("message")?.takeIf { it.isNotBlank() }
            ?: if (ok) (if (isUpdate) "订阅已保存" else "已添加到我的订阅") else "订阅操作失败（HTTP ${resp.status}）"
        return Triple(ok, msg, createdId)
    }

    /** 创建或更新订阅，返回 `(是否成功, 服务端提示文案)`。 */
    suspend fun createOrUpdateSubscriptionWithMessage(item: SubscribeItemDto, isUpdate: Boolean = false): Pair<Boolean, String> {
        val (ok, msg, _) = createOrUpdateSubscriptionFull(item, isUpdate)
        return ok to msg
    }

    suspend fun createOrUpdateSubscription(item: SubscribeItemDto, isUpdate: Boolean = false): Boolean =
        createOrUpdateSubscriptionWithMessage(item, isUpdate).first

    /** 按媒体规范身份取消订阅（`DELETE /api/v1/subscribe/media/{rawMediaId}?media_source=...`），并刷新缓存。 */
    suspend fun unsubscribeMediaWithMessage(item: MediaCardItem, season: Int? = null): Pair<Boolean, String> {
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val isTv = isTvType(item.type)
        if (identity != null) {
            val q = buildList {
                add("media_source" to identity.first)
                if (isTv && season != null) add("season" to season.toString())
            }
            val resp = authedRequest(
                segments = listOf("subscribe", "media", identity.second),
                method = "DELETE",
                query = q,
            ).getOrNull() ?: return false to "网络请求失败"
            val rootObj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
            val ok = resp.status in 200..299 && rootObj?.bool("success") == true
            if (ok) cachedSubscriptions = null
            val msg = rootObj?.str("message")?.takeIf { it.isNotBlank() }
                ?: if (ok) "已取消订阅" else "取消订阅失败（HTTP ${resp.status}）"
            return ok to msg
        }
        // 无外部数据源身份时按标题与季号从订阅列表回退定位主键删除
        val target = fetchSubscriptions(forceRefresh = true).firstOrNull { sub ->
            sub.name == item.title &&
                (item.year.isBlank() || sub.year.isBlank() || sub.year == item.year) &&
                (!isTv || season == null || sub.season == season)
        } ?: return false to "未找到匹配的订阅记录"
        val ok = deleteSubscription(target.id)
        return ok to (if (ok) "已取消订阅" else "取消订阅失败")
    }

    suspend fun deleteSubscription(id: Int): Boolean {
        val resp = authedRequest(listOf("subscribe", id.toString()), method = "DELETE").getOrNull()
        val ok = resp != null && resp.status in 200..299 &&
            (runCatching { json.parseToJsonElement(resp.body).asObj()?.bool("success") }.getOrNull() != false)
        if (ok) cachedSubscriptions = null
        return ok
    }

    // ==================== 站点资源（Rust 9 维筛选分组） & 下载 ====================

    suspend fun searchResources(keyword: String, siteIds: List<Int> = emptyList()): List<ResourceItemDto> {
        fun parseItems(body: String?): List<ResourceItemDto> = extractArray(body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val torrent = obj["torrent_info"].asObj() ?: obj
            val meta = obj["meta_info"].asObj()
            val media = obj["media_info"].asObj()
            val id = torrent.str("id") ?: torrent.str("enclosure") ?: torrent.str("page_url") ?: torrent.str("title") ?: ""
            if (id.isNotBlank()) {
                resourceRawCache[id] = obj
            }
            ResourceItemDto(
                id = id,
                title = torrent.str("title") ?: return@mapNotNull null,
                siteName = torrent.str("site_name") ?: "站点",
                size = torrent.lng("size") ?: (torrent.dbl("size") ?: 0.0).toLong(),
                seeders = torrent.int("seeders") ?: 0,
                peers = torrent.int("peers") ?: 0,
                resourcePix = meta?.str("resource_pix") ?: torrent.str("resource_pix") ?: "",
                resourceType = meta?.str("resource_type") ?: torrent.str("resource_type") ?: "",
                videoEncode = meta?.str("video_encode") ?: torrent.str("video_encode") ?: "",
                audioEncode = meta?.str("audio_encode") ?: torrent.str("audio_encode") ?: "",
                resourceTeam = meta?.str("resource_team") ?: torrent.str("resource_team") ?: "",
                edition = meta?.str("edition") ?: torrent.str("edition") ?: "",
                downloadvolumefactor = torrent.dbl("downloadvolumefactor") ?: 1.0,
                uploadvolumefactor = torrent.dbl("uploadvolumefactor") ?: 1.0,
                labels = torrent["labels"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s != "null" } } ?: emptyList(),
                description = torrent.str("description") ?: "",
                enclosure = torrent.str("enclosure") ?: "",
                mediaTitle = media?.str("title") ?: meta?.str("cn_name") ?: meta?.str("en_name") ?: "",
                mediaYear = media?.str("year") ?: meta?.str("year") ?: "",
                mediaType = media?.str("type") ?: meta?.str("type") ?: "",
                seasonEpisode = meta?.str("season_episode") ?: "",
            )
        }

        if (keyword.isBlank()) {
            return when {
                siteIds.isEmpty() -> parseItems(authedRequest(listOf("search", "last")).getOrNull()?.body)
                siteIds.size == 1 -> parseItems(authedRequest(listOf("site", "resource", siteIds.first().toString())).getOrNull()?.body)
                else -> coroutineScope {
                    siteIds.take(10).map { sid ->
                        async { parseItems(authedRequest(listOf("site", "resource", sid.toString())).getOrNull()?.body) }
                    }.flatMap { it.await() }
                }
            }
        } else {
            val q = mutableListOf("keyword" to keyword)
            if (siteIds.isNotEmpty()) q += "sites" to siteIds.joinToString(",")
            return parseItems(authedRequest(listOf("search", "title"), query = q).getOrNull()?.body)
        }
    }

    suspend fun searchResources(keyword: String, siteId: Int?): List<ResourceItemDto> =
        searchResources(keyword, siteId?.let { listOf(it) } ?: emptyList())

    fun filterResourcesWithRust(items: List<ResourceItemDto>, criteriaJson: String = ""): ResourceFilterResultDto {
        val rawJson = json.encodeToString(kotlinx.serialization.builtins.ListSerializer(ResourceItemDto.serializer()), items)
        val outJson = RustCoreBridge.filterResources(rawJson, criteriaJson)
        return runCatching { json.decodeFromString<ResourceFilterResultDto>(outJson) }
            .getOrDefault(ResourceFilterResultDto())
    }

    /** 提交真实站点种子下载请求（调用 `POST /api/v1/download/add`，无损携带服务端原始 `torrent_info`）。 */
    suspend fun addDownload(
        item: ResourceItemDto,
        downloader: String? = null,
        savePath: String? = null,
    ): Pair<Boolean, String> {
        val rawWrapper = resourceRawCache[item.id]
        val torrentObj = rawWrapper?.get("torrent_info").asObj() ?: rawWrapper ?: JsonObject(
            mapOf(
                "title" to JsonPrimitive(item.title),
                "description" to JsonPrimitive(item.description),
                "enclosure" to JsonPrimitive(item.enclosure),
                "site_name" to JsonPrimitive(item.siteName),
                "size" to JsonPrimitive(item.size),
                "seeders" to JsonPrimitive(item.seeders),
                "peers" to JsonPrimitive(item.peers),
                "downloadvolumefactor" to JsonPrimitive(item.downloadvolumefactor),
                "uploadvolumefactor" to JsonPrimitive(item.uploadvolumefactor),
                "labels" to JsonArray(item.labels.map { JsonPrimitive(it) }),
            ),
        )
        val payloadMap = mutableMapOf<String, JsonElement>(
            "torrent_in" to torrentObj,
        )
        val dlClean = downloader?.trim().orEmpty()
        val pathClean = savePath?.trim().orEmpty()
        if (dlClean.isNotBlank() && dlClean != "默认下载器") {
            payloadMap["downloader"] = JsonPrimitive(dlClean)
        }
        if (pathClean.isNotBlank() && pathClean != "自动目录") {
            payloadMap["save_path"] = JsonPrimitive(pathClean)
        }
        var resp = authedRequest(
            segments = listOf("download", "add"),
            method = "POST",
            body = JsonObject(payloadMap).toString(),
        ).getOrNull()
        // 兼容直接接收扁平 TorrentInfo + Query 参数的实例签名
        val firstObj = runCatching { resp?.body?.let { json.parseToJsonElement(it).asObj() } }.getOrNull()
        val firstOk = firstObj?.bool("success") ?: (resp != null && resp.status in 200..299)
        if (resp != null && (resp.status == 422 || (!firstOk && (firstObj?.str("message")?.contains("为空") == true)))) {
            val flatMap = torrentObj.toMutableMap()
            if (dlClean.isNotBlank() && dlClean != "默认下载器") flatMap["downloader"] = JsonPrimitive(dlClean)
            if (pathClean.isNotBlank() && pathClean != "自动目录") flatMap["save_path"] = JsonPrimitive(pathClean)
            val fallbackQuery = buildList {
                if (dlClean.isNotBlank() && dlClean != "默认下载器") add("downloader" to dlClean)
                if (pathClean.isNotBlank() && pathClean != "自动目录") add("save_path" to pathClean)
            }
            resp = authedRequest(
                segments = listOf("download", "add"),
                method = "POST",
                query = fallbackQuery,
                body = JsonObject(flatMap).toString(),
            ).getOrNull()
        }
        if (resp == null) return false to "下载请求发送失败，请检查网络连接"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: if (ok) "已添加下载任务：${item.title}" else "添加下载失败（HTTP ${resp.status}）"
        return ok to msg
    }

    suspend fun fetchDownloads(downloaderName: String? = null): List<DownloadTaskDto> {
        val query = if (!downloaderName.isNullOrBlank()) listOf("name" to downloaderName) else emptyList()
        val resp = authedRequest(listOf("download"), query = query, trailingSlash = true).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val media = obj["media"].asObj()
            DownloadTaskDto(
                hash = obj.str("hash") ?: "",
                downloader = obj.str("downloader") ?: downloaderName?.takeIf { it.isNotBlank() } ?: "qBittorrent",
                title = obj.str("title") ?: return@mapNotNull null,
                name = obj.str("name") ?: media?.str("title") ?: obj.str("title") ?: "",
                year = obj.str("year") ?: "",
                seasonEpisode = obj.str("season_episode") ?: "",
                siteName = obj.str("site_name") ?: "",
                size = obj.dbl("size") ?: 0.0,
                progress = obj.dbl("progress") ?: 0.0,
                state = obj.str("state") ?: "downloading",
                upspeed = obj.str("upspeed") ?: "0 B/s",
                dlspeed = obj.str("dlspeed") ?: "0 B/s",
                leftTime = obj.str("left_time") ?: "",
                poster = resolveImageUrl(media?.str("poster") ?: media?.str("backdrop"), maxWidth = 360),
            )
        }
    }

    /** 恢复指定下载任务（`GET /api/v1/download/start/{hash}?name=...`）。 */
    suspend fun startDownload(hash: String, downloaderName: String? = null): Pair<Boolean, String> {
        if (hash.isBlank()) return false to "任务缺少 Hash 标识"
        val q = if (!downloaderName.isNullOrBlank()) listOf("name" to downloaderName) else emptyList()
        val resp = authedRequest(listOf("download", "start", hash), method = "GET", query = q).getOrNull()
            ?: return false to "网络请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "已恢复下载任务" else "恢复失败（HTTP ${resp.status}）")
    }

    /** 暂停指定下载任务（`GET /api/v1/download/stop/{hash}?name=...`）。 */
    suspend fun stopDownload(hash: String, downloaderName: String? = null): Pair<Boolean, String> {
        if (hash.isBlank()) return false to "任务缺少 Hash 标识"
        val q = if (!downloaderName.isNullOrBlank()) listOf("name" to downloaderName) else emptyList()
        val resp = authedRequest(listOf("download", "stop", hash), method = "GET", query = q).getOrNull()
            ?: return false to "网络请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "已暂停下载任务" else "暂停失败（HTTP ${resp.status}）")
    }

    /** 删除指定下载任务（`DELETE /api/v1/download/{hash}?name=...`）。 */
    suspend fun removeDownload(hash: String, downloaderName: String? = null): Pair<Boolean, String> {
        if (hash.isBlank()) return false to "任务缺少 Hash 标识"
        val q = if (!downloaderName.isNullOrBlank()) listOf("name" to downloaderName) else emptyList()
        val resp = authedRequest(listOf("download", hash), method = "DELETE", query = q).getOrNull()
            ?: return false to "网络请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "已移除下载任务" else "移除失败（HTTP ${resp.status}）")
    }

    // ==================== 文件 / 整理历史 / 队列 ====================

    suspend fun fetchFiles(storage: String = "local", path: String = "/"): List<StorageFileDto> {
        val body = """{"storage":"${esc(storage)}","path":"${esc(path)}","type":"dir"}"""
        val resp = authedRequest(listOf("storage", "list"), method = "POST", body = body).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            StorageFileDto(
                storage = obj.str("storage") ?: storage,
                type = obj.str("type") ?: "file",
                path = obj.str("path") ?: "",
                name = obj.str("name") ?: return@mapNotNull null,
                extension = obj.str("extension"),
                size = obj.lng("size") ?: 0L,
                modifyTime = obj.str("modify_time") ?: "",
            )
        }
    }

    suspend fun fetchTransferHistory(search: String = ""): Pair<Int, List<TransferHistoryDto>> {
        val query = if (search.isBlank()) listOf("page" to "1", "count" to "50") else listOf("title" to search, "page" to "1", "count" to "50")
        val resp = authedRequest(listOf("history", "transfer"), query = query).getOrNull() ?: return 0 to emptyList()
        val dataObj = extractObject(resp.body)
        val total = dataObj?.int("total") ?: 0
        val list = extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val srcFile = obj["src_fileitem"].asObj()
            val destFile = obj["dest_fileitem"].asObj()
            TransferHistoryDto(
                id = obj.int("id") ?: 0,
                title = obj.str("title") ?: return@mapNotNull null,
                type = obj.str("type") ?: "电影",
                year = obj.str("year") ?: "",
                seasons = obj.str("seasons") ?: "",
                episodes = obj.str("episodes") ?: "",
                status = obj.bool("status") ?: true,
                mode = obj.str("mode") ?: "copy",
                date = obj.str("date") ?: "",
                errmsg = obj.str("errmsg"),
                src = obj.str("src") ?: "",
                dest = obj.str("dest") ?: "",
                srcStorage = srcFile?.str("storage") ?: obj.str("src_storage") ?: "local",
                destStorage = destFile?.str("storage") ?: obj.str("dest_storage") ?: "local",
                sizeBytes = srcFile?.lng("size") ?: 0L,
                image = resolveImageUrl(obj.str("image"), maxWidth = 320),
                rawJson = obj.toString(),
            )
        }
        return (if (total > 0) total else list.size) to list
    }

    /**
     * 删除整理历史记录并按需清理源文件/目标文件（调用 `DELETE /api/v1/history/transfer?deletesrc=...&deletedest=...`，
     * 请求体完整携带服务端 `TransferHistory` JSON 对象，1:1 对齐 MoviePilot `history.py`）。
     */
    suspend fun deleteTransferHistory(
        record: TransferHistoryDto,
        deleteSrc: Boolean,
        deleteDest: Boolean,
    ): Pair<Boolean, String> {
        val bodyJson = record.rawJson.takeIf { it.isNotBlank() } ?: JsonObject(
            mapOf(
                "id" to JsonPrimitive(record.id),
                "title" to JsonPrimitive(record.title),
                "type" to JsonPrimitive(record.type),
                "year" to JsonPrimitive(record.year),
                "seasons" to JsonPrimitive(record.seasons),
                "episodes" to JsonPrimitive(record.episodes),
                "src" to JsonPrimitive(record.src),
                "dest" to JsonPrimitive(record.dest),
                "src_storage" to JsonPrimitive(record.srcStorage),
                "dest_storage" to JsonPrimitive(record.destStorage),
                "mode" to JsonPrimitive(record.mode),
                "status" to JsonPrimitive(record.status),
                "date" to JsonPrimitive(record.date),
            ),
        ).toString()
        val resp = authedRequest(
            segments = listOf("history", "transfer"),
            method = "DELETE",
            query = listOf(
                "deletesrc" to deleteSrc.toString(),
                "deletedest" to deleteDest.toString(),
            ),
            body = bodyJson,
        ).getOrNull() ?: return false to "删除请求失败，请检查网络连接"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: if (ok) "整理记录已移除" else "删除失败（HTTP ${resp.status}）"
        return ok to msg
    }

    suspend fun fetchTransferQueue(): List<TransferQueueItemDto> {
        val resp = authedRequest(listOf("transfer", "queue")).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val fileitem = obj["fileitem"].asObj()
            val media = obj["media"].asObj()
            TransferQueueItemDto(
                title = media?.str("title") ?: fileitem?.str("name") ?: obj.str("title") ?: return@mapNotNull null,
                src = fileitem?.str("path") ?: obj.str("src") ?: "",
                dest = obj.str("target") ?: obj.str("dest") ?: "",
                state = obj.str("state") ?: "等待整理",
                size = fileitem?.lng("size") ?: 0L,
            )
        }
    }

    // ==================== 仪表盘 / 定时服务 / 插件图表 / 系统日志 / 真实诊断 ====================

    suspend fun fetchDashboardStats(): DashboardStatsDto {
        val statObj = extractObject(authedRequest(listOf("dashboard", "statistic")).getOrNull()?.body)
        val storageObj = extractObject(authedRequest(listOf("dashboard", "storage")).getOrNull()?.body)
        val dlObj = extractObject(authedRequest(listOf("dashboard", "downloader")).getOrNull()?.body)
        val transferArr = extractArray(authedRequest(listOf("dashboard", "transfer")).getOrNull()?.body)
        val cpuResp = authedRequest(listOf("dashboard", "cpu")).getOrNull()?.body
        val memObj = extractObject(authedRequest(listOf("dashboard", "memory")).getOrNull()?.body)

        val cpuVal = runCatching {
            val root = json.parseToJsonElement(cpuResp ?: "{}")
            when (root) {
                is JsonPrimitive -> root.doubleOrNull
                is JsonObject -> root["data"].asPrim()?.doubleOrNull
                else -> null
            }
        }.getOrNull() ?: 0.0

        val memUsage = memObj?.dbl("usage")
            ?: memObj?.let {
                val u = it.dbl("used") ?: 0.0
                val t = it.dbl("total") ?: 1.0
                if (t > 0) u / t * 100.0 else 0.0
            } ?: 0.0

        val days = transferArr.mapNotNull { it.asPrim()?.intOrNull }

        val stats = DashboardStatsDto(
            movieCount = statObj?.int("movie_count") ?: 0,
            tvCount = statObj?.int("tv_count") ?: 0,
            episodeCount = statObj?.int("episode_count"),
            musicCount = statObj?.int("music_count") ?: 0,
            movieCountMonth = statObj?.int("movie_count_month") ?: 0,
            tvCountMonth = statObj?.int("tv_count_month") ?: 0,
            episodeCountMonth = statObj?.int("episode_count_month") ?: 0,
            musicCountMonth = statObj?.int("music_count_month") ?: 0,
            usedBytes = storageObj?.dbl("used_storage") ?: 0.0,
            totalBytes = storageObj?.dbl("total_storage") ?: 0.0,
            downloadSpeed = dlObj?.dbl("download_speed") ?: 0.0,
            uploadSpeed = dlObj?.dbl("upload_speed") ?: 0.0,
            totalDownloadBytes = dlObj?.dbl("download_size") ?: 0.0,
            cpuPercent = cpuVal,
            memoryPercent = memUsage,
            transfer7Days = days,
        )
        persistWidgetSnapshot(stats)
        return stats
    }

    private fun formatRateLabel(bytesPerSec: Double): String = when {
        bytesPerSec >= 1024.0 * 1024.0 * 1024.0 -> String.format("%.1f GB/s", bytesPerSec / (1024.0 * 1024.0 * 1024.0))
        bytesPerSec >= 1024.0 * 1024.0 -> String.format("%.1f MB/s", bytesPerSec / (1024.0 * 1024.0))
        bytesPerSec >= 1024.0 -> String.format("%.1f KB/s", bytesPerSec / 1024.0)
        bytesPerSec > 0.0 -> String.format("%.0f B/s", bytesPerSec)
        else -> "0 B/s"
    }

    private fun formatStorageLabel(bytes: Double): String = when {
        bytes >= 1024.0 * 1024.0 * 1024.0 * 1024.0 -> String.format("%.2f TB", bytes / (1024.0 * 1024.0 * 1024.0 * 1024.0))
        bytes >= 1024.0 * 1024.0 * 1024.0 -> String.format("%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0))
        bytes >= 1024.0 * 1024.0 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
        bytes > 0.0 -> String.format("%.0f KB", bytes / 1024.0)
        else -> "—"
    }

    private fun buildOverviewSectionJson(stats: DashboardStatsDto, nowTime: String): JsonObject {
        val dlRate = formatRateLabel(stats.downloadSpeed)
        val ulRate = formatRateLabel(stats.uploadSpeed)
        val freeBytes = (stats.totalBytes - stats.usedBytes).coerceAtLeast(0.0)
        return buildJsonObject {
            put("content", "overview")
            put("title", "系统概览")
            put("updatedAt", nowTime)
            put(
                "metrics",
                JsonArray(
                    listOf(
                        buildJsonObject {
                            put("id", "cpu")
                            put("title", "CPU 占用")
                            put("value", String.format("%.1f%%", stats.cpuPercent))
                            put("tone", if (stats.cpuPercent >= 85.0) "warning" else "accent")
                        },
                        buildJsonObject {
                            put("id", "memory")
                            put("title", "内存占用")
                            put("value", String.format("%.1f%%", stats.memoryPercent))
                            put("tone", if (stats.memoryPercent >= 85.0) "warning" else "default")
                        },
                        buildJsonObject {
                            put("id", "networkDownload")
                            put("title", "下载速度")
                            put("value", dlRate)
                            put("tone", "success")
                        },
                        buildJsonObject {
                            put("id", "networkUpload")
                            put("title", "上传速度")
                            put("value", ulRate)
                            put("tone", "default")
                        },
                        buildJsonObject {
                            put("id", "storageUsed")
                            put("title", "已用存储")
                            put("value", formatStorageLabel(stats.usedBytes))
                            put("tone", "default")
                        },
                        buildJsonObject {
                            put("id", "freeSpace")
                            put("title", "剩余空间")
                            put("value", if (stats.totalBytes > 0.0) formatStorageLabel(freeBytes) else "—")
                            put("tone", "default")
                        },
                    ),
                ),
            )
            put("items", JsonArray(emptyList()))
        }
    }

    private fun persistWidgetSnapshot(stats: DashboardStatsDto) {
        runCatching {
            val serverHost = (_session.value as? SessionState.Authenticated)?.serverUrl
                ?.substringAfter("://")
                ?.substringBefore("/")
                ?.ifBlank { "MoviePilot" } ?: "MoviePilot"
            val speedStr = formatRateLabel(stats.downloadSpeed)
            val nowTime = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date())
            val overviewJson = buildOverviewSectionJson(stats, nowTime).toString()
            val prefs = appContext.getSharedPreferences("mp_widget_snapshot_v1", Context.MODE_PRIVATE)
            val editor = prefs.edit()
                .putInt("movies", stats.movieCount)
                .putInt("tvs", stats.tvCount)
                .putString("speed", speedStr)
                .putString("server", serverHost)
                .putString("updated_at", nowTime)
                .putString("overview", overviewJson)
            if (prefs.getString("imports", null).isNullOrBlank()) {
                val totalMedia = stats.movieCount + stats.tvCount + stats.musicCount
                val fallbackImports = buildJsonObject {
                    put("content", "imports")
                    put("title", "近期入库")
                    put("updatedAt", nowTime)
                    put(
                        "metrics",
                        JsonArray(
                            listOf(
                                buildJsonObject { put("id", "count"); put("title", "总入库"); put("value", totalMedia.toString()); put("tone", "accent") },
                                buildJsonObject { put("id", "typeMOVIE"); put("title", "电影"); put("value", stats.movieCount.toString()) },
                                buildJsonObject { put("id", "typeTV"); put("title", "电视剧"); put("value", stats.tvCount.toString()) },
                                buildJsonObject { put("id", "typeMUSIC"); put("title", "音乐"); put("value", stats.musicCount.toString()) },
                            ),
                        ),
                    )
                    put("items", JsonArray(emptyList()))
                }
                editor.putString("imports", fallbackImports.toString())
            }
            editor.apply()
            val updateIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                setPackage(appContext.packageName)
            }
            appContext.sendBroadcast(updateIntent)
        }
    }

    /** 完整同步 APP 主体桌面小组件的 4 类核心快照（`overview` / `downloads` / `imports` / `subscriptions`）至 `"mp_widget_snapshot_v1"`。 */
    suspend fun syncAppWidgetSnapshot(): Boolean = coroutineScope {
        if (_session.value !is SessionState.Authenticated) return@coroutineScope false
        runCatching {
            val statsDef = async { runCatching { fetchDashboardStats() }.getOrNull() }
            val dlDef = async { runCatching { fetchDownloads() }.getOrDefault(emptyList()) }
            val histDef = async { runCatching { fetchTransferHistory() }.getOrDefault(0 to emptyList()) }
            val subDef = async { runCatching { fetchSubscriptions(forceRefresh = false) }.getOrDefault(emptyList()) }

            val stats = statsDef.await() ?: DashboardStatsDto()
            val downloads = dlDef.await()
            val (historyTotal, historyItems) = histDef.await()
            val subs = subDef.await()
            val nowTime = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date())
            val serverHost = (_session.value as? SessionState.Authenticated)?.serverUrl
                ?.substringAfter("://")
                ?.substringBefore("/")
                ?.ifBlank { "MoviePilot" } ?: "MoviePilot"

            val overviewObj = buildOverviewSectionJson(stats, nowTime)
            val freeBytes = (stats.totalBytes - stats.usedBytes).coerceAtLeast(0.0)
            val downloadingCount = downloads.count { !it.state.lowercase().contains("pause") && !it.state.lowercase().contains("stop") }
            val pausedCount = (downloads.size - downloadingCount).coerceAtLeast(0)
            val downloadsObj = buildJsonObject {
                put("content", "downloads")
                put("title", "下载状态")
                put("updatedAt", nowTime)
                put(
                    "metrics",
                    JsonArray(
                        listOf(
                            buildJsonObject { put("id", "downloadSpeed"); put("title", "下载速度"); put("value", formatRateLabel(stats.downloadSpeed)); put("tone", "success") },
                            buildJsonObject { put("id", "uploadSpeed"); put("title", "上传速度"); put("value", formatRateLabel(stats.uploadSpeed)) },
                            buildJsonObject { put("id", "freeSpace"); put("title", "剩余空间"); put("value", if (stats.totalBytes > 0.0) formatStorageLabel(freeBytes) else "—") },
                            buildJsonObject { put("id", "count"); put("title", "任务数"); put("value", downloads.size.toString()); put("tone", "accent") },
                            buildJsonObject { put("id", "statedownloading"); put("title", "下载中"); put("value", downloadingCount.toString()) },
                            buildJsonObject { put("id", "statepaused"); put("title", "已暂停"); put("value", pausedCount.toString()) },
                        ),
                    ),
                )
                put(
                    "items",
                    JsonArray(
                        downloads.take(6).mapIndexed { idx, task ->
                            val normProg = (if (task.progress > 1.0) task.progress / 100.0 else task.progress).coerceIn(0.0, 1.0)
                            val subParts = listOfNotNull(
                                task.seasonEpisode.takeIf { it.isNotBlank() },
                                task.dlspeed.takeIf { it.isNotBlank() },
                                task.leftTime.takeIf { it.isNotBlank() }?.let { "剩余 $it" },
                            )
                            buildJsonObject {
                                put("id", task.hash.ifBlank { "dl-$idx" })
                                put("title", task.name.ifBlank { task.title })
                                put("subtitle", subParts.joinToString(" · "))
                                put("progress", normProg)
                            }
                        },
                    ),
                )
            }

            val successHistory = historyItems.filter { it.status }
            val totalImports = if (historyTotal > 0) historyTotal else (stats.movieCount + stats.tvCount + stats.musicCount)
            val importsObj = buildJsonObject {
                put("content", "imports")
                put("title", "近期入库")
                put("updatedAt", nowTime)
                put(
                    "metrics",
                    JsonArray(
                        listOf(
                            buildJsonObject { put("id", "count"); put("title", "总入库"); put("value", totalImports.toString()); put("tone", "accent") },
                            buildJsonObject { put("id", "typeMOVIE"); put("title", "电影"); put("value", stats.movieCount.toString()) },
                            buildJsonObject { put("id", "typeTV"); put("title", "电视剧"); put("value", stats.tvCount.toString()) },
                            buildJsonObject { put("id", "typeMUSIC"); put("title", "音乐"); put("value", stats.musicCount.toString()) },
                        ),
                    ),
                )
                put(
                    "items",
                    JsonArray(
                        successHistory.take(6).mapIndexed { idx, item ->
                            val se = listOf(item.seasons, item.episodes).filter { it.isNotBlank() }.joinToString(" ")
                            val subParts = listOfNotNull(
                                item.year.takeIf { it.isNotBlank() },
                                item.type.takeIf { it.isNotBlank() },
                                se.takeIf { it.isNotBlank() },
                                item.date.takeIf { it.isNotBlank() },
                            )
                            buildJsonObject {
                                put("id", "imp-${item.id}-$idx")
                                put("title", item.title)
                                put("subtitle", subParts.joinToString(" · "))
                            }
                        },
                    ),
                )
            }

            val movieSubs = subs.count { !isTvType(it.type) && !it.type.contains("音乐") && !it.type.lowercase().contains("music") }
            val tvSubs = subs.count { isTvType(it.type) }
            val musicSubs = (subs.size - movieSubs - tvSubs).coerceAtLeast(0)
            val activeSubs = subs.count { it.state.equals("R", true) || it.state.equals("N", true) }
            val subscriptionsObj = buildJsonObject {
                put("content", "subscriptions")
                put("title", "订阅")
                put("updatedAt", nowTime)
                put(
                    "metrics",
                    JsonArray(
                        listOf(
                            buildJsonObject { put("id", "count"); put("title", "总订阅"); put("value", subs.size.toString()); put("tone", "accent") },
                            buildJsonObject { put("id", "typeMOVIE"); put("title", "电影"); put("value", movieSubs.toString()) },
                            buildJsonObject { put("id", "typeTV"); put("title", "电视剧"); put("value", tvSubs.toString()) },
                            buildJsonObject { put("id", "stateR"); put("title", "订阅中"); put("value", activeSubs.toString()); put("tone", "success") },
                        ) + if (musicSubs > 0) {
                            listOf(buildJsonObject { put("id", "typeMUSIC"); put("title", "音乐"); put("value", musicSubs.toString()) })
                        } else {
                            emptyList()
                        },
                    ),
                )
                put(
                    "items",
                    JsonArray(
                        subs.take(6).mapIndexed { idx, sub ->
                            val doneEp = (sub.totalEpisode - sub.lackEpisode).coerceAtLeast(0)
                            val prog = if (sub.totalEpisode > 0) (doneEp.toDouble() / sub.totalEpisode.toDouble()).coerceIn(0.0, 1.0) else null
                            val subParts = buildList {
                                add(if (isTvType(sub.type)) "电视剧" else sub.type.ifBlank { "电影" })
                                if (isTvType(sub.type) && (sub.season ?: 0) > 0) add("S%02d".format(sub.season))
                                if (sub.totalEpisode > 0) add("$doneEp/${sub.totalEpisode} 集")
                                if (sub.resolution.isNotBlank()) add(sub.resolution)
                            }
                            buildJsonObject {
                                put("id", "sub-${sub.id}-$idx")
                                put("title", sub.name)
                                put("subtitle", subParts.joinToString(" · "))
                                if (prog != null) put("progress", prog)
                            }
                        },
                    ),
                )
            }

            appContext.getSharedPreferences("mp_widget_snapshot_v1", Context.MODE_PRIVATE)
                .edit()
                .putInt("movies", stats.movieCount)
                .putInt("tvs", stats.tvCount)
                .putString("speed", formatRateLabel(stats.downloadSpeed))
                .putString("server", serverHost)
                .putString("updated_at", nowTime)
                .putString("overview", overviewObj.toString())
                .putString("downloads", downloadsObj.toString())
                .putString("imports", importsObj.toString())
                .putString("subscriptions", subscriptionsObj.toString())
                .apply()

            val updateIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                setPackage(appContext.packageName)
            }
            appContext.sendBroadcast(updateIntent)
            true
        }.getOrDefault(false)
    }

    /** 拉取已启用模块并合并目录类型元数据；主列表失败时向调用方报告，避免误显示为空列表。 */
    suspend fun fetchSystemModules(): List<SystemModuleStatusDto> = coroutineScope {
        val listDef = async { authedRequest(listOf("system", "modulelist")).getOrThrow() }
        val catalogDef = async {
            runCatching { authedRequest(listOf("system", "module-catalog")).getOrNull() }.getOrNull()
        }
        val resp = listDef.await()
        check(resp.status in 200..299) { "加载系统模块失败（HTTP ${resp.status}）" }

        val catalogMap = mutableMapOf<String, Pair<String, String>>()
        val catBody = catalogDef.await()?.takeIf { it.status in 200..299 }?.body
        if (!catBody.isNullOrBlank()) {
            val catArr = (extractObject(catBody)?.get("modules") as? JsonArray) ?: extractArray(catBody)
            catArr.forEach { el ->
                val obj = el.asObj() ?: return@forEach
                val id = obj.str("id") ?: return@forEach
                val mType = obj.str("type") ?: obj.str("module_type").orEmpty()
                val subType = obj.str("subtype") ?: obj.str("module_subtype") ?: obj.str("sub_type").orEmpty()
                catalogMap[id] = mType to subType
            }
        }

        val moduleArr = (extractObject(resp.body)?.get("modules") as? JsonArray) ?: extractArray(resp.body)
        moduleArr.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val id = obj.str("id") ?: return@mapNotNull null
            val (catType, catSub) = catalogMap[id] ?: ("" to "")
            SystemModuleStatusDto(
                id = id,
                name = obj.str("name_i18n")?.takeIf { it.isNotBlank() }
                    ?: obj.str("name")?.takeIf { it.isNotBlank() }
                    ?: id,
                moduleType = obj.str("type") ?: obj.str("module_type") ?: catType,
                subType = obj.str("subtype") ?: obj.str("module_subtype") ?: obj.str("sub_type") ?: catSub,
            )
        }
    }

    /** 对单个系统模块执行真实连通/健康自检（`GET /api/v1/system/moduletest/{id}`）。 */
    suspend fun testSystemModule(moduleId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("system", "moduletest", moduleId)).getOrNull()
            ?: return false to "请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message")?.takeIf { it.isNotBlank() }
            ?: if (ok) "模块运行正常" else "检测未通过（HTTP ${resp.status}）"
        return ok to msg
    }

    /** 调用服务端真实媒体名称识别接口（`GET /api/v1/media/recognize`）。 */
    suspend fun recognizeMediaTitle(title: String, subtitle: String = ""): RecognizeResultDto? {
        val clean = title.trim()
        if (clean.isEmpty()) return null
        val q = buildList {
            add("title" to clean)
            if (subtitle.isNotBlank()) add("subtitle" to subtitle.trim())
        }
        val resp = authedRequest(listOf("media", "recognize"), query = q).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val root = extractObject(resp.body) ?: return null
        val meta = root["meta_info"].asObj() ?: root
        val media = root["media_info"].asObj()
        val seasonEp = buildString {
            val s = meta.str("season_episode") ?: media?.str("season_episode").orEmpty()
            if (s.isNotBlank()) {
                append(s)
            } else {
                meta.int("begin_season")?.let { append("S%02d".format(it)) }
                meta.int("begin_episode")?.let { append("E%02d".format(it)) }
            }
        }
        return RecognizeResultDto(
            rawTitle = clean,
            cnName = meta.str("cn_name").orEmpty(),
            enName = meta.str("en_name").orEmpty(),
            recognizedTitle = media?.str("title") ?: meta.str("name") ?: meta.str("cn_name") ?: meta.str("en_name").orEmpty(),
            year = media?.str("year") ?: meta.str("year").orEmpty(),
            type = media?.str("type") ?: meta.str("type").orEmpty(),
            category = media?.str("category").orEmpty(),
            tmdbId = media?.int("tmdb_id") ?: media?.int("tmdbid"),
            seasonEpisode = seasonEp,
            resourcePix = meta.str("resource_pix").orEmpty(),
            resourceType = meta.str("resource_type").orEmpty(),
            videoEncode = meta.str("video_encode").orEmpty(),
            audioEncode = meta.str("audio_encode").orEmpty(),
            resourceTeam = meta.str("resource_team").orEmpty(),
            voteAverage = media?.dbl("vote_average") ?: 0.0,
            posterPath = resolveImageUrl(media?.str("poster_path") ?: media?.str("backdrop_path"), maxWidth = 400),
            overview = media?.str("overview").orEmpty(),
        )
    }

    /** 调用服务端真实网络连通性测试接口（`GET /api/v1/system/nettest`）。 */
    suspend fun runNetworkTest(url: String, proxy: Boolean = true, name: String = ""): NetTestResultDto {
        val targetUrl = url.trim()
        val startMs = System.currentTimeMillis()
        val resp = authedRequest(
            segments = listOf("system", "nettest"),
            query = listOf("url" to targetUrl, "proxy" to proxy.toString()),
        ).getOrNull()
        val elapsed = (System.currentTimeMillis() - startMs).coerceAtLeast(1L)
        if (resp == null) {
            return NetTestResultDto(
                name = name.ifBlank { targetUrl },
                url = targetUrl,
                proxy = proxy,
                ok = false,
                latencyMs = null,
                message = "请求超时或网络不可达",
            )
        }
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val dataObj = obj?.get("data").asObj()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val serverTimeMs = dataObj?.dbl("time")?.let {
            if (it < 30.0) (it * 1000.0).toLong() else it.toLong()
        } ?: dataObj?.lng("latency") ?: if (ok) elapsed else null
        val msg = obj?.str("message") ?: if (ok) "连通正常" else "连接失败（HTTP ${resp.status}）"
        return NetTestResultDto(
            name = name.ifBlank { targetUrl },
            url = targetUrl,
            proxy = proxy,
            ok = ok,
            latencyMs = serverTimeMs,
            message = msg,
        )
    }

    suspend fun fetchScheduledServices(): List<ScheduledServiceDto> {
        val resp = authedRequest(listOf("dashboard", "schedule")).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            ScheduledServiceDto(
                id = obj.str("id") ?: return@mapNotNull null,
                name = obj.str("name") ?: "",
                provider = obj.str("provider") ?: "",
                status = obj.str("status") ?: "等待",
                nextRun = obj.str("next_run") ?: "",
            )
        }
    }

    suspend fun fetchPluginDashboardMetas(): List<PluginDashboardMetaDto> {
        val resp = authedRequest(listOf("plugin", "dashboard", "meta")).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            PluginDashboardMetaDto(
                id = obj.str("id") ?: return@mapNotNull null,
                key = obj.str("key") ?: "",
                name = obj.str("name") ?: "",
            )
        }
    }

    suspend fun fetchPluginDashboardWidgetJson(id: String, key: String): String? {
        val segs = if (key.isNotBlank()) listOf("plugin", "dashboard", id, key) else listOf("plugin", "dashboard", id)
        val resp = authedRequest(segs).getOrNull() ?: return null
        return if (resp.status in 200..299) resp.body else null
    }

    /** 拉取后端已启用插件的桌面小组件目录（`GET /api/v1/plugin/widgets/meta`，旧版后端 404 时自动回退仪表盘元信息）。 */
    suspend fun fetchPluginWidgetMetas(): List<PluginWidgetMetaDto> {
        val resp = authedRequest(listOf("plugin", "widgets", "meta")).getOrNull()
        if (resp != null && resp.status in 200..299) {
            val parsed = extractArray(resp.body).mapNotNull { el ->
                val obj = el.asObj() ?: return@mapNotNull null
                val pid = obj.str("plugin_id") ?: obj.str("pluginId") ?: obj.str("id") ?: return@mapNotNull null
                val pname = obj.str("plugin_name") ?: obj.str("pluginName") ?: pid
                val wkey = obj.str("key") ?: obj.str("widgetKey") ?: ""
                val wname = obj.str("name") ?: pname
                PluginWidgetMetaDto(
                    pluginId = pid,
                    pluginName = pname,
                    widgetKey = wkey,
                    name = wname,
                    description = obj.str("description") ?: "",
                    kind = obj.str("kind") ?: "metrics",
                    source = obj.str("source") ?: "widget",
                    hasPage = obj.bool("has_page") ?: obj.bool("hasPage") ?: false,
                )
            }
            if (parsed.isNotEmpty()) return parsed
        }
        return fetchPluginDashboardMetas().map { dash ->
            PluginWidgetMetaDto(
                pluginId = dash.id,
                pluginName = dash.id,
                widgetKey = dash.key,
                name = dash.name.ifBlank { dash.id },
                kind = "metrics",
                source = "dashboard",
                hasPage = true,
            )
        }
    }

    /** 拉取单个插件的专属桌面小组件快照 JSON（`GET /api/v1/plugin/widgets/{pluginId}?key=...`；不支持或为空时返回 `null` 供上层回退）。 */
    suspend fun fetchPluginWidgetSnapshotJson(pluginId: String, widgetKey: String = ""): String? {
        if (pluginId.isBlank()) return null
        val q = if (widgetKey.isNotBlank()) listOf("key" to widgetKey) else emptyList()
        val resp = authedRequest(listOf("plugin", "widgets", pluginId), query = q).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val trimmed = resp.body.trim()
        if (trimmed.isEmpty() || trimmed == "null" || trimmed == "{}") return null
        val obj = extractObject(trimmed)
        if (obj != null && obj.isEmpty()) return null
        return trimmed
    }

    /** 读取有限系统日志快照；后端 `length=-1` 按新到旧返回，正数会开启持续 SSE。 */
    suspend fun fetchSystemLogs(length: Int = 80): List<String> {
        val resp = authedRequest(listOf("system", "logging"), query = listOf("length" to "-1")).getOrNull()
            ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return resp.body.lineSequence().filter { it.isNotBlank() }.take(length.coerceAtLeast(0)).toList()
    }

    // ==================== 站点管理 + 实时流量聚合 + 单站历史趋势 + 图标 ====================

    suspend fun fetchSites(): List<SiteItemDto> {
        val siteResp = authedRequest(listOf("site"), trailingSlash = true).getOrNull()
        val udResp = authedRequest(listOf("site", "userdata", "latest")).getOrNull()
        val udMap = mutableMapOf<String, SiteUserDataPointDto>()
        extractArray(udResp?.body).forEach { el ->
            val obj = el.asObj() ?: return@forEach
            val domain = obj.str("domain") ?: return@forEach
            udMap[domain.lowercase()] = parseSiteUserDataPoint(obj)
        }
        return extractArray(siteResp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val id = obj.int("id") ?: 0
            val domain = obj.str("domain") ?: ""
            val ud = udMap[domain.lowercase()]
            SiteItemDto(
                id = id,
                name = obj.str("name") ?: return@mapNotNull null,
                domain = domain,
                url = obj.str("url") ?: "",
                pri = obj.int("pri") ?: 0,
                isActive = obj.bool("is_active") ?: true,
                uploadBytes = ud?.uploadBytes ?: obj.dbl("upload") ?: 0.0,
                downloadBytes = ud?.downloadBytes ?: obj.dbl("download") ?: 0.0,
                ratio = ud?.ratio ?: obj.dbl("ratio") ?: 0.0,
                seedingCount = ud?.seedingCount ?: obj.int("seeding") ?: 0,
                seedingSizeBytes = ud?.seedingSizeBytes ?: 0.0,
                bonus = ud?.bonus ?: 0.0,
                userLevel = ud?.userLevel ?: "",
                username = ud?.username ?: "",
                joinAt = ud?.joinAt ?: "",
                updatedDay = ud?.updatedDay ?: "",
                iconUrl = siteIconCache[id],
                cookie = obj.str("cookie") ?: "",
                ua = obj.str("ua") ?: "",
                rss = obj.str("rss") ?: "",
                proxy = obj.bool("proxy") ?: false,
                render = obj.bool("render") ?: false,
                rawJson = obj.toString(),
            )
        }.sortedBy { it.pri }
    }

    /** 新增或编辑站点（`POST /api/v1/site/` 或 `PUT /api/v1/site/`，无损保留其余字段）。 */
    suspend fun saveSite(site: SiteItemDto, isCreate: Boolean): Pair<Boolean, String> {
        val baseMap = runCatching {
            if (site.rawJson.isNotBlank()) json.parseToJsonElement(site.rawJson).asObj()?.toMutableMap() else null
        }.getOrNull() ?: mutableMapOf()
        if (!isCreate && site.id > 0) baseMap["id"] = JsonPrimitive(site.id)
        baseMap["name"] = JsonPrimitive(site.name.trim())
        baseMap["url"] = JsonPrimitive(site.url.trim())
        val domainClean = site.domain.trim().ifBlank {
            site.url.trim().substringAfter("://").substringBefore("/").substringBefore(":")
        }
        baseMap["domain"] = JsonPrimitive(domainClean)
        baseMap["pri"] = JsonPrimitive(site.pri)
        baseMap["is_active"] = JsonPrimitive(site.isActive)
        baseMap["cookie"] = JsonPrimitive(site.cookie.trim())
        baseMap["ua"] = JsonPrimitive(site.ua.trim())
        baseMap["rss"] = JsonPrimitive(site.rss.trim())
        baseMap["proxy"] = JsonPrimitive(site.proxy)
        baseMap["render"] = JsonPrimitive(site.render)
        val resp = authedRequest(
            segments = listOf("site"),
            method = if (isCreate) "POST" else "PUT",
            body = JsonObject(baseMap).toString(),
            trailingSlash = true,
        ).getOrNull() ?: return false to "网络请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: if (ok) (if (isCreate) "已新增站点" else "已保存站点配置") else "保存失败（HTTP ${resp.status}）"
        return ok to msg
    }

    /** 删除站点（`DELETE /api/v1/site/{id}`）。 */
    suspend fun deleteSite(siteId: Int): Boolean {
        val resp = authedRequest(listOf("site", siteId.toString()), method = "DELETE").getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun fetchSiteIcon(siteId: Int): String? {
        siteIconCache[siteId]?.let { return it }
        val resp = authedRequest(listOf("site", "icon", siteId.toString())).getOrNull() ?: return null
        val icon = extractObject(resp.body)?.str("icon") ?: return null
        siteIconCache[siteId] = icon
        return icon
    }

    suspend fun fetchSiteUserDataHistory(siteId: Int): List<SiteUserDataPointDto> {
        val resp = authedRequest(listOf("site", "userdata", siteId.toString())).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            parseSiteUserDataPoint(obj)
        }
    }

    suspend fun testSiteConnection(siteId: Int): Pair<Boolean, String> {
        val resp = authedRequest(listOf("site", "test", siteId.toString())).getOrNull()
            ?: return false to "请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: if (ok) "连通正常" else "连接失败"
        return ok to msg
    }

    private fun parseSiteUserDataPoint(obj: JsonObject) = SiteUserDataPointDto(
        domain = obj.str("domain") ?: "",
        name = obj.str("name") ?: "",
        username = obj.str("username") ?: "",
        userLevel = obj.str("user_level") ?: "",
        joinAt = obj.str("join_at") ?: "",
        uploadBytes = obj.dbl("upload") ?: 0.0,
        downloadBytes = obj.dbl("download") ?: 0.0,
        ratio = obj.dbl("ratio") ?: 0.0,
        seedingCount = obj.int("seeding") ?: 0,
        seedingSizeBytes = obj.dbl("seeding_size") ?: 0.0,
        bonus = obj.dbl("bonus") ?: 0.0,
        updatedDay = obj.str("updated_day") ?: "",
        updatedTime = obj.str("updated_time") ?: "",
    )

    // ==================== 用户管理 ====================

    suspend fun fetchUsers(): List<UserIdentity> {
        val resp = authedRequest(listOf("user"), trailingSlash = true).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            UserIdentity(
                id = obj.int("id") ?: 0,
                name = obj.str("name") ?: return@mapNotNull null,
                email = obj.str("email") ?: "",
                isSuperuser = obj.bool("is_superuser") ?: false,
                isActive = obj.bool("is_active") ?: true,
                isOtp = obj.bool("is_otp") ?: false,
                avatar = resolveImageUrl(obj.str("avatar")),
            )
        }
    }

    /** 新增用户账号（`POST /api/v1/user/`）。 */
    suspend fun createUser(
        name: String,
        password: String,
        email: String = "",
        isSuperuser: Boolean = false,
        isActive: Boolean = true,
        permissions: Map<String, Boolean> = emptyMap(),
    ): Pair<Boolean, String> {
        val permsJson = JsonObject(permissions.mapValues { JsonPrimitive(it.value) })
        val payload = JsonObject(
            buildMap {
                put("name", JsonPrimitive(name.trim()))
                put("password", JsonPrimitive(password))
                put("email", JsonPrimitive(email.trim()))
                put("is_superuser", JsonPrimitive(isSuperuser))
                put("is_active", JsonPrimitive(isActive))
                put("permissions", permsJson)
            },
        )
        val resp = authedRequest(
            segments = listOf("user"),
            method = "POST",
            body = payload.toString(),
            trailingSlash = true,
        ).getOrNull() ?: return false to "创建用户失败，请检查网络连接"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: obj?.str("detail") ?: if (ok) "已创建用户 ${name.trim()}" else "创建失败（HTTP ${resp.status}）"
        return ok to msg
    }

    /** 按用户 ID 删除账号（`DELETE /api/v1/user/id/{id}`）。 */
    suspend fun deleteUserById(userId: Int): Pair<Boolean, String> {
        val resp = authedRequest(
            segments = listOf("user", "id", userId.toString()),
            method = "DELETE",
        ).getOrNull() ?: return false to "删除请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: obj?.str("detail") ?: if (ok) "已删除该用户" else "删除失败（HTTP ${resp.status}）"
        return ok to msg
    }

    // ==================== 全量系统设置模块 ====================

    private suspend fun fetchSettingValue(key: String): JsonElement? {
        val resp = authedRequest(listOf("system", "setting", key)).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        return obj["value"] ?: obj
    }

    suspend fun saveSettingValue(key: String, rawValueJson: String): Boolean {
        val resp = authedRequest(
            segments = listOf("system", "setting", key),
            method = "POST",
            body = rawValueJson,
        ).getOrNull()
        val ok = resp != null && resp.status in 200..299
        if (ok && key in setOf("GLOBAL_IMAGE_CACHE", "TMDB_IMAGE_DOMAIN", "BANGUMI_PROXY_ENABLE", "BANGUMI_IMAGE_DOMAIN")) {
            refreshGlobalImageSettings()
        }
        return ok
    }

    suspend fun fetchDownloaders(): List<ServiceConfigDto> {
        val arr = fetchSettingValue("Downloaders").asArr() ?: return emptyList()
        return arr.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val cfg = obj["config"].asObj()
            ServiceConfigDto(
                name = obj.str("name") ?: return@mapNotNull null,
                type = obj.str("type") ?: "qbittorrent",
                enabled = obj.bool("enabled") ?: true,
                isDefault = obj.bool("default") ?: false,
                host = cfg?.str("host") ?: "",
                username = cfg?.str("username") ?: "",
                password = cfg?.str("password") ?: "",
                rawJson = obj.toString(),
            )
        }
    }

    suspend fun saveDownloader(item: ServiceConfigDto, originalName: String? = null): Boolean {
        val existing = fetchSettingValue("Downloaders").asArr()?.mapNotNull { it.asObj() }.orEmpty().toMutableList()
        val matchIdx = originalName?.let { orig -> existing.indexOfFirst { it.str("name") == orig } } ?: -1
        val baseMap = if (matchIdx >= 0) existing[matchIdx].toMutableMap() else mutableMapOf()
        val cfgMap = (baseMap["config"].asObj() ?: JsonObject(emptyMap())).toMutableMap()
        cfgMap["host"] = JsonPrimitive(item.host.trim())
        if (item.username.isNotBlank() || cfgMap.containsKey("username")) cfgMap["username"] = JsonPrimitive(item.username.trim())
        if (item.password.isNotBlank() || cfgMap.containsKey("password")) cfgMap["password"] = JsonPrimitive(item.password)
        baseMap["name"] = JsonPrimitive(item.name.trim())
        baseMap["type"] = JsonPrimitive(item.type.trim().ifBlank { "qbittorrent" })
        baseMap["enabled"] = JsonPrimitive(item.enabled)
        baseMap["default"] = JsonPrimitive(item.isDefault)
        baseMap["config"] = JsonObject(cfgMap)
        val updatedObj = JsonObject(baseMap)
        if (item.isDefault) {
            for (i in existing.indices) {
                val m = existing[i].toMutableMap()
                m["default"] = JsonPrimitive(false)
                existing[i] = JsonObject(m)
            }
        }
        if (matchIdx >= 0) existing[matchIdx] = updatedObj else existing.add(updatedObj)
        return saveSettingValue("Downloaders", JsonArray(existing).toString())
    }

    suspend fun deleteDownloader(name: String): Boolean {
        val remaining = fetchSettingValue("Downloaders").asArr()?.mapNotNull { it.asObj() }
            ?.filterNot { it.str("name") == name } ?: return false
        return saveSettingValue("Downloaders", JsonArray(remaining).toString())
    }

    suspend fun fetchMediaServers(): List<ServiceConfigDto> {
        val arr = fetchSettingValue("MediaServers").asArr() ?: return emptyList()
        return arr.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val cfg = obj["config"].asObj()
            ServiceConfigDto(
                name = obj.str("name") ?: return@mapNotNull null,
                type = obj.str("type") ?: "emby",
                enabled = obj.bool("enabled") ?: true,
                host = cfg?.str("host") ?: "",
                apikey = cfg?.str("apikey") ?: cfg?.str("token") ?: "",
                playHost = cfg?.str("play_host") ?: "",
                username = cfg?.str("username") ?: "",
                rawJson = obj.toString(),
            )
        }
    }

    suspend fun saveMediaServer(item: ServiceConfigDto, originalName: String? = null): Boolean {
        val existing = fetchSettingValue("MediaServers").asArr()?.mapNotNull { it.asObj() }.orEmpty().toMutableList()
        val matchIdx = originalName?.let { orig -> existing.indexOfFirst { it.str("name") == orig } } ?: -1
        val baseMap = if (matchIdx >= 0) existing[matchIdx].toMutableMap() else mutableMapOf()
        val cfgMap = (baseMap["config"].asObj() ?: JsonObject(emptyMap())).toMutableMap()
        cfgMap["host"] = JsonPrimitive(item.host.trim())
        if (item.apikey.isNotBlank() || cfgMap.containsKey("apikey")) {
            val keyField = if (item.type.equals("plex", ignoreCase = true) && !cfgMap.containsKey("apikey")) "token" else "apikey"
            cfgMap[keyField] = JsonPrimitive(item.apikey.trim())
        }
        if (item.playHost.isNotBlank() || cfgMap.containsKey("play_host")) cfgMap["play_host"] = JsonPrimitive(item.playHost.trim())
        if (item.username.isNotBlank() || cfgMap.containsKey("username")) cfgMap["username"] = JsonPrimitive(item.username.trim())
        baseMap["name"] = JsonPrimitive(item.name.trim())
        baseMap["type"] = JsonPrimitive(item.type.trim().ifBlank { "emby" })
        baseMap["enabled"] = JsonPrimitive(item.enabled)
        baseMap["config"] = JsonObject(cfgMap)
        val updatedObj = JsonObject(baseMap)
        if (matchIdx >= 0) existing[matchIdx] = updatedObj else existing.add(updatedObj)
        return saveSettingValue("MediaServers", JsonArray(existing).toString())
    }

    suspend fun deleteMediaServer(name: String): Boolean {
        val remaining = fetchSettingValue("MediaServers").asArr()?.mapNotNull { it.asObj() }
            ?.filterNot { it.str("name") == name } ?: return false
        return saveSettingValue("MediaServers", JsonArray(remaining).toString())
    }

    suspend fun fetchDirectories(): List<DirectoryConfigDto> {
        val arr = fetchSettingValue("Directories").asArr() ?: return emptyList()
        return arr.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            DirectoryConfigDto(
                name = obj.str("name") ?: "默认目录",
                priority = obj.int("priority") ?: 1,
                storage = obj.str("storage") ?: "local",
                downloadPath = obj.str("download_path") ?: "",
                libraryStorage = obj.str("library_storage") ?: "local",
                libraryPath = obj.str("library_path") ?: "",
                transferType = obj.str("transfer_type") ?: "copy",
                monitorType = obj.str("monitor_type") ?: "",
                renaming = obj.bool("renaming") ?: true,
                scraping = obj.bool("scraping") ?: true,
                notify = obj.bool("notify") ?: true,
                rawJson = obj.toString(),
            )
        }
    }

    suspend fun saveDirectory(item: DirectoryConfigDto, originalName: String? = null): Boolean {
        val existing = fetchSettingValue("Directories").asArr()?.mapNotNull { it.asObj() }.orEmpty().toMutableList()
        val matchIdx = originalName?.let { orig -> existing.indexOfFirst { it.str("name") == orig } } ?: -1
        val baseMap = if (matchIdx >= 0) existing[matchIdx].toMutableMap() else mutableMapOf()
        baseMap["name"] = JsonPrimitive(item.name.trim())
        baseMap["priority"] = JsonPrimitive(item.priority)
        baseMap["storage"] = JsonPrimitive(item.storage.ifBlank { "local" })
        baseMap["download_path"] = JsonPrimitive(item.downloadPath.trim())
        baseMap["library_storage"] = JsonPrimitive(item.libraryStorage.ifBlank { "local" })
        baseMap["library_path"] = JsonPrimitive(item.libraryPath.trim())
        baseMap["transfer_type"] = JsonPrimitive(item.transferType.ifBlank { "copy" })
        baseMap["monitor_type"] = JsonPrimitive(item.monitorType)
        baseMap["renaming"] = JsonPrimitive(item.renaming)
        baseMap["scraping"] = JsonPrimitive(item.scraping)
        baseMap["notify"] = JsonPrimitive(item.notify)
        val updatedObj = JsonObject(baseMap)
        if (matchIdx >= 0) existing[matchIdx] = updatedObj else existing.add(updatedObj)
        return saveSettingValue("Directories", JsonArray(existing).toString())
    }

    suspend fun deleteDirectory(name: String): Boolean {
        val remaining = fetchSettingValue("Directories").asArr()?.mapNotNull { it.asObj() }
            ?.filterNot { it.str("name") == name } ?: return false
        return saveSettingValue("Directories", JsonArray(remaining).toString())
    }

    suspend fun fetchStorages(): List<StorageConfigDto> {
        val arr = fetchSettingValue("Storages").asArr() ?: return emptyList()
        return arr.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            StorageConfigDto(
                name = obj.str("name") ?: return@mapNotNull null,
                type = obj.str("type") ?: "local",
            )
        }
    }

    suspend fun fetchNotificationChannels(): List<ServiceConfigDto> {
        val arr = fetchSettingValue("Notifications").asArr() ?: return emptyList()
        return arr.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val cfgObj = obj["config"].asObj()
            val cfgMap = mutableMapOf<String, String>()
            cfgObj?.forEach { (k, v) ->
                val prim = v.asPrim()
                if (prim != null && prim.content != "null") {
                    cfgMap[k] = prim.content
                }
            }
            ServiceConfigDto(
                name = obj.str("name") ?: return@mapNotNull null,
                type = obj.str("type") ?: "telegram",
                enabled = obj.bool("enabled") ?: true,
                switchs = obj["switchs"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s != "null" } } ?: emptyList(),
                config = cfgMap,
                rawJson = obj.toString(),
            )
        }
    }

    /** 新增或更新通知渠道配置（写入 `/api/v1/system/setting/Notifications`，无损保留未知 config 键）。 */
    suspend fun saveNotificationChannel(item: ServiceConfigDto, originalName: String? = null): Boolean {
        val existing = fetchSettingValue("Notifications").asArr()?.mapNotNull { it.asObj() }.orEmpty().toMutableList()
        val matchIdx = originalName?.let { orig -> existing.indexOfFirst { it.str("name") == orig } } ?: -1
        val baseMap = if (matchIdx >= 0) existing[matchIdx].toMutableMap() else mutableMapOf()
        val cfgMap = (baseMap["config"].asObj() ?: JsonObject(emptyMap())).toMutableMap()
        item.config.forEach { (k, v) ->
            if (k.isNotBlank()) {
                cfgMap[k] = JsonPrimitive(v.trim())
            }
        }
        baseMap["name"] = JsonPrimitive(item.name.trim())
        baseMap["type"] = JsonPrimitive(item.type.trim().ifBlank { "telegram" })
        baseMap["enabled"] = JsonPrimitive(item.enabled)
        baseMap["switchs"] = JsonArray(item.switchs.map { JsonPrimitive(it) })
        baseMap["config"] = JsonObject(cfgMap)
        val updatedObj = JsonObject(baseMap)
        if (matchIdx >= 0) existing[matchIdx] = updatedObj else existing.add(updatedObj)
        return saveSettingValue("Notifications", JsonArray(existing).toString())
    }

    /** 删除指定通知渠道配置（写入 `/api/v1/system/setting/Notifications`）。 */
    suspend fun deleteNotificationChannel(name: String): Boolean {
        val remaining = fetchSettingValue("Notifications").asArr()?.mapNotNull { it.asObj() }
            ?.filterNot { it.str("name") == name } ?: return false
        return saveSettingValue("Notifications", JsonArray(remaining).toString())
    }

    // ==================== 渠道授权（`/api/v1/authorization` 5 分钟绑定码 + 审批/解绑） ====================

    /** 读取当前后端成员列表，尾斜杠避免被禁止跟随的 307 重定向。 */
    private suspend fun channelAuthorizationMembers(expectedSession: SessionState.Authenticated? = null): List<JsonObject> {
        val resp = authedRequest(listOf("authorization"), trailingSlash = true, expectedSession = expectedSession).getOrThrow()
        check(resp.status in 200..299) { "加载渠道授权失败（HTTP ${resp.status}）" }
        return extractObject(resp.body)?.get("members").asArr().orEmpty().mapNotNull { it.asObj() }
    }

    /** 展示真实成员身份和全部审批状态，不把停用或拒绝记录显示为已授权。 */
    suspend fun fetchChannelAuthorizations(): List<ChannelAuthRecordDto> = channelAuthorizationMembers().map { obj ->
        ChannelAuthRecordDto(
            id = obj.str("id").orEmpty(),
            channel = obj.str("channel").orEmpty(),
            channelUserId = obj.str("sender_id").orEmpty(),
            channelUsername = obj.str("display_name").orEmpty(),
            boundUsername = obj.str("linked_username").orEmpty(),
            status = obj.str("status").orEmpty(),
            createdAt = obj.str("created_at").orEmpty(),
        )
    }

    /** 从 `/authorization/binding` 读取关联码及绝对到期时间，不调用直接授权成员接口。 */
    suspend fun generateChannelBindingCode(): Result<ChannelBindingCodeDto> = runCatching {
        val resp = authedRequest(listOf("authorization", "binding"), method = "POST", body = "{}").getOrThrow()
        val data = extractObject(resp.body)
        val code = data?.str("code").orEmpty()
        check(resp.status in 200..299 && code.isNotBlank()) { "生成关联码失败（HTTP ${resp.status}）" }
        val now = System.currentTimeMillis()
        val expires = data?.dbl("expires_at") ?: error("关联码缺少到期时间")
        ChannelBindingCodeDto(
            code = code,
            expiresInSeconds = ((expires * 1000 - now) / 1000).toInt().coerceAtLeast(0),
            commandHint = "/bind $code",
            createdAtEpochMs = now,
        )
    }

    /** 保留成员角色和能力集合，仅修改管理员要求的状态。 */
    private suspend fun updateChannelAuthorizationStatus(id: String, status: String): Pair<Boolean, String> {
        val auth = _session.value as? SessionState.Authenticated ?: return false to "未登录"
        return runCatching {
            val member = channelAuthorizationMembers(auth).firstOrNull { it.str("id") == id }
                ?: return false to "渠道成员不存在，请刷新列表"
            val body = buildJsonObject {
                put("status", status)
                put("role", member["role"] ?: error("成员缺少角色"))
                put("scopes", member["scopes"] ?: error("成员缺少能力集合"))
            }.toString()
            val resp = authedRequest(listOf("authorization", id), method = "PUT", body = body, expectedSession = auth).getOrThrow()
            val root = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
            val ok = resp.status in 200..299 && root?.bool("success") == true
            ok to (root?.str("message")?.takeIf { it.isNotBlank() } ?: if (ok) "渠道授权已更新" else "更新失败（HTTP ${resp.status}）")
        }.getOrElse { false to (it.message ?: "更新渠道授权失败") }
    }

    /** 通过成员状态更新接口批准申请，并保留既有角色和能力。 */
    suspend fun approveChannelAuthorization(id: String): Pair<Boolean, String> =
        updateChannelAuthorizationStatus(id, "approved")

    /** 后端保留不可变成员身份；撤销对应停用而不是删除资源。 */
    suspend fun deleteChannelAuthorization(id: String): Pair<Boolean, String> =
        updateChannelAuthorizationStatus(id, "disabled")

    suspend fun fetchSearchSources(): Set<String> {
        val el = fetchSettingValue("SEARCH_SOURCE") ?: return setOf("themoviedb")
        return when (el) {
            is JsonPrimitive -> el.content.split(",").map { it.trim().lowercase() }.filter { it.isNotBlank() && it != "null" }.toSet()
            is JsonArray -> el.mapNotNull { it.asPrim()?.content?.trim()?.lowercase()?.takeIf { s -> s.isNotBlank() && s != "null" } }.toSet()
            else -> setOf("themoviedb")
        }
    }

    suspend fun fetchSubscribeSearchSettings(): SubscribeSearchSettingsDto {
        val rss = fetchSettingValue("RssSites").asArr()?.mapNotNull { it.asPrim()?.intOrNull } ?: emptyList()
        val idx = fetchSettingValue("IndexerSites").asArr()?.mapNotNull { it.asPrim()?.intOrNull } ?: emptyList()
        val mode = fetchSettingValue("SUBSCRIBE_MODE").asPrim()?.content?.takeIf { it != "null" } ?: "spider"
        val groups = fetchSettingValue("UserFilterRuleGroups").asArr()?.mapNotNull { el ->
            val o = el.asObj() ?: return@mapNotNull null
            FilterRuleGroupDto(o.str("name") ?: return@mapNotNull null, o.str("rule_string") ?: "")
        } ?: emptyList()
        return SubscribeSearchSettingsDto(rss, idx, mode, groups)
    }

    suspend fun fetchCustomWordList(settingKey: String): List<String> {
        val arr = fetchSettingValue(settingKey).asArr() ?: return emptyList()
        return arr.mapNotNull { it.asPrim()?.content?.takeIf { s -> s != "null" } }
    }

    // ==================== 工作流 / 插件 / 消息 / Agent ====================

    suspend fun fetchWorkflows(): List<WorkflowItemDto> {
        val resp = authedRequest(listOf("workflow"), trailingSlash = true).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val actions = obj["actions"].asArr()?.mapIndexedNotNull { idx, a ->
                val ao = a.asObj() ?: return@mapIndexedNotNull null
                val pos = ao["position"].asObj()
                WorkflowActionDto(
                    id = ao.str("id") ?: "act-$idx",
                    type = ao.str("type") ?: "Action",
                    name = ao.str("name") ?: "动作节点",
                    description = ao.str("description") ?: "",
                    x = pos?.dbl("x")?.toFloat() ?: (idx * 240f + 40f),
                    y = pos?.dbl("y")?.toFloat() ?: (idx * 120f + 60f),
                    paramCount = ao["data"].asObj()?.size ?: 0,
                )
            } ?: emptyList()
            val flows = obj["flows"].asArr()?.mapNotNull { f ->
                val fo = f.asObj() ?: return@mapNotNull null
                WorkflowFlowEdgeDto(
                    source = fo.str("source") ?: return@mapNotNull null,
                    target = fo.str("target") ?: return@mapNotNull null,
                )
            } ?: emptyList()
            WorkflowItemDto(
                id = obj.int("id") ?: 0,
                name = obj.str("name") ?: return@mapNotNull null,
                description = obj.str("description") ?: "",
                timer = obj.str("timer") ?: "",
                state = obj.str("state") ?: "P",
                runCount = obj.int("run_count") ?: 0,
                actions = actions,
                flows = flows,
            )
        }
    }

    suspend fun fetchWorkflowShares(page: Int = 1): List<WorkflowShareDto> {
        val resp = authedRequest(listOf("workflow", "shares"), query = listOf("page" to page.toString(), "count" to "20")).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            WorkflowShareDto(
                id = obj.int("id") ?: 0,
                name = obj.str("name") ?: obj.str("share_title") ?: return@mapNotNull null,
                description = obj.str("description") ?: "",
                shareTitle = obj.str("share_title") ?: obj.str("name") ?: "",
                shareComment = obj.str("share_comment") ?: "",
                shareUser = obj.str("share_user") ?: "",
                count = obj.int("count") ?: 0,
                date = obj.str("date") ?: "",
                rawJson = obj.toString(),
            )
        }
    }

    /** 立即执行指定工作流（`POST /api/v1/workflow/{id}/run`）。 */
    suspend fun runWorkflow(workflowId: Int): Pair<Boolean, String> {
        val resp = authedRequest(listOf("workflow", workflowId.toString(), "run"), method = "POST").getOrNull()
            ?: return false to "请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "工作流已触发执行" else "触发失败（HTTP ${resp.status}）")
    }

    /** 启用指定工作流调度（`POST /api/v1/workflow/{id}/start`）。 */
    suspend fun startWorkflow(workflowId: Int): Pair<Boolean, String> {
        val resp = authedRequest(listOf("workflow", workflowId.toString(), "start"), method = "POST").getOrNull()
            ?: return false to "请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "工作流已启用" else "启用失败（HTTP ${resp.status}）")
    }

    /** 暂停指定工作流调度（`POST /api/v1/workflow/{id}/pause`）。 */
    suspend fun pauseWorkflow(workflowId: Int): Pair<Boolean, String> {
        val resp = authedRequest(listOf("workflow", workflowId.toString(), "pause"), method = "POST").getOrNull()
            ?: return false to "请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "工作流已暂停" else "暂停失败（HTTP ${resp.status}）")
    }

    /** 删除指定工作流（`DELETE /api/v1/workflow/{id}`）。 */
    suspend fun deleteWorkflow(workflowId: Int): Pair<Boolean, String> {
        val resp = authedRequest(listOf("workflow", workflowId.toString()), method = "DELETE").getOrNull()
            ?: return false to "删除请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "工作流已删除" else "删除失败（HTTP ${resp.status}）")
    }

    /** 复用社区分享工作流（`POST /api/v1/workflow/fork`）。 */
    suspend fun forkWorkflowShare(share: WorkflowShareDto): Pair<Boolean, String> {
        val bodyJson = share.rawJson.takeIf { it.isNotBlank() } ?: JsonObject(
            mapOf(
                "id" to JsonPrimitive(share.id),
                "name" to JsonPrimitive(share.name),
                "description" to JsonPrimitive(share.description),
                "share_title" to JsonPrimitive(share.shareTitle),
                "share_comment" to JsonPrimitive(share.shareComment),
                "share_user" to JsonPrimitive(share.shareUser),
            ),
        ).toString()
        val resp = authedRequest(
            segments = listOf("workflow", "fork"),
            method = "POST",
            body = bodyJson,
        ).getOrNull() ?: return false to "网络请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "已复用工作流「${share.shareTitle.ifBlank { share.name }}」" else "复用失败（HTTP ${resp.status}）")
    }

    suspend fun fetchPlugins(installedOnly: Boolean, forceRefresh: Boolean = false): List<PluginItemDto> =
        fetchPluginsOrNull(installedOnly = installedOnly, forceRefresh = forceRefresh).orEmpty()

    /** 查询已安装或市场插件列表；网络失败或非 2xx 时返回 `null`，避免把失败误当作空列表覆盖更新标记。 */
    suspend fun fetchPluginsOrNull(installedOnly: Boolean, forceRefresh: Boolean = false): List<PluginItemDto>? {
        if (!forceRefresh) {
            val cached = if (installedOnly) cachedInstalledPlugins else cachedMarketPlugins
            if (!cached.isNullOrEmpty()) return cached
        }
        val state = if (installedOnly) "installed" else "market"
        val (resp, remotesResp, statsAndRatings) = coroutineScope {
            val listDeferred = async {
                authedRequest(
                    segments = listOf("plugin"),
                    query = listOf("state" to state),
                    trailingSlash = true,
                ).getOrNull()
            }
            val remotesDeferred = async {
                if (installedOnly) {
                    runCatching {
                        authedRequest(
                            segments = listOf("plugin", "remotes"),
                            query = listOf("token" to "moviepilot"),
                        ).getOrNull()
                    }.getOrNull()
                } else {
                    null
                }
            }
            val statsDeferred = async {
                if (!installedOnly) {
                    runCatching {
                        authedRequest(segments = listOf("plugin", "statistic")).getOrNull()
                    }.getOrNull()
                } else {
                    null
                }
            }
            val ratingsDeferred = async {
                if (!installedOnly) {
                    runCatching {
                        authedRequest(segments = listOf("plugin", "rating")).getOrNull()
                    }.getOrNull()
                } else {
                    null
                }
            }
            Triple(listDeferred.await(), remotesDeferred.await(), statsDeferred.await() to ratingsDeferred.await())
        }
        if (resp == null || resp.status !in 200..299) {
            return null
        }
        val statsResp = statsAndRatings.first
        val ratingsResp = statsAndRatings.second
        val remoteVueIds = if (remotesResp != null) {
            extractArray(remotesResp.body).flatMap { rem ->
                val remObj = rem.asObj() ?: return@flatMap emptyList()
                listOfNotNull(
                    remObj.str("id")?.lowercase(),
                    remObj.str("source_plugin_id")?.lowercase(),
                )
            }.toSet()
        } else {
            emptySet()
        }
        val statsMap: Map<String, Int> = if (statsResp != null && statsResp.status in 200..299) {
            extractObject(statsResp.body)?.entries?.mapNotNull { (k, v) ->
                val cnt = v.asPrim()?.intOrNull ?: return@mapNotNull null
                k.lowercase() to cnt
            }?.toMap().orEmpty()
        } else {
            emptyMap()
        }
        val ratingsMap: Map<String, Double> = if (ratingsResp != null && ratingsResp.status in 200..299) {
            extractObject(ratingsResp.body)?.entries?.mapNotNull { (k, v) ->
                val avg = v.asObj()?.dbl("average_rating") ?: return@mapNotNull null
                k.lowercase() to avg
            }?.toMap().orEmpty()
        } else {
            emptyMap()
        }
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val id = obj.str("id") ?: return@mapNotNull null
            val rawSourceId = obj.str("source_plugin_id").orEmpty()
            val sourceId = rawSourceId.takeIf { it.isNotBlank() }?.lowercase()
            val rawRenderMode = obj.str("render_mode")
            val resolvedRenderMode = if (
                rawRenderMode.equals("vue", ignoreCase = true) ||
                id.lowercase() in remoteVueIds ||
                (sourceId != null && sourceId in remoteVueIds)
            ) {
                "vue"
            } else {
                rawRenderMode ?: "vuetify"
            }
            val labelRaw = obj.str("plugin_label").orEmpty()
            val labels = labelRaw.split(",", "，", " ").map { it.trim() }.filter { it.isNotBlank() }
            val rawDownloads = obj.int("install_count") ?: 0
            val mergedDownloads = maxOf(
                rawDownloads,
                statsMap[id.lowercase()] ?: 0,
                sourceId?.let { statsMap[it] } ?: 0,
            )
            PluginItemDto(
                id = id,
                name = obj.str("plugin_name") ?: id,
                desc = obj.str("plugin_desc") ?: "",
                version = obj.str("plugin_version") ?: "1.0.0",
                author = obj.str("plugin_author") ?: "",
                icon = resolvePluginIconUrl(obj.str("plugin_icon")),
                labels = labels,
                installed = obj.bool("installed") ?: installedOnly,
                state = obj.bool("state") ?: false,
                hasPage = obj.bool("has_page") ?: false,
                hasUpdate = obj.bool("has_update") ?: false,
                renderMode = resolvedRenderMode,
                repoUrl = obj.str("repo_url").orEmpty(),
                sourcePluginId = rawSourceId,
                installCount = mergedDownloads,
                addTime = obj.int("add_time") ?: 0,
                averageRating = obj.dbl("average_rating")
                    ?: ratingsMap[id.lowercase()]
                    ?: sourceId?.let { ratingsMap[it] }
                    ?: 0.0,
            )
        }.distinctBy { it.id }.also { parsed ->
            if (installedOnly) {
                cachedInstalledPlugins = parsed
            } else {
                cachedMarketPlugins = parsed
            }
        }
    }

    /** 从市场安装或更新插件（`GET /api/v1/plugin/install/{plugin_id}?repo_url=...&force=...`）。 */
    suspend fun installPlugin(pluginId: String, repoUrl: String = "", force: Boolean = false): Pair<Boolean, String> {
        val q = buildList {
            if (repoUrl.isNotBlank()) add("repo_url" to repoUrl)
            add("force" to force.toString())
        }
        val resp = authedRequest(listOf("plugin", "install", pluginId), method = "GET", query = q).getOrNull()
            ?: return false to "安装请求失败，请检查网络连接"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        if (ok) {
            cachedInstalledPlugins = cachedInstalledPlugins?.let {
                PluginUpdateReconciler.markPluginUpdated(it, pluginId)
            }
            cachedMarketPlugins = cachedMarketPlugins?.let {
                PluginUpdateReconciler.markPluginUpdated(it, pluginId)
            }
        }
        return ok to (obj?.str("message") ?: if (ok) (if (force) "插件更新成功" else "插件安装成功") else "安装失败（HTTP ${resp.status}）")
    }

    /** 卸载指定插件（`DELETE /api/v1/plugin/{plugin_id}`）。 */
    suspend fun uninstallPlugin(pluginId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("plugin", pluginId), method = "DELETE").getOrNull()
            ?: return false to "卸载请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        if (ok) {
            cachedInstalledPlugins = null
            cachedMarketPlugins = null
        }
        return ok to (obj?.str("message") ?: if (ok) "插件已卸载" else "卸载失败（HTTP ${resp.status}）")
    }

    /** 重置指定插件配置与运行数据（`GET /api/v1/plugin/reset/{plugin_id}`）。 */
    suspend fun resetPlugin(pluginId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("plugin", "reset", pluginId), method = "GET").getOrNull()
            ?: return false to "重置请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        if (ok) {
            cachedInstalledPlugins = null
        }
        return ok to (obj?.str("message") ?: if (ok) "插件已重置" else "重置失败（HTTP ${resp.status}）")
    }

    /** 重新加载指定插件运行时（`POST /api/v1/plugin/reload/{plugin_id}`）。 */
    suspend fun reloadPlugin(pluginId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("plugin", "reload", pluginId), method = "POST", body = "{}").getOrNull()
            ?: return false to "重新加载请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        if (ok) {
            cachedInstalledPlugins = null
        }
        return ok to (obj?.str("message")?.takeIf { it.isNotBlank() } ?: if (ok) "插件已重新加载" else "重新加载失败（HTTP ${resp.status}）")
    }

    /** 读取插件日志快照；用 `length=-1` 避免等待 SSE 结束，本地截取倒序文本中的最新行。 */
    suspend fun fetchPluginLogs(pluginId: String, length: Int = 200): List<String> {
        val cleanId = pluginId.trim().lowercase()
        if (cleanId.isEmpty() || cleanId.contains("..") || cleanId.contains('/')) return emptyList()
        val resp = authedRequest(
            segments = listOf("system", "logging"),
            query = listOf("length" to "-1", "logfile" to "plugins/$cleanId.log"),
        ).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        val body = resp.body.trim()
        if (body.isEmpty()) return emptyList()
        val unwrapped = runCatching {
            val el = json.parseToJsonElement(body)
            el.asObj()?.str("data") ?: el.asPrim()?.content
        }.getOrNull() ?: body
        return unwrapped.lineSequence().map { it.trimEnd() }.filter { it.isNotBlank() }
            .take(length.coerceIn(20, 500)).toList()
    }

    /** 拉取插件通过 `ChainEventType.RecommendSource` 动态注册的额外推荐榜单（`GET /api/v1/recommend/source`）。 */
    suspend fun fetchRecommendSources(): List<RecommendSourceDto> {
        val resp = authedRequest(listOf("recommend", "source")).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        val seen = HashSet<String>()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val name = obj.str("name")?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val rawApiPath = obj.str("api_path")?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val safePath = sanitizeRelativeRecommendApiPath(rawApiPath) ?: return@mapNotNull null
            if (!seen.add(safePath)) return@mapNotNull null
            RecommendSourceDto(
                name = name,
                apiPath = safePath,
                type = obj.str("type")?.trim().orEmpty(),
            )
        }
    }

    /**
     * 按受控相对 `api_path` 拉取插件推荐榜单媒体列表：
     * 严禁访问外部域名、协议相对路径或 `..` 穿越段；仅允许同源 `/api/v1/` 子路径。
     */
    suspend fun fetchRecommendByApiPath(apiPath: String, page: Int = 1): List<MediaCardItem> {
        val parsed = parseSafeRelativeApiPath(apiPath, page = page) ?: return emptyList()
        return fetchMediaList(parsed.first, parsed.second)
    }

    /** 从海报卡片长按菜单一键快捷添加订阅（`POST /api/v1/subscribe/`）。 */
    suspend fun quickSubscribeMediaCard(item: MediaCardItem): Pair<Boolean, String> {
        val identity = normalizeCanonicalMediaIdentity(
            source = item.source,
            mediaId = item.mediaId,
            tmdbId = item.tmdbId,
            doubanId = item.doubanId,
            bangumiId = item.bangumiId,
            imdbId = item.imdbId,
            tvdbId = item.tvdbId,
        )
        val canonicalType = canonicalMediaType(item.type)
        val sub = SubscribeItemDto(
            name = item.title,
            year = item.year,
            type = canonicalType,
            season = if (isTvType(canonicalType)) (item.season ?: 1) else null,
            mediaSource = identity?.first ?: item.source.ifBlank { "themoviedb" },
            mediaId = identity?.second ?: item.mediaId.orEmpty(),
        )
        return createOrUpdateSubscriptionWithMessage(sub, isUpdate = false)
    }

    private fun sanitizeRelativeRecommendApiPath(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed.length > 4096) return null
        if (trimmed.contains("://") || trimmed.startsWith("//") || trimmed.contains('\\') || trimmed.contains('#')) return null
        if (trimmed.any { it.isISOControl() }) return null
        val pathPart = trimmed.substringBefore('?').trimStart('/').let {
            if (it.startsWith("api/v1/")) it.removePrefix("api/v1/") else it
        }
        val queryPart = if ('?' in trimmed) trimmed.substringAfter('?') else ""
        if (pathPart.isEmpty() || pathPart.contains("//")) return null
        val segments = pathPart.split('/').filter { it.isNotEmpty() }
        if (segments.isEmpty() || segments.any { seg ->
                val dec = runCatching { java.net.URLDecoder.decode(seg, "UTF-8") }.getOrDefault(seg)
                dec == "." || dec == ".." || dec.contains('/') || dec.contains('\\')
            }
        ) {
            return null
        }
        return if (queryPart.isNotEmpty()) "${segments.joinToString("/")}?$queryPart" else segments.joinToString("/")
    }

    private fun parseSafeRelativeApiPath(
        apiPath: String,
        page: Int = 1,
    ): Pair<List<String>, List<Pair<String, String>>>? {
        val clean = sanitizeRelativeRecommendApiPath(apiPath) ?: return null
        val pathPart = clean.substringBefore('?')
        val queryPart = if ('?' in clean) clean.substringAfter('?') else ""
        val segments = pathPart.split('/').filter { it.isNotEmpty() }.map { seg ->
            runCatching { java.net.URLDecoder.decode(seg, "UTF-8") }.getOrDefault(seg)
        }
        if (segments.isEmpty() || segments.any { it == "." || it == ".." || it.contains('/') || it.contains('\\') }) {
            return null
        }
        val query = mutableListOf<Pair<String, String>>()
        if (queryPart.isNotBlank()) {
            queryPart.split('&').forEach { pair ->
                if (pair.isBlank()) return@forEach
                val kRaw = pair.substringBefore('=')
                val vRaw = if ('=' in pair) pair.substringAfter('=') else ""
                val k = runCatching { java.net.URLDecoder.decode(kRaw, "UTF-8") }.getOrDefault(kRaw)
                val v = runCatching { java.net.URLDecoder.decode(vRaw, "UTF-8") }.getOrDefault(vRaw)
                if (k.isNotBlank() && (page <= 1 || k != "page")) {
                    query += k to v
                }
            }
        }
        if (page > 1) {
            query += "page" to page.toString()
        }
        return segments to query
    }

    suspend fun fetchPluginFormJson(pluginId: String): String? {
        val resp = authedRequest(listOf("plugin", "form", pluginId)).getOrNull() ?: return null
        return if (resp.status in 200..299) resp.body else null
    }

    suspend fun fetchPluginPageJson(pluginId: String): String? {
        val resp = authedRequest(listOf("plugin", "page", pluginId)).getOrNull() ?: return null
        return if (resp.status in 200..299) resp.body else null
    }

    suspend fun savePluginFormModel(pluginId: String, fullModelJson: String): Boolean {
        val resp = authedRequest(
            segments = listOf("plugin", pluginId),
            method = "PUT",
            body = fullModelJson,
        ).getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun fetchMessages(page: Int = 1, size: Int = 30): List<SystemMessageDto> {
        val resp = authedRequest(
            listOf("message", "web"),
            query = listOf("page" to page.toString(), "size" to size.toString()),
        ).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val rawImg = obj.str("image")?.takeIf { it.isNotBlank() }
                ?: obj.str("poster")?.takeIf { it.isNotBlank() }
            SystemMessageDto(
                id = obj.str("id") ?: obj.str("reg_time") ?: "${obj.str("title")}_${obj.str("date")}",
                title = obj.str("title") ?: "系统消息",
                text = obj.str("text") ?: obj.str("content") ?: "",
                date = obj.str("reg_time") ?: obj.str("date") ?: "",
                category = obj.str("mtype") ?: "系统",
                image = resolveImageUrl(rawImg),
            )
        }
    }

    /**
     * 拉取服务端已发送的 MoviePilot 系统通知与插件通知（优先 V3 `GET /api/v1/message/notification`，
     * 若旧版后端返回 404 则回退 `GET /api/v1/message/web` 并仅保留 `action == 1` 发送记录）。
     * 网络异常或非 2xx 时返回 `null`，避免误改本地通知增量水位。
     */
    suspend fun fetchSentNotifications(count: Int = 20): List<SentNotificationItemDto>? {
        val primaryResp = authedRequest(
            listOf("message", "notification"),
            query = listOf("page" to "1", "count" to count.toString()),
        ).getOrNull()
        val effectiveResp = if (primaryResp != null && primaryResp.status == 404) {
            authedRequest(
                listOf("message", "web"),
                query = listOf("page" to "1", "size" to count.toString()),
            ).getOrNull()
        } else {
            primaryResp
        }
        if (effectiveResp == null || effectiveResp.status !in 200..299) return null
        val fromFallback = primaryResp?.status == 404
        return extractArray(effectiveResp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val action = obj.int("action")
            if (fromFallback && action != null && action != 1) return@mapNotNull null
            val numId = obj.lng("id")
            val regTime = obj.str("reg_time") ?: obj.str("date") ?: ""
            val title = obj.str("title") ?: ""
            val text = obj.str("text") ?: obj.str("content") ?: ""
            if (title.isBlank() && text.isBlank()) return@mapNotNull null
            val rawLink = obj.str("link")?.trim().orEmpty()
            val safeRoute = if (rawLink.startsWith("/") && !rawLink.startsWith("//") && !rawLink.contains('\\')) {
                rawLink
            } else {
                "/?shotcut=message"
            }
            val rawImg = obj.str("poster")?.takeIf { it.isNotBlank() }
                ?: obj.str("image")?.takeIf { it.isNotBlank() }
            val stableKey = "${numId ?: ""}|$regTime|${title.take(64)}|${text.take(64)}"
            SentNotificationItemDto(
                numericId = numId,
                stableKey = stableKey,
                title = title.ifBlank { "MoviePilot 通知" },
                text = text,
                category = obj.str("mtype")?.takeIf { it.isNotBlank() } ?: "系统",
                source = obj.str("source").orEmpty(),
                channel = obj.str("channel").orEmpty(),
                userid = obj.str("userid").orEmpty(),
                regTime = regTime,
                route = safeRoute,
                image = resolveImageUrl(rawImg),
            )
        }
    }

    /** 媒体服务器客户端列表（`GET /api/v1/mediaserver/clients`）。 */
    suspend fun fetchMediaServerClients(): List<MediaServerClientDto> {
        val resp = authedRequest(listOf("mediaserver", "clients")).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val name = obj.str("name") ?: return@mapNotNull null
            MediaServerClientDto(name = name, type = obj.str("type").orEmpty())
        }
    }

    /** 媒体服务器媒体库列表（`GET /api/v1/mediaserver/library?server=...`；未指定 server 时自动遍历已配置服务器聚合）。 */
    suspend fun fetchMediaServerLibraries(server: String? = null): List<MediaServerLibraryDto> {
        val targetServers = if (!server.isNullOrBlank()) {
            listOf(server to "")
        } else {
            val clients = fetchMediaServerClients().map { it.name to it.type }
            clients.ifEmpty {
                fetchMediaServers().filter { it.enabled }.map { it.name to it.type }
            }
        }
        val result = mutableListOf<MediaServerLibraryDto>()
        for ((srvName, srvType) in targetServers) {
            val resp = authedRequest(
                listOf("mediaserver", "library"),
                query = listOf("server" to srvName),
            ).getOrNull()
            extractArray(resp?.body).forEach { el ->
                val obj = el.asObj() ?: return@forEach
                val libId = obj.str("item_id") ?: obj.str("id") ?: return@forEach
                val rawImg = obj.str("image")
                    ?: obj["image_list"].asArr()?.firstOrNull()?.asPrim()?.content
                result += MediaServerLibraryDto(
                    id = libId,
                    name = obj.str("name") ?: "媒体库",
                    type = obj.str("type").orEmpty(),
                    itemCount = obj.int("item_count")?.takeIf { it >= 0 },
                    server = srvName,
                    serverType = obj.str("server_type")?.takeIf { it.isNotBlank() } ?: srvType,
                    imageUrl = resolveImageUrl(rawImg, maxWidth = 640),
                    link = obj.str("link"),
                )
            }
        }
        return result
    }

    /** 媒体服务器筛选候选项（`GET /api/v1/mediaserver/filters`）。 */
    suspend fun fetchMediaServerFilters(server: String, libraryId: String? = null): MediaServerFilterOptionsDto {
        val q = buildList {
            if (server.isNotBlank()) add("server" to server)
            if (!libraryId.isNullOrBlank()) add("library_id" to libraryId)
        }
        val resp = authedRequest(listOf("mediaserver", "filters"), query = q).getOrNull()
        val obj = extractObject(resp?.body) ?: return MediaServerFilterOptionsDto()
        val genres = obj["genres"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" } }.orEmpty()
        val years = obj["years"].asArr()?.mapNotNull { it.asPrim()?.intOrNull }.orEmpty().sortedDescending()
        return MediaServerFilterOptionsDto(genres = genres, years = years)
    }

    /** 媒体服务器分页浏览（`GET /api/v1/mediaserver/browse`）。 */
    suspend fun fetchMediaServerBrowse(
        server: String,
        libraryId: String? = null,
        sortBy: String = "date_created",
        sortOrder: String = "desc",
        genre: String = "",
        year: Int? = null,
        playedFilter: String = "all",
        keyword: String = "",
        startIndex: Int = 0,
        limit: Int = 30,
        itemType: String? = null,
    ): MediaServerBrowsePageDto {
        val q = buildList {
            if (server.isNotBlank()) add("server" to server)
            add("sort_by" to sortBy)
            add("sort_order" to sortOrder)
            add("start_index" to startIndex.toString())
            add("limit" to limit.toString())
            if (!libraryId.isNullOrBlank()) add("library_id" to libraryId)
            if (!itemType.isNullOrBlank()) add("item_type" to itemType)
            if (genre.isNotBlank()) add("genre" to genre)
            if (year != null) add("year" to year.toString())
            if (playedFilter != "all") add("played_filter" to playedFilter)
            if (keyword.isNotBlank()) add("keyword" to keyword)
        }
        val resp = authedRequest(listOf("mediaserver", "browse"), query = q).getOrNull()
        val root = extractObject(resp?.body) ?: return MediaServerBrowsePageDto()
        val rawItems = root["items"].asArr() ?: extractArray(resp?.body)
        val total = root.int("total_count") ?: root.int("total") ?: rawItems.size
        val hasMore = root.bool("has_more") ?: (startIndex + rawItems.size < total)
        val items = rawItems.mapNotNull { el -> parseMediaServerBrowseItem(el, defaultServer = server) }
        return MediaServerBrowsePageDto(items = items, totalCount = total, hasMore = hasMore)
    }

    private fun parseMediaServerBrowseItem(el: JsonElement, defaultServer: String = ""): MediaServerBrowseItemDto? {
        val obj = el.asObj() ?: return null
        val itemId = obj.str("item_id") ?: obj.str("id") ?: return null
        val useCookies = obj.bool("use_cookies") == true
        val posterUrl = resolveImageUrl(obj.str("poster") ?: obj.str("poster_path"), maxWidth = 480, useCookies = useCookies)
        val thumbUrl = resolveImageUrl(obj.str("thumb"), maxWidth = 780, useCookies = useCookies)
        val backdropUrl = resolveImageUrl(obj.str("backdrop") ?: obj.str("backdrop_path"), maxWidth = 1080, useCookies = useCookies)
        val fallbackImg = resolveImageUrl(obj.str("image"), maxWidth = 480, useCookies = useCookies)
        return MediaServerBrowseItemDto(
            itemId = itemId,
            title = obj.str("title") ?: obj.str("name") ?: "未命名条目",
            originalTitle = obj.str("original_title").orEmpty(),
            subtitle = obj.str("subtitle") ?: obj.str("artist") ?: obj.str("album").orEmpty(),
            overview = obj.str("overview").orEmpty(),
            type = obj.str("item_type") ?: obj.str("type").orEmpty(),
            mediaType = obj.str("media_type").orEmpty(),
            year = obj.str("year").orEmpty(),
            premiereDate = obj.str("premiere_date").orEmpty(),
            imageUrl = posterUrl ?: thumbUrl ?: fallbackImg ?: backdropUrl,
            poster = posterUrl ?: fallbackImg,
            backdrop = backdropUrl,
            thumb = thumbUrl,
            server = obj.str("server") ?: defaultServer,
            serverType = obj.str("server_type").orEmpty(),
            durationMs = obj.lng("duration_ms"),
            seriesId = obj.str("series_id"),
            seriesName = obj.str("series_name").orEmpty(),
            seasonId = obj.str("season_id"),
            seasonNumber = obj.int("season_number"),
            episodeNumber = obj.int("episode_number"),
            childCount = obj.int("child_count"),
            played = obj.bool("is_played") ?: obj.bool("played") ?: false,
            playedPercentage = obj.dbl("played_percentage") ?: obj.dbl("percent") ?: 0.0,
            resumePositionMs = obj.lng("resume_position_ms") ?: 0L,
            userRating = obj.dbl("rating") ?: obj.dbl("vote_average") ?: obj.dbl("community_rating") ?: 0.0,
            unplayedCount = obj.int("unplayed_count"),
            tmdbId = obj.int("tmdbid") ?: obj.int("tmdb_id") ?: obj.str("tmdb_id")?.toIntOrNull(),
            mediaId = obj.str("media_id"),
        )
    }

    /**
     * 拉取媒体服务器单个条目完整详情（`GET /api/v1/mediaserver/detail`），
     * 自动支持 Season/Episode 向父剧集继承外部编号，并通过 `/api/v1/media/{id}` 补全豆瓣/IMDb/透明片名 Logo。
     */
    suspend fun fetchMediaServerItemDetail(
        itemId: String,
        server: String? = null,
        enrichMetadata: Boolean = true,
    ): MediaServerItemDetailDto? {
        if (itemId.isBlank()) return null
        val q = buildList {
            add("itemid" to itemId)
            if (!server.isNullOrBlank()) add("server" to server)
        }
        val resp = authedRequest(listOf("mediaserver", "detail"), query = q).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val useCookies = obj.bool("use_cookies") == true

        val people = obj["people"].asArr().orEmpty().mapNotNull { pEl ->
            val pObj = pEl.asObj() ?: return@mapNotNull null
            val pName = pObj.str("name") ?: return@mapNotNull null
            MediaServerPersonDto(
                id = pObj.str("id").orEmpty(),
                name = pName,
                role = pObj.str("role").orEmpty(),
                type = pObj.str("type").orEmpty(),
                image = resolveImageUrl(pObj.str("image"), maxWidth = 320, useCookies = useCookies),
            )
        }

        val mediaSources = obj["media_sources"].asArr().orEmpty().mapNotNull { srcEl ->
            val srcObj = srcEl.asObj() ?: return@mapNotNull null
            val streams = srcObj["streams"].asArr().orEmpty().mapNotNull { stEl ->
                val stObj = stEl.asObj() ?: return@mapNotNull null
                val rawFrameRate = stObj.str("frame_rate")
                    ?: stObj.str("average_frame_rate")
                    ?: stObj.str("real_frame_rate")
                    ?: stObj.dbl("frame_rate")?.let { if (it > 0.0) it.toString() else null }
                val rawLevel = stObj.str("level")
                    ?: stObj.dbl("level")?.let { if (it > 0.0) it.toString() else null }
                MediaServerStreamTrackDto(
                    index = stObj.int("index"),
                    type = stObj.str("type")?.lowercase() ?: "unknown",
                    codec = stObj.str("codec")?.takeIf { it.isNotBlank() },
                    language = stObj.str("language")?.takeIf { it.isNotBlank() },
                    title = stObj.str("title")?.takeIf { it.isNotBlank() },
                    displayTitle = stObj.str("display_title")?.takeIf { it.isNotBlank() },
                    isDefault = stObj.bool("is_default") ?: false,
                    isForced = stObj.bool("is_forced") ?: false,
                    isExternal = stObj.bool("is_external") ?: false,
                    subtitleId = stObj.str("subtitle_id")?.takeIf { it.isNotBlank() },
                    channels = stObj.int("channels"),
                    channelLayout = stObj.str("channel_layout")?.takeIf { it.isNotBlank() },
                    bitrate = stObj.lng("bitrate"),
                    width = stObj.int("width"),
                    height = stObj.int("height"),
                    videoRange = stObj.str("video_range")?.takeIf { it.isNotBlank() },
                    frameRate = rawFrameRate?.takeIf { it.isNotBlank() && it != "0" && it != "0.0" },
                    profile = stObj.str("profile")?.takeIf { it.isNotBlank() },
                    level = rawLevel?.takeIf { it.isNotBlank() && it != "0" && it != "0.0" },
                    aspectRatio = stObj.str("aspect_ratio")?.takeIf { it.isNotBlank() },
                    isInterlaced = stObj.bool("is_interlaced"),
                    colorPrimaries = stObj.str("color_primaries")?.takeIf { it.isNotBlank() },
                    colorSpace = stObj.str("color_space")?.takeIf { it.isNotBlank() },
                    bitDepth = stObj.int("bit_depth"),
                    sampleRate = stObj.int("sample_rate"),
                )
            }
            MediaServerSourceDto(
                id = srcObj.str("id").orEmpty(),
                name = srcObj.str("name").orEmpty(),
                container = srcObj.str("container").orEmpty(),
                size = srcObj.lng("size"),
                bitrate = srcObj.lng("bitrate"),
                durationMs = srcObj.lng("duration_ms"),
                streams = streams,
            )
        }

        val resolvedServer = obj.str("server") ?: server.orEmpty()
        var resolvedServerType = obj.str("server_type").orEmpty()
        if (resolvedServer.isNotBlank() && resolvedServerType.isBlank()) {
            resolvedServerType = fetchMediaServers().firstOrNull { it.name.equals(resolvedServer, ignoreCase = true) }?.type.orEmpty()
        }

        val serverRatings = obj["ratings"].asArr().orEmpty().mapNotNull { rEl ->
            val rObj = rEl.asObj() ?: return@mapNotNull null
            val src = normalizeRatingSourceKey(rObj.str("source")) ?: return@mapNotNull null
            val value = rObj.dbl("value") ?: 0.0
            if (value <= 0.0) return@mapNotNull null
            val scale = rObj.str("scale")?.lowercase() ?: "ten"
            val label = if (scale == "percent") {
                "${value.roundToInt().coerceIn(1, 100)}%"
            } else {
                String.format(java.util.Locale.US, "%.1f", value.coerceAtMost(10.0))
            }
            MediaRatingBadgeDto(src, label)
        }

        var detail = MediaServerItemDetailDto(
            itemId = obj.str("item_id") ?: itemId,
            server = resolvedServer,
            serverType = resolvedServerType,
            itemType = obj.str("item_type") ?: "Movie",
            mediaType = obj.str("media_type").orEmpty(),
            title = obj.str("title") ?: obj.str("name").orEmpty(),
            originalTitle = obj.str("original_title").orEmpty(),
            subtitle = obj.str("subtitle").orEmpty(),
            tagline = obj.str("tagline").orEmpty(),
            overview = obj.str("overview").orEmpty(),
            year = obj.str("year").orEmpty(),
            premiereDate = obj.str("premiere_date").orEmpty(),
            officialRating = obj.str("official_rating").orEmpty(),
            rating = obj.dbl("rating") ?: 0.0,
            criticRating = obj.dbl("critic_rating") ?: 0.0,
            ratings = serverRatings,
            durationMs = obj.lng("duration_ms"),
            poster = resolveImageUrl(obj.str("poster") ?: obj.str("image"), maxWidth = 600, useCookies = useCookies),
            backdrop = resolveImageUrl(obj.str("backdrop") ?: obj.str("backdrop_path"), maxWidth = 1280, useCookies = useCookies),
            thumb = resolveImageUrl(obj.str("thumb"), maxWidth = 780, useCookies = useCookies),
            logoUrl = resolveImageUrl(obj.str("logo") ?: obj.str("logo_path"), maxWidth = 720, useCookies = useCookies),
            genres = obj["genres"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" } }.orEmpty(),
            studios = obj["studios"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s.isNotBlank() && s != "null" } }.orEmpty(),
            people = people,
            mediaSource = obj.str("media_source"),
            mediaId = obj.str("media_id"),
            imdbId = obj.str("imdb_id")?.takeIf { it.isNotBlank() },
            tmdbId = obj.str("tmdb_id")?.takeIf { it.isNotBlank() } ?: obj.int("tmdb_id")?.toString(),
            tvdbId = obj.str("tvdb_id")?.takeIf { it.isNotBlank() } ?: obj.int("tvdb_id")?.toString(),
            doubanId = obj.str("douban_id")?.takeIf { it.isNotBlank() },
            parentId = obj.str("parent_id"),
            seriesId = obj.str("series_id"),
            seriesName = obj.str("series_name").orEmpty(),
            seasonId = obj.str("season_id"),
            seasonName = obj.str("season_name").orEmpty(),
            seasonNumber = obj.int("season_number"),
            episodeNumber = obj.int("episode_number"),
            seasonCount = obj.int("season_count"),
            episodeCount = obj.int("episode_count"),
            childCount = obj.int("child_count"),
            played = obj.bool("played") ?: false,
            playedPercentage = obj.dbl("played_percentage") ?: 0.0,
            resumePositionMs = obj.lng("resume_position_ms") ?: 0L,
            mediaSources = mediaSources,
            playUrl = obj.str("play_url")?.takeIf { it.isNotBlank() },
            canPlay = obj.bool("can_play") ?: false,
        )

        if (!enrichMetadata) return detail

        // 1. Season / Episode 条目缺少外部元数据时，向所属父剧集继承 tmdb_id / douban_id / imdb_id / genres / people
        val isChildEpisodeOrSeason = detail.itemType.equals("Episode", ignoreCase = true) ||
            detail.itemType.equals("Season", ignoreCase = true)
        val parentSeriesId = detail.seriesId?.takeIf { it.isNotBlank() }
            ?: (if (detail.itemType.equals("Season", ignoreCase = true)) detail.parentId?.takeIf { it.isNotBlank() } else null)
        if (isChildEpisodeOrSeason && parentSeriesId != null && parentSeriesId != detail.itemId &&
            (detail.tmdbId.isNullOrBlank() || detail.doubanId.isNullOrBlank() || detail.imdbId.isNullOrBlank() || detail.people.isEmpty())
        ) {
            val parent = fetchMediaServerItemDetail(parentSeriesId, detail.server.ifBlank { server }, enrichMetadata = false)
            if (parent != null) {
                detail = detail.copy(
                    tmdbId = detail.tmdbId ?: parent.tmdbId,
                    imdbId = detail.imdbId ?: parent.imdbId,
                    tvdbId = detail.tvdbId ?: parent.tvdbId,
                    doubanId = detail.doubanId ?: parent.doubanId,
                    mediaSource = detail.mediaSource ?: parent.mediaSource,
                    mediaId = detail.mediaId ?: parent.mediaId,
                    genres = detail.genres.ifEmpty { parent.genres },
                    people = detail.people.ifEmpty { parent.people },
                    backdrop = detail.backdrop ?: parent.backdrop,
                    logoUrl = detail.logoUrl ?: parent.logoUrl,
                    year = detail.year.ifBlank { parent.year },
                )
            }
        }

        // 2. 通过 `/api/v1/media/{id}` 补全豆瓣 / IMDb / TVDB 外部编号与透明片名 Logo（如 Emby 仅存了 tmdb_id）
        val identity = normalizeCanonicalMediaIdentity(
            source = detail.mediaSource,
            mediaId = detail.mediaId,
            tmdbId = detail.tmdbId?.toIntOrNull(),
            doubanId = detail.doubanId,
            imdbId = detail.imdbId,
            tvdbId = detail.tvdbId,
        )
        if (identity != null && (detail.doubanId.isNullOrBlank() || detail.imdbId.isNullOrBlank() || detail.logoUrl.isNullOrBlank())) {
            val typeName = canonicalMediaType(detail.mediaType.ifBlank { detail.itemType })
            val mediaResp = authedRequest(
                segments = listOf("media", identity.second),
                query = listOf("media_source" to identity.first, "type_name" to typeName),
            ).getOrNull()
            if (mediaResp != null && mediaResp.status in 200..299) {
                val mObj = extractObject(mediaResp.body)
                if (mObj != null) {
                    val enrichedGenres = if (detail.genres.isEmpty()) {
                        parseMediaCard(mObj)?.genres.orEmpty()
                    } else {
                        detail.genres
                    }
                    detail = detail.copy(
                        tmdbId = detail.tmdbId ?: mObj.int("tmdb_id")?.toString() ?: mObj.str("tmdb_id")?.takeIf { it.isNotBlank() },
                        imdbId = detail.imdbId ?: mObj.str("imdb_id")?.takeIf { it.isNotBlank() } ?: mObj.str("imdbid")?.takeIf { it.isNotBlank() },
                        tvdbId = detail.tvdbId ?: mObj.int("tvdb_id")?.toString() ?: mObj.str("tvdb_id")?.takeIf { it.isNotBlank() },
                        doubanId = detail.doubanId ?: mObj.str("douban_id")?.takeIf { it.isNotBlank() } ?: mObj.str("doubanid")?.takeIf { it.isNotBlank() },
                        logoUrl = detail.logoUrl ?: resolveImageUrl(mObj.str("logo_path"), maxWidth = 720),
                        genres = enrichedGenres,
                        overview = detail.overview.ifBlank { mObj.str("overview").orEmpty() },
                    )
                }
            }
        }
        return detail
    }

    /** 查询媒体服务器电视剧全部季列表（`GET /api/v1/mediaserver/seasons`）。 */
    suspend fun fetchMediaServerSeasons(seriesId: String, server: String): List<MediaServerBrowseItemDto> {
        if (seriesId.isBlank() || server.isBlank()) return emptyList()
        val resp = authedRequest(
            segments = listOf("mediaserver", "seasons"),
            query = listOf("itemid" to seriesId, "server" to server),
        ).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { parseMediaServerBrowseItem(it, defaultServer = server) }
    }

    /** 查询媒体服务器指定季的全部单集详情卡片（`GET /api/v1/mediaserver/season-episodes`）。 */
    suspend fun fetchMediaServerSeasonEpisodes(
        seriesId: String,
        server: String,
        seasonId: String? = null,
        seasonNumber: Int? = null,
    ): List<MediaServerBrowseItemDto> {
        if (seriesId.isBlank() || server.isBlank()) return emptyList()
        val q = buildList {
            add("itemid" to seriesId)
            add("server" to server)
            if (!seasonId.isNullOrBlank()) add("season_id" to seasonId)
            if (seasonNumber != null) add("season" to seasonNumber.toString())
        }
        val resp = authedRequest(
            segments = listOf("mediaserver", "season-episodes"),
            query = q,
        ).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { parseMediaServerBrowseItem(it, defaultServer = server) }
    }

    /**
     * 拉取媒体服务器条目的「类似作品」列表：
     * 按 `/tmdb/similar` -> `/tmdb/recommend` -> `/douban/recommend` -> `/mediaserver/browse` 同风格回退顺序聚合。
     */
    suspend fun fetchSimilarMediaForServerItem(detail: MediaServerItemDetailDto): List<MediaCardItem> {
        val typeName = if (isTvType(detail.mediaType.ifBlank { detail.itemType })) "电视剧" else "电影"
        var candidates = emptyList<MediaCardItem>()

        val tmdbId = detail.tmdbId?.trim()?.takeIf { it.isNotBlank() && it != "0" }
            ?: (if (normalizeMediaSource(detail.mediaSource) == "themoviedb") detail.mediaId?.trim()?.takeIf { it.isNotBlank() } else null)
        val doubanId = detail.doubanId?.trim()?.takeIf { it.isNotBlank() && it != "0" }
            ?: (if (normalizeMediaSource(detail.mediaSource) == "douban") detail.mediaId?.trim()?.takeIf { it.isNotBlank() } else null)

        if (tmdbId != null) {
            candidates = fetchMediaList(
                listOf("tmdb", "similar", tmdbId, typeName),
                listOf("page" to "1", "count" to "20"),
            )
            if (candidates.isEmpty()) {
                candidates = fetchMediaList(
                    listOf("tmdb", "recommend", tmdbId, typeName),
                    listOf("page" to "1", "count" to "20"),
                )
            }
        }
        if (candidates.isEmpty() && doubanId != null) {
            candidates = fetchMediaList(
                listOf("douban", "recommend", doubanId, typeName),
                listOf("page" to "1", "count" to "20"),
            )
        }
        if (candidates.isEmpty() && detail.server.isNotBlank()) {
            val browsePage = fetchMediaServerBrowse(
                server = detail.server,
                genre = detail.genres.firstOrNull().orEmpty(),
                itemType = if (typeName == "电视剧") "Series" else "Movie",
                limit = 20,
            )
            candidates = browsePage.items
                .filter { it.itemId != detail.itemId && it.itemId != detail.seriesId }
                .map { cand ->
                    MediaCardItem(
                        title = cand.title,
                        year = cand.year,
                        type = typeName,
                        overview = cand.overview,
                        posterPath = cand.poster ?: cand.imageUrl,
                        backdropPath = cand.backdrop ?: cand.thumb,
                        voteAverage = cand.userRating,
                        source = if (cand.tmdbId != null) "themoviedb" else cand.server.ifBlank { detail.server },
                        tmdbId = cand.tmdbId,
                        mediaId = cand.mediaId ?: cand.tmdbId?.toString() ?: cand.itemId,
                        serverItemId = cand.itemId,
                        serverName = cand.server.ifBlank { detail.server },
                        serverType = cand.serverType.ifBlank { detail.serverType },
                        inLibrary = true,
                    )
                }
        }
        val selfTitle = detail.seriesName.ifBlank { detail.title }
        return candidates
            .filterNot { c ->
                (tmdbId != null && c.tmdbId?.toString() == tmdbId) ||
                    (doubanId != null && c.doubanId == doubanId) ||
                    (c.title == selfTitle && (detail.year.isBlank() || c.year == detail.year))
            }
            .distinctBy { it.resolvedId }
            .take(20)
    }

    private fun isStrmDirectPlayEnabled(): Boolean =
        runCatching {
            appContext.getSharedPreferences("mp_playback_prefs_v1", Context.MODE_PRIVATE)
                .getBoolean("strm_direct_play", true)
        }.getOrDefault(true)

    private fun isServerDirectPlayEnabled(): Boolean =
        runCatching {
            appContext.getSharedPreferences("mp_playback_prefs_v1", Context.MODE_PRIVATE)
                .getBoolean("server_direct_play", true)
        }.getOrDefault(true)

    private data class ResolvedPlaybackRoutes(
        val activeUrl: String,
        val activeRouteKind: String,
        val activeHeaders: Map<String, String>,
        val streamHeaders: Map<String, String>,
        val proxyFallbackUrl: String?,
        val fallbackRoutes: List<PlaybackRouteDto>,
        val candidates: List<PlaybackRouteDto>,
    )

    private suspend fun resolveManifestRoutes(
        obj: JsonObject,
        auth: SessionState.Authenticated,
        sameOriginUrl: String,
        parsedStrmUrl: String?,
        sameOriginHeaders: Map<String, String>,
        serverName: String,
    ): ResolvedPlaybackRoutes {
        val candidates = mutableListOf<PlaybackRouteDto>()
        obj["playback_routes"].asArr().orEmpty().forEach { el ->
            val ro = el.asObj() ?: return@forEach
            val kind = ro.str("kind")?.trim().orEmpty()
            val rawRouteUrl = ro.str("url")?.trim().orEmpty()
            if (kind.isEmpty() || rawRouteUrl.isEmpty()) return@forEach
            val resolvedUrl = if (kind == "mp_proxy") {
                resolveSameOriginUrl(auth.serverUrl, rawRouteUrl)
            } else {
                rawRouteUrl
            }
            if (kind == "mp_proxy" && !RustCoreBridge.containsUrl(auth.serverUrl, resolvedUrl)) return@forEach
            val hdrs = buildMap<String, String> {
                ro["headers"].asObj()?.let { ho ->
                    ho.keys.forEach { hk ->
                        val s = ho.str(hk)?.trim().orEmpty()
                        if (hk.isNotBlank() && s.isNotBlank()) put(hk, s)
                    }
                }
            }
            candidates += PlaybackRouteDto(
                kind = kind,
                url = resolvedUrl,
                probeUrl = ro.str("probe_url")?.takeIf { it.isNotBlank() },
                headers = hdrs,
                priority = ro.int("priority") ?: 100,
                requiresSameOriginAuth = ro.bool("requires_same_origin_auth") ?: (kind == "mp_proxy"),
            )
        }
        if (!parsedStrmUrl.isNullOrBlank() && candidates.none { it.kind == "strm_direct" }) {
            candidates += PlaybackRouteDto(
                kind = "strm_direct",
                url = parsedStrmUrl,
                priority = 10,
            )
        }
        if (candidates.none { it.kind == "mp_proxy" }) {
            candidates += PlaybackRouteDto(
                kind = "mp_proxy",
                url = sameOriginUrl,
                priority = 100,
                requiresSameOriginAuth = true,
            )
        }

        val plan = playbackRouteResolver.resolve(
            server = serverName,
            routes = candidates,
            preferStrmDirect = isStrmDirectPlayEnabled(),
            preferServerDirect = isServerDirectPlayEnabled(),
            allowSelfSignedTls = secretStore.allowSelfSignedTls,
        )
        if (plan != null) {
            val active = plan.active
            val isProxy = active.kind == "mp_proxy" || RustCoreBridge.containsUrl(auth.serverUrl, active.url)
            val activeHeaders = if (isProxy) sameOriginHeaders else active.headers
            val streamHeaders = if (isProxy) emptyMap() else active.headers
            val proxyFallback = plan.fallbacks.lastOrNull { it.kind == "mp_proxy" }?.url
                ?: sameOriginUrl.takeIf { active.url != it }
            return ResolvedPlaybackRoutes(
                activeUrl = active.url,
                activeRouteKind = active.kind,
                activeHeaders = activeHeaders,
                streamHeaders = streamHeaders,
                proxyFallbackUrl = proxyFallback,
                fallbackRoutes = plan.fallbacks,
                candidates = candidates,
            )
        }

        val useStrmDirect = parsedStrmUrl != null && isStrmDirectPlayEnabled()
        val activeUrl = if (useStrmDirect) parsedStrmUrl!! else sameOriginUrl
        val isSame = RustCoreBridge.containsUrl(auth.serverUrl, activeUrl)
        return ResolvedPlaybackRoutes(
            activeUrl = activeUrl,
            activeRouteKind = if (useStrmDirect) "strm_direct" else "mp_proxy",
            activeHeaders = if (isSame) sameOriginHeaders else emptyMap(),
            streamHeaders = emptyMap(),
            proxyFallbackUrl = if (useStrmDirect && activeUrl != sameOriginUrl) sameOriginUrl else null,
            fallbackRoutes = if (useStrmDirect && activeUrl != sameOriginUrl) {
                listOf(PlaybackRouteDto(kind = "mp_proxy", url = sameOriginUrl, priority = 100, requiresSameOriginAuth = true))
            } else {
                emptyList()
            },
            candidates = candidates,
        )
    }

    /** 拉取媒体服务器真实直放流与外挂字幕清单（`GET /api/v1/mediaserver/stream-info`）；优先直连可达路由，失败自动回退后台中转。 */
    suspend fun fetchVideoStreamInfo(
        itemId: String,
        server: String? = null,
        mediaSourceId: String? = null,
    ): MediaPlaybackManifestDto? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val q = buildList {
            add("itemid" to itemId)
            if (!server.isNullOrBlank()) add("server" to server)
            if (!mediaSourceId.isNullOrBlank()) add("media_source_id" to mediaSourceId)
        }
        val resp = authedRequest(
            segments = listOf("mediaserver", "stream-info"),
            query = q,
            extraHeaders = playbackProgressReporter.clientHeaders(),
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        playbackProgressReporter.flushPendingStops(this)
        val obj = extractObject(resp.body) ?: return null
        val rawUrl = obj.str("content_url")?.takeIf { it.isNotBlank() } ?: return null
        val sameOriginUrl = resolveSameOriginUrl(auth.serverUrl, rawUrl)
        val parsedStrmUrl = obj.str("strm_url")
            ?.takeIf { it.isNotBlank() }
            ?.let { RustCoreBridge.parseStrm(it)?.url }
        val sameOriginHeaders = buildPlaybackHeaders(sameOriginUrl)
        val resolvedServer = obj.str("server") ?: server.orEmpty()
        val resolvedRoutes = resolveManifestRoutes(
            obj = obj,
            auth = auth,
            sameOriginUrl = sameOriginUrl,
            parsedStrmUrl = parsedStrmUrl,
            sameOriginHeaders = sameOriginHeaders,
            serverName = resolvedServer,
        )
        val subs = obj["subtitles"].asArr().orEmpty().mapNotNull { el ->
            val so = el.asObj() ?: return@mapNotNull null
            val su = so.str("url")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            MediaStreamSubtitleDto(
                subtitleId = so.str("subtitle_id") ?: so.str("id").orEmpty(),
                title = so.str("title") ?: so.str("display_title") ?: so.str("language") ?: "外挂字幕",
                language = so.str("language").orEmpty(),
                url = resolveSameOriginUrl(auth.serverUrl, su),
            )
        }
        val lyricsUrl = obj.str("lyrics_url")?.takeIf { it.isNotBlank() }?.let { resolveSameOriginUrl(auth.serverUrl, it) }
        return MediaPlaybackManifestDto(
            itemId = obj.str("item_id") ?: itemId,
            server = resolvedServer,
            serverType = obj.str("server_type").orEmpty(),
            mediaSourceId = obj.str("media_source_id") ?: mediaSourceId,
            playSessionId = obj.str("play_session_id")?.takeIf { it.isNotBlank() },
            progressSyncMode = obj.str("progress_sync_mode")?.takeIf { it.isNotBlank() },
            mediaType = obj.str("media_type") ?: "video",
            title = obj.str("title").orEmpty(),
            contentUrl = resolvedRoutes.activeUrl,
            strmUrl = parsedStrmUrl,
            proxyFallbackUrl = resolvedRoutes.proxyFallbackUrl,
            originUrl = auth.serverUrl,
            subtitles = subs,
            lyricsUrl = lyricsUrl,
            durationMs = obj.lng("duration_ms") ?: ((obj.dbl("duration") ?: 0.0) * 1000.0).toLong(),
            resumePositionMs = obj.lng("position_ms") ?: obj.lng("resume_position_ms") ?: 0L,
            headers = resolvedRoutes.activeHeaders,
            sameOriginHeaders = sameOriginHeaders,
            streamHeaders = resolvedRoutes.streamHeaders,
            activeRouteKind = resolvedRoutes.activeRouteKind,
            fallbackRoutes = resolvedRoutes.fallbackRoutes,
            playbackRoutes = resolvedRoutes.candidates,
            danmakuEnabled = obj.bool("danmaku_enabled") ?: false,
            seriesName = obj.str("series_name")?.takeIf { it.isNotBlank() },
            seasonNumber = obj.lng("season_number")?.toInt(),
            episodeNumber = obj.lng("episode_number")?.toInt(),
            year = obj.lng("year")?.toInt(),
            tmdbId = obj.str("tmdb_id")?.takeIf { it.isNotBlank() },
            fileName = obj.str("file_name")?.takeIf { it.isNotBlank() },
            fileSize = obj.lng("file_size"),
        )
    }

    /** 拉取音乐曲目媒体服务器音频流与同步 LRC 歌词（`POST /api/v1/mediaserver/stream-info/music`）。 */
    suspend fun fetchMusicStreamInfo(
        title: String,
        artist: String? = null,
        album: String? = null,
    ): MediaPlaybackManifestDto? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val parts = mutableListOf("\"title\":\"${esc(title)}\"")
        if (!artist.isNullOrBlank()) parts += "\"artist\":\"${esc(artist)}\""
        if (!album.isNullOrBlank()) parts += "\"album\":\"${esc(album)}\""
        val resp = authedRequest(
            segments = listOf("mediaserver", "stream-info", "music"),
            method = "POST",
            body = "{${parts.joinToString(",")}}",
            extraHeaders = playbackProgressReporter.clientHeaders(),
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        playbackProgressReporter.flushPendingStops(this)
        val obj = extractObject(resp.body) ?: return null
        val rawUrl = obj.str("content_url")?.takeIf { it.isNotBlank() } ?: return null
        val sameOriginUrl = resolveSameOriginUrl(auth.serverUrl, rawUrl)
        val parsedStrmUrl = obj.str("strm_url")
            ?.takeIf { it.isNotBlank() }
            ?.let { RustCoreBridge.parseStrm(it)?.url }
        val sameOriginHeaders = buildPlaybackHeaders(sameOriginUrl)
        val resolvedServer = obj.str("server").orEmpty()
        val resolvedRoutes = resolveManifestRoutes(
            obj = obj,
            auth = auth,
            sameOriginUrl = sameOriginUrl,
            parsedStrmUrl = parsedStrmUrl,
            sameOriginHeaders = sameOriginHeaders,
            serverName = resolvedServer,
        )
        val lyricsUrl = obj.str("lyrics_url")?.takeIf { it.isNotBlank() }?.let { resolveSameOriginUrl(auth.serverUrl, it) }
        return MediaPlaybackManifestDto(
            itemId = obj.str("item_id").orEmpty(),
            server = resolvedServer,
            serverType = obj.str("server_type").orEmpty(),
            mediaSourceId = obj.str("media_source_id"),
            playSessionId = obj.str("play_session_id")?.takeIf { it.isNotBlank() },
            progressSyncMode = obj.str("progress_sync_mode")?.takeIf { it.isNotBlank() },
            mediaType = "audio",
            title = obj.str("title") ?: title,
            contentUrl = resolvedRoutes.activeUrl,
            strmUrl = parsedStrmUrl,
            proxyFallbackUrl = resolvedRoutes.proxyFallbackUrl,
            originUrl = auth.serverUrl,
            lyricsUrl = lyricsUrl,
            durationMs = obj.lng("duration_ms") ?: 0L,
            headers = resolvedRoutes.activeHeaders,
            sameOriginHeaders = sameOriginHeaders,
            streamHeaders = resolvedRoutes.streamHeaders,
            activeRouteKind = resolvedRoutes.activeRouteKind,
            fallbackRoutes = resolvedRoutes.fallbackRoutes,
            playbackRoutes = resolvedRoutes.candidates,
            danmakuEnabled = obj.bool("danmaku_enabled") ?: false,
            seriesName = obj.str("series_name")?.takeIf { it.isNotBlank() },
            seasonNumber = obj.lng("season_number")?.toInt(),
            episodeNumber = obj.lng("episode_number")?.toInt(),
            year = obj.lng("year")?.toInt(),
            tmdbId = obj.str("tmdb_id")?.takeIf { it.isNotBlank() },
            fileName = obj.str("file_name")?.takeIf { it.isNotBlank() },
            fileSize = obj.lng("file_size"),
        )
    }

    /** 下载同源 LRC 歌词或字幕文本（附带 Bearer 令牌与资源 Cookie）。 */
    suspend fun downloadSameOriginText(url: String): String? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        if (!RustCoreBridge.containsUrl(auth.serverUrl, url)) return null
        val resp = runCatching {
            transport.execute(url = url, method = "GET", token = auth.token)
        }.getOrNull() ?: return null
        return if (resp.status in 200..299 && resp.body.isNotBlank()) resp.body else null
    }

    /** 为本地或支持渐进流式的远端存储（SMB / OpenList / 阿里云盘 / 115 等）音视频文件签发短期 Range 流票据（`POST /api/v1/mediaserver/stream-ticket`），实现边加载边播放。 */
    suspend fun createStorageStreamTicket(
        storage: String,
        path: String,
        fileName: String,
        mediaType: String,
    ): String? {
        val cleanStorage = storage.trim().ifBlank { "local" }
        val cleanPath = path.trim()
        if (cleanPath.isBlank()) return null
        val resolvedName = fileName.trim().ifBlank { cleanPath.substringAfterLast('/') }
        val ext = resolvedName.substringAfterLast('.', "")
        val normalizedType = if (mediaType.equals("audio", ignoreCase = true)) "audio" else "video"
        val payload = """{"file":{"storage":"${esc(cleanStorage)}","type":"file","path":"${esc(cleanPath)}","name":"${esc(resolvedName)}","extension":"${esc(ext)}"},"media_type":"$normalizedType"}"""
        val resp = runCatching {
            authedRequest(listOf("mediaserver", "stream-ticket"), method = "POST", body = payload).getOrNull()
        }.getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        return obj.str("item_id")?.takeIf { it.isNotBlank() }
    }

    /** 兼容旧调用签名（本地存储流票据）。 */
    suspend fun createLocalStreamTicket(
        path: String,
        fileName: String,
        mediaType: String,
    ): String? = createStorageStreamTicket("local", path, fileName, mediaType)

    /** 下载本地或云盘存储文件至应用受管缓存目录供 ExoPlayer 无缝直放（云盘或旧版后端兼容回退）。 */
    suspend fun downloadStorageFileToCache(
        storage: String,
        path: String,
        destFile: java.io.File,
    ): java.io.File? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val url = RustCoreBridge.buildEndpointUrl(auth.serverUrl, listOf("storage", "download"))
        val fileName = path.substringAfterLast('/').ifBlank { destFile.name }
        val ext = fileName.substringAfterLast('.', "")
        val payload = """{"storage":"${esc(storage)}","type":"file","path":"${esc(path)}","name":"${esc(fileName)}","extension":"${esc(ext)}"}"""
        val ok = runCatching {
            transport.downloadToFile(url = url, method = "POST", token = auth.token, body = payload, destFile = destFile)
        }.getOrDefault(false)
        return if (ok) destFile else null
    }

    /**
     * 解析并准备存储音视频文件起播源：
     * - 所有非 `.strm` 音视频文件严格通过 `POST /api/v1/mediaserver/stream-ticket` + `stream-info` 获取 HTTP Range 流地址，
     *   边加载边播放，严禁回退 `POST /api/v1/storage/download` 整文件落盘（避免在服务端临时目录与客户端缓存产生大体积媒体副本）；
     * - 仅远端 `.strm` 轻量文本指针文件（`<= 64 KB`）在无流票据时读取直链并立即删除临时指针文件。
     */
    suspend fun resolveStoragePlayback(
        storage: String,
        path: String,
        destFile: java.io.File,
        fallbackKind: String? = null,
    ): ResolvedStoragePlaybackDto? {
        val fileName = path.substringAfterLast('/').ifBlank { destFile.name }
        val detectedKind = fallbackKind ?: RustCoreBridge.detectMediaKind(path, false)
        val normalizedStorage = storage.trim().ifBlank { "local" }
        val isStrm = RustCoreBridge.isStrmPath(fileName) || RustCoreBridge.isStrmPath(path)
        val shouldTryStreamTicket =
            normalizedStorage.equals("local", ignoreCase = true) || !isStrm
        if (shouldTryStreamTicket) {
            val ticketId = createStorageStreamTicket(
                storage = normalizedStorage,
                path = path,
                fileName = fileName,
                mediaType = if (detectedKind == "audio") "audio" else "video",
            )
            if (!ticketId.isNullOrBlank()) {
                val manifest = fetchVideoStreamInfo(itemId = ticketId, server = null)
                if (manifest != null && manifest.contentUrl.isNotBlank()) {
                    val isStrmDirect = manifest.activeRouteKind == "strm_direct"
                    return ResolvedStoragePlaybackDto(
                        url = manifest.contentUrl,
                        isAudio = manifest.mediaType.equals("audio", ignoreCase = true) || detectedKind == "audio",
                        headers = manifest.headers,
                        sameOriginHeaders = manifest.sameOriginHeaders,
                        streamHeaders = manifest.streamHeaders,
                        originUrl = manifest.originUrl,
                        proxyFallbackUrl = manifest.proxyFallbackUrl,
                        activeRouteKind = manifest.activeRouteKind,
                        fallbackRoutes = manifest.fallbackRoutes,
                        itemId = manifest.itemId,
                        lyricsUrl = manifest.lyricsUrl,
                        title = manifest.title,
                        tempFilePath = null,
                        isStrmDirect = isStrmDirect,
                    )
                }
            }
        }

        if (!isStrm) {
            return null
        }

        val downloaded = downloadStorageFileToCache(storage, path, destFile) ?: return null
        if (!downloaded.exists()) return null
        val rawBytes = runCatching {
            if (downloaded.length() in 1..65_536L) downloaded.readBytes() else null
        }.getOrNull()
        runCatching { downloaded.delete() }
        val bytes = rawBytes ?: return null
        val text = decodeStrmBytes(bytes) ?: return null
        val spec = RustCoreBridge.parseStrm(text, fileName) ?: return null
        return ResolvedStoragePlaybackDto(
            url = spec.url,
            isAudio = spec.mediaKind == "audio",
            streamHeaders = spec.headers,
            tempFilePath = null,
            isStrmDirect = true,
        )
    }

    /** 回传当前播放位置、会话生命周期及轨道上下文到媒体服务器（`POST /api/v1/mediaserver/progress`）。 */
    suspend fun reportMediaPlaybackProgress(
        itemId: String,
        server: String,
        positionMs: Long,
        durationMs: Long,
        isPaused: Boolean,
        state: String,
        mediaSourceId: String? = null,
        eventName: String? = null,
        playSessionId: String? = null,
        clientId: String? = null,
        deviceName: String? = null,
        platform: String? = "Android",
        appVersion: String? = null,
        playMethod: String = "DirectPlay",
        playbackTimeMs: Long? = null,
        audioStreamIndex: Int? = null,
        subtitleStreamIndex: Int? = null,
        seq: Long? = null,
        expectedSession: SessionState.Authenticated? = null,
    ): Boolean {
        if (itemId.isBlank() || server.isBlank() || itemId.startsWith("file.") || itemId.startsWith("file:")) {
            return false
        }
        val fields = mutableListOf(
            """"item_id":"${esc(itemId)}"""",
            """"server":"${esc(server)}"""",
            """"position_ms":${positionMs.coerceAtLeast(0L)}""",
            """"is_paused":$isPaused""",
            """"state":"${esc(state)}"""",
            """"play_method":"${esc(playMethod)}"""",
        )
        if (durationMs > 0L) fields += """"duration_ms":$durationMs"""
        if (!mediaSourceId.isNullOrBlank()) fields += """"media_source_id":"${esc(mediaSourceId)}""""
        if (!eventName.isNullOrBlank()) fields += """"event_name":"${esc(eventName)}""""
        if (!playSessionId.isNullOrBlank()) fields += """"play_session_id":"${esc(playSessionId)}""""
        if (!clientId.isNullOrBlank()) fields += """"client_id":"${esc(clientId)}""""
        if (!deviceName.isNullOrBlank()) fields += """"device_name":"${esc(deviceName)}""""
        if (!platform.isNullOrBlank()) fields += """"platform":"${esc(platform)}""""
        if (!appVersion.isNullOrBlank()) fields += """"app_version":"${esc(appVersion)}""""
        if (playbackTimeMs != null && playbackTimeMs >= 0L) fields += """"playback_time_ms":$playbackTimeMs"""
        if (audioStreamIndex != null && audioStreamIndex >= 0) fields += """"audio_stream_index":$audioStreamIndex"""
        if (subtitleStreamIndex != null) fields += """"subtitle_stream_index":$subtitleStreamIndex"""
        if (seq != null && seq >= 0L) fields += """"seq":$seq"""
        val body = "{${fields.joinToString(",")}}"
        val resp = runCatching {
            authedRequest(listOf("mediaserver", "progress"), method = "POST", body = body, expectedSession = expectedSession).getOrNull()
        }.getOrNull() ?: return false
        if (resp.status !in 200..299) return false
        // 核验响应体中的 `success` 与 `data.reported` 字段，避免 Emby 写入失败仍被当作成功从而跳过离线重试
        val rootObj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull() ?: return true
        val apiSuccess = rootObj.bool("success")
        if (apiSuccess == false) return false
        val dataObj = rootObj["data"]?.asObj()
        val reported = dataObj?.bool("reported")
        return reported ?: true
    }

    /** 查询当前用户在全部已启用媒体服务器上的账号绑定状态与同步模式（`GET /api/v1/mediaserver/account-bindings`）。 */
    suspend fun fetchMediaServerAccountBindings(): Result<List<MediaServerAccountBindingDto>> {
        val resp = authedRequest(listOf("mediaserver", "account-bindings")).getOrElse {
            return Result.failure(it)
        }
        if (resp.status !in 200..299) {
            val err = parseApiErrorDetail(resp.body) ?: "加载媒体服务器绑定状态失败 (HTTP ${resp.status})"
            return Result.failure(IllegalStateException(err))
        }
        val arr = extractArray(resp.body)
            ?: return Result.success(emptyList())
        val items = arr.mapNotNull { el ->
            val o = el.asObj() ?: return@mapNotNull null
            parseMediaServerAccountBinding(o)
        }
        return Result.success(items)
    }

    /** 使用账号密码或 Plex Token 一次性换取加密个人令牌并绑定到当前用户（绝不在本地保存密码）。 */
    suspend fun bindMediaServerAccount(
        server: String,
        username: String? = null,
        password: String? = null,
        token: String? = null,
    ): Result<MediaServerAccountBindingDto> {
        val fields = mutableListOf(""""server":"${esc(server)}"""")
        if (!token.isNullOrBlank()) {
            fields += """"token":"${esc(token.trim())}""""
        } else {
            if (!username.isNullOrBlank()) fields += """"username":"${esc(username.trim())}""""
            if (!password.isNullOrEmpty()) fields += """"password":"${esc(password)}""""
        }
        val resp = authedRequest(
            segments = listOf("mediaserver", "account-bindings"),
            method = "POST",
            body = "{${fields.joinToString(",")}}",
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            val err = parseApiErrorDetail(resp.body) ?: "媒体服务器账号验证失败，请检查凭据"
            return Result.failure(IllegalStateException(err))
        }
        val obj = extractObject(resp.body)
            ?: return Result.failure(IllegalStateException("绑定响应格式异常"))
        val dto = parseMediaServerAccountBinding(obj)
            ?: return Result.failure(IllegalStateException("绑定响应缺少服务器标识"))
        return Result.success(dto)
    }

    /** 解除当前用户在指定媒体服务器上的个人令牌绑定（`DELETE /api/v1/mediaserver/account-bindings/{server}`）。 */
    suspend fun unbindMediaServerAccount(server: String): Result<String> {
        val clean = server.trim()
        if (clean.isEmpty() || clean == "." || clean == ".." || '/' in clean || '\\' in clean) {
            return Result.failure(IllegalArgumentException("媒体服务器名称格式无效"))
        }
        val resp = authedRequest(
            segments = listOf("mediaserver", "account-bindings", clean),
            method = "DELETE",
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            val err = parseApiErrorDetail(resp.body) ?: "解绑媒体服务器账号失败"
            return Result.failure(IllegalStateException(err))
        }
        val msg = runCatching { json.parseToJsonElement(resp.body).asObj()?.str("message") }.getOrNull()
            ?: "已解除账号绑定"
        return Result.success(msg)
    }

    private fun parseApiErrorDetail(rawBody: String): String? {
        val obj = runCatching { json.parseToJsonElement(rawBody).asObj() }.getOrNull() ?: return null
        return obj.str("detail")?.takeIf { it.isNotBlank() }
            ?: obj.str("message")?.takeIf { it.isNotBlank() }
    }

    private fun parseMediaServerAccountBinding(o: JsonObject): MediaServerAccountBindingDto? {
        val srv = o.str("server")?.takeIf { it.isNotBlank() } ?: return null
        val srvType = o.str("server_type").orEmpty()
        return MediaServerAccountBindingDto(
            server = srv,
            serverType = srvType,
            syncMode = o.str("sync_mode") ?: "none",
            supportsBinding = o.bool("supports_binding") ?: false,
            bound = o.bool("bound") ?: false,
            status = o.str("status") ?: "unsupported",
            remoteUsername = o.str("remote_username")?.takeIf { it.isNotBlank() },
            source = o.str("source")?.takeIf { it.isNotBlank() },
            updatedAt = o.lng("updated_at"),
        )
    }

    /** 执行插件页面/表单按钮声明的同源 API 动作（对齐 iOS `triggerPluginAction`）。 */
    suspend fun triggerPluginAction(api: String, method: String = "GET", paramsJson: String? = null): Pair<Boolean, String> {
        val auth = _session.value as? SessionState.Authenticated ?: return false to "未登录"
        val cleanApi = api.trim()
        val targetUrl = when {
            cleanApi.startsWith("http://") || cleanApi.startsWith("https://") -> {
                if (!RustCoreBridge.containsUrl(auth.serverUrl, cleanApi)) return false to "仅允许调用当前实例同源接口"
                cleanApi
            }
            cleanApi.startsWith("/api/") -> "${auth.serverUrl.trimEnd('/')}$cleanApi"
            cleanApi.startsWith("/") -> "${auth.serverUrl.trimEnd('/')}/api/v1$cleanApi"
            else -> "${auth.serverUrl.trimEnd('/')}/api/v1/$cleanApi"
        }
        val resp = runCatching {
            transport.execute(
                url = targetUrl,
                method = method.uppercase(),
                token = auth.token,
                body = if (method.uppercase() in listOf("POST", "PUT", "PATCH")) paramsJson ?: "{}" else null,
            )
        }.getOrNull() ?: return false to "请求失败"
        val msg = extractObject(resp.body)?.str("message") ?: if (resp.status in 200..299) "操作已执行" else "操作失败 (HTTP ${resp.status})"
        return (resp.status in 200..299) to msg
    }

    /** 返回当前同源鉴权头（Authorization + Cookie + Cloudflare Access 网关令牌），专供 Media3 / MPV 播放与字幕预取复用。 */
    fun buildPlaybackHeaders(targetUrl: String): Map<String, String> {
        val auth = _session.value as? SessionState.Authenticated ?: return emptyMap()
        if (!RustCoreBridge.containsUrl(auth.serverUrl, targetUrl)) return emptyMap()
        val map = mutableMapOf<String, String>()
        if (auth.token.isNotBlank()) map["Authorization"] = "Bearer ${auth.token}"
        val rawCookie = transport.exportCookieHeader(targetUrl)
        val cfToken = cloudflareOAuth.accessTokenForUrl(targetUrl)
        val mergedCookie = if (!cfToken.isNullOrBlank()) {
            RustCoreBridge.mergeCloudflareAccessCookie(rawCookie, cfToken)
        } else {
            rawCookie
        }
        if (mergedCookie.isNotBlank()) map["Cookie"] = mergedCookie
        if (!cfToken.isNullOrBlank()) map["cf-access-token"] = cfToken
        return map
    }

    /** 导出同源 Cookie 条目，专供 Vue 模块联邦插件隔离 WebView 写入 `CookieManager`。 */
    fun exportOriginCookieEntries(): List<String> {
        val auth = _session.value as? SessionState.Authenticated ?: return emptyList()
        return transport.exportSetCookieEntries(auth.serverUrl)
    }

    /** 查询当前管理员实例环境变量中的匿名版本统计开关与服务地址（失败返回 `null`）。 */
    suspend fun fetchUsageReportingConfig(): Pair<Boolean, String>? {
        val resp = authedRequest(listOf("system", "env")).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val data = extractObject(resp.body) ?: return null
        val enabled = data.bool("USAGE_STATISTIC_SHARE") == true
        val rawHost = data.str("MP_SERVER_HOST")?.trim().orEmpty()
        return enabled to rawHost.ifEmpty { "https://movie-pilot.org" }
    }

    internal fun resolveSameOriginUrl(serverUrl: String, raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""
        RustCoreBridge.rebaseInstanceApiUrl(serverUrl, trimmed)?.let { return it }
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return trimmed
        val base = serverUrl.trimEnd('/')
        return if (trimmed.startsWith("/")) "$base$trimmed" else "$base/$trimmed"
    }

    // ==================== 手动整理（1:1 对齐 iOS target-path / history / preview / manual） ====================

    suspend fun matchManualTransferTargetPath(payloadJson: String): ManualTransferTargetHintDto? {
        val resp = authedRequest(
            segments = listOf("transfer", "manual", "target-path"),
            method = "POST",
            body = payloadJson,
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val data = extractObject(resp.body) ?: return null
        return ManualTransferTargetHintDto(
            targetStorage = data.str("target_storage") ?: data.str("library_storage") ?: "",
            targetPath = data.str("target_path") ?: data.str("library_path") ?: "",
            transferType = data.str("transfer_type") ?: "",
            overwriteMode = data.str("overwrite_mode") ?: "",
            scrape = data.bool("scrape"),
            libraryTypeFolder = data.bool("library_type_folder"),
            libraryCategoryFolder = data.bool("library_category_folder"),
        )
    }

    suspend fun matchManualTransferHistory(payloadJson: String): ManualTransferHistoryHintDto? {
        val resp = authedRequest(
            segments = listOf("transfer", "manual", "history"),
            method = "POST",
            body = payloadJson,
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val data = extractObject(resp.body) ?: return null
        return ManualTransferHistoryHintDto(
            historyCount = data.int("history_count") ?: data.int("count") ?: 0,
            reorganize = data.bool("reorganize") ?: false,
        )
    }

    suspend fun executeManualTransfer(
        payloadJson: String,
        preview: Boolean,
        background: Boolean,
    ): Triple<Boolean, String, List<ManualTransferPreviewItemDto>> {
        val resp = authedRequest(
            segments = listOf("transfer", "manual"),
            method = "POST",
            query = listOf("background" to (if (preview) "false" else background.toString())),
            body = payloadJson,
        ).getOrNull() ?: return Triple(false, "整理请求失败，请检查网络连接", emptyList())
        val root = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val data = root?.get("data").asObj() ?: root
        val ok = root?.bool("success") ?: (resp.status in 200..299)
        val msg = root?.str("message")?.takeIf { it.isNotBlank() }
            ?: data?.str("message")?.takeIf { it.isNotBlank() }
            ?: if (ok) "整理任务已提交" else "整理失败（HTTP ${resp.status}）"
        val items = (data?.get("items").asArr() ?: data?.get("preview_items").asArr() ?: JsonArray(emptyList()))
            .mapNotNull { el ->
                val o = el.asObj() ?: return@mapNotNull null
                ManualTransferPreviewItemDto(
                    src = o.str("src") ?: o.str("source") ?: o.str("src_path") ?: "",
                    dest = o.str("dest") ?: o.str("target") ?: o.str("dest_path") ?: "",
                    title = o.str("title") ?: o.str("name") ?: "",
                    seasonEpisode = o.str("season_episode") ?: o.str("episodes") ?: "",
                    status = o.str("status") ?: "",
                    message = o.str("message") ?: o.str("errmsg") ?: "",
                )
            }
        return Triple(ok, msg, items)
    }

    // ==================== AI 智能助手（全量对齐 iOS `/api/v1/message/agent/*`） ====================

    suspend fun fetchAgentCommands(): List<AgentCommandDto> {
        val resp = authedRequest(listOf("message", "agent", "commands")).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val o = el.asObj() ?: return@mapNotNull null
            val cmd = o.str("command") ?: o.str("name") ?: return@mapNotNull null
            AgentCommandDto(command = cmd, description = o.str("description") ?: "")
        }
    }

    suspend fun fetchAgentSessions(page: Int = 1, count: Int = 30): List<AgentSessionSummaryDto> {
        val resp = authedRequest(
            segments = listOf("message", "agent", "sessions"),
            query = listOf("page" to page.toString(), "count" to count.toString()),
        ).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val o = el.asObj() ?: return@mapNotNull null
            val sid = o.str("session_id") ?: o.str("id") ?: return@mapNotNull null
            AgentSessionSummaryDto(
                sessionId = sid,
                title = o.str("title")?.takeIf { it.isNotBlank() } ?: "新对话",
                updatedAt = o.str("updated_at") ?: o.str("created_at") ?: "",
                messageCount = o.int("message_count") ?: 0,
                isProcessing = o.bool("is_processing") ?: false,
            )
        }
    }

    suspend fun fetchAgentSessionDetail(sessionId: String): Pair<List<AgentChatMessageDto>, Boolean>? {
        val resp = authedRequest(listOf("message", "agent", "sessions", sessionId)).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val isProcessing = obj.bool("is_processing") ?: false
        val rawMsgs = obj["messages"].asArr() ?: JsonArray(emptyList())
        val parsed = rawMsgs.mapIndexedNotNull { idx, el ->
            val m = el.asObj() ?: return@mapIndexedNotNull null
            val role = m.str("role") ?: "assistant"
            val content = m.str("content") ?: m.str("message") ?: ""
            val tools = m["tools"].asArr()?.mapNotNull { tEl ->
                val to = tEl.asObj() ?: return@mapNotNull null
                AgentToolEntryDto(
                    id = to.str("id") ?: "t-$idx",
                    toolName = to.str("tool_name") ?: "",
                    message = to.str("message") ?: to.str("tool_name") ?: "调用工具",
                    structured = to.bool("structured") ?: true,
                    status = to.str("status") ?: "done",
                )
            } ?: emptyList()
            val attachments = m["attachments"].asArr()?.mapNotNull { aEl ->
                val ao = aEl.asObj() ?: return@mapNotNull null
                AgentAttachmentDto(
                    kind = ao.str("kind") ?: "file",
                    ref = ao.str("ref") ?: "",
                    url = resolveImageUrl(ao.str("url")) ?: ao.str("url") ?: "",
                    downloadUrl = resolveImageUrl(ao.str("download_url")) ?: ao.str("download_url") ?: "",
                    name = ao.str("name") ?: "",
                    mimeType = ao.str("mime_type") ?: "",
                    size = ao.lng("size") ?: 0L,
                    localPath = ao.str("local_path") ?: "",
                )
            } ?: emptyList()
            val choices = m["choices"].asArr()?.mapNotNull { cEl ->
                parseChoiceCard(cEl.asObj())
            } ?: emptyList()
            if (role != "user" && content.isBlank() && tools.isEmpty() && attachments.isEmpty() && choices.isEmpty()) {
                return@mapIndexedNotNull null
            }
            AgentChatMessageDto(
                id = m.str("id") ?: "msg-$idx-${System.currentTimeMillis()}",
                role = role,
                content = content,
                tools = tools,
                attachments = attachments,
                choices = choices,
                isProtected = m.bool("is_protected") ?: false,
            )
        }
        return parsed to isProcessing
    }

    private fun parseChoiceCard(obj: JsonObject?): AgentChoiceCardDto? {
        if (obj == null) return null
        val buttons = obj["buttons"].asArr()?.flatMap { rowEl ->
            when (rowEl) {
                is JsonArray -> rowEl.mapNotNull { b ->
                    val bo = b.asObj() ?: return@mapNotNull null
                    AgentChoiceButtonDto(
                        label = bo.str("label") ?: bo.str("text") ?: return@mapNotNull null,
                        callbackData = bo.str("callback_data") ?: bo.str("data") ?: "",
                    )
                }
                is JsonObject -> listOfNotNull(
                    rowEl.str("label")?.let { AgentChoiceButtonDto(it, rowEl.str("callback_data") ?: "") },
                )
                else -> emptyList()
            }
        } ?: emptyList()
        if (buttons.isEmpty()) return null
        return AgentChoiceCardDto(
            id = obj.str("id") ?: UUID.randomUUID().toString(),
            title = obj.str("title") ?: obj.str("prompt") ?: "",
            buttons = buttons,
            selectedLabel = obj.str("selected_label"),
        )
    }

    suspend fun deleteAgentSession(sessionId: String): Boolean {
        val resp = authedRequest(listOf("message", "agent", "sessions", sessionId), method = "DELETE").getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun stopAgentSession(sessionId: String): Boolean {
        val resp = authedRequest(listOf("message", "agent", "sessions", sessionId, "stop"), method = "POST").getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun saveAgentSessionDisplay(sessionId: String, title: String, messagesJson: String): Boolean {
        val body = """{"title":"${esc(title.take(40))}","messages":$messagesJson}"""
        val resp = authedRequest(
            segments = listOf("message", "agent", "sessions", sessionId, "display"),
            method = "PUT",
            body = body,
        ).getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun uploadAgentAttachment(
        sessionId: String,
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
    ): AgentAttachmentDto? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val url = RustCoreBridge.buildEndpointUrl(auth.serverUrl, listOf("message", "agent", "upload"))
        val resp = runCatching {
            transport.uploadMultipart(
                url = url,
                token = auth.token,
                fieldName = "file",
                fileName = fileName,
                mimeType = mimeType,
                bytes = bytes,
                formFields = mapOf("session_id" to sessionId),
            )
        }.getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val ref = obj.str("ref") ?: obj.str("url") ?: return null
        val rawUrl = obj.str("url") ?: ""
        val rawDl = obj.str("download_url") ?: rawUrl
        val inferredKind = obj.str("kind")?.takeIf { it.isNotBlank() } ?: when {
            mimeType.startsWith("image/") -> "image"
            mimeType.startsWith("audio/") -> "audio"
            else -> "file"
        }
        return AgentAttachmentDto(
            kind = inferredKind,
            ref = ref,
            url = if (rawUrl.isNotBlank()) (resolveImageUrl(rawUrl) ?: rawUrl) else "",
            downloadUrl = if (rawDl.isNotBlank()) (resolveImageUrl(rawDl) ?: rawDl) else "",
            name = obj.str("name") ?: fileName,
            mimeType = obj.str("mime_type") ?: mimeType,
            size = obj.lng("size") ?: bytes.size.toLong(),
            localPath = obj.str("local_path") ?: "",
        )
    }

    suspend fun triggerAgentCallback(
        sessionId: String,
        callbackData: String,
        originalMessageId: String,
    ): Pair<String, String>? {
        val body = """{"session_id":"${esc(sessionId)}","callback_data":"${esc(callbackData)}","original_message_id":"${esc(originalMessageId)}"}"""
        val resp = authedRequest(
            segments = listOf("message", "agent", "callback"),
            method = "POST",
            body = body,
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val msg = obj.str("message").orEmpty()
        val display = obj.str("display_message") ?: msg
        return msg to display
    }

    fun streamAgentChatPayload(payloadJson: String): Flow<SseEventFfi>? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val url = RustCoreBridge.buildEndpointUrl(auth.serverUrl, listOf("message", "agent", "stream"))
        return transport.streamSse(
            url = url,
            token = auth.token,
            bodyJson = payloadJson,
            extraHeaders = mapOf("X-MoviePilot-Agent-Interaction" to "1"),
        )
    }

    fun streamAgentChat(prompt: String, sessionId: String = "android-default"): Flow<SseEventFfi>? {
        val body = """{"text":"${esc(prompt)}","display_text":"${esc(prompt)}","session_id":"${esc(sessionId)}","echo_user":true}"""
        return streamAgentChatPayload(body)
    }

    // ==================== Agent 助手形象（`plugin/agent_pets` + `user/config/AgentPet`） ====================

        /** 获取服务端公布且当前账号可用的插件助手列表。 */
    suspend fun fetchAgentPets(): List<AgentPetDeclarationDto> {
        val resp = authedRequest(listOf("plugin", "agent_pets")).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val o = el.asObj() ?: return@mapNotNull null
            val pid = o.str("plugin_id")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val key = o.str("key")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val mode = o.str("mode")?.takeIf { it == "stage" || it == "renderer" } ?: return@mapNotNull null
            val apiVer = o.int("api_version") ?: 1
            if (apiVer != 1) return@mapNotNull null
            val randomActions = o["random_actions"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s.isNotBlank() } }
            AgentPetDeclarationDto(
                pluginId = pid,
                sourcePluginId = o.str("source_plugin_id")?.takeIf { it.isNotBlank() } ?: pid,
                pluginName = o.str("plugin_name")?.takeIf { it.isNotBlank() } ?: pid,
                key = key,
                name = o.str("name")?.takeIf { it.isNotBlank() } ?: key,
                description = o.str("description").orEmpty(),
                mode = mode,
                component = o.str("component")?.trim()?.removePrefix("./")?.ifBlank { "AgentPet" } ?: "AgentPet",
                apiVersion = apiVer,
                previewUrl = resolveImageUrl(o.str("preview_url")) ?: o.str("preview_url"),
                avatarUrl = resolveImageUrl(o.str("avatar_url")) ?: o.str("avatar_url"),
                remoteUrl = o.str("remote_url"),
                pluginVersion = o.str("plugin_version"),
                bubbles = o.str("bubbles"),
                randomActions = randomActions,
            )
        }
    }

        /** 读取当前用户持久化的助手形象选择。 */
    suspend fun fetchAgentPetSelection(): AgentPetSelection {
        val resp = authedRequest(listOf("user", "config", "AgentPet")).getOrNull() ?: return AgentPetSelection.FollowDefault
        if (resp.status !in 200..299) return AgentPetSelection.FollowDefault
        val obj = extractObject(resp.body) ?: return AgentPetSelection.FollowDefault
        val valueEl = obj["value"] ?: return AgentPetSelection.FollowDefault
        if (valueEl is JsonPrimitive && valueEl.isString && valueEl.content == "builtin") {
            return AgentPetSelection.Builtin
        }
        val mapObj = valueEl.asObj()
        if (mapObj != null) {
            val pid = mapObj.str("plugin_id")?.takeIf { it.isNotBlank() }
            val key = mapObj.str("key")?.takeIf { it.isNotBlank() }
            if (pid != null && key != null) {
                return AgentPetSelection.Plugin(pid, key)
            }
        }
        return AgentPetSelection.FollowDefault
    }

        /** 保存用户的助手形象选择，返回服务端是否接受。 */
    suspend fun saveAgentPetSelection(selection: AgentPetSelection): Boolean {
        val body = when (selection) {
            AgentPetSelection.FollowDefault -> "null"
            AgentPetSelection.Builtin -> "\"builtin\""
            is AgentPetSelection.Plugin -> """{"plugin_id":"${esc(selection.pluginId)}","key":"${esc(selection.key)}"}"""
        }
        val resp = authedRequest(
            segments = listOf("user", "config", "AgentPet"),
            method = "POST",
            body = body,
        ).getOrNull() ?: return false
        return resp.status in 200..299
    }

        /** 读取管理员配置的默认助手形象标识。 */
    suspend fun fetchGlobalAgentPetDefault(): String {
        val resp = authedRequest(listOf("system", "global", "user")).getOrNull() ?: return ""
        if (resp.status !in 200..299) return ""
        val obj = extractObject(resp.body) ?: return ""
        return obj.str("AI_AGENT_PET")?.trim().orEmpty()
    }

    // ==================== 100% JsonNull-Safe 解析工具 ====================

    private fun extractArray(body: String?): List<JsonElement> {
        if (body.isNullOrBlank()) return emptyList()
        val root = runCatching { json.parseToJsonElement(body) }.getOrNull() ?: return emptyList()
        return when (root) {
            is JsonArray -> root
            is JsonObject -> {
                val data = root["data"]
                when (data) {
                    is JsonArray -> data
                    is JsonObject -> data["list"].asArr() ?: data["items"].asArr() ?: emptyList()
                    else -> root["list"].asArr() ?: root["items"].asArr() ?: emptyList()
                }
            }
            else -> emptyList()
        }
    }

    private fun extractObject(body: String?): JsonObject? {
        if (body.isNullOrBlank()) return null
        val root = runCatching { json.parseToJsonElement(body).asObj() }.getOrNull() ?: return null
        return root["data"].asObj() ?: root
    }

    private fun JsonElement?.asObj(): JsonObject? = this as? JsonObject
    private fun JsonElement?.asArr(): JsonArray? = this as? JsonArray
    private fun JsonElement?.asPrim(): JsonPrimitive? = this as? JsonPrimitive

    private fun JsonObject.str(key: String): String? {
        val prim = this[key].asPrim() ?: return null
        return if (prim.content == "null") null else prim.content
    }

    private fun JsonObject.int(key: String): Int? = this[key].asPrim()?.intOrNull
    private fun JsonObject.lng(key: String): Long? = this[key].asPrim()?.longOrNull
    private fun JsonObject.dbl(key: String): Double? = this[key].asPrim()?.doubleOrNull
    private fun JsonObject.bool(key: String): Boolean? = this[key].asPrim()?.booleanOrNull

    private fun esc(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

    private val danmakuCommentsCache = java.util.concurrent.ConcurrentHashMap<Long, Pair<String, String>>()

    /** 查询当前实例弹幕代理服务是否启用（普通用户可读，不暴露上游地址与密钥）。 */
    suspend fun fetchDanmakuStatus(): Boolean {
        val resp = authedRequest(segments = listOf("danmaku", "status")).getOrNull() ?: return false
        if (resp.status !in 200..299) return false
        return extractObject(resp.body)?.bool("enabled") ?: false
    }

    /** 管理员读取弹幕服务配置快照及磁盘缓存统计。 */
    suspend fun fetchDanmakuConfig(): Result<DanmakuConfigDto> {
        val resp = authedRequest(segments = listOf("danmaku", "config")).getOrElse { return Result.failure(it) }
        if (resp.status == 404) {
            return Result.failure(IllegalStateException("当前后端版本暂不支持弹幕服务，请先升级 MoviePilot 后端"))
        }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "读取弹幕服务配置失败")))
        }
        val obj = extractObject(resp.body) ?: return Result.failure(IllegalStateException("弹幕配置响应格式异常"))
        return runCatching { json.decodeFromJsonElement(DanmakuConfigDto.serializer(), obj) }
    }

    /** 管理员加密更新弹幕服务配置。 */
    suspend fun updateDanmakuConfig(payloadJson: String): Result<DanmakuConfigDto> {
        val resp = authedRequest(
            segments = listOf("danmaku", "config"),
            method = "PUT",
            body = payloadJson,
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "保存弹幕服务配置失败")))
        }
        val obj = extractObject(resp.body) ?: return Result.failure(IllegalStateException("弹幕配置响应格式异常"))
        return runCatching { json.decodeFromJsonElement(DanmakuConfigDto.serializer(), obj) }
    }

    /** 管理员测试弹幕上游连通性与鉴权。 */
    suspend fun testDanmakuConfig(payloadJson: String): Result<DanmakuConfigTestResultDto> {
        val resp = authedRequest(
            segments = listOf("danmaku", "config", "test"),
            method = "POST",
            body = payloadJson,
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "测试弹幕服务连接失败")))
        }
        val obj = extractObject(resp.body) ?: return Result.failure(IllegalStateException("测试结果格式异常"))
        return runCatching { json.decodeFromJsonElement(DanmakuConfigTestResultDto.serializer(), obj) }
    }

    /** 管理员清空服务端弹幕元数据与磁盘缓存。 */
    suspend fun clearDanmakuCache(): Result<DanmakuCacheClearResultDto> {
        val resp = authedRequest(
            segments = listOf("danmaku", "cache"),
            method = "DELETE",
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "清空弹幕缓存失败")))
        }
        danmakuCommentsCache.clear()
        val obj = extractObject(resp.body) ?: return Result.success(DanmakuCacheClearResultDto())
        return runCatching { json.decodeFromJsonElement(DanmakuCacheClearResultDto.serializer(), obj) }
    }

    /** 匹配当前播放媒体对应的弹幕分集（优先手动绑定，再自动匹配与剧名兜底）。 */
    suspend fun matchDanmaku(
        itemId: String?,
        server: String?,
        title: String?,
        seriesName: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        year: Int?,
        tmdbId: String?,
        fileName: String?,
        fileSize: Long?,
        durationMs: Long?,
    ): Result<DanmakuMatchResponseDto> {
        val body = buildJsonObject {
            if (!itemId.isNullOrBlank()) put("item_id", itemId)
            if (!server.isNullOrBlank()) put("server", server)
            if (!title.isNullOrBlank()) put("title", title)
            if (!seriesName.isNullOrBlank()) put("series_name", seriesName)
            if (seasonNumber != null) put("season_number", seasonNumber)
            if (episodeNumber != null) put("episode_number", episodeNumber)
            if (year != null) put("year", year)
            if (!tmdbId.isNullOrBlank()) put("tmdb_id", tmdbId)
            if (!fileName.isNullOrBlank()) put("file_name", fileName)
            if (fileSize != null && fileSize > 0L) put("file_size", fileSize)
            if (durationMs != null && durationMs > 0L) put("duration_ms", durationMs)
        }.toString()
        val resp = authedRequest(
            segments = listOf("danmaku", "match"),
            method = "POST",
            body = body,
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "匹配弹幕失败")))
        }
        val obj = extractObject(resp.body) ?: return Result.success(DanmakuMatchResponseDto())
        return runCatching { json.decodeFromJsonElement(DanmakuMatchResponseDto.serializer(), obj) }
    }

    /** 手动搜剧查询弹幕候选作品与分集列表。 */
    suspend fun searchDanmaku(keyword: String, episode: String? = null): Result<List<DanmakuAnimeSearchItemDto>> {
        val q = buildList {
            add("keyword" to keyword.trim())
            if (!episode.isNullOrBlank()) add("episode" to episode.trim())
        }
        val resp = authedRequest(segments = listOf("danmaku", "search"), query = q)
            .getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "搜索弹幕剧集失败")))
        }
        val arr = extractArray(resp.body) ?: return Result.success(emptyList())
        return runCatching {
            arr.mapNotNull { el ->
                runCatching { json.decodeFromJsonElement(DanmakuAnimeSearchItemDto.serializer(), el) }.getOrNull()
            }
        }
    }

    /** 查询指定作品的完整弹幕分集目录。 */
    suspend fun fetchDanmakuBangumi(animeId: Long): Result<DanmakuBangumiDto> {
        val resp = authedRequest(segments = listOf("danmaku", "bangumi", animeId.toString()))
            .getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "获取分集列表失败")))
        }
        val obj = extractObject(resp.body) ?: return Result.failure(IllegalStateException("分集目录响应异常"))
        return runCatching { json.decodeFromJsonElement(DanmakuBangumiDto.serializer(), obj) }
    }

    /** 拉取单集归一化紧凑弹幕载荷，自动携带 `If-None-Match` 协商 304 缓存命中。 */
    suspend fun fetchDanmakuComments(episodeId: Long, forceRefresh: Boolean = false): Result<DanmakuCommentsRawDto> {
        val cached = if (forceRefresh) null else danmakuCommentsCache[episodeId]
        val extra = if (cached != null) mapOf("If-None-Match" to cached.first) else emptyMap()
        val query = if (forceRefresh) listOf("force_refresh" to "true") else emptyList()
        val resp = authedRequest(
            segments = listOf("danmaku", "comments", episodeId.toString()),
            query = query,
            extraHeaders = extra,
        ).getOrElse { return Result.failure(it) }
        if (resp.status == 304 && cached != null) {
            return Result.success(DanmakuCommentsRawDto(rawJson = cached.second, etag = cached.first, fromCache = true))
        }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "拉取弹幕失败")))
        }
        val etag = resp.headers.entries.firstOrNull { it.key.equals("ETag", ignoreCase = true) }?.value
        if (!etag.isNullOrBlank()) {
            if (danmakuCommentsCache.size >= 12) danmakuCommentsCache.clear()
            danmakuCommentsCache[episodeId] = etag to resp.body
        }
        return Result.success(DanmakuCommentsRawDto(rawJson = resp.body, etag = etag, fromCache = false))
    }

    /** 持久化保存手动纠偏绑定与时间偏移至服务端，一端纠偏全端共享。 */
    suspend fun saveDanmakuBinding(
        server: String?,
        itemId: String?,
        tmdbId: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        episodeId: Long,
        animeId: Long?,
        animeTitle: String,
        episodeTitle: String,
        shiftMs: Int,
    ): Result<DanmakuEpisodeCandidateDto> {
        val body = buildJsonObject {
            if (!server.isNullOrBlank()) put("server", server)
            if (!itemId.isNullOrBlank()) put("item_id", itemId)
            if (!tmdbId.isNullOrBlank()) put("tmdb_id", tmdbId)
            if (seasonNumber != null) put("season_number", seasonNumber)
            if (episodeNumber != null) put("episode_number", episodeNumber)
            put("episode_id", episodeId)
            if (animeId != null) put("anime_id", animeId)
            put("anime_title", animeTitle)
            put("episode_title", episodeTitle)
            put("shift_ms", shiftMs)
        }.toString()
        val resp = authedRequest(
            segments = listOf("danmaku", "bindings"),
            method = "PUT",
            body = body,
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "保存弹幕绑定失败")))
        }
        val obj = extractObject(resp.body) ?: return Result.success(
            DanmakuEpisodeCandidateDto(episodeId = episodeId, animeId = animeId, animeTitle = animeTitle, episodeTitle = episodeTitle, shiftMs = shiftMs),
        )
        return runCatching { json.decodeFromJsonElement(DanmakuEpisodeCandidateDto.serializer(), obj) }
    }

    /** 删除媒体条目的手动弹幕绑定，恢复自动匹配。 */
    suspend fun deleteDanmakuBinding(
        server: String?,
        itemId: String?,
        tmdbId: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
    ): Result<Boolean> {
        val q = buildList {
            if (!server.isNullOrBlank()) add("server" to server)
            if (!itemId.isNullOrBlank()) add("item_id" to itemId)
            if (!tmdbId.isNullOrBlank()) add("tmdb_id" to tmdbId)
            if (seasonNumber != null) add("season_number" to seasonNumber.toString())
            if (episodeNumber != null) add("episode_number" to episodeNumber.toString())
        }
        val resp = authedRequest(
            segments = listOf("danmaku", "bindings"),
            method = "DELETE",
            query = q,
        ).getOrElse { return Result.failure(it) }
        if (resp.status !in 200..299) {
            return Result.failure(IllegalStateException(extractErrorMessage(resp.body, "解除弹幕绑定失败")))
        }
        return Result.success(true)
    }

    private fun extractErrorMessage(body: String, fallback: String): String {
        val root = runCatching { json.parseToJsonElement(body).asObj() }.getOrNull() ?: return fallback
        return root.str("detail")?.takeIf { it.isNotBlank() }
            ?: root.str("message")?.takeIf { it.isNotBlank() }
            ?: fallback
    }

    companion object {
        /** 解码 `.strm` 字节数组（兼容 UTF-8 BOM、UTF-16 LE/BE 与 GB18030）。 */
        fun decodeStrmBytes(bytes: ByteArray): String? {
            if (bytes.isEmpty() || bytes.size > 65_536) return null
            if (bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) {
                return String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
            }
            if (bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()) {
                return String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
            }
            val utf8 = runCatching {
                java.nio.charset.StandardCharsets.UTF_8
                    .newDecoder()
                    .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                    .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                    .decode(java.nio.ByteBuffer.wrap(bytes))
                    .toString()
            }.getOrNull()
            if (utf8 != null) return utf8.removePrefix("\uFEFF")
            return runCatching {
                String(bytes, java.nio.charset.Charset.forName("GB18030"))
            }.getOrNull()
        }

        private val TMDB_GENRE_ID_TO_ZH = mapOf(
            28 to "动作", 12 to "冒险", 16 to "动画", 35 to "喜剧", 80 to "犯罪",
            99 to "纪录", 18 to "剧情", 10751 to "家庭", 14 to "奇幻", 36 to "历史",
            27 to "恐怖", 10402 to "音乐", 9648 to "悬疑", 10749 to "爱情", 878 to "科幻",
            10770 to "电视电影", 53 to "惊悚", 10752 to "战争", 37 to "西部",
            10759 to "动作冒险", 10762 to "儿童", 10763 to "新闻", 10764 to "真人秀",
            10765 to "科幻奇幻", 10766 to "肥皂剧", 10767 to "脱口秀", 10768 to "战争政治",
        )

        private val TMDB_GENRE_LABEL_TO_ID = mapOf(
            "动作" to "28", "科幻" to "878", "动画" to "16",
            "喜剧" to "35", "剧情" to "18", "悬疑" to "9648",
            "犯罪" to "80", "奇幻" to "14", "冒险" to "12",
        )

        private val TMDB_LANG_LABEL_TO_CODE = mapOf(
            "华语" to "zh", "英语" to "en", "日语" to "ja", "韩语" to "ko",
        )

        /** 统一判定媒体类型是否属于剧集/分季/单集维度（避免 `"tv"` / `"Series"` / `"电视剧"` 状态跳变）。 */
        fun isTvType(type: String?): Boolean {
            val t = type?.trim()?.lowercase() ?: return false
            return t in setOf("电视剧", "tv", "series", "show", "season", "episode", "anime", "番剧", "剧集", "tvshow")
        }

        /** 将英文、媒体服务器或榜单类型统一映射为 MoviePilot V3 标准中文 `MediaType`（`电影` / `电视剧` / `音乐`）。 */
        fun canonicalMediaType(type: String?): String {
            val t = type?.trim().orEmpty()
            return when {
                isTvType(t) -> "电视剧"
                t.lowercase() in setOf("音乐", "music", "audio", "musicalbum", "album", "track") -> "音乐"
                else -> "电影"
            }
        }

        /** 将客户端探索页、推荐流或历史别名统一映射为 MoviePilot V3 规范 `MediaSource`；媒体服务器名返回 `null`。 */
        fun normalizeMediaSource(rawSource: String?): String? {
            val s = rawSource?.trim()?.lowercase()?.takeIf { it.isNotBlank() } ?: return null
            return when (s) {
                "themoviedb", "tmdb", "tmdb_movies", "tmdb_tvs", "tmdb_trending" -> "themoviedb"
                "douban", "douban_movies", "douban_tvs", "douban_showing", "douban_top250" -> "douban"
                "doubanmusic", "douban_music" -> "doubanmusic"
                "bangumi", "bgm" -> "bangumi"
                "anilist" -> "anilist"
                "imdb" -> "imdb"
                "tvdb", "thetvdb" -> "tvdb"
                "musicbrainz", "music" -> "musicbrainz"
                "theaudiodb", "audio_db" -> "theaudiodb"
                else -> null
            }
        }

        /**
         * 规范化 `(media_source, raw_media_id)` 元数据身份对：
         * - 自动剥离 `tmdb:12345`、`douban:3520`、`bangumi:400` 等历史前缀；
         * - 拒绝 `"0"`、空白或媒体服务器内部条目 ID 混入 V3 外部元数据接口。
         */
        fun normalizeCanonicalMediaIdentity(
            source: String?,
            mediaId: String?,
            tmdbId: Int? = null,
            doubanId: String? = null,
            bangumiId: Int? = null,
            imdbId: String? = null,
            tvdbId: String? = null,
        ): Pair<String, String>? {
            val rawIdTrimmed = mediaId?.trim()?.takeIf { it.isNotBlank() && it != "0" && !it.equals("null", true) }
            if (rawIdTrimmed != null && rawIdTrimmed.contains(":")) {
                val prefix = rawIdTrimmed.substringBefore(":")
                val rest = rawIdTrimmed.substringAfter(":").trim()
                val mappedPrefix = normalizeMediaSource(prefix)
                if (mappedPrefix != null && rest.isNotBlank() && rest != "0") {
                    return mappedPrefix to rest
                }
            }

            val normSrc = normalizeMediaSource(source)
            if (normSrc != null) {
                val candidateId = when (normSrc) {
                    "themoviedb" -> tmdbId?.takeIf { it > 0 }?.toString() ?: rawIdTrimmed
                    "douban" -> doubanId?.trim()?.takeIf { it.isNotBlank() && it != "0" } ?: rawIdTrimmed
                    "bangumi" -> bangumiId?.takeIf { it > 0 }?.toString() ?: rawIdTrimmed
                    "imdb" -> imdbId?.trim()?.takeIf { it.isNotBlank() && it != "0" } ?: rawIdTrimmed
                    "tvdb" -> tvdbId?.trim()?.takeIf { it.isNotBlank() && it != "0" } ?: rawIdTrimmed
                    else -> rawIdTrimmed
                }
                if (!candidateId.isNullOrBlank() && candidateId != "0" && !candidateId.contains(":")) {
                    return normSrc to candidateId
                }
            }

            tmdbId?.takeIf { it > 0 }?.let { return "themoviedb" to it.toString() }
            doubanId?.trim()?.takeIf { it.isNotBlank() && it != "0" }?.let { return "douban" to it }
            bangumiId?.takeIf { it > 0 }?.let { return "bangumi" to it.toString() }
            imdbId?.trim()?.takeIf { it.isNotBlank() && it != "0" }?.let { return "imdb" to it }
            tvdbId?.trim()?.takeIf { it.isNotBlank() && it != "0" }?.let { return "tvdb" to it }
            return null
        }

        /**
         * 构造音乐探索四大榜单的规范化 API 路径与查询参数（修复 MusicBrainz `mode=chart` / `mode=fresh` 422 参数问题）。
         */
        fun buildMusicFeedEndpoint(feed: String, page: Int = 1): Pair<List<String>, List<Pair<String, String>>> {
            val pageStr = page.coerceAtLeast(1).toString()
            return when (feed) {
                "weekly" -> listOf("recommend", "music_weekly") to listOf("page" to pageStr)
                "popular" -> listOf("music", "explore") to listOf(
                    "mode" to "chart",
                    "entity" to "album",
                    "range_name" to "this_month",
                    "media_source" to "musicbrainz",
                    "count" to "30",
                    "page" to pageStr,
                )
                "latest" -> listOf("music", "explore") to listOf(
                    "mode" to "fresh",
                    "days" to "30",
                    "media_source" to "musicbrainz",
                    "count" to "30",
                    "page" to pageStr,
                )
                else -> listOf("recommend", "music_douban") to listOf("page" to pageStr)
            }
        }

        /**
         * 剧集智能续播定位（对齐 iOS `nextPlayableEpisodeIndex`）：
         * 优先定位 `resumePositionMs > 30_000 && !played` 的在看集，其次首个 `!played` 未看集，全部看完回退首集 `0`。
         */
        fun smartNextPlayableEpisodeIndex(episodes: List<MediaServerBrowseItemDto>): Int? {
            if (episodes.isEmpty()) return null
            val resumingIdx = episodes.indexOfFirst { it.resumePositionMs > 30_000L && !it.played }
            if (resumingIdx >= 0) return resumingIdx
            val unplayedIdx = episodes.indexOfFirst { !it.played }
            if (unplayedIdx >= 0) return unplayedIdx
            return 0
        }

        private val SUBSCRIBE_QUALITY_ALIASES = mapOf(
            "全部" to "",
            "all" to "",
            "蓝光原盘" to "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD",
            "藍光原盤" to "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD",
            "blu-ray original" to "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD",
            "bluray original" to "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD",
            "remux" to "Remux",
            "bluray" to "Blu-?Ray",
            "blu-ray" to "Blu-?Ray",
            "uhd" to "UHD|UltraHD",
            "web-dl" to "WEB-?DL|WEB-?RIP",
            "webdl" to "WEB-?DL|WEB-?RIP",
            "hdtv" to "HDTV",
            "h265" to "[Hx].?265|HEVC",
            "h.265" to "[Hx].?265|HEVC",
            "hevc" to "[Hx].?265|HEVC",
            "h264" to "[Hx].?264|AVC",
            "h.264" to "[Hx].?264|AVC",
            "avc" to "[Hx].?264|AVC",
        )

        private val SUBSCRIBE_RESOLUTION_ALIASES = mapOf(
            "全部" to "",
            "all" to "",
            "4k" to "4K|2160p|x2160",
            "1080p" to "1080[pi]|x1080",
            "720p" to "720[pi]|x720",
        )

        private val SUBSCRIBE_EFFECT_ALIASES = mapOf(
            "全部" to "",
            "all" to "",
            "杜比视界" to "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+",
            "杜比視界" to "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+",
            "dolby vision" to "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+",
            "dovi" to "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+",
            "dv" to "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+",
            "杜比全景声" to "Dolby[\\s.]*\\+?Atmos|Atmos",
            "杜比全景聲" to "Dolby[\\s.]*\\+?Atmos|Atmos",
            "dolby atmos" to "Dolby[\\s.]*\\+?Atmos|Atmos",
            "atmos" to "Dolby[\\s.]*\\+?Atmos|Atmos",
            "hdr" to "[\\s.]+HDR[\\s.]+|HDR10|HDR10\\+",
            "sdr" to "[\\s.]+SDR[\\s.]+",
        )

        /** 将订阅质量、分辨率、特效的界面短标签展开为与 Web `constants.ts` 一致的正则，保留自定义正则。 */
        fun normalizeSubscribeFilterOption(field: String, raw: String): String {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) return ""
            val aliases = when (field) {
                "quality" -> SUBSCRIBE_QUALITY_ALIASES
                "resolution" -> SUBSCRIBE_RESOLUTION_ALIASES
                "effect" -> SUBSCRIBE_EFFECT_ALIASES
                else -> return raw
            }
            return aliases[trimmed.lowercase()] ?: raw
        }

        internal val PLUGIN_ICON_FILENAME_REGEX = Regex(
            "^[A-Za-z0-9_][A-Za-z0-9._+\\-]*\\.(?:png|jpe?g|webp|svg|gif|ico)$",
            RegexOption.IGNORE_CASE,
        )

        /** 提取并校验插件相对图标的合法裸文件名（兼容 `./plugin_icon/`、`/plugin_icon/`、`plugin_icon/` 前缀），拒绝路径穿越或非法扩展名。 */
        internal fun extractSafePluginIconFileName(raw: String?): String? {
            val trimmed = raw?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            if (trimmed.equals("null", ignoreCase = true) || trimmed.equals("none", ignoreCase = true)) return null
            if (trimmed.contains("..") || trimmed.contains('\\')) return null
            val candidate = when {
                trimmed.startsWith("./plugin_icon/") -> trimmed.removePrefix("./plugin_icon/")
                trimmed.startsWith("/plugin_icon/") -> trimmed.removePrefix("/plugin_icon/")
                trimmed.startsWith("plugin_icon/") -> trimmed.removePrefix("plugin_icon/")
                else -> trimmed
            }
            if (candidate.isEmpty() || candidate.contains('/') || candidate.contains('\\') || candidate.contains("..")) {
                return null
            }
            return candidate.takeIf { PLUGIN_ICON_FILENAME_REGEX.matches(it) }
        }
    }
}
