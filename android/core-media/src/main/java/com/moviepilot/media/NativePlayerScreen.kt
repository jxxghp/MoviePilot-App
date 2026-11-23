package com.moviepilot.media

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
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
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeGlassSheet
import kotlinx.coroutines.delay
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

/** 根据请求创建带同源 Authorization/Cookie 头与外挂字幕配置的 ExoPlayer 实例。 */
@OptIn(UnstableApi::class)
fun buildConfiguredExoPlayer(context: Context, request: MediaPlaybackRequest): ExoPlayer {
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
    return ExoPlayer.Builder(context)
        .setMediaSourceFactory(mediaSourceFactory)
        .build()
        .apply {
            setMediaItem(itemBuilder.build())
            if (request.resumePositionMs > 0L) {
                seekTo(request.resumePositionMs)
            }
            prepare()
            playWhenReady = true
        }
}

private data class ResolvedTrackChoice(
    val label: String,
    val group: Tracks.Group?,
    val trackIndex: Int,
    val selected: Boolean,
)

/**
 * 原生 Media3 全格式音视频播放器（1:1 对齐 iOS 播控规范 + Android 原生手势与轨道能力）：
 * - 完整支持同源 Bearer/Cookie 鉴权流、`content://`/`file://` 本机文件与外挂字幕加载；
 * - 真实 ExoPlayer 音轨/字幕轨道枚举与切换弹窗（支持关闭字幕、选择内嵌/外挂字幕与多声道音轨）；
 * - Android 原生手势：左半屏上下滑调亮度、右半屏上下滑调音量、左右滑快进快退、双击暂停/播放；
 * - 右上角仅保留画中画（PiP）纯图标；锁定/解锁居中靠右且仅横屏显示；
 * - 进度条下方左（字幕/音轨）右（填充模式/倍速）全纯图标；
 * - 音乐模式支持多行 LRC 同步滚动歌词、队列上下首切歌、最小化至底部悬浮迷你条后台连续播放；
 * - 自动回传播放进度至 `/api/v1/mediaserver/progress`。
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
    val colors = LocalMoviePilotColors.current
    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    val ownsPlayer = sharedPlayer == null
    val exoPlayer = remember(request.url, sharedPlayer) {
        sharedPlayer ?: buildConfiguredExoPlayer(context, request)
    }

    var isPlaying by remember { mutableStateOf(true) }
    var positionMs by remember { mutableLongStateOf(request.resumePositionMs) }
    var durationMs by remember { mutableLongStateOf(1L) }
    var controlsVisible by remember { mutableStateOf(true) }
    var isLocked by remember { mutableStateOf(false) }
    var speedIndex by remember { mutableIntStateOf(1) }
    var resizeModeIndex by remember { mutableIntStateOf(0) }
    var showSubtitleSheet by remember { mutableStateOf(false) }
    var showAudioTrackSheet by remember { mutableStateOf(false) }
    var hudMessage by remember { mutableStateOf<String?>(null) }
    var tracksVersion by remember { mutableIntStateOf(0) }

    val speeds = listOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    val resizeModes = listOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT to "自适应",
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM to "铺满裁剪",
        AspectRatioFrameLayout.RESIZE_MODE_FILL to "拉伸填充",
    )
    val lrcLines = remember(request.lyricsLrc) { parseLrcLyrics(request.lyricsLrc) }
    val lrcListState = rememberLazyListState()

    // 监听轨道变化以实时更新真实字幕/音轨列表
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

    // 实时同步进度并每 10 秒上报媒体服务器进度
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

    // 自动清除手势/切换 HUD 提示
    LaunchedEffect(hudMessage) {
        if (hudMessage != null) {
            delay(1400)
            hudMessage = null
        }
    }

    // 同步滚动 LRC 歌词到当前行
    val activeLrcIdx = remember(positionMs, lrcLines) {
        lrcLines.indexOfLast { it.timeMs <= positionMs }.coerceAtLeast(0)
    }
    LaunchedEffect(activeLrcIdx, lrcLines.size) {
        if (request.isAudio && lrcLines.isNotEmpty()) {
            lrcListState.animateScrollToItem((activeLrcIdx - 2).coerceAtLeast(0))
        }
    }

    // 解析真实内嵌/外挂字幕与音轨选项
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
                if (!request.isAudio && !isLocked) {
                    Modifier.pointerInput(Unit) {
                        var startX = 0f
                        var mode = 0 // 1=brightness, 2=volume, 3=seek
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
        if (!request.isAudio) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        useController = false
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
        } else {
            // 音频全屏封面 + 多行同步滚动 LRC 歌词
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            colors.palette.ifEmpty { listOf(Color(0xFF30334A), Color(0xFF242E40)) },
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier
                        .fillMaxWidth()
                        .statusBarsPadding()
                        .padding(horizontal = 28.dp, vertical = 72.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(if (lrcLines.isNotEmpty()) 176.dp else 224.dp)
                            .clip(RoundedCornerShape(24.dp))
                            .background(Color.White.copy(alpha = 0.12f))
                            .border(0.8.dp, Color.White.copy(alpha = 0.22f), RoundedCornerShape(24.dp)),
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
                                tint = colors.accent,
                                modifier = Modifier.size(68.dp),
                            )
                        }
                    }
                    Spacer(Modifier.height(18.dp))
                    Text(
                        text = request.title,
                        color = Color.White,
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (request.subtitle.isNotBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text(request.subtitle, color = Color.White.copy(alpha = 0.72f), fontSize = 14.sp, maxLines = 1)
                    }
                    if (lrcLines.isNotEmpty()) {
                        Spacer(Modifier.height(16.dp))
                        LazyColumn(
                            state = lrcListState,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(180.dp),
                            contentPadding = PaddingValues(vertical = 24.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            itemsIndexed(lrcLines) { idx, line ->
                                val active = idx == activeLrcIdx
                                Text(
                                    text = line.text,
                                    color = if (active) Color.White else Color.White.copy(alpha = 0.42f),
                                    fontSize = if (active) 16.sp else 13.sp,
                                    fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.clickable { exoPlayer.seekTo(line.timeMs) },
                                )
                            }
                        }
                    }
                }
            }
        }

        // 手势/切换瞬时浮标 HUD
        hudMessage?.let { msg ->
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 64.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.68f))
                    .padding(horizontal = 16.dp, vertical = 7.dp),
            ) {
                Text(msg, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        // 横屏锁定/解锁纯图标按钮（居中靠右，严格仅横屏显示）
        if (isLandscape && controlsVisible) {
            IconButton(
                onClick = { isLocked = !isLocked },
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 20.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f)),
            ) {
                Icon(
                    imageVector = if (isLocked) Icons.Rounded.Lock else Icons.Rounded.LockOpen,
                    contentDescription = if (isLocked) "解锁屏幕" else "锁定屏幕",
                    tint = Color.White,
                )
            }
        }

        if (controlsVisible && !isLocked) {
            // 顶部极简条：左侧返回 + 标题；右上角仅保留画中画（PiP）纯图标按钮
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.65f), Color.Transparent)))
                    .statusBarsPadding()
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = {
                    if (request.isAudio && onMinimizeToMiniBar != null) onMinimizeToMiniBar() else onClose()
                }) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回", tint = Color.White)
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
                IconButton(onClick = {
                    val activity = context as? Activity
                    if (activity != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(Rational(16, 9))
                            .build()
                        activity.enterPictureInPictureMode(params)
                    }
                }) {
                    Icon(Icons.Rounded.PictureInPictureAlt, contentDescription = "画中画", tint = Color.White)
                }
            }

            // 中央播放/暂停（音频或队列支持上一首/下一首）
            Row(
                modifier = Modifier.align(Alignment.Center),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                if (request.queue.size > 1 && onSwitchRequest != null) {
                    IconButton(
                        onClick = {
                            val prevIdx = (request.queueIndex - 1 + request.queue.size) % request.queue.size
                            onSwitchRequest(request.queue[prevIdx].copy(queue = request.queue, queueIndex = prevIdx))
                        },
                        modifier = Modifier.size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.42f)),
                    ) {
                        Icon(Icons.Rounded.SkipPrevious, contentDescription = "上一首", tint = Color.White, modifier = Modifier.size(28.dp))
                    }
                }
                IconButton(
                    onClick = {
                        if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                    },
                    modifier = Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.48f)),
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                        contentDescription = if (isPlaying) "暂停" else "播放",
                        tint = Color.White,
                        modifier = Modifier.size(36.dp),
                    )
                }
                if (request.queue.size > 1 && onSwitchRequest != null) {
                    IconButton(
                        onClick = {
                            val nextIdx = (request.queueIndex + 1) % request.queue.size
                            onSwitchRequest(request.queue[nextIdx].copy(queue = request.queue, queueIndex = nextIdx))
                        },
                        modifier = Modifier.size(48.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.42f)),
                    ) {
                        Icon(Icons.Rounded.SkipNext, contentDescription = "下一首", tint = Color.White, modifier = Modifier.size(28.dp))
                    }
                }
            }

            // 底部进度条 + 左（字幕/音轨）右（填充模式/倍速）全纯图标
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.74f))))
                    .navigationBarsPadding()
                    .padding(horizontal = 18.dp, vertical = 14.dp),
            ) {
                val progress = (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
                var draggingProgress by remember { mutableFloatStateOf(-1f) }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(formatDurationMs(if (draggingProgress >= 0f) (draggingProgress * durationMs).toLong() else positionMs), color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp)
                    Text(formatDurationMs(durationMs), color = Color.White.copy(alpha = 0.65f), fontSize = 11.sp)
                }
                Slider(
                    value = if (draggingProgress >= 0f) draggingProgress else progress,
                    onValueChange = { draggingProgress = it },
                    onValueChangeFinished = {
                        if (draggingProgress >= 0f) {
                            exoPlayer.seekTo((draggingProgress * durationMs).toLong())
                            draggingProgress = -1f
                        }
                    },
                    colors = SliderDefaults.colors(
                        thumbColor = Color.White,
                        activeTrackColor = colors.accent,
                        inactiveTrackColor = Color.White.copy(alpha = 0.30f),
                    ),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // 左侧纯图标：字幕（真实轨道选择器）、音轨（真实轨道选择器）
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        IconButton(onClick = { showSubtitleSheet = true }) {
                            Icon(
                                Icons.Rounded.ClosedCaption,
                                contentDescription = "字幕",
                                tint = if (subtitleChoices.any { it.group != null && it.selected }) colors.accent else Color.White.copy(alpha = 0.82f),
                            )
                        }
                        IconButton(onClick = { showAudioTrackSheet = true }) {
                            Icon(
                                Icons.Rounded.GraphicEq,
                                contentDescription = "音轨",
                                tint = Color.White,
                            )
                        }
                    }
                    // 右侧纯图标：填充模式、倍速
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        IconButton(onClick = {
                            resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size
                            hudMessage = "画面：${resizeModes[resizeModeIndex].second}"
                        }) {
                            Icon(Icons.Rounded.AspectRatio, contentDescription = "画面填充", tint = Color.White)
                        }
                        IconButton(onClick = {
                            speedIndex = (speedIndex + 1) % speeds.size
                            val spd = speeds[speedIndex]
                            exoPlayer.playbackParameters = PlaybackParameters(spd)
                            hudMessage = "倍速：${spd}x"
                        }) {
                            Icon(Icons.Rounded.Speed, contentDescription = "播放倍速", tint = Color.White)
                        }
                    }
                }
            }
        }
    }

    // 真实字幕轨道选择弹窗
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
                            .clip(RoundedCornerShape(14.dp))
                            .background(if (choice.selected) colors.accent.copy(alpha = 0.20f) else colors.chipFill)
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

    // 真实音轨选择弹窗
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
                                .clip(RoundedCornerShape(14.dp))
                                .background(if (choice.selected) colors.accent.copy(alpha = 0.20f) else colors.chipFill)
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

/** 停靠于 4+1 底栏上方的原生悬浮玻璃迷你音乐条（直连同一 ExoPlayer 后台无缝续播）。 */
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
    val colors = LocalMoviePilotColors.current
    CinematicGlassSurface(
        shape = RoundedCornerShape(22.dp),
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 18.dp)
            .clickable(onClick = onExpand),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(colors.accent.copy(alpha = 0.25f)),
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
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = colors.accent)
                }
            }
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = request.title,
                    color = colors.textPrimary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (request.subtitle.isNotBlank()) {
                    Text(
                        text = request.subtitle,
                        color = colors.textSecondary,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            IconButton(onClick = onTogglePlay) {
                Icon(
                    if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = "播放或暂停",
                    tint = colors.textPrimary,
                )
            }
            if (request.queue.size > 1) {
                IconButton(onClick = onNext) {
                    Icon(Icons.Rounded.SkipNext, contentDescription = "下一首", tint = colors.textPrimary)
                }
            }
            IconButton(onClick = onClose) {
                Icon(Icons.Rounded.Close, contentDescription = "关闭", tint = colors.textMuted)
            }
        }
    }
}
