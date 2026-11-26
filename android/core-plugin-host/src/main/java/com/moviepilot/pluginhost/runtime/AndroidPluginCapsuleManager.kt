package com.moviepilot.pluginhost.runtime

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color as AndroidColor
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.OpenInFull
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.pluginhost.VuePluginSurface
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlin.math.abs
import kotlin.math.roundToInt

/** 最小化悬浮胶囊上的单个插件快捷动作描述。 */
data class PluginCapsuleActionItem(
    val id: String,
    val label: String,
    val icon: String? = null,
    val active: Boolean = false,
    val destructive: Boolean = false,
)

/** 联邦插件最小化胶囊实时展示快照。 */
data class PluginCapsuleSnapshot(
    val pluginId: String,
    val pluginName: String,
    val title: String,
    val subtitle: String = "",
    val statusText: String = "",
    val iconUrl: String? = null,
    val mode: String = "jump", // "jump" | "mini"
    val isPlaying: Boolean = false,
    val keepOutsideApp: Boolean = false,
    val actions: List<PluginCapsuleActionItem> = emptyList(),
) {
    val isMiniWindowMode: Boolean
        get() = mode.equals("mini", ignoreCase = true) || actions.isNotEmpty()

    fun mergePatch(payload: JsonObject): PluginCapsuleSnapshot {
        fun JsonElement?.str(): String? = when (this) {
            is JsonNull, null -> null
            is JsonPrimitive -> content.takeIf { it != "null" }
            else -> null
        }
        val nextTitle = payload["title"].str()?.takeIf { it.isNotBlank() } ?: title
        val nextSubtitle = payload["subtitle"].str() ?: subtitle
        val nextStatus = payload["statusText"].str() ?: statusText
        val nextIcon = payload["iconUrl"].str()?.takeIf { it.isNotBlank() } ?: iconUrl
        val nextMode = payload["mode"].str()?.lowercase()?.takeIf { it == "jump" || it == "mini" } ?: mode
        val nextPlaying = (payload["isPlaying"] as? JsonPrimitive)?.booleanOrNull ?: isPlaying
        val nextKeepOutside = (payload["keepOutsideApp"] as? JsonPrimitive)?.booleanOrNull ?: keepOutsideApp
        val nextActions = if (payload.containsKey("actions")) {
            parseCapsuleActions(payload["actions"] as? JsonArray)
        } else {
            actions
        }
        return copy(
            title = nextTitle,
            subtitle = nextSubtitle,
            statusText = nextStatus,
            iconUrl = nextIcon,
            mode = nextMode,
            isPlaying = nextPlaying,
            keepOutsideApp = nextKeepOutside,
            actions = nextActions,
        )
    }

    companion object {
        fun fromMinimizePayload(
            pluginId: String,
            fallbackName: String,
            payload: JsonObject,
        ): PluginCapsuleSnapshot {
            fun JsonElement?.str(): String? = when (this) {
                is JsonNull, null -> null
                is JsonPrimitive -> content.takeIf { it != "null" }
                else -> null
            }
            val resolvedName = payload["pluginName"].str()?.takeIf { it.isNotBlank() } ?: fallbackName.ifBlank { pluginId }
            val resolvedTitle = payload["title"].str()?.takeIf { it.isNotBlank() } ?: resolvedName
            val rawMode = payload["mode"].str()?.lowercase()
            val actions = parseCapsuleActions(payload["actions"] as? JsonArray)
            val resolvedMode = when {
                rawMode == "mini" || rawMode == "jump" -> rawMode
                actions.isNotEmpty() -> "mini"
                else -> "jump"
            }
            return PluginCapsuleSnapshot(
                pluginId = pluginId,
                pluginName = resolvedName,
                title = resolvedTitle,
                subtitle = payload["subtitle"].str().orEmpty(),
                statusText = payload["statusText"].str().orEmpty(),
                iconUrl = payload["iconUrl"].str()?.takeIf { it.isNotBlank() },
                mode = resolvedMode,
                isPlaying = (payload["isPlaying"] as? JsonPrimitive)?.booleanOrNull ?: false,
                keepOutsideApp = (payload["keepOutsideApp"] as? JsonPrimitive)?.booleanOrNull ?: false,
                actions = actions,
            )
        }

        fun parseCapsuleActions(raw: JsonArray?): List<PluginCapsuleActionItem> {
            if (raw == null) return emptyList()
            return raw.mapNotNull { el ->
                val obj = el as? JsonObject ?: return@mapNotNull null
                val id = (obj["id"] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
                    ?: return@mapNotNull null
                val label = (obj["label"] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
                    ?: (obj["title"] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
                    ?: id
                val icon = (obj["icon"] as? JsonPrimitive)?.content?.trim()?.takeIf { it.isNotEmpty() && it != "null" }
                val active = (obj["active"] as? JsonPrimitive)?.booleanOrNull ?: false
                val destructive = (obj["destructive"] as? JsonPrimitive)?.booleanOrNull ?: false
                PluginCapsuleActionItem(
                    id = id,
                    label = label,
                    icon = icon,
                    active = active,
                    destructive = destructive,
                )
            }
        }
    }
}

/** 保活中的最小化联邦插件会话（持有未卸载的实时 `PooledAndroidPluginWebView`）。 */
data class MinimizedAndroidPluginSession(
    val pluginId: String,
    val pluginName: String,
    val surface: VuePluginSurface,
    val pluginHasPage: Boolean,
    val serverUrl: String,
    val slot: PooledAndroidPluginWebView,
    val snapshot: PluginCapsuleSnapshot,
)

/**
 * Android 端联邦插件最小化保活与悬浮胶囊协调器：
 * 1. 最小化时不调用 `plugin.unmount`，保留运行态 `WebView`、JS 上下文与音频播放状态；
 * 2. 支持应用内跨 Tab 悬浮胶囊（仅跳转胶囊 `jump` / 可展开快捷操作小窗 `mini`）；
 * 3. 当插件开启 `keepOutsideApp` 且用户授予 `SYSTEM_ALERT_WINDOW` 权限时，退回桌面后自动无缝切换为系统级悬浮胶囊。
 */
object AndroidPluginCapsuleManager {
    private val mainHandler = Handler(Looper.getMainLooper())

    var currentSession by mutableStateOf<MinimizedAndroidPluginSession?>(null)
        private set

    var isMiniCardExpanded by mutableStateOf(false)
    var restoreRequestNonce by mutableIntStateOf(0)
        private set
    var pendingRestorePluginId by mutableStateOf<String?>(null)
        private set

    private var isAppInBackground = false
    private var systemOverlayRoot: LinearLayout? = null
    private var systemOverlayExpanded = false
    private var overlayLayoutParams: WindowManager.LayoutParams? = null

    /** 判断指定 WebView 槽是否正处于最小化保活托管中（供 `onDispose` 跳过销毁）。 */
    fun isSlotParked(slot: PooledAndroidPluginWebView): Boolean =
        currentSession?.slot === slot

    /** 检查当前应用是否已获系统悬浮窗权限。 */
    fun canDrawSystemOverlays(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /** 拉起当前应用的系统悬浮窗权限设置页。 */
    fun openOverlayPermissionSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        runCatching {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }

    /** 将运行中的联邦插件槽转入后台保活胶囊状态。 */
    fun parkSession(context: Context, session: MinimizedAndroidPluginSession) {
        val appCtx = context.applicationContext
        val previous = currentSession
        if (previous != null && previous.slot !== session.slot) {
            AndroidPluginWebViewPool.release(previous.slot, appCtx)
        }
        (session.slot.webView.parent as? ViewGroup)?.removeView(session.slot.webView)
        currentSession = session
        isMiniCardExpanded = false

        // 绑定后台驻留期桥接回调：支持最小化期间实时更新胶囊标题/状态、主动恢复或关闭
        session.slot.bridge.onCapsuleUpdate = { patch ->
            val active = currentSession
            if (active != null && active.slot === session.slot) {
                currentSession = active.copy(snapshot = active.snapshot.mergePatch(patch))
                if (isAppInBackground) {
                    refreshSystemOverlayIfNeeded(appCtx)
                }
            }
        }
        session.slot.bridge.onPluginRestore = { reqId ->
            if (reqId.isNotBlank()) {
                session.slot.bridge.sendSimpleSuccess(reqId, "restored" to true)
            }
            requestRestoreToForeground(appCtx, session.pluginId)
        }
        session.slot.bridge.onPluginClose = {
            closeAndRelease(appCtx)
        }

        if (isAppInBackground) {
            refreshSystemOverlayIfNeeded(appCtx)
        }
    }

    /** 在已经最小化期间或未最小化时同步胶囊元数据。 */
    fun updateActiveSnapshot(patch: JsonObject) {
        val cur = currentSession ?: return
        currentSession = cur.copy(snapshot = cur.snapshot.mergePatch(patch))
    }

    /** 当重新进入同一插件页面时，无损取回已保活的 `PooledAndroidPluginWebView`。 */
    fun consumeMatchingSession(pluginId: String, serverUrl: String): MinimizedAndroidPluginSession? {
        val cur = currentSession ?: return null
        if (!cur.pluginId.equals(pluginId, ignoreCase = true) ||
            !cur.serverUrl.trimEnd('/').equals(serverUrl.trimEnd('/'), ignoreCase = true)
        ) {
            return null
        }
        currentSession = null
        isMiniCardExpanded = false
        pendingRestorePluginId = null
        removeSystemOverlay(cur.slot.webView.context.applicationContext)
        return cur
    }

    /** 向后台保活的联邦插件派发小悬浮窗快捷动作。 */
    fun dispatchAction(actionId: String) {
        val cur = currentSession ?: return
        cur.slot.bridge.sendCapsuleAction(actionId)
    }

    /** 请求从胶囊跳回完整联邦插件窗口（若应用在后台则通过 `moviepilot://plugin/{id}` 唤醒前台）。 */
    fun requestRestoreToForeground(context: Context, pluginId: String? = currentSession?.pluginId) {
        val targetId = pluginId?.takeIf { it.isNotBlank() } ?: return
        isMiniCardExpanded = false
        removeSystemOverlay(context.applicationContext)
        if (isAppInBackground) {
            runCatching {
                val uri = Uri.parse("moviepilot://plugin/${Uri.encode(targetId)}")
                val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                    setPackage(context.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                context.startActivity(intent)
            }
        } else {
            pendingRestorePluginId = targetId
            restoreRequestNonce += 1
        }
    }

    fun clearPendingRestoreRequest() {
        pendingRestorePluginId = null
    }

    /** 彻底关闭最小化胶囊并卸载释放底层 WebView。 */
    fun closeAndRelease(context: Context) {
        val appCtx = context.applicationContext
        removeSystemOverlay(appCtx)
        val cur = currentSession
        currentSession = null
        isMiniCardExpanded = false
        pendingRestorePluginId = null
        if (cur != null) {
            AndroidPluginWebViewPool.release(cur.slot, appCtx)
        }
    }

    /** 登出或切换实例时强制销毁保活插件与系统悬浮窗。 */
    fun resetForSessionChange(context: Context) {
        mainHandler.post {
            closeAndRelease(context)
        }
    }

    /** 宿主 Activity 进入前台：收起系统级悬浮窗，交由应用内 Compose 悬浮胶囊接管。 */
    fun onHostAppForegrounded(context: Context) {
        isAppInBackground = false
        removeSystemOverlay(context.applicationContext)
    }

    /** 宿主 Activity 退至后台：若插件声明 `keepOutsideApp` 且具备悬浮窗权限，展示系统级悬浮胶囊。 */
    fun onHostAppBackgrounded(context: Context) {
        isAppInBackground = true
        refreshSystemOverlayIfNeeded(context.applicationContext)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun refreshSystemOverlayIfNeeded(appContext: Context) {
        val session = currentSession
        if (session == null || !session.snapshot.keepOutsideApp || !canDrawSystemOverlays(appContext)) {
            removeSystemOverlay(appContext)
            return
        }
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        val snap = session.snapshot

        fun dp(v: Int): Int = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            appContext.resources.displayMetrics,
        ).roundToInt()

        val root = systemOverlayRoot ?: LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.removeAllViews()

        val pillBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(24).toFloat()
            setColor(AndroidColor.parseColor("#EB161924"))
            setStroke(dp(1), AndroidColor.parseColor("#40FFFFFF"))
        }

        if (snap.isMiniWindowMode && systemOverlayExpanded) {
            val card = LinearLayout(appContext).apply {
                orientation = LinearLayout.VERTICAL
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(18).toFloat()
                    setColor(AndroidColor.parseColor("#F2161924"))
                    setStroke(dp(1), AndroidColor.parseColor("#45FFFFFF"))
                }
                setPadding(dp(14), dp(12), dp(14), dp(12))
            }
            val headerRow = LinearLayout(appContext).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            val titleCol = LinearLayout(appContext).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            }
            titleCol.addView(
                TextView(appContext).apply {
                    text = snap.title
                    setTextColor(AndroidColor.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
                    paint.isFakeBoldText = true
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                },
            )
            val sub = snap.subtitle.ifBlank { snap.statusText }
            if (sub.isNotBlank()) {
                titleCol.addView(
                    TextView(appContext).apply {
                        text = sub
                        setTextColor(AndroidColor.parseColor("#B8FFFFFF"))
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.END
                    },
                )
            }
            headerRow.addView(titleCol)
            headerRow.addView(
                TextView(appContext).apply {
                    text = "展开"
                    setTextColor(AndroidColor.parseColor("#8AB4F8"))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setPadding(dp(8), dp(4), dp(8), dp(4))
                    setOnClickListener {
                        systemOverlayExpanded = false
                        requestRestoreToForeground(appContext, snap.pluginId)
                    }
                },
            )
            headerRow.addView(
                TextView(appContext).apply {
                    text = "✕"
                    setTextColor(AndroidColor.parseColor("#B8FFFFFF"))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    setPadding(dp(8), dp(4), dp(4), dp(4))
                    setOnClickListener {
                        systemOverlayExpanded = false
                        closeAndRelease(appContext)
                    }
                },
            )
            card.addView(headerRow)

            if (snap.actions.isNotEmpty()) {
                val actionsRow = LinearLayout(appContext).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(0, dp(8), 0, 0)
                }
                snap.actions.take(4).forEach { act ->
                    val btn = TextView(appContext).apply {
                        text = act.label
                        setTextColor(if (act.destructive) AndroidColor.parseColor("#FF7B7B") else AndroidColor.WHITE)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                        setPadding(dp(10), dp(6), dp(10), dp(6))
                        background = GradientDrawable().apply {
                            shape = GradientDrawable.RECTANGLE
                            cornerRadius = dp(14).toFloat()
                            setColor(if (act.active) AndroidColor.parseColor("#4D5E9CFF") else AndroidColor.parseColor("#28FFFFFF"))
                        }
                        setOnClickListener {
                            performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            dispatchAction(act.id)
                        }
                    }
                    val lp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                        marginEnd = dp(6)
                    }
                    actionsRow.addView(btn, lp)
                }
                card.addView(actionsRow)
            }
            val cardLp = LinearLayout.LayoutParams(dp(260), ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = dp(6)
            }
            root.addView(card, cardLp)
        }

        val pillRow = LinearLayout(appContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = pillBg
            setPadding(dp(14), dp(9), dp(10), dp(9))
        }
        val labelView = TextView(appContext).apply {
            val sub = snap.statusText.ifBlank { snap.subtitle }
            text = if (sub.isNotBlank()) "${snap.title} · $sub" else snap.title
            setTextColor(AndroidColor.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            paint.isFakeBoldText = true
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            maxWidth = dp(190)
        }
        val closeView = TextView(appContext).apply {
            text = "✕"
            setTextColor(AndroidColor.parseColor("#B0FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            setPadding(dp(10), dp(2), dp(4), dp(2))
            setOnClickListener {
                systemOverlayExpanded = false
                closeAndRelease(appContext)
            }
        }
        pillRow.addView(labelView)
        pillRow.addView(closeView)
        root.addView(pillRow)

        val params = overlayLayoutParams ?: WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dp(16)
            y = dp(160)
            overlayLayoutParams = this
        }

        var downRawX = 0f
        var downRawY = 0f
        var startParamX = 0
        var startParamY = 0
        var moved = false
        pillRow.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startParamX = params.x
                    startParamY = params.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downRawX).roundToInt()
                    val dy = (event.rawY - downRawY).roundToInt()
                    if (abs(dx) > dp(4) || abs(dy) > dp(4)) {
                        moved = true
                        params.x = (startParamX - dx).coerceAtLeast(0)
                        params.y = (startParamY + dy).coerceAtLeast(dp(48))
                        runCatching { wm.updateViewLayout(root, params) }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        if (snap.isMiniWindowMode) {
                            systemOverlayExpanded = !systemOverlayExpanded
                            refreshSystemOverlayIfNeeded(appContext)
                        } else {
                            requestRestoreToForeground(appContext, snap.pluginId)
                        }
                    }
                    true
                }
                else -> false
            }
        }

        runCatching {
            if (systemOverlayRoot == null) {
                systemOverlayRoot = root
                wm.addView(root, params)
            } else {
                wm.updateViewLayout(root, params)
            }
        }
    }

    private fun removeSystemOverlay(appContext: Context) {
        val root = systemOverlayRoot ?: return
        systemOverlayRoot = null
        systemOverlayExpanded = false
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        runCatching { wm.removeView(root) }
    }
}

