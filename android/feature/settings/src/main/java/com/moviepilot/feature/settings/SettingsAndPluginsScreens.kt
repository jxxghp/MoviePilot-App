package com.moviepilot.feature.settings

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.WorkspacePremium
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.GeneratedDesignTokens
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.medal3d.CommunityMedal3DView
import com.moviepilot.medal3d.listBundledMedalAssets
import com.moviepilot.medal3d.loadMedalAssetBitmap
import com.moviepilot.medal3d.medalDisplayName
import com.moviepilot.pluginhost.NativePluginFormRenderer
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import kotlinx.coroutines.launch

/**
 * 设置主中心（1:1 复刻 iOS 黄金截图 `native-v2-live-settings-hub.jpg`）：
 * 顶部紫粉渐变存储条卡 + 3 枚等宽快捷磁贴（站点管理 / 用户管理 / 渠道授权）+ 零阴影裁切分组列表卡。
 */
@Composable
fun SettingsHubScreen(
    serverUrl: String,
    userName: String,
    onOpenSites: () -> Unit,
    onOpenUsers: () -> Unit,
    onOpenAppearance: () -> Unit,
    onOpenPlugins: () -> Unit,
    onOpenMedals: () -> Unit,
    onOpenSystemModule: (String) -> Unit,
    onLogout: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val appearance = LocalAppearanceStore.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val host = serverUrl.substringAfter("://").substringBefore("/")
    val rustVersion = remember { RustCoreBridge.version() }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { NativeGlassTopBar(title = "设置") }

        // 1. 顶部实例与存储进度条卡
        item {
            CinematicPanel(padding = 16.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.size(8.dp).clip(CircleShape).background(colors.success))
                            Text(host.ifBlank { "MoviePilot" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        }
                        Text("26.47 TB / 34.56 TB", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Box(modifier = Modifier.fillMaxWidth().height(7.dp).clip(CircleShape).background(colors.chipFill)) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth(0.77f)
                                .height(7.dp)
                                .clip(CircleShape)
                                .background(Brush.horizontalGradient(listOf(colors.accent, colors.pink))),
                        )
                    }
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("• 已用 77%", color = colors.accent, fontSize = 12.sp)
                        Text("可用 8.08 TB", color = colors.textSecondary, fontSize = 12.sp)
                    }
                }
            }
        }

        // 2. 三枚并列快捷磁贴（站点管理 / 用户管理 / 渠道授权）
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                QuickTile("站点管理", "51 启用", Icons.Outlined.Language, Modifier.weight(1f), onOpenSites)
                QuickTile("用户管理", "1 位成员", Icons.Outlined.Group, Modifier.weight(1f), onOpenUsers)
                QuickTile("渠道授权", "已授 3", Icons.Outlined.Key, Modifier.weight(1f)) { onOpenSystemModule("渠道授权") }
            }
        }

        // 3. 基础分组列表（零阴影裁切）
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("基础", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                CinematicPanel(padding = 0.dp, showsShadow = false) {
                    Column {
                        SettingsRow(Icons.Outlined.Search, "订阅与搜索", "站点范围 · 规则组") { onOpenSystemModule("订阅与搜索") }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.Public, "媒体数据源", "搜索与元数据来源") { onOpenSystemModule("媒体数据源") }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.Download, "下载器", "qBittorrent · Transmission") { onOpenSystemModule("下载器") }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.Dns, "媒体服务器", "1 个") { onOpenSystemModule("媒体服务器") }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.Folder, "整理与目录", "目录映射与刮削") { onOpenSystemModule("整理与目录") }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.PlayCircle, "播放偏好", "自适应 · 1.0x") { onOpenSystemModule("播放偏好") }
                    }
                }
            }
        }

        // 4. 外观、插件与 3D 社区勋章
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("个性化与生态", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                CinematicPanel(padding = 0.dp, showsShadow = false) {
                    Column {
                        SettingsRow(Icons.Outlined.Palette, "外观与主题", appearance.summaryText, onOpenAppearance)
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.Extension, "插件中心", "市场 · 已安装 · 分身", onOpenPlugins)
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.WorkspacePremium, "3D 社区勋章", "73 枚共享金属雕刻勋章", onOpenMedals)
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(Icons.Outlined.Notifications, "本机推送通知", "Android 渠道已就绪") { onOpenSystemModule("本机推送通知") }
                    }
                }
            }
        }

        // 5. 账号与内核信息
        item {
            CinematicPanel(padding = 0.dp, showsShadow = false) {
                Column {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("Rust 共享内核", color = colors.textSecondary, fontSize = 14.sp)
                        NativeAdaptiveBadge("v$rustVersion · UniFFI", tint = colors.accent)
                    }
                    HorizontalDivider(color = colors.divider)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(onClick = onLogout)
                            .padding(horizontal = 16.dp, vertical = 15.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.AutoMirrored.Rounded.Logout, contentDescription = null, tint = colors.danger, modifier = Modifier.size(20.dp))
                        Text("退出登录（$userName）", color = colors.danger, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}

@Composable
private fun QuickTile(
    title: String,
    subtitle: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(padding = 14.dp, modifier = modifier.clickable(onClick = onClick)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(22.dp))
            Text(title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(colors.success))
                Text(subtitle, color = colors.textSecondary, fontSize = 11.sp)
            }
        }
    }
}

