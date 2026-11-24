package com.moviepilot.media

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.drawable.BitmapDrawable
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.view.HapticFeedbackConstants
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Fullscreen
import androidx.compose.material.icons.rounded.FullscreenExit
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.Lyrics
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
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
import com.moviepilot.rustbridge.NativeSecretStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
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
    val originUrl: String = "",
    val allowSelfSignedTls: Boolean = false,
    val itemId: String = "",
    val server: String = "",
    val serverType: String = "",
    val mediaSourceId: String = "",
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

private fun subtitleMimeTypeForUrl(url: String): String {
    val lower = url.substringBefore('?').lowercase()
    return when {
        lower.endsWith(".vtt") -> MimeTypes.TEXT_VTT
        lower.endsWith(".ass") || lower.endsWith(".ssa") -> MimeTypes.TEXT_SSA
        else -> MimeTypes.APPLICATION_SUBRIP
    }
}

/**
 * 根据播放清单构建完整配置的 `ExoPlayer`：
 * - 使用 `OkHttpDataSource.Factory` 支持自签名 TLS 与跨源重定向自动剥离敏感凭据；
 * - 启用 Media3 音频焦点托管（来电自动闪避/暂停）与拔出耳机自动暂停（`HandleAudioBecomingNoisy`）；
 * - 注入系统锁屏/通知栏/蓝牙媒体元数据与外挂字幕；
 * - 音频固定以 `1.0x` 原速启动，视频应用用户默认倍速与清晰度上限。
 */
