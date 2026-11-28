package com.moviepilot.pluginhost.runtime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color as AndroidColor
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.ViewGroup
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.SmartToy
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AgentMascotAction
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.FloatingAgentMascot
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.pluginhost.VuePluginSessionPayload
import com.moviepilot.rustbridge.AgentPetDeclarationDto
import com.moviepilot.rustbridge.AgentPetSelection
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * Android 端全局会话作用域 Agent 助手形象状态管理：
 * 读写 `plugin/agent_pets`、`user/config/AgentPet` 与全局 `AI_AGENT_PET`，
 * 失败自动记录并无感退回原生内置机器人。
 */
object AndroidAgentPetManager {
    private var scopeKey: String = ""
    var declarations by mutableStateOf<List<AgentPetDeclarationDto>>(emptyList())
        private set
    var userSelection by mutableStateOf<AgentPetSelection>(AgentPetSelection.FollowDefault)
        private set
    var adminDefaultPetId by mutableStateOf("")
        private set
    var failedIds by mutableStateOf<Set<String>>(emptySet())
        private set
    var isLoading by mutableStateOf(false)
        private set
    var isSaving by mutableStateOf(false)
        private set
    var lastFailureMessage by mutableStateOf<String?>(null)
        private set

    val effectivePet: AgentPetDeclarationDto?
        get() {
            val requested = when (val sel = userSelection) {
                AgentPetSelection.Builtin -> return null
                is AgentPetSelection.Plugin -> "${sel.pluginId}:${sel.key}"
                AgentPetSelection.FollowDefault -> adminDefaultPetId.trim()
            }
            if (requested.isEmpty() || requested in failedIds) return null
            return declarations.firstOrNull { it.id == requested }
        }

    val adminDefaultDeclaration: AgentPetDeclarationDto?
        get() {
            val trimmed = adminDefaultPetId.trim()
            if (trimmed.isEmpty()) return null
            return declarations.firstOrNull { it.id == trimmed }
        }

    /** 清理登录会话范围内缓存的助手选择与失败状态。 */
    fun reset() {
        scopeKey = ""
        declarations = emptyList()
        userSelection = AgentPetSelection.FollowDefault
        adminDefaultPetId = ""
        failedIds = emptySet()
        isLoading = false
        isSaving = false
        lastFailureMessage = null
    }

    /** 确保指定账号作用域的助手数据已载入。 */
    suspend fun ensureLoaded(repository: MoviePilotRepository, accountScopeKey: String) {
        if (accountScopeKey.isBlank()) return
        if (scopeKey == accountScopeKey && (declarations.isNotEmpty() || isLoading)) return
        if (scopeKey != accountScopeKey) {
            reset()
            scopeKey = accountScopeKey
        }
        refresh(repository, clearFailures = false)
    }

    /** 并发刷新助手列表、用户选择和管理员默认项。 */
    suspend fun refresh(repository: MoviePilotRepository, clearFailures: Boolean = false) {
        if (clearFailures) {
            failedIds = emptySet()
            lastFailureMessage = null
        }
        isLoading = true
        try {
            coroutineScope {
                val petsDef = async { repository.fetchAgentPets() }
                val selDef = async { repository.fetchAgentPetSelection() }
                val adminDef = async { repository.fetchGlobalAgentPetDefault() }
                val nextPets = petsDef.await()
                val oldMap = declarations.associateBy { it.id }
                declarations = nextPets
                val upgraded = nextPets.filter { p ->
                    val prev = oldMap[p.id]
                    prev != null && (prev.pluginVersion != p.pluginVersion || prev.remoteUrl != p.remoteUrl)
                }.map { it.id }.toSet()
                if (upgraded.isNotEmpty()) {
                    failedIds = failedIds - upgraded
                }
                userSelection = selDef.await()
                adminDefaultPetId = adminDef.await()
            }
        } finally {
            isLoading = false
        }
    }

    /** 保存助手选择并更新对应的本地运行状态。 */
    suspend fun select(repository: MoviePilotRepository, selection: AgentPetSelection): Boolean {
        if (isSaving) return false
        isSaving = true
        lastFailureMessage = null
        try {
            val ok = repository.saveAgentPetSelection(selection)
            if (ok) {
                userSelection = selection
                if (selection is AgentPetSelection.Plugin) {
                    failedIds = failedIds - "${selection.pluginId}:${selection.key}"
                }
                return true
            } else {
                lastFailureMessage = "保存助手形象失败，请稍后重试。"
                return false
            }
        } finally {
            isSaving = false
        }
    }

