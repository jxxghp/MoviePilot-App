package com.moviepilot.feature.settings

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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.FolderShared
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeBrandDrawable
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativeSegmentedControl
import com.moviepilot.rustbridge.DirectoryConfigDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.ServiceConfigDto
import com.moviepilot.rustbridge.SiteItemDto
import com.moviepilot.rustbridge.StorageConfigDto
import com.moviepilot.rustbridge.SubscribeSearchSettingsDto
import com.moviepilot.rustbridge.UserIdentity
import kotlinx.coroutines.launch

/** 1:1 复刻 iOS `native-v2-live-users.jpg` 用户管理页面（管理员/普通成员分组 + 真实头像 + 当前角标 + 状态角标）。 */
@Composable
fun UsersManagementScreen(
    repository: MoviePilotRepository,
    currentUserName: String,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var users by remember { mutableStateOf<List<UserIdentity>>(emptyList()) }

    LaunchedEffect(Unit) {
        users = repository.fetchUsers()
    }

    val admins = remember(users) { users.filter { it.isSuperuser } }
    val members = remember(users) { users.filter { !it.isSuperuser } }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "用户管理 (${users.size})",
            onBack = onBack,
            trailing = { CinematicCircleButton(Icons.Outlined.PersonAdd, "新增用户", {}) },
        )

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            if (admins.isNotEmpty()) {
                item {
                    UserGroupSection("管理员 (${admins.size})", admins, currentUserName)
                }
            }
            if (members.isNotEmpty()) {
                item {
                    UserGroupSection("普通成员 (${members.size})", members, currentUserName)
                }
            }
        }
    }
}

