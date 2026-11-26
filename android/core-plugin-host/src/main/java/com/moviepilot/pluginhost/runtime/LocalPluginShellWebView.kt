package com.moviepilot.pluginhost.runtime

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeCardListSkeleton
import com.moviepilot.designsystem.SkeletonCardStyle
import com.moviepilot.pluginhost.VuePluginChromeController
import com.moviepilot.pluginhost.VuePluginConfirmation
import com.moviepilot.pluginhost.VuePluginSessionPayload
import com.moviepilot.pluginhost.VuePluginSurface
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

private data class RemotePluginEntryMeta(
    val id: String,
    val url: String,
    val name: String?,
    val sourcePluginId: String?,
    val version: String?,
    val bundleHash: String?,
) {
    val preferredCacheVersion: String
        get() {
            val hash = bundleHash?.trim().orEmpty()
            val ver = version?.trim().orEmpty()
            return when {
                hash.isNotEmpty() && ver.isNotEmpty() -> "$ver-$hash"
                hash.isNotEmpty() -> hash
                else -> ver
            }
        }
}

/**
 * Android 端本地预热极简联邦运行时宿主（Route A）：
 * - 透明 `WebView` 直接叠加在 Compose 原生背景上，自动响应深浅主题、Material You 与 AMOLED 纯黑；
 * - 零前端 3000 端口依赖，零 WebView Bearer Token 暴露；
 * - 失败时提供「重新加载」与「用兼容网页容器打开」一键回退。
 */
