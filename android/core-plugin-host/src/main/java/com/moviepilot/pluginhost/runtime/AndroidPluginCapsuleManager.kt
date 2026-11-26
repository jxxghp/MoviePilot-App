package com.moviepilot.pluginhost.runtime

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.LruCache
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.pluginhost.R
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

/** 胶囊内联快捷动作图标语义枚举。 */
internal enum class CapsuleInlineActionKind {
    PREVIOUS,
    PLAY_PAUSE,
    NEXT,
    HEART,
    REPEAT_ONE,
    REPEAT,
    SHUFFLE,
    LYRICS,
    GENERIC,
}

/** 根据动作 `id` 与 `icon` 提示推断内联图标类型。 */
internal fun classifyCapsuleAction(action: PluginCapsuleActionItem): CapsuleInlineActionKind {
    val combined = "${action.id} ${action.icon.orEmpty()}".lowercase()
    return when {
        combined.contains("prev") || combined.contains("skip-previous") || combined.contains("step-backward") ->
            CapsuleInlineActionKind.PREVIOUS
        combined.contains("play") || combined.contains("pause") || combined.contains("toggle") ->
            CapsuleInlineActionKind.PLAY_PAUSE
        combined.contains("next") || combined.contains("skip-next") || combined.contains("step-forward") ->
            CapsuleInlineActionKind.NEXT
        combined.contains("heart") || combined.contains("like") || combined.contains("fav") ->
            CapsuleInlineActionKind.HEART
        combined.contains("repeat-one") || combined.contains("repeat_one") ||
            combined.contains("repeat-once") || combined.contains("repeat_once") ||
            combined.contains("loop-one") || combined.contains("loop_one") ->
            CapsuleInlineActionKind.REPEAT_ONE
        combined.contains("repeat") || combined.contains("loop") ->
            CapsuleInlineActionKind.REPEAT
        combined.contains("shuffle") || combined.contains("random") ->
            CapsuleInlineActionKind.SHUFFLE
        combined.contains("lyric") || combined.contains("lrc") ->
            CapsuleInlineActionKind.LYRICS
        else -> CapsuleInlineActionKind.GENERIC
    }
}

/** 将播放状态同步写回动作列表中播放控制项的 `active` 标记，保持状态唯一可信。 */
private fun syncPlayActionActive(
    actions: List<PluginCapsuleActionItem>,
    isPlaying: Boolean,
): List<PluginCapsuleActionItem> = actions.map { act ->
    if (classifyCapsuleAction(act) == CapsuleInlineActionKind.PLAY_PAUSE) {
        act.copy(active = isPlaying)
    } else {
        act
    }
}

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

    /** 合并插件增量更新补丁并保持播放按钮状态联动。 */
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
        val parsedActions = if (payload.containsKey("actions")) {
            parseCapsuleActions(payload["actions"] as? JsonArray)
        } else {
            actions
        }
        val explicitPlaying = (payload["isPlaying"] as? JsonPrimitive)?.booleanOrNull
        val nextPlaying = explicitPlaying
            ?: if (payload.containsKey("actions")) {
                parsedActions.firstOrNull { classifyCapsuleAction(it) == CapsuleInlineActionKind.PLAY_PAUSE }?.active
                    ?: isPlaying
            } else {
                isPlaying
            }
        val nextKeepOutside = (payload["keepOutsideApp"] as? JsonPrimitive)?.booleanOrNull ?: keepOutsideApp
        return copy(
            title = nextTitle,
            subtitle = nextSubtitle,
            statusText = nextStatus,
            iconUrl = nextIcon,
            mode = nextMode,
            isPlaying = nextPlaying,
            keepOutsideApp = nextKeepOutside,
            actions = syncPlayActionActive(parsedActions, nextPlaying),
        )
    }

    companion object {
        /** 从 `plugin.minimize` 载荷构造初始胶囊快照。 */
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
            val explicitPlaying = (payload["isPlaying"] as? JsonPrimitive)?.booleanOrNull
            val resolvedPlaying = explicitPlaying
                ?: actions.firstOrNull { classifyCapsuleAction(it) == CapsuleInlineActionKind.PLAY_PAUSE }?.active
                ?: false
            return PluginCapsuleSnapshot(
                pluginId = pluginId,
                pluginName = resolvedName,
                title = resolvedTitle,
                subtitle = payload["subtitle"].str().orEmpty(),
                statusText = payload["statusText"].str().orEmpty(),
                iconUrl = payload["iconUrl"].str()?.takeIf { it.isNotBlank() },
                mode = resolvedMode,
                isPlaying = resolvedPlaying,
                keepOutsideApp = (payload["keepOutsideApp"] as? JsonPrimitive)?.booleanOrNull ?: false,
                actions = syncPlayActionActive(actions, resolvedPlaying),
            )
        }

        /** 解析胶囊快捷动作数组。 */
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
 * 支持触摸拖拽拦截的系统悬浮胶囊横向容器：
 * 当手指滑动距离超过阈值时由外层统一接管窗口移动；轻点子按钮或标题区时正常触发各自点击事件。
 */
