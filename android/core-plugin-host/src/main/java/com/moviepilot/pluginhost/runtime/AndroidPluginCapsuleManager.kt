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
import android.view.WindowInsets as PlatformWindowInsets
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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
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
import kotlinx.serialization.json.intOrNull
import kotlin.math.abs
import kotlin.math.roundToInt

/** 最小化胶囊贴边方向（用于左右边缘自动吸附并收缩为半圆「超级最小化」形态）。 */
enum class CapsuleDockedEdge(val wireValue: String) {
    NONE("none"),
    LEFT("left"),
    RIGHT("right");

    companion object {
        fun fromWire(raw: String?): CapsuleDockedEdge = when (raw?.lowercase()) {
            "left" -> LEFT
            "right" -> RIGHT
            else -> NONE
        }
    }
}

/** 最小化胶囊在安全区内的归一化坐标与贴边吸附状态（供应用内浮层与系统级悬浮窗共享持久化）。 */
data class CapsulePlacementState(
    val normX: Float = 1f,
    val normY: Float = 0.78f,
    val dockedEdge: CapsuleDockedEdge = CapsuleDockedEdge.NONE,
) {
    val isSuperMinimized: Boolean
        get() = dockedEdge != CapsuleDockedEdge.NONE
}

/** 屏幕视口与安全区边界参数（单位 px）。 */
data class CapsuleSafeBounds(
    val viewportWidthPx: Int,
    val viewportHeightPx: Int,
    val insetLeftPx: Int,
    val insetTopPx: Int,
    val insetRightPx: Int,
    val insetBottomPx: Int,
    val horizontalMarginPx: Int,
    val verticalMarginPx: Int,
)

/**
 * 应用内 Compose 悬浮胶囊与系统级 `TYPE_APPLICATION_OVERLAY` 悬浮窗共用的纯几何边界约束与贴边吸附计算器：
 * 1. 拖动全程限制在安全区内（避开状态栏、底部手势条、挖孔/刘海）；
 * 2. 松手时若距左/右安全边缘小于 `snapThresholdPx`（默认 24dp，可配置），自动贴边收缩为半圆「超级最小化」；
 * 3. 点击半圆恢复完整单行胶囊时自动内缩回安全留白区间并持久化安全坐标，杜绝越界丢失。
 */
internal object PluginCapsuleLayoutCalculator {
    const val DEFAULT_EDGE_SNAP_THRESHOLD_DP = 24
    const val MAX_EDGE_SNAP_THRESHOLD_DP = 72

    fun normalizeSnapThresholdDp(rawDp: Int?): Int =
        (rawDp ?: DEFAULT_EDGE_SNAP_THRESHOLD_DP).coerceIn(0, MAX_EDGE_SNAP_THRESHOLD_DP)

    /** 拖动过程中实时将左上角像素坐标约束在安全区内（允许触及左右安全边缘以触发贴边吸附，绝不越出屏幕）。 */
    fun clampDuringDrag(
        rawX: Int,
        rawY: Int,
        itemWidthPx: Int,
        itemHeightPx: Int,
        bounds: CapsuleSafeBounds,
    ): Pair<Int, Int> {
        val safeW = itemWidthPx.coerceAtLeast(1)
        val safeH = itemHeightPx.coerceAtLeast(1)
        val minDragX = bounds.insetLeftPx.coerceAtLeast(0)
        val maxDragX = (bounds.viewportWidthPx - bounds.insetRightPx.coerceAtLeast(0) - safeW)
            .coerceAtLeast(minDragX)
        val minY = (bounds.insetTopPx + bounds.verticalMarginPx).coerceAtLeast(0)
        val maxY = (bounds.viewportHeightPx - bounds.insetBottomPx - bounds.verticalMarginPx - safeH)
            .coerceAtLeast(minY)
        return rawX.coerceIn(minDragX, maxDragX) to rawY.coerceIn(minY, maxY)
    }

