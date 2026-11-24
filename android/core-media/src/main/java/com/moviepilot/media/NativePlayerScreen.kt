package com.moviepilot.media

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.drawable.BitmapDrawable
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.Forward10
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
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
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

/** 跨端统一音视频播放清单项（支持鉴权流、外挂字幕、LRC 同步歌词、进度续播与播放队列）。 */
data class MediaPlaybackRequest(
    val url: String,
    val title: String,
    val subtitle: String = "",
    val artworkUrl: String? = null,
    val isAudio: Boolean = false,
    val lyricsLrc: String? = null,
    val headers: Map<String, String> = emptyMap(),
    val itemId: String = "",
    val server: String = "",
    val resumePositionMs: Long = 0L,
    val subtitles: List<SubtitleTrackItem> = emptyList(),
    val queue: List<MediaPlaybackRequest> = emptyList(),
    val queueIndex: Int = 0,
)

/** 简易 LRC 同步歌词行。 */
data class LrcLine(val timeMs: Long, val text: String)

/** 解析 LRC 同步歌词文本。 */
fun parseLrcLyrics(raw: String?): List<LrcLine> {
    if (raw.isNullOrBlank()) return emptyList()
    val regex = Regex("""\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?](.*)""")
    return raw.lines().mapNotNull { line ->
        val m = regex.find(line.trim()) ?: return@mapNotNull null
        val min = m.groupValues[1].toLongOrNull() ?: 0L
        val sec = m.groupValues[2].toLongOrNull() ?: 0L
        val frac = m.groupValues[3].padEnd(3, '0').take(3).toLongOrNull() ?: 0L
        val txt = m.groupValues[4].trim()
        if (txt.isEmpty()) null else LrcLine(min * 60_000 + sec * 1000 + frac, txt)
    }.sortedBy { it.timeMs }
}