private class DraggableOverlayPillRow(
    context: Context,
    private val touchSlopPx: Int,
    private val onDragBy: (dx: Int, dy: Int) -> Unit,
) : LinearLayout(context) {
    private var downRawX = 0f
    private var downRawY = 0f
    private var lastRawX = 0f
    private var lastRawY = 0f
    private var isDragging = false

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downRawX = ev.rawX
                downRawY = ev.rawY
                lastRawX = ev.rawX
                lastRawY = ev.rawY
                isDragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (abs(ev.rawX - downRawX) > touchSlopPx || abs(ev.rawY - downRawY) > touchSlopPx) {
                    isDragging = true
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isDragging = false
            }
        }
        return super.onInterceptTouchEvent(ev)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downRawX = event.rawX
                downRawY = event.rawY
                lastRawX = event.rawX
                lastRawY = event.rawY
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = (event.rawX - lastRawX).roundToInt()
                val dy = (event.rawY - lastRawY).roundToInt()
                if (dx != 0 || dy != 0) {
                    lastRawX = event.rawX
                    lastRawY = event.rawY
                    onDragBy(dx, dy)
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isDragging = false
                return true
            }
        }
        return super.onTouchEvent(event)
    }
}

/**
 * Android 端联邦插件最小化保活与紧凑单行悬浮胶囊协调器：
 * 1. 最小化时不调用 `plugin.unmount`，保留运行态 `WebView`、JS 上下文与音频播放状态；
 * 2. 统一采用紧凑单行横向播控胶囊（圆形鉴权封面 + 点击直达标题区 + 最多 3 个内联快捷图标按钮 + 关闭按钮）；
 * 3. 原生音频状态变化与 `setNowPlaying` 自动同步更新胶囊播放/暂停图标及曲目信息；
 * 4. 当开启 `keepOutsideApp` 且授予悬浮窗权限时，退回桌面自动无缝切换为单行系统级悬浮胶囊。
 */
object AndroidPluginCapsuleManager {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val iconCache = LruCache<String, Bitmap>(24)
    private val inflightIconKeys = HashSet<String>()

    var currentSession by mutableStateOf<MinimizedAndroidPluginSession?>(null)
        private set

    var isMiniCardExpanded by mutableStateOf(false)
    var restoreRequestNonce by mutableIntStateOf(0)
        private set
    var pendingRestorePluginId by mutableStateOf<String?>(null)
        private set
    var iconCacheRevision by mutableIntStateOf(0)
        private set

    private var isAppInBackground = false
    private var systemOverlayRoot: LinearLayout? = null
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

    /** 生成会话隔离的胶囊封面缓存键。 */
    internal fun makeIconCacheKey(serverUrl: String, rawIconUrl: String?): String? {
        val trimmed = rawIconUrl?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return "${serverUrl.trimEnd('/')}|$trimmed"
    }

