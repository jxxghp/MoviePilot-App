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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Dashboard
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.font.FontWeight as ComposeFontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment as GlanceAlignment
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
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.MoviePilotTheme
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeAppearanceStore
import com.moviepilot.designsystem.NativeNetworkEntityLogo
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.PluginDashboardMetaDto
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.SessionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** 单个桌面小组件持久化配置与最近一次同步的数据快照。 */
data class PluginDesktopWidgetConfig(
    val appWidgetId: Int,
    val kind: String, // "plugin_dashboard" | "plugin_launch" | "overview"
    val pluginId: String = "",
    val pluginName: String = "",
    val dashboardKey: String = "",
    val dashboardName: String = "",
    val targetSurface: String = "data", // "data" | "config"
    val subtitle: String = "",
    val badgeText: String = "",
    val lines: List<String> = emptyList(),
    val updatedAt: String = "",
)

/**
 * 自定义桌面小组件数据持久化与插件仪表盘 JSON 摘要提取工具：
 * 兼容 MoviePilot 后端 `/api/v1/plugin/dashboard/{id}[/{key}]` 返回的 Vuetify 节点树与联邦组件描述。
 */
object PluginDesktopWidgetStore {
    private const val PREF_NAME = "mp_plugin_widgets_v1"
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    fun loadConfig(context: Context, appWidgetId: Int): PluginDesktopWidgetConfig? {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val kind = prefs.getString("w_${appWidgetId}_kind", null) ?: return null
        val rawLines = prefs.getString("w_${appWidgetId}_lines", "").orEmpty()
        val parsedLines = runCatching {
            (json.parseToJsonElement(rawLines) as? JsonArray)?.mapNotNull { el ->
                (el as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" }
            }
        }.getOrNull().orEmpty()
        return PluginDesktopWidgetConfig(
            appWidgetId = appWidgetId,
            kind = kind,
            pluginId = prefs.getString("w_${appWidgetId}_plugin_id", "").orEmpty(),
            pluginName = prefs.getString("w_${appWidgetId}_plugin_name", "").orEmpty(),
            dashboardKey = prefs.getString("w_${appWidgetId}_dash_key", "").orEmpty(),
            dashboardName = prefs.getString("w_${appWidgetId}_dash_name", "").orEmpty(),
            targetSurface = prefs.getString("w_${appWidgetId}_surface", "data") ?: "data",
            subtitle = prefs.getString("w_${appWidgetId}_subtitle", "").orEmpty(),
            badgeText = prefs.getString("w_${appWidgetId}_badge", "").orEmpty(),
            lines = parsedLines,
            updatedAt = prefs.getString("w_${appWidgetId}_updated", "").orEmpty(),
        )
    }

    fun saveConfig(context: Context, config: PluginDesktopWidgetConfig) {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val encodedLines = JsonArray(config.lines.map { JsonPrimitive(it) }).toString()
        val allIds = (prefs.getStringSet("configured_ids", emptySet()) ?: emptySet()).toMutableSet()
        allIds += config.appWidgetId.toString()
        prefs.edit()
            .putStringSet("configured_ids", allIds)
            .putString("w_${config.appWidgetId}_kind", config.kind)
            .putString("w_${config.appWidgetId}_plugin_id", config.pluginId)
            .putString("w_${config.appWidgetId}_plugin_name", config.pluginName)
            .putString("w_${config.appWidgetId}_dash_key", config.dashboardKey)
            .putString("w_${config.appWidgetId}_dash_name", config.dashboardName)
            .putString("w_${config.appWidgetId}_surface", config.targetSurface)
            .putString("w_${config.appWidgetId}_subtitle", config.subtitle)
            .putString("w_${config.appWidgetId}_badge", config.badgeText)
            .putString("w_${config.appWidgetId}_lines", encodedLines)
            .putString("w_${config.appWidgetId}_updated", config.updatedAt)
            .apply()
    }

    fun deleteConfig(context: Context, appWidgetId: Int) {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val allIds = (prefs.getStringSet("configured_ids", emptySet()) ?: emptySet()).toMutableSet()
        allIds.remove(appWidgetId.toString())
        prefs.edit()
            .putStringSet("configured_ids", allIds)
            .remove("w_${appWidgetId}_kind")
            .remove("w_${appWidgetId}_plugin_id")
            .remove("w_${appWidgetId}_plugin_name")
            .remove("w_${appWidgetId}_dash_key")
            .remove("w_${appWidgetId}_dash_name")
            .remove("w_${appWidgetId}_surface")
            .remove("w_${appWidgetId}_subtitle")
            .remove("w_${appWidgetId}_badge")
            .remove("w_${appWidgetId}_lines")
            .remove("w_${appWidgetId}_updated")
            .apply()
    }

    fun listConfiguredIds(context: Context): List<Int> {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        return (prefs.getStringSet("configured_ids", emptySet()) ?: emptySet())
            .mapNotNull { it.toIntOrNull() }
    }

    /** 拉取单个已配置小组件的最新远端状态并写回缓存。 */
    suspend fun syncWidgetData(context: Context, appWidgetId: Int): PluginDesktopWidgetConfig? = withContext(Dispatchers.IO) {
        val current = loadConfig(context, appWidgetId) ?: return@withContext null
        val repo = MoviePilotRepository(context.applicationContext)
        val nowStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

        when (current.kind) {
            "plugin_dashboard" -> {
                val raw = runCatching {
                    repo.fetchPluginDashboardWidgetJson(current.pluginId, current.dashboardKey)
                }.getOrNull()
                val extracted = if (!raw.isNullOrBlank()) {
                    extractDashboardSummaryLines(raw)
                } else {
                    emptyList()
                }
                val updated = current.copy(
                    lines = if (extracted.isNotEmpty()) extracted else current.lines.ifEmpty { listOf("点击打开插件查看完整实时仪表盘") },
                    updatedAt = nowStr,
                )
                saveConfig(context, updated)
                updated
            }

            "plugin_launch" -> {
                val matched = runCatching { repo.fetchPlugins(true) }.getOrDefault(emptyList())
                    .firstOrNull { it.id.equals(current.pluginId, ignoreCase = true) }
                if (matched != null) {
                    val updated = current.copy(
                        pluginName = matched.name,
                        subtitle = matched.desc.ifBlank { current.subtitle },
                        badgeText = if (matched.state) "已启用 · v${matched.version}" else "未启用 · v${matched.version}",
                        updatedAt = nowStr,
                    )
                    saveConfig(context, updated)
                    updated
                } else {
                    current
                }
            }

            else -> {
                runCatching { repo.fetchDashboardStats() }
                val snap = context.getSharedPreferences("mp_widget_snapshot_v1", Context.MODE_PRIVATE)
                val movies = snap.getInt("movies", 0)
                val tvs = snap.getInt("tvs", 0)
                val speed = snap.getString("speed", "0 B/s") ?: "0 B/s"
                val server = snap.getString("server", "MoviePilot") ?: "MoviePilot"
                val updated = current.copy(
                    pluginName = server,
                    badgeText = "实时下载 $speed",
                    lines = listOf("电影入库：$movies 部", "剧集入库：$tvs 部"),
                    updatedAt = nowStr,
                )
                saveConfig(context, updated)
                updated
            }
        }
    }

    /** 从插件仪表盘 `/api/v1/plugin/dashboard/{id}` JSON 树中提取适合桌面卡片展示的精简指标行。 */
    internal fun extractDashboardSummaryLines(rawJson: String): List<String> {
        val root = runCatching { json.parseToJsonElement(rawJson) }.getOrNull() ?: return emptyList()
        val unwrapped: JsonElement = if (root is JsonObject && root.containsKey("data") && root["data"] !is JsonNull) {
            root["data"]!!
        } else {
            root
        }
        if (unwrapped is JsonObject) {
            val renderMode = (unwrapped["render_mode"] as? JsonPrimitive)?.content?.lowercase()
            if (renderMode == "vue") {
                val title = (unwrapped["title"] as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" }
                return listOfNotNull(
                    title,
                    "交互式联邦组件仪表盘 · 点击直达插件",
                )
            }
        }

        val collected = mutableListOf<String>()
        fun cleanText(raw: String): String =
            raw.replace(Regex("\\s+"), " ").trim()

        fun collectLeafSnippets(node: JsonElement, out: MutableList<String>, depth: Int = 0) {
            if (depth > 14 || out.size >= 24) return
            when (node) {
                is JsonPrimitive -> {
                    if (node.isString) {
                        val s = cleanText(node.content)
                        if (s.isNotEmpty() && s != "null" && !s.startsWith("mdi-") && !s.startsWith("ri-") && !s.startsWith("#") && !s.contains("{") && s.length <= 64) {
                            out += s
                        }
                    }
                }
                is JsonArray -> node.forEach { collectLeafSnippets(it, out, depth + 1) }
                is JsonObject -> {
                    val comp = (node["component"] as? JsonPrimitive)?.content.orEmpty()
                    if (comp.equals("style", true) || comp.equals("script", true) || comp.equals("VIcon", true)) return
                    val props = node["props"] as? JsonObject
                    listOf("title", "subtitle", "label", "text", "value").forEach { key ->
                        val pv = (props?.get(key) as? JsonPrimitive)?.content?.let(::cleanText).orEmpty()
                        if (pv.isNotEmpty() && pv != "null" && !pv.startsWith("mdi-") && pv.length <= 64) {
                            out += pv
                        }
                    }
                    val directText = (node["text"] as? JsonPrimitive)?.content?.let(::cleanText).orEmpty()
                    if (directText.isNotEmpty() && directText != "null" && !directText.startsWith(".") && directText.length <= 64) {
                        out += directText
                    }
                    // 对紧凑双子节点列（如「指标名 + 数值」）优先拼成单行 "标签：数值"
                    val contentArr = node["content"] as? JsonArray
                    if (contentArr != null) {
                        val localParts = mutableListOf<String>()
                        contentArr.forEach { child -> collectLeafSnippets(child, localParts, depth + 1) }
                        if (localParts.size == 2 && localParts[0].length <= 18 && localParts[1].length <= 24) {
                            val combined = "${localParts[0]}：${localParts[1]}"
                            if (combined !in out) out += combined
                        } else {
                            localParts.forEach { p -> if (p !in out) out += p }
                        }
                    }
                }
            }
        }

        val targetElements: JsonElement = when {
            unwrapped is JsonObject && unwrapped["elements"] != null -> unwrapped["elements"]!!
            unwrapped is JsonObject && unwrapped["content"] != null -> unwrapped["content"]!!
            else -> unwrapped
        }
        collectLeafSnippets(targetElements, collected)
        return collected
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .take(5)
    }
}

private val WidgetIdParamKey = ActionParameters.Key<Int>("mp_app_widget_id")

/** 点击小组件右上角「↻」触发后台实时刷新。 */
class RefreshPluginWidgetAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val appWidgetId = parameters[WidgetIdParamKey]
            ?: runCatching { GlanceAppWidgetManager(context).getAppWidgetId(glanceId) }.getOrNull()
            ?: return
        PluginDesktopWidgetStore.syncWidgetData(context, appWidgetId)
        MoviePilotPluginGlanceWidget().update(context, glanceId)
    }
}

