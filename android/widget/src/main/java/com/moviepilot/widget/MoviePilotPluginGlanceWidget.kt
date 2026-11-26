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
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image as GlanceImage
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
import androidx.glance.layout.Alignment as GlanceAlignment
import androidx.glance.layout.Box as GlanceBox
import androidx.glance.layout.Column as GlanceColumn
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row as GlanceRow
import androidx.glance.layout.Spacer as GlanceSpacer
import androidx.glance.layout.fillMaxSize as glanceFillMaxSize
import androidx.glance.layout.fillMaxWidth as glanceFillMaxWidth
import androidx.glance.layout.height as glanceHeight
import androidx.glance.layout.padding as glancePadding
import androidx.glance.layout.size as glanceSize
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
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.PluginWidgetMetaDto
import com.moviepilot.rustbridge.SessionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** 单个桌面小组件持久化配置与最近一次同步的数据快照。 */
data class PluginDesktopWidgetConfig(
    val appWidgetId: Int,
    val kind: String, // "plugin_dashboard" | "plugin_widget" | "plugin_launch" | "overview"
    val pluginId: String = "",
    val pluginName: String = "",
    val dashboardKey: String = "",
    val dashboardName: String = "",
    val targetSurface: String = "data", // "data" | "config"
    val subtitle: String = "",
    val badgeText: String = "",
    val lines: List<String> = emptyList(),
    val updatedAt: String = "",
    val widgetKey: String = "",
    val payloadJson: String = "",
)

/** 插件小组件自定义按钮交互动作定义。 */
data class PluginWidgetNodeAction(
    val type: String = "openPlugin",
    val surface: String = "data",
    val route: String = "",
    val actionId: String = "",
)

/** 声明式自定义插件小组件布局树节点（最大递归深度 5，单卡片总节点不超过 40）。 */
data class PluginWidgetLayoutNode(
    val type: String,
    val text: String = "",
    val label: String = "",
    val valueText: String = "",
    val subValue: String = "",
    val name: String = "",
    val size: String = "md",
    val weight: String = "regular",
    val align: String = "start",
    val tone: String = "default",
    val gap: Float = 6f,
    val padding: Float = 0f,
    val cornerRadius: Float = 10f,
    val width: Float? = null,
    val height: Float? = null,
    val maxLines: Int = 2,
    val progressValue: Float? = null,
    val monospace: Boolean = false,
    val filled: Boolean = true,
    val url: String = "",
    val action: PluginWidgetNodeAction? = null,
    val children: List<PluginWidgetLayoutNode> = emptyList(),
)

/** 插件预设指标项。 */
data class PluginWidgetMetricEntry(
    val id: String,
    val label: String,
    val value: String,
    val subValue: String = "",
    val tone: String = "default",
)

/** 插件预设列表项。 */
data class PluginWidgetListEntry(
    val id: String,
    val title: String,
    val subtitle: String = "",
    val trailing: String = "",
    val progress: Float? = null,
)

/** 解析后的插件小组件完整快照模型。 */
data class ParsedPluginWidgetPayload(
    val kind: String = "metrics",
    val title: String = "",
    val subtitle: String = "",
    val accentHex: String? = null,
    val artworkPath: String = "",
    val updatedEpochSec: Double = 0.0,
    val metrics: List<PluginWidgetMetricEntry> = emptyList(),
    val items: List<PluginWidgetListEntry> = emptyList(),
    val layout: PluginWidgetLayoutNode? = null,
    val layouts: Map<String, PluginWidgetLayoutNode> = emptyMap(),
) {
    fun resolveLayout(sizeKey: String): PluginWidgetLayoutNode? = layouts[sizeKey] ?: layout
}

/** 插件小组件快照与声明式 `PluginWidgetNode` 布局树安全解析器。 */
internal object PluginWidgetPayloadParser {
    const val MAX_DEPTH = 5
    const val MAX_NODES = 40
    private val ALLOWED_TYPES = setOf(
        "column", "row", "stack", "box", "text", "metric", "icon", "image",
        "progress", "badge", "button", "spacer", "divider",
    )
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private fun JsonObject.str(key: String): String? {
        val p = this[key] as? JsonPrimitive ?: return null
        return p.content.takeIf { it != "null" && it.isNotBlank() }
    }

    /** 解析完整插件快照 JSON，失败或非结构化时返回 `null`。 */
    fun parseSnapshot(rawJson: String): ParsedPluginWidgetPayload? {
        if (rawJson.isBlank()) return null
        val rootEl = runCatching { json.parseToJsonElement(rawJson) }.getOrNull() ?: return null
        val obj = when (rootEl) {
            is JsonObject -> (rootEl["data"] as? JsonObject) ?: rootEl
            else -> return null
        }
        // 识别是否为标准插件小组件快照（区别于旧版 Vuetify 节点树）
        val hasSnapshotShape = obj.containsKey("kind") || obj.containsKey("metrics") ||
            obj.containsKey("items") || obj.containsKey("layout") || obj.containsKey("layouts")
        if (!hasSnapshotShape) return null

        val kind = obj.str("kind") ?: "metrics"
        val title = obj.str("title") ?: obj.str("pluginName") ?: obj.str("plugin_name").orEmpty()
        val subtitle = obj.str("subtitle") ?: obj.str("message").orEmpty()
        val accentHex = obj.str("accentHex") ?: obj.str("accent_hex")
        val artworkPath = obj.str("artworkPath") ?: obj.str("artwork_path") ?: obj.str("artworkFileName").orEmpty()
        val updatedSec = (obj["updatedAt"] as? JsonPrimitive)?.doubleOrNull
            ?: (obj["updated_at"] as? JsonPrimitive)?.doubleOrNull
            ?: (obj["generatedAt"] as? JsonPrimitive)?.doubleOrNull
            ?: 0.0

        val metrics = (obj["metrics"] as? JsonArray)?.take(8)?.mapIndexedNotNull { idx, el ->
            val m = el as? JsonObject ?: return@mapIndexedNotNull null
            val label = m.str("label") ?: m.str("title") ?: return@mapIndexedNotNull null
            val value = m.str("value") ?: "—"
            PluginWidgetMetricEntry(
                id = m.str("id") ?: "m-$idx",
                label = label,
                value = value,
                subValue = m.str("subValue") ?: m.str("sub_value").orEmpty(),
                tone = m.str("tone") ?: "default",
            )
        }.orEmpty()

        val items = (obj["items"] as? JsonArray)?.take(6)?.mapIndexedNotNull { idx, el ->
            val itObj = el as? JsonObject ?: return@mapIndexedNotNull null
            val itemTitle = itObj.str("title") ?: return@mapIndexedNotNull null
            val prog = (itObj["progress"] as? JsonPrimitive)?.doubleOrNull?.toFloat()?.coerceIn(0f, 1f)
            PluginWidgetListEntry(
                id = itObj.str("id") ?: "i-$idx",
                title = itemTitle,
                subtitle = itObj.str("subtitle").orEmpty(),
                trailing = itObj.str("trailing").orEmpty(),
                progress = prog,
            )
        }.orEmpty()

        val singleLayout = (obj["layout"] as? JsonObject)?.let { parseNodeTree(it) }
        val layoutsMap = mutableMapOf<String, PluginWidgetLayoutNode>()
        (obj["layouts"] as? JsonObject)?.let { mapObj ->
            listOf("small", "medium", "large").forEach { sizeKey ->
                (mapObj[sizeKey] as? JsonObject)?.let { treeObj ->
                    parseNodeTree(treeObj)?.let { parsedTree ->
                        layoutsMap[sizeKey] = parsedTree
                    }
                }
            }
        }

        return ParsedPluginWidgetPayload(
            kind = kind,
            title = title,
            subtitle = subtitle,
            accentHex = accentHex,
            artworkPath = artworkPath,
            updatedEpochSec = updatedSec,
            metrics = metrics,
            items = items,
            layout = singleLayout,
            layouts = layoutsMap,
        )
    }