    /** 松手后根据左右边缘距离判定是否进入贴边「超级最小化」，并换算为可持久化的归一化安全坐标。 */
    fun settleAfterDrag(
        rawX: Int,
        rawY: Int,
        itemWidthPx: Int,
        itemHeightPx: Int,
        bounds: CapsuleSafeBounds,
        snapThresholdPx: Int,
    ): CapsulePlacementState {
        val safeW = itemWidthPx.coerceAtLeast(1)
        val safeH = itemHeightPx.coerceAtLeast(1)
        val (clampedX, clampedY) = clampDuringDrag(rawX, rawY, safeW, safeH, bounds)

        val leftSafeEdge = bounds.insetLeftPx.coerceAtLeast(0)
        val rightSafeEdge = (bounds.viewportWidthPx - bounds.insetRightPx.coerceAtLeast(0))
            .coerceAtLeast(leftSafeEdge + safeW)
        val distToLeft = (clampedX - leftSafeEdge).coerceAtLeast(0)
        val distToRight = (rightSafeEdge - (clampedX + safeW)).coerceAtLeast(0)

        val minY = (bounds.insetTopPx + bounds.verticalMarginPx).coerceAtLeast(0)
        val maxY = (bounds.viewportHeightPx - bounds.insetBottomPx - bounds.verticalMarginPx - safeH)
            .coerceAtLeast(minY)
        val normY = if (maxY > minY) {
            ((clampedY - minY).toFloat() / (maxY - minY).toFloat()).coerceIn(0f, 1f)
        } else {
            0.78f
        }

        if (snapThresholdPx > 0) {
            if (distToLeft <= snapThresholdPx && distToLeft <= distToRight) {
                return CapsulePlacementState(normX = 0f, normY = normY, dockedEdge = CapsuleDockedEdge.LEFT)
            }
            if (distToRight <= snapThresholdPx) {
                return CapsulePlacementState(normX = 1f, normY = normY, dockedEdge = CapsuleDockedEdge.RIGHT)
            }
        }

        val minFreeX = leftSafeEdge + bounds.horizontalMarginPx.coerceAtLeast(0)
        val maxFreeX = (rightSafeEdge - bounds.horizontalMarginPx.coerceAtLeast(0) - safeW)
            .coerceAtLeast(minFreeX)
        val settledX = clampedX.coerceIn(minFreeX, maxFreeX)
        val normX = if (maxFreeX > minFreeX) {
            ((settledX - minFreeX).toFloat() / (maxFreeX - minFreeX).toFloat()).coerceIn(0f, 1f)
        } else {
            1f
        }
        return CapsulePlacementState(normX = normX, normY = normY, dockedEdge = CapsuleDockedEdge.NONE)
    }

    /** 将持久化归一化状态还原为当前屏幕与组件尺寸下的安全左上角像素坐标。 */
    fun resolveTopLeftPx(
        placement: CapsulePlacementState,
        itemWidthPx: Int,
        itemHeightPx: Int,
        bounds: CapsuleSafeBounds,
    ): Pair<Int, Int> {
        val safeW = itemWidthPx.coerceAtLeast(1)
        val safeH = itemHeightPx.coerceAtLeast(1)
        val leftSafeEdge = bounds.insetLeftPx.coerceAtLeast(0)
        val rightSafeEdge = (bounds.viewportWidthPx - bounds.insetRightPx.coerceAtLeast(0))
            .coerceAtLeast(leftSafeEdge + safeW)

        val minY = (bounds.insetTopPx + bounds.verticalMarginPx).coerceAtLeast(0)
        val maxY = (bounds.viewportHeightPx - bounds.insetBottomPx - bounds.verticalMarginPx - safeH)
            .coerceAtLeast(minY)
        val resolvedY = (minY + ((maxY - minY) * placement.normY.coerceIn(0f, 1f)).roundToInt())
            .coerceIn(minY, maxY)

        val resolvedX = when (placement.dockedEdge) {
            CapsuleDockedEdge.LEFT -> leftSafeEdge
            CapsuleDockedEdge.RIGHT -> (rightSafeEdge - safeW).coerceAtLeast(leftSafeEdge)
            CapsuleDockedEdge.NONE -> {
                val minFreeX = leftSafeEdge + bounds.horizontalMarginPx.coerceAtLeast(0)
                val maxFreeX = (rightSafeEdge - bounds.horizontalMarginPx.coerceAtLeast(0) - safeW)
                    .coerceAtLeast(minFreeX)
                (minFreeX + ((maxFreeX - minFreeX) * placement.normX.coerceIn(0f, 1f)).roundToInt())
                    .coerceIn(minFreeX, maxFreeX)
            }
        }
        return resolvedX to resolvedY
    }

