package com.moviepilot.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.layout.layout
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.app.PictureInPictureModeChangedInfo
import androidx.core.content.ContextCompat
import androidx.core.util.Consumer
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
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.designsystem.SystemNotificationPreferencesStore
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
import com.moviepilot.feature.discover.MusicAlbumDetailScreen
import com.moviepilot.feature.discover.MusicArtistDetailScreen
import com.moviepilot.feature.discover.MusicDiscoveryScreen
import com.moviepilot.feature.download.DownloadsScreen
import com.moviepilot.feature.download.ResourceSearchScreen
import com.moviepilot.feature.library.FileManagerScreen
import com.moviepilot.feature.library.TransferHistoryScreen
import com.moviepilot.feature.media.MediaDetailScreen
import com.moviepilot.feature.media.MediaSeasonDetailScreen
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
import com.moviepilot.feature.subscribe.SubscribeHistoryScreen
import com.moviepilot.feature.subscribe.SubscriptionsScreen
import com.moviepilot.medal3d.CommunityProfile
import com.moviepilot.medal3d.NativeCommunityMedalShowcaseOverlay
import com.moviepilot.media.FloatingMiniMusicBar
import com.moviepilot.media.LocalPlaybackHistoryStore
import com.moviepilot.media.EmbeddedAudioMetadataFetcher
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.NativeMediaPlayerOverlay
import com.moviepilot.media.PlaybackServiceBridge
import com.moviepilot.media.QueueTrackSpec
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.media.buildConfiguredExoPlayer
import com.moviepilot.pluginhost.clearIsolatedPluginWebViewSession
import com.moviepilot.pluginhost.VuePluginSurface
import com.moviepilot.pluginhost.runtime.AndroidPluginCapsuleManager
import com.moviepilot.pluginhost.runtime.AndroidPluginWebViewPool
import com.moviepilot.pluginhost.runtime.PluginFloatingCapsuleOverlay
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaPersonDto
import com.moviepilot.rustbridge.MediaSeasonDto
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.MusicAlbumDto
import com.moviepilot.rustbridge.PlaybackSyncSessionTracker
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import com.moviepilot.rustbridge.WorkflowItemDto
import com.moviepilot.rustcore.PermissionsFfi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.random.Random

