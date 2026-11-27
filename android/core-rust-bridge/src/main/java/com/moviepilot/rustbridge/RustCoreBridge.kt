package com.moviepilot.rustbridge

import com.moviepilot.rustcore.CronSummaryFfi
import com.moviepilot.rustcore.JwtClaimsFfi
import com.moviepilot.rustcore.MarkdownBlockFfi
import com.moviepilot.rustcore.MedalPaletteFfi
import com.moviepilot.rustcore.NativeSseParser
import com.moviepilot.rustcore.PermissionsFfi
import com.moviepilot.rustcore.StrmStreamFfi
import com.moviepilot.rustcore.SubscribeProgressFfi
import com.moviepilot.rustcore.analyzeCronExpression
import com.moviepilot.rustcore.applyPluginFormPatch
import com.moviepilot.rustcore.buildExternalPlayerUrl
import com.moviepilot.rustcore.buildOauthAuthorizeUrl
import com.moviepilot.rustcore.buildOauthDiscoveryUrlsJson
import com.moviepilot.rustcore.buildPluginRemoteCacheKeyJson
import com.moviepilot.rustcore.buildV3EndpointUrl
import com.moviepilot.rustcore.classifyHttpAuthStatus
import com.moviepilot.rustcore.computeMedalPalette
import com.moviepilot.rustcore.computePkceS256Challenge
import com.moviepilot.rustcore.computeSubscribeProgress
import com.moviepilot.rustcore.coreVersion
import com.moviepilot.rustcore.decodeJwtTokenClaims
import com.moviepilot.rustcore.detectCloudflareAccessChallengeJson
import com.moviepilot.rustcore.detectPlayableMediaKind
import com.moviepilot.rustcore.evaluatePluginExpression
import com.moviepilot.rustcore.evaluateUserPermissions
import com.moviepilot.rustcore.filterAndGroupResources
import com.moviepilot.rustcore.generatePkcePairJson
import com.moviepilot.rustcore.isPasskeySecureOrigin as ffiIsPasskeySecureOrigin
import com.moviepilot.rustcore.isSameHttpOrigin
import com.moviepilot.rustcore.mergeCfAccessCookie
import com.moviepilot.rustcore.normalizeDanmakuQueryTitle
import com.moviepilot.rustcore.normalizeOauthResourceUrl
import com.moviepilot.rustcore.normalizePendingPlaybackStopsJson
import com.moviepilot.rustcore.normalizePluginRemoteEntryJson
import com.moviepilot.rustcore.normalizeServerAddress
import com.moviepilot.rustcore.parseAgentMarkdown
import com.moviepilot.rustcore.parseAudioEmbeddedMetadata as ffiParseAudioEmbeddedMetadata
import com.moviepilot.rustcore.parseDeepLinkJson
import com.moviepilot.rustcore.parseOauthCallbackUrlJson
import com.moviepilot.rustcore.parseOauthServerMetadataJson
import com.moviepilot.rustcore.parsePasskeyProviderEnabled as ffiParsePasskeyProviderEnabled
import com.moviepilot.rustcore.parseProtectedResourceMetadataDetailJson
import com.moviepilot.rustcore.parseProtectedResourceMetadataJson
import com.moviepilot.rustcore.parseStrmContent
import com.moviepilot.rustcore.planPlaybackRoutesJson
import com.moviepilot.rustcore.planPlaybackSyncStepJson
import com.moviepilot.rustcore.planPluginFormJson
import com.moviepilot.rustcore.prepareDanmakuTimelineJson
import com.moviepilot.rustcore.preparePasskeyRequestJson as ffiPreparePasskeyRequestJson
import com.moviepilot.rustcore.rebaseInstanceApiUrl as ffiRebaseInstanceApiUrl
import com.moviepilot.rustcore.resolvePlaybackEngineJson
import com.moviepilot.rustcore.resolvePluginRemoteUpstreamJson
import com.moviepilot.rustcore.serverAddressContains
import com.moviepilot.rustcore.supportsPasskeyFrontendMarker as ffiSupportsPasskeyFrontendMarker
import com.moviepilot.rustcore.validatePluginBridgeApiPath
import com.moviepilot.rustcore.validatePluginShellAsset
import com.moviepilot.rustcore.verifyPasskeyCallbackJson as ffiVerifyPasskeyCallbackJson
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest

/**
 * Rust 共享业务内核统一 Kotlin 门面：所有无 UI 核心逻辑（路由解析、SSE 流、9 维筛选分组、
 * JWT/RBAC 权限判定、动态插件表单规划与无损补丁、Cron 摘要、3D 勋章配色）全部委托 UniFFI。
 */
/** 解析出的 `.strm` 直链播放规格（含可选安全请求头与推断出的音视频模式）。 */
data class ParsedStrmStream(
    val url: String,
    val headers: Map<String, String> = emptyMap(),
    val mediaKind: String = "video",
)

/** 音频内嵌元数据解析结果（FLAC / ID3v2 / MP4·M4A / Ogg Vorbis·Opus）。 */
data class AudioEmbeddedMetadataDto(
    val title: String? = null,
    val artist: String? = null,
    val album: String? = null,
    val lyrics: String? = null,
    val coverMime: String? = null,
    val coverBytes: ByteArray? = null,
    val neededHeadBytes: Long? = null,
    val neededTailBytes: Long? = null,
)

@Serializable
data class PluginRemoteCacheKeyDto(
    @SerialName("instance_hash") val instanceHash: String,
    @SerialName("plugin_id_lower") val pluginIdLower: String,
    @SerialName("version_segment") val versionSegment: String,
    @SerialName("relative_dir") val relativeDir: String,
)

@Serializable
data class PluginRemoteEntryPlanDto(
    @SerialName("plugin_id") val pluginId: String,
    @SerialName("version_tag") val versionTag: String,
    @SerialName("virtual_entry_path") val virtualEntryPath: String,
    @SerialName("upstream_file_path") val upstreamFilePath: String,
)

@Serializable
data class PluginRemoteUpstreamTargetDto(
    @SerialName("plugin_id") val pluginId: String,
    @SerialName("version_tag") val versionTag: String,
    @SerialName("asset_rel_path") val assetRelPath: String,
    @SerialName("upstream_api_path") val upstreamApiPath: String,
)

@Serializable
data class DanmakuItemDto(
    @SerialName("time_ms") val timeMs: Long,
    val mode: Int = 1,
    @SerialName("color_rgb") val colorRgb: Int = 0xFFFFFF,
    val text: String,
    @SerialName("repeat_count") val repeatCount: Int = 1,
)

@Serializable
data class DanmakuFilterOptionsDto(
    @SerialName("allow_scroll") val allowScroll: Boolean = true,
    @SerialName("allow_top") val allowTop: Boolean = true,
    @SerialName("allow_bottom") val allowBottom: Boolean = true,
    @SerialName("allow_color") val allowColor: Boolean = true,
    @SerialName("merge_duplicates") val mergeDuplicates: Boolean = true,
    @SerialName("merge_window_ms") val mergeWindowMs: Long = 3000L,
    @SerialName("max_per_second") val maxPerSecond: Int = 12,
    @SerialName("block_keywords") val blockKeywords: List<String> = emptyList(),
    @SerialName("offset_ms") val offsetMs: Long = 0L,
)

@Serializable
data class PreparedDanmakuTimelineDto(
    @SerialName("raw_count") val rawCount: Int = 0,
    @SerialName("filtered_count") val filteredCount: Int = 0,
    val items: List<DanmakuItemDto> = emptyList(),
)

@Serializable
data class CloudflareChallengeDto(
    val isChallenge: Boolean = false,
    val reason: String = "",
    val resourceMetadataUrl: String? = null,
    val loginUrl: String? = null,
)

@Serializable
data class PkcePairDto(
    val codeVerifier: String = "",
    val codeChallenge: String = "",
    val codeChallengeMethod: String = "S256",
    val state: String = "",
)

@Serializable
data class ProtectedResourceMetadataDto(
    val resource: String? = null,
    val authorizationServers: List<String> = emptyList(),
)

@Serializable
data class OAuthServerMetadataDto(
    val issuer: String = "",
    val authorizationEndpoint: String = "",
    val tokenEndpoint: String = "",
    val registrationEndpoint: String? = null,
)

@Serializable
data class OAuthCallbackResultDto(
    val valid: Boolean = false,
    val stateMatched: Boolean = false,
    val code: String? = null,
    val error: String? = null,
    val errorDescription: String? = null,
)

@Serializable
data class PreparedPasskeyRequestDto(
    val authorizationUrl: String = "",
    val state: String = "",
    val challenge: String = "",
    val transactionToken: String = "",
    val timeoutSecs: Long = 120L,
)

@Serializable
data class PasskeyCallbackOutcomeDto(
    val ok: Boolean = false,
    val finishBodyJson: String? = null,
    val errorCode: String? = null,
    val errorMessageZh: String? = null,
)

object RustCoreBridge {

    /** 返回 Rust 共享内核版本号，用于启动冒烟检查与关于页展示。 */
    fun version(): String = runCatching { coreVersion() }.getOrDefault("2.0.3")

    /** 规范化 MoviePilot 服务地址，保留部署子路径并拒绝内嵌凭据。 */
    fun normalizeAddress(raw: String): Result<String> = runCatching {
        normalizeServerAddress(raw)
    }.recoverCatching { err ->
        if (err is UnsatisfiedLinkError || err is NoClassDefFoundError) {
            fallbackNormalizeAddress(raw)
        } else {
            throw err
        }
    }

    /** 校验目标 URL 是否严格属于当前实例源及部署子路径。 */
    fun containsUrl(baseUrl: String, candidateUrl: String): Boolean =
        runCatching { serverAddressContains(baseUrl, candidateUrl) }
            .getOrElse { fallbackContainsUrl(baseUrl, candidateUrl) }

    /** 将反代环境下协议或主机失配的 `/api/v1/...` 地址安全重绑到当前已验证实例根地址；非 `/api/v1/` 跨源直链返回 `null`。 */
    fun rebaseInstanceApiUrl(baseUrl: String, rawUrl: String): String? =
        runCatching { ffiRebaseInstanceApiUrl(baseUrl, rawUrl) }
            .getOrElse { fallbackRebaseInstanceApiUrl(baseUrl, rawUrl) }

    /** 构造安全的 `/api/v1/...` 完整端点 URL。 */
    fun buildEndpointUrl(
        baseUrl: String,
        segments: List<String>,
        query: List<Pair<String, String>> = emptyList(),
        trailingSlash: Boolean = false,
    ): String {
        val queryJson = if (query.isEmpty()) {
            ""
        } else {
            query.joinToString(prefix = "[", postfix = "]") { (k, v) ->
                "[\"${escapeJson(k)}\",\"${escapeJson(v)}\"]"
            }
        }
        return buildV3EndpointUrl(baseUrl, segments, queryJson, trailingSlash)
    }