    /** 读取已缓存的胶囊封面位图。 */
    internal fun getCachedIconBitmap(serverUrl: String, rawIconUrl: String?): Bitmap? {
        val key = makeIconCacheKey(serverUrl, rawIconUrl) ?: return null
        return iconCache.get(key)
    }

    /** 触发后台鉴权加载胶囊封面，加载完成后自动通知应用内 Compose 与系统悬浮窗重绘。 */
    internal fun ensureIconLoaded(session: MinimizedAndroidPluginSession, appContext: Context) {
        val rawUrl = session.snapshot.iconUrl?.trim()?.takeIf { it.isNotEmpty() } ?: return
        val cacheKey = makeIconCacheKey(session.serverUrl, rawUrl) ?: return
        if (iconCache.get(cacheKey) != null || !inflightIconKeys.add(cacheKey)) return
        session.slot.bridge.nativeCapabilities.fetchAuthenticatedBitmap(rawUrl, maxSidePx = 192) { bmp ->
            inflightIconKeys.remove(cacheKey)
            if (bmp != null) {
                iconCache.put(cacheKey, bmp)
                iconCacheRevision += 1
                if (isAppInBackground && currentSession?.pluginId == session.pluginId) {
                    refreshSystemOverlayIfNeeded(appContext)
                }
            }
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
        session.slot.bridge.nativeCapabilities.activePluginId = session.pluginId
        session.slot.bridge.nativeCapabilities.activePluginName = session.pluginName
        currentSession = session
        isMiniCardExpanded = false
        ensureIconLoaded(session, appCtx)

        // 绑定后台驻留期桥接回调：支持最小化期间实时更新胶囊标题/状态、主动恢复或关闭
        session.slot.bridge.onCapsuleUpdate = { patch ->
            val active = currentSession
            if (active != null && active.slot === session.slot) {
                val updated = active.copy(snapshot = active.snapshot.mergePatch(patch))
                currentSession = updated
                ensureIconLoaded(updated, appCtx)
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

    /** 在已经最小化期间同步胶囊元数据补丁。 */
    fun updateActiveSnapshot(patch: JsonObject) {
        val cur = currentSession ?: return
        val appCtx = cur.slot.webView.context.applicationContext
        val updated = cur.copy(snapshot = cur.snapshot.mergePatch(patch))
        currentSession = updated
        ensureIconLoaded(updated, appCtx)
        if (isAppInBackground) {
            refreshSystemOverlayIfNeeded(appCtx)
        }
    }

    /**
     * 当原生音频播放状态变化或插件调用 `audio.setNowPlaying` 时，实时联动活跃胶囊的播放状态与曲目信息，
     * 避免后台网页定时器节流导致胶囊播放/暂停图标失步。
     */
    fun syncAudioPlaybackState(
        context: Context,
        pluginId: String,
        isPlaying: Boolean,
        title: String? = null,
        subtitle: String? = null,
        iconUrl: String? = null,
    ) {
        mainHandler.post {
            val cur = currentSession ?: return@post
            if (pluginId.isNotBlank() && !cur.pluginId.equals(pluginId, ignoreCase = true)) {
                return@post
            }
            val snap = cur.snapshot
            val nextTitle = title?.trim()?.takeIf { it.isNotEmpty() } ?: snap.title
            val nextSubtitle = subtitle?.trim()?.takeIf { it.isNotEmpty() } ?: snap.subtitle
            val nextIcon = iconUrl?.trim()?.takeIf { it.isNotEmpty() } ?: snap.iconUrl
            val nextActions = syncPlayActionActive(snap.actions, isPlaying)
            val updatedSnap = snap.copy(
                title = nextTitle,
                subtitle = nextSubtitle,
                iconUrl = nextIcon,
                isPlaying = isPlaying,
                actions = nextActions,
            )
            if (updatedSnap != snap) {
                val updatedSession = cur.copy(snapshot = updatedSnap)
                currentSession = updatedSession
                val appCtx = context.applicationContext
                ensureIconLoaded(updatedSession, appCtx)
                if (isAppInBackground) {
                    refreshSystemOverlayIfNeeded(appCtx)
                }
            }
        }
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

    /** 向后台保活的联邦插件派发胶囊内联快捷动作。 */
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

    /** 登出或切换实例时强制销毁保活插件、封面缓存与系统悬浮窗。 */
    fun resetForSessionChange(context: Context) {
        mainHandler.post {
            iconCache.evictAll()
            inflightIconKeys.clear()
            closeAndRelease(context)
        }
    }

    /** 宿主 Activity 进入前台：收起系统级悬浮窗，交由应用内 Compose 悬浮胶囊接管。 */
    fun onHostAppForegrounded(context: Context) {
        isAppInBackground = false
        removeSystemOverlay(context.applicationContext)
    }

    /** 宿主 Activity 退至后台：若插件声明 `keepOutsideApp` 且具备悬浮窗权限，展示单行系统级悬浮胶囊。 */
    fun onHostAppBackgrounded(context: Context) {
        isAppInBackground = true
        refreshSystemOverlayIfNeeded(context.applicationContext)
    }

    /** 解析系统悬浮窗内联动作按钮的矢量图标资源。 */
    private fun resolveOverlayActionDrawableRes(action: PluginCapsuleActionItem, isPlaying: Boolean): Int? =
        when (classifyCapsuleAction(action)) {
            CapsuleInlineActionKind.PREVIOUS -> R.drawable.ic_plugin_media_prev
            CapsuleInlineActionKind.PLAY_PAUSE ->
                if (isPlaying) R.drawable.ic_plugin_media_pause else R.drawable.ic_plugin_media_play
            CapsuleInlineActionKind.NEXT -> R.drawable.ic_plugin_media_next
            CapsuleInlineActionKind.HEART ->
                if (action.active) R.drawable.ic_plugin_media_heart_filled else R.drawable.ic_plugin_media_heart_outline
            CapsuleInlineActionKind.REPEAT_ONE -> R.drawable.ic_plugin_media_repeat_one
            CapsuleInlineActionKind.REPEAT -> R.drawable.ic_plugin_media_repeat
            CapsuleInlineActionKind.SHUFFLE -> R.drawable.ic_plugin_media_shuffle
            CapsuleInlineActionKind.LYRICS -> R.drawable.ic_plugin_media_lyrics
            CapsuleInlineActionKind.GENERIC -> null
        }

    /** 刷新系统级 `WindowManager` 紧凑单行圆角悬浮胶囊。 */
    @SuppressLint("ClickableViewAccessibility")
    private fun refreshSystemOverlayIfNeeded(appContext: Context) {
        val session = currentSession
        if (session == null || !session.snapshot.keepOutsideApp || !canDrawSystemOverlays(appContext)) {
            removeSystemOverlay(appContext)
            return
        }
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        val snap = session.snapshot
        ensureIconLoaded(session, appContext)

        fun dp(v: Int): Int = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            v.toFloat(),
            appContext.resources.displayMetrics,
        ).roundToInt()

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

        val root = systemOverlayRoot ?: LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.removeAllViews()

        val pillRow = DraggableOverlayPillRow(
            context = appContext,
            touchSlopPx = dp(5),
            onDragBy = { dx, dy ->
                params.x = (params.x - dx).coerceAtLeast(0)
                params.y = (params.y + dy).coerceAtLeast(dp(48))
                runCatching { wm.updateViewLayout(root, params) }
            },
        ).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(999).toFloat()
                setColor(AndroidColor.parseColor("#EE161924"))
                setStroke(dp(1), AndroidColor.parseColor("#42FFFFFF"))
            }
            setPadding(dp(8), dp(6), dp(6), dp(6))
        }

        // 1. 圆形封面 ImageView (28dp)
        val coverSize = dp(28)
        val cachedBmp = getCachedIconBitmap(session.serverUrl, snap.iconUrl)
        val coverView = ImageView(appContext).apply {
            layoutParams = LinearLayout.LayoutParams(coverSize, coverSize).apply {
                marginEnd = dp(8)
            }
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(AndroidColor.parseColor("#335E9CFF"))
            }
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            clipToOutline = true
            if (cachedBmp != null) {
                setImageBitmap(cachedBmp)
            } else {
                val pad = dp(6)
                setPadding(pad, pad, pad, pad)
                setImageResource(R.drawable.ic_plugin_media_queue)
                setColorFilter(AndroidColor.parseColor("#8AB4F8"))
            }
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                requestRestoreToForeground(appContext, snap.pluginId)
            }
        }
        pillRow.addView(coverView)

        // 2. 标题与副标题点击直达区
        val textCol = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginEnd = dp(6)
            }
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                requestRestoreToForeground(appContext, snap.pluginId)
            }
        }
        textCol.addView(
            TextView(appContext).apply {
                text = snap.title
                setTextColor(AndroidColor.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
                paint.isFakeBoldText = true
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                maxWidth = dp(148)
            },
        )
        val secondary = snap.subtitle.ifBlank { snap.statusText }
        if (secondary.isNotBlank()) {
            textCol.addView(
                TextView(appContext).apply {
                    text = secondary
                    setTextColor(AndroidColor.parseColor("#B5FFFFFF"))
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    maxWidth = dp(148)
                },
            )
        }
        pillRow.addView(textCol)

        // 3. 最多 3 个内联快捷纯图标按钮
        snap.actions.take(3).forEach { act ->
            val iconRes = resolveOverlayActionDrawableRes(act, snap.isPlaying)
            val btnSize = dp(28)
            val actionView: View = if (iconRes != null) {
                ImageView(appContext).apply {
                    layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                        marginEnd = dp(2)
                    }
                    val pad = dp(5)
                    setPadding(pad, pad, pad, pad)
                    setImageResource(iconRes)
                    val kind = classifyCapsuleAction(act)
                    val tint = when {
                        act.destructive -> AndroidColor.parseColor("#FF7B7B")
                        kind == CapsuleInlineActionKind.HEART && act.active -> AndroidColor.parseColor("#FF5C8A")
                        kind != CapsuleInlineActionKind.PLAY_PAUSE && act.active -> AndroidColor.parseColor("#8AB4F8")
                        else -> AndroidColor.WHITE
                    }
                    setColorFilter(tint)
                    contentDescription = act.label
                    setOnClickListener {
                        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        dispatchAction(act.id)
                    }
                }
            } else {
                TextView(appContext).apply {
                    layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                        marginEnd = dp(2)
                    }
                    gravity = Gravity.CENTER
                    text = act.label.take(1)
                    setTextColor(if (act.destructive) AndroidColor.parseColor("#FF7B7B") else AndroidColor.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                    paint.isFakeBoldText = true
                    contentDescription = act.label
                    setOnClickListener {
                        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        dispatchAction(act.id)
                    }
                }
            }
            pillRow.addView(actionView)
        }

        // 4. 关闭按钮 ✕
        val closeView = TextView(appContext).apply {
            layoutParams = LinearLayout.LayoutParams(dp(26), dp(26))
            gravity = Gravity.CENTER
            text = "✕"
            setTextColor(AndroidColor.parseColor("#B0FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            contentDescription = "关闭悬浮胶囊"
            setOnClickListener {
                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                closeAndRelease(appContext)
            }
        }
        pillRow.addView(closeView)
        root.addView(pillRow)

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
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        runCatching { wm.removeView(root) }
    }
}

