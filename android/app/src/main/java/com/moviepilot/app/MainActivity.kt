package com.moviepilot.app

import android.content.Intent
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import coil.Coil
import coil.ImageLoader
import coil.decode.DataSource
import coil.decode.ImageSource
import coil.fetch.FetchResult
import coil.fetch.Fetcher
import coil.fetch.SourceResult
import coil.request.Options
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.MoviePilotTheme
import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeAppearanceStore
import com.moviepilot.media.LocalMediaMetadataExtractor
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.PlaybackPipBridge
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SessionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.Buffer

/**
 * MoviePilot Android 主入口 Activity：
 * 启用全屏 Edge-to-Edge 透明状态栏/导航栏，处理 `moviepilot://` 深度链接与系统音视频文件打开方式。
 */
class MainActivity : ComponentActivity() {
    private lateinit var repository: MoviePilotRepository
    private lateinit var appearanceStore: NativeAppearanceStore

    private var pendingDeepLink by mutableStateOf<String?>(null)
    private var pendingDeepLinkOrigin by mutableStateOf<String?>(null)
    private var pendingExternalMedia by mutableStateOf<MediaPlaybackRequest?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)

        AndroidPushProvider.ensureChannels(this)
        repository = MoviePilotRepository(applicationContext)
        // 为 Coil 注入同源鉴权、Cookie 复用 OkHttpClient 与 data:image Base64 解码器，秒开全部海报、用户头像与站点图标
        Coil.setImageLoader(
            ImageLoader.Builder(applicationContext)
                .okHttpClient {
                    repository.transport.buildImageClient(
                        serverUrlProvider = { (repository.session.value as? SessionState.Authenticated)?.serverUrl },
                        tokenProvider = { (repository.session.value as? SessionState.Authenticated)?.token },
                    )
                }
                .components {
                    add(
                        Fetcher.Factory<android.net.Uri> { data, options, _ ->
                            val raw = data.toString()
                            if (raw.startsWith("data:image/")) Base64DataUriFetcher(raw, options) else null
                        },
                    )
                    add(
                        Fetcher.Factory<String> { data, options, _ ->
                            if (data.startsWith("data:image/")) Base64DataUriFetcher(data, options) else null
                        },
                    )
                }
                .crossfade(true)
                .build(),
        )
        appearanceStore = NativeAppearanceStore(applicationContext)
        if (savedInstanceState == null) {
            handleIntent(intent)
        }
        val systemDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val initialDark = appearanceStore.resolveIsDark(systemDark)
        window.setBackgroundDrawable(
            ColorDrawable(if (initialDark) android.graphics.Color.BLACK else 0xFFF4F6FA.toInt()),
        )

        setContent {
            MoviePilotTheme(appearanceStore = appearanceStore) {
                val isDark = LocalMoviePilotColors.current.isDark
                val view = LocalView.current
                LaunchedEffect(isDark, appearanceStore.mode, appearanceStore.pureBlackDark) {
                    window.setBackgroundDrawable(
                        ColorDrawable(if (isDark) android.graphics.Color.BLACK else 0xFFF4F6FA.toInt()),
                    )
                    appearanceStore.syncPlatformNightMode()
                }
                SideEffect {
                    val controller = WindowCompat.getInsetsController(window, view)
                    controller.isAppearanceLightStatusBars = !isDark
                    controller.isAppearanceLightNavigationBars = !isDark
                }
                MoviePilotRootShell(
                    repository = repository,
                    incomingDeepLink = pendingDeepLink,
                    incomingDeepLinkOrigin = pendingDeepLinkOrigin,
                    incomingExternalMedia = pendingExternalMedia,
                    onConsumeDeepLink = {
                        pendingDeepLink = null
                        pendingDeepLinkOrigin = null
                    },
                    onConsumeExternalMedia = { pendingExternalMedia = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        PlaybackPipBridge.notifyUserLeaveHint()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        // 支持验收测试通过显式 Extra 切换外观深浅色（不引入任何硬编码业务数据）
        intent.getStringExtra("appearance_mode")?.let { modeId ->
            appearanceStore.updateMode(NativeAppearanceMode.fromId(modeId))
        }
        val extraRoute = (
            intent.getStringExtra(AndroidPushProvider.EXTRA_NOTIFICATION_ROUTE)
                ?: intent.getStringExtra("route")
            )?.trim()
        if (!extraRoute.isNullOrEmpty() && extraRoute.startsWith("/")) {
            pendingDeepLinkOrigin = intent.getStringExtra(AndroidPushProvider.EXTRA_NOTIFICATION_ORIGIN)
                ?: intent.getStringExtra("origin")
            pendingDeepLink = extraRoute
            return
        }
        val uri = intent.data ?: return
        when (uri.scheme?.lowercase()) {
            "moviepilot" -> {
                pendingDeepLinkOrigin = null
                pendingDeepLink = uri.toString()
            }
            "moviepilot-app" -> {
                pendingDeepLinkOrigin = AndroidPushProvider.extractNotificationOrigin(uri.toString())
                pendingDeepLink = uri.toString()
            }
            "content", "file" -> {
                val mimeHint = intent.type
                lifecycleScope.launch {
                    val extracted = withContext(Dispatchers.IO) {
                        LocalMediaMetadataExtractor.buildLocalPlaybackRequest(
                            context = applicationContext,
                            uri = uri,
                            mimeHint = mimeHint,
                        )
                    }
                    pendingExternalMedia = extracted
                }
            }
        }
    }
}

/** 支持 `data:image/...;base64,...` 内联头像与 PT 站点 Favicon 直接由 Coil 渲染。 */
private class Base64DataUriFetcher(
    private val dataUri: String,
    private val options: Options,
) : Fetcher {
    override suspend fun fetch(): FetchResult {
        val commaIdx = dataUri.indexOf(',')
        val header = if (commaIdx > 0) dataUri.substring(5, commaIdx) else "image/png"
        val mime = header.substringBefore(';').ifBlank { "image/png" }
        val payload = if (commaIdx > 0) dataUri.substring(commaIdx + 1) else ""
        val bytes = Base64.decode(payload, Base64.DEFAULT)
        return SourceResult(
            source = ImageSource(Buffer().write(bytes), options.context),
            mimeType = mime,
            dataSource = DataSource.MEMORY,
        )
    }
}
