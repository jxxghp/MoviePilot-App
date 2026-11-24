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
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlin.math.roundToInt

/** 登录请求结果（支持正常登录、MFA/OTP 二次挑战与错误提示）。 */
sealed interface LoginOutcome {
    data class Success(val identity: UserIdentity) : LoginOutcome
    data class OtpRequired(val message: String) : LoginOutcome
    data class Failure(val message: String) : LoginOutcome
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
    val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    private val _session = MutableStateFlow<SessionState>(SessionState.Unconnected)
    val session: StateFlow<SessionState> = _session.asStateFlow()

    private val _savedServers = MutableStateFlow(secretStore.loadServers())
    val savedServers: StateFlow<List<SavedServerEntry>> = _savedServers.asStateFlow()

    private val siteIconCache = ConcurrentHashMap<Int, String>()
    private val mediaLogoCache = ConcurrentHashMap<String, String>()
    private val resourceRawCache = ConcurrentHashMap<String, JsonObject>()
    @Volatile
    private var resourceCookiePrimed = false

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

    /** 清空当前会话内存数据缓存（在登出、切换实例或遗忘实例时调用）。 */
    fun clearSessionCaches() {
        cachedDiscover = null
        cachedExplore.clear()
        cachedSubscriptions = null
        cachedDashboard = null
        cachedWorkspace = null
        siteIconCache.clear()
        mediaLogoCache.clear()
        resourceRawCache.clear()
    }

    init {
        transport.onAuthClassified = { decision, _, _ ->
            if (decision == "logout" && _session.value is SessionState.Authenticated) {
                logout("登录状态已过期，请重新登录")
            }
        }
        restoreSessionIfPossible()
    }

    /** 启动时尝试恢复上次已连接的实例与有效会话；若 JWT 已过期则安全退回登录页。 */
    private fun restoreSessionIfPossible() {
        val activeUrl = secretStore.activeServerUrl() ?: return
        val token = secretStore.loadToken(activeUrl)
        if (!token.isNullOrBlank() && secretStore.keepLogin) {
            val claims = RustCoreBridge.decodeJwt(token)
            if (!claims.isExpired) {
                val perms = RustCoreBridge.evaluatePermissions("{}", claims.superUser)
                _session.value = SessionState.Authenticated(
                    serverUrl = activeUrl,
                    token = token,
                    identity = UserIdentity(
                        name = claims.userName ?: "admin",
                        isSuperuser = claims.superUser,
                    ),
                    permissions = perms,
                )
                return
            } else {
                secretStore.clearToken(activeUrl)
            }
        }
        _session.value = SessionState.NeedsLogin(activeUrl)
    }