@Composable
fun LocalPluginShellWebView(
    pluginId: String,
    session: VuePluginSessionPayload,
    surface: VuePluginSurface = VuePluginSurface.DataPage,
    chromeController: VuePluginChromeController? = null,
    pluginHasPage: Boolean = false,
    onFallbackToLegacy: () -> Unit,
    onRequestExit: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val appearance = LocalAppearanceStore.current
    val fontScale = LocalDensity.current.fontScale
    val backHandler = remember { android.os.Handler(android.os.Looper.getMainLooper()) }
    val pendingBackFallback = remember { mutableStateOf<Runnable?>(null) }

    var reloadNonce by remember { mutableIntStateOf(0) }
    var activeSlot by remember { mutableStateOf<PooledAndroidPluginWebView?>(null) }
    var isMounted by remember(pluginId, surface, reloadNonce) { mutableStateOf(false) }
    var errorMessage by remember(pluginId, surface, reloadNonce) { mutableStateOf<String?>(null) }
    var activeToast by remember { mutableStateOf<AndroidPluginToast?>(null) }
    var standaloneConfirm by remember { mutableStateOf<VuePluginConfirmation?>(null) }

    // Activity 作用域原生能力回调（权限申请、相册/相机/文件选取、设备认证、屏幕常亮、DeepLink 路由与播放）
    val pendingPermissionCb = remember { mutableStateOf<((Boolean) -> Unit)?>(null) }
    val pendingSinglePickCb = remember { mutableStateOf<((List<Uri>) -> Unit)?>(null) }
    val pendingMultiPickCb = remember { mutableStateOf<((List<Uri>) -> Unit)?>(null) }
    val pendingCameraCb = remember { mutableStateOf<Pair<Uri, (List<Uri>) -> Unit>?>(null) }
    val pendingAuthCb = remember { mutableStateOf<((Boolean, String) -> Unit)?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val cb = pendingPermissionCb.value
        pendingPermissionCb.value = null
        cb?.invoke(granted)
    }
    val openSingleDocLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val cb = pendingSinglePickCb.value
        pendingSinglePickCb.value = null
        cb?.invoke(if (uri != null) listOf(uri) else emptyList())
    }
    val openMultiDocLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        val cb = pendingMultiPickCb.value
        pendingMultiPickCb.value = null
        cb?.invoke(uris)
    }
    val takePictureLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val pending = pendingCameraCb.value
        pendingCameraCb.value = null
        if (pending != null) {
            pending.second(if (saved) listOf(pending.first) else emptyList())
        }
    }
    val authLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val cb = pendingAuthCb.value
        pendingAuthCb.value = null
        cb?.invoke(result.resultCode == Activity.RESULT_OK, "deviceCredential")
    }

    val activityHost = remember(context) {
        object : AndroidPluginActivityHost {
            override fun requestPermission(permission: String, onResult: (Boolean) -> Unit) {
                pendingPermissionCb.value = onResult
                permissionLauncher.launch(permission)
            }

            override fun pickMedia(mediaType: String, multiple: Boolean, fromCamera: Boolean, onResult: (List<Uri>) -> Unit) {
                if (fromCamera) {
                    runCatching {
                        val dir = File(context.cacheDir, "plugin_camera").apply { mkdirs() }
                        val photo = File(dir, "cam_${UUID.randomUUID()}.jpg")
                        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", photo)
                        pendingCameraCb.value = uri to onResult
                        takePictureLauncher.launch(uri)
                    }.onFailure {
                        onResult(emptyList())
                    }
                    return
                }
                val mimeTypes = when (mediaType) {
                    "video" -> arrayOf("video/*")
                    "any" -> arrayOf("image/*", "video/*")
                    else -> arrayOf("image/*")
                }
                if (multiple) {
                    pendingMultiPickCb.value = onResult
                    openMultiDocLauncher.launch(mimeTypes)
                } else {
                    pendingSinglePickCb.value = onResult
                    openSingleDocLauncher.launch(mimeTypes)
                }
            }

            override fun pickFile(accept: List<String>, multiple: Boolean, onResult: (List<Uri>) -> Unit) {
                val mimes = accept.filter { it.contains("/") }.ifEmpty { listOf("*/*") }.toTypedArray()
                if (multiple) {
                    pendingMultiPickCb.value = onResult
                    openMultiDocLauncher.launch(mimes)
                } else {
                    pendingSinglePickCb.value = onResult
                    openSingleDocLauncher.launch(mimes)
                }
            }

            override fun setKeepAwake(enabled: Boolean) {
                val act = context.findHostActivity() ?: return
                if (enabled) {
                    act.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    act.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }

            override fun openDeepLink(deepLink: String) {
                runCatching {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(deepLink)).apply {
                        setPackage(context.packageName)
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                    context.startActivity(intent)
                }
            }

            @Suppress("DEPRECATION")
            override fun authenticate(reason: String, onResult: (Boolean, String) -> Unit) {
                val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                val intent = km?.createConfirmDeviceCredentialIntent("身份验证", reason)
                if (intent == null) {
                    onResult(false, "none")
                    return
                }
                pendingAuthCb.value = onResult
                authLauncher.launch(intent)
            }
        }
    }

    val visualTokens = remember(colors, appearance.pureBlackDark, fontScale) {
        AndroidPluginVisualTokens.from(colors, appearance, fontScale)
    }

    val webAlpha by animateFloatAsState(
        targetValue = if (isMounted && errorMessage == null) 1f else 0f,
        animationSpec = tween(durationMillis = 160),
        label = "pluginShellFadeIn",
    )

    val dismissHostPage: () -> Unit = {
        pendingBackFallback.value?.let { backHandler.removeCallbacks(it) }
        pendingBackFallback.value = null
        if (chromeController != null) {
            chromeController.shouldDismiss = true
        } else {
            onRequestExit?.invoke()
        }
    }

    val dispatchNavBackOrDismiss: () -> Boolean = {
        val slot = activeSlot
        if (!isMounted || slot == null) {
            false
        } else {
            pendingBackFallback.value?.let { backHandler.removeCallbacks(it) }
            val fallback = Runnable {
                pendingBackFallback.value = null
                dismissHostPage()
            }
            pendingBackFallback.value = fallback
            backHandler.postDelayed(fallback, 500L)
            slot.bridge.sendNavBack()
            true
        }
    }

    // 返回键透传给壳内 `nav.back`：若插件内有弹窗/遮罩则仅关闭内层（`handled == true`），否则退出插件页
    BackHandler(enabled = isMounted && standaloneConfirm == null && chromeController?.confirmation == null) {
        if (!dispatchNavBackOrDismiss()) {
            dismissHostPage()
        }
    }

    // 实时同步主题与外观变更到运行中插件，无需重载 WebView
    LaunchedEffect(visualTokens, activeSlot) {
        activeSlot?.bridge?.sendVisualTokens(visualTokens)
    }

    // 自动消失 Toast
    LaunchedEffect(activeToast?.id) {
        if (activeToast != null) {
            delay(2600L)
            activeToast = null
        }
    }

    // 挂载远程插件
    LaunchedEffect(pluginId, surface, session.serverUrl, session.authToken, reloadNonce) {
        isMounted = false
        errorMessage = null
        chromeController?.isReady = false

        activeSlot?.let { old ->
            activeSlot = null
            if (!AndroidPluginCapsuleManager.isSlotParked(old)) {
                AndroidPluginWebViewPool.release(old, context)
            }
        }

        fun bindLiveSlotCallbacks(slot: PooledAndroidPluginWebView, resolvedPluginName: String) {
            slot.bridge.nativeCapabilities.activityHost = activityHost
            slot.bridge.onOpenRoute = { deepLink ->
                activityHost.openDeepLink(deepLink)
            }
            slot.bridge.onPluginMounted = { _, _ ->
                isMounted = true
                errorMessage = null
                chromeController?.isReady = true
            }
            slot.bridge.onPluginError = { _, msg, _ ->
                isMounted = false
                errorMessage = msg
                chromeController?.isReady = false
            }
            slot.bridge.onPluginClose = {
                dismissHostPage()
            }
            slot.bridge.onPluginMinimize = { reqId, payload ->
                val keepOutside = (payload["keepOutsideApp"] as? JsonPrimitive)?.let { it.content == "true" } ?: false
                val reqOverlay = (payload["requestOverlayPermission"] as? JsonPrimitive)?.let { it.content == "true" } ?: false
                val overlayGranted = AndroidPluginCapsuleManager.canDrawSystemOverlays(context)
                if (keepOutside && reqOverlay && !overlayGranted) {
                    AndroidPluginCapsuleManager.openOverlayPermissionSettings(context)
                }
                val snap = PluginCapsuleSnapshot.fromMinimizePayload(
                    pluginId = pluginId,
                    fallbackName = chromeController?.title?.takeIf { it.isNotBlank() } ?: resolvedPluginName,
                    payload = payload,
                )
                if (reqId.isNotBlank()) {
                    slot.bridge.sendSimpleSuccess(
                        reqId,
                        "minimized" to true,
                        "overlaySupported" to true,
                        "overlayGranted" to overlayGranted,
                    )
                }
                AndroidPluginCapsuleManager.parkSession(
                    context = context,
                    session = MinimizedAndroidPluginSession(
                        pluginId = pluginId,
                        pluginName = snap.pluginName,
                        surface = surface,
                        pluginHasPage = pluginHasPage,
                        serverUrl = session.serverUrl,
                        slot = slot,
                        snapshot = snap,
                    ),
                )
                activeSlot = null
                dismissHostPage()
            }
            slot.bridge.onCapsuleUpdate = { patch ->
                AndroidPluginCapsuleManager.updateActiveSnapshot(patch)
            }
            slot.bridge.onPluginRestore = { reqId ->
                if (reqId.isNotBlank()) {
                    slot.bridge.sendSimpleSuccess(reqId, "restored" to true)
                }
            }
            slot.bridge.onNavBackResult = { handled ->
                pendingBackFallback.value?.let { backHandler.removeCallbacks(it) }
                pendingBackFallback.value = null
                if (!handled) {
                    dismissHostPage()
                }
            }
            slot.bridge.onHeaderUpdate = { title, actions ->
                if (chromeController != null) {
                    if (title.isNotBlank()) chromeController.title = title
                    chromeController.actions = actions
                }
            }
            slot.bridge.onToast = { toast ->
                activeToast = toast
            }
            slot.bridge.onConfirm = { conf ->
                if (chromeController != null) {
                    chromeController.confirmation = conf
                } else {
                    standaloneConfirm = conf
                }
            }
            slot.onRenderProcessGone = {
                isMounted = false
                errorMessage = "插件渲染进程异常中断，请重新加载。"
                chromeController?.isReady = false
            }

            if (chromeController != null) {
                chromeController.invokeActionHandler = { aid -> slot.bridge.sendHostAction(aid) }
                chromeController.requestCloseHandler = {
                    dispatchNavBackOrDismiss()
                }
                chromeController.respondConfirmationHandler = { cid, confirmed ->
                    slot.bridge.sendConfirmResult(cid, confirmed)
                }
            }
        }

        // 若该插件正处于最小化胶囊保活状态，零重载直接恢复原 WebView 实例
        val resumed = AndroidPluginCapsuleManager.consumeMatchingSession(pluginId, session.serverUrl)
        if (resumed != null) {
            val slot = resumed.slot
            slot.interceptor.updateSession(session)
            slot.bridge.updateSession(session)
            activeSlot = slot
            bindLiveSlotCallbacks(slot, resumed.pluginName)
            slot.bridge.sendVisualTokens(visualTokens)
            isMounted = true
            errorMessage = null
            chromeController?.isReady = true
            return@LaunchedEffect
        }

        val remoteResult = withContext(Dispatchers.IO) {
            fetchRemoteDescriptor(session, pluginId)
        }
        val descriptor = remoteResult.getOrElse { err ->
            errorMessage = err.message ?: "无法从后端获取联邦插件入口。"
            return@LaunchedEffect
        }
        val plan = RustCoreBridge.normalizePluginRemoteEntry(
            pluginId = descriptor.sourcePluginId ?: descriptor.id,
            versionOrHash = descriptor.preferredCacheVersion,
            rawRemoteUrl = descriptor.url,
        )
        if (plan == null) {
            errorMessage = "联邦插件入口路径不符合安全规范。"
            return@LaunchedEffect
        }

        val slot = AndroidPluginWebViewPool.acquire(context, session)
        activeSlot = slot
        bindLiveSlotCallbacks(slot, descriptor.name ?: pluginId)

        val mountPayload = buildMountPayload(
            pluginId = pluginId,
            descriptor = descriptor,
            virtualEntryUrl = "${PluginShellRequestInterceptor.VIRTUAL_ORIGIN}${plan.virtualEntryPath}",
            surface = surface,
            pluginHasPage = pluginHasPage,
            session = session,
            visualTokens = visualTokens,
        )
        slot.whenShellReady {
            slot.bridge.sendToWeb("plugin.mount", payload = mountPayload)
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            pendingBackFallback.value?.let { backHandler.removeCallbacks(it) }
            pendingBackFallback.value = null
            chromeController?.invokeActionHandler = null
            chromeController?.requestCloseHandler = null
            chromeController?.respondConfirmationHandler = null
            activeSlot?.let { slot ->
                activeSlot = null
                if (!AndroidPluginCapsuleManager.isSlotParked(slot)) {
                    AndroidPluginWebViewPool.release(slot, context)
                }
            }
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        val currentSlot = activeSlot
        if (currentSlot != null) {
            AndroidView(
                factory = { ctx ->
                    FrameLayout(ctx).apply {
                        setBackgroundColor(android.graphics.Color.TRANSPARENT)
                        attachPooledWebView(this, currentSlot.webView)
                    }
                },
                update = { container ->
                    attachPooledWebView(container, currentSlot.webView)
                },
                modifier = Modifier
                    .fillMaxSize()
                    .alpha(webAlpha),
            )
        }

        val err = errorMessage
        if (err != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.Center,
            ) {
                CinematicPanel(padding = 20.dp) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.WarningAmber,
                            contentDescription = null,
                            tint = colors.warning,
                            modifier = Modifier.size(30.dp),
                        )
                        Text(
                            text = "本地运行时加载插件失败",
                            color = colors.textPrimary,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = err,
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                        )
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            modifier = Modifier.padding(top = 4.dp),
                        ) {
                            Button(
                                onClick = { reloadNonce += 1 },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = colors.accent,
                                    contentColor = colors.primaryButtonFg,
                                ),
                            ) {
                                Text("重新加载")
                            }
                            OutlinedButton(onClick = onFallbackToLegacy) {
                                Text("用兼容网页容器打开", color = colors.textPrimary)
                            }
                        }
                        if (chromeController != null || onRequestExit != null) {
                            TextButton(onClick = dismissHostPage) {
                                Text("返回上一页", color = colors.textSecondary)
                            }
                        }
                    }
                }
            }
        } else if (!isMounted) {
            NativeCardListSkeleton(
                style = SkeletonCardStyle.FormPanel,
                count = 3,
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
                modifier = Modifier.fillMaxSize(),
            )
        }

        AnimatedVisibility(
            visible = activeToast != null,
            enter = fadeIn(tween(150)),
            exit = fadeOut(tween(180)),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(horizontal = 16.dp, vertical = 20.dp),
        ) {
            activeToast?.let { toast ->
                val (icon, tint) = when (toast.level.lowercase()) {
                    "success" -> Icons.Outlined.CheckCircle to colors.success
                    "warning" -> Icons.Outlined.WarningAmber to colors.warning
                    "error" -> Icons.Outlined.ErrorOutline to colors.danger
                    else -> Icons.Outlined.Info to colors.accent
                }
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = colors.surfaceContainerHigh,
                    border = BorderStroke(1.dp, colors.divider),
                    shadowElevation = 6.dp,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    ) {
                        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
                        Text(toast.message, color = colors.textPrimary, fontSize = 13.5.sp)
                    }
                }
            }
        }
    }

    standaloneConfirm?.let { conf ->
        AlertDialog(
            onDismissRequest = {
                standaloneConfirm = null
                activeSlot?.bridge?.sendConfirmResult(conf.id, false)
            },
            title = { Text(conf.title) },
            text = { Text(conf.message) },
            confirmButton = {
                TextButton(
                    onClick = {
                        standaloneConfirm = null
                        activeSlot?.bridge?.sendConfirmResult(conf.id, true)
                    },
                ) {
                    Text(conf.confirmText, color = if (conf.destructive) colors.danger else colors.accent)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        standaloneConfirm = null
                        activeSlot?.bridge?.sendConfirmResult(conf.id, false)
                    },
                ) {
                    Text(conf.cancelText)
                }
            },
        )
    }
}

