package com.moviepilot.rustbridge

import android.content.Context
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
    @Volatile
    private var resourceCookiePrimed = false

    init {
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
        _session.value = SessionState.NeedsLogin(normalized)
        return Result.success(normalized)
    }

    /** 切换到指定历史实例。 */
    fun selectSavedServer(entry: SavedServerEntry) {
        secretStore.setActiveServerUrl(entry.url)
        resourceCookiePrimed = false
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
        val lookupId = item.tmdbId?.toString()
            ?: item.doubanId?.takeIf { it.isNotBlank() }
            ?: item.bangumiId?.toString()
            ?: item.mediaId?.takeIf { it.isNotBlank() }
            ?: return null
        val src = when {
            item.source.isNotBlank() -> item.source
            item.tmdbId != null -> "themoviedb"
            item.doubanId != null -> "douban"
            item.bangumiId != null -> "bangumi"
            else -> "themoviedb"
        }
        val resp = authedRequest(
            segments = listOf("media", lookupId),
            query = listOf("media_source" to src, "type_name" to item.type.ifBlank { "电影" }),
        ).getOrNull() ?: return null
        if (resp.status !in 200..299) return null
        val obj = extractObject(resp.body) ?: return null
        val parsed = parseMediaCard(obj) ?: return null
        if (!parsed.logoPath.isNullOrBlank()) {
            mediaLogoCache["$src:$lookupId"] = parsed.logoPath
        }
        return parsed
    }

    /** 为发现页 Hero 异步补拉透明片名 Logo（带内存缓存，与 iOS `hydrateHeroLogos` 一致）。 */
    suspend fun fetchHeroLogo(item: MediaCardItem): String? {
        if (!item.logoPath.isNullOrBlank()) return item.logoPath
        val lookupId = item.tmdbId?.toString() ?: item.mediaId ?: return null
        val key = "${item.source}:$lookupId"
        mediaLogoCache[key]?.let { return it }
        return fetchMediaDetail(item)?.logoPath
    }

    /** 拉取影视演职员列表（自动路由 TMDB / 豆瓣 / Bangumi）。 */
    suspend fun fetchMediaCredits(item: MediaCardItem): List<MediaPersonDto> {
        val typeName = item.type.ifBlank { "电影" }
        val segs = when {
            item.source.contains("douban", true) && !item.doubanId.isNullOrBlank() ->
                listOf("douban", "credits", item.doubanId, typeName)
            item.source.contains("bangumi", true) && item.bangumiId != null ->
                listOf("bangumi", "credits", item.bangumiId.toString())
            item.tmdbId != null ->
                listOf("tmdb", "credits", item.tmdbId.toString(), typeName)
            !item.doubanId.isNullOrBlank() ->
                listOf("douban", "credits", item.doubanId, typeName)
            !item.mediaId.isNullOrBlank() ->
                listOf("tmdb", "credits", item.mediaId, typeName)
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

    /** 拉取已启用媒体服务器的真实「继续观看」列表（精确还原小数进度百分比）。 */
    suspend fun fetchContinueWatching(): List<ContinueWatchingItem> {
        val servers = fetchMediaServers().filter { it.enabled }.map { it.name }.ifEmpty { listOf("Emby", "Jellyfin", "Plex") }
        val result = mutableListOf<ContinueWatchingItem>()
        for (srv in servers) {
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
                    type = obj.str("type") ?: "电视剧",
                    link = obj.str("link"),
                )
            }
            if (result.isNotEmpty()) break
        }
        return result
    }

    /** 拉取媒体服务器「最近入库」列表（用于发现页与仪表盘最近入库卡片）。 */
    suspend fun fetchMediaServerLatest(): List<MediaCardItem> {
        val servers = fetchMediaServers().filter { it.enabled }.map { it.name }.ifEmpty { listOf("Emby", "Jellyfin", "Plex") }
        for (srv in servers) {
            val resp = authedRequest(listOf("mediaserver", "latest"), query = listOf("server" to srv)).getOrNull()
            val arr = extractArray(resp?.body)
            if (arr.isNotEmpty()) {
                return arr.mapNotNull { el ->
                    val obj = el.asObj() ?: return@mapNotNull null
                    val title = obj.str("title") ?: return@mapNotNull null
                    MediaCardItem(
                        title = title,
                        year = obj.str("year") ?: obj.str("subtitle")?.take(4) ?: "",
                        type = obj.str("type") ?: "电影",
                        overview = obj.str("subtitle") ?: "",
                        posterPath = resolveImageUrl(obj.str("image"), maxWidth = 450),
                        backdropPath = resolveImageUrl(obj.str("image"), maxWidth = 900),
                        mediaId = obj.str("item_id") ?: obj.str("id"),
                        source = obj.str("server") ?: srv,
                        inLibrary = true,
                    )
                }
            }
        }
        return emptyList()
    }

    private suspend fun fetchMediaList(segments: List<String>, query: List<Pair<String, String>>): List<MediaCardItem> {
        val resp = authedRequest(segments, query = query).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { parseMediaCard(it) }
    }

    private fun parseMediaCard(el: JsonElement): MediaCardItem? {
        val obj = el.asObj() ?: return null
        val title = obj.str("title") ?: obj.str("name") ?: return null
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

        val tmdbId = obj.int("tmdb_id")
        val mediaId = obj.str("media_id") ?: obj.str("id")
        val src = obj.str("source") ?: obj.str("media_source") ?: "themoviedb"
        val cachedLogo = mediaLogoCache["$src:${tmdbId ?: mediaId}"]

        return MediaCardItem(
            title = title,
            year = obj.str("year") ?: obj.str("release_date")?.take(4) ?: obj.str("first_air_date")?.take(4) ?: "",
            type = obj.str("type") ?: "电影",
            overview = obj.str("overview") ?: obj.str("description") ?: "",
            posterPath = resolveImageUrl(obj.str("poster_path") ?: obj.str("poster") ?: obj.str("image"), maxWidth = 500),
            backdropPath = resolveImageUrl(obj.str("backdrop_path") ?: obj.str("backdrop"), maxWidth = 1080),
            voteAverage = obj.dbl("vote_average") ?: obj.dbl("vote") ?: 0.0,
            source = src,
            tmdbId = tmdbId,
            doubanId = obj.str("douban_id"),
            bangumiId = obj.int("bangumi_id"),
            mediaId = mediaId,
            logoPath = resolveImageUrl(obj.str("logo_path"), maxWidth = 720) ?: cachedLogo,
            genres = genres,
            runtime = obj.int("runtime"),
            numberOfSeasons = obj.int("number_of_seasons"),
            contentRating = obj.str("content_rating"),
            releaseDate = obj.str("release_date") ?: obj.str("first_air_date"),
            inLibrary = obj.bool("in_library") ?: false,
            popularityCount = obj.int("count") ?: 0,
            shareUser = obj.str("share_user"),
            shareComment = obj.str("share_comment"),
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

    suspend fun fetchSubscriptions(): List<SubscribeItemDto> {
        val resp = authedRequest(listOf("subscribe"), trailingSlash = true).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            SubscribeItemDto(
                id = obj.int("id") ?: 0,
                name = obj.str("name") ?: return@mapNotNull null,
                year = obj.str("year") ?: "",
                type = obj.str("type") ?: "电影",
                season = obj.int("season"),
                poster = resolveImageUrl(obj.str("poster"), maxWidth = 400),
                backdrop = resolveImageUrl(obj.str("backdrop"), maxWidth = 900),
                vote = obj.dbl("vote") ?: 0.0,
                state = obj.str("state") ?: "R",
                totalEpisode = obj.int("total_episode") ?: 0,
                lackEpisode = obj.int("lack_episode") ?: 0,
                mediaSource = obj.str("media_source") ?: "themoviedb",
                mediaId = obj.str("media_id") ?: "",
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
    }

    suspend fun fetchSubscribePopular(stype: String = "电影", page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("subscribe", "popular"), listOf("stype" to stype, "page" to page.toString()))

    suspend fun fetchSubscribeShares(page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("subscribe", "shares"), listOf("page" to page.toString()))

    suspend fun toggleSubscriptionState(id: Int, targetState: String): Boolean {
        val resp = authedRequest(
            segments = listOf("subscribe", "status", id.toString()),
            method = "PUT",
            query = listOf("state" to targetState),
        ).getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun createOrUpdateSubscription(item: SubscribeItemDto, isUpdate: Boolean = false): Boolean {
        val baseMap = runCatching {
            if (isUpdate && item.rawJson.isNotBlank()) json.parseToJsonElement(item.rawJson).asObj()?.toMutableMap() else null
        }.getOrNull() ?: mutableMapOf()
        if (item.id > 0) baseMap["id"] = JsonPrimitive(item.id)
        baseMap["name"] = JsonPrimitive(item.name)
        baseMap["year"] = JsonPrimitive(item.year)
        baseMap["type"] = JsonPrimitive(item.type)
        if (item.season != null) baseMap["season"] = JsonPrimitive(item.season) else baseMap.remove("season")
        baseMap["media_source"] = JsonPrimitive(item.mediaSource)
        if (item.mediaId.isNotBlank()) baseMap["media_id"] = JsonPrimitive(item.mediaId)
        baseMap["total_episode"] = JsonPrimitive(item.totalEpisode)
        if (item.startEpisode != null) baseMap["start_episode"] = JsonPrimitive(item.startEpisode) else baseMap.remove("start_episode")
        baseMap["quality"] = JsonPrimitive(item.quality)
        baseMap["resolution"] = JsonPrimitive(item.resolution)
        baseMap["effect"] = JsonPrimitive(item.effect)
        baseMap["best_version"] = JsonPrimitive(if (item.bestVersion) 1 else 0)
        baseMap["sites"] = JsonArray(item.sites.map { JsonPrimitive(it) })
        baseMap["filter_groups"] = JsonArray(item.filterGroups.map { JsonPrimitive(it) })
        baseMap["search_imdbid"] = JsonPrimitive(if (item.searchImdbId) 1 else 0)
        if (item.searchInterval != null) baseMap["search_interval"] = JsonPrimitive(item.searchInterval) else baseMap.remove("search_interval")
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
        ).getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun deleteSubscription(id: Int): Boolean {
        val resp = authedRequest(listOf("subscribe", id.toString()), method = "DELETE").getOrNull()
        return resp != null && resp.status in 200..299
    }

    // ==================== 站点资源（Rust 9 维筛选分组） & 下载 ====================

    suspend fun searchResources(keyword: String, siteIds: List<Int> = emptyList()): List<ResourceItemDto> {
        fun parseItems(body: String?): List<ResourceItemDto> = extractArray(body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val torrent = obj["torrent_info"].asObj() ?: obj
            val meta = obj["meta_info"].asObj()
            val media = obj["media_info"].asObj()
            ResourceItemDto(
                id = torrent.str("id") ?: torrent.str("enclosure") ?: torrent.str("title") ?: "",
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

    suspend fun fetchDownloads(): List<DownloadTaskDto> {
        val resp = authedRequest(listOf("download"), trailingSlash = true).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val media = obj["media"].asObj()
            DownloadTaskDto(
                hash = obj.str("hash") ?: "",
                downloader = obj.str("downloader") ?: "qBittorrent",
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
                srcStorage = srcFile?.str("storage") ?: "local",
                destStorage = destFile?.str("storage") ?: "local",
                sizeBytes = srcFile?.lng("size") ?: 0L,
                image = resolveImageUrl(obj.str("image"), maxWidth = 320),
            )
        }
        return (if (total > 0) total else list.size) to list
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

    // ==================== 仪表盘 / 定时服务 / 插件图表 / 系统日志 ====================

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

        return DashboardStatsDto(
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
            ServiceConfigDto(
                name = obj.str("name") ?: return@mapNotNull null,
                type = obj.str("type") ?: "",
                enabled = obj.bool("enabled") ?: true,
                switchs = obj["switchs"].asArr()?.mapNotNull { it.asPrim()?.content?.takeIf { s -> s != "null" } } ?: emptyList(),
            )
        }
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
            )
        }
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
            )
        }.distinctBy { it.id }
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
        val items = rawItems.mapNotNull { el ->
            val obj = el.asObj() ?: return@mapNotNull null
            val itemId = obj.str("item_id") ?: obj.str("id") ?: return@mapNotNull null
            val rawImg = obj.str("poster")
                ?: obj.str("thumb")
                ?: obj.str("image")
                ?: obj.str("poster_path")
                ?: obj.str("backdrop")
                ?: obj.str("backdrop_path")
            val useCookies = obj.bool("use_cookies") == true
            MediaServerBrowseItemDto(
                itemId = itemId,
                title = obj.str("title") ?: obj.str("name") ?: "未命名条目",
                subtitle = obj.str("subtitle") ?: obj.str("artist") ?: obj.str("album").orEmpty(),
                type = obj.str("item_type") ?: obj.str("type").orEmpty(),
                year = obj.str("year").orEmpty(),
                imageUrl = resolveImageUrl(rawImg, maxWidth = 480, useCookies = useCookies),
                server = obj.str("server") ?: server,
                serverType = obj.str("server_type").orEmpty(),
                played = obj.bool("is_played") ?: obj.bool("played") ?: false,
                userRating = obj.dbl("rating") ?: obj.dbl("vote_average") ?: obj.dbl("community_rating") ?: 0.0,
                unplayedCount = obj.int("unplayed_count"),
                tmdbId = obj.int("tmdbid") ?: obj.int("tmdb_id"),
                mediaId = obj.str("media_id"),
            )
        }
        return MediaServerBrowsePageDto(items = items, totalCount = total, hasMore = hasMore)
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
    }
}
