package com.moviepilot.feature.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.DownloadForOffline
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Hub
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.TravelExplore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.rustbridge.DashboardStatsDto
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.WorkspaceSessionSnapshot
import com.moviepilot.rustcore.PermissionsFfi
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * Android Material Design 3「更多（工作台）」一级主 Tab：
 * 将下载、站点资源、文件管理、整理历史、工作流、插件中心、站点管理、追剧日历与系统诊断以高清晰 Material 3 Tonal 卡片一屏呈现，
 * 顶部实时汇总下载器双速与活跃计数，支持下拉刷新、内存快照保活与基于 `PermissionsFfi` 的细粒度 RBAC 权限过滤。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceHubScreen(
    repository: MoviePilotRepository,
    onOpenSearch: () -> Unit,
    onOpenResources: () -> Unit,
    onOpenDownloads: () -> Unit,
    onOpenFiles: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenWorkflows: () -> Unit,
    onOpenPlugins: () -> Unit,
    onOpenSites: () -> Unit,
    onOpenCalendar: () -> Unit,
    onOpenSubscribeCommunity: () -> Unit,
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

    val canSearch = permissions?.search != false
    val canSubscribe = permissions?.subscribe != false
    val canManage = permissions?.manage != false
    val isAdmin = permissions?.admin != false
    val initialCache = remember { repository.cachedWorkspace }

    var stats by remember { mutableStateOf(initialCache?.stats ?: DashboardStatsDto()) }
    var activeDownloads by remember { mutableIntStateOf(initialCache?.activeDownloads?.size ?: 0) }
    var sitesCount by remember { mutableIntStateOf(initialCache?.sites?.count { it.isActive } ?: 0) }
    var pluginsCount by remember { mutableIntStateOf(initialCache?.pluginsCount ?: 0) }
    var workflowsCount by remember { mutableIntStateOf(initialCache?.workflows?.size ?: 0) }
    var libraries by remember { mutableStateOf(initialCache?.libraries ?: emptyList()) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadSummary() {
        coroutineScope {
            val sDef = async { repository.fetchDashboardStats() }
            val dlDef = async { if (canManage) repository.fetchDownloads() else emptyList() }
            val siteDef = async { if (isAdmin) repository.fetchSites() else emptyList() }
            val plugDef = async { if (isAdmin) repository.fetchPlugins(installedOnly = true) else emptyList() }
            val wfDef = async { if (isAdmin) repository.fetchWorkflows() else emptyList() }
            val libDef = async { repository.fetchMediaServerLibraries() }
            val loadedStats = sDef.await()
            val loadedDls = dlDef.await()
            val loadedSites = siteDef.await()
            val loadedPlugins = plugDef.await()
            val loadedWorkflows = wfDef.await()
            val loadedLibs = libDef.await()

            stats = loadedStats
            activeDownloads = loadedDls.size
            sitesCount = loadedSites.count { it.isActive }
            pluginsCount = loadedPlugins.size
            workflowsCount = loadedWorkflows.size
            libraries = loadedLibs
            repository.cachedWorkspace = WorkspaceSessionSnapshot(
                stats = loadedStats,
                activeDownloads = loadedDls,
                sites = loadedSites,
                pluginsCount = loadedPlugins.size,
                workflows = loadedWorkflows,
                libraries = loadedLibs,
            )
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
            if (canSearch) {
                ExpressiveHeaderActionButton(
                    icon = Icons.Rounded.Search,
                    contentDescription = "全局搜索",
                    onClick = onOpenSearch,
                )
            }
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
                // 实时传输与任务状态总览卡
                if (canManage) {
                    item(key = "ws_runtime_overview") {
                        CinematicPanel(
                            padding = 16.dp,
                            modifier = Modifier.clickable(onClick = onOpenDownloads),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text("实时运行概览", color = colors.textPrimary, style = MaterialTheme.typography.titleMedium)
                                    NativeAdaptiveBadge(
                                        text = if (activeDownloads > 0) "$activeDownloads 任务活跃" else "下载空闲",
                                        tint = if (activeDownloads > 0) colors.success else colors.textMuted,
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    SpeedMiniMetric(
                                        icon = Icons.Rounded.ArrowDownward,
                                        label = "下载速度",
                                        value = fmtSpeedRate(stats.downloadSpeed),
                                        tint = colors.success,
                                        modifier = Modifier.weight(1f),
                                    )
                                    SpeedMiniMetric(
                                        icon = Icons.Rounded.ArrowUpward,
                                        label = "上传速度",
                                        value = fmtSpeedRate(stats.uploadSpeed),
                                        tint = colors.info,
                                        modifier = Modifier.weight(1f),
                                    )
                                }
                            }
                        }
                    }
                }

                // 分组 1：资源与媒体流转（按 RBAC search / manage / admin 动态组装双列卡片）
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
                    if (isAdmin) {
                        add { mod ->
                            WorkspaceTileCard(
                                title = "站点管理",
                                subtitle = if (sitesCount > 0) "$sitesCount 站点启用" else "流量趋势与连通测速",
                                icon = Icons.Rounded.Language,
                                accentTint = colors.success,
                                onClick = onOpenSites,
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
                                accentTint = colors.success,
                                onClick = onOpenDownloads,
                                modifier = mod,
                            )
                        }
                        add { mod ->
                            WorkspaceTileCard(
                                title = "文件管理",
                                subtitle = "多存储浏览与播放",
                                icon = Icons.Rounded.Folder,
                                accentTint = colors.warning,
                                onClick = onOpenFiles,
                                modifier = mod,
                            )
                        }
                        add { mod ->
                            WorkspaceTileCard(
                                title = "整理历史",
                                subtitle = "识别入库与记录队列",
                                icon = Icons.Rounded.History,
                                accentTint = colors.brand,
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
                                accentTint = colors.accent,
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
                                    repeat(gridCols - rowItems.size) {
                                        Spacer(Modifier.weight(1f))
                                    }
                                }
                            }
                        }
                    }
                }

                // 分组 2：插件与工作流（管理员专属）
                if (isAdmin) {
                    item(key = "ws_plugins_workflows") {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                "插件与工作流",
                                color = colors.textSecondary,
                                style = MaterialTheme.typography.labelLarge,
                                modifier = Modifier.padding(start = 4.dp),
                            )
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                WorkspaceTileCard(
                                    title = "插件中心",
                                    subtitle = if (pluginsCount > 0) "已装 $pluginsCount 款" else "插件市场与管理",
                                    icon = Icons.Rounded.Extension,
                                    accentTint = colors.cyan,
                                    onClick = onOpenPlugins,
                                    modifier = Modifier.weight(1f),
                                )
                                WorkspaceTileCard(
                                    title = "工作流",
                                    subtitle = if (workflowsCount > 0) "$workflowsCount 个编排画布" else "自动化流程编排",
                                    icon = Icons.Rounded.Hub,
                                    accentTint = colors.accent,
                                    onClick = onOpenWorkflows,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }

                // 分组 3：追剧与广场（订阅权限可见）
                if (canSubscribe) {
                    item(key = "ws_subscribe_community") {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                "追剧与广场",
                                color = colors.textSecondary,
                                style = MaterialTheme.typography.labelLarge,
                                modifier = Modifier.padding(start = 4.dp),
                            )
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                WorkspaceTileCard(
                                    title = "追剧日历",
                                    subtitle = "本周更新排期",
                                    icon = Icons.Rounded.CalendarMonth,
                                    accentTint = colors.pink,
                                    onClick = onOpenCalendar,
                                    modifier = Modifier.weight(1f),
                                )
                                WorkspaceTileCard(
                                    title = "订阅广场",
                                    subtitle = "热门社区共享订阅",
                                    icon = Icons.Rounded.LocalFireDepartment,
                                    accentTint = colors.warning,
                                    onClick = onOpenSubscribeCommunity,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }

                // 分组 4：系统诊断（管理员专属，自适应 2~4 列网格）
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
                                "系统诊断",
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
private fun SpeedMiniMetric(
    icon: ImageVector,
    label: String,
    value: String,
    tint: Color,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Column {
            Text(label, color = colors.textMuted, fontSize = 11.sp)
            Text(value, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1)
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

private fun fmtSpeedRate(bytesPerSec: Double): String {
    val mb = bytesPerSec / (1024.0 * 1024.0)
    if (mb >= 1.0) return String.format("%.1f MB/s", mb)
    val kb = bytesPerSec / 1024.0
    if (kb >= 1.0) return String.format("%.0f KB/s", kb)
    return "0 KB/s"
}