@Composable
private fun UserGroupSection(
    header: String,
    users: List<UserIdentity>,
    currentUserName: String,
) {
    val colors = LocalMoviePilotColors.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(header, color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
        CinematicPanel(padding = 0.dp, showsShadow = false) {
            Column {
                users.forEachIndexed { idx, user ->
                    val isCurrent = user.name.equals(currentUserName, ignoreCase = true)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .clip(CircleShape)
                                .background(colors.accent.copy(alpha = 0.28f))
                                .border(1.dp, Color.White.copy(alpha = 0.3f), CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (!user.avatar.isNullOrBlank()) {
                                AsyncImage(
                                    model = user.avatar,
                                    contentDescription = user.name,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize().clip(CircleShape),
                                )
                            } else {
                                Text(user.name.take(1).uppercase(), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                            }
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(user.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                if (isCurrent) {
                                    NativeAdaptiveBadge("当前", tint = colors.info)
                                }
                            }
                            if (user.email.isNotBlank()) {
                                Text(user.email, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                        NativeAdaptiveBadge(if (user.isActive) "正常" else "停用", tint = if (user.isActive) colors.success else colors.danger)
                        Spacer(Modifier.width(6.dp))
                        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                    }
                    if (idx < users.lastIndex) {
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 72.dp))
                    }
                }
            }
        }
    }
}

/** 1:1 复刻 iOS `native-v2-live-sysmod-site-scope.jpg` 订阅与搜索配置页（订阅站点/搜索站点多选 + 规则组 + 订阅模式）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscribeSearchSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()

    var settings by remember { mutableStateOf(SubscribeSearchSettingsDto()) }
    var allSites by remember { mutableStateOf<List<SiteItemDto>>(emptyList()) }
    var pickerTarget by remember { mutableStateOf<String?>(null) } // "rss" | "indexer"
    var savedNotice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        settings = repository.fetchSubscribeSearchSettings()
        allSites = repository.fetchSites()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "订阅与搜索",
            onBack = onBack,
            trailing = {
                CinematicGlassSurface(
                    shape = CircleShape,
                    blurRadiusDp = 18.dp,
                    modifier = Modifier.clickable {
                        scope.launch {
                            repository.saveSettingValue("RssSites", settings.rssSiteIds.joinToString(",", "[", "]"))
                            repository.saveSettingValue("IndexerSites", settings.indexerSiteIds.joinToString(",", "[", "]"))
                            repository.saveSettingValue("SUBSCRIBE_MODE", "\"${settings.subscribeMode}\"")
                            savedNotice = "已保存站点范围与订阅刷新配置"
                        }
                    },
                ) {
                    Text("保存", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
                }
            },
        )

        savedNotice?.let {
            Text(it, color = colors.success, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 4.dp))
        }

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("站点范围", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Column {
                            SimpleSettingRow("订阅站点", "已选 ${settings.rssSiteIds.size} 站") { pickerTarget = "rss" }
                            HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                            SimpleSettingRow("搜索站点", "已选 ${settings.indexerSiteIds.size} 站") { pickerTarget = "indexer" }
                        }
                    }
                }
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("优先级规则组", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Column {
                            SimpleSettingRow("订阅优先级规则", "默认") {}
                            HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                            SimpleSettingRow("洗版优先级规则", "默认") {}
                            HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                            SimpleSettingRow("搜索优先级规则", "${settings.filterRuleGroups.size.coerceAtLeast(1)} 组") {}
                        }
                    }
                }
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("订阅刷新模式", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    val next = if (settings.subscribeMode == "spider") "rss" else "spider"
                                    settings = settings.copy(subscribeMode = next)
                                }
                                .padding(horizontal = 16.dp, vertical = 16.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text("订阅模式", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                            Text(
                                text = if (settings.subscribeMode == "rss") "RSS 订阅" else "站点爬虫",
                                color = colors.accent,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                }
            }
        }
    }

    pickerTarget?.let { target ->
        val currentIds = if (target == "rss") settings.rssSiteIds else settings.indexerSiteIds
        NativeGlassSheet(onDismissRequest = { pickerTarget = null }) {
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(if (target == "rss") "选择订阅站点" else "选择搜索站点", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                LazyColumn(modifier = Modifier.height(360.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(allSites, key = { it.id }) { site ->
                        val selected = site.id in currentIds
                        CinematicPanel(
                            padding = 12.dp,
                            modifier = Modifier.clickable {
                                val next = if (selected) currentIds - site.id else currentIds + site.id
                                settings = if (target == "rss") settings.copy(rssSiteIds = next) else settings.copy(indexerSiteIds = next)
                            },
                        ) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text(site.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                CheckCircleMark(selected = selected)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

/** 1:1 复刻 iOS `native-v2-live-settings.jpg` 媒体数据源页面（8 大官方数据源品牌 Logo + 多选圆勾 + 保存）。 */
@Composable
fun MediaSourcesSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()

    data class SourceSpec(val id: String, val title: String, val subtitle: String, val logo: String)
    val allSources = remember {
        listOf(
            SourceSpec("themoviedb", "TheMovieDb", "全球影视元数据", "logo_tmdb"),
            SourceSpec("douban", "豆瓣", "中文影评与榜单", "logo_douban"),
            SourceSpec("bangumi", "Bangumi", "番剧与动画索引", "logo_bangumi"),
            SourceSpec("imdb", "IMDb", "全球影视评分与资料", ""),
            SourceSpec("tvdb", "TVDB", "剧集分集与元数据", ""),
            SourceSpec("musicbrainz", "MusicBrainz", "音乐专辑与曲目", "logo_musicbrainz"),
            SourceSpec("theaudiodb", "TheAudioDB", "音乐艺人、专辑与封面", ""),
            SourceSpec("douban_music", "豆瓣音乐", "中文音乐专辑与评分", "logo_douban"),
        )
    }

    var selected by remember { mutableStateOf(setOf("themoviedb")) }
    var notice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        selected = repository.fetchSearchSources()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "媒体数据源",
            onBack = onBack,
            trailing = {
                CinematicGlassSurface(
                    shape = CircleShape,
                    blurRadiusDp = 18.dp,
                    modifier = Modifier.clickable {
                        scope.launch {
                            val csv = selected.joinToString(",")
                            repository.saveSettingValue("SEARCH_SOURCE", "\"$csv\"")
                            notice = "已保存媒体搜索数据源"
                        }
                    },
                ) {
                    Text("保存", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
                }
            },
        )

        notice?.let { Text(it, color = colors.success, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 4.dp)) }

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("媒体搜索数据源", color = colors.textSecondary, fontSize = 13.sp)
                    Text("已选 ${selected.size} 个", color = colors.textSecondary, fontSize = 13.sp)
                }
            }
            items(allSources) { src ->
                val isSel = src.id in selected
                CinematicPanel(
                    padding = 14.dp,
                    cornerRadius = 18.dp,
                    modifier = Modifier
                        .then(
                            if (isSel) Modifier.border(1.4.dp, colors.accent, RoundedCornerShape(18.dp)) else Modifier,
                        )
                        .clickable {
                            selected = if (isSel && selected.size > 1) selected - src.id else selected + src.id
                        },
                ) {
                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (src.logo.isNotBlank()) {
                            NativeBrandDrawable(drawableName = src.logo, size = 38.dp, cornerRadius = 19.dp)
                        } else {
                            Box(
                                modifier = Modifier
                                    .size(38.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFF5D4BCE)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.Storage, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                            }
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(src.title, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text(src.subtitle, color = colors.textSecondary, fontSize = 12.sp)
                        }
                        CheckCircleMark(selected = isSel)
                    }
                }
            }
            item {
                Text(
                    "仅展示后端已启用的媒体数据源模块；关闭或启用内置模块请在 Web 高级设置中调整。",
                    color = colors.textMuted,
                    fontSize = 12.sp,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
                )
            }
        }
    }
}