    /** 记录插件助手加载失败并显示回退提示。 */
    fun markFailed(pet: AgentPetDeclarationDto, reason: String) {
        failedIds = failedIds + pet.id
        lastFailureMessage = "${pet.name} 加载失败（$reason），已回退内置机器人。"
    }
}

/**
 * 支持精准热区触摸穿透的透明 WebView（用于 Android `stage` 全屏宠物舞台）：
 * - 当 `passthroughEnabled == true` 且 `!forceCaptureAll` 时，仅接受落在 `anchorRectCss`（含 ±16dp 容差）内的 ACTION_DOWN，
 *   其余全屏区域返回 `false`，将触摸事件 100% 原生穿透给下层 Compose 页面与滚动列表。
 */
@SuppressLint("ViewConstructor")
private class StagePassthroughWebView(context: Context) : WebView(context) {
    @Volatile
    var passthroughEnabled: Boolean = false

    @Volatile
    var forceCaptureAll: Boolean = false

    @Volatile
    var anchorRectCss: RectF? = null

    private var activeGestureCaptured: Boolean = false
    var onHostWindowRefocused: (() -> Unit)? = null

    /** 窗口焦点恢复后刷新透明舞台并重置手势状态。 */
    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) {
            activeGestureCaptured = false
        } else {
            postInvalidate()
            requestLayout()
            onHostWindowRefocused?.invoke()
        }
    }

    /** 仅在助手热区内截获触摸，其他触点交还原生页面。 */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (!passthroughEnabled) {
            return super.dispatchTouchEvent(ev)
        }
        val action = ev.actionMasked
        if (action == MotionEvent.ACTION_DOWN) {
            if (forceCaptureAll) {
                activeGestureCaptured = true
            } else {
                val rect = anchorRectCss
                val density = resources.displayMetrics.density.coerceAtLeast(1f)
                val xCss = ev.x / density
                val yCss = ev.y / density
                val pad = 24f
                activeGestureCaptured = rect != null &&
                    rect.width() > 0f &&
                    rect.height() > 0f &&
                    xCss >= rect.left - pad &&
                    xCss <= rect.right + pad &&
                    yCss >= rect.top - pad &&
                    yCss <= rect.bottom + pad
            }
            if (!activeGestureCaptured) {
                return false
            }
        }
        if (!activeGestureCaptured && !forceCaptureAll) {
            return false
        }
        val handled = super.dispatchTouchEvent(ev)
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            activeGestureCaptured = false
        }
        return handled
    }
}

/** 封装单个插件助手专用的 WebView 与资源状态。 */
private class DedicatedAndroidPetSlot(
    val webView: StagePassthroughWebView,
    val interceptor: PluginShellRequestInterceptor,
    val bridge: AndroidPluginHostBridgeV2,
) {
    var isShellReady: Boolean = false
    var pendingMountPayload: JsonObject? = null
    var latestAgentState: JsonObject? = null
    var disposed: Boolean = false
}

@SuppressLint("SetJavaScriptEnabled")
/** 创建隔离的插件 WebView 并安装安全请求拦截器。 */
private fun createDedicatedPetSlot(
    context: Context,
    repository: MoviePilotRepository,
    session: VuePluginSessionPayload,
    onRenderProcessGone: () -> Unit,
): DedicatedAndroidPetSlot {
    val appCtx = context.applicationContext
    val interceptor = PluginShellRequestInterceptor(
        appCtx,
        currentSession = { bound -> currentPetResourceSession(repository, bound) },
        refreshResourceCookie = {
            if (currentPetResourceSession(repository, session) != null) {
                runBlocking(Dispatchers.IO) { repository.authedRequest(listOf("media", "source")) }
            }
        },
    ).apply { updateSession(session) }
    val bridge = AndroidPluginHostBridgeV2(appCtx).apply { updateSession(session) }
    val wv = StagePassthroughWebView(appCtx)
    val slot = DedicatedAndroidPetSlot(wv, interceptor, bridge)

    wv.layoutParams = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT,
    )
    wv.setBackgroundColor(AndroidColor.TRANSPARENT)
    wv.isVerticalScrollBarEnabled = false
    wv.isHorizontalScrollBarEnabled = false
    wv.overScrollMode = WebView.OVER_SCROLL_NEVER
    wv.settings.apply {
        javaScriptEnabled = true
        domStorageEnabled = true
        databaseEnabled = false
        allowFileAccess = false
        allowContentAccess = false
        mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        cacheMode = WebSettings.LOAD_DEFAULT
        mediaPlaybackRequiresUserGesture = false
        useWideViewPort = false
        loadWithOverviewMode = false
    }
    wv.addJavascriptInterface(bridge, AndroidPluginHostBridgeV2.JS_INTERFACE_NAME)
    wv.webViewClient = object : WebViewClient() {
        /** 校验并代理插件资源请求，阻断越权跨源访问。 */
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
            interceptor.intercept(request)

        /** 拦截不属于当前插件的页面导航。 */
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val host = request.url?.host.orEmpty()
            return !host.equals(PluginShellRequestInterceptor.VIRTUAL_HOST, ignoreCase = true)
        }

        /** 在 WebView 渲染进程退出后清理专用槽位。 */
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            onRenderProcessGone()
            return true
        }
    }
    bridge.webView = wv
    wv.onHostWindowRefocused = {
        if (slot.isShellReady && !slot.disposed) {
            slot.latestAgentState?.let { latest ->
                slot.bridge.sendAgentState(latest)
            }
        }
    }
    wv.loadUrl(PluginShellRequestInterceptor.SHELL_ENTRY_URL)
    return slot
}