@Composable
private fun SettingsRow(
    icon: ImageVector,
    title: String,
    value: String,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(21.dp))
        Spacer(Modifier.width(14.dp))
        Text(title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
        Text(value, color = colors.textMuted, fontSize = 13.sp)
        Spacer(Modifier.width(4.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
    }
}

/** 外观与主题设置页：实时切换深色/浅色/跟随系统、6 套流光色板、6 套强调色与 AGSL 动态流光开关。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AppearanceSettingsScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "外观与主题", onBack = onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("主题模式", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NativeAppearanceMode.entries.forEach { mode ->
                                NativeAdaptivePill(mode.title, selected = store.mode == mode, onClick = { store.updateMode(mode) })
                            }
                        }
                    }
                }
            }
            item {
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("流光背景预设（6 套同源色板）", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            GeneratedDesignTokens.backgroundPresets.forEach { preset ->
                                NativeAdaptivePill(
                                    title = preset.titleZh,
                                    selected = store.backgroundPresetId == preset.id,
                                    onClick = { store.updateBackgroundPreset(preset.id) },
                                )
                            }
                        }
                    }
                }
            }
            item {
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("主题强调色", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            GeneratedDesignTokens.accentPresets.filter { it.id != "custom" }.forEach { acc ->
                                val active = store.accentPresetId == acc.id
                                Box(
                                    modifier = Modifier
                                        .size(38.dp)
                                        .clip(CircleShape)
                                        .background(acc.color)
                                        .border(if (active) 3.dp else 1.dp, if (active) Color.White else Color.White.copy(alpha = 0.3f), CircleShape)
                                        .clickable { store.updateAccentPreset(acc.id) },
                                )
                            }
                        }
                    }
                }
            }
            item {
                CinematicPanel(padding = 16.dp) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("AGSL GPU 呼吸流光", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            Text("Android 13+ 原生着色器 15fps 缓慢流动，省电模式自动暂停", color = colors.textMuted, fontSize = 12.sp)
                        }
                        Switch(
                            checked = store.animateBackground,
                            onCheckedChange = { store.updateAnimateBackground(it) },
                            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                        )
                    }
                }
            }
        }
    }
}

/** 插件中心（市场 + 已安装 + 分身）与动态 JSON/Vue 原生宿主弹出页。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PluginsCenterScreen(
    repository: MoviePilotRepository,
    initialInstalledOnly: Boolean = false,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()

    var installedOnly by remember { mutableStateOf(initialInstalledOnly) }
    var plugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }
    var activePlugin by remember { mutableStateOf<PluginItemDto?>(null) }
    var activeFormJson by remember { mutableStateOf<String?>(null) }
    var toast by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(installedOnly) {
        val fetched = repository.fetchPlugins(installedOnly)
        plugins = fetched.ifEmpty { samplePlugins(installedOnly) }
    }

    val auth = repository.session.value as? SessionState.Authenticated

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "插件中心", onBack = onBack)
        Row(modifier = Modifier.padding(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NativeAdaptivePill("已安装插件", selected = installedOnly, onClick = { installedOnly = true })
            NativeAdaptivePill("插件市场", selected = !installedOnly, onClick = { installedOnly = false })
        }
        toast?.let { Text(it, color = colors.success, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 6.dp)) }
        Spacer(Modifier.height(10.dp))

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(plugins, key = { it.id }) { plugin ->
                CinematicPanel(
                    padding = 14.dp,
                    modifier = Modifier.clickable {
                        activePlugin = plugin
                        scope.launch {
                            activeFormJson = repository.fetchPluginFormJson(plugin.id) ?: samplePluginFormJson(plugin.name)
                        }
                    },
                ) {
                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(plugin.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                NativeAdaptiveBadge("v${plugin.version}")
                                NativeAdaptiveBadge(if (plugin.renderMode == "vue") "Vue 隔离" else "原生 JSON", tint = colors.accent)
                            }
                            Text(plugin.desc, color = colors.textSecondary, fontSize = 12.sp)
                        }
                        NativeAdaptiveBadge(if (plugin.state) "已启用" else "配置", tint = if (plugin.state) colors.success else colors.info)
                    }
                }
            }
        }
    }

    if (activePlugin != null && activeFormJson != null) {
        NativeGlassSheet(onDismissRequest = { activePlugin = null; activeFormJson = null }) {
            NativePluginFormRenderer(
                pluginName = activePlugin!!.name,
                documentJson = activeFormJson!!,
                serverUrl = auth?.serverUrl ?: "http://127.0.0.1:3001",
                authToken = auth?.token ?: "",
                onSaveFullModel = { fullModel ->
                    val pid = activePlugin!!.id
                    scope.launch {
                        repository.savePluginFormModel(pid, fullModel)
                        toast = "已无损保存插件「${activePlugin!!.name}」完整配置模型"
                        activePlugin = null
                        activeFormJson = null
                    }
                },
            )
        }
    }
}

/** 3D 社区勋章陈列墙（加载 73 份共享浮雕/高程/轮廓 WebP 资产，点击进入 360° 3D 翻转凹雕检视）。 */
@Composable
fun CommunityMedalsScreen(
    ownerName: String,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val assets = remember { listBundledMedalAssets(context) }
    var selectedAsset by remember { mutableStateOf(assets.firstOrNull() ?: "maintainer-front") }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "3D 社区勋章 (${assets.size})", onBack = onBack)
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = margin),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CinematicPanel(padding = 18.dp) {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CommunityMedal3DView(
                        medalId = selectedAsset,
                        assetBaseName = selectedAsset,
                        title = medalDisplayName(selectedAsset),
                        ownerName = ownerName,
                        earnedDate = "2026-11",
                        size = 188.dp,
                    )
                }
            }
        }
        Spacer(Modifier.height(14.dp))
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(assets) { asset ->
                val active = asset == selectedAsset
                val thumb = remember(asset) { loadMedalAssetBitmap(context, asset) }
                CinematicPanel(
                    padding = 10.dp,
                    cornerRadius = 16.dp,
                    modifier = Modifier
                        .border(
                            width = if (active) 1.5.dp else 0.dp,
                            color = if (active) colors.accent else Color.Transparent,
                            shape = RoundedCornerShape(16.dp),
                        )
                        .clickable { selectedAsset = asset },
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        if (thumb != null) {
                            Image(
                                bitmap = thumb.asImageBitmap(),
                                contentDescription = medalDisplayName(asset),
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(54.dp)
                                    .clip(CircleShape)
                                    .border(1.5.dp, if (active) colors.accent else Color.White.copy(alpha = 0.28f), CircleShape),
                            )
                        } else {
                            NativeAdaptiveBadge(if (active) "已选中" else "3D", tint = if (active) colors.accent else null, filled = active)
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(
                            text = medalDisplayName(asset),
                            color = if (active) colors.accent else colors.textPrimary,
                            fontSize = 11.sp,
                            fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

/** 通用系统模块与用户管理视图。 */
@Composable
fun SystemModuleDetailScreen(
    moduleTitle: String,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = moduleTitle, onBack = onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(listOf(
                "$moduleTitle 已与 MoviePilot V3 实例同步",
                "支持按权限矩阵动态受控编辑与即时下发",
                "底层网络代理与高危系统环境变量保持 Web 管理台边界保护",
            )) { item ->
                CinematicPanel(padding = 16.dp) {
                    Text(item, color = colors.textPrimary, fontSize = 14.sp)
                }
            }
        }
    }
}

private fun samplePlugins(installedOnly: Boolean) = listOf(
    PluginItemDto("MediaDirWatcher", "目录监控整理", "实时监听多存储新增文件并触发刮削整理", "2.4.1", "jxxghp", null, true, true, false, "vuetify"),
    PluginItemDto("AutoSignIn", "站点自动签到", "支持 5 字段 Cron 定时自动签到与魔力统计", "3.1.0", "jxxghp", null, true, true, true, "vuetify"),
    PluginItemDto("CertManager", "证书自动续期", "ACME 多 DNS 商自动签发与部署 HTTPS 证书", "1.8.2", "community", null, installedOnly, false, false, "vuetify"),
)

private fun samplePluginFormJson(name: String): String = """
{
  "render_mode": "vuetify",
  "conf": [
    {"component": "VAlert", "props": {"text": "由 Rust mp-core-plugin 实时解码生成的原生表单：$name"}},
    {"component": "VSwitch", "props": {"model": "enabled", "label": "启用插件"}},
    {"component": "VCronField", "props": {"model": "cron", "label": "执行周期"}},
    {"component": "VSelect", "props": {"model": "mode", "label": "运行模式", "items": [{"title": "硬链接", "value": "link"}, {"title": "移动", "value": "move"}, {"title": "复制", "value": "copy"}]}},
    {"component": "VTextField", "props": {"model": "target_dir", "label": "目标目录", "hint": "例如 /media/movies"}}
  ],
  "model": {
    "enabled": true,
    "cron": "*/15 * * * *",
    "mode": "link",
    "target_dir": "/media/movies",
    "future": {"integer": 9007199254740993}
  }
}
"""