    /** 恢复会话后异步刷新 `/user/current`（拿真实头像与权限）并预热短效资源 Cookie（保证图片代理首屏即命中）。 */
    suspend fun hydrateAuthenticatedSession() {
        val auth = _session.value as? SessionState.Authenticated ?: return
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
                avatar = dataObj.str("avatar") ?: auth.identity.avatar,
            )
            val perms = RustCoreBridge.evaluatePermissions(
                dataObj["permissions"]?.toString() ?: "{}",
                isSu,
            )
            _session.value = auth.copy(identity = refreshed, permissions = perms)
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
        _session.value = SessionState.NeedsLogin(normalized)
        return Result.success(normalized)
    }

    /** 切换到指定历史实例。 */
    fun selectSavedServer(entry: SavedServerEntry) {
        secretStore.setActiveServerUrl(entry.url)
        resourceCookiePrimed = false
        clearSessionCaches()
        val existingToken = secretStore.loadToken(entry.url)
        if (!existingToken.isNullOrBlank() && !RustCoreBridge.decodeJwt(existingToken).isExpired) {
            val claims = RustCoreBridge.decodeJwt(existingToken)
            _session.value = SessionState.Authenticated(
                serverUrl = entry.url,
                token = existingToken,
                identity = UserIdentity(name = entry.username.ifBlank { claims.userName ?: "admin" }, isSuperuser = claims.superUser),
                permissions = RustCoreBridge.evaluatePermissions("{}", claims.superUser),
            )
        } else {
            _session.value = SessionState.NeedsLogin(entry.url)
        }
    }

    fun openServerConnection() {
        _session.value = SessionState.Unconnected
    }

    fun forgetServer(url: String) {
        secretStore.forgetServer(url)
        _savedServers.value = secretStore.loadServers()
        if ((_session.value as? SessionState.NeedsLogin)?.serverUrl == url ||
            (_session.value as? SessionState.Authenticated)?.serverUrl == url
        ) {
            clearSessionCaches()
            _session.value = SessionState.Unconnected
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
        val resp = runCatching {
            transport.execute(
                url = url,
                method = "POST",
                body = form,
                contentType = "application/x-www-form-urlencoded",
            )
        }.getOrElse { return LoginOutcome.Failure("无法连接到服务：${it.message ?: "网络异常"}") }

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

        val superUser = root.bool("super_user") ?: true
        val userName = root.str("user_name") ?: username.trim()
        val avatar = root.str("avatar")
        val permsJson = root["permissions"]?.toString() ?: "{}"

        val identityResp = runCatching {
            val meUrl = RustCoreBridge.buildEndpointUrl(serverUrl, listOf("user", "current"))
            transport.execute(url = meUrl, method = "GET", token = token)
        }.getOrNull()

        var identity = UserIdentity(name = userName, isSuperuser = superUser, avatar = avatar)
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
        _session.value = SessionState.Authenticated(serverUrl, token, identity, permissions)
        primeResourceCookie()
        return LoginOutcome.Success(identity)
    }

    fun logout(notice: String? = null) {
        transport.clearCookies()
        resourceCookiePrimed = false
        clearSessionCaches()
        val current = _session.value
        val url = when (current) {
            is SessionState.Authenticated -> current.serverUrl
            is SessionState.NeedsLogin -> current.serverUrl
            SessionState.Unconnected -> null
        }
        if (url != null) {
            secretStore.clearToken(url)
            _session.value = SessionState.NeedsLogin(url, notice)
        } else {
            _session.value = SessionState.Unconnected
        }
    }

    /** 统一带认证请求执行器：经 Rust 判定 401/令牌失效 403 自动清缓存退登录。 */
    suspend fun authedRequest(
        segments: List<String>,
        method: String = "GET",
        query: List<Pair<String, String>> = emptyList(),
        body: String? = null,
        trailingSlash: Boolean = false,
    ): Result<NativeHttpResponse> {
        val auth = _session.value as? SessionState.Authenticated
            ?: return Result.failure(IllegalStateException("未登录"))
        val url = if (segments.any { seg -> seg.any { it.code > 127 } }) {
            // 含中文路径段（如 `/tmdb/credits/{id}/电视剧`）直接进行单次 UTF-8 百分号编码，避免双重转义
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
        val resp = runCatching {
            transport.execute(url = url, method = method, token = auth.token, body = body)
        }.getOrElse { return Result.failure(it) }

        if (RustCoreBridge.classifyAuthStatus(resp.status, resp.body) == "logout") {
            logout("登录状态已过期，请重新登录")
            return Result.failure(IllegalStateException("登录状态已过期"))
        }
        return Result.success(resp)
    }

    /**
     * 解析图片绝对地址并统一经 MoviePilot V3 服务端图片代理转发：
     * - `data:image/...` 原样返回（由 Coil Base64DataUriFetcher 解码）；
     * - TMDB / 豆瓣 / Bangumi / Emby 等外链经 `${serverUrl}/api/v1/system/img/0?imgurl=...&cache=true` 秒开；
     * - 相对 `/api/...` 自动拼接当前服务器前缀。
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
        val normalized = trimmed.replace("image.tmdb.org/t/p/original/", "image.tmdb.org/t/p/w780/")
        val absolute = when {
            normalized.startsWith("http://") || normalized.startsWith("https://") -> normalized
            normalized.startsWith("/") -> "https://image.tmdb.org/t/p/w500$normalized"
            else -> return null
        }
        if (auth == null) return absolute
        val base = auth.serverUrl.trimEnd('/')
        if (absolute.startsWith("$base/api/")) return absolute
        val encoded = URLEncoder.encode(absolute, "UTF-8")
        val widthQuery = if (maxWidth != null) "&maxWidth=$maxWidth" else ""
        val cookieQuery = if (useCookies) "&use_cookies=true" else ""
        return "$base/api/v1/system/img/0?imgurl=$encoded&cache=true$widthQuery$cookieQuery"
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

    suspend fun searchMedia(keyword: String, kind: String = "media", page: Int = 1): List<MediaCardItem> {
        if (keyword.isBlank()) return emptyList()
        return fetchMediaList(
            listOf("media", "search"),
            listOf("title" to keyword, "type" to kind, "page" to page.toString(), "count" to "20"),
        )
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
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val num = obj.int("season_number") ?: return@mapNotNull null
            if (num <= 0) return@mapNotNull null
            MediaSeasonDto(
                seasonNumber = num,
                name = obj.str("name") ?: "第 $num 季",
                overview = obj.str("overview") ?: "",
                airDate = obj.str("air_date") ?: "",
                episodeCount = obj.int("episode_count") ?: 0,
                posterPath = resolveImageUrl(obj.str("poster_path"), maxWidth = 320),
                voteAverage = obj.dbl("vote_average") ?: 0.0,
            )
        }
    }

    /** 拉取电视剧单季分集列表（`/api/v1/tmdb/{tmdb_id}/{season}`）。 */
    suspend fun fetchSeasonEpisodes(tmdbId: Int, seasonNumber: Int): List<MediaEpisodeDto> {
        val resp = authedRequest(listOf("tmdb", tmdbId.toString(), seasonNumber.toString())).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            MediaEpisodeDto(
                episodeNumber = obj.int("episode_number") ?: return@mapNotNull null,
                name = obj.str("name") ?: "",
                overview = obj.str("overview") ?: "",
                airDate = obj.str("air_date") ?: "",
                runtime = obj.int("runtime"),
                stillPath = resolveImageUrl(obj.str("still_path"), maxWidth = 500),
                voteAverage = obj.dbl("vote_average") ?: 0.0,
            )
        }
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
        val resp = when (feed) {
            "weekly" -> authedRequest(listOf("recommend", "music_weekly"), query = listOf("page" to page.toString()))
            "popular" -> authedRequest(
                listOf("music", "explore"),
                query = listOf("media_source" to "musicbrainz", "sort" to "popular", "page" to page.toString()),
            )
            "latest" -> authedRequest(
                listOf("music", "explore"),
                query = listOf("media_source" to "musicbrainz", "sort" to "latest", "page" to page.toString()),
            )
            else -> authedRequest(listOf("recommend", "music_douban"), query = listOf("page" to page.toString()))
        }.getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val title = obj.str("title") ?: obj.str("name") ?: return@mapNotNull null
            MusicAlbumDto(
                id = obj.str("media_id") ?: obj.str("douban_id") ?: obj.str("id") ?: title,
                title = title,
                artist = obj.str("artist") ?: obj.str("author") ?: obj.str("subtitle") ?: obj.str("original_title") ?: "",
                year = obj.str("year") ?: obj.str("release_date")?.take(4) ?: "",
                coverUrl = resolveImageUrl(obj.str("poster_path") ?: obj.str("cover") ?: obj.str("image"), maxWidth = 500),
                source = obj.str("media_source") ?: "douban",
                voteAverage = obj.dbl("vote_average") ?: 0.0,
                overview = obj.str("overview") ?: "",
            )
        }
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
            bestVersion = (obj.int("best_version") ?: 0) == 1 || obj.bool("best_version") == true,
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

    /** 拉取真实播映日历（优先 `GET /api/v1/subscribe/calendar`；若服务端无此路由则聚合真实 TMDB 单集 air_date）。 */
    suspend fun fetchSubscribeCalendar(): List<CalendarEntryDto> {
        val resp = authedRequest(listOf("subscribe", "calendar")).getOrNull()
        if (resp != null && resp.status in 200..299) {
            return extractArray(resp.body).mapNotNull { el ->
                val obj = el.asObj() ?: return@mapNotNull null
                val title = obj.str("name") ?: obj.str("title") ?: obj.str("show_name") ?: return@mapNotNull null
                val airDate = obj.str("air_date") ?: obj.str("release_date") ?: obj.str("date") ?: return@mapNotNull null
                val tmdbId = obj.int("tmdbid") ?: obj.int("tmdb_id")
                val season = obj.int("season") ?: obj.int("season_number")
                val episode = obj.int("episode") ?: obj.int("episode_number")
                CalendarEntryDto(
                    id = obj.str("id") ?: "${tmdbId ?: title}_S${season ?: 1}E${episode ?: 1}_$airDate",
                    subscribeId = obj.int("subscribe_id") ?: obj.int("id") ?: 0,
                    title = title,
                    year = obj.str("year") ?: airDate.take(4),
                    type = obj.str("type") ?: "电视剧",
                    season = season,
                    episode = episode,
                    episodeTitle = obj.str("episode_title") ?: obj.str("episode_name") ?: "",
                    airDate = airDate.take(10),
                    poster = resolveImageUrl(obj.str("poster") ?: obj.str("poster_path") ?: obj.str("still_path") ?: obj.str("image"), maxWidth = 400),
                    backdrop = resolveImageUrl(obj.str("backdrop") ?: obj.str("backdrop_path") ?: obj.str("still_path"), maxWidth = 720),
                    voteAverage = obj.dbl("vote_average") ?: obj.dbl("vote") ?: 0.0,
                    source = obj.str("media_source") ?: obj.str("source") ?: "themoviedb",
                    tmdbId = tmdbId,
                    doubanId = obj.str("doubanid") ?: obj.str("douban_id"),
                    bangumiId = obj.int("bangumiid") ?: obj.int("bangumi_id"),
                    mediaId = obj.str("media_id"),
                    overview = obj.str("overview") ?: obj.str("description") ?: "",
                )
            }
        }
        // 兼容未提供 `/subscribe/calendar` 的后端版本：按已订阅剧集拉取真实 TMDB 分集 air_date（绝不使用取模伪造日期）
        val tvSubs = fetchSubscriptions(forceRefresh = false).filter { it.type != "电影" }
        if (tvSubs.isEmpty()) return emptyList()
        return coroutineScope {
            tvSubs.take(16).map { sub ->
                async {
                    val tmdbId = sub.mediaId.removePrefix("tmdb:").toIntOrNull()
                        ?: runCatching { json.parseToJsonElement(sub.rawJson).asObj()?.int("tmdbid") }.getOrNull()
                        ?: return@async emptyList()
                    val sNum = sub.season ?: 1
                    fetchSeasonEpisodes(tmdbId, sNum).mapNotNull { ep ->
                        if (ep.airDate.isBlank()) return@mapNotNull null
                        CalendarEntryDto(
                            id = "${sub.id}_S${sNum}E${ep.episodeNumber}",
                            subscribeId = sub.id,
                            title = sub.name,
                            year = sub.year,
                            type = sub.type,
                            season = sNum,
                            episode = ep.episodeNumber,
                            episodeTitle = ep.name,
                            airDate = ep.airDate.take(10),
                            poster = sub.poster ?: ep.stillPath,
                            backdrop = sub.backdrop ?: ep.stillPath,
                            voteAverage = if (ep.voteAverage > 0.0) ep.voteAverage else sub.vote,
                            source = sub.mediaSource,
                            tmdbId = tmdbId,
                            mediaId = sub.mediaId,
                            overview = ep.overview,
                        )
                    }
                }
            }.flatMap { it.await() }
        }
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
            baseMap["season"] = JsonPrimitive(item.season ?: 1)
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
        if (item.startEpisode != null) baseMap["start_episode"] = JsonPrimitive(item.startEpisode) else baseMap.remove("start_episode")
        baseMap["quality"] = JsonPrimitive(item.quality)
        baseMap["resolution"] = JsonPrimitive(item.resolution)
        baseMap["effect"] = JsonPrimitive(item.effect)
        baseMap["best_version"] = JsonPrimitive(if (item.bestVersion) 1 else 0)
        baseMap["sites"] = JsonArray(item.sites.map { JsonPrimitive(it) })
        baseMap["filter_groups"] = JsonArray(item.filterGroups.map { JsonPrimitive(it) })
        baseMap["search_imdbid"] = JsonPrimitive(if (item.searchImdbId) 1 else 0)
        if (item.searchInterval != null && item.searchInterval > 0) {
            baseMap["search_interval"] = JsonPrimitive(item.searchInterval)
        } else {
            baseMap.remove("search_interval")
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

    private fun persistWidgetSnapshot(stats: DashboardStatsDto) {
        runCatching {
            val serverHost = (_session.value as? SessionState.Authenticated)?.serverUrl
                ?.substringAfter("://")
                ?.substringBefore("/")
                ?.ifBlank { "MoviePilot" } ?: "MoviePilot"
            val speedStr = when {
                stats.downloadSpeed >= 1024 * 1024 * 1024 -> String.format("%.1f GB/s", stats.downloadSpeed / (1024 * 1024 * 1024))
                stats.downloadSpeed >= 1024 * 1024 -> String.format("%.1f MB/s", stats.downloadSpeed / (1024 * 1024))
                stats.downloadSpeed >= 1024 -> String.format("%.1f KB/s", stats.downloadSpeed / 1024)
                stats.downloadSpeed > 0 -> String.format("%.0f B/s", stats.downloadSpeed)
                else -> "0 B/s"
            }
            appContext.getSharedPreferences("mp_widget_snapshot_v1", Context.MODE_PRIVATE)
                .edit()
                .putInt("movies", stats.movieCount)
                .putInt("tvs", stats.tvCount)
                .putString("speed", speedStr)
                .putString("server", serverHost)
                .apply()
            val updateIntent = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                setPackage(appContext.packageName)
            }
            appContext.sendBroadcast(updateIntent)
        }
    }

    /** 拉取系统模块列表（`GET /api/v1/module/modulelist`）。 */
    suspend fun fetchSystemModules(): List<SystemModuleStatusDto> {
        val resp = authedRequest(listOf("module", "modulelist")).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val id = obj.str("id") ?: return@mapNotNull null
            SystemModuleStatusDto(
                id = id,
                name = obj.str("name") ?: id,
                moduleType = obj.str("module_type") ?: obj.str("type").orEmpty(),
                subType = obj.str("module_subtype") ?: obj.str("sub_type").orEmpty(),
            )
        }
    }

    /** 对单个系统模块执行真实连通/健康自检（`GET /api/v1/module/moduletest/{id}`）。 */
    suspend fun testSystemModule(moduleId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("module", "moduletest", moduleId)).getOrNull()
            ?: return false to "请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        val msg = obj?.str("message") ?: if (ok) "模块运行正常" else "检测未通过（HTTP ${resp.status}）"
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

    suspend fun fetchSystemLogs(length: Int = 80): List<String> {
        val resp = authedRequest(listOf("system", "logging"), query = listOf("length" to length.toString())).getOrNull()
            ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return resp.body.lines().filter { it.isNotBlank() }.takeLast(length)
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
        return resp != null && resp.status in 200..299
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

    /** 拉取已授权与待审批的消息渠道用户绑定列表（`GET /api/v1/authorization`）。 */
    suspend fun fetchChannelAuthorizations(): List<ChannelAuthRecordDto> {
        val resp = authedRequest(listOf("authorization")).getOrNull()
            ?.takeIf { it.status != 404 }
            ?: authedRequest(listOf("authorization"), trailingSlash = true).getOrNull()
            ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val id = obj.str("id") ?: obj.str("auth_id") ?: obj.str("key") ?: obj.str("userid") ?: return@mapNotNull null
            val rawStatus = obj.str("status") ?: obj.str("state") ?: if (obj.bool("approved") == false) "pending" else "approved"
            ChannelAuthRecordDto(
                id = id,
                channel = obj.str("channel") ?: obj.str("source") ?: obj.str("type") ?: "notification",
                channelUserId = obj.str("channel_user_id") ?: obj.str("userid") ?: obj.str("external_id") ?: id,
                channelUsername = obj.str("channel_username") ?: obj.str("nickname") ?: obj.str("username") ?: "",
                boundUsername = obj.str("bound_user") ?: obj.str("user_name") ?: obj.str("mp_username") ?: "",
                status = if (rawStatus.lowercase() in setOf("pending", "wait", "waiting", "unapproved", "0")) "pending" else "approved",
                createdAt = obj.str("created_at") ?: obj.str("updated_at") ?: obj.str("date") ?: "",
            )
        }
    }

    /** 生成 5 分钟短效渠道绑定授权码（调用 `POST /api/v1/authorization/code`，兼容回退 `POST /api/v1/authorization`）。 */
    suspend fun generateChannelBindingCode(): Result<ChannelBindingCodeDto> {
        var resp = authedRequest(listOf("authorization", "code"), method = "POST", body = "{}").getOrNull()
        if (resp == null || resp.status in setOf(404, 405)) {
            resp = authedRequest(listOf("authorization"), method = "POST", body = "{}").getOrNull()
        }
        if (resp == null) return Result.failure(IllegalStateException("请求失败，请检查网络连接"))
        val root = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val data = root?.get("data").asObj() ?: root
        val code = data?.str("code") ?: data?.str("bind_code") ?: data?.str("token").orEmpty()
        if (resp.status !in 200..299 || code.isBlank()) {
            val errMsg = root?.str("message") ?: root?.str("detail") ?: "服务端暂未开启渠道授权码接口（HTTP ${resp.status}）"
            return Result.failure(IllegalStateException(errMsg))
        }
        val ttl = data?.int("expires_in") ?: data?.int("ttl") ?: 300
        val cmd = data?.str("command") ?: data?.str("instruction") ?: "/bind $code"
        return Result.success(
            ChannelBindingCodeDto(
                code = code,
                expiresInSeconds = ttl.coerceAtLeast(30),
                commandHint = cmd,
                createdAtEpochMs = System.currentTimeMillis(),
            ),
        )
    }

    /** 管理员批准待审核渠道绑定请求（`POST /api/v1/authorization/{id}/approve` 兼容 `PUT /api/v1/authorization/{id}`）。 */
    suspend fun approveChannelAuthorization(id: String): Pair<Boolean, String> {
        var resp = authedRequest(listOf("authorization", id, "approve"), method = "POST", body = "{}").getOrNull()
        if (resp == null || resp.status in setOf(404, 405)) {
            resp = authedRequest(
                segments = listOf("authorization", id),
                method = "PUT",
                body = """{"status":"approved","approved":true}""",
            ).getOrNull()
        }
        if (resp == null) return false to "审批请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "已批准该渠道授权" else "审批失败（HTTP ${resp.status}）")
    }

    /** 删除/解除渠道绑定记录（`DELETE /api/v1/authorization/{id}`）。 */
    suspend fun deleteChannelAuthorization(id: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("authorization", id), method = "DELETE").getOrNull()
            ?: return false to "解绑请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "已移除该渠道绑定" else "移除失败（HTTP ${resp.status}）")
    }

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

    suspend fun fetchPlugins(installedOnly: Boolean): List<PluginItemDto> {
        val state = if (installedOnly) "installed" else "market"
        val resp = authedRequest(
            segments = listOf("plugin"),
            query = listOf("state" to state),
            trailingSlash = true,
        ).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val labelRaw = obj.str("plugin_label").orEmpty()
            val labels = labelRaw.split(",", "，", " ").map { it.trim() }.filter { it.isNotBlank() }
            PluginItemDto(
                id = obj.str("id") ?: return@mapNotNull null,
                name = obj.str("plugin_name") ?: obj.str("id") ?: "",
                desc = obj.str("plugin_desc") ?: "",
                version = obj.str("plugin_version") ?: "1.0.0",
                author = obj.str("plugin_author") ?: "",
                icon = resolveImageUrl(obj.str("plugin_icon")),
                labels = labels,
                installed = obj.bool("installed") ?: installedOnly,
                state = obj.bool("state") ?: false,
                hasPage = obj.bool("has_page") ?: false,
                hasUpdate = obj.bool("has_update") ?: false,
                renderMode = obj.str("render_mode") ?: "vuetify",
                repoUrl = obj.str("repo_url").orEmpty(),
            )
        }.distinctBy { it.id }
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
        return ok to (obj?.str("message") ?: if (ok) (if (force) "插件更新成功" else "插件安装成功") else "安装失败（HTTP ${resp.status}）")
    }

    /** 卸载指定插件（`DELETE /api/v1/plugin/{plugin_id}`）。 */
    suspend fun uninstallPlugin(pluginId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("plugin", pluginId), method = "DELETE").getOrNull()
            ?: return false to "卸载请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "插件已卸载" else "卸载失败（HTTP ${resp.status}）")
    }

    /** 重置指定插件配置与运行数据（`GET /api/v1/plugin/reset/{plugin_id}`）。 */
    suspend fun resetPlugin(pluginId: String): Pair<Boolean, String> {
        val resp = authedRequest(listOf("plugin", "reset", pluginId), method = "GET").getOrNull()
            ?: return false to "重置请求失败"
        val obj = runCatching { json.parseToJsonElement(resp.body).asObj() }.getOrNull()
        val ok = obj?.bool("success") ?: (resp.status in 200..299)
        return ok to (obj?.str("message") ?: if (ok) "插件已重置" else "重置失败（HTTP ${resp.status}）")
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

    /** 拉取媒体服务器真实直放流与外挂字幕清单（`GET /api/v1/mediaserver/stream-info`）。 */
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
        val resp = authedRequest(listOf("mediaserver", "stream-info"), query = q).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val rawUrl = obj.str("content_url")?.takeIf { it.isNotBlank() } ?: return null
        val contentUrl = resolveSameOriginUrl(auth.serverUrl, rawUrl)
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
            server = obj.str("server") ?: server.orEmpty(),
            mediaType = obj.str("media_type") ?: "video",
            title = obj.str("title").orEmpty(),
            contentUrl = contentUrl,
            subtitles = subs,
            lyricsUrl = lyricsUrl,
            durationMs = obj.lng("duration_ms") ?: ((obj.dbl("duration") ?: 0.0) * 1000.0).toLong(),
            resumePositionMs = obj.lng("position_ms") ?: obj.lng("resume_position_ms") ?: 0L,
            headers = buildPlaybackHeaders(contentUrl),
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
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val rawUrl = obj.str("content_url")?.takeIf { it.isNotBlank() } ?: return null
        val contentUrl = resolveSameOriginUrl(auth.serverUrl, rawUrl)
        val lyricsUrl = obj.str("lyrics_url")?.takeIf { it.isNotBlank() }?.let { resolveSameOriginUrl(auth.serverUrl, it) }
        return MediaPlaybackManifestDto(
            itemId = obj.str("item_id").orEmpty(),
            server = obj.str("server").orEmpty(),
            mediaType = "audio",
            title = obj.str("title") ?: title,
            contentUrl = contentUrl,
            lyricsUrl = lyricsUrl,
            durationMs = obj.lng("duration_ms") ?: 0L,
            headers = buildPlaybackHeaders(contentUrl),
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

    /** 下载本地或云盘存储文件至应用受管缓存目录供 ExoPlayer 无缝直放（对齐 iOS `loadStorageFileManifest`）。 */
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

    /** 回传当前播放位置与状态到媒体服务器（`POST /api/v1/mediaserver/progress`）。 */
    suspend fun reportMediaPlaybackProgress(
        itemId: String,
        server: String,
        positionMs: Long,
        durationMs: Long,
        isPaused: Boolean,
        state: String,
    ) {
        if (itemId.isBlank() || server.isBlank() || itemId.startsWith("file.")) return
        val body = """{"item_id":"${esc(itemId)}","server":"${esc(server)}","position_ms":${positionMs.coerceAtLeast(0L)},"duration_ms":${durationMs.coerceAtLeast(0L)},"is_paused":$isPaused,"state":"${esc(state)}"}"""
        runCatching {
            authedRequest(listOf("mediaserver", "progress"), method = "POST", body = body)
        }
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

    /** 返回当前同源鉴权头（Authorization + Cookie），专供 Media3 播放请求复用。 */
    fun buildPlaybackHeaders(targetUrl: String): Map<String, String> {
        val auth = _session.value as? SessionState.Authenticated ?: return emptyMap()
        if (!RustCoreBridge.containsUrl(auth.serverUrl, targetUrl)) return emptyMap()
        val map = mutableMapOf<String, String>()
        if (auth.token.isNotBlank()) map["Authorization"] = "Bearer ${auth.token}"
        val cookie = transport.exportCookieHeader(targetUrl)
        if (cookie.isNotBlank()) map["Cookie"] = cookie
        return map
    }

    /** 导出同源 Cookie 条目，专供 Vue 模块联邦插件隔离 WebView 写入 `CookieManager`。 */
    fun exportOriginCookieEntries(): List<String> {
        val auth = _session.value as? SessionState.Authenticated ?: return emptyList()
        return transport.exportSetCookieEntries(auth.serverUrl)
    }

    private fun resolveSameOriginUrl(serverUrl: String, raw: String): String {
        if (raw.startsWith("http://") || raw.startsWith("https://")) return raw
        val base = serverUrl.trimEnd('/')
        return if (raw.startsWith("/")) "$base$raw" else "$base/$raw"
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

    companion object {
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
    }
}
