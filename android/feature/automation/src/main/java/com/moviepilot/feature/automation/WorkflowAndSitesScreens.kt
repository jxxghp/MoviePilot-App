package com.moviepilot.feature.automation

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.automirrored.rounded.ShowChart
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.WifiTethering
import androidx.compose.material.icons.rounded.ZoomIn
import androidx.compose.material.icons.rounded.ZoomOut
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassFab
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativePrimaryTabBar
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SiteItemDto
import com.moviepilot.rustbridge.SiteUserDataPointDto
import com.moviepilot.rustbridge.WorkflowActionDto
import com.moviepilot.rustbridge.WorkflowFlowEdgeDto
import com.moviepilot.rustbridge.WorkflowItemDto
import com.moviepilot.rustbridge.WorkflowShareDto
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/** Android Material 3 工作流中心：HorizontalPager 左右滑切「我的工作流 / 社区分享」+ 下拉刷新 + 右下角单手 FAB。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkflowsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onOpenCanvas: (WorkflowItemDto) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    val pagerState = rememberPagerState(initialPage = 0, pageCount = { 2 })

    var workflows by remember { mutableStateOf<List<WorkflowItemDto>>(emptyList()) }
    var shares by remember { mutableStateOf<List<WorkflowShareDto>>(emptyList()) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadPage(page: Int) {
        if (page == 0) {
            val fetched = repository.fetchWorkflows()
            workflows = fetched.ifEmpty { sampleWorkflows() }
        } else {
            shares = repository.fetchWorkflowShares(1)
        }
        isRefreshing = false
    }

    LaunchedEffect(Unit) {
        loadPage(0)
        loadPage(1)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            NativeGlassTopBar(title = "工作流", onBack = onBack)
            NativePrimaryTabBar(
                tabs = listOf("我的工作流 (${workflows.size})", "社区分享 (${shares.size})"),
                selectedIndex = pagerState.currentPage,
                onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
            )
            Spacer(Modifier.height(10.dp))
            HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { pageIdx ->
                PullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        scope.launch { loadPage(pageIdx) }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn(
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        if (pageIdx == 0) {
                            items(workflows, key = { it.id }) { wf ->
                                val cronDesc = remember(wf.timer) { RustCoreBridge.analyzeCron(wf.timer).descriptionZh }
                                CinematicPanel(
                                    padding = 16.dp,
                                    modifier = Modifier.clickable { onOpenCanvas(wf) },
                                ) {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                            Text(wf.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                            NativeAdaptiveBadge(if (wf.state == "R") "运行中" else "已就绪", tint = if (wf.state == "R") colors.success else colors.accent)
                                        }
                                        if (wf.description.isNotBlank()) {
                                            Text(wf.description, color = colors.textSecondary, fontSize = 13.sp)
                                        }
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                            Text("${wf.actions.size} 节点 · $cronDesc", color = colors.textMuted, fontSize = 12.sp)
                                            NativeAdaptivePill("打开画布", selected = false, icon = Icons.Rounded.PlayArrow, onClick = { onOpenCanvas(wf) })
                                        }
                                    }
                                }
                            }
                        } else {
                            items(shares, key = { it.id }) { sh ->
                                CinematicPanel(padding = 16.dp, showsShadow = false) {
                                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                            Text(sh.shareTitle.ifBlank { sh.name }, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                            NativeAdaptiveBadge("🔥 ${sh.count}", tint = colors.warning)
                                        }
                                        if (sh.shareComment.isNotBlank() || sh.description.isNotBlank()) {
                                            Text(sh.shareComment.ifBlank { sh.description }, color = colors.textSecondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                        }
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                            Text("作者：${sh.shareUser.ifBlank { "社区用户" }}", color = colors.textMuted, fontSize = 12.sp)
                                            Text(sh.date.take(10), color = colors.textMuted, fontSize = 12.sp)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        NativeGlassFab(
            icon = Icons.Rounded.Add,
            label = "新建工作流",
            onClick = {
                val draft = sampleWorkflows().first().copy(id = 0, name = "新建自动化工作流")
                onOpenCanvas(draft)
                scope.launch { snackbar?.showSnackbar("已进入新建工作流节点画布") }
            },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = margin, bottom = 20.dp),
        )
    }
}

/**
 * 纯 Compose 原生工作流节点画布（1:1 对标 iOS 黄金截图 `native-v2-live-workflow-canvas.jpg`）：
 * 支持双指缩放和平移、点阵背景、纵/横智能贝塞尔连线、玻璃节点卡片与底部实时磨砂属性检视浮卡。
 */
