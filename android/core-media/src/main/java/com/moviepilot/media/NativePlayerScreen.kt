package com.moviepilot.media

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color as AndroidColor
import android.graphics.drawable.BitmapDrawable
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.SurfaceView
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Cast
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.Comment
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Fullscreen
import androidx.compose.material.icons.rounded.FullscreenExit
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.Lyrics
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.PictureInPictureModeChangedInfo
import androidx.core.util.Consumer
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.media3.ui.SubtitleView
import coil.compose.AsyncImage
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.moviepilot.designsystem.ExpressiveDockAction
import com.moviepilot.designsystem.ExpressiveGroupedActionDock
import com.moviepilot.designsystem.ExpressiveMorphingPlayButton
import com.moviepilot.designsystem.ExpressiveSplitIconPair
import com.moviepilot.designsystem.ExpressiveWavySlider
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.media.danmaku.DanmakuManualMatchBottomSheet
import com.moviepilot.media.danmaku.DanmakuOverlayView
import com.moviepilot.media.danmaku.DanmakuPreferencesStore
import com.moviepilot.media.danmaku.DanmakuSettingsBottomSheet
import com.moviepilot.media.engine.AndroidPlaybackEngineRouter
import com.moviepilot.media.engine.AudioNightModeEffect
import com.moviepilot.media.engine.EngineTrackItem
import com.moviepilot.media.engine.MpvPlaybackEngine
import com.moviepilot.media.engine.ResolvedAndroidEngine
import com.moviepilot.rustbridge.DanmakuEpisodeCandidateDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.NativeSecretStore
import com.moviepilot.rustbridge.PlaybackRouteDto
import com.moviepilot.rustbridge.PlaybackSyncSessionTracker
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs

/** 播放器外挂字幕描述项。 */
data class SubtitleTrackItem(
    val id: String,
    val title: String,
    val language: String,
    val url: String,
)

/** 播放队列延迟解析规格：支持已解析直链、音乐库元数据匹配及媒体服务器条目实时拉流。 */
sealed interface QueueTrackSpec {
    /** 已具备可播放 URL 的直链条目。 */
    data class DirectUrl(val url: String) : QueueTrackSpec

    /** 音乐曲目查询规格（按曲名/艺人/专辑向 `/api/v1/mediaserver/stream-info/music` 延迟匹配）。 */
    data class MusicQuery(
        val title: String,
        val artist: String? = null,
        val album: String? = null,
    ) : QueueTrackSpec

    /** 媒体服务器音视频条目规格（按 `itemId` 与 `server` 延迟调用 `/api/v1/mediaserver/stream-info`）。 */
    data class MediaServerItem(
        val itemId: String,
        val server: String,
        val mediaSourceId: String? = null,
    ) : QueueTrackSpec
}

/** 跨端统一音视频播放清单项（支持鉴权流、外挂字幕、LRC 同步歌词、进度续播、延迟解析队列与播前选轨）。 */
data class MediaPlaybackRequest(
    val url: String,
    val title: String,
    val subtitle: String = "",
    val albumTitle: String = "",
    val artworkUrl: String? = null,
    val artworkBytes: ByteArray? = null,
    val isAudio: Boolean = false,
    val lyricsLrc: String? = null,
    val headers: Map<String, String> = emptyMap(),
    val sameOriginHeaders: Map<String, String> = emptyMap(),
    val streamHeaders: Map<String, String> = emptyMap(),
    val proxyFallbackUrl: String? = null,
    val activeRouteKind: String = "",
    val fallbackRoutes: List<PlaybackRouteDto> = emptyList(),
    val originUrl: String = "",
    val allowSelfSignedTls: Boolean = false,
    val itemId: String = "",
    val server: String = "",
    val serverType: String = "",
    val mediaSourceId: String = "",
    val playSessionId: String? = null,
    val progressSyncMode: String? = null,
    val resumePositionMs: Long = 0L,
    val subtitles: List<SubtitleTrackItem> = emptyList(),
    val queue: List<MediaPlaybackRequest> = emptyList(),
    val queueIndex: Int = 0,
    val lazySpec: QueueTrackSpec? = null,
    val isSessionBound: Boolean = true,
    val tempFilePath: String? = null,
    val externalPlayUrl: String? = null,
    val preferredAudioLang: String? = null,
    val preferredAudioIndex: Int? = null,
    val preferredSubtitleId: String? = null,
    val preferredSubtitleLang: String? = null,
    val disableSubtitles: Boolean = false,
    val danmakuEnabled: Boolean = false,
    val seriesName: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val year: Int? = null,
    val tmdbId: String? = null,
    val fileName: String? = null,
    val fileSize: Long? = null,
) {
    /** 用于本地续播存储的稳定资源标识（优先 `itemId`，无 `itemId` 时采用文件路径或流地址）。 */
    val localResumeId: String
        get() = itemId.ifBlank { tempFilePath?.takeIf { it.isNotBlank() } ?: url }
}

/** 简易 LRC 同步歌词行。 */
data class LrcLine(val timeMs: Long, val text: String)

private val LRC_TIMESTAMP_REGEX = Regex("""\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?]""")
private val LRC_OFFSET_REGEX = Regex("""^\[offset:([+-]?\d+)]$""", RegexOption.IGNORE_CASE)

/**
 * 解析 LRC 同步歌词文本：
 * 完整支持单行多时间戳（如 `[00:12.34][01:45.67]副歌歌词`）、2~3 位毫秒及全局 `[offset:+/-ms]` 偏移标签。
 */
fun parseLrcLyrics(raw: String?): List<LrcLine> {
    if (raw.isNullOrBlank()) return emptyList()
    var globalOffsetMs = 0L
    val parsed = mutableListOf<LrcLine>()
    for (rawLine in raw.lines()) {
        val trimmed = rawLine.trim()
        if (trimmed.isEmpty()) continue
        val offsetMatch = LRC_OFFSET_REGEX.matchEntire(trimmed)
        if (offsetMatch != null) {
            globalOffsetMs = offsetMatch.groupValues[1].toLongOrNull() ?: 0L
            continue
        }
        val matches = LRC_TIMESTAMP_REGEX.findAll(trimmed).toList()
        if (matches.isEmpty()) continue
        // 仅提取行首连续的时间标签序列，保留歌词正文
        var cursor = 0
        val lineTimes = mutableListOf<Long>()
        for (m in matches) {
            if (m.range.first != cursor) break
            val min = m.groupValues[1].toLongOrNull() ?: 0L
            val sec = m.groupValues[2].toLongOrNull() ?: 0L
            val fracRaw = m.groupValues[3]
            val fracMs = if (fracRaw.isEmpty()) {
                0L
            } else {
                fracRaw.padEnd(3, '0').take(3).toLongOrNull() ?: 0L
            }
            lineTimes += (min * 60_000L + sec * 1_000L + fracMs + globalOffsetMs).coerceAtLeast(0L)
            cursor = m.range.last + 1
        }
        if (lineTimes.isEmpty()) continue
        val lyricText = trimmed.substring(cursor).trim()
        if (lyricText.isEmpty()) continue
        for (t in lineTimes) {
            parsed += LrcLine(timeMs = t, text = lyricText)
        }
    }
    return parsed.sortedBy { it.timeMs }
}

/** 格式化毫秒时长为 `MM:SS` 或 `H:MM:SS`。 */
fun formatDurationMs(ms: Long): String {
    val totalSec = (ms / 1000L).coerceAtLeast(0L)
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}

/** 格式化媒体服务器播放方式描述（供右上角弹出菜单与内核面板展示，不占用顶部标题空间）。 */
private fun formatPlaybackRouteSummary(routeKind: String): String? = when (routeKind) {
    "server_lan" -> "直流播放 · 局域网直连"
    "server_wan" -> "直流播放 · 外网直连"
    "strm_direct" -> "直流播放 · STRM 直链"
    "mp_proxy" -> "非直流播放 · 后台中转"
    else -> null
}

private const val EXO_EXT_SUB_ID_PREFIX = "mp_ext:"

private fun subtitleMimeTypeForUrl(url: String): String {
    val lower = url.substringBefore('?').lowercase()
    return when {
        lower.endsWith(".vtt") -> MimeTypes.TEXT_VTT
        lower.endsWith(".ass") || lower.endsWith(".ssa") -> MimeTypes.TEXT_SSA
        else -> MimeTypes.APPLICATION_SUBRIP
    }
}

/**
 * 从播放清单挑选起播阶段需要自动预取并挂载的首选外挂字幕（遵循 `preferredSubtitleId` -> `preferredSubtitleLang` -> `preferChineseSub` 优先级）。
 */
private fun pickInitialExternalSubtitle(
    request: MediaPlaybackRequest,
    prefs: PlaybackPreferencesStore,
): SubtitleTrackItem? {
    if (request.isAudio || request.disableSubtitles || request.subtitles.isEmpty()) return null
    val validSubs = request.subtitles.filter { it.url.isNotBlank() }
    if (validSubs.isEmpty()) return null

    if (!request.preferredSubtitleId.isNullOrBlank()) {
        val targetId = request.preferredSubtitleId.trim()
        validSubs.firstOrNull { it.id == targetId || it.title == targetId }?.let { return it }
    }
    if (!request.preferredSubtitleLang.isNullOrBlank()) {
        val targetLang = request.preferredSubtitleLang.trim().lowercase()
        validSubs.firstOrNull {
            it.language.trim().lowercase() == targetLang ||
                it.title.lowercase().contains(targetLang)
        }?.let { return it }
    }
    if (prefs.preferChineseSub) {
        return validSubs
            .map { sub ->
                sub to ChineseSubtitleMatcher.scoreChineseSubtitle(
                    language = sub.language,
                    label = sub.title,
                    isExternal = true,
                )
            }
            .filter { it.second > 0 }
            .maxByOrNull { it.second }
            ?.first
    }
    return null
}

/**
 * 判断已嗅探落盘的外挂字幕是否需要从 Media3 原生内核智能升级至 MPV 全能内核：
 * - 含 `[Fonts]` 内嵌子集化字体的 ASS/SSA（且未忽略特效样式）必须使用 MPV `libass` 渲染；
 * - 用户处于默认自动选核（非强制固定原生内核）且真实格式为 ASS/SSA（如无后缀 URL 或 SRT 实时转 ASS）时自动切 MPV。
 */
private fun shouldUpgradeToMpvForPrefetchedSubtitle(
    prefetched: PrefetchedSubtitle,
    prefs: PlaybackPreferencesStore,
): Boolean {
    if (!prefetched.isAssOrSsa || prefs.ignoreAssStyle) return false
    if (prefetched.hasEmbeddedFonts) return true
    return prefs.videoEngine != "native"
}

private fun upgradeReasonForSubtitle(prefetched: PrefetchedSubtitle): String =
    if (prefetched.hasEmbeddedFonts) {
        "检测到内嵌字体特效字幕，已切换至 MPV 渲染"
    } else {
        "检测到 ASS 特效字幕，已切换至 MPV 渲染"
    }

/**
 * 构建 Media3 `ExoPlayer` 外挂字幕配置：优先采用已预取的本地文件 `Uri` 与嗅探出的真实 `MimeTypes`，
 * 当开启延迟挂载远端字幕时跳过未预取的远端 HTTP URL，杜绝无后缀 MIME 误判与 `Range` 请求触发上游 `501`。
 */
@OptIn(UnstableApi::class)
private fun buildExoSubtitleConfigurations(
    request: MediaPlaybackRequest,
    prefetchedMap: Map<String, PrefetchedSubtitle>,
    deferRemoteSubtitles: Boolean,
): List<MediaItem.SubtitleConfiguration> {
    if (request.isAudio || request.subtitles.isEmpty()) return emptyList()
    val configs = mutableListOf<MediaItem.SubtitleConfiguration>()
    for (sub in request.subtitles) {
        val rawUrl = sub.url.trim()
        if (rawUrl.isBlank()) continue
        val subKey = SubtitlePrefetcher.subtitleKey(sub)
        val prefetched = prefetchedMap[subKey]
        val resolvedUriAndMime: Pair<Uri, String>? = when {
            prefetched != null && prefetched.file.exists() ->
                prefetched.localUri to prefetched.mimeType
            rawUrl.startsWith("file://", ignoreCase = true) ->
                Uri.parse(rawUrl) to subtitleMimeTypeForUrl(rawUrl)
            rawUrl.startsWith("/") ->
                Uri.fromFile(File(rawUrl)) to subtitleMimeTypeForUrl(rawUrl)
            deferRemoteSubtitles -> null
            else -> Uri.parse(rawUrl) to subtitleMimeTypeForUrl(rawUrl)
        }
        if (resolvedUriAndMime != null) {
            val label = sub.title.ifBlank { sub.language.ifBlank { "外挂字幕" } }
            val cfgId = if (deferRemoteSubtitles || prefetched != null) {
                "$EXO_EXT_SUB_ID_PREFIX$subKey"
            } else {
                sub.id.ifBlank { "$EXO_EXT_SUB_ID_PREFIX$subKey" }
            }
            configs += MediaItem.SubtitleConfiguration.Builder(resolvedUriAndMime.first)
                .setMimeType(resolvedUriAndMime.second)
                .setLanguage(sub.language.ifBlank { "und" })
                .setLabel(label)
                .setId(cfgId)
                .build()
        }
    }
    return configs
}

/**
 * 根据播放清单构建完整配置的 `ExoPlayer`：
 * - 使用 `OkHttpDataSource.Factory` 支持自签名 TLS 与跨源重定向自动剥离敏感凭据；
 * - 启用 Media3 音频焦点托管（来电自动闪避/暂停）与拔出耳机自动暂停（`HandleAudioBecomingNoisy`）；
 * - 注入系统锁屏/通知栏/蓝牙媒体元数据与真实嗅探后的本地外挂字幕；
 * - 音频固定以 `1.0x` 原速启动，视频应用用户默认倍速与清晰度上限。
 */
@OptIn(UnstableApi::class)
fun buildConfiguredExoPlayer(
    context: Context,
    request: MediaPlaybackRequest,
    resumePositionOverrideMs: Long? = null,
    activeStreamProvider: (() -> Pair<String, Map<String, String>>)? = null,
    prefetchedSubtitles: Map<String, PrefetchedSubtitle> = emptyMap(),
    deferRemoteSubtitles: Boolean = false,
): ExoPlayer {
    val prefs = PlaybackPreferencesStore(context)
    val allowInsecureTls = request.allowSelfSignedTls ||
        runCatching { NativeSecretStore(context).allowSelfSignedTls }.getOrDefault(false)
    val effectiveOrigin = request.originUrl.ifBlank { request.url }
    val effectiveOriginHeaders = request.sameOriginHeaders.ifEmpty { request.headers }
    val httpFactory = PlaybackHttpDataSource.createFactory(
        originUrl = effectiveOrigin,
        headers = effectiveOriginHeaders,
        allowSelfSignedTls = allowInsecureTls,
        streamUrl = request.url,
        streamHeaders = request.streamHeaders,
        activeStreamProvider = activeStreamProvider,
    )
    val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
    val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
    val renderersFactory = DefaultRenderersFactory(context)
        .setEnableDecoderFallback(true)
        .setExtensionRendererMode(
            if (prefs.hwDecode) DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON
            else DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER,
        )

    val metadataBuilder = MediaMetadata.Builder()
        .setTitle(request.title)
        .setDisplayTitle(request.title)
    if (request.subtitle.isNotBlank()) {
        metadataBuilder.setArtist(request.subtitle)
        metadataBuilder.setSubtitle(request.subtitle)
    }
    if (request.albumTitle.isNotBlank()) {
        metadataBuilder.setAlbumTitle(request.albumTitle)
    }
    request.artworkBytes?.takeIf { it.isNotEmpty() }?.let { bytes ->
        metadataBuilder.setArtworkData(bytes, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
    }
    request.artworkUrl?.takeIf { it.isNotBlank() }?.let { art ->
        metadataBuilder.setArtworkUri(Uri.parse(art))
    }

    val itemBuilder = MediaItem.Builder()
        .setUri(Uri.parse(request.url))
        .setMediaMetadata(metadataBuilder.build())

    if (request.subtitles.isNotEmpty()) {
        val subConfigs = buildExoSubtitleConfigurations(
            request = request,
            prefetchedMap = prefetchedSubtitles,
            deferRemoteSubtitles = deferRemoteSubtitles,
        )
        if (subConfigs.isNotEmpty()) {
            itemBuilder.setSubtitleConfigurations(subConfigs)
        }
    }

    val audioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(if (request.isAudio) C.AUDIO_CONTENT_TYPE_MUSIC else C.AUDIO_CONTENT_TYPE_MOVIE)
        .build()

    val isLargeBuffer = prefs.bufferProfile == "large"
    val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            if (isLargeBuffer) 30_000 else 15_000,
            if (isLargeBuffer) 120_000 else 50_000,
            if (request.isAudio) (if (isLargeBuffer) 1_000 else 500) else (if (isLargeBuffer) 2_500 else 1_000),
            if (request.isAudio) (if (isLargeBuffer) 2_000 else 1_000) else (if (isLargeBuffer) 5_000 else 2_000),
        )
        .setPrioritizeTimeOverSizeThresholds(true)
        .build()

    // 仅视频应用默认倍速偏好；音乐固定 1.0x 原速启动
    val initialSpeed = if (request.isAudio) 1.0f else prefs.defaultSpeed.coerceIn(0.5f, 2.0f)
    val effectiveStartMs = (resumePositionOverrideMs ?: request.resumePositionMs).coerceAtLeast(0L)

    return ExoPlayer.Builder(context, renderersFactory)
        .setMediaSourceFactory(mediaSourceFactory)
        .setLoadControl(loadControl)
        .setAudioAttributes(audioAttributes, /* handleAudioFocus = */ true)
        .setHandleAudioBecomingNoisy(true)
        .build()
        .apply {
            setMediaItem(itemBuilder.build())
            playbackParameters = PlaybackParameters(initialSpeed)
            if (!request.isAudio) {
                when (prefs.defaultQuality) {
                    "720p", "流畅省流" -> {
                        trackSelectionParameters = trackSelectionParameters
                            .buildUpon()
                            .setMaxVideoSize(1280, 720)
                            .build()
                    }
                    "1080p" -> {
                        trackSelectionParameters = trackSelectionParameters
                            .buildUpon()
                            .setMaxVideoSize(1920, 1080)
                            .build()
                    }
                }
            }
            if (effectiveStartMs > 0L) {
                seekTo(effectiveStartMs)
            }
            prepare()
            playWhenReady = true
        }
}

@Immutable
private data class PlayerExpressivePalette(
    val canvas: Color,
    val accent: Color,
    val onAccent: Color,
    val dock: Color,
    val buttonBg: Color,
)

/**
 * 播放封面动态取色引擎（纯 Kotlin 零额外依赖）：
 * 从当前播放封面采样主色相，合成深丝绒底色 + 柔和粉彩高光主色 + 沉入式胶囊坞色，平滑过渡切换。
 */
@Composable
private fun rememberArtworkPlayerPalette(
    artworkUrl: String?,
    artworkBytes: ByteArray? = null,
): PlayerExpressivePalette {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val context = LocalContext.current
    val fallback = remember(colors) {
        PlayerExpressivePalette(
            canvas = colors.playerTint,
            accent = colors.playerAccent,
            onAccent = colors.playerOnAccent,
            dock = colors.playerDock,
            buttonBg = colors.playerButtonBg,
        )
    }
    val bytesKey = artworkBytes?.size ?: 0
    var extracted by remember(artworkUrl, bytesKey, fallback, store.albumArtDynamicColor) {
        mutableStateOf(fallback)
    }

    LaunchedEffect(artworkUrl, bytesKey, store.albumArtDynamicColor) {
        val hasUrl = !artworkUrl.isNullOrBlank()
        val hasBytes = artworkBytes != null && artworkBytes.isNotEmpty()
        if (!store.albumArtDynamicColor || (!hasUrl && !hasBytes)) {
            extracted = fallback
            return@LaunchedEffect
        }
        val derived = withContext(Dispatchers.IO) {
            runCatching {
                val bmp: Bitmap? = if (hasUrl) {
                    val loader = context.imageLoader
                    val req = ImageRequest.Builder(context)
                        .data(artworkUrl)
                        .size(48)
                        .allowHardware(false)
                        .build()
                    val res = loader.execute(req) as? SuccessResult
                    (res?.drawable as? BitmapDrawable)?.bitmap
                } else {
                    val opts = BitmapFactory.Options().apply { inSampleSize = 4 }
                    BitmapFactory.decodeByteArray(artworkBytes, 0, artworkBytes!!.size, opts)
                }
                bmp?.let { derivePaletteFromBitmap(it) }
            }.getOrNull()
        }
        extracted = derived ?: fallback
    }

    val animCanvas by animateColorAsState(extracted.canvas, tween(420), label = "playerCanvas")
    val animAccent by animateColorAsState(extracted.accent, tween(420), label = "playerAccent")
    val animOnAccent by animateColorAsState(extracted.onAccent, tween(420), label = "playerOnAccent")
    val animDock by animateColorAsState(extracted.dock, tween(420), label = "playerDock")
    val animBtn by animateColorAsState(extracted.buttonBg, tween(420), label = "playerBtn")
    return PlayerExpressivePalette(animCanvas, animAccent, animOnAccent, animDock, animBtn)
}

