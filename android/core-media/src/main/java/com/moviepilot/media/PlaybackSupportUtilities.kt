package com.moviepilot.media

import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Rational
import com.moviepilot.rustbridge.RustCoreBridge
import java.io.File

/**
 * 画中画（PiP）动态宽高比收敛与 Android 10–11（API 29–30）Home 键自动小窗桥接器。
 */
object PlaybackPipBridge {
    private const val MIN_RATIO = 100.0 / 239.0
    private const val MAX_RATIO = 239.0 / 100.0

    /** API 29–30 下 `MainActivity.onUserLeaveHint()` 触发的自动进入 PiP 回调。 */
    @Volatile
    var onUserLeaveHintCallback: (() -> Unit)? = null

    /** 由宿主 Activity 在 `onUserLeaveHint()` 调用。 */
    fun notifyUserLeaveHint() {
        onUserLeaveHintCallback?.invoke()
    }

    /** 计算收敛在 Android 系统合法区间 `[100:239, 239:100]` 内的宽高整数对（异常尺寸回退 `16:9`）。 */
    fun clampAspectRatioPair(videoWidth: Int, videoHeight: Int): Pair<Int, Int> {
        if (videoWidth <= 0 || videoHeight <= 0) return 16 to 9
        val ratio = videoWidth.toDouble() / videoHeight.toDouble()
        return when {
            ratio < MIN_RATIO -> 100 to 239
            ratio > MAX_RATIO -> 239 to 100
            else -> videoWidth to videoHeight
        }
    }

    /** 计算供 `PictureInPictureParams.Builder.setAspectRatio` 使用的安全 `Rational`。 */
    fun computeClampedPipAspectRatio(videoWidth: Int, videoHeight: Int): Rational {
        val (w, h) = clampAspectRatioPair(videoWidth, videoHeight)
        return Rational(w, h)
    }
}

/**
 * 中文字幕轨道智能匹配工具（供播放器初始自动选轨与详情页播前预选器共用）。
 */
object ChineseSubtitleMatcher {
    private val SIMPLIFIED_TOKENS = listOf("chs", "zh-cn", "zh_cn", "zh-hans", "zh_hans", "zh-sg", "简体", "简中", "简英")
    private val TRADITIONAL_TOKENS = listOf("cht", "zh-tw", "zh_tw", "zh-hk", "zh_hk", "zh-hant", "zh_hant", "繁体", "繁中", "繁英")
    private val GENERIC_CHINESE_LANGS = setOf("zh", "chi", "zho", "cmn", "yue", "cn")
    private val CHINESE_LABEL_KEYWORDS = listOf("中文", "简体", "繁体", "中字", "简中", "繁中", "双语", "国配字幕", "chinese")

    /** 判断给定语言代码或轨道标签是否属于中文字幕轨道。 */
    fun isChineseSubtitle(language: String?, label: String?): Boolean =
        scoreChineseSubtitle(language, label) > 0

    /**
     * 对候选字幕轨道打分（`<= 0` 表示非中文字幕，分值越高优先级越高：简体 > 通用中文 > 繁体，外挂/默认微调加分）。
     */
    fun scoreChineseSubtitle(
        language: String?,
        label: String?,
        isDefault: Boolean = false,
        isExternal: Boolean = false,
    ): Int {
        val lang = language?.trim()?.lowercase().orEmpty()
        val lbl = label?.trim()?.lowercase().orEmpty()
        val combined = "$lang $lbl"
        val baseScore = when {
            SIMPLIFIED_TOKENS.any { combined.contains(it) } -> 100
            TRADITIONAL_TOKENS.any { combined.contains(it) } -> 80
            lang in GENERIC_CHINESE_LANGS || lang.startsWith("zh-") || lang.startsWith("zh_") -> 90
            CHINESE_LABEL_KEYWORDS.any { combined.contains(it) } -> 85
            else -> return 0
        }
        var bonus = 0
        if (isExternal) bonus += 4
        if (isDefault) bonus += 2
        return baseScore + bonus
    }
}

/**
 * 外部第三方播放器选择器与媒体服务器原生客户端（`emby://` / `jellyfin://` / `plex://` / `trimemedia://`）唤起器。
 */
