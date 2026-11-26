package com.moviepilot.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment as ComposeAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight as ComposeFontWeight
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
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
import androidx.glance.layout.Box as GlanceBox
import androidx.glance.layout.Column as GlanceColumn
import androidx.glance.layout.Row as GlanceRow
import androidx.glance.layout.Spacer as GlanceSpacer
import androidx.glance.layout.fillMaxSize as glanceFillMaxSize
import androidx.glance.layout.fillMaxWidth as glanceFillMaxWidth
import androidx.glance.layout.height as glanceHeight
import androidx.glance.layout.padding as glancePadding
import androidx.glance.layout.width as glanceWidth
import androidx.glance.text.FontWeight
import androidx.glance.text.Text as GlanceText
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.moviepilot.designsystem.CinematicAmbientGradient
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.MoviePilotTheme
import com.moviepilot.designsystem.NativeAppearanceStore
import com.moviepilot.rustbridge.MoviePilotRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * 三端统一的 Android Glance 自适应明暗语义色盘：
 * 浅色底 `#F6F8FC` / 次级容器 `#FFFFFF` / 主字 `#121826` / 次字 `#5B6475`；
 * 深色底 `#121620` / 次级容器 `#1B2130` / 主字 `#F3F6FC` / 次字 `#9AA4B8`。
 */
internal data class GlanceSemanticPalette(
    val isDark: Boolean,
    val cardBackground: Color,
    val surfaceSecondary: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val divider: Color,
    val accent: Color,
    val success: Color = Color(0xFF22C55E),
    val warning: Color = Color(0xFFF59E0B),
    val danger: Color = Color(0xFFEF4444),
) {
    fun toneColor(tone: String?): Color {
        parseHexColor(tone)?.let { return it }
        return when (tone?.trim()?.lowercase()) {
            "muted", "secondary" -> textSecondary
            "accent", "primary" -> accent
            "success" -> success
            "warning" -> warning
            "danger", "error" -> danger
            else -> textPrimary
        }
    }

    fun badgeBackground(tone: String?): Color {
        val base = when (tone?.trim()?.lowercase()) {
            "muted", "secondary" -> textSecondary
            else -> toneColor(tone).takeIf { it != textPrimary } ?: accent
        }
        return base.copy(alpha = if (isDark) 0.20f else 0.14f)
    }

    fun badgeForeground(tone: String?): Color {
        return when (tone?.trim()?.lowercase()) {
            "muted", "secondary" -> textSecondary
            "default", null, "" -> accent
            else -> toneColor(tone)
        }
    }

    companion object {
        val CornerRadius = 22.dp
        val DefaultAccent = Color(0xFF3B82F6)

        fun resolve(context: Context, customAccentHex: String? = null): GlanceSemanticPalette {
            val nightMode = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            val isDark = nightMode == Configuration.UI_MODE_NIGHT_YES
            val accent = parseHexColor(customAccentHex) ?: DefaultAccent
            return if (isDark) {
                GlanceSemanticPalette(
                    isDark = true,
                    cardBackground = Color(0xFF121620),
                    surfaceSecondary = Color(0xFF1B2130),
                    textPrimary = Color(0xFFF3F6FC),
                    textSecondary = Color(0xFF9AA4B8),
                    divider = Color(0xFF262F42),
                    accent = accent,
                )
            } else {
                GlanceSemanticPalette(
                    isDark = false,
                    cardBackground = Color(0xFFF6F8FC),
                    surfaceSecondary = Color(0xFFFFFFFF),
                    textPrimary = Color(0xFF121826),
                    textSecondary = Color(0xFF5B6475),
                    divider = Color(0xFFE2E8F0),
                    accent = accent,
                )
            }
        }

        fun parseHexColor(raw: String?): Color? {
            val clean = raw?.trim() ?: return null
            if (!clean.startsWith("#") || clean.length != 7) return null
            val rgb = clean.substring(1).toLongOrNull(16) ?: return null
            return Color(0xFF000000L or rgb)
        }
    }
}