private fun derivePaletteFromBitmap(bitmap: Bitmap): PlayerExpressivePalette? {
    val hsv = FloatArray(3)
    var bestHue = -1f
    var bestScore = 0f
    val stepX = (bitmap.width / 12).coerceAtLeast(1)
    val stepY = (bitmap.height / 12).coerceAtLeast(1)
    var y = 0
    while (y < bitmap.height) {
        var x = 0
        while (x < bitmap.width) {
            val px = bitmap.getPixel(x, y)
            if (AndroidColor.alpha(px) > 180) {
                AndroidColor.colorToHSV(px, hsv)
                val sat = hsv[1]
                val v = hsv[2]
                val score = sat * (1f - abs(v - 0.55f))
                if (sat > 0.22f && v > 0.16f && v < 0.94f && score > bestScore) {
                    bestScore = score
                    bestHue = hsv[0]
                }
            }
            x += stepX
        }
        y += stepY
    }
    if (bestHue < 0f) return null
    fun hsvColor(h: Float, s: Float, v: Float): Color =
        Color(AndroidColor.HSVToColor(floatArrayOf(h, s.coerceIn(0f, 1f), v.coerceIn(0f, 1f))))

    return PlayerExpressivePalette(
        canvas = hsvColor(bestHue, 0.58f, 0.34f),
        accent = hsvColor(bestHue, 0.22f, 0.94f),
        onAccent = hsvColor(bestHue, 0.72f, 0.28f),
        dock = hsvColor(bestHue, 0.66f, 0.22f),
        buttonBg = hsvColor(bestHue, 0.48f, 0.43f),
    )
}

private data class ResolvedTrackChoice(
    val label: String,
    val language: String?,
    val trackId: String?,
    val group: Tracks.Group?,
    val trackIndex: Int,
    val selected: Boolean,
    val externalSub: SubtitleTrackItem? = null,
    val isLoading: Boolean = false,
    val isFailed: Boolean = false,
)

private val VIDEO_RESIZE_MODES: List<Pair<Int, String>> = listOf(
    AspectRatioFrameLayout.RESIZE_MODE_FIT to "自适应",
    AspectRatioFrameLayout.RESIZE_MODE_ZOOM to "铺满裁剪",
    AspectRatioFrameLayout.RESIZE_MODE_FILL to "拉伸填充",
)

/** 支持的全量倍速档位（与播放偏好页一致）。 */
val PLAYER_SUPPORTED_SPEEDS: List<Float> = listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f)

@Stable
private class PlayerUiPersistentState(
    initialResizeMode: Int,
    initialOrientation: Int,
    initialInPip: Boolean,
    initialShuffle: Boolean,
    initialRepeatMode: Int,
    initialDanmakuVisible: Boolean,
) {
    var controlsVisible by mutableStateOf(true)
    var lastInteractionTick by mutableLongStateOf(System.currentTimeMillis())
    var isLocked by mutableStateOf(false)
    var showRemainingTime by mutableStateOf(false)
    var isLongPressBoost by mutableStateOf(false)
    var resizeModeIndex by mutableIntStateOf(initialResizeMode)
    var localShuffle by mutableStateOf(initialShuffle)
    var localRepeatMode by mutableIntStateOf(initialRepeatMode)
    var showLyricsView by mutableStateOf(false)
    var showQueueSheet by mutableStateOf(false)
    var showSubtitleSheet by mutableStateOf(false)
    var showAudioTrackSheet by mutableStateOf(false)
    var showSpeedSheet by mutableStateOf(false)
    var showEngineSheet by mutableStateOf(false)
    var showCastSheet by mutableStateOf(false)
    var showTopMoreMenu by mutableStateOf(false)
    var showDanmakuSettingsSheet by mutableStateOf(false)
    var showDanmakuMatchSheet by mutableStateOf(false)
    var hudMessage by mutableStateOf<String?>(null)
    var tracksVersion by mutableIntStateOf(0)
    var danmakuVisible by mutableStateOf(initialDanmakuVisible)
    var danmakuOverlayRef by mutableStateOf<DanmakuOverlayView?>(null)
    var danmakuPrefsVersion by mutableIntStateOf(0)
    var videoAspectRatio by mutableStateOf(Rational(16, 9))
    var preLockOrientation by mutableIntStateOf(initialOrientation)
    var isInPipMode by mutableStateOf(initialInPip)
    var draggingProgress by mutableFloatStateOf(-1f)

    val anySheetOpen: Boolean
        get() = showQueueSheet || showSubtitleSheet || showAudioTrackSheet ||
            showSpeedSheet || showEngineSheet || showCastSheet || showTopMoreMenu ||
            showDanmakuSettingsSheet || showDanmakuMatchSheet

    fun bumpInteraction() {
        lastInteractionTick = System.currentTimeMillis()
    }

    fun dismissSheetsOnPipEnter() {
        showSubtitleSheet = false
        showAudioTrackSheet = false
        showQueueSheet = false
        showSpeedSheet = false
        showEngineSheet = false
        showCastSheet = false
        showDanmakuSettingsSheet = false
        showDanmakuMatchSheet = false
    }
}

@Stable
private class PlayerSessionState(
    request: MediaPlaybackRequest,
    ownsPlayer: Boolean,
    primaryEngineId: String,
    bestInitialResumeMs: Long,
    initialExternalSubKey: String? = null,
) {
    var embeddedAudioMeta by mutableStateOf<ResolvedEmbeddedAudioMetadata?>(null)
    val activeStreamRouteRef: AtomicReference<Pair<String, Map<String, String>>> =
        AtomicReference(request.url to request.streamHeaders)
    var currentRouteKind by mutableStateOf(request.activeRouteKind)
    var activeEngineKind by mutableStateOf(
        if (ownsPlayer && !request.isAudio) {
            ResolvedAndroidEngine.fromId(primaryEngineId)
        } else {
            ResolvedAndroidEngine.NATIVE
        },
    )
    var engineCarryPositionMs by mutableLongStateOf(bestInitialResumeMs)
    val suppressStopForEngineSwitchRef: AtomicBoolean = AtomicBoolean(false)
    var didAutoFallbackEngine by mutableStateOf(false)
    var playbackLoadFailed by mutableStateOf(false)
    var mpvAudioTracks by mutableStateOf<List<EngineTrackItem>>(emptyList())
    var mpvSubtitleTracks by mutableStateOf<List<EngineTrackItem>>(emptyList())
    var positionMs by mutableLongStateOf(bestInitialResumeMs.coerceAtLeast(0L))
    var durationMs by mutableLongStateOf(1L)
    var activePreferredAudioLang by mutableStateOf(request.preferredAudioLang)
    var activePreferredSubtitleLang by mutableStateOf(request.preferredSubtitleLang)
    var activeDisableSubtitles by mutableStateOf(request.disableSubtitles)
    var appliedInitialTracks by mutableStateOf(false)
    val prefetchedSubtitles = mutableStateMapOf<String, PrefetchedSubtitle>()
    var selectedExternalSubKey by mutableStateOf(initialExternalSubKey)
    var loadingExternalSubKey by mutableStateOf<String?>(null)
    var failedExternalSubKey by mutableStateOf<String?>(null)
    var startupSubtitleGateReady by mutableStateOf(initialExternalSubKey == null)
    var activeSubtitleJob: Job? = null
    var resumeBannerPositionMs by mutableStateOf(
        bestInitialResumeMs.takeIf { it > LocalPlaybackHistoryStore.MIN_RESUME_POSITION_MS },
    )
    var upNextCancelled by mutableStateOf(false)
    var autoAdvancedTriggered by mutableStateOf(false)
    var mpvEngineHolder by mutableStateOf<MpvPlaybackEngine?>(null)
    val mpvFallbackRoutes: ArrayDeque<PlaybackRouteDto> = buildFallbackRoutesDeque(request)
}

@Stable
private class VideoDanmakuSessionState {
    var rawJson by mutableStateOf<String?>(null)
    var episodeId by mutableStateOf<Long?>(null)
    var animeId by mutableStateOf<Long?>(null)
    var animeTitle by mutableStateOf<String?>(null)
    var episodeTitle by mutableStateOf<String?>(null)
    var candidates by mutableStateOf<List<DanmakuEpisodeCandidateDto>>(emptyList())
    var fromBinding by mutableStateOf(false)
    var shiftMs by mutableIntStateOf(0)
    var totalCount by mutableIntStateOf(0)
}

private fun buildFallbackRoutesDeque(request: MediaPlaybackRequest): ArrayDeque<PlaybackRouteDto> =
    ArrayDeque<PlaybackRouteDto>().apply {
        request.fallbackRoutes.forEach { addLast(it) }
        val legacyFallback = request.proxyFallbackUrl
        if (!legacyFallback.isNullOrBlank() && legacyFallback != request.url && none { it.url == legacyFallback }) {
            addLast(
                PlaybackRouteDto(
                    kind = "mp_proxy",
                    url = legacyFallback,
                    priority = 100,
                    requiresSameOriginAuth = true,
                ),
            )
        }
    }

@OptIn(UnstableApi::class)
@Stable
private class PlayerRuntimeController(
    val context: Context,
    val request: MediaPlaybackRequest,
    val ownsPlayer: Boolean,
    val instanceUrl: String,
    val repository: MoviePilotRepository?,
    val playbackPrefs: PlaybackPreferencesStore,
    val localHistoryStore: LocalPlaybackHistoryStore,
    val ui: PlayerUiPersistentState,
    val session: PlayerSessionState,
    val exoPlayer: ExoPlayer?,
    val isMpvActive: Boolean,
    val speeds: List<Float>,
    private val isPlayingState: MutableState<Boolean>,
    private val speedIndexState: MutableIntState,
    private val hasEmittedVideoStartState: MutableState<Boolean>,
    private val videoSyncTracker: PlaybackSyncSessionTracker,
    private val latestReportProgressState: State<((Long, Long, Boolean, String) -> Unit)?>,
    private val latestSwitchRequestState: State<((MediaPlaybackRequest) -> Unit)?>,
    private val latestCloseState: State<() -> Unit>,
    private val latestMetadataEnrichedState: State<((MediaPlaybackRequest) -> Unit)?>,
    val subtitlePrefetcher: SubtitlePrefetcher? = null,
    val playerScope: CoroutineScope,
) {
    var isPlaying: Boolean
        get() = isPlayingState.value
        set(value) {
            isPlayingState.value = value
        }

    var speedIndex: Int
        get() = speedIndexState.intValue
        set(value) {
            speedIndexState.intValue = value
        }

    var hasEmittedVideoStart: Boolean
        get() = hasEmittedVideoStartState.value
        set(value) {
            hasEmittedVideoStartState.value = value
        }

    val hasPrevVideoEpisode: Boolean
        get() = !request.isAudio && request.queue.size > 1 && request.queueIndex > 0

    val hasNextVideoEpisode: Boolean
        get() = !request.isAudio && request.queue.size > 1 && request.queueIndex + 1 < request.queue.size

    val nextVideoEpisode: MediaPlaybackRequest?
        get() = if (hasNextVideoEpisode) request.queue.getOrNull(request.queueIndex + 1) else null

    val currentSelectedSpeed: Float
        get() = speeds[speedIndex.coerceIn(0, speeds.lastIndex)]

    fun notifyMetadataEnriched(enriched: MediaPlaybackRequest) {
        latestMetadataEnrichedState.value?.invoke(enriched)
    }

    fun activeCurrentPositionMs(): Long =
        if (isMpvActive) {
            session.mpvEngineHolder?.positionMs ?: session.positionMs
        } else {
            exoPlayer?.currentPosition?.coerceAtLeast(0L) ?: session.positionMs
        }

    fun activeDurationMs(): Long =
        if (isMpvActive) {
            session.mpvEngineHolder?.durationMs ?: session.durationMs
        } else {
            exoPlayer?.duration?.coerceAtLeast(0L) ?: session.durationMs
        }

    fun activeIsPlaying(): Boolean =
        if (isMpvActive) {
            session.mpvEngineHolder?.isPlaying ?: isPlaying
        } else {
            exoPlayer?.isPlaying == true
        }

    fun activePlay() {
        if (isMpvActive) {
            if (session.playbackLoadFailed) {
                session.playbackLoadFailed = false
                val curRoute = session.activeStreamRouteRef.get()
                session.mpvEngineHolder?.reloadWithRoute(curRoute.first, curRoute.second)
            } else {
                session.mpvEngineHolder?.play()
            }
        } else {
            exoPlayer?.let { ep ->
                if (session.playbackLoadFailed || ep.playbackState == Player.STATE_IDLE) {
                    session.playbackLoadFailed = false
                    ep.prepare()
                }
                ep.play()
            }
        }
    }

    fun activePause() {
        if (isMpvActive) session.mpvEngineHolder?.pause() else exoPlayer?.pause()
    }

    fun activeSeekTo(targetMs: Long) {
        val clamped = targetMs.coerceAtLeast(0L)
        if (isMpvActive) {
            session.mpvEngineHolder?.seekTo(clamped)
            session.positionMs = clamped
        } else {
            exoPlayer?.seekTo(clamped)
        }
        ui.danmakuOverlayRef?.syncPlayback(
            positionMs = clamped,
            playing = activeIsPlaying(),
            rate = currentSelectedSpeed,
            inPip = ui.isInPipMode,
        )
    }

    fun activeSetSpeed(spd: Float) {
        if (isMpvActive) {
            session.mpvEngineHolder?.setSpeed(spd)
        } else {
            exoPlayer?.playbackParameters = PlaybackParameters(spd)
        }
        ui.danmakuOverlayRef?.syncPlayback(
            positionMs = activeCurrentPositionMs(),
            playing = activeIsPlaying(),
            rate = spd,
            inPip = ui.isInPipMode,
        )
    }

    /** 播放器内一键热切换内核：保留当前进度与 `play_session_id`，绝不向媒体服务器发送 `stopped`。 */
    fun switchVideoEngine(target: ResolvedAndroidEngine, reasonNotice: String? = null) {
        if (!ownsPlayer || request.isAudio || target == session.activeEngineKind) return
        session.engineCarryPositionMs = activeCurrentPositionMs().coerceAtLeast(0L)
        session.suppressStopForEngineSwitchRef.set(true)
        session.playbackLoadFailed = false
        session.mpvAudioTracks = emptyList()
        session.mpvSubtitleTracks = emptyList()
        session.activeEngineKind = target
        ui.hudMessage = reasonNotice ?: "已切换至 ${target.displayName}"
    }

    fun resolveSelectedAudioIndex(): Int? {
        if (isMpvActive) {
            val idx = session.mpvAudioTracks.indexOfFirst { it.isSelected }
            return if (idx >= 0) idx else null
        }
        val ep = exoPlayer ?: return null
        var ordinal = 0
        for (grp in ep.currentTracks.groups) {
            if (grp.type != C.TRACK_TYPE_AUDIO) continue
            for (i in 0 until grp.length) {
                if (grp.isTrackSelected(i)) return ordinal
                ordinal++
            }
        }
        return null
    }

    fun resolveSelectedSubtitleIndex(): Int? {
        if (isMpvActive) {
            val idx = session.mpvSubtitleTracks.indexOfFirst { it.isSelected }
            return if (idx >= 0) idx else -1
        }
        val ep = exoPlayer ?: return null
        if (ep.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)) {
            return -1
        }
        var ordinal = 0
        for (grp in ep.currentTracks.groups) {
            if (grp.type != C.TRACK_TYPE_TEXT) continue
            for (i in 0 until grp.length) {
                if (grp.isTrackSelected(i)) return ordinal
                ordinal++
            }
        }
        return null
    }

    fun dispatchVideoSync(
        trigger: String,
        posOverrideMs: Long? = null,
        durOverrideMs: Long? = null,
        pausedOverride: Boolean? = null,
    ) {
        if (!ownsPlayer || request.isAudio) return
        val pos = (posOverrideMs ?: activeCurrentPositionMs()).coerceAtLeast(0L)
        val dur = (durOverrideMs ?: activeDurationMs()).coerceAtLeast(0L)
        val paused = pausedOverride ?: !activeIsPlaying()
        val audioIdx = resolveSelectedAudioIndex()
        val subIdx = resolveSelectedSubtitleIndex()
        val decision = videoSyncTracker.step(
            trigger = trigger,
            positionMs = pos,
            durationMs = dur.takeIf { it > 0L },
            isPaused = paused,
            audioStreamIndex = audioIdx,
            subtitleStreamIndex = subIdx,
        )
        if (decision.state == "started") {
            hasEmittedVideoStart = true
        }
        if (!decision.shouldReport) return
        if (repository != null) {
            repository.playbackProgressReporter.enqueueDecision(
                repository = repository,
                itemId = request.itemId,
                server = request.server,
                mediaSourceId = request.mediaSourceId.ifBlank { null },
                decision = decision,
                playSessionId = request.playSessionId,
                durationMs = dur.takeIf { it > 0L },
                audioStreamIndex = audioIdx,
                subtitleStreamIndex = subIdx,
            )
        } else {
            latestReportProgressState.value?.invoke(decision.positionMs, dur, decision.isPaused, decision.state)
        }
    }

    private fun buildCarryOverEpisodeRequest(target: MediaPlaybackRequest, nextIndex: Int): MediaPlaybackRequest =
        target.copy(
            queue = request.queue,
            queueIndex = nextIndex,
            preferredAudioLang = session.activePreferredAudioLang,
            preferredSubtitleLang = session.activePreferredSubtitleLang,
            disableSubtitles = session.activeDisableSubtitles,
        )

    fun closeVideoCleanly() {
        if (ownsPlayer && !request.isAudio) {
            val pos = activeCurrentPositionMs().coerceAtLeast(0L)
            val dur = activeDurationMs().coerceAtLeast(0L)
            localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, pos, dur)
            dispatchVideoSync("stop", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = true)
        }
        latestCloseState.value.invoke()
    }

    fun switchVideoEpisode(nextIdx: Int) {
        val target = request.queue.getOrNull(nextIdx) ?: return
        if (ownsPlayer && !request.isAudio) {
            val pos = activeCurrentPositionMs().coerceAtLeast(0L)
            val dur = activeDurationMs().coerceAtLeast(0L)
            localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, pos, dur)
            dispatchVideoSync("stop", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = true)
        }
        latestSwitchRequestState.value?.invoke(buildCarryOverEpisodeRequest(target, nextIdx))
    }

    /** 当 Media3 轨道列表就绪或动态注入外挂字幕后，确保当前选中的预取外挂字幕被精确激活。 */
    fun applySelectedExternalSubtitleToExoIfPresent(tracks: Tracks) {
        val ep = exoPlayer ?: return
        val targetSubKey = session.selectedExternalSubKey ?: return
        if (request.isAudio || session.activeDisableSubtitles) return
        val targetTrackId = "$EXO_EXT_SUB_ID_PREFIX$targetSubKey"
        for (grp in tracks.groups) {
            if (grp.type != C.TRACK_TYPE_TEXT) continue
            for (i in 0 until grp.length) {
                val fmt = grp.getTrackFormat(i)
                if (fmt.id == targetTrackId || fmt.id?.endsWith(":$targetTrackId") == true) {
                    val isTextDisabled = ep.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
                    if (isTextDisabled || !grp.isTrackSelected(i)) {
                        ep.trackSelectionParameters = ep.trackSelectionParameters
                            .buildUpon()
                            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                            .setOverrideForType(TrackSelectionOverride(grp.mediaTrackGroup, i))
                            .build()
                        ui.tracksVersion++
                    }
                    return
                }
            }
        }
    }

    /** 将新预取落盘的外挂字幕动态注入 Media3 当前播放项并保持当前播放进度无缝对齐。 */
    private fun injectPrefetchedSubtitlesIntoExo(selectKey: String?) {
        val ep = exoPlayer ?: return
        val curItem = ep.currentMediaItem ?: return
        val curUri = curItem.localConfiguration?.uri ?: Uri.parse(request.url)
        val curMeta = curItem.mediaMetadata
        val subConfigs = buildExoSubtitleConfigurations(
            request = request,
            prefetchedMap = session.prefetchedSubtitles.toMap(),
            deferRemoteSubtitles = true,
        )
        val updatedItem = MediaItem.Builder()
            .setUri(curUri)
            .setMediaMetadata(curMeta)
            .setSubtitleConfigurations(subConfigs)
            .build()
        val currentPos = ep.currentPosition.coerceAtLeast(0L)
        val wasPlayWhenReady = ep.playWhenReady
        if (selectKey != null) {
            session.selectedExternalSubKey = selectKey
            session.activeDisableSubtitles = false
        }
        ep.setMediaItem(updatedItem, currentPos)
        ep.prepare()
        ep.playWhenReady = wasPlayWhenReady
    }

    /**
     * 应用预取成功的外挂字幕：
     * - 若检测到内嵌 `[Fonts]` 字体或自动模式下嗅探出 ASS/SSA，自动热切至 MPV 渲染完整特效与子集化字体；
     * - 否则挂载至当前活动内核（MPV `sub-add` 或 Media3 本地 `SubtitleConfiguration`），自动对齐当前时间轴。
     */
    fun applyPrefetchedExternalSubtitle(
        sub: SubtitleTrackItem,
        prefetched: PrefetchedSubtitle,
        fromAutoStartup: Boolean,
    ) {
        val subKey = SubtitlePrefetcher.subtitleKey(sub)
        session.prefetchedSubtitles[subKey] = prefetched
        session.selectedExternalSubKey = subKey
        session.activeDisableSubtitles = false
        session.failedExternalSubKey = null
        session.activePreferredSubtitleLang = sub.language.ifBlank { sub.title }

        if (
            !isMpvActive &&
            ownsPlayer &&
            !request.isAudio &&
            shouldUpgradeToMpvForPrefetchedSubtitle(prefetched, playbackPrefs)
        ) {
            switchVideoEngine(
                ResolvedAndroidEngine.ENHANCED,
                upgradeReasonForSubtitle(prefetched),
            )
            return
        }

        val label = sub.title.ifBlank { sub.language.ifBlank { "外挂字幕" } }
        if (isMpvActive) {
            session.mpvEngineHolder?.addExternalSubtitleFile(
                localFilePath = prefetched.file.absolutePath,
                title = label,
                language = sub.language,
                select = true,
            )
        } else {
            injectPrefetchedSubtitlesIntoExo(selectKey = subKey)
            exoPlayer?.currentTracks?.let { applySelectedExternalSubtitleToExoIfPresent(it) }
        }
        ui.tracksVersion++
        ui.hudMessage = if (fromAutoStartup) "已加载外挂字幕：$label" else "字幕：$label"
        if (hasEmittedVideoStart) {
            dispatchVideoSync("track_change")
        }
    }

    fun applyInitialTrackPreferencesIfReady(tracks: Tracks) {
        val ep = exoPlayer ?: return
        if (request.isAudio || session.appliedInitialTracks) return
        val hasMediaGroups = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO || it.type == C.TRACK_TYPE_AUDIO }
        if (!hasMediaGroups) return
        session.appliedInitialTracks = true

        var paramsBuilder = ep.trackSelectionParameters.buildUpon()
        var changed = false

        val audioGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (audioGroups.isNotEmpty()) {
            val flattenedAudio = buildList {
                audioGroups.forEach { grp ->
                    for (i in 0 until grp.length) add(grp to i)
                }
            }
            val matchedAudio: Pair<Tracks.Group, Int>? = when {
                request.preferredAudioIndex != null && request.preferredAudioIndex in flattenedAudio.indices ->
                    flattenedAudio[request.preferredAudioIndex]
                !request.preferredAudioLang.isNullOrBlank() -> {
                    val targetLang = request.preferredAudioLang.trim().lowercase()
                    flattenedAudio.firstOrNull { (grp, idx) ->
                        val fmt = grp.getTrackFormat(idx)
                        fmt.language?.lowercase() == targetLang ||
                            fmt.label?.lowercase()?.contains(targetLang) == true
                    }
                }
                else -> null
            }
            if (matchedAudio != null) {
                paramsBuilder = paramsBuilder.setOverrideForType(
                    TrackSelectionOverride(matchedAudio.first.mediaTrackGroup, matchedAudio.second),
                )
                changed = true
            }
        }

        val textGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }
        if (request.disableSubtitles) {
            paramsBuilder = paramsBuilder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            changed = true
        } else if (session.selectedExternalSubKey != null) {
            // 已指定或正在后台预取首选外挂字幕：若已挂载则直接选中，否则保持等待预取完成注入
            if (changed) {
                ep.trackSelectionParameters = paramsBuilder.build()
                ui.tracksVersion++
            }
            applySelectedExternalSubtitleToExoIfPresent(tracks)
            return
        } else if (textGroups.isNotEmpty()) {
            val flattenedSubs = buildList {
                textGroups.forEach { grp ->
                    for (i in 0 until grp.length) add(grp to i)
                }
            }
            val explicitSub: Pair<Tracks.Group, Int>? = when {
                !request.preferredSubtitleId.isNullOrBlank() -> {
                    val targetId = request.preferredSubtitleId.trim()
                    flattenedSubs.firstOrNull { (grp, idx) ->
                        val fmt = grp.getTrackFormat(idx)
                        fmt.id == targetId || fmt.id?.endsWith(":$targetId") == true || fmt.label == targetId
                    }
                }
                !request.preferredSubtitleLang.isNullOrBlank() -> {
                    val targetLang = request.preferredSubtitleLang.trim().lowercase()
                    flattenedSubs.firstOrNull { (grp, idx) ->
                        val fmt = grp.getTrackFormat(idx)
                        fmt.language?.lowercase() == targetLang ||
                            fmt.label?.lowercase()?.contains(targetLang) == true
                    }
                }
                else -> null
            }
            val chosenSub = explicitSub ?: if (playbackPrefs.preferChineseSub) {
                flattenedSubs
                    .map { pair ->
                        val fmt = pair.first.getTrackFormat(pair.second)
                        val isDefault = (fmt.selectionFlags and C.SELECTION_FLAG_DEFAULT) != 0
                        val isExternal = fmt.sampleMimeType == MimeTypes.APPLICATION_SUBRIP ||
                            fmt.sampleMimeType == MimeTypes.TEXT_VTT ||
                            fmt.sampleMimeType == MimeTypes.TEXT_SSA
                        pair to ChineseSubtitleMatcher.scoreChineseSubtitle(
                            language = fmt.language,
                            label = fmt.label,
                            isDefault = isDefault,
                            isExternal = isExternal,
                        )
                    }
                    .filter { it.second > 0 }
                    .maxByOrNull { it.second }
                    ?.first
            } else {
                null
            }

            if (chosenSub != null) {
                paramsBuilder = paramsBuilder
                    .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                    .setOverrideForType(
                        TrackSelectionOverride(chosenSub.first.mediaTrackGroup, chosenSub.second),
                    )
                changed = true
            }
        }

        if (changed) {
            ep.trackSelectionParameters = paramsBuilder.build()
            ui.tracksVersion++
        }
    }

    fun selectSubtitleChoice(choice: ResolvedTrackChoice) {
        val extSub = choice.externalSub
        if (extSub != null) {
            ui.showSubtitleSheet = false
            val subKey = SubtitlePrefetcher.subtitleKey(extSub)
            session.activeSubtitleJob?.cancel()
            session.activeSubtitleJob = null
            session.failedExternalSubKey = null
            session.activeDisableSubtitles = false
            session.selectedExternalSubKey = subKey
            session.activePreferredSubtitleLang = extSub.language.ifBlank { extSub.title }

            val cached = subtitlePrefetcher?.getCached(extSub) ?: session.prefetchedSubtitles[subKey]
            if (cached != null && cached.file.exists()) {
                session.loadingExternalSubKey = null
                applyPrefetchedExternalSubtitle(extSub, cached, fromAutoStartup = false)
                return
            }
            val prefetcher = subtitlePrefetcher
            if (prefetcher == null) {
                ui.hudMessage = "外挂字幕不可用"
                return
            }
            session.loadingExternalSubKey = subKey
            ui.tracksVersion++
            session.activeSubtitleJob = playerScope.launch {
                val res = prefetcher.prefetch(extSub)
                if (session.loadingExternalSubKey == subKey) {
                    session.loadingExternalSubKey = null
                }
                res.onSuccess { prefetched ->
                    session.prefetchedSubtitles[subKey] = prefetched
                    if (session.selectedExternalSubKey == subKey && !session.activeDisableSubtitles) {
                        applyPrefetchedExternalSubtitle(extSub, prefetched, fromAutoStartup = false)
                    }
                }.onFailure {
                    if (session.selectedExternalSubKey == subKey) {
                        session.selectedExternalSubKey = null
                    }
                    session.failedExternalSubKey = subKey
                    ui.tracksVersion++
                    ui.hudMessage = "外挂字幕加载失败，请点击字幕菜单重试"
                }
            }
            return
        }

        session.activeSubtitleJob?.cancel()
        session.activeSubtitleJob = null
        session.loadingExternalSubKey = null
        session.selectedExternalSubKey = null

        if (isMpvActive) {
            if (choice.trackId == null) {
                session.mpvEngineHolder?.disableSubtitles()
                session.activeDisableSubtitles = true
                session.activePreferredSubtitleLang = null
            } else {
                session.mpvEngineHolder?.selectSubtitleTrack(choice.trackId)
                session.activeDisableSubtitles = false
                session.activePreferredSubtitleLang = choice.language ?: choice.label
            }
            dispatchVideoSync("track_change")
        } else {
            val ep = exoPlayer
            if (ep != null) {
                val builder = ep.trackSelectionParameters.buildUpon()
                if (choice.group == null) {
                    builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                    session.activeDisableSubtitles = true
                    session.activePreferredSubtitleLang = null
                } else {
                    builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .setOverrideForType(TrackSelectionOverride(choice.group.mediaTrackGroup, choice.trackIndex))
                    session.activeDisableSubtitles = false
                    session.activePreferredSubtitleLang = choice.language ?: choice.label
                }
                ep.trackSelectionParameters = builder.build()
            }
        }
        ui.tracksVersion++
        ui.hudMessage = "字幕：${choice.label}"
        ui.showSubtitleSheet = false
    }

    fun selectAudioChoice(choice: ResolvedTrackChoice) {
        if (isMpvActive) {
            choice.trackId?.let { id ->
                session.mpvEngineHolder?.selectAudioTrack(id)
                session.activePreferredAudioLang = choice.language ?: choice.label
                ui.tracksVersion++
                dispatchVideoSync("track_change")
                ui.hudMessage = "音轨：${choice.label}"
            }
        } else {
            choice.group?.let { grp ->
                exoPlayer?.let { ep ->
                    ep.trackSelectionParameters = ep.trackSelectionParameters
                        .buildUpon()
                        .setOverrideForType(TrackSelectionOverride(grp.mediaTrackGroup, choice.trackIndex))
                        .build()
                    session.activePreferredAudioLang = choice.language ?: choice.label
                    ui.tracksVersion++
                    ui.hudMessage = "音轨：${choice.label}"
                }
            }
        }
        ui.showAudioTrackSheet = false
    }
}