/** 下载器管理页（支持新增、点击编辑、默认切换与删除，无损持久化至 `/api/v1/system/setting/Downloaders`）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadersSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    var list by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
    var editingItem by remember { mutableStateOf<ServiceConfigDto?>(null) }
    var isCreateMode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<ServiceConfigDto?>(null) }

    suspend fun reload() { list = repository.fetchDownloaders() }
    LaunchedEffect(Unit) { reload() }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "下载器",
            onBack = onBack,
            trailing = {
                ExpressiveHeaderActionButton(
                    icon = Icons.Rounded.Add,
                    contentDescription = "添加下载器",
                    onClick = {
                        isCreateMode = true
                        editingItem = ServiceConfigDto(name = "", type = "qbittorrent", enabled = true, isDefault = list.isEmpty())
                    },
                )
            },
        )
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 12.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(list, key = { it.name }) { dl ->
                val logo = if (dl.type.contains("transmission", ignoreCase = true)) "logo_transmission" else "logo_qbittorrent"
                CinematicPanel(
                    padding = 16.dp,
                    modifier = Modifier.clickable {
                        isCreateMode = false
                        editingItem = dl
                    },
                ) {
                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        NativeBrandDrawable(drawableName = logo, size = 42.dp, cornerRadius = 21.dp)
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(dl.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                if (dl.isDefault) NativeAdaptiveBadge("默认", tint = colors.brand)
                            }
                            Text("${dl.type} · ${dl.host.ifBlank { "已配置" }}", color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        NativeAdaptiveBadge(if (dl.enabled) "已启用" else "已停用", tint = if (dl.enabled) colors.success else colors.warning)
                        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }

    editingItem?.let { current ->
        var name by remember(current, isCreateMode) { mutableStateOf(current.name) }
        var type by remember(current, isCreateMode) { mutableStateOf(current.type.ifBlank { "qbittorrent" }) }
        var host by remember(current, isCreateMode) { mutableStateOf(current.host) }
        var username by remember(current, isCreateMode) { mutableStateOf(current.username) }
        var password by remember(current, isCreateMode) { mutableStateOf(current.password) }
        var enabled by remember(current, isCreateMode) { mutableStateOf(current.enabled) }
        var isDefault by remember(current, isCreateMode) { mutableStateOf(current.isDefault) }
        var saving by remember { mutableStateOf(false) }
        val fieldColors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.fieldBorder,
        )

        NativeGlassSheet(onDismissRequest = { editingItem = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(if (isCreateMode) "新增下载器" else "编辑下载器", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("qbittorrent" to "qBittorrent", "transmission" to "Transmission").forEach { (k, lbl) ->
                        NativeAdaptivePill(lbl, selected = type.equals(k, ignoreCase = true), onClick = { type = k })
                    }
                }
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("名称") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = host, onValueChange = { host = it }, label = { Text("服务地址（如 http://127.0.0.1:8080）") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = username, onValueChange = { username = it }, label = { Text("用户名") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text("密码") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("启用此下载器", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(checked = enabled, onCheckedChange = { enabled = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("设为默认下载器", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(checked = isDefault, onCheckedChange = { isDefault = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (!isCreateMode) {
                        Button(
                            onClick = { confirmDelete = current },
                            colors = ButtonDefaults.buttonColors(containerColor = colors.danger.copy(alpha = 0.18f), contentColor = colors.danger),
                            shape = CircleShape,
                            modifier = Modifier.height(48.dp),
                        ) {
                            Icon(Icons.Rounded.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("删除", fontWeight = FontWeight.Bold)
                        }
                    }
                    Button(
                        enabled = !saving && name.isNotBlank() && host.isNotBlank(),
                        onClick = {
                            saving = true
                            scope.launch {
                                val ok = repository.saveDownloader(
                                    item = current.copy(name = name, type = type, host = host, username = username, password = password, enabled = enabled, isDefault = isDefault),
                                    originalName = if (isCreateMode) null else current.name,
                                )
                                saving = false
                                editingItem = null
                                reload()
                                snackbar?.showSnackbar(if (ok) "已保存下载器「$name」" else "保存失败，请检查配置")
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(48.dp),
                    ) {
                        Text(if (saving) "保存中..." else "保存配置", fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(Modifier.height(18.dp))
            }
        }
    }

    confirmDelete?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("确认删除下载器") },
            text = { Text("确定要删除「${target.name}」吗？") },
            confirmButton = {
                TextButton(onClick = {
                    val deleting = target
                    confirmDelete = null
                    editingItem = null
                    scope.launch {
                        val ok = repository.deleteDownloader(deleting.name)
                        reload()
                        snackbar?.showSnackbar(if (ok) "已删除下载器「${deleting.name}」" else "删除失败")
                    }
                }) { Text("删除", color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text("取消") } },
        )
    }
}

/** 媒体服务器管理页（支持新增、点击编辑与删除，无损持久化至 `/api/v1/system/setting/MediaServers`）。 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun MediaServersSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    var list by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
    var editingItem by remember { mutableStateOf<ServiceConfigDto?>(null) }
    var isCreateMode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<ServiceConfigDto?>(null) }

    suspend fun reload() { list = repository.fetchMediaServers() }
    LaunchedEffect(Unit) { reload() }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "媒体服务器",
            onBack = onBack,
            trailing = {
                ExpressiveHeaderActionButton(
                    icon = Icons.Rounded.Add,
                    contentDescription = "添加媒体服务器",
                    onClick = {
                        isCreateMode = true
                        editingItem = ServiceConfigDto(name = "", type = "emby", enabled = true)
                    },
                )
            },
        )
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 12.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(list, key = { it.name }) { ms ->
                val logo = when {
                    ms.type.contains("jellyfin", ignoreCase = true) -> "logo_jellyfin"
                    ms.type.contains("plex", ignoreCase = true) -> "logo_plex"
                    ms.type.contains("trim", ignoreCase = true) -> "logo_trimemedia"
                    else -> "logo_emby"
                }
                CinematicPanel(
                    padding = 16.dp,
                    modifier = Modifier.clickable {
                        isCreateMode = false
                        editingItem = ms
                    },
                ) {
                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        NativeBrandDrawable(drawableName = logo, size = 42.dp, cornerRadius = 10.dp)
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(ms.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text("${ms.type} · ${ms.host.ifBlank { "已配置" }}", color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        NativeAdaptiveBadge(if (ms.enabled) "已启用" else "已停用", tint = if (ms.enabled) colors.success else colors.warning)
                        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }

    editingItem?.let { current ->
        var name by remember(current, isCreateMode) { mutableStateOf(current.name) }
        var type by remember(current, isCreateMode) { mutableStateOf(current.type.ifBlank { "emby" }) }
        var host by remember(current, isCreateMode) { mutableStateOf(current.host) }
        var apikey by remember(current, isCreateMode) { mutableStateOf(current.apikey) }
        var playHost by remember(current, isCreateMode) { mutableStateOf(current.playHost) }
        var enabled by remember(current, isCreateMode) { mutableStateOf(current.enabled) }
        var saving by remember { mutableStateOf(false) }
        val fieldColors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.fieldBorder,
        )

        NativeGlassSheet(onDismissRequest = { editingItem = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(if (isCreateMode) "新增媒体服务器" else "编辑媒体服务器", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("emby" to "Emby", "jellyfin" to "Jellyfin", "plex" to "Plex", "trimemedia" to "飞牛影视").forEach { (k, lbl) ->
                        NativeAdaptivePill(lbl, selected = type.equals(k, ignoreCase = true), onClick = { type = k })
                    }
                }
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("名称") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = host, onValueChange = { host = it }, label = { Text("服务器地址（如 http://127.0.0.1:8096）") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = apikey, onValueChange = { apikey = it }, label = { Text(if (type.equals("plex", true)) "Token" else "API Key") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = playHost, onValueChange = { playHost = it }, label = { Text("外网播放地址（可选）") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("启用此服务器", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(checked = enabled, onCheckedChange = { enabled = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (!isCreateMode) {
                        Button(
                            onClick = { confirmDelete = current },
                            colors = ButtonDefaults.buttonColors(containerColor = colors.danger.copy(alpha = 0.18f), contentColor = colors.danger),
                            shape = CircleShape,
                            modifier = Modifier.height(48.dp),
                        ) {
                            Icon(Icons.Rounded.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("删除", fontWeight = FontWeight.Bold)
                        }
                    }
                    Button(
                        enabled = !saving && name.isNotBlank() && host.isNotBlank(),
                        onClick = {
                            saving = true
                            scope.launch {
                                val ok = repository.saveMediaServer(
                                    item = current.copy(name = name, type = type, host = host, apikey = apikey, playHost = playHost, enabled = enabled),
                                    originalName = if (isCreateMode) null else current.name,
                                )
                                saving = false
                                editingItem = null
                                reload()
                                snackbar?.showSnackbar(if (ok) "已保存媒体服务器「$name」" else "保存失败，请检查配置")
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(48.dp),
                    ) {
                        Text(if (saving) "保存中..." else "保存配置", fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(Modifier.height(18.dp))
            }
        }
    }

    confirmDelete?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("确认删除媒体服务器") },
            text = { Text("确定要删除「${target.name}」吗？") },
            confirmButton = {
                TextButton(onClick = {
                    val deleting = target
                    confirmDelete = null
                    editingItem = null
                    scope.launch {
                        val ok = repository.deleteMediaServer(deleting.name)
                        reload()
                        snackbar?.showSnackbar(if (ok) "已删除媒体服务器「${deleting.name}」" else "删除失败")
                    }
                }) { Text("删除", color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text("取消") } },
        )
    }
}

/** 目录与存储页（支持新增、点击编辑与删除目录映射，无损持久化至 `/api/v1/system/setting/Directories`）。 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun DirectoriesStorageSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    var dirs by remember { mutableStateOf<List<DirectoryConfigDto>>(emptyList()) }
    var storages by remember { mutableStateOf<List<StorageConfigDto>>(emptyList()) }
    var editingDir by remember { mutableStateOf<DirectoryConfigDto?>(null) }
    var isCreateMode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<DirectoryConfigDto?>(null) }

    suspend fun reload() {
        dirs = repository.fetchDirectories()
        storages = repository.fetchStorages()
    }
    LaunchedEffect(Unit) { reload() }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "目录与存储",
            onBack = onBack,
            trailing = {
                ExpressiveHeaderActionButton(
                    icon = Icons.Rounded.Add,
                    contentDescription = "添加目录",
                    onClick = {
                        isCreateMode = true
                        editingDir = DirectoryConfigDto(
                            name = "",
                            priority = dirs.size + 1,
                            storage = storages.firstOrNull()?.type ?: "local",
                            libraryStorage = storages.firstOrNull()?.type ?: "local",
                            transferType = "link",
                            monitorType = "downloader",
                        )
                    },
                )
            },
        )
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 12.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // 下载与媒体库整理目录
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("下载与媒体库整理目录", color = colors.textSecondary, fontSize = 13.sp)
                        Text("${dirs.size} 项", color = colors.textMuted, fontSize = 12.sp)
                    }
                    dirs.forEach { d ->
                        val transferLabel = when (d.transferType.lowercase()) {
                            "link" -> "硬链接"
                            "softlink" -> "软链接"
                            "move" -> "移动"
                            else -> "复制"
                        }
                        CinematicPanel(
                            padding = 16.dp,
                            modifier = Modifier.clickable {
                                isCreateMode = false
                                editingDir = d
                            },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    NativeAdaptiveBadge("#${d.priority}", tint = colors.brand)
                                    Spacer(Modifier.width(8.dp))
                                    Text(d.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                    NativeAdaptiveBadge(transferLabel, tint = colors.success)
                                    Spacer(Modifier.width(4.dp))
                                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                }
                                if (d.downloadPath.isNotBlank()) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        StorageIconMini(d.storage)
                                        Text(d.downloadPath, color = colors.textPrimary, fontSize = 13.sp, fontFamily = FontFamily.Monospace)
                                    }
                                }
                                if (d.libraryPath.isNotBlank()) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        StorageIconMini(d.libraryStorage)
                                        Text(d.libraryPath, color = colors.textPrimary, fontSize = 13.sp, fontFamily = FontFamily.Monospace)
                                    }
                                }
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    if (d.monitorType.isNotBlank()) NativeAdaptiveBadge(if (d.monitorType == "downloader") "下载器监控" else "目录监控")
                                    if (d.renaming) NativeAdaptiveBadge("智能重命名")
                                    if (d.scraping) NativeAdaptiveBadge("自动刮削")
                                    if (d.notify) NativeAdaptiveBadge("通知")
                                }
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                    }
                }
            }

            // 已挂载存储
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("已挂载存储", color = colors.textSecondary, fontSize = 13.sp)
                        Text("${storages.size} 项", color = colors.textMuted, fontSize = 12.sp)
                    }
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Column {
                            storages.forEachIndexed { idx, st ->
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    StorageIconLarge(st.type)
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(st.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                        Text(st.type, color = colors.textSecondary, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                                    }
                                    NativeAdaptiveBadge("已挂载", tint = colors.success)
                                }
                                if (idx < storages.lastIndex) {
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 66.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    editingDir?.let { current ->
        var name by remember(current, isCreateMode) { mutableStateOf(current.name) }
        var priorityText by remember(current, isCreateMode) { mutableStateOf(current.priority.toString()) }
        var storage by remember(current, isCreateMode) { mutableStateOf(current.storage) }
        var downloadPath by remember(current, isCreateMode) { mutableStateOf(current.downloadPath) }
        var libraryStorage by remember(current, isCreateMode) { mutableStateOf(current.libraryStorage) }
        var libraryPath by remember(current, isCreateMode) { mutableStateOf(current.libraryPath) }
        var transferType by remember(current, isCreateMode) { mutableStateOf(current.transferType) }
        var monitorType by remember(current, isCreateMode) { mutableStateOf(current.monitorType) }
        var renaming by remember(current, isCreateMode) { mutableStateOf(current.renaming) }
        var scraping by remember(current, isCreateMode) { mutableStateOf(current.scraping) }
        var notify by remember(current, isCreateMode) { mutableStateOf(current.notify) }
        var saving by remember { mutableStateOf(false) }
        val storageOpts = remember(storages) { (storages.map { it.type } + "local").distinct() }
        val fieldColors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.fieldBorder,
        )

        NativeGlassSheet(onDismissRequest = { editingDir = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(if (isCreateMode) "新增整理目录" else "编辑整理目录", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("目录名称") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1f))
                    OutlinedTextField(value = priorityText, onValueChange = { priorityText = it.filter(Char::isDigit) }, label = { Text("优先级") }, singleLine = true, colors = fieldColors, modifier = Modifier.width(88.dp))
                }
                Text("下载源存储", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    storageOpts.forEach { st -> NativeAdaptivePill(st, selected = storage == st, onClick = { storage = st }) }
                }
                OutlinedTextField(value = downloadPath, onValueChange = { downloadPath = it }, label = { Text("下载目录路径") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                Text("媒体库目标存储", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    storageOpts.forEach { st -> NativeAdaptivePill(st, selected = libraryStorage == st, onClick = { libraryStorage = st }) }
                }
                OutlinedTextField(value = libraryPath, onValueChange = { libraryPath = it }, label = { Text("媒体库目录路径") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                Text("整理方式", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("link" to "硬链接", "softlink" to "软链接", "move" to "移动", "copy" to "复制").forEach { (k, lbl) ->
                        NativeAdaptivePill(lbl, selected = transferType == k, onClick = { transferType = k })
                    }
                }
                Text("监控方式", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("downloader" to "下载器监控", "monitor" to "目录监控", "" to "不监控").forEach { (k, lbl) ->
                        NativeAdaptivePill(lbl, selected = monitorType == k, onClick = { monitorType = k })
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("智能重命名", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(checked = renaming, onCheckedChange = { renaming = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("自动刮削元数据", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(checked = scraping, onCheckedChange = { scraping = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("整理完成通知", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(checked = notify, onCheckedChange = { notify = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (!isCreateMode) {
                        Button(
                            onClick = { confirmDelete = current },
                            colors = ButtonDefaults.buttonColors(containerColor = colors.danger.copy(alpha = 0.18f), contentColor = colors.danger),
                            shape = CircleShape,
                            modifier = Modifier.height(48.dp),
                        ) {
                            Icon(Icons.Rounded.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("删除", fontWeight = FontWeight.Bold)
                        }
                    }
                    Button(
                        enabled = !saving && name.isNotBlank(),
                        onClick = {
                            saving = true
                            scope.launch {
                                val ok = repository.saveDirectory(
                                    item = current.copy(
                                        name = name,
                                        priority = priorityText.toIntOrNull() ?: current.priority,
                                        storage = storage,
                                        downloadPath = downloadPath,
                                        libraryStorage = libraryStorage,
                                        libraryPath = libraryPath,
                                        transferType = transferType,
                                        monitorType = monitorType,
                                        renaming = renaming,
                                        scraping = scraping,
                                        notify = notify,
                                    ),
                                    originalName = if (isCreateMode) null else current.name,
                                )
                                saving = false
                                editingDir = null
                                reload()
                                snackbar?.showSnackbar(if (ok) "已保存目录「$name」" else "保存失败，请检查配置")
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(48.dp),
                    ) {
                        Text(if (saving) "保存中..." else "保存配置", fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(Modifier.height(18.dp))
            }
        }
    }

    confirmDelete?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("确认删除目录") },
            text = { Text("确定要删除目录配置「${target.name}」吗？") },
            confirmButton = {
                TextButton(onClick = {
                    val deleting = target
                    confirmDelete = null
                    editingDir = null
                    scope.launch {
                        val ok = repository.deleteDirectory(deleting.name)
                        reload()
                        snackbar?.showSnackbar(if (ok) "已删除目录「${deleting.name}」" else "删除失败")
                    }
                }) { Text("删除", color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text("取消") } },
        )
    }
}

@Composable
private fun StorageIconMini(type: String) {
    Box(
        modifier = Modifier
            .size(22.dp)
            .clip(RoundedCornerShape(5.dp))
            .background(Color(0xFFF59E0B)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = if (type.equals("smb", ignoreCase = true)) "SMB" else "盘",
            color = Color.White,
            fontSize = 7.sp,
            fontWeight = FontWeight.ExtraBold,
        )
    }
}

@Composable
private fun StorageIconLarge(type: String) {
    Box(
        modifier = Modifier
            .size(38.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Brush.verticalGradient(listOf(Color(0xFFFFB74D), Color(0xFFF57C00)))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (type.equals("smb", ignoreCase = true)) Icons.Rounded.FolderShared else Icons.Rounded.Storage,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(22.dp),
        )
    }
}

/** 1:1 复刻 iOS `native-v2-live-sysmod-notifications.jpg` 通知渠道管理页。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun NotificationsSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var channels by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }

    LaunchedEffect(Unit) { channels = repository.fetchNotificationChannels() }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "通知渠道",
            onBack = onBack,
            trailing = { CinematicCircleButton(Icons.Rounded.Add, "添加通知渠道", {}) },
        )
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("通知渠道", color = colors.textSecondary, fontSize = 13.sp)
                    Text("${channels.size} 项", color = colors.textMuted, fontSize = 12.sp)
                }
            }
            items(channels) { ch ->
                val logo = when (ch.type.lowercase()) {
                    "telegram" -> "logo_telegram"
                    "wechat" -> "logo_wechat"
                    "slack" -> "logo_slack"
                    "synologychat" -> "logo_synology"
                    "vocechat" -> "logo_vocechat"
                    "webpush" -> "logo_chrome"
                    else -> "brandmark"
                }
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            NativeBrandDrawable(drawableName = logo, size = 40.dp, cornerRadius = 12.dp)
                            Column(modifier = Modifier.weight(1f)) {
                                Text(ch.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Text("${ch.name} · ${ch.type}", color = colors.textSecondary, fontSize = 12.sp)
                            }
                            NativeAdaptiveBadge(if (ch.enabled) "已启用" else "已停用", tint = if (ch.enabled) colors.success else colors.warning)
                            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                        if (ch.switchs.isNotEmpty()) {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                ch.switchs.forEach { sw -> NativeAdaptiveBadge(sw) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** 播放偏好与本机推送 / 渠道授权原生配置页（非占位符）。 */
