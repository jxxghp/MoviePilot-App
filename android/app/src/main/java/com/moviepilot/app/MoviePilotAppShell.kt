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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
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
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicAmbientGradient
import com.moviepilot.designsystem.FloatingAgentMascot
import com.moviepilot.designsystem.FloatingNavigationRail
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
import com.moviepilot.feature.media.PersonDetailScreen
import com.moviepilot.feature.settings.AppearanceSettingsScreen
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
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaPersonDto
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import com.moviepilot.rustbridge.WorkflowItemDto
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** 主壳路由目的栈条目（覆盖全部业务页面、媒体库、独立人物页、独立消息页、插件宿主与全部设置模块）。 */
sealed interface AppRoute {
    data object TabRoot : AppRoute
    data object SettingsHub : AppRoute
    data class GlobalSearch(val query: String = "", val kind: String = "media") : AppRoute
    data class MediaDetail(val item: MediaCardItem) : AppRoute
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
    data object PlaybackSettings : AppRoute
    data class Plugins(val installedOnly: Boolean = true) : AppRoute
    data class PluginDetail(val plugin: PluginItemDto) : AppRoute
    data class Diagnostics(val tab: String = "词表") : AppRoute
    data class Agent(val prompt: String = "") : AppRoute
    data object Appearance : AppRoute
}

/**
 * MoviePilot Android Material Design 3 根容器（方案 A）：
 * 1. 手机端采用 Material 3 标准全宽贴底 5 Tab `NavigationBar`（发现 / 探索 / 订阅 / 工具 / 我的），
 *    宽屏/折叠屏/平板自动切换左侧 Material 3 `NavigationRail`；全局搜索上移顶栏，设置位于「我的」右上角；
 * 2. 遵循 Android 双轨返回模型（系统边缘 Back 按时间历史栈回退，左上角 Up 沿信息层级向上返回），完整接管 `BackHandler`；
 * 3. 进入任意深层子页自动收起底栏与 AI 悬浮球，释放完整沉浸垂直视野与右下角单手 FAB 热区；
 * 4. 全局注入 `LocalSnackbarHostState` 承载非阻塞式操作反馈与「撤销」动作；
 * 5. 后台音乐由根容器持有的持久 `ExoPlayer` 驱动，最小化至悬浮迷你条仍无缝连续播放、暂停与切歌。
 */