@OptIn(UnstableApi::class)
private fun resolveSubtitleChoices(
    isMpvActive: Boolean,
    exoPlayer: ExoPlayer?,
    mpvEngine: MpvPlaybackEngine?,
    mpvSubtitleTracks: List<EngineTrackItem>,
    externalSubtitles: List<SubtitleTrackItem>,
    prefetchedSubtitles: Map<String, PrefetchedSubtitle>,
    selectedExternalSubKey: String?,
    loadingExternalSubKey: String?,
    failedExternalSubKey: String?,
    disableSubtitles: Boolean,
): List<ResolvedTrackChoice> {
    val list = mutableListOf<ResolvedTrackChoice>()
    val validExtSubs = externalSubtitles.filter { it.url.isNotBlank() }

    if (isMpvActive) {
        val extTrackIdBySubKey = HashMap<String, String>()
        for (sub in validExtSubs) {
            val subKey = SubtitlePrefetcher.subtitleKey(sub)
            val localFile = prefetchedSubtitles[subKey]?.file
            if (localFile != null) {
                mpvEngine?.findTrackIdForExternalFile(localFile.absolutePath)?.let { tid ->
                    extTrackIdBySubKey[subKey] = tid
                }
            }
        }
        val mappedExtIds = extTrackIdBySubKey.values.toSet()
        val embeddedTracks = mpvSubtitleTracks.filter { it.id !in mappedExtIds }
        val anySelected = !disableSubtitles && (
            selectedExternalSubKey != null || embeddedTracks.any { it.isSelected }
            )
        list += ResolvedTrackChoice("关闭字幕", null, null, null, -1, !anySelected)
        embeddedTracks.forEachIndexed { idx, track ->
            list += ResolvedTrackChoice(
                label = "内封 · ${track.label}",
                language = track.language,
                trackId = track.id,
                group = null,
                trackIndex = idx,
                selected = !disableSubtitles && selectedExternalSubKey == null && track.isSelected,
            )
        }
        validExtSubs.forEachIndexed { idx, sub ->
            val subKey = SubtitlePrefetcher.subtitleKey(sub)
            val prefetched = prefetchedSubtitles[subKey]
            val fmtTag = prefetched?.format?.extension?.uppercase()
            val label = listOfNotNull(
                "外挂",
                sub.title.takeIf { it.isNotBlank() },
                sub.language.takeIf { it.isNotBlank() && it != "und" },
                fmtTag,
            ).distinct().joinToString(" · ").ifBlank { "外挂字幕 ${idx + 1}" }
            val loading = loadingExternalSubKey == subKey
            val failed = failedExternalSubKey == subKey && !loading
            list += ResolvedTrackChoice(
                label = label,
                language = sub.language,
                trackId = extTrackIdBySubKey[subKey],
                group = null,
                trackIndex = idx,
                selected = !disableSubtitles && selectedExternalSubKey == subKey,
                externalSub = sub,
                isLoading = loading,
                isFailed = failed,
            )
        }
        return list
    }

    val ep = exoPlayer
    val tracks = ep?.currentTracks
    val isTextDisabled = ep?.trackSelectionParameters?.disabledTrackTypes?.contains(C.TRACK_TYPE_TEXT) == true

    val exoExtMatch = HashMap<String, Pair<Tracks.Group, Int>>()
    val embeddedExoItems = mutableListOf<ResolvedTrackChoice>()
    tracks?.groups?.filter { it.type == C.TRACK_TYPE_TEXT }?.forEachIndexed { gIdx, grp ->
        for (i in 0 until grp.length) {
            val fmt = grp.getTrackFormat(i)
            val rawId = fmt.id.orEmpty()
            val markerIdx = rawId.indexOf(EXO_EXT_SUB_ID_PREFIX)
            if (markerIdx >= 0) {
                val subKey = rawId.substring(markerIdx + EXO_EXT_SUB_ID_PREFIX.length)
                exoExtMatch[subKey] = grp to i
            } else {
                val baseLabel = listOfNotNull(
                    fmt.label?.takeIf { it.isNotBlank() },
                    fmt.language?.takeIf { it.isNotBlank() && it != "und" },
                ).joinToString(" · ").ifBlank { "字幕轨道 ${gIdx + 1}" }
                embeddedExoItems += ResolvedTrackChoice(
                    label = "内封 · $baseLabel",
                    language = fmt.language,
                    trackId = fmt.id,
                    group = grp,
                    trackIndex = i,
                    selected = !disableSubtitles && !isTextDisabled && selectedExternalSubKey == null && grp.isTrackSelected(i),
                )
            }
        }
    }

    val anySelected = !disableSubtitles && (
        selectedExternalSubKey != null || embeddedExoItems.any { it.selected }
        )
    list += ResolvedTrackChoice("关闭字幕", null, null, null, -1, !anySelected)
    list += embeddedExoItems
    validExtSubs.forEachIndexed { idx, sub ->
        val subKey = SubtitlePrefetcher.subtitleKey(sub)
        val prefetched = prefetchedSubtitles[subKey]
        val fmtTag = prefetched?.format?.extension?.uppercase()
        val label = listOfNotNull(
            "外挂",
            sub.title.takeIf { it.isNotBlank() },
            sub.language.takeIf { it.isNotBlank() && it != "und" },
            fmtTag,
        ).distinct().joinToString(" · ").ifBlank { "外挂字幕 ${idx + 1}" }
        val exoPair = exoExtMatch[subKey]
        val loading = loadingExternalSubKey == subKey
        val failed = failedExternalSubKey == subKey && !loading
        list += ResolvedTrackChoice(
            label = label,
            language = sub.language,
            trackId = sub.id,
            group = exoPair?.first,
            trackIndex = exoPair?.second ?: idx,
            selected = !disableSubtitles && selectedExternalSubKey == subKey,
            externalSub = sub,
            isLoading = loading,
            isFailed = failed,
        )
    }
    return list
}

private fun resolveAudioChoices(
    isMpvActive: Boolean,
    exoPlayer: ExoPlayer?,
    mpvAudioTracks: List<EngineTrackItem>,
): List<ResolvedTrackChoice> {
    val list = mutableListOf<ResolvedTrackChoice>()
    if (isMpvActive) {
        mpvAudioTracks.forEachIndexed { idx, track ->
            list += ResolvedTrackChoice(
                label = track.label,
                language = track.language,
                trackId = track.id,
                group = null,
                trackIndex = idx,
                selected = track.isSelected,
            )
        }
        return list
    }
    val ep = exoPlayer ?: return list
    ep.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }.forEachIndexed { gIdx, grp ->
        for (i in 0 until grp.length) {
            val fmt = grp.getTrackFormat(i)
            val ch = if (fmt.channelCount > 0) "${fmt.channelCount}ch" else null
            val label = listOfNotNull(
                fmt.label?.takeIf { it.isNotBlank() },
                fmt.language?.takeIf { it.isNotBlank() && it != "und" },
                ch,
            ).joinToString(" · ").ifBlank { "音轨 ${gIdx + 1}" }
            list += ResolvedTrackChoice(
                label = label,
                language = fmt.language,
                trackId = fmt.id,
                group = grp,
                trackIndex = i,
                selected = grp.isTrackSelected(i),
            )
        }
    }
    return list
}

/**
 * Material 3 Expressive 原生全屏音视频播放器：
 * - **音频模式**：动态丝绒封面着色、LRC 多时间戳同步歌词、3 秒上一曲规则、随机/循环与延迟解析队列、收起迷你条不误报停止；
 * - **视频模式**：Media3 硬件/FFmpeg 渲染、4.5 秒控制栏自动隐藏与沉浸式系统栏、三分区双击快进快退/播控、长按 2.0x 触觉加速、
 *   横竖屏双态锁屏、动态比例自动画中画（PiP）、中文字幕与播前选轨自动匹配、本地断点续播胶囊、5 秒片尾自动连播下一集玻璃卡片及外部播放器唤起。
 */
