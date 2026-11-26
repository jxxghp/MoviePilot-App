package com.moviepilot.widget

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File

/** 正在播放桌面小组件读取的本地共享偏好模型（对应 `"mp_now_playing_widget_v1"`）。 */
data class NowPlayingWidgetState(
    val active: Boolean = false,
    val pluginId: String = "",
    val pluginName: String = "",
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val lyrics: String = "",
    val artworkPath: String = "",
    val isPlaying: Boolean = false,
    val liked: Boolean = false,
    val hasLike: Boolean = false,
    val canNext: Boolean = true,
    val canPrev: Boolean = true,
    val durationMs: Long = 0L,
    val positionMs: Long = 0L,
    val updatedAt: Long = 0L,
)

/** 正在播放桌面小组件持久化读写与乐观状态翻转工具。 */
object NowPlayingWidgetStore {
    const val PREF_NAME = "mp_now_playing_widget_v1"
    const val ACTION_NOW_PLAYING_UPDATED = "com.moviepilot.widget.ACTION_NOW_PLAYING_UPDATED"
    const val ACTION_MEDIA_TOGGLE = "com.moviepilot.plugin.MEDIA_TOGGLE"
    const val ACTION_MEDIA_PREV = "com.moviepilot.plugin.MEDIA_PREV"
    const val ACTION_MEDIA_NEXT = "com.moviepilot.plugin.MEDIA_NEXT"
    const val ACTION_MEDIA_LIKE = "com.moviepilot.plugin.MEDIA_LIKE"

    /** 读取 `"mp_now_playing_widget_v1"` 快照。 */
    fun load(context: Context): NowPlayingWidgetState {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        return NowPlayingWidgetState(
            active = prefs.getBoolean("active", false),
            pluginId = prefs.getString("plugin_id", "").orEmpty(),
            pluginName = prefs.getString("plugin_name", "").orEmpty(),
            title = prefs.getString("title", "").orEmpty(),
            artist = prefs.getString("artist", "").orEmpty(),
            album = prefs.getString("album", "").orEmpty(),
            lyrics = prefs.getString("lyrics", "").orEmpty(),
            artworkPath = prefs.getString("artwork_path", "").orEmpty(),
            isPlaying = prefs.getBoolean("is_playing", false),
            liked = prefs.getBoolean("liked", false),
            hasLike = prefs.getBoolean("has_like", false),
            canNext = prefs.getBoolean("can_next", true),
            canPrev = prefs.getBoolean("can_prev", true),
            durationMs = prefs.getLong("duration_ms", 0L).coerceAtLeast(0L),
            positionMs = prefs.getLong("position_ms", 0L).coerceAtLeast(0L),
            updatedAt = prefs.getLong("updated_at", 0L),
        )
    }

    /** 乐观翻转 `"is_playing"` 或 `"liked"` 状态，保证桌面点击零延迟视觉响应。 */
    fun applyOptimisticBroadcastAction(context: Context, broadcastAction: String): NowPlayingWidgetState {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("active", false)) return load(context)
        val editor = prefs.edit()
        when (broadcastAction) {
            ACTION_MEDIA_TOGGLE -> {
                val cur = prefs.getBoolean("is_playing", false)
                editor.putBoolean("is_playing", !cur)
            }
            ACTION_MEDIA_LIKE -> {
                if (prefs.getBoolean("has_like", false)) {
                    val cur = prefs.getBoolean("liked", false)
                    editor.putBoolean("liked", !cur)
                }
            }
        }
        editor.putLong("updated_at", System.currentTimeMillis()).apply()
        return load(context)
    }

    /** 按采样尺寸安全解码本地缓存专辑封面，防止超大位图触发 RemoteViews Binder 溢出。 */
    fun loadSampledArtwork(rawPath: String, maxSidePx: Int = 256): Bitmap? {
        val clean = rawPath.trim()
        if (clean.isEmpty() || clean.contains("..")) return null
        return runCatching {
            val file = File(clean)
            if (!file.isFile || !file.canRead() || file.length() <= 0L || file.length() > 8L * 1024L * 1024L) {
                return null
            }
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outWidth / sample > maxSidePx || bounds.outHeight / sample > maxSidePx) {
                sample *= 2
            }
            BitmapFactory.decodeFile(
                file.absolutePath,
                BitmapFactory.Options().apply { inSampleSize = sample },
            )
        }.getOrNull()
    }
}