@Composable
fun MoviePilotRootShell(
    repository: MoviePilotRepository,
    incomingDeepLink: String?,
    incomingExternalMedia: MediaPlaybackRequest?,
    onConsumeIncoming: () -> Unit,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val session by repository.session.collectAsState()
    val savedServers by repository.savedServers.collectAsState()
    val hazeState = remember { HazeState() }
    val snackbarHostState = remember { SnackbarHostState() }
    val medalJson = remember { Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true } }

    var selectedTabId by rememberSaveable { mutableStateOf(MainTab.Discover.id) }
    val selectedTab = MainTab.entries.firstOrNull { it.id == selectedTabId } ?: MainTab.Discover
    fun selectTab(tab: MainTab) { selectedTabId = tab.id }

    var exploreSource by rememberSaveable { mutableStateOf("tmdb_movies") }
    val routeBackStack = remember { mutableStateListOf<AppRoute>() }
    val isWideCanvas = AdaptiveDeviceLayout.isWideCanvas()

    var activePlayerRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var bgAudioRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var bgAudioPlayer by remember { mutableStateOf<ExoPlayer?>(null) }
    var bgAudioPlaying by remember { mutableStateOf(false) }
    var activeMedalShowcase by remember { mutableStateOf<Pair<CommunityProfile, String>?>(null) }

    val currentRoute: AppRoute = routeBackStack.lastOrNull() ?: AppRoute.TabRoot

    fun pushRoute(route: AppRoute) {
        if (route == AppRoute.TabRoot) {
            routeBackStack.clear()
        } else {
            routeBackStack.add(route)
        }
    }

    fun popRoute() {
        if (routeBackStack.isNotEmpty()) {
            routeBackStack.removeAt(routeBackStack.lastIndex)
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

    // Android 系统 Back 返回键 / 边缘侧滑统一接管（时间栈优先）
    val canHandleBack = activePlayerRequest != null ||
        activeMedalShowcase != null ||
        routeBackStack.isNotEmpty() ||
        selectedTab != MainTab.Discover

    BackHandler(enabled = canHandleBack) {
        when {
            activePlayerRequest != null -> activePlayerRequest = null
            activeMedalShowcase != null -> activeMedalShowcase = null
            routeBackStack.isNotEmpty() -> popRoute()
            selectedTab != MainTab.Discover -> selectTab(MainTab.Discover)
        }
    }

    // 鉴权就绪后拉取权威用户信息（真实头像）并预热图片代理 Cookie
    val authKey = (session as? SessionState.Authenticated)?.let { "${it.serverUrl}|${it.token.takeLast(8)}" }
    LaunchedEffect(authKey) {
        if (authKey != null) {
            repository.hydrateAuthenticatedSession()
        }
    }

    // 处理未登录也可直放的本地/外部音视频打开请求
    LaunchedEffect(incomingExternalMedia) {
        if (incomingExternalMedia != null) {
            startPlayback(incomingExternalMedia)
            onConsumeIncoming()
        }
    }

    // 处理经 Rust 解析的 moviepilot:// 全量深度链接
    LaunchedEffect(incomingDeepLink) {
        if (!incomingDeepLink.isNullOrBlank()) {
            activeMedalShowcase = null
            val parsedJson = RustCoreBridge.parseDeepLink(incomingDeepLink)
            if (!parsedJson.isNullOrBlank()) {
                val obj = runCatching { Json.parseToJsonElement(parsedJson).jsonObject }.getOrNull()
                val kind = obj?.get("kind")?.jsonPrimitive?.content
                when (kind) {
                    "discover" -> { selectTab(MainTab.Discover); routeBackStack.clear() }
                    "explore" -> {
                        selectTab(MainTab.Explore)
                        obj["source"]?.jsonPrimitive?.content?.takeIf { it != "null" }?.let { exploreSource = it }
                        routeBackStack.clear()
                    }
                    "dashboard" -> { selectTab(MainTab.Dashboard); routeBackStack.clear() }
                    "settings" -> {
                        val sub = obj["sub"]?.jsonPrimitive?.content?.takeIf { it != "null" }
                        selectTab(MainTab.Dashboard)
                        routeBackStack.clear()
                        pushRoute(AppRoute.SettingsHub)
                        val target = when (sub) {
                            "users" -> AppRoute.Users
                            "subscribe" -> AppRoute.SubscribeSearchSettings
                            "sources", "system" -> AppRoute.MediaSourcesSettings
                            "downloaders" -> AppRoute.DownloadersSettings
                            "mediaservers" -> AppRoute.MediaServersSettings
                            "directories" -> AppRoute.DirectoriesSettings
                            "notifications" -> AppRoute.NotificationsSettings
                            "playback" -> AppRoute.PlaybackSettings
                            else -> null
                        }
                        if (target != null) pushRoute(target)
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
                            selectTab(MainTab.Subscribe)
                            routeBackStack.clear()
                        } else {
                            pushRoute(AppRoute.Subscriptions(cat))
                        }
                    }
                    "subscribeCommunity" -> pushRoute(AppRoute.SubscribeCommunity)
                    "calendar" -> pushRoute(AppRoute.Calendar)
                    "resources" -> pushRoute(AppRoute.Resources(obj["keyword"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()))
                    "downloads" -> pushRoute(AppRoute.Downloads)
                    "files" -> pushRoute(
                        AppRoute.Files(
                            storage = obj["storage"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "local",
                            path = obj["path"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "/",
                        ),
                    )
                    "history" -> pushRoute(AppRoute.History(obj["search"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()))
                    "workflows" -> pushRoute(AppRoute.Workflows)
                    "sites" -> pushRoute(AppRoute.Sites)
                    "plugins" -> pushRoute(AppRoute.Plugins(obj["installed_only"]?.jsonPrimitive?.booleanOrNull ?: true))
                    "agent" -> pushRoute(AppRoute.Agent(obj["prompt"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty()))
                    "music" -> pushRoute(AppRoute.Music)
                    "shortcuts" -> pushRoute(AppRoute.Diagnostics("词表"))
                    "appearance" -> pushRoute(AppRoute.Appearance)
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
                    "playDirect" -> {
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
                    }
                }
            }
            onConsumeIncoming()
        }
    }

    CompositionLocalProvider(
        LocalHazeState provides hazeState,
        LocalSnackbarHostState provides snackbarHostState,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            // 1. 底层实时磨砂源：包含 AGSL 动态流光背景与全部滚动业务页面
            // 重要：在 hazeSource 子树内将 LocalHazeState 置空，杜绝任意业务页面内嵌的玻璃按钮/面板
            // 反向消费父级 hazeState 触发 Haze 递归绘制异常；页面内顶部渐进模糊均显式传入同级 localHaze。
            val railStartPadding = if (isWideCanvas && currentRoute == AppRoute.TabRoot && session is SessionState.Authenticated) 80.dp else 0.dp
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .hazeSource(state = hazeState),
            ) {
                CompositionLocalProvider(LocalHazeState provides null) {
                CinematicAmbientGradient()

                Box(modifier = Modifier.fillMaxSize().padding(start = railStartPadding)) {
                    when (val s = session) {
                        is SessionState.Unconnected -> {
                            ServerConnectionScreen(
                                savedServers = savedServers,
                                onConnect = { repository.connectServer(it) },
                                onSelectSaved = { repository.selectSavedServer(it) },
                                onDeleteSaved = { repository.forgetServer(it) },
                            )
                        }

                        is SessionState.NeedsLogin -> {
                            LoginScreen(
                                serverUrl = s.serverUrl,
                                initialNotice = s.notice,
                                repository = repository,
                                onSwitchServer = { repository.openServerConnection() },
                                onLoginSuccess = { routeBackStack.clear() },
                            )
                        }

                        is SessionState.Authenticated -> {
                            val stackKey = if (currentRoute == AppRoute.TabRoot) {
                                "tab_${selectedTab.id}"
                            } else {
                                "stack_${routeBackStack.size}_${currentRoute.hashCode()}"
                            }

                            AnimatedContent(
                                targetState = currentRoute to stackKey,
                                transitionSpec = {
                                    val enteringSub = targetState.first != AppRoute.TabRoot && initialState.first == AppRoute.TabRoot
                                    val returningRoot = targetState.first == AppRoute.TabRoot && initialState.first != AppRoute.TabRoot
                                    when {
                                        enteringSub -> (slideInHorizontally(tween(220)) { it / 5 } + fadeIn(tween(220)))
                                            .togetherWith(fadeOut(tween(150)))
                                        returningRoot -> fadeIn(tween(200))
                                            .togetherWith(slideOutHorizontally(tween(200)) { it / 5 } + fadeOut(tween(180)))
                                        else -> fadeIn(tween(180)).togetherWith(fadeOut(tween(140)))
                                    }
                                },
                                label = "mpMainRouter",
                            ) { (route, _) ->
                                when (route) {
                                    AppRoute.TabRoot -> when (selectedTab) {
                                        MainTab.Discover -> DiscoverScreen(
                                            repository = repository,
                                            onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                            onOpenExplore = { src -> exploreSource = src; selectTab(MainTab.Explore) },
                                            onOpenMusic = { pushRoute(AppRoute.Music) },
                                            onOpenMediaLibrary = { lib -> pushRoute(AppRoute.MediaServerLibrary(lib)) },
                                            onOpenSearch = { pushRoute(AppRoute.GlobalSearch()) },
                                            onPlayMedia = ::startPlayback,
                                        )
                                        MainTab.Explore -> ExploreScreen(
                                            repository = repository,
                                            initialSource = exploreSource,
                                            onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                            onOpenSearch = { pushRoute(AppRoute.GlobalSearch()) },
                                            onPlayAudio = ::startPlayback,
                                        )
                                        MainTab.Subscribe -> SubscriptionsScreen(
                                            repository = repository,
                                            initialCategory = null,
                                            onBack = null,
                                            onOpenSearch = { pushRoute(AppRoute.GlobalSearch()) },
                                            onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                            onOpenCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                        )
                                        MainTab.Workspace -> WorkspaceHubScreen(
                                            repository = repository,
                                            onOpenSearch = { pushRoute(AppRoute.GlobalSearch()) },
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
                                        )
                                        MainTab.Dashboard -> DashboardScreen(
                                            repository = repository,
                                            onOpenMessages = { pushRoute(AppRoute.Messages) },
                                            onOpenDiagnosticTab = { tab -> pushRoute(AppRoute.Diagnostics(tab)) },
                                            onOpenMedalShowcase = { profile, key -> activeMedalShowcase = profile to key },
                                            onOpenSettings = { pushRoute(AppRoute.SettingsHub) },
                                        )
                                    }

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
                                        onLogout = {
                                            releaseBackgroundAudio()
                                            routeBackStack.clear()
                                            repository.logout()
                                        },
                                    )
                                    is AppRoute.GlobalSearch -> GlobalSearchScreen(
                                        repository = repository,
                                        initialQuery = route.query,
                                        initialKind = route.kind,
                                        onBack = ::popRoute,
                                        onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
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
                                        onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                    )
                                    is AppRoute.PersonDetail -> PersonDetailScreen(
                                        seed = route.person,
                                        repository = repository,
                                        onBack = ::popRoute,
                                        onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                    )
                                    is AppRoute.MediaServerLibrary -> MediaServerLibraryScreen(
                                        repository = repository,
                                        initialLibrary = route.library,
                                        onBack = ::popRoute,
                                        onOpenMedia = { pushRoute(AppRoute.MediaDetail(it)) },
                                        onPlayMedia = ::startPlayback,
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
                                        onOpenSearch = { pushRoute(AppRoute.GlobalSearch()) },
                                        onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                        onOpenCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                    )
                                    AppRoute.Calendar -> CalendarScreen(
                                        repository = repository,
                                        onBack = ::popRoute,
                                    )
                                    AppRoute.SubscribeCommunity -> SubscribeCommunityScreen(
                                        repository = repository,
                                        onBack = ::popRoute,
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
                                    )
                                    AppRoute.Sites -> SitesScreen(repository, onBack = ::popRoute)
                                    AppRoute.Users -> UsersManagementScreen(repository, s.identity.name, onBack = ::popRoute)
                                    AppRoute.SubscribeSearchSettings -> SubscribeSearchSettingsScreen(repository, onBack = ::popRoute)
                                    AppRoute.MediaSourcesSettings -> MediaSourcesSettingsScreen(repository, onBack = ::popRoute)
                                    AppRoute.DownloadersSettings -> DownloadersSettingsScreen(repository, onBack = ::popRoute)
                                    AppRoute.MediaServersSettings -> MediaServersSettingsScreen(repository, onBack = ::popRoute)
                                    AppRoute.DirectoriesSettings -> DirectoriesStorageSettingsScreen(repository, onBack = ::popRoute)
                                    AppRoute.NotificationsSettings -> NotificationsSettingsScreen(repository, onBack = ::popRoute)
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
                                    is AppRoute.Diagnostics -> ShortcutsDiagnosticsScreen(repository, route.tab, onBack = ::popRoute)
                                    is AppRoute.Agent -> AgentChatScreen(repository, route.prompt, onBack = ::popRoute)
                                    AppRoute.Appearance -> AppearanceSettingsScreen(onBack = ::popRoute)
                                }
                            }
                        }
                    }
                }
                }
            }

            // 2. Material 3 导航前景层（位于 hazeSource 之外）
            val authSession = session as? SessionState.Authenticated
            val isTopLevelTab = currentRoute == AppRoute.TabRoot

            if (authSession != null && activeMedalShowcase == null && activePlayerRequest == null) {
                // 宽屏 / 折叠屏展开 / 平板：左侧 Material 3 NavigationRail
                if (isTopLevelTab && isWideCanvas) {
                    FloatingNavigationRail(
                        selectedTab = selectedTab,
                        onTabClick = { selectTab(it) },
                        onSearchClick = { pushRoute(AppRoute.GlobalSearch()) },
                        userAvatarUrl = repository.resolveImageUrl(authSession.identity.avatar),
                        userInitial = authSession.identity.name.ifBlank { "M" },
                        modifier = Modifier.align(Alignment.CenterStart),
                    )
                }

                // 一级主 Tab 右下角 AI 助手入口（贴底导航栏上方，与底栏/搜索零热区冲突）
                if (isTopLevelTab) {
                    FloatingAgentMascot(
                        onClick = { pushRoute(AppRoute.Agent()) },
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .navigationBarsPadding()
                            .padding(end = 16.dp, bottom = if (isWideCanvas) 24.dp else 96.dp),
                    )
                }

                // 底部区域：迷你音乐条（跨页面常驻，直连持久 ExoPlayer）+ 手机态贴底 5 Tab NavigationBar
                Column(
                    modifier = Modifier.align(Alignment.BottomCenter),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
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
                            modifier = Modifier.then(if (!isTopLevelTab || isWideCanvas) Modifier.navigationBarsPadding().padding(bottom = 10.dp) else Modifier),
                        )
                        if (isTopLevelTab && !isWideCanvas) Spacer(Modifier.height(6.dp))
                    }

                    if (isTopLevelTab && !isWideCanvas) {
                        MoviePilotBottomNavigationBar(
                            selectedTab = selectedTab,
                            onTabClick = { selectTab(it) },
                            userAvatarUrl = repository.resolveImageUrl(authSession.identity.avatar),
                            userInitial = authSession.identity.name.ifBlank { "M" },
                        )
                    }
                }
            }

            // 3. Android Material 3 全局非阻塞 Snackbar 宿主（带“撤销”等动作按钮）
            SnackbarHost(
                hostState = snackbarHostState,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = if (isTopLevelTab && !isWideCanvas) 92.dp else 20.dp),
            ) { data ->
                Snackbar(
                    snackbarData = data,
                    shape = RoundedCornerShape(16.dp),
                    containerColor = if (colors.isDark) Color(0xEE2B243D) else Color(0xF5211C2E),
                    contentColor = Color.White,
                    actionColor = colors.accent,
                )
            }

            // 4. 全屏 OpenGL ES 3D 社区勋章互动舞台
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

            // 5. 全屏原生音视频播放器覆盖层（音频直连后台共享 ExoPlayer；自动同步媒体服务器播放进度）
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
