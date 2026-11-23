package com.moviepilot.pluginhost

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * 动态插件原生渲染宿主：
 * - 100% 消费 Rust `planPluginForm` 输出的规划树与 `evalFormExpression` / `analyzeCron` / `applyPluginPatch`；
 * - 保存时通过 Rust 无损补丁合并服务端原始完整模型（保留未知键与 64 位大整数）；
 * - 仅当 `render_mode == "vue"` 时启用严格隔离的 `IsolatedVuePluginWebView`。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NativePluginFormRenderer(
    pluginName: String,
    documentJson: String,
    serverUrl: String,
    authToken: String,
    onSaveFullModel: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val json = remember { Json { ignoreUnknownKeys = true; isLenient = true } }
    val planJson = remember(documentJson) {
        runCatching { RustCoreBridge.planPluginForm(documentJson) }.getOrDefault("{}")
    }
    val planObj = remember(planJson) {
        runCatching { json.parseToJsonElement(planJson).jsonObject }.getOrNull()
    }
    val renderMode = planObj?.get("renderMode")?.jsonPrimitive?.content ?: "vuetify"
    val originalModelJson = remember(planObj) { planObj?.get("model")?.toString() ?: "{}" }
    val fields = remember(planObj) { planObj?.get("fields")?.jsonArray ?: JsonArray(emptyList()) }

    if (renderMode == "vue") {
        IsolatedVuePluginWebView(
            pluginName = pluginName,
            serverUrl = serverUrl,
            authToken = authToken,
            modifier = modifier.fillMaxSize(),
        )
        return
    }

    val initialModel = remember(originalModelJson) {
        runCatching { json.parseToJsonElement(originalModelJson).jsonObject }.getOrDefault(JsonObject(emptyMap()))
    }
    val draftValues = remember(documentJson) {
        mutableStateMapOf<String, String>().apply {
            initialModel.forEach { (k, v) ->
                put(k, if (v is JsonPrimitive) v.content else v.toString())
            }
        }
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

    var cronPreviewExpr by remember { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (fields.isEmpty()) {
            CinematicPanel {
                Text(
                    text = "该插件暂无可配置表单项（render_mode=$renderMode）",
                    color = colors.textSecondary,
                    fontSize = 14.sp,
                )
            }
        }

        fields.forEach { el ->
            val field = el.jsonObject
            val component = field["component"]?.jsonPrimitive?.content ?: return@forEach
            val key = field["modelKey"]?.jsonPrimitive?.content?.takeIf { it != "null" }
            val label = field["label"]?.jsonPrimitive?.content.orEmpty()
            val hint = field["hint"]?.jsonPrimitive?.content.orEmpty()
            val text = field["text"]?.jsonPrimitive?.content.orEmpty()
            val visible = field["visible"]?.jsonPrimitive?.booleanOrNull ?: true
            if (!visible) return@forEach

            when (component) {
                "VSwitch", "VCheckbox" -> {
                    val checked = draftValues[key]?.equals("true", ignoreCase = true) == true
                    CinematicPanel(padding = 14.dp) {
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
                                onCheckedChange = { if (key != null) draftValues[key] = it.toString() },
                                colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                            )
                        }
                    }
                }

                "VCronField" -> {
                    val expr = draftValues[key].orEmpty()
                    val summary = remember(expr) { RustCoreBridge.analyzeCron(expr) }
                    CinematicPanel(padding = 14.dp) {
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
                                onValueChange = { if (key != null) draftValues[key] = it; cronPreviewExpr = it },
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
                                        onClick = { if (key != null) draftValues[key] = preset },
                                    )
                                }
                            }
                        }
                    }
                }

                "VSelect", "VAutocomplete", "VCombobox" -> {
                    val items = field["items"]?.jsonArray ?: JsonArray(emptyList())
                    val current = draftValues[key].orEmpty()
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(label.ifBlank { key ?: "选择器" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                items.forEach { itEl ->
                                    val obj = itEl.jsonObject
                                    val t = obj["title"]?.jsonPrimitive?.content ?: ""
                                    val v = obj["value"]?.jsonPrimitive?.content ?: t
                                    NativeAdaptivePill(
                                        title = t,
                                        selected = current == v,
                                        onClick = { if (key != null) draftValues[key] = v },
                                    )
                                }
                            }
                            if (component == "VCombobox") {
                                OutlinedTextField(
                                    value = current,
                                    onValueChange = { if (key != null) draftValues[key] = it },
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
                    CinematicPanel(padding = 14.dp) {
                        Column {
                            Text("${label.ifBlank { key ?: "数值" }}：${v.toInt()}", color = colors.textPrimary, fontSize = 14.sp)
                            Slider(
                                value = v.coerceIn(0f, 100f),
                                valueRange = 0f..100f,
                                onValueChange = { if (key != null) draftValues[key] = it.toInt().toString() },
                            )
                        }
                    }
                }

                "VAlert" -> {
                    CinematicPanel(padding = 14.dp) {
                        Text(
                            text = text.ifBlank { label },
                            color = colors.info,
                            fontSize = 13.sp,
                        )
                    }
                }

                "VAceEditor", "VTextarea" -> {
                    val value = draftValues[key].orEmpty()
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(label.ifBlank { key ?: "脚本 / 文本" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            OutlinedTextField(
                                value = value,
                                onValueChange = { if (key != null) draftValues[key] = it },
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
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(label.ifBlank { key ?: "输入项" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                            OutlinedTextField(
                                value = value,
                                onValueChange = { if (key != null) draftValues[key] = it },
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
                        CinematicPanel(padding = 12.dp) {
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
                // 构造仅含用户编辑键的局部补丁，交由 Rust 无损合并回完整模型（保留 64 位大整数与未知键）
                val patchEntries = draftValues.entries.joinToString(",") { (k, v) ->
                    val jsonVal = when {
                        v == "true" || v == "false" -> v
                        v.toLongOrNull() != null && initialModel[k] is JsonPrimitive && initialModel[k]?.jsonPrimitive?.isString == false -> v
                        else -> "\"${v.replace("\\", "\\\\").replace("\"", "\\\"")}\""
                    }
                    "\"$k\":$jsonVal"
                }
                val merged = runCatching {
                    RustCoreBridge.applyPluginPatch(originalModelJson, "{$patchEntries}")
                }.getOrDefault(originalModelJson)
                onSaveFullModel(merged)
            },
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.accent,
                contentColor = Color.White,
            ),
            shape = RoundedCornerShape(24.dp),
            modifier = Modifier.fillMaxWidth().height(50.dp),
        ) {
            Text("保存插件配置", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(24.dp))
    }
}

/**
 * 受控隔离 Vue 插件 WebView 容器（仅用于 `render_mode == "vue"` 遗留插件）：
 * 严格限定仅允许同源导航，注入免登 Cookie，并在销毁时立即清理缓存与 Cookie。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun IsolatedVuePluginWebView(
    pluginName: String,
    serverUrl: String,
    authToken: String,
    modifier: Modifier = Modifier,
) {
    val allowedOrigin = remember(serverUrl) { serverUrl.trimEnd('/') }
    DisposableEffect(Unit) {
        onDispose {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
        }
    }
    Box(modifier = modifier) {
        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setCookie(allowedOrigin, "token=$authToken; Path=/")
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?,
                        ): Boolean {
                            val target = request?.url?.toString().orEmpty()
                            // 严格拦截跳出当前实例源的非法导航
                            return !RustCoreBridge.containsUrl(allowedOrigin, target)
                        }
                    }
                    loadUrl("$allowedOrigin/#/plugins/$pluginName")
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}
