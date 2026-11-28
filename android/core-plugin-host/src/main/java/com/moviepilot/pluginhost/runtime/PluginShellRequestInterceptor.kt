package com.moviepilot.pluginhost.runtime

import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import androidx.webkit.WebViewAssetLoader
import com.moviepilot.pluginhost.VuePluginSessionPayload
import com.moviepilot.rustbridge.RustCoreBridge
import java.io.ByteArrayInputStream

/**
 * Android 端虚拟安全源 `https://plugin-shell.moviepilot.local/` 请求拦截器：
 * - `/shell/` 路径通过 `WebViewAssetLoader` 从 APK `assets/plugin_shell/` 零网络返回；
 * - `/plugin-remote/{id}/{ver}/` 路径优先读实例隔离磁盘缓存，未命中时经 `OkHttpClient` 携鉴权头回源并落盘；
 * - `/api/v1/` 路径仅代理被动 `GET` 静态资源（图片、图标），杜绝在 WebView 暴露 Bearer Token。
 */
class PluginShellRequestInterceptor(
    private val appContext: Context,
    private val currentSession: ((VuePluginSessionPayload) -> VuePluginSessionPayload?)? = null,
    refreshResourceCookie: (() -> Unit)? = null,
) {
    companion object {
        const val VIRTUAL_HOST = "plugin-shell.moviepilot.local"
        const val VIRTUAL_ORIGIN = "https://$VIRTUAL_HOST"
        const val SHELL_ENTRY_URL = "$VIRTUAL_ORIGIN/shell/plugin-shell.html"
    }

    @Volatile
    private var activeSession: VuePluginSessionPayload? = null

    private val resources = PluginResourceHttpClient({ resolveSession() }, refreshResourceCookie)

    private val assetLoader = WebViewAssetLoader.Builder()
        .setDomain(VIRTUAL_HOST)
        .addPathHandler("/shell/", WebViewAssetLoader.AssetsPathHandler(appContext))
        .build()

    /** 更新容器归属会话；置空后停止所有新的带凭据资源请求。 */
    fun updateSession(session: VuePluginSessionPayload?) {
        activeSession = session
    }

    /** 助手容器按请求读取原生 Cookie，失效的会话不能回退到旧快照。 */
    private fun resolveSession(): VuePluginSessionPayload? {
        val bound = activeSession ?: return null
        return if (currentSession != null) currentSession.invoke(bound) else bound
    }

    /** 拦截虚拟安全源请求，只代理经 Rust 校验的资源路径。 */
    fun intercept(request: WebResourceRequest): WebResourceResponse? {
        val uri = request.url ?: return null
        if (!uri.scheme.equals("https", ignoreCase = true) || !uri.host.equals(VIRTUAL_HOST, ignoreCase = true)) {
            return null
        }
        val method = request.method.uppercase()
        if (method == "OPTIONS") {
            return WebResourceResponse(
                "text/plain",
                "utf-8",
                204,
                "No Content",
                corsHeaders("no-store"),
                ByteArrayInputStream(ByteArray(0)),
            )
        }
        val path = uri.path.orEmpty()
        return when {
            path.startsWith("/shell/") -> serveShellAsset(path)
            path.startsWith("/plugin-remote/") -> serveRemotePluginAsset(path)
            path.startsWith("/api/v1/") -> {
                if (method != "GET" && method != "HEAD") {
                    errorResponse(405, "Only passive GET allowed")
                } else {
                    val pathWithQuery = if (!uri.encodedQuery.isNullOrEmpty()) "$path?${uri.encodedQuery}" else path
                    servePassiveApiResource(pathWithQuery)
                }
            }
            else -> errorResponse(404, "Not Found")
        }
    }

    /** 从 APK 读取受控的本地插件壳资源。 */
    private fun serveShellAsset(virtualPath: String): WebResourceResponse {
        val relPath = RustCoreBridge.validatePluginShellAssetPath(virtualPath)
            ?: return errorResponse(400, "Invalid shell asset path")
        // 优先走 WebViewAssetLoader 或直接从 assets/plugin_shell/ 读取并补充 CORS + 精准 MIME
        val bytes = runCatching {
            appContext.assets.open("plugin_shell/$relPath").use { it.readBytes() }
        }.getOrNull()
        if (bytes != null) {
            val mime = PluginRemoteDiskCache.guessMimeType(relPath)
            val encoding = if (mime.startsWith("text/") || mime.contains("javascript") || mime.contains("json") || mime.contains("svg")) "utf-8" else null
            return WebResourceResponse(
                mime,
                encoding,
                200,
                "OK",
                corsHeaders("no-cache"),
                ByteArrayInputStream(bytes),
            )
        }
        return assetLoader.shouldInterceptRequest(android.net.Uri.parse("$VIRTUAL_ORIGIN/shell/plugin_shell/$relPath"))
            ?: errorResponse(404, "Shell asset not found")
    }

    /** 优先读取实例缓存，未命中时以最新资源 Cookie 回源。 */
    private fun serveRemotePluginAsset(virtualPath: String): WebResourceResponse {
        val target = RustCoreBridge.resolvePluginRemoteUpstream(virtualPath)
            ?: return errorResponse(400, "Invalid plugin remote path")
        val session = resolveSession() ?: return errorResponse(401, "No active session")
        val origin = session.serverUrl.trimEnd('/')

        PluginRemoteDiskCache.read(
            context = appContext,
            instanceOrigin = origin,
            pluginId = target.pluginId,
            versionTag = target.versionTag,
            assetRelPath = target.assetRelPath,
        )?.let { cached ->
            return buildBinaryResponse(200, cached.mimeType, cached.bytes, "public, max-age=31536000, immutable")
        }

        return runCatching {
            val response = resources.execute(target.upstreamApiPath)
                ?: return errorResponse(401, "No active session")
            response.use { resp ->
                val data = resp.body?.bytes() ?: ByteArray(0)
                val rawCt = resp.header("Content-Type")?.substringBefore(';')?.trim().orEmpty()
                val mime = if (rawCt.isBlank() || rawCt == "application/octet-stream") {
                    PluginRemoteDiskCache.guessMimeType(target.assetRelPath)
                } else {
                    rawCt
                }
                if (resp.isSuccessful) {
                    PluginRemoteDiskCache.write(
                        context = appContext,
                        instanceOrigin = origin,
                        pluginId = target.pluginId,
                        versionTag = target.versionTag,
                        assetRelPath = target.assetRelPath,
                        bytes = data,
                        mimeType = mime,
                    )
                }
                buildBinaryResponse(
                    status = resp.code,
                    mimeType = mime,
                    bytes = data,
                    cacheControl = if (resp.isSuccessful) "public, max-age=31536000, immutable" else "no-store",
                )
            }
        }.getOrElse { err ->
            errorResponse(502, err.message ?: "Upstream fetch failed")
        }
    }

    /** 代理插件只读资源并使用相同的 Cookie 刷新边界。 */
    private fun servePassiveApiResource(pathWithQuery: String): WebResourceResponse {
        val normalized = RustCoreBridge.validatePluginApiPath(pathWithQuery)
            ?: return errorResponse(400, "Invalid API path")
        return runCatching {
            val response = resources.execute(normalized)
                ?: return errorResponse(401, "No active session")
            response.use { resp ->
                val data = resp.body?.bytes() ?: ByteArray(0)
                val rawCt = resp.header("Content-Type")?.substringBefore(';')?.trim().orEmpty()
                val mime = if (rawCt.isBlank() || rawCt == "application/octet-stream") {
                    PluginRemoteDiskCache.guessMimeType(normalized)
                } else {
                    rawCt
                }
                buildBinaryResponse(resp.code, mime, data, "private, max-age=300")
            }
        }.getOrElse { err ->
            errorResponse(502, err.message ?: "Passive proxy failed")
        }
    }

    /** 为虚拟安全源响应补齐 CORS 与缓存策略。 */
    private fun corsHeaders(cacheControl: String): Map<String, String> = mapOf(
        "Access-Control-Allow-Origin" to VIRTUAL_ORIGIN,
        "Access-Control-Allow-Methods" to "GET, HEAD, OPTIONS",
        "Access-Control-Allow-Headers" to "*",
        "Cache-Control" to cacheControl,
    )

    /** 构造保留上游状态码和资源 MIME 的二进制响应。 */
    private fun buildBinaryResponse(
        status: Int,
        mimeType: String,
        bytes: ByteArray,
        cacheControl: String,
    ): WebResourceResponse {
        val encoding = if (mimeType.startsWith("text/") || mimeType.contains("javascript") || mimeType.contains("json") || mimeType.contains("svg")) "utf-8" else null
        return WebResourceResponse(
            mimeType,
            encoding,
            status,
            if (status in 200..299) "OK" else "Error",
            corsHeaders(cacheControl),
            ByteArrayInputStream(bytes),
        )
    }

    /** 构造不可缓存的本地拦截错误。 */
    private fun errorResponse(status: Int, message: String): WebResourceResponse =
        WebResourceResponse(
            "text/plain",
            "utf-8",
            status,
            message,
            corsHeaders("no-store"),
            ByteArrayInputStream(message.toByteArray(Charsets.UTF_8)),
        )
}