@Composable
fun WorkflowCanvasScreen(
    workflow: WorkflowItemDto,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val density = LocalDensity.current
    val nodeWidthDp = 172f
    val nodeHeightDp = 90f
    val nodeWidthPx = with(density) { nodeWidthDp.dp.toPx() }
    val nodeHeightPx = with(density) { nodeHeightDp.dp.toPx() }
    val resolvedActions = remember(workflow.actions) { resolveNonOverlappingNodes(workflow.actions) }

    var scale by remember { mutableFloatStateOf(0.86f) }
    var panX by remember { mutableFloatStateOf(with(density) { 18.dp.toPx() }) }
    var panY by remember { mutableFloatStateOf(with(density) { 42.dp.toPx() }) }
    var selectedNode by remember { mutableStateOf(resolvedActions.firstOrNull()) }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            NativeGlassTopBar(
                title = workflow.name,
                onBack = onBack,
                trailing = {
                    CinematicCircleButton(Icons.Rounded.Add, "新增节点", {})
                },
            )
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Rounded.AccountTree, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(16.dp))
                    Text("${resolvedActions.size} 节点 · ${workflow.flows.size} 连线", color = colors.textSecondary, fontSize = 13.sp)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    IconButton(onClick = { scale = (scale - 0.12f).coerceAtLeast(0.45f) }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Rounded.ZoomOut, contentDescription = "缩小", tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                    }
                    NativeAdaptiveBadge("${(scale * 100).roundToInt()}%")
                    IconButton(onClick = { scale = (scale + 0.12f).coerceAtMost(1.8f) }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Rounded.ZoomIn, contentDescription = "放大", tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                    }
                }
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(0.45f, 1.8f)
                            panX += pan.x
                            panY += pan.y
                        }
                    },
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val step = 28.dp.toPx() * scale
                    if (step > 8f) {
                        val dotColor = if (colors.isDark) Color.White.copy(alpha = 0.12f) else Color.Black.copy(alpha = 0.10f)
                        var x = ((panX % step) + step) % step
                        while (x < size.width) {
                            var y = ((panY % step) + step) % step
                            while (y < size.height) {
                                drawCircle(dotColor, radius = 1.6f, center = Offset(x, y))
                                y += step
                            }
                            x += step
                        }
                    }

                    val nodeMap = resolvedActions.associateBy { it.id }
                    workflow.flows.forEach { edge ->
                        val src = nodeMap[edge.source] ?: return@forEach
                        val dst = nodeMap[edge.target] ?: return@forEach
                        val isHorizontal = dst.x > src.x + nodeWidthDp * 0.65f
                        val sx: Float
                        val sy: Float
                        val ex: Float
                        val ey: Float
                        val path = Path()
                        if (isHorizontal) {
                            sx = (src.x.dp.toPx() + nodeWidthPx) * scale + panX
                            sy = (src.y.dp.toPx() + nodeHeightPx * 0.48f) * scale + panY
                            ex = dst.x.dp.toPx() * scale + panX
                            ey = (dst.y.dp.toPx() + nodeHeightPx * 0.48f) * scale + panY
                            val ctrlSpan = ((ex - sx) * 0.48f).coerceAtLeast(48.dp.toPx() * scale)
                            path.moveTo(sx, sy)
                            path.cubicTo(sx + ctrlSpan, sy, ex - ctrlSpan, ey, ex, ey)
                        } else {
                            sx = (src.x.dp.toPx() + nodeWidthPx * 0.5f) * scale + panX
                            sy = (src.y.dp.toPx() + nodeHeightPx * 0.94f) * scale + panY
                            ex = (dst.x.dp.toPx() + nodeWidthPx * 0.5f) * scale + panX
                            ey = dst.y.dp.toPx() * scale + panY
                            val ctrlSpan = ((ey - sy) * 0.52f).coerceAtLeast(36.dp.toPx() * scale)
                            path.moveTo(sx, sy)
                            path.cubicTo(sx, sy + ctrlSpan, ex, ey - ctrlSpan, ex, ey)
                        }
                        drawPath(
                            path = path,
                            brush = Brush.linearGradient(listOf(colors.accent, colors.pink), start = Offset(sx, sy), end = Offset(ex, ey)),
                            style = Stroke(width = 3.dp.toPx() * scale, cap = StrokeCap.Round),
                        )
                        drawCircle(colors.accent, radius = 4.5.dp.toPx() * scale, center = Offset(sx, sy))
                        drawCircle(colors.pink, radius = 4.5.dp.toPx() * scale, center = Offset(ex, ey))
                    }
                }

                resolvedActions.forEach { node ->
                    val isSelected = selectedNode?.id == node.id
                    Box(
                        modifier = Modifier
                            .offset {
                                IntOffset(
                                    (with(density) { node.x.dp.toPx() } * scale + panX).roundToInt(),
                                    (with(density) { node.y.dp.toPx() } * scale + panY).roundToInt(),
                                )
                            }
                            .graphicsLayer {
                                transformOrigin = TransformOrigin(0f, 0f)
                                scaleX = scale
                                scaleY = scale
                            }
                            .width(nodeWidthDp.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(
                                if (isSelected) {
                                    colors.accent.copy(alpha = if (colors.isDark) 0.36f else 0.20f)
                                } else {
                                    if (colors.isDark) Color(0xCC282236) else Color(0xEEFFFFFF)
                                },
                            )
                            .border(
                                width = if (isSelected) 1.5.dp else 0.85.dp,
                                color = if (isSelected) colors.accent else colors.chipBorder,
                                shape = RoundedCornerShape(16.dp),
                            )
                            .clickable { selectedNode = node }
                            .padding(12.dp),
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Box(Modifier.size(7.dp).clip(CircleShape).background(if (isSelected) colors.accent else colors.success))
                                Text(node.name, color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            }
                            Text(node.type, color = colors.textSecondary, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
                            if (node.description.isNotBlank()) {
                                Text(node.description, color = colors.textMuted, fontSize = 11.sp, maxLines = 2)
                            }
                        }
                    }
                }
            }
        }

        selectedNode?.let { node ->
            CinematicPanel(
                padding = 16.dp,
                elevatedBlur = true,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(start = 18.dp, end = 18.dp, bottom = 108.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Column {
                            Text(node.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text("${node.type} · 参数 ${node.paramCount} 项", color = colors.textSecondary, fontSize = 12.sp)
                        }
                        IconButton(onClick = { selectedNode = null }, modifier = Modifier.size(28.dp)) {
                            Icon(Icons.Rounded.Close, contentDescription = "关闭", tint = colors.textMuted)
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NativeAdaptivePill("编辑参数", selected = true, icon = Icons.Rounded.Tune, onClick = {})
                        NativeAdaptivePill("连线", selected = false, icon = Icons.Rounded.AccountTree, onClick = {})
                        Spacer(Modifier.weight(1f))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Rounded.Delete, contentDescription = "删除", tint = colors.danger, modifier = Modifier.size(16.dp))
                            Text("删除", color = colors.danger, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Android Material 3 站点管理与双向流量图示：
 * 真实站点图标、聚合实时上传下载量、双向流量条、下拉刷新、尾部 `⋮` 溢出菜单与 13 天历史流量面积图弹窗。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SitesScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current

    var sites by remember { mutableStateOf<List<SiteItemDto>>(emptyList()) }
    var isRefreshing by remember { mutableStateOf(false) }
    var selectedSiteForData by remember { mutableStateOf<SiteItemDto?>(null) }
    val loadedIcons = remember { mutableStateMapOf<Int, String>() }

    suspend fun loadSites() {
        sites = repository.fetchSites()
        isRefreshing = false
        sites.take(20).forEach { s ->
            if (!loadedIcons.containsKey(s.id)) {
                scope.launch {
                    repository.fetchSiteIcon(s.id)?.let { loadedIcons[s.id] = it }
                }
            }
        }
    }

    LaunchedEffect(Unit) { loadSites() }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            NativeGlassTopBar(
                title = "站点管理 (${sites.size})",
                onBack = onBack,
            )

            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { loadSites() }
                },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                LazyColumn(
                    contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 96.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(sites, key = { it.id }) { site ->
                        val iconData = loadedIcons[site.id] ?: site.iconUrl
                        val totalTraffic = (site.uploadBytes + site.downloadBytes).coerceAtLeast(1.0)
                        val hasTraffic = site.uploadBytes > 0.0 || site.downloadBytes > 0.0
                        val upFraction = if (hasTraffic) (site.uploadBytes / totalTraffic).toFloat().coerceIn(0.02f, 0.98f) else 0.5f
                        var rowMenuOpen by remember { mutableStateOf(false) }

                        CinematicPanel(
                            padding = 16.dp,
                            modifier = Modifier.clickable { selectedSiteForData = site },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    Box(
                                        modifier = Modifier
                                            .size(44.dp)
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(Brush.linearGradient(listOf(Color(0xFF42A5F5), Color(0xFF2962FF)))),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(Icons.Rounded.Language, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
                                        if (!iconData.isNullOrBlank()) {
                                            AsyncImage(
                                                model = iconData,
                                                contentDescription = site.name,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)),
                                            )
                                        }
                                    }
                                    Spacer(Modifier.width(12.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Text(site.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                            NativeAdaptiveBadge(if (site.isActive) "已启用" else "已停用", tint = if (site.isActive) colors.success else colors.warning)
                                        }
                                        Text("${site.domain}  优先级 ${site.pri}", color = colors.textMuted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    NativeAdaptivePill("测试", selected = false, icon = Icons.Rounded.WifiTethering, onClick = {
                                        scope.launch {
                                            val (ok, msg) = repository.testSiteConnection(site.id)
                                            snackbar?.showSnackbar("站点「${site.name}」${if (ok) "连通正常" else "检测失败"}：$msg")
                                        }
                                    })
                                    Box {
                                        IconButton(onClick = { rowMenuOpen = true }, modifier = Modifier.size(32.dp)) {
                                            Icon(Icons.Rounded.MoreVert, contentDescription = "更多操作", tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                        }
                                        DropdownMenu(expanded = rowMenuOpen, onDismissRequest = { rowMenuOpen = false }) {
                                            DropdownMenuItem(
                                                text = { Text("查看 13 天流量趋势") },
                                                leadingIcon = { Icon(Icons.AutoMirrored.Rounded.ShowChart, contentDescription = null) },
                                                onClick = {
                                                    rowMenuOpen = false
                                                    selectedSiteForData = site
                                                },
                                            )
                                            DropdownMenuItem(
                                                text = { Text("检测站点连通性") },
                                                leadingIcon = { Icon(Icons.Rounded.WifiTethering, contentDescription = null) },
                                                onClick = {
                                                    rowMenuOpen = false
                                                    scope.launch {
                                                        val (ok, msg) = repository.testSiteConnection(site.id)
                                                        snackbar?.showSnackbar("站点「${site.name}」${if (ok) "连通正常" else "检测失败"}：$msg")
                                                    }
                                                },
                                            )
                                        }
                                    }
                                }

                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Text("↑ ${formatTraffic(site.uploadBytes)}", color = colors.success, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                        Text("↓ ${formatTraffic(site.downloadBytes)}", color = colors.pink, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                    val rightStat = buildList {
                                        if (site.ratio > 0) add("分享率 ${String.format("%.2f", site.ratio)}")
                                        if (site.seedingCount > 0) add("做种 ${site.seedingCount}")
                                    }.joinToString("  ")
                                    if (rightStat.isNotBlank()) {
                                        Text(rightStat, color = colors.textSecondary, fontSize = 12.sp)
                                    }
                                }

                                if (hasTraffic) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth().height(5.dp),
                                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                                    ) {
                                        if (site.uploadBytes > 0) {
                                            Box(
                                                modifier = Modifier
                                                    .weight(upFraction)
                                                    .height(5.dp)
                                                    .clip(CircleShape)
                                                    .background(Brush.horizontalGradient(listOf(colors.success, colors.brand))),
                                            )
                                        }
                                        if (site.downloadBytes > 0) {
                                            Box(
                                                modifier = Modifier
                                                    .weight((1f - upFraction).coerceAtLeast(0.02f))
                                                    .height(5.dp)
                                                    .clip(CircleShape)
                                                    .background(colors.pink),
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        NativeGlassFab(
            icon = Icons.Rounded.Add,
            label = "同步站点",
            onClick = {
                isRefreshing = true
                scope.launch {
                    loadSites()
                    snackbar?.showSnackbar("已刷新 ${sites.size} 个站点最新状态与流量数据")
                }
            },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = margin, bottom = 20.dp),
        )
    }

    selectedSiteForData?.let { site ->
        SiteDataDetailSheet(
            site = site,
            iconData = loadedIcons[site.id] ?: site.iconUrl,
            repository = repository,
            onDismiss = { selectedSiteForData = null },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SiteDataDetailSheet(
    site: SiteItemDto,
    iconData: String?,
    repository: MoviePilotRepository,
    onDismiss: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    var history by remember(site.id) { mutableStateOf<List<SiteUserDataPointDto>>(emptyList()) }
    var refreshing by remember { mutableStateOf(false) }

    suspend fun loadHistory() {
        refreshing = true
        history = repository.fetchSiteUserDataHistory(site.id)
        refreshing = false
    }

    LaunchedEffect(site.id) { loadHistory() }

    val latest = history.lastOrNull()
    val upBytes = latest?.uploadBytes ?: site.uploadBytes
    val dlBytes = latest?.downloadBytes ?: site.downloadBytes
    val ratio = latest?.ratio ?: site.ratio
    val seeding = latest?.seedingCount ?: site.seedingCount
    val seedingSize = latest?.seedingSizeBytes ?: site.seedingSizeBytes
    val bonus = latest?.bonus ?: site.bonus
    val level = latest?.userLevel?.ifBlank { null } ?: site.userLevel.ifBlank { "--" }
    val username = latest?.username?.ifBlank { null } ?: site.username.ifBlank { "--" }
    val joinAt = latest?.joinAt?.ifBlank { null } ?: site.joinAt.ifBlank { "--" }
    val updatedDay = latest?.updatedDay?.ifBlank { null } ?: site.updatedDay.ifBlank { "--" }

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                CinematicCircleButton(Icons.Rounded.Close, "关闭", onDismiss, size = 38.dp)
                Text(
                    "站点数据",
                    color = colors.textPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                Spacer(Modifier.width(38.dp))
            }

            // 站点头部卡 + 刷新数据按钮
            CinematicPanel(padding = 14.dp) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(46.dp).clip(RoundedCornerShape(12.dp)).background(Color(0xFF2962FF)),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (!iconData.isNullOrBlank()) {
                            AsyncImage(model = iconData, contentDescription = site.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                        } else {
                            Icon(Icons.Rounded.Language, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
                        }
                    }
                    Spacer(Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(site.name, color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                        Text(site.url.ifBlank { "https://${site.domain}/" }, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    NativeAdaptivePill(
                        title = if (refreshing) "刷新中" else "刷新数据",
                        selected = true,
                        icon = Icons.Rounded.Refresh,
                        onClick = { scope.launch { loadHistory() } },
                    )
                }
            }

            // 2×3 指标统计卡
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SiteMetricBox("上传量", formatTraffic(upBytes), colors.success, Modifier.weight(1f))
                SiteMetricBox("下载量", formatTraffic(dlBytes), colors.warning, Modifier.weight(1f))
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SiteMetricBox("分享率", String.format("%.2f", ratio), colors.info, Modifier.weight(1f))
                SiteMetricBox("做种数 / 体积", "$seeding · ${formatTraffic(seedingSize)}", colors.brand, Modifier.weight(1f))
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SiteMetricBox("魔力 / 积分", String.format("%.1f", bonus), colors.warning, Modifier.weight(1f))
                SiteMetricBox("用户等级", level, colors.cyan, Modifier.weight(1f))
            }

            // 历史流量趋势双曲线面积图
            val points = history.ifEmpty {
                listOf(
                    SiteUserDataPointDto(uploadBytes = upBytes, downloadBytes = dlBytes, updatedDay = updatedDay),
                    SiteUserDataPointDto(uploadBytes = upBytes, downloadBytes = dlBytes, updatedDay = updatedDay),
                )
            }
            CinematicPanel(padding = 16.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.AutoMirrored.Rounded.ShowChart, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                            Text("历史流量趋势", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        }
                        Text("最近 ${points.size} 天 · GB", color = colors.textMuted, fontSize = 12.sp)
                    }

                    val gb = 1024.0 * 1024.0 * 1024.0
                    val upGb = points.map { (it.uploadBytes / gb).toFloat() }
                    val dlGb = points.map { (it.downloadBytes / gb).toFloat() }
                    val maxY = maxOf(upGb.maxOrNull() ?: 1f, dlGb.maxOrNull() ?: 1f, 10f) * 1.18f

                    Row(modifier = Modifier.fillMaxWidth().height(160.dp)) {
                        Column(
                            modifier = Modifier.width(42.dp).height(160.dp),
                            verticalArrangement = Arrangement.SpaceBetween,
                        ) {
                            listOf(maxY, maxY * 0.75f, maxY * 0.5f, maxY * 0.25f, 0f).forEach { v ->
                                Text("${v.roundToInt()}", color = colors.textMuted, fontSize = 10.sp)
                            }
                        }
                        Canvas(modifier = Modifier.weight(1f).height(160.dp)) {
                            val w = size.width
                            val h = size.height
                            val dash = PathEffect.dashPathEffect(floatArrayOf(8f, 8f), 0f)
                            for (i in 0..4) {
                                val y = h * (i / 4f)
                                drawLine(colors.divider, Offset(0f, y), Offset(w, y), strokeWidth = 1f, pathEffect = dash)
                            }

                            fun drawSeries(values: List<Float>, strokeColor: Color) {
                                if (values.isEmpty()) return
                                val line = Path()
                                val area = Path()
                                val count = values.size.coerceAtLeast(2)
                                values.forEachIndexed { idx, v ->
                                    val x = if (values.size == 1) w else w * idx / (count - 1f)
                                    val y = h - (v / maxY).coerceIn(0f, 1f) * h
                                    if (idx == 0) {
                                        line.moveTo(x, y)
                                        area.moveTo(x, h)
                                        area.lineTo(x, y)
                                    } else {
                                        line.lineTo(x, y)
                                        area.lineTo(x, y)
                                    }
                                    if (idx == values.lastIndex) {
                                        area.lineTo(x, h)
                                        area.close()
                                    }
                                }
                                drawPath(
                                    area,
                                    brush = Brush.verticalGradient(listOf(strokeColor.copy(alpha = 0.34f), Color.Transparent)),
                                )
                                drawPath(line, color = strokeColor, style = Stroke(width = 2.6.dp.toPx(), cap = StrokeCap.Round))
                            }

                            drawSeries(upGb, colors.success)
                            drawSeries(dlGb, colors.warning)
                        }
                    }

                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Box(Modifier.size(8.dp).clip(CircleShape).background(colors.success))
                                Text("上传量", color = colors.textSecondary, fontSize = 12.sp)
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Box(Modifier.size(8.dp).clip(CircleShape).background(colors.warning))
                                Text("下载量", color = colors.textSecondary, fontSize = 12.sp)
                            }
                        }
                        Text(
                            text = listOfNotNull(points.firstOrNull()?.updatedDay?.takeLast(5), points.lastOrNull()?.updatedDay?.takeLast(5)).distinct().joinToString(" ~ "),
                            color = colors.textMuted,
                            fontSize = 11.sp,
                        )
                    }
                }
            }

            // 账号与统计元数据
            CinematicPanel(padding = 0.dp, showsShadow = false) {
                Column {
                    SiteMetaRow("站点账号", username)
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    SiteMetaRow("加入时间", joinAt)
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    SiteMetaRow("统计日期", updatedDay)
                }
            }
            Spacer(Modifier.height(22.dp))
        }
    }
}

@Composable
private fun SiteMetricBox(label: String, value: String, valueColor: Color, modifier: Modifier = Modifier) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(padding = 14.dp, cornerRadius = 18.dp, modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, color = colors.textSecondary, fontSize = 12.sp)
            Text(value, color = valueColor, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun SiteMetaRow(label: String, value: String) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, color = colors.textSecondary, fontSize = 14.sp)
        Text(value, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
    }
}

/** 自动展开重叠的工作流节点坐标（以逻辑 dp 计量），确保连线和卡片清晰可读。 */
private fun resolveNonOverlappingNodes(actions: List<WorkflowActionDto>): List<WorkflowActionDto> {
    if (actions.size <= 1) return actions
    val hasOverlap = actions.indices.any { i ->
        (i + 1 until actions.size).any { j ->
            abs(actions[i].x - actions[j].x) < 205f && abs(actions[i].y - actions[j].y) < 110f
        }
    }
    if (!hasOverlap) return actions
    return actions.mapIndexed { idx, node ->
        val col = idx % 2
        val row = idx / 2
        node.copy(
            x = 12f + col * 218f,
            y = 20f + row * 138f + col * 26f,
        )
    }
}

private fun formatTraffic(bytes: Double): String {
    val tb = bytes / (1024.0 * 1024.0 * 1024.0 * 1024.0)
    if (tb >= 1.0) return String.format("%.2f TB", tb)
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    if (gb >= 1.0) return String.format("%.2f GB", gb)
    val mb = bytes / (1024.0 * 1024.0)
    if (mb >= 1.0) return String.format("%.1f MB", mb)
    return String.format("%.0f KB", bytes / 1024.0)
}

private fun sampleWorkflows() = listOf(
    WorkflowItemDto(
        id = 31,
        name = "观众海外剧集",
        description = "自动拉取 RSS 订阅、按画质规则过滤并推送下载整理",
        timer = "*/15 * * * *",
        state = "R",
        runCount = 18,
        actions = listOf(
            WorkflowActionDto("n1", "FetchRssAction", "获取 RSS 资源", "订阅 RSS 地址获取资源", 18f, 40f, 9),
            WorkflowActionDto("n2", "FilterTorrentsAction", "过滤资源", "对资源列表数据进行过滤", 240f, 18f, 6),
            WorkflowActionDto("n3", "AddDownloadAction", "添加下载任务", "推送精选种子到下载器", 240f, 160f, 4),
            WorkflowActionDto("n4", "NoteAction", "备注", "给工作流添加备注", 28f, 190f, 1),
        ),
        flows = listOf(
            WorkflowFlowEdgeDto("n1", "n2"),
            WorkflowFlowEdgeDto("n2", "n3"),
        ),
    ),
)