/** 单个 APP 主体小组件实例的持久化配置。 */
data class AppDesktopWidgetConfig(
    val appWidgetId: Int,
    val content: String = "overview", // "overview" | "downloads" | "imports" | "subscriptions"
    val showMediaNames: Boolean = true,
)

/** 主体小组件单类展示指标。 */
data class AppWidgetMetricEntry(
    val id: String,
    val title: String,
    val value: String,
    val tone: String = "default",
)

/** 主体小组件近期明细条目。 */
data class AppWidgetItemEntry(
    val id: String,
    val title: String,
    val subtitle: String = "",
    val progress: Float? = null,
)

/** 主体小组件解析后的完整单节快照。 */
data class AppWidgetSectionSnapshot(
    val server: String,
    val content: String,
    val title: String,
    val updatedAt: String,
    val metrics: List<AppWidgetMetricEntry>,
    val items: List<AppWidgetItemEntry>,
)

/** APP 主体桌面小组件配置与 4 类核心快照读取仓。 */
object AppDesktopWidgetStore {
    const val CONFIG_PREF_NAME = "mp_app_widgets_v1"
    const val SNAPSHOT_PREF_NAME = "mp_widget_snapshot_v1"
    val CONTENT_ORDER = listOf("overview", "downloads", "imports", "subscriptions")
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    /** 读取指定实例配置；未单独配置时默认展示 `overview` 并开启媒体名称。 */
    fun loadConfig(context: Context, appWidgetId: Int): AppDesktopWidgetConfig {
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            return AppDesktopWidgetConfig(appWidgetId, "overview", true)
        }
        val prefs = context.getSharedPreferences(CONFIG_PREF_NAME, Context.MODE_PRIVATE)
        val rawContent = prefs.getString("app_${appWidgetId}_content", "overview") ?: "overview"
        val validContent = if (rawContent in CONTENT_ORDER) rawContent else "overview"
        val showNames = prefs.getBoolean("app_${appWidgetId}_show_names", true)
        return AppDesktopWidgetConfig(appWidgetId, validContent, showNames)
    }

    /** 保存单个主体小组件实例的内容类型与隐私开关。 */
    fun saveConfig(context: Context, config: AppDesktopWidgetConfig) {
        if (config.appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
        context.getSharedPreferences(CONFIG_PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString("app_${config.appWidgetId}_content", config.content)
            .putBoolean("app_${config.appWidgetId}_show_names", config.showMediaNames)
            .apply()
    }

    /** 循环切换小组件展示的 4 类核心内容。 */
    fun cycleContent(context: Context, appWidgetId: Int): AppDesktopWidgetConfig {
        val current = loadConfig(context, appWidgetId)
        val nextIdx = (CONTENT_ORDER.indexOf(current.content) + 1) % CONTENT_ORDER.size
        val updated = current.copy(content = CONTENT_ORDER[nextIdx])
        saveConfig(context, updated)
        return updated
    }

    /** 删除被移除的桌面实例配置。 */
    fun deleteConfig(context: Context, appWidgetId: Int) {
        context.getSharedPreferences(CONFIG_PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove("app_${appWidgetId}_content")
            .remove("app_${appWidgetId}_show_names")
            .apply()
    }

    /** 内容对应的中文标题。 */
    fun titleForContent(content: String): String = when (content) {
        "downloads" -> "下载状态"
        "imports" -> "近期入库"
        "subscriptions" -> "订阅"
        else -> "系统概览"
    }

    /** 内容对应的精确深链地址。 */
    fun deepLinkForContent(content: String): String = when (content) {
        "downloads" -> "moviepilot://downloading"
        "imports" -> "moviepilot://history"
        "subscriptions" -> "moviepilot://subscribe"
        else -> "moviepilot://dashboard"
    }

    /** 读取 `"mp_widget_snapshot_v1"` 中对应分类快照，并按 `showMediaNames` 执行隐私投影。 */
    fun loadSectionSnapshot(
        context: Context,
        content: String,
        showMediaNames: Boolean,
    ): AppWidgetSectionSnapshot {
        val snap = context.getSharedPreferences(SNAPSHOT_PREF_NAME, Context.MODE_PRIVATE)
        val server = snap.getString("server", "MoviePilot") ?: "MoviePilot"
        val fallbackUpdated = snap.getString("updated_at", "") ?: ""
        val rawSection = snap.getString(content, null)
        if (!rawSection.isNullOrBlank()) {
            val parsed = runCatching { json.parseToJsonElement(rawSection) as? JsonObject }.getOrNull()
            if (parsed != null) {
                val title = (parsed["title"] as? JsonPrimitive)?.content ?: titleForContent(content)
                val updatedAt = (parsed["updatedAt"] as? JsonPrimitive)?.content ?: fallbackUpdated
                val metrics = (parsed["metrics"] as? JsonArray)?.mapNotNull { el ->
                    val obj = el as? JsonObject ?: return@mapNotNull null
                    val id = (obj["id"] as? JsonPrimitive)?.content ?: return@mapNotNull null
                    val mTitle = (obj["title"] as? JsonPrimitive)?.content ?: id
                    val mValue = (obj["value"] as? JsonPrimitive)?.content ?: "—"
                    val mTone = (obj["tone"] as? JsonPrimitive)?.content ?: "default"
                    AppWidgetMetricEntry(id, mTitle, mValue, mTone)
                }.orEmpty()
                val rawItems = (parsed["items"] as? JsonArray)?.mapIndexedNotNull { idx, el ->
                    val obj = el as? JsonObject ?: return@mapIndexedNotNull null
                    val id = (obj["id"] as? JsonPrimitive)?.content ?: "item-$idx"
                    val rawTitle = (obj["title"] as? JsonPrimitive)?.content ?: return@mapIndexedNotNull null
                    val rawSub = (obj["subtitle"] as? JsonPrimitive)?.content.orEmpty()
                    val prog = (obj["progress"] as? JsonPrimitive)?.doubleOrNull?.toFloat()?.coerceIn(0f, 1f)
                    if (showMediaNames) {
                        AppWidgetItemEntry(id = id, title = rawTitle, subtitle = rawSub, progress = prog)
                    } else {
                        AppWidgetItemEntry(id = id, title = "项目 ${idx + 1}", subtitle = "", progress = prog)
                    }
                }.orEmpty()
                return AppWidgetSectionSnapshot(
                    server = server,
                    content = content,
                    title = title,
                    updatedAt = updatedAt,
                    metrics = metrics,
                    items = rawItems,
                )
            }
        }

        // 向下兼容旧版仅含 movies / tvs / speed 键的缓存快照
        val movies = snap.getInt("movies", 0)
        val tvs = snap.getInt("tvs", 0)
        val speed = snap.getString("speed", "0 B/s") ?: "0 B/s"
        val fallbackMetrics = when (content) {
            "downloads" -> listOf(
                AppWidgetMetricEntry("downloadSpeed", "下载速度", speed, "success"),
                AppWidgetMetricEntry("uploadSpeed", "上传速度", "0 B/s"),
            )
            "imports" -> listOf(
                AppWidgetMetricEntry("count", "总入库", (movies + tvs).toString(), "accent"),
                AppWidgetMetricEntry("typeMOVIE", "电影", movies.toString()),
                AppWidgetMetricEntry("typeTV", "电视剧", tvs.toString()),
            )
            "subscriptions" -> listOf(
                AppWidgetMetricEntry("count", "总订阅", "0", "accent"),
                AppWidgetMetricEntry("typeMOVIE", "电影", "0"),
                AppWidgetMetricEntry("typeTV", "电视剧", "0"),
            )
            else -> listOf(
                AppWidgetMetricEntry("cpu", "CPU 占用", "—", "accent"),
                AppWidgetMetricEntry("memory", "内存占用", "—"),
                AppWidgetMetricEntry("networkDownload", "下载速度", speed, "success"),
                AppWidgetMetricEntry("typeMOVIE", "入库影视", "${movies + tvs}"),
            )
        }
        return AppWidgetSectionSnapshot(
            server = server,
            content = content,
            title = titleForContent(content),
            updatedAt = fallbackUpdated,
            metrics = fallbackMetrics,
            items = emptyList(),
        )
    }
}

private val AppWidgetIdKey = ActionParameters.Key<Int>("mp_main_app_widget_id")
internal val MainWidgetRevisionKey = longPreferencesKey("mp_main_widget_revision")

internal suspend fun notifyMainWidgetUpdated(context: Context, glanceId: GlanceId) {
    updateAppWidgetState(context, glanceId) { prefs ->
        prefs[MainWidgetRevisionKey] = (prefs[MainWidgetRevisionKey] ?: 0L) + 1L
    }
    MoviePilotGlanceWidget().update(context, glanceId)
}

/** 桌面卡片顶栏点击直接循环切换 `overview -> downloads -> imports -> subscriptions`。 */
class CycleAppWidgetContentAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val appWidgetId = parameters[AppWidgetIdKey]
            ?: runCatching { GlanceAppWidgetManager(context).getAppWidgetId(glanceId) }.getOrNull()
            ?: return
        AppDesktopWidgetStore.cycleContent(context, appWidgetId)
        notifyMainWidgetUpdated(context, glanceId)
    }
}