private val BroadcastActionKey = ActionParameters.Key<String>("mp_np_broadcast_action")
private val PluginIdKey = ActionParameters.Key<String>("mp_np_plugin_id")
internal val NowPlayingRevisionKey = longPreferencesKey("mp_now_playing_revision")

internal suspend fun redrawAllNowPlayingWidgets(context: Context) {
    val manager = GlanceAppWidgetManager(context)
    val glanceIds = runCatching {
        manager.getGlanceIds(MoviePilotNowPlayingGlanceWidget::class.java)
    }.getOrDefault(emptyList())
    glanceIds.forEach { gid ->
        updateAppWidgetState(context, gid) { prefs ->
            prefs[NowPlayingRevisionKey] = (prefs[NowPlayingRevisionKey] ?: 0L) + 1L
        }
        MoviePilotNowPlayingGlanceWidget().update(context, gid)
    }
}

/** 播控按钮交互回调：发送包内显式播控广播并立即乐观重绘 Glance。 */
class NowPlayingControlAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val action = parameters[BroadcastActionKey] ?: return
        val pluginId = parameters[PluginIdKey].orEmpty()
        NowPlayingWidgetStore.applyOptimisticBroadcastAction(context, action)
        val broadcast = Intent(action).apply {
            setPackage(context.packageName)
            putExtra("plugin_id", pluginId)
        }
        context.sendBroadcast(broadcast)
        updateAppWidgetState(context, glanceId) { prefs ->
            prefs[NowPlayingRevisionKey] = (prefs[NowPlayingRevisionKey] ?: 0L) + 1L
        }
        MoviePilotNowPlayingGlanceWidget().update(context, glanceId)
    }
}

/**
 * MoviePilot 正在播放（固定音频播控）桌面小组件：
 * 支持小号（封面+歌名+播放暂停）、中号（左图右词+完整播控）与大号（大图+多行歌词+进度+播控栏）。
 */
class MoviePilotNowPlayingGlanceWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(220.dp, 110.dp),
            DpSize(280.dp, 200.dp),
        ),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val revision = currentState<Preferences>()[NowPlayingRevisionKey]
            val state = remember(revision) { NowPlayingWidgetStore.load(context) }
            val bitmap = remember(state.artworkPath, revision) {
                if (state.active) NowPlayingWidgetStore.loadSampledArtwork(state.artworkPath) else null
            }
            val palette = GlanceSemanticPalette.resolve(context)
            NowPlayingWidgetContent(
                context = context,
                state = state,
                artwork = bitmap,
                palette = palette,
            )
        }
    }
}