/**
 * 应用内跨页面悬浮插件胶囊与可展开小悬浮窗组件（支持拖拽定位、仅跳转模式与快捷操作小窗模式）。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PluginFloatingCapsuleOverlay(
    session: MinimizedAndroidPluginSession,
    isExpanded: Boolean,
    onToggleExpanded: (Boolean) -> Unit,
    onOpenPluginWindow: () -> Unit,
    onDispatchAction: (String) -> Unit,
    onCloseCapsule: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val colors = LocalMoviePilotColors.current
    val snap = session.snapshot
    var dragOffsetX by remember { mutableFloatStateOf(0f) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    val overlayGranted = remember(snap.keepOutsideApp, isExpanded) {
        AndroidPluginCapsuleManager.canDrawSystemOverlays(context)
    }

    Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .offset { IntOffset(dragOffsetX.roundToInt(), dragOffsetY.roundToInt()) }
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    dragOffsetX += dragAmount.x
                    dragOffsetY += dragAmount.y
                }
            },
    ) {
        AnimatedVisibility(
            visible = isExpanded && snap.isMiniWindowMode,
            enter = fadeIn() + scaleIn(initialScale = 0.92f),
            exit = fadeOut() + scaleOut(targetScale = 0.92f),
        ) {
            Surface(
                shape = RoundedCornerShape(22.dp),
                color = colors.surfaceContainerHigh.copy(alpha = 0.96f),
                border = BorderStroke(1.dp, colors.divider),
                shadowElevation = 12.dp,
                modifier = Modifier.widthIn(min = 240.dp, max = 310.dp),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.padding(14.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        CapsulePluginIcon(iconUrl = snap.iconUrl, accent = colors.accent, sizeDp = 36)
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = snap.title,
                                color = colors.textPrimary,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            val sub = snap.subtitle.ifBlank { snap.statusText.ifBlank { snap.pluginName } }
                            if (sub.isNotBlank()) {
                                Text(
                                    text = sub,
                                    color = colors.textSecondary,
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                        IconButton(
                            onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                onOpenPluginWindow()
                            },
                            modifier = Modifier.size(32.dp),
                        ) {
                            Icon(
                                Icons.Rounded.OpenInFull,
                                contentDescription = "打开插件窗口",
                                tint = colors.accent,
                                modifier = Modifier.size(17.dp),
                            )
                        }
                    }

                    if (snap.actions.isNotEmpty()) {
                        HorizontalDivider(color = colors.divider)
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            snap.actions.forEach { action ->
                                NativeAdaptivePill(
                                    title = action.label,
                                    selected = action.active,
                                    onClick = {
                                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                        onDispatchAction(action.id)
                                    },
                                )
                            }
                        }
                    }

                    if (snap.keepOutsideApp && !overlayGranted) {
                        HorizontalDivider(color = colors.divider)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                            modifier = Modifier
                                .clip(RoundedCornerShape(12.dp))
                                .background(colors.accent.copy(alpha = 0.12f))
                                .clickable { AndroidPluginCapsuleManager.openOverlayPermissionSettings(context) }
                                .padding(horizontal = 10.dp, vertical = 7.dp),
                        ) {
                            Icon(
                                Icons.Rounded.PictureInPictureAlt,
                                contentDescription = null,
                                tint = colors.accent,
                                modifier = Modifier.size(15.dp),
                            )
                            Spacer(Modifier.size(6.dp))
                            Text(
                                text = "开启悬浮窗权限以支持退回桌面继续显示",
                                color = colors.accent,
                                fontSize = 11.5.sp,
                                fontWeight = FontWeight.Medium,
                            )
                        }
                    }
                }
            }
        }

        // 紧凑悬浮胶囊主体
        Surface(
            shape = RoundedCornerShape(999.dp),
            color = colors.surfaceContainerHigh.copy(alpha = 0.94f),
            border = BorderStroke(1.dp, colors.accent.copy(alpha = 0.36f)),
            shadowElevation = 10.dp,
            modifier = Modifier.clickable {
                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                if (snap.isMiniWindowMode) {
                    onToggleExpanded(!isExpanded)
                } else {
                    onOpenPluginWindow()
                }
            },
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(start = 8.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
            ) {
                CapsulePluginIcon(iconUrl = snap.iconUrl, accent = colors.accent, sizeDp = 28)
                Column(modifier = Modifier.widthIn(max = 168.dp)) {
                    Text(
                        text = snap.title,
                        color = colors.textPrimary,
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    val secondary = snap.statusText.ifBlank { snap.subtitle }
                    if (secondary.isNotBlank()) {
                        Text(
                            text = secondary,
                            color = colors.textSecondary,
                            fontSize = 10.5.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                if (snap.isMiniWindowMode) {
                    IconButton(
                        onClick = {
                            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            onOpenPluginWindow()
                        },
                        modifier = Modifier.size(26.dp),
                    ) {
                        Icon(
                            Icons.Rounded.KeyboardArrowUp,
                            contentDescription = "进入联邦窗口",
                            tint = colors.accent,
                            modifier = Modifier.size(17.dp),
                        )
                    }
                }
                IconButton(
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        onCloseCapsule()
                    },
                    modifier = Modifier.size(26.dp),
                ) {
                    Icon(
                        Icons.Rounded.Close,
                        contentDescription = "关闭最小化插件",
                        tint = colors.textMuted,
                        modifier = Modifier.size(15.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun CapsulePluginIcon(
    iconUrl: String?,
    accent: Color,
    sizeDp: Int,
) {
    if (!iconUrl.isNullOrBlank()) {
        AsyncImage(
            model = iconUrl,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(sizeDp.dp)
                .clip(CircleShape),
        )
    } else {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(sizeDp.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = 0.18f)),
        ) {
            Icon(
                Icons.Rounded.Extension,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size((sizeDp * 0.56f).dp),
            )
        }
    }
}
