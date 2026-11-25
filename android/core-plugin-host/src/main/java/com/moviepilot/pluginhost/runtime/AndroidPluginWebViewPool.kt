package com.moviepilot.pluginhost.runtime

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.ContextCompat
import com.moviepilot.pluginhost.VuePluginSessionPayload

/**
 * Android 端可热复用的本地联邦运行时 WebView 实例槽。
 */
class PooledAndroidPluginWebView(
    val webView: WebView,
    val interceptor: PluginShellRequestInterceptor,
    val bridge: AndroidPluginHostBridgeV2,
) {
    enum class State { COLD, WARMING, WARM_IDLE, ACTIVE, DISPOSED }

    var state: State = State.COLD
    var reuseCount: Int = 0
    var isShellReady: Boolean = false
    val readyCallbacks = mutableListOf<() -> Unit>()
    var onRenderProcessGone: (() -> Unit)? = null

    fun markShellReady() {
        if (isShellReady) return
        isShellReady = true
        if (state == State.WARMING) {
            state = State.WARM_IDLE
        }
        val pending = readyCallbacks.toList()
        readyCallbacks.clear()
        pending.forEach { it() }
    }

    fun whenShellReady(callback: () -> Unit) {
        if (isShellReady) {
            callback()
        } else {
            readyCallbacks += callback
        }
    }
}

/**
 * Android 端 Vue 联邦插件本地预热 `WebView` 池（Route A）：
 * - 维护 1 个透明热备 `WebView`（`https://plugin-shell.moviepilot.local/shell/plugin-shell.html`）；
 * - 单实例复用上限 15 次，自动处理 `onRenderProcessGone`、低内存回收及退出登录/切换实例彻底销毁。
 */
object AndroidPluginWebViewPool {
    private const val MAX_REUSES = 15
    private val mainHandler = Handler(Looper.getMainLooper())
    private var idleSlot: PooledAndroidPluginWebView? = null
    private var activeSlot: PooledAndroidPluginWebView? = null
    private var prewarmRunnable: Runnable? = null

