package com.moviepilot.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Search
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.moviepilot.designsystem.CinematicAmbientGradient
import com.moviepilot.designsystem.FloatingAgentMascot
import com.moviepilot.designsystem.FloatingFourPlusOneNavBar
import com.moviepilot.designsystem.FloatingOverflowMenuPopover
import com.moviepilot.designsystem.MainTab
import com.moviepilot.designsystem.OverflowMenuDestination
import com.moviepilot.feature.agent.AgentChatScreen
import com.moviepilot.feature.auth.LoginScreen
import com.moviepilot.feature.auth.ServerConnectionScreen
import com.moviepilot.feature.automation.SitesScreen
import com.moviepilot.feature.automation.WorkflowCanvasScreen
import com.moviepilot.feature.automation.WorkflowsScreen
import com.moviepilot.feature.dashboard.DashboardScreen
import com.moviepilot.feature.dashboard.ShortcutsDiagnosticsScreen
import com.moviepilot.feature.discover.DiscoverScreen
import com.moviepilot.feature.discover.ExploreScreen
import com.moviepilot.feature.discover.GlobalSearchScreen
import com.moviepilot.feature.discover.MusicDiscoveryScreen
import com.moviepilot.feature.download.DownloadsScreen
import com.moviepilot.feature.download.ResourceSearchScreen
import com.moviepilot.feature.library.FileManagerScreen
import com.moviepilot.feature.library.TransferHistoryScreen
import com.moviepilot.feature.media.MediaDetailScreen
import com.moviepilot.feature.settings.AppearanceSettingsScreen
import com.moviepilot.feature.settings.CommunityMedalsScreen
import com.moviepilot.feature.settings.PluginsCenterScreen
import com.moviepilot.feature.settings.SettingsHubScreen
import com.moviepilot.feature.settings.SystemModuleDetailScreen
import com.moviepilot.feature.subscribe.CalendarScreen
import com.moviepilot.feature.subscribe.SubscribeCommunityScreen
import com.moviepilot.feature.subscribe.SubscriptionsScreen
import com.moviepilot.media.FloatingMiniMusicBar
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.NativeMediaPlayerOverlay
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import com.moviepilot.rustbridge.WorkflowItemDto
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** 主壳路由目的栈条目（溢出菜单与子页均独立管理，不污染 4 主 Tab 状态）。 */
sealed interface AppRoute {
    data object TabRoot : AppRoute
    data class GlobalSearch(val query: String = "", val kind: String = "media") : AppRoute
    data class MediaDetail(val item: MediaCardItem) : AppRoute
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
    data class Plugins(val installedOnly: Boolean = true) : AppRoute
    data object Shortcuts : AppRoute
    data class Agent(val prompt: String = "") : AppRoute
    data object Appearance : AppRoute
    data object Medals : AppRoute
    data class SystemModule(val title: String) : AppRoute
}

/**
 * MoviePilot Android 根容器：
 * 1. 全局铺设原生 AGSL 流光背景（`CinematicAmbientGradient`）；
 * 2. 严格响应认证状态机（连接服务 -> 登录 -> 4+1 主壳）；
 * 3. 支持未登录状态下直接播放外部/本地音视频文件（`pendingExternalMedia`）；
 * 4. 所有 `moviepilot://` 深度链接统一委托 Rust `parseDeepLink` 精准跳转。
 */