    /** 解析并按最大深度 5、最大节点 40 清洗自定义节点树。 */
    fun parseNodeTree(rootObj: JsonObject): PluginWidgetLayoutNode? {
        val budget = intArrayOf(MAX_NODES)
        return parseNodeRecursive(rootObj, depth = 0, budget = budget)
    }

    /** 从 JSON 字符串解析单个根节点，供测试与外部校验调用。 */
    fun parseNodeTreeFromJson(rawNodeJson: String): PluginWidgetLayoutNode? {
        val obj = runCatching { json.parseToJsonElement(rawNodeJson) as? JsonObject }.getOrNull() ?: return null
        return parseNodeTree(obj)
    }

    private fun parseNodeRecursive(
        obj: JsonObject,
        depth: Int,
        budget: IntArray,
    ): PluginWidgetLayoutNode? {
        if (depth > MAX_DEPTH || budget[0] <= 0) return null
        val type = obj.str("type") ?: return null
        if (type !in ALLOWED_TYPES) return null
        budget[0] -= 1

        val rawValuePrim = obj["value"] as? JsonPrimitive
        val explicitValueText = obj.str("valueText")
        val numericVal = rawValuePrim?.doubleOrNull
        val progressValue = if (type == "progress") {
            numericVal?.toFloat()?.coerceIn(0f, 1f) ?: 0f
        } else {
            numericVal?.takeIf { it in 0.0..1.0 }?.toFloat()
        }
        val valueText = when {
            !explicitValueText.isNullOrBlank() -> explicitValueText
            rawValuePrim != null && rawValuePrim.content != "null" -> rawValuePrim.content
            else -> ""
        }

        val actionObj = obj["action"] as? JsonObject
        val action = actionObj?.let { act ->
            PluginWidgetNodeAction(
                type = act.str("type") ?: "openPlugin",
                surface = act.str("surface") ?: "data",
                route = act.str("route").orEmpty(),
                actionId = act.str("actionId") ?: act.str("action_id").orEmpty(),
            )
        }

        val children = if (type in setOf("column", "row", "stack", "box") && depth < MAX_DEPTH) {
            (obj["children"] as? JsonArray)?.take(16)?.mapNotNull { childEl ->
                if (budget[0] <= 0) null
                else (childEl as? JsonObject)?.let { parseNodeRecursive(it, depth + 1, budget) }
            }.orEmpty()
        } else {
            emptyList()
        }

        val gap = ((obj["gap"] as? JsonPrimitive)?.doubleOrNull ?: 6.0).coerceIn(0.0, 32.0).toFloat()
        val pad = ((obj["padding"] as? JsonPrimitive)?.doubleOrNull ?: 0.0).coerceIn(0.0, 32.0).toFloat()
        val radius = (
            (obj["cornerRadius"] as? JsonPrimitive)?.doubleOrNull
                ?: (obj["radius"] as? JsonPrimitive)?.doubleOrNull
                ?: 10.0
            ).coerceIn(0.0, 32.0).toFloat()
        val width = (obj["width"] as? JsonPrimitive)?.doubleOrNull?.coerceIn(8.0, 360.0)?.toFloat()
        val height = (obj["height"] as? JsonPrimitive)?.doubleOrNull?.coerceIn(8.0, 360.0)?.toFloat()
        val maxLines = ((obj["maxLines"] as? JsonPrimitive)?.intOrNull ?: 2).coerceIn(1, 6)
        val mono = (obj["monospace"] as? JsonPrimitive)?.booleanOrNull
            ?: (obj["tabularNums"] as? JsonPrimitive)?.booleanOrNull
            ?: false
        val filled = (obj["filled"] as? JsonPrimitive)?.booleanOrNull
            ?: (obj.str("style") != "outlined")

        return PluginWidgetLayoutNode(
            type = type,
            text = obj.str("text").orEmpty(),
            label = obj.str("label").orEmpty(),
            valueText = valueText,
            subValue = obj.str("subValue").orEmpty(),
            name = obj.str("name").orEmpty(),
            size = obj.str("size") ?: "md",
            weight = obj.str("weight") ?: "regular",
            align = obj.str("align") ?: obj.str("justify") ?: "start",
            tone = obj.str("tone") ?: "default",
            gap = gap,
            padding = pad,
            cornerRadius = radius,
            width = width,
            height = height,
            maxLines = maxLines,
            progressValue = progressValue,
            monospace = mono,
            filled = filled,
            url = obj.str("url").orEmpty(),
            action = action,
            children = children,
        )
    }

    /** 将结构化快照提炼为向后兼容的 `lines` 文本摘要。 */
    fun summarizeLines(payload: ParsedPluginWidgetPayload): List<String> {
        val out = mutableListOf<String>()
        payload.metrics.forEach { m ->
            out += "${m.label}：${m.value}"
        }
        payload.items.forEach { it ->
            val suffix = if (it.trailing.isNotBlank()) " (${it.trailing})" else ""
            out += "${it.title}$suffix"
        }
        if (out.isEmpty() && payload.subtitle.isNotBlank()) {
            out += payload.subtitle
        }
        return out.take(5)
    }
}

/**
 * 自定义桌面小组件数据持久化、双通道快照融合与插件仪表盘摘要提取工具：
 * 同时支持后端 `/api/v1/plugin/widgets/{id}`、旧版 `/api/v1/plugin/dashboard/{id}` 与运行态 `"rt_${id}_${key}"`。
 */