@OptIn(UnstableApi::class)
@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeMediaPlayerOverlay(
    request: MediaPlaybackRequest,
    sharedPlayer: ExoPlayer? = null,
    instanceUrl: String = "",
    audioShuffleEnabled: Boolean = false,
    audioRepeatMode: Int = Player.REPEAT_MODE_OFF,
    onUpdateAudioShuffle: ((Boolean) -> Unit)? = null,
    onUpdateAudioRepeatMode: ((Int) -> Unit)? = null,
    onAudioSkipPrevious: (() -> Unit)? = null,
    onAudioSkipNext: (() -> Unit)? = null,
    onClose: () -> Unit,
    onMinimizeToMiniBar: (() -> Unit)? = null,
    onSwitchRequest: ((MediaPlaybackRequest) -> Unit)? = null,
    onMetadataEnriched: ((MediaPlaybackRequest) -> Unit)? = null,
    repository: MoviePilotRepository? = null,
    onReportProgress: ((positionMs: Long, durationMs: Long, isPaused: Boolean, state: String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val playbackPrefs = remember(context) { PlaybackPreferencesStore(context) }
    val localHistoryStore = remember(context) { LocalPlaybackHistoryStore(context) }
    val danmakuPrefs = remember(context) { DanmakuPreferencesStore(context) }
    val activity = context as? Activity
    val initialOrientation = remember(activity) {
        activity?.requestedOrientation ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }
    val ui = remember {
        PlayerUiPersistentState(
            initialResizeMode = playbackPrefs.defaultResizeMode.coerceIn(0, VIDEO_RESIZE_MODES.lastIndex),
            initialOrientation = initialOrientation,
            initialInPip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity?.isInPictureInPictureMode == true,
            initialShuffle = audioShuffleEnabled,
            initialRepeatMode = audioRepeatMode,
            initialDanmakuVisible = danmakuPrefs.enabled,
        )
    }

    val initialLocalSavedMs = remember(request.localResumeId, instanceUrl, request.server) {
        localHistoryStore.readResumePositionMs(instanceUrl, request.server, request.localResumeId)
    }
    val bestInitialResumeMs = remember(initialLocalSavedMs, request.resumePositionMs) {
        LocalPlaybackHistoryStore.resolveBestResumeMs(initialLocalSavedMs, request.resumePositionMs)
    }

    val ownsPlayer = sharedPlayer == null
    val playerScope = rememberCoroutineScope()
    val initialExternalSub = remember(
        request.url,
        request.itemId,
        request.subtitles,
        request.preferredSubtitleId,
        request.preferredSubtitleLang,
        request.disableSubtitles,
        ownsPlayer,
    ) {
        if (ownsPlayer && !request.isAudio) {
            pickInitialExternalSubtitle(request, playbackPrefs)
        } else {
            null
        }
    }
    val enginePlan = remember(
        request.url,
        request.isAudio,
        playbackPrefs.videoEngine,
        playbackPrefs.decodeMode,
        playbackPrefs.ignoreAssStyle,
    ) {
        AndroidPlaybackEngineRouter.resolvePlan(request, playbackPrefs)
    }
    val session = remember(request.url, ownsPlayer) {
        PlayerSessionState(
            request = request,
            ownsPlayer = ownsPlayer,
            primaryEngineId = enginePlan.primary,
            bestInitialResumeMs = bestInitialResumeMs,
            initialExternalSubKey = initialExternalSub?.let { SubtitlePrefetcher.subtitleKey(it) },
        )
    }
    val subtitlePrefetcher = remember(request.url, request.itemId, ownsPlayer) {
        if (ownsPlayer && !request.isAudio && request.subtitles.isNotEmpty()) {
            SubtitlePrefetcher(
                context = context,
                request = request,
                activeStreamProvider = { session.activeStreamRouteRef.get() },
            )
        } else {
            null
        }
    }
    DisposableEffect(subtitlePrefetcher) {
        onDispose {
            session.activeSubtitleJob?.cancel()
            subtitlePrefetcher?.close()
        }
    }

    val isMpvActive = ownsPlayer && !request.isAudio && session.activeEngineKind == ResolvedAndroidEngine.ENHANCED
    val exoPlayer: ExoPlayer? = remember(request.url, sharedPlayer, isMpvActive, session.startupSubtitleGateReady) {
        if (isMpvActive || (!session.startupSubtitleGateReady && ownsPlayer && !request.isAudio)) {
            null
        } else {
            val built = sharedPlayer ?: buildConfiguredExoPlayer(
                context = context,
                request = request,
                resumePositionOverrideMs = session.engineCarryPositionMs,
                activeStreamProvider = { session.activeStreamRouteRef.get() },
                prefetchedSubtitles = session.prefetchedSubtitles.toMap(),
                deferRemoteSubtitles = ownsPlayer && !request.isAudio,
            )
            session.positionMs = session.positionMs.coerceAtLeast(built.currentPosition.coerceAtLeast(0L))
            session.durationMs = (built.duration).coerceAtLeast(1L)
            built
        }
    }

    val speeds = remember(isMpvActive) {
        if (isMpvActive) listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f, 2.5f, 3.0f) else PLAYER_SUPPORTED_SPEEDS
    }
    val isPlayingState = remember(exoPlayer, isMpvActive) {
        mutableStateOf(exoPlayer?.let { it.isPlaying || it.playWhenReady } ?: true)
    }
    val speedIndexState = remember(request.isAudio, isMpvActive) {
        val targetSpd = if (request.isAudio) 1.0f else playbackPrefs.defaultSpeed
        val defaultIdx = speeds.indexOfFirst { abs(it - targetSpd) < 0.05f }.takeIf { it >= 0 }
            ?: speeds.indexOf(1.0f).coerceAtLeast(0)
        mutableIntStateOf(defaultIdx)
    }
    val videoSyncTracker = remember(request.url, request.playSessionId, ownsPlayer) {
        PlaybackSyncSessionTracker(request.playSessionId.orEmpty())
    }
    val hasEmittedVideoStartState = remember(request.url, request.playSessionId, ownsPlayer) {
        mutableStateOf(false)
    }

    val latestReportProgressState = rememberUpdatedState(onReportProgress)
    val latestSwitchRequestState = rememberUpdatedState(onSwitchRequest)
    val latestCloseState = rememberUpdatedState(onClose)
    val latestMetadataEnrichedState = rememberUpdatedState(onMetadataEnriched)

    val controller = remember(
        request,
        ownsPlayer,
        exoPlayer,
        isMpvActive,
        videoSyncTracker,
        instanceUrl,
        repository,
        subtitlePrefetcher,
        playerScope,
    ) {
        PlayerRuntimeController(
            context = context,
            request = request,
            ownsPlayer = ownsPlayer,
            instanceUrl = instanceUrl,
            repository = repository,
            playbackPrefs = playbackPrefs,
            localHistoryStore = localHistoryStore,
            ui = ui,
            session = session,
            exoPlayer = exoPlayer,
            isMpvActive = isMpvActive,
            speeds = speeds,
            isPlayingState = isPlayingState,
            speedIndexState = speedIndexState,
            hasEmittedVideoStartState = hasEmittedVideoStartState,
            videoSyncTracker = videoSyncTracker,
            latestReportProgressState = latestReportProgressState,
            latestSwitchRequestState = latestSwitchRequestState,
            latestCloseState = latestCloseState,
            latestMetadataEnrichedState = latestMetadataEnrichedState,
            subtitlePrefetcher = subtitlePrefetcher,
            playerScope = playerScope,
        )
    }

    val canMinimizeAudio = request.isAudio && playbackPrefs.keepMusicMiniBar && onMinimizeToMiniBar != null
    PlayerBackAndCommonTimersEffect(
        controller = controller,
        canMinimizeAudio = canMinimizeAudio,
        onMinimizeToMiniBar = onMinimizeToMiniBar,
        onCloseAudio = onClose,
    )
    PlayerInitialSubtitlePrefetchEffect(
        controller = controller,
        initialExternalSub = initialExternalSub,
    )
    PlayerMpvEngineEffect(controller = controller)
    PlayerExoEngineEffect(controller = controller)
    PlayerWindowPipAndSessionEffects(
        controller = controller,
        activity = activity,
        initialOrientation = initialOrientation,
    )
    PlayerProgressTickerEffect(controller = controller)

    if (request.isAudio) {
        NativeAudioPlayerStage(
            controller = controller,
            canMinimizeAudio = canMinimizeAudio,
            audioShuffleEnabled = audioShuffleEnabled,
            audioRepeatMode = audioRepeatMode,
            onUpdateAudioShuffle = onUpdateAudioShuffle,
            onUpdateAudioRepeatMode = onUpdateAudioRepeatMode,
            onAudioSkipPrevious = onAudioSkipPrevious,
            onAudioSkipNext = onAudioSkipNext,
            onClose = onClose,
            onMinimizeToMiniBar = onMinimizeToMiniBar,
            onSwitchRequest = onSwitchRequest,
        )
        return
    }

    NativeVideoPlayerStage(
        controller = controller,
        activity = activity,
        danmakuPrefs = danmakuPrefs,
    )
    VideoDanmakuHost(
        controller = controller,
        danmakuPrefs = danmakuPrefs,
    )
}

@Composable
private fun PlayerBackAndCommonTimersEffect(
    controller: PlayerRuntimeController,
    canMinimizeAudio: Boolean,
    onMinimizeToMiniBar: (() -> Unit)?,
    onCloseAudio: () -> Unit,
) {
    val ui = controller.ui
    val session = controller.session
    val request = controller.request

    BackHandler(enabled = ui.isLocked) {
        ui.controlsVisible = true
        ui.bumpInteraction()
        ui.hudMessage = "屏幕已锁定，请点击右侧锁图标解锁"
    }
    BackHandler(enabled = !ui.isLocked) {
        if (canMinimizeAudio) {
            onMinimizeToMiniBar?.invoke()
        } else if (request.isAudio) {
            onCloseAudio()
        } else {
            controller.closeVideoCleanly()
        }
    }

    LaunchedEffect(session.resumeBannerPositionMs) {
        if (session.resumeBannerPositionMs != null) {
            delay(6_000L)
            session.resumeBannerPositionMs = null
        }
    }

    val isNotDragging = ui.draggingProgress < 0f
    LaunchedEffect(
        request.isAudio,
        ui.controlsVisible,
        controller.isPlaying,
        isNotDragging,
        ui.anySheetOpen,
        ui.isLongPressBoost,
        ui.lastInteractionTick,
    ) {
        if (!request.isAudio && ui.controlsVisible && controller.isPlaying && isNotDragging && !ui.anySheetOpen && !ui.isLongPressBoost) {
            delay(4_500L)
            ui.controlsVisible = false
        }
    }

    LaunchedEffect(ui.hudMessage) {
        if (ui.hudMessage != null) {
            delay(1400L)
            ui.hudMessage = null
        }
    }
}

/**
 * 起播阶段首选外挂字幕受控预取协调器：
 * - 启动后台无 Range 预取并在顶部展示非阻塞「正在加载外挂字幕…」提示；
 * - 最多等待 2500ms：若已完成则零延迟带真实嗅探格式与最优内核（含内嵌字体自动切 MPV）起播；
 * - 若超过 2500ms 仍在实时子集化，则立即放行画面起播，并在预取完成瞬间动态注入/热切对齐当前进度。
 */
@Composable
private fun PlayerInitialSubtitlePrefetchEffect(
    controller: PlayerRuntimeController,
    initialExternalSub: SubtitleTrackItem?,
) {
    val latestController by rememberUpdatedState(controller)
    val session = controller.session
    val ui = controller.ui
    val prefetcher = controller.subtitlePrefetcher
    val request = controller.request

    LaunchedEffect(request.url, request.itemId, controller.ownsPlayer) {
        if (!controller.ownsPlayer || request.isAudio || initialExternalSub == null || prefetcher == null) {
            session.startupSubtitleGateReady = true
            return@LaunchedEffect
        }
        val targetKey = SubtitlePrefetcher.subtitleKey(initialExternalSub)
        session.loadingExternalSubKey = targetKey
        session.failedExternalSubKey = null

        val fastResult = withTimeoutOrNull(2_500L) {
            prefetcher.prefetch(initialExternalSub)
        }
        if (fastResult != null) {
            if (session.loadingExternalSubKey == targetKey) {
                session.loadingExternalSubKey = null
            }
            fastResult.onSuccess { prefetched ->
                session.prefetchedSubtitles[targetKey] = prefetched
                if (
                    session.activeEngineKind != ResolvedAndroidEngine.ENHANCED &&
                    shouldUpgradeToMpvForPrefetchedSubtitle(prefetched, latestController.playbackPrefs)
                ) {
                    session.activeEngineKind = ResolvedAndroidEngine.ENHANCED
                    ui.hudMessage = upgradeReasonForSubtitle(prefetched)
                }
            }.onFailure {
                if (session.selectedExternalSubKey == targetKey) {
                    session.selectedExternalSubKey = null
                }
                session.failedExternalSubKey = targetKey
                ui.hudMessage = "外挂字幕加载失败，可在字幕菜单点击重试"
            }
            session.startupSubtitleGateReady = true
            return@LaunchedEffect
        }

        // 子集化超过 2.5s 仍在进行中：先放行视频起播，后台继续等待同一预取任务完成并实时对齐注入
        session.startupSubtitleGateReady = true
        val slowResult = prefetcher.prefetch(initialExternalSub)
        if (session.loadingExternalSubKey == targetKey) {
            session.loadingExternalSubKey = null
        }
        slowResult.onSuccess { prefetched ->
            session.prefetchedSubtitles[targetKey] = prefetched
            if (session.selectedExternalSubKey == targetKey && !session.activeDisableSubtitles) {
                latestController.applyPrefetchedExternalSubtitle(
                    sub = initialExternalSub,
                    prefetched = prefetched,
                    fromAutoStartup = true,
                )
            } else {
                ui.tracksVersion++
            }
        }.onFailure {
            if (session.selectedExternalSubKey == targetKey) {
                session.selectedExternalSubKey = null
            }
            session.failedExternalSubKey = targetKey
            ui.tracksVersion++
            ui.hudMessage = "外挂字幕加载失败，可在字幕菜单点击重试"
        }
    }
}

@Composable
private fun PlayerMpvEngineEffect(controller: PlayerRuntimeController) {
    val request = controller.request
    val session = controller.session
    val ui = controller.ui
    DisposableEffect(request.url, controller.isMpvActive, session.startupSubtitleGateReady) {
        if (!controller.isMpvActive || !session.startupSubtitleGateReady) {
            session.mpvEngineHolder = null
            return@DisposableEffect onDispose {}
        }
        val engine = MpvPlaybackEngine(
            context = controller.context,
            request = request,
            prefs = controller.playbackPrefs,
            initialStartPositionMs = session.engineCarryPositionMs,
            activeStreamRouteRef = session.activeStreamRouteRef,
            onStateSnapshot = { playing, pos, dur ->
                controller.isPlaying = playing
                session.positionMs = pos.coerceAtLeast(0L)
                if (dur > 0L) session.durationMs = dur
                if (playing && !controller.hasEmittedVideoStart && pos > 0L) {
                    controller.dispatchVideoSync("start", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = false)
                }
            },
            onVideoSizeChanged = { w, h ->
                ui.videoAspectRatio = PlaybackPipBridge.computeClampedPipAspectRatio(w, h)
            },
            onTracksUpdated = { audio, subs ->
                session.mpvAudioTracks = audio
                session.mpvSubtitleTracks = subs
                ui.tracksVersion++
            },
            onEnded = {
                controller.localHistoryStore.clearResumePosition(controller.instanceUrl, request.server, request.localResumeId)
                val dur = controller.activeDurationMs()
                controller.dispatchVideoSync("finish", posOverrideMs = dur, durOverrideMs = dur, pausedOverride = true)
                if (controller.hasNextVideoEpisode && !session.upNextCancelled && !session.autoAdvancedTriggered) {
                    session.autoAdvancedTriggered = true
                    controller.switchVideoEpisode(request.queueIndex + 1)
                }
            },
            onError = { _ ->
                val curPos = controller.activeCurrentPositionMs()
                if (curPos <= 3_000L && session.mpvFallbackRoutes.isNotEmpty()) {
                    val failedKind = session.currentRouteKind
                    val failedUrl = session.activeStreamRouteRef.get().first
                    if (failedKind == "server_lan" || failedKind == "server_wan") {
                        controller.repository?.playbackRouteResolver?.markRouteFailed(request.server, failedUrl)
                    }
                    while (session.mpvFallbackRoutes.isNotEmpty()) {
                        val nextRoute = session.mpvFallbackRoutes.removeFirst()
                        if (nextRoute.url.isBlank() || nextRoute.url == failedUrl) continue
                        session.currentRouteKind = nextRoute.kind
                        session.mpvEngineHolder?.reloadWithRoute(nextRoute.url, nextRoute.headers)
                        return@MpvPlaybackEngine
                    }
                }
                if (controller.playbackPrefs.videoEngine == "auto" && !session.didAutoFallbackEngine && curPos <= 3_000L) {
                    session.didAutoFallbackEngine = true
                    controller.switchVideoEngine(ResolvedAndroidEngine.NATIVE, "已自动切换至 Media3 原生内核")
                    return@MpvPlaybackEngine
                }
                session.playbackLoadFailed = true
                controller.isPlaying = false
                ui.hudMessage = "无法加载当前媒体流，请检查网络或在右上角菜单切换内核重试"
            },
            prefetchedSubtitlesProvider = { session.prefetchedSubtitles.toMap() },
            selectedExternalSubKeyProvider = {
                if (session.activeDisableSubtitles) null else session.selectedExternalSubKey
            },
            deferRemoteSubtitlesToPrefetcher = true,
        )
        engine.setResizeMode(ui.resizeModeIndex)
        session.mpvEngineHolder = engine
        onDispose {
            val isEngineSwitch = session.suppressStopForEngineSwitchRef.compareAndSet(true, false)
            val pos = engine.positionMs.coerceAtLeast(0L)
            val dur = engine.durationMs.coerceAtLeast(0L)
            if (!isEngineSwitch) {
                controller.localHistoryStore.recordPlaybackProgress(controller.instanceUrl, request.server, request.localResumeId, pos, dur)
                controller.dispatchVideoSync("stop", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = true)
            }
            if (session.mpvEngineHolder === engine) {
                session.mpvEngineHolder = null
            }
            engine.release()
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun PlayerExoEngineEffect(controller: PlayerRuntimeController) {
    val ep = controller.exoPlayer
    val request = controller.request
    val session = controller.session
    val ui = controller.ui
    val nightModeEffect = remember(ep) { AudioNightModeEffect() }

    LaunchedEffect(request.url, request.isAudio) {
        if (!request.isAudio || !EmbeddedAudioMetadataFetcher.needsExtraction(request)) {
            return@LaunchedEffect
        }
        val fetched = EmbeddedAudioMetadataFetcher.fetchEmbeddedMetadata(controller.context, request)
        if (fetched != null) {
            session.embeddedAudioMeta = fetched
            controller.notifyMetadataEnriched(EmbeddedAudioMetadataFetcher.applyToRequest(request, fetched))
        }
    }

    DisposableEffect(ep, controller.ownsPlayer, request.url) {
        if (ep == null) return@DisposableEffect onDispose {}
        val fallbackQueue = buildFallbackRoutesDeque(request)
        nightModeEffect.apply(ep.audioSessionId, controller.playbackPrefs.audioNightMode)
        val listener = createExoOverlayListener(controller, ep, nightModeEffect, fallbackQueue)
        ep.addListener(listener)
        if (ep.currentTracks.groups.isNotEmpty()) {
            controller.applyInitialTrackPreferencesIfReady(ep.currentTracks)
        }
        onDispose {
            ep.removeListener(listener)
            nightModeEffect.release()
            if (controller.ownsPlayer) {
                val isEngineSwitch = session.suppressStopForEngineSwitchRef.compareAndSet(true, false)
                val pos = ep.currentPosition.coerceAtLeast(0L)
                val dur = ep.duration.coerceAtLeast(0L)
                if (!isEngineSwitch) {
                    controller.localHistoryStore.recordPlaybackProgress(controller.instanceUrl, request.server, request.localResumeId, pos, dur)
                    if (!request.isAudio) {
                        controller.dispatchVideoSync("stop", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = true)
                    }
                }
                ep.release()
            }
        }
    }
}

@OptIn(UnstableApi::class)
private fun createExoOverlayListener(
    controller: PlayerRuntimeController,
    ep: ExoPlayer,
    nightModeEffect: AudioNightModeEffect,
    fallbackQueue: ArrayDeque<PlaybackRouteDto>,
): Player.Listener {
    val request = controller.request
    val session = controller.session
    val ui = controller.ui

    fun extractLiveAudioMetaIfNeeded() {
        val currentDisplay = EmbeddedAudioMetadataFetcher.applyToRequest(request, session.embeddedAudioMeta)
        if (!request.isAudio || !EmbeddedAudioMetadataFetcher.needsExtraction(currentDisplay)) return
        val liveMeta = EmbeddedAudioMetadataFetcher.extractFromExoPlayer(
            context = controller.context,
            player = ep,
            cacheKey = request.localResumeId.ifBlank { request.url },
        ) ?: return
        val prev = session.embeddedAudioMeta
        val mergedMeta = ResolvedEmbeddedAudioMetadata(
            title = prev?.title ?: liveMeta.title,
            artist = prev?.artist ?: liveMeta.artist,
            album = prev?.album ?: liveMeta.album,
            lyrics = prev?.lyrics ?: liveMeta.lyrics,
            artworkFileUri = prev?.artworkFileUri ?: liveMeta.artworkFileUri,
            artworkBytes = prev?.artworkBytes ?: liveMeta.artworkBytes,
        )
        session.embeddedAudioMeta = mergedMeta
        controller.notifyMetadataEnriched(EmbeddedAudioMetadataFetcher.applyToRequest(request, mergedMeta))
    }

    return object : Player.Listener {
        override fun onAudioSessionIdChanged(audioSessionId: Int) {
            nightModeEffect.apply(audioSessionId, controller.playbackPrefs.audioNightMode)
        }

        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
            if (!controller.ownsPlayer || ep.currentPosition > 3_000L) return
            val isDecoderOrFormatError = error.errorCode in setOf(
                androidx.media3.common.PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
                androidx.media3.common.PlaybackException.ERROR_CODE_DECODING_FAILED,
                androidx.media3.common.PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
                androidx.media3.common.PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
                androidx.media3.common.PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
                androidx.media3.common.PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
            )
            if (
                isDecoderOrFormatError &&
                !request.isAudio &&
                session.activeEngineKind == ResolvedAndroidEngine.NATIVE &&
                !session.didAutoFallbackEngine
            ) {
                session.didAutoFallbackEngine = true
                controller.switchVideoEngine(
                    ResolvedAndroidEngine.ENHANCED,
                    "当前格式不兼容，已自动切换至 ${ResolvedAndroidEngine.ENHANCED.displayName}",
                )
                return
            }
            val failedKind = session.currentRouteKind
            val failedUrl = session.activeStreamRouteRef.get().first
            if (failedKind == "server_lan" || failedKind == "server_wan") {
                controller.repository?.playbackRouteResolver?.markRouteFailed(request.server, failedUrl)
            }
            while (fallbackQueue.isNotEmpty()) {
                val nextRoute = fallbackQueue.removeFirst()
                if (nextRoute.url.isBlank() || nextRoute.url == failedUrl) continue
                session.activeStreamRouteRef.set(nextRoute.url to nextRoute.headers)
                session.currentRouteKind = nextRoute.kind
                val curMeta = ep.currentMediaItem?.mediaMetadata ?: MediaMetadata.EMPTY
                val curSubs = ep.currentMediaItem?.localConfiguration?.subtitleConfigurations.orEmpty()
                val fallbackItem = MediaItem.Builder()
                    .setUri(Uri.parse(nextRoute.url))
                    .setMediaMetadata(curMeta)
                    .setSubtitleConfigurations(curSubs)
                    .build()
                ep.setMediaItem(fallbackItem)
                ep.prepare()
                ep.playWhenReady = true
                return
            }
            if (!request.isAudio && controller.playbackPrefs.videoEngine == "auto" && !session.didAutoFallbackEngine) {
                session.didAutoFallbackEngine = true
                controller.switchVideoEngine(
                    ResolvedAndroidEngine.ENHANCED,
                    "当前格式不兼容，已自动切换至 ${ResolvedAndroidEngine.ENHANCED.displayName}",
                )
                return
            }
            session.playbackLoadFailed = true
            controller.isPlaying = false
            ui.hudMessage = "无法加载当前媒体流，请检查网络或在右上角菜单切换内核重试"
        }

        override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
            extractLiveAudioMetaIfNeeded()
        }

        override fun onTracksChanged(tracks: Tracks) {
            val hadInitial = session.appliedInitialTracks
            ui.tracksVersion++
            controller.applyInitialTrackPreferencesIfReady(tracks)
            controller.applySelectedExternalSubtitleToExoIfPresent(tracks)
            extractLiveAudioMetaIfNeeded()
            if (controller.ownsPlayer && !request.isAudio && hadInitial && controller.hasEmittedVideoStart) {
                controller.dispatchVideoSync("track_change")
            }
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            if (
                controller.ownsPlayer &&
                !request.isAudio &&
                (reason == Player.DISCONTINUITY_REASON_SEEK || reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT)
            ) {
                controller.dispatchVideoSync("seek", posOverrideMs = newPosition.positionMs.coerceAtLeast(0L))
            }
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (videoSize.width > 0 && videoSize.height > 0) {
                ui.videoAspectRatio = PlaybackPipBridge.computeClampedPipAspectRatio(videoSize.width, videoSize.height)
            }
        }

        override fun onIsPlayingChanged(playing: Boolean) {
            controller.isPlaying = playing
            if (controller.ownsPlayer && !request.isAudio) {
                val pos = ep.currentPosition.coerceAtLeast(0L)
                val dur = ep.duration.coerceAtLeast(0L)
                controller.localHistoryStore.recordPlaybackProgress(controller.instanceUrl, request.server, request.localResumeId, pos, dur)
                val trigger = when {
                    playing && !controller.hasEmittedVideoStart -> "start"
                    playing -> "resume"
                    else -> "pause"
                }
                controller.dispatchVideoSync(trigger, posOverrideMs = pos, durOverrideMs = dur, pausedOverride = !playing)
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED && controller.ownsPlayer && !request.isAudio) {
                controller.localHistoryStore.clearResumePosition(controller.instanceUrl, request.server, request.localResumeId)
                val dur = ep.duration.coerceAtLeast(0L)
                controller.dispatchVideoSync("finish", posOverrideMs = dur, durOverrideMs = dur, pausedOverride = true)
                if (controller.hasNextVideoEpisode && !session.upNextCancelled && !session.autoAdvancedTriggered) {
                    session.autoAdvancedTriggered = true
                    controller.switchVideoEpisode(request.queueIndex + 1)
                }
            }
        }
    }
}

@Composable
private fun PlayerWindowPipAndSessionEffects(
    controller: PlayerRuntimeController,
    activity: Activity?,
    initialOrientation: Int,
) {
    val hostView = LocalView.current
    val request = controller.request
    val ui = controller.ui
    val session = controller.session

    DisposableEffect(activity, hostView, request.isAudio, ui.controlsVisible, ui.isInPipMode) {
        val window = activity?.window
        val insetsController = if (window != null) WindowCompat.getInsetsController(window, hostView) else null
        if (!request.isAudio && insetsController != null) {
            insetsController.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (!ui.controlsVisible && !ui.isInPipMode) {
                insetsController.hide(WindowInsetsCompat.Type.systemBars())
            } else {
                insetsController.show(WindowInsetsCompat.Type.systemBars())
            }
        }
        onDispose {
            insetsController?.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    DisposableEffect(hostView, activity, request.isAudio) {
        val prevKeepScreenOn = hostView.keepScreenOn
        if (!request.isAudio) {
            hostView.keepScreenOn = true
        }
        val compActivity = activity as? ComponentActivity
        val pipListener = Consumer<PictureInPictureModeChangedInfo> { info ->
            ui.isInPipMode = info.isInPictureInPictureMode
            if (info.isInPictureInPictureMode) {
                ui.dismissSheetsOnPipEnter()
            }
            ui.danmakuOverlayRef?.syncPlayback(
                positionMs = controller.activeCurrentPositionMs(),
                playing = controller.activeIsPlaying(),
                rate = controller.currentSelectedSpeed,
                inPip = info.isInPictureInPictureMode,
            )
        }
        compActivity?.addOnPictureInPictureModeChangedListener(pipListener)
        onDispose {
            compActivity?.removeOnPictureInPictureModeChangedListener(pipListener)
            PlaybackPipBridge.onUserLeaveHintCallback = null
            if (activity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !request.isAudio) {
                runCatching {
                    activity.setPictureInPictureParams(
                        PictureInPictureParams.Builder().setAutoEnterEnabled(false).build(),
                    )
                }
            }
            hostView.keepScreenOn = prevKeepScreenOn
            if (activity != null) {
                if (!request.isAudio) {
                    activity.requestedOrientation = initialOrientation
                }
                val lp = activity.window.attributes
                if (lp.screenBrightness >= 0f) {
                    lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    activity.window.attributes = lp
                }
            }
        }
    }

    LaunchedEffect(activity, request.isAudio, controller.isPlaying, controller.playbackPrefs.autoPip, ui.videoAspectRatio) {
        if (activity == null || request.isAudio) {
            PlaybackPipBridge.onUserLeaveHintCallback = null
            return@LaunchedEffect
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PlaybackPipBridge.onUserLeaveHintCallback = null
            runCatching {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(ui.videoAspectRatio)
                    .setAutoEnterEnabled(controller.isPlaying && controller.playbackPrefs.autoPip)
                    .build()
                activity.setPictureInPictureParams(params)
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PlaybackPipBridge.onUserLeaveHintCallback = {
                if (controller.activeIsPlaying() && controller.playbackPrefs.autoPip && !activity.isInPictureInPictureMode) {
                    runCatching {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(ui.videoAspectRatio)
                            .build()
                        activity.enterPictureInPictureMode(params)
                    }
                }
            }
        }
    }

    val sessionBridgePlayer: Player? = if (controller.isMpvActive) session.mpvEngineHolder?.sessionPlayer else controller.exoPlayer
    DisposableEffect(sessionBridgePlayer, controller.ownsPlayer, request.isAudio, request.queueIndex, request.queue.size) {
        if (controller.ownsPlayer && !request.isAudio && sessionBridgePlayer != null) {
            PlaybackServiceBridge.attachActivePlayer(
                context = controller.context,
                exoPlayer = sessionBridgePlayer,
                canSkipPrevious = { controller.activeCurrentPositionMs() > 3_000L || controller.hasPrevVideoEpisode },
                canSkipNext = { controller.hasNextVideoEpisode },
                onSkipPrevious = {
                    if (controller.activeCurrentPositionMs() > 3_000L || !controller.hasPrevVideoEpisode) {
                        controller.activeSeekTo(0L)
                    } else {
                        controller.switchVideoEpisode(request.queueIndex - 1)
                    }
                },
                onSkipNext = {
                    if (controller.hasNextVideoEpisode) {
                        controller.switchVideoEpisode(request.queueIndex + 1)
                    }
                },
            )
        }
        onDispose {
            if (controller.ownsPlayer && sessionBridgePlayer != null) {
                PlaybackServiceBridge.detachIfMatching(sessionBridgePlayer)
            }
        }
    }

    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, controller.ownsPlayer, request.url) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if ((event == androidx.lifecycle.Lifecycle.Event.ON_PAUSE || event == androidx.lifecycle.Lifecycle.Event.ON_STOP) &&
                controller.ownsPlayer && !request.isAudio
            ) {
                val pos = controller.activeCurrentPositionMs().coerceAtLeast(0L)
                val dur = controller.activeDurationMs().coerceAtLeast(0L)
                if (pos > 0L) {
                    controller.localHistoryStore.recordPlaybackProgress(controller.instanceUrl, request.server, request.localResumeId, pos, dur)
                    controller.dispatchVideoSync("background", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = !controller.activeIsPlaying())
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
}

@Composable
private fun PlayerProgressTickerEffect(controller: PlayerRuntimeController) {
    val request = controller.request
    val session = controller.session
    val ui = controller.ui
    LaunchedEffect(controller.exoPlayer, session.mpvEngineHolder, controller.isMpvActive, controller.ownsPlayer, request.url) {
        var tick = 0
        while (true) {
            val playing = controller.activeIsPlaying()
            val pos = controller.activeCurrentPositionMs().coerceAtLeast(0L)
            val dur = controller.activeDurationMs().coerceAtLeast(1L)
            controller.isPlaying = playing
            session.positionMs = pos
            session.durationMs = dur
            if (!request.isAudio && request.danmakuEnabled) {
                val activeRate = if (ui.isLongPressBoost) 2.0f else controller.currentSelectedSpeed
                ui.danmakuOverlayRef?.syncPlayback(
                    positionMs = pos,
                    playing = playing,
                    rate = activeRate,
                    inPip = ui.isInPipMode,
                )
            }
            tick++
            if (controller.ownsPlayer && !request.isAudio && (dur > 1L || pos > 0L)) {
                if (tick % 3 == 0) {
                    controller.dispatchVideoSync("tick", posOverrideMs = pos, durOverrideMs = dur, pausedOverride = !playing)
                }
                if (tick % 25 == 0) {
                    controller.localHistoryStore.recordPlaybackProgress(controller.instanceUrl, request.server, request.localResumeId, pos, dur)
                }
            }
            delay(400L)
        }
    }
}

@Composable
private fun ResumeFromHistoryBanner(
    savedMs: Long?,
    onRestartFromZero: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (savedMs == null) return
    val colors = LocalMoviePilotColors.current
    Surface(
        shape = CircleShape,
        color = Color(0xDD171B26),
        modifier = modifier
            .border(0.8.dp, Color.White.copy(alpha = 0.18f), CircleShape),
    ) {
        Row(
            modifier = Modifier.padding(start = 14.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Rounded.Replay, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
            Text(
                text = "已从 ${formatDurationMs(savedMs)} 继续播放",
                color = Color.White,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.Medium,
            )
            Surface(
                onClick = onRestartFromZero,
                shape = CircleShape,
                color = colors.accent,
            ) {
                Text(
                    text = "从头开始",
                    color = colors.primaryButtonFg,
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
            IconButton(onClick = onDismiss, modifier = Modifier.size(22.dp)) {
                Icon(Icons.Rounded.Close, contentDescription = "关闭提示", tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
            }
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SpeedSelectorBottomSheet(
    visible: Boolean,
    speeds: List<Float>,
    selectedIndex: Int,
    onSelectSpeed: (Int, Float) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("选择播放倍速", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(speeds) { idx, spd ->
                    val selected = idx == selectedIndex
                    val label = if (abs(spd - 1.0f) < 0.01f) "1.0x（正常原速）" else "${spd}x"
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (selected) colors.activeIndicator else colors.surfaceContainerLow)
                            .clickable { onSelectSpeed(idx, spd) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            text = label,
                            color = colors.textPrimary,
                            fontSize = 15.sp,
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
                        )
                        if (selected) {
                            Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EngineSelectorBottomSheet(
    visible: Boolean,
    activeEngineKind: ResolvedAndroidEngine,
    routeSummary: String?,
    onSelectEngine: (ResolvedAndroidEngine) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    val options = listOf(
        Triple(
            ResolvedAndroidEngine.NATIVE,
            "Media3 原生",
            "系统硬解省电秒开，支持原生画中画与 SurfaceView/TextureView",
        ),
        Triple(
            ResolvedAndroidEngine.ENHANCED,
            "MPV 全能",
            "libmpv 全格式内核，支持视频软解、完整 ASS 动漫特效与 PGS 蓝光字幕",
        ),
    )
    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("切换播放内核", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Text(
                "切换时自动保留当前进度且不中断媒体服务器正在播放状态",
                color = colors.textSecondary,
                fontSize = 12.5.sp,
            )
            if (routeSummary != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(colors.surfaceContainerLow)
                        .padding(horizontal = 16.dp, vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("播放方式", color = colors.textSecondary, fontSize = 13.5.sp)
                    Text(routeSummary, color = colors.textPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            options.forEach { (kind, title, desc) ->
                val selected = activeEngineKind == kind
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(if (selected) colors.activeIndicator else colors.surfaceContainerLow)
                        .clickable { onSelectEngine(kind) }
                        .padding(horizontal = 16.dp, vertical = 13.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            text = title,
                            color = colors.textPrimary,
                            fontSize = 15.sp,
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        )
                        Text(text = desc, color = colors.textSecondary, fontSize = 12.sp)
                    }
                    if (selected) {
                        Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@Composable
private fun NativeAudioPlayerStage(
    controller: PlayerRuntimeController,
    canMinimizeAudio: Boolean,
    audioShuffleEnabled: Boolean,
    audioRepeatMode: Int,
    onUpdateAudioShuffle: ((Boolean) -> Unit)?,
    onUpdateAudioRepeatMode: ((Int) -> Unit)?,
    onAudioSkipPrevious: (() -> Unit)?,
    onAudioSkipNext: (() -> Unit)?,
    onClose: () -> Unit,
    onMinimizeToMiniBar: (() -> Unit)?,
    onSwitchRequest: ((MediaPlaybackRequest) -> Unit)?,
) {
    val request = controller.request
    val session = controller.session
    val ui = controller.ui
    val cfg = LocalConfiguration.current
    val isLandscape = cfg.orientation == Configuration.ORIENTATION_LANDSCAPE || cfg.screenWidthDp > cfg.screenHeightDp
    val compactHeight = cfg.screenHeightDp < 480

    val displayRequest = remember(request, session.embeddedAudioMeta) {
        EmbeddedAudioMetadataFetcher.applyToRequest(request, session.embeddedAudioMeta)
    }
    val resolvedArtworkModel: Any? = displayRequest.artworkUrl?.takeIf { it.isNotBlank() }
        ?: displayRequest.artworkBytes?.takeIf { it.isNotEmpty() }
    val playerPalette = rememberArtworkPlayerPalette(displayRequest.artworkUrl, displayRequest.artworkBytes)

    val lrcLines = remember(displayRequest.lyricsLrc) { parseLrcLyrics(displayRequest.lyricsLrc) }
    val plainLyricsLines = remember(displayRequest.lyricsLrc, lrcLines) {
        if (lrcLines.isEmpty()) EmbeddedAudioMetadataFetcher.extractPlainLyricsLines(displayRequest.lyricsLrc) else emptyList()
    }
    val lrcListState = rememberLazyListState()
    val activeLrcIdx = remember(session.positionMs, lrcLines) {
        lrcLines.indexOfLast { it.timeMs <= session.positionMs }.coerceAtLeast(0)
    }
    LaunchedEffect(activeLrcIdx, lrcLines.size, ui.showLyricsView) {
        if (ui.showLyricsView && lrcLines.isNotEmpty()) {
            lrcListState.animateScrollToItem((activeLrcIdx - 2).coerceAtLeast(0))
        }
    }

    val effectiveShuffle = if (onUpdateAudioShuffle != null) audioShuffleEnabled else ui.localShuffle
    val effectiveRepeatMode = if (onUpdateAudioRepeatMode != null) audioRepeatMode else ui.localRepeatMode
    val defaultAudioSpeedIdx = controller.speeds.indexOf(1.0f).coerceAtLeast(0)
    val currentAudioSpeedLabel = "${controller.speeds.getOrElse(controller.speedIndex) { 1.0f }}x"
    val audioDockActions = buildList {
        add(
            ExpressiveDockAction(
                icon = Icons.Rounded.Lyrics,
                contentDescription = "同步歌词",
                active = ui.showLyricsView,
                onClick = { ui.showLyricsView = !ui.showLyricsView },
            ),
        )
        add(
            ExpressiveDockAction(
                icon = Icons.Rounded.Shuffle,
                contentDescription = "随机播放",
                active = effectiveShuffle,
                onClick = {
                    val nextVal = !effectiveShuffle
                    if (onUpdateAudioShuffle != null) onUpdateAudioShuffle(nextVal) else ui.localShuffle = nextVal
                    controller.exoPlayer?.shuffleModeEnabled = nextVal
                    ui.hudMessage = if (nextVal) "已开启随机播放" else "已关闭随机播放"
                },
            ),
        )
        add(
            ExpressiveDockAction(
                icon = if (effectiveRepeatMode == Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                contentDescription = "循环模式",
                active = effectiveRepeatMode != Player.REPEAT_MODE_OFF,
                onClick = {
                    val nextMode = when (effectiveRepeatMode) {
                        Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
                        Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
                        else -> Player.REPEAT_MODE_OFF
                    }
                    if (onUpdateAudioRepeatMode != null) onUpdateAudioRepeatMode(nextMode) else ui.localRepeatMode = nextMode
                    controller.exoPlayer?.repeatMode = if (nextMode == Player.REPEAT_MODE_ONE) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    ui.hudMessage = when (nextMode) {
                        Player.REPEAT_MODE_ALL -> "列表循环"
                        Player.REPEAT_MODE_ONE -> "单曲循环"
                        else -> "顺序播放"
                    }
                },
            ),
        )
        if (request.queue.size > 1) {
            add(
                ExpressiveDockAction(
                    icon = Icons.AutoMirrored.Rounded.QueueMusic,
                    contentDescription = "播放队列",
                    active = ui.showQueueSheet,
                    onClick = { ui.showQueueSheet = true },
                ),
            )
        }
        add(
            ExpressiveDockAction(
                icon = Icons.Rounded.Cast,
                contentDescription = "投屏与输出设备",
                active = ui.showCastSheet,
                onClick = { ui.showCastSheet = true },
            ),
        )
    }

    val onPreviousTrack = {
        if (controller.activeCurrentPositionMs() > 3_000L) {
            controller.activeSeekTo(0L)
            ui.hudMessage = "已回到本曲开头"
        } else if (onAudioSkipPrevious != null && request.queue.size > 1) {
            onAudioSkipPrevious()
        } else if (request.queue.size > 1 && onSwitchRequest != null) {
            val prevIdx = (request.queueIndex - 1 + request.queue.size) % request.queue.size
            onSwitchRequest(request.queue[prevIdx].copy(queue = request.queue, queueIndex = prevIdx))
        } else {
            controller.activeSeekTo(0L)
        }
    }
    val onNextTrack = {
        if (onAudioSkipNext != null && request.queue.size > 1) {
            onAudioSkipNext()
        } else if (request.queue.size > 1 && onSwitchRequest != null) {
            val nextIdx = (request.queueIndex + 1) % request.queue.size
            onSwitchRequest(request.queue[nextIdx].copy(queue = request.queue, queueIndex = nextIdx))
        } else {
            controller.activeSeekTo((controller.activeCurrentPositionMs() + 15_000L).coerceAtMost(session.durationMs))
            ui.hudMessage = "快进 15 秒"
        }
    }
    val onBackOrMinimize = {
        if (canMinimizeAudio) onMinimizeToMiniBar?.invoke() else onClose()
        Unit
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(playerPalette.canvas),
    ) {
        if (isLandscape) {
            AudioLandscapeBody(
                controller = controller,
                displayRequest = displayRequest,
                resolvedArtworkModel = resolvedArtworkModel,
                playerPalette = playerPalette,
                compactHeight = compactHeight,
                canMinimizeAudio = canMinimizeAudio,
                lrcLines = lrcLines,
                plainLyricsLines = plainLyricsLines,
                lrcListState = lrcListState,
                activeLrcIdx = activeLrcIdx,
                audioDockActions = audioDockActions,
                currentSpeedLabel = currentAudioSpeedLabel,
                speedActive = controller.speedIndex != defaultAudioSpeedIdx,
                onBackOrMinimize = onBackOrMinimize,
                onStopAndClose = onClose,
                onPreviousTrack = onPreviousTrack,
                onNextTrack = onNextTrack,
            )
        } else {
            AudioPortraitBody(
                controller = controller,
                displayRequest = displayRequest,
                resolvedArtworkModel = resolvedArtworkModel,
                playerPalette = playerPalette,
                canMinimizeAudio = canMinimizeAudio,
                lrcLines = lrcLines,
                plainLyricsLines = plainLyricsLines,
                lrcListState = lrcListState,
                activeLrcIdx = activeLrcIdx,
                audioDockActions = audioDockActions,
                currentSpeedLabel = currentAudioSpeedLabel,
                speedActive = controller.speedIndex != defaultAudioSpeedIdx,
                onBackOrMinimize = onBackOrMinimize,
                onStopAndClose = onClose,
                onPreviousTrack = onPreviousTrack,
                onNextTrack = onNextTrack,
            )
        }

        val topOverlayInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout)
            .only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)
        ResumeFromHistoryBanner(
            savedMs = session.resumeBannerPositionMs,
            onRestartFromZero = {
                controller.activeSeekTo(0L)
                controller.localHistoryStore.clearResumePosition(controller.instanceUrl, request.server, request.localResumeId)
                session.resumeBannerPositionMs = null
                ui.hudMessage = "已从头开始播放"
            },
            onDismiss = { session.resumeBannerPositionMs = null },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .windowInsetsPadding(topOverlayInsets)
                .padding(top = if (compactHeight) 50.dp else 64.dp),
        )

        ui.hudMessage?.let { msg ->
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .windowInsetsPadding(topOverlayInsets)
                    .padding(top = if (compactHeight) 48.dp else 66.dp)
                    .clip(CircleShape)
                    .background(playerPalette.dock.copy(alpha = 0.92f))
                    .padding(horizontal = 16.dp, vertical = 7.dp),
            ) {
                Text(msg, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }

    AudioQueueBottomSheet(
        visible = ui.showQueueSheet,
        request = request,
        onSelectTrack = { nextReq ->
            onSwitchRequest?.invoke(nextReq)
            ui.showQueueSheet = false
        },
        onDismiss = { ui.showQueueSheet = false },
    )
    SpeedSelectorBottomSheet(
        visible = ui.showSpeedSheet,
        speeds = controller.speeds,
        selectedIndex = controller.speedIndex,
        onSelectSpeed = { idx, spd ->
            controller.speedIndex = idx
            controller.activeSetSpeed(spd)
            ui.hudMessage = "倍速：${spd}x"
            ui.showSpeedSheet = false
        },
        onDismiss = { ui.showSpeedSheet = false },
    )
    CastOptionsBottomSheet(
        visible = ui.showCastSheet,
        controller = controller,
        onDismiss = { ui.showCastSheet = false },
    )
}

@Composable
private fun AudioTopBar(
    compact: Boolean,
    canMinimizeAudio: Boolean,
    showLyricsView: Boolean,
    hasQueue: Boolean,
    currentSpeedLabel: String,
    speedActive: Boolean,
    playerPalette: PlayerExpressivePalette,
    onBackOrMinimize: () -> Unit,
    onToggleLyrics: () -> Unit,
    onOpenQueue: () -> Unit,
    onOpenSpeed: () -> Unit,
    onStopAndClose: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    val btnSz = if (compact) 38.dp else 44.dp
    val iconSz = if (compact) 22.dp else 24.dp
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Surface(
            onClick = onBackOrMinimize,
            shape = CircleShape,
            color = playerPalette.dock,
            modifier = Modifier.size(btnSz),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = if (canMinimizeAudio) Icons.Rounded.KeyboardArrowDown else Icons.AutoMirrored.Rounded.ArrowBack,
                    contentDescription = if (canMinimizeAudio) "收起至迷你播放条" else "关闭播放器",
                    tint = Color.White,
                    modifier = Modifier.size(iconSz),
                )
            }
        }

        Text(
            text = "正在播放",
            color = Color.White.copy(alpha = 0.92f),
            fontSize = if (compact) 15.sp else 17.sp,
            fontWeight = FontWeight.Medium,
        )

        Box {
            Surface(
                onClick = { showMenu = true },
                shape = CircleShape,
                color = if (speedActive) playerPalette.accent else playerPalette.dock,
                modifier = Modifier.size(btnSz),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Rounded.MoreHoriz,
                        contentDescription = "更多选项",
                        tint = if (speedActive) playerPalette.onAccent else Color.White,
                        modifier = Modifier.size(iconSz),
                    )
                }
            }
            DropdownMenu(
                expanded = showMenu,
                onDismissRequest = { showMenu = false },
            ) {
                DropdownMenuItem(
                    text = { Text(if (showLyricsView) "返回封面视图" else "全屏歌词视图") },
                    leadingIcon = { Icon(Icons.Rounded.Lyrics, contentDescription = null) },
                    onClick = {
                        showMenu = false
                        onToggleLyrics()
                    },
                )
                if (hasQueue) {
                    DropdownMenuItem(
                        text = { Text("播放队列") },
                        leadingIcon = { Icon(Icons.AutoMirrored.Rounded.QueueMusic, contentDescription = null) },
                        onClick = {
                            showMenu = false
                            onOpenQueue()
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text("播放速度 ($currentSpeedLabel)") },
                    leadingIcon = { Icon(Icons.Rounded.Speed, contentDescription = null) },
                    onClick = {
                        showMenu = false
                        onOpenSpeed()
                    },
                )
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text("停止并关闭") },
                    leadingIcon = { Icon(Icons.Rounded.Close, contentDescription = null) },
                    onClick = {
                        showMenu = false
                        onStopAndClose()
                    },
                )
            }
        }
    }
}

@Composable
private fun AudioTransportRow(
    compact: Boolean,
    isPlaying: Boolean,
    hasMultiQueue: Boolean,
    playerPalette: PlayerExpressivePalette,
    onPrevious: () -> Unit,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
) {
    val sideBtnSz = if (compact) 54.dp else 72.dp
    val sideIconSz = if (compact) 24.dp else 28.dp
    val playW = if (compact) 72.dp else 88.dp
    val playH = if (compact) 60.dp else 78.dp
    val playIconSz = if (compact) 30.dp else 36.dp
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(if (compact) 14.dp else 16.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            onClick = onPrevious,
            shape = CircleShape,
            color = playerPalette.buttonBg,
            modifier = Modifier.size(sideBtnSz),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Rounded.SkipPrevious,
                    contentDescription = "上一首",
                    tint = Color.White,
                    modifier = Modifier.size(sideIconSz),
                )
            }
        }

        ExpressiveMorphingPlayButton(
            isPlaying = isPlaying,
            onClick = onTogglePlay,
            containerColor = playerPalette.accent,
            contentColor = playerPalette.onAccent,
            width = playW,
            height = playH,
            iconSize = playIconSz,
        )

        Surface(
            onClick = onNext,
            shape = CircleShape,
            color = playerPalette.buttonBg,
            modifier = Modifier.size(sideBtnSz),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = if (hasMultiQueue) Icons.Rounded.SkipNext else Icons.Rounded.Forward10,
                    contentDescription = "下一首",
                    tint = Color.White,
                    modifier = Modifier.size(sideIconSz),
                )
            }
        }
    }
}

@Composable
private fun AudioLandscapeBody(
    controller: PlayerRuntimeController,
    displayRequest: MediaPlaybackRequest,
    resolvedArtworkModel: Any?,
    playerPalette: PlayerExpressivePalette,
    compactHeight: Boolean,
    canMinimizeAudio: Boolean,
    lrcLines: List<LrcLine>,
    plainLyricsLines: List<String>,
    lrcListState: LazyListState,
    activeLrcIdx: Int,
    audioDockActions: List<ExpressiveDockAction>,
    currentSpeedLabel: String,
    speedActive: Boolean,
    onBackOrMinimize: () -> Unit,
    onStopAndClose: () -> Unit,
    onPreviousTrack: () -> Unit,
    onNextTrack: () -> Unit,
) {
    val ui = controller.ui
    val session = controller.session
    val progress = (session.positionMs.toFloat() / session.durationMs.toFloat()).coerceIn(0f, 1f)
    val displayPositionMs = if (ui.draggingProgress >= 0f) (ui.draggingProgress * session.durationMs).toLong() else session.positionMs
    val rightDurationLabel = if (ui.showRemainingTime && session.durationMs > 1_000L) {
        "-${formatDurationMs((session.durationMs - displayPositionMs).coerceAtLeast(0L))}"
    } else {
        formatDurationMs(session.durationMs)
    }

    Row(
        modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout))
            .padding(horizontal = 20.dp, vertical = if (compactHeight) 8.dp else 16.dp),
        horizontalArrangement = Arrangement.spacedBy(22.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .weight(0.44f)
                .fillMaxHeight(),
            contentAlignment = Alignment.Center,
        ) {
            val artSide = minOf(maxWidth * 0.90f, maxHeight * 0.82f)
            Box(
                modifier = Modifier
                    .size(artSide)
                    .shadow(
                        elevation = 16.dp,
                        shape = RoundedCornerShape(26.dp),
                        ambientColor = Color.Black.copy(alpha = 0.45f),
                        spotColor = Color.Black.copy(alpha = 0.45f),
                    )
                    .clip(RoundedCornerShape(26.dp))
                    .background(playerPalette.buttonBg),
                contentAlignment = Alignment.Center,
            ) {
                if (resolvedArtworkModel != null) {
                    AsyncImage(
                        model = resolvedArtworkModel,
                        contentDescription = displayRequest.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = playerPalette.accent, modifier = Modifier.size(72.dp))
                }
            }
        }

        Column(
            modifier = Modifier
                .weight(0.56f)
                .fillMaxHeight(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (compactHeight) 6.dp else 12.dp),
        ) {
            AudioTopBar(
                compact = compactHeight,
                canMinimizeAudio = canMinimizeAudio,
                showLyricsView = ui.showLyricsView,
                hasQueue = controller.request.queue.size > 1,
                currentSpeedLabel = currentSpeedLabel,
                speedActive = speedActive,
                playerPalette = playerPalette,
                onBackOrMinimize = onBackOrMinimize,
                onToggleLyrics = { ui.showLyricsView = !ui.showLyricsView },
                onOpenQueue = { ui.showQueueSheet = true },
                onOpenSpeed = { ui.showSpeedSheet = true },
                onStopAndClose = onStopAndClose,
            )

            AnimatedContent(
                targetState = ui.showLyricsView,
                transitionSpec = { fadeIn(tween(220)) togetherWith fadeOut(tween(160)) },
                modifier = Modifier.fillMaxWidth().weight(1f),
                label = "audioLandscapeStage",
            ) { lyricsMode ->
                if (!lyricsMode) {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = displayRequest.title,
                            color = Color.White,
                            fontSize = if (compactHeight) 20.sp else 24.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                        )
                        if (displayRequest.subtitle.isNotBlank()) {
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = displayRequest.subtitle,
                                color = Color.White.copy(alpha = 0.72f),
                                fontSize = if (compactHeight) 13.5.sp else 15.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = TextAlign.Center,
                            )
                        }
                        val previewLyric = lrcLines.getOrNull(activeLrcIdx)?.text?.takeIf { it.isNotBlank() }
                            ?: plainLyricsLines.firstOrNull()
                        if (!previewLyric.isNullOrBlank()) {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                text = previewLyric,
                                color = playerPalette.accent,
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.clickable { ui.showLyricsView = true },
                            )
                        }
                    }
                } else {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            text = listOfNotNull(displayRequest.title, displayRequest.subtitle.takeIf { it.isNotBlank() }).joinToString(" · "),
                            color = Color.White.copy(alpha = 0.88f),
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        AudioLyricsListContent(
                            lrcLines = lrcLines,
                            plainLyricsLines = plainLyricsLines,
                            lrcListState = lrcListState,
                            activeLrcIdx = activeLrcIdx,
                            compact = compactHeight,
                            isPortrait = false,
                            onSeekTo = { controller.activeSeekTo(it) },
                            modifier = Modifier.fillMaxWidth().weight(1f),
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(formatDurationMs(displayPositionMs), color = Color.White.copy(alpha = 0.78f), fontSize = 11.5.sp)
                ExpressiveWavySlider(
                    value = if (ui.draggingProgress >= 0f) ui.draggingProgress else progress,
                    onValueChange = { ui.draggingProgress = it },
                    onValueChangeFinished = {
                        if (ui.draggingProgress >= 0f) {
                            controller.activeSeekTo((ui.draggingProgress * session.durationMs).toLong())
                            ui.draggingProgress = -1f
                        }
                    },
                    isPlaying = controller.isPlaying,
                    activeColor = playerPalette.accent,
                    inactiveColor = Color.White.copy(alpha = 0.24f),
                    modifier = Modifier.weight(1f).height(28.dp),
                )
                Text(
                    text = rightDurationLabel,
                    color = Color.White.copy(alpha = 0.72f),
                    fontSize = 11.5.sp,
                    modifier = Modifier.clickable { ui.showRemainingTime = !ui.showRemainingTime },
                )
            }

            AudioTransportRow(
                compact = compactHeight,
                isPlaying = controller.isPlaying,
                hasMultiQueue = controller.request.queue.size > 1,
                playerPalette = playerPalette,
                onPrevious = onPreviousTrack,
                onTogglePlay = { if (controller.activeIsPlaying()) controller.activePause() else controller.activePlay() },
                onNext = onNextTrack,
            )

            ExpressiveGroupedActionDock(
                actions = audioDockActions,
                dockColor = playerPalette.dock,
                buttonColor = playerPalette.buttonBg.copy(alpha = 0.55f),
                activeButtonColor = playerPalette.accent,
                iconColor = Color.White.copy(alpha = 0.88f),
                activeIconColor = playerPalette.onAccent,
                modifier = Modifier.fillMaxWidth(0.90f),
            )
        }
    }
}

@Composable
private fun AudioPortraitBody(
    controller: PlayerRuntimeController,
    displayRequest: MediaPlaybackRequest,
    resolvedArtworkModel: Any?,
    playerPalette: PlayerExpressivePalette,
    canMinimizeAudio: Boolean,
    lrcLines: List<LrcLine>,
    plainLyricsLines: List<String>,
    lrcListState: LazyListState,
    activeLrcIdx: Int,
    audioDockActions: List<ExpressiveDockAction>,
    currentSpeedLabel: String,
    speedActive: Boolean,
    onBackOrMinimize: () -> Unit,
    onStopAndClose: () -> Unit,
    onPreviousTrack: () -> Unit,
    onNextTrack: () -> Unit,
) {
    val ui = controller.ui
    val session = controller.session
    val progress = (session.positionMs.toFloat() / session.durationMs.toFloat()).coerceIn(0f, 1f)
    val displayPositionMs = if (ui.draggingProgress >= 0f) (ui.draggingProgress * session.durationMs).toLong() else session.positionMs
    val rightDurationLabel = if (ui.showRemainingTime && session.durationMs > 1_000L) {
        "-${formatDurationMs((session.durationMs - displayPositionMs).coerceAtLeast(0L))}"
    } else {
        formatDurationMs(session.durationMs)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout))
            .padding(horizontal = 24.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        AudioTopBar(
            compact = false,
            canMinimizeAudio = canMinimizeAudio,
            showLyricsView = ui.showLyricsView,
            hasQueue = controller.request.queue.size > 1,
            currentSpeedLabel = currentSpeedLabel,
            speedActive = speedActive,
            playerPalette = playerPalette,
            onBackOrMinimize = onBackOrMinimize,
            onToggleLyrics = { ui.showLyricsView = !ui.showLyricsView },
            onOpenQueue = { ui.showQueueSheet = true },
            onOpenSpeed = { ui.showSpeedSheet = true },
            onStopAndClose = onStopAndClose,
        )

        Spacer(Modifier.height(22.dp))

        AnimatedContent(
            targetState = ui.showLyricsView,
            transitionSpec = { fadeIn(tween(240)) togetherWith fadeOut(tween(180)) },
            modifier = Modifier.fillMaxWidth().weight(1f),
            label = "audioPlayerStage",
        ) { lyricsMode ->
            if (!lyricsMode) {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.84f)
                            .aspectRatio(1f)
                            .shadow(
                                elevation = 18.dp,
                                shape = RoundedCornerShape(28.dp),
                                ambientColor = Color.Black.copy(alpha = 0.45f),
                                spotColor = Color.Black.copy(alpha = 0.45f),
                            )
                            .clip(RoundedCornerShape(28.dp))
                            .background(playerPalette.buttonBg),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (resolvedArtworkModel != null) {
                            AsyncImage(
                                model = resolvedArtworkModel,
                                contentDescription = displayRequest.title,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                        } else {
                            Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = playerPalette.accent, modifier = Modifier.size(84.dp))
                        }
                    }
                    Spacer(Modifier.height(26.dp))
                    Text(
                        text = displayRequest.title,
                        color = Color.White,
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                    if (displayRequest.subtitle.isNotBlank()) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = displayRequest.subtitle,
                            color = Color.White.copy(alpha = 0.72f),
                            fontSize = 15.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                        )
                    }
                    val previewLyric = lrcLines.getOrNull(activeLrcIdx)?.text?.takeIf { it.isNotBlank() }
                        ?: plainLyricsLines.firstOrNull()
                    if (!previewLyric.isNullOrBlank()) {
                        Spacer(Modifier.height(10.dp))
                        Text(
                            text = previewLyric,
                            color = playerPalette.accent,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.clickable { ui.showLyricsView = true },
                        )
                    }
                }
            } else {
                Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(54.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(playerPalette.buttonBg),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (resolvedArtworkModel != null) {
                                AsyncImage(
                                    model = resolvedArtworkModel,
                                    contentDescription = displayRequest.title,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            } else {
                                Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = playerPalette.accent)
                            }
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(displayRequest.title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (displayRequest.subtitle.isNotBlank()) {
                                Text(displayRequest.subtitle, color = Color.White.copy(alpha = 0.72f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                    AudioLyricsListContent(
                        lrcLines = lrcLines,
                        plainLyricsLines = plainLyricsLines,
                        lrcListState = lrcListState,
                        activeLrcIdx = activeLrcIdx,
                        compact = false,
                        isPortrait = true,
                        onSeekTo = { controller.activeSeekTo(it) },
                        modifier = Modifier.fillMaxWidth().weight(1f),
                    )
                }
            }
        }

        Spacer(Modifier.height(14.dp))

        ExpressiveWavySlider(
            value = if (ui.draggingProgress >= 0f) ui.draggingProgress else progress,
            onValueChange = { ui.draggingProgress = it },
            onValueChangeFinished = {
                if (ui.draggingProgress >= 0f) {
                    controller.activeSeekTo((ui.draggingProgress * session.durationMs).toLong())
                    ui.draggingProgress = -1f
                }
            },
            isPlaying = controller.isPlaying,
            activeColor = playerPalette.accent,
            inactiveColor = Color.White.copy(alpha = 0.24f),
        )
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(formatDurationMs(displayPositionMs), color = Color.White.copy(alpha = 0.72f), fontSize = 12.sp)
            Text(
                text = rightDurationLabel,
                color = Color.White.copy(alpha = 0.72f),
                fontSize = 12.sp,
                modifier = Modifier.clickable { ui.showRemainingTime = !ui.showRemainingTime },
            )
        }

        Spacer(Modifier.height(22.dp))

        AudioTransportRow(
            compact = false,
            isPlaying = controller.isPlaying,
            hasMultiQueue = controller.request.queue.size > 1,
            playerPalette = playerPalette,
            onPrevious = onPreviousTrack,
            onTogglePlay = { if (controller.activeIsPlaying()) controller.activePause() else controller.activePlay() },
            onNext = onNextTrack,
        )

        Spacer(Modifier.height(24.dp))

        ExpressiveGroupedActionDock(
            actions = audioDockActions,
            dockColor = playerPalette.dock,
            buttonColor = playerPalette.buttonBg.copy(alpha = 0.55f),
            activeButtonColor = playerPalette.accent,
            iconColor = Color.White.copy(alpha = 0.88f),
            activeIconColor = playerPalette.onAccent,
            modifier = Modifier.fillMaxWidth(0.84f),
        )

        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun AudioLyricsListContent(
    lrcLines: List<LrcLine>,
    plainLyricsLines: List<String>,
    lrcListState: LazyListState,
    activeLrcIdx: Int,
    compact: Boolean,
    isPortrait: Boolean,
    onSeekTo: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (lrcLines.isNotEmpty()) {
        LazyColumn(
            state = lrcListState,
            modifier = modifier,
            contentPadding = PaddingValues(vertical = if (isPortrait) 24.dp else 8.dp),
            verticalArrangement = Arrangement.spacedBy(if (isPortrait) 14.dp else 8.dp),
        ) {
            itemsIndexed(lrcLines) { idx, line ->
                val active = idx == activeLrcIdx
                val activeSz = if (isPortrait) 21.sp else (if (compact) 17.sp else 20.sp)
                val inactiveSz = if (isPortrait) 16.sp else 14.sp
                Text(
                    text = line.text,
                    color = if (active) Color.White else Color.White.copy(alpha = 0.43f),
                    fontSize = if (active) activeSz else inactiveSz,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                    lineHeight = if (isPortrait) 28.sp else (if (compact) 22.sp else 26.sp),
                    modifier = Modifier.clickable { onSeekTo(line.timeMs) },
                )
            }
        }
    } else if (plainLyricsLines.isNotEmpty()) {
        LazyColumn(
            modifier = modifier,
            contentPadding = PaddingValues(vertical = if (isPortrait) 16.dp else 8.dp),
            verticalArrangement = Arrangement.spacedBy(if (isPortrait) 12.dp else 8.dp),
        ) {
            item {
                Text(
                    text = "内嵌歌词（纯文本，无时间轴）",
                    color = Color.White.copy(alpha = 0.52f),
                    fontSize = 12.sp,
                )
            }
            itemsIndexed(plainLyricsLines) { _, line ->
                Text(
                    text = line,
                    color = Color.White.copy(alpha = 0.88f),
                    fontSize = if (isPortrait) 16.5.sp else (if (compact) 14.sp else 15.5.sp),
                    fontWeight = FontWeight.Medium,
                    lineHeight = if (isPortrait) 26.sp else (if (compact) 21.sp else 24.sp),
                )
            }
        }
    } else {
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            Text("当前曲目暂未附带歌词", color = Color.White.copy(alpha = 0.60f), fontSize = if (isPortrait) 15.sp else 14.sp)
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AudioQueueBottomSheet(
    visible: Boolean,
    request: MediaPlaybackRequest,
    onSelectTrack: (MediaPlaybackRequest) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val list = if (request.queue.isNotEmpty()) request.queue else listOf(request)
            Text(
                text = "播放队列 (${list.size})",
                color = colors.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(list) { idx, track ->
                    val current = idx == request.queueIndex
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (current) colors.activeIndicator else colors.surfaceContainerLow)
                            .clickable { onSelectTrack(track.copy(queue = list, queueIndex = idx)) }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = "${idx + 1}",
                            color = if (current) colors.accent else colors.textMuted,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(track.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (track.subtitle.isNotBlank()) {
                                Text(track.subtitle, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1)
                            }
                        }
                        if (current) {
                            Icon(Icons.Rounded.GraphicEq, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun NativeVideoPlayerStage(
    controller: PlayerRuntimeController,
    activity: Activity?,
    danmakuPrefs: DanmakuPreferencesStore,
) {
    val colors = LocalMoviePilotColors.current
    val hostView = LocalView.current
    val cfg = LocalConfiguration.current
    val isLandscape = cfg.orientation == Configuration.ORIENTATION_LANDSCAPE || cfg.screenWidthDp > cfg.screenHeightDp
    val compactVideoHeight = isLandscape && cfg.screenHeightDp < 460

    val request = controller.request
    val ui = controller.ui
    val session = controller.session
    val audioManager = remember { controller.context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager }
    var dragSeekDeltaMs by remember { mutableLongStateOf(0L) }

    val prefetchedSnapshot = session.prefetchedSubtitles.toMap()
    val subtitleChoices = remember(
        ui.tracksVersion,
        controller.exoPlayer,
        session.mpvEngineHolder,
        session.mpvSubtitleTracks,
        controller.isMpvActive,
        request.subtitles,
        prefetchedSnapshot,
        session.selectedExternalSubKey,
        session.loadingExternalSubKey,
        session.failedExternalSubKey,
        session.activeDisableSubtitles,
    ) {
        resolveSubtitleChoices(
            isMpvActive = controller.isMpvActive,
            exoPlayer = controller.exoPlayer,
            mpvEngine = session.mpvEngineHolder,
            mpvSubtitleTracks = session.mpvSubtitleTracks,
            externalSubtitles = request.subtitles,
            prefetchedSubtitles = prefetchedSnapshot,
            selectedExternalSubKey = session.selectedExternalSubKey,
            loadingExternalSubKey = session.loadingExternalSubKey,
            failedExternalSubKey = session.failedExternalSubKey,
            disableSubtitles = session.activeDisableSubtitles,
        )
    }
    val audioChoices = remember(ui.tracksVersion, controller.exoPlayer, session.mpvAudioTracks, controller.isMpvActive) {
        resolveAudioChoices(controller.isMpvActive, controller.exoPlayer, session.mpvAudioTracks)
    }

    val progress = (session.positionMs.toFloat() / session.durationMs.toFloat()).coerceIn(0f, 1f)
    val remainingMs = (session.durationMs - session.positionMs).coerceAtLeast(0L)
    val showUpNextCard = !ui.isInPipMode &&
        controller.hasNextVideoEpisode &&
        controller.nextVideoEpisode != null &&
        !session.upNextCancelled &&
        session.durationMs > 10_000L &&
        (progress >= 0.93f || remainingMs in 1L..3_500L)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(ui.isLocked, controller.speedIndex) {
                detectTapGestures(
                    onPress = {
                        try {
                            tryAwaitRelease()
                        } finally {
                            if (ui.isLongPressBoost) {
                                ui.isLongPressBoost = false
                                controller.activeSetSpeed(controller.currentSelectedSpeed)
                            }
                        }
                    },
                    onLongPress = {
                        if (!ui.isLocked) {
                            ui.isLongPressBoost = true
                            hostView.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            controller.activeSetSpeed(2.0f)
                        }
                    },
                    onTap = {
                        ui.controlsVisible = !ui.controlsVisible
                        if (ui.controlsVisible) ui.bumpInteraction()
                    },
                    onDoubleTap = { offset ->
                        if (!ui.isLocked) {
                            val w = size.width.toFloat().coerceAtLeast(1f)
                            when {
                                offset.x < w * 0.30f -> {
                                    controller.activeSeekTo((controller.activeCurrentPositionMs() - 10_000L).coerceAtLeast(0L))
                                    ui.hudMessage = "快退 10 秒"
                                }
                                offset.x > w * 0.70f -> {
                                    controller.activeSeekTo((controller.activeCurrentPositionMs() + 10_000L).coerceAtMost(session.durationMs))
                                    ui.hudMessage = "快进 10 秒"
                                }
                                else -> {
                                    if (controller.activeIsPlaying()) {
                                        controller.activePause()
                                        ui.hudMessage = "已暂停"
                                    } else {
                                        controller.activePlay()
                                        ui.hudMessage = "继续播放"
                                    }
                                }
                            }
                            ui.bumpInteraction()
                        }
                    },
                )
            }
            .then(
                if (!ui.isLocked) {
                    Modifier.pointerInput(Unit) {
                        var startX = 0f
                        var mode = 0
                        detectDragGestures(
                            onDragStart = { offset ->
                                startX = offset.x
                                mode = 0
                                dragSeekDeltaMs = 0L
                            },
                            onDragEnd = {
                                if (mode == 3 && dragSeekDeltaMs != 0L) {
                                    val target = (controller.activeCurrentPositionMs() + dragSeekDeltaMs).coerceIn(0L, session.durationMs)
                                    controller.activeSeekTo(target)
                                }
                                dragSeekDeltaMs = 0L
                                mode = 0
                                ui.bumpInteraction()
                            },
                            onDragCancel = {
                                dragSeekDeltaMs = 0L
                                mode = 0
                            },
                        ) { change, dragAmount ->
                            change.consume()
                            if (mode == 0) {
                                mode = if (abs(dragAmount.x) > abs(dragAmount.y) * 1.2f) {
                                    3
                                } else if (startX < size.width / 2f) {
                                    1
                                } else {
                                    2
                                }
                            }
                            when (mode) {
                                1 -> {
                                    if (activity != null) {
                                        val lp = activity.window.attributes
                                        val cur = if (lp.screenBrightness < 0f) 0.5f else lp.screenBrightness
                                        val next = (cur - dragAmount.y / size.height.coerceAtLeast(1) * 1.4f).coerceIn(0.05f, 1.0f)
                                        lp.screenBrightness = next
                                        activity.window.attributes = lp
                                        ui.hudMessage = "亮度 ${(next * 100).toInt()}%"
                                    }
                                }
                                2 -> {
                                    if (audioManager != null) {
                                        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                                        val curVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                                        val delta = if (dragAmount.y < -12f) 1 else if (dragAmount.y > 12f) -1 else 0
                                        if (delta != 0) {
                                            val next = (curVol + delta).coerceIn(0, maxVol)
                                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, next, 0)
                                            ui.hudMessage = "音量 ${(next * 100 / maxVol)}%"
                                        }
                                    }
                                }
                                3 -> {
                                    dragSeekDeltaMs += (dragAmount.x * 120f).toLong()
                                    val preview = (session.positionMs + dragSeekDeltaMs).coerceIn(0L, session.durationMs)
                                    val sign = if (dragSeekDeltaMs >= 0) "+" else "-"
                                    ui.hudMessage = "${formatDurationMs(preview)} (${sign}${abs(dragSeekDeltaMs) / 1000}s)"
                                }
                            }
                        }
                    }
                } else {
                    Modifier
                },
            ),
    ) {
        VideoSurfaceCanvas(controller = controller)

        if (request.danmakuEnabled && !ui.isInPipMode) {
            AndroidView(
                factory = { ctx ->
                    DanmakuOverlayView(ctx).apply {
                        applyPreferences(danmakuPrefs)
                        ui.danmakuOverlayRef = this
                    }
                },
                update = { view ->
                    if (ui.danmakuOverlayRef !== view) {
                        ui.danmakuOverlayRef = view
                    }
                    view.applyPreferences(danmakuPrefs)
                },
                modifier = Modifier.fillMaxSize(),
            )
        }

        val safePlayerInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout)

        if (!ui.isInPipMode) {
            if (ui.isLongPressBoost) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactVideoHeight) 48.dp else 62.dp)
                        .clip(CircleShape)
                        .background(colors.accent.copy(alpha = 0.92f))
                        .padding(horizontal = 18.dp, vertical = 7.dp),
                ) {
                    Text("2.0x 倍速播放中", color = colors.primaryButtonFg, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
            } else if (ui.hudMessage != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactVideoHeight) 52.dp else 66.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.72f))
                        .padding(horizontal = 16.dp, vertical = 7.dp),
                ) {
                    Text(ui.hudMessage.orEmpty(), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            } else if (session.loadingExternalSubKey != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactVideoHeight) 52.dp else 66.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.74f))
                        .padding(horizontal = 16.dp, vertical = 7.dp),
                ) {
                    Text("正在加载外挂字幕…", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            } else if (session.resumeBannerPositionMs != null) {
                ResumeFromHistoryBanner(
                    savedMs = session.resumeBannerPositionMs,
                    onRestartFromZero = {
                        controller.activeSeekTo(0L)
                        controller.localHistoryStore.clearResumePosition(controller.instanceUrl, request.server, request.localResumeId)
                        session.resumeBannerPositionMs = null
                        ui.hudMessage = "已从头开始播放"
                    },
                    onDismiss = { session.resumeBannerPositionMs = null },
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactVideoHeight) 52.dp else 66.dp),
                )
            }
        }

        if (!ui.isInPipMode && ui.controlsVisible) {
            Surface(
                onClick = {
                    val nextLocked = !ui.isLocked
                    ui.isLocked = nextLocked
                    ui.bumpInteraction()
                    if (activity != null) {
                        if (nextLocked) {
                            ui.preLockOrientation = activity.requestedOrientation
                            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
                            ui.hudMessage = "已锁定当前屏幕与方向"
                        } else {
                            activity.requestedOrientation = ui.preLockOrientation
                            ui.hudMessage = "已解除锁定"
                        }
                    }
                },
                shape = CircleShape,
                color = Color.Black.copy(alpha = 0.56f),
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.End))
                    .padding(end = 20.dp)
                    .size(48.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = if (ui.isLocked) Icons.Rounded.Lock else Icons.Rounded.LockOpen,
                        contentDescription = if (ui.isLocked) "解锁屏幕" else "锁定屏幕",
                        tint = if (ui.isLocked) colors.accent else Color.White,
                    )
                }
            }
        }

        if (!ui.isInPipMode && ui.controlsVisible && !ui.isLocked) {
            VideoTopBarOverlay(
                controller = controller,
                activity = activity,
                isLandscape = isLandscape,
                compactVideoHeight = compactVideoHeight,
                safePlayerInsets = safePlayerInsets,
                modifier = Modifier.align(Alignment.TopCenter),
            )

            VideoCenterTransportOverlay(
                controller = controller,
                compactVideoHeight = compactVideoHeight,
                modifier = Modifier.align(Alignment.Center),
            )

            VideoBottomControlsOverlay(
                controller = controller,
                danmakuPrefs = danmakuPrefs,
                subtitleChoices = subtitleChoices,
                compactVideoHeight = compactVideoHeight,
                safePlayerInsets = safePlayerInsets,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }

        VideoUpNextCardOverlay(
            visible = showUpNextCard,
            nextEpisode = controller.nextVideoEpisode,
            controlsVisible = ui.controlsVisible,
            compactVideoHeight = compactVideoHeight,
            safePlayerInsets = safePlayerInsets,
            onPlayNextNow = {
                session.autoAdvancedTriggered = true
                controller.switchVideoEpisode(request.queueIndex + 1)
            },
            onCancelUpNext = { session.upNextCancelled = true },
            modifier = Modifier.align(Alignment.BottomEnd),
        )
    }

    VideoQueueBottomSheet(
        visible = ui.showQueueSheet,
        request = request,
        onSelectEpisode = { idx ->
            ui.showQueueSheet = false
            if (idx != request.queueIndex) controller.switchVideoEpisode(idx)
        },
        onDismiss = { ui.showQueueSheet = false },
    )
    VideoSubtitleSelectorBottomSheet(
        visible = ui.showSubtitleSheet,
        choices = subtitleChoices,
        onSelectChoice = { controller.selectSubtitleChoice(it) },
        onDismiss = { ui.showSubtitleSheet = false },
    )
    VideoAudioTrackSelectorBottomSheet(
        visible = ui.showAudioTrackSheet,
        choices = audioChoices,
        onSelectChoice = { controller.selectAudioChoice(it) },
        onDismiss = { ui.showAudioTrackSheet = false },
    )
    SpeedSelectorBottomSheet(
        visible = ui.showSpeedSheet,
        speeds = controller.speeds,
        selectedIndex = controller.speedIndex,
        onSelectSpeed = { idx, spd ->
            controller.speedIndex = idx
            controller.activeSetSpeed(spd)
            ui.hudMessage = "倍速：${spd}x"
            ui.showSpeedSheet = false
        },
        onDismiss = { ui.showSpeedSheet = false },
    )
    val routeSummary = if (request.server.isNotBlank()) formatPlaybackRouteSummary(session.currentRouteKind) else null
    EngineSelectorBottomSheet(
        visible = ui.showEngineSheet && controller.ownsPlayer,
        activeEngineKind = session.activeEngineKind,
        routeSummary = routeSummary,
        onSelectEngine = { kind ->
            ui.showEngineSheet = false
            controller.switchVideoEngine(kind)
        },
        onDismiss = { ui.showEngineSheet = false },
    )
    CastOptionsBottomSheet(
        visible = ui.showCastSheet,
        controller = controller,
        onDismiss = { ui.showCastSheet = false },
    )
}

@OptIn(UnstableApi::class)
@Composable
private fun VideoSurfaceCanvas(controller: PlayerRuntimeController) {
    val ui = controller.ui
    val session = controller.session
    if (controller.isMpvActive) {
        val activeMpv = session.mpvEngineHolder
        if (activeMpv != null) {
            androidx.compose.runtime.key(activeMpv) {
                AndroidView(
                    factory = { ctx ->
                        SurfaceView(ctx).apply {
                            keepScreenOn = true
                            layoutParams = ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT,
                            )
                            holder.addCallback(activeMpv.createSurfaceCallback())
                            activeMpv.attachExistingSurfaceIfReady(holder)
                        }
                    },
                    update = { sv ->
                        activeMpv.attachExistingSurfaceIfReady(sv.holder)
                        activeMpv.setResizeMode(ui.resizeModeIndex)
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    } else {
        val useTexture = controller.playbackPrefs.surfaceType == "texture"
        AndroidView(
            factory = { ctx ->
                val layoutId = if (useTexture) R.layout.mp_player_view_texture else R.layout.mp_player_view_surface
                (LayoutInflater.from(ctx).inflate(layoutId, null) as PlayerView).apply {
                    useController = false
                    keepScreenOn = true
                    player = controller.exoPlayer
                    subtitleView?.setFractionalTextSize(
                        SubtitleView.DEFAULT_TEXT_SIZE_FRACTION * controller.playbackPrefs.subtitleScale,
                    )
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                }
            },
            update = { pv ->
                if (pv.player !== controller.exoPlayer) pv.player = controller.exoPlayer
                pv.resizeMode = VIDEO_RESIZE_MODES[ui.resizeModeIndex].first
                pv.subtitleView?.setFractionalTextSize(
                    SubtitleView.DEFAULT_TEXT_SIZE_FRACTION * controller.playbackPrefs.subtitleScale,
                )
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun VideoTopBarOverlay(
    controller: PlayerRuntimeController,
    activity: Activity?,
    isLandscape: Boolean,
    compactVideoHeight: Boolean,
    safePlayerInsets: WindowInsets,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val request = controller.request
    val ui = controller.ui
    val session = controller.session
    val btnSize = if (compactVideoHeight) 38.dp else 42.dp

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.72f), Color.Transparent)))
            .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .padding(horizontal = 16.dp, vertical = if (compactVideoHeight) 8.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Surface(
            onClick = { controller.closeVideoCleanly() },
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.45f),
            modifier = Modifier.size(btnSize),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = Color.White)
            }
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = request.title,
                color = Color.White,
                fontSize = if (compactVideoHeight) 14.5.sp else 16.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (request.subtitle.isNotBlank() && !compactVideoHeight) {
                Text(
                    text = request.subtitle,
                    color = Color.White.copy(alpha = 0.68f),
                    fontSize = 11.5.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Surface(
            onClick = {
                ui.bumpInteraction()
                if (activity != null) {
                    if (isLandscape) {
                        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        ui.hudMessage = "已切换竖屏"
                    } else {
                        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        ui.hudMessage = "已切换全屏横屏"
                    }
                }
            },
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.45f),
            modifier = Modifier.size(btnSize),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = if (isLandscape) Icons.Rounded.FullscreenExit else Icons.Rounded.Fullscreen,
                    contentDescription = if (isLandscape) "退出全屏横屏" else "全屏横屏播放",
                    tint = Color.White,
                )
            }
        }
        Surface(
            onClick = {
                ui.bumpInteraction()
                ui.showCastSheet = true
            },
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.45f),
            modifier = Modifier.size(btnSize),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Cast, contentDescription = "投屏", tint = Color.White)
            }
        }
        Surface(
            onClick = {
                if (activity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    runCatching {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(ui.videoAspectRatio)
                            .build()
                        activity.enterPictureInPictureMode(params)
                    }
                }
            },
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.45f),
            modifier = Modifier.size(btnSize),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.PictureInPictureAlt, contentDescription = "画中画", tint = Color.White)
            }
        }
        Box {
            Surface(
                onClick = {
                    ui.bumpInteraction()
                    ui.showTopMoreMenu = true
                },
                shape = CircleShape,
                color = Color.Black.copy(alpha = 0.45f),
                modifier = Modifier.size(btnSize),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Rounded.MoreVert,
                        contentDescription = "更多播放选项",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
            DropdownMenu(
                expanded = ui.showTopMoreMenu,
                onDismissRequest = { ui.showTopMoreMenu = false },
            ) {
                if (controller.ownsPlayer) {
                    DropdownMenuItem(
                        text = {
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text("切换播放内核", fontWeight = FontWeight.Medium)
                                Text(session.activeEngineKind.displayName, fontSize = 12.sp, color = colors.textSecondary)
                            }
                        },
                        leadingIcon = { Icon(Icons.Rounded.Memory, contentDescription = null) },
                        onClick = {
                            ui.showTopMoreMenu = false
                            ui.bumpInteraction()
                            ui.showEngineSheet = true
                        },
                    )
                }
                val routeSummary = if (request.server.isNotBlank()) formatPlaybackRouteSummary(session.currentRouteKind) else null
                if (routeSummary != null) {
                    DropdownMenuItem(
                        text = {
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text("播放方式", fontWeight = FontWeight.Medium)
                                Text(routeSummary, fontSize = 12.sp, color = colors.textSecondary)
                            }
                        },
                        leadingIcon = { Icon(Icons.Rounded.Tune, contentDescription = null) },
                        enabled = false,
                        onClick = {},
                    )
                }
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text("使用外部播放器打开") },
                    leadingIcon = { Icon(Icons.AutoMirrored.Rounded.OpenInNew, contentDescription = null) },
                    onClick = {
                        ui.showTopMoreMenu = false
                        ui.bumpInteraction()
                        controller.activePause()
                        val ok = ExternalPlayerLauncher.launchExternalPlayerChooser(
                            context = controller.context,
                            streamUrl = request.url,
                            title = request.title,
                            isAudio = false,
                            headers = request.headers,
                        )
                        if (!ok) ui.hudMessage = "未找到可用的外部播放器"
                    },
                )
            }
        }
    }
}

