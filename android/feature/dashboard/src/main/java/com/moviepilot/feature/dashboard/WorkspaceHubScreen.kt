package com.moviepilot.feature.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Hub
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.TravelExplore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeWorkspaceSkeleton
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.WorkspaceSessionSnapshot
import com.moviepilot.rustcore.PermissionsFfi
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * Android Material Design 3「更多（工作台）」一级主 Tab：
 * 顶栏右上角统一承载「设置」入口，正文按「资源与媒体流转 / 插件与工作流 / 快捷工具与系统诊断」
 * 三大分组展示全部能力磁贴（站点管理归属设置页，追剧日历与订阅广场归属订阅页），支持下拉刷新、内存快照保活与基于 `PermissionsFfi` 的细粒度 RBAC 权限过滤。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceHubScreen(
    repository: MoviePilotRepository,
    onOpenSettings: () -> Unit = {},
    onOpenAgent: () -> Unit = {},
    onOpenMusic: () -> Unit = {},
    onOpenResources: () -> Unit,
    onOpenDownloads: () -> Unit,
    onOpenFiles: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenWorkflows: () -> Unit,
    onOpenPlugins: () -> Unit,
    onOpenSites: () -> Unit = {},
    onOpenCalendar: () -> Unit = {},
    onOpenSubscribeCommunity: () -> Unit = {},
    onOpenMediaLibrary: (MediaServerLibraryDto) -> Unit = {},
    onOpenDiagnosticTab: (String) -> Unit,
    permissions: PermissionsFfi? = null,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val gridCols = AdaptiveDeviceLayout.effectiveContentWidthDp().let { w ->
        when {
            w >= 1040 -> 4
            w >= 700 -> 3
            else -> 2
        }
    }
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    val canDiscover = permissions?.discovery != false
    val canSearch = permissions?.search != false
    val canManage = permissions?.manage != false
    val isAdmin = permissions?.admin != false
    val initialCache = remember { repository.cachedWorkspace }

    var activeDownloads by remember { mutableIntStateOf(initialCache?.activeDownloads?.size ?: 0) }
    var pluginsCount by remember { mutableIntStateOf(initialCache?.pluginsCount ?: 0) }
    var workflowsCount by remember { mutableIntStateOf(initialCache?.workflows?.size ?: 0) }
    var libraries by remember { mutableStateOf(initialCache?.libraries ?: emptyList()) }
    var isInitialLoading by remember { mutableStateOf(initialCache == null) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadSummary() {
        coroutineScope {
            val dlDef = async { if (canManage) repository.fetchDownloads() else emptyList() }
            val plugDef = async { if (isAdmin) repository.fetchPlugins(installedOnly = true) else emptyList() }
            val wfDef = async { if (isAdmin) repository.fetchWorkflows() else emptyList() }
            val libDef = async { repository.fetchMediaServerLibraries() }
            val loadedDls = dlDef.await()
            val loadedPlugins = plugDef.await()
            val loadedWorkflows = wfDef.await()
            val loadedLibs = libDef.await()

            activeDownloads = loadedDls.size
            pluginsCount = loadedPlugins.size
            workflowsCount = loadedWorkflows.size
            libraries = loadedLibs
            repository.cachedWorkspace = WorkspaceSessionSnapshot(
                activeDownloads = loadedDls,
                sites = initialCache?.sites ?: emptyList(),
                pluginsCount = loadedPlugins.size,
                workflows = loadedWorkflows,
                libraries = loadedLibs,
            )
            isInitialLoading = false
            isRefreshing = false
        }
    }

    LaunchedEffect(Unit) {
        if (repository.cachedWorkspace == null) {
            loadSummary()
        }
    }

    ExpressiveTintedScaffold(
        title = "更多",
        subtitle = "资源、下载与自动化中心",
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Outlined.Settings,
                contentDescription = "设置",
                onClick = onOpenSettings,
            )
        },
    ) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { loadSummary() }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            if (isInitialLoading) {
                NativeWorkspaceSkeleton()
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = margin,
                        end = margin,
                        top = 16.dp,
                        bottom = bottomOverlayInset + 28.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    // 分组 1：资源与媒体流转（冷静蓝青色系收束；窄屏双列若为奇数项则尾项全宽承托）
                    val flowCards = buildList<@Composable (Modifier) -> Unit> {
                        if (canSearch) {
                            add { mod ->
                                WorkspaceTileCard(
                                    title = "站点资源",
                                    subtitle = "多站搜索与精细筛选",
                                    icon = Icons.Rounded.TravelExplore,
                                    accentTint = colors.info,
                                    onClick = onOpenResources,
                                    modifier = mod,
                                )
                            }
                        }
                        if (canManage) {
                            add { mod ->
                                WorkspaceTileCard(
                                    title = "下载管理",
                                    subtitle = if (activeDownloads > 0) "$activeDownloads 个任务" else "队列与限速控制",
                                    icon = Icons.Rounded.DownloadForOffline,
                                    accentTint = colors.cyan,
                                    onClick = onOpenDownloads,
                                    modifier = mod,
                                )
                            }
                            add { mod ->
                                WorkspaceTileCard(
                                    title = "文件管理",
                                    subtitle = "多存储浏览与播放",
                                    icon = Icons.Rounded.Folder,
                                    accentTint = colors.info,
                                    onClick = onOpenFiles,
                                    modifier = mod,
                                )
                            }
                            add { mod ->
                                WorkspaceTileCard(
                                    title = "整理历史",
                                    subtitle = "识别入库与记录队列",
                                    icon = Icons.Rounded.History,
                                    accentTint = colors.cyan,
                                    onClick = onOpenHistory,
                                    modifier = mod,
                                )
                            }
                        }
                        if (libraries.isNotEmpty()) {
                            add { mod ->
                                WorkspaceTileCard(
                                    title = "媒体库",
                                    subtitle = "${libraries.size} 个媒体库浏览",
                                    icon = Icons.Rounded.Folder,
                                    accentTint = colors.info,
                                    onClick = { onOpenMediaLibrary(libraries.first()) },
                                    modifier = mod,
                                )
                            }
                        }
                    }
                    if (flowCards.isNotEmpty()) {
                        item(key = "ws_media_flow") {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    "资源与媒体流转",
                                    color = colors.textSecondary,
                                    style = MaterialTheme.typography.labelLarge,
                                    modifier = Modifier.padding(start = 4.dp),
                                )
                                flowCards.chunked(gridCols).forEach { rowItems ->
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        rowItems.forEach { card -> card(Modifier.weight(1f)) }
                                        if (!(gridCols == 2 && rowItems.size == 1 && flowCards.size > 1)) {
                                            repeat(gridCols - rowItems.size) {
                                                Spacer(Modifier.weight(1f))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 分组 2：插件与工作流（面向管理员开放，单插件中心入口默认展示已安装并可切换插件商店）
                    if (isAdmin) {
                        val automationCards = listOf<@Composable (Modifier) -> Unit>(
                            { mod ->
                                WorkspaceTileCard(
                                    title = "插件中心",
                                    subtitle = if (pluginsCount > 0) "已装 $pluginsCount 款" else "插件市场与管理",
                                    icon = Icons.Rounded.Extension,
                                    accentTint = colors.cyan,
                                    onClick = onOpenPlugins,
                                    modifier = mod,
                                )
                            },
                            { mod ->
                                WorkspaceTileCard(
                                    title = "工作流",
                                    subtitle = if (workflowsCount > 0) "$workflowsCount 个编排画布" else "自动化流程编排",
                                    icon = Icons.Rounded.Hub,
                                    accentTint = colors.accent,
                                    onClick = onOpenWorkflows,
                                    modifier = mod,
                                )
                            },
                        )
                        item(key = "ws_plugins_workflows") {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    "插件与工作流",
                                    color = colors.textSecondary,
                                    style = MaterialTheme.typography.labelLarge,
                                    modifier = Modifier.padding(start = 4.dp),
                                )
                                automationCards.chunked(gridCols).forEach { rowItems ->
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        rowItems.forEach { card -> card(Modifier.weight(1f)) }
                                        repeat(gridCols - rowItems.size) {
                                            Spacer(Modifier.weight(1f))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 分组 3：快捷工具与系统诊断（管理员专属，自适应 2~4 列网格，保留全部 6 项工具）
                    if (isAdmin) {
                        item(key = "ws_system_diagnostics") {
                            val diagItems: List<@Composable (Modifier) -> Unit> = listOf(
                                { mod -> DiagnosticQuickPill("系统检查", Icons.Rounded.Shield, colors.success, mod) { onOpenDiagnosticTab("健康检查") } },
                                { mod -> DiagnosticQuickPill("定时服务", Icons.Rounded.Schedule, colors.pink, mod) { onOpenDiagnosticTab("定时服务") } },
                                { mod -> DiagnosticQuickPill("实时日志", Icons.Rounded.Terminal, colors.info, mod) { onOpenDiagnosticTab("实时日志") } },
                                { mod -> DiagnosticQuickPill("词表管理", Icons.Rounded.Book, colors.cyan, mod) { onOpenDiagnosticTab("词表") } },
                                { mod -> DiagnosticQuickPill("名称识别", Icons.Rounded.Search, colors.brand, mod) { onOpenDiagnosticTab("名称识别") } },
                                { mod -> DiagnosticQuickPill("网络测试", Icons.Rounded.Language, colors.warning, mod) { onOpenDiagnosticTab("网络测试") } },
                            )
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    "快捷工具与系统诊断",
                                    color = colors.textSecondary,
                                    style = MaterialTheme.typography.labelLarge,
                                    modifier = Modifier.padding(start = 4.dp),
                                )
                                CinematicPanel(padding = 12.dp, showsShadow = false) {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        diagItems.chunked(gridCols).forEach { rowItems ->
                                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                rowItems.forEach { pill -> pill(Modifier.weight(1f)) }
                                                repeat(gridCols - rowItems.size) {
                                                    Spacer(Modifier.weight(1f))
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
        }
    }
}

@Composable
private fun WorkspaceTileCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    accentTint: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(colors.cardRadiusDp.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 0.dp,
        modifier = modifier.heightIn(min = 92.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(accentTint.copy(alpha = if (colors.isDark) 0.22f else 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = title, tint = accentTint, modifier = Modifier.size(21.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = title,
                    color = colors.textPrimary,
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = subtitle,
                    color = colors.textSecondary,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun DiagnosticQuickPill(
    title: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = modifier.heightIn(min = 48.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, contentDescription = title, tint = tint, modifier = Modifier.size(18.dp))
            Text(title, color = colors.textPrimary, style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp), maxLines = 1)
        }
    }
}