    /** 解析 `moviepilot://` 或 Web 路径为 JSON 路由对象。 */
    fun parseDeepLink(rawUrl: String): String? =
        runCatching { parseDeepLinkJson(rawUrl) }.getOrNull()

    /** 判别本地或远端媒体路径是否支持原生播放（`video` / `audio` / `null`）。 */
    fun detectMediaKind(pathOrExt: String, includeStreaming: Boolean = false): String? =
        runCatching { detectPlayableMediaKind(pathOrExt, includeStreaming) }
            .getOrElse { fallbackDetectMediaKind(pathOrExt, includeStreaming) }

    /** 判断文件名或路径是否为 `.strm` 直链描述文件。 */
    fun isStrmPath(pathOrName: String): Boolean {
        val trimmed = pathOrName.trim().trimStart('.')
        val ext = if ('.' in trimmed) trimmed.substringAfterLast('.') else trimmed
        return ext.equals("strm", ignoreCase = true)
    }

    /** 解析 `.strm` 文本内容，优先调用 Rust 内核并在宿主机 JVM 单测未加载 JNI 时无缝回退同构解析。 */
    fun parseStrm(rawText: String, fallbackFileName: String? = null): ParsedStrmStream? {
        val ffi: StrmStreamFfi? = runCatching {
            parseStrmContent(rawText, fallbackFileName)
        }.getOrNull()
        if (ffi != null) {
            return ParsedStrmStream(
                url = ffi.url,
                headers = parseSimpleJsonStringMap(ffi.headersJson),
                mediaKind = ffi.mediaKind,
            )
        }
        return fallbackParseStrm(rawText, fallbackFileName)
    }

    /** 解析 AI 智能助手流式 Markdown 块级节点。 */
    fun parseMarkdown(markdown: String): List<MarkdownBlockFfi> =
        runCatching { parseAgentMarkdown(markdown) }.getOrElse { emptyList() }

    /** 创建有状态流式 SSE 解析器，供 OkHttp 响应流逐块喂入。 */
    fun createSseParser(): NativeSseParser = NativeSseParser()

    /** 调用 Rust 9 维级联筛选与同规格分组引擎。 */
    fun filterResources(resourcesJson: String, criteriaJson: String = ""): String =
        filterAndGroupResources(resourcesJson, criteriaJson)

    /** 本地解析 JWT 过期时间与声明。 */
    fun decodeJwt(token: String, nowEpochSecs: Long = System.currentTimeMillis() / 1000): JwtClaimsFfi =
        decodeJwtTokenClaims(token, nowEpochSecs)

    /** 按前后端一致的严格布尔规则计算用户权限矩阵。 */
    fun evaluatePermissions(permissionsJson: String, isSuperuser: Boolean): PermissionsFfi =
        evaluateUserPermissions(permissionsJson, isSuperuser)

    /** 分类 401/403 响应决策：`valid` / `logout` / `forbidden`。 */
    fun classifyAuthStatus(status: Int, bodyText: String): String =
        classifyHttpAuthStatus(status.toUShort(), bodyText)

    /** 解析插件 `get_form`/`get_page` 文档并输出扁平渲染表单计划 JSON。 */
    fun planPluginForm(documentJson: String): String = planPluginFormJson(documentJson)

    /** 将局部表单补丁无损合并回服务端完整模型（保留未知键与 64 位大整数）。 */
    fun applyPluginPatch(originalModelJson: String, patchJson: String): String =
        applyPluginFormPatch(originalModelJson, patchJson)

    /** 沙箱评估插件表单条件表达式（`v-show` / `v-if`）。 */
    fun evalFormExpression(expr: String, modelJson: String): Boolean =
        runCatching { evaluatePluginExpression(expr, modelJson) }.getOrDefault(true)

    /** 分析 5 字段 Cron 表达式并返回可读中文摘要。 */
    fun analyzeCron(expr: String): CronSummaryFfi = analyzeCronExpression(expr)

    /** 计算 3D 社区勋章金属基色与背面凹雕配色方案。 */
    fun medalPalette(medalId: String): MedalPaletteFfi = computeMedalPalette(medalId)

    /** 计算剧集订阅完成进度。 */
    fun subscribeProgress(total: Int, lack: Int): SubscribeProgressFfi =
        computeSubscribeProgress(total, lack)