    fun scheduleIdlePrewarm(context: Context, delayMs: Long = 1500L) {
        val appCtx = context.applicationContext
        prewarmRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            if (idleSlot == null) {
                idleSlot = createWarmingSlot(appCtx)
            }
        }
        prewarmRunnable = r
        mainHandler.postDelayed(r, delayMs)
    }

    fun acquire(context: Context, session: VuePluginSessionPayload): PooledAndroidPluginWebView {
        val appCtx = context.applicationContext
        val warm = idleSlot
        val slot = if (warm != null && (warm.state == PooledAndroidPluginWebView.State.WARM_IDLE || warm.state == PooledAndroidPluginWebView.State.WARMING)) {
            idleSlot = null
            warm
        } else {
            createWarmingSlot(appCtx)
        }
        slot.state = PooledAndroidPluginWebView.State.ACTIVE
        slot.reuseCount += 1
        slot.interceptor.updateSession(session)
        slot.bridge.updateSession(session)
        activeSlot = slot
        return slot
    }

    fun release(slot: PooledAndroidPluginWebView, context: Context, forceDispose: Boolean = false) {
        slot.bridge.sendUnmount()
        slot.bridge.abortAllInFlightRequests()
        slot.bridge.cleanupNativeCapabilities()
        slot.bridge.clearCallbacks()
        slot.bridge.updateSession(null)
        slot.interceptor.updateSession(null)
        slot.onRenderProcessGone = null
        slot.readyCallbacks.clear()
        if (activeSlot === slot) activeSlot = null

        (slot.webView.parent as? ViewGroup)?.removeView(slot.webView)

        val canRecycle = !forceDispose &&
            slot.state != PooledAndroidPluginWebView.State.DISPOSED &&
            slot.isShellReady &&
            slot.reuseCount < MAX_REUSES &&
            idleSlot == null

        if (canRecycle) {
            slot.state = PooledAndroidPluginWebView.State.WARM_IDLE
            slot.bridge.onShellReady = { slot.markShellReady() }
            idleSlot = slot
        } else {
            disposeSlot(slot)
            scheduleIdlePrewarm(context, 1500L)
        }
    }

    fun resetForSessionChange() {
        mainHandler.post {
            prewarmRunnable?.let { mainHandler.removeCallbacks(it) }
            prewarmRunnable = null
            idleSlot?.let {
                idleSlot = null
                disposeSlot(it)
            }
            activeSlot?.let {
                it.bridge.abortAllInFlightRequests()
                it.bridge.cleanupNativeCapabilities()
                it.bridge.updateSession(null)
                it.interceptor.updateSession(null)
                it.state = PooledAndroidPluginWebView.State.DISPOSED
            }
        }
    }

    fun onTrimMemory() {
        mainHandler.post {
            idleSlot?.let {
                idleSlot = null
                disposeSlot(it)
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWarmingSlot(appContext: Context): PooledAndroidPluginWebView {
        val interceptor = PluginShellRequestInterceptor(appContext)
        val bridge = AndroidPluginHostBridgeV2(appContext)
        val wv = WebView(appContext)
        lateinit var slot: PooledAndroidPluginWebView

        wv.setBackgroundColor(Color.TRANSPARENT)
        wv.isVerticalScrollBarEnabled = true
        wv.isHorizontalScrollBarEnabled = false
        wv.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = false
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = false
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        wv.addJavascriptInterface(bridge, AndroidPluginHostBridgeV2.JS_INTERFACE_NAME)
        wv.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                val originHost = request.origin?.host.orEmpty()
                if (!originHost.equals(PluginShellRequestInterceptor.VIRTUAL_HOST, ignoreCase = true)) {
                    request.deny()
                    return
                }
                val resources = request.resources ?: emptyArray()
                val needsAudio = PermissionRequest.RESOURCE_AUDIO_CAPTURE in resources
                val needsVideo = PermissionRequest.RESOURCE_VIDEO_CAPTURE in resources
                val neededPerms = mutableListOf<String>()
                if (needsAudio && ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    neededPerms += Manifest.permission.RECORD_AUDIO
                }
                if (needsVideo && ContextCompat.checkSelfPermission(appContext, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                    neededPerms += Manifest.permission.CAMERA
                }
                if (neededPerms.isEmpty()) {
                    request.grant(resources)
                    return
                }
                val host = bridge.nativeCapabilities.activityHost
                if (host == null) {
                    request.deny()
                    return
                }
                fun requestNext(idx: Int) {
                    if (idx >= neededPerms.size) {
                        request.grant(resources)
                        return
                    }
                    host.requestPermission(neededPerms[idx]) { granted ->
                        if (granted) requestNext(idx + 1) else request.deny()
                    }
                }
                requestNext(0)
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>,
                fileChooserParams: FileChooserParams,
            ): Boolean {
                val host = bridge.nativeCapabilities.activityHost ?: return false
                val accept = fileChooserParams.acceptTypes?.filter { it.isNotBlank() }.orEmpty()
                val multiple = fileChooserParams.mode == FileChooserParams.MODE_OPEN_MULTIPLE
                host.pickFile(accept, multiple) { uris ->
                    filePathCallback.onReceiveValue(if (uris.isEmpty()) null else uris.toTypedArray())
                }
                return true
            }
        }
        wv.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? = interceptor.intercept(request)

            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean {
                val url = request.url ?: return true
                if (url.host.equals(PluginShellRequestInterceptor.VIRTUAL_HOST, ignoreCase = true)) {
                    return false
                }
                return true
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                slot.state = PooledAndroidPluginWebView.State.DISPOSED
                if (idleSlot === slot) {
                    idleSlot = null
                    disposeSlot(slot)
                } else {
                    slot.onRenderProcessGone?.invoke()
                }
                return true
            }
        }

        bridge.webView = wv
        slot = PooledAndroidPluginWebView(wv, interceptor, bridge)
        slot.state = PooledAndroidPluginWebView.State.WARMING
        bridge.onShellReady = { slot.markShellReady() }
        wv.loadUrl(PluginShellRequestInterceptor.SHELL_ENTRY_URL)
        return slot
    }

    private fun disposeSlot(slot: PooledAndroidPluginWebView) {
        slot.state = PooledAndroidPluginWebView.State.DISPOSED
        slot.bridge.abortAllInFlightRequests()
        slot.bridge.cleanupNativeCapabilities()
        slot.bridge.clearCallbacks()
        slot.bridge.updateSession(null)
        slot.interceptor.updateSession(null)
        (slot.webView.parent as? ViewGroup)?.removeView(slot.webView)
        runCatching {
            slot.webView.stopLoading()
            slot.webView.removeJavascriptInterface(AndroidPluginHostBridgeV2.JS_INTERFACE_NAME)
            slot.webView.destroy()
        }
    }
}