/**
 * MoviePilot 可配置插件与插件仪表盘桌面小组件（支持多尺寸自适应）：
 * - 点击主体自动拉起 `MainActivity` 并通过 `moviepilot://plugin/{id}?surface={data|config}` 直达插件弹窗/页面；
 * - 支持直接展示后端插件注册的仪表盘指标数据与一键手动刷新。
 */
class MoviePilotPluginGlanceWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(220.dp, 110.dp),
            DpSize(280.dp, 180.dp),
        ),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appWidgetId = runCatching { GlanceAppWidgetManager(context).getAppWidgetId(id) }
            .getOrDefault(AppWidgetManager.INVALID_APPWIDGET_ID)
        val config = if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            PluginDesktopWidgetStore.loadConfig(context, appWidgetId)
        } else {
            null
        }

        provideContent {
            PluginWidgetCardContent(
                context = context,
                appWidgetId = appWidgetId,
                config = config,
            )
        }
    }
}

@Composable
private fun PluginWidgetCardContent(
    context: Context,
    appWidgetId: Int,
    config: PluginDesktopWidgetConfig?,
) {
    val size = LocalSize.current
    val isCompactSquare = size.width < 180.dp
    val maxLinesToShow = when {
        size.height >= 165.dp -> 4
        isCompactSquare -> 1
        else -> 2
    }

    val openIntent = remember(config, appWidgetId) {
        if (config == null) {
            Intent(context, PluginWidgetConfigureActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        } else if (config.kind == "overview" || config.pluginId.isBlank()) {
            Intent().apply {
                component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        } else {
            val uri = Uri.parse(
                "moviepilot://plugin/${Uri.encode(config.pluginId)}?surface=${Uri.encode(config.targetSurface)}",
            )
            Intent(Intent.ACTION_VIEW, uri).apply {
                component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        }
    }

    GlanceColumn(
        modifier = GlanceModifier
            .glanceFillMaxSize()
            .cornerRadius(20.dp)
            .background(ColorProvider(Color(0xFF10141E)))
            .clickable(actionStartActivity(openIntent))
            .glancePadding(if (isCompactSquare) 12.dp else 14.dp),
        verticalAlignment = GlanceAlignment.Vertical.Top,
    ) {
        if (config == null) {
            GlanceText(
                text = "MoviePilot 插件小组件",
                style = TextStyle(
                    color = ColorProvider(Color(0xFFD6BDFF)),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            GlanceSpacer(GlanceModifier.glanceHeight(6.dp))
            GlanceText(
                text = "点击选择要固定到桌面的插件快捷入口或插件仪表盘",
                style = TextStyle(
                    color = ColorProvider(Color(0xCCFFFFFF)),
                    fontSize = 12.sp,
                ),
            )
            return@GlanceColumn
        }

        // 顶部标题行 + 手动刷新按钮
        GlanceRow(
            modifier = GlanceModifier.glanceFillMaxWidth(),
            verticalAlignment = GlanceAlignment.Vertical.CenterVertically,
        ) {
            val headerTitle = if (config.kind == "plugin_dashboard" && config.dashboardName.isNotBlank()) {
                config.dashboardName
            } else {
                config.pluginName.ifBlank { config.pluginId.ifBlank { "MoviePilot" } }
            }
            GlanceColumn(modifier = GlanceModifier.defaultWeight()) {
                GlanceText(
                    text = headerTitle,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(Color.White),
                        fontSize = if (isCompactSquare) 13.5.sp else 14.5.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                val tagLine = when (config.kind) {
                    "plugin_dashboard" -> buildString {
                        append(config.pluginName.ifBlank { "插件仪表盘" })
                        if (config.updatedAt.isNotBlank()) append(" · ${config.updatedAt}")
                    }
                    "plugin_launch" -> if (config.targetSurface == "config") "点击直达插件配置" else "点击直达插件弹窗"
                    else -> config.badgeText.ifBlank { "实例概览" }
                }
                GlanceText(
                    text = tagLine,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFA8C7FA)),
                        fontSize = 11.sp,
                    ),
                )
            }

            if (!isCompactSquare && appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                GlanceSpacer(GlanceModifier.glanceWidth(6.dp))
                GlanceText(
                    text = "↻",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFD6BDFF)),
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    modifier = GlanceModifier
                        .cornerRadius(12.dp)
                        .background(ColorProvider(Color(0x24FFFFFF)))
                        .clickable(
                            actionRunCallback<RefreshPluginWidgetAction>(
                                actionParametersOf(WidgetIdParamKey to appWidgetId),
                            ),
                        )
                        .glancePadding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        }

        GlanceSpacer(GlanceModifier.glanceHeight(8.dp))

        if (config.kind == "plugin_launch") {
            if (config.badgeText.isNotBlank()) {
                GlanceText(
                    text = config.badgeText,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF75E6A3)),
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
                GlanceSpacer(GlanceModifier.glanceHeight(4.dp))
            }
            if (!isCompactSquare && config.subtitle.isNotBlank()) {
                GlanceText(
                    text = config.subtitle,
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(Color(0xB8FFFFFF)),
                        fontSize = 12.sp,
                    ),
                )
            }
        } else {
            val displayLines = config.lines.take(maxLinesToShow)
            if (displayLines.isEmpty()) {
                GlanceText(
                    text = "点击打开「${config.pluginName.ifBlank { config.pluginId }}」查看详情",
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(Color(0xB8FFFFFF)),
                        fontSize = 12.sp,
                    ),
                )
            } else {
                displayLines.forEachIndexed { idx, line ->
                    if (idx > 0) GlanceSpacer(GlanceModifier.glanceHeight(3.dp))
                    GlanceText(
                        text = line,
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(if (idx == 0) Color(0xFFEFF3FA) else Color(0xC4FFFFFF)),
                            fontSize = 12.sp,
                            fontWeight = if (idx == 0) FontWeight.Medium else FontWeight.Normal,
                        ),
                    )
                }
            }
        }
    }
}