    private val syncJson = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }

    /** 调用 Rust 播放进度与会话上报状态机，未加载 JNI 时回退同构纯 Kotlin 实现（保障 JVM 单测）。 */
    fun planPlaybackSyncStep(
        state: PlaybackSyncStateDto,
        input: PlaybackSyncInputDto,
    ): PlaybackSyncDecisionDto {
        val stateJson = syncJson.encodeToString(state)
        val inputJson = syncJson.encodeToString(input)
        val raw = runCatching { planPlaybackSyncStepJson(stateJson, inputJson) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<PlaybackSyncDecisionDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackPlanPlaybackSyncStep(state, input)
    }

    /** 整理离线待补报 `stopped` 队列（同服务器同条目保留最新、7 天过期清理、上限 30 条）。 */
    fun normalizePendingPlaybackStops(
        entries: List<PendingPlaybackStopDto>,
        nowEpochMs: Long,
    ): List<PendingPlaybackStopDto> {
        if (entries.isEmpty()) return emptyList()
        val entriesJson = syncJson.encodeToString(entries)
        val raw = runCatching { normalizePendingPlaybackStopsJson(entriesJson, nowEpochMs) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<List<PendingPlaybackStopDto>>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackNormalizePendingPlaybackStops(entries, nowEpochMs)
    }

    /** 规划最优主播放路由及降级回退队列（优先调用 Rust UniFFI，JVM 单测未加载 `.so` 时使用同构 Kotlin 回退）。 */
    fun planPlaybackRoutes(
        routes: List<PlaybackRouteDto>,
        preferences: PlaybackRoutePreferenceDto = PlaybackRoutePreferenceDto(),
        probes: List<RouteProbeOutcomeDto> = emptyList(),
    ): PlaybackRoutePlanDto? {
        if (routes.isEmpty()) return null
        val routesJson = syncJson.encodeToString(routes)
        val prefsJson = syncJson.encodeToString(preferences)
        val probesJson = syncJson.encodeToString(probes)
        val raw = runCatching { planPlaybackRoutesJson(routesJson, prefsJson, probesJson) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<PlaybackRoutePlanDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackPlanPlaybackRoutes(routes, preferences, probes)
    }

    /** 严格校验两条 HTTP(S) URL 是否同源（scheme + 大小写无关 host + 默认/显式端口）。 */
    fun isSameHttpOriginUrl(urlA: String, urlB: String): Boolean {
        runCatching { isSameHttpOrigin(urlA, urlB) }.getOrNull()?.let { return it }
        return fallbackIsSameHttpOrigin(urlA, urlB)
    }

    /** 调用 Rust 共享选核路由决定主播放内核及起播失败回退内核（JVM 单测未加载 `.so` 时使用同构回退）。 */
    fun resolvePlaybackEngine(input: EngineResolutionInputDto): EngineResolutionPlanDto {
        val raw = runCatching {
            resolvePlaybackEngineJson(syncJson.encodeToString(input))
        }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<EngineResolutionPlanDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackResolvePlaybackEngine(input)
    }

    /** 按安全模板渲染外部播放器拉起 URL，拒绝控制字符、危险协议或缺少 `{url}` 占位符的模板。 */
    fun buildSafeExternalPlayerUrl(template: String, mediaUrl: String, title: String = ""): String? {
        runCatching { buildExternalPlayerUrl(template, mediaUrl, title) }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?.let { return it }
        return fallbackBuildExternalPlayerUrl(template, mediaUrl, title)
    }

    /** 校验并规范化插件 Bridge 请求的 `/api/v1/...` 路径，拒绝外部主机与路径穿越。 */
    fun validatePluginApiPath(rawPath: String): String? {
        runCatching { validatePluginBridgeApiPath(rawPath) }
            .onSuccess { if (it.isNotBlank()) return it }
            .onFailure { if (it !is UnsatisfiedLinkError && it !is NoClassDefFoundError) return null }
        return fallbackValidatePluginApiPath(rawPath)
    }

    /** 校验本地运行时壳 `/shell/...` 资产路径并返回安全包内相对路径。 */
    fun validatePluginShellAssetPath(virtualPath: String): String? {
        runCatching { validatePluginShellAsset(virtualPath) }
            .onSuccess { if (it.isNotBlank()) return it }
            .onFailure { if (it !is UnsatisfiedLinkError && it !is NoClassDefFoundError) return null }
        return fallbackValidatePluginShellAssetPath(virtualPath)
    }

    /** 调用 Rust 共享弹幕处理内核完成解析、屏蔽、短窗合并与每秒限流（JVM 单测未加载 `.so` 时回退纯 Kotlin 实现）。 */
    fun prepareDanmakuTimeline(
        rawPayloadJson: String,
        options: DanmakuFilterOptionsDto = DanmakuFilterOptionsDto(),
    ): PreparedDanmakuTimelineDto {
        val optsJson = syncJson.encodeToString(options)
        val raw = runCatching { prepareDanmakuTimelineJson(rawPayloadJson, optsJson) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<PreparedDanmakuTimelineDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackPrepareDanmakuTimeline(rawPayloadJson, options)
    }

    /** 跨端统一生成弹幕手动搜索默认关键词。 */
    fun normalizeDanmakuTitle(
        seriesName: String? = null,
        title: String? = null,
        season: Int? = null,
        episode: Int? = null,
        fileName: String? = null,
    ): String {
        runCatching {
            normalizeDanmakuQueryTitle(seriesName, title, season, episode, fileName)
        }.getOrNull()?.let { return it }
        val base = seriesName?.trim()?.takeIf { it.isNotEmpty() }
            ?: title?.trim()?.takeIf { it.isNotEmpty() }
            ?: fileName?.substringAfterLast('/')?.substringAfterLast('\\')?.substringBeforeLast('.')?.trim()
            ?: ""
        return if (!seriesName.isNullOrBlank() && season != null && season > 1 && !base.contains("第${season}季")) {
            "$base 第${season}季"
        } else {
            base
        }
    }

    private fun fallbackPrepareDanmakuTimeline(
        rawPayloadJson: String,
        options: DanmakuFilterOptionsDto,
    ): PreparedDanmakuTimelineDto {
        val trimmed = rawPayloadJson.trim().removePrefix("\uFEFF")
        if (trimmed.isEmpty()) return PreparedDanmakuTimelineDto()
        val parsed = mutableListOf<DanmakuItemDto>()
        val root = runCatching { syncJson.parseToJsonElement(trimmed) }.getOrNull()
        val arr = when (root) {
            is kotlinx.serialization.json.JsonArray -> root
            is kotlinx.serialization.json.JsonObject ->
                (root["data"] as? kotlinx.serialization.json.JsonObject)?.get("items") as? kotlinx.serialization.json.JsonArray
                    ?: root["items"] as? kotlinx.serialization.json.JsonArray
                    ?: root["comments"] as? kotlinx.serialization.json.JsonArray
            else -> null
        } ?: return PreparedDanmakuTimelineDto()
        for (el in arr) {
            if (el is kotlinx.serialization.json.JsonArray && el.size >= 4) {
                val t = (el[0] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toLongOrNull() ?: continue
                val m = (el[1] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toIntOrNull() ?: 1
                val c = (el[2] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toIntOrNull() ?: 0xFFFFFF
                val txt = (el[3] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim().orEmpty()
                if (txt.isNotEmpty()) parsed.add(DanmakuItemDto(t, if (m == 4 || m == 5) m else 1, c and 0xFFFFFF, txt, 1))
            }
        }
        val lowerBlocks = options.blockKeywords.map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        val filtered = parsed.mapNotNull { item ->
            val t = item.timeMs + options.offsetMs
            if (t < 0L) return@mapNotNull null
            val allowed = when (item.mode) {
                4 -> options.allowBottom
                5 -> options.allowTop
                else -> options.allowScroll
            }
            if (!allowed) return@mapNotNull null
            val lower = item.text.lowercase()
            if (lowerBlocks.any { lower.contains(it) }) return@mapNotNull null
            item.copy(timeMs = t, colorRgb = if (options.allowColor) item.colorRgb else 0xFFFFFF)
        }.sortedBy { it.timeMs }
        return PreparedDanmakuTimelineDto(rawCount = parsed.size, filteredCount = filtered.size, items = filtered)
    }

    /** 派生按实例源 SHA-256、插件 ID 与版本/产物哈希隔离的磁盘缓存键。 */
    fun buildPluginRemoteCacheKey(
        instanceOrigin: String,
        pluginId: String,
        versionOrHash: String,
    ): PluginRemoteCacheKeyDto {
        val raw = runCatching {
            buildPluginRemoteCacheKeyJson(instanceOrigin, pluginId, versionOrHash)
        }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<PluginRemoteCacheKeyDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackBuildPluginRemoteCacheKey(instanceOrigin, pluginId, versionOrHash)
    }

    /** 将后端 `/api/v1/plugin/remotes` 返回的入口规划为虚拟源入口与上游文件路径。 */
    fun normalizePluginRemoteEntry(
        pluginId: String,
        versionOrHash: String,
        rawRemoteUrl: String,
    ): PluginRemoteEntryPlanDto? {
        runCatching {
            normalizePluginRemoteEntryJson(pluginId, versionOrHash, rawRemoteUrl)
        }.onSuccess { raw ->
            if (raw.isNotBlank()) {
                runCatching { syncJson.decodeFromString<PluginRemoteEntryPlanDto>(raw) }
                    .getOrNull()
                    ?.let { return it }
            }
        }.onFailure {
            if (it !is UnsatisfiedLinkError && it !is NoClassDefFoundError) return null
        }
        return fallbackNormalizePluginRemoteEntry(versionOrHash, rawRemoteUrl)
    }

    /** 将虚拟源 `/plugin-remote/...` 请求还原为上游 API 路径与缓存相对路径。 */
    fun resolvePluginRemoteUpstream(virtualPath: String): PluginRemoteUpstreamTargetDto? {
        runCatching {
            resolvePluginRemoteUpstreamJson(virtualPath)
        }.onSuccess { raw ->
            if (raw.isNotBlank()) {
                runCatching { syncJson.decodeFromString<PluginRemoteUpstreamTargetDto>(raw) }
                    .getOrNull()
                    ?.let { return it }
            }
        }.onFailure {
            if (it !is UnsatisfiedLinkError && it !is NoClassDefFoundError) return null
        }
        return fallbackResolvePluginRemoteUpstream(virtualPath)
    }

    private fun hasUnsafeControlOrBackslash(s: String): Boolean =
        s.any { it.code < 0x20 || it.code == 0x7F || it == '\\' }

    private fun sanitizeCacheSegment(raw: String, fallback: String): String {
        val sb = StringBuilder()
        for (ch in raw.trim()) {
            if (sb.length >= 64) break
            if (ch.isLetterOrDigit() && ch.code < 128 || ch == '-' || ch == '_' || ch == '.') {
                sb.append(ch)
            } else {
                sb.append('_')
            }
        }
        val cleaned = sb.toString().trim('.', '_')
        return if (cleaned.isEmpty() || cleaned == "." || cleaned == ".." || cleaned.contains("..")) fallback else cleaned
    }

    private fun validateSafeSegments(raw: String): List<String>? {
        val trimmed = raw.trim('/')
        if (trimmed.isEmpty()) return null
        val out = mutableListOf<String>()
        for (seg in trimmed.split('/')) {
            if (seg.isEmpty() || seg == "." || seg == "..") return null
            val decoded = runCatching { java.net.URLDecoder.decode(seg, "UTF-8") }.getOrDefault(seg).lowercase()
            if (decoded == "." || decoded == ".." || decoded.contains("..") || decoded.contains('/') || decoded.contains('\\') || decoded.contains('\u0000')) {
                return null
            }
            out += seg
        }
        return out
    }

    private fun fallbackValidatePluginApiPath(rawPath: String): String? {
        val trimmed = rawPath.trim()
        if (trimmed.isEmpty() || hasUnsafeControlOrBackslash(trimmed)) return null
        val lower = trimmed.lowercase()
        if ("://" in lower || lower.startsWith("//") || lower.startsWith("http:") || lower.startsWith("https:") || lower.startsWith("javascript:") || lower.startsWith("data:") || lower.startsWith("file:")) {
            return null
        }
        val noFrag = trimmed.substringBefore('#')
        val pathPart = noFrag.substringBefore('?')
        val queryPart = if ('?' in noFrag) noFrag.substringAfter('?') else null
        val stripped = pathPart.trimStart('/')
        val rel = when {
            stripped.startsWith("api/v1/") -> stripped.removePrefix("api/v1/")
            stripped == "api/v1" -> ""
            else -> stripped
        }
        val segs = validateSafeSegments(rel) ?: return null
        val normalized = "/api/v1/${segs.joinToString("/")}"
        return if (queryPart != null) {
            if (hasUnsafeControlOrBackslash(queryPart)) null else "$normalized?$queryPart"
        } else {
            normalized
        }
    }

    private fun fallbackValidatePluginShellAssetPath(virtualPath: String): String? {
        val trimmed = virtualPath.trim()
        if (trimmed.isEmpty() || hasUnsafeControlOrBackslash(trimmed)) return null
        val clean = trimmed.substringBefore('#').substringBefore('?').trimStart('/')
        val rel = clean.removePrefix("shell/")
        val segs = validateSafeSegments(rel) ?: return null
        return segs.joinToString("/")
    }

    private fun fallbackBuildPluginRemoteCacheKey(
        instanceOrigin: String,
        pluginId: String,
        versionOrHash: String,
    ): PluginRemoteCacheKeyDto {
        val norm = instanceOrigin.trim().trimEnd('/').lowercase()
        val digest = MessageDigest.getInstance("SHA-256").digest(norm.toByteArray(Charsets.UTF_8))
        val hash16 = digest.joinToString("") { "%02x".format(it) }.take(16)
        val pid = sanitizeCacheSegment(pluginId.lowercase(), "plugin")
        val ver = sanitizeCacheSegment(versionOrHash, "default")
        return PluginRemoteCacheKeyDto(hash16, pid, ver, "$hash16/$pid/$ver")
    }

    private fun fallbackNormalizePluginRemoteEntry(
        versionOrHash: String,
        rawRemoteUrl: String,
    ): PluginRemoteEntryPlanDto? {
        val trimmed = rawRemoteUrl.trim()
        if (trimmed.isEmpty() || hasUnsafeControlOrBackslash(trimmed)) return null
        val noFrag = trimmed.substringBefore('#')
        val pathOrUrl = noFrag.substringBefore('?')
        val query = if ('?' in noFrag) noFrag.substringAfter('?') else ""
        val pathOnly = if ("://" in pathOrUrl) {
            val after = pathOrUrl.substringAfter("://")
            val idx = after.indexOf('/')
            if (idx < 0) return null else after.substring(idx)
        } else {
            pathOrUrl
        }
        val marker = "plugin/file/"
        val idx = pathOnly.lowercase().indexOf(marker)
        if (idx < 0) return null
        val segs = validateSafeSegments(pathOnly.substring(idx + marker.length)) ?: return null
        if (segs.size < 2) return null
        val filePid = segs[0]
        val rel = segs.drop(1).joinToString("/")
        val qv = query.split('&').firstOrNull { it.startsWith("v=") }?.substringAfter("v=")?.trim()
        val verRaw = versionOrHash.trim().ifEmpty { qv.orEmpty().ifEmpty { "default" } }
        val verTag = sanitizeCacheSegment(verRaw, "default")
        return PluginRemoteEntryPlanDto(
            pluginId = filePid,
            versionTag = verTag,
            virtualEntryPath = "/plugin-remote/$filePid/$verTag/$rel",
            upstreamFilePath = "/api/v1/plugin/file/$filePid/$rel",
        )
    }

    private fun fallbackResolvePluginRemoteUpstream(virtualPath: String): PluginRemoteUpstreamTargetDto? {
        val trimmed = virtualPath.trim()
        if (trimmed.isEmpty() || hasUnsafeControlOrBackslash(trimmed)) return null
        val stripped = trimmed.substringBefore('#').substringBefore('?').trimStart('/')
        if (!stripped.startsWith("plugin-remote/")) return null
        val segs = validateSafeSegments(stripped.removePrefix("plugin-remote/")) ?: return null
        if (segs.size < 3) return null
        val pid = segs[0]
        val ver = sanitizeCacheSegment(segs[1], "default")
        val rel = segs.drop(2).joinToString("/")
        return PluginRemoteUpstreamTargetDto(
            pluginId = pid,
            versionTag = ver,
            assetRelPath = rel,
            upstreamApiPath = "/api/v1/plugin/file/$pid/$rel",
        )
    }

    private fun fallbackResolvePlaybackEngine(input: EngineResolutionInputDto): EngineResolutionPlanDto {
        val enhanced = input.hasEnhancedEngine
        val legacy = input.hasLegacyEngine
        when (input.preferred.lowercase()) {
            "native" -> return EngineResolutionPlanDto("native", null, "user_pinned_native")
            "enhanced" -> return if (enhanced) {
                EngineResolutionPlanDto("enhanced", "native", "user_pinned_enhanced")
            } else {
                EngineResolutionPlanDto("native", null, "enhanced_unavailable_fallback_native")
            }
            "legacy" -> return when {
                legacy -> EngineResolutionPlanDto("legacy", if (enhanced) "enhanced" else "native", "user_pinned_legacy")
                enhanced -> EngineResolutionPlanDto("enhanced", "native", "legacy_unavailable_fallback_enhanced")
                else -> EngineResolutionPlanDto("native", null, "legacy_unavailable_fallback_native")
            }
        }
        val cleanPath = input.urlOrFilename.trim().substringBefore('#').substringBefore('?').lowercase()
        val ext = cleanPath.substringAfterLast('/', cleanPath).substringAfterLast('.', "").takeIf { '.' in cleanPath.substringAfterLast('/', cleanPath) }.orEmpty()
        val container = input.container?.trim()?.lowercase()?.trimStart('.')?.takeIf { it.isNotEmpty() } ?: ext
        val audioCodec = input.audioCodec?.trim()?.lowercase().orEmpty()
        if (input.isAudio) {
            val exoticAudio = container in setOf("ape", "wv", "dsf", "dff", "wma", "opus", "ogg") ||
                audioCodec in setOf("ape", "wavpack", "dsd", "wma", "dts", "truehd")
            return if (exoticAudio && enhanced) {
                EngineResolutionPlanDto("enhanced", "native", "auto_audio_exotic_enhanced")
            } else {
                EngineResolutionPlanDto("native", if (enhanced) "enhanced" else null, "auto_audio_native")
            }
        }
        if (input.decodeForceSoftware && enhanced) {
            return EngineResolutionPlanDto("enhanced", "native", "auto_force_software_enhanced")
        }
        return EngineResolutionPlanDto("native", if (enhanced) "enhanced" else null, "auto_native_default")
    }

    private fun fallbackBuildExternalPlayerUrl(template: String, mediaUrl: String, title: String): String? {
        val tmpl = template.trim()
        val media = mediaUrl.trim()
        if (tmpl.isEmpty() || media.isEmpty()) return null
        if (tmpl.any { it.isISOControl() } || media.any { it.isISOControl() }) return null
        if (!tmpl.contains("{url}") && !tmpl.contains("{raw_url}")) return null
        val scheme = tmpl.substringBefore("://", "").lowercase()
        if (scheme.isEmpty() || scheme in setOf("javascript", "data", "file", "vbscript", "blob", "about")) return null
        if (!scheme.first().isLetter() || scheme.any { !(it.isLetterOrDigit() || it == '+' || it == '-' || it == '.') }) return null
        val encodedUrl = java.net.URLEncoder.encode(media, "UTF-8").replace("+", "%20")
        val encodedTitle = java.net.URLEncoder.encode(title.trim(), "UTF-8").replace("+", "%20")
        return tmpl
            .replace("{url}", encodedUrl)
            .replace("{raw_url}", media)
            .replace("{title}", encodedTitle)
    }

    private fun fallbackIsSameHttpOrigin(urlA: String, urlB: String): Boolean {
        val a = runCatching { java.net.URI(urlA.trim()) }.getOrNull() ?: return false
        val b = runCatching { java.net.URI(urlB.trim()) }.getOrNull() ?: return false
        val schemeA = a.scheme?.lowercase() ?: return false
        val schemeB = b.scheme?.lowercase() ?: return false
        if (schemeA !in setOf("http", "https") || schemeA != schemeB) return false
        val hostA = a.host?.lowercase()?.takeIf { it.isNotBlank() } ?: return false
        val hostB = b.host?.lowercase()?.takeIf { it.isNotBlank() } ?: return false
        if (hostA != hostB) return false
        val portA = if (a.port > 0) a.port else if (schemeA == "https") 443 else 80
        val portB = if (b.port > 0) b.port else if (schemeB == "https") 443 else 80
        return portA == portB
    }

    private fun fallbackPlanPlaybackRoutes(
        routes: List<PlaybackRouteDto>,
        prefs: PlaybackRoutePreferenceDto,
        probes: List<RouteProbeOutcomeDto>,
    ): PlaybackRoutePlanDto? {
        fun isValidHttp(raw: String): Boolean {
            val u = runCatching { java.net.URI(raw) }.getOrNull() ?: return false
            val sch = u.scheme?.lowercase() ?: return false
            return sch in setOf("http", "https") && !u.host.isNullOrBlank() && u.userInfo == null
        }

        fun reachableLatency(route: PlaybackRouteDto): Int? {
            val probeKey = route.probeUrl?.trim()?.takeIf { it.isNotBlank() }
            val outcome = probes.firstOrNull { item ->
                val target = item.url.trim()
                (probeKey != null && target == probeKey) || target == route.url
            } ?: return null
            if (!outcome.reachable) return null
            return outcome.latencyMs ?: (Int.MAX_VALUE / 2)
        }

        val strm = mutableListOf<PlaybackRouteDto>()
        val lan = mutableListOf<Pair<Int, PlaybackRouteDto>>()
        val wan = mutableListOf<Pair<Int, PlaybackRouteDto>>()
        val proxy = mutableListOf<PlaybackRouteDto>()
        val seen = mutableSetOf<String>()

        for (route in routes) {
            val trimmed = route.url.trim()
            if (trimmed.isEmpty() || !isValidHttp(trimmed)) continue
            if (!seen.add("${route.kind}|$trimmed")) continue
            val normalized = route.copy(url = trimmed, probeUrl = route.probeUrl?.trim())
            when (normalized.kind) {
                "strm_direct" -> if (prefs.preferStrmDirect) strm += normalized
                "server_lan" -> if (prefs.preferServerDirect) {
                    reachableLatency(normalized)?.let { lan += it to normalized }
                }
                "server_wan" -> if (prefs.preferServerDirect) {
                    reachableLatency(normalized)?.let { wan += it to normalized }
                }
                "mp_proxy" -> proxy += normalized
            }
        }

        strm.sortBy { it.priority }
        lan.sortWith(compareBy<Pair<Int, PlaybackRouteDto>> { it.first }.thenBy { it.second.priority })
        wan.sortWith(compareBy<Pair<Int, PlaybackRouteDto>> { it.first }.thenBy { it.second.priority })
        proxy.sortBy { it.priority }

        val ordered = mutableListOf<PlaybackRouteDto>()
        ordered += strm
        val bestLan = lan.firstOrNull()?.first
        val bestWan = wan.firstOrNull()?.first
        val preferWan = bestLan != null && bestWan != null &&
            bestLan > prefs.lanPreferredMaxLatencyMs && bestWan < bestLan
        if (preferWan) {
            ordered += wan.map { it.second }
            ordered += lan.map { it.second }
        } else {
            ordered += lan.map { it.second }
            ordered += wan.map { it.second }
        }
        ordered += proxy

        val active = ordered.firstOrNull() ?: return null
        val label = when (active.kind) {
            "strm_direct" -> "STRM 直链"
            "server_lan" -> "局域网直连"
            "server_wan" -> "外网直连"
            else -> "后台中转"
        }
        return PlaybackRoutePlanDto(
            active = active,
            fallbacks = ordered.drop(1),
            routeLabelZh = label,
        )
    }

    /** 原生库暂不可用时的降级状态机也必须使用后端允许的播放事件枚举。 */
    internal fun fallbackPlanPlaybackSyncStep(
        current: PlaybackSyncStateDto,
        input: PlaybackSyncInputDto,
    ): PlaybackSyncDecisionDto {
        val now = input.nowMs.coerceAtLeast(0L)
        var next = current
        val playingNow = !input.isPaused && input.trigger != "pause" && input.trigger != "background"
        if (playingNow) {
            val prevTick = next.lastPlayingTickAtMs
            val added = if (prevTick != null && now > prevTick) (now - prevTick).coerceAtMost(60_000L) else 0L
            next = next.copy(
                cumulativePlaybackTimeMs = next.cumulativePlaybackTimeMs + added,
                lastPlayingTickAtMs = now,
            )
        } else {
            next = next.copy(lastPlayingTickAtMs = null)
        }

        val resolvedPos = when (input.trigger) {
            "seek" -> input.positionMs.coerceAtLeast(0L)
            "finish" -> input.durationMs?.takeIf { it > 0L }
                ?: maxOf(input.positionMs, next.lastPositionMs, 0L)
            else -> if (input.positionMs > 0L) {
                input.positionMs
            } else if (next.lastPositionMs > 0L && input.trigger in setOf("stop", "pause", "background")) {
                next.lastPositionMs
            } else {
                0L
            }
        }
        next = next.copy(lastPositionMs = resolvedPos)
        if (input.audioStreamIndex != null) {
            next = next.copy(lastAudioStreamIndex = input.audioStreamIndex)
        }
        if (input.subtitleStreamIndex != null) {
            next = next.copy(lastSubtitleStreamIndex = input.subtitleStreamIndex)
        }

        fun emit(state: String, eventName: String?, paused: Boolean, update: (PlaybackSyncStateDto) -> PlaybackSyncStateDto = { it }): PlaybackSyncDecisionDto {
            val updated = update(next).let { s ->
                s.copy(
                    seq = s.seq + 1L,
                    lastReportAtMs = now,
                )
            }
            return PlaybackSyncDecisionDto(
                shouldReport = true,
                state = state,
                eventName = eventName,
                isPaused = paused,
                positionMs = resolvedPos,
                playbackTimeMs = updated.cumulativePlaybackTimeMs,
                seq = updated.seq,
                nextState = updated,
            )
        }

        fun skip(state: String, paused: Boolean, updated: PlaybackSyncStateDto = next): PlaybackSyncDecisionDto =
            PlaybackSyncDecisionDto(
                shouldReport = false,
                state = state,
                eventName = null,
                isPaused = paused,
                positionMs = resolvedPos,
                playbackTimeMs = updated.cumulativePlaybackTimeMs,
                seq = updated.seq,
                nextState = updated,
            )

        return when (input.trigger) {
            "start" -> {
                if (next.startedSent && !next.stoppedSent) {
                    skip(if (input.isPaused) "paused" else "playing", input.isPaused)
                } else {
                    emit("started", "Start", input.isPaused) { s ->
                        s.copy(
                            startedSent = true,
                            stoppedSent = false,
                            pausedSinceMs = if (input.isPaused) now else null,
                        )
                    }
                }
            }
            "pause" -> {
                if (next.stoppedSent) return skip("stopped", true)
                val pausedSince = next.pausedSinceMs ?: now
                emit("paused", "Pause", true) { s ->
                    s.copy(startedSent = true, pausedSinceMs = pausedSince)
                }
            }
            "resume" -> {
                if (next.stoppedSent) {
                    emit("started", "Start", false) { s ->
                        s.copy(
                            startedSent = true,
                            stoppedSent = false,
                            pausedSinceMs = null,
                            lastPlayingTickAtMs = now,
                        )
                    }
                } else {
                    emit("playing", "Unpause", false) { s ->
                        s.copy(startedSent = true, pausedSinceMs = null, lastPlayingTickAtMs = now)
                    }
                }
            }
            "seek" -> {
                if (next.stoppedSent) return skip("stopped", true)
                val lastSeek = next.lastSeekAtMs
                if (lastSeek != null && (now - lastSeek) in 0 until 300L) {
                    skip(if (input.isPaused) "paused" else "playing", input.isPaused)
                } else {
                    val st = if (input.isPaused) "paused" else "playing"
                    emit(st, "TimeUpdate", input.isPaused) { s ->
                        s.copy(startedSent = true, lastSeekAtMs = now)
                    }
                }
            }
            "track_change" -> {
                if (next.stoppedSent) return skip("stopped", true)
                val st = if (input.isPaused) "paused" else "playing"
                val event = when {
                    input.audioStreamIndex != next.lastAudioStreamIndex -> "AudioTrackChange"
                    input.subtitleStreamIndex != next.lastSubtitleStreamIndex -> "SubtitleTrackChange"
                    else -> "TimeUpdate"
                }
                emit(st, event, input.isPaused) { s ->
                    s.copy(startedSent = true, lastAudioStreamIndex = input.audioStreamIndex, lastSubtitleStreamIndex = input.subtitleStreamIndex)
                }
            }
            "background" -> {
                if (next.stoppedSent) return skip("stopped", true)
                val pausedSince = if (input.isPaused) (next.pausedSinceMs ?: now) else null
                val st = if (input.isPaused) "paused" else "playing"
                emit(st, if (input.isPaused) "Pause" else "TimeUpdate", input.isPaused) { s ->
                    s.copy(startedSent = true, pausedSinceMs = pausedSince)
                }
            }
            "stop", "finish" -> {
                if (next.stoppedSent) return skip("stopped", true)
                emit("stopped", null, true) { s ->
                    s.copy(stoppedSent = true, pausedSinceMs = null, lastPlayingTickAtMs = null)
                }
            }
            else -> { // tick
                if (next.stoppedSent) return skip("stopped", true)
                if (!next.startedSent) {
                    return emit("started", "Start", input.isPaused) { s ->
                        s.copy(
                            startedSent = true,
                            stoppedSent = false,
                            pausedSinceMs = if (input.isPaused) now else null,
                        )
                    }
                }
                if (input.isPaused) {
                    val pausedSince = next.pausedSinceMs ?: now
                    next = next.copy(pausedSinceMs = pausedSince)
                    if (now - pausedSince >= 15 * 60 * 1_000L) {
                        return emit("stopped", null, true) { s ->
                            s.copy(stoppedSent = true, pausedSinceMs = null, lastPlayingTickAtMs = null)
                        }
                    }
                    val elapsed = next.lastReportAtMs?.let { now - it } ?: Long.MAX_VALUE
                    if (elapsed >= 12_000L) {
                        emit("paused", "Pause", true)
                    } else {
                        skip("paused", true, next)
                    }
                } else {
                    next = next.copy(pausedSinceMs = null)
                    val elapsed = next.lastReportAtMs?.let { now - it } ?: Long.MAX_VALUE
                    if (elapsed >= 10_000L) {
                        emit("playing", "TimeUpdate", false)
                    } else {
                        skip("playing", false, next)
                    }
                }
            }
        }
    }

    private fun fallbackNormalizePendingPlaybackStops(
        entries: List<PendingPlaybackStopDto>,
        nowEpochMs: Long,
    ): List<PendingPlaybackStopDto> {
        val cutoff = nowEpochMs - 7L * 24L * 60L * 60L * 1000L
        val deduped = linkedMapOf<Pair<String, String>, PendingPlaybackStopDto>()
        for (item in entries) {
            val srv = item.server.trim()
            val id = item.itemId.trim()
            if (srv.isEmpty() || id.isEmpty() || item.updatedAtMs < cutoff) continue
            val normalized = item.copy(server = srv, itemId = id, positionMs = item.positionMs.coerceAtLeast(0L))
            val key = srv to id
            val existing = deduped[key]
            if (existing == null || normalized.updatedAtMs >= existing.updatedAtMs) {
                deduped[key] = normalized
            }
        }
        return deduped.values.sortedByDescending { it.updatedAtMs }.take(30)
    }

    private fun escapeJson(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

    /** 检测 HTTP 响应是否被 Cloudflare Access 拦截。 */
    fun detectCloudflareChallenge(
        status: Int,
        headers: Map<String, String>,
        body: String,
        requestUrl: String,
    ): CloudflareChallengeDto {
        val headersJson = syncJson.encodeToString(headers)
        val raw = runCatching {
            detectCloudflareAccessChallengeJson(status.toUShort(), headersJson, body.take(8192), requestUrl)
        }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<CloudflareChallengeDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        return fallbackDetectCloudflareChallenge(status, headers, body, requestUrl)
    }

    /** 生成 RFC 7636 PKCE `S256` 校验对与防 CSRF `state`。 */
    fun generatePkcePair(extraEntropy: String = ""): PkcePairDto {
        val raw = runCatching { generatePkcePairJson(extraEntropy) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<PkcePairDto>(raw) }
                .getOrNull()
                ?.takeIf { it.codeVerifier.isNotBlank() && it.codeChallenge.isNotBlank() }
                ?.let { return it }
        }
        val rnd = java.security.SecureRandom()
        val vBytes = ByteArray(48).also { rnd.nextBytes(it) }
        val sBytes = ByteArray(24).also { rnd.nextBytes(it) }
        val verifier = base64UrlNoPad(vBytes)
        val challenge = computePkceChallenge(verifier)
        return PkcePairDto(
            codeVerifier = verifier,
            codeChallenge = challenge,
            codeChallengeMethod = "S256",
            state = base64UrlNoPad(sBytes),
        )
    }

    /** 根据 RFC 7636 计算 `BASE64URL-ENCODE(SHA256(ASCII(codeVerifier)))`。 */
    fun computePkceChallenge(codeVerifier: String): String =
        runCatching { computePkceS256Challenge(codeVerifier) }.getOrElse {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(codeVerifier.toByteArray(Charsets.US_ASCII))
            base64UrlNoPad(digest)
        }

    /** 构造按 RFC 9728 -> RFC 8414 优先顺序排列的元数据发现候选 URL 列表。 */
    fun buildOAuthDiscoveryUrls(serverUrl: String, resourceMetadataUrl: String? = null): List<String> {
        val raw = runCatching { buildOauthDiscoveryUrlsJson(serverUrl, resourceMetadataUrl) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<List<String>>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        val out = mutableListOf<String>()
        val cleanMeta = resourceMetadataUrl?.trim().orEmpty()
        if (cleanMeta.startsWith("https://") || cleanMeta.startsWith("http://")) {
            out.add(cleanMeta)
        }
        val uri = runCatching { java.net.URI(serverUrl.trim()) }.getOrNull()
        val scheme = uri?.scheme?.lowercase()
        val host = uri?.host
        if ((scheme == "https" || scheme == "http") && !host.isNullOrBlank()) {
            val portPart = if (uri.port > 0) ":${uri.port}" else ""
            val origin = "$scheme://$host$portPart"
            listOf(
                "$origin/.well-known/oauth-protected-resource",
                "$origin/.well-known/oauth-authorization-server",
            ).forEach { if (it !in out) out.add(it) }
        }
        return out
    }

    /** 解析 RFC 9728 Protected Resource Metadata，完整返回规范化 `resource` 与 `authorizationServers`。 */
    fun parseProtectedResourceMetadataDetail(jsonStr: String): Result<ProtectedResourceMetadataDto> = runCatching {
        val raw = runCatching { parseProtectedResourceMetadataDetailJson(jsonStr) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            return@runCatching syncJson.decodeFromString<ProtectedResourceMetadataDto>(raw)
        }
        val elem = syncJson.parseToJsonElement(jsonStr)
        val obj = elem as? kotlinx.serialization.json.JsonObject ?: error("Invalid metadata JSON")
        val rawResource = (obj["resource"] as? kotlinx.serialization.json.JsonPrimitive)
            ?.content
            ?.trim()
            ?.substringBefore('#')
            ?.trim()
            ?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
        val arr = obj["authorization_servers"] as? kotlinx.serialization.json.JsonArray
            ?: error("Missing authorization_servers")
        val servers = arr.mapNotNull { item ->
            val str = (item as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim()
            if (str.isNullOrBlank() || (!str.startsWith("https://") && !str.startsWith("http://"))) {
                null
            } else {
                val trimmed = str.trimEnd('/')
                if ("/.well-known/" in trimmed) trimmed else "$trimmed/.well-known/oauth-authorization-server"
            }
        }.ifEmpty { error("No authorization_servers URL found") }
        ProtectedResourceMetadataDto(resource = rawResource, authorizationServers = servers)
    }

    /** 解析 RFC 9728 Protected Resource Metadata 中的 `authorization_servers`。 */
    fun parseProtectedResourceMetadata(jsonStr: String): Result<List<String>> =
        parseProtectedResourceMetadataDetail(jsonStr).map { it.authorizationServers }

    /** 将实例地址规范化为 RFC 8707 `resource` 默认回退值（去除查询串、片段、默认端口及末尾 `/`）。 */
    fun normalizeOAuthResourceUrl(rawUrl: String): String? {
        runCatching { normalizeOauthResourceUrl(rawUrl) }.getOrNull()?.takeIf { it.isNotBlank() }?.let { return it }
        val uri = runCatching { java.net.URI(rawUrl.trim()) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        val host = uri.host?.lowercase()?.takeIf { it.isNotBlank() } ?: return null
        val defaultPort = if (scheme == "https") 443 else 80
        val portPart = if (uri.port > 0 && uri.port != defaultPort) ":${uri.port}" else ""
        val pathPart = uri.rawPath.orEmpty().trimEnd('/')
        return "$scheme://$host$portPart$pathPart"
    }

    /** 解析 RFC 8414 Authorization Server Metadata。 */
    fun parseOAuthServerMetadata(jsonStr: String): Result<OAuthServerMetadataDto> = runCatching {
        val raw = runCatching { parseOauthServerMetadataJson(jsonStr) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            return@runCatching syncJson.decodeFromString<OAuthServerMetadataDto>(raw)
        }
        val obj = syncJson.parseToJsonElement(jsonStr) as? kotlinx.serialization.json.JsonObject
            ?: error("Invalid metadata JSON")
        fun str(k: String): String? =
            (obj[k] as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() }
        val authEp = str("authorization_endpoint") ?: error("Missing authorization_endpoint")
        val tokenEp = str("token_endpoint") ?: error("Missing token_endpoint")
        OAuthServerMetadataDto(
            issuer = str("issuer").orEmpty(),
            authorizationEndpoint = authEp,
            tokenEndpoint = tokenEp,
            registrationEndpoint = str("registration_endpoint"),
        )
    }

    /** 构造标准 OAuth 2.0 + PKCE (`S256`) + RFC 8707 `resource` 授权 URL。 */
    fun buildOAuthAuthorizeUrl(
        authorizationEndpoint: String,
        clientId: String,
        redirectUri: String = "moviepilot://oauth/callback",
        codeChallenge: String,
        state: String,
        scope: String = "openid email profile offline_access",
        resource: String? = null,
    ): Result<String> = runCatching {
        val cleanResource = resource?.trim()?.substringBefore('#')?.trim()?.takeIf { it.isNotEmpty() }
        if (cleanResource != null && !cleanResource.startsWith("https://") && !cleanResource.startsWith("http://")) {
            error("Invalid OAuth resource indicator URI: $cleanResource")
        }
        runCatching {
            buildOauthAuthorizeUrl(
                authorizationEndpoint,
                clientId,
                redirectUri,
                codeChallenge,
                state,
                scope,
                cleanResource,
            )
        }.getOrElse {
            fun enc(v: String) = java.net.URLEncoder.encode(v.trim(), "UTF-8")
            val sep = if ('?' in authorizationEndpoint) "&" else "?"
            buildString {
                append(authorizationEndpoint.trim()).append(sep)
                append("response_type=code")
                append("&client_id=").append(enc(clientId))
                append("&redirect_uri=").append(enc(redirectUri))
                append("&code_challenge=").append(enc(codeChallenge))
                append("&code_challenge_method=S256")
                append("&state=").append(enc(state))
                if (scope.isNotBlank()) append("&scope=").append(enc(scope))
                if (cleanResource != null) append("&resource=").append(enc(cleanResource))
            }
        }
    }

    /** 校验并解析 OAuth 回调 URL 的 `code` / `state` / `error`。 */
    fun parseOAuthCallbackUrl(callbackUrl: String, expectedState: String): OAuthCallbackResultDto {
        val raw = runCatching { parseOauthCallbackUrlJson(callbackUrl, expectedState) }.getOrNull()
        if (!raw.isNullOrBlank()) {
            runCatching { syncJson.decodeFromString<OAuthCallbackResultDto>(raw) }
                .getOrNull()
                ?.let { return it }
        }
        val query = callbackUrl.substringAfter('?', "").substringBefore('#')
        val params = mutableMapOf<String, String>()
        query.split('&').forEach { pair ->
            val eq = pair.indexOf('=')
            if (eq > 0) {
                val k = java.net.URLDecoder.decode(pair.substring(0, eq), "UTF-8")
                val v = java.net.URLDecoder.decode(pair.substring(eq + 1), "UTF-8").trim()
                if (v.isNotEmpty()) params[k] = v
            }
        }
        val stateMatched = expectedState.isNotBlank() && params["state"] == expectedState.trim()
        val error = params["error"]
        val code = if (stateMatched) params["code"] else null
        return OAuthCallbackResultDto(
            valid = stateMatched && error == null && !code.isNullOrBlank(),
            stateMatched = stateMatched,
            code = code,
            error = error,
            errorDescription = params["error_description"],
        )
    }

    /** 将 `CF_Authorization=<token>` 安全合并到现有同源 Cookie 头（保留 `resource_token` 等其他 Cookie）。 */
    fun mergeCloudflareAccessCookie(existingCookieHeader: String, cfToken: String): String =
        runCatching { mergeCfAccessCookie(existingCookieHeader, cfToken) }.getOrElse {
            val clean = cfToken.trim()
            val parts = existingCookieHeader.split(';')
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.substringBefore('=').trim().equals("CF_Authorization", ignoreCase = true) }
                .toMutableList()
            if (clean.isNotEmpty()) parts.add("CF_Authorization=$clean")
            parts.joinToString("; ")
        }

    private fun base64UrlNoPad(bytes: ByteArray): String =
        java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    private fun fallbackDetectCloudflareChallenge(
        status: Int,
        headers: Map<String, String>,
        body: String,
        requestUrl: String,
    ): CloudflareChallengeDto {
        val lower = headers.entries.associate { it.key.trim().lowercase() to it.value }
        if (status in 300..399) {
            val loc = lower["location"].orEmpty()
            val locLower = loc.lowercase()
            if ("cloudflareaccess.com" in locLower || "/cdn-cgi/access/login" in locLower) {
                return CloudflareChallengeDto(
                    isChallenge = true,
                    reason = "redirect_to_cloudflare_access",
                    loginUrl = loc,
                )
            }
        }
        if (status == 401 || status == 403) {
            val wwwAuth = lower["www-authenticate"].orEmpty()
            val match = Regex("""resource_metadata\s*=\s*"([^"]+)"""", RegexOption.IGNORE_CASE).find(wwwAuth)
            if (match != null) {
                return CloudflareChallengeDto(
                    isChallenge = true,
                    reason = "www_authenticate_resource_metadata",
                    resourceMetadataUrl = match.groupValues[1].trim(),
                )
            }
        }
        val prefix = body.take(8192).lowercase()
        val isHtml = lower["content-type"]?.lowercase()?.contains("text/html") == true ||
            "<!doctype html" in prefix || "<html" in prefix
        if (isHtml && ("cloudflareaccess.com" in prefix || "/cdn-cgi/access/login" in prefix ||
                ("cloudflare access" in prefix && "sign in" in prefix))
        ) {
            return CloudflareChallengeDto(isChallenge = true, reason = "html_cloudflare_access_gate")
        }
        return CloudflareChallengeDto(isChallenge = false)
    }

    private val FALLBACK_AUDIO_EXTS = setOf(
        "mp3", "flac", "m4a", "aac", "wav", "ogg", "oga", "opus", "alac", "ape",
        "aiff", "aif", "wma", "mka", "caf", "dsf", "dff", "amr",
    )
    private val FALLBACK_VIDEO_EXTS = setOf(
        "mp4", "mkv", "mk3d", "mov", "m4v", "avi", "ts", "m2ts", "mts", "webm",
        "flv", "f4v", "wmv", "asf", "rmvb", "rm", "mpg", "mpeg", "vob", "3gp", "3g2", "ogv", "strm",
    )

    private fun fallbackDetectMediaKind(pathOrExt: String, includeStreaming: Boolean): String? {
        val trimmed = pathOrExt.trim()
        if (trimmed.isEmpty()) return null
        val ext = if ('.' in trimmed && !trimmed.startsWith('.')) {
            trimmed.substringAfterLast('.').lowercase()
        } else {
            trimmed.trimStart('.').lowercase()
        }
        if (ext == "strm" && '.' in trimmed.removeSuffix(".$ext").removeSuffix(".STRM")) {
            val innerExt = trimmed.substringBeforeLast('.').substringAfterLast('.', "").lowercase()
            if (innerExt in FALLBACK_AUDIO_EXTS) return "audio"
            return "video"
        }
        return when {
            ext in FALLBACK_AUDIO_EXTS -> "audio"
            ext in FALLBACK_VIDEO_EXTS -> "video"
            includeStreaming && (ext == "m3u8" || ext == "mpd") -> "video"
            else -> null
        }
    }

    private fun fallbackParseStrm(rawText: String, fallbackFileName: String?): ParsedStrmStream? {
        if (rawText.length > 65_536 || '\u0000' in rawText) return null
        val headers = linkedMapOf<String, String>()
        var targetLine: String? = null
        for (rawLine in rawText.removePrefix("\uFEFF").lineSequence()) {
            val line = rawLine.trim()
            if (line.isEmpty()) continue
            if (line.startsWith('#')) {
                val directive = line.removePrefix("#").trim()
                if (directive.startsWith("EXTVLCOPT:", ignoreCase = true)) {
                    val rest = directive.substringAfter(':')
                    val k = rest.substringBefore('=', "").trim().lowercase()
                    val v = rest.substringAfter('=', "").trim()
                    val headerName = when (k) {
                        "http-user-agent" -> "User-Agent"
                        "http-referrer", "http-referer" -> "Referer"
                        "http-cookie" -> "Cookie"
                        else -> null
                    }
                    if (headerName != null && v.isNotEmpty() && v.none { it.isISOControl() }) {
                        headers[headerName] = v
                    }
                }
                continue
            }
            if (targetLine == null) targetLine = line
        }
        val rawTarget = targetLine ?: return null
        val rawUrlPart = rawTarget.substringBefore('|').trim()
        val pipePart = if ('|' in rawTarget) rawTarget.substringAfter('|').trim() else ""
        if (pipePart.isNotEmpty()) {
            for (pair in pipePart.split('&')) {
                val k = pair.substringBefore('=', "").trim().lowercase()
                val v = runCatching {
                    java.net.URLDecoder.decode(pair.substringAfter('=', "").trim(), "UTF-8")
                }.getOrDefault("")
                val headerName = when (k) {
                    "user-agent" -> "User-Agent"
                    "referer", "referrer" -> "Referer"
                    "cookie" -> "Cookie"
                    "origin" -> "Origin"
                    "authorization" -> "Authorization"
                    else -> null
                }
                if (headerName != null && v.isNotEmpty() && v.none { it.isISOControl() }) {
                    headers[headerName] = v
                }
            }
        }
        val normalized = normalizeRawHttpUrl(rawUrlPart) ?: return null
        val decodedPath = runCatching {
            java.net.URLDecoder.decode(java.net.URI(normalized).rawPath ?: "", "UTF-8")
        }.getOrDefault("")
        val kind = (if (!isStrmPath(decodedPath)) fallbackDetectMediaKind(decodedPath, true) else null)
            ?: fallbackFileName?.let { fallbackDetectMediaKind(it, true) }
            ?: "video"
        return ParsedStrmStream(url = normalized, headers = headers, mediaKind = kind)
    }

    private fun normalizeRawHttpUrl(raw: String): String? {
        val sep = raw.indexOf("://")
        if (sep <= 0) return null
        val scheme = raw.substring(0, sep).lowercase()
        if (scheme != "http" && scheme != "https") return null
        val rest = raw.substring(sep + 3)
        val authEnd = rest.indexOfAny(charArrayOf('/', '?')).let { if (it < 0) rest.length else it }
        val authority = rest.substring(0, authEnd)
        if (authority.isBlank() || '@' in authority) return null
        val pathAndQuery = rest.substring(authEnd).substringBefore('#')
        val sb = StringBuilder(raw.length + 16).append(scheme).append("://").append(authority)
        var i = 0
        while (i < pathAndQuery.length) {
            val ch = pathAndQuery[i]
            when {
                ch == ' ' -> sb.append("%20")
                ch == '[' -> sb.append("%5B")
                ch == ']' -> sb.append("%5D")
                ch == '%' -> {
                    val hexOk = i + 2 < pathAndQuery.length &&
                        pathAndQuery[i + 1].isDigitOrHex() &&
                        pathAndQuery[i + 2].isDigitOrHex()
                    if (hexOk) {
                        sb.append('%').append(pathAndQuery[i + 1]).append(pathAndQuery[i + 2])
                        i += 3
                        continue
                    } else {
                        sb.append("%25")
                    }
                }
                ch.code > 0x7F -> {
                    val cp = Character.codePointAt(pathAndQuery, i)
                    val utf8 = String(Character.toChars(cp)).toByteArray(Charsets.UTF_8)
                    for (b in utf8) {
                        sb.append('%').append(String.format("%02X", b.toInt() and 0xFF))
                    }
                    i += Character.charCount(cp)
                    continue
                }
                ch.isISOControl() -> return null
                else -> sb.append(ch)
            }
            i++
        }
        return runCatching {
            val uri = java.net.URI(sb.toString())
            if (uri.host.isNullOrBlank() && authority.substringBefore(':').isBlank()) null else uri.toASCIIString()
        }.getOrNull()
    }

    private fun Char.isDigitOrHex(): Boolean =
        this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'

    private fun parseSimpleJsonStringMap(json: String): Map<String, String> {
        if (json.isBlank() || json == "{}") return emptyMap()
        val out = linkedMapOf<String, String>()
        val regex = Regex(""""((?:\\.|[^"\\])*)"\s*:\s*"((?:\\.|[^"\\])*)"""")
        for (m in regex.findAll(json)) {
            val k = unescapeJsonString(m.groupValues[1])
            val v = unescapeJsonString(m.groupValues[2])
            if (k.isNotEmpty()) out[k] = v
        }
        return out
    }

    private fun unescapeJsonString(raw: String): String =
        raw.replace("\\\"", "\"").replace("\\\\", "\\").replace("\\n", "\n").replace("\\t", "\t")

    /**
     * 解析音频头部（及可选尾部）字节中的内嵌标题、歌手、专辑、歌词与封面字节。
     */
    fun parseAudioEmbeddedMetadata(
        headBytes: ByteArray,
        tailBytes: ByteArray = ByteArray(0),
    ): AudioEmbeddedMetadataDto {
        if (headBytes.size < 4) return AudioEmbeddedMetadataDto()
        return runCatching {
            val res = ffiParseAudioEmbeddedMetadata(headBytes, tailBytes)
            AudioEmbeddedMetadataDto(
                title = res.title,
                artist = res.artist,
                album = res.album,
                lyrics = res.lyrics,
                coverMime = res.coverMime,
                coverBytes = res.coverBytes,
                neededHeadBytes = res.neededHeadBytes?.toLong(),
                neededTailBytes = res.neededTailBytes?.toLong(),
            )
        }.getOrElse { AudioEmbeddedMetadataDto() }
    }

    // ==================== 通行密钥（moviepilot.passkey v1）与反代地址重绑 ====================

    /** 判断服务地址是否满足 WebAuthn 安全来源要求（`https://` 或回环地址）。 */
    fun isPasskeySecureOrigin(serverUrl: String): Boolean =
        runCatching { ffiIsPasskeySecureOrigin(serverUrl) }
            .getOrElse { fallbackIsPasskeySecureOrigin(serverUrl) }

    /** 解析 `/api/v1/auth/providers` 响应，仅当存在已启用系统级 `passkey` 时返回 `true`。 */
    fun parsePasskeyProviderEnabled(body: String): Boolean =
        runCatching { ffiParsePasskeyProviderEnabled(body) }
            .getOrElse { err ->
                if (err is UnsatisfiedLinkError || err is NoClassDefFoundError) {
                    fallbackParsePasskeyProviderEnabled(body)
                } else {
                    false
                }
            }

    /** 校验 `<server>/native-passkey.json` 静态协议标记是否精确为 `moviepilot.passkey` v1。 */
    fun supportsPasskeyFrontendMarker(body: String): Boolean =
        runCatching { ffiSupportsPasskeyFrontendMarker(body) }
            .getOrElse { fallbackSupportsPasskeyFrontendMarker(body) }

    /** 校验 `authenticate/start` 响应并构造公开浏览器挑战跳转 URL 与内存事务。 */
    fun preparePasskeyRequest(
        startBody: String,
        serverUrl: String,
        stateHex: String,
    ): Result<PreparedPasskeyRequestDto> = runCatching {
        val raw = ffiPreparePasskeyRequestJson(startBody, serverUrl, stateHex)
        syncJson.decodeFromString<PreparedPasskeyRequestDto>(raw)
    }.recoverCatching { err ->
        if (err is UnsatisfiedLinkError || err is NoClassDefFoundError) {
            fallbackPreparePasskeyRequest(startBody, serverUrl, stateHex)
        } else {
            throw err
        }
    }

    /** 校验 `moviepilot://passkey/callback#result=...` 并返回 `PasskeyCallbackOutcomeDto`。 */
    fun verifyPasskeyCallback(
        callbackUrl: String,
        serverUrl: String,
        expectedState: String,
        expectedChallenge: String,
        transactionToken: String,
    ): PasskeyCallbackOutcomeDto = runCatching {
        val raw = ffiVerifyPasskeyCallbackJson(
            callbackUrl,
            serverUrl,
            expectedState,
            expectedChallenge,
            transactionToken,
        )
        syncJson.decodeFromString<PasskeyCallbackOutcomeDto>(raw)
    }.getOrElse { err ->
        if (err is UnsatisfiedLinkError || err is NoClassDefFoundError) {
            fallbackVerifyPasskeyCallback(
                callbackUrl,
                serverUrl,
                expectedState,
                expectedChallenge,
                transactionToken,
            )
        } else {
            PasskeyCallbackOutcomeDto(
                ok = false,
                errorCode = "invalid",
                errorMessageZh = "通行密钥验证结果无效，请重新尝试。",
            )
        }
    }

    private fun fallbackNormalizeAddress(raw: String): String {
        val trimmed = raw.trim()
        require(trimmed.isNotEmpty()) { "服务地址不能为空" }
        val candidate = if ("://" in trimmed) trimmed else "http://$trimmed"
        val uri = java.net.URI(candidate)
        val scheme = uri.scheme?.lowercase() ?: error("仅支持 http 或 https 协议")
        require(scheme == "http" || scheme == "https") { "仅支持 http 或 https 协议" }
        require(uri.rawUserInfo == null) { "服务地址不允许内嵌用户名或密码" }
        val host = uri.host?.lowercase()?.takeIf { it.isNotBlank() } ?: error("服务地址缺少合法主机名")
        val defaultPort = if (scheme == "https") 443 else 80
        val port = if (uri.port > 0 && uri.port != defaultPort) ":${uri.port}" else ""
        val cleanPath = (uri.rawPath ?: "").trimEnd('/')
        return "$scheme://$host$port$cleanPath"
    }

    private fun fallbackOriginKey(normalizedOrCandidate: String): Pair<String, String>? {
        val uri = runCatching { java.net.URI(normalizedOrCandidate.trim()) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        if (uri.rawUserInfo != null) return null
        val host = uri.host?.lowercase()?.takeIf { it.isNotBlank() } ?: return null
        val defaultPort = if (scheme == "https") 443 else 80
        val effectivePort = if (uri.port > 0) uri.port else defaultPort
        val origin = "$scheme://$host:$effectivePort"
        val path = uri.rawPath ?: ""
        return origin to path
    }

    private fun fallbackContainsUrl(baseUrl: String, candidateUrl: String): Boolean {
        val normBase = runCatching { fallbackNormalizeAddress(baseUrl) }.getOrNull() ?: return false
        val (baseOrigin, basePathRaw) = fallbackOriginKey(normBase) ?: return false
        val (candOrigin, candPath) = fallbackOriginKey(candidateUrl) ?: return false
        if (baseOrigin != candOrigin) return false
        val basePath = basePathRaw.trimEnd('/')
        if (basePath.isEmpty()) return true
        return candPath == basePath || candPath.startsWith("$basePath/")
    }

    private fun fallbackRebaseInstanceApiUrl(baseUrl: String, rawUrl: String): String? {
        val normBase = runCatching { fallbackNormalizeAddress(baseUrl) }.getOrNull() ?: return null
        val trimmed = rawUrl.trim()
        if (trimmed.isEmpty() || trimmed.any { it.isWhitespace() } || '#' in trimmed) return null
        val basePath = (runCatching { java.net.URI(normBase).rawPath }.getOrNull() ?: "").trimEnd('/')
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            val uri = runCatching { java.net.URI(trimmed) }.getOrNull() ?: return null
            if (uri.rawUserInfo != null || uri.rawFragment != null) return null
            if (fallbackContainsUrl(normBase, trimmed)) return trimmed
            val path = uri.rawPath ?: return null
            if (path.split('/').any { it == ".." }) return null
            val apiSuffix = when {
                basePath.isNotEmpty() && path.startsWith("$basePath/api/v1/") -> path.substring(basePath.length)
                path.startsWith("/api/v1/") -> path
                else -> return null
            }
            val query = uri.rawQuery?.let { "?$it" }.orEmpty()
            val rebased = "$normBase$apiSuffix$query"
            return rebased.takeIf { fallbackContainsUrl(normBase, it) }
        }
        if (trimmed.startsWith("//") || "://" in trimmed) return null
        val relPath = trimmed.substringBefore('?')
        val query = if ('?' in trimmed) "?" + trimmed.substringAfter('?') else ""
        val withSlash = if (relPath.startsWith('/')) relPath else "/$relPath"
        if (withSlash.split('/').any { it == ".." }) return null
        val suffix = if (basePath.isNotEmpty() && (withSlash == basePath || withSlash.startsWith("$basePath/"))) {
            withSlash.substring(basePath.length)
        } else {
            withSlash
        }
        val rebased = "$normBase$suffix$query"
        return rebased.takeIf { fallbackContainsUrl(normBase, it) }
    }

    private fun fallbackIsPasskeySecureOrigin(serverUrl: String): Boolean {
        val norm = runCatching { fallbackNormalizeAddress(serverUrl) }.getOrNull() ?: return false
        val uri = runCatching { java.net.URI(norm) }.getOrNull() ?: return false
        if (uri.scheme == "https") return true
        val bareHost = uri.host?.trim('[', ']')?.lowercase() ?: return false
        return bareHost == "localhost" || bareHost == "127.0.0.1" || bareHost == "::1"
    }

    private fun fallbackParsePasskeyProviderEnabled(body: String): Boolean {
        if (body.length > 65_536) return false
        val el = runCatching { syncJson.parseToJsonElement(body) }.getOrNull() ?: return false
        val arr = when (el) {
            is kotlinx.serialization.json.JsonArray -> el
            is kotlinx.serialization.json.JsonObject -> {
                val ok = (el["success"] as? kotlinx.serialization.json.JsonPrimitive)?.let {
                    !it.isString && it.content == "true"
                } ?: false
                if (!ok) return false
                el["data"] as? kotlinx.serialization.json.JsonArray ?: return false
            }
            else -> return false
        }
        if (arr.size > 128) return false
        return arr.any { item ->
            val obj = item as? kotlinx.serialization.json.JsonObject ?: return@any false
            val t = (obj["type"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
            val m = (obj["method"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
            val en = (obj["enabled"] as? kotlinx.serialization.json.JsonPrimitive)?.let { !it.isString && it.content == "true" } == true
            t == "system" && m == "passkey" && en
        }
    }

    private fun fallbackSupportsPasskeyFrontendMarker(body: String): Boolean {
        if (body.toByteArray().size > 1024) return false
        val obj = runCatching {
            syncJson.parseToJsonElement(body) as? kotlinx.serialization.json.JsonObject
        }.getOrNull() ?: return false
        if (obj.size != 2) return false
        val proto = (obj["protocol"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val ver = (obj["version"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { !it.isString }?.content?.toDoubleOrNull()
        return proto == "moviepilot.passkey" && ver == 1.0
    }

    private fun fallbackEncodeBase64Url(bytes: ByteArray): String =
        java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    private fun fallbackDecodeCanonicalBase64Url(raw: String, min: Int, max: Int): ByteArray? {
        val maxChars = (max * 4 + 2) / 3
        if (raw.isEmpty() || raw.length > maxChars) return null
        if (!raw.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' }) return null
        val decoded = runCatching { java.util.Base64.getUrlDecoder().decode(raw) }.getOrNull() ?: return null
        if (decoded.size !in min..max) return null
        return decoded.takeIf { fallbackEncodeBase64Url(it) == raw }
    }

    private fun fallbackPreparePasskeyRequest(
        startBody: String,
        serverUrl: String,
        stateHex: String,
    ): PreparedPasskeyRequestDto {
        val norm = runCatching { fallbackNormalizeAddress(serverUrl) }.getOrElse { error("unsupported") }
        if (!fallbackIsPasskeySecureOrigin(norm) || stateHex.trim().length != 64) error("unsupported")
        val stateBytes = ByteArray(32) { i ->
            stateHex.trim().substring(i * 2, i * 2 + 2).toIntOrNull(16)?.toByte() ?: error("invalid")
        }
        val root = (syncJson.parseToJsonElement(startBody) as? kotlinx.serialization.json.JsonObject) ?: error("invalid")
        val ok = (root["success"] as? kotlinx.serialization.json.JsonPrimitive)?.let { !it.isString && it.content == "true" } == true
        if (!ok) error("failed")
        val data = root["data"] as? kotlinx.serialization.json.JsonObject ?: error("failed")
        val token = (data["transaction_token"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content ?: error("failed")
        if (token.isEmpty() || token.toByteArray().size > 8192 || token.any { it.isISOControl() }) error("failed")
        val optionsObj = when (val optEl = data["options"]) {
            is kotlinx.serialization.json.JsonObject -> optEl
            is kotlinx.serialization.json.JsonPrimitive -> {
                if (!optEl.isString) error("invalid")
                (syncJson.parseToJsonElement(optEl.content) as? kotlinx.serialization.json.JsonObject) ?: error("invalid")
            }
            else -> error("invalid")
        }
        val allowedKeys = setOf("challenge", "rpId", "timeout", "allowCredentials", "userVerification")
        if (!optionsObj.keys.all { it in allowedKeys }) error("invalid")
        val challenge = (optionsObj["challenge"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content ?: error("invalid")
        fallbackDecodeCanonicalBase64Url(challenge, 16, 1024) ?: error("invalid")
        val host = java.net.URI(norm).host.trim('[', ']').lowercase()
        (optionsObj["rpId"] as? kotlinx.serialization.json.JsonPrimitive)?.let { rpPrim ->
            if (!rpPrim.isString) error("invalid")
            val rp = rpPrim.content
            val matches = rp.isNotEmpty() && rp == rp.lowercase() &&
                (rp == host || ('.' in rp && ':' !in rp && host.endsWith(".$rp")))
            if (!matches) error("invalid")
        }
        var timeoutSecs = 120.0
        (optionsObj["timeout"] as? kotlinx.serialization.json.JsonPrimitive)?.let { tPrim ->
            if (tPrim.isString) error("invalid")
            val ms = tPrim.content.toDoubleOrNull() ?: error("invalid")
            if (!ms.isFinite() || ms < 1.0) error("invalid")
            timeoutSecs = minOf(ms / 1000.0, timeoutSecs)
        }
        val state = fallbackEncodeBase64Url(stateBytes)
        val reqJson = kotlinx.serialization.json.buildJsonObject {
            put("version", kotlinx.serialization.json.JsonPrimitive(1))
            put("state", kotlinx.serialization.json.JsonPrimitive(state))
            put("options", optionsObj)
        }.toString()
        val encodedReq = fallbackEncodeBase64Url(reqJson.toByteArray(Charsets.UTF_8))
        return PreparedPasskeyRequestDto(
            authorizationUrl = "$norm/native-passkey.html#request=$encodedReq",
            state = state,
            challenge = challenge,
            transactionToken = token,
            timeoutSecs = kotlin.math.ceil(timeoutSecs).toLong().coerceIn(1L, 120L),
        )
    }

    private fun fallbackVerifyPasskeyCallback(
        callbackUrl: String,
        serverUrl: String,
        expectedState: String,
        expectedChallenge: String,
        transactionToken: String,
    ): PasskeyCallbackOutcomeDto {
        fun fail(code: String, msg: String?): PasskeyCallbackOutcomeDto =
            PasskeyCallbackOutcomeDto(ok = false, errorCode = code, errorMessageZh = msg)
        if (transactionToken.isEmpty()) return fail("expired", "通行密钥验证已过期，请重新尝试。")
        val norm = runCatching { fallbackNormalizeAddress(serverUrl) }.getOrNull()
            ?: return fail("expired", "通行密钥验证已过期，请重新尝试。")
        val (baseOrigin, _) = fallbackOriginKey(norm) ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        if (!callbackUrl.startsWith("moviepilot://passkey/callback#result=")) {
            return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        }
        val encoded = callbackUrl.removePrefix("moviepilot://passkey/callback#result=")
        val bytes = fallbackDecodeCanonicalBase64Url(encoded, 1, 24_576)
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val resultObj = runCatching {
            syncJson.parseToJsonElement(String(bytes, Charsets.UTF_8)) as? kotlinx.serialization.json.JsonObject
        }.getOrNull() ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val ver = (resultObj["version"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { !it.isString }?.content?.toDoubleOrNull()
        val st = (resultObj["state"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        if (ver != 1.0 || st != expectedState || resultObj.size != 3) {
            return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        }
        (resultObj["error"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content?.let { errCode ->
            return when (errCode) {
                "canceled" -> fail("canceled", null)
                "expired" -> fail("expired", "通行密钥验证已过期，请重新尝试。")
                "unsupported" -> fail("unsupported", "当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。")
                "invalid" -> fail("invalid", "通行密钥验证结果无效，请重新尝试。")
                "failed" -> fail("failed", "未能完成通行密钥验证，请重新尝试。")
                else -> fail("invalid", "通行密钥验证结果无效，请重新尝试。")
            }
        }
        val cred = resultObj["credential"] as? kotlinx.serialization.json.JsonObject
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val id = (cred["id"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val rawId = (cred["rawId"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val cType = (cred["type"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val resp = cred["response"] as? kotlinx.serialization.json.JsonObject
        if (cred.size != 4 || cType != "public-key" || id == null || id != rawId || resp == null || resp.size != 4) {
            return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        }
        fallbackDecodeCanonicalBase64Url(id, 1, 1024) ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val authData = (resp["authenticatorData"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val clientB64 = (resp["clientDataJSON"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val sig = (resp["signature"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        fallbackDecodeCanonicalBase64Url(authData, 37, 2048) ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        fallbackDecodeCanonicalBase64Url(sig, 1, 2048) ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val clientBytes = fallbackDecodeCanonicalBase64Url(clientB64, 1, 4096)
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val clientObj = runCatching {
            syncJson.parseToJsonElement(String(clientBytes, Charsets.UTF_8)) as? kotlinx.serialization.json.JsonObject
        }.getOrNull() ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        val wType = (clientObj["type"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val wChal = (clientObj["challenge"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val wOrigin = (clientObj["origin"] as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
        val cross = clientObj["crossOrigin"]
        val crossOk = cross == null || (cross is kotlinx.serialization.json.JsonPrimitive && !cross.isString && cross.content == "false")
        val (candOrigin, candPath) = wOrigin?.takeIf { !it.endsWith('/') }?.let { fallbackOriginKey(it) }
            ?: return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        if (wType != "webauthn.get" || wChal != expectedChallenge || !crossOk || candOrigin != baseOrigin || candPath.isNotEmpty()) {
            return fail("invalid", "通行密钥验证结果无效，请重新尝试。")
        }
        val finishJson = kotlinx.serialization.json.buildJsonObject {
            put("credential", cred)
            put("transaction_token", kotlinx.serialization.json.JsonPrimitive(transactionToken))
        }.toString()
        return PasskeyCallbackOutcomeDto(ok = true, finishBodyJson = finishJson)
    }
}