@Composable
private fun NowPlayingWidgetContent(
    context: Context,
    state: NowPlayingWidgetState,
    artwork: Bitmap?,
    palette: GlanceSemanticPalette,
) {
    val size = LocalSize.current
    val isSmall = size.width < 180.dp
    val isLarge = size.height >= 175.dp

    val openIntent = remember(state.pluginId, state.active) {
        val uri = if (state.pluginId.isNotBlank()) {
            Uri.parse("moviepilot://plugin/${Uri.encode(state.pluginId)}?surface=data")
        } else {
            Uri.parse("moviepilot://music")
        }
        Intent(Intent.ACTION_VIEW, uri).apply {
            component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
    }

    if (!state.active || state.title.isBlank()) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(GlanceSemanticPalette.CornerRadius)
                .background(ColorProvider(palette.cardBackground))
                .clickable(actionStartActivity(openIntent))
                .padding(14.dp),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            Text(
                text = "MoviePilot 正在播放",
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(palette.accent),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Spacer(GlanceModifier.height(6.dp))
            Text(
                text = "当前暂无播放中的插件音频 · 点击打开 MoviePilot",
                maxLines = 2,
                style = TextStyle(
                    color = ColorProvider(palette.textSecondary),
                    fontSize = 12.sp,
                ),
            )
        }
        return
    }

    val cleanLyrics = remember(state.lyrics) {
        state.lyrics.lineSequence()
            .map { raw ->
                val close = raw.indexOf(']')
                if (raw.startsWith("[") && close > 0) raw.substring(close + 1).trim() else raw.trim()
            }
            .filter { it.isNotEmpty() }
            .toList()
    }
    val subtitleLine = remember(state.artist, state.album, state.pluginName) {
        listOf(state.artist, state.album).filter { it.isNotBlank() }.joinToString(" · ")
            .ifBlank { state.pluginName.ifBlank { "MoviePilot" } }
    }
    val progress = if (state.durationMs > 0L) {
        (state.positionMs.toFloat() / state.durationMs.toFloat()).coerceIn(0f, 1f)
    } else {
        null
    }

    if (isSmall) {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(GlanceSemanticPalette.CornerRadius)
                .background(ColorProvider(palette.cardBackground))
                .clickable(actionStartActivity(openIntent))
                .padding(12.dp),
            verticalAlignment = Alignment.Vertical.Top,
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                ArtworkBox(artwork = artwork, sizeDp = 44, radiusDp = 12, palette = palette)
                Spacer(GlanceModifier.defaultWeight())
                ControlChip(
                    label = if (state.isPlaying) "⏸" else "▶",
                    action = NowPlayingWidgetStore.ACTION_MEDIA_TOGGLE,
                    pluginId = state.pluginId,
                    emphasized = true,
                    palette = palette,
                )
            }
            Spacer(GlanceModifier.defaultWeight())
            Text(
                text = state.title,
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(palette.textPrimary),
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            Text(
                text = state.artist.ifBlank { state.pluginName.ifBlank { "MoviePilot" } },
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(palette.textSecondary),
                    fontSize = 11.sp,
                ),
            )
        }
    } else if (!isLarge) {
        Row(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(GlanceSemanticPalette.CornerRadius)
                .background(ColorProvider(palette.cardBackground))
                .clickable(actionStartActivity(openIntent))
                .padding(14.dp),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            ArtworkBox(artwork = artwork, sizeDp = 76, radiusDp = 16, palette = palette)
            Spacer(GlanceModifier.width(12.dp))
            Column(
                modifier = GlanceModifier.defaultWeight(),
                verticalAlignment = Alignment.Vertical.Top,
            ) {
                Text(
                    text = state.title,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.textPrimary),
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                Text(
                    text = subtitleLine,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.textSecondary),
                        fontSize = 11.5.sp,
                    ),
                )
                if (cleanLyrics.isNotEmpty()) {
                    Spacer(GlanceModifier.height(2.dp))
                    Text(
                        text = cleanLyrics.first(),
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(palette.accent),
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }
                Spacer(GlanceModifier.height(6.dp))
                NowPlayingControlBar(state = state, palette = palette)
            }
        }
    } else {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(GlanceSemanticPalette.CornerRadius)
                .background(ColorProvider(palette.cardBackground))
                .clickable(actionStartActivity(openIntent))
                .padding(14.dp),
            verticalAlignment = Alignment.Vertical.Top,
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.Vertical.CenterVertically,
            ) {
                ArtworkBox(artwork = artwork, sizeDp = 82, radiusDp = 18, palette = palette)
                Spacer(GlanceModifier.width(12.dp))
                Column(modifier = GlanceModifier.defaultWeight()) {
                    if (state.pluginName.isNotBlank()) {
                        Text(
                            text = state.pluginName,
                            maxLines = 1,
                            style = TextStyle(
                                color = ColorProvider(palette.accent),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                        )
                    }
                    Text(
                        text = state.title,
                        maxLines = 2,
                        style = TextStyle(
                            color = ColorProvider(palette.textPrimary),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                    )
                    Text(
                        text = subtitleLine,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(palette.textSecondary),
                            fontSize = 12.sp,
                        ),
                    )
                }
            }

            if (progress != null) {
                Spacer(GlanceModifier.height(8.dp))
                LinearProgressIndicator(
                    progress = progress,
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .height(4.dp)
                        .cornerRadius(2.dp),
                    color = ColorProvider(palette.accent),
                    backgroundColor = ColorProvider(palette.divider),
                )
            }

            Spacer(GlanceModifier.height(8.dp))
            Box(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(ColorProvider(palette.divider)),
            ) {}
            Spacer(GlanceModifier.height(6.dp))

            if (cleanLyrics.isEmpty()) {
                Text(
                    text = "暂无同步歌词",
                    style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 12.sp),
                )
            } else {
                cleanLyrics.take(3).forEachIndexed { idx, line ->
                    if (idx > 0) Spacer(GlanceModifier.height(3.dp))
                    Text(
                        text = line,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(if (idx == 0) palette.textPrimary else palette.textSecondary),
                            fontSize = if (idx == 0) 13.sp else 11.5.sp,
                            fontWeight = if (idx == 0) FontWeight.Bold else FontWeight.Normal,
                        ),
                    )
                }
            }

            Spacer(GlanceModifier.defaultWeight())
            NowPlayingControlBar(state = state, palette = palette)
        }
    }
}