/** 自定义插件与插件仪表盘桌面小组件广播接收器。 */
class MoviePilotPluginWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MoviePilotPluginGlanceWidget()

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val manager = GlanceAppWidgetManager(context)
                for (wid in appWidgetIds) {
                    PluginDesktopWidgetStore.syncWidgetData(context, wid)
                    runCatching {
                        val glanceId = manager.getGlanceIdBy(wid)
                        MoviePilotPluginGlanceWidget().update(context, glanceId)
                    }
                }
            } finally {
                pending.finish()
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach { wid ->
            PluginDesktopWidgetStore.deleteConfig(context, wid)
        }
    }
}

/**
 * 桌面小组件可视化自定义配置页（添加小组件或长按小组件点击「重新配置」时拉起）：
 * 支持选择「插件仪表盘数据小部件」、「已安装插件快捷直达小部件」或「媒体库与下载概览」。
 */
class PluginWidgetConfigureActivity : ComponentActivity() {
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
        val initialDark = appearanceStore.resolveIsDark(systemDark)
        window.setBackgroundDrawable(
            ColorDrawable(if (initialDark) android.graphics.Color.BLACK else 0xFFF4F6FA.toInt()),
        )
        val repository = MoviePilotRepository(applicationContext)

        setContent {
            MoviePilotTheme(appearanceStore = appearanceStore) {
                PluginWidgetConfigureScreen(
                    repository = repository,
                    appWidgetId = appWidgetId,
                    onCancel = { finish() },
                    onSaved = {
                        val okIntent = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        setResult(RESULT_OK, okIntent)
                        finish()
                    },
                )
            }
        }
    }
}