/** 桌面卡片手动触发后台全量快照拉取。 */
class RefreshAppWidgetAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        withContext(Dispatchers.IO) {
            runCatching { MoviePilotRepository(context.applicationContext).syncAppWidgetSnapshot() }
        }
        notifyMainWidgetUpdated(context, glanceId)
    }
}

/**
 * MoviePilot APP 主体 Jetpack Glance 桌面小组件：
 * 支持 `overview`、`downloads`、`imports`、`subscriptions` 四类内容、小/中/大三种响应式尺寸及隐私脱敏。
 */
class MoviePilotGlanceWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(220.dp, 110.dp),
            DpSize(280.dp, 200.dp),
        ),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appWidgetId = runCatching { GlanceAppWidgetManager(context).getAppWidgetId(id) }
            .getOrDefault(AppWidgetManager.INVALID_APPWIDGET_ID)

        provideContent {
            val revision = currentState<Preferences>()[MainWidgetRevisionKey]
            val config = remember(appWidgetId, revision) {
                AppDesktopWidgetStore.loadConfig(context, appWidgetId)
            }
            val section = remember(config, revision) {
                AppDesktopWidgetStore.loadSectionSnapshot(
                    context = context,
                    content = config.content,
                    showMediaNames = config.showMediaNames,
                )
            }
            val palette = GlanceSemanticPalette.resolve(context)
            MoviePilotMainWidgetCard(
                context = context,
                appWidgetId = appWidgetId,
                config = config,
                section = section,
                palette = palette,
            )
        }
    }
}