@Composable
private fun VideoCenterTransportOverlay(
    controller: PlayerRuntimeController,
    compactVideoHeight: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val request = controller.request
    val ui = controller.ui
    val session = controller.session

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (compactVideoHeight) 14.dp else 18.dp),
    ) {
        if (request.queue.size > 1) {
            Surface(
                onClick = {
                    if (controller.hasPrevVideoEpisode) controller.switchVideoEpisode(request.queueIndex - 1)
                },
                enabled = controller.hasPrevVideoEpisode,
                shape = CircleShape,
                color = Color.Black.copy(alpha = if (controller.hasPrevVideoEpisode) 0.48f else 0.22f),
                modifier = Modifier.size(if (compactVideoHeight) 42.dp else 46.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Rounded.SkipPrevious,
                        contentDescription = "上一集",
                        tint = Color.White.copy(alpha = if (controller.hasPrevVideoEpisode) 1f else 0.38f),
                        modifier = Modifier.size(if (compactVideoHeight) 22.dp else 24.dp),
                    )
                }
            }
        }

        Surface(
            onClick = {
                ui.bumpInteraction()
                controller.activeSeekTo((controller.activeCurrentPositionMs() - 10_000L).coerceAtLeast(0L))
                ui.hudMessage = "快退 10 秒"
            },
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.48f),
            modifier = Modifier.size(if (compactVideoHeight) 46.dp else 54.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Replay10, contentDescription = "快退10秒", tint = Color.White, modifier = Modifier.size(if (compactVideoHeight) 23.dp else 26.dp))
            }
        }

        ExpressiveMorphingPlayButton(
            isPlaying = controller.isPlaying,
            onClick = {
                ui.bumpInteraction()
                if (controller.activeIsPlaying()) controller.activePause() else controller.activePlay()
            },
            containerColor = colors.accent,
            contentColor = colors.primaryButtonFg,
            width = if (compactVideoHeight) 68.dp else 76.dp,
            height = if (compactVideoHeight) 58.dp else 68.dp,
            iconSize = if (compactVideoHeight) 30.dp else 34.dp,
        )

        Surface(
            onClick = {
                ui.bumpInteraction()
                controller.activeSeekTo((controller.activeCurrentPositionMs() + 10_000L).coerceAtMost(session.durationMs))
                ui.hudMessage = "快进 10 秒"
            },
            shape = CircleShape,
            color = Color.Black.copy(alpha = 0.48f),
            modifier = Modifier.size(if (compactVideoHeight) 46.dp else 54.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Forward10, contentDescription = "快进10秒", tint = Color.White, modifier = Modifier.size(if (compactVideoHeight) 23.dp else 26.dp))
            }
        }

        if (request.queue.size > 1) {
            Surface(
                onClick = {
                    if (controller.hasNextVideoEpisode) controller.switchVideoEpisode(request.queueIndex + 1)
                },
                enabled = controller.hasNextVideoEpisode,
                shape = CircleShape,
                color = Color.Black.copy(alpha = if (controller.hasNextVideoEpisode) 0.48f else 0.22f),
                modifier = Modifier.size(if (compactVideoHeight) 42.dp else 46.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Rounded.SkipNext,
                        contentDescription = "下一集",
                        tint = Color.White.copy(alpha = if (controller.hasNextVideoEpisode) 1f else 0.38f),
                        modifier = Modifier.size(if (compactVideoHeight) 22.dp else 24.dp),
                    )
                }
            }
        }
    }
}

