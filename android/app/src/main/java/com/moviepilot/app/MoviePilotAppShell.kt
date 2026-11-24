package com.moviepilot.app

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicAmbientGradient
import com.moviepilot.designsystem.FloatingAgentMascot
import com.moviepilot.designsystem.FloatingNavigationRail
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalHazeState
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.MainTab
import com.moviepilot.designsystem.MoviePilotBottomNavigationBar
import com.moviepilot.feature.agent.AgentChatScreen
import com.moviepilot.feature.auth.LoginScreen
import com.moviepilot.feature.auth.ServerConnectionScreen
import com.moviepilot.feature.automation.SitesScreen
import com.moviepilot.feature.automation.WorkflowCanvasScreen
import com.moviepilot.feature.automation.WorkflowsScreen
import com.moviepilot.feature.dashboard.DashboardScreen
import com.moviepilot.feature.dashboard.MessagesCenterScreen
import com.moviepilot.feature.dashboard.ShortcutsDiagnosticsScreen
import com.moviepilot.feature.dashboard.WorkspaceHubScreen
import com.moviepilot.feature.discover.DiscoverScreen
import com.moviepilot.feature.discover.ExploreScreen
import com.moviepilot.feature.discover.GlobalSearchScreen
import com.moviepilot.feature.discover.MediaServerLibraryScreen
import com.moviepilot.feature.discover.MusicDiscoveryScreen
import com.moviepilot.feature.download.DownloadsScreen
import com.moviepilot.feature.download.ResourceSearchScreen
import com.moviepilot.feature.library.FileManagerScreen
import com.moviepilot.feature.library.TransferHistoryScreen
import com.moviepilot.feature.media.MediaDetailScreen
import com.moviepilot.feature.media.MediaServerDetailScreen
import com.moviepilot.feature.media.PersonDetailScreen
import com.moviepilot.feature.settings.AppearanceSettingsScreen
import com.moviepilot.feature.settings.ChannelAuthorizationScreen
import com.moviepilot.feature.settings.DirectoriesStorageSettingsScreen
import com.moviepilot.feature.settings.DownloadersSettingsScreen
import com.moviepilot.feature.settings.MediaServersSettingsScreen
import com.moviepilot.feature.settings.MediaSourcesSettingsScreen
import com.moviepilot.feature.settings.NotificationsSettingsScreen
import com.moviepilot.feature.settings.PlaybackPreferencesScreen
import com.moviepilot.feature.settings.PluginDetailScreen
import com.moviepilot.feature.settings.PluginsCenterScreen
import com.moviepilot.feature.settings.SettingsHubScreen
import com.moviepilot.feature.settings.SubscribeSearchSettingsScreen
import com.moviepilot.feature.settings.UsersManagementScreen
import com.moviepilot.feature.subscribe.CalendarScreen
import com.moviepilot.feature.subscribe.SubscribeCommunityScreen
import com.moviepilot.feature.subscribe.SubscriptionsScreen
import com.moviepilot.medal3d.CommunityProfile
import com.moviepilot.medal3d.NativeCommunityMedalShowcaseOverlay
import com.moviepilot.media.FloatingMiniMusicBar
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.NativeMediaPlayerOverlay
import com.moviepilot.media.buildConfiguredExoPlayer
import com.moviepilot.pluginhost.clearIsolatedPluginWebViewSession
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaPersonDto
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import com.moviepilot.rustbridge.WorkflowItemDto
import com.moviepilot.rustcore.PermissionsFfi
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** 主壳路由目的栈条目（覆盖全部业务页面、分类探索、媒体库、独立人物页、独立消息页、渠道授权、插件宿主与全部设置模块）。 */
sealed interface AppRoute {
    data object TabRoot : AppRoute
    data class Explore(val source: String = "tmdb_movies") : AppRoute
    data object SettingsHub : AppRoute
    data class GlobalSearch(val query: String = "", val kind: String = "media") : AppRoute
    data class MediaDetail(val item: MediaCardItem) : AppRoute
    data class MediaServerDetail(
        val itemId: String,
        val server: String,
        val fallbackTitle: String = "",
        val fallbackPoster: String? = null,
    ) : AppRoute
    data class PersonDetail(val person: MediaPersonDto) : AppRoute
    data class MediaServerLibrary(val library: MediaServerLibraryDto) : AppRoute
    data object Messages : AppRoute
    data object Music : AppRoute
    data class Subscriptions(val category: String? = null) : AppRoute
    data object Calendar : AppRoute
    data object SubscribeCommunity : AppRoute
    data class Resources(val keyword: String = "") : AppRoute
    data object Downloads : AppRoute
    data class Files(val storage: String = "local", val path: String = "/") : AppRoute
    data class History(val search: String = "") : AppRoute
    data object Workflows : AppRoute
    data class WorkflowCanvas(val workflow: WorkflowItemDto) : AppRoute
    data object Sites : AppRoute
    data object Users : AppRoute
    data object SubscribeSearchSettings : AppRoute
    data object MediaSourcesSettings : AppRoute
    data object DownloadersSettings : AppRoute
    data object MediaServersSettings : AppRoute
    data object DirectoriesSettings : AppRoute
    data object NotificationsSettings : AppRoute
    data object ChannelAuthorization : AppRoute
    data object PlaybackSettings : AppRoute
    data class Plugins(val installedOnly: Boolean = true) : AppRoute
    data class PluginDetail(val plugin: PluginItemDto) : AppRoute
    data class Diagnostics(val tab: String = "词表") : AppRoute
    data class Agent(val prompt: String = "") : AppRoute
    data object Appearance : AppRoute
}