@Composable
private fun MoviePilotMainWidgetCard(
    context: Context,
    appWidgetId: Int,
    config: AppDesktopWidgetConfig,
    section: AppWidgetSectionSnapshot,
    palette: GlanceSemanticPalette,
) {
    val size = LocalSize.current
    val isSmall = size.width < 180.dp
    val isLarge = size.height >= 175.dp

    val openIntent = remember(config.content) {
        val deepLink = Uri.parse(AppDesktopWidgetStore.deepLinkForContent(config.content))
        Intent(Intent.ACTION_VIEW, deepLink).apply {
            component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
    }

    GlanceColumn(
        modifier = GlanceModifier
            .glanceFillMaxSize()
            .cornerRadius(GlanceSemanticPalette.CornerRadius)
            .background(ColorProvider(palette.cardBackground))
            .clickable(actionStartActivity(openIntent))
            .glancePadding(if (isSmall) 12.dp else 14.dp),
        verticalAlignment = Alignment.Vertical.Top,
    ) {
        // 顶栏：实例名 + 内容切换胶囊 + 刷新按钮
        GlanceRow(
            modifier = GlanceModifier.glanceFillMaxWidth(),
            verticalAlignment = Alignment.Vertical.CenterVertically,
        ) {
            GlanceColumn(modifier = GlanceModifier.defaultWeight()) {
                GlanceText(
                    text = section.server,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.textPrimary),
                        fontSize = if (isSmall) 12.5.sp else 13.5.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                if (isSmall) {
                    GlanceText(
                        text = section.title,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(palette.accent),
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }
            }

            if (!isSmall && appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                GlanceText(
                    text = section.title,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.accent),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    modifier = GlanceModifier
                        .cornerRadius(10.dp)
                        .background(ColorProvider(palette.badgeBackground("accent")))
                        .clickable(
                            actionRunCallback<CycleAppWidgetContentAction>(
                                actionParametersOf(AppWidgetIdKey to appWidgetId),
                            ),
                        )
                        .glancePadding(horizontal = 8.dp, vertical = 3.dp),
                )
                GlanceSpacer(GlanceModifier.glanceWidth(6.dp))
                GlanceText(
                    text = "↻",
                    style = TextStyle(
                        color = ColorProvider(palette.textSecondary),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    modifier = GlanceModifier
                        .cornerRadius(10.dp)
                        .background(ColorProvider(palette.surfaceSecondary))
                        .clickable(actionRunCallback<RefreshAppWidgetAction>())
                        .glancePadding(horizontal = 7.dp, vertical = 3.dp),
                )
            }
        }

        GlanceSpacer(GlanceModifier.glanceHeight(if (isSmall) 6.dp else 8.dp))

        if (isSmall) {
            val compactList = section.metrics.take(2)
            compactList.forEachIndexed { idx, m ->
                if (idx > 0) GlanceSpacer(GlanceModifier.glanceHeight(4.dp))
                GlanceColumn(modifier = GlanceModifier.glanceFillMaxWidth()) {
                    GlanceText(
                        text = m.value,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(palette.toneColor(m.tone)),
                            fontSize = if (compactList.size == 1) 22.sp else 16.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                    )
                    GlanceText(
                        text = m.title,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(palette.textSecondary),
                            fontSize = 10.5.sp,
                        ),
                    )
                }
            }
        } else {
            val cols = when {
                config.content == "subscriptions" && section.metrics.size >= 4 -> 4
                config.content == "downloads" && section.metrics.size >= 3 -> 3
                else -> 2
            }
            val visibleMetrics = section.metrics.take(if (isLarge) 6 else 4)
            val rows = visibleMetrics.chunked(cols)
            rows.forEachIndexed { rIdx, rowItems ->
                if (rIdx > 0) GlanceSpacer(GlanceModifier.glanceHeight(6.dp))
                GlanceRow(modifier = GlanceModifier.glanceFillMaxWidth()) {
                    for (cIdx in 0 until cols) {
                        if (cIdx > 0) GlanceSpacer(GlanceModifier.glanceWidth(6.dp))
                        val item = rowItems.getOrNull(cIdx)
                        if (item != null) {
                            GlanceColumn(
                                modifier = GlanceModifier
                                    .defaultWeight()
                                    .cornerRadius(12.dp)
                                    .background(ColorProvider(palette.surfaceSecondary))
                                    .glancePadding(horizontal = 8.dp, vertical = 6.dp),
                            ) {
                                GlanceText(
                                    text = item.title,
                                    maxLines = 1,
                                    style = TextStyle(
                                        color = ColorProvider(palette.textSecondary),
                                        fontSize = 10.5.sp,
                                    ),
                                )
                                GlanceText(
                                    text = item.value,
                                    maxLines = 1,
                                    style = TextStyle(
                                        color = ColorProvider(palette.toneColor(item.tone)),
                                        fontSize = 14.5.sp,
                                        fontWeight = FontWeight.Bold,
                                    ),
                                )
                            }
                        } else {
                            GlanceSpacer(GlanceModifier.defaultWeight())
                        }
                    }
                }
            }

            if (isLarge && config.content != "overview") {
                GlanceSpacer(GlanceModifier.glanceHeight(8.dp))
                GlanceBox(
                    modifier = GlanceModifier
                        .glanceFillMaxWidth()
                        .glanceHeight(1.dp)
                        .background(ColorProvider(palette.divider)),
                ) {}
                GlanceSpacer(GlanceModifier.glanceHeight(6.dp))

                if (section.items.isEmpty()) {
                    GlanceText(
                        text = "当前暂无近期记录",
                        style = TextStyle(
                            color = ColorProvider(palette.textSecondary),
                            fontSize = 11.5.sp,
                        ),
                    )
                } else {
                    section.items.take(3).forEachIndexed { idx, item ->
                        if (idx > 0) GlanceSpacer(GlanceModifier.glanceHeight(5.dp))
                        GlanceColumn(modifier = GlanceModifier.glanceFillMaxWidth()) {
                            GlanceRow(
                                modifier = GlanceModifier.glanceFillMaxWidth(),
                                verticalAlignment = Alignment.Vertical.CenterVertically,
                            ) {
                                GlanceText(
                                    text = item.title,
                                    maxLines = 1,
                                    modifier = GlanceModifier.defaultWeight(),
                                    style = TextStyle(
                                        color = ColorProvider(palette.textPrimary),
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                    ),
                                )
                                if (item.progress != null) {
                                    GlanceText(
                                        text = "${(item.progress * 100).toInt()}%",
                                        maxLines = 1,
                                        style = TextStyle(
                                            color = ColorProvider(palette.textSecondary),
                                            fontSize = 10.5.sp,
                                        ),
                                    )
                                }
                            }
                            if (item.subtitle.isNotBlank()) {
                                GlanceText(
                                    text = item.subtitle,
                                    maxLines = 1,
                                    style = TextStyle(
                                        color = ColorProvider(palette.textSecondary),
                                        fontSize = 10.5.sp,
                                    ),
                                )
                            }
                            if (item.progress != null) {
                                GlanceSpacer(GlanceModifier.glanceHeight(2.dp))
                                LinearProgressIndicator(
                                    progress = item.progress,
                                    modifier = GlanceModifier
                                        .glanceFillMaxWidth()
                                        .glanceHeight(4.dp)
                                        .cornerRadius(2.dp),
                                    color = ColorProvider(palette.accent),
                                    backgroundColor = ColorProvider(palette.divider),
                                )
                            }
                        }
                    }
                }
            }
        }

        GlanceSpacer(GlanceModifier.defaultWeight())

        if (section.updatedAt.isNotBlank()) {
            GlanceText(
                text = "更新于 ${section.updatedAt}",
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(palette.textSecondary),
                    fontSize = 10.sp,
                ),
            )
        }
    }
}