/** 主壳路由目的栈条目（覆盖全部业务页面、分类探索、媒体库、音乐专辑/艺人页、人物页、消息页、渠道授权、插件宿主与全部设置模块）。 */
sealed interface AppRoute {
    data object TabRoot : AppRoute
    data class Explore(val source: String = "tmdb_movies") : AppRoute
    data object SettingsHub : AppRoute
    data class GlobalSearch(val query: String = "", val kind: String = "media") : AppRoute
    data class MediaDetail(val item: MediaCardItem) : AppRoute
    data class MediaSeasonDetail(
        val seriesItem: MediaCardItem,
        val season: MediaSeasonDto,
        val seriesItemId: String = "",
        val server: String = "",
    ) : AppRoute
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
    data class MusicAlbumDetail(val album: MusicAlbumDto) : AppRoute
    data class MusicArtistDetail(
        val artistId: String,
        val artistName: String,
        val source: String = "musicbrainz",
    ) : AppRoute
    data class Subscriptions(val category: String? = null) : AppRoute
    data object Calendar : AppRoute
    data object SubscribeCommunity : AppRoute
    data class SubscribeHistory(val initialType: String = "电影") : AppRoute
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
    data class PluginDetail(val plugin: PluginItemDto, val openConfigFirst: Boolean = false) : AppRoute
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
internal fun checkRoutePermission(route: AppRoute, perms: PermissionsFfi): String? {
    if (perms.admin) return null
    return when (route) {
        AppRoute.Users,
        AppRoute.SubscribeSearchSettings,
        AppRoute.MediaSourcesSettings,
        AppRoute.DownloadersSettings,
        AppRoute.MediaServersSettings,
        AppRoute.DirectoriesSettings,
        AppRoute.NotificationsSettings,
        is AppRoute.Plugins,
        is AppRoute.PluginDetail,
        is AppRoute.Diagnostics,
        -> "当前账号无管理员权限"

        AppRoute.Sites,
        AppRoute.Workflows,
        is AppRoute.WorkflowCanvas,
        AppRoute.Downloads,
        is AppRoute.Files,
        is AppRoute.History,
        -> if (perms.manage) null else "当前账号无下载与文件整理权限"

        is AppRoute.Explore,
        AppRoute.Music,
        is AppRoute.MusicAlbumDetail,
        is AppRoute.MusicArtistDetail,
        -> if (perms.discovery) null else "当前账号无探索与发现权限"

        is AppRoute.Resources -> if (perms.search) null else "当前账号无站点资源搜索权限"

        is AppRoute.Subscriptions,
        AppRoute.Calendar,
        AppRoute.SubscribeCommunity,
        is AppRoute.SubscribeHistory,
        -> if (perms.subscribe) null else "当前账号无订阅管理权限"

        else -> null
    }
}

private fun isMeteredCellularOnly(context: Context): Boolean {
    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
    val net = cm.activeNetwork ?: return false
    val caps = cm.getNetworkCapabilities(net) ?: return false
    return caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
        !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
        !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
}

/**
 * MoviePilot Android Material Design 3 根容器与全局播放协调器：
 * 1. 维护 4 个一级 Tab 各自独立的子路由栈（`tabStacks`）并配合 `rememberSaveableStateHolder` 保活状态；
 * 2. 窄屏提供 4+1 分离式磨砂玻璃底栏，宽屏常驻左侧 `FloatingNavigationRail`；
 * 3. 全局托管后台音乐 `ExoPlayer`、Media3 系统媒体通知栏/锁屏会话、延迟解析队列自动连播、15 秒持续进度上报（最小化至迷你条绝不误报 `stopped`）与受管缓存清理；
 * 4. 在 401 会话过期、主动登出与实例切换时自动终止会话绑定播放并保留本机离线媒体播放。
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
    val activity = context as? Activity
    val colors = LocalMoviePilotColors.current
    val appearanceStore = LocalAppearanceStore.current
    val scope = rememberCoroutineScope()
    val session by repository.session.collectAsState()
    val savedServers by repository.savedServers.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val saveableStateHolder = rememberSaveableStateHolder()
    val localHistoryStore = remember(context) { LocalPlaybackHistoryStore(context) }
    val medalJson = remember { Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true } }

    var allowSelfSignedTls by remember { mutableStateOf(repository.secretStore.allowSelfSignedTls) }
    var isSwitchingServer by rememberSaveable { mutableStateOf(false) }
    var selectedTabId by rememberSaveable { mutableStateOf(MainTab.Discover.id) }
    val selectedTab = MainTab.entries.firstOrNull { it.id == selectedTabId } ?: MainTab.Discover
    val visitedTabs = remember { mutableStateListOf(MainTab.Discover) }
    LaunchedEffect(selectedTab) {
        if (selectedTab !in visitedTabs) {
            visitedTabs.add(selectedTab)
        }
    }

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
    var audioShuffleEnabled by rememberSaveable { mutableStateOf(false) }
    var audioRepeatMode by rememberSaveable { mutableIntStateOf(Player.REPEAT_MODE_OFF) }
    var pendingCellularRequest by remember { mutableStateOf<MediaPlaybackRequest?>(null) }
    var cellularConfirmedInSession by rememberSaveable { mutableStateOf(false) }
    var activeMedalShowcase by remember { mutableStateOf<Pair<CommunityProfile, String>?>(null) }

    var isInPipMode by remember(activity) {
        mutableStateOf(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) activity?.isInPictureInPictureMode == true else false)
    }
    DisposableEffect(activity) {
        val comp = activity as? ComponentActivity
        val pipListener = Consumer<PictureInPictureModeChangedInfo> { info ->
            isInPipMode = info.isInPictureInPictureMode
        }
        comp?.addOnPictureInPictureModeChangedListener(pipListener)
        onDispose {
            comp?.removeOnPictureInPictureModeChangedListener(pipListener)
        }
    }

    fun currentSelectedTab(): MainTab =
        MainTab.entries.firstOrNull { it.id == selectedTabId } ?: MainTab.Discover

    fun currentActiveInstanceUrl(): String = when (val cur = repository.session.value) {
        is SessionState.Authenticated -> cur.serverUrl
        is SessionState.NeedsLogin -> cur.serverUrl
        SessionState.Unconnected -> ""
    }

    val activeInstanceUrl = currentActiveInstanceUrl()

    // 登录后空闲 1.5s 自动预热 1 个本地联邦插件运行时壳，做到点击 Vue 插件零冷启动延迟
    LaunchedEffect(activeInstanceUrl) {
        if (activeInstanceUrl.isNotBlank()) {
            AndroidPluginWebViewPool.scheduleIdlePrewarm(context, 1500L)
        }
    }

    // 启动时清扫上次异常退出遗留的远程存储播放临时缓存文件
    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) {
            val dir = File(context.cacheDir, "mp_storage_playback")
            if (dir.isDirectory) {
                dir.listFiles()?.forEach { f -> runCatching { f.delete() } }
            }
        }
    }

    fun deleteTempFileIfUnused(tempPath: String?, keepPaths: Set<String?> = emptySet()) {
        if (tempPath.isNullOrBlank() || tempPath in keepPaths) return
        scope.launch(Dispatchers.IO) {
            runCatching {
                val f = File(tempPath)
                if (f.isFile && f.canonicalPath.startsWith(context.cacheDir.canonicalPath)) {
                    f.delete()
                }
            }
        }
    }

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
        visitedTabs.clear()
        visitedTabs.add(MainTab.Discover)
        selectedTabId = MainTab.Discover.id
        clearIsolatedPluginWebViewSession(context)
    }

    fun onTabBarClick(tab: MainTab) {
        // 始终实时读取 MutableState 中的 selectedTabId，避免 Compose Strong Skipping 记忆化局部函数引用时捕获首帧 Discover 快照。
        when (resolveMainTabClick(currentTab = currentSelectedTab(), clickedTab = tab, hasSubStack = tabStacks[tab].orEmpty().isNotEmpty())) {
            MainTabClickAction.SwitchTab -> selectedTabId = tab.id
            MainTabClickAction.ClearActiveStack -> clearTabStack(tab)
            MainTabClickAction.NoOp -> Unit
        }
    }

    fun pushRoute(route: AppRoute, targetTab: MainTab = currentSelectedTab()) {
        if (route == AppRoute.TabRoot) {
            clearTabStack(targetTab)
            selectedTabId = targetTab.id
            return
        }
        val auth = repository.session.value as? SessionState.Authenticated
        if (auth != null) {
            val deniedReason = checkRoutePermission(route, auth.permissions)
            if (deniedReason != null) {
                scope.launch { snackbarHostState.showSnackbar(deniedReason) }
                return
            }
        }
        if (targetTab != currentSelectedTab()) {
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
        val activeTab = currentSelectedTab()
        val currentList = tabStacks[activeTab].orEmpty()
        if (currentList.isNotEmpty()) {
            val popped = currentList.last()
            saveableStateHolder.removeState(popped.stateKey)
            tabStacks[activeTab] = currentList.dropLast(1)
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

    var bgAudioSyncTracker by remember { mutableStateOf<PlaybackSyncSessionTracker?>(null) }
    var bgAudioStartedSent by remember { mutableStateOf(false) }

    fun dispatchAudioSync(
        req: MediaPlaybackRequest?,
        trigger: String,
        posMs: Long,
        durMs: Long,
        isPaused: Boolean,
    ) {
        val r = req ?: return
        if (r.itemId.isBlank() || r.server.isBlank()) return
        val tracker = bgAudioSyncTracker ?: PlaybackSyncSessionTracker(r.playSessionId.orEmpty()).also {
            bgAudioSyncTracker = it
        }
        val decision = tracker.step(
            trigger = trigger,
            positionMs = posMs,
            durationMs = durMs.takeIf { it > 0L },
            isPaused = isPaused,
        )
        if (decision.state == "started") {
            bgAudioStartedSent = true
        }
        repository.playbackProgressReporter.enqueueDecision(
            repository = repository,
            itemId = r.itemId,
            server = r.server,
            mediaSourceId = r.mediaSourceId.ifBlank { null },
            decision = decision,
            playSessionId = r.playSessionId,
            durationMs = durMs.takeIf { it > 0L },
        )
    }

    fun releaseBackgroundAudio(reportStopped: Boolean = true) {
        val prevPlayer = bgAudioPlayer
        val prevReq = bgAudioRequest
        val instanceUrl = currentActiveInstanceUrl()
        if (prevPlayer != null && prevReq != null) {
            val pos = prevPlayer.currentPosition.coerceAtLeast(0L)
            val dur = prevPlayer.duration.coerceAtLeast(0L)
            localHistoryStore.recordPlaybackProgress(instanceUrl, prevReq.server, prevReq.localResumeId, pos, dur)
            if (reportStopped) {
                dispatchAudioSync(prevReq, "stop", pos, dur, isPaused = true)
            }
        }
        PlaybackServiceBridge.detachIfMatching(prevPlayer)
        prevPlayer?.release()
        bgAudioPlayer = null
        bgAudioRequest = null
        bgAudioSyncTracker = null
        bgAudioStartedSent = false
        bgAudioPlaying = false
        deleteTempFileIfUnused(prevReq?.tempFilePath, keepPaths = setOf(activePlayerRequest?.tempFilePath))
    }

    fun stopSessionBoundPlayback() {
        if (bgAudioRequest?.isSessionBound == true) {
            releaseBackgroundAudio(reportStopped = false)
        }
        val activeReq = activePlayerRequest
        if (activeReq != null && activeReq.isSessionBound) {
            activePlayerRequest = null
            deleteTempFileIfUnused(activeReq.tempFilePath, keepPaths = setOf(bgAudioRequest?.tempFilePath))
        }
    }

    suspend fun resolvePlayableRequest(rawReq: MediaPlaybackRequest): MediaPlaybackRequest? {
        val instanceUrl = currentActiveInstanceUrl()
        if (rawReq.url.isNotBlank()) {
            val resolvedOrigin = rawReq.originUrl.ifBlank { instanceUrl.ifBlank { rawReq.url } }
            val resolvedSameOriginHeaders = rawReq.sameOriginHeaders.ifEmpty {
                if (instanceUrl.isNotBlank()) repository.buildPlaybackHeaders(instanceUrl) else rawReq.headers
            }
            val cachedPlan = repository.playbackRouteResolver.lookupPlanForUrl(rawReq.url)
            val resolvedStreamHeaders = rawReq.streamHeaders.ifEmpty {
                cachedPlan?.active?.headers.orEmpty()
            }
            val resolvedRouteKind = rawReq.activeRouteKind.ifBlank {
                cachedPlan?.active?.kind.orEmpty()
            }
            val resolvedFallbacks = rawReq.fallbackRoutes.ifEmpty {
                cachedPlan?.fallbacks.orEmpty()
            }
            val inferredFallback = rawReq.proxyFallbackUrl ?: resolvedFallbacks.lastOrNull { it.kind == "mp_proxy" }?.url ?: run {
                if (
                    rawReq.isSessionBound &&
                    rawReq.itemId.isNotBlank() &&
                    !rawReq.itemId.startsWith("file:") &&
                    !rawReq.itemId.startsWith("local:") &&
                    !rawReq.itemId.startsWith("external:") &&
                    instanceUrl.isNotBlank() &&
                    !RustCoreBridge.containsUrl(instanceUrl, rawReq.url)
                ) {
                    val q = buildList {
                        add("itemid" to rawReq.itemId)
                        if (rawReq.server.isNotBlank()) add("server" to rawReq.server)
                        if (rawReq.mediaSourceId.isNotBlank()) add("media_source_id" to rawReq.mediaSourceId)
                    }
                    runCatching { RustCoreBridge.buildEndpointUrl(instanceUrl, listOf("mediaserver", "stream"), q) }.getOrNull()
                } else {
                    null
                }
            }
            return rawReq.copy(
                originUrl = resolvedOrigin,
                sameOriginHeaders = resolvedSameOriginHeaders,
                streamHeaders = resolvedStreamHeaders,
                proxyFallbackUrl = inferredFallback,
                activeRouteKind = resolvedRouteKind,
                fallbackRoutes = resolvedFallbacks,
                allowSelfSignedTls = rawReq.allowSelfSignedTls || repository.secretStore.allowSelfSignedTls,
            )
        }
        return when (val spec = rawReq.lazySpec) {
            is QueueTrackSpec.DirectUrl -> rawReq.copy(
                url = spec.url,
                originUrl = rawReq.originUrl.ifBlank { instanceUrl.ifBlank { spec.url } },
                sameOriginHeaders = rawReq.sameOriginHeaders.ifEmpty {
                    if (instanceUrl.isNotBlank()) repository.buildPlaybackHeaders(instanceUrl) else rawReq.headers
                },
                allowSelfSignedTls = rawReq.allowSelfSignedTls || repository.secretStore.allowSelfSignedTls,
            )

            is QueueTrackSpec.MusicQuery -> {
                val manifest = repository.fetchMusicStreamInfo(
                    title = spec.title,
                    artist = spec.artist,
                    album = spec.album,
                ) ?: return null
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                rawReq.copy(
                    url = manifest.contentUrl,
                    title = manifest.title.ifBlank { rawReq.title },
                    isAudio = true,
                    lyricsLrc = lrc,
                    headers = manifest.headers,
                    sameOriginHeaders = manifest.sameOriginHeaders,
                    streamHeaders = manifest.streamHeaders,
                    proxyFallbackUrl = manifest.proxyFallbackUrl,
                    activeRouteKind = manifest.activeRouteKind,
                    fallbackRoutes = manifest.fallbackRoutes,
                    originUrl = manifest.originUrl.ifBlank { instanceUrl.ifBlank { manifest.contentUrl } },
                    allowSelfSignedTls = repository.secretStore.allowSelfSignedTls,
                    itemId = manifest.itemId,
                    server = manifest.server,
                    serverType = manifest.serverType,
                    mediaSourceId = manifest.mediaSourceId.orEmpty(),
                    playSessionId = manifest.playSessionId,
                    progressSyncMode = manifest.progressSyncMode,
                )
            }

            is QueueTrackSpec.MediaServerItem -> {
                val manifest = repository.fetchVideoStreamInfo(
                    itemId = spec.itemId,
                    server = spec.server.ifBlank { null },
                    mediaSourceId = spec.mediaSourceId,
                ) ?: return null
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                rawReq.copy(
                    url = manifest.contentUrl,
                    title = rawReq.title.ifBlank { manifest.title },
                    isAudio = rawReq.isAudio || manifest.mediaType == "audio",
                    lyricsLrc = lrc,
                    headers = manifest.headers,
                    sameOriginHeaders = manifest.sameOriginHeaders,
                    streamHeaders = manifest.streamHeaders,
                    proxyFallbackUrl = manifest.proxyFallbackUrl,
                    activeRouteKind = manifest.activeRouteKind,
                    fallbackRoutes = manifest.fallbackRoutes,
                    originUrl = manifest.originUrl.ifBlank { instanceUrl.ifBlank { manifest.contentUrl } },
                    allowSelfSignedTls = repository.secretStore.allowSelfSignedTls,
                    itemId = manifest.itemId,
                    server = manifest.server.ifBlank { spec.server },
                    serverType = manifest.serverType.ifBlank { rawReq.serverType },
                    mediaSourceId = manifest.mediaSourceId ?: spec.mediaSourceId.orEmpty(),
                    playSessionId = manifest.playSessionId,
                    progressSyncMode = manifest.progressSyncMode,
                    resumePositionMs = manifest.resumePositionMs.takeIf { it > 0L } ?: rawReq.resumePositionMs,
                    subtitles = manifest.subtitles.map {
                        SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                    },
                    danmakuEnabled = manifest.danmakuEnabled,
                    seriesName = manifest.seriesName,
                    seasonNumber = manifest.seasonNumber,
                    episodeNumber = manifest.episodeNumber,
                    year = manifest.year,
                    tmdbId = manifest.tmdbId,
                    fileName = manifest.fileName,
                    fileSize = manifest.fileSize,
                )
            }

            null -> null
        }
    }

    val latestAudioShuffle by rememberUpdatedState(audioShuffleEnabled)
    val latestAudioRepeat by rememberUpdatedState(audioRepeatMode)
    val latestBgAudioReq by rememberUpdatedState(bgAudioRequest)
    val latestActivePlayerReq by rememberUpdatedState(activePlayerRequest)

    // 前向声明供监听器与队列控制复用
    var startPlaybackInternalRef: ((MediaPlaybackRequest, Boolean) -> Unit)? = null

    fun advanceAudioTrack(forward: Boolean, autoEnded: Boolean = false) {
        val cur = latestBgAudioReq ?: return
        val queue = cur.queue
        val player = bgAudioPlayer

        if (!forward && player != null && player.currentPosition > 3_000L) {
            player.seekTo(0L)
            return
        }
        if (autoEnded && latestAudioRepeat == Player.REPEAT_MODE_ONE && player != null) {
            player.seekTo(0L)
            player.play()
            return
        }
        if (queue.size <= 1) {
            if (autoEnded && latestAudioRepeat == Player.REPEAT_MODE_ALL && player != null) {
                player.seekTo(0L)
                player.play()
            }
            return
        }

        scope.launch {
            val maxTries = minOf(queue.size, 6)
            var candidateIdx = cur.queueIndex
            for (attempt in 0 until maxTries) {
                candidateIdx = when {
                    latestAudioShuffle && queue.size > 1 -> {
                        val others = queue.indices.filter { it != candidateIdx }
                        others.random(Random.Default)
                    }
                    forward -> {
                        val next = candidateIdx + 1
                        if (next >= queue.size) {
                            if (!autoEnded || latestAudioRepeat == Player.REPEAT_MODE_ALL) 0 else return@launch
                        } else {
                            next
                        }
                    }
                    else -> (candidateIdx - 1 + queue.size) % queue.size
                }

                val nextCandidate = queue[candidateIdx].copy(queue = queue, queueIndex = candidateIdx)
                val resolved = resolvePlayableRequest(nextCandidate)
                if (resolved != null) {
                    val keepFullscreen = latestActivePlayerReq?.isAudio == true
                    startPlaybackInternalRef?.invoke(resolved, keepFullscreen)
                    return@launch
                }
            }
            snackbarHostState.showSnackbar("队列中后续曲目暂未在媒体服务器中找到音频流")
        }
    }

    fun attachAudioMediaSession(player: ExoPlayer, req: MediaPlaybackRequest) {
        PlaybackServiceBridge.attachActivePlayer(
            context = context,
            exoPlayer = player,
            canSkipPrevious = { true },
            canSkipNext = { req.queue.size > 1 || latestAudioRepeat != Player.REPEAT_MODE_OFF },
            onSkipPrevious = { advanceAudioTrack(forward = false, autoEnded = false) },
            onSkipNext = { advanceAudioTrack(forward = true, autoEnded = false) },
        )
    }

    fun syncEnrichedAudioMetadata(enriched: MediaPlaybackRequest) {
        if (bgAudioRequest?.url == enriched.url) {
            bgAudioRequest = enriched
            val player = bgAudioPlayer
            val curItem = player?.currentMediaItem
            if (player != null && curItem != null && player.currentMediaItemIndex >= 0) {
                val metaBuilder = curItem.mediaMetadata.buildUpon()
                    .setTitle(enriched.title)
                    .setDisplayTitle(enriched.title)
                if (enriched.subtitle.isNotBlank()) {
                    metaBuilder.setArtist(enriched.subtitle)
                    metaBuilder.setSubtitle(enriched.subtitle)
                }
                if (enriched.albumTitle.isNotBlank()) {
                    metaBuilder.setAlbumTitle(enriched.albumTitle)
                }
                enriched.artworkBytes?.takeIf { it.isNotEmpty() }?.let { bytes ->
                    metaBuilder.setArtworkData(bytes, androidx.media3.common.MediaMetadata.PICTURE_TYPE_FRONT_COVER)
                }
                enriched.artworkUrl?.takeIf { it.isNotBlank() }?.let { art ->
                    metaBuilder.setArtworkUri(android.net.Uri.parse(art))
                }
                val updatedItem = curItem.buildUpon().setMediaMetadata(metaBuilder.build()).build()
                runCatching { player.replaceMediaItem(player.currentMediaItemIndex, updatedItem) }
            }
        }
        if (activePlayerRequest?.url == enriched.url) {
            activePlayerRequest = enriched
        }
    }

    fun executeStartPlayback(rawReq: MediaPlaybackRequest, expandOverlay: Boolean = true) {
        scope.launch {
            val req = runCatching { resolvePlayableRequest(rawReq) }.getOrNull()
            if (req == null) {
                snackbarHostState.showSnackbar("暂无法解析「${rawReq.title}」的可播放流")
                return@launch
            }
            try {
            if (req.isAudio) {
                val prevReq = bgAudioRequest
                val prevPlayer = bgAudioPlayer
                if (prevReq?.url != req.url || prevPlayer == null) {
                    val instanceUrl = currentActiveInstanceUrl()
                    if (prevPlayer != null && prevReq != null) {
                        val prevPos = prevPlayer.currentPosition.coerceAtLeast(0L)
                        val prevDur = prevPlayer.duration.coerceAtLeast(0L)
                        localHistoryStore.recordPlaybackProgress(instanceUrl, prevReq.server, prevReq.localResumeId, prevPos, prevDur)
                        dispatchAudioSync(prevReq, "stop", prevPos, prevDur, isPaused = true)
                        PlaybackServiceBridge.detachIfMatching(prevPlayer)
                        prevPlayer.release()
                        deleteTempFileIfUnused(prevReq.tempFilePath, keepPaths = setOf(req.tempFilePath))
                    }
                    bgAudioSyncTracker = PlaybackSyncSessionTracker(req.playSessionId.orEmpty())
                    bgAudioStartedSent = false
                    val savedMs = localHistoryStore.readResumePositionMs(instanceUrl, req.server, req.localResumeId)
                    val bestMs = LocalPlaybackHistoryStore.resolveBestResumeMs(savedMs, req.resumePositionMs)
                    val player = buildConfiguredExoPlayer(context, req, resumePositionOverrideMs = bestMs).apply {
                        shuffleModeEnabled = audioShuffleEnabled
                        repeatMode = if (audioRepeatMode == Player.REPEAT_MODE_ONE) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    }
                    player.addListener(object : Player.Listener {
                        override fun onPositionDiscontinuity(
                            oldPosition: Player.PositionInfo,
                            newPosition: Player.PositionInfo,
                            reason: Int,
                        ) {
                            if (reason == Player.DISCONTINUITY_REASON_SEEK || reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT) {
                                val curReq = latestBgAudioReq ?: req
                                dispatchAudioSync(
                                    req = curReq,
                                    trigger = "seek",
                                    posMs = newPosition.positionMs.coerceAtLeast(0L),
                                    durMs = player.duration.coerceAtLeast(0L),
                                    isPaused = !player.isPlaying,
                                )
                            }
                        }

                        override fun onIsPlayingChanged(isPlaying: Boolean) {
                            bgAudioPlaying = isPlaying
                            val curReq = latestBgAudioReq ?: req
                            val pos = player.currentPosition.coerceAtLeast(0L)
                            val dur = player.duration.coerceAtLeast(0L)
                            localHistoryStore.recordPlaybackProgress(currentActiveInstanceUrl(), curReq.server, curReq.localResumeId, pos, dur)
                            val trigger = when {
                                isPlaying && !bgAudioStartedSent -> "start"
                                isPlaying -> "resume"
                                else -> "pause"
                            }
                            dispatchAudioSync(
                                req = curReq,
                                trigger = trigger,
                                posMs = pos,
                                durMs = dur,
                                isPaused = !isPlaying,
                            )
                        }

                        override fun onPlaybackStateChanged(playbackState: Int) {
                            if (playbackState == Player.STATE_ENDED) {
                                val curReq = latestBgAudioReq ?: req
                                localHistoryStore.clearResumePosition(currentActiveInstanceUrl(), curReq.server, curReq.localResumeId)
                                val dur = player.duration.coerceAtLeast(0L)
                                dispatchAudioSync(
                                    req = curReq,
                                    trigger = "finish",
                                    posMs = dur,
                                    durMs = dur,
                                    isPaused = true,
                                )
                                advanceAudioTrack(forward = true, autoEnded = true)
                            }
                        }
                    })
                    bgAudioPlayer = player
                    bgAudioRequest = req
                    bgAudioPlaying = true
                    attachAudioMediaSession(player, req)
                    if (EmbeddedAudioMetadataFetcher.needsExtraction(req)) {
                        scope.launch {
                            val extracted = EmbeddedAudioMetadataFetcher.fetchEmbeddedMetadata(context, req)
                            if (extracted != null && bgAudioRequest?.url == req.url) {
                                val latest = bgAudioRequest ?: req
                                syncEnrichedAudioMetadata(EmbeddedAudioMetadataFetcher.applyToRequest(latest, extracted))
                            }
                        }
                    }
                } else {
                    prevPlayer.playWhenReady = true
                    bgAudioRequest = req
                    attachAudioMediaSession(prevPlayer, req)
                }
                if (expandOverlay) {
                    val prevOverlay = activePlayerRequest
                    activePlayerRequest = req
                    if (prevOverlay != null && !prevOverlay.isAudio) {
                        deleteTempFileIfUnused(prevOverlay.tempFilePath, keepPaths = setOf(req.tempFilePath))
                    }
                } else if (activePlayerRequest?.isAudio == true) {
                    activePlayerRequest = req
                }
            } else {
                bgAudioPlayer?.pause()
                val prevOverlay = activePlayerRequest
                activePlayerRequest = req
                if (prevOverlay != null && prevOverlay.tempFilePath != req.tempFilePath) {
                    deleteTempFileIfUnused(prevOverlay.tempFilePath, keepPaths = setOf(req.tempFilePath, bgAudioRequest?.tempFilePath))
                }
            }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Throwable) {
                snackbarHostState.showSnackbar("无法启动播放「${req.title}」：${e.message ?: "播放器初始化失败"}")
            }
        }
    }

    startPlaybackInternalRef = { nextReq, expand -> executeStartPlayback(nextReq, expandOverlay = expand) }

    fun startPlayback(req: MediaPlaybackRequest) {
        val isRemoteStream = req.url.startsWith("http://", ignoreCase = true) ||
            req.url.startsWith("https://", ignoreCase = true) ||
            req.lazySpec != null
        val prefs = PlaybackPreferencesStore(context)
        if (isRemoteStream && prefs.cellularWarn && !cellularConfirmedInSession && isMeteredCellularOnly(context)) {
            pendingCellularRequest = req
            return
        }
        executeStartPlayback(req, expandOverlay = true)
    }

    // 根壳层 1 秒音频状态机心跳（覆盖播放中 10s 心跳、暂停 12s 保活与 15 分钟暂停自动释放，全屏/迷你条/后台均不中断）
    LaunchedEffect(bgAudioPlayer, bgAudioRequest) {
        val player = bgAudioPlayer ?: return@LaunchedEffect
        val req = bgAudioRequest ?: return@LaunchedEffect
        var tick = 0
        while (true) {
            delay(1_000L)
            tick++
            val pos = player.currentPosition.coerceAtLeast(0L)
            val dur = player.duration.coerceAtLeast(0L)
            val playing = player.isPlaying
            if (dur > 1_000L) {
                if (tick % 10 == 0) {
                    localHistoryStore.recordPlaybackProgress(activeInstanceUrl, req.server, req.localResumeId, pos, dur)
                }
                dispatchAudioSync(
                    req = req,
                    trigger = "tick",
                    posMs = pos,
                    durMs = dur,
                    isPaused = !playing,
                )
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            releaseBackgroundAudio(reportStopped = true)
            PlaybackServiceBridge.releaseAll()
        }
    }

    // 监听从已认证态退出（含 401 自动登出）：终止会话绑定播放，保留本机离线播放，并清理导航栈与隔离插件 WebView 会话
    var wasAuthenticated by remember { mutableStateOf(session is SessionState.Authenticated) }
    LaunchedEffect(session is SessionState.Authenticated) {
        val nowAuth = session is SessionState.Authenticated
        if (wasAuthenticated && !nowAuth) {
            stopSessionBoundPlayback()
            clearAllNavigationAndWebSession()
        }
        wasAuthenticated = nowAuth
    }

    // Android 系统 Back 返回键 / 边缘侧滑统一接管
    val canHandleBack = activePlayerRequest != null ||
        activeMedalShowcase != null ||
        isSwitchingServer ||
        (session is SessionState.Authenticated && (activeStack.isNotEmpty() || selectedTab != MainTab.Discover))

    BackHandler(enabled = canHandleBack) {
        when {
            activePlayerRequest != null -> {
                val cur = activePlayerRequest!!
                val keepMini = PlaybackPreferencesStore(context).keepMusicMiniBar
                if (cur.isAudio && keepMini) {
                    activePlayerRequest = null
                } else {
                    if (cur.isAudio) releaseBackgroundAudio()
                    else deleteTempFileIfUnused(cur.tempFilePath, keepPaths = setOf(bgAudioRequest?.tempFilePath))
                    activePlayerRequest = null
                }
            }
            activeMedalShowcase != null -> activeMedalShowcase = null
            isSwitchingServer -> isSwitchingServer = false
            activeStack.isNotEmpty() -> popRoute()
            selectedTab != MainTab.Discover -> selectedTabId = MainTab.Discover.id
        }
    }

    // 鉴权就绪后拉取权威用户信息（真实头像）、预热图片代理 Cookie，并在管理员实例允许时执行匿名版本统计上报
    val authKey = (session as? SessionState.Authenticated)?.let { "${it.serverUrl}|${it.token.takeLast(8)}" }
    val systemNotifPrefs = remember(context) { SystemNotificationPreferencesStore(context) }
    var notifPermissionGrantVersion by remember { mutableIntStateOf(0) }
    val postNotificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        systemNotifPrefs.markPermissionPrompted()
        if (granted) {
            notifPermissionGrantVersion++
        }
    }

    LaunchedEffect(authKey, systemNotifPrefs.systemBarNotificationsEnabled) {
        if (
            authKey != null &&
            systemNotifPrefs.systemBarNotificationsEnabled &&
            !systemNotifPrefs.hasPromptedPermission
        ) {
            systemNotifPrefs.markPermissionPrompted()
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                postNotificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    LaunchedEffect(
        authKey,
        systemNotifPrefs.systemBarNotificationsEnabled,
        systemNotifPrefs.includePluginNotifications,
        systemNotifPrefs.includeSystemNotifications,
        notifPermissionGrantVersion,
    ) {
        val shouldSync = authKey != null &&
            systemNotifPrefs.systemBarNotificationsEnabled &&
            (systemNotifPrefs.includePluginNotifications || systemNotifPrefs.includeSystemNotifications)
        AndroidNotificationSyncManager.syncBackgroundWork(context, enabled = shouldSync)
        if (!shouldSync) return@LaunchedEffect
        while (true) {
            runCatching {
                AndroidNotificationSyncManager.pollAndPostOnce(context, repository)
            }
            delay(30_000L)
        }
    }

    LaunchedEffect(authKey) {
        if (authKey != null) {
            repository.hydrateAuthenticatedSession()
            val latestAuth = repository.session.value as? SessionState.Authenticated
            if (latestAuth?.permissions?.admin == true) {
                val appVersion = runCatching {
                    context.packageManager.getPackageInfo(context.packageName, 0).versionName
                }.getOrNull()?.takeIf { it.isNotBlank() }.orEmpty()
                if (appVersion.isNotEmpty()) {
                    runCatching {
                        val cfg = repository.fetchUsageReportingConfig()
                        if (cfg != null && cfg.first) {
                            AppUsageReporter.forContext(context).report(
                                enabled = true,
                                host = cfg.second,
                                version = appVersion,
                            )
                        }
                    }
                }
            }
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
            val rawUri = runCatching { Uri.parse(incomingDeepLink) }.getOrNull()
            val queryTitleHint = rawUri?.getQueryParameter("title")?.takeIf { it.isNotBlank() }
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
                            title = obj["title"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() }
                                ?: queryTitleHint
                                ?: "外部直链播放",
                            isAudio = obj["media_kind"]?.jsonPrimitive?.content == "audio",
                            isSessionBound = false,
                        ),
                    )
                }
                onConsumeDeepLink()
                return@LaunchedEffect
            }

            // 其余业务路由与媒体库/存储深链播放需等待会话进入 Authenticated 后再执行
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
                    "playMediaServerItem" -> {
                        val itemId = obj["item_id"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() }.orEmpty()
                        val server = obj["server"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() }
                        if (itemId.isNotBlank()) {
                            val manifest = repository.fetchVideoStreamInfo(itemId, server)
                            if (manifest != null) {
                                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                startPlayback(
                                    MediaPlaybackRequest(
                                        url = manifest.contentUrl,
                                        title = manifest.title.ifBlank { queryTitleHint ?: "媒体库播放" },
                                        subtitle = manifest.server.ifBlank { server.orEmpty() },
                                        isAudio = manifest.mediaType == "audio",
                                        lyricsLrc = lrc,
                                        headers = manifest.headers,
                                        sameOriginHeaders = manifest.sameOriginHeaders,
                                        streamHeaders = manifest.streamHeaders,
                                        proxyFallbackUrl = manifest.proxyFallbackUrl,
                                        activeRouteKind = manifest.activeRouteKind,
                                        fallbackRoutes = manifest.fallbackRoutes,
                                        originUrl = manifest.originUrl,
                                        itemId = manifest.itemId,
                                        server = manifest.server.ifBlank { server.orEmpty() },
                                        serverType = manifest.serverType,
                                        mediaSourceId = manifest.mediaSourceId.orEmpty(),
                                        playSessionId = manifest.playSessionId,
                                        progressSyncMode = manifest.progressSyncMode,
                                        resumePositionMs = manifest.resumePositionMs,
                                        subtitles = manifest.subtitles.map {
                                            SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                                        },
                                        isSessionBound = true,
                                        danmakuEnabled = manifest.danmakuEnabled,
                                        seriesName = manifest.seriesName,
                                        seasonNumber = manifest.seasonNumber,
                                        episodeNumber = manifest.episodeNumber,
                                        year = manifest.year,
                                        tmdbId = manifest.tmdbId,
                                        fileName = manifest.fileName,
                                        fileSize = manifest.fileSize,
                                    ),
                                )
                            } else {
                                snackbarHostState.showSnackbar("无法拉取媒体服务器条目（$itemId）播放流")
                            }
                        }
                    }

                    "playStorageFile" -> {
                        val storage = obj["storage"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() } ?: "local"
                        val path = obj["path"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() }.orEmpty()
                        if (path.isNotBlank()) {
                            val fileName = path.substringAfterLast('/').ifBlank { queryTitleHint ?: "存储媒体" }
                            val safeName = fileName.replace(Regex("[^a-zA-Z0-9._\\-\\u4e00-\\u9fa5]"), "_")
                            val cacheDir = File(context.cacheDir, "mp_storage_playback").apply { mkdirs() }
                            val destFile = File(cacheDir, "${path.hashCode()}_$safeName")
                            val resolved = repository.resolveStoragePlayback(storage, path, destFile)
                            if (resolved != null) {
                                val lrc = resolved.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                startPlayback(
                                    MediaPlaybackRequest(
                                        url = resolved.url,
                                        title = queryTitleHint ?: fileName.substringBeforeLast('.').ifBlank { fileName },
                                        subtitle = "$storage · $path",
                                        isAudio = resolved.isAudio,
                                        lyricsLrc = lrc,
                                        headers = resolved.headers,
                                        sameOriginHeaders = resolved.sameOriginHeaders,
                                        streamHeaders = resolved.streamHeaders,
                                        originUrl = resolved.originUrl,
                                        proxyFallbackUrl = resolved.proxyFallbackUrl,
                                        activeRouteKind = resolved.activeRouteKind,
                                        fallbackRoutes = resolved.fallbackRoutes,
                                        itemId = resolved.itemId,
                                        isSessionBound = !resolved.isStrmDirect,
                                        tempFilePath = resolved.tempFilePath,
                                    ),
                                )
                            } else {
                                snackbarHostState.showSnackbar("无法从存储（$storage）拉取媒体文件")
                            }
                        }
                    }

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
                    "pluginDetail" -> {
                        val targetId = obj["plugin_id"]?.jsonPrimitive?.content?.takeIf { it != "null" && it.isNotBlank() }.orEmpty()
                        val surf = obj["surface"]?.jsonPrimitive?.content?.takeIf { it != "null" }?.lowercase().orEmpty()
                        if (targetId.isNotBlank()) {
                            val matched = runCatching { repository.fetchPlugins(true) }.getOrDefault(emptyList())
                                .firstOrNull { it.id.equals(targetId, ignoreCase = true) }
                            val pluginItem = matched ?: PluginItemDto(
                                id = targetId,
                                name = targetId,
                                desc = "",
                                version = "",
                                author = "",
                                icon = null,
                                labels = emptyList(),
                                installed = true,
                                state = true,
                                hasPage = true,
                                hasUpdate = false,
                            )
                            pushRoute(
                                AppRoute.PluginDetail(
                                    plugin = pluginItem,
                                    openConfigFirst = surf == "config",
                                ),
                                MainTab.Workspace,
                            )
                        }
                    }
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
    val showWideRail = isWideCanvas && authSession != null && !isSwitchingServer && activeMedalShowcase == null && activePlayerRequest == null && !isInPipMode
    val showBottomNav = authSession != null && !isSwitchingServer && isTopLevelTab && !isWideCanvas && activeMedalShowcase == null && activePlayerRequest == null && !isInPipMode
    val showMiniMusicBar = bgAudioRequest != null && !isSwitchingServer && activeMedalShowcase == null && activePlayerRequest == null && !isInPipMode

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
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Row(modifier = Modifier.fillMaxSize()) {
                // 1. 宽屏（>= 600dp）常驻左侧 NavigationRail
                if (showWideRail) {
                    val authed = authSession!!
                    FloatingNavigationRail(
                        selectedTab = selectedTab,
                        onTabClick = { onTabBarClick(it) },
                        onSearchClick = { pushRoute(AppRoute.GlobalSearch()) },
                        userAvatarUrl = repository.resolveImageUrl(authed.identity.avatar),
                        userInitial = authed.identity.name.ifBlank { "M" },
                    )
                }

                // 2. 主内容与底部浮层区域
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
                    Box(
                        modifier = Modifier.fillMaxSize(),
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
                                                        stopSessionBoundPlayback()
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
                                            stopSessionBoundPlayback()
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
                                    repository = repository,
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
                                    Box(modifier = Modifier.fillMaxSize()) {
                                        // 常驻保活已访问过的 4 个一级主 Tab：未激活或处于二级页面下层时置为 unplaced（零绘制、零点击命中、零无障碍冲突），切换与返回实现 0ms 秒开
                                        visitedTabs.forEach { tab ->
                                            key(tab.id) {
                                                val isActiveRoot = isTopLevelTab && selectedTab == tab
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxSize()
                                                        .layout { measurable, constraints ->
                                                            val placeable = measurable.measure(constraints)
                                                            if (isActiveRoot) {
                                                                layout(placeable.width, placeable.height) {
                                                                    placeable.placeRelative(0, 0)
                                                                }
                                                            } else {
                                                                layout(0, 0) {}
                                                            }
                                                        },
                                                ) {
                                                    saveableStateHolder.SaveableStateProvider("tab_root_${tab.id}") {
                                                        when (tab) {
                                                            MainTab.Discover -> DiscoverScreen(
                                                                repository = repository,
                                                                onOpenMedia = ::openMediaSmart,
                                                                onOpenExplore = { src -> pushRoute(AppRoute.Explore(src)) },
                                                                onOpenMusic = { pushRoute(AppRoute.Music) },
                                                                onOpenMusicAlbum = { album -> pushRoute(AppRoute.MusicAlbumDetail(album)) },
                                                                onOpenMediaLibrary = { lib -> pushRoute(AppRoute.MediaServerLibrary(lib)) },
                                                                onPlayMedia = ::startPlayback,
                                                            )
                                                            MainTab.Subscribe -> SubscriptionsScreen(
                                                                repository = repository,
                                                                initialCategory = null,
                                                                onBack = null,
                                                                onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                                                onOpenCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                                                onOpenSubscribeHistory = { mtype ->
                                                                    pushRoute(AppRoute.SubscribeHistory(mtype))
                                                                },
                                                                onOpenMedia = ::openMediaSmart,
                                                                onPlayMedia = ::startPlayback,
                                                                onOpenServerItem = { itemId, server, title ->
                                                                    pushRoute(AppRoute.MediaServerDetail(itemId, server, title))
                                                                },
                                                            )
                                                            MainTab.Dashboard -> DashboardScreen(
                                                                repository = repository,
                                                                onOpenMessages = { pushRoute(AppRoute.Messages) },
                                                                onOpenDiagnosticTab = { tabName -> pushRoute(AppRoute.Diagnostics(tabName)) },
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
                                                                onOpenDiagnosticTab = { tabName -> pushRoute(AppRoute.Diagnostics(tabName)) },
                                                                permissions = s.permissions,
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        AnimatedContent(
                                            targetState = Pair(currentRoute, currentStateKey),
                                            transitionSpec = {
                                                val enteringSub = targetState.first != AppRoute.TabRoot && initialState.first == AppRoute.TabRoot
                                                val returningRoot = targetState.first == AppRoute.TabRoot && initialState.first != AppRoute.TabRoot
                                                when {
                                                    enteringSub -> (slideInHorizontally(tween(200)) { it / 6 } + fadeIn(tween(180)))
                                                        .togetherWith(fadeOut(tween(120)))
                                                    returningRoot -> fadeIn(tween(140))
                                                        .togetherWith(slideOutHorizontally(tween(180)) { it / 6 } + fadeOut(tween(150)))
                                                    else -> fadeIn(tween(150)).togetherWith(fadeOut(tween(110)))
                                                }
                                            },
                                            label = "mpMainRouter",
                                        ) { (route, stateKey) ->
                                            if (route == AppRoute.TabRoot) {
                                                Spacer(Modifier.fillMaxSize())
                                            } else {
                                                Box(modifier = Modifier.fillMaxSize()) {
                                                    CinematicAmbientGradient()
                                                    saveableStateHolder.SaveableStateProvider(stateKey) {
                                                        when (route) {
                                                            AppRoute.TabRoot -> Unit

                                                is AppRoute.Explore -> ExploreScreen(
                                                    repository = repository,
                                                    initialSource = route.source,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = ::openMediaSmart,
                                                    onOpenMusicAlbum = { album -> pushRoute(AppRoute.MusicAlbumDetail(album)) },
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
                                                    onSendTestNotification = {
                                                        AndroidNotificationSyncManager.sendTestNotification(context, s.serverUrl)
                                                    },
                                                    permissions = s.permissions,
                                                    onSwitchServer = { isSwitchingServer = true },
                                                    onLogout = {
                                                        stopSessionBoundPlayback()
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
                                                    onOpenMusicAlbum = { album -> pushRoute(AppRoute.MusicAlbumDetail(album)) },
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
                                                    onOpenSeasonDetail = { seriesItem, season, seriesItemId, srv ->
                                                        pushRoute(AppRoute.MediaSeasonDetail(seriesItem, season, seriesItemId, srv))
                                                    },
                                                )
                                                is AppRoute.MediaSeasonDetail -> MediaSeasonDetailScreen(
                                                    seriesItem = route.seriesItem,
                                                    initialSeason = route.season,
                                                    initialSeriesItemId = route.seriesItemId,
                                                    initialServer = route.server,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onSearchResource = { kw -> pushRoute(AppRoute.Resources(kw)) },
                                                    onPlayMedia = ::startPlayback,
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
                                                    onOpenAlbum = { album -> pushRoute(AppRoute.MusicAlbumDetail(album)) },
                                                    repository = repository,
                                                )
                                                is AppRoute.MusicAlbumDetail -> MusicAlbumDetailScreen(
                                                    seed = route.album,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onOpenArtist = { artistId, artistName, src ->
                                                        pushRoute(AppRoute.MusicArtistDetail(artistId, artistName, src))
                                                    },
                                                    onPlayAudio = ::startPlayback,
                                                    canSubscribe = s.permissions.admin || s.permissions.subscribe,
                                                )
                                                is AppRoute.MusicArtistDetail -> MusicArtistDetailScreen(
                                                    artistId = route.artistId,
                                                    artistName = route.artistName,
                                                    source = route.source,
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                    onOpenAlbum = { album -> pushRoute(AppRoute.MusicAlbumDetail(album)) },
                                                )
                                                is AppRoute.Subscriptions -> SubscriptionsScreen(
                                                    repository = repository,
                                                    initialCategory = route.category,
                                                    onBack = ::popRoute,
                                                    onOpenCalendar = { pushRoute(AppRoute.Calendar) },
                                                    onOpenCommunity = { pushRoute(AppRoute.SubscribeCommunity) },
                                                    onOpenSubscribeHistory = { mtype ->
                                                        pushRoute(AppRoute.SubscribeHistory(mtype))
                                                    },
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
                                                is AppRoute.SubscribeHistory -> SubscribeHistoryScreen(
                                                    repository = repository,
                                                    initialType = route.initialType,
                                                    onBack = ::popRoute,
                                                    onOpenMedia = ::openMediaSmart,
                                                )
                                                is AppRoute.Resources -> ResourceSearchScreen(repository, route.keyword, onBack = ::popRoute)
                                                AppRoute.Downloads -> DownloadsScreen(repository, onBack = ::popRoute)
                                                is AppRoute.Files -> FileManagerScreen(repository, route.storage, route.path, onBack = ::popRoute, onPlayMedia = ::startPlayback)
                                                is AppRoute.History -> TransferHistoryScreen(repository, route.search, onBack = ::popRoute, onPlayMedia = ::startPlayback)
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
                                                AppRoute.PlaybackSettings -> PlaybackPreferencesScreen(
                                                    repository = repository,
                                                    onBack = ::popRoute,
                                                )
                                                is AppRoute.Plugins -> PluginsCenterScreen(
                                                    repository = repository,
                                                    initialInstalledOnly = route.installedOnly,
                                                    onBack = ::popRoute,
                                                    onOpenPluginDetail = { p, configFirst -> pushRoute(AppRoute.PluginDetail(p, configFirst)) },
                                                )
                                                is AppRoute.PluginDetail -> PluginDetailScreen(
                                                    plugin = route.plugin,
                                                    repository = repository,
                                                    openConfigFirst = route.openConfigFirst,
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
                            }
                        }
                    }

                    // 3. 一级主 Tab 右下角 AI 助手入口
                    if (authSession != null && !isSwitchingServer && isTopLevelTab && appearanceStore.showAgentMascot && activeMedalShowcase == null && activePlayerRequest == null && !isInPipMode) {
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

                    // 3.5 联邦插件最小化悬浮胶囊与快捷操作小窗（跨一级 Tab 与子页面保活）
                    val minimizedPluginSession = AndroidPluginCapsuleManager.currentSession
                    val isViewingSameMinimizedPlugin = minimizedPluginSession != null &&
                        (currentRoute as? AppRoute.PluginDetail)?.plugin?.id?.equals(minimizedPluginSession.pluginId, ignoreCase = true) == true
                    LaunchedEffect(AndroidPluginCapsuleManager.restoreRequestNonce) {
                        val targetId = AndroidPluginCapsuleManager.pendingRestorePluginId
                        val parked = AndroidPluginCapsuleManager.currentSession
                        if (!targetId.isNullOrBlank() && parked != null && parked.pluginId.equals(targetId, ignoreCase = true)) {
                            AndroidPluginCapsuleManager.clearPendingRestoreRequest()
                            pushRoute(
                                AppRoute.PluginDetail(
                                    plugin = PluginItemDto(
                                        id = parked.pluginId,
                                        name = parked.pluginName,
                                        desc = parked.snapshot.subtitle,
                                        version = "",
                                        author = "",
                                        icon = parked.snapshot.iconUrl,
                                        labels = emptyList(),
                                        installed = true,
                                        state = true,
                                        hasPage = parked.pluginHasPage,
                                        hasUpdate = false,
                                        renderMode = "vue",
                                    ),
                                    openConfigFirst = parked.surface == VuePluginSurface.Config,
                                ),
                                MainTab.Workspace,
                            )
                        }
                    }
                    if (authSession != null && !isSwitchingServer && minimizedPluginSession != null && !isViewingSameMinimizedPlugin && activeMedalShowcase == null && activePlayerRequest == null && !isInPipMode) {
                        val capsuleBottom = when {
                            showBottomNav && showMiniMusicBar -> 166.dp
                            showBottomNav -> 96.dp
                            showMiniMusicBar -> 92.dp
                            else -> 24.dp
                        }
                        PluginFloatingCapsuleOverlay(
                            session = minimizedPluginSession,
                            isExpanded = AndroidPluginCapsuleManager.isMiniCardExpanded,
                            onToggleExpanded = { AndroidPluginCapsuleManager.isMiniCardExpanded = it },
                            onOpenPluginWindow = {
                                AndroidPluginCapsuleManager.isMiniCardExpanded = false
                                pushRoute(
                                    AppRoute.PluginDetail(
                                        plugin = PluginItemDto(
                                            id = minimizedPluginSession.pluginId,
                                            name = minimizedPluginSession.pluginName,
                                            desc = minimizedPluginSession.snapshot.subtitle,
                                            version = "",
                                            author = "",
                                            icon = minimizedPluginSession.snapshot.iconUrl,
                                            labels = emptyList(),
                                            installed = true,
                                            state = true,
                                            hasPage = minimizedPluginSession.pluginHasPage,
                                            hasUpdate = false,
                                            renderMode = "vue",
                                        ),
                                        openConfigFirst = minimizedPluginSession.surface == VuePluginSurface.Config,
                                    ),
                                    MainTab.Workspace,
                                )
                            },
                            onDispatchAction = { actionId -> AndroidPluginCapsuleManager.dispatchAction(actionId) },
                            onCloseCapsule = { AndroidPluginCapsuleManager.closeAndRelease(context) },
                            bottomClearanceDp = capsuleBottom,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }

                    // 4. 底部悬浮区域：迷你音乐播控条（PiP 小窗模式下自动隐藏）+ 手机态 4+1 磨砂玻璃胶囊底栏
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
                                            advanceAudioTrack(forward = true, autoEnded = false)
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

                            if (showBottomNav) {
                                val authed = authSession!!
                                MoviePilotBottomNavigationBar(
                                    selectedTab = selectedTab,
                                    onTabClick = { onTabBarClick(it) },
                                    onSearchClick = { pushRoute(AppRoute.GlobalSearch()) },
                                    userAvatarUrl = repository.resolveImageUrl(authed.identity.avatar),
                                    userInitial = authed.identity.name.ifBlank { "M" },
                                )
                            }
                        }
                    }

                    // 5. Android Material 3 全局非阻塞 Snackbar 宿主
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

            // 7. 全屏原生音视频播放器覆盖层（音频复用根壳共享 ExoPlayer；视频独立释放并在退出后恢复后台音频会话）
            activePlayerRequest?.let { req ->
                NativeMediaPlayerOverlay(
                    request = req,
                    sharedPlayer = if (req.isAudio && bgAudioRequest?.url == req.url) bgAudioPlayer else null,
                    instanceUrl = activeInstanceUrl,
                    audioShuffleEnabled = audioShuffleEnabled,
                    audioRepeatMode = audioRepeatMode,
                    onUpdateAudioShuffle = { audioShuffleEnabled = it },
                    onUpdateAudioRepeatMode = { audioRepeatMode = it },
                    onAudioSkipPrevious = { advanceAudioTrack(forward = false, autoEnded = false) },
                    onAudioSkipNext = { advanceAudioTrack(forward = true, autoEnded = false) },
                    onClose = {
                        if (req.isAudio) {
                            releaseBackgroundAudio()
                        } else {
                            deleteTempFileIfUnused(req.tempFilePath, keepPaths = setOf(bgAudioRequest?.tempFilePath))
                            val resumeBgPlayer = bgAudioPlayer
                            val resumeBgReq = bgAudioRequest
                            if (resumeBgPlayer != null && resumeBgReq != null) {
                                attachAudioMediaSession(resumeBgPlayer, resumeBgReq)
                            }
                        }
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
                    onSwitchRequest = { next -> executeStartPlayback(next, expandOverlay = true) },
                    onMetadataEnriched = { enriched -> syncEnrichedAudioMetadata(enriched) },
                    repository = repository,
                )
            }

            // 8. 蜂窝移动数据网络播放确认对话框
            pendingCellularRequest?.let { pendingReq ->
                AlertDialog(
                    onDismissRequest = { pendingCellularRequest = null },
                    title = { Text("当前使用移动数据网络") },
                    text = { Text("即将播放「${pendingReq.title}」，在线音视频流可能消耗较多移动数据流量，是否继续？") },
                    dismissButton = {
                        TextButton(onClick = { pendingCellularRequest = null }) {
                            Text("取消")
                        }
                    },
                    confirmButton = {
                        TextButton(
                            onClick = {
                                pendingCellularRequest = null
                                cellularConfirmedInSession = true
                                executeStartPlayback(pendingReq, expandOverlay = true)
                            },
                        ) {
                            Text("继续播放", color = colors.accent)
                        }
                    },
                )
            }
        }
    }
}

internal enum class MainTabClickAction {
    SwitchTab,
    ClearActiveStack,
    NoOp,
}

/** 根据当前激活的一级 Tab 与子栈状态判定点击底部/侧栏导航项应执行的动作。 */
internal fun resolveMainTabClick(
    currentTab: MainTab,
    clickedTab: MainTab,
    hasSubStack: Boolean,
): MainTabClickAction = when {
    clickedTab != currentTab -> MainTabClickAction.SwitchTab
    hasSubStack -> MainTabClickAction.ClearActiveStack
    else -> MainTabClickAction.NoOp
}