private tailrec fun Context.findHostActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findHostActivity()
    else -> null
}

private fun attachPooledWebView(container: FrameLayout, webView: android.webkit.WebView) {
    if (webView.parent === container) return
    (webView.parent as? ViewGroup)?.removeView(webView)
    container.removeAllViews()
    container.addView(
        webView,
        FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        ),
    )
    val layoutTagKey = 0x504C5756 // "PLWV"
    if (container.getTag(layoutTagKey) == null) {
        val listener = android.view.View.OnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            val w = right - left
            val h = bottom - top
            if (w > 0 && h > 0 && (w != oldRight - oldLeft || h != oldBottom - oldTop)) {
                webView.post {
                    runCatching { webView.evaluateJavascript("window.dispatchEvent(new Event('resize'));", null) }
                }
            }
        }
        container.addOnLayoutChangeListener(listener)
        container.setTag(layoutTagKey, listener)
    }
    webView.post {
        runCatching { webView.evaluateJavascript("window.dispatchEvent(new Event('resize'));", null) }
    }
}

private fun fetchRemoteDescriptor(
    session: VuePluginSessionPayload,
    pluginId: String,
): Result<RemotePluginEntryMeta> = runCatching {
    val client = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
    val url = "${session.serverUrl.trimEnd('/')}/api/v1/plugin/remotes?token=moviepilot"
    val req = Request.Builder()
        .url(url)
        .header("Authorization", "Bearer ${session.authToken}")
        .header("X-MoviePilot-Locale", "zh-CN")
        .build()
    client.newCall(req).execute().use { resp ->
        if (!resp.isSuccessful) {
            error("获取联邦插件入口失败（HTTP ${resp.code}）")
        }
        val body = resp.body?.string().orEmpty()
        val json = Json { ignoreUnknownKeys = true; isLenient = true }
        val root = json.parseToJsonElement(body)
        val arr = when (root) {
            is JsonArray -> root
            is JsonObject -> (root["data"] as? JsonArray) ?: JsonArray(emptyList())
            else -> JsonArray(emptyList())
        }
        val metas = arr.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val id = (obj["id"] as? JsonPrimitive)?.content ?: return@mapNotNull null
            val entryUrl = (obj["url"] as? JsonPrimitive)?.content ?: return@mapNotNull null
            RemotePluginEntryMeta(
                id = id,
                url = entryUrl,
                name = (obj["name"] as? JsonPrimitive)?.content,
                sourcePluginId = (obj["source_plugin_id"] as? JsonPrimitive)?.content?.takeIf { it != "null" },
                version = (obj["version"] as? JsonPrimitive)?.content?.takeIf { it != "null" },
                bundleHash = (obj["bundle_hash"] as? JsonPrimitive)?.content?.takeIf { it != "null" },
            )
        }
        metas.firstOrNull { it.id.equals(pluginId, ignoreCase = true) }
            ?: error("未在运行态联邦插件列表中找到 $pluginId")
    }
}