@Composable
fun MoviePilotRootShell(
    repository: MoviePilotRepository,
    incomingDeepLink: String?,
    incomingExternalMedia: MediaPlaybackRequest?,
    onConsumeIncoming: () -> Unit,
) {
    val session by repository.session.collectAsState()
    val savedServers by repository.savedServers.collectAsState()

    var selectedTab by remember { mutableStateOf(MainTab.Discover) }
    var exploreSource by remember { mutableStateOf("tmdb_movies") }
    var activeOverlayRoute by remember { mutableStateOf<AppRoute>(AppRoute.TabRoot) }
    var showOverflowMenu by remember { mutableStateOf(false) }

    var activePlayerRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var miniMusicRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var miniMusicPlaying by remember { mutableStateOf(true) }

    // 处理未登录也可直放的本地/外部音视频打开请求
    LaunchedEffect(incomingExternalMedia) {
        if (incomingExternalMedia != null) {
            activePlayerRequest = incomingExternalMedia
            onConsumeIncoming()
        }
    }

    // 处理经 Rust 解析的 moviepilot:// 全量深度链接
    LaunchedEffect(incomingDeepLink) {
        if (!incomingDeepLink.isNullOrBlank()) {
            showOverflowMenu = false
            val parsedJson = RustCoreBridge.parseDeepLink(incomingDeepLink)
            if (!parsedJson.isNullOrBlank()) {
                val obj = runCatching { Json.parseToJsonElement(parsedJson).jsonObject }.getOrNull()
                val kind = obj?.get("kind")?.jsonPrimitive?.content
                when (kind) {
                    "discover" -> { selectedTab = MainTab.Discover; activeOverlayRoute = AppRoute.TabRoot }
                    "explore" -> {
                        selectedTab = MainTab.Explore
                        obj["source"]?.jsonPrimitive?.content?.takeIf { it != "null" }?.let { exploreSource = it }
                        activeOverlayRoute = AppRoute.TabRoot
                    }
                    "dashboard" -> { selectedTab = MainTab.Dashboard; activeOverlayRoute = AppRoute.TabRoot }
                    "settings" -> { selectedTab = MainTab.Settings; activeOverlayRoute = AppRoute.TabRoot }
                    "search" -> activeOverlayRoute = AppRoute.GlobalSearch(
                        query = obj["query"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty(),
                        kind = obj["search_kind"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "media",
                    )
                    "subscriptions" -> activeOverlayRoute = AppRoute.Subscriptions(obj["category"]?.jsonPrimitive?.content?.takeIf { it != "null" })
                    "subscribeCommunity" -> activeOverlayRoute = AppRoute.SubscribeCommunity
                    "calendar" -> activeOverlayRoute = AppRoute.Calendar
                    "resources" -> activeOverlayRoute = AppRoute.Resources(obj["keyword"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty())
                    "downloads" -> activeOverlayRoute = AppRoute.Downloads
                    "files" -> activeOverlayRoute = AppRoute.Files(
                        storage = obj["storage"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "local",
                        path = obj["path"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "/",
                    )
                    "history" -> activeOverlayRoute = AppRoute.History(obj["search"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty())
                    "workflows" -> activeOverlayRoute = AppRoute.Workflows
                    "sites" -> activeOverlayRoute = AppRoute.Sites
                    "plugins" -> activeOverlayRoute = AppRoute.Plugins(obj["installed_only"]?.jsonPrimitive?.booleanOrNull ?: true)
                    "agent" -> activeOverlayRoute = AppRoute.Agent(obj["prompt"]?.jsonPrimitive?.content?.takeIf { it != "null" }.orEmpty())
                    "music" -> activeOverlayRoute = AppRoute.Music
                    "shortcuts" -> activeOverlayRoute = AppRoute.Shortcuts
                    "appearance" -> activeOverlayRoute = AppRoute.Appearance
                    "mediaDetail" -> activeOverlayRoute = AppRoute.MediaDetail(
                        MediaCardItem(
                            title = "媒体详情 #${obj["media_id"]?.jsonPrimitive?.content.orEmpty()}",
                            source = obj["source"]?.jsonPrimitive?.content ?: "themoviedb",
                            mediaId = obj["media_id"]?.jsonPrimitive?.content,
                            type = obj["media_type"]?.jsonPrimitive?.content ?: "电影",
                        ),
                    )
                    "playDirect" -> {
                        val url = obj["direct_url"]?.jsonPrimitive?.content.orEmpty()
                        if (url.isNotBlank()) {
                            activePlayerRequest = MediaPlaybackRequest(
                                url = url,
                                title = obj["title"]?.jsonPrimitive?.content?.takeIf { it != "null" } ?: "外部直链播放",
                                isAudio = obj["media_kind"]?.jsonPrimitive?.content == "audio",
                            )
                        }
                    }
                }
            }
            onConsumeIncoming()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // 全局连续原生 AGSL 流光背景
        CinematicAmbientGradient()

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
                    onLoginSuccess = { activeOverlayRoute = AppRoute.TabRoot },
                )
            }

            is SessionState.Authenticated -> {
                val playHandler: (MediaPlaybackRequest) -> Unit = { req ->
                    activePlayerRequest = req
                    if (req.isAudio) {
                        miniMusicRequest = req
                        miniMusicPlaying = true
                    }
                }

                // 主内容区（当前 Tab 根页面或溢出/子路由）
                Box(modifier = Modifier.fillMaxSize()) {
                    when (val route = activeOverlayRoute) {
                        AppRoute.TabRoot -> when (selectedTab) {
                            MainTab.Discover -> DiscoverScreen(
                                repository = repository,
                                onOpenMedia = { activeOverlayRoute = AppRoute.MediaDetail(it) },
                                onOpenExplore = { src -> exploreSource = src; selectedTab = MainTab.Explore },
                                onOpenMusic = { activeOverlayRoute = AppRoute.Music },
                                onPlayMedia = playHandler,
                            )
                            MainTab.Explore -> ExploreScreen(
                                repository = repository,
                                initialSource = exploreSource,
                                onOpenMedia = { activeOverlayRoute = AppRoute.MediaDetail(it) },
                            )
                            MainTab.Dashboard -> DashboardScreen(
                                repository = repository,
                                onOpenShortcuts = { activeOverlayRoute = AppRoute.Shortcuts },
                            )
                            MainTab.Settings -> SettingsHubScreen(
                                serverUrl = s.serverUrl,
                                userName = s.identity.name,
                                onOpenSites = { activeOverlayRoute = AppRoute.Sites },
                                onOpenUsers = { activeOverlayRoute = AppRoute.SystemModule("用户管理") },
                                onOpenAppearance = { activeOverlayRoute = AppRoute.Appearance },
                                onOpenPlugins = { activeOverlayRoute = AppRoute.Plugins(installedOnly = true) },
                                onOpenMedals = { activeOverlayRoute = AppRoute.Medals },
                                onOpenSystemModule = { activeOverlayRoute = AppRoute.SystemModule(it) },
                                onLogout = { repository.logout() },
                            )
                        }

                        is AppRoute.GlobalSearch -> GlobalSearchScreen(
                            repository = repository,
                            initialQuery = route.query,
                            initialKind = route.kind,
                            onBack = { activeOverlayRoute = AppRoute.TabRoot },
                            onOpenMedia = { activeOverlayRoute = AppRoute.MediaDetail(it) },
                            onPlayLibraryItem = playHandler,
                        )
                        is AppRoute.MediaDetail -> MediaDetailScreen(
                            item = route.item,
                            repository = repository,
                            onBack = { activeOverlayRoute = AppRoute.TabRoot },
                            onSearchResource = { kw -> activeOverlayRoute = AppRoute.Resources(kw) },
                            onPlayMedia = playHandler,
                        )
                        AppRoute.Music -> MusicDiscoveryScreen(
                            onBack = { activeOverlayRoute = AppRoute.TabRoot },
                            onPlayAudio = playHandler,
                        )
                        is AppRoute.Subscriptions -> SubscriptionsScreen(
                            repository = repository,
                            initialCategory = route.category,
                            onBack = { activeOverlayRoute = AppRoute.TabRoot },
                            onOpenCalendar = { activeOverlayRoute = AppRoute.Calendar },
                            onOpenCommunity = { activeOverlayRoute = AppRoute.SubscribeCommunity },
                        )
                        AppRoute.Calendar -> CalendarScreen(onBack = { activeOverlayRoute = AppRoute.Subscriptions() })
                        AppRoute.SubscribeCommunity -> SubscribeCommunityScreen(repository, onBack = { activeOverlayRoute = AppRoute.Subscriptions() })
                        is AppRoute.Resources -> ResourceSearchScreen(repository, route.keyword, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        AppRoute.Downloads -> DownloadsScreen(repository, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        is AppRoute.Files -> FileManagerScreen(repository, route.storage, route.path, onBack = { activeOverlayRoute = AppRoute.TabRoot }, onPlayMedia = playHandler)
                        is AppRoute.History -> TransferHistoryScreen(repository, route.search, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        AppRoute.Workflows -> WorkflowsScreen(
                            repository = repository,
                            onBack = { activeOverlayRoute = AppRoute.TabRoot },
                            onOpenCanvas = { activeOverlayRoute = AppRoute.WorkflowCanvas(it) },
                        )
                        is AppRoute.WorkflowCanvas -> WorkflowCanvasScreen(
                            workflow = route.workflow,
                            onBack = { activeOverlayRoute = AppRoute.Workflows },
                        )
                        AppRoute.Sites -> SitesScreen(repository, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        is AppRoute.Plugins -> PluginsCenterScreen(repository, route.installedOnly, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        AppRoute.Shortcuts -> ShortcutsDiagnosticsScreen(onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        is AppRoute.Agent -> AgentChatScreen(repository, route.prompt, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        AppRoute.Appearance -> AppearanceSettingsScreen(onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        AppRoute.Medals -> CommunityMedalsScreen(s.identity.name, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                        is AppRoute.SystemModule -> SystemModuleDetailScreen(route.title, onBack = { activeOverlayRoute = AppRoute.TabRoot })
                    }
                }

                // 可自由拖动悬浮 AI 机器人（在 AI 对话页隐藏自身）
                if (activeOverlayRoute !is AppRoute.Agent) {
                    FloatingAgentMascot(
                        onClick = { activeOverlayRoute = AppRoute.Agent() },
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .navigationBarsPadding()
                            .padding(end = 22.dp, bottom = 148.dp),
                    )
                }

                // 点击背景空白收起 8 项快捷溢出菜单
                if (showOverflowMenu) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { showOverflowMenu = false },
                    )
                }

                // 8 项高透玻璃快捷菜单弹层（停靠于底栏左上方）
                FloatingOverflowMenuPopover(
                    visible = showOverflowMenu,
                    userName = s.identity.name,
                    isSuperuser = s.identity.isSuperuser,
                    userAvatarUrl = repository.resolveImageUrl(s.identity.avatar),
                    onDismiss = { showOverflowMenu = false },
                    onSelect = { dest ->
                        activeOverlayRoute = when (dest) {
                            OverflowMenuDestination.Subscriptions -> AppRoute.Subscriptions()
                            OverflowMenuDestination.Calendar -> AppRoute.Calendar
                            OverflowMenuDestination.Resources -> AppRoute.Resources()
                            OverflowMenuDestination.Downloads -> AppRoute.Downloads
                            OverflowMenuDestination.Files -> AppRoute.Files()
                            OverflowMenuDestination.History -> AppRoute.History()
                            OverflowMenuDestination.Workflows -> AppRoute.Workflows
                            OverflowMenuDestination.Plugins -> AppRoute.Plugins(installedOnly = true)
                        }
                    },
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .navigationBarsPadding()
                        .padding(start = 18.dp, bottom = 92.dp),
                )

                // 底部区域：可选迷你悬浮音乐条 + 4+1 悬浮玻璃导航栏（AI 对话页自动隐藏底栏让给输入框）
                if (activeOverlayRoute !is AppRoute.Agent) {
                    Column(
                        modifier = Modifier.align(Alignment.BottomCenter),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        miniMusicRequest?.let { req ->
                            FloatingMiniMusicBar(
                                request = req,
                                isPlaying = miniMusicPlaying,
                                onTogglePlay = { miniMusicPlaying = !miniMusicPlaying },
                                onNext = {},
                                onExpand = { activePlayerRequest = req },
                                onClose = { miniMusicRequest = null },
                            )
                            Spacer(Modifier.height(6.dp))
                        }

                        val plusOneIsAdd = activeOverlayRoute is AppRoute.Sites || activeOverlayRoute is AppRoute.Workflows
                        FloatingFourPlusOneNavBar(
                            selectedTab = selectedTab,
                            onTabClick = { tab ->
                                if (tab == selectedTab && activeOverlayRoute == AppRoute.TabRoot) {
                                    // 重复点击当前主图标弹出 8 项快捷菜单
                                    showOverflowMenu = !showOverflowMenu
                                } else {
                                    showOverflowMenu = false
                                    selectedTab = tab
                                    activeOverlayRoute = AppRoute.TabRoot
                                }
                            },
                            plusOneIcon = if (plusOneIsAdd) Icons.Rounded.Add else Icons.Rounded.Search,
                            plusOneContentDescription = if (plusOneIsAdd) "新建" else "全局搜索",
                            onPlusOneClick = {
                                showOverflowMenu = false
                                activeOverlayRoute = AppRoute.GlobalSearch()
                            },
                            userAvatarUrl = repository.resolveImageUrl(s.identity.avatar),
                            userInitial = s.identity.name.ifBlank { "M" },
                        )
                    }
                }
            }
        }

        // 全屏原生音视频播放器覆盖层（支持未登录状态直接打开外部文件播放）
        activePlayerRequest?.let { req ->
            NativeMediaPlayerOverlay(
                request = req,
                onClose = { activePlayerRequest = null },
                onMinimizeToMiniBar = if (req.isAudio) {
                    {
                        miniMusicRequest = req
                        activePlayerRequest = null
                    }
                } else {
                    null
                },
            )
        }
    }
}