object PluginDesktopWidgetStore {
    const val PREF_NAME = "mp_plugin_widgets_v1"
    const val ACTION_RUNTIME_UPDATED = "com.moviepilot.widget.ACTION_PLUGIN_WIDGET_RUNTIME_UPDATED"
    const val ACTION_WIDGET_CUSTOM_CLICK = "com.moviepilot.plugin.WIDGET_ACTION"
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    /** 读取指定小组件的配置与已缓存摘要，未配置时返回空。 */
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
            widgetKey = prefs.getString("w_${appWidgetId}_widget_key", "").orEmpty(),
            payloadJson = prefs.getString("w_${appWidgetId}_payload_json", "").orEmpty(),
        )
    }

    /** 原子写入配置和数据快照，并登记已配置的小组件 ID。 */
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
            .putString("w_${config.appWidgetId}_widget_key", config.widgetKey)
            .putString("w_${config.appWidgetId}_payload_json", config.payloadJson)
            .apply()
    }

    /** 删除小组件专属配置与快照，不影响其余桌面实例。 */
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
            .remove("w_${appWidgetId}_widget_key")
            .remove("w_${appWidgetId}_payload_json")
            .apply()
    }

    /** 返回已保存配置的小组件 ID，忽略损坏的索引条目。 */
    fun listConfiguredIds(context: Context): List<Int> {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        return (prefs.getStringSet("configured_ids", emptySet()) ?: emptySet())
            .mapNotNull { it.toIntOrNull() }
    }

    /** 读取本机前端插件运行态推送的 `"rt_${pluginId}_${key}"` 快照 JSON。 */
    fun loadRuntimeSnapshotJson(context: Context, pluginId: String, widgetKey: String): String? {
        if (pluginId.isBlank()) return null
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val direct = prefs.getString("rt_${pluginId}_$widgetKey", null)?.takeIf { it.isNotBlank() }
        if (direct != null) return direct
        if (widgetKey.isBlank()) {
            return prefs.getString("rt_${pluginId}_default", null)?.takeIf { it.isNotBlank() }
        }
        return null
    }

    /** 读取 `"rt_catalog"` 中由本机插件运行态登记的可选小组件清单（兼容 `StringSet` 复合键与 JSON 数组格式）。 */
    fun listRuntimeCatalog(context: Context): List<PluginWidgetMetaDto> {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val rawCatalog = prefs.all["rt_catalog"] ?: return emptyList()
        if (rawCatalog is Set<*>) {
            return rawCatalog.mapNotNull { item -> item as? String }
                .sorted()
                .mapNotNull { composite ->
                    val pid = composite.substringBefore("::", "").trim()
                    val wkey = composite.substringAfter("::", "").trim()
                    if (pid.isEmpty()) return@mapNotNull null
                    val entryJson = prefs.getString("rt_${pid}_$wkey", null)?.takeIf { it.isNotBlank() }
                    val obj = entryJson?.let { runCatching { json.parseToJsonElement(it) as? JsonObject }.getOrNull() }
                    val pname = (obj?.get("pluginName") as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" } ?: pid
                    val wname = (obj?.get("title") as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" } ?: pname
                    val kind = (obj?.get("kind") as? JsonPrimitive)?.content?.takeIf { it.isNotBlank() && it != "null" } ?: "custom"
                    val desc = (obj?.get("subtitle") as? JsonPrimitive)?.content?.takeIf { it != "null" }.orEmpty()
                    PluginWidgetMetaDto(
                        pluginId = pid,
                        pluginName = pname,
                        widgetKey = wkey,
                        name = wname,
                        description = desc,
                        kind = kind,
                        source = "runtime",
                        hasPage = true,
                    )
                }
        }
        val raw = (rawCatalog as? String)?.takeIf { it.isNotBlank() } ?: return emptyList()
        val arr = runCatching { json.parseToJsonElement(raw) as? JsonArray }.getOrNull() ?: return emptyList()
        return arr.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val pid = (obj["pluginId"] as? JsonPrimitive ?: obj["plugin_id"] as? JsonPrimitive)?.content
                ?.takeIf { it.isNotBlank() && it != "null" } ?: return@mapNotNull null
            val pname = (obj["pluginName"] as? JsonPrimitive ?: obj["plugin_name"] as? JsonPrimitive)?.content
                ?.takeIf { it.isNotBlank() && it != "null" } ?: pid
            val wkey = (obj["widgetKey"] as? JsonPrimitive ?: obj["key"] as? JsonPrimitive)?.content
                ?.takeIf { it != "null" }.orEmpty()
            val wname = (obj["name"] as? JsonPrimitive ?: obj["title"] as? JsonPrimitive)?.content
                ?.takeIf { it.isNotBlank() && it != "null" } ?: pname
            val kind = (obj["kind"] as? JsonPrimitive)?.content?.takeIf { it != "null" } ?: "custom"
            val desc = (obj["description"] as? JsonPrimitive ?: obj["subtitle"] as? JsonPrimitive)?.content
                ?.takeIf { it != "null" }.orEmpty()
            PluginWidgetMetaDto(
                pluginId = pid,
                pluginName = pname,
                widgetKey = wkey,
                name = wname,
                description = desc,
                kind = kind,
                source = "runtime",
                hasPage = true,
            )
        }
    }

    private fun normalizeEpochSeconds(raw: Double): Double =
        if (raw > 1_000_000_000_000.0) raw / 1000.0 else raw

    /** 拉取单个已配置小组件的最新状态（优先融合运行态新鲜缓存与 `/api/v1/plugin/widgets/{id}`，404 时平滑回退旧仪表盘）。 */
    suspend fun syncWidgetData(context: Context, appWidgetId: Int): PluginDesktopWidgetConfig? = withContext(Dispatchers.IO) {
        val current = loadConfig(context, appWidgetId) ?: return@withContext null
        val repo = MoviePilotRepository(context.applicationContext)
        val nowStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

        when (current.kind) {
            "plugin_dashboard", "plugin_widget" -> {
                val effectiveKey = current.widgetKey.ifBlank { current.dashboardKey }
                val runtimeRaw = loadRuntimeSnapshotJson(context, current.pluginId, effectiveKey)
                val remoteWidgetRaw = runCatching {
                    repo.fetchPluginWidgetSnapshotJson(current.pluginId, effectiveKey)
                }.getOrNull()

                val runtimeParsed = runtimeRaw?.let(PluginWidgetPayloadParser::parseSnapshot)
                val remoteParsed = remoteWidgetRaw?.let(PluginWidgetPayloadParser::parseSnapshot)

                val chosenPair: Pair<String, ParsedPluginWidgetPayload>? = when {
                    runtimeParsed != null && remoteParsed != null -> {
                        if (normalizeEpochSeconds(runtimeParsed.updatedEpochSec) >= normalizeEpochSeconds(remoteParsed.updatedEpochSec)) {
                            runtimeRaw to runtimeParsed
                        } else {
                            remoteWidgetRaw to remoteParsed
                        }
                    }
                    runtimeParsed != null -> runtimeRaw to runtimeParsed
                    remoteParsed != null -> remoteWidgetRaw to remoteParsed
                    else -> null
                }

                if (chosenPair != null) {
                    val (chosenJson, chosenPayload) = chosenPair
                    val summaryLines = PluginWidgetPayloadParser.summarizeLines(chosenPayload)
                    val updated = current.copy(
                        dashboardName = chosenPayload.title.ifBlank { current.dashboardName },
                        subtitle = chosenPayload.subtitle.ifBlank { current.subtitle },
                        lines = if (summaryLines.isNotEmpty()) summaryLines else current.lines,
                        updatedAt = nowStr,
                        payloadJson = chosenJson,
                    )
                    saveConfig(context, updated)
                    return@withContext updated
                }

                // 404 或旧版后端回退至 `/api/v1/plugin/dashboard/{id}/{key}`
                val rawDashboard = runCatching {
                    repo.fetchPluginDashboardWidgetJson(current.pluginId, current.dashboardKey.ifBlank { effectiveKey })
                }.getOrNull()
                val extracted = if (!rawDashboard.isNullOrBlank()) {
                    extractDashboardSummaryLines(rawDashboard)
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
private val ActionPluginIdKey = ActionParameters.Key<String>("mp_act_plugin_id")
private val ActionWidgetKeyKey = ActionParameters.Key<String>("mp_act_widget_key")
private val ActionIdParamKey = ActionParameters.Key<String>("mp_act_action_id")

/** 驱动仍在运行的 Glance composition 重新读取已持久化的数据快照。 */
internal val PluginWidgetRevisionKey = longPreferencesKey("mp_plugin_widget_revision")

/** 保存刷新版本后请求 Glance 重绘，兼容配置保存、手动刷新与后台同步。 */
internal suspend fun updatePluginWidget(context: Context, glanceId: GlanceId) {
    updateAppWidgetState(context, glanceId) { preferences ->
        preferences[PluginWidgetRevisionKey] = (preferences[PluginWidgetRevisionKey] ?: 0L) + 1L
    }
    MoviePilotPluginGlanceWidget().update(context, glanceId)
}

/** 点击小组件右上角「↻」触发后台实时刷新。 */
class RefreshPluginWidgetAction : ActionCallback {
    /** 同步目标小组件的数据后通知当前 Glance 会话重读快照。 */
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val appWidgetId = parameters[WidgetIdParamKey]
            ?: runCatching { GlanceAppWidgetManager(context).getAppWidgetId(glanceId) }.getOrNull()
            ?: return
        PluginDesktopWidgetStore.syncWidgetData(context, appWidgetId)
        updatePluginWidget(context, glanceId)
    }
}

/** 自定义布局树中 `button(pluginAction)` 的动作派发回调，发送包内广播通知宿主插件。 */
class PluginWidgetCustomActionCallback : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val pluginId = parameters[ActionPluginIdKey].orEmpty()
        val widgetKey = parameters[ActionWidgetKeyKey].orEmpty()
        val actionId = parameters[ActionIdParamKey].orEmpty()
        if (pluginId.isBlank() || actionId.isBlank()) return
        val broadcast = Intent(PluginDesktopWidgetStore.ACTION_WIDGET_CUSTOM_CLICK).apply {
            setPackage(context.packageName)
            putExtra("plugin_id", pluginId)
            putExtra("widget_key", widgetKey)
            putExtra("action_id", actionId)
        }
        context.sendBroadcast(broadcast)
        updatePluginWidget(context, glanceId)
    }
}

/**
 * MoviePilot 插件桌面小组件（支持预设模板 `metrics` / `list` / `poster` / `nowPlaying` / `plugin_launch`
 * 与声明式 `PluginWidgetNode` 自定义布局树）：
 * - 自适应浅色/深色系统外观与 `22.dp` 圆角语义；
 * - 点击直达对应插件页面或派发自定义插件动作广播。
 */
class MoviePilotPluginGlanceWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(220.dp, 110.dp),
            DpSize(280.dp, 180.dp),
        ),
    )

    /** 按刷新版本读取快照，避免后台更新后仍显示当前会话捕获的旧配置。 */
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appWidgetId = runCatching { GlanceAppWidgetManager(context).getAppWidgetId(id) }
            .getOrDefault(AppWidgetManager.INVALID_APPWIDGET_ID)

        provideContent {
            val revision = currentState<Preferences>()[PluginWidgetRevisionKey]
            val config = remember(appWidgetId, revision) {
                if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    PluginDesktopWidgetStore.loadConfig(context, appWidgetId)
                } else {
                    null
                }
            }
            val parsedPayload = remember(config?.payloadJson, revision) {
                config?.payloadJson?.takeIf { it.isNotBlank() }?.let(PluginWidgetPayloadParser::parseSnapshot)
            }
            val palette = GlanceSemanticPalette.resolve(context, parsedPayload?.accentHex)
            PluginWidgetCardContent(
                context = context,
                appWidgetId = appWidgetId,
                config = config,
                payload = parsedPayload,
                palette = palette,
            )
        }
    }
}