private data class BackStackEntry(
    val stateKey: String,
    val route: AppRoute,
)

/**
 * 校验目标路由是否满足当前用户的 `PermissionsFfi` RBAC 权限；返回 `null` 代表放行，非空字符串代表拦截原因。
 */
private fun checkRoutePermission(route: AppRoute, perms: PermissionsFfi): String? {
    if (perms.admin) return null
    return when (route) {
        AppRoute.Sites,
        AppRoute.Users,
        AppRoute.SubscribeSearchSettings,
        AppRoute.MediaSourcesSettings,
        AppRoute.DownloadersSettings,
        AppRoute.MediaServersSettings,
        AppRoute.DirectoriesSettings,
        AppRoute.NotificationsSettings,
        AppRoute.Workflows,
        is AppRoute.WorkflowCanvas,
        is AppRoute.Plugins,
        is AppRoute.PluginDetail,
        is AppRoute.Diagnostics,
        -> "当前账号无管理员权限"

        AppRoute.Downloads,
        is AppRoute.Files,
        is AppRoute.History,
        -> if (perms.manage) null else "当前账号无下载与文件整理权限"

        is AppRoute.Explore -> if (perms.discovery) null else "当前账号无探索与发现权限"

        is AppRoute.Resources -> if (perms.search) null else "当前账号无站点资源搜索权限"

        is AppRoute.Subscriptions,
        AppRoute.Calendar,
        AppRoute.SubscribeCommunity,
        -> if (perms.subscribe) null else "当前账号无订阅管理权限"

        else -> null
    }
}

/**
 * MoviePilot Android Material Design 3 根容器：
 * 1. 维护 4 个一级 Tab（发现、订阅、我的、更多）各自独立的子路由栈（`tabStacks`）并配合 `rememberSaveableStateHolder` 保活滚动位置与视图状态；
 * 2. 窄屏提供 4+1 分离式实时磨砂玻璃胶囊底栏（左侧 4 主 Tab + 右侧独立圆形「搜索」按钮），宽屏（`>= 600dp`）常驻左侧 `FloatingNavigationRail`；
 * 3. 支持 `NeedsLogin` -> `Authenticated` 跨登录态保留并自动重放 `incomingDeepLink`；
 * 4. 全局拦截 RBAC 管理员/子权限越权路由，并在登出或 401 会话过期时自动清理隔离插件 WebView 会话；
 * 5. 动态计算底部覆盖层安全内边距（`LocalBottomOverlayInset`），兼顾未登录本地音频悬浮迷你播控条。
 */