@Composable
private fun ArtworkBox(
    artwork: Bitmap?,
    sizeDp: Int,
    radiusDp: Int,
    palette: GlanceSemanticPalette,
) {
    if (artwork != null) {
        Image(
            provider = ImageProvider(artwork),
            contentDescription = "专辑封面",
            contentScale = ContentScale.Crop,
            modifier = GlanceModifier
                .size(sizeDp.dp)
                .cornerRadius(radiusDp.dp),
        )
    } else {
        Box(
            modifier = GlanceModifier
                .size(sizeDp.dp)
                .cornerRadius(radiusDp.dp)
                .background(ColorProvider(palette.surfaceSecondary)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "♪",
                style = TextStyle(
                    color = ColorProvider(palette.accent),
                    fontSize = (sizeDp * 0.36f).sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
        }
    }
}

@Composable
private fun NowPlayingControlBar(
    state: NowPlayingWidgetState,
    palette: GlanceSemanticPalette,
) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        if (state.hasLike) {
            ControlChip(
                label = if (state.liked) "♥" else "♡",
                action = NowPlayingWidgetStore.ACTION_MEDIA_LIKE,
                pluginId = state.pluginId,
                emphasized = false,
                customTint = if (state.liked) palette.danger else palette.textSecondary,
                palette = palette,
            )
            Spacer(GlanceModifier.width(8.dp))
        }
        if (state.canPrev) {
            ControlChip(
                label = "⏮",
                action = NowPlayingWidgetStore.ACTION_MEDIA_PREV,
                pluginId = state.pluginId,
                emphasized = false,
                palette = palette,
            )
            Spacer(GlanceModifier.width(8.dp))
        }
        ControlChip(
            label = if (state.isPlaying) "⏸" else "▶",
            action = NowPlayingWidgetStore.ACTION_MEDIA_TOGGLE,
            pluginId = state.pluginId,
            emphasized = true,
            palette = palette,
        )
        if (state.canNext) {
            Spacer(GlanceModifier.width(8.dp))
            ControlChip(
                label = "⏭",
                action = NowPlayingWidgetStore.ACTION_MEDIA_NEXT,
                pluginId = state.pluginId,
                emphasized = false,
                palette = palette,
            )
        }
    }
}

@Composable
private fun ControlChip(
    label: String,
    action: String,
    pluginId: String,
    emphasized: Boolean,
    palette: GlanceSemanticPalette,
    customTint: Color? = null,
) {
    Text(
        text = label,
        style = TextStyle(
            color = ColorProvider(
                when {
                    emphasized -> Color.White
                    customTint != null -> customTint
                    else -> palette.textPrimary
                },
            ),
            fontSize = if (emphasized) 14.sp else 13.sp,
            fontWeight = FontWeight.Bold,
        ),
        modifier = GlanceModifier
            .cornerRadius(12.dp)
            .background(ColorProvider(if (emphasized) palette.accent else palette.surfaceSecondary))
            .clickable(
                actionRunCallback<NowPlayingControlAction>(
                    actionParametersOf(
                        BroadcastActionKey to action,
                        PluginIdKey to pluginId,
                    ),
                ),
            )
            .padding(horizontal = if (emphasized) 14.dp else 10.dp, vertical = 5.dp),
    )
}

/** 正在播放桌面小组件广播接收器：同时响应系统刷新与 `ACTION_NOW_PLAYING_UPDATED` 秒级更新广播。 */
class MoviePilotNowPlayingWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MoviePilotNowPlayingGlanceWidget()

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NowPlayingWidgetStore.ACTION_NOW_PLAYING_UPDATED) {
            val pending = goAsync()
            CoroutineScope(Dispatchers.Default).launch {
                try {
                    redrawAllNowPlayingWidgets(context.applicationContext)
                } finally {
                    pending.finish()
                }
            }
            return
        }
        super.onReceive(context, intent)
    }
}