private fun buildMountPayload(
    pluginId: String,
    descriptor: RemotePluginEntryMeta,
    virtualEntryUrl: String,
    surface: VuePluginSurface,
    pluginHasPage: Boolean,
    session: VuePluginSessionPayload,
    visualTokens: AndroidPluginVisualTokens,
): JsonObject {
    val surfaceName = when (surface) {
        VuePluginSurface.DataPage -> "dataPage"
        VuePluginSurface.Config -> "config"
        is VuePluginSurface.AppPage -> "appPage"
    }
    return buildJsonObject {
        put("mountId", java.util.UUID.randomUUID().toString())
        put("pluginId", pluginId)
        if (!descriptor.sourcePluginId.isNullOrBlank()) put("sourcePluginId", descriptor.sourcePluginId)
        if (!descriptor.name.isNullOrBlank()) put("pluginName", descriptor.name)
        if (!descriptor.version.isNullOrBlank()) put("pluginVersion", descriptor.version)
        put("remoteEntryUrl", virtualEntryUrl)
        put("surface", surfaceName)
        if (surface is VuePluginSurface.AppPage) put("navKey", surface.navKey)
        put("showSwitch", pluginHasPage)
        put("locale", "zh-CN")
        put("visualTokens", visualTokens.toJsonObject())
        put(
            "safeArea",
            buildJsonObject {
                put("top", 0)
                put("bottom", 16)
                put("left", 0)
                put("right", 0)
            },
        )
        put(
            "user",
            buildJsonObject {
                put("id", session.userId)
                put("superUser", session.isSuperuser)
                put("userName", session.userName)
                put("avatar", session.avatar)
                put("level", 2)
                put(
                    "permissions",
                    buildJsonObject {
                        put("discovery", true)
                        put("search", true)
                        put("subscribe", true)
                        put("manage", true)
                        put("admin", session.isSuperuser)
                    },
                )
            },
        )
    }
}