private fun formatDurationMs(ms: Long): String {
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

/** 根据请求创建带同源 Authorization/Cookie 头、解码偏好与外挂字幕配置的 ExoPlayer 实例。 */
@OptIn(UnstableApi::class)
fun buildConfiguredExoPlayer(context: Context, request: MediaPlaybackRequest): ExoPlayer {
    val prefs = PlaybackPreferencesStore(context)
    val httpFactory = DefaultHttpDataSource.Factory()
        .setAllowCrossProtocolRedirects(true)
        .setConnectTimeoutMs(15_000)
        .setReadTimeoutMs(30_000)
        .apply {
            if (request.headers.isNotEmpty()) {
                setDefaultRequestProperties(request.headers)
            }
        }
    val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
    val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
    val renderersFactory = DefaultRenderersFactory(context)
        .setEnableDecoderFallback(true)
        .setExtensionRendererMode(
            if (prefs.hwDecode) DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON
            else DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER,
        )
    val itemBuilder = MediaItem.Builder().setUri(Uri.parse(request.url))
    if (request.subtitles.isNotEmpty()) {
        val subConfigs = request.subtitles.map { sub ->
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(sub.url))
                .setMimeType(subtitleMimeTypeForUrl(sub.url))
                .setLanguage(sub.language.ifBlank { "und" })
                .setLabel(sub.title.ifBlank { sub.language.ifBlank { "外挂字幕" } })
                .build()
        }
        itemBuilder.setSubtitleConfigurations(subConfigs)
    }
    val defaultSpeedVal = prefs.defaultSpeed.coerceIn(0.5f, 3.0f)
    return ExoPlayer.Builder(context, renderersFactory)
        .setMediaSourceFactory(mediaSourceFactory)
        .build()
        .apply {
            setMediaItem(itemBuilder.build())
            playbackParameters = PlaybackParameters(defaultSpeedVal)
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
            if (request.resumePositionMs > 0L) {
                seekTo(request.resumePositionMs)
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
                // 优先挑选色彩鲜明、明暗适中的主色相
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
    val group: Tracks.Group?,
    val trackIndex: Int,
    val selected: Boolean,
)

/**
 * Material 3 Expressive 原生音视频播放器：
 * - **音频模式**：封面动态丝绒着色全屏画布、左上圆形下拉收起键 + 右上连体歌词/队列双钮、
 *   28dp 大圆角专辑主视觉、实时流动正弦波浪进度条（ExpressiveWavySlider）、形变方圆主播放键（播放呈 Squircle，暂停弹回正圆）、
 *   以及底部沉入式连体播控胶囊坞（随机 / 循环 / 倍速）；
 * - **视频模式**：全屏 Media3 ExoPlayer 硬件渲染、亮度/音量/进度手势与双击播控、右上画中画、横屏专属锁屏键，
 *   并同步采用波浪进度条、形变播控键与底部连体字幕/音轨/画面/倍速胶囊坞。
 */
@OptIn(UnstableApi::class)
@kotlin.OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeMediaPlayerOverlay(
    request: MediaPlaybackRequest,
    sharedPlayer: ExoPlayer? = null,
    onClose: () -> Unit,
    onMinimizeToMiniBar: (() -> Unit)? = null,
    onSwitchRequest: ((MediaPlaybackRequest) -> Unit)? = null,
    onReportProgress: ((positionMs: Long, durationMs: Long, isPaused: Boolean, state: String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val hostView = LocalView.current
    val colors = LocalMoviePilotColors.current
    val playerPalette = rememberArtworkPlayerPalette(request.artworkUrl)
    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val playbackPrefs = remember(context) { PlaybackPreferencesStore(context) }

    val ownsPlayer = sharedPlayer == null
    val exoPlayer = remember(request.url, sharedPlayer) {
        sharedPlayer ?: buildConfiguredExoPlayer(context, request)
    }

    val speeds = listOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    val resizeModes = listOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT to "自适应",
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM to "铺满裁剪",
        AspectRatioFrameLayout.RESIZE_MODE_FILL to "拉伸填充",
    )

    var isPlaying by remember { mutableStateOf(true) }
    var positionMs by remember { mutableLongStateOf(request.resumePositionMs) }
    var durationMs by remember { mutableLongStateOf(1L) }
    var controlsVisible by remember { mutableStateOf(true) }
    var isLocked by remember { mutableStateOf(false) }
    var speedIndex by remember {
        val defSpd = playbackPrefs.defaultSpeed
        mutableIntStateOf(speeds.indexOfFirst { abs(it - defSpd) < 0.05f }.takeIf { it >= 0 } ?: 1)
    }
    var resizeModeIndex by remember {
        mutableIntStateOf(playbackPrefs.defaultResizeMode.coerceIn(0, resizeModes.lastIndex))
    }
    var shuffleEnabled by remember { mutableStateOf(false) }
    var repeatMode by remember { mutableIntStateOf(Player.REPEAT_MODE_OFF) }
    var showLyricsView by remember { mutableStateOf(false) }
    var showQueueSheet by remember { mutableStateOf(false) }
    var showSubtitleSheet by remember { mutableStateOf(false) }
    var showAudioTrackSheet by remember { mutableStateOf(false) }
    var hudMessage by remember { mutableStateOf<String?>(null) }
    var tracksVersion by remember { mutableIntStateOf(0) }

    val activity = context as? Activity
    var isInPipMode by remember(activity) {
        mutableStateOf(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity?.isInPictureInPictureMode == true else false)
    }

    // 锁屏状态下拦截系统返回手势并给出解锁提示；未锁屏时返回退出/最小化播放器
    BackHandler(enabled = isLocked) {
        controlsVisible = true
        hudMessage = "屏幕已锁定，请先点击右侧锁图标解锁"
    }
    BackHandler(enabled = !isLocked) {
        if (request.isAudio && onMinimizeToMiniBar != null) onMinimizeToMiniBar() else onClose()
    }

    // 保持屏幕常亮、监听画中画模式，并在退出播放页时自动还原窗口亮度
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
            }
        }
        compActivity?.addOnPictureInPictureModeChangedListener(pipListener)
        onDispose {
            compActivity?.removeOnPictureInPictureModeChangedListener(pipListener)
            hostView.keepScreenOn = prevKeepScreenOn
            if (activity != null) {
                val lp = activity.window.attributes
                if (lp.screenBrightness >= 0f) {
                    lp.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    activity.window.attributes = lp
                }
            }
        }
    }

    val lrcLines = remember(request.lyricsLrc) { parseLrcLyrics(request.lyricsLrc) }
    val lrcListState = rememberLazyListState()

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onTracksChanged(tracks: Tracks) {
                tracksVersion++
            }
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                onReportProgress?.invoke(
                    exoPlayer.currentPosition.coerceAtLeast(0L),
                    exoPlayer.duration.coerceAtLeast(0L),
                    !playing,
                    if (playing) "playing" else "paused",
                )
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            onReportProgress?.invoke(
                exoPlayer.currentPosition.coerceAtLeast(0L),
                exoPlayer.duration.coerceAtLeast(0L),
                true,
                "stopped",
            )
            exoPlayer.removeListener(listener)
            if (ownsPlayer) {
                exoPlayer.release()
            }
        }
    }

    LaunchedEffect(exoPlayer) {
        var tick = 0
        while (true) {
            isPlaying = exoPlayer.isPlaying
            positionMs = exoPlayer.currentPosition.coerceAtLeast(0L)
            durationMs = exoPlayer.duration.coerceAtLeast(1L)
            tick++
            if (tick % 25 == 0 && durationMs > 1L) {
                onReportProgress?.invoke(positionMs, durationMs, !isPlaying, if (isPlaying) "playing" else "paused")
            }
            delay(400)
        }
    }

    LaunchedEffect(hudMessage) {
        if (hudMessage != null) {
            delay(1400)
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
        list += ResolvedTrackChoice("关闭字幕", null, -1, isTextDisabled)
        tracks.groups.filter { it.type == C.TRACK_TYPE_TEXT }.forEachIndexed { gIdx, grp ->
            for (i in 0 until grp.length) {
                val fmt = grp.getTrackFormat(i)
                val label = listOfNotNull(
                    fmt.label?.takeIf { it.isNotBlank() },
                    fmt.language?.takeIf { it.isNotBlank() && it != "und" },
                ).joinToString(" · ").ifBlank { "字幕轨道 ${gIdx + 1}" }
                list += ResolvedTrackChoice(label, grp, i, !isTextDisabled && grp.isTrackSelected(i))
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
                list += ResolvedTrackChoice(label, grp, i, grp.isTrackSelected(i))
            }
        }
        list
    }

    val progress = (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
    var draggingProgress by remember { mutableFloatStateOf(-1f) }
    val displayPositionMs = if (draggingProgress >= 0f) (draggingProgress * durationMs).toLong() else positionMs

    if (request.isAudio) {
        // ═══════════════════════════════════════════════════════════════
        // Material 3 Expressive 音频全屏播放页（波浪进度条、形变播控键与连体胶囊坞）
        // ═══════════════════════════════════════════════════════════════
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(playerPalette.canvas),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(horizontal = 24.dp, vertical = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // 1. 顶栏：左侧圆形下拉收起键 + 居中「正在播放」+ 右上角连体双圆钮（歌词 + 队列）
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Surface(
                        onClick = {
                            if (onMinimizeToMiniBar != null) onMinimizeToMiniBar() else onClose()
                        },
                        shape = CircleShape,
                        color = playerPalette.dock,
                        modifier = Modifier.size(44.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.KeyboardArrowDown,
                                contentDescription = "收起至迷你播放条",
                                tint = Color.White,
                                modifier = Modifier.size(26.dp),
                            )
                        }
                    }

                    Text(
                        text = "正在播放",
                        color = Color.White.copy(alpha = 0.92f),
                        fontSize = 17.sp,
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

                Spacer(Modifier.height(22.dp))

                // 2. 中央舞台：28dp 大圆角专辑主视觉 ↔ 交互式同步歌词视图
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

                // 3. 流动正弦波浪进度条 + 时间戳
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
                    Text(formatDurationMs(durationMs), color = Color.White.copy(alpha = 0.72f), fontSize = 12.sp)
                }

                Spacer(Modifier.height(22.dp))

                // 4. 三联主播控：大圆上一首 + 形变方圆暂停/播放主按钮 + 大圆下一首
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Surface(
                        onClick = {
                            if (request.queue.size > 1 && onSwitchRequest != null) {
                                val prevIdx = (request.queueIndex - 1 + request.queue.size) % request.queue.size
                                onSwitchRequest(request.queue[prevIdx].copy(queue = request.queue, queueIndex = prevIdx))
                            } else {
                                exoPlayer.seekTo((exoPlayer.currentPosition - 15_000L).coerceAtLeast(0L))
                                hudMessage = "快退 15 秒"
                            }
                        },
                        shape = CircleShape,
                        color = playerPalette.buttonBg,
                        modifier = Modifier.size(72.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = if (request.queue.size > 1) Icons.Rounded.SkipPrevious else Icons.Rounded.Replay10,
                                contentDescription = "上一首",
                                tint = Color.White,
                                modifier = Modifier.size(28.dp),
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
                        width = 88.dp,
                        height = 78.dp,
                        iconSize = 36.dp,
                    )

                    Surface(
                        onClick = {
                            if (request.queue.size > 1 && onSwitchRequest != null) {
                                val nextIdx = (request.queueIndex + 1) % request.queue.size
                                onSwitchRequest(request.queue[nextIdx].copy(queue = request.queue, queueIndex = nextIdx))
                            } else {
                                exoPlayer.seekTo((exoPlayer.currentPosition + 15_000L).coerceAtMost(durationMs))
                                hudMessage = "快进 15 秒"
                            }
                        },
                        shape = CircleShape,
                        color = playerPalette.buttonBg,
                        modifier = Modifier.size(72.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = if (request.queue.size > 1) Icons.Rounded.SkipNext else Icons.Rounded.Forward10,
                                contentDescription = "下一首",
                                tint = Color.White,
                                modifier = Modifier.size(28.dp),
                            )
                        }
                    }
                }

                Spacer(Modifier.height(24.dp))

                // 5. 底部沉入式连体胶囊坞（随机 / 循环 / 倍速）
                ExpressiveGroupedActionDock(
                    actions = listOf(
                        ExpressiveDockAction(
                            icon = Icons.Rounded.Shuffle,
                            contentDescription = "随机播放",
                            active = shuffleEnabled,
                            onClick = {
                                shuffleEnabled = !shuffleEnabled
                                exoPlayer.shuffleModeEnabled = shuffleEnabled
                                hudMessage = if (shuffleEnabled) "已开启随机播放" else "已关闭随机播放"
                            },
                        ),
                        ExpressiveDockAction(
                            icon = if (repeatMode == Player.REPEAT_MODE_ONE) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat,
                            contentDescription = "循环模式",
                            active = repeatMode != Player.REPEAT_MODE_OFF,
                            onClick = {
                                repeatMode = when (repeatMode) {
                                    Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
                                    Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
                                    else -> Player.REPEAT_MODE_OFF
                                }
                                exoPlayer.repeatMode = repeatMode
                                hudMessage = when (repeatMode) {
                                    Player.REPEAT_MODE_ALL -> "列表循环"
                                    Player.REPEAT_MODE_ONE -> "单曲循环"
                                    else -> "顺序播放"
                                }
                            },
                        ),
                        ExpressiveDockAction(
                            icon = Icons.Rounded.Speed,
                            contentDescription = "播放倍速",
                            active = speedIndex != 1,
                            onClick = {
                                speedIndex = (speedIndex + 1) % speeds.size
                                val spd = speeds[speedIndex]
                                exoPlayer.playbackParameters = PlaybackParameters(spd)
                                hudMessage = "倍速：${spd}x"
                            },
                        ),
                    ),
                    dockColor = playerPalette.dock,
                    buttonColor = playerPalette.buttonBg.copy(alpha = 0.55f),
                    activeButtonColor = playerPalette.accent,
                    iconColor = Color.White.copy(alpha = 0.88f),
                    activeIconColor = playerPalette.onAccent,
                    modifier = Modifier.fillMaxWidth(0.84f),
                )

                Spacer(Modifier.height(8.dp))
            }

            hudMessage?.let { msg ->
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .statusBarsPadding()
                        .padding(top = 66.dp)
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
                    Text(
                        text = "播放队列 (${request.queue.size.coerceAtLeast(1)})",
                        color = colors.textPrimary,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    val list = if (request.queue.isNotEmpty()) request.queue else listOf(request)
                    LazyColumn(
                        modifier = Modifier.height(320.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        itemsIndexed(list) { idx, track ->
                            val current = idx == request.queueIndex || track.url == request.url
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
        return
    }

    // ═══════════════════════════════════════════════════════════════
    // Material 3 Expressive 全屏视频播放器（保留完整手势/PiP/横屏锁屏 + 波浪条/形变键/胶囊坞）
    // ═══════════════════════════════════════════════════════════════
    val audioManager = remember { context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager }
    var dragSeekDeltaMs by remember { mutableLongStateOf(0L) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(isLocked) {
                detectTapGestures(
                    onTap = { controlsVisible = !controlsVisible },
                    onDoubleTap = {
                        if (!isLocked) {
                            if (exoPlayer.isPlaying) {
                                exoPlayer.pause()
                                hudMessage = "已暂停"
                            } else {
                                exoPlayer.play()
                                hudMessage = "继续播放"
                            }
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
                                    val activity = context as? Activity
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

        if (!isInPipMode) {
            hudMessage?.let { msg ->
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .statusBarsPadding()
                        .padding(top = 66.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.72f))
                        .padding(horizontal = 16.dp, vertical = 7.dp),
                ) {
                    Text(msg, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        // 横屏锁定/解锁纯图标按钮（居中靠右，严格仅横屏且非画中画显示）
        if (!isInPipMode && isLandscape && controlsVisible) {
            Surface(
                onClick = { isLocked = !isLocked },
                shape = CircleShape,
                color = Color.Black.copy(alpha = 0.56f),
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 20.dp)
                    .size(48.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = if (isLocked) Icons.Rounded.Lock else Icons.Rounded.LockOpen,
                        contentDescription = if (isLocked) "解锁屏幕" else "锁定屏幕",
                        tint = Color.White,
                    )
                }
            }
        }

        if (!isInPipMode && controlsVisible && !isLocked) {
            // 顶部栏：圆形返回 + 标题 + 右上角画中画圆钮
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.72f), Color.Transparent)))
                    .statusBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Surface(
                    onClick = onClose,
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.size(42.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = Color.White)
                    }
                }
                Text(
                    text = request.title,
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Surface(
                    onClick = {
                        val activity = context as? Activity
                        if (activity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            activity.enterPictureInPictureMode(params)
                        }
                    },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.45f),
                    modifier = Modifier.size(42.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.PictureInPictureAlt, contentDescription = "画中画", tint = Color.White)
                    }
                }
            }

            // 中央 Expressive 形变播放/暂停 + 快退/快进圆钮
            Row(
                modifier = Modifier.align(Alignment.Center),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Surface(
                    onClick = {
                        exoPlayer.seekTo((exoPlayer.currentPosition - 10_000L).coerceAtLeast(0L))
                        hudMessage = "-10s"
                    },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.48f),
                    modifier = Modifier.size(54.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.Replay10, contentDescription = "快退10秒", tint = Color.White, modifier = Modifier.size(26.dp))
                    }
                }

                ExpressiveMorphingPlayButton(
                    isPlaying = isPlaying,
                    onClick = {
                        if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                    },
                    containerColor = colors.accent,
                    contentColor = colors.primaryButtonFg,
                    width = 76.dp,
                    height = 68.dp,
                    iconSize = 34.dp,
                )

                Surface(
                    onClick = {
                        exoPlayer.seekTo((exoPlayer.currentPosition + 10_000L).coerceAtMost(durationMs))
                        hudMessage = "+10s"
                    },
                    shape = CircleShape,
                    color = Color.Black.copy(alpha = 0.48f),
                    modifier = Modifier.size(54.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.Forward10, contentDescription = "快进10秒", tint = Color.White, modifier = Modifier.size(26.dp))
                    }
                }
            }

            // 底部波浪进度条 + 连体播控胶囊坞（字幕 / 音轨 / 填充 / 倍速）
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.80f))))
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
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
                    activeColor = colors.accent,
                    inactiveColor = Color.White.copy(alpha = 0.28f),
                )
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(formatDurationMs(displayPositionMs), color = Color.White.copy(alpha = 0.86f), fontSize = 12.sp)
                    Text(formatDurationMs(durationMs), color = Color.White.copy(alpha = 0.68f), fontSize = 12.sp)
                }
                ExpressiveGroupedActionDock(
                    actions = listOf(
                        ExpressiveDockAction(
                            icon = Icons.Rounded.ClosedCaption,
                            contentDescription = "字幕",
                            active = subtitleChoices.any { it.group != null && it.selected },
                            onClick = { showSubtitleSheet = true },
                        ),
                        ExpressiveDockAction(
                            icon = Icons.Rounded.GraphicEq,
                            contentDescription = "音轨",
                            active = false,
                            onClick = { showAudioTrackSheet = true },
                        ),
                        ExpressiveDockAction(
                            icon = Icons.Rounded.AspectRatio,
                            contentDescription = "画面填充",
                            active = resizeModeIndex != 0,
                            onClick = {
                                resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
                                hudMessage = "画面：${resizeModes[resizeModeIndex].second}"
                            },
                        ),
                        ExpressiveDockAction(
                            icon = Icons.Rounded.Speed,
                            contentDescription = "播放倍速",
                            active = speedIndex != 1,
                            onClick = {
                                speedIndex = (speedIndex + 1) % speeds.size
                                val spd = speeds[speedIndex]
                                exoPlayer.playbackParameters = PlaybackParameters(spd)
                                hudMessage = "倍速：${spd}x"
                            },
                        ),
                    ),
                    dockColor = Color(0xCC12151E),
                    buttonColor = Color.White.copy(alpha = 0.12f),
                    activeButtonColor = colors.accent,
                    iconColor = Color.White,
                    activeIconColor = colors.primaryButtonFg,
                    modifier = Modifier.fillMaxWidth(),
                )
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
                subtitleChoices.forEach { choice ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (choice.selected) colors.activeIndicator else colors.surfaceContainerLow)
                            .clickable {
                                val builder = exoPlayer.trackSelectionParameters.buildUpon()
                                if (choice.group == null) {
                                    builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                                } else {
                                    builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                        .setOverrideForType(TrackSelectionOverride(choice.group.mediaTrackGroup, choice.trackIndex))
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
                Spacer(Modifier.height(20.dp))
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
                    audioChoices.forEach { choice ->
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
                Spacer(Modifier.height(20.dp))
            }
        }
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
