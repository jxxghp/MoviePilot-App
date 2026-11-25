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
import com.moviepilot.rustcore.buildV3EndpointUrl
import com.moviepilot.rustcore.classifyHttpAuthStatus
import com.moviepilot.rustcore.computeMedalPalette
import com.moviepilot.rustcore.computeSubscribeProgress
import com.moviepilot.rustcore.coreVersion
import com.moviepilot.rustcore.decodeJwtTokenClaims
import com.moviepilot.rustcore.detectPlayableMediaKind
import com.moviepilot.rustcore.evaluatePluginExpression
import com.moviepilot.rustcore.evaluateUserPermissions
import com.moviepilot.rustcore.filterAndGroupResources
import com.moviepilot.rustcore.normalizePendingPlaybackStopsJson
import com.moviepilot.rustcore.normalizeServerAddress
import com.moviepilot.rustcore.parseAgentMarkdown
import com.moviepilot.rustcore.parseDeepLinkJson
import com.moviepilot.rustcore.parseStrmContent
import com.moviepilot.rustcore.planPlaybackSyncStepJson
import com.moviepilot.rustcore.planPluginFormJson
import com.moviepilot.rustcore.serverAddressContains
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

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

object RustCoreBridge {

    /** 返回 Rust 共享内核版本号，用于启动冒烟检查与关于页展示。 */
    fun version(): String = runCatching { coreVersion() }.getOrDefault("2.0.3")

    /** 规范化 MoviePilot 服务地址，保留部署子路径并拒绝内嵌凭据。 */
    fun normalizeAddress(raw: String): Result<String> = runCatching {
        normalizeServerAddress(raw)
    }

    /** 校验目标 URL 是否严格属于当前实例源及部署子路径。 */
    fun containsUrl(baseUrl: String, candidateUrl: String): Boolean =
        runCatching { serverAddressContains(baseUrl, candidateUrl) }.getOrDefault(false)

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

    private fun fallbackPlanPlaybackSyncStep(
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
                    emit("started", null, input.isPaused) { s ->
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
                emit("paused", "pause", true) { s ->
                    s.copy(startedSent = true, pausedSinceMs = pausedSince)
                }
            }
            "resume" -> {
                if (next.stoppedSent) {
                    emit("started", null, false) { s ->
                        s.copy(
                            startedSent = true,
                            stoppedSent = false,
                            pausedSinceMs = null,
                            lastPlayingTickAtMs = now,
                        )
                    }
                } else {
                    emit("playing", "unpause", false) { s ->
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
                    emit(st, "timeupdate", input.isPaused) { s ->
                        s.copy(startedSent = true, lastSeekAtMs = now)
                    }
                }
            }
            "track_change" -> {
                if (next.stoppedSent) return skip("stopped", true)
                val st = if (input.isPaused) "paused" else "playing"
                emit(st, "trackchange", input.isPaused) { s ->
                    s.copy(startedSent = true)
                }
            }
            "background" -> {
                if (next.stoppedSent) return skip("stopped", true)
                val pausedSince = if (input.isPaused) (next.pausedSinceMs ?: now) else null
                val st = if (input.isPaused) "paused" else "playing"
                emit(st, if (input.isPaused) "pause" else "timeupdate", input.isPaused) { s ->
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
                    return emit("started", null, input.isPaused) { s ->
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
                        emit("paused", "timeupdate", true)
                    } else {
                        skip("paused", true, next)
                    }
                } else {
                    next = next.copy(pausedSinceMs = null)
                    val elapsed = next.lastReportAtMs?.let { now - it } ?: Long.MAX_VALUE
                    if (elapsed >= 10_000L) {
                        emit("playing", "timeupdate", false)
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
}