@Composable
private fun PluginWidgetConfigureScreen(
    repository: MoviePilotRepository,
    appWidgetId: Int,
    onCancel: () -> Unit,
    onSaved: () -> Unit,
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()

    var selectedTab by remember { mutableIntStateOf(0) } // 0: 插件仪表盘, 1: 插件快捷直达, 2: 实例概览
    var searchQuery by remember { mutableStateOf("") }
    var launchSurface by remember { mutableStateOf("data") } // "data" | "config"
    var isLoading by remember { mutableStateOf(true) }
    var isSaving by remember { mutableStateOf(false) }
    var dashboards by remember { mutableStateOf<List<PluginDashboardMetaDto>>(emptyList()) }
    var installedPlugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }

    val authed = repository.session.value is SessionState.Authenticated

    LaunchedEffect(Unit) {
        if (authed) {
            val loadedPlugins = runCatching { repository.fetchPlugins(true) }.getOrDefault(emptyList())
            val loadedDash = runCatching { repository.fetchPluginDashboardMetas() }.getOrDefault(emptyList())
            installedPlugins = loadedPlugins
            dashboards = loadedDash
            if (loadedDash.isEmpty() && loadedPlugins.isNotEmpty()) {
                selectedTab = 1
            }
        }
        isLoading = false
    }

    fun commitSelection(initialConfig: PluginDesktopWidgetConfig) {
        if (isSaving) return
        isSaving = true
        scope.launch {
            PluginDesktopWidgetStore.saveConfig(context, initialConfig)
            PluginDesktopWidgetStore.syncWidgetData(context, appWidgetId)
            runCatching {
                val manager = GlanceAppWidgetManager(context)
                val glanceId = manager.getGlanceIdBy(appWidgetId)
                MoviePilotPluginGlanceWidget().update(context, glanceId)
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
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "配置桌面小部件",
                        color = colors.textPrimary,
                        fontSize = 20.sp,
                        fontWeight = ComposeFontWeight.Bold,
                    )
                    Text(
                        text = "选择插件仪表盘桌面数据卡或插件一键直达入口",
                        color = colors.textSecondary,
                        fontSize = 12.5.sp,
                    )
                }
                IconButton(onClick = onCancel) {
                    Icon(Icons.Rounded.Close, contentDescription = "取消", tint = colors.textSecondary)
                }
            }

            ExpressivePillTabRow(
                tabs = listOf("插件仪表盘", "插件直达", "实例概览"),
                selectedIndex = selectedTab,
                onSelect = { selectedTab = it },
                onTintedHeader = false,
            )

            Spacer(Modifier.height(10.dp))

            if (!authed) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(20.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CinematicPanel(padding = 20.dp) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text = "请先在 MoviePilot App 中登录实例",
                                color = colors.textPrimary,
                                fontSize = 16.sp,
                                fontWeight = ComposeFontWeight.Bold,
                            )
                            Text(
                                text = "登录后即可将任意已安装插件或插件仪表盘绑定到手机桌面。",
                                color = colors.textSecondary,
                                fontSize = 13.sp,
                            )
                        }
                    }
                }
            } else if (isLoading || isSaving) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.accent)
                }
            } else {
                when (selectedTab) {
                    0 -> {
                        val pluginMap = remember(installedPlugins) {
                            installedPlugins.associateBy { it.id.lowercase() }
                        }
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            if (dashboards.isEmpty()) {
                                item {
                                    CinematicPanel(padding = 20.dp, showsShadow = false) {
                                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(
                                                text = "当前暂无提供仪表盘的已启用插件",
                                                color = colors.textPrimary,
                                                fontSize = 15.sp,
                                                fontWeight = ComposeFontWeight.Bold,
                                            )
                                            Text(
                                                text = "可切换到「插件直达」页签，将任意已安装插件添加为点击即达的桌面快捷小部件。",
                                                color = colors.textSecondary,
                                                fontSize = 12.5.sp,
                                            )
                                        }
                                    }
                                }
                            } else {
                                items(dashboards, key = { "${it.id}_${it.key}" }) { dash ->
                                    val owner = pluginMap[dash.id.lowercase()]
                                    val ownerName = owner?.name ?: dash.id
                                    val cardTitle = dash.name.ifBlank { ownerName }
                                    CinematicPanel(
                                        padding = 14.dp,
                                        modifier = Modifier.clickable {
                                            commitSelection(
                                                PluginDesktopWidgetConfig(
                                                    appWidgetId = appWidgetId,
                                                    kind = "plugin_dashboard",
                                                    pluginId = dash.id,
                                                    pluginName = ownerName,
                                                    dashboardKey = dash.key,
                                                    dashboardName = cardTitle,
                                                    targetSurface = "data",
                                                ),
                                            )
                                        },
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            NativeNetworkEntityLogo(
                                                imageUrl = owner?.icon,
                                                kind = "plugin",
                                                value = ownerName,
                                                size = 44.dp,
                                                cornerRadius = 12.dp,
                                            )
                                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                                Row(
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                                ) {
                                                    Text(
                                                        text = cardTitle,
                                                        color = colors.textPrimary,
                                                        fontSize = 15.sp,
                                                        fontWeight = ComposeFontWeight.Bold,
                                                        maxLines = 1,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                    NativeAdaptiveBadge("仪表盘数据", tint = colors.accent)
                                                }
                                                Text(
                                                    text = "来自插件：$ownerName · 桌面实时查看指标并点击直达插件",
                                                    color = colors.textSecondary,
                                                    fontSize = 12.sp,
                                                    maxLines = 2,
                                                    overflow = TextOverflow.Ellipsis,
                                                )
                                            }
                                            Icon(Icons.Rounded.Dashboard, contentDescription = null, tint = colors.accent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    1 -> {
                        Column(modifier = Modifier.fillMaxSize()) {
                            // 搜索栏 + 点击动作选择（打开数据页/弹窗 vs 参数配置）
                            Column(
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                                modifier = Modifier.padding(horizontal = 16.dp),
                            ) {
                                CinematicPanel(padding = 11.dp, cornerRadius = 18.dp, showsShadow = false) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                        Box(modifier = Modifier.weight(1f)) {
                                            if (searchQuery.isEmpty()) {
                                                Text("搜索已安装插件…", color = colors.textMuted, fontSize = 13.5.sp)
                                            }
                                            BasicTextField(
                                                value = searchQuery,
                                                onValueChange = { searchQuery = it },
                                                singleLine = true,
                                                textStyle = ComposeTextStyle(color = colors.textPrimary, fontSize = 13.5.sp),
                                                cursorBrush = SolidColor(colors.accent),
                                                modifier = Modifier.fillMaxWidth(),
                                            )
                                        }
                                    }
                                }
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Text("点击小部件打开：", color = colors.textSecondary, fontSize = 12.5.sp)
                                    NativeAdaptivePill(
                                        title = "插件页面 / 弹窗",
                                        selected = launchSurface == "data",
                                        onClick = { launchSurface = "data" },
                                    )
                                    NativeAdaptivePill(
                                        title = "参数配置",
                                        selected = launchSurface == "config",
                                        onClick = { launchSurface = "config" },
                                    )
                                }
                            }

                            Spacer(Modifier.height(8.dp))
                            val filtered = remember(installedPlugins, searchQuery) {
                                val q = searchQuery.trim().lowercase()
                                if (q.isEmpty()) installedPlugins else installedPlugins.filter {
                                    it.name.lowercase().contains(q) || it.desc.lowercase().contains(q) || it.id.lowercase().contains(q)
                                }
                            }
                            LazyColumn(
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                                modifier = Modifier.fillMaxSize(),
                            ) {
                                items(filtered, key = { it.id }) { plugin ->
                                    CinematicPanel(
                                        padding = 14.dp,
                                        modifier = Modifier.clickable {
                                            val effectiveSurface = if (!plugin.hasPage && plugin.renderMode != "vue") {
                                                "config"
                                            } else {
                                                launchSurface
                                            }
                                            commitSelection(
                                                PluginDesktopWidgetConfig(
                                                    appWidgetId = appWidgetId,
                                                    kind = "plugin_launch",
                                                    pluginId = plugin.id,
                                                    pluginName = plugin.name,
                                                    targetSurface = effectiveSurface,
                                                    subtitle = plugin.desc,
                                                    badgeText = if (plugin.state) "已启用 · v${plugin.version}" else "未启用 · v${plugin.version}",
                                                ),
                                            )
                                        },
                                    ) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            NativeNetworkEntityLogo(
                                                imageUrl = plugin.icon,
                                                kind = "plugin",
                                                value = plugin.name,
                                                size = 44.dp,
                                                cornerRadius = 12.dp,
                                            )
                                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                                Row(
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                                ) {
                                                    Text(
                                                        text = plugin.name,
                                                        color = colors.textPrimary,
                                                        fontSize = 15.sp,
                                                        fontWeight = ComposeFontWeight.Bold,
                                                        maxLines = 1,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                    NativeAdaptiveBadge(
                                                        if (plugin.state) "已启用" else "未启用",
                                                        tint = if (plugin.state) colors.success else colors.textMuted,
                                                    )
                                                }
                                                if (plugin.desc.isNotBlank()) {
                                                    Text(
                                                        text = plugin.desc,
                                                        color = colors.textSecondary,
                                                        fontSize = 12.sp,
                                                        maxLines = 2,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                }
                                            }
                                            Icon(Icons.Rounded.Extension, contentDescription = null, tint = colors.accent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    else -> {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CinematicPanel(
                                padding = 16.dp,
                                modifier = Modifier.clickable {
                                    commitSelection(
                                        PluginDesktopWidgetConfig(
                                            appWidgetId = appWidgetId,
                                            kind = "overview",
                                            pluginName = "MoviePilot",
                                        ),
                                    )
                                },
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Icon(
                                        Icons.Rounded.Speed,
                                        contentDescription = null,
                                        tint = colors.accent,
                                        modifier = Modifier.size(34.dp),
                                    )
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(
                                            text = "实例媒体库与下载速览",
                                            color = colors.textPrimary,
                                            fontSize = 15.5.sp,
                                            fontWeight = ComposeFontWeight.Bold,
                                        )
                                        HorizontalDivider(color = colors.divider)
                                        Text(
                                            text = "在桌面实时展示当前实例的电影/剧集入库总量与下载速率，点击进入主界面。",
                                            color = colors.textSecondary,
                                            fontSize = 12.5.sp,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
