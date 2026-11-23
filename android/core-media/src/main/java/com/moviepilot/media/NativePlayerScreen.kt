package com.moviepilot.media

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.Speed
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.LocalMoviePilotColors
import kotlinx.coroutines.delay

/** 跨端统一音视频播放清单项。 */
data class MediaPlaybackRequest(
    val url: String,
    val title: String,
    val subtitle: String = "",
    val artworkUrl: String? = null,
    val isAudio: Boolean = false,
    val lyricsLrc: String? = null,
    val headers: Map<String, String> = emptyMap(),
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

/**
 * 原生 Media3 全格式音视频播放器（严格遵循极简纯图标播控规范）：
 * - 右上角仅保留画中画（PiP）纯图标按钮；
 * - 锁定/解锁纯图标居中靠右，且仅在横屏时显示；
 * - 进度条下方左侧：字幕、音轨纯图标；右侧：填充模式、倍速纯图标。
 */
@OptIn(UnstableApi::class)
@Composable
fun NativeMediaPlayerOverlay(
    request: MediaPlaybackRequest,
    onClose: () -> Unit,
    onMinimizeToMiniBar: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    val exoPlayer = remember(request.url) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(request.url))
            prepare()
            playWhenReady = true
        }
    }

    var isPlaying by remember { mutableStateOf(true) }
    var positionMs by remember { mutableLongStateOf(0L) }
    var durationMs by remember { mutableLongStateOf(1L) }
    var controlsVisible by remember { mutableStateOf(true) }
    var isLocked by remember { mutableStateOf(false) }
    var speedIndex by remember { mutableIntStateOf(1) } // 1.0x
    var resizeModeIndex by remember { mutableIntStateOf(0) }
    var subtitleEnabled by remember { mutableStateOf(true) }
    var audioTrackIndex by remember { mutableIntStateOf(0) }

    val speeds = listOf(0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
    val resizeModes = listOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
    )
    val lrcLines = remember(request.lyricsLrc) { parseLrcLyrics(request.lyricsLrc) }

    DisposableEffect(exoPlayer) {
        onDispose { exoPlayer.release() }
    }

    LaunchedEffect(exoPlayer) {
        while (true) {
            isPlaying = exoPlayer.isPlaying
            positionMs = exoPlayer.currentPosition.coerceAtLeast(0L)
            durationMs = exoPlayer.duration.coerceAtLeast(1L)
            delay(400)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable { controlsVisible = !controlsVisible },
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
                    pv.resizeMode = resizeModes[resizeModeIndex]
                },
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // 音频全屏封面 + LRC 同步歌词视图
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
                    modifier = Modifier.padding(horizontal = 28.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(220.dp)
                            .clip(RoundedCornerShape(24.dp))
                            .background(Color.White.copy(alpha = 0.12f)),
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
                                modifier = Modifier.size(72.dp),
                            )
                        }
                    }
                    Spacer(Modifier.height(22.dp))
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
                        Text(request.subtitle, color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp)
                    }
                    if (lrcLines.isNotEmpty()) {
                        val activeLine = lrcLines.lastOrNull { it.timeMs <= positionMs } ?: lrcLines.first()
                        Spacer(Modifier.height(18.dp))
                        Text(
                            text = activeLine.text,
                            color = colors.accent,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
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

            // 中央播放/暂停
            IconButton(
                onClick = {
                    if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                },
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f)),
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = if (isPlaying) "暂停" else "播放",
                    tint = Color.White,
                    modifier = Modifier.size(36.dp),
                )
            }

            // 底部进度条 + 左（字幕/音轨）右（填充模式/倍速）全纯图标
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomCenter)
                    .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.72f))))
                    .padding(horizontal = 18.dp, vertical = 16.dp),
            ) {
                val progress = (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
                var draggingProgress by remember { mutableFloatStateOf(-1f) }
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
                    // 左侧纯图标：字幕、音轨
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        IconButton(onClick = { subtitleEnabled = !subtitleEnabled }) {
                            Icon(
                                Icons.Rounded.ClosedCaption,
                                contentDescription = "字幕",
                                tint = if (subtitleEnabled) colors.accent else Color.White.copy(alpha = 0.75f),
                            )
                        }
                        IconButton(onClick = { audioTrackIndex = (audioTrackIndex + 1) % 2 }) {
                            Icon(
                                Icons.Rounded.GraphicEq,
                                contentDescription = "音轨",
                                tint = Color.White,
                            )
                        }
                    }
                    // 右侧纯图标：填充模式、倍速
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        IconButton(onClick = { resizeModeIndex = (resizeModeIndex + 1) % resizeModes.size }) {
                            Icon(Icons.Rounded.AspectRatio, contentDescription = "画面填充", tint = Color.White)
                        }
                        IconButton(onClick = {
                            speedIndex = (speedIndex + 1) % speeds.size
                            exoPlayer.playbackParameters = PlaybackParameters(speeds[speedIndex])
                        }) {
                            Icon(Icons.Rounded.Speed, contentDescription = "播放倍速", tint = Color.White)
                        }
                    }
                }
            }
        }
    }
}

/** 停靠于 4+1 底栏上方的原生悬浮玻璃迷你音乐条。 */
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
            IconButton(onClick = onNext) {
                Icon(Icons.Rounded.SkipNext, contentDescription = "下一首", tint = colors.textPrimary)
            }
            IconButton(onClick = onClose) {
                Icon(Icons.Rounded.Close, contentDescription = "关闭", tint = colors.textMuted)
            }
        }
    }
}