/** 仅为仍归属当前账号和实例的助手导出最新 Cookie，防止旧容器借用新会话。 */
private fun currentPetResourceSession(
    repository: MoviePilotRepository,
    bound: VuePluginSessionPayload,
): VuePluginSessionPayload? {
    val auth = repository.session.value as? SessionState.Authenticated ?: return null
    if (auth.serverUrl != bound.serverUrl || auth.token != bound.authToken ||
        auth.identity.id != bound.userId || auth.identity.name != bound.userName
    ) return null
    val cookies = repository.exportOriginCookieEntries()
    if (repository.session.value !== auth) return null
    return bound.copy(originCookies = cookies)
}

/**
 * Android 全界面 Agent 助手形象统一宿主层（挂在 `MoviePilotAppShell` 根层，覆盖所有 Tab 与二级子页面）：
 * - 未选插件形象或加载失败：展示纯原生高质感 `FloatingAgentMascot`（0 WebView 内存）；
 * - `renderer` 模式：原生可拖拽悬浮盒 + 透明 `plugin-shell` 远程组件；
 * - `stage` 模式：全屏透明舞台 + 精准触摸穿透 + 底部 Dock 坐标同步 + 原生台词气泡！
 */
@Composable
fun AndroidAgentPetOverlayHost(
    repository: MoviePilotRepository,
    session: VuePluginSessionPayload,
    accountScopeKey: String,
    isVisible: Boolean,
    panelOpen: Boolean,
    dockVisible: Boolean,
    isWideCanvas: Boolean,
    showMiniMusicBar: Boolean,
    onOpenAgent: (draft: String?) -> Unit,
    onCloseAgent: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(accountScopeKey) {
        AndroidAgentPetManager.ensureLoaded(repository, accountScopeKey)
    }

    val effectivePet = AndroidAgentPetManager.effectivePet
    if (effectivePet != null) {
        AndroidPluginAgentPetRuntimeOverlay(
            pet = effectivePet,
            repository = repository,
            session = session,
            isVisible = isVisible,
            panelOpen = panelOpen,
            dockVisible = dockVisible,
            isWideCanvas = isWideCanvas,
            showMiniMusicBar = showMiniMusicBar,
            onOpenAgent = onOpenAgent,
            onCloseAgent = onCloseAgent,
            modifier = modifier,
        )
    } else if (isVisible && !panelOpen) {
        val mascotBottom = when {
            isWideCanvas && showMiniMusicBar -> 92.dp
            isWideCanvas -> 24.dp
            dockVisible && showMiniMusicBar -> 158.dp
            dockVisible -> 92.dp
            showMiniMusicBar -> 96.dp
            else -> 24.dp
        }
        Box(modifier = modifier.fillMaxSize()) {
            FloatingAgentMascot(
                onClick = { onOpenAgent(null) },
                motionActive = true,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .navigationBarsPadding()
                    .padding(end = 16.dp, bottom = mascotBottom),
            )
        }
    }
}