object ExternalPlayerLauncher {

    /**
     * 拉起系统外部音视频播放器选择面板（兼容 VLC / MPV / MX Player 等通用 HTTP 请求头传递约定）。
     * 安全红线：严禁把实例主 `Authorization` / `Cookie` / 媒体服务器直连令牌传递给第三方外部应用。
     */
    fun launchExternalPlayerChooser(
        context: Context,
        streamUrl: String,
        title: String,
        isAudio: Boolean = false,
        headers: Map<String, String> = emptyMap(),
    ): Boolean {
        if (streamUrl.isBlank()) return false
        val safeHeaders = PlaybackHttpDataSource.stripAllSensitiveHeaders(headers)
        return runCatching {
            val uri = Uri.parse(streamUrl)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, if (isAudio) "audio/*" else "video/*")
                putExtra("title", title)
                putExtra("android.intent.extra.TITLE", title)
                if (uri.scheme.equals("content", ignoreCase = true)) {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                if (safeHeaders.isNotEmpty() && (uri.scheme == "http" || uri.scheme == "https")) {
                    val flatHeaders = ArrayList<String>(safeHeaders.size * 2)
                    val lineHeaders = ArrayList<String>(safeHeaders.size)
                    safeHeaders.forEach { (k, v) ->
                        flatHeaders.add(k)
                        flatHeaders.add(v)
                        lineHeaders.add("$k: $v")
                    }
                    putExtra("headers", flatHeaders.toTypedArray())
                    putExtra("http-header-fields", lineHeaders.toTypedArray())
                }
            }
            val chooser = Intent.createChooser(intent, "选择外部播放器").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(chooser)
            true
        }.getOrDefault(false)
    }

    /**
     * 构造媒体服务器官方客户端 Scheme 深度链接（对齐 iOS `emby://` / `jellyfin://` / `plex://` / `trimemedia://` 规范）。
     */
    fun buildMediaServerDeepLink(
        serverType: String,
        serverName: String,
        itemId: String,
        playUrl: String?,
    ): String? {
        val kind = serverType.ifBlank { serverName }.trim().lowercase()
        val hostPort = extractHostPort(playUrl)
        return when {
            kind.contains("emby") -> {
                val mediaId = itemId.ifBlank {
                    firstCapture("""[?&]id=([^&#]+)""", playUrl)
                        ?: firstCapture("""/items?/([^/?#]+)""", playUrl).orEmpty()
                }
                val serverId = firstCapture("""[?&]serverId=([^&#]+)""", playUrl)
                when {
                    mediaId.isNotBlank() && !serverId.isNullOrBlank() ->
                        "emby://items?serverId=${Uri.encode(serverId)}&itemId=${Uri.encode(mediaId)}"
                    mediaId.isNotBlank() ->
                        "emby://items?itemId=${Uri.encode(mediaId)}"
                    !hostPort.isNullOrBlank() -> "emby://$hostPort"
                    else -> "emby://"
                }
            }

            kind.contains("jellyfin") -> {
                val mediaId = firstCapture("""/details\?id=([^&#]+)""", playUrl) ?: itemId
                val serverId = firstCapture("""[?&]serverId=([^&#]+)""", playUrl)
                when {
                    mediaId.isNotBlank() && !hostPort.isNullOrBlank() -> buildString {
                        append("jellyfin://$hostPort/item/$mediaId")
                        if (!serverId.isNullOrBlank()) append("?serverId=$serverId")
                    }
                    !hostPort.isNullOrBlank() -> "jellyfin://$hostPort"
                    else -> "jellyfin://"
                }
            }

            kind.contains("plex") -> {
                val token = firstCapture("""X-Plex-Token=([^&#]+)""", playUrl)
                val serverId = firstCapture("""/server/([^/]+)/details""", playUrl)
                val keyVal = firstCapture("""[?&]key=([^&#]+)""", playUrl)
                if (!serverId.isNullOrBlank() && !keyVal.isNullOrBlank()) {
                    val cleanId = firstCapture("""/library/metadata/(\d+)""", Uri.decode(keyVal)) ?: itemId
                    buildString {
                        append("plex://play/?metadataKey=/library/metadata/$cleanId&server=$serverId")
                        if (!token.isNullOrBlank()) append("&X-Plex-Token=$token")
                    }
                } else {
                    buildString {
                        append("plex://library/sections")
                        if (!token.isNullOrBlank()) append("?X-Plex-Token=$token")
                    }
                }
            }

            kind.contains("trimemedia") || kind.contains("fnos") || kind.contains("飞牛") -> {
                val mediaId = firstCapture("""/item/([^/?#]+)""", playUrl)
                    ?: firstCapture("""[?&]id=([^&#]+)""", playUrl)
                    ?: itemId
                if (mediaId.isNotBlank() && !hostPort.isNullOrBlank()) {
                    "trimemedia://$hostPort/item/$mediaId"
                } else if (!hostPort.isNullOrBlank()) {
                    "trimemedia://$hostPort"
                } else {
                    "trimemedia://"
                }
            }

            else -> null
        }
    }

    /**
     * 优先拉起媒体服务器原生客户端（Emby / Jellyfin / Plex / 飞牛影视），若本机未安装则平滑回退浏览器 `playUrl`。
     */
    fun launchMediaServerClientOrFallback(
        context: Context,
        serverType: String,
        serverName: String,
        itemId: String,
        playUrl: String?,
    ): Boolean {
        val schemeUrl = buildMediaServerDeepLink(serverType, serverName, itemId, playUrl)
        if (!schemeUrl.isNullOrBlank()) {
            val launched = runCatching {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(schemeUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                true
            }.getOrDefault(false)
            if (launched) return true
        }
        if (!playUrl.isNullOrBlank()) {
            return runCatching {
                val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse(playUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(webIntent)
                true
            }.getOrDefault(false)
        }
        return false
    }

    private fun extractHostPort(rawUrl: String?): String? {
        if (rawUrl.isNullOrBlank()) return null
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull() ?: return null
        val host = uri.host?.takeIf { it.isNotBlank() } ?: return null
        return if (uri.port > 0) "$host:${uri.port}" else host
    }

    private fun firstCapture(pattern: String, text: String?): String? {
        if (text.isNullOrBlank()) return null
        return Regex(pattern, RegexOption.IGNORE_CASE).find(text)?.groupValues?.getOrNull(1)?.takeIf { it.isNotBlank() }
    }
}

/**
 * 本机 `content://` / `file://` 媒体文件真实元数据提取器：
 * 结合 `OpenableColumns.DISPLAY_NAME` 与 `MediaMetadataRetriever` 解析曲名、艺人、专辑及内嵌封面图。
 */
object LocalMediaMetadataExtractor {

    /** 解析本机 URI 的可读文件名。 */
    fun resolveDisplayName(context: Context, uri: Uri): String {
        if (uri.scheme.equals("content", ignoreCase = true)) {
            val cursor = runCatching {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            }.getOrNull()
            cursor?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val name = c.getString(idx)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() } ?: "本机媒体文件"
    }

    /** 提取本机音视频完整元数据并构造未绑定会话（`isSessionBound = false`）的 `MediaPlaybackRequest`。 */
    fun buildLocalPlaybackRequest(
        context: Context,
        uri: Uri,
        mimeHint: String? = null,
    ): MediaPlaybackRequest {
        val displayName = resolveDisplayName(context, uri)
        val resolvedMime = mimeHint?.takeIf { it.isNotBlank() }
            ?: runCatching { context.contentResolver.getType(uri) }.getOrNull().orEmpty()

        if (RustCoreBridge.isStrmPath(displayName) || RustCoreBridge.isStrmPath(uri.path.orEmpty())) {
            val strmBytes = runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    val buf = ByteArray(65_537)
                    var total = 0
                    while (total < buf.size) {
                        val n = input.read(buf, total, buf.size - total)
                        if (n <= 0) break
                        total += n
                    }
                    if (total in 1..65_536) buf.copyOf(total) else null
                }
            }.getOrNull()
            val strmText = strmBytes?.let { com.moviepilot.rustbridge.MoviePilotRepository.decodeStrmBytes(it) }
            val spec = strmText?.let { RustCoreBridge.parseStrm(it, displayName) }
            if (spec != null) {
                val cleanStem = displayName.substringBeforeLast('.').ifBlank { displayName }
                return MediaPlaybackRequest(
                    url = spec.url,
                    title = cleanStem,
                    subtitle = "STRM 直链播放",
                    isAudio = spec.mediaKind == "audio",
                    streamHeaders = spec.headers,
                    isSessionBound = false,
                )
            }
        }

        var metaTitle: String? = null
        var metaArtist: String? = null
        var metaAlbum: String? = null
        var hasVideoTrack: Boolean? = null
        var embeddedBytes: ByteArray? = null
        var cachedArtworkUri: String? = null

        val retriever = MediaMetadataRetriever()
        try {
            runCatching {
                retriever.setDataSource(context, uri)
                metaTitle = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)?.trim()?.takeIf { it.isNotEmpty() }
                metaArtist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)?.trim()?.takeIf { it.isNotEmpty() }
                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)?.trim()?.takeIf { it.isNotEmpty() }
                metaAlbum = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)?.trim()?.takeIf { it.isNotEmpty() }
                val hasVideoStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO)
                if (!hasVideoStr.isNullOrBlank()) {
                    hasVideoTrack = hasVideoStr.equals("yes", ignoreCase = true)
                }
                embeddedBytes = retriever.embeddedPicture?.takeIf { it.isNotEmpty() }
                if (embeddedBytes != null) {
                    val artDir = File(context.cacheDir, "mp_local_artwork").apply { mkdirs() }
                    val artFile = File(artDir, "art_${uri.toString().hashCode()}.jpg")
                    artFile.writeBytes(embeddedBytes!!)
                    cachedArtworkUri = Uri.fromFile(artFile).toString()
                }
            }
        } finally {
            runCatching { retriever.release() }
        }

        var embeddedLyrics: String? = null
        val embeddedTags = EmbeddedAudioMetadataFetcher.extractFromLocalUriBlocking(context, uri)
        if (embeddedTags != null) {
            if (metaTitle.isNullOrBlank()) metaTitle = embeddedTags.title?.takeIf { it.isNotBlank() }
            if (metaArtist.isNullOrBlank()) metaArtist = embeddedTags.artist?.takeIf { it.isNotBlank() }
            if (metaAlbum.isNullOrBlank()) metaAlbum = embeddedTags.album?.takeIf { it.isNotBlank() }
            embeddedLyrics = embeddedTags.lyrics?.takeIf { it.isNotBlank() }
            if (embeddedBytes == null && embeddedTags.coverBytes != null && embeddedTags.coverBytes!!.isNotEmpty()) {
                embeddedBytes = embeddedTags.coverBytes
                runCatching {
                    val artDir = File(context.cacheDir, "mp_local_artwork").apply { mkdirs() }
                    val artFile = File(artDir, "art_${uri.toString().hashCode()}.jpg")
                    artFile.writeBytes(embeddedBytes!!)
                    cachedArtworkUri = Uri.fromFile(artFile).toString()
                }
            }
        }

        val detectedByName = RustCoreBridge.detectMediaKind(displayName, false)
        val isAudio = when {
            resolvedMime.startsWith("audio/", ignoreCase = true) -> true
            resolvedMime.startsWith("video/", ignoreCase = true) -> false
            detectedByName == "audio" -> true
            detectedByName == "video" -> false
            hasVideoTrack == false -> true
            else -> false
        }

        val cleanDisplayStem = if (isAudio && displayName.contains('.')) {
            displayName.substringBeforeLast('.').ifBlank { displayName }
        } else {
            displayName
        }
        val subtitleParts = listOfNotNull(metaArtist, metaAlbum)
        val subtitle = if (subtitleParts.isNotEmpty()) {
            subtitleParts.joinToString(" · ")
        } else {
            if (isAudio) "本机音乐" else "本机视频"
        }

        return MediaPlaybackRequest(
            url = uri.toString(),
            title = metaTitle ?: cleanDisplayStem,
            subtitle = subtitle,
            albumTitle = metaAlbum.orEmpty(),
            artworkUrl = cachedArtworkUri,
            artworkBytes = embeddedBytes,
            isAudio = isAudio,
            lyricsLrc = embeddedLyrics,
            isSessionBound = false,
        )
    }
}
