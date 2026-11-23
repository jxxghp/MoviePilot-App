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
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.rustbridge.DashboardStatsDto
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * Android Material Design 3「工具（工作台）」一级主 Tab（方案 A）：
 * 取代 iOS 隐藏的“重复点按底栏弹出 8 项菜单”，将下载、站点资源、文件管理、整理历史、
 * 工作流、插件中心、站点管理、追剧日历与系统诊断以高清晰 Material 3 Tonal 卡片一屏呈现，
 * 顶部实时汇总下载器双速与活跃计数，支持下拉刷新与顶栏全局搜索。
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
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    var stats by remember { mutableStateOf(DashboardStatsDto()) }
    var activeDownloads by remember { mutableIntStateOf(0) }
    var sitesCount by remember { mutableIntStateOf(0) }
    var pluginsCount by remember { mutableIntStateOf(0) }
    var workflowsCount by remember { mutableIntStateOf(0) }
    var libraries by remember { mutableStateOf<List<MediaServerLibraryDto>>(emptyList()) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadSummary() {
        coroutineScope {
            val sDef = async { repository.fetchDashboardStats() }
            val dlDef = async { repository.fetchDownloads() }
            val siteDef = async { repository.fetchSites() }
            val plugDef = async { repository.fetchPlugins(installedOnly = true) }
            val wfDef = async { repository.fetchWorkflows() }
            val libDef = async { repository.fetchMediaServerLibraries() }
            stats = sDef.await()
            activeDownloads = dlDef.await().size
            sitesCount = siteDef.await().count { it.isActive }
            pluginsCount = plugDef.await().size
            workflowsCount = wfDef.await().size
            libraries = libDef.await()
            isRefreshing = false
        }
    }

    LaunchedEffect(Unit) { loadSummary() }

    val topBlurAlpha by remember {
        derivedStateOf {
            if (listState.firstVisibleItemIndex > 0) 1f
            else (listState.firstVisibleItemScrollOffset / 90f).coerceIn(0f, 1f)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { loadSummary() }
            },
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                item {
                    NativeGlassTopBar(
                        title = "更多",
                        showTopBlur = false,
                        trailing = {
                            IconButton(onClick = onOpenSearch, modifier = Modifier.size(48.dp)) {
                                Icon(
                                    imageVector = Icons.Rounded.Search,
                                    contentDescription = "全局搜索",
                                    tint = colors.textPrimary,
                                    modifier = Modifier.size(24.dp),
                                )
                            }
                        },
                    )
                }

                // 实时传输与任务状态总览卡
                item {
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

                // 分组 1：资源与媒体管理
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            "资源与文件管理",
                            color = colors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            WorkspaceTileCard(
                                title = "站点资源",
                                subtitle = "9 维精准筛选",
                                icon = Icons.Rounded.TravelExplore,
                                accentTint = colors.info,
                                onClick = onOpenResources,
                                modifier = Modifier.weight(1f),
                            )
                            WorkspaceTileCard(
                                title = "下载管理",
                                subtitle = if (activeDownloads > 0) "$activeDownloads 个任务" else "队列与限速",
                                icon = Icons.Rounded.DownloadForOffline,
                                accentTint = colors.success,
                                onClick = onOpenDownloads,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            WorkspaceTileCard(
                                title = "文件管理",
                                subtitle = "多存储与本机播放",
                                icon = Icons.Rounded.Folder,
                                accentTint = colors.warning,
                                onClick = onOpenFiles,
                                modifier = Modifier.weight(1f),
                            )
                            WorkspaceTileCard(
                                title = "整理历史",
                                subtitle = "识别记录与队列",
                                icon = Icons.Rounded.History,
                                accentTint = colors.brand,
                                onClick = onOpenHistory,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }

                // 分组 2：自动化、站点与插件生态
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            "自动化与扩展生态",
                            color = colors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            WorkspaceTileCard(
                                title = "工作流",
                                subtitle = if (workflowsCount > 0) "$workflowsCount 个节点画布" else "画布与社区分享",
                                icon = Icons.Rounded.Hub,
                                accentTint = colors.accent,
                                onClick = onOpenWorkflows,
                                modifier = Modifier.weight(1f),
                            )
                            WorkspaceTileCard(
                                title = "插件中心",
                                subtitle = if (pluginsCount > 0) "已装 $pluginsCount 款" else "原生与 Vue 宿主",
                                icon = Icons.Rounded.Extension,
                                accentTint = colors.cyan,
                                onClick = onOpenPlugins,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            WorkspaceTileCard(
                                title = "站点管理",
                                subtitle = if (sitesCount > 0) "$sitesCount 站点启用" else "流量趋势与测速",
                                icon = Icons.Rounded.Language,
                                accentTint = colors.success,
                                onClick = onOpenSites,
                                modifier = Modifier.weight(1f),
                            )
                            WorkspaceTileCard(
                                title = "追剧日历",
                                subtitle = "本周更新排期",
                                icon = Icons.Rounded.CalendarMonth,
                                accentTint = colors.pink,
                                onClick = onOpenCalendar,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }

                // 分组 3：发现广场与系统诊断工具
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(
                            "社区与系统诊断",
                            color = colors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                        CinematicPanel(padding = 12.dp, showsShadow = false) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (libraries.isNotEmpty()) {
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        DiagnosticQuickPill(
                                            title = "媒体库浏览 (${libraries.size})",
                                            icon = Icons.Rounded.Folder,
                                            tint = colors.accent,
                                            modifier = Modifier.weight(1f),
                                        ) { onOpenMediaLibrary(libraries.first()) }
                                        DiagnosticQuickPill("订阅广场", Icons.Rounded.LocalFireDepartment, colors.warning, Modifier.weight(1f), onOpenSubscribeCommunity)
                                    }
                                } else {
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        DiagnosticQuickPill("订阅广场", Icons.Rounded.LocalFireDepartment, colors.warning, Modifier.weight(1f), onOpenSubscribeCommunity)
                                        DiagnosticQuickPill("系统健康", Icons.Rounded.Shield, colors.success, Modifier.weight(1f)) { onOpenDiagnosticTab("健康检查") }
                                    }
                                }
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    DiagnosticQuickPill("实时日志", Icons.Rounded.Terminal, colors.info, Modifier.weight(1f)) { onOpenDiagnosticTab("实时日志") }
                                    DiagnosticQuickPill("定时服务", Icons.Rounded.Schedule, colors.pink, Modifier.weight(1f)) { onOpenDiagnosticTab("定时服务") }
                                }
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    DiagnosticQuickPill("识别与词表", Icons.Rounded.Book, colors.cyan, Modifier.weight(1f)) { onOpenDiagnosticTab("词表") }
                                    DiagnosticQuickPill("网络测试", Icons.Rounded.Language, colors.brand, Modifier.weight(1f)) { onOpenDiagnosticTab("网络测试") }
                                }
                            }
                        }
                    }
                }
            }
        }

        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = topBlurAlpha,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )
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
        shape = RoundedCornerShape(16.dp),
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
