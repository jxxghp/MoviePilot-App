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
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.net.URLEncoder

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
 * - 底层传输通过 Android 原生 OkHttp（ADR-01），凭据通过 Android Keystore（ADR-02）。
 */
class MoviePilotRepository(context: Context) {
    val secretStore = NativeSecretStore(context)
    val transport = NativeHttpTransport(allowSelfSignedTls = { secretStore.allowSelfSignedTls })
    val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }

    private val _session = MutableStateFlow<SessionState>(SessionState.Unconnected)
    val session: StateFlow<SessionState> = _session.asStateFlow()

    private val _savedServers = MutableStateFlow(secretStore.loadServers())
    val savedServers: StateFlow<List<SavedServerEntry>> = _savedServers.asStateFlow()

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

    /** 返回连接服务页（可切换或新增实例）。 */
    fun openServerConnection() {
        _session.value = SessionState.Unconnected
    }

    /** 忘记指定历史实例并清除其 Keystore 凭据。 */
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

        val root = runCatching { json.parseToJsonElement(resp.body).jsonObject }.getOrNull()
        if (resp.status == 401) {
            val mfa = root?.get("data")?.jsonObject?.get("mfa_methods")?.jsonArray
            if (mfa != null && mfa.isNotEmpty()) {
                return LoginOutcome.OtpRequired("该账号已启用动态口令（OTP），请输入 6 位验证码")
            }
            val msg = root?.str("detail") ?: root?.str("message") ?: "用户名、密码或验证码错误"
            return LoginOutcome.Failure(msg)
        }
        if (resp.status !in 200..299 || root == null) {
            return LoginOutcome.Failure("登录失败（HTTP ${resp.status}）")
        }

        val token = root.str("access_token") ?: root["data"]?.jsonObject?.str("access_token")
        if (token.isNullOrBlank()) {
            return LoginOutcome.Failure("服务端未返回有效访问令牌")
        }

        val superUser = root["super_user"]?.jsonPrimitive?.booleanOrNull ?: true
        val userName = root.str("user_name") ?: username.trim()
        val avatar = root.str("avatar")
        val permsJson = root["permissions"]?.toString() ?: "{}"

        // 拉取完整 /user/current 以获取权威权限与头像
        val identityResp = runCatching {
            val meUrl = RustCoreBridge.buildEndpointUrl(serverUrl, listOf("user", "current"))
            transport.execute(url = meUrl, method = "GET", token = token)
        }.getOrNull()

        var identity = UserIdentity(name = userName, isSuperuser = superUser, avatar = avatar)
        var permissions = RustCoreBridge.evaluatePermissions(permsJson, superUser)

        if (identityResp != null && identityResp.status == 200) {
            val meRoot = runCatching { json.parseToJsonElement(identityResp.body).jsonObject }.getOrNull()
            val dataObj = meRoot?.get("data")?.jsonObject ?: meRoot
            if (dataObj != null) {
                val isSu = dataObj["is_superuser"]?.jsonPrimitive?.booleanOrNull ?: superUser
                identity = UserIdentity(
                    id = dataObj["id"]?.jsonPrimitive?.intOrNull ?: 0,
                    name = dataObj.str("name") ?: userName,
                    email = dataObj.str("email") ?: "",
                    isSuperuser = isSu,
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
        _session.value = SessionState.Authenticated(serverUrl, token, identity, permissions)
        return LoginOutcome.Success(identity)
    }

    /** 主动登出或 401 自动失效清理。 */
    fun logout(notice: String? = null) {
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
        val url = RustCoreBridge.buildEndpointUrl(auth.serverUrl, segments, query, trailingSlash)
        val resp = runCatching {
            transport.execute(url = url, method = method, token = auth.token, body = body)
        }.getOrElse { return Result.failure(it) }

        if (RustCoreBridge.classifyAuthStatus(resp.status, resp.body) == "logout") {
            logout("登录状态已过期，请重新登录")
            return Result.failure(IllegalStateException("登录状态已过期"))
        }
        return Result.success(resp)
    }

    /** 解析图片绝对地址（兼容相对路径、反代子路径与 TMDB 短路径）。 */
    fun resolveImageUrl(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        if (raw.startsWith("http://") || raw.startsWith("https://")) return raw
        if (raw.startsWith("/")) {
            val auth = _session.value as? SessionState.Authenticated
            if (raw.startsWith("/api/") && auth != null) {
                return "${auth.serverUrl}$raw"
            }
            return "https://image.tmdb.org/t/p/w500$raw"
        }
        return raw
    }

    // ==================== 发现 / 探索 / 搜索 / 详情 ====================

    suspend fun fetchDiscoverTrending(page: Int = 1): List<MediaCardItem> =
        fetchMediaList(listOf("recommend", "tmdb_trending"), listOf("page" to page.toString()))

    suspend fun fetchExplore(source: String, page: Int = 1, genre: String? = null, sort: String? = null): List<MediaCardItem> {
        val query = mutableListOf("page" to page.toString())
        if (!genre.isNullOrBlank() && genre != "全部类型") query += "with_genres" to genre
        if (!sort.isNullOrBlank()) query += "sort_by" to sort
        return fetchMediaList(listOf("discover", source), query)
    }

    suspend fun searchMedia(keyword: String, kind: String = "media", page: Int = 1): List<MediaCardItem> {
        if (keyword.isBlank()) return emptyList()
        return fetchMediaList(
            listOf("media", "search"),
            listOf("title" to keyword, "type" to kind, "page" to page.toString(), "count" to "20"),
        )
    }

    suspend fun fetchContinueWatching(): List<ContinueWatchingItem> {
        val resp = authedRequest(listOf("mediaserver", "playing")).getOrNull()
        val arr = extractArray(resp?.body)
        if (arr.isNotEmpty()) {
            return arr.mapNotNull { el ->
                val obj = el as? JsonObject ?: return@mapNotNull null
                ContinueWatchingItem(
                    id = obj.str("id") ?: obj.str("item_id") ?: "",
                    title = obj.str("title") ?: obj.str("name") ?: "",
                    subtitle = obj.str("subtitle") ?: obj.str("episode_title") ?: "",
                    image = resolveImageUrl(obj.str("image") ?: obj.str("backdrop_path")),
                    percent = obj["percent"]?.jsonPrimitive?.intOrNull ?: 35,
                    server = obj.str("server") ?: "Emby",
                    type = obj.str("type") ?: "电视剧",
                )
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
        val obj = el as? JsonObject ?: return null
        val title = obj.str("title") ?: obj.str("name") ?: return null
        return MediaCardItem(
            title = title,
            year = obj.str("year") ?: obj.str("release_date")?.take(4) ?: "",
            type = obj.str("type") ?: "电影",
            overview = obj.str("overview") ?: obj.str("description") ?: "",
            posterPath = resolveImageUrl(obj.str("poster_path") ?: obj.str("poster") ?: obj.str("image")),
            backdropPath = resolveImageUrl(obj.str("backdrop_path") ?: obj.str("backdrop")),
            voteAverage = obj["vote_average"]?.jsonPrimitive?.doubleOrNull
                ?: obj["vote"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
            source = obj.str("source") ?: obj.str("media_source") ?: "themoviedb",
            tmdbId = obj["tmdb_id"]?.jsonPrimitive?.intOrNull,
            doubanId = obj.str("douban_id"),
            bangumiId = obj["bangumi_id"]?.jsonPrimitive?.intOrNull,
            mediaId = obj.str("media_id") ?: obj.str("id"),
            logoPath = resolveImageUrl(obj.str("logo_path")),
            inLibrary = obj["in_library"]?.jsonPrimitive?.booleanOrNull ?: false,
        )
    }

    // ==================== 订阅 / 日历 / 社区 ====================

    suspend fun fetchSubscriptions(): List<SubscribeItemDto> {
        val resp = authedRequest(listOf("subscribe"), trailingSlash = true).getOrNull() ?: return emptyList()
        if (resp.status !in 200..299) return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            SubscribeItemDto(
                id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
                name = obj.str("name") ?: return@mapNotNull null,
                year = obj.str("year") ?: "",
                type = obj.str("type") ?: "电影",
                season = obj["season"]?.jsonPrimitive?.intOrNull,
                poster = resolveImageUrl(obj.str("poster")),
                backdrop = resolveImageUrl(obj.str("backdrop")),
                vote = obj["vote"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                state = obj.str("state") ?: "R",
                totalEpisode = obj["total_episode"]?.jsonPrimitive?.intOrNull ?: 0,
                lackEpisode = obj["lack_episode"]?.jsonPrimitive?.intOrNull ?: 0,
                mediaSource = obj.str("media_source") ?: "themoviedb",
                mediaId = obj.str("media_id") ?: "",
                quality = obj.str("quality") ?: "",
                resolution = obj.str("resolution") ?: "",
                effect = obj.str("effect") ?: "",
                savePath = obj.str("save_path") ?: "",
                include = obj.str("include") ?: "",
                exclude = obj.str("exclude") ?: "",
            )
        }
    }

    suspend fun createOrUpdateSubscription(item: SubscribeItemDto, isUpdate: Boolean = false): Boolean {
        val payload = """{"id":${item.id},"name":"${esc(item.name)}","year":"${esc(item.year)}","type":"${esc(item.type)}","season":${item.season ?: "null"},"media_source":"${esc(item.mediaSource)}","media_id":"${esc(item.mediaId)}","quality":"${esc(item.quality)}","resolution":"${esc(item.resolution)}","effect":"${esc(item.effect)}","save_path":"${esc(item.savePath)}","include":"${esc(item.include)}","exclude":"${esc(item.exclude)}"}"""
        val resp = authedRequest(
            segments = listOf("subscribe"),
            method = if (isUpdate) "PUT" else "POST",
            body = payload,
            trailingSlash = true,
        ).getOrNull()
        return resp != null && resp.status in 200..299
    }

    suspend fun deleteSubscription(id: Int): Boolean {
        val resp = authedRequest(listOf("subscribe", id.toString()), method = "DELETE").getOrNull()
        return resp != null && resp.status in 200..299
    }

    // ==================== 站点资源（Rust 9 维筛选分组） & 下载 ====================

    suspend fun searchResources(keyword: String): List<ResourceItemDto> {
        val resp = authedRequest(
            segments = listOf("search", "title"),
            query = if (keyword.isBlank()) emptyList() else listOf("keyword" to keyword),
        ).getOrNull()
        val arr = extractArray(resp?.body)
        if (arr.isNotEmpty()) {
            return arr.mapNotNull { el ->
                val obj = el as? JsonObject ?: return@mapNotNull null
                val torrent = obj["torrent_info"]?.jsonObject ?: obj
                val meta = obj["meta_info"]?.jsonObject
                ResourceItemDto(
                    id = torrent.str("id") ?: torrent.str("enclosure") ?: torrent.str("title") ?: "",
                    title = torrent.str("title") ?: return@mapNotNull null,
                    siteName = torrent.str("site_name") ?: "站点",
                    size = torrent["size"]?.jsonPrimitive?.longOrNull ?: 0L,
                    seeders = torrent["seeders"]?.jsonPrimitive?.intOrNull ?: 0,
                    peers = torrent["peers"]?.jsonPrimitive?.intOrNull ?: 0,
                    resourcePix = meta?.str("resource_pix") ?: torrent.str("resource_pix") ?: "2160p",
                    resourceType = meta?.str("resource_type") ?: torrent.str("resource_type") ?: "WEB-DL",
                    videoEncode = meta?.str("video_encode") ?: torrent.str("video_encode") ?: "HEVC",
                    audioEncode = meta?.str("audio_encode") ?: torrent.str("audio_encode") ?: "AAC",
                    resourceTeam = meta?.str("resource_team") ?: torrent.str("resource_team") ?: "",
                    edition = meta?.str("edition") ?: torrent.str("edition") ?: "WEB-DL",
                    downloadvolumefactor = torrent["downloadvolumefactor"]?.jsonPrimitive?.doubleOrNull ?: 1.0,
                    uploadvolumefactor = torrent["uploadvolumefactor"]?.jsonPrimitive?.doubleOrNull ?: 1.0,
                    labels = torrent["labels"]?.jsonArray?.mapNotNull { it.jsonPrimitive.content } ?: emptyList(),
                    description = torrent.str("description") ?: "",
                    enclosure = torrent.str("enclosure") ?: "",
                )
            }
        }
        return emptyList()
    }

    /** 将原始资源列表交由 Rust `filter_and_group_resources` 完成 9 维级联筛选与同规格合并。 */
    fun filterResourcesWithRust(items: List<ResourceItemDto>, criteriaJson: String = ""): ResourceFilterResultDto {
        val rawJson = json.encodeToString(kotlinx.serialization.builtins.ListSerializer(ResourceItemDto.serializer()), items)
        val outJson = RustCoreBridge.filterResources(rawJson, criteriaJson)
        return runCatching { json.decodeFromString<ResourceFilterResultDto>(outJson) }
            .getOrDefault(ResourceFilterResultDto())
    }

    suspend fun fetchDownloads(): List<DownloadTaskDto> {
        val resp = authedRequest(listOf("download"), trailingSlash = true).getOrNull() ?: return emptyList()
        return extractArray(resp.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val media = obj["media"]?.jsonObject
            DownloadTaskDto(
                hash = obj.str("hash") ?: "",
                downloader = obj.str("downloader") ?: "qBittorrent",
                title = obj.str("title") ?: return@mapNotNull null,
                name = obj.str("name") ?: media?.str("title") ?: obj.str("title") ?: "",
                year = obj.str("year") ?: "",
                seasonEpisode = obj.str("season_episode") ?: "",
                siteName = obj.str("site_name") ?: "",
                size = obj["size"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                progress = obj["progress"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                state = obj.str("state") ?: "downloading",
                upspeed = obj.str("upspeed") ?: "0 B/s",
                dlspeed = obj.str("dlspeed") ?: "0 B/s",
                leftTime = obj.str("left_time") ?: "",
                poster = resolveImageUrl(media?.str("poster") ?: media?.str("backdrop")),
            )
        }
    }

    // ==================== 文件 / 整理历史 ====================

    suspend fun fetchFiles(storage: String = "local", path: String = "/"): List<StorageFileDto> {
        val body = """{"storage":"${esc(storage)}","path":"${esc(path)}","type":"dir"}"""
        val resp = authedRequest(listOf("storage", "list"), method = "POST", body = body).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            StorageFileDto(
                storage = obj.str("storage") ?: storage,
                type = obj.str("type") ?: "file",
                path = obj.str("path") ?: "",
                name = obj.str("name") ?: return@mapNotNull null,
                extension = obj.str("extension"),
                size = obj["size"]?.jsonPrimitive?.longOrNull ?: 0L,
                modifyTime = obj.str("modify_time") ?: "",
            )
        }
    }

    suspend fun fetchTransferHistory(search: String = ""): List<TransferHistoryDto> {
        val query = if (search.isBlank()) listOf("page" to "1", "count" to "50") else listOf("title" to search, "page" to "1", "count" to "50")
        val resp = authedRequest(listOf("history", "transfer"), query = query).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            TransferHistoryDto(
                id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
                title = obj.str("title") ?: return@mapNotNull null,
                type = obj.str("type") ?: "电影",
                year = obj.str("year") ?: "",
                seasons = obj.str("seasons") ?: "",
                episodes = obj.str("episodes") ?: "",
                status = obj["status"]?.jsonPrimitive?.booleanOrNull ?: true,
                mode = obj.str("mode") ?: "copy",
                date = obj.str("date") ?: "",
                errmsg = obj.str("errmsg"),
                src = obj.str("src") ?: "",
                dest = obj.str("dest") ?: "",
                image = resolveImageUrl(obj.str("image")),
            )
        }
    }

    // ==================== 仪表盘 / 站点 / 工作流 / 插件 / 消息 ====================

    suspend fun fetchDashboardStats(): DashboardStatsDto {
        val statResp = authedRequest(listOf("dashboard", "statistic")).getOrNull()
        val storageResp = authedRequest(listOf("dashboard", "storage")).getOrNull()
        val dlResp = authedRequest(listOf("dashboard", "downloader")).getOrNull()

        val statObj = extractObject(statResp?.body)
        val storageObj = extractObject(storageResp?.body)
        val dlObj = extractObject(dlResp?.body)

        return DashboardStatsDto(
            movieCount = statObj?.get("movie_count")?.jsonPrimitive?.intOrNull ?: 0,
            tvCount = statObj?.get("tv_count")?.jsonPrimitive?.intOrNull ?: 0,
            episodeCount = statObj?.get("episode_count")?.jsonPrimitive?.intOrNull,
            musicCount = statObj?.get("music_count")?.jsonPrimitive?.intOrNull ?: 0,
            movieCountMonth = statObj?.get("movie_count_month")?.jsonPrimitive?.intOrNull ?: 0,
            tvCountMonth = statObj?.get("tv_count_month")?.jsonPrimitive?.intOrNull ?: 0,
            episodeCountMonth = statObj?.get("episode_count_month")?.jsonPrimitive?.intOrNull ?: 0,
            musicCountMonth = statObj?.get("music_count_month")?.jsonPrimitive?.intOrNull ?: 0,
            usedBytes = storageObj?.get("used_storage")?.jsonPrimitive?.doubleOrNull ?: 0.0,
            totalBytes = storageObj?.get("total_storage")?.jsonPrimitive?.doubleOrNull ?: 0.0,
            downloadSpeed = dlObj?.get("download_speed")?.jsonPrimitive?.doubleOrNull ?: 0.0,
            uploadSpeed = dlObj?.get("upload_speed")?.jsonPrimitive?.doubleOrNull ?: 0.0,
            totalDownloadBytes = dlObj?.get("download_size")?.jsonPrimitive?.doubleOrNull ?: 0.0,
        )
    }

    suspend fun fetchSites(): List<SiteItemDto> {
        val resp = authedRequest(listOf("site"), trailingSlash = true).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            SiteItemDto(
                id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
                name = obj.str("name") ?: return@mapNotNull null,
                domain = obj.str("domain") ?: "",
                url = obj.str("url") ?: "",
                pri = obj["pri"]?.jsonPrimitive?.intOrNull ?: 0,
                isActive = obj["is_active"]?.jsonPrimitive?.booleanOrNull ?: true,
                uploadBytes = obj["upload"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                downloadBytes = obj["download"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                ratio = obj["ratio"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                seedingCount = obj["seeding"]?.jsonPrimitive?.intOrNull ?: 0,
            )
        }
    }

    suspend fun fetchWorkflows(): List<WorkflowItemDto> {
        val resp = authedRequest(listOf("workflow"), trailingSlash = true).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val actions = obj["actions"]?.jsonArray?.mapIndexedNotNull { idx, a ->
                val ao = a as? JsonObject ?: return@mapIndexedNotNull null
                val pos = ao["position"]?.jsonObject
                WorkflowActionDto(
                    id = ao.str("id") ?: "act-$idx",
                    type = ao.str("type") ?: "Action",
                    name = ao.str("name") ?: "动作节点",
                    description = ao.str("description") ?: "",
                    x = pos?.get("x")?.jsonPrimitive?.doubleOrNull?.toFloat() ?: (idx * 240f + 40f),
                    y = pos?.get("y")?.jsonPrimitive?.doubleOrNull?.toFloat() ?: (idx * 120f + 60f),
                    paramCount = ao["data"]?.jsonObject?.size ?: 0,
                )
            } ?: emptyList()
            val flows = obj["flows"]?.jsonArray?.mapNotNull { f ->
                val fo = f as? JsonObject ?: return@mapNotNull null
                WorkflowFlowEdgeDto(
                    source = fo.str("source") ?: return@mapNotNull null,
                    target = fo.str("target") ?: return@mapNotNull null,
                )
            } ?: emptyList()
            WorkflowItemDto(
                id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
                name = obj.str("name") ?: return@mapNotNull null,
                description = obj.str("description") ?: "",
                timer = obj.str("timer") ?: "",
                state = obj.str("state") ?: "P",
                runCount = obj["run_count"]?.jsonPrimitive?.intOrNull ?: 0,
                actions = actions,
                flows = flows,
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
            val obj = el as? JsonObject ?: return@mapNotNull null
            PluginItemDto(
                id = obj.str("id") ?: return@mapNotNull null,
                name = obj.str("plugin_name") ?: obj.str("id") ?: "",
                desc = obj.str("plugin_desc") ?: "",
                version = obj.str("plugin_version") ?: "1.0.0",
                author = obj.str("plugin_author") ?: "",
                icon = resolveImageUrl(obj.str("plugin_icon")),
                installed = obj["installed"]?.jsonPrimitive?.booleanOrNull ?: installedOnly,
                state = obj["state"]?.jsonPrimitive?.booleanOrNull ?: false,
                hasPage = obj["has_page"]?.jsonPrimitive?.booleanOrNull ?: false,
                renderMode = obj.str("render_mode") ?: "vuetify",
            )
        }
    }

    suspend fun fetchPluginFormJson(pluginId: String): String? {
        val resp = authedRequest(listOf("plugin", "form", pluginId)).getOrNull() ?: return null
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

    suspend fun fetchMessages(): List<SystemMessageDto> {
        val resp = authedRequest(listOf("message", "web"), query = listOf("page" to "1", "size" to "30")).getOrNull()
        return extractArray(resp?.body).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            SystemMessageDto(
                id = obj.str("id") ?: obj.str("reg_time") ?: "",
                title = obj.str("title") ?: "系统消息",
                text = obj.str("text") ?: obj.str("content") ?: "",
                date = obj.str("reg_time") ?: obj.str("date") ?: "",
                category = obj.str("mtype") ?: "系统",
                image = resolveImageUrl(obj.str("image")),
            )
        }
    }

    /** 发起 AI 智能助手 SSE 流式对话（经 OkHttp + Rust NativeSseParser 解析）。 */
    fun streamAgentChat(prompt: String, sessionId: String = "android-default"): Flow<SseEventFfi>? {
        val auth = _session.value as? SessionState.Authenticated ?: return null
        val url = RustCoreBridge.buildEndpointUrl(auth.serverUrl, listOf("agent", "chat"))
        val body = """{"message":"${esc(prompt)}","session_id":"${esc(sessionId)}"}"""
        return transport.streamSse(url, auth.token, body)
    }

    // ==================== JSON 解析工具 ====================

    private fun extractArray(body: String?): List<JsonElement> {
        if (body.isNullOrBlank()) return emptyList()
        val root = runCatching { json.parseToJsonElement(body) }.getOrNull() ?: return emptyList()
        return when (root) {
            is JsonArray -> root
            is JsonObject -> {
                val data = root["data"]
                when (data) {
                    is JsonArray -> data
                    is JsonObject -> data["list"]?.jsonArray ?: data["items"]?.jsonArray ?: emptyList()
                    else -> root["list"]?.jsonArray ?: root["items"]?.jsonArray ?: emptyList()
                }
            }
            else -> emptyList()
        }
    }

    private fun extractObject(body: String?): JsonObject? {
        if (body.isNullOrBlank()) return null
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull() ?: return null
        return root["data"]?.jsonObject ?: root
    }

    private fun JsonObject.str(key: String): String? {
        val prim = this[key] as? JsonPrimitive ?: return null
        return if (prim.content == "null") null else prim.content
    }

    private fun esc(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
}