@OptIn(UnstableApi::class)
fun buildConfiguredExoPlayer(
    context: Context,
    request: MediaPlaybackRequest,
    resumePositionOverrideMs: Long? = null,
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
        val subConfigs = request.subtitles.map { sub ->
            val builder = MediaItem.SubtitleConfiguration.Builder(Uri.parse(sub.url))
                .setMimeType(subtitleMimeTypeForUrl(sub.url))
                .setLanguage(sub.language.ifBlank { "und" })
                .setLabel(sub.title.ifBlank { sub.language.ifBlank { "外挂字幕" } })
            if (sub.id.isNotBlank()) {
                builder.setId(sub.id)
            }
            builder.build()
        }
        itemBuilder.setSubtitleConfigurations(subConfigs)
    }

    val audioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(if (request.isAudio) C.AUDIO_CONTENT_TYPE_MUSIC else C.AUDIO_CONTENT_TYPE_MOVIE)
        .build()

    // 仅视频应用默认倍速偏好；音乐固定 1.0x 原速启动
    val initialSpeed = if (request.isAudio) 1.0f else prefs.defaultSpeed.coerceIn(0.5f, 2.0f)
    val effectiveStartMs = (resumePositionOverrideMs ?: request.resumePositionMs).coerceAtLeast(0L)

    return ExoPlayer.Builder(context, renderersFactory)
        .setMediaSourceFactory(mediaSourceFactory)
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
private fun rememberArtworkPlayerPalette(artworkUrl: String?): PlayerExpressivePalette {
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
    var extracted by remember(artworkUrl, fallback, store.albumArtDynamicColor) {
        mutableStateOf(fallback)
    }

    LaunchedEffect(artworkUrl, store.albumArtDynamicColor) {
        if (!store.albumArtDynamicColor || artworkUrl.isNullOrBlank()) {
            extracted = fallback
            return@LaunchedEffect
        }
        val derived = withContext(Dispatchers.IO) {
            runCatching {
                val loader = context.imageLoader
                val req = ImageRequest.Builder(context)
                    .data(artworkUrl)
                    .size(48)
                    .allowHardware(false)
                    .build()
                val res = loader.execute(req) as? SuccessResult ?: return@runCatching null
                val bmp = (res.drawable as? BitmapDrawable)?.bitmap ?: return@runCatching null
                derivePaletteFromBitmap(bmp)
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
)

/** 支持的全量倍速档位（与播放偏好页一致）。 */
val PLAYER_SUPPORTED_SPEEDS: List<Float> = listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f)

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
    onReportProgress: ((positionMs: Long, durationMs: Long, isPaused: Boolean, state: String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val hostView = LocalView.current
    val colors = LocalMoviePilotColors.current
    val playerPalette = rememberArtworkPlayerPalette(request.artworkUrl)
    val cfg = LocalConfiguration.current
    val isLandscape = cfg.orientation == Configuration.ORIENTATION_LANDSCAPE || cfg.screenWidthDp > cfg.screenHeightDp
    val compactHeight = cfg.screenHeightDp < 480
    val compactVideoHeight = isLandscape && cfg.screenHeightDp < 460
    val playbackPrefs = remember(context) { PlaybackPreferencesStore(context) }
    val localHistoryStore = remember(context) { LocalPlaybackHistoryStore(context) }

    val initialLocalSavedMs = remember(request.localResumeId, instanceUrl, request.server) {
        localHistoryStore.readResumePositionMs(instanceUrl, request.server, request.localResumeId)
    }
    val bestInitialResumeMs = remember(initialLocalSavedMs, request.resumePositionMs) {
        LocalPlaybackHistoryStore.resolveBestResumeMs(initialLocalSavedMs, request.resumePositionMs)
    }

    val ownsPlayer = sharedPlayer == null
    val exoPlayer = remember(request.url, sharedPlayer) {
        sharedPlayer ?: buildConfiguredExoPlayer(
            context = context,
            request = request,
            resumePositionOverrideMs = bestInitialResumeMs,
        )
    }

    val speeds = PLAYER_SUPPORTED_SPEEDS
    val resizeModes = listOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT to "自适应",
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM to "铺满裁剪",
        AspectRatioFrameLayout.RESIZE_MODE_FILL to "拉伸填充",
    )

    var isPlaying by remember(exoPlayer) { mutableStateOf(exoPlayer.isPlaying || exoPlayer.playWhenReady) }
    var positionMs by remember(request.url) { mutableLongStateOf(bestInitialResumeMs.coerceAtLeast(exoPlayer.currentPosition.coerceAtLeast(0L))) }
    var durationMs by remember(request.url) { mutableLongStateOf(exoPlayer.duration.coerceAtLeast(1L)) }
    var controlsVisible by remember { mutableStateOf(true) }
    var lastInteractionTick by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var isLocked by remember { mutableStateOf(false) }
    var showRemainingTime by remember { mutableStateOf(false) }
    var isLongPressBoost by remember { mutableStateOf(false) }

    var speedIndex by remember(request.isAudio) {
        val targetSpd = if (request.isAudio) 1.0f else playbackPrefs.defaultSpeed
        val defaultIdx = speeds.indexOfFirst { abs(it - targetSpd) < 0.05f }.takeIf { it >= 0 }
            ?: speeds.indexOf(1.0f).coerceAtLeast(0)
        mutableIntStateOf(defaultIdx)
    }
    var resizeModeIndex by remember {
        mutableIntStateOf(playbackPrefs.defaultResizeMode.coerceIn(0, resizeModes.lastIndex))
    }
    var localShuffle by remember { mutableStateOf(audioShuffleEnabled) }
    var localRepeatMode by remember { mutableIntStateOf(audioRepeatMode) }
    val effectiveShuffle = if (onUpdateAudioShuffle != null) audioShuffleEnabled else localShuffle
    val effectiveRepeatMode = if (onUpdateAudioRepeatMode != null) audioRepeatMode else localRepeatMode

    var showLyricsView by remember { mutableStateOf(false) }
    var showQueueSheet by remember { mutableStateOf(false) }
    var showSubtitleSheet by remember { mutableStateOf(false) }
    var showAudioTrackSheet by remember { mutableStateOf(false) }
    var showSpeedSheet by remember { mutableStateOf(false) }
    var hudMessage by remember { mutableStateOf<String?>(null) }
    var tracksVersion by remember { mutableIntStateOf(0) }

    // 记录当前会话用户选定的音轨/字幕偏好，用于跨剧集连播时无损继承
    var activePreferredAudioLang by remember(request.url) { mutableStateOf(request.preferredAudioLang) }
    var activePreferredSubtitleLang by remember(request.url) { mutableStateOf(request.preferredSubtitleLang) }
    var activeDisableSubtitles by remember(request.url) { mutableStateOf(request.disableSubtitles) }
    var appliedInitialTracks by remember(request.url) { mutableStateOf(false) }

    // 续播提示胶囊（> 30s 时展示 6 秒，支持一键从 00:00 重新开始）
    var resumeBannerPositionMs by remember(request.url) {
        mutableStateOf(bestInitialResumeMs.takeIf { it > LocalPlaybackHistoryStore.MIN_RESUME_POSITION_MS })
    }
    // 下一集自动连播倒计时与取消标记
    var upNextCancelled by remember(request.url) { mutableStateOf(false) }
    var autoAdvancedTriggered by remember(request.url) { mutableStateOf(false) }

    var videoAspectRatio by remember { mutableStateOf(Rational(16, 9)) }

    val activity = context as? Activity
    val initialOrientation = remember(activity) {
        activity?.requestedOrientation ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }
    var preLockOrientation by remember { mutableIntStateOf(initialOrientation) }
    var isInPipMode by remember(activity) {
        mutableStateOf(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity?.isInPictureInPictureMode == true else false)
    }

    val latestReportProgress by rememberUpdatedState(onReportProgress)
    val latestSwitchRequest by rememberUpdatedState(onSwitchRequest)
    val latestClose by rememberUpdatedState(onClose)

    fun bumpInteraction() {
        lastInteractionTick = System.currentTimeMillis()
    }

    fun buildCarryOverEpisodeRequest(target: MediaPlaybackRequest, nextIndex: Int): MediaPlaybackRequest =
        target.copy(
            queue = request.queue,
            queueIndex = nextIndex,
            preferredAudioLang = activePreferredAudioLang,
            preferredSubtitleLang = activePreferredSubtitleLang,
            disableSubtitles = activeDisableSubtitles,
        )

    val hasPrevVideoEpisode = !request.isAudio && request.queue.size > 1 && request.queueIndex > 0
    val hasNextVideoEpisode = !request.isAudio && request.queue.size > 1 && request.queueIndex + 1 < request.queue.size
    val nextVideoEpisode = if (hasNextVideoEpisode) request.queue.getOrNull(request.queueIndex + 1) else null

    fun closeVideoCleanly() {
        if (ownsPlayer && !request.isAudio) {
            val pos = exoPlayer.currentPosition.coerceAtLeast(0L)
            val dur = exoPlayer.duration.coerceAtLeast(0L)
            localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, pos, dur)
            latestReportProgress?.invoke(pos, dur, true, "stopped")
        }
        latestClose()
    }

    fun switchVideoEpisode(nextIdx: Int) {
        val target = request.queue.getOrNull(nextIdx) ?: return
        if (ownsPlayer && !request.isAudio) {
            val pos = exoPlayer.currentPosition.coerceAtLeast(0L)
            val dur = exoPlayer.duration.coerceAtLeast(0L)
            localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, pos, dur)
            latestReportProgress?.invoke(pos, dur, true, "stopped")
        }
        latestSwitchRequest?.invoke(buildCarryOverEpisodeRequest(target, nextIdx))
    }

    val canMinimizeAudio = request.isAudio && playbackPrefs.keepMusicMiniBar && onMinimizeToMiniBar != null

    // 锁屏状态下拦截系统返回手势并唤出解锁提示；未锁屏时按偏好最小化或关闭
    BackHandler(enabled = isLocked) {
        controlsVisible = true
        bumpInteraction()
        hudMessage = "屏幕已锁定，请点击右侧锁图标解锁"
    }
    BackHandler(enabled = !isLocked) {
        if (canMinimizeAudio) {
            onMinimizeToMiniBar?.invoke()
        } else if (request.isAudio) {
            onClose()
        } else {
            closeVideoCleanly()
        }
    }

    // 续播胶囊 6 秒后自动淡出
    LaunchedEffect(resumeBannerPositionMs) {
        if (resumeBannerPositionMs != null) {
            delay(6_000L)
            resumeBannerPositionMs = null
        }
    }

    val anySheetOpen = showQueueSheet || showSubtitleSheet || showAudioTrackSheet || showSpeedSheet
    var draggingProgress by remember { mutableFloatStateOf(-1f) }

    // 视频控制栏播放中 4.5 秒无操作自动隐藏
    LaunchedEffect(request.isAudio, controlsVisible, isPlaying, draggingProgress < 0f, anySheetOpen, isLongPressBoost, lastInteractionTick) {
        if (!request.isAudio && controlsVisible && isPlaying && draggingProgress < 0f && !anySheetOpen && !isLongPressBoost) {
            delay(4_500L)
            controlsVisible = false
        }
    }

    // 视频沉浸式系统状态栏/导航栏联动隐藏，退出时完整还原
    DisposableEffect(activity, hostView, request.isAudio, controlsVisible, isInPipMode) {
        val window = activity?.window
        val controller = if (window != null) WindowCompat.getInsetsController(window, hostView) else null
        if (!request.isAudio && controller != null) {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            if (!controlsVisible && !isInPipMode) {
                controller.hide(WindowInsetsCompat.Type.systemBars())
            } else {
                controller.show(WindowInsetsCompat.Type.systemBars())
            }
        }
        onDispose {
            controller?.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    // 保持屏幕常亮、监听画中画模式，并在退出播放页时还原窗口亮度、方向与 PiP 自动进入标志
    DisposableEffect(hostView, activity, request.isAudio) {
        val prevKeepScreenOn = hostView.keepScreenOn
        if (!request.isAudio) {
            hostView.keepScreenOn = true
        }
        val compActivity = activity as? ComponentActivity
        val pipListener = Consumer<PictureInPictureModeChangedInfo> { info ->
            isInPipMode = info.isInPictureInPictureMode
            if (info.isInPictureInPictureMode) {
                showSubtitleSheet = false
                showAudioTrackSheet = false
                showQueueSheet = false
                showSpeedSheet = false
            }
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

    // 动态同步 API 31+ setAutoEnterEnabled 与 API 29–30 onUserLeaveHint 自动画中画参数
    LaunchedEffect(activity, request.isAudio, isPlaying, playbackPrefs.autoPip, videoAspectRatio) {
        if (activity == null || request.isAudio) {
            PlaybackPipBridge.onUserLeaveHintCallback = null
            return@LaunchedEffect
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PlaybackPipBridge.onUserLeaveHintCallback = null
            runCatching {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(videoAspectRatio)
                    .setAutoEnterEnabled(isPlaying && playbackPrefs.autoPip)
                    .build()
                activity.setPictureInPictureParams(params)
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PlaybackPipBridge.onUserLeaveHintCallback = {
                if (exoPlayer.isPlaying && playbackPrefs.autoPip && !activity.isInPictureInPictureMode) {
                    runCatching {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(videoAspectRatio)
                            .build()
                        activity.enterPictureInPictureMode(params)
                    }
                }
            }
        }
    }

    // 视频独立播放器绑定系统 MediaSession 通知栏与蓝牙播控
    DisposableEffect(exoPlayer, ownsPlayer, request.isAudio, request.queueIndex, request.queue.size) {
        if (ownsPlayer && !request.isAudio) {
            PlaybackServiceBridge.attachActivePlayer(
                context = context,
                exoPlayer = exoPlayer,
                canSkipPrevious = { exoPlayer.currentPosition > 3_000L || hasPrevVideoEpisode },
                canSkipNext = { hasNextVideoEpisode },
                onSkipPrevious = {
                    if (exoPlayer.currentPosition > 3_000L || !hasPrevVideoEpisode) {
                        exoPlayer.seekTo(0L)
                    } else {
                        switchVideoEpisode(request.queueIndex - 1)
                    }
                },
                onSkipNext = {
                    if (hasNextVideoEpisode) {
                        switchVideoEpisode(request.queueIndex + 1)
                    }
                },
            )
        }
        onDispose {
            if (ownsPlayer) {
                PlaybackServiceBridge.detachIfMatching(exoPlayer)
            }
        }
    }

    val lrcLines = remember(request.lyricsLrc) { parseLrcLyrics(request.lyricsLrc) }
    val lrcListState = rememberLazyListState()

    // 初始音轨/中文字幕偏好应用辅助方法
    fun applyInitialTrackPreferencesIfReady(tracks: Tracks) {
        if (request.isAudio || appliedInitialTracks) return
        val hasMediaGroups = tracks.groups.any { it.type == C.TRACK_TYPE_VIDEO || it.type == C.TRACK_TYPE_AUDIO }
        if (!hasMediaGroups) return
        appliedInitialTracks = true

        var paramsBuilder = exoPlayer.trackSelectionParameters.buildUpon()
        var changed = false

        // 1. 匹配预选音轨（按序号或语言标签）
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

        // 2. 匹配预选字幕或自动启用中文字幕
        val textGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }
        if (request.disableSubtitles) {
            paramsBuilder = paramsBuilder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
            changed = true
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
            exoPlayer.trackSelectionParameters = paramsBuilder.build()
            tracksVersion++
        }
    }

    DisposableEffect(exoPlayer, ownsPlayer, request.url) {
        var didFallbackToProxy = false
        val listener = object : Player.Listener {
            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                val fallbackUrl = request.proxyFallbackUrl
                if (
                    ownsPlayer &&
                    !didFallbackToProxy &&
                    !fallbackUrl.isNullOrBlank() &&
                    fallbackUrl != request.url &&
                    exoPlayer.currentPosition <= 1_000L
                ) {
                    didFallbackToProxy = true
                    val curMeta = exoPlayer.currentMediaItem?.mediaMetadata ?: MediaMetadata.EMPTY
                    val curSubs = exoPlayer.currentMediaItem?.localConfiguration?.subtitleConfigurations.orEmpty()
                    val fallbackItem = MediaItem.Builder()
                        .setUri(Uri.parse(fallbackUrl))
                        .setMediaMetadata(curMeta)
                        .setSubtitleConfigurations(curSubs)
                        .build()
                    exoPlayer.setMediaItem(fallbackItem)
                    exoPlayer.prepare()
                    exoPlayer.playWhenReady = true
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                tracksVersion++
                applyInitialTrackPreferencesIfReady(tracks)
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    videoAspectRatio = PlaybackPipBridge.computeClampedPipAspectRatio(videoSize.width, videoSize.height)
                }
            }

            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                if (ownsPlayer) {
                    val pos = exoPlayer.currentPosition.coerceAtLeast(0L)
                    val dur = exoPlayer.duration.coerceAtLeast(0L)
                    localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, pos, dur)
                    latestReportProgress?.invoke(
                        pos,
                        dur,
                        !playing,
                        if (playing) "playing" else "paused",
                    )
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED && ownsPlayer && !request.isAudio) {
                    localHistoryStore.clearResumePosition(instanceUrl, request.server, request.localResumeId)
                    if (hasNextVideoEpisode && !upNextCancelled && !autoAdvancedTriggered) {
                        autoAdvancedTriggered = true
                        switchVideoEpisode(request.queueIndex + 1)
                    } else {
                        latestReportProgress?.invoke(
                            exoPlayer.duration.coerceAtLeast(0L),
                            exoPlayer.duration.coerceAtLeast(0L),
                            true,
                            "stopped",
                        )
                    }
                }
            }
        }
        exoPlayer.addListener(listener)
        if (exoPlayer.currentTracks.groups.isNotEmpty()) {
            applyInitialTrackPreferencesIfReady(exoPlayer.currentTracks)
        }
        onDispose {
            exoPlayer.removeListener(listener)
            // 仅在播放器归属当前页面时释放并记录本地断点；共享后台音乐播放器交由根壳协调器托管（绝不误发 stopped）
            if (ownsPlayer) {
                val pos = exoPlayer.currentPosition.coerceAtLeast(0L)
                val dur = exoPlayer.duration.coerceAtLeast(0L)
                localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, pos, dur)
                exoPlayer.release()
            }
        }
    }

    // 400ms 刷新界面进度，视频独立播放器每 15 秒（37 * 400ms ≈ 14.8s）同步一次服务端与本地续播进度
    LaunchedEffect(exoPlayer, ownsPlayer) {
        var tick = 0
        while (true) {
            isPlaying = exoPlayer.isPlaying
            positionMs = exoPlayer.currentPosition.coerceAtLeast(0L)
            durationMs = exoPlayer.duration.coerceAtLeast(1L)
            tick++
            if (ownsPlayer && tick % 37 == 0 && durationMs > 1L) {
                localHistoryStore.recordPlaybackProgress(instanceUrl, request.server, request.localResumeId, positionMs, durationMs)
                latestReportProgress?.invoke(positionMs, durationMs, !isPlaying, if (isPlaying) "playing" else "paused")
            }
            delay(400L)
        }
    }

    LaunchedEffect(hudMessage) {
        if (hudMessage != null) {
            delay(1400L)
            hudMessage = null
        }
    }

    val activeLrcIdx = remember(positionMs, lrcLines) {
        lrcLines.indexOfLast { it.timeMs <= positionMs }.coerceAtLeast(0)
    }
    LaunchedEffect(activeLrcIdx, lrcLines.size, showLyricsView) {
        if (request.isAudio && showLyricsView && lrcLines.isNotEmpty()) {
            lrcListState.animateScrollToItem((activeLrcIdx - 2).coerceAtLeast(0))
        }
    }

    val subtitleChoices = remember(tracksVersion, exoPlayer) {
        val list = mutableListOf<ResolvedTrackChoice>()
        val tracks = exoPlayer.currentTracks
        val isTextDisabled = exoPlayer.trackSelectionParameters.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT)
        list += ResolvedTrackChoice("关闭字幕", null, null, null, -1, isTextDisabled)
        tracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }.forEachIndexed { gIdx, grp ->
            for (i in 0 until grp.length) {
                val fmt = grp.getTrackFormat(i)
                val label = listOfNotNull(
                    fmt.label?.takeIf { it.isNotBlank() },
                    fmt.language?.takeIf { it.isNotBlank() && it != "und" },
                ).joinToString(" · ").ifBlank { "字幕轨道 ${gIdx + 1}" }
                list += ResolvedTrackChoice(
                    label = label,
                    language = fmt.language,
                    trackId = fmt.id,
                    group = grp,
                    trackIndex = i,
                    selected = !isTextDisabled && grp.isTrackSelected(i),
                )
            }
        }
        list
    }
    val audioChoices = remember(tracksVersion, exoPlayer) {
        val list = mutableListOf<ResolvedTrackChoice>()
        exoPlayer.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }.forEachIndexed { gIdx, grp ->
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
        list
    }

    val progress = (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
    val displayPositionMs = if (draggingProgress >= 0f) (draggingProgress * durationMs).toLong() else positionMs
    val rightDurationLabel = if (showRemainingTime && durationMs > 1_000L) {
        "-${formatDurationMs((durationMs - displayPositionMs).coerceAtLeast(0L))}"
    } else {
        formatDurationMs(durationMs)
    }

    @Composable
    fun ResumeFromHistoryBanner(modifier: Modifier = Modifier) {
        val savedMs = resumeBannerPositionMs ?: return
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
                    onClick = {
                        exoPlayer.seekTo(0L)
                        localHistoryStore.clearResumePosition(instanceUrl, request.server, request.localResumeId)
                        resumeBannerPositionMs = null
                        hudMessage = "已从头开始播放"
                    },
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
                IconButton(onClick = { resumeBannerPositionMs = null }, modifier = Modifier.size(22.dp)) {
                    Icon(Icons.Rounded.Close, contentDescription = "关闭提示", tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(14.dp))
                }
            }
        }
    }

    @Composable
    fun SpeedSelectorBottomSheet() {
        if (!showSpeedSheet) return
        NativeGlassSheet(onDismissRequest = { showSpeedSheet = false }) {
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
                        val selected = idx == speedIndex
                        val label = if (abs(spd - 1.0f) < 0.01f) "1.0x（正常原速）" else "${spd}x"
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (selected) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable {
                                    speedIndex = idx
                                    exoPlayer.playbackParameters = PlaybackParameters(spd)
                                    hudMessage = "倍速：${spd}x"
                                    showSpeedSheet = false
                                }
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

    if (request.isAudio) {
        // ═══════════════════════════════════════════════════════════════
        // Material 3 Expressive 音频全屏播放页（横屏自动切换左封面右播控双栏）
        // ═══════════════════════════════════════════════════════════════
        val defaultAudioSpeedIdx = speeds.indexOf(1.0f).coerceAtLeast(0)
        val audioDockActions = listOf(
            ExpressiveDockAction(
                icon = Icons.Rounded.Shuffle,
                contentDescription = "随机播放",
                active = effectiveShuffle,
                onClick = {
                    val nextVal = !effectiveShuffle
                    if (onUpdateAudioShuffle != null) {
                        onUpdateAudioShuffle(nextVal)
                    } else {
                        localShuffle = nextVal
                    }
                    exoPlayer.shuffleModeEnabled = nextVal
                    hudMessage = if (nextVal) "已开启随机播放" else "已关闭随机播放"
                },
            ),
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
                    if (onUpdateAudioRepeatMode != null) {
                        onUpdateAudioRepeatMode(nextMode)
                    } else {
                        localRepeatMode = nextMode
                    }
                    exoPlayer.repeatMode = if (nextMode == Player.REPEAT_MODE_ONE) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    hudMessage = when (nextMode) {
                        Player.REPEAT_MODE_ALL -> "列表循环"
                        Player.REPEAT_MODE_ONE -> "单曲循环"
                        else -> "顺序播放"
                    }
                },
            ),
            ExpressiveDockAction(
                icon = Icons.Rounded.Speed,
                contentDescription = "播放倍速",
                active = speedIndex != defaultAudioSpeedIdx,
                onClick = { showSpeedSheet = true },
            ),
        )

        @Composable
        fun AudioTopBar(compact: Boolean) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Surface(
                    onClick = {
                        if (canMinimizeAudio) onMinimizeToMiniBar?.invoke() else onClose()
                    },
                    shape = CircleShape,
                    color = playerPalette.dock,
                    modifier = Modifier.size(if (compact) 38.dp else 44.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = if (canMinimizeAudio) Icons.Rounded.KeyboardArrowDown else Icons.AutoMirrored.Rounded.ArrowBack,
                            contentDescription = if (canMinimizeAudio) "收起至迷你播放条" else "关闭播放器",
                            tint = Color.White,
                            modifier = Modifier.size(if (compact) 22.dp else 24.dp),
                        )
                    }
                }

                Text(
                    text = "正在播放",
                    color = Color.White.copy(alpha = 0.92f),
                    fontSize = if (compact) 15.sp else 17.sp,
                    fontWeight = FontWeight.Medium,
                )

                ExpressiveSplitIconPair(
                    firstIcon = Icons.Rounded.Lyrics,
                    firstDesc = "同步歌词",
                    firstActive = showLyricsView,
                    onFirstClick = { showLyricsView = !showLyricsView },
                    secondIcon = Icons.AutoMirrored.Rounded.QueueMusic,
                    secondDesc = "播放队列",
                    secondActive = showQueueSheet,
                    onSecondClick = { showQueueSheet = true },
                    containerColor = playerPalette.dock,
                    activeContainerColor = playerPalette.accent,
                    contentColor = Color.White.copy(alpha = 0.90f),
                    activeContentColor = playerPalette.onAccent,
                )
            }
        }

        @Composable
        fun AudioTransportRow(compact: Boolean) {
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
                    onClick = {
                        // 对齐 iOS 3 秒上一曲规则：超过 3 秒回到本曲开头，3 秒内切上一首
                        if (exoPlayer.currentPosition > 3_000L) {
                            exoPlayer.seekTo(0L)
                            hudMessage = "已回到本曲开头"
                        } else if (onAudioSkipPrevious != null && request.queue.size > 1) {
                            onAudioSkipPrevious()
                        } else if (request.queue.size > 1 && onSwitchRequest != null) {
                            val prevIdx = (request.queueIndex - 1 + request.queue.size) % request.queue.size
                            onSwitchRequest(request.queue[prevIdx].copy(queue = request.queue, queueIndex = prevIdx))
                        } else {
                            exoPlayer.seekTo(0L)
                        }
                    },
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
                    onClick = {
                        if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                    },
                    containerColor = playerPalette.accent,
                    contentColor = playerPalette.onAccent,
                    width = playW,
                    height = playH,
                    iconSize = playIconSz,
                )

                Surface(
                    onClick = {
                        if (onAudioSkipNext != null && request.queue.size > 1) {
                            onAudioSkipNext()
                        } else if (request.queue.size > 1 && onSwitchRequest != null) {
                            val nextIdx = (request.queueIndex + 1) % request.queue.size
                            onSwitchRequest(request.queue[nextIdx].copy(queue = request.queue, queueIndex = nextIdx))
                        } else {
                            exoPlayer.seekTo((exoPlayer.currentPosition + 15_000L).coerceAtMost(durationMs))
                            hudMessage = "快进 15 秒"
                        }
                    },
                    shape = CircleShape,
                    color = playerPalette.buttonBg,
                    modifier = Modifier.size(sideBtnSz),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = if (request.queue.size > 1) Icons.Rounded.SkipNext else Icons.Rounded.Forward10,
                            contentDescription = "下一首",
                            tint = Color.White,
                            modifier = Modifier.size(sideIconSz),
                        )
                    }
                }
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(playerPalette.canvas),
        ) {
            if (isLandscape) {
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
                            if (!request.artworkUrl.isNullOrBlank()) {
                                AsyncImage(
                                    model = request.artworkUrl,
                                    contentDescription = request.title,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            } else {
                                Icon(
                                    Icons.Rounded.MusicNote,
                                    contentDescription = null,
                                    tint = playerPalette.accent,
                                    modifier = Modifier.size(72.dp),
                                )
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
                        AudioTopBar(compact = compactHeight)

                        AnimatedContent(
                            targetState = showLyricsView,
                            transitionSpec = { fadeIn(tween(220)) togetherWith fadeOut(tween(160)) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .weight(1f),
                            label = "audioLandscapeStage",
                        ) { lyricsMode ->
                            if (!lyricsMode) {
                                Column(
                                    modifier = Modifier.fillMaxSize(),
                                    verticalArrangement = Arrangement.Center,
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                ) {
                                    Text(
                                        text = request.title,
                                        color = Color.White,
                                        fontSize = if (compactHeight) 20.sp else 24.sp,
                                        fontWeight = FontWeight.Bold,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                        textAlign = TextAlign.Center,
                                    )
                                    if (request.subtitle.isNotBlank()) {
                                        Spacer(Modifier.height(4.dp))
                                        Text(
                                            text = request.subtitle,
                                            color = Color.White.copy(alpha = 0.72f),
                                            fontSize = if (compactHeight) 13.5.sp else 15.sp,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            textAlign = TextAlign.Center,
                                        )
                                    }
                                    if (lrcLines.isNotEmpty()) {
                                        val curLine = lrcLines.getOrNull(activeLrcIdx)?.text.orEmpty()
                                        if (curLine.isNotBlank()) {
                                            Spacer(Modifier.height(8.dp))
                                            Text(
                                                text = curLine,
                                                color = playerPalette.accent,
                                                fontSize = 13.5.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                textAlign = TextAlign.Center,
                                                modifier = Modifier.clickable { showLyricsView = true },
                                            )
                                        }
                                    }
                                }
                            } else {
                                Column(
                                    modifier = Modifier.fillMaxSize(),
                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    Text(
                                        text = listOfNotNull(request.title, request.subtitle.takeIf { it.isNotBlank() }).joinToString(" · "),
                                        color = Color.White.copy(alpha = 0.88f),
                                        fontSize = 13.5.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    if (lrcLines.isNotEmpty()) {
                                        LazyColumn(
                                            state = lrcListState,
                                            modifier = Modifier.fillMaxWidth().weight(1f),
                                            contentPadding = PaddingValues(vertical = 8.dp),
                                            verticalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            itemsIndexed(lrcLines) { idx, line ->
                                                val active = idx == activeLrcIdx
                                                Text(
                                                    text = line.text,
                                                    color = if (active) Color.White else Color.White.copy(alpha = 0.44f),
                                                    fontSize = if (active) (if (compactHeight) 17.sp else 20.sp) else 14.sp,
                                                    fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                                                    lineHeight = if (compactHeight) 22.sp else 26.sp,
                                                    modifier = Modifier.clickable { exoPlayer.seekTo(line.timeMs) },
                                                )
                                            }
                                        }
                                    } else {
                                        Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                                            Text("当前曲目暂未附带同步歌词", color = Color.White.copy(alpha = 0.60f), fontSize = 14.sp)
                                        }
                                    }
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
                                value = if (draggingProgress >= 0f) draggingProgress else progress,
                                onValueChange = { draggingProgress = it },
                                onValueChangeFinished = {
                                    if (draggingProgress >= 0f) {
                                        exoPlayer.seekTo((draggingProgress * durationMs).toLong())
                                        draggingProgress = -1f
                                    }
                                },
                                isPlaying = isPlaying,
                                activeColor = playerPalette.accent,
                                inactiveColor = Color.White.copy(alpha = 0.24f),
                                modifier = Modifier.weight(1f).height(28.dp),
                            )
                            Text(
                                text = rightDurationLabel,
                                color = Color.White.copy(alpha = 0.72f),
                                fontSize = 11.5.sp,
                                modifier = Modifier.clickable { showRemainingTime = !showRemainingTime },
                            )
                        }

                        AudioTransportRow(compact = compactHeight)

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
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout))
                        .padding(horizontal = 24.dp, vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    AudioTopBar(compact = false)

                    Spacer(Modifier.height(22.dp))

                    AnimatedContent(
                        targetState = showLyricsView,
                        transitionSpec = { fadeIn(tween(240)) togetherWith fadeOut(tween(180)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
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
                                    if (!request.artworkUrl.isNullOrBlank()) {
                                        AsyncImage(
                                            model = request.artworkUrl,
                                            contentDescription = request.title,
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier.fillMaxSize(),
                                        )
                                    } else {
                                        Icon(
                                            Icons.Rounded.MusicNote,
                                            contentDescription = null,
                                            tint = playerPalette.accent,
                                            modifier = Modifier.size(84.dp),
                                        )
                                    }
                                }
                                Spacer(Modifier.height(26.dp))
                                Text(
                                    text = request.title,
                                    color = Color.White,
                                    fontSize = 24.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.Center,
                                )
                                if (request.subtitle.isNotBlank()) {
                                    Spacer(Modifier.height(6.dp))
                                    Text(
                                        text = request.subtitle,
                                        color = Color.White.copy(alpha = 0.72f),
                                        fontSize = 15.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        textAlign = TextAlign.Center,
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
                                        if (!request.artworkUrl.isNullOrBlank()) {
                                            AsyncImage(
                                                model = request.artworkUrl,
                                                contentDescription = request.title,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize(),
                                            )
                                        } else {
                                            Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = playerPalette.accent)
                                        }
                                    }
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(request.title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        if (request.subtitle.isNotBlank()) {
                                            Text(request.subtitle, color = Color.White.copy(alpha = 0.72f), fontSize = 13.sp, maxLines = 1)
                                        }
                                    }
                                }
                                if (lrcLines.isNotEmpty()) {
                                    LazyColumn(
                                        state = lrcListState,
                                        modifier = Modifier.fillMaxWidth().weight(1f),
                                        contentPadding = PaddingValues(vertical = 24.dp),
                                        verticalArrangement = Arrangement.spacedBy(14.dp),
                                        horizontalAlignment = Alignment.Start,
                                    ) {
                                        itemsIndexed(lrcLines) { idx, line ->
                                            val active = idx == activeLrcIdx
                                            Text(
                                                text = line.text,
                                                color = if (active) Color.White else Color.White.copy(alpha = 0.42f),
                                                fontSize = if (active) 21.sp else 16.sp,
                                                fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                                                lineHeight = 28.sp,
                                                modifier = Modifier.clickable { exoPlayer.seekTo(line.timeMs) },
                                            )
                                        }
                                    }
                                } else {
                                    Box(modifier = Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                                        Text("当前曲目暂未附带同步歌词", color = Color.White.copy(alpha = 0.60f), fontSize = 15.sp)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(Modifier.height(14.dp))

                    ExpressiveWavySlider(
                        value = if (draggingProgress >= 0f) draggingProgress else progress,
                        onValueChange = { draggingProgress = it },
                        onValueChangeFinished = {
                            if (draggingProgress >= 0f) {
                                exoPlayer.seekTo((draggingProgress * durationMs).toLong())
                                draggingProgress = -1f
                            }
                        },
                        isPlaying = isPlaying,
                        activeColor = playerPalette.accent,
                        inactiveColor = Color.White.copy(alpha = 0.24f),
                    )
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(formatDurationMs(displayPositionMs), color = Color.White.copy(alpha = 0.72f), fontSize = 12.sp)
                        Text(
                            text = rightDurationLabel,
                            color = Color.White.copy(alpha = 0.72f),
                            fontSize = 12.sp,
                            modifier = Modifier.clickable { showRemainingTime = !showRemainingTime },
                        )
                    }

                    Spacer(Modifier.height(22.dp))

                    AudioTransportRow(compact = false)

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

            ResumeFromHistoryBanner(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                    .padding(top = if (compactHeight) 50.dp else 64.dp),
            )

            hudMessage?.let { msg ->
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout).only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactHeight) 48.dp else 66.dp)
                        .clip(CircleShape)
                        .background(playerPalette.dock.copy(alpha = 0.92f))
                        .padding(horizontal = 16.dp, vertical = 7.dp),
                ) {
                    Text(msg, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        if (showQueueSheet) {
            NativeGlassSheet(onDismissRequest = { showQueueSheet = false }) {
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
                                    .clickable {
                                        onSwitchRequest?.invoke(track.copy(queue = list, queueIndex = idx))
                                        showQueueSheet = false
                                    }
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
        SpeedSelectorBottomSheet()
        return
    }

    // ═══════════════════════════════════════════════════════════════
    // Material 3 Expressive 全屏视频播放器
    // ═══════════════════════════════════════════════════════════════
    val audioManager = remember { context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager }
    var dragSeekDeltaMs by remember { mutableLongStateOf(0L) }
    val defaultVideoSpeedIdx = speeds.indexOf(1.0f).coerceAtLeast(0)

    val remainingMs = (durationMs - positionMs).coerceAtLeast(0L)
    val showUpNextCard = !isInPipMode &&
        hasNextVideoEpisode &&
        nextVideoEpisode != null &&
        !upNextCancelled &&
        durationMs > 10_000L &&
        (progress >= 0.93f || remainingMs in 1L..3_500L)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(isLocked, speedIndex) {
                detectTapGestures(
                    onPress = {
                        try {
                            tryAwaitRelease()
                        } finally {
                            if (isLongPressBoost) {
                                isLongPressBoost = false
                                exoPlayer.playbackParameters = PlaybackParameters(speeds[speedIndex])
                            }
                        }
                    },
                    onLongPress = {
                        if (!isLocked) {
                            isLongPressBoost = true
                            hostView.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            exoPlayer.playbackParameters = PlaybackParameters(2.0f)
                        }
                    },
                    onTap = {
                        controlsVisible = !controlsVisible
                        if (controlsVisible) bumpInteraction()
                    },
                    onDoubleTap = { offset ->
                        if (!isLocked) {
                            val w = size.width.toFloat().coerceAtLeast(1f)
                            when {
                                offset.x < w * 0.30f -> {
                                    val target = (exoPlayer.currentPosition - 10_000L).coerceAtLeast(0L)
                                    exoPlayer.seekTo(target)
                                    hudMessage = "快退 10 秒"
                                }
                                offset.x > w * 0.70f -> {
                                    val target = (exoPlayer.currentPosition + 10_000L).coerceAtMost(durationMs)
                                    exoPlayer.seekTo(target)
                                    hudMessage = "快进 10 秒"
                                }
                                else -> {
                                    if (exoPlayer.isPlaying) {
                                        exoPlayer.pause()
                                        hudMessage = "已暂停"
                                    } else {
                                        exoPlayer.play()
                                        hudMessage = "继续播放"
                                    }
                                }
                            }
                            bumpInteraction()
                        }
                    },
                )
            }
            .then(
                if (!isLocked) {
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
                                    val target = (exoPlayer.currentPosition + dragSeekDeltaMs).coerceIn(0L, durationMs)
                                    exoPlayer.seekTo(target)
                                }
                                dragSeekDeltaMs = 0L
                                mode = 0
                                bumpInteraction()
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
                                        hudMessage = "亮度 ${(next * 100).toInt()}%"
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
                                            hudMessage = "音量 ${(next * 100 / maxVol)}%"
                                        }
                                    }
                                }
                                3 -> {
                                    dragSeekDeltaMs += (dragAmount.x * 120f).toLong()
                                    val preview = (positionMs + dragSeekDeltaMs).coerceIn(0L, durationMs)
                                    val sign = if (dragSeekDeltaMs >= 0) "+" else "-"
                                    hudMessage = "${formatDurationMs(preview)} (${sign}${abs(dragSeekDeltaMs) / 1000}s)"
                                }
                            }
                        }
                    }
                } else {
                    Modifier
                },
            ),
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    keepScreenOn = true
                    player = exoPlayer
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                }
            },
            update = { pv ->
                if (pv.player !== exoPlayer) pv.player = exoPlayer
                pv.resizeMode = resizeModes[resizeModeIndex].first
            },
            modifier = Modifier.fillMaxSize(),
        )

        val safePlayerInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout)

        // 长按 2.0x 悬浮加速胶囊 / 续播提示胶囊 / 操作 HUD
        if (!isInPipMode) {
            if (isLongPressBoost) {
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
            } else if (hudMessage != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactVideoHeight) 52.dp else 66.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.72f))
                        .padding(horizontal = 16.dp, vertical = 7.dp),
                ) {
                    Text(hudMessage.orEmpty(), color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            } else if (resumeBannerPositionMs != null) {
                ResumeFromHistoryBanner(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                        .padding(top = if (compactVideoHeight) 52.dp else 66.dp),
                )
            }
        }

        // 屏幕锁定/解锁按钮：横竖屏双态均在点击屏幕后可见，确保竖屏锁定后随时可解锁
        if (!isInPipMode && controlsVisible) {
            Surface(
                onClick = {
                    val nextLocked = !isLocked
                    isLocked = nextLocked
                    bumpInteraction()
                    if (activity != null) {
                        if (nextLocked) {
                            preLockOrientation = activity.requestedOrientation
                            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
                            hudMessage = "已锁定当前屏幕与方向"
                        } else {
                            activity.requestedOrientation = preLockOrientation
                            hudMessage = "已解除锁定"
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
                        imageVector = if (isLocked) Icons.Rounded.Lock else Icons.Rounded.LockOpen,
                        contentDescription = if (isLocked) "解锁屏幕" else "锁定屏幕",
                        tint = if (isLocked) colors.accent else Color.White,
                    )
                }
            }
        }

        if (!isInPipMode && controlsVisible && !isLocked) {
            // 顶部栏：圆形返回 + 标题 + 外部播放器 + 横竖屏切换 + 画中画
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.72f), Color.Transparent)))
                    .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                    .padding(horizontal = 16.dp, vertical = if (compactVideoHeight) 8.dp else 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Surface(
                    onClick = { closeVideoCleanly() },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.size(if (compactVideoHeight) 38.dp else 42.dp),
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
                        bumpInteraction()
                        exoPlayer.pause()
                        val ok = ExternalPlayerLauncher.launchExternalPlayerChooser(
                            context = context,
                            streamUrl = request.url,
                            title = request.title,
                            isAudio = false,
                            headers = request.headers,
                        )
                        if (!ok) hudMessage = "未找到可用的外部播放器"
                    },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.size(if (compactVideoHeight) 38.dp else 42.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.OpenInNew,
                            contentDescription = "外部播放器",
                            tint = Color.White,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
                Surface(
                    onClick = {
                        bumpInteraction()
                        if (activity != null) {
                            if (isLandscape) {
                                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                                hudMessage = "已切换竖屏"
                            } else {
                                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                                hudMessage = "已切换全屏横屏"
                            }
                        }
                    },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.size(if (compactVideoHeight) 38.dp else 42.dp),
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
                        if (activity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            runCatching {
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(videoAspectRatio)
                                    .build()
                                activity.enterPictureInPictureMode(params)
                            }
                        }
                    },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.size(if (compactVideoHeight) 38.dp else 42.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.PictureInPictureAlt, contentDescription = "画中画", tint = Color.White)
                    }
                }
            }

            // 中央 Expressive 形变播放/暂停 + 上一集/快退/快进/下一集圆钮
            Row(
                modifier = Modifier.align(Alignment.Center),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(if (compactVideoHeight) 14.dp else 18.dp),
            ) {
                if (request.queue.size > 1) {
                    Surface(
                        onClick = {
                            if (hasPrevVideoEpisode) {
                                switchVideoEpisode(request.queueIndex - 1)
                            }
                        },
                        enabled = hasPrevVideoEpisode,
                        shape = CircleShape,
                        color = Color.Black.copy(alpha = if (hasPrevVideoEpisode) 0.48f else 0.22f),
                        modifier = Modifier.size(if (compactVideoHeight) 42.dp else 46.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                Icons.Rounded.SkipPrevious,
                                contentDescription = "上一集",
                                tint = Color.White.copy(alpha = if (hasPrevVideoEpisode) 1f else 0.38f),
                                modifier = Modifier.size(if (compactVideoHeight) 22.dp else 24.dp),
                            )
                        }
                    }
                }

                Surface(
                    onClick = {
                        bumpInteraction()
                        exoPlayer.seekTo((exoPlayer.currentPosition - 10_000L).coerceAtLeast(0L))
                        hudMessage = "快退 10 秒"
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
                    isPlaying = isPlaying,
                    onClick = {
                        bumpInteraction()
                        if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                    },
                    containerColor = colors.accent,
                    contentColor = colors.primaryButtonFg,
                    width = if (compactVideoHeight) 68.dp else 76.dp,
                    height = if (compactVideoHeight) 58.dp else 68.dp,
                    iconSize = if (compactVideoHeight) 30.dp else 34.dp,
                )

                Surface(
                    onClick = {
                        bumpInteraction()
                        exoPlayer.seekTo((exoPlayer.currentPosition + 10_000L).coerceAtMost(durationMs))
                        hudMessage = "快进 10 秒"
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
                            if (hasNextVideoEpisode) {
                                switchVideoEpisode(request.queueIndex + 1)
                            }
                        },
                        enabled = hasNextVideoEpisode,
                        shape = CircleShape,
                        color = Color.Black.copy(alpha = if (hasNextVideoEpisode) 0.48f else 0.22f),
                        modifier = Modifier.size(if (compactVideoHeight) 42.dp else 46.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                Icons.Rounded.SkipNext,
                                contentDescription = "下一集",
                                tint = Color.White.copy(alpha = if (hasNextVideoEpisode) 1f else 0.38f),
                                modifier = Modifier.size(if (compactVideoHeight) 22.dp else 24.dp),
                            )
                        }
                    }
                }
            }

            // 底部波浪进度条 + 连体播控胶囊坞
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
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
                            value = if (draggingProgress >= 0f) draggingProgress else progress,
                            onValueChange = {
                                draggingProgress = it
                                bumpInteraction()
                            },
                            onValueChangeFinished = {
                                if (draggingProgress >= 0f) {
                                    exoPlayer.seekTo((draggingProgress * durationMs).toLong())
                                    draggingProgress = -1f
                                    bumpInteraction()
                                }
                            },
                            isPlaying = isPlaying,
                            activeColor = colors.accent,
                            inactiveColor = Color.White.copy(alpha = 0.28f),
                            modifier = Modifier.weight(1f).height(28.dp),
                        )
                        Text(
                            text = rightDurationLabel,
                            color = Color.White.copy(alpha = 0.68f),
                            fontSize = 11.5.sp,
                            modifier = Modifier.clickable {
                                showRemainingTime = !showRemainingTime
                                bumpInteraction()
                            },
                        )
                    }
                } else {
                    ExpressiveWavySlider(
                        value = if (draggingProgress >= 0f) draggingProgress else progress,
                        onValueChange = {
                            draggingProgress = it
                            bumpInteraction()
                        },
                        onValueChangeFinished = {
                            if (draggingProgress >= 0f) {
                                exoPlayer.seekTo((draggingProgress * durationMs).toLong())
                                draggingProgress = -1f
                                bumpInteraction()
                            }
                        },
                        isPlaying = isPlaying,
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
                                showRemainingTime = !showRemainingTime
                                bumpInteraction()
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
                                active = showQueueSheet,
                                onClick = {
                                    bumpInteraction()
                                    showQueueSheet = true
                                },
                            ),
                        )
                    }
                    add(
                        ExpressiveDockAction(
                            icon = Icons.Rounded.ClosedCaption,
                            contentDescription = "字幕",
                            active = subtitleChoices.any { it.group != null && it.selected },
                            onClick = {
                                bumpInteraction()
                                showSubtitleSheet = true
                            },
                        ),
                    )
                    add(
                        ExpressiveDockAction(
                            icon = Icons.Rounded.GraphicEq,
                            contentDescription = "音轨",
                            active = false,
                            onClick = {
                                bumpInteraction()
                                showAudioTrackSheet = true
                            },
                        ),
                    )
                    add(
                        ExpressiveDockAction(
                            icon = Icons.Rounded.AspectRatio,
                            contentDescription = "画面填充",
                            active = resizeModeIndex != 0,
                            onClick = {
                                bumpInteraction()
                                resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
                                hudMessage = "画面：${resizeModes[resizeModeIndex].second}"
                            },
                        ),
                    )
                    add(
                        ExpressiveDockAction(
                            icon = Icons.Rounded.Speed,
                            contentDescription = "播放倍速",
                            active = speedIndex != defaultVideoSpeedIdx,
                            onClick = {
                                bumpInteraction()
                                showSpeedSheet = true
                            },
                        ),
                    )
                }

                ExpressiveGroupedActionDock(
                    actions = dockActions,
                    dockColor = Color(0xCC12151E),
                    buttonColor = Color.White.copy(alpha = 0.12f),
                    activeButtonColor = colors.accent,
                    iconColor = Color.White,
                    activeIconColor = colors.primaryButtonFg,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        // 片尾「即将播放下一集」磨砂玻璃卡片（>= 93% 或剩余 <= 3.5 秒自动浮现，支持立即连播与取消）
        AnimatedVisibility(
            visible = showUpNextCard,
            enter = fadeIn(tween(220)) + slideInVertically(tween(220)) { it / 2 },
            exit = fadeOut(tween(180)) + slideOutVertically(tween(180)) { it / 2 },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .windowInsetsPadding(safePlayerInsets.only(WindowInsetsSides.Bottom + WindowInsetsSides.End))
                .padding(end = 20.dp, bottom = if (controlsVisible) (if (compactVideoHeight) 110.dp else 148.dp) else 28.dp),
        ) {
            nextVideoEpisode?.let { nextEp ->
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
                                onClick = {
                                    autoAdvancedTriggered = true
                                    switchVideoEpisode(request.queueIndex + 1)
                                },
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
                                onClick = { upNextCancelled = true },
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

    // 视频选集面板
    if (showQueueSheet && !request.isAudio) {
        NativeGlassSheet(onDismissRequest = { showQueueSheet = false }) {
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
                                .clickable {
                                    showQueueSheet = false
                                    if (!current) {
                                        switchVideoEpisode(idx)
                                    }
                                }
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

    if (showSubtitleSheet) {
        NativeGlassSheet(onDismissRequest = { showSubtitleSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("选择字幕轨道", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    itemsIndexed(subtitleChoices) { _, choice ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (choice.selected) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable {
                                    val builder = exoPlayer.trackSelectionParameters.buildUpon()
                                    if (choice.group == null) {
                                        builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                                        activeDisableSubtitles = true
                                        activePreferredSubtitleLang = null
                                    } else {
                                        builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                            .setOverrideForType(TrackSelectionOverride(choice.group.mediaTrackGroup, choice.trackIndex))
                                        activeDisableSubtitles = false
                                        activePreferredSubtitleLang = choice.language ?: choice.label
                                    }
                                    exoPlayer.trackSelectionParameters = builder.build()
                                    tracksVersion++
                                    hudMessage = "字幕：${choice.label}"
                                    showSubtitleSheet = false
                                }
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
                Spacer(Modifier.height(14.dp))
            }
        }
    }

    if (showAudioTrackSheet) {
        NativeGlassSheet(onDismissRequest = { showAudioTrackSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("选择音轨", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                if (audioChoices.isEmpty()) {
                    Text("当前流仅包含默认音轨", color = colors.textSecondary, fontSize = 14.sp)
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        itemsIndexed(audioChoices) { _, choice ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(if (choice.selected) colors.activeIndicator else colors.surfaceContainerLow)
                                    .clickable {
                                        choice.group?.let { grp ->
                                            exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
                                                .buildUpon()
                                                .setOverrideForType(TrackSelectionOverride(grp.mediaTrackGroup, choice.trackIndex))
                                                .build()
                                            activePreferredAudioLang = choice.language ?: choice.label
                                            tracksVersion++
                                            hudMessage = "音轨：${choice.label}"
                                        }
                                        showAudioTrackSheet = false
                                    }
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

    SpeedSelectorBottomSheet()
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
    val playerPalette = rememberArtworkPlayerPalette(request.artworkUrl)
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
                if (!request.artworkUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = request.artworkUrl,
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
