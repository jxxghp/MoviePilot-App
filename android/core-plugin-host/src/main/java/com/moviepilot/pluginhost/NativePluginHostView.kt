package com.moviepilot.pluginhost

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.imePadding
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeCardListSkeleton
import com.moviepilot.designsystem.SkeletonCardStyle
import com.moviepilot.pluginhost.runtime.AndroidPluginWebViewPool
import com.moviepilot.pluginhost.runtime.LocalPluginShellWebView
import com.moviepilot.pluginhost.runtime.PluginRemoteDiskCache
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.net.URLEncoder

private fun JsonElement?.safeObj(): JsonObject? = this as? JsonObject
private fun JsonElement?.safeArr(): JsonArray? = this as? JsonArray
private fun JsonElement?.safePrim(): JsonPrimitive? = this as? JsonPrimitive
private fun JsonObject.safeStr(key: String): String? = this[key].safePrim()?.content?.takeIf { it != "null" }

/**
 * 清空受控隔离 Vue 模块联邦 WebView 的全部会话态（Cookie、localStorage/WebStorage 与磁盘缓存）。
 * 必须在用户主动退出登录或 401 令牌失效自动退登时调用，杜绝跨账号残留。
 */
fun clearIsolatedPluginWebViewSession(context: Context) {
    com.moviepilot.pluginhost.runtime.AndroidPluginCapsuleManager.resetForSessionChange(context)
    AndroidPluginWebViewPool.resetForSessionChange()
    PluginRemoteDiskCache.clearAll(context)
    runCatching {
        val cm = CookieManager.getInstance()
        cm.removeAllCookies(null)
        cm.flush()
    }
    runCatching {
        WebStorage.getInstance().deleteAllData()
    }
    val runOnMain = Runnable {
        runCatching {
            WebView(context.applicationContext).apply {
                clearCache(true)
                clearHistory()
                destroy()
            }
        }
    }
    if (Looper.myLooper() == Looper.getMainLooper()) {
        runOnMain.run()
    } else {
        Handler(Looper.getMainLooper()).post(runOnMain)
    }
}

/** 插件 Vue 模块联邦隔离 WebView 启动配置（1:1 对齐 iOS `VuePluginLaunchConfig`）。 */
data class VuePluginSessionPayload(
    val serverUrl: String,
    val authToken: String,
    val userId: Int = 1,
    val userName: String = "admin",
    val avatar: String = "",
    val isSuperuser: Boolean = true,
    val originCookies: List<String> = emptyList(),
)