@Composable
/** 运行插件助手舞台与渲染器并转发宿主状态。 */
private fun AndroidPluginAgentPetRuntimeOverlay(
    pet: AgentPetDeclarationDto,
    repository: MoviePilotRepository,
    session: VuePluginSessionPayload,
    isVisible: Boolean,
    panelOpen: Boolean,
    dockVisible: Boolean,
    isWideCanvas: Boolean,
    showMiniMusicBar: Boolean,
    onOpenAgent: (draft: String?) -> Unit,
    onCloseAgent: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val appearance = LocalAppearanceStore.current
    val density = LocalDensity.current
    val layoutDir = LocalLayoutDirection.current
    val safePadding = WindowInsets.systemBars.union(WindowInsets.displayCutout).asPaddingValues()

    val visualTokens = remember(colors, appearance.pureBlackDark, density.fontScale) {
        AndroidPluginVisualTokens.from(colors, appearance, density.fontScale)
    }

    var isMounted by remember(pet.id) { mutableStateOf(false) }
    var anchorRectCss by remember(pet.id) { mutableStateOf<RectF?>(null) }
    var lastValidAnchorRectCss by remember(pet.id) { mutableStateOf<RectF?>(null) }
    var isInteracting by remember(pet.id) { mutableStateOf(false) }
    var speechBubbleText by remember(pet.id) { mutableStateOf<String?>(null) }
    var speechBubbleNonce by remember(pet.id) { mutableStateOf(0) }
    var speechDurationMs by remember(pet.id) { mutableStateOf(3500L) }
    var rendererAction by remember(pet.id) { mutableStateOf<String?>(null) }

    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    val slot = remember(pet.id, session.serverUrl, session.authToken) {
        createDedicatedPetSlot(context, repository, session) {
            mainHandler.post {
                isMounted = false
                AndroidAgentPetManager.markFailed(pet, "渲染进程中断")
            }
        }
    }

    DisposableEffect(slot) {
        onDispose {
            slot.disposed = true
            slot.bridge.sendUnmount()
            slot.bridge.abortAllInFlightRequests()
            slot.bridge.cleanupNativeCapabilities()
            slot.bridge.clearCallbacks()
            slot.bridge.updateSession(null)
            slot.interceptor.updateSession(null)
            (slot.webView.parent as? ViewGroup)?.removeView(slot.webView)
            slot.webView.destroy()
        }
    }

    LaunchedEffect(speechBubbleNonce) {
        if (speechBubbleText != null) {
            delay(speechDurationMs)
            speechBubbleText = null
        }
    }

    val motionActive = isVisible && !panelOpen

    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val widthDp = maxWidth.value
        val heightDp = maxHeight.value
        val safeTopDp = safePadding.calculateTopPadding().value
        val safeBottomDp = safePadding.calculateBottomPadding().value
        val safeLeftDp = safePadding.calculateLeftPadding(layoutDir).value
        val safeRightDp = safePadding.calculateRightPadding(layoutDir).value

        /** 生成发往插件的 Agent 状态快照。 */
        fun buildStateJson(): JsonObject = buildJsonObject {
            put("available", true)
            put("panelOpen", panelOpen)
            put("thinking", false)
            put("phase", "idle")
            put("pageVisible", motionActive)
            put("motionAllowed", motionActive)
            put("reducedMotion", !motionActive)
            put("theme", if (colors.isDark) "dark" else "light")
            put("isMobile", widthDp < 960f)
            if (dockVisible && !isWideCanvas) {
                val dockH = 62f
                val dockY = (heightDp - safeBottomDp - dockH - 8f).coerceAtLeast(0f)
                val dockW = (widthDp - 32f).coerceIn(220f, 420f)
                val dockX = (widthDp - dockW) * 0.5f
                val bounds = buildJsonObject {
                    put("x", dockX.toDouble())
                    put("y", dockY.toDouble())
                    put("width", dockW.toDouble())
                    put("height", dockH.toDouble())
                }
                put(
                    "dock",
                    buildJsonObject {
                        put("bounds", bounds)
                        put("items", buildJsonArray { add(bounds) })
                    },
                )
            } else {
                put("dock", JsonNull)
            }
            put(
                "viewport",
                buildJsonObject {
                    put("width", widthDp.toDouble())
                    put("height", heightDp.toDouble())
                    put("keyboardInset", 0)
                    put(
                        "safeArea",
                        buildJsonObject {
                            put("top", safeTopDp.toDouble())
                            put("right", safeRightDp.toDouble())
                            put("bottom", safeBottomDp.toDouble())
                            put("left", safeLeftDp.toDouble())
                        },
                    )
                },
            )
            if (!pet.isStageMode) {
                if (rendererAction != null) put("action", rendererAction!!) else put("action", JsonNull)
                put("intent", "idle")
                put("motionActive", motionActive)
            }
        }

        // 挂载宠物组件
        LaunchedEffect(slot, pet.id) {
            isMounted = false
            anchorRectCss = null
            isInteracting = false

            slot.bridge.onShellReady = {
                slot.isShellReady = true
                slot.pendingMountPayload?.let { payload ->
                    slot.pendingMountPayload = null
                    slot.bridge.sendToWeb("plugin.mount", payload)
                    slot.latestAgentState?.let { slot.bridge.sendAgentState(it) }
                }
            }
            slot.bridge.onPluginMounted = { _, _ ->
                isMounted = true
                slot.latestAgentState?.let { slot.bridge.sendAgentState(it) }
            }
            slot.bridge.onPluginError = { _, msg, _ ->
                isMounted = false
                AndroidAgentPetManager.markFailed(pet, msg.ifBlank { "插件运行异常" })
            }
            slot.bridge.onAgentOpen = { draft ->
                mainHandler.post {
                    isInteracting = false
                    slot.webView.forceCaptureAll = false
                    onOpenAgent(draft)
                }
            }
            slot.bridge.onAgentClose = {
                mainHandler.post { onCloseAgent() }
            }
            slot.bridge.onAgentPetAnchor = { x, y, w, h ->
                val rect = RectF(x, y, x + w, y + h)
                if (w > 0f && h > 0f) {
                    lastValidAnchorRectCss = rect
                }
                anchorRectCss = rect
                slot.webView.anchorRectCss = rect
            }
            slot.bridge.onAgentPetAnchorCleared = {
                val fallback = lastValidAnchorRectCss
                anchorRectCss = fallback
                slot.webView.anchorRectCss = fallback
            }
            slot.bridge.onAgentPetInteracting = { active ->
                isInteracting = active
                slot.webView.forceCaptureAll = active
            }
            slot.bridge.onAgentPetSay = { text, durationMs ->
                speechDurationMs = durationMs.toLong()
                speechBubbleText = text
                speechBubbleNonce++
            }

            // 必须等待资源 Cookie 就绪后再挂载，不能记住登录初期尚为空的 Cookie 快照。
            repository.authedRequest(listOf("media", "source"))
            val resourceSession = currentPetResourceSession(repository, session) ?: return@LaunchedEffect
            slot.bridge.updateSession(resourceSession)
            val rawRemoteUrl = pet.remoteUrl?.takeIf { it.isNotBlank() } ?: withContext(Dispatchers.IO) {
                discoverRemoteEntryUrl(session, pet.pluginId)
            }
            if (rawRemoteUrl.isNullOrBlank()) {
                AndroidAgentPetManager.markFailed(pet, "未找到联邦入口")
                return@LaunchedEffect
            }
            val plan = RustCoreBridge.normalizePluginRemoteEntry(
                pluginId = pet.sourcePluginId,
                versionOrHash = pet.pluginVersion.orEmpty(),
                rawRemoteUrl = rawRemoteUrl,
            )
            if (plan == null) {
                AndroidAgentPetManager.markFailed(pet, "入口路径无效")
                return@LaunchedEffect
            }
            val virtualEntryUrl = "${PluginShellRequestInterceptor.VIRTUAL_ORIGIN}${plan.virtualEntryPath}"
            val mountPayload = buildJsonObject {
                put("mountId", "pet-and-${UUID.randomUUID()}")
                put("pluginId", pet.pluginId)
                put("sourcePluginId", pet.sourcePluginId)
                put("pluginName", pet.pluginName)
                put("pluginVersion", pet.pluginVersion.orEmpty())
                put("surface", "agentPet")
                put("exposeComponent", pet.normalizedComponent)
                put(
                    "agentPet",
                    buildJsonObject {
                        put("key", pet.key)
                        put("mode", pet.mode)
                        put("bubbles", pet.bubbles ?: "host")
                        put("name", pet.name)
                    },
                )
                put("agentHostState", buildStateJson())
                put("remoteEntryUrl", virtualEntryUrl)
                put("locale", "zh-CN")
                put("visualTokens", visualTokens.toJsonObject())
                put(
                    "safeArea",
                    buildJsonObject {
                        put("top", safeTopDp.toDouble())
                        put("bottom", safeBottomDp.toDouble())
                        put("left", safeLeftDp.toDouble())
                        put("right", safeRightDp.toDouble())
                    },
                )
                put(
                    "user",
                    buildJsonObject {
                        put("id", session.userId)
                        put("superUser", session.isSuperuser)
                        put("userName", session.userName)
                        put("avatar", session.avatar)
                        put("level", if (session.isSuperuser) 2 else 1)
                        put(
                            "permissions",
                            buildJsonObject {
                                put("discovery", true)
                                put("search", true)
                                put("subscribe", true)
                                put("manage", session.isSuperuser)
                                put("admin", session.isSuperuser)
                            },
                        )
                    },
                )
            }

            if (slot.isShellReady) {
                slot.bridge.sendToWeb("plugin.mount", mountPayload)
            } else {
                slot.pendingMountPayload = mountPayload
            }

            // 10s 加载超时自动回退原生机器人
            delay(10_000L)
            if (!isMounted && !slot.disposed) {
                AndroidAgentPetManager.markFailed(pet, "加载超时")
            }
        }

        // 实时同步状态与主题
        LaunchedEffect(isVisible, panelOpen, dockVisible, widthDp, heightDp, visualTokens, rendererAction) {
            val latest = buildStateJson()
            slot.latestAgentState = latest
            if (slot.isShellReady) {
                slot.bridge.sendAgentState(latest)
                slot.bridge.sendVisualTokens(visualTokens)
            }
        }

        // renderer 模式随机动作调度
        LaunchedEffect(pet.id, motionActive) {
            if (pet.isStageMode || !motionActive) return@LaunchedEffect
            val pool = pet.randomActions?.takeIf { it.isNotEmpty() }
                ?: listOf("sleep", "stretch", "sit", "wave", "peek", "shy", "confused")
            var last: String? = null
            while (true) {
                delay((12_000L..22_000L).random())
                val next = pool.filter { it != last }.randomOrNull() ?: pool.first()
                last = next
                rendererAction = next
                val dur = AgentMascotAction.entries.firstOrNull { it.wireName == next }?.durationMs ?: 3200L
                delay(dur)
                if (rendererAction == next) rendererAction = null
            }
        }

        val petInteractive = isVisible && !panelOpen && isMounted
        if (pet.isStageMode) {
            // 全屏透明舞台 + 像素级触摸穿透（保持 WebView 自身可见态避免页面挂起，由内层 CSS 与 dispatchTouchEvent 控制显隐穿透）
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .alpha(if (isMounted) 1f else 0f),
            ) {
                AndroidView(
                    factory = {
                        (slot.webView.parent as? ViewGroup)?.removeView(slot.webView)
                        slot.webView.passthroughEnabled = true
                        slot.webView.forceCaptureAll = petInteractive && isInteracting
                        slot.webView.anchorRectCss = if (petInteractive) anchorRectCss else null
                        slot.webView
                    },
                    update = { wv ->
                        wv.passthroughEnabled = true
                        wv.forceCaptureAll = petInteractive && isInteracting
                        wv.anchorRectCss = if (petInteractive) anchorRectCss else null
                    },
                    modifier = Modifier.fillMaxSize(),
                )

                val bubble = speechBubbleText
                val anchor = anchorRectCss
                if (petInteractive && bubble != null && anchor != null) {
                    val bxDp = ((anchor.left + anchor.right) * 0.5f - 100f).coerceIn(12f, (widthDp - 212f).coerceAtLeast(12f))
                    val byDp = (anchor.top - 48f).coerceAtLeast(safeTopDp + 12f)
                    AgentPetSpeechBubble(
                        text = bubble,
                        modifier = Modifier.offset(x = bxDp.dp, y = byDp.dp),
                    )
                }
            }
        } else {
            // renderer 模式：原生可拖拽悬浮盒 + 透明 WebView（跨会话持久化拖拽偏移）
            val prefs = remember(context) { context.getSharedPreferences("mp_agent_pet_prefs", Context.MODE_PRIVATE) }
            val boxW = 86.dp
            val boxH = 96.dp
            var dragOffX by remember(pet.id) { mutableFloatStateOf(prefs.getFloat("renderer_dx", 0f)) }
            var dragOffY by remember(pet.id) { mutableFloatStateOf(prefs.getFloat("renderer_dy", 0f)) }
            val baseBottom = when {
                isWideCanvas && showMiniMusicBar -> 92.dp
                isWideCanvas -> 24.dp
                dockVisible && showMiniMusicBar -> 158.dp
                dockVisible -> 92.dp
                else -> 24.dp
            }
            Box(modifier = Modifier.fillMaxSize()) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .navigationBarsPadding()
                        .padding(end = 12.dp, bottom = baseBottom)
                        .offset { IntOffset(dragOffX.roundToInt(), dragOffY.roundToInt()) }
                        .size(width = boxW, height = boxH)
                        .then(
                            if (petInteractive) {
                                Modifier
                                    .pointerInput(pet.id) {
                                        detectDragGestures(
                                            onDragEnd = {
                                                prefs.edit()
                                                    .putFloat("renderer_dx", dragOffX)
                                                    .putFloat("renderer_dy", dragOffY)
                                                    .apply()
                                                rendererAction = "nod"
                                            },
                                        ) { change, dragAmount ->
                                            change.consume()
                                            dragOffX += dragAmount.x
                                            dragOffY += dragAmount.y
                                        }
                                    }
                                    .clickable { onOpenAgent(null) }
                            } else {
                                Modifier
                            },
                        ),
                ) {
                    AndroidView(
                        factory = {
                            (slot.webView.parent as? ViewGroup)?.removeView(slot.webView)
                            slot.webView.passthroughEnabled = true
                            slot.webView.forceCaptureAll = false
                            slot.webView.anchorRectCss = null
                            slot.webView
                        },
                        modifier = Modifier
                            .fillMaxSize()
                            .alpha(if (petInteractive) 1f else if (isMounted) 0.015f else 0f),
                    )
                }
                if (petInteractive) {
                    speechBubbleText?.let { bubble ->
                        AgentPetSpeechBubble(
                            text = bubble,
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .navigationBarsPadding()
                                .padding(end = 16.dp, bottom = baseBottom + boxH + 6.dp)
                                .offset { IntOffset(dragOffX.roundToInt(), dragOffY.roundToInt()) },
                        )
                    }
                }
            }
        }

        // 加载中托底显示原生机器人避免空白闪烁
        if (!isMounted && isVisible && !panelOpen) {
            val fallbackBottom = if (dockVisible && !isWideCanvas) 92.dp else 24.dp
            FloatingAgentMascot(
                onClick = { onOpenAgent(null) },
                motionActive = true,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .navigationBarsPadding()
                    .padding(end = 16.dp, bottom = fallbackBottom),
            )
        }
    }
}

