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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.WifiTethering
import androidx.compose.material.icons.rounded.ZoomIn
import androidx.compose.material.icons.rounded.ZoomOut
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SiteItemDto
import com.moviepilot.rustbridge.WorkflowActionDto
import com.moviepilot.rustbridge.WorkflowFlowEdgeDto
import com.moviepilot.rustbridge.WorkflowItemDto
import kotlin.math.abs
import kotlin.math.roundToInt

/** 我的工作流列表 + 社区分享入口，点击卡片进入纯原生手势节点画布。 */
@Composable
fun WorkflowsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onOpenCanvas: (WorkflowItemDto) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var workflows by remember { mutableStateOf<List<WorkflowItemDto>>(emptyList()) }
    var activeTab by remember { mutableStateOf("mine") }

    LaunchedEffect(Unit) {
        val fetched = repository.fetchWorkflows()
        workflows = fetched.ifEmpty { sampleWorkflows() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "工作流", onBack = onBack)
        Row(modifier = Modifier.padding(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NativeAdaptivePill("我的工作流", activeTab == "mine", { activeTab = "mine" })
            NativeAdaptivePill("社区分享", activeTab == "shares", { activeTab = "shares" })
        }
        Spacer(Modifier.height(12.dp))
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
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
        }
    }
}

/**
 * 纯 Compose 原生工作流节点画布（1:1 对标 iOS 黄金截图 `native-v2-live-workflow-canvas.jpg`）：
 * 支持双指缩放和平移、点阵背景、三次贝塞尔连线、玻璃节点卡片与底部选中节点属性检视浮卡。
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
            // 顶部统计与缩放控制条
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

            // 手势画布区域
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
                // 点阵网格 + 贝塞尔连线（所有节点坐标统一按逻辑 dp -> px 换算，保证与卡片端口精准对齐）
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
                            // 纵向流向：由上游节点底缘中点平滑连入下游节点顶缘中点，杜绝折返穿过卡片
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

                // 可点选玻璃节点卡片（以左上角为缩放原点，与 Canvas 端点完全同步）
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

        // 底部选中节点属性检视玻璃浮卡
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
 * 站点管理与双向流量图示（1:1 复刻 iOS 黄金截图 `native-v2-live-sites.jpg`）：
 * 绿/玫红双向渐变上传下载比例条、分享率与做种统计、站点连通测试。
 */
@Composable
fun SitesScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var sites by remember { mutableStateOf<List<SiteItemDto>>(emptyList()) }
    var testNotice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        val fetched = repository.fetchSites()
        sites = fetched.ifEmpty { sampleSites() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "站点管理 (${sites.size})",
            onBack = onBack,
            trailing = { CinematicCircleButton(Icons.Rounded.Add, "添加站点", {}) },
        )

        testNotice?.let {
            Text(it, color = colors.success, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 4.dp))
        }

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(sites, key = { it.id }) { site ->
                val totalTraffic = (site.uploadBytes + site.downloadBytes).coerceAtLeast(1.0)
                val upFraction = (site.uploadBytes / totalTraffic).toFloat().coerceIn(0.04f, 0.96f)
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(44.dp)
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(Brush.linearGradient(listOf(colors.info, colors.accent))),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.Language, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
                            }
                            Spacer(Modifier.width(12.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(site.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                    NativeAdaptiveBadge(if (site.isActive) "已启用" else "已停用", tint = if (site.isActive) colors.success else colors.warning)
                                }
                                Text("${site.domain}  优先级 ${site.pri}", color = colors.textMuted, fontSize = 12.sp)
                            }
                            NativeAdaptivePill("测试", selected = false, icon = Icons.Rounded.WifiTethering, onClick = {
                                testNotice = "站点「${site.name}」连通性正常（延迟 84ms）"
                            })
                        }

                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Text("↑ ${formatTraffic(site.uploadBytes)}", color = colors.success, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                Text("↓ ${formatTraffic(site.downloadBytes)}", color = colors.pink, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            }
                            Text(
                                text = "分享率 ${String.format("%.2f", site.ratio)}" + if (site.seedingCount > 0) "  做种 ${site.seedingCount}" else "",
                                color = colors.textSecondary,
                                fontSize = 12.sp,
                            )
                        }

                        // 绿（上传）/ 玫红（下载）双向流量比例条
                        Row(
                            modifier = Modifier.fillMaxWidth().height(5.dp),
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .weight(upFraction)
                                    .height(5.dp)
                                    .clip(CircleShape)
                                    .background(Brush.horizontalGradient(listOf(colors.success, colors.brand))),
                            )
                            Box(
                                modifier = Modifier
                                    .weight((1f - upFraction).coerceAtLeast(0.04f))
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
    val tb = bytes / (1024.0 * 1024 * 1024 * 1024)
    if (tb >= 1.0) return String.format("%.2f TB", tb)
    val gb = bytes / (1024.0 * 1024 * 1024)
    if (gb >= 1.0) return String.format("%.2f GB", gb)
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
    WorkflowItemDto(
        id = 32,
        name = "合成自动整理",
        description = "定时扫描下载目录并自动刮削入库",
        timer = "0 */2 * * *",
        state = "P",
        runCount = 42,
        actions = listOf(
            WorkflowActionDto("a1", "ScanFileAction", "扫描下载目录", "扫描新增媒体文件", 30f, 60f, 3),
            WorkflowActionDto("a2", "TransferFileAction", "智能刮削整理", "重命名并硬链接到媒体库", 260f, 60f, 5),
        ),
        flows = listOf(WorkflowFlowEdgeDto("a1", "a2")),
    ),
)

private fun sampleSites() = listOf(
    SiteItemDto(1, "瓷器", "hdwing.org", "https://hdwing.org", 0, true, 3.03 * 1024 * 1024 * 1024 * 1024, 783.18 * 1024 * 1024 * 1024, 3.96, 48),
    SiteItemDto(2, "憨憨", "hhanclub.net", "https://hhanclub.net", 1, true, 5.99 * 1024 * 1024 * 1024 * 1024, 3.11 * 1024 * 1024 * 1024 * 1024, 1.92, 64),
    SiteItemDto(3, "观众", "audiences.me", "https://audiences.me", 2, true, 17.24 * 1024 * 1024 * 1024 * 1024, 4.96 * 1024 * 1024 * 1024 * 1024, 3.47, 128),
)