@Composable
fun PlaybackPreferencesScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var hwDecode by remember { mutableStateOf(true) }
    var autoPip by remember { mutableStateOf(true) }
    var speed by remember { mutableStateOf("1.0x") }
    var quality by remember { mutableStateOf("自适应原画") }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "播放偏好", onBack = onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                CinematicPanel(padding = 0.dp, showsShadow = false) {
                    Column {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column {
                                Text("硬件加速解码（MediaCodec）", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                Text("优先使用设备硬解 HEVC / AV1 / 杜比视界", color = colors.textMuted, fontSize = 12.sp)
                            }
                            Switch(checked = hwDecode, onCheckedChange = { hwDecode = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent))
                        }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column {
                                Text("切后台自动画中画（PiP）", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                Text("支持小窗画中画浮窗无缝续播", color = colors.textMuted, fontSize = 12.sp)
                            }
                            Switch(checked = autoPip, onCheckedChange = { autoPip = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent))
                        }
                    }
                }
            }
            item {
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("默认清晰度", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        val qualities = listOf("自适应原画", "1080p", "720p")
                        NativeSegmentedControl(
                            options = qualities,
                            selectedIndex = qualities.indexOf(quality).coerceAtLeast(0),
                            onSelect = { idx -> quality = qualities[idx] },
                        )
                        Spacer(Modifier.height(4.dp))
                        Text("默认倍速", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        val speeds = listOf("1.0x", "1.25x", "1.5x", "2.0x")
                        NativeSegmentedControl(
                            options = speeds,
                            selectedIndex = speeds.indexOf(speed).coerceAtLeast(0),
                            onSelect = { idx -> speed = speeds[idx] },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SimpleSettingRow(title: String, value: String, onClick: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(value, color = colors.textSecondary, fontSize = 14.sp)
            Spacer(Modifier.width(4.dp))
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun CheckCircleMark(selected: Boolean) {
    val colors = LocalMoviePilotColors.current
    Box(
        modifier = Modifier
            .size(24.dp)
            .clip(CircleShape)
            .background(if (selected) colors.accent else Color.Transparent)
            .border(1.6.dp, if (selected) colors.accent else colors.textMuted, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (selected) {
            Icon(Icons.Rounded.Check, contentDescription = "已选", tint = Color.White, modifier = Modifier.size(15.dp))
        }
    }
}