/**
 * 动态插件表单原生渲染宿主（1:1 对齐 iOS `NativePluginFormView.swift` + 100% JsonNull 免疫）：
 * - 消费 Rust `planPluginForm` 规划树 + `analyzeCron` + `applyPluginPatch` 无损合并完整服务端模型；
 * - 支持 `VSwitch`/`VCheckbox`/`VCronField`/`VSelect`(单选与多选)/`VAutocomplete`/`VCombobox`/`VSlider`/`VAlert`/`VAceEditor`/`VTextarea`/`VTextField`/`VBtn`(同源动作调用)；
 * - 若插件声明 `render_mode == "vue"` 或存在自定义不支持组件，支持无缝切换至免登隔离 Vue 模块联邦 WebView。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NativePluginFormRenderer(
    pluginId: String,
    pluginName: String,
    documentJson: String,
    vueSession: VuePluginSessionPayload,
    onSaveFullModel: (String) -> Unit,
    onTriggerAction: (suspend (api: String, method: String, paramsJson: String?) -> Pair<Boolean, String>)? = null,
    onDirtyChanged: ((Boolean) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val json = remember { Json { ignoreUnknownKeys = true; isLenient = true } }
    val rawDocObj = remember(documentJson) {
        val parsed = runCatching { json.parseToJsonElement(documentJson).safeObj() }.getOrNull()
        // 自动解包 MoviePilot V3 `{success, message, data: {render_mode, conf, model}}` 信封
        if (parsed != null && !parsed.containsKey("conf") && !parsed.containsKey("page")) {
            parsed["data"].safeObj() ?: parsed
        } else {
            parsed
        }
    }
    val unwrappedDocumentJson = remember(rawDocObj, documentJson) {
        rawDocObj?.toString() ?: documentJson
    }
    val planJson = remember(unwrappedDocumentJson) {
        runCatching { RustCoreBridge.planPluginForm(unwrappedDocumentJson) }.getOrDefault("{}")
    }
    val planObj = remember(planJson) {
        runCatching { json.parseToJsonElement(planJson).safeObj() }.getOrNull()
    }
    val renderMode = rawDocObj?.safeStr("render_mode")
        ?: planObj?.safeStr("renderMode")
        ?: "vuetify"
    val originalModelJson = remember(planObj, rawDocObj) {
        planObj?.get("model")?.takeIf { it is JsonObject && it.isNotEmpty() }?.toString()
            ?: rawDocObj?.get("model")?.takeIf { it is JsonObject }?.toString()
            ?: "{}"
    }
    val fields = remember(planObj, rawDocObj) {
        val fromRust = planObj?.get("fields").safeArr()
        if (fromRust != null && fromRust.isNotEmpty()) {
            fromRust
        } else {
            val confArr = rawDocObj?.get("conf").safeArr()
                ?: rawDocObj?.get("page").safeArr()
                ?: JsonArray(emptyList())
            JsonArray(extractNullSafeFormFields(confArr))
        }
    }
    var actionFeedback by remember(documentJson) { mutableStateOf<Pair<Boolean, String>?>(null) }
    // Vue 模块联邦插件或无原生 Vuetify 表单字段时，直接无缝以隔离兼容网页模式打开，无需任何提示与二次点击
    if (renderMode.equals("vue", ignoreCase = true) || fields.isEmpty()) {
        IsolatedVuePluginWebView(
            pluginId = pluginId,
            session = vueSession,
            surface = VuePluginSurface.Config,
            modifier = modifier.fillMaxSize(),
        )
        return
    }

    val initialModel = remember(originalModelJson) {
        runCatching { json.parseToJsonElement(originalModelJson).safeObj() }.getOrNull() ?: JsonObject(emptyMap())
    }
    val draftValues = remember(documentJson) {
        mutableStateMapOf<String, String>().apply {
            initialModel.forEach { (k, v) ->
                put(k, if (v is JsonPrimitive) v.content.takeIf { it != "null" }.orEmpty() else v.toString())
            }
        }
    }
    fun updateField(k: String?, v: String) {
        if (k == null) return
        draftValues[k] = v
        onDirtyChanged?.invoke(true)
    }

    // 构造实时模型快照：每当用户修改开关或输入项时动态重算 v-if / v-show / show 表达式显隐
    val livePatchEntries = draftValues.entries.joinToString(",") { (k, v) ->
        val orig = initialModel[k]
        val origPrim = orig.safePrim()
        val jsonVal = when {
            v == "true" || v == "false" -> v
            (v.trim().startsWith("[") && v.trim().endsWith("]")) ||
                (v.trim().startsWith("{") && v.trim().endsWith("}")) -> v
            v.toLongOrNull() != null && origPrim != null && !origPrim.isString -> v
            else -> "\"${v.replace("\\", "\\\\").replace("\"", "\\\"")}\""
        }
        "\"$k\":$jsonVal"
    }
    val liveModelJson = remember(originalModelJson, livePatchEntries) {
        runCatching {
            RustCoreBridge.applyPluginPatch(originalModelJson, "{$livePatchEntries}")
        }.getOrDefault(originalModelJson)
    }
    val confConditionMap = remember(rawDocObj) {
        val confArr = rawDocObj?.get("conf").safeArr()
            ?: rawDocObj?.get("page").safeArr()
            ?: JsonArray(emptyList())
        extractFieldConditionMap(confArr)
    }
    val liveFields = remember(rawDocObj, liveModelJson, fields) {
        val rePlanned = runCatching {
            if (rawDocObj != null) {
                val liveModelObj = json.parseToJsonElement(liveModelJson).safeObj()
                if (liveModelObj != null) {
                    val nextDoc = rawDocObj.toMutableMap().apply { put("model", liveModelObj) }
                    val nextPlanStr = RustCoreBridge.planPluginForm(JsonObject(nextDoc).toString())
                    json.parseToJsonElement(nextPlanStr).safeObj()?.get("fields").safeArr()
                } else null
            } else null
        }.getOrNull()
        if (rePlanned != null && rePlanned.isNotEmpty()) rePlanned else fields
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = colors.textPrimary,
        unfocusedTextColor = colors.textPrimary,
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.fieldBorder,
        cursorColor = colors.accent,
        focusedPlaceholderColor = colors.textMuted,
        unfocusedPlaceholderColor = colors.textMuted,
    )

    Column(
        modifier = modifier
            .fillMaxWidth()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        actionFeedback?.let { (ok, msg) ->
            CinematicPanel(padding = 12.dp, showsShadow = false) {
                Text(msg, color = if (ok) colors.success else colors.warning, fontSize = 13.sp)
            }
        }

        liveFields.forEach { el ->
            val field = el.safeObj() ?: return@forEach
            val component = field.safeStr("component") ?: return@forEach
            val key = field.safeStr("modelKey")
            val label = field.safeStr("label").orEmpty()
            val hint = field.safeStr("hint").orEmpty()
            val text = field.safeStr("text").orEmpty()
            val rawProps = field["rawProps"].safeObj()
            val showExpr = field.safeStr("showExpr")
                ?: field.safeStr("show")
                ?: field.safeStr("vIf")
                ?: field.safeStr("vShow")
                ?: field.safeStr("condition")
                ?: rawProps?.safeStr("show")
                ?: rawProps?.safeStr("v-show")
                ?: rawProps?.safeStr("v-if")
                ?: key?.let { confConditionMap[it] }
            val exprVisible = if (!showExpr.isNullOrBlank()) {
                RustCoreBridge.evalFormExpression(showExpr, liveModelJson)
            } else {
                true
            }
            val visible = (field["visible"].safePrim()?.booleanOrNull ?: true) && exprVisible
            if (!visible) return@forEach

            when (component) {
                "VSwitch", "VCheckbox" -> {
                    val checked = draftValues[key]?.equals("true", ignoreCase = true) == true
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(label.ifBlank { key ?: "开关" }, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                if (hint.isNotBlank()) {
                                    Text(hint, color = colors.textSecondary, fontSize = 12.sp)
                                }
                            }
                            Switch(
                                checked = checked,
                                onCheckedChange = { updateField(key, it.toString()) },
                                colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                            )
                        }
                    }
                }

                "VCronField" -> {
                    val expr = draftValues[key].orEmpty()
                    val summary = remember(expr) { RustCoreBridge.analyzeCron(expr) }
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                                Text(label.ifBlank { "执行周期 (Cron)" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                NativeAdaptiveBadge(
                                    text = if (summary.isValidFiveField) "5 字段有效" else "自定义方言",
                                    tint = if (summary.isValidFiveField) colors.success else colors.warning,
                                )
                            }
                            OutlinedTextField(
                                value = expr,
                                onValueChange = { updateField(key, it) },
                                placeholder = { Text("例如 */15 * * * *") },
                                singleLine = true,
                                colors = fieldColors,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Text(summary.descriptionZh, color = colors.accent, fontSize = 12.sp)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                listOf("*/15 * * * *" to "每15分", "0 */2 * * *" to "每2小时", "0 9 * * *" to "每天9点", "0 0 last * *" to "月末").forEach { (preset, tag) ->
                                    NativeAdaptivePill(
                                        title = tag,
                                        selected = expr.trim() == preset,
                                        onClick = { updateField(key, preset) },
                                    )
                                }
                            }
                        }
                    }
                }

                "VSelect", "VAutocomplete", "VCombobox" -> {
                    val items = field["items"].safeArr() ?: JsonArray(emptyList())
                    val isMultiple = field["multiple"].safePrim()?.booleanOrNull == true ||
                        (draftValues[key]?.trim()?.startsWith("[") == true)
                    val current = draftValues[key].orEmpty()
                    val selectedSet = remember(current, isMultiple) {
                        if (isMultiple) {
                            runCatching {
                                json.parseToJsonElement(current).safeArr()
                                    ?.mapNotNull { it.safePrim()?.content }
                                    ?.toSet()
                            }.getOrNull() ?: emptySet()
                        } else {
                            setOf(current)
                        }
                    }
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(label.ifBlank { key ?: "选择器" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                items.forEach { itEl ->
                                    val obj = itEl.safeObj()
                                    val t = obj?.safeStr("title") ?: itEl.safePrim()?.content.orEmpty()
                                    val v = obj?.safeStr("value") ?: t
                                    val isSel = v in selectedSet
                                    NativeAdaptivePill(
                                        title = t,
                                        selected = isSel,
                                        onClick = {
                                            if (isMultiple) {
                                                val next = if (isSel) selectedSet - v else selectedSet + v
                                                val encoded = next.joinToString(",") { "\"${it.replace("\"", "\\\"")}\"" }
                                                updateField(key, "[$encoded]")
                                            } else {
                                                updateField(key, v)
                                            }
                                        },
                                    )
                                }
                            }
                            if (component == "VCombobox") {
                                OutlinedTextField(
                                    value = current,
                                    onValueChange = { updateField(key, it) },
                                    placeholder = { Text("可直接输入自定义值") },
                                    singleLine = true,
                                    colors = fieldColors,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }
                }

                "VSlider", "VRangeSlider" -> {
                    val v = draftValues[key]?.toFloatOrNull() ?: 50f
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Column {
                            Text("${label.ifBlank { key ?: "数值" }}：${v.toInt()}", color = colors.textPrimary, fontSize = 14.sp)
                            Slider(
                                value = v.coerceIn(0f, 100f),
                                valueRange = 0f..100f,
                                onValueChange = { updateField(key, it.toInt().toString()) },
                            )
                        }
                    }
                }

                "VBtn" -> {
                    val api = field.safeStr("api")
                    val method = field.safeStr("method") ?: "POST"
                    Button(
                        onClick = {
                            if (!api.isNullOrBlank() && onTriggerAction != null) {
                                scope.launch {
                                    actionFeedback = onTriggerAction(api, method, null)
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.chipFill, contentColor = colors.textPrimary),
                        shape = RoundedCornerShape(16.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(text.ifBlank { label.ifBlank { "执行操作" } }, fontWeight = FontWeight.SemiBold)
                    }
                }

                "VAlert" -> {
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Text(text = text.ifBlank { label }, color = colors.info, fontSize = 13.sp)
                    }
                }

                "VAceEditor", "VTextarea" -> {
                    val value = draftValues[key].orEmpty()
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(label.ifBlank { key ?: "脚本 / 文本" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            OutlinedTextField(
                                value = value,
                                onValueChange = { updateField(key, it) },
                                minLines = 3,
                                colors = fieldColors,
                                modifier = Modifier.fillMaxWidth(),
                                textStyle = androidx.compose.ui.text.TextStyle(
                                    fontFamily = if (component == "VAceEditor") FontFamily.Monospace else FontFamily.Default,
                                    color = colors.textPrimary,
                                ),
                            )
                        }
                    }
                }

                "VTextField" -> {
                    val value = draftValues[key].orEmpty()
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(label.ifBlank { key ?: "输入项" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                            OutlinedTextField(
                                value = value,
                                onValueChange = { updateField(key, it) },
                                singleLine = true,
                                placeholder = { Text(hint) },
                                colors = fieldColors,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }

                else -> {
                    if (text.isNotBlank() || label.isNotBlank()) {
                        CinematicPanel(padding = 12.dp, showsShadow = false) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                                Text(text.ifBlank { label }, color = colors.textPrimary, fontSize = 14.sp)
                                NativeAdaptiveBadge(component)
                            }
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(6.dp))
        Button(
            onClick = {
                val patchEntries = draftValues.entries.joinToString(",") { (k, v) ->
                    val orig = initialModel[k]
                    val origPrim = orig.safePrim()
                    val jsonVal = when {
                        v == "true" || v == "false" -> v
                        (v.trim().startsWith("[") && v.trim().endsWith("]")) ||
                            (v.trim().startsWith("{") && v.trim().endsWith("}")) -> v
                        v.toLongOrNull() != null && origPrim != null && !origPrim.isString -> v
                        else -> "\"${v.replace("\\", "\\\\").replace("\"", "\\\"")}\""
                    }
                    "\"$k\":$jsonVal"
                }
                val merged = runCatching {
                    RustCoreBridge.applyPluginPatch(originalModelJson, "{$patchEntries}")
                }.getOrDefault(originalModelJson)
                onDirtyChanged?.invoke(false)
                onSaveFullModel(merged)
            },
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
            shape = RoundedCornerShape(24.dp),
            modifier = Modifier.fillMaxWidth().height(50.dp),
        ) {
            Text("保存插件配置", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * 原生插件动态数据页与仪表盘小组件渲染器（1:1 复刻 iOS `NativePluginDataPageView.swift`）：
 * - 支持递归原生渲染 Vuetify JSON 树（`VApexChart`/`VTable`/`VCard`/`VRow`/`VCol`/`VChip`/`VAlert`/`VImg`/`VBtn` 动作按钮）；
 * - 当后端声明 `render_mode == "vue"` 时，自动切换为免登隔离 Vue 模块联邦 WebView。
 */
@Composable
fun NativePluginDataPageView(
    rawPageJson: String,
    resolveImageUrl: (String?) -> String?,
    scrollable: Boolean = true,
    pluginId: String = "",
    vueSession: VuePluginSessionPayload? = null,
    onTriggerAction: (suspend (api: String, method: String, paramsJson: String?) -> Pair<Boolean, String>)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val json = remember { Json { ignoreUnknownKeys = true; isLenient = true } }
    var actionFeedback by remember(rawPageJson) { mutableStateOf<Pair<Boolean, String>?>(null) }

    val parsed = remember(rawPageJson) {
        runCatching {
            val root = json.parseToJsonElement(rawPageJson)
            val data = root.safeObj()?.get("data") ?: root
            val renderMode = root.safeObj()?.safeStr("render_mode")
                ?: data.safeObj()?.safeStr("render_mode")
                ?: "vuetify"
            val arr = when (data) {
                is JsonArray -> data
                is JsonObject -> data["page"].safeArr()
                    ?: data["elements"].safeArr()
                    ?: data["attrs"].safeObj()?.get("elements").safeArr()
                    ?: JsonArray(listOf(data))
                else -> JsonArray(emptyList())
            }
            renderMode to arr
        }.getOrDefault("vuetify" to JsonArray(emptyList()))
    }

    val renderMode = parsed.first
    val nodes = parsed.second

    if (renderMode.equals("vue", ignoreCase = true) && vueSession != null && pluginId.isNotBlank()) {
        IsolatedVuePluginWebView(
            pluginId = pluginId,
            session = vueSession,
            surface = VuePluginSurface.DataPage,
            modifier = modifier.fillMaxSize(),
        )
        return
    }

    val colModifier = if (scrollable) {
        modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 10.dp)
    } else {
        modifier.fillMaxWidth()
    }

    Column(modifier = colModifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        actionFeedback?.let { (ok, msg) ->
            CinematicPanel(padding = 12.dp, showsShadow = false) {
                Text(msg, color = if (ok) colors.success else colors.warning, fontSize = 13.sp)
            }
        }
        if (nodes.isEmpty()) {
            CinematicPanel(padding = 16.dp, showsShadow = false) {
                Text("暂无插件数据内容", color = colors.textSecondary, fontSize = 14.sp)
            }
        } else {
            nodes.forEach { el ->
                RenderVuetifyNode(
                    element = el,
                    resolveImageUrl = resolveImageUrl,
                    onInvokeApi = { api, method, params ->
                        if (onTriggerAction != null) {
                            scope.launch {
                                actionFeedback = onTriggerAction(api, method, params)
                            }
                        }
                    },
                )
            }
        }
        if (scrollable) Spacer(Modifier.height(24.dp))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RenderVuetifyNode(
    element: JsonElement,
    resolveImageUrl: (String?) -> String?,
    onInvokeApi: (api: String, method: String, paramsJson: String?) -> Unit = { _, _, _ -> },
) {
    val colors = LocalMoviePilotColors.current
    val obj = element.safeObj() ?: return
    val comp = obj.safeStr("component") ?: return
    val compLower = comp.lowercase()
    if (compLower in setOf("style", "script", "link", "meta", "vdialogclosebtn")) return
    val props = obj["props"].safeObj() ?: JsonObject(emptyMap())
    val events = obj["events"].safeObj()
    val children = obj["content"].safeArr() ?: JsonArray(emptyList())
    val ownText = obj.safeStr("text") ?: props.safeStr("text") ?: props.safeStr("title")

    when (comp) {
        "VApexChart", "VChart" -> RenderApexChart(props)

        "VBtn" -> {
            val clickEv = events?.get("click").safeObj()
            val api = clickEv?.safeStr("api") ?: props.safeStr("api")
            val method = clickEv?.safeStr("method") ?: props.safeStr("method") ?: "GET"
            val params = clickEv?.get("params")?.toString()
            val txt = ownText ?: collectAllText(children).ifBlank { "执行" }
            Button(
                onClick = { if (!api.isNullOrBlank()) onInvokeApi(api, method, params) },
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent.copy(alpha = 0.24f), contentColor = colors.textPrimary),
                shape = CircleShape,
            ) {
                Text(txt, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        "VCard" -> {
            CinematicPanel(padding = 14.dp, cornerRadius = 20.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    val cardTitle = props.safeStr("title")
                    val cardSub = props.safeStr("subtitle")
                    if (!cardTitle.isNullOrBlank()) {
                        Text(cardTitle, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                    if (!cardSub.isNullOrBlank()) {
                        Text(cardSub, color = colors.textSecondary, fontSize = 12.sp)
                    }
                    children.forEach { RenderVuetifyNode(it, resolveImageUrl, onInvokeApi) }
                }
            }
        }

        "VRow" -> {
            val colChildren = children.mapNotNull { it.safeObj() }.filter { it.safeStr("component") == "VCol" }
            if (colChildren.isEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    children.forEach { RenderVuetifyNode(it, resolveImageUrl, onInvokeApi) }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    var i = 0
                    while (i < colChildren.size) {
                        val cur = colChildren[i]
                        val curRaw = cur.toString()
                        val curCols = cur["props"].safeObj()?.get("cols")?.safePrim()?.intOrNull ?: 12
                        val isFullWidth = curCols >= 12 || curRaw.contains("\"VApexChart\"") || curRaw.contains("\"VChart\"") || curRaw.contains("\"VTable\"")
                        val next = colChildren.getOrNull(i + 1)
                        val nextFull = next == null || run {
                            val nr = next.toString()
                            val nc = next["props"].safeObj()?.get("cols")?.safePrim()?.intOrNull ?: 12
                            nc >= 12 || nr.contains("\"VApexChart\"") || nr.contains("\"VChart\"") || nr.contains("\"VTable\"")
                        }
                        if (!isFullWidth && !nextFull) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Box(modifier = Modifier.weight(1f)) { RenderVuetifyNode(cur, resolveImageUrl, onInvokeApi) }
                                Box(modifier = Modifier.weight(1f)) { RenderVuetifyNode(next!!, resolveImageUrl, onInvokeApi) }
                            }
                            i += 2
                        } else {
                            RenderVuetifyNode(cur, resolveImageUrl, onInvokeApi)
                            i += 1
                        }
                    }
                }
            }
        }

        "VCol", "VCardText", "VCardItem", "VContainer", "VSheet", "div" -> {
            val css = props.safeStr("class").orEmpty()
            if (css.contains("d-flex") && !css.contains("flex-column") && children.size in 2..4 && !obj.toString().contains("VApexChart")) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (!ownText.isNullOrBlank()) {
                        Text(ownText, color = colors.textPrimary, fontSize = 14.sp)
                    }
                    children.forEach { RenderVuetifyNode(it, resolveImageUrl, onInvokeApi) }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (!ownText.isNullOrBlank()) {
                        Text(ownText, color = colors.textPrimary, fontSize = 14.sp)
                    }
                    children.forEach { RenderVuetifyNode(it, resolveImageUrl, onInvokeApi) }
                }
            }
        }

        "VCardTitle" -> {
            val txt = ownText ?: collectAllText(children)
            if (txt.isNotBlank()) Text(txt, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }

        "VCardSubtitle" -> {
            val txt = ownText ?: collectAllText(children)
            if (txt.isNotBlank()) Text(txt, color = colors.textSecondary, fontSize = 12.sp)
        }

        "VChip" -> {
            val txt = ownText ?: collectAllText(children)
            if (txt.isNotBlank()) {
                val colorName = props.safeStr("color").orEmpty().lowercase()
                val tint = when {
                    colorName.contains("success") || colorName.contains("green") -> colors.success
                    colorName.contains("error") || colorName.contains("red") -> colors.danger
                    colorName.contains("warning") || colorName.contains("orange") -> colors.warning
                    colorName.contains("info") || colorName.contains("blue") -> colors.info
                    else -> colors.accent
                }
                NativeAdaptiveBadge(txt, tint = tint)
            }
        }

        "VAlert" -> {
            val txt = ownText ?: collectAllText(children)
            if (txt.isNotBlank()) {
                CinematicPanel(padding = 12.dp, showsShadow = false) {
                    Text(txt, color = colors.info, fontSize = 13.sp, lineHeight = 19.sp)
                }
            }
        }

        "VImg" -> {
            val rawSrc = props.safeStr("src")
            val resolved = resolveImageUrl(rawSrc)
            if (!resolved.isNullOrBlank() && (rawSrc.orEmpty().startsWith("http://") || rawSrc.orEmpty().startsWith("https://"))) {
                AsyncImage(
                    model = resolved,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().height(148.dp).clip(RoundedCornerShape(14.dp)),
                )
            }
        }

        "VAvatar" -> {
            val imgSrc = children.firstOrNull()?.safeObj()?.get("props")?.safeObj()?.safeStr("src")
            Box(
                modifier = Modifier.size(38.dp).clip(CircleShape).background(colors.chipFill),
                contentAlignment = Alignment.Center,
            ) {
                val resolved = resolveImageUrl(imgSrc)
                if (!resolved.isNullOrBlank()) {
                    AsyncImage(model = resolved, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                }
            }
        }

        "VTable" -> RenderVuetifyTable(children)
        "VDivider" -> HorizontalDivider(color = colors.divider)

        "span", "p", "a", "h1", "h2", "h3", "h4", "h5", "h6" -> {
            val txt = ownText ?: collectAllText(children)
            if (txt.isNotBlank()) {
                val css = props.safeStr("class").orEmpty()
                val isBig = css.contains("text-h5") || css.contains("text-h6") || comp in listOf("h1", "h2", "h3", "h4")
                val isMuted = css.contains("text-caption") || css.contains("text-medium-emphasis")
                Text(
                    text = txt,
                    color = if (comp == "a") colors.accent else if (isMuted) colors.textSecondary else colors.textPrimary,
                    fontSize = if (isBig) 20.sp else if (isMuted) 12.sp else 14.sp,
                    fontWeight = if (isBig) FontWeight.ExtraBold else FontWeight.Medium,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        else -> {
            if (!ownText.isNullOrBlank()) {
                Text(ownText, color = colors.textPrimary, fontSize = 14.sp)
            }
            children.forEach { RenderVuetifyNode(it, resolveImageUrl, onInvokeApi) }
        }
    }
}

@Composable
private fun RenderApexChart(props: JsonObject) {
    val colors = LocalMoviePilotColors.current
    val options = props["options"].safeObj() ?: JsonObject(emptyMap())
    val title = options["title"].safeObj()?.safeStr("text") ?: props.safeStr("title") ?: "数据统计"
    val chartType = (options["chart"].safeObj()?.safeStr("type") ?: props.safeStr("type") ?: "donut").lowercase()
    val labels = options["labels"].safeArr()?.mapNotNull { it.safePrim()?.content?.takeIf { s -> s != "null" } }.orEmpty()
    val xCategories = options["xaxis"].safeObj()?.get("categories").safeArr()
        ?.mapNotNull { it.safePrim()?.content?.takeIf { s -> s != "null" } }
        .orEmpty()
        .ifEmpty { labels }
    val rawSeries = props["series"].safeArr() ?: JsonArray(emptyList())
    val palette = listOf(
        Color(0xFF8B6EFF),
        Color(0xFFE95C96),
        Color(0xFF2DC98A),
        Color(0xFF42A5F5),
        Color(0xFFFFB74D),
        Color(0xFF26C6DA),
    )

    val isRadial = chartType in setOf("donut", "pie", "radialbar")

    CinematicPanel(padding = 16.dp, cornerRadius = 20.dp, showsShadow = false) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            if (isRadial) {
                val values = rawSeries.mapNotNull { el ->
                    el.safePrim()?.doubleOrNull
                        ?: el.safeObj()?.get("data").safeArr()?.sumOf { it.safePrim()?.doubleOrNull ?: 0.0 }
                }
                val total = values.sum()
                if (values.isEmpty() || total <= 0.0) {
                    Text("暂无图表数据", color = colors.textMuted, fontSize = 13.sp)
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        Box(modifier = Modifier.size(126.dp), contentAlignment = Alignment.Center) {
                            Canvas(modifier = Modifier.fillMaxSize()) {
                                val strokeW = 19.dp.toPx()
                                val inset = strokeW / 2f
                                var startAngle = -90f
                                values.forEachIndexed { idx, v ->
                                    val sweep = ((v / total) * 360.0).toFloat()
                                    drawArc(
                                        color = palette[idx % palette.size],
                                        startAngle = startAngle,
                                        sweepAngle = sweep,
                                        useCenter = false,
                                        topLeft = Offset(inset, inset),
                                        size = Size(size.width - strokeW, size.height - strokeW),
                                        style = Stroke(width = strokeW, cap = StrokeCap.Butt),
                                    )
                                    startAngle += sweep
                                }
                            }
                            Text(
                                text = if (total >= 100) String.format("%.0f", total) else String.format("%.1f", total),
                                color = colors.textPrimary,
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            values.forEachIndexed { idx, v ->
                                val lbl = labels.getOrElse(idx) { "项 ${idx + 1}" }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.weight(1f)) {
                                        Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(palette[idx % palette.size]))
                                        Text(lbl, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    Text(
                                        text = if (v % 1.0 == 0.0) v.toInt().toString() else String.format("%.1f", v),
                                        color = colors.textPrimary,
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                // 折线图 / 面积图 / 柱状图原生 Canvas 绘制
                val parsedSeries: List<Pair<String, List<Double>>> = remember(rawSeries, title) {
                    fun extractPoint(p: JsonElement): Double? = when (p) {
                        is JsonPrimitive -> p.doubleOrNull
                        is JsonObject -> p["y"]?.safePrim()?.doubleOrNull ?: p["value"]?.safePrim()?.doubleOrNull
                        is JsonArray -> p.getOrNull(1)?.safePrim()?.doubleOrNull ?: p.firstOrNull()?.safePrim()?.doubleOrNull
                    }
                    val objSeries = rawSeries.mapIndexedNotNull { idx, el ->
                        val so = el.safeObj() ?: return@mapIndexedNotNull null
                        val sName = so.safeStr("name") ?: "系列 ${idx + 1}"
                        val pts = so["data"].safeArr()?.mapNotNull { extractPoint(it) }.orEmpty()
                        if (pts.isEmpty()) null else sName to pts
                    }
                    if (objSeries.isNotEmpty()) {
                        objSeries
                    } else {
                        val flatPts = rawSeries.mapNotNull { extractPoint(it) }
                        if (flatPts.isNotEmpty()) listOf(title to flatPts) else emptyList()
                    }
                }
                val maxVal = parsedSeries.flatMap { it.second }.maxOrNull()?.takeIf { it > 0.0 } ?: 0.0
                if (parsedSeries.isEmpty() || maxVal <= 0.0) {
                    Text("暂无图表数据", color = colors.textMuted, fontSize = 13.sp)
                } else {
                    val isBar = chartType == "bar" || chartType == "column"
                    if (parsedSeries.size > 1) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            parsedSeries.forEachIndexed { sIdx, (sName, _) ->
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(palette[sIdx % palette.size]))
                                    Text(sName, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1)
                                }
                            }
                        }
                    }
                    Canvas(modifier = Modifier.fillMaxWidth().height(152.dp)) {
                        val padTop = 8.dp.toPx()
                        val padBottom = 10.dp.toPx()
                        val usableH = (size.height - padTop - padBottom).coerceAtLeast(1f)
                        val gridColor = colors.divider
                        for (g in 0..3) {
                            val gy = padTop + usableH * (g / 3f)
                            drawLine(
                                color = gridColor,
                                start = Offset(0f, gy),
                                end = Offset(size.width, gy),
                                strokeWidth = 1.dp.toPx(),
                            )
                        }
                        if (isBar) {
                            val primaryPts = parsedSeries.first().second
                            val count = primaryPts.size.coerceAtLeast(1)
                            val slotW = size.width / count
                            val groupCount = parsedSeries.size.coerceAtLeast(1)
                            val barW = ((slotW * 0.68f) / groupCount).coerceAtMost(28.dp.toPx())
                            parsedSeries.forEachIndexed { sIdx, (_, pts) ->
                                val barColor = palette[sIdx % palette.size]
                                pts.forEachIndexed { pIdx, v ->
                                    if (pIdx >= count) return@forEachIndexed
                                    val ratio = (v / maxVal).coerceIn(0.0, 1.0).toFloat()
                                    val bh = (usableH * ratio).coerceAtLeast(2.dp.toPx())
                                    val groupStart = pIdx * slotW + (slotW - barW * groupCount) / 2f
                                    val bx = groupStart + sIdx * barW
                                    val by = padTop + usableH - bh
                                    drawRoundRect(
                                        color = barColor,
                                        topLeft = Offset(bx, by),
                                        size = Size((barW - 2.dp.toPx()).coerceAtLeast(2f), bh),
                                        cornerRadius = CornerRadius(4.dp.toPx(), 4.dp.toPx()),
                                    )
                                }
                            }
                        } else {
                            parsedSeries.forEachIndexed { sIdx, (_, pts) ->
                                if (pts.isEmpty()) return@forEachIndexed
                                val lineColor = palette[sIdx % palette.size]
                                val stepX = if (pts.size > 1) size.width / (pts.size - 1) else 0f
                                val coords = pts.mapIndexed { idx, v ->
                                    val x = if (pts.size > 1) idx * stepX else size.width / 2f
                                    val y = padTop + usableH * (1f - (v / maxVal).coerceIn(0.0, 1.0).toFloat())
                                    Offset(x, y)
                                }
                                if (coords.size >= 2) {
                                    val areaPath = Path().apply {
                                        moveTo(coords.first().x, padTop + usableH)
                                        coords.forEach { lineTo(it.x, it.y) }
                                        lineTo(coords.last().x, padTop + usableH)
                                        close()
                                    }
                                    drawPath(
                                        path = areaPath,
                                        brush = Brush.verticalGradient(
                                            colors = listOf(lineColor.copy(alpha = 0.28f), lineColor.copy(alpha = 0.01f)),
                                            startY = padTop,
                                            endY = padTop + usableH,
                                        ),
                                    )
                                    val strokePath = Path().apply {
                                        moveTo(coords.first().x, coords.first().y)
                                        coords.drop(1).forEach { lineTo(it.x, it.y) }
                                    }
                                    drawPath(
                                        path = strokePath,
                                        color = lineColor,
                                        style = Stroke(width = 2.6.dp.toPx(), cap = StrokeCap.Round),
                                    )
                                }
                                coords.forEach { pt ->
                                    drawCircle(color = lineColor, radius = 3.2.dp.toPx(), center = pt)
                                }
                            }
                        }
                    }
                    if (xCategories.isNotEmpty()) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(xCategories.first(), color = colors.textMuted, fontSize = 11.sp, maxLines = 1)
                            if (xCategories.size >= 3) {
                                Text(xCategories[xCategories.size / 2], color = colors.textMuted, fontSize = 11.sp, maxLines = 1)
                            }
                            if (xCategories.size >= 2) {
                                Text(xCategories.last(), color = colors.textMuted, fontSize = 11.sp, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RenderVuetifyTable(children: JsonArray) {
    val colors = LocalMoviePilotColors.current
    val rows = remember(children) {
        val out = mutableListOf<List<String>>()
        fun extractRows(arr: JsonArray) {
            arr.forEach { el ->
                val o = el.safeObj() ?: return@forEach
                val c = o.safeStr("component").orEmpty().lowercase()
                val ch = o["content"].safeArr() ?: JsonArray(emptyList())
                if (c == "tr") {
                    val cells = ch.mapNotNull { cell ->
                        val co = cell.safeObj() ?: return@mapNotNull null
                        co.safeStr("text") ?: collectAllText(co["content"].safeArr() ?: JsonArray(emptyList()))
                    }
                    if (cells.isNotEmpty()) out += cells
                } else {
                    extractRows(ch)
                }
            }
        }
        extractRows(children)
        out
    }
    if (rows.isEmpty()) return
    CinematicPanel(padding = 12.dp, cornerRadius = 18.dp, showsShadow = false) {
        Column(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            rows.take(15).forEachIndexed { rIdx, cells ->
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.padding(vertical = 4.dp)) {
                    cells.take(6).forEach { cell ->
                        Text(
                            text = cell,
                            color = if (rIdx == 0) colors.textPrimary else colors.textSecondary,
                            fontSize = 12.sp,
                            fontWeight = if (rIdx == 0) FontWeight.Bold else FontWeight.Normal,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.width(88.dp),
                        )
                    }
                }
                if (rIdx == 0) HorizontalDivider(color = colors.divider)
            }
        }
    }
}

private fun collectAllText(arr: JsonArray): String {
    val parts = mutableListOf<String>()
    arr.forEach { el ->
        val o = el.safeObj() ?: return@forEach
        val compLower = o.safeStr("component")?.lowercase().orEmpty()
        if (compLower in setOf("style", "script", "link", "meta")) return@forEach
        o.safeStr("text")?.takeIf { it.isNotBlank() }?.let { parts += it }
        o["content"].safeArr()?.let {
            val nested = collectAllText(it)
            if (nested.isNotBlank()) parts += nested
        }
    }
    return parts.joinToString(" ").trim()
}

/** 提取原始 Vuetify 节点树中各 `model` 字段挂载的显隐表达式（支持父级容器继承 `show` / `v-show` / `v-if`）。 */
private fun extractFieldConditionMap(nodes: JsonArray): Map<String, String> {
    val map = mutableMapOf<String, String>()
    fun walk(arr: JsonArray, inheritedExpr: String?) {
        arr.forEach { el ->
            val obj = el.safeObj() ?: return@forEach
            val props = obj["props"].safeObj() ?: JsonObject(emptyMap())
            val ownExpr = obj.safeStr("show")
                ?: obj.safeStr("v-show")
                ?: obj.safeStr("v-if")
                ?: props.safeStr("show")
                ?: props.safeStr("v-show")
                ?: props.safeStr("v-if")
            val combinedExpr = when {
                !inheritedExpr.isNullOrBlank() && !ownExpr.isNullOrBlank() -> "($inheritedExpr) && ($ownExpr)"
                !ownExpr.isNullOrBlank() -> ownExpr
                else -> inheritedExpr
            }
            val modelKey = props.safeStr("model")
            if (!modelKey.isNullOrBlank() && !combinedExpr.isNullOrBlank()) {
                map[modelKey] = combinedExpr
            }
            obj["content"].safeArr()?.let { walk(it, combinedExpr) }
        }
    }
    walk(nodes, null)
    return map
}

/**
 * 100% JsonNull 免疫的 Vuetify 插件表单节点扁平提取器：
 * 兼容 Python 插件中 `props: null` / `content: null` / 嵌套 VForm/VRow/VCol/VCard 树结构。
 */
private fun extractNullSafeFormFields(nodes: JsonArray): List<JsonObject> {
    val out = mutableListOf<JsonObject>()
    val leafComponents = setOf(
        "VSwitch", "VCheckbox", "VTextField", "VTextarea", "VSelect",
        "VAutocomplete", "VCombobox", "VCronField", "VSlider", "VRangeSlider",
        "VAlert", "VAceEditor", "VBtn",
    )
    fun walk(arr: JsonArray, inheritedExpr: String? = null) {
        arr.forEach { el ->
            val obj = el.safeObj() ?: return@forEach
            val comp = obj.safeStr("component").orEmpty()
            val props = obj["props"].safeObj() ?: JsonObject(emptyMap())
            val events = obj["events"].safeObj()
            val children = obj["content"].safeArr() ?: JsonArray(emptyList())
            val ownExpr = obj.safeStr("show")
                ?: obj.safeStr("v-show")
                ?: obj.safeStr("v-if")
                ?: props.safeStr("show")
                ?: props.safeStr("v-show")
                ?: props.safeStr("v-if")
            val combinedExpr = when {
                !inheritedExpr.isNullOrBlank() && !ownExpr.isNullOrBlank() -> "($inheritedExpr) && ($ownExpr)"
                !ownExpr.isNullOrBlank() -> ownExpr
                else -> inheritedExpr
            }
            if (comp in leafComponents) {
                val modelKey = props.safeStr("model")
                val label = props.safeStr("label") ?: props.safeStr("title") ?: ""
                val hint = props.safeStr("hint") ?: ""
                val placeholder = props.safeStr("placeholder") ?: ""
                val text = obj.safeStr("text") ?: props.safeStr("text") ?: collectAllText(children)
                val multiple = props["multiple"].safePrim()?.booleanOrNull == true
                val rawItems = props["items"].safeArr() ?: JsonArray(emptyList())
                val normItems = rawItems.mapNotNull { itemEl ->
                    when (itemEl) {
                        is JsonPrimitive -> {
                            val v = itemEl.content.takeIf { it != "null" } ?: return@mapNotNull null
                            JsonObject(mapOf("title" to JsonPrimitive(v), "value" to JsonPrimitive(v)))
                        }
                        is JsonObject -> {
                            val title = itemEl.safeStr("title") ?: itemEl.safeStr("text") ?: itemEl.safeStr("name") ?: itemEl.safeStr("value") ?: return@mapNotNull null
                            val value = itemEl.safeStr("value") ?: title
                            JsonObject(mapOf("title" to JsonPrimitive(title), "value" to JsonPrimitive(value)))
                        }
                        else -> null
                    }
                }
                val mergedProps = buildMap<String, JsonElement> {
                    putAll(props)
                    if (events != null) put("events", events)
                }
                out += JsonObject(
                    buildMap {
                        put("component", JsonPrimitive(comp))
                        if (modelKey != null) put("modelKey", JsonPrimitive(modelKey))
                        put("label", JsonPrimitive(label))
                        put("hint", JsonPrimitive(hint))
                        put("placeholder", JsonPrimitive(placeholder))
                        put("visible", JsonPrimitive(true))
                        if (!combinedExpr.isNullOrBlank()) put("showExpr", JsonPrimitive(combinedExpr))
                        put("multiple", JsonPrimitive(multiple))
                        put("items", JsonArray(normItems))
                        put("text", JsonPrimitive(text))
                        put("rawProps", JsonObject(mergedProps))
                    },
                )
            } else if (children.isNotEmpty()) {
                walk(children, combinedExpr)
            }
        }
    }
    walk(nodes, null)
    return out
}

/** Vue 模块联邦插件加载目标面（对齐 iOS `NativeVuePluginWebContainer.Surface`）。 */
sealed interface VuePluginSurface {
    data object DataPage : VuePluginSurface
    data object Config : VuePluginSurface
    data class AppPage(val navKey: String) : VuePluginSurface
}

/** 前端弹窗标题栏投影到 Android Material 3 TopAppBar 的动作项（1:1 对齐 iOS `NativeVueSheetAction`）。 */
data class VuePluginSheetAction(
    val id: String,
    val title: String,
    val icon: String? = null,
    val enabled: Boolean = true,
)

/** 前端确认框投影到 Android Material 3 AlertDialog 的状态（1:1 对齐 iOS `NativeVueSheetConfirmation`）。 */
data class VuePluginConfirmation(
    val id: String,
    val title: String,
    val message: String,
    val confirmText: String = "确认",
    val cancelText: String = "取消",
    val confirmEnabled: Boolean = true,
    val cancelEnabled: Boolean = true,
    val destructive: Boolean = false,
)

/**
 * 原生容器与 Vue 联邦插件之间的双向桥接控制器（1:1 对齐 iOS `NativeVueSheetBridge`）：
 * 承载前端接管后的实时标题、标题栏动作按钮、系统确认框及优雅关闭信号。
 */
class VuePluginChromeController(defaultTitle: String) {
    var title by mutableStateOf(defaultTitle)
    var actions by mutableStateOf<List<VuePluginSheetAction>>(emptyList())
    var confirmation by mutableStateOf<VuePluginConfirmation?>(null)
    var isReady by mutableStateOf(false)
    var shouldDismiss by mutableStateOf(false)

    internal var invokeActionHandler: ((String) -> Unit)? = null
    internal var requestCloseHandler: (() -> Boolean)? = null
    internal var respondConfirmationHandler: ((String, Boolean) -> Unit)? = null

    fun invokeAction(id: String) {
        invokeActionHandler?.invoke(id)
    }

    /** 请求关闭当前最上层 Vue 弹窗；返回 false 时调用方应立即退出当前页面。 */
    fun requestClose(): Boolean = requestCloseHandler?.invoke() ?: false

    fun respondConfirmation(confirmed: Boolean) {
        val current = confirmation ?: return
        confirmation = null
        respondConfirmationHandler?.invoke(current.id, confirmed)
    }
}

/**
 * Android 端 `moviepilot.chrome` v1 + `sheets.v1` + `confirmations.v1` 协议宿主（1:1 复刻 iOS `NativeVuePluginChromeHost`）：
 * - 通过 `@JavascriptInterface` 向前端暴露 `window.MoviePilotNative`；
 * - 完成 `web.ready` → `host.configure` → `chrome.prepare` → `chrome.accepted` → `presentation.attach` 事务握手；
 * - 由 MoviePilot-Frontend 自动剥离网页原弹窗标题栏、关闭按钮、半透明渐变背景与悬浮球，
 *   并将标题与动作按钮无损投影至 Android 原生 Material 3 TopAppBar。
 */
private class AndroidVuePluginChromeHost(
    private val allowedOrigin: String,
    private val controller: VuePluginChromeController?,
    private val switchesToConfig: Boolean,
    private val onLoadingChanged: (Boolean) -> Unit,
) {
    private enum class Phase { WAITING, CONFIGURED, PREPARING, ACTIVE, RELEASED }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private var webView: WebView? = null
    private var phase: Phase = Phase.WAITING
    private var sessionId: String? = null
    private var routeRevision: Int = 0
    private var stateRevision: Int = 0
    private var sequence: Int = 0
    private var layoutRevision: Int = 0
    private var latestSnapshot: JsonObject? = null
    private var currentSheetId: String? = null
    private var currentSheetCanDismiss: Boolean = false
    private var closeRequested: Boolean = false
    private var attachedSheetId: String? = null
    private var attachingSheetId: String? = null
    private val attachAttempts = mutableMapOf<String, Int>()
    private var hasPresentedSheet: Boolean = false
    private var configSwitchDone: Boolean = false
    private var configSwitchAttempts: Int = 0
    private var confirmationId: String? = null
    private val pendingCommands = mutableMapOf<String, (Boolean) -> Unit>()
    private var dismissRunnable: Runnable? = null
    private var fallbackRunnable: Runnable? = null
    private var configSwitchRunnable: Runnable? = null

    fun attach(view: WebView) {
        webView = view
        controller?.invokeActionHandler = { id -> invokeSheetAction(id) }
        controller?.requestCloseHandler = { requestCloseCurrentSheet() }
        controller?.respondConfirmationHandler = { id, ok -> respondConfirmation(id, ok) }
    }

    fun stop() {
        phase = Phase.RELEASED
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        fallbackRunnable?.let { mainHandler.removeCallbacks(it) }
        configSwitchRunnable?.let { mainHandler.removeCallbacks(it) }
        failPendingCommands()
        controller?.invokeActionHandler = null
        controller?.requestCloseHandler = null
        controller?.respondConfirmationHandler = null
        webView = null
    }

    fun scheduleFallbackReveal(delayMs: Long = 12_000L) {
        fallbackRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            if (controller?.isReady != true) {
                releaseToWebContent()
            }
        }
        fallbackRunnable = r
        mainHandler.postDelayed(r, delayMs)
    }

    @JavascriptInterface
    fun postMessage(rawJson: String) {
        mainHandler.post { handleRawMessage(rawJson) }
    }

    private fun handleRawMessage(rawJson: String) {
        val currentUrl = webView?.url.orEmpty()
        if (currentUrl.isNotBlank() && !RustCoreBridge.containsUrl(allowedOrigin, currentUrl)) return
        val body = runCatching { json.parseToJsonElement(rawJson).safeObj() }.getOrNull() ?: return
        if (body.safeStr("kind") == "authentication.required") {
            reveal()
            return
        }
        if (body.safeStr("protocol") != "moviepilot.chrome") return
        if (body["major"].safePrim()?.intOrNull != 1) return
        val type = body.safeStr("type") ?: return
        val payload = body["payload"].safeObj() ?: JsonObject(emptyMap())
        if (type != "web.ready" && body.safeStr("sessionId") != sessionId) return
        body["routeRevision"].safePrim()?.intOrNull?.takeIf { it >= 0 }?.let { routeRevision = it }
        body["stateRevision"].safePrim()?.intOrNull?.takeIf { it >= 0 }?.let { stateRevision = it }
        handleProtocolEvent(type, payload)
    }

    private fun handleProtocolEvent(type: String, payload: JsonObject) {
        when (type) {
            "web.ready" -> {
                val id = "android-${UUID.randomUUID()}"
                sessionId = id
                phase = Phase.CONFIGURED
                resetPresentationState()
                send(
                    type = "host.configure",
                    payload = buildJsonObject {
                        put("sessionId", id)
                        put("major", 1)
                        put(
                            "capabilities",
                            buildJsonArray {
                                add(JsonPrimitive("actions.v1"))
                                add(JsonPrimitive("layout.v1"))
                                add(JsonPrimitive("menu.v1"))
                                add(JsonPrimitive("navigation.v1"))
                            },
                        )
                    },
                )
            }
            "navigation.state" -> {
                latestSnapshot = payload
                if (phase == Phase.CONFIGURED) {
                    phase = Phase.PREPARING
                    send("chrome.prepare", layoutPayload())
                } else if (phase == Phase.ACTIVE) {
                    applySnapshot(payload)
                }
            }
            "chrome.accepted" -> {
                if (phase != Phase.PREPARING) return
                phase = Phase.ACTIVE
                latestSnapshot?.let { applySnapshot(it) }
            }
            "command.result" -> {
                val reqId = payload.safeStr("requestId") ?: return
                val cb = pendingCommands.remove(reqId) ?: return
                cb(payload["accepted"].safePrim()?.booleanOrNull == true)
            }
            "session.state" -> {
                val prev = sessionId ?: return
                if (phase != Phase.ACTIVE) return
                val next = "android-${UUID.randomUUID()}"
                failPendingCommands()
                send("host.rekey", buildJsonObject { put("sessionId", next) }, sessionOverride = prev)
                sessionId = next
            }
            "chrome.failed" -> releaseToWebContent()
        }
    }

    private fun applySnapshot(snapshot: JsonObject) {
        val presentation = snapshot["presentation"].safeObj()
        updateConfirmation(presentation?.get("confirmation").safeObj())
        val sheet = presentation?.get("sheet").safeObj()
        val sheetId = sheet?.safeStr("id")?.takeIf { it.isNotBlank() }
        if (sheet == null || sheetId == null) {
            currentSheetId = null
            currentSheetCanDismiss = false
            if (closeRequested) {
                controller?.shouldDismiss = true
            } else if (hasPresentedSheet) {
                scheduleDismiss()
            }
            return
        }
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        if (sheetId != currentSheetId) closeRequested = false
        currentSheetId = sheetId
        currentSheetCanDismiss = sheet["canDismiss"].safePrim()?.booleanOrNull == true
        val pageTitle = snapshot["route"].safeObj()?.safeStr("title")
        updateSheetChrome(sheet, pageTitle)
        if (sheetId == attachedSheetId || sheetId == attachingSheetId) return
        if (switchesToConfig && !configSwitchDone) {
            attemptSwitchToConfig()
            return
        }
        attachSheet(sheetId)
    }

    private fun updateSheetChrome(sheet: JsonObject, pageTitle: String?) {
        val ctrl = controller ?: return
        val rawTitle = sheet.safeStr("title")
        if (!rawTitle.isNullOrBlank() && rawTitle != "MoviePilot" && rawTitle != pageTitle) {
            ctrl.title = rawTitle
        }
        val rawActions = sheet["actions"].safeArr().orEmpty()
        ctrl.actions = rawActions.mapNotNull { el ->
            val obj = el.safeObj() ?: return@mapNotNull null
            val id = obj.safeStr("id")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val title = obj.safeStr("title")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
            VuePluginSheetAction(
                id = id,
                title = title,
                icon = obj.safeStr("icon"),
                enabled = obj["enabled"].safePrim()?.booleanOrNull ?: true,
            )
        }
    }

    private fun attachSheet(sheetId: String) {
        val attempts = (attachAttempts[sheetId] ?: 0) + 1
        attachAttempts[sheetId] = attempts
        if (attempts > 5) {
            releaseToWebContent()
            return
        }
        attachingSheetId = sheetId
        sendCommand("presentation.attach", buildJsonObject { put("id", sheetId) }) { accepted ->
            if (attachingSheetId != sheetId) return@sendCommand
            attachingSheetId = null
            if (!accepted) return@sendCommand
            attachedSheetId = sheetId
            hasPresentedSheet = true
            reveal()
        }
    }

    private fun attemptSwitchToConfig() {
        if (configSwitchRunnable != null) return
        val wv = webView ?: return
        configSwitchAttempts += 1
        wv.evaluateJavascript("window.__mpNativeSwitchToConfig ? window.__mpNativeSwitchToConfig() : false;") { raw ->
            val switched = raw?.trim() == "true"
            if (phase != Phase.ACTIVE) return@evaluateJavascript
            if (switched || configSwitchAttempts >= 10) {
                configSwitchDone = true
                if (!switched) {
                    currentSheetId?.let { attachSheet(it) }
                }
                return@evaluateJavascript
            }
            val r = Runnable {
                configSwitchRunnable = null
                if (phase == Phase.ACTIVE) latestSnapshot?.let { applySnapshot(it) }
            }
            configSwitchRunnable = r
            mainHandler.postDelayed(r, 250L)
        }
    }

    private fun scheduleDismiss() {
        dismissRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            if (currentSheetId == null && hasPresentedSheet) {
                controller?.shouldDismiss = true
            }
        }
        dismissRunnable = r
        mainHandler.postDelayed(r, 1_500L)
    }

    private fun updateConfirmation(raw: JsonObject?) {
        val ctrl = controller ?: return
        val id = raw?.safeStr("id")?.takeIf { it.isNotBlank() }
        if (raw == null || id == null) {
            confirmationId = null
            if (ctrl.confirmation != null) ctrl.confirmation = null
            return
        }
        if (id == confirmationId) return
        confirmationId = id
        ctrl.confirmation = VuePluginConfirmation(
            id = id,
            title = raw.safeStr("title") ?: "MoviePilot",
            message = raw.safeStr("message") ?: "",
            confirmText = raw.safeStr("confirmText") ?: "确认",
            cancelText = raw.safeStr("cancelText") ?: "取消",
            confirmEnabled = raw["confirmEnabled"].safePrim()?.booleanOrNull ?: true,
            cancelEnabled = raw["cancelEnabled"].safePrim()?.booleanOrNull ?: true,
            destructive = raw["destructive"].safePrim()?.booleanOrNull ?: false,
        )
    }

    private fun invokeSheetAction(actionId: String) {
        val sheetId = currentSheetId ?: return
        if (phase != Phase.ACTIVE) return
        sendCommand(
            "presentation.action",
            buildJsonObject {
                put("id", sheetId)
                put("actionId", actionId)
            },
        ) {}
    }

    private fun requestCloseCurrentSheet(): Boolean {
        val sheetId = currentSheetId ?: return false
        if (phase != Phase.ACTIVE || !currentSheetCanDismiss) return false
        closeRequested = true
        sendCommand("presentation.dismiss", buildJsonObject { put("id", sheetId) }) { accepted ->
            if (!accepted) controller?.shouldDismiss = true
        }
        mainHandler.postDelayed({
            if (closeRequested && currentSheetId == sheetId) {
                controller?.shouldDismiss = true
            }
        }, 1_200L)
        return true
    }

    private fun respondConfirmation(id: String, confirmed: Boolean) {
        if (phase != Phase.ACTIVE) return
        sendCommand(
            "confirmation.respond",
            buildJsonObject {
                put("id", id)
                put("confirmed", confirmed)
            },
        ) {}
    }

    private fun reveal() {
        fallbackRunnable?.let { mainHandler.removeCallbacks(it) }
        onLoadingChanged(false)
        controller?.isReady = true
    }

    private fun releaseToWebContent() {
        if (phase == Phase.RELEASED) return
        if (sessionId != null && (phase == Phase.ACTIVE || phase == Phase.PREPARING)) {
            send("chrome.release", JsonObject(emptyMap()))
        }
        phase = Phase.RELEASED
        failPendingCommands()
        reveal()
    }

    private fun resetPresentationState() {
        latestSnapshot = null
        currentSheetId = null
        attachedSheetId = null
        attachingSheetId = null
        attachAttempts.clear()
        configSwitchRunnable?.let { mainHandler.removeCallbacks(it) }
        configSwitchRunnable = null
        failPendingCommands()
    }

    private fun sendCommand(type: String, payload: JsonObject, completion: (Boolean) -> Unit) {
        if (sessionId == null) {
            completion(false)
            return
        }
        sequence += 1
        val reqId = "android-cmd-$sequence"
        pendingCommands[reqId] = completion
        send(type, payload, requestId = reqId)
        mainHandler.postDelayed({
            pendingCommands.remove(reqId)?.invoke(false)
        }, 5_000L)
    }

    private fun failPendingCommands() {
        val copy = pendingCommands.values.toList()
        pendingCommands.clear()
        copy.forEach { it(false) }
    }

    private fun send(
        type: String,
        payload: JsonObject,
        requestId: String? = null,
        sessionOverride: String? = null,
    ) {
        val wv = webView ?: return
        val resolvedReqId = requestId ?: run {
            sequence += 1
            "android-msg-$sequence"
        }
        val activeSession = sessionOverride ?: sessionId
        val envelope = buildJsonObject {
            put("protocol", "moviepilot.chrome")
            put("major", 1)
            put("type", type)
            put("requestId", resolvedReqId)
            put("payload", payload)
            if (activeSession != null) {
                put("sessionId", activeSession)
                put("routeRevision", routeRevision)
                put("stateRevision", stateRevision)
            }
        }
        val js = "window.dispatchEvent(new CustomEvent('moviepilot:native-message', { detail: $envelope }));"
        wv.evaluateJavascript(js, null)
    }

    private fun layoutPayload(): JsonObject {
        layoutRevision += 1
        val wv = webView
        val cfg = wv?.resources?.configuration
        val density = wv?.resources?.displayMetrics?.density?.takeIf { it > 0f } ?: 3f
        val fallbackWidthDp = cfg?.screenWidthDp?.takeIf { it > 0 }?.toDouble() ?: 390.0
        val fallbackHeightDp = cfg?.screenHeightDp?.takeIf { it > 0 }?.toDouble() ?: 844.0
        val widthDp = ((wv?.width ?: 0) / density).toDouble().takeIf { it > 0 } ?: fallbackWidthDp
        val heightDp = ((wv?.height ?: 0) / density).toDouble().takeIf { it > 0 } ?: fallbackHeightDp
        val zero = buildJsonObject {
            put("top", 0)
            put("left", 0)
            put("bottom", 0)
            put("right", 0)
        }
        return buildJsonObject {
            put("layoutRevision", layoutRevision)
            put(
                "viewportPoints",
                buildJsonObject {
                    put("width", widthDp)
                    put("height", heightDp)
                },
            )
            put("contentInsets", zero)
            put("systemSafeArea", zero)
            put("chromeOcclusion", zero)
            put("keyboardOcclusion", 0)
            put("consumedByNativeFrame", true)
        }
    }
}

/**
 * 1:1 对齐 iOS `NativeVuePluginWebView` + `NativeVuePluginChromeHost` 的受控隔离 Vue 模块联邦 WebView 容器：
 * - 首帧前向 `localStorage` 写入 Pinia `auth`/`user`/`MP_LOCALE`/`theme`/`moviepilot-theme-customizer` 实现零登录直达；
 * - 写入同源资源 Cookie 保障远程联邦 `remoteEntry.js` 与图片代理零 401；
 * - 注入 `window.MoviePilotNative` 传输门面与 `moviepilot.chrome` v1 协议宿主，由前端原生容器协议接管弹窗标题栏、
 *   操作按钮与关闭按钮，彻底剥离网页原弹窗标题栏、背景渐变/模糊与悬浮球，无缝融入 Android Material 3 纯净底色；
 * - 严格锁定同源导航，销毁时立即清空 Cookie 与 WebStorage。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun IsolatedVuePluginWebView(
    pluginId: String,
    session: VuePluginSessionPayload,
    surface: VuePluginSurface = VuePluginSurface.DataPage,
    chromeController: VuePluginChromeController? = null,
    pluginHasPage: Boolean = false,
    onLegacyFallbackChanged: ((Boolean) -> Unit)? = null,
    onRequestExit: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var fallbackToLegacy by remember(pluginId, surface) { mutableStateOf(false) }
    if (!fallbackToLegacy) {
        LocalPluginShellWebView(
            pluginId = pluginId,
            session = session,
            surface = surface,
            chromeController = chromeController,
            pluginHasPage = pluginHasPage,
            onFallbackToLegacy = {
                fallbackToLegacy = true
                onLegacyFallbackChanged?.invoke(true)
            },
            onRequestExit = onRequestExit,
            modifier = modifier,
        )
        return
    }
    LegacyIsolatedVuePluginWebView(
        pluginId = pluginId,
        session = session,
        surface = surface,
        chromeController = chromeController,
        pluginHasPage = pluginHasPage,
        modifier = modifier,
    )
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun LegacyIsolatedVuePluginWebView(
    pluginId: String,
    session: VuePluginSessionPayload,
    surface: VuePluginSurface = VuePluginSurface.DataPage,
    chromeController: VuePluginChromeController? = null,
    pluginHasPage: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val allowedOrigin = remember(session.serverUrl) { session.serverUrl.trimEnd('/') }
    val themeName = if (colors.isDark) "dark" else "light"
    val accentHex = remember(colors.accent) { String.format("#%06X", 0xFFFFFF and colors.accent.toArgb()) }
    var isWebLoading by remember(pluginId, surface) { mutableStateOf(true) }

    val targetUrl = remember(allowedOrigin, pluginId, surface) {
        val encId = URLEncoder.encode(pluginId, "UTF-8")
        when (surface) {
            is VuePluginSurface.AppPage -> {
                val encNav = URLEncoder.encode(surface.navKey, "UTF-8")
                "$allowedOrigin/#/plugin-app/$encId/$encNav"
            }
            VuePluginSurface.DataPage, VuePluginSurface.Config -> {
                "$allowedOrigin/#/plugins?id=$encId&tab=installed"
            }
        }
    }

    val chromeHost = remember(pluginId, surface, chromeController, pluginHasPage) {
        AndroidVuePluginChromeHost(
            allowedOrigin = allowedOrigin,
            controller = chromeController,
            switchesToConfig = surface == VuePluginSurface.Config && pluginHasPage,
            onLoadingChanged = { loading -> isWebLoading = loading },
        )
    }

    fun jsEsc(s: String): String =
        s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")

    val bootstrapAndTransportJs = remember(session, themeName, accentHex, chromeController != null) {
        val authJson = """{"token":"${jsEsc(session.authToken)}","remember":true,"originalPath":null}"""
        val userJson = """{"superUser":${session.isSuperuser},"userID":${session.userId},"userName":"${jsEsc(session.userName)}","avatar":"${jsEsc(session.avatar)}","level":2,"permissions":{"discovery":true,"search":true,"subscribe":true,"manage":true,"admin":${session.isSuperuser},"features":{}}}"""
        val customizerJson = """{"theme":"$themeName","primaryColor":"$accentHex"}"""
        val enableSheets = chromeController != null
        """
        (function() {
          if (window.top !== window) return;
          try {
            var needsReload = !window.localStorage.getItem('auth');
            window.localStorage.setItem('auth', '${jsEsc(authJson)}');
            window.localStorage.setItem('user', '${jsEsc(userJson)}');
            window.localStorage.setItem('MP_LOCALE', 'zh-CN');
            window.localStorage.setItem('theme', '$themeName');
            window.localStorage.setItem('materio-initial-resolved-theme', '$themeName');
            window.localStorage.setItem('materio-initial-loader-color', '$accentHex');
            window.localStorage.setItem('moviepilot-theme-customizer', '${jsEsc(customizerJson)}');
            if (needsReload && !window.__mpNativeReloaded) {
              window.__mpNativeReloaded = true;
              window.location.reload();
              return;
            }
          } catch (e) {}

          // 1. 注入去壳与去原背景 CSS（与 MoviePilot-Frontend native.scss 协同，剥离 Vue 渐变/毛玻璃底壳与悬浮球，并守护输入框对比度）
          function applyNativePluginStyle() {
            try {
              var existing = document.getElementById('mp-native-vue-plugin-style');
              var s = existing || document.createElement('style');
              s.id = 'mp-native-vue-plugin-style';
              var inputBg = '$themeName' === 'dark' ? 'rgba(255,255,255,0.06)' : 'rgba(15,23,42,0.05)';
              var inputText = '$themeName' === 'dark' ? '#F3F5FA' : '#181C26';
              var inputBorder = '$themeName' === 'dark' ? 'rgba(255,255,255,0.18)' : 'rgba(15,23,42,0.20)';
              s.textContent = [
                'html{color-scheme:$themeName;}',
                '.layout-navbar,.layout-vertical-nav,.layout-overlay,.layout-footer,.footer-content-container,',
                '.mobile-dock,.v-bottom-navigation,.app-customizer-toggler,.agent-pet-container,',
                '.agent-pet-stage-layer,.agent-assistant-fab,.floating-agent-btn,',
                '[data-native-page-title],[data-native-page-heading],[data-native-page-actions]{display:none!important;}',
                'html,body,#app,.v-application,.v-application__wrap{background:transparent!important;background-image:none!important;}',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>*,',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>.v-card,',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current] [class*="dialog-card"],',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current] [class*="plugin-config"]:not(input):not(textarea):not(select):not(.v-field),',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current] [class*="plugin-page"]:not(input):not(textarea):not(select):not(.v-field){',
                '  background:transparent!important;background-color:transparent!important;background-image:none!important;',
                '  backdrop-filter:none!important;-webkit-backdrop-filter:none!important;',
                '  border:0!important;border-radius:0!important;box-shadow:none!important;',
                '}',
                'input:not([type="checkbox"]):not([type="radio"]):not(.v-field__input),textarea:not(.v-field__input),select{',
                '  background-color:' + inputBg + '!important;color:' + inputText + '!important;border:1px solid ' + inputBorder + '!important;border-radius:10px;',
                '}',
                '.v-field__input,.v-label{color:' + inputText + '!important;}',
                '.v-field--variant-filled .v-field__overlay,.v-field--variant-solo .v-field__overlay{background-color:' + inputBg + '!important;opacity:1!important;}',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>*::before,',
                'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>*::after{display:none!important;}'
              ].join('\n');
              if (!existing) (document.head || document.documentElement).appendChild(s);
            } catch (e) {}
          }
          applyNativePluginStyle();
          document.addEventListener('DOMContentLoaded', applyNativePluginStyle, { once: true });

          // 2. 注入 window.MoviePilotNative 传输门面 + 联邦插件自定义标题栏标准化（1:1 复刻 iOS）
          if (${if (enableSheets) "true" else "false"} && !window.MoviePilotNative && window.__mpAndroidChromeHost) {
            Object.defineProperty(window, 'MoviePilotNative', {
              value: Object.freeze({
                transportVersion: 1,
                sheetsVersion: 1,
                confirmationsVersion: 1,
                postMessage: function (message) {
                  try { window.__mpAndroidChromeHost.postMessage(JSON.stringify(message)); } catch (e) {}
                },
                authenticationRequired: function () {
                  try { window.__mpAndroidChromeHost.postMessage(JSON.stringify({ kind: 'authentication.required' })); } catch (e) {}
                }
              }),
              configurable: false,
              writable: false
            });

            function extractMdi(el) {
              var iconEl = el.querySelector('[class*="mdi-"]')
                || (el.className && String(el.className).indexOf('mdi-') >= 0 ? el : null);
              if (iconEl) {
                var m = String(iconEl.className || '').match(/mdi-[a-z0-9-]+/i);
                if (m) return m[0].toLowerCase();
              }
              var vIcon = el.querySelector('.v-icon');
              if (vIcon) {
                var t = (vIcon.textContent || '').trim().toLowerCase();
                if (t.indexOf('mdi-') === 0) return t;
              }
              return '';
            }
            function labelForIcon(icon) {
              if (!icon) return '';
              if (icon.indexOf('cog') >= 0 || icon.indexOf('tune') >= 0) return '设置';
              if (icon.indexOf('refresh') >= 0 || icon.indexOf('sync') >= 0 || icon.indexOf('reload') >= 0) return '刷新';
              if (icon.indexOf('save') >= 0 || icon === 'mdi-check') return '保存';
              if (icon.indexOf('plus') >= 0 || icon.indexOf('add') >= 0) return '添加';
              if (icon.indexOf('delete') >= 0 || icon.indexOf('trash') >= 0) return '删除';
              if (icon.indexOf('history') >= 0 || icon.indexOf('clock') >= 0) return '历史';
              if (icon.indexOf('undo') >= 0 || icon.indexOf('restore') >= 0) return '重置';
              if (icon.indexOf('info') >= 0 || icon.indexOf('help') >= 0) return '详情';
              return '';
            }
            function isCloseLike(btn, icon, rawText, aria) {
              var cls = String(btn.className || '').toLowerCase();
              return btn.classList.contains('v-dialog-close-btn')
                || cls.indexOf('close') >= 0
                || icon === 'mdi-close' || icon === 'mdi-close-circle' || icon === 'mdi-close-circle-outline'
                || rawText === '关闭' || rawText === 'Close' || rawText === '×' || rawText === '✕'
                || aria === '关闭' || aria === 'Close';
            }
            function buttonFacts(btn) {
              return {
                icon: extractMdi(btn),
                text: (btn.textContent || '').replace(/mdi-[a-z0-9-]+/gi, '').trim(),
                aria: (btn.getAttribute('aria-label') || '').trim()
              };
            }
            function findCustomHeader(root) {
              var content = root.querySelector(':scope > .v-overlay__content') || root;
              var top = content.getBoundingClientRect().top;
              var candidates = content.querySelectorAll('header, [class*="header"], [class*="toolbar"], [class*="topbar"]');
              for (var i = 0; i < candidates.length && i < 40; i++) {
                var el = candidates[i];
                if (el.closest('[data-native-dialog-content]')) continue;
                if (el.querySelector('input, select, textarea, [role="tablist"]')) continue;
                if (el.getBoundingClientRect().top - top > 160) continue;
                var buttons = el.querySelectorAll('button');
                for (var b = 0; b < buttons.length; b++) {
                  var f = buttonFacts(buttons[b]);
                  if (isCloseLike(buttons[b], f.icon, f.text, f.aria)) return el;
                }
              }
              return null;
            }
            function findDialogHeader(root) {
              return root.querySelector('[data-native-dialog-header]')
                || root.querySelector(':scope > .v-overlay__content > .v-card > .v-card-item, :scope > .v-overlay__content > .v-card > .v-toolbar, :scope > .v-overlay__content > .v-card > .v-card-title')
                || findCustomHeader(root)
                || root.querySelector('.v-card-item, .v-toolbar');
            }
            function normalizeVueDialogHeaders() {
              var dialogs = document.querySelectorAll('.v-overlay--active.v-dialog');
              for (var d = 0; d < dialogs.length; d++) {
                var root = dialogs[d];
                var header = findDialogHeader(root);
                if (!header || header.closest('[data-native-dialog-content]')) continue;
                if (!header.hasAttribute('data-native-dialog-header')
                  && !header.matches('.v-card-item, .v-toolbar, .v-card-title')) {
                  header.setAttribute('data-native-dialog-header', '');
                }
                if (!root.querySelector('[data-native-dialog-title]')) {
                  var heading = header.querySelector('.v-card-title, .v-toolbar-title, h1, h2, h3, [class*="title"]');
                  if (heading && !heading.querySelector('button')) heading.setAttribute('data-native-dialog-title', '');
                }
                var hasClose = Boolean(root.querySelector('[data-native-dialog-close]'));
                var buttons = header.querySelectorAll('button');
                for (var i = 0; i < buttons.length; i++) {
                  var btn = buttons[i];
                  var rendered = btn.getClientRects().length > 0;
                  if (!rendered) {
                    if (!btn.hasAttribute('aria-hidden')) {
                      btn.setAttribute('aria-hidden', 'true');
                      btn.setAttribute('data-mp-native-hidden', '');
                    }
                    continue;
                  }
                  if (btn.hasAttribute('data-mp-native-hidden')) {
                    btn.removeAttribute('aria-hidden');
                    btn.removeAttribute('data-mp-native-hidden');
                  }
                  if (btn.hasAttribute('data-native-dialog-close') || btn.hasAttribute('data-mp-native-duplicate-close')) continue;
                  var f = buttonFacts(btn);
                  if (isCloseLike(btn, f.icon, f.text, f.aria)) {
                    if (!hasClose) {
                      btn.setAttribute('data-native-dialog-close', '');
                      hasClose = true;
                    } else {
                      btn.setAttribute('aria-hidden', 'true');
                      btn.setAttribute('data-mp-native-duplicate-close', '');
                    }
                    continue;
                  }
                  if (f.icon && !btn.hasAttribute('data-native-sheet-action') && !header.hasAttribute('data-native-sheet-actions')) {
                    btn.setAttribute('data-native-sheet-action', f.icon);
                  }
                  if (!f.aria && !btn.getAttribute('title') && !f.text) {
                    var fallback = labelForIcon(f.icon);
                    if (fallback) btn.setAttribute('aria-label', fallback);
                  }
                }
              }
            }
            function installHeaderObserver() {
              if (!document.body) return;
              normalizeVueDialogHeaders();
              new MutationObserver(function (records) {
                for (var i = 0; i < records.length; i++) {
                  if (records[i].type === 'childList') {
                    normalizeVueDialogHeaders();
                    break;
                  }
                }
              }).observe(document.body, { childList: true, subtree: true });
            }
            if (document.body) installHeaderObserver();
            else document.addEventListener('DOMContentLoaded', installHeaderObserver, { once: true });

            window.__mpNativeSwitchToConfig = function () {
              var dialogs = Array.prototype.slice.call(document.querySelectorAll('.v-overlay--active.v-dialog'));
              if (!dialogs.length) return false;
              dialogs.sort(function (a, b) {
                return (parseInt(getComputedStyle(a).zIndex || '0', 10) || 0)
                  - (parseInt(getComputedStyle(b).zIndex || '0', 10) || 0);
              });
              var buttons = dialogs[dialogs.length - 1].querySelectorAll('button, .v-btn');
              for (var i = 0; i < buttons.length; i++) {
                var button = buttons[i];
                var icon = extractMdi(button);
                var text = (button.textContent || '').replace(/mdi-[a-z0-9-]+/gi, '').trim();
                var label = (button.getAttribute('aria-label') || '').trim();
                if (icon === 'mdi-cog' || icon === 'mdi-cog-outline' || icon === 'mdi-tune'
                  || text === '设置' || text === '配置' || text.indexOf('前往配置') >= 0 || text.indexOf('切换配置') >= 0
                  || label === '设置' || label === 'Settings' || label === '切换配置') {
                  button.click();
                  return true;
                }
              }
              return false;
            };
          }
        })();
        """.trimIndent()
    }

    DisposableEffect(chromeHost) {
        onDispose {
            chromeHost.stop()
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
            runCatching { WebStorage.getInstance().deleteAllData() }
        }
    }

    val waitForChromeReady = chromeController != null
    val contentVisible = !isWebLoading && (!waitForChromeReady || chromeController?.isReady == true)

    Box(modifier = modifier) {
        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                    settings.cacheMode = WebSettings.LOAD_NO_CACHE
                    settings.mediaPlaybackRequiresUserGesture = false
                    settings.useWideViewPort = false
                    settings.loadWithOverviewMode = false
                    if (waitForChromeReady) {
                        addJavascriptInterface(chromeHost, "__mpAndroidChromeHost")
                    }
                    chromeHost.attach(this)
                    val cm = CookieManager.getInstance()
                    cm.setAcceptCookie(true)
                    cm.setAcceptThirdPartyCookies(this, false)
                    session.originCookies.forEach { cookie ->
                        cm.setCookie(allowedOrigin, cookie)
                    }
                    cm.flush()
                    webViewClient = object : WebViewClient() {
                        override fun shouldInterceptRequest(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): WebResourceResponse? {
                            if (request == null || !request.isForMainFrame) return null
                            if (!request.method.equals("GET", ignoreCase = true)) return null
                            val reqUrl = request.url?.toString().orEmpty()
                            if (!RustCoreBridge.containsUrl(allowedOrigin, reqUrl)) return null
                            val path = request.url?.path.orEmpty()
                            if (path.startsWith("/api/") || path.endsWith(".js") || path.endsWith(".css")) return null
                            return runCatching {
                                val conn = (URL(reqUrl).openConnection() as HttpURLConnection).apply {
                                    requestMethod = "GET"
                                    connectTimeout = 8000
                                    readTimeout = 8000
                                    CookieManager.getInstance().getCookie(reqUrl)?.takeIf { it.isNotBlank() }?.let {
                                        setRequestProperty("Cookie", it)
                                    }
                                    setRequestProperty("Accept", "text/html,application/xhtml+xml")
                                    setRequestProperty("Accept-Language", "zh-CN")
                                }
                                if (conn.responseCode !in 200..299) {
                                    conn.disconnect()
                                    return null
                                }
                                val contentType = conn.contentType.orEmpty()
                                if (!contentType.contains("text/html", ignoreCase = true)) {
                                    conn.disconnect()
                                    return null
                                }
                                val html = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
                                conn.disconnect()
                                val safeJs = bootstrapAndTransportJs.replace("</script", "<\\/script", ignoreCase = true)
                                val scriptTag = "<script>$safeJs</script>"
                                val headMatch = Regex("<head[^>]*>", RegexOption.IGNORE_CASE).find(html)
                                val injected = if (headMatch != null) {
                                    val insertAt = headMatch.range.last + 1
                                    html.substring(0, insertAt) + scriptTag + html.substring(insertAt)
                                } else {
                                    "$scriptTag$html"
                                }
                                WebResourceResponse(
                                    "text/html",
                                    "UTF-8",
                                    ByteArrayInputStream(injected.toByteArray(Charsets.UTF_8)),
                                )
                            }.getOrNull()
                        }

                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): Boolean {
                            val target = request?.url?.toString().orEmpty()
                            return !RustCoreBridge.containsUrl(allowedOrigin, target)
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            view?.evaluateJavascript(bootstrapAndTransportJs, null)
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            view?.evaluateJavascript(bootstrapAndTransportJs, null)
                            if (waitForChromeReady) {
                                chromeHost.scheduleFallbackReveal()
                            } else {
                                isWebLoading = false
                            }
                        }
                    }
                    loadUrl(targetUrl)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .alpha(if (contentVisible) 1f else 0f),
        )
        if (!contentVisible) {
            NativeCardListSkeleton(
                style = SkeletonCardStyle.FormPanel,
                count = 3,
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