/** APP 主体桌面小组件系统广播接收器。 */
class MoviePilotWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MoviePilotGlanceWidget()

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach { wid ->
            AppDesktopWidgetStore.deleteConfig(context, wid)
        }
    }
}

/**
 * APP 主体桌面小组件可选配置与重配页面：
 * 支持选择「系统概览 / 下载状态 / 近期入库 / 订阅」及「显示媒体名称」隐私开关。
 */
class AppWidgetConfigureActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)

        val appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        val cancelResult = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(RESULT_CANCELED, cancelResult)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        val appearanceStore = NativeAppearanceStore(applicationContext)
        val systemDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        window.setBackgroundDrawable(
            ColorDrawable(if (appearanceStore.resolveIsDark(systemDark)) android.graphics.Color.BLACK else 0xFFF4F6FA.toInt()),
        )

        setContent {
            MoviePilotTheme(appearanceStore = appearanceStore) {
                AppWidgetConfigureScreen(
                    appWidgetId = appWidgetId,
                    onCancel = { finish() },
                    onSaved = {
                        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
                        finish()
                    },
                )
            }
        }
    }
}

@Composable
private fun AppWidgetConfigureScreen(
    appWidgetId: Int,
    onCancel: () -> Unit,
    onSaved: () -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val initial = remember(appWidgetId) { AppDesktopWidgetStore.loadConfig(context, appWidgetId) }

    var selectedContent by remember { mutableStateOf(initial.content) }
    var showMediaNames by remember { mutableStateOf(initial.showMediaNames) }
    var isSaving by remember { mutableStateOf(false) }

    val options = remember {
        listOf(
            Triple("overview", "系统概览", "展示 CPU 占用、内存占用、实时下载/上传速率与存储空间"),
            Triple("downloads", "下载状态", "展示实时上下行速率、剩余空间与活跃下载任务进度列表"),
            Triple("imports", "近期入库", "展示总入库与电影/剧集/音乐分类统计及近期整理入库明细"),
            Triple("subscriptions", "订阅", "展示总订阅计数、分类分布及近期订阅集数完成进度"),
        )
    }

    fun commit() {
        if (isSaving) return
        isSaving = true
        scope.launch {
            AppDesktopWidgetStore.saveConfig(
                context,
                AppDesktopWidgetConfig(
                    appWidgetId = appWidgetId,
                    content = selectedContent,
                    showMediaNames = showMediaNames,
                ),
            )
            withContext(Dispatchers.IO) {
                runCatching { MoviePilotRepository(context.applicationContext).syncAppWidgetSnapshot() }
            }
            runCatching {
                val glanceId = GlanceAppWidgetManager(context).getGlanceIdBy(appWidgetId)
                notifyMainWidgetUpdated(context, glanceId)
            }
            isSaving = false
            onSaved()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        CinematicAmbientGradient()
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            Row(
                verticalAlignment = ComposeAlignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "配置 MoviePilot 小组件",
                        color = colors.textPrimary,
                        fontSize = 20.sp,
                        fontWeight = ComposeFontWeight.Bold,
                    )
                    Text(
                        text = "选择桌面卡片展示的核心模块与媒体名称隐私偏好",
                        color = colors.textSecondary,
                        fontSize = 12.5.sp,
                    )
                }
                IconButton(onClick = onCancel) {
                    Icon(Icons.Rounded.Close, contentDescription = "关闭", tint = colors.textSecondary)
                }
            }

            if (isSaving) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = ComposeAlignment.Center) {
                    CircularProgressIndicator(color = colors.accent)
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    item {
                        CinematicPanel(padding = 14.dp) {
                            Row(
                                verticalAlignment = ComposeAlignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "显示媒体名称",
                                        color = colors.textPrimary,
                                        fontSize = 15.sp,
                                        fontWeight = ComposeFontWeight.SemiBold,
                                    )
                                    Text(
                                        text = "关闭后大尺寸明细将隐藏影视片名，显示为「项目 1 / 项目 2」",
                                        color = colors.textSecondary,
                                        fontSize = 12.sp,
                                    )
                                }
                                Switch(
                                    checked = showMediaNames,
                                    onCheckedChange = { showMediaNames = it },
                                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                                )
                            }
                        }
                    }

                    items(options, key = { it.first }) { (key, title, desc) ->
                        val isSelected = selectedContent == key
                        CinematicPanel(
                            padding = 14.dp,
                            modifier = Modifier.clickable {
                                selectedContent = key
                                commit()
                            },
                        ) {
                            Row(
                                verticalAlignment = ComposeAlignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(
                                        text = title,
                                        color = colors.textPrimary,
                                        fontSize = 15.5.sp,
                                        fontWeight = ComposeFontWeight.Bold,
                                    )
                                    Text(
                                        text = desc,
                                        color = colors.textSecondary,
                                        fontSize = 12.sp,
                                    )
                                }
                                if (isSelected) {
                                    Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = colors.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