@Composable
/** 绘制带自动显隐动画的助手消息气泡。 */
private fun AgentPetSpeechBubble(
    text: String,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Surface(
        modifier = modifier.widthIn(max = 216.dp),
        shape = RoundedCornerShape(14.dp),
        color = colors.surfaceContainerHigh.copy(alpha = 0.96f),
        border = BorderStroke(0.75.dp, colors.borderSubtle),
        shadowElevation = 6.dp,
    ) {
        Text(
            text = text,
            color = colors.textPrimary,
            fontSize = 12.sp,
            lineHeight = 16.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
        )
    }
}

/** 根据插件声明解析远程模块入口地址。 */
private fun discoverRemoteEntryUrl(session: VuePluginSessionPayload, targetPluginId: String): String? {
    val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()
    val url = "${session.serverUrl.trimEnd('/')}/api/v1/plugin/remotes?token=moviepilot"
    val req = Request.Builder()
        .url(url)
        .header("Authorization", "Bearer ${session.authToken}")
        .build()
    val body = runCatching {
        client.newCall(req).execute().use { resp ->
            if (resp.isSuccessful) resp.body?.string() else null
        }
    }.getOrNull() ?: return null
    val root = runCatching { Json { ignoreUnknownKeys = true; isLenient = true }.parseToJsonElement(body) }.getOrNull()
        ?: return null
    val arr = when (root) {
        is JsonArray -> root
        is JsonObject -> root["data"] as? JsonArray ?: return null
        else -> return null
    }
    return arr.firstNotNullOfOrNull { el ->
        val obj = el as? JsonObject ?: return@firstNotNullOfOrNull null
        val id = (obj["id"] as? JsonPrimitive)?.content ?: return@firstNotNullOfOrNull null
        if (id.equals(targetPluginId, ignoreCase = true)) (obj["url"] as? JsonPrimitive)?.content else null
    }
}