@Composable
fun MoviePilotRootShell(
    repository: MoviePilotRepository,
    incomingDeepLink: String?,
    incomingDeepLinkOrigin: String? = null,
    incomingExternalMedia: MediaPlaybackRequest?,
    onConsumeDeepLink: () -> Unit = {},
    onConsumeExternalMedia: () -> Unit = {},
    onConsumeIncoming: () -> Unit = {
        onConsumeDeepLink()
        onConsumeExternalMedia()
    },
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val appearanceStore = LocalAppearanceStore.current
    val scope = rememberCoroutineScope()
    val session by repository.session.collectAsState()
    val savedServers by repository.savedServers.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val shellHazeState = remember { HazeState() }
    val saveableStateHolder = rememberSaveableStateHolder()
    val medalJson = remember { Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true } }

    var allowSelfSignedTls by remember { mutableStateOf(repository.secretStore.allowSelfSignedTls) }
    var isSwitchingServer by rememberSaveable { mutableStateOf(false) }
    var selectedTabId by rememberSaveable { mutableStateOf(MainTab.Discover.id) }
    val selectedTab = MainTab.entries.firstOrNull { it.id == selectedTabId } ?: MainTab.Discover

    var nextEntrySeq by rememberSaveable { mutableIntStateOf(1) }
    val tabStacks = remember {
        mutableStateMapOf<MainTab, List<BackStackEntry>>(
            MainTab.Discover to emptyList(),
            MainTab.Subscribe to emptyList(),
            MainTab.Dashboard to emptyList(),
            MainTab.Workspace to emptyList(),
        )
    }

    val isWideCanvas = AdaptiveDeviceLayout.isWideCanvas()
    var activePlayerRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var bgAudioRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var bgAudioPlayer by remember { mutableStateOf<ExoPlayer?>(null) }
    var bgAudioPlaying by remember { mutableStateOf(false) }
    var activeMedalShowcase by remember { mutableStateOf<Pair<CommunityProfile, String>?>(null) }

    val activeStack = tabStacks[selectedTab].orEmpty()
    val currentRoute: AppRoute = activeStack.lastOrNull()?.route ?: AppRoute.TabRoot
    val currentStateKey: String = activeStack.lastOrNull()?.stateKey ?: "tab_root_${selectedTab.id}"

    fun clearTabStack(tab: MainTab) {
        tabStacks[tab].orEmpty().forEach { entry ->
            saveableStateHolder.removeState(entry.stateKey)
        }
        tabStacks[tab] = emptyList()
    }

    fun clearAllNavigationAndWebSession() {
        MainTab.entries.forEach { tab ->
            clearTabStack(tab)
            saveableStateHolder.removeState("tab_root_${tab.id}")
        }
        selectedTabId = MainTab.Discover.id
        clearIsolatedPluginWebViewSession(context)
    }

    fun onTabBarClick(tab: MainTab) {
        if (tab == selectedTab) {
            if (tabStacks[tab].orEmpty().isNotEmpty()) {
                clearTabStack(tab)
            }
        } else {
            selectedTabId = tab.id
        }
    }

    fun pushRoute(route: AppRoute, targetTab: MainTab = selectedTab) {
        if (route == AppRoute.TabRoot) {
            clearTabStack(targetTab)
            selectedTabId = targetTab.id
            return
        }
        val auth = session as? SessionState.Authenticated
        if (auth != null) {
            val deniedReason = checkRoutePermission(route, auth.permissions)
            if (deniedReason != null) {
                scope.launch { snackbarHostState.showSnackbar(deniedReason) }
                return
            }
        }
        if (targetTab != selectedTab) {
            selectedTabId = targetTab.id
        }
        val currentList = tabStacks[targetTab].orEmpty()
        val entry = BackStackEntry(
            stateKey = "sub_${targetTab.id}_${nextEntrySeq++}",
            route = route,
        )
        tabStacks[targetTab] = currentList + entry
    }

    fun popRoute() {
        val currentList = tabStacks[selectedTab].orEmpty()
        if (currentList.isNotEmpty()) {
            val popped = currentList.last()
            saveableStateHolder.removeState(popped.stateKey)
            tabStacks[selectedTab] = currentList.dropLast(1)
        }
    }

    /** 智能分发媒体卡片跳转：携带 `serverItemId` 与 `serverName` 的已入库卡片直达 `MediaServerDetailScreen`。 */
    fun openMediaSmart(item: MediaCardItem) {
        if (!item.serverItemId.isNullOrBlank() && !item.serverName.isNullOrBlank()) {
            pushRoute(
                AppRoute.MediaServerDetail(
                    itemId = item.serverItemId!!,
                    server = item.serverName!!,
                    fallbackTitle = item.title,
                    fallbackPoster = item.posterPath,
                ),
            )
        } else {
            pushRoute(AppRoute.MediaDetail(item))
        }
    }

    fun releaseBackgroundAudio() {
        bgAudioPlayer?.release()
        bgAudioPlayer = null
        bgAudioRequest = null
        bgAudioPlaying = false
    }

    fun startPlayback(req: MediaPlaybackRequest) {
        if (req.isAudio) {
            if (bgAudioRequest?.url != req.url || bgAudioPlayer == null) {
                bgAudioPlayer?.release()
                val player = buildConfiguredExoPlayer(context, req)
                player.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        bgAudioPlaying = isPlaying
                    }
                })
                bgAudioPlayer = player
                bgAudioRequest = req
                bgAudioPlaying = true
            } else {
                bgAudioPlayer?.playWhenReady = true
            }
            activePlayerRequest = req
        } else {
            bgAudioPlayer?.pause()
            activePlayerRequest = req
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            bgAudioPlayer?.release()
        }
    }

    // 监听从已认证态退出（含 401 自动登出）：清理所有 Tab 栈、状态持有器与隔离插件 WebView 会话
    var wasAuthenticated by remember { mutableStateOf(session is SessionState.Authenticated) }
    LaunchedEffect(session is SessionState.Authenticated) {
        val nowAuth = session is SessionState.Authenticated
        if (wasAuthenticated && !nowAuth) {
            clearAllNavigationAndWebSession()
        }
        wasAuthenticated = nowAuth
    }

    // Android 系统 Back 返回键 / 边缘侧滑统一接管（按播放器 -> 勋章 -> 切换服务覆盖层 -> 当前 Tab 子栈 -> Discover 根 Tab 顺序回退）
    val canHandleBack = activePlayerRequest != null ||
        activeMedalShowcase != null ||
        isSwitchingServer ||
        (session is SessionState.Authenticated && (activeStack.isNotEmpty() || selectedTab != MainTab.Discover))

    BackHandler(enabled = canHandleBack) {
        when {
            activePlayerRequest != null -> activePlayerRequest = null
            activeMedalShowcase != null -> activeMedalShowcase = null
            isSwitchingServer -> isSwitchingServer = false
            activeStack.isNotEmpty() -> popRoute()
            selectedTab != MainTab.Discover -> selectedTabId = MainTab.Discover.id
        }
    }

    // 鉴权就绪后拉取权威用户信息（真实头像）并预热图片代理 Cookie
    val authKey = (session as? SessionState.Authenticated)?.let { "${it.serverUrl}|${it.token.takeLast(8)}" }
    LaunchedEffect(authKey) {
        if (authKey != null) {
            repository.hydrateAuthenticatedSession()
        }
    }

    // 处理未登录也可直放的本地/外部音视频打开请求（仅消费外部媒体，不误清待登录重放的 DeepLink）
    LaunchedEffect(incomingExternalMedia) {
        if (incomingExternalMedia != null) {
            startPlayback(incomingExternalMedia)
            onConsumeExternalMedia()
        }
    }

    // 处理经 Rust 解析的 moviepilot:// 深度链接；未登录时保留业务 DeepLink，待登录完成后自动重放
    LaunchedEffect(incomingDeepLink, authKey) {
        if (!incomingDeepLink.isNullOrBlank()) {
            val parsedJson = RustCoreBridge.parseDeepLink(incomingDeepLink)
            val obj = parsedJson?.takeIf { it.isNotBlank() }?.let {
                runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull()
            }
            val kind = obj?.get("kind")?.jsonPrimitive?.content

            if (kind == "playDirect") {
                activeMedalShowcase = null
                val url = obj["direct_url"]?.jsonPrimitive?.content.orEmpty()
                if (url.isNotBlank()) {
                    startPlayback(
                        MediaPlaybackRequest(
                            url = url,
                            title = obj["title"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "外部直链播放",
                            isAudio = obj["media_kind"]?.jsonPrimitive?.content == "audio",
                        ),
                    )
                }
                onConsumeDeepLink()
                return@LaunchedEffect
            }

            // 其余业务路由需等待会话进入 Authenticated 后再导航并消费，确保 NeedsLogin -> Authenticated 无损重放
            val activeSession = session as? SessionState.Authenticated ?: return@LaunchedEffect
            if (!AndroidPushProvider.matchesServerOrigin(incomingDeepLinkOrigin, activeSession.serverUrl)) {
                snackbarHostState.showSnackbar("这条通知属于其他实例或账号，请切换服务后查看消息中心")
                onConsumeDeepLink()
                return@LaunchedEffect
            }

            isSwitchingServer = false
            activeMedalShowcase = null
            if (obj != null) {
                when (kind) {
                    "discover" -> pushRoute(AppRoute.TabRoot, MainTab.Discover)
                    "explore" -> {
                        val src = obj["source"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() } ?: "tmdb_movies"
                        pushRoute(AppRoute.Explore(src), MainTab.Discover)
                    }
                    "dashboard" -> pushRoute(AppRoute.TabRoot, MainTab.Dashboard)
                    "workspace", "more" -> pushRoute(AppRoute.TabRoot, MainTab.Workspace)
                    "messages" -> pushRoute(AppRoute.Messages, MainTab.Dashboard)
                    "authorization" -> {
                        clearTabStack(MainTab.Workspace)
                        pushRoute(AppRoute.SettingsHub, MainTab.Workspace)
                        pushRoute(AppRoute.ChannelAuthorization, MainTab.Workspace)
                    }
                    "settings" -> {
                        val sub = obj["sub"]?.jsonPrimitive?.content?.takeIf { it != "null" }
                        clearTabStack(MainTab.Workspace)
                        pushRoute(AppRoute.SettingsHub, MainTab.Workspace)
                        val target = when (sub) {
                            "users" -> AppRoute.Users
                            "subscribe" -> AppRoute.SubscribeSearchSettings
                            "sources", "system" -> AppRoute.MediaSourcesSettings
                            "downloaders" -> AppRoute.DownloadersSettings
                            "mediaservers" -> AppRoute.MediaServersSettings
                            "directories" -> AppRoute.DirectoriesSettings
                            "notifications" -> AppRoute.NotificationsSettings
                            "authorization", "channel-auth" -> AppRoute.ChannelAuthorization
                            "playback" -> AppRoute.PlaybackSettings
                            "appearance" -> AppRoute.Appearance
                            else -> null
                        }
                        if (target != null) pushRoute(target, MainTab.Workspace)
                    }
                    "users" -> pushRoute(AppRoute.Users, MainTab.Workspace)
                    "systemSettings" -> pushRoute(AppRoute.MediaSourcesSettings, MainTab.Workspace)
                    "playbackSettings" -> pushRoute(AppRoute.PlaybackSettings, MainTab.Workspace)
                    "diagnostics" -> {
                        val sec = obj["section"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()
                        val tabName = when (sec.lowercase()) {
                            "recognize", "rule", "rule_test" -> "名称识别"
                            "network", "nettest" -> "网络测试"
                            "logs", "log", "live_log" -> "实时日志"
                            "schedulers", "scheduler", "schedule" -> "定时服务"
                            "words", "word" -> "词表"
                            else -> "健康检查"
                        }
                        pushRoute(AppRoute.Diagnostics(tabName), MainTab.Workspace)
                    }
                    "search" -> pushRoute(
                        AppRoute.GlobalSearch(
                            query = obj["query"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty(),
                            kind = obj["search_kind"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "media",
                        ),
                    )
                    "subscriptions" -> {
                        val cat = obj["category"]?.jsonPrimitive?.content?.takeIf { it != "null" }
                        if (cat == null) {
                            pushRoute(AppRoute.TabRoot, MainTab.Subscribe)
                        } else {
                            pushRoute(AppRoute.Subscriptions(cat), MainTab.Subscribe)
                        }
                    }
                    "subscribeCommunity" -> pushRoute(AppRoute.SubscribeCommunity, MainTab.Subscribe)
                    "calendar" -> pushRoute(AppRoute.Calendar, MainTab.Subscribe)
                    "resources" -> pushRoute(AppRoute.Resources(obj["keyword"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()), MainTab.Workspace)
                    "downloads" -> pushRoute(AppRoute.Downloads, MainTab.Workspace)
                    "files" -> pushRoute(
                        AppRoute.Files(
                            storage = obj["storage"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "local",
                            path = obj["path"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "/",
                        ),
                        MainTab.Workspace,
                    )
                    "history" -> pushRoute(AppRoute.History(obj["search"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()), MainTab.Workspace)
                    "workflows" -> pushRoute(AppRoute.Workflows, MainTab.Workspace)
                    "sites" -> pushRoute(AppRoute.Sites, MainTab.Workspace)
                    "plugins" -> pushRoute(AppRoute.Plugins(obj["installed_only"]?.jsonPrimitive?.booleanOrNull ?: true), MainTab.Workspace)
                    "agent" -> pushRoute(AppRoute.Agent(obj["prompt"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()))
                    "music" -> pushRoute(AppRoute.Music, MainTab.Discover)
                    "shortcuts" -> pushRoute(AppRoute.Diagnostics("词表"), MainTab.Workspace)
                    "appearance" -> pushRoute(AppRoute.Appearance, MainTab.Workspace)
                    "mediaDetail" -> pushRoute(
                        AppRoute.MediaDetail(
                            MediaCardItem(
                                title = "媒体详情 #${obj["media_id"]?.jsonPrimitive?.content.orEmpty()}",
                                source = obj["source"]?.jsonPrimitive?.content ?: "themoviedb",
                                mediaId = obj["media_id"]?.jsonPrimitive?.content,
                                type = obj["media_type"]?.jsonPrimitive?.content ?: "电影",
                            ),
                        ),
                    )
                }
            }
            onConsumeDeepLink()
        }
    }

    val authSession = session as? SessionState.Authenticated
    val isTopLevelTab = currentRoute == AppRoute.TabRoot
    val showWideRail = isWideCanvas && authSession != null && !isSwitchingServer && activeMedalShowcase == null && activePlayerRequest == null
    val showBottomNav = authSession != null && !isSwitchingServer && isTopLevelTab && !isWideCanvas && activeMedalShowcase == null && activePlayerRequest == null
    val showMiniMusicBar = bgAudioRequest != null && !isSwitchingServer && activeMedalShowcase == null && activePlayerRequest == null

    val navBarBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val bottomOverlayInset = when {
        showBottomNav && showMiniMusicBar -> 154.dp + navBarBottom
        showBottomNav -> 88.dp + navBarBottom
        showMiniMusicBar -> 78.dp + navBarBottom
        else -> 12.dp + navBarBottom
    }

    CompositionLocalProvider(
        LocalSnackbarHostState provides snackbarHostState,
        LocalBottomOverlayInset provides bottomOverlayInset,
        LocalHazeState provides shellHazeState,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Row(modifier = Modifier.fillMaxSize()) {
                // 1. 宽屏（>= 600dp）常驻左侧 NavigationRail（跨一级 Tab 与全部深层子路由可见，自带左侧刘海与上下系统栏避让）
                if (showWideRail && authSession != null) {
                    FloatingNavigationRail(
                        selectedTab = selectedTab,
                        onTabClick = ::onTabBarClick,
                        onSearchClick = { pushRoute(AppRoute.GlobalSearch()) },
                        userAvatarUrl = repository.resolveImageUrl(authSession.identity.avatar),
                        userInitial = authSession.identity.name.ifBlank { "M" },
                    )
                }

                // 2. 主内容与底部浮层区域（自动避让右侧或双侧系统导航栏与摄像头挖孔）
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight()
                        .windowInsetsPadding(
                            WindowInsets.systemBars
                                .union(WindowInsets.displayCutout)
                                .only(if (showWideRail) WindowInsetsSides.End else WindowInsetsSides.Horizontal),
                        ),
                ) {
                    // 主背景流光 + 业务页面内容层（挂载 shellHazeState 为底部 4+1 磨砂玻璃胶囊提供实时背板模糊采样）
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .hazeSource(shellHazeState),
                    ) {
                        CinematicAmbientGradient()

                        CompositionLocalProvider(LocalHazeState provides null) {
                            val currentConnectedUrl = when (val cur = session) {
                                is SessionState.Authenticated -> cur.serverUrl
                                is SessionState.NeedsLogin -> cur.serverUrl
                                SessionState.Unconnected -> null
                            }
                            if (session is SessionState.Unconnected || isSwitchingServer) {
                                ServerConnectionScreen(
                                    savedServers = savedServers,
                                    currentServerUrl = currentConnectedUrl,
                                    onBack = if (isSwitchingServer) ({ isSwitchingServer = false }) else null,
                                    onConnect = { rawUrl ->
                                        val normalizedRes = RustCoreBridge.normalizeAddress(rawUrl)
                                        normalizedRes.fold(
                                            onSuccess = { normalized ->
                                                if (isSwitchingServer && !currentConnectedUrl.isNullOrBlank() &&
                                                    normalized.trimEnd('/').equals(currentConnectedUrl.trimEnd('/'), ignoreCase = true)
                                                ) {
                                                    isSwitchingServer = false
                                                    Result.success(normalized)
                                                } else {
                                                    val connectRes = repository.connectServer(rawUrl)
                                                    if (connectRes.isSuccess) {
                                                        releaseBackgroundAudio()
                                                        clearAllNavigationAndWebSession()
                                                        isSwitchingServer = false
                                                    }
                                                    connectRes
                                                }
                                            },
                                            onFailure = { Result.failure(it) },
                                        )
                                    },
                                    onSelectSaved = { entry ->
                                        if (isSwitchingServer && !currentConnectedUrl.isNullOrBlank() &&
                                            entry.url.trimEnd('/').equals(currentConnectedUrl.trimEnd('/'), ignoreCase = true)
                                        ) {
                                            isSwitchingServer = false
                                        } else {
                                            releaseBackgroundAudio()
                                            clearAllNavigationAndWebSession()
                                            repository.selectSavedServer(entry)
                                            isSwitchingServer = false
                                        }
                                    },
                                    onDeleteSaved = { url ->
                                        repository.forgetServer(url)
                                        if (repository.session.value is SessionState.Unconnected) {
                                            isSwitchingServer = false
                                        }
                                    },
                                    allowSelfSignedTls = allowSelfSignedTls,
                                    onToggleSelfSignedTls = { enabled ->
                                        allowSelfSignedTls = enabled
                                        repository.secretStore.allowSelfSignedTls = enabled
                                    },
                                )
                            } else when (val s = session) {
                                SessionState.Unconnected -> Unit

                                is SessionState.NeedsLogin -> {
                                    LoginScreen(
                                        serverUrl = s.serverUrl,
                                        initialNotice = s.notice,
                                        repository = repository,
                                        onSwitchServer = { isSwitchingServer = true },
                                        onLoginSuccess = {},
                                    )
                                }

                                is SessionState.Authenticated -> {
                                    AnimatedContent(
                                        targetState = Triple(selectedTab, currentRoute, currentStateKey),
                                        transitionSpec = {
                                            val sameTab = targetState.first == initialState.first
                                            val enteringSub = sameTab && targetState.second != AppRoute.TabRoot && initialState.second == AppRoute.TabRoot
                                            val returningRoot = sameTab && targetState.second == AppRoute.TabRoot && initialState.second != AppRoute.TabRoot
                                            when {
                                                enteringSub -> (slideInHorizontally(tween(220)) { it / 5 } + fadeIn(tween(220)))
                                                    .togetherWith(fadeOut(tween(150)))
                                                returningRoot -> fadeIn(tween(200))
                                                    .togetherWith(slideOutHorizontally(tween(200)) { it / 5 } + fadeOut(tween(180)))
                                                else -> fadeIn(tween(160)).togetherWith(fadeOut(tween(120)))
                                            }
                                        },
                                        label = "mpMainRouter",
                                    ) { (tabAtFrame, route, stateKey) ->
                                        saveableStateHolder.SaveableStateProvider(stateKey) {
                                            when (route) {
                                                AppRoute.TabRoot -> when (tabAtFrame) {
                                                    MainTab.Discover -> DiscoverScreen(
                                                        repository = repository,
                                                        onOpenMedia = ::openMediaSmart,
                                                        onOpenExplore = { src -> pushRoute(AppRoute.Explore(src)) },
                                                        onOpenMusic = { pushRoute(AppRoute.Music) },
                                                        onOpenMediaLibrary = { lib -> pushRoute(AppRoute.MediaServerLibrary(lib)) },
                                                        onPlayMedia = ::startPlayback,
                                                    )
                                                    MainTab.Subscribe -> SubscriptionsScreen(
                                                        repository = repository,
                                                        initialCategory = null,
                                                        onBack = null,
                                                        onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                                        onOpenCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                                        onOpenMedia = ::openMediaSmart,
                                                        onPlayMedia = ::startPlayback,
                                                        onOpenServerItem = { itemId, server, title ->
                                                            pushRoute(AppRoute.MediaServerDetail(itemId, server, title))
                                                        },
                                                    )
                                                    MainTab.Dashboard -> DashboardScreen(
                                                        repository = repository,
                                                        onOpenMessages = { pushRoute(AppRoute.Messages) },
                                                        onOpenDiagnosticTab = { tab -> pushRoute(AppRoute.Diagnostics(tab)) },
                                                        onOpenMedalShowcase = { profile, key -> activeMedalShowcase = profile to key },
                                                        permissions = s.permissions,
                                                    )
                                                    MainTab.Workspace -> WorkspaceHubScreen(
                                                        repository = repository,
                                                        onOpenSettings = { pushRoute(AppRoute.SettingsHub) },
                                                        onOpenAgent = { pushRoute(AppRoute.Agent()) },
                                                        onOpenMusic = { pushRoute(AppRoute.Music) },
                                                        onOpenResources = { pushRoute(AppRoute.Resources()) },
                                                        onOpenDownloads = { pushRoute(AppRoute.Downloads) },
                                                        onOpenFiles = { pushRoute(AppRoute.Files()) },
                                                        onOpenHistory = { pushRoute(AppRoute.History()) },
                                                        onOpenWorkflows = { pushRoute(AppRoute.Workflows) },
                                                        onOpenPlugins = { pushRoute(AppRoute.Plugins(installedOnly = true)) },
                                                        onOpenSites = { pushRoute(AppRoute.Sites) },
                                                        onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                                        onOpenSubscribeCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                                        onOpenMediaLibrary = { lib -> pushRoute(AppRoute.MediaServerLibrary(lib)) },
                                                        onOpenDiagnosticTab = { tab -> pushRoute(AppRoute.Diagnostics(tab)) },
                                                        permissions = s.permissions,
                                                    )
                                                }

                                                is AppRoute.Explore -> ExploreScreen(
                                                    repository = repository,
                                                    initialSource = route.source,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = ::openMediaSmart,
                                                    onPlayAudio = ::startPlayback,
                                                )

                                                AppRoute.SettingsHub -> SettingsHubScreen(
                                                    repository = repository,
                                                    serverUrl = s.serverUrl,
                                                    userName = s.identity.name,
                                                    onBack = ::popRoute,
                                                    onOpenSites = { pushRoute(AppRoute.Sites) },
                                                    onOpenUsers = { pushRoute(AppRoute.Users) },
                                                    onOpenSubscribeSearch = { pushRoute(AppRoute.SubscribeSearchSettings) },
                                                    onOpenMediaSources = { pushRoute(AppRoute.MediaSourcesSettings) },
                                                    onOpenDownloaders = { pushRoute(AppRoute.DownloadersSettings) },
                                                    onOpenMediaServers = { pushRoute(AppRoute.MediaServersSettings) },
                                                    onOpenDirectories = { pushRoute(AppRoute.DirectoriesSettings) },
                                                    onOpenPlayback = { pushRoute(AppRoute.PlaybackSettings) },
                                                    onOpenNotifications = { pushRoute(AppRoute.NotificationsSettings) },
                                                    onOpenAppearance = { pushRoute(AppRoute.Appearance) },
                                                    onOpenPlugins = { pushRoute(AppRoute.Plugins(installedOnly = true)) },
                                                    onOpenChannelAuth = { pushRoute(AppRoute.ChannelAuthorization) },
                                                    permissions = s.permissions,
                                                    onSwitchServer = { isSwitchingServer = true },
                                                    onLogout = {
                                                        releaseBackgroundAudio()
                                                        clearAllNavigationAndWebSession()
                                                        repository.logout()
                                                    },
                                                )
                                                is AppRoute.GlobalSearch -> GlobalSearchScreen(
                                                    repository = repository,
                                                    initialQuery = route.query,
                                                    initialKind = route.kind,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = ::openMediaSmart,
                                                    onOpenPerson = { pushRoute(AppRoute.PersonDetail(it)) },
                                                    onPlayLibraryItem = ::startPlayback,
                                                )
                                                is AppRoute.MediaDetail -> MediaDetailScreen(
                                                    item = route.item,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onSearchResource = { kw -> pushRoute(AppRoute.Resources(kw)) },
                                                    onPlayMedia = ::startPlayback,
                                                    onOpenPerson = { p -> pushRoute(AppRoute.PersonDetail(p)) },
                                                    onOpenMedia = ::openMediaSmart,
                                                    onOpenServerDetail = { itemId, server, title ->
                                                        pushRoute(AppRoute.MediaServerDetail(itemId, server, title))
                                                    },
                                                )
                                                is AppRoute.MediaServerDetail -> MediaServerDetailScreen(
                                                    itemId = route.itemId,
                                                    server = route.server,
                                                    fallbackTitle = route.fallbackTitle,
                                                    fallbackPoster = route.fallbackPoster,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onPlayMedia = ::startPlayback,
                                                    onSearchResource = { kw -> pushRoute(AppRoute.Resources(kw)) },
                                                    onOpenMedia = ::openMediaSmart,
                                                    onOpenServerDetail = { itemId, server, title, poster ->
                                                        pushRoute(AppRoute.MediaServerDetail(itemId, server, title, poster))
                                                    },
                                                    onOpenPerson = { p -> pushRoute(AppRoute.PersonDetail(p)) },
                                                )
                                                is AppRoute.PersonDetail -> PersonDetailScreen(
                                                    seed = route.person,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = ::openMediaSmart,
                                                )
                                                is AppRoute.MediaServerLibrary -> MediaServerLibraryScreen(
                                                    repository = repository,
                                                    initialLibrary = route.library,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = ::openMediaSmart,
                                                    onPlayMedia = ::startPlayback,
                                                    onOpenServerDetail = { itemId, server, title, poster ->
                                                        pushRoute(AppRoute.MediaServerDetail(itemId, server, title, poster))
                                                    },
                                                )
                                                AppRoute.Messages -> MessagesCenterScreen(
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                )
                                                AppRoute.Music -> MusicDiscoveryScreen(
                                                    onBack = ::popRoute,
                                                    onPlayAudio = ::startPlayback,
                                                    repository = repository,
                                                )
                                                is AppRoute.Subscriptions -> SubscriptionsScreen(
                                                    repository = repository,
                                                    initialCategory = route.category,
                                                    onBack = ::popRoute,
                                                    onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                                    onOpenCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                                    onOpenMedia = ::openMediaSmart,
                                                    onPlayMedia = ::startPlayback,
                                                    onOpenServerItem = { itemId, server, title ->
                                                        pushRoute(AppRoute.MediaServerDetail(itemId, server, title))
                                                    },
                                                )
                                                AppRoute.Calendar -> CalendarScreen(
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                                )
                                                AppRoute.SubscribeCommunity -> SubscribeCommunityScreen(
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                                )
                                                is AppRoute.Resources -> ResourceSearchScreen(repository, route.keyword, onBack = ::popRoute)
                                                AppRoute.Downloads -> DownloadsScreen(repository, onBack = ::popRoute)
                                                is AppRoute.Files -> FileManagerScreen(repository, route.storage, route.path, onBack = ::popRoute, onPlayMedia = ::startPlayback)
                                                is AppRoute.History -> TransferHistoryScreen(repository, route.search, onBack = ::popRoute)
                                                AppRoute.Workflows -> WorkflowsScreen(
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onOpenCanvas = { pushRoute(AppRoute.WorkflowCanvas(it)) },
                                                )
                                                is AppRoute.WorkflowCanvas -> WorkflowCanvasScreen(
                                                    workflow = route.workflow,
                                                    onBack = ::popRoute,
                                                    repository = repository,
                                                )
                                                AppRoute.Sites -> SitesScreen(repository, onBack = ::popRoute)
                                                AppRoute.Users -> UsersManagementScreen(repository, s.identity.name, onBack = ::popRoute)
                                                AppRoute.SubscribeSearchSettings -> SubscribeSearchSettingsScreen(repository, onBack = ::popRoute)
                                                AppRoute.MediaSourcesSettings -> MediaSourcesSettingsScreen(repository, onBack = ::popRoute)
                                                AppRoute.DownloadersSettings -> DownloadersSettingsScreen(repository, onBack = ::popRoute)
                                                AppRoute.MediaServersSettings -> MediaServersSettingsScreen(repository, onBack = ::popRoute)
                                                AppRoute.DirectoriesSettings -> DirectoriesStorageSettingsScreen(repository, onBack = ::popRoute)
                                                AppRoute.NotificationsSettings -> NotificationsSettingsScreen(repository, onBack = ::popRoute)
                                                AppRoute.ChannelAuthorization -> ChannelAuthorizationScreen(
                                                    repository = repository,
                                                    isAdmin = s.permissions.admin,
                                                    onBack = ::popRoute,
                                                )
                                                AppRoute.PlaybackSettings -> PlaybackPreferencesScreen(onBack = ::popRoute)
                                                is AppRoute.Plugins -> PluginsCenterScreen(
                                                    repository = repository,
                                                    initialInstalledOnly = route.installedOnly,
                                                    onBack = ::popRoute,
                                                    onOpenPluginDetail = { p -> pushRoute(AppRoute.PluginDetail(p)) },
                                                )
                                                is AppRoute.PluginDetail -> PluginDetailScreen(
                                                    plugin = route.plugin,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                )
                                                is AppRoute.Diagnostics -> ShortcutsDiagnosticsScreen(
                                                    repository = repository,
                                                    initialTab = route.tab,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                                )
                                                is AppRoute.Agent -> AgentChatScreen(repository, route.prompt, onBack = ::popRoute)
                                                AppRoute.Appearance -> AppearanceSettingsScreen(onBack = ::popRoute)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3. 一级主 Tab 右下角 AI 助手入口（受外观开关控制，自动避让底部 4+1 导航栏与悬浮迷你播控条）
                    if (authSession != null && !isSwitchingServer && isTopLevelTab && appearanceStore.showAgentMascot && activeMedalShowcase == null && activePlayerRequest == null) {
                        val mascotBottom = when {
                            isWideCanvas && showMiniMusicBar -> 92.dp
                            isWideCanvas -> 24.dp
                            showMiniMusicBar -> 158.dp
                            else -> 92.dp
                        }
                        FloatingAgentMascot(
                            onClick = { pushRoute(AppRoute.Agent()) },
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .navigationBarsPadding()
                                .padding(end = 16.dp, bottom = mascotBottom),
                        )
                    }

                    // 4. 底部悬浮区域：迷你音乐播控条（含未登录本地音频，宽屏限宽 560dp）+ 手机态 4+1 分离式磨砂玻璃胶囊底栏
                    if (showMiniMusicBar || showBottomNav) {
                        Column(
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            if (showMiniMusicBar) {
                                bgAudioRequest?.let { req ->
                                    FloatingMiniMusicBar(
                                        request = req,
                                        isPlaying = bgAudioPlaying,
                                        onTogglePlay = {
                                            bgAudioPlayer?.let { p ->
                                                if (p.isPlaying) p.pause() else p.play()
                                            }
                                        },
                                        onNext = {
                                            if (req.queue.size > 1) {
                                                val nextIdx = (req.queueIndex + 1) % req.queue.size
                                                startPlayback(req.queue[nextIdx].copy(queue = req.queue, queueIndex = nextIdx))
                                                activePlayerRequest = null
                                            }
                                        },
                                        onExpand = { activePlayerRequest = req },
                                        onClose = { releaseBackgroundAudio() },
                                        modifier = Modifier
                                            .widthIn(max = 560.dp)
                                            .then(
                                                if (!showBottomNav) Modifier.navigationBarsPadding().padding(bottom = 10.dp) else Modifier,
                                            ),
                                    )
                                    if (showBottomNav) Spacer(Modifier.height(2.dp))
                                }
                            }

                            if (showBottomNav && authSession != null) {
                                MoviePilotBottomNavigationBar(
                                    selectedTab = selectedTab,
                                    onTabClick = ::onTabBarClick,
                                    onSearchClick = { pushRoute(AppRoute.GlobalSearch()) },
                                    userAvatarUrl = repository.resolveImageUrl(authSession.identity.avatar),
                                    userInitial = authSession.identity.name.ifBlank { "M" },
                                )
                            }
                        }
                    }

                    // 5. Android Material 3 全局非阻塞 Snackbar 宿主（宽屏限宽 560dp）
                    SnackbarHost(
                        hostState = snackbarHostState,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .widthIn(max = 560.dp)
                            .padding(
                                start = 16.dp,
                                end = 16.dp,
                                bottom = bottomOverlayInset + 8.dp,
                            ),
                    ) { data ->
                        Snackbar(
                            snackbarData = data,
                            shape = RoundedCornerShape(18.dp),
                            containerColor = colors.surfaceContainerHigh,
                            contentColor = colors.textPrimary,
                            actionColor = colors.accent,
                        )
                    }
                }
            }

            // 6. 全屏 OpenGL ES 3D 社区勋章互动舞台
            activeMedalShowcase?.let { (profile, initialKey) ->
                NativeCommunityMedalShowcaseOverlay(
                    profile = profile,
                    initialKey = initialKey,
                    onDismiss = { activeMedalShowcase = null },
                    onRefreshProfile = {
                        repository.fetchCommunityProfileJson(refresh = true)?.let { raw ->
                            runCatching { medalJson.decodeFromString<CommunityProfile>(raw) }.getOrNull()
                        }
                    },
                )
            }

            // 7. 全屏原生音视频播放器覆盖层（音频直连后台共享 ExoPlayer；自动同步媒体服务器播放进度）
            activePlayerRequest?.let { req ->
                NativeMediaPlayerOverlay(
                    request = req,
                    sharedPlayer = if (req.isAudio && bgAudioRequest?.url == req.url) bgAudioPlayer else null,
                    onClose = {
                        if (req.isAudio) releaseBackgroundAudio()
                        activePlayerRequest = null
                    },
                    onMinimizeToMiniBar = if (req.isAudio) {
                        {
                            bgAudioRequest = req
                            activePlayerRequest = null
                        }
                    } else {
                        null
                    },
                    onSwitchRequest = { next -> startPlayback(next) },
                    onReportProgress = if (req.itemId.isNotBlank() && req.server.isNotBlank()) {
                        { posMs, durMs, isPaused, state ->
                            scope.launch {
                                repository.reportMediaPlaybackProgress(
                                    itemId = req.itemId,
                                    server = req.server,
                                    positionMs = posMs,
                                    durationMs = durMs,
                                    isPaused = isPaused,
                                    state = state,
                                )
                            }
                        }
                    } else {
                        null
                    },
                )
            }
        }
    }
}