/** 视频底部进度与紧凑图标操作栏，保留窄屏横向滚动和各项播放设置入口。 */
@Composable
private fun VideoBottomControlsOverlay(
    controller: PlayerRuntimeController,
    danmakuPrefs: DanmakuPreferencesStore,
    subtitleChoices: List<ResolvedTrackChoice>,
    compactVideoHeight: Boolean,
    safePlayerInsets: WindowInsets,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val request = controller.request
    val ui = controller.ui
    val session = controller.session
    val progress = (session.positionMs.toFloat() / session.durationMs.toFloat()).coerceIn(0f, 1f)
    val displayPositionMs = if (ui.draggingProgress >= 0f) (ui.draggingProgress * session.durationMs).toLong() else session.positionMs
    val rightDurationLabel = if (ui.showRemainingTime && session.durationMs > 1_000L) {
        "-${formatDurationMs((session.durationMs - displayPositionMs).coerceAtLeast(0L))}"
    } else {
        formatDurationMs(session.durationMs)
    }
    val defaultVideoSpeedIdx = controller.speeds.indexOf(1.0f).coerceAtLeast(0)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.80f))))
            .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal))
            .padding(horizontal = 20.dp, vertical = if (compactVideoHeight) 8.dp else 14.dp),
        verticalArrangement = Arrangement.spacedBy(if (compactVideoHeight) 6.dp else 10.dp),
    ) {
        if (compactVideoHeight) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(formatDurationMs(displayPositionMs), color = Color.White.copy(alpha = 0.86f), fontSize = 11.5.sp)
                ExpressiveWavySlider(
                    value = if (ui.draggingProgress >= 0f) ui.draggingProgress else progress,
                    onValueChange = {
                        ui.draggingProgress = it
                        ui.bumpInteraction()
                    },
                    onValueChangeFinished = {
                        if (ui.draggingProgress >= 0f) {
                            controller.activeSeekTo((ui.draggingProgress * session.durationMs).toLong())
                            ui.draggingProgress = -1f
                            ui.bumpInteraction()
                        }
                    },
                    isPlaying = controller.isPlaying,
                    activeColor = colors.accent,
                    inactiveColor = Color.White.copy(alpha = 0.28f),
                    modifier = Modifier.weight(1f).height(28.dp),
                )
                Text(
                    text = rightDurationLabel,
                    color = Color.White.copy(alpha = 0.68f),
                    fontSize = 11.5.sp,
                    modifier = Modifier.clickable {
                        ui.showRemainingTime = !ui.showRemainingTime
                        ui.bumpInteraction()
                    },
                )
            }
        } else {
            ExpressiveWavySlider(
                value = if (ui.draggingProgress >= 0f) ui.draggingProgress else progress,
                onValueChange = {
                    ui.draggingProgress = it
                    ui.bumpInteraction()
                },
                onValueChangeFinished = {
                    if (ui.draggingProgress >= 0f) {
                        controller.activeSeekTo((ui.draggingProgress * session.durationMs).toLong())
                        ui.draggingProgress = -1f
                        ui.bumpInteraction()
                    }
                },
                isPlaying = controller.isPlaying,
                activeColor = colors.accent,
                inactiveColor = Color.White.copy(alpha = 0.28f),
            )
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(formatDurationMs(displayPositionMs), color = Color.White.copy(alpha = 0.86f), fontSize = 12.sp)
                Text(
                    text = rightDurationLabel,
                    color = Color.White.copy(alpha = 0.68f),
                    fontSize = 12.sp,
                    modifier = Modifier.clickable {
                        ui.showRemainingTime = !ui.showRemainingTime
                        ui.bumpInteraction()
                    },
                )
            }
        }

        val dockActions = buildList {
            if (request.queue.size > 1) {
                add(
                    ExpressiveDockAction(
                        icon = Icons.AutoMirrored.Rounded.FormatListBulleted,
                        contentDescription = "选集",
                        active = ui.showQueueSheet,
                        onClick = {
                            ui.bumpInteraction()
                            ui.showQueueSheet = true
                        },
                    ),
                )
            }
            if (request.danmakuEnabled) {
                add(
                    ExpressiveDockAction(
                        icon = Icons.Rounded.Comment,
                        contentDescription = if (ui.danmakuVisible) "关闭弹幕" else "开启弹幕",
                        active = ui.danmakuVisible,
                        onClick = {
                            ui.bumpInteraction()
                            val nextEnabled = !danmakuPrefs.enabled
                            danmakuPrefs.updateEnabled(nextEnabled)
                            ui.danmakuVisible = nextEnabled
                            ui.danmakuPrefsVersion++
                            ui.hudMessage = if (nextEnabled) "已开启弹幕" else "已关闭弹幕"
                        },
                    ),
                )
                add(
                    ExpressiveDockAction(
                        icon = Icons.Rounded.Tune,
                        contentDescription = "弹幕设置",
                        active = ui.showDanmakuSettingsSheet || ui.showDanmakuMatchSheet,
                        onClick = {
                            ui.bumpInteraction()
                            ui.showDanmakuSettingsSheet = true
                        },
                    ),
                )
            }
            add(
                ExpressiveDockAction(
                    icon = Icons.Rounded.ClosedCaption,
                    contentDescription = "字幕",
                    active = subtitleChoices.any { (it.group != null || it.trackId != null) && it.selected },
                    onClick = {
                        ui.bumpInteraction()
                        ui.showSubtitleSheet = true
                    },
                ),
            )
            add(
                ExpressiveDockAction(
                    icon = Icons.Rounded.GraphicEq,
                    contentDescription = "音轨",
                    active = false,
                    onClick = {
                        ui.bumpInteraction()
                        ui.showAudioTrackSheet = true
                    },
                ),
            )
            add(
                ExpressiveDockAction(
                    icon = Icons.Rounded.AspectRatio,
                    contentDescription = "画面填充",
                    active = ui.resizeModeIndex != 0,
                    onClick = {
                        ui.bumpInteraction()
                        ui.resizeModeIndex = (ui.resizeModeIndex + 1) % VIDEO_RESIZE_MODES.size
                        session.mpvEngineHolder?.setResizeMode(ui.resizeModeIndex)
                        ui.hudMessage = "画面：${VIDEO_RESIZE_MODES[ui.resizeModeIndex].second}"
                    },
                ),
            )
            add(
                ExpressiveDockAction(
                    icon = Icons.Rounded.Speed,
                    contentDescription = "播放倍速",
                    active = controller.speedIndex != defaultVideoSpeedIdx,
                    onClick = {
                        ui.bumpInteraction()
                        ui.showSpeedSheet = true
                    },
                ),
            )
            if (controller.ownsPlayer) {
                add(
                    ExpressiveDockAction(
                        icon = Icons.Rounded.Memory,
                        contentDescription = "切换播放内核",
                        active = controller.isMpvActive,
                        onClick = {
                            ui.bumpInteraction()
                            ui.showEngineSheet = true
                        },
                    ),
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            dockActions.forEach { action ->
                IconButton(onClick = action.onClick, modifier = Modifier.size(48.dp)) {
                    Box(
                        modifier = Modifier.size(36.dp).clip(CircleShape)
                            .background(if (action.active) colors.accent else Color.Transparent),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = action.icon,
                            contentDescription = action.contentDescription,
                            tint = if (action.active) colors.primaryButtonFg else Color.White,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VideoUpNextCardOverlay(
    visible: Boolean,
    nextEpisode: MediaPlaybackRequest?,
    controlsVisible: Boolean,
    compactVideoHeight: Boolean,
    safePlayerInsets: WindowInsets,
    onPlayNextNow: () -> Unit,
    onCancelUpNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(tween(220)) + slideInVertically(tween(220)) { it / 2 },
        exit = fadeOut(tween(180)) + slideOutVertically(tween(180)) { it / 2 },
        modifier = modifier
            .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Bottom + WindowInsetsSides.End))
            .padding(end = 20.dp, bottom = if (controlsVisible) (if (compactVideoHeight) 110.dp else 148.dp) else 28.dp),
    ) {
        nextEpisode?.let { nextEp ->
            Surface(
                shape = RoundedCornerShape(20.dp),
                color = Color(0xE0161A26),
                shadowElevation = 12.dp,
                modifier = Modifier
                    .widthIn(max = 320.dp)
                    .border(0.9.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(20.dp)),
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 13.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = "即将播放下一集 · ${nextEp.title}",
                        color = Color.White,
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Surface(
                            onClick = onPlayNextNow,
                            shape = CircleShape,
                            color = colors.accent,
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = colors.primaryButtonFg, modifier = Modifier.size(16.dp))
                                Text("立即播放", color = colors.primaryButtonFg, fontSize = 12.5.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                        Surface(
                            onClick = onCancelUpNext,
                            shape = CircleShape,
                            color = Color.White.copy(alpha = 0.14f),
                        ) {
                            Text(
                                text = "取消",
                                color = Color.White.copy(alpha = 0.90f),
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VideoQueueBottomSheet(
    visible: Boolean,
    request: MediaPlaybackRequest,
    onSelectEpisode: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val list = request.queue.ifEmpty { listOf(request) }
            Text(
                text = "选集 (${list.size})",
                color = colors.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(list) { idx, ep ->
                    val current = idx == request.queueIndex
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (current) colors.activeIndicator else colors.surfaceContainerLow)
                            .clickable { onSelectEpisode(idx) }
                            .padding(horizontal = 14.dp, vertical = 13.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            text = "E%02d".format(idx + 1),
                            color = if (current) colors.accent else colors.textMuted,
                            fontSize = 12.5.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = ep.title,
                                color = colors.textPrimary,
                                fontSize = 14.5.sp,
                                fontWeight = if (current) FontWeight.Bold else FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (ep.subtitle.isNotBlank()) {
                                Text(ep.subtitle, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1)
                            }
                        }
                        if (current) {
                            Icon(Icons.Rounded.GraphicEq, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VideoSubtitleSelectorBottomSheet(
    visible: Boolean,
    choices: List<ResolvedTrackChoice>,
    onSelectChoice: (ResolvedTrackChoice) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("选择字幕轨道", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(choices) { _, choice ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (choice.selected) colors.activeIndicator else colors.surfaceContainerLow)
                            .clickable { onSelectChoice(choice) }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(
                            modifier = Modifier.weight(1f).padding(end = 10.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                text = choice.label,
                                color = colors.textPrimary,
                                fontSize = 15.sp,
                                fontWeight = if (choice.selected) FontWeight.Bold else FontWeight.Normal,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (choice.isLoading) {
                                Text(
                                    text = "正在加载外挂字幕…",
                                    color = colors.accent,
                                    fontSize = 12.sp,
                                )
                            } else if (choice.isFailed) {
                                Text(
                                    text = "加载失败 · 点击重试",
                                    color = Color(0xFFFF8A80),
                                    fontSize = 12.sp,
                                )
                            }
                        }
                        if (choice.selected) {
                            Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VideoAudioTrackSelectorBottomSheet(
    visible: Boolean,
    choices: List<ResolvedTrackChoice>,
    onSelectChoice: (ResolvedTrackChoice) -> Unit,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("选择音轨", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            if (choices.isEmpty()) {
                Text("当前流仅包含默认音轨", color = colors.textSecondary, fontSize = 14.sp)
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    itemsIndexed(choices) { _, choice ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (choice.selected) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable { onSelectChoice(choice) }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(choice.label, color = colors.textPrimary, fontSize = 15.sp, fontWeight = if (choice.selected) FontWeight.Bold else FontWeight.Normal)
                            if (choice.selected) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(14.dp))
        }
    }
}

@Composable
private fun VideoDanmakuHost(
    controller: PlayerRuntimeController,
    danmakuPrefs: DanmakuPreferencesStore,
) {
    val request = controller.request
    val ui = controller.ui
    val session = controller.session
    val repository = controller.repository
    val danmakuScope = rememberCoroutineScope()
    val danmakuState = remember(request.url, request.itemId) { VideoDanmakuSessionState() }

    suspend fun rebuildTimelineOnWorker(rawJson: String) {
        val options = danmakuPrefs.toFilterOptions(danmakuState.shiftMs.toLong())
        val prepared = withContext(Dispatchers.Default) {
            RustCoreBridge.prepareDanmakuTimeline(rawJson, options)
        }
        danmakuState.totalCount = prepared.items.size
        ui.danmakuOverlayRef?.let { overlay ->
            overlay.applyPreferences(danmakuPrefs)
            overlay.loadTimeline(prepared.items, controller.activeCurrentPositionMs())
            overlay.syncPlayback(
                positionMs = controller.activeCurrentPositionMs(),
                playing = controller.activeIsPlaying(),
                rate = controller.currentSelectedSpeed,
                inPip = ui.isInPipMode,
            )
        }
    }

    suspend fun loadEpisodeComments(epId: Long, forceRefresh: Boolean = false) {
        val repo = repository ?: return
        val res = withContext(Dispatchers.IO) {
            repo.fetchDanmakuComments(epId, forceRefresh = forceRefresh)
        }
        res.onSuccess { payload ->
            danmakuState.rawJson = payload.rawJson
            rebuildTimelineOnWorker(payload.rawJson)
        }
    }

    LaunchedEffect(request.itemId, request.server, request.danmakuEnabled, repository) {
        if (!request.danmakuEnabled || repository == null) {
            ui.danmakuOverlayRef?.stopAndClear()
            return@LaunchedEffect
        }
        val matchRes = withContext(Dispatchers.IO) {
            repository.matchDanmaku(
                itemId = request.itemId.ifBlank { null },
                server = request.server.ifBlank { null },
                title = request.title.ifBlank { null },
                seriesName = request.seriesName,
                seasonNumber = request.seasonNumber,
                episodeNumber = request.episodeNumber,
                year = request.year,
                tmdbId = request.tmdbId,
                fileName = request.fileName,
                fileSize = request.fileSize,
                durationMs = session.durationMs.takeIf { it > 1_000L },
            )
        }
        matchRes.onSuccess { resp ->
            danmakuState.fromBinding = resp.fromBinding
            danmakuState.candidates = resp.candidates
            danmakuState.shiftMs = resp.shiftMs
            val ep = resp.episode
            if (resp.matched && ep != null && ep.episodeId > 0L) {
                danmakuState.episodeId = ep.episodeId
                danmakuState.animeId = ep.animeId
                danmakuState.animeTitle = ep.animeTitle
                danmakuState.episodeTitle = ep.episodeTitle
                loadEpisodeComments(ep.episodeId, forceRefresh = false)
            } else {
                danmakuState.episodeId = null
                danmakuState.rawJson = null
                danmakuState.totalCount = 0
                ui.danmakuOverlayRef?.stopAndClear()
            }
        }
    }

    LaunchedEffect(ui.danmakuPrefsVersion, ui.danmakuVisible, ui.danmakuOverlayRef) {
        if (!request.danmakuEnabled) return@LaunchedEffect
        ui.danmakuOverlayRef?.applyPreferences(danmakuPrefs)
        val raw = danmakuState.rawJson
        if (!raw.isNullOrBlank()) {
            rebuildTimelineOnWorker(raw)
        }
    }

    if (ui.showDanmakuSettingsSheet && request.danmakuEnabled) {
        val matchedSummary = listOfNotNull(
            danmakuState.animeTitle?.takeIf { it.isNotBlank() },
            danmakuState.episodeTitle?.takeIf { it.isNotBlank() },
        ).joinToString(" · ")
        DanmakuSettingsBottomSheet(
            prefs = danmakuPrefs,
            matchedSummary = matchedSummary,
            totalCount = danmakuState.totalCount,
            fromBinding = danmakuState.fromBinding,
            shiftMs = danmakuState.shiftMs,
            onPreferencesChanged = {
                ui.danmakuVisible = danmakuPrefs.enabled
                ui.danmakuPrefsVersion++
            },
            onShiftChanged = { nextShift ->
                danmakuState.shiftMs = nextShift
                ui.danmakuPrefsVersion++
            },
            onSaveShiftToServer = {
                val epId = danmakuState.episodeId
                if (repository != null && epId != null && epId > 0L) {
                    repository.saveDanmakuBinding(
                        server = request.server.ifBlank { null },
                        itemId = request.itemId.ifBlank { null },
                        tmdbId = request.tmdbId,
                        seasonNumber = request.seasonNumber,
                        episodeNumber = request.episodeNumber,
                        episodeId = epId,
                        animeId = danmakuState.animeId,
                        animeTitle = danmakuState.animeTitle.orEmpty(),
                        episodeTitle = danmakuState.episodeTitle.orEmpty(),
                        shiftMs = danmakuState.shiftMs,
                    ).onSuccess {
                        danmakuState.fromBinding = true
                    }
                }
            },
            onOpenManualMatch = {
                ui.showDanmakuSettingsSheet = false
                ui.showDanmakuMatchSheet = true
            },
            onForceRefresh = {
                val epId = danmakuState.episodeId
                if (epId != null && epId > 0L) {
                    loadEpisodeComments(epId, forceRefresh = true)
                }
            },
            onDismiss = { ui.showDanmakuSettingsSheet = false },
        )
    }

    if (ui.showDanmakuMatchSheet && request.danmakuEnabled && repository != null) {
        val initialQuery = remember(request.seriesName, request.title, request.fileName) {
            RustCoreBridge.normalizeDanmakuTitle(
                request.seriesName?.takeIf { it.isNotBlank() }
                    ?: request.title.takeIf { it.isNotBlank() }
                    ?: request.fileName.orEmpty(),
            )
        }
        DanmakuManualMatchBottomSheet(
            repository = repository,
            initialKeyword = initialQuery,
            initialCandidates = danmakuState.candidates,
            fromBinding = danmakuState.fromBinding,
            onSelectEpisode = { cand ->
                danmakuState.episodeId = cand.episodeId
                danmakuState.animeId = cand.animeId
                danmakuState.animeTitle = cand.animeTitle
                danmakuState.episodeTitle = cand.episodeTitle
                danmakuState.shiftMs = cand.shiftMs
                repository.saveDanmakuBinding(
                    server = request.server.ifBlank { null },
                    itemId = request.itemId.ifBlank { null },
                    tmdbId = request.tmdbId,
                    seasonNumber = request.seasonNumber,
                    episodeNumber = request.episodeNumber,
                    episodeId = cand.episodeId,
                    animeId = cand.animeId,
                    animeTitle = cand.animeTitle,
                    episodeTitle = cand.episodeTitle,
                    shiftMs = cand.shiftMs,
                ).onSuccess {
                    danmakuState.fromBinding = true
                }
                danmakuScope.launch {
                    loadEpisodeComments(cand.episodeId, forceRefresh = false)
                }
                ui.hudMessage = "已切换弹幕：${cand.animeTitle}"
            },
            onUnbind = {
                repository.deleteDanmakuBinding(
                    server = request.server.ifBlank { null },
                    itemId = request.itemId.ifBlank { null },
                    tmdbId = request.tmdbId,
                    seasonNumber = request.seasonNumber,
                    episodeNumber = request.episodeNumber,
                ).onSuccess {
                    danmakuState.fromBinding = false
                    val reMatch = withContext(Dispatchers.IO) {
                        repository.matchDanmaku(
                            itemId = request.itemId.ifBlank { null },
                            server = request.server.ifBlank { null },
                            title = request.title.ifBlank { null },
                            seriesName = request.seriesName,
                            seasonNumber = request.seasonNumber,
                            episodeNumber = request.episodeNumber,
                            year = request.year,
                            tmdbId = request.tmdbId,
                            fileName = request.fileName,
                            fileSize = request.fileSize,
                            durationMs = session.durationMs.takeIf { it > 1_000L },
                        )
                    }
                    reMatch.onSuccess { resp ->
                        danmakuState.candidates = resp.candidates
                        danmakuState.shiftMs = resp.shiftMs
                        val ep = resp.episode
                        if (resp.matched && ep != null && ep.episodeId > 0L) {
                            danmakuState.episodeId = ep.episodeId
                            danmakuState.animeId = ep.animeId
                            danmakuState.animeTitle = ep.animeTitle
                            danmakuState.episodeTitle = ep.episodeTitle
                            loadEpisodeComments(ep.episodeId, forceRefresh = false)
                        } else {
                            danmakuState.episodeId = null
                            danmakuState.rawJson = null
                            danmakuState.totalCount = 0
                            ui.danmakuOverlayRef?.stopAndClear()
                        }
                    }
                    ui.hudMessage = "已解除手动绑定并恢复自动匹配"
                }
            },
            onDismiss = { ui.showDanmakuMatchSheet = false },
        )
    }
}

/**
 * 底部悬浮动态着色迷你播控条：
 * 随封面自动丝绒着色圆角卡片 + 左侧圆形专辑封面 + 柔和主色圆形播放/暂停键 + 同色系下一首圆钮。
 */
@Composable
fun FloatingMiniMusicBar(
    request: MediaPlaybackRequest,
    isPlaying: Boolean,
    onTogglePlay: () -> Unit,
    onNext: () -> Unit,
    onExpand: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val miniArtModel: Any? = request.artworkUrl?.takeIf { it.isNotBlank() }
        ?: request.artworkBytes?.takeIf { it.isNotEmpty() }
    val playerPalette = rememberArtworkPlayerPalette(request.artworkUrl, request.artworkBytes)
    val shape = RoundedCornerShape(22.dp)
    Surface(
        onClick = onExpand,
        shape = shape,
        color = playerPalette.canvas,
        shadowElevation = 10.dp,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(playerPalette.buttonBg),
                contentAlignment = Alignment.Center,
            ) {
                if (miniArtModel != null) {
                    AsyncImage(
                        model = miniArtModel,
                        contentDescription = request.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = playerPalette.accent)
                }
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    text = request.title,
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (request.subtitle.isNotBlank()) {
                    Text(
                        text = request.subtitle,
                        color = Color.White.copy(alpha = 0.74f),
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Surface(
                onClick = onTogglePlay,
                shape = CircleShape,
                color = playerPalette.accent,
                contentColor = playerPalette.onAccent,
                modifier = Modifier.size(40.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                        contentDescription = "播放或暂停",
                        tint = playerPalette.onAccent,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
            Surface(
                onClick = onNext,
                shape = CircleShape,
                color = playerPalette.buttonBg,
                contentColor = Color.White,
                modifier = Modifier.size(40.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Rounded.SkipNext,
                        contentDescription = "下一首",
                        tint = Color.White,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
            IconButton(onClick = onClose, modifier = Modifier.size(28.dp)) {
                Icon(
                    Icons.Rounded.Close,
                    contentDescription = "关闭",
                    tint = Color.White.copy(alpha = 0.65f),
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CastOptionsBottomSheet(
    visible: Boolean,
    controller: PlayerRuntimeController,
    onDismiss: () -> Unit,
) {
    if (!visible) return
    val colors = LocalMoviePilotColors.current
    val request = controller.request
    val ctx = controller.context
    val canExternalCast = request.url.startsWith("http://", ignoreCase = true) ||
        request.url.startsWith("https://", ignoreCase = true)

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = "投屏与输出设备",
                color = colors.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = "无线镜像投屏可保留全部字幕、弹幕与多音轨；外部投屏器支持 DLNA 与 Chromecast 直投。",
                color = colors.textSecondary,
                fontSize = 12.5.sp,
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(colors.surfaceContainerLow)
                    .clickable {
                        onDismiss()
                        val launched = runCatching {
                            ctx.startActivity(
                                Intent(Settings.ACTION_CAST_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                            true
                        }.getOrElse {
                            runCatching {
                                ctx.startActivity(
                                    Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                                true
                            }.getOrDefault(false)
                        }
                        if (!launched) {
                            controller.ui.hudMessage = "请从系统快捷控制面板开启无线投屏"
                        }
                    }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Rounded.Cast, contentDescription = null, tint = colors.accent, modifier = Modifier.size(22.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("系统无线投屏（Miracast）", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("兼容全部播放内核、外挂特效字幕与实时弹幕", color = colors.textSecondary, fontSize = 12.sp)
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(colors.surfaceContainerLow)
                    .clickable {
                        onDismiss()
                        val launched = runCatching {
                            val panelIntent = Intent("com.android.settings.panel.action.MEDIA_OUTPUT")
                                .putExtra("com.android.settings.panel.extra.PACKAGE_NAME", ctx.packageName)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            ctx.startActivity(panelIntent)
                            true
                        }.getOrElse {
                            runCatching {
                                ctx.startActivity(
                                    Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                                true
                            }.getOrDefault(false)
                        }
                        if (!launched) {
                            controller.ui.hudMessage = "请从系统音量面板切换输出设备"
                        }
                    }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Rounded.GraphicEq, contentDescription = null, tint = colors.accent, modifier = Modifier.size(22.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("切换音频输出设备", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("选择蓝牙耳机、无线音箱或系统媒体输出", color = colors.textSecondary, fontSize = 12.sp)
                }
            }

            if (canExternalCast) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(colors.surfaceContainerLow)
                        .clickable {
                            onDismiss()
                            controller.activePause()
                            val ok = ExternalPlayerLauncher.launchExternalPlayerChooser(
                                context = ctx,
                                streamUrl = request.url,
                                title = request.title,
                                isAudio = request.isAudio,
                                headers = request.headers,
                            )
                            if (!ok) controller.ui.hudMessage = "未找到可用的外部投屏或播放应用"
                        }
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.AutoMirrored.Rounded.OpenInNew, contentDescription = null, tint = colors.accent, modifier = Modifier.size(22.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("使用外部 DLNA / Chromecast 应用投屏", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text("调用 VLC、BubbleUPnP、Web Video Caster 等直投电视", color = colors.textSecondary, fontSize = 12.sp)
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}