/**
 * Android 原生「更换助手形象」底部弹窗（同步读写 `user/config/AgentPet`，与 Web 端互通）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AndroidAgentPetPickerSheet(
    repository: MoviePilotRepository,
    onDismiss: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var draftSelection by remember { mutableStateOf(AndroidAgentPetManager.userSelection) }
    var hasEditedDraft by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        AndroidAgentPetManager.refresh(repository, clearFailures = false)
        if (!hasEditedDraft) {
            draftSelection = AndroidAgentPetManager.userSelection
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.surfaceContainerHigh,
        contentColor = colors.textPrimary,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "取消",
                    fontSize = 15.sp,
                    color = colors.textSecondary,
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(onClick = onDismiss)
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                    Text("更换助手形象", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
                    IconButton(
                        onClick = { scope.launch { AndroidAgentPetManager.refresh(repository, clearFailures = true) } },
                        modifier = Modifier.size(30.dp),
                    ) {
                        Icon(Icons.Rounded.Refresh, contentDescription = "刷新", tint = colors.textSecondary, modifier = Modifier.size(17.dp))
                    }
                }
                Text(
                    text = if (AndroidAgentPetManager.isSaving) "保存中…" else "保存",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.accent,
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(enabled = !AndroidAgentPetManager.isSaving) {
                            scope.launch {
                                if (AndroidAgentPetManager.select(repository, draftSelection)) {
                                    onDismiss()
                                }
                            }
                        }
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                )
            }

            AndroidAgentPetManager.lastFailureMessage?.let { msg ->
                Text(
                    text = msg,
                    fontSize = 12.sp,
                    color = colors.warning,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(colors.warning.copy(alpha = 0.14f))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                )
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 460.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (AndroidAgentPetManager.adminDefaultPetId.isNotBlank()) {
                    item(key = "follow-default") {
                        val defName = AndroidAgentPetManager.adminDefaultDeclaration?.name ?: "内置机器人"
                        PetPickerRowCard(
                            title = "跟随默认（$defName）",
                            subtitle = "使用管理员配置的默认助手形象",
                            badge = "系统默认",
                            previewUrl = null,
                            selected = draftSelection == AgentPetSelection.FollowDefault,
                            onClick = {
                                hasEditedDraft = true
                                draftSelection = AgentPetSelection.FollowDefault
                            },
                        )
                    }
                }
                item(key = "builtin") {
                    val isBuiltinSelected = draftSelection == AgentPetSelection.Builtin ||
                        (draftSelection == AgentPetSelection.FollowDefault && AndroidAgentPetManager.adminDefaultPetId.isBlank())
                    PetPickerRowCard(
                        title = "内置机器人",
                        subtitle = "原生绘制，支持贴边探头、呼吸眨眼与 16 种动作，零额外内存",
                        badge = "原生",
                        previewUrl = null,
                        selected = isBuiltinSelected,
                        onClick = {
                            hasEditedDraft = true
                            draftSelection = AgentPetSelection.Builtin
                        },
                    )
                }
                if (AndroidAgentPetManager.isLoading && AndroidAgentPetManager.declarations.isEmpty()) {
                    item(key = "loading") {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = colors.accent)
                            Spacer(Modifier.size(10.dp))
                            Text("正在加载插件形象…", fontSize = 13.sp, color = colors.textSecondary)
                        }
                    }
                } else {
                    items(AndroidAgentPetManager.declarations, key = { it.id }) { pet ->
                        val candidate = AgentPetSelection.Plugin(pet.pluginId, pet.key)
                        val selected = draftSelection == candidate
                        val failed = pet.id in AndroidAgentPetManager.failedIds
                        PetPickerRowCard(
                            title = pet.name,
                            subtitle = pet.description.ifBlank { pet.pluginName },
                            badge = if (failed) "异常·保存重试" else if (pet.isStageMode) "全屏舞台" else "悬浮形象",
                            previewUrl = pet.previewUrl ?: pet.avatarUrl,
                            selected = selected,
                            onClick = {
                                hasEditedDraft = true
                                draftSelection = candidate
                            },
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
/** 构建助手选择列表中的单项预览卡片。 */
private fun PetPickerRowCard(
    title: String,
    subtitle: String,
    badge: String,
    previewUrl: String?,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(
        padding = 12.dp,
        showsShadow = false,
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (selected) Modifier.border(1.4.dp, colors.accent, RoundedCornerShape(colors.cardRadiusDp.dp))
                else Modifier,
            )
            .clickable(enabled = !AndroidAgentPetManager.isSaving, onClick = onClick),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(50.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.accent.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                if (!previewUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = previewUrl,
                        contentDescription = title,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(Icons.Rounded.SmartToy, contentDescription = null, tint = colors.accent, modifier = Modifier.size(26.dp))
                }
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        text = badge,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = if (selected) colors.accent else colors.textSecondary,
                        modifier = Modifier
                            .clip(RoundedCornerShape(99.dp))
                            .background((if (selected) colors.accent else colors.textSecondary).copy(alpha = 0.14f))
                            .padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
                Text(subtitle, fontSize = 12.sp, color = colors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            if (selected) {
                Icon(Icons.Rounded.CheckCircle, contentDescription = "已选中", tint = colors.accent, modifier = Modifier.size(22.dp))
            }
        }
    }
}