/**
 * 应用内跨页面紧凑单行横向悬浮胶囊组件：
 * `[圆形鉴权封面 (29dp)] + [标题/副标题文字区 (点击直接恢复完整插件窗口)] + [最多 3 个内联快捷图标按钮] + [关闭按钮 ✕]`。
 */
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
    val view = LocalView.current
    val colors = LocalMoviePilotColors.current
    val snap = session.snapshot
    var dragOffsetX by remember { mutableFloatStateOf(0f) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(session.serverUrl, snap.iconUrl) {
        AndroidPluginCapsuleManager.ensureIconLoaded(session, view.context.applicationContext)
    }

    Surface(
        shape = RoundedCornerShape(999.dp),
        color = colors.surfaceContainerHigh.copy(alpha = 0.95f),
        border = BorderStroke(1.dp, colors.accent.copy(alpha = 0.36f)),
        shadowElevation = 10.dp,
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
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(start = 8.dp, end = 5.dp, top = 5.dp, bottom = 5.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .clickable {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        if (isExpanded) onToggleExpanded(false)
                        onOpenPluginWindow()
                    }
                    .padding(end = 4.dp, top = 1.dp, bottom = 1.dp),
            ) {
                CapsulePluginIcon(
                    serverUrl = session.serverUrl,
                    iconUrl = snap.iconUrl,
                    accent = colors.accent,
                    sizeDp = 29,
                )
                Column(modifier = Modifier.widthIn(max = 152.dp)) {
                    Text(
                        text = snap.title,
                        color = colors.textPrimary,
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    val secondary = snap.subtitle.ifBlank { snap.statusText }
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
            }

            snap.actions.take(3).forEach { action ->
                CapsuleInlineActionButton(
                    action = action,
                    isPlaying = snap.isPlaying,
                    onClick = {
                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                        onDispatchAction(action.id)
                    },
                )
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

/** 胶囊内联纯图标快捷按钮（自动映射常见媒体控制动作并实时同步播放状态）。 */
@Composable
private fun CapsuleInlineActionButton(
    action: PluginCapsuleActionItem,
    isPlaying: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val kind = classifyCapsuleAction(action)
    val tint = when {
        action.destructive -> colors.danger
        kind == CapsuleInlineActionKind.HEART && action.active -> Color(0xFFFF5C8A)
        kind != CapsuleInlineActionKind.PLAY_PAUSE && action.active -> colors.accent
        else -> colors.textPrimary
    }

    IconButton(
        onClick = onClick,
        modifier = Modifier.size(28.dp),
    ) {
        val vectorIcon: ImageVector? = when (kind) {
            CapsuleInlineActionKind.PREVIOUS -> Icons.Rounded.SkipPrevious
            CapsuleInlineActionKind.PLAY_PAUSE -> if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow
            CapsuleInlineActionKind.NEXT -> Icons.Rounded.SkipNext
            else -> null
        }
        val drawableRes: Int? = when (kind) {
            CapsuleInlineActionKind.HEART ->
                if (action.active) R.drawable.ic_plugin_media_heart_filled else R.drawable.ic_plugin_media_heart_outline
            CapsuleInlineActionKind.REPEAT_ONE -> R.drawable.ic_plugin_media_repeat_one
            CapsuleInlineActionKind.REPEAT -> R.drawable.ic_plugin_media_repeat
            CapsuleInlineActionKind.SHUFFLE -> R.drawable.ic_plugin_media_shuffle
            CapsuleInlineActionKind.LYRICS -> R.drawable.ic_plugin_media_lyrics
            else -> null
        }
        when {
            vectorIcon != null -> Icon(
                imageVector = vectorIcon,
                contentDescription = action.label,
                tint = tint,
                modifier = Modifier.size(18.dp),
            )
            drawableRes != null -> Icon(
                painter = painterResource(drawableRes),
                contentDescription = action.label,
                tint = tint,
                modifier = Modifier.size(16.dp),
            )
            else -> Icon(
                imageVector = Icons.Rounded.Star,
                contentDescription = action.label,
                tint = tint,
                modifier = Modifier.size(15.dp),
            )
        }
    }
}

/** 胶囊圆形封面或默认插件图标（支持相对路径原生鉴权缓存渲染）。 */
@Composable
private fun CapsulePluginIcon(
    serverUrl: String,
    iconUrl: String?,
    accent: Color,
    sizeDp: Int,
) {
    val revision = AndroidPluginCapsuleManager.iconCacheRevision
    val bitmap = remember(serverUrl, iconUrl, revision) {
        AndroidPluginCapsuleManager.getCachedIconBitmap(serverUrl, iconUrl)
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
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
                modifier = Modifier.size((sizeDp * 0.55f).dp),
            )
        }
    }
}
