package com.moviepilot.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.MoviePilotTheme
import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeAppearanceStore
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge

/**
 * MoviePilot Android 主入口 Activity：
 * 启用全屏 Edge-to-Edge 透明状态栏/导航栏，处理 `moviepilot://` 深度链接与系统音视频文件打开方式。
 */
class MainActivity : ComponentActivity() {
    private lateinit var repository: MoviePilotRepository
    private lateinit var appearanceStore: NativeAppearanceStore

    private var pendingDeepLink by mutableStateOf<String?>(null)
    private var pendingExternalMedia by mutableStateOf<MediaPlaybackRequest?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)

        AndroidPushProvider.ensureChannels(this)
        repository = MoviePilotRepository(applicationContext)
        appearanceStore = NativeAppearanceStore(applicationContext)
        handleIntent(intent)

        setContent {
            MoviePilotTheme(appearanceStore = appearanceStore) {
                val isDark = LocalMoviePilotColors.current.isDark
                val view = LocalView.current
                SideEffect {
                    val controller = WindowCompat.getInsetsController(window, view)
                    controller.isAppearanceLightStatusBars = !isDark
                    controller.isAppearanceLightNavigationBars = !isDark
                }
                MoviePilotRootShell(
                    repository = repository,
                    incomingDeepLink = pendingDeepLink,
                    incomingExternalMedia = pendingExternalMedia,
                    onConsumeIncoming = {
                        pendingDeepLink = null
                        pendingExternalMedia = null
                    },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        // 支持验收测试通过显式 Extra 切换外观深浅色（不引入任何硬编码业务数据）
        intent.getStringExtra("appearance_mode")?.let { modeId ->
            appearanceStore.updateMode(NativeAppearanceMode.fromId(modeId))
        }
        val uri = intent.data ?: return
        when (uri.scheme?.lowercase()) {
            "moviepilot" -> pendingDeepLink = uri.toString()
            "content", "file" -> {
                val path = uri.toString()
                val isAudio = intent.type?.startsWith("audio/") == true ||
                    RustCoreBridge.detectMediaKind(path) == "audio"
                pendingExternalMedia = MediaPlaybackRequest(
                    url = path,
                    title = uri.lastPathSegment ?: "本地媒体文件",
                    isAudio = isAudio,
                )
            }
        }
    }
}