    /** 从贴边「超级最小化」点击恢复为完整单行胶囊，保持当前纵向位置并停靠在对应侧安全留白内。 */
    fun expandFromDocked(placement: CapsulePlacementState): CapsulePlacementState = when (placement.dockedEdge) {
        CapsuleDockedEdge.LEFT -> placement.copy(normX = 0f, dockedEdge = CapsuleDockedEdge.NONE)
        CapsuleDockedEdge.RIGHT -> placement.copy(normX = 1f, dockedEdge = CapsuleDockedEdge.NONE)
        CapsuleDockedEdge.NONE -> placement
    }
}

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
    val capsuleTitle: String? = null,
    val capsuleArtist: String? = null,
    val statusText: String = "",
    val iconUrl: String? = null,
    val mode: String = "jump", // "jump" | "mini"
    val isPlaying: Boolean = false,
    val keepOutsideApp: Boolean = false,
    val edgeSnapThresholdDp: Int = PluginCapsuleLayoutCalculator.DEFAULT_EDGE_SNAP_THRESHOLD_DP,
    val actions: List<PluginCapsuleActionItem> = emptyList(),
) {
    val isMiniWindowMode: Boolean
        get() = mode.equals("mini", ignoreCase = true) || actions.isNotEmpty()

    /** 胶囊主标题：优先展示插件显式提供的短标题 `capsuleTitle`，否则回退完整 `title`。 */
    val displayTitle: String
        get() = capsuleTitle?.takeIf { it.isNotBlank() } ?: title

    /** 胶囊副标题：优先展示插件显式提供的短歌手/副标题 `capsuleArtist`，否则回退 `subtitle` 或 `statusText`。 */
    val displaySubtitle: String
        get() = capsuleArtist?.takeIf { it.isNotBlank() } ?: subtitle.ifBlank { statusText }

    /** 合并插件增量更新补丁并保持播放按钮状态联动。 */
    fun mergePatch(payload: JsonObject): PluginCapsuleSnapshot {
        fun JsonElement?.str(): String? = when (this) {
            is JsonNull, null -> null
            is JsonPrimitive -> content.takeIf { it != "null" }
            else -> null
        }
        val nextTitle = payload["title"].str()?.takeIf { it.isNotBlank() } ?: title
        val nextSubtitle = payload["subtitle"].str() ?: subtitle
        val nextCapsuleTitle = if (payload.containsKey("capsuleTitle")) {
            payload["capsuleTitle"].str()?.trim()?.takeIf { it.isNotEmpty() }
        } else {
            capsuleTitle
        }
        val nextCapsuleArtist = if (payload.containsKey("capsuleArtist")) {
            payload["capsuleArtist"].str()?.trim()?.takeIf { it.isNotEmpty() }
        } else {
            capsuleArtist
        }
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
        val rawSnapDp = (payload["edgeSnapThresholdDp"] as? JsonPrimitive)?.intOrNull
            ?: (payload["snapThresholdDp"] as? JsonPrimitive)?.intOrNull
        val nextSnapDp = if (rawSnapDp != null) {
            PluginCapsuleLayoutCalculator.normalizeSnapThresholdDp(rawSnapDp)
        } else {
            edgeSnapThresholdDp
        }
        return copy(
            title = nextTitle,
            subtitle = nextSubtitle,
            capsuleTitle = nextCapsuleTitle,
            capsuleArtist = nextCapsuleArtist,
            statusText = nextStatus,
            iconUrl = nextIcon,
            mode = nextMode,
            isPlaying = nextPlaying,
            keepOutsideApp = nextKeepOutside,
            edgeSnapThresholdDp = nextSnapDp,
            actions = syncPlayActionActive(parsedActions, nextPlaying),
        )
    }

    /** 由原生音频状态或 `audio.setNowPlaying` 同步胶囊字段，保留当前曲目的专用短标题 `capsuleTitle` / `capsuleArtist`。 */
    internal fun applyAudioSync(
        isPlaying: Boolean,
        title: String? = null,
        subtitle: String? = null,
        capsuleTitle: String? = null,
        capsuleArtist: String? = null,
        iconUrl: String? = null,
    ): PluginCapsuleSnapshot {
        val cleanTitle = title?.trim()?.takeIf { it.isNotEmpty() }
        val cleanSubtitle = subtitle?.trim()?.takeIf { it.isNotEmpty() }
        val cleanCapTitle = capsuleTitle?.trim()?.takeIf { it.isNotEmpty() }
        val cleanCapArtist = capsuleArtist?.trim()?.takeIf { it.isNotEmpty() }
        val trackChanged = cleanTitle != null && cleanTitle != this.title
        val nextTitle = cleanTitle ?: this.title
        val nextSubtitle = cleanSubtitle ?: this.subtitle
        val nextCapTitle = cleanCapTitle ?: if (trackChanged) null else this.capsuleTitle
        val nextCapArtist = cleanCapArtist ?: if (trackChanged) null else this.capsuleArtist
        val nextIcon = iconUrl?.trim()?.takeIf { it.isNotEmpty() } ?: this.iconUrl
        return copy(
            title = nextTitle,
            subtitle = nextSubtitle,
            capsuleTitle = nextCapTitle,
            capsuleArtist = nextCapArtist,
            iconUrl = nextIcon,
            isPlaying = isPlaying,
            actions = syncPlayActionActive(actions, isPlaying),
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
            val rawSnapDp = (payload["edgeSnapThresholdDp"] as? JsonPrimitive)?.intOrNull
                ?: (payload["snapThresholdDp"] as? JsonPrimitive)?.intOrNull
            return PluginCapsuleSnapshot(
                pluginId = pluginId,
                pluginName = resolvedName,
                title = resolvedTitle,
                subtitle = payload["subtitle"].str().orEmpty(),
                capsuleTitle = payload["capsuleTitle"].str()?.trim()?.takeIf { it.isNotEmpty() },
                capsuleArtist = payload["capsuleArtist"].str()?.trim()?.takeIf { it.isNotEmpty() },
                statusText = payload["statusText"].str().orEmpty(),
                iconUrl = payload["iconUrl"].str()?.takeIf { it.isNotBlank() },
                mode = resolvedMode,
                isPlaying = resolvedPlaying,
                keepOutsideApp = (payload["keepOutsideApp"] as? JsonPrimitive)?.booleanOrNull ?: false,
                edgeSnapThresholdDp = PluginCapsuleLayoutCalculator.normalizeSnapThresholdDp(rawSnapDp),
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
 * 支持触摸拖拽拦截与松手吸附回调的系统悬浮胶囊横向容器：
 * 当手指滑动距离超过阈值时由外层统一接管窗口安全区移动，松手时执行边缘吸附收敛；
 * 轻点子按钮、半圆胶囊或标题区时正常触发各自点击事件。
 */
private class DraggableOverlayPillRow(
    context: Context,
    private val touchSlopPx: Int,
    private val onDragBy: (dx: Int, dy: Int) -> Unit,
    private val onDragEnd: () -> Unit,
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
                    isDragging = true
                    lastRawX = event.rawX
                    lastRawY = event.rawY
                    onDragBy(dx, dy)
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val hadDragged = isDragging
                isDragging = false
                if (hadDragged) {
                    onDragEnd()
                    return true
                }
                performClick()
                return true
            }
        }
        return super.onTouchEvent(event)
    }
}

/**
 * Android 端联邦插件最小化保活与紧凑单行悬浮胶囊协调器：
 * 1. 最小化时不调用 `plugin.unmount`，保留运行态 `WebView`、JS 上下文与音频播放状态；
 * 2. 统一采用紧凑单行横向播控胶囊，并在靠近左右边缘时自动吸附收缩为半圆「超级最小化」；
 * 3. 应用内浮条与 `TYPE_APPLICATION_OVERLAY` 系统悬浮窗共用同一套安全区边界约束与持久化坐标；
 * 4. 原生音频状态变化与 `setNowPlaying` 自动同步更新胶囊播放/暂停图标及曲目信息。
 */
object AndroidPluginCapsuleManager {
    private const val PREF_CAPSULE_PLACEMENT = "mp_plugin_capsule_prefs_v1"
    private const val KEY_NORM_X = "norm_x"
    private const val KEY_NORM_Y = "norm_y"
    private const val KEY_DOCKED_EDGE = "docked_edge"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val iconCache = LruCache<String, Bitmap>(24)
    private val inflightIconKeys = HashSet<String>()

    var currentSession by mutableStateOf<MinimizedAndroidPluginSession?>(null)
        private set

    var placementState by mutableStateOf(CapsulePlacementState())
        private set

    var isMiniCardExpanded by mutableStateOf(false)
    var restoreRequestNonce by mutableIntStateOf(0)
        private set
    var pendingRestorePluginId by mutableStateOf<String?>(null)
        private set
    var iconCacheRevision by mutableIntStateOf(0)
        private set

    private var hasLoadedPlacement = false
    private var isAppInBackground = false
    private var systemOverlayRoot: LinearLayout? = null
    private var overlayLayoutParams: WindowManager.LayoutParams? = null

    /** 从本地 `SharedPreferences` 懒加载已持久化的安全吸附坐标。 */
    fun ensurePlacementLoaded(context: Context) {
        if (hasLoadedPlacement) return
        hasLoadedPlacement = true
        val prefs = context.applicationContext.getSharedPreferences(PREF_CAPSULE_PLACEMENT, Context.MODE_PRIVATE)
        val normX = prefs.getFloat(KEY_NORM_X, 1f).coerceIn(0f, 1f)
        val normY = prefs.getFloat(KEY_NORM_Y, 0.78f).coerceIn(0f, 1f)
        val dockedEdge = CapsuleDockedEdge.fromWire(prefs.getString(KEY_DOCKED_EDGE, null))
        placementState = CapsulePlacementState(
            normX = normX,
            normY = normY,
            dockedEdge = dockedEdge,
        )
    }

    /** 更新并持久化胶囊位置与贴边吸附状态，形态变化时同步推送 `capsule.state`。 */
    fun updatePlacement(context: Context, next: CapsulePlacementState) {
        val sanitized = CapsulePlacementState(
            normX = next.normX.coerceIn(0f, 1f),
            normY = next.normY.coerceIn(0f, 1f),
            dockedEdge = next.dockedEdge,
        )
        val prevEdge = placementState.dockedEdge
        placementState = sanitized
        hasLoadedPlacement = true
        val appCtx = context.applicationContext
        appCtx.getSharedPreferences(PREF_CAPSULE_PLACEMENT, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_NORM_X, sanitized.normX)
            .putFloat(KEY_NORM_Y, sanitized.normY)
            .putString(KEY_DOCKED_EDGE, sanitized.dockedEdge.wireValue)
            .apply()
        if (prevEdge != sanitized.dockedEdge) {
            currentSession?.slot?.bridge?.sendCapsuleState(
                minimized = true,
                superMinimized = sanitized.isSuperMinimized,
                dockedEdge = sanitized.dockedEdge.wireValue,
            )
            if (isAppInBackground) {
                refreshSystemOverlayIfNeeded(appCtx)
            }
        }
    }

    /** 点击贴边半圆「超级最小化」胶囊时恢复为完整单行胶囊并停留在安全区内。 */
    fun expandSuperMinimized(context: Context) {
        if (!placementState.isSuperMinimized) return
        val expanded = PluginCapsuleLayoutCalculator.expandFromDocked(placementState)
        updatePlacement(context, expanded)
    }

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
        ensurePlacementLoaded(appCtx)
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
        session.slot.bridge.sendCapsuleState(
            minimized = true,
            superMinimized = placementState.isSuperMinimized,
            dockedEdge = placementState.dockedEdge.wireValue,
        )

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
        capsuleTitle: String? = null,
        capsuleArtist: String? = null,
        iconUrl: String? = null,
    ) {
        mainHandler.post {
            val cur = currentSession ?: return@post
            if (pluginId.isNotBlank() && !cur.pluginId.equals(pluginId, ignoreCase = true)) {
                return@post
            }
            val snap = cur.snapshot
            val updatedSnap = snap.applyAudioSync(
                isPlaying = isPlaying,
                title = title,
                subtitle = subtitle,
                capsuleTitle = capsuleTitle,
                capsuleArtist = capsuleArtist,
                iconUrl = iconUrl,
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
        cur.slot.bridge.sendCapsuleState(minimized = false, superMinimized = false, dockedEdge = "none")
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

    /** 宿主 Activity 进入前台：收起系统级悬浮窗，交由应用内 Compose 悬浮胶囊无缝承接同一位置状态。 */
    fun onHostAppForegrounded(context: Context) {
        isAppInBackground = false
        removeSystemOverlay(context.applicationContext)
    }

    /** 宿主 Activity 退至后台：若插件声明 `keepOutsideApp` 且具备悬浮窗权限，按同一安全区位置展示系统悬浮窗。 */
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

    /** 计算系统窗口当前真实屏幕视口与状态栏/手势条/刘海安全区内边距。 */
    private fun querySystemSafeBounds(appContext: Context, wm: WindowManager, horizontalMarginPx: Int, verticalMarginPx: Int): CapsuleSafeBounds {
        val dm = appContext.resources.displayMetrics
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = wm.currentWindowMetrics
            val rect = metrics.bounds
            val insets = metrics.windowInsets.getInsetsIgnoringVisibility(
                PlatformWindowInsets.Type.systemBars() or PlatformWindowInsets.Type.displayCutout(),
            )
            return CapsuleSafeBounds(
                viewportWidthPx = rect.width().coerceAtLeast(dm.widthPixels),
                viewportHeightPx = rect.height().coerceAtLeast(dm.heightPixels),
                insetLeftPx = insets.left,
                insetTopPx = insets.top,
                insetRightPx = insets.right,
                insetBottomPx = insets.bottom,
                horizontalMarginPx = horizontalMarginPx,
                verticalMarginPx = verticalMarginPx,
            )
        }
        val statusResId = appContext.resources.getIdentifier("status_bar_height", "dimen", "android")
        val navResId = appContext.resources.getIdentifier("navigation_bar_height", "dimen", "android")
        val statusBarPx = if (statusResId > 0) appContext.resources.getDimensionPixelSize(statusResId) else (28 * dm.density).roundToInt()
        val navBarPx = if (navResId > 0) appContext.resources.getDimensionPixelSize(navResId) else (24 * dm.density).roundToInt()
        return CapsuleSafeBounds(
            viewportWidthPx = dm.widthPixels,
            viewportHeightPx = dm.heightPixels,
            insetLeftPx = 0,
            insetTopPx = statusBarPx,
            insetRightPx = 0,
            insetBottomPx = navBarPx,
            horizontalMarginPx = horizontalMarginPx,
            verticalMarginPx = verticalMarginPx,
        )
    }

    /** 刷新系统级 `WindowManager` 紧凑单行圆角悬浮胶囊（支持贴边半圆「超级最小化」与安全区约束）。 */
    @SuppressLint("ClickableViewAccessibility")
    private fun refreshSystemOverlayIfNeeded(appContext: Context) {
        ensurePlacementLoaded(appContext)
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

        val dockedEdge = placementState.dockedEdge
        val isSuperMini = dockedEdge != CapsuleDockedEdge.NONE
        val snapThresholdPx = dp(snap.edgeSnapThresholdDp)
        val hMarginPx = dp(12)
        val vMarginPx = dp(10)

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
            gravity = Gravity.TOP or Gravity.START
            overlayLayoutParams = this
        }
        params.gravity = Gravity.TOP or Gravity.START

        val root = systemOverlayRoot ?: LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
        }
        root.removeAllViews()

        fun currentMeasuredSize(): Pair<Int, Int> {
            val w = root.width.takeIf { it > 0 } ?: root.measuredWidth.takeIf { it > 0 } ?: if (isSuperMini) dp(42) else dp(206)
            val h = root.height.takeIf { it > 0 } ?: root.measuredHeight.takeIf { it > 0 } ?: dp(38)
            return w to h
        }

        val pillRadius = dp(999).toFloat()
        val pillRow = DraggableOverlayPillRow(
            context = appContext,
            touchSlopPx = dp(5),
            onDragBy = { dx, dy ->
                val bounds = querySystemSafeBounds(appContext, wm, hMarginPx, vMarginPx)
                val (itemW, itemH) = currentMeasuredSize()
                val (clampedX, clampedY) = PluginCapsuleLayoutCalculator.clampDuringDrag(
                    rawX = params.x + dx,
                    rawY = params.y + dy,
                    itemWidthPx = itemW,
                    itemHeightPx = itemH,
                    bounds = bounds,
                )
                params.x = clampedX
                params.y = clampedY
                runCatching { wm.updateViewLayout(root, params) }
            },
            onDragEnd = {
                val bounds = querySystemSafeBounds(appContext, wm, hMarginPx, vMarginPx)
                val (itemW, itemH) = currentMeasuredSize()
                val nextPlacement = PluginCapsuleLayoutCalculator.settleAfterDrag(
                    rawX = params.x,
                    rawY = params.y,
                    itemWidthPx = itemW,
                    itemHeightPx = itemH,
                    bounds = bounds,
                    snapThresholdPx = snapThresholdPx,
                )
                val edgeChanged = nextPlacement.dockedEdge != placementState.dockedEdge
                updatePlacement(appContext, nextPlacement)
                if (!edgeChanged) {
                    val (settledX, settledY) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
                        placement = nextPlacement,
                        itemWidthPx = itemW,
                        itemHeightPx = itemH,
                        bounds = bounds,
                    )
                    params.x = settledX
                    params.y = settledY
                    runCatching { wm.updateViewLayout(root, params) }
                }
            },
        ).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadii = when (dockedEdge) {
                    CapsuleDockedEdge.LEFT -> floatArrayOf(0f, 0f, pillRadius, pillRadius, pillRadius, pillRadius, 0f, 0f)
                    CapsuleDockedEdge.RIGHT -> floatArrayOf(pillRadius, pillRadius, 0f, 0f, 0f, 0f, pillRadius, pillRadius)
                    CapsuleDockedEdge.NONE -> FloatArray(8) { pillRadius }
                }
                setColor(AndroidColor.parseColor("#EE161924"))
                setStroke(
                    dp(1),
                    if (snap.isPlaying) AndroidColor.parseColor("#885E9CFF") else AndroidColor.parseColor("#42FFFFFF"),
                )
            }
            when (dockedEdge) {
                CapsuleDockedEdge.LEFT -> setPadding(dp(6), dp(5), dp(8), dp(5))
                CapsuleDockedEdge.RIGHT -> setPadding(dp(8), dp(5), dp(6), dp(5))
                CapsuleDockedEdge.NONE -> setPadding(dp(6), dp(5), dp(4), dp(5))
            }
        }

        val coverSize = if (isSuperMini) dp(28) else dp(26)
        val cachedBmp = getCachedIconBitmap(session.serverUrl, snap.iconUrl)
        val coverView = ImageView(appContext).apply {
            layoutParams = LinearLayout.LayoutParams(coverSize, coverSize).apply {
                marginEnd = if (isSuperMini) 0 else dp(6)
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
                if (isSuperMini) {
                    expandSuperMinimized(appContext)
                } else {
                    requestRestoreToForeground(appContext, snap.pluginId)
                }
            }
        }
        pillRow.addView(coverView)

        if (isSuperMini) {
            pillRow.contentDescription = "展开最小化胶囊"
            pillRow.setOnClickListener {
                it.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                expandSuperMinimized(appContext)
            }
        } else {
            val textCol = LinearLayout(appContext).apply {
                orientation = LinearLayout.VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    dp(64),
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply {
                    marginEnd = dp(2)
                }
                setOnClickListener {
                    performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    requestRestoreToForeground(appContext, snap.pluginId)
                }
            }
            textCol.addView(
                TextView(appContext).apply {
                    text = snap.displayTitle
                    setTextColor(AndroidColor.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    paint.isFakeBoldText = true
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                },
            )
            val secondary = snap.displaySubtitle
            if (secondary.isNotBlank()) {
                textCol.addView(
                    TextView(appContext).apply {
                        text = secondary
                        setTextColor(AndroidColor.parseColor("#B5FFFFFF"))
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                        maxLines = 1
                        ellipsize = TextUtils.TruncateAt.END
                    },
                )
            }
            pillRow.addView(textCol)

            snap.actions.take(3).forEach { act ->
                val iconRes = resolveOverlayActionDrawableRes(act, snap.isPlaying)
                val btnSize = dp(25)
                val actionView: View = if (iconRes != null) {
                    ImageView(appContext).apply {
                        layoutParams = LinearLayout.LayoutParams(btnSize, btnSize).apply {
                            marginEnd = dp(1)
                        }
                        val pad = dp(4)
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
                            marginEnd = dp(1)
                        }
                        gravity = Gravity.CENTER
                        text = act.label.take(1)
                        setTextColor(if (act.destructive) AndroidColor.parseColor("#FF7B7B") else AndroidColor.WHITE)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
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

            val closeView = TextView(appContext).apply {
                layoutParams = LinearLayout.LayoutParams(dp(23), dp(25))
                gravity = Gravity.CENTER
                text = "✕"
                setTextColor(AndroidColor.parseColor("#B0FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
                contentDescription = "关闭悬浮胶囊"
                setOnClickListener {
                    performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    closeAndRelease(appContext)
                }
            }
            pillRow.addView(closeView)
        }

        root.addView(pillRow)
        val unspec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        root.measure(unspec, unspec)
        val initBounds = querySystemSafeBounds(appContext, wm, hMarginPx, vMarginPx)
        val (initX, initY) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
            placement = placementState,
            itemWidthPx = root.measuredWidth.coerceAtLeast(dp(42)),
            itemHeightPx = root.measuredHeight.coerceAtLeast(dp(38)),
            bounds = initBounds,
        )
        params.x = initX
        params.y = initY

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
 * - 与 `TYPE_APPLICATION_OVERLAY` 系统悬浮窗共用安全区边界约束与持久化坐标；
 * - 拖至左右边缘 `< edgeSnapThresholdDp`（默认 24dp）松手自动贴边收缩为半圆「超级最小化」，点击恢复完整单行胶囊。
 */
@Composable
fun PluginFloatingCapsuleOverlay(
    session: MinimizedAndroidPluginSession,
    isExpanded: Boolean,
    onToggleExpanded: (Boolean) -> Unit,
    onOpenPluginWindow: () -> Unit,
    onDispatchAction: (String) -> Unit,
    onCloseCapsule: () -> Unit,
    bottomClearanceDp: Dp = 96.dp,
    modifier: Modifier = Modifier,
) {
    val view = LocalView.current
    val appContext = view.context.applicationContext
    val colors = LocalMoviePilotColors.current
    val density = LocalDensity.current
    val layoutDirection = LocalLayoutDirection.current
    val safeDrawingInsets = WindowInsets.safeDrawing
    val snap = session.snapshot

    LaunchedEffect(Unit) {
        AndroidPluginCapsuleManager.ensurePlacementLoaded(appContext)
    }
    LaunchedEffect(session.serverUrl, snap.iconUrl) {
        AndroidPluginCapsuleManager.ensureIconLoaded(session, appContext)
    }

    val placement = AndroidPluginCapsuleManager.placementState
    val dockedEdge = placement.dockedEdge
    val isSuperMini = dockedEdge != CapsuleDockedEdge.NONE

    var measuredSize by remember(isSuperMini) { mutableStateOf(IntSize.Zero) }
    var isDragging by remember { mutableStateOf(false) }
    var liveDragX by remember { mutableFloatStateOf(0f) }
    var liveDragY by remember { mutableFloatStateOf(0f) }

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val viewportWidthPx = constraints.maxWidth.coerceAtLeast(1)
        val viewportHeightPx = constraints.maxHeight.coerceAtLeast(1)
        val insetLeftPx = safeDrawingInsets.getLeft(density, layoutDirection)
        val insetTopPx = safeDrawingInsets.getTop(density)
        val insetRightPx = safeDrawingInsets.getRight(density, layoutDirection)
        val insetBottomPx = safeDrawingInsets.getBottom(density) + with(density) { bottomClearanceDp.roundToPx() }
        val hMarginPx = with(density) { 12.dp.roundToPx() }
        val vMarginPx = with(density) { 8.dp.roundToPx() }
        val snapThresholdPx = with(density) { snap.edgeSnapThresholdDp.dp.roundToPx() }
        val fallbackWidthPx = with(density) { (if (isSuperMini) 42.dp else 206.dp).roundToPx() }
        val fallbackHeightPx = with(density) { 38.dp.roundToPx() }
        val itemWidthPx = measuredSize.width.takeIf { it > 0 } ?: fallbackWidthPx
        val itemHeightPx = measuredSize.height.takeIf { it > 0 } ?: fallbackHeightPx

        val safeBounds = CapsuleSafeBounds(
            viewportWidthPx = viewportWidthPx,
            viewportHeightPx = viewportHeightPx,
            insetLeftPx = insetLeftPx,
            insetTopPx = insetTopPx,
            insetRightPx = insetRightPx,
            insetBottomPx = insetBottomPx,
            horizontalMarginPx = hMarginPx,
            verticalMarginPx = vMarginPx,
        )
        val (resolvedX, resolvedY) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
            placement = placement,
            itemWidthPx = itemWidthPx,
            itemHeightPx = itemHeightPx,
            bounds = safeBounds,
        )
        val (displayX, displayY) = if (isDragging) {
            PluginCapsuleLayoutCalculator.clampDuringDrag(
                rawX = liveDragX.roundToInt(),
                rawY = liveDragY.roundToInt(),
                itemWidthPx = itemWidthPx,
                itemHeightPx = itemHeightPx,
                bounds = safeBounds,
            )
        } else {
            resolvedX to resolvedY
        }

        val pillShape = when (dockedEdge) {
            CapsuleDockedEdge.LEFT -> RoundedCornerShape(
                topStart = 0.dp,
                bottomStart = 0.dp,
                topEnd = 999.dp,
                bottomEnd = 999.dp,
            )
            CapsuleDockedEdge.RIGHT -> RoundedCornerShape(
                topStart = 999.dp,
                bottomStart = 999.dp,
                topEnd = 0.dp,
                bottomEnd = 0.dp,
            )
            CapsuleDockedEdge.NONE -> RoundedCornerShape(999.dp)
        }

        Surface(
            shape = pillShape,
            color = colors.surfaceContainerHigh.copy(alpha = 0.95f),
            border = BorderStroke(
                1.dp,
                colors.accent.copy(alpha = if (snap.isPlaying && isSuperMini) 0.62f else 0.36f),
            ),
            shadowElevation = 10.dp,
            modifier = Modifier
                .onSizeChanged { measuredSize = it }
                .offset { IntOffset(displayX, displayY) }
                .pointerInput(viewportWidthPx, viewportHeightPx, insetBottomPx, snapThresholdPx, isSuperMini) {
                    detectDragGestures(
                        onDragStart = {
                            val (startX, startY) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
                                placement = AndroidPluginCapsuleManager.placementState,
                                itemWidthPx = itemWidthPx,
                                itemHeightPx = itemHeightPx,
                                bounds = safeBounds,
                            )
                            liveDragX = startX.toFloat()
                            liveDragY = startY.toFloat()
                            isDragging = true
                        },
                        onDragCancel = {
                            isDragging = false
                        },
                        onDragEnd = {
                            val nextPlacement = PluginCapsuleLayoutCalculator.settleAfterDrag(
                                rawX = liveDragX.roundToInt(),
                                rawY = liveDragY.roundToInt(),
                                itemWidthPx = itemWidthPx,
                                itemHeightPx = itemHeightPx,
                                bounds = safeBounds,
                                snapThresholdPx = snapThresholdPx,
                            )
                            isDragging = false
                            if (nextPlacement.dockedEdge != AndroidPluginCapsuleManager.placementState.dockedEdge) {
                                view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                            }
                            AndroidPluginCapsuleManager.updatePlacement(appContext, nextPlacement)
                        },
                        onDrag = { change, dragAmount ->
                            change.consume()
                            val (clampedX, clampedY) = PluginCapsuleLayoutCalculator.clampDuringDrag(
                                rawX = (liveDragX + dragAmount.x).roundToInt(),
                                rawY = (liveDragY + dragAmount.y).roundToInt(),
                                itemWidthPx = itemWidthPx,
                                itemHeightPx = itemHeightPx,
                                bounds = safeBounds,
                            )
                            liveDragX = clampedX.toFloat()
                            liveDragY = clampedY.toFloat()
                        },
                    )
                },
        ) {
            if (isSuperMini) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .clickable {
                            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            AndroidPluginCapsuleManager.expandSuperMinimized(appContext)
                        }
                        .padding(
                            start = if (dockedEdge == CapsuleDockedEdge.LEFT) 6.dp else 8.dp,
                            end = if (dockedEdge == CapsuleDockedEdge.RIGHT) 6.dp else 8.dp,
                            top = 5.dp,
                            bottom = 5.dp,
                        ),
                ) {
                    CapsulePluginIcon(
                        serverUrl = session.serverUrl,
                        iconUrl = snap.iconUrl,
                        accent = colors.accent,
                        sizeDp = 28,
                    )
                }
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(1.dp),
                    modifier = Modifier.padding(start = 6.dp, end = 4.dp, top = 4.5.dp, bottom = 4.5.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier
                            .clip(RoundedCornerShape(999.dp))
                            .clickable {
                                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                if (isExpanded) onToggleExpanded(false)
                                onOpenPluginWindow()
                            }
                            .padding(end = 2.dp, top = 1.dp, bottom = 1.dp),
                    ) {
                        CapsulePluginIcon(
                            serverUrl = session.serverUrl,
                            iconUrl = snap.iconUrl,
                            accent = colors.accent,
                            sizeDp = 26,
                        )
                        Column(modifier = Modifier.width(64.dp)) {
                            Text(
                                text = snap.displayTitle,
                                color = colors.textPrimary,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            val secondary = snap.displaySubtitle
                            if (secondary.isNotBlank()) {
                                Text(
                                    text = secondary,
                                    color = colors.textSecondary,
                                    fontSize = 10.sp,
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
                        modifier = Modifier.size(23.dp),
                    ) {
                        Icon(
                            Icons.Rounded.Close,
                            contentDescription = "关闭最小化插件",
                            tint = colors.textMuted,
                            modifier = Modifier.size(14.dp),
                        )
                    }
                }
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
        modifier = Modifier.size(25.dp),
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
                modifier = Modifier.size(17.dp),
            )
            drawableRes != null -> Icon(
                painter = painterResource(drawableRes),
                contentDescription = action.label,
                tint = tint,
                modifier = Modifier.size(15.dp),
            )
            else -> Icon(
                imageVector = Icons.Rounded.Star,
                contentDescription = action.label,
                tint = tint,
                modifier = Modifier.size(14.dp),
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