@Composable
private fun PluginWidgetCardContent(
    context: Context,
    appWidgetId: Int,
    config: PluginDesktopWidgetConfig?,
    payload: ParsedPluginWidgetPayload?,
    palette: GlanceSemanticPalette,
) {
    val size = LocalSize.current
    val isSmall = size.width < 180.dp
    val isLarge = size.height >= 165.dp
    val sizeKey = when {
        isSmall -> "small"
        isLarge -> "large"
        else -> "medium"
    }

    val openIntent = remember(config, appWidgetId) {
        if (config == null) {
            Intent(context, PluginWidgetConfigureActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        } else if (config.kind == "overview" || config.pluginId.isBlank()) {
            Intent(Intent.ACTION_VIEW, Uri.parse("moviepilot://dashboard")).apply {
                component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        } else {
            val wKey = config.widgetKey.ifBlank { config.dashboardKey }
            val querySuffix = if (wKey.isNotBlank()) "&widgetKey=${Uri.encode(wKey)}" else ""
            val uri = Uri.parse(
                "moviepilot://plugin/${Uri.encode(config.pluginId)}?surface=${Uri.encode(config.targetSurface)}$querySuffix",
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
            .cornerRadius(GlanceSemanticPalette.CornerRadius)
            .background(ColorProvider(palette.cardBackground))
            .clickable(actionStartActivity(openIntent))
            .glancePadding(if (isSmall) 12.dp else 14.dp),
        verticalAlignment = GlanceAlignment.Vertical.Top,
    ) {
        if (config == null) {
            GlanceText(
                text = "MoviePilot 插件",
                style = TextStyle(
                    color = ColorProvider(palette.accent),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
            )
            GlanceSpacer(GlanceModifier.glanceHeight(6.dp))
            GlanceText(
                text = "点击选择要固定到桌面的插件卡片、自定义布局或插件直达入口",
                style = TextStyle(
                    color = ColorProvider(palette.textSecondary),
                    fontSize = 12.sp,
                ),
            )
            return@GlanceColumn
        }

        // 顶部标题栏 + 手动刷新
        GlanceRow(
            modifier = GlanceModifier.glanceFillMaxWidth(),
            verticalAlignment = GlanceAlignment.Vertical.CenterVertically,
        ) {
            val headerTitle = payload?.title?.takeIf { it.isNotBlank() }
                ?: config.dashboardName.takeIf { it.isNotBlank() }
                ?: config.pluginName.ifBlank { config.pluginId.ifBlank { "MoviePilot" } }
            GlanceColumn(modifier = GlanceModifier.defaultWeight()) {
                GlanceText(
                    text = headerTitle,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.textPrimary),
                        fontSize = if (isSmall) 13.sp else 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                val tagLine = when (config.kind) {
                    "plugin_launch" -> if (config.targetSurface == "config") "点击直达插件配置" else "点击直达插件页面"
                    "overview" -> config.badgeText.ifBlank { "实例概览" }
                    else -> buildString {
                        append(config.pluginName.ifBlank { "插件小组件" })
                        if (config.updatedAt.isNotBlank()) append(" · ${config.updatedAt}")
                    }
                }
                GlanceText(
                    text = tagLine,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.textSecondary),
                        fontSize = 10.5.sp,
                    ),
                )
            }

            if (!isSmall && appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                GlanceSpacer(GlanceModifier.glanceWidth(6.dp))
                GlanceText(
                    text = "↻",
                    style = TextStyle(
                        color = ColorProvider(palette.accent),
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    modifier = GlanceModifier
                        .cornerRadius(10.dp)
                        .background(ColorProvider(palette.surfaceSecondary))
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

        // 优先使用结构化插件小组件载荷（custom 布局树 / metrics / list / poster）
        if (payload != null) {
            val customRoot = if (payload.kind == "custom") payload.resolveLayout(sizeKey) else null
            if (customRoot != null) {
                RenderPluginCustomNode(
                    context = context,
                    node = customRoot,
                    pluginId = config.pluginId,
                    widgetKey = config.widgetKey.ifBlank { config.dashboardKey },
                    palette = palette,
                    depth = 0,
                )
                return@GlanceColumn
            }

            when (payload.kind) {
                "list" -> RenderPresetListPayload(payload = payload, isSmall = isSmall, isLarge = isLarge, palette = palette)
                "poster" -> RenderPresetPosterPayload(payload = payload, isSmall = isSmall, isLarge = isLarge, palette = palette)
                else -> RenderPresetMetricsPayload(payload = payload, isSmall = isSmall, isLarge = isLarge, palette = palette)
            }
            return@GlanceColumn
        }

        // 兼容插件直达与仪表盘文本摘要模式
        if (config.kind == "plugin_launch") {
            if (config.badgeText.isNotBlank()) {
                GlanceText(
                    text = config.badgeText,
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.success),
                        fontSize = 11.5.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
                GlanceSpacer(GlanceModifier.glanceHeight(4.dp))
            }
            if (!isSmall && config.subtitle.isNotBlank()) {
                GlanceText(
                    text = config.subtitle,
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(palette.textSecondary),
                        fontSize = 12.sp,
                    ),
                )
            }
        } else {
            val maxLinesToShow = when {
                isLarge -> 4
                isSmall -> 1
                else -> 2
            }
            val displayLines = config.lines.take(maxLinesToShow)
            if (displayLines.isEmpty()) {
                GlanceText(
                    text = "点击打开「${config.pluginName.ifBlank { config.pluginId }}」查看详情",
                    maxLines = 2,
                    style = TextStyle(
                        color = ColorProvider(palette.textSecondary),
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
                            color = ColorProvider(if (idx == 0) palette.textPrimary else palette.textSecondary),
                            fontSize = 12.sp,
                            fontWeight = if (idx == 0) FontWeight.Medium else FontWeight.Normal,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
private fun RenderPresetMetricsPayload(
    payload: ParsedPluginWidgetPayload,
    isSmall: Boolean,
    isLarge: Boolean,
    palette: GlanceSemanticPalette,
) {
    val cols = if (isSmall) 1 else if (payload.metrics.size == 3) 3 else 2
    val visible = payload.metrics.take(if (isSmall) 2 else if (isLarge) 6 else 4)
    if (visible.isEmpty() && payload.items.isEmpty()) {
        GlanceText(
            text = payload.subtitle.ifBlank { "暂无小组件指标数据" },
            maxLines = 2,
            style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 12.sp),
        )
        return
    }
    visible.chunked(cols).forEachIndexed { rIdx, row ->
        if (rIdx > 0) GlanceSpacer(GlanceModifier.glanceHeight(6.dp))
        GlanceRow(modifier = GlanceModifier.glanceFillMaxWidth()) {
            for (cIdx in 0 until cols) {
                if (cIdx > 0) GlanceSpacer(GlanceModifier.glanceWidth(6.dp))
                val item = row.getOrNull(cIdx)
                if (item != null) {
                    GlanceColumn(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .cornerRadius(12.dp)
                            .background(ColorProvider(palette.surfaceSecondary))
                            .glancePadding(horizontal = 8.dp, vertical = 6.dp),
                    ) {
                        GlanceText(
                            text = item.label,
                            maxLines = 1,
                            style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.5.sp),
                        )
                        GlanceText(
                            text = item.value,
                            maxLines = 1,
                            style = TextStyle(
                                color = ColorProvider(palette.toneColor(item.tone)),
                                fontSize = 14.sp,
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
    if (isLarge && payload.items.isNotEmpty()) {
        GlanceSpacer(GlanceModifier.glanceHeight(8.dp))
        RenderPresetListRows(items = payload.items.take(2), isSmall = false, palette = palette)
    }
}

@Composable
private fun RenderPresetListPayload(
    payload: ParsedPluginWidgetPayload,
    isSmall: Boolean,
    isLarge: Boolean,
    palette: GlanceSemanticPalette,
) {
    if (payload.items.isEmpty()) {
        RenderPresetMetricsPayload(payload, isSmall, isLarge, palette)
        return
    }
    val count = when {
        isSmall -> 2
        isLarge -> 4
        else -> 2
    }
    RenderPresetListRows(items = payload.items.take(count), isSmall = isSmall, palette = palette)
}

@Composable
private fun RenderPresetListRows(
    items: List<PluginWidgetListEntry>,
    isSmall: Boolean,
    palette: GlanceSemanticPalette,
) {
    items.forEachIndexed { idx, item ->
        if (idx > 0) GlanceSpacer(GlanceModifier.glanceHeight(5.dp))
        GlanceColumn(modifier = GlanceModifier.glanceFillMaxWidth()) {
            GlanceRow(
                modifier = GlanceModifier.glanceFillMaxWidth(),
                verticalAlignment = GlanceAlignment.Vertical.CenterVertically,
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
                val rightText = item.trailing.ifBlank {
                    item.progress?.let { "${(it * 100).toInt()}%" }.orEmpty()
                }
                if (rightText.isNotBlank()) {
                    GlanceText(
                        text = rightText,
                        maxLines = 1,
                        style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.5.sp),
                    )
                }
            }
            if (!isSmall && item.subtitle.isNotBlank()) {
                GlanceText(
                    text = item.subtitle,
                    maxLines = 1,
                    style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.5.sp),
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

@Composable
private fun RenderPresetPosterPayload(
    payload: ParsedPluginWidgetPayload,
    isSmall: Boolean,
    isLarge: Boolean,
    palette: GlanceSemanticPalette,
) {
    val bmp = remember(payload.artworkPath) {
        if (payload.artworkPath.isNotBlank()) NowPlayingWidgetStore.loadSampledArtwork(payload.artworkPath, 240) else null
    }
    GlanceRow(
        modifier = GlanceModifier.glanceFillMaxWidth(),
        verticalAlignment = GlanceAlignment.Vertical.CenterVertically,
    ) {
        if (bmp != null) {
            GlanceImage(
                provider = ImageProvider(bmp),
                contentDescription = payload.title,
                contentScale = ContentScale.Crop,
                modifier = GlanceModifier
                    .glanceSize(width = if (isSmall) 48.dp else 64.dp, height = if (isSmall) 64.dp else 80.dp)
                    .cornerRadius(12.dp),
            )
            GlanceSpacer(GlanceModifier.glanceWidth(10.dp))
        }
        GlanceColumn(modifier = GlanceModifier.defaultWeight()) {
            if (payload.subtitle.isNotBlank()) {
                GlanceText(
                    text = payload.subtitle,
                    maxLines = if (isLarge) 3 else 2,
                    style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 11.5.sp),
                )
            }
            payload.metrics.firstOrNull()?.let { firstMetric ->
                GlanceSpacer(GlanceModifier.glanceHeight(4.dp))
                GlanceText(
                    text = "${firstMetric.label}：${firstMetric.value}",
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.accent),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }
        }
    }
}

/** 递归渲染声明式 `PluginWidgetLayoutNode` Glance 节点树（严格控制每容器子节点数量 <= 8 以适配 RemoteViews）。 */
@Composable
private fun RenderPluginCustomNode(
    context: Context,
    node: PluginWidgetLayoutNode,
    pluginId: String,
    widgetKey: String,
    palette: GlanceSemanticPalette,
    depth: Int,
) {
    if (depth > PluginWidgetPayloadParser.MAX_DEPTH) return

    val containerMod = buildContainerModifier(node, palette)
    when (node.type) {
        "column" -> {
            val horiz = when (node.align) {
                "center" -> GlanceAlignment.Horizontal.CenterHorizontally
                "end" -> GlanceAlignment.Horizontal.End
                else -> GlanceAlignment.Horizontal.Start
            }
            GlanceColumn(
                modifier = containerMod,
                horizontalAlignment = horiz,
            ) {
                node.children.take(4).forEachIndexed { idx, child ->
                    if (idx > 0 && node.gap > 0f) {
                        GlanceSpacer(GlanceModifier.glanceHeight(node.gap.dp))
                    }
                    RenderPluginCustomNode(context, child, pluginId, widgetKey, palette, depth + 1)
                }
            }
        }

        "row" -> {
            val isSpaceBetween = node.align == "spaceBetween"
            val vert = when (node.align) {
                "start" -> GlanceAlignment.Vertical.Top
                "end" -> GlanceAlignment.Vertical.Bottom
                else -> GlanceAlignment.Vertical.CenterVertically
            }
            GlanceRow(
                modifier = if (isSpaceBetween) containerMod.glanceFillMaxWidth() else containerMod,
                verticalAlignment = vert,
            ) {
                node.children.take(4).forEachIndexed { idx, child ->
                    if (idx > 0) {
                        if (isSpaceBetween) {
                            GlanceSpacer(GlanceModifier.defaultWeight())
                        } else if (node.gap > 0f) {
                            GlanceSpacer(GlanceModifier.glanceWidth(node.gap.dp))
                        }
                    }
                    RenderPluginCustomNode(context, child, pluginId, widgetKey, palette, depth + 1)
                }
            }
        }

        "stack", "box" -> {
            GlanceBox(modifier = containerMod) {
                node.children.take(4).forEach { child ->
                    RenderPluginCustomNode(context, child, pluginId, widgetKey, palette, depth + 1)
                }
            }
        }

        "text" -> {
            val fontSize = when (node.size) {
                "xs" -> 10.5.sp
                "sm" -> 11.5.sp
                "lg" -> 15.sp
                "xl" -> 18.sp
                else -> 13.sp
            }
            val weight = when (node.weight) {
                "bold", "semibold" -> FontWeight.Bold
                "medium" -> FontWeight.Medium
                else -> FontWeight.Normal
            }
            GlanceText(
                text = node.text.ifBlank { node.label.ifBlank { node.valueText } },
                maxLines = node.maxLines,
                style = TextStyle(
                    color = ColorProvider(palette.toneColor(node.tone)),
                    fontSize = fontSize,
                    fontWeight = weight,
                ),
            )
        }

        "metric" -> {
            GlanceColumn(modifier = containerMod) {
                if (node.label.isNotBlank()) {
                    GlanceText(
                        text = node.label,
                        maxLines = 1,
                        style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.5.sp),
                    )
                }
                GlanceText(
                    text = node.valueText.ifBlank { node.text.ifBlank { "—" } },
                    maxLines = 1,
                    style = TextStyle(
                        color = ColorProvider(palette.toneColor(node.tone)),
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
                if (node.subValue.isNotBlank()) {
                    GlanceText(
                        text = node.subValue,
                        maxLines = 1,
                        style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.sp),
                    )
                }
            }
        }

        "progress" -> {
            val progress = (node.progressValue ?: 0f).coerceIn(0f, 1f)
            GlanceColumn(modifier = GlanceModifier.glanceFillMaxWidth()) {
                if (node.label.isNotBlank() || node.valueText.isNotBlank()) {
                    GlanceRow(modifier = GlanceModifier.glanceFillMaxWidth()) {
                        GlanceText(
                            text = node.label,
                            maxLines = 1,
                            modifier = GlanceModifier.defaultWeight(),
                            style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.5.sp),
                        )
                        if (node.valueText.isNotBlank()) {
                            GlanceText(
                                text = node.valueText,
                                maxLines = 1,
                                style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 10.5.sp),
                            )
                        }
                    }
                    GlanceSpacer(GlanceModifier.glanceHeight(2.dp))
                }
                LinearProgressIndicator(
                    progress = progress,
                    modifier = GlanceModifier
                        .glanceFillMaxWidth()
                        .glanceHeight(4.dp)
                        .cornerRadius(2.dp),
                    color = ColorProvider(palette.toneColor(node.tone).takeIf { it != palette.textPrimary } ?: palette.accent),
                    backgroundColor = ColorProvider(palette.divider),
                )
            }
        }

        "badge" -> {
            GlanceText(
                text = node.text.ifBlank { node.label },
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(palette.badgeForeground(node.tone)),
                    fontSize = 10.5.sp,
                    fontWeight = FontWeight.Medium,
                ),
                modifier = GlanceModifier
                    .cornerRadius(8.dp)
                    .background(ColorProvider(palette.badgeBackground(node.tone)))
                    .glancePadding(horizontal = 6.dp, vertical = 2.dp),
            )
        }

        "image" -> {
            val w = (node.width ?: 44f).dp
            val h = (node.height ?: 44f).dp
            val r = node.cornerRadius.dp
            val bmp = remember(node.url) {
                if (node.url.isNotBlank()) NowPlayingWidgetStore.loadSampledArtwork(node.url, 200) else null
            }
            if (bmp != null) {
                GlanceImage(
                    provider = ImageProvider(bmp),
                    contentDescription = node.label,
                    contentScale = ContentScale.Crop,
                    modifier = GlanceModifier.glanceSize(w, h).cornerRadius(r),
                )
            } else {
                GlanceBox(
                    modifier = GlanceModifier
                        .glanceSize(w, h)
                        .cornerRadius(r)
                        .background(ColorProvider(palette.surfaceSecondary)),
                    contentAlignment = GlanceAlignment.Center,
                ) {
                    GlanceText(
                        text = "▣",
                        style = TextStyle(color = ColorProvider(palette.textSecondary), fontSize = 12.sp),
                    )
                }
            }
        }

        "button" -> {
            val btnLabel = node.label.ifBlank { node.text.ifBlank { "执行" } }
            val action = node.action
            val bgColor = if (node.filled) {
                palette.toneColor(node.tone).takeIf { it != palette.textPrimary } ?: palette.accent
            } else {
                palette.badgeBackground(node.tone)
            }
            val fgColor = if (node.filled) Color.White else palette.badgeForeground(node.tone)

            val clickMod = when {
                action?.type == "pluginAction" && action.actionId.isNotBlank() -> {
                    GlanceModifier.clickable(
                        actionRunCallback<PluginWidgetCustomActionCallback>(
                            actionParametersOf(
                                ActionPluginIdKey to pluginId,
                                ActionWidgetKeyKey to widgetKey,
                                ActionIdParamKey to action.actionId,
                            ),
                        ),
                    )
                }
                action?.type == "openRoute" && action.route.isNotBlank() -> {
                    val uri = Uri.parse("moviepilot://open?path=${Uri.encode(action.route)}")
                    val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                        component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                    GlanceModifier.clickable(actionStartActivity(intent))
                }
                pluginId.isNotBlank() -> {
                    val surf = if (action?.surface == "config") "config" else "data"
                    val uri = Uri.parse("moviepilot://plugin/${Uri.encode(pluginId)}?surface=$surf")
                    val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                        component = ComponentName(context.packageName, "com.moviepilot.app.MainActivity")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                    GlanceModifier.clickable(actionStartActivity(intent))
                }
                else -> GlanceModifier
            }

            GlanceText(
                text = btnLabel,
                maxLines = 1,
                style = TextStyle(
                    color = ColorProvider(fgColor),
                    fontSize = 11.5.sp,
                    fontWeight = FontWeight.Bold,
                ),
                modifier = GlanceModifier
                    .cornerRadius(8.dp)
                    .background(ColorProvider(bgColor))
                    .then(clickMod)
                    .glancePadding(horizontal = 10.dp, vertical = 4.dp),
            )
        }

        "divider" -> {
            GlanceBox(
                modifier = GlanceModifier
                    .glanceFillMaxWidth()
                    .glanceHeight(1.dp)
                    .background(ColorProvider(palette.divider)),
            ) {}
        }

        "spacer" -> {
            GlanceSpacer(GlanceModifier.glanceHeight(4.dp))
        }
    }
}

private fun buildContainerModifier(
    node: PluginWidgetLayoutNode,
    palette: GlanceSemanticPalette,
): GlanceModifier {
    var mod: GlanceModifier = GlanceModifier
    if (node.width != null) mod = mod.glanceWidth(node.width.dp)
    if (node.height != null) mod = mod.glanceHeight(node.height.dp)
    if (node.tone.isNotBlank() && node.tone != "default") {
        mod = mod
            .cornerRadius(node.cornerRadius.dp)
            .background(ColorProvider(palette.badgeBackground(node.tone)))
    }
    if (node.padding > 0f) {
        mod = mod.glancePadding(node.padding.dp)
    }
    return mod
}

/** 自定义插件与声明式布局桌面小组件广播接收器。 */
class MoviePilotPluginWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MoviePilotPluginGlanceWidget()

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == PluginDesktopWidgetStore.ACTION_RUNTIME_UPDATED) {
            val targetPluginId = intent.getStringExtra("plugin_id").orEmpty()
            val pending = goAsync()
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val appContext = context.applicationContext
                    val manager = GlanceAppWidgetManager(appContext)
                    val configuredIds = PluginDesktopWidgetStore.listConfiguredIds(appContext)
                    configuredIds.forEach { wid ->
                        val cfg = PluginDesktopWidgetStore.loadConfig(appContext, wid) ?: return@forEach
                        if (targetPluginId.isBlank() || cfg.pluginId.equals(targetPluginId, ignoreCase = true)) {
                            val effectiveKey = cfg.widgetKey.ifBlank { cfg.dashboardKey }
                            val rtJson = PluginDesktopWidgetStore.loadRuntimeSnapshotJson(appContext, cfg.pluginId, effectiveKey)
                            val parsed = rtJson?.let(PluginWidgetPayloadParser::parseSnapshot)
                            if (rtJson != null && parsed != null) {
                                val nowStr = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
                                val summary = PluginWidgetPayloadParser.summarizeLines(parsed)
                                PluginDesktopWidgetStore.saveConfig(
                                    appContext,
                                    cfg.copy(
                                        dashboardName = parsed.title.ifBlank { cfg.dashboardName },
                                        subtitle = parsed.subtitle.ifBlank { cfg.subtitle },
                                        lines = if (summary.isNotEmpty()) summary else cfg.lines,
                                        updatedAt = nowStr,
                                        payloadJson = rtJson,
                                    ),
                                )
                            }
                            runCatching {
                                val glanceId = manager.getGlanceIdBy(wid)
                                updatePluginWidget(appContext, glanceId)
                            }
                        }
                    }
                } finally {
                    pending.finish()
                }
            }
            return
        }
        super.onReceive(context, intent)
    }

    /** 广播仅由 Glance 接管；网络同步交给 WorkManager，避免重复 goAsync/finish。 */
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        PluginWidgetUpdateWorker.enqueue(context, appWidgetIds)
    }

    /** 保留 Glance 自身清理流程，再删除对应的业务配置。 */
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        appWidgetIds.forEach { wid ->
            PluginDesktopWidgetStore.deleteConfig(context, wid)
        }
    }
}

/**
 * 桌面小组件可视化自定义配置页（添加小组件或长按小组件点击「重新配置」时拉起）：
 * 同时展示后端 `/api/v1/plugin/widgets/meta`（专属插件小组件 + 仪表盘兜底）、本机 `"rt_catalog"` 运行态小组件、
 * 插件快捷直达与实例概览。
 */
class PluginWidgetConfigureActivity : ComponentActivity() {
    /** 初始化添加或重新配置入口，缺失有效小组件 ID 时按取消处理。 */
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

/** 展示插件专属/运行态小组件、插件快捷入口和实例概览三种桌面配置方式。 */
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

    var selectedTab by remember { mutableIntStateOf(0) } // 0: 插件小组件, 1: 插件快捷直达, 2: 实例概览
    var searchQuery by remember { mutableStateOf("") }
    var launchSurface by remember { mutableStateOf("data") } // "data" | "config"
    var isLoading by remember { mutableStateOf(true) }
    var isSaving by remember { mutableStateOf(false) }
    var widgetMetas by remember { mutableStateOf<List<PluginWidgetMetaDto>>(emptyList()) }
    var installedPlugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }

    val authed = repository.session.value is SessionState.Authenticated

    LaunchedEffect(Unit) {
        val localRuntime = PluginDesktopWidgetStore.listRuntimeCatalog(context)
        if (authed) {
            val loadedPlugins = runCatching { repository.fetchPlugins(true) }.getOrDefault(emptyList())
            val remoteMetas = runCatching { repository.fetchPluginWidgetMetas() }.getOrDefault(emptyList())
            val mergedMap = LinkedHashMap<String, PluginWidgetMetaDto>()
            remoteMetas.forEach { m -> mergedMap["${m.pluginId.lowercase()}::${m.widgetKey}"] = m }
            localRuntime.forEach { m -> mergedMap["${m.pluginId.lowercase()}::${m.widgetKey}"] = m }
            installedPlugins = loadedPlugins
            widgetMetas = mergedMap.values.toList()
            if (widgetMetas.isEmpty() && loadedPlugins.isNotEmpty()) {
                selectedTab = 1
            }
        } else {
            widgetMetas = localRuntime
        }
        isLoading = false
    }

    /** 持久化选择并完成首次同步，通知 Glance 刷新后返回配置成功。 */
    fun commitSelection(initialConfig: PluginDesktopWidgetConfig) {
        if (isSaving) return
        isSaving = true
        scope.launch {
            PluginDesktopWidgetStore.saveConfig(context, initialConfig)
            PluginDesktopWidgetStore.syncWidgetData(context, appWidgetId)
            runCatching {
                val manager = GlanceAppWidgetManager(context)
                val glanceId = manager.getGlanceIdBy(appWidgetId)
                updatePluginWidget(context, glanceId)
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
                        text = "配置 MoviePilot 插件小组件",
                        color = colors.textPrimary,
                        fontSize = 20.sp,
                        fontWeight = ComposeFontWeight.Bold,
                    )
                    Text(
                        text = "支持插件专属卡片、声明式自定义布局、运行态实时组件与快捷入口",
                        color = colors.textSecondary,
                        fontSize = 12.5.sp,
                    )
                }
                IconButton(onClick = onCancel) {
                    Icon(Icons.Rounded.Close, contentDescription = "取消", tint = colors.textSecondary)
                }
            }

            ExpressivePillTabRow(
                tabs = listOf("插件数据卡", "插件直达", "实例概览"),
                selectedIndex = selectedTab,
                onSelect = { selectedTab = it },
                onTintedHeader = false,
            )

            Spacer(Modifier.height(10.dp))

            if (!authed && widgetMetas.isEmpty()) {
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
                                text = "登录后即可将任意已安装插件的数据卡片、自定义组件或快捷入口固定到桌面。",
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
                            if (widgetMetas.isEmpty()) {
                                item {
                                    CinematicPanel(padding = 20.dp, showsShadow = false) {
                                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(
                                                text = "当前暂无提供桌面数据卡片的已启用插件",
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
                                items(widgetMetas, key = { "${it.pluginId}_${it.widgetKey}" }) { meta ->
                                    val owner = pluginMap[meta.pluginId.lowercase()]
                                    val ownerName = owner?.name ?: meta.pluginName.ifBlank { meta.pluginId }
                                    val cardTitle = meta.name.ifBlank { ownerName }
                                    val kindBadge = when {
                                        meta.source == "runtime" -> "运行态实时"
                                        meta.kind == "custom" -> "自定义布局"
                                        meta.kind == "list" -> "进度列表"
                                        meta.kind == "poster" -> "海报横幅"
                                        meta.source == "dashboard" -> "仪表盘数据"
                                        else -> "指标网格"
                                    }
                                    CinematicPanel(
                                        padding = 14.dp,
                                        modifier = Modifier.clickable {
                                            commitSelection(
                                                PluginDesktopWidgetConfig(
                                                    appWidgetId = appWidgetId,
                                                    kind = "plugin_dashboard",
                                                    pluginId = meta.pluginId,
                                                    pluginName = ownerName,
                                                    dashboardKey = meta.widgetKey,
                                                    dashboardName = cardTitle,
                                                    targetSurface = "data",
                                                    subtitle = meta.description,
                                                    widgetKey = meta.widgetKey,
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
                                                    NativeAdaptiveBadge(kindBadge, tint = colors.accent)
                                                }
                                                Text(
                                                    text = meta.description.ifBlank { "来自插件：$ownerName · 桌面实时查看并点击直达插件" },
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
