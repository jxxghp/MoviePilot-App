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
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeNetworkEntityLogo
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.rustbridge.ChannelAuthRecordDto
import com.moviepilot.rustbridge.ChannelBindingCodeDto
import com.moviepilot.rustbridge.DirectoryConfigDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.ServiceConfigDto
import com.moviepilot.rustbridge.SiteItemDto
import com.moviepilot.rustbridge.StorageConfigDto
import com.moviepilot.rustbridge.SubscribeSearchSettingsDto
import com.moviepilot.rustbridge.UserIdentity
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 用户管理页面（统一使用 `ExpressiveTintedScaffold` + `logo_avatar_default` 头像回退）：
 * 支持管理员/普通成员分组展示、新增用户（`POST /api/v1/user/`）与删除非当前用户（`DELETE /api/v1/user/id/{id}`）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UsersManagementScreen(
    repository: MoviePilotRepository,
    currentUserName: String,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current

    var users by remember { mutableStateOf<List<UserIdentity>>(emptyList()) }
    var showCreateSheet by remember { mutableStateOf(false) }
    var confirmDeleteUser by remember { mutableStateOf<UserIdentity?>(null) }

    suspend fun reloadUsers() {
        users = repository.fetchUsers()
    }

    LaunchedEffect(Unit) { reloadUsers() }

    val admins = remember(users) { users.filter { it.isSuperuser } }
    val members = remember(users) { users.filter { !it.isSuperuser } }

    ExpressiveTintedScaffold(
        title = "用户管理 (${users.size})",
        subtitle = "账号角色、权限分配与安全管理",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Outlined.PersonAdd,
                contentDescription = "新增用户",
                onClick = { showCreateSheet = true },
            )
        },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            if (admins.isNotEmpty()) {
                item(key = "users_admins") {
                    UserGroupSection(
                        header = "管理员 (${admins.size})",
                        users = admins,
                        currentUserName = currentUserName,
                        onRequestDelete = { confirmDeleteUser = it },
                    )
                }
            }
            if (members.isNotEmpty()) {
                item(key = "users_members") {
                    UserGroupSection(
                        header = "普通成员 (${members.size})",
                        users = members,
                        currentUserName = currentUserName,
                        onRequestDelete = { confirmDeleteUser = it },
                    )
                }
            }
        }
    }

    if (showCreateSheet) {
        var newName by remember { mutableStateOf("") }
        var newPassword by remember { mutableStateOf("") }
        var newEmail by remember { mutableStateOf("") }
        var isSuperuser by remember { mutableStateOf(false) }
        var isActive by remember { mutableStateOf(true) }
        var permDiscovery by remember { mutableStateOf(true) }
        var permSearch by remember { mutableStateOf(true) }
        var permSubscribe by remember { mutableStateOf(true) }
        var permManage by remember { mutableStateOf(false) }
        var creating by remember { mutableStateOf(false) }
        val fieldColors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.fieldBorder,
        )

        NativeGlassSheet(onDismissRequest = { showCreateSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("新增用户账号", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = newName,
                    onValueChange = { newName = it },
                    label = { Text("用户名") },
                    singleLine = true,
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    label = { Text("初始登录密码") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = newEmail,
                    onValueChange = { newEmail = it },
                    label = { Text("邮箱（可选）") },
                    singleLine = true,
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("设为超级管理员", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(
                        checked = isSuperuser,
                        onCheckedChange = { isSuperuser = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
                    )
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("启用此账号", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(
                        checked = isActive,
                        onCheckedChange = { isActive = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
                    )
                }
                if (!isSuperuser) {
                    HorizontalDivider(color = colors.divider)
                    Text("细粒度功能权限", color = colors.textSecondary, fontSize = 12.5.sp)
                    PermissionToggleRow("探索与推荐浏览", permDiscovery) { permDiscovery = it }
                    PermissionToggleRow("站点资源搜索", permSearch) { permSearch = it }
                    PermissionToggleRow("影视订阅管理", permSubscribe) { permSubscribe = it }
                    PermissionToggleRow("下载与整理文件管理", permManage) { permManage = it }
                }
                Button(
                    enabled = !creating && newName.isNotBlank() && newPassword.isNotBlank(),
                    onClick = {
                        creating = true
                        scope.launch {
                            val perms = if (isSuperuser) {
                                mapOf("discovery" to true, "search" to true, "subscribe" to true, "manage" to true)
                            } else {
                                mapOf(
                                    "discovery" to permDiscovery,
                                    "search" to permSearch,
                                    "subscribe" to permSubscribe,
                                    "manage" to permManage,
                                )
                            }
                            val (ok, msg) = repository.createUser(
                                name = newName,
                                password = newPassword,
                                email = newEmail,
                                isSuperuser = isSuperuser,
                                isActive = isActive,
                                permissions = perms,
                            )
                            creating = false
                            if (ok) {
                                showCreateSheet = false
                                reloadUsers()
                            }
                            snackbar?.showSnackbar(msg)
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Text(if (creating) "正在创建…" else "创建用户", fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    confirmDeleteUser?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDeleteUser = null },
            title = { Text("确认删除用户") },
            text = { Text("确定要永久删除账号「${target.name}」吗？") },
            dismissButton = {
                TextButton(onClick = { confirmDeleteUser = null }) { Text("取消") }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val deleting = target
                        confirmDeleteUser = null
                        scope.launch {
                            val (ok, msg) = repository.deleteUserById(deleting.id)
                            if (ok) reloadUsers()
                            snackbar?.showSnackbar(msg)
                        }
                    },
                ) {
                    Text("确认删除", color = colors.danger)
                }
            },
        )
    }
}

@Composable
private fun PermissionToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = colors.textPrimary, fontSize = 13.5.sp)
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
        )
    }
}

@Composable
private fun UserGroupSection(
    header: String,
    users: List<UserIdentity>,
    currentUserName: String,
    onRequestDelete: (UserIdentity) -> Unit,
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
                        NativeNetworkEntityLogo(
                            imageUrl = user.avatar,
                            kind = "avatar",
                            value = user.name,
                            size = 44.dp,
                            cornerRadius = 22.dp,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(user.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                if (isCurrent) {
                                    NativeAdaptiveBadge("当前", tint = colors.info)
                                }
                                if (user.isOtp) {
                                    NativeAdaptiveBadge("2FA", tint = colors.brand)
                                }
                            }
                            if (user.email.isNotBlank()) {
                                Text(user.email, color = colors.textSecondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                        NativeAdaptiveBadge(
                            if (user.isActive) "正常" else "停用",
                            tint = if (user.isActive) colors.success else colors.danger,
                        )
                        if (!isCurrent && user.id > 0) {
                            Spacer(Modifier.width(4.dp))
                            IconButton(
                                onClick = { onRequestDelete(user) },
                                modifier = Modifier.size(34.dp),
                            ) {
                                Icon(
                                    Icons.Rounded.Delete,
                                    contentDescription = "删除用户 ${user.name}",
                                    tint = colors.danger,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                    if (idx < users.lastIndex) {
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 72.dp))
                    }
                }
            }
        }
    }
}

/**
 * 订阅与搜索配置页（统一使用 `ExpressiveTintedScaffold`，站点多选面板展示真实站点 Favicon 与 `logo_site` 回退）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscribeSearchSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()

    var settings by remember { mutableStateOf(SubscribeSearchSettingsDto()) }
    var allSites by remember { mutableStateOf<List<SiteItemDto>>(emptyList()) }
    val siteIcons = remember { mutableStateMapOf<Int, String>() }
    var pickerTarget by remember { mutableStateOf<String?>(null) } // "rss" | "indexer"
    var savedNotice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        settings = repository.fetchSubscribeSearchSettings()
        val loadedSites = repository.fetchSites()
        allSites = loadedSites
        loadedSites.forEach { site ->
            site.iconUrl?.let { siteIcons[site.id] = it }
        }
    }

    ExpressiveTintedScaffold(
        title = "订阅与搜索",
        subtitle = "站点范围、优先级规则组与刷新策略",
        onBack = onBack,
        actions = {
            Surface(
                onClick = {
                    scope.launch {
                        repository.saveSettingValue("RssSites", settings.rssSiteIds.joinToString(",", "[", "]"))
                        repository.saveSettingValue("IndexerSites", settings.indexerSiteIds.joinToString(",", "[", "]"))
                        repository.saveSettingValue("SUBSCRIBE_MODE", "\"${settings.subscribeMode}\"")
                        savedNotice = "已保存站点范围与订阅刷新配置"
                    }
                },
                shape = CircleShape,
                color = colors.accent,
                contentColor = colors.primaryButtonFg,
            ) {
                Text(
                    "保存",
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 9.dp),
                )
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            savedNotice?.let {
                Text(it, color = colors.success, fontSize = 12.5.sp, modifier = Modifier.padding(horizontal = margin, vertical = 8.dp))
            }

            LazyColumn(
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 14.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(18.dp),
                modifier = Modifier.weight(1f),
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
                        CinematicPanel(padding = 16.dp, showsShadow = false) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text("订阅模式", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    NativeAdaptivePill(
                                        title = "站点爬虫",
                                        selected = settings.subscribeMode != "rss",
                                        onClick = { settings = settings.copy(subscribeMode = "spider") },
                                    )
                                    NativeAdaptivePill(
                                        title = "RSS 订阅",
                                        selected = settings.subscribeMode == "rss",
                                        onClick = { settings = settings.copy(subscribeMode = "rss") },
                                    )
                                }
                            }
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
                LazyColumn(modifier = Modifier.fillMaxWidth().weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(allSites, key = { it.id }) { site ->
                        LaunchedEffect(site.id) {
                            if (!siteIcons.containsKey(site.id)) {
                                repository.fetchSiteIcon(site.id)?.let { siteIcons[site.id] = it }
                            }
                        }
                        val selected = site.id in currentIds
                        CinematicPanel(
                            padding = 12.dp,
                            modifier = Modifier.clickable {
                                val next = if (selected) currentIds - site.id else currentIds + site.id
                                settings = if (target == "rss") settings.copy(rssSiteIds = next) else settings.copy(indexerSiteIds = next)
                            },
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                NativeNetworkEntityLogo(
                                    imageUrl = siteIcons[site.id] ?: site.iconUrl,
                                    kind = "site",
                                    value = site.name,
                                    size = 30.dp,
                                    cornerRadius = 8.dp,
                                )
                                Text(
                                    site.name,
                                    color = colors.textPrimary,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium,
                                    modifier = Modifier.weight(1f),
                                )
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

/**
 * 媒体数据源配置页（统一使用 `ExpressiveTintedScaffold` + 官方 `TMDB` / `豆瓣` / `Bangumi` / `MusicBrainz` 徽标与精细化角标）。
 */
@Composable
fun MediaSourcesSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()

    data class SourceSpec(
        val id: String,
        val title: String,
        val subtitle: String,
        val categoryTag: String,
        val hasBrandLogo: Boolean,
        val monogram: String = "",
        val monogramTint: Color = Color(0xFF5D4BCE),
    )

    val allSources = remember {
        listOf(
            SourceSpec("themoviedb", "TheMovieDb", "全球电影剧集海报、ClearLogo 与元数据", "影视核心", hasBrandLogo = true),
            SourceSpec("douban", "豆瓣电影", "中文影评、院线热映与高分榜单", "中文影视", hasBrandLogo = true),
            SourceSpec("bangumi", "Bangumi 番组计划", "每日新番放送与动画剧集索引", "番剧动画", hasBrandLogo = true),
            SourceSpec("musicbrainz", "MusicBrainz", "全球音乐艺人、专辑发行与曲目索引", "无损音乐", hasBrandLogo = true),
            SourceSpec("douban_music", "豆瓣音乐", "中文唱片排行、专辑封面与评分", "华语音乐", hasBrandLogo = true),
            SourceSpec("imdb", "IMDb", "全球权威影视评分与演职员资料库", "评分索引", hasBrandLogo = false, monogram = "IMDb", monogramTint = Color(0xFFEAB308)),
            SourceSpec("tvdb", "TheTVDB", "剧集分季、特殊集号与播出排期", "剧集排期", hasBrandLogo = false, monogram = "TVDB", monogramTint = Color(0xFF10B981)),
            SourceSpec("theaudiodb", "TheAudioDB", "音乐艺人写真、专辑高清封面库", "音乐封面", hasBrandLogo = false, monogram = "ADB", monogramTint = Color(0xFF06B6D4)),
        )
    }

    var selected by remember { mutableStateOf(setOf("themoviedb")) }
    var notice by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        selected = repository.fetchSearchSources()
    }

    ExpressiveTintedScaffold(
        title = "媒体数据源",
        subtitle = "已启用 ${selected.size} 个搜索与刮削来源",
        onBack = onBack,
        actions = {
            Surface(
                onClick = {
                    scope.launch {
                        val csv = selected.joinToString(",")
                        repository.saveSettingValue("SEARCH_SOURCE", "\"$csv\"")
                        notice = "已保存媒体搜索数据源"
                    }
                },
                shape = CircleShape,
                color = colors.accent,
                contentColor = colors.primaryButtonFg,
            ) {
                Text(
                    "保存",
                    fontSize = 13.5.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 9.dp),
                )
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            notice?.let {
                Text(it, color = colors.success, fontSize = 12.5.sp, modifier = Modifier.padding(horizontal = margin, vertical = 8.dp))
            }

            LazyColumn(
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 14.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(allSources, key = { it.id }) { src ->
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
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (src.hasBrandLogo) {
                                NativeEntityLogo(
                                    kind = "datasource",
                                    value = src.id,
                                    size = 42.dp,
                                    cornerRadius = 12.dp,
                                )
                            } else {
                                Box(
                                    modifier = Modifier
                                        .size(42.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(src.monogramTint.copy(alpha = if (colors.isDark) 0.24f else 0.16f))
                                        .border(0.8.dp, src.monogramTint.copy(alpha = 0.45f), RoundedCornerShape(12.dp)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        text = src.monogram,
                                        color = src.monogramTint,
                                        fontSize = 11.sp,
                                        fontWeight = FontWeight.ExtraBold,
                                    )
                                }
                            }
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(src.title, color = colors.textPrimary, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
                                    NativeAdaptiveBadge(src.categoryTag, tint = if (isSel) colors.accent else colors.textMuted)
                                }
                                Text(src.subtitle, color = colors.textSecondary, fontSize = 12.sp)
                            }
                            CheckCircleMark(selected = isSel)
                        }
                    }
                }
                item {
                    Text(
                        "仅展示后端已支持的媒体数据源模块；关闭或启用底层插件模块可在插件中心与 Web 高级设置中调整。",
                        color = colors.textMuted,
                        fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 4.dp),
                    )
                }
            }
        }
    }
}

/**
 * 下载器管理页（统一使用 `ExpressiveTintedScaffold`，在卡片与编辑面板类型胶囊全量展示 `qBittorrent` / `Transmission` / `rTorrent` 官方品牌 Logo）。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun DownloadersSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    var list by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
    var editingItem by remember { mutableStateOf<ServiceConfigDto?>(null) }
    var isCreateMode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<ServiceConfigDto?>(null) }

    suspend fun reload() { list = repository.fetchDownloaders() }
    LaunchedEffect(Unit) { reload() }

    ExpressiveTintedScaffold(
        title = "下载器",
        subtitle = "已配置 ${list.size} 个下载客户端",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Add,
                contentDescription = "添加下载器",
                onClick = {
                    isCreateMode = true
                    editingItem = ServiceConfigDto(name = "", type = "qbittorrent", enabled = true, isDefault = list.isEmpty())
                },
            )
        },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(list, key = { it.name }) { dl ->
                CinematicPanel(
                    padding = 16.dp,
                    modifier = Modifier.clickable {
                        isCreateMode = false
                        editingItem = dl
                    },
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        NativeEntityLogo(
                            kind = "downloader",
                            value = dl.type.ifBlank { dl.name },
                            size = 42.dp,
                            cornerRadius = 12.dp,
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(dl.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                if (dl.isDefault) NativeAdaptiveBadge("默认", tint = colors.brand)
                            }
                            Text(
                                "${dl.type} · ${dl.host.ifBlank { "已配置" }}",
                                color = colors.textSecondary,
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
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
        val downloaderTypes = remember {
            listOf(
                "qbittorrent" to "qBittorrent",
                "transmission" to "Transmission",
                "rtorrent" to "rTorrent",
            )
        }

        NativeGlassSheet(onDismissRequest = { editingItem = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(if (isCreateMode) "新增下载器" else "编辑下载器", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    downloaderTypes.forEach { (k, lbl) ->
                        NativeAdaptivePill(
                            title = lbl,
                            selected = type.equals(k, ignoreCase = true),
                            leadingContent = {
                                NativeEntityLogo(kind = "downloader", value = k, size = 18.dp, cornerRadius = 5.dp)
                            },
                            onClick = { type = k },
                        )
                    }
                }
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("名称") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = host, onValueChange = { host = it }, label = { Text("服务地址（如 http://127.0.0.1:8080）") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = username, onValueChange = { username = it }, label = { Text("用户名") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(value = password, onValueChange = { password = it }, label = { Text("密码") }, singleLine = true, visualTransformation = PasswordVisualTransformation(), colors = fieldColors, modifier = Modifier.fillMaxWidth())
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

/**
 * 媒体服务器管理页（统一使用 `ExpressiveTintedScaffold`，在卡片与类型选择胶囊全量呈现 `Emby` / `Jellyfin` / `Plex` / `飞牛` / `绿联` / `极空间` 官方品牌 Logo）。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun MediaServersSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    var list by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
    var editingItem by remember { mutableStateOf<ServiceConfigDto?>(null) }
    var isCreateMode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<ServiceConfigDto?>(null) }

    suspend fun reload() { list = repository.fetchMediaServers() }
    LaunchedEffect(Unit) { reload() }

    ExpressiveTintedScaffold(
        title = "媒体服务器",
        subtitle = "已接入 ${list.size} 个播放服务端",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Add,
                contentDescription = "添加媒体服务器",
                onClick = {
                    isCreateMode = true
                    editingItem = ServiceConfigDto(name = "", type = "emby", enabled = true)
                },
            )
        },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(list, key = { it.name }) { ms ->
                CinematicPanel(
                    padding = 16.dp,
                    modifier = Modifier.clickable {
                        isCreateMode = false
                        editingItem = ms
                    },
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        NativeEntityLogo(
                            kind = "mediaserver",
                            value = ms.type.ifBlank { ms.name },
                            size = 42.dp,
                            cornerRadius = 12.dp,
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(ms.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text(
                                "${ms.type} · ${ms.host.ifBlank { "已配置" }}",
                                color = colors.textSecondary,
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
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
        val serverTypes = remember {
            listOf(
                "emby" to "Emby",
                "jellyfin" to "Jellyfin",
                "plex" to "Plex",
                "trimemedia" to "飞牛影视",
                "ugreen" to "绿联影视",
                "zspace" to "极空间",
            )
        }

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
                    serverTypes.forEach { (k, lbl) ->
                        NativeAdaptivePill(
                            title = lbl,
                            selected = type.equals(k, ignoreCase = true),
                            leadingContent = {
                                NativeEntityLogo(kind = "mediaserver", value = k, size = 18.dp, cornerRadius = 5.dp)
                            },
                            onClick = { type = k },
                        )
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

private fun formatStorageLabel(type: String): String = when (type.trim().lowercase()) {
    "local" -> "本地存储"
    "smb" -> "SMB"
    "u115", "115" -> "115网盘"
    "alipan", "aliyun" -> "阿里云盘"
    "rclone" -> "Rclone"
    else -> type
}

/**
 * 目录与存储页（统一使用 `ExpressiveTintedScaffold`，在整理目录卡、挂载存储卡与存储类型胶囊全量呈现 `本地` / `SMB` / `115` / `阿里云盘` / `Rclone` 官方品牌 Logo）。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun DirectoriesStorageSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
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

    ExpressiveTintedScaffold(
        title = "整理与目录",
        subtitle = "目录映射与多网盘挂载",
        onBack = onBack,
        actions = {
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
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item(key = "dirs_section") {
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
                                        NativeEntityLogo(kind = "storage", value = d.storage, size = 22.dp, cornerRadius = 6.dp)
                                        Text(
                                            text = "${formatStorageLabel(d.storage)} · ${d.downloadPath}",
                                            color = colors.textPrimary,
                                            fontSize = 13.sp,
                                            fontFamily = FontFamily.Monospace,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }
                                if (d.libraryPath.isNotBlank()) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        NativeEntityLogo(kind = "storage", value = d.libraryStorage, size = 22.dp, cornerRadius = 6.dp)
                                        Text(
                                            text = "${formatStorageLabel(d.libraryStorage)} · ${d.libraryPath}",
                                            color = colors.textPrimary,
                                            fontSize = 13.sp,
                                            fontFamily = FontFamily.Monospace,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
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

            item(key = "mounted_storages_section") {
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
                                    NativeEntityLogo(
                                        kind = "storage",
                                        value = st.type.ifBlank { st.name },
                                        size = 40.dp,
                                        cornerRadius = 11.dp,
                                    )
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(st.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                        Text(formatStorageLabel(st.type), color = colors.textSecondary, fontSize = 12.sp)
                                    }
                                    NativeAdaptiveBadge("已挂载", tint = colors.success)
                                }
                                if (idx < storages.lastIndex) {
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 68.dp))
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
        val storageOpts = remember(storages) {
            (listOf("local", "smb", "u115", "alipan", "rclone") + storages.map { it.type }).distinct()
        }
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
                    storageOpts.forEach { st ->
                        NativeAdaptivePill(
                            title = formatStorageLabel(st),
                            selected = storage.equals(st, ignoreCase = true),
                            leadingContent = {
                                NativeEntityLogo(kind = "storage", value = st, size = 18.dp, cornerRadius = 5.dp)
                            },
                            onClick = { storage = st },
                        )
                    }
                }
                OutlinedTextField(value = downloadPath, onValueChange = { downloadPath = it }, label = { Text("下载目录路径") }, singleLine = true, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                Text("媒体库目标存储", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    storageOpts.forEach { st ->
                        NativeAdaptivePill(
                            title = formatStorageLabel(st),
                            selected = libraryStorage.equals(st, ignoreCase = true),
                            leadingContent = {
                                NativeEntityLogo(kind = "storage", value = st, size = 18.dp, cornerRadius = 5.dp)
                            },
                            onClick = { libraryStorage = st },
                        )
                    }
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

private data class NotificationFieldSpec(val key: String, val label: String, val secret: Boolean = false)
private data class NotificationTypeMeta(val id: String, val label: String, val fields: List<NotificationFieldSpec>)

private val ALL_NOTIFICATION_TYPES: List<NotificationTypeMeta> = listOf(
    NotificationTypeMeta(
        "telegram",
        "Telegram",
        listOf(
            NotificationFieldSpec("TELEGRAM_TOKEN", "Bot Token", secret = true),
            NotificationFieldSpec("TELEGRAM_CHAT_ID", "Chat ID"),
            NotificationFieldSpec("TELEGRAM_ADMINS", "管理员 ID（可选）"),
        ),
    ),
    NotificationTypeMeta(
        "wechat",
        "微信 / 企业微信",
        listOf(
            NotificationFieldSpec("WECHAT_CORPID", "企业 ID (CorpID)"),
            NotificationFieldSpec("WECHAT_APP_ID", "应用 AgentId"),
            NotificationFieldSpec("WECHAT_APP_SECRET", "应用 Secret", secret = true),
            NotificationFieldSpec("WECHAT_PROXY", "微信代理地址（可选）"),
        ),
    ),
    NotificationTypeMeta(
        "feishu",
        "飞书",
        listOf(
            NotificationFieldSpec("FEISHU_APP_ID", "飞书 App ID / Webhook"),
            NotificationFieldSpec("FEISHU_APP_SECRET", "飞书 App Secret", secret = true),
        ),
    ),
    NotificationTypeMeta(
        "clawbot",
        "ClawBot",
        listOf(
            NotificationFieldSpec("CLAWBOT_HOST", "ClawBot 服务地址"),
            NotificationFieldSpec("CLAWBOT_TOKEN", "访问令牌 Token", secret = true),
        ),
    ),
    NotificationTypeMeta(
        "qq",
        "QQ",
        listOf(
            NotificationFieldSpec("QQ_BOT_URL", "OneBot / NapCat HTTP 地址"),
            NotificationFieldSpec("QQ_TOKEN", "Access Token（可选）", secret = true),
            NotificationFieldSpec("QQ_USER_ID", "目标 QQ 号或群号"),
        ),
    ),
    NotificationTypeMeta(
        "vocechat",
        "VoceChat",
        listOf(
            NotificationFieldSpec("VOCECHAT_HOST", "VoceChat 地址"),
            NotificationFieldSpec("VOCECHAT_API_KEY", "Bot API Key", secret = true),
            NotificationFieldSpec("VOCECHAT_CHANNEL_ID", "频道或用户 ID"),
        ),
    ),
    NotificationTypeMeta(
        "synologychat",
        "SynologyChat",
        listOf(
            NotificationFieldSpec("SYNOLOGYCHAT_WEBHOOK", "Incoming Webhook 地址"),
            NotificationFieldSpec("SYNOLOGYCHAT_TOKEN", "Outgoing Token（可选）", secret = true),
        ),
    ),
    NotificationTypeMeta(
        "slack",
        "Slack",
        listOf(
            NotificationFieldSpec("SLACK_OAUTH_TOKEN", "Bot User OAuth Token", secret = true),
            NotificationFieldSpec("SLACK_APP_TOKEN", "App-Level Token（可选）", secret = true),
            NotificationFieldSpec("SLACK_CHANNEL", "默认频道名（如 #moviepilot）"),
        ),
    ),
    NotificationTypeMeta(
        "discord",
        "Discord",
        listOf(
            NotificationFieldSpec("DISCORD_BOT_TOKEN", "Bot Token 或 Webhook", secret = true),
            NotificationFieldSpec("DISCORD_GUILD_ID", "服务器 / 频道 ID"),
        ),
    ),
    NotificationTypeMeta(
        "dingtalk",
        "钉钉",
        listOf(
            NotificationFieldSpec("DINGTALK_WEBHOOK", "机器人 Webhook / AppKey"),
            NotificationFieldSpec("DINGTALK_SECRET", "加签密钥 / AppSecret", secret = true),
        ),
    ),
    NotificationTypeMeta(
        "webpush",
        "WebPush",
        listOf(
            NotificationFieldSpec("WEBPUSH_SUBJECT", "推送联系邮箱 (mailto:...)"),
        ),
    ),
)

private val NOTIFICATION_SCENARIOS = listOf(
    "资源下载",
    "整理入库",
    "订阅",
    "站点",
    "媒体服务器",
    "手动处理",
    "插件",
    "其它",
)

private fun notificationTypeLabel(type: String): String =
    ALL_NOTIFICATION_TYPES.firstOrNull { it.id.equals(type.trim(), ignoreCase = true) }?.label ?: type

/**
 * 通知渠道完整管理页（新增 / 点击编辑 / 删除 CRUD，持久化至 `/api/v1/system/setting/Notifications`）：
 * 全量支持全部 11 类官方通知渠道品牌徽标（`微信`、`ClawBot`、`飞书`、`Telegram`、`QQ`、`VoceChat`、`SynologyChat`、`Slack`、`Discord`、`钉钉`、`WebPush`）。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun NotificationsSettingsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current

    var channels by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
    var editingChannel by remember { mutableStateOf<ServiceConfigDto?>(null) }
    var isCreateMode by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf<ServiceConfigDto?>(null) }

    suspend fun reload() {
        channels = repository.fetchNotificationChannels()
    }
    LaunchedEffect(Unit) { reload() }

    ExpressiveTintedScaffold(
        title = "通知渠道",
        subtitle = "已配置 ${channels.size} 个消息推送通道",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Add,
                contentDescription = "添加通知渠道",
                onClick = {
                    isCreateMode = true
                    editingChannel = ServiceConfigDto(
                        name = "",
                        type = "telegram",
                        enabled = true,
                        switchs = listOf("资源下载", "整理入库", "订阅"),
                    )
                },
            )
        },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (channels.isEmpty()) {
                item(key = "notif_empty") {
                    CinematicPanel(padding = 20.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("暂未配置通知渠道", color = colors.textPrimary, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
                            Text("点击右上角「+」即可添加微信、Telegram、飞书、Slack、Discord、钉钉、QQ 等 11 类消息渠道。", color = colors.textSecondary, fontSize = 13.sp)
                        }
                    }
                }
            }
            items(channels, key = { it.name }) { ch ->
                CinematicPanel(
                    padding = 16.dp,
                    modifier = Modifier.clickable {
                        isCreateMode = false
                        editingChannel = ch
                    },
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            NativeEntityLogo(
                                kind = "notification",
                                value = ch.type.ifBlank { ch.name },
                                size = 42.dp,
                                cornerRadius = 12.dp,
                            )
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(ch.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Text(notificationTypeLabel(ch.type), color = colors.textSecondary, fontSize = 12.sp)
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

    editingChannel?.let { current ->
        var name by remember(current, isCreateMode) { mutableStateOf(current.name) }
        var type by remember(current, isCreateMode) { mutableStateOf(current.type.ifBlank { "telegram" }.lowercase()) }
        var enabled by remember(current, isCreateMode) { mutableStateOf(current.enabled) }
        var switchs by remember(current, isCreateMode) { mutableStateOf(current.switchs.toSet()) }
        val draftConfig = remember(current, isCreateMode) {
            mutableStateMapOf<String, String>().apply { putAll(current.config) }
        }
        var saving by remember { mutableStateOf(false) }

        val activeMeta = remember(type) {
            ALL_NOTIFICATION_TYPES.firstOrNull { it.id.equals(type, ignoreCase = true) } ?: ALL_NOTIFICATION_TYPES.first()
        }
        val fieldColors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.fieldBorder,
        )

        NativeGlassSheet(onDismissRequest = { editingChannel = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    if (isCreateMode) "新增通知渠道" else "编辑通知渠道",
                    color = colors.textPrimary,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text("选择渠道平台（11 类官方通道）", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ALL_NOTIFICATION_TYPES.forEach { meta ->
                        val selected = type.equals(meta.id, ignoreCase = true)
                        NativeAdaptivePill(
                            title = meta.label,
                            selected = selected,
                            leadingContent = {
                                NativeEntityLogo(
                                    kind = "notification",
                                    value = meta.id,
                                    size = 18.dp,
                                    cornerRadius = 5.dp,
                                )
                            },
                            onClick = {
                                type = meta.id
                                if (isCreateMode && name.isBlank()) {
                                    name = meta.label
                                }
                            },
                        )
                    }
                }
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("渠道实例名称") },
                    placeholder = { Text("例如：我的 ${activeMeta.label}") },
                    singleLine = true,
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth(),
                )
                activeMeta.fields.forEach { spec ->
                    OutlinedTextField(
                        value = draftConfig[spec.key].orEmpty(),
                        onValueChange = { draftConfig[spec.key] = it },
                        label = { Text(spec.label) },
                        singleLine = true,
                        visualTransformation = if (spec.secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
                        colors = fieldColors,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Text("推送消息场景（多选）", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NOTIFICATION_SCENARIOS.forEach { sc ->
                        val isSel = sc in switchs
                        NativeAdaptivePill(
                            title = sc,
                            selected = isSel,
                            onClick = { switchs = if (isSel) switchs - sc else switchs + sc },
                        )
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("启用此通知渠道", color = colors.textPrimary, fontSize = 14.sp)
                    Switch(
                        checked = enabled,
                        onCheckedChange = { enabled = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
                    )
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
                                val ok = repository.saveNotificationChannel(
                                    item = current.copy(
                                        name = name.trim(),
                                        type = type,
                                        enabled = enabled,
                                        switchs = NOTIFICATION_SCENARIOS.filter { it in switchs },
                                        config = draftConfig.toMap(),
                                    ),
                                    originalName = if (isCreateMode) null else current.name,
                                )
                                saving = false
                                editingChannel = null
                                reload()
                                snackbar?.showSnackbar(if (ok) "已保存通知渠道「${name.trim()}」" else "保存通知渠道失败")
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(48.dp),
                    ) {
                        Text(if (saving) "保存中…" else "保存渠道配置", fontWeight = FontWeight.Bold)
                    }
                }
                Spacer(Modifier.height(18.dp))
            }
        }
    }

    confirmDelete?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("确认删除通知渠道") },
            text = { Text("确定要删除通知渠道「${target.name}」吗？") },
            confirmButton = {
                TextButton(onClick = {
                    val deleting = target
                    confirmDelete = null
                    editingChannel = null
                    scope.launch {
                        val ok = repository.deleteNotificationChannel(deleting.name)
                        reload()
                        snackbar?.showSnackbar(if (ok) "已删除通知渠道「${deleting.name}」" else "删除失败")
                    }
                }) { Text("删除", color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = null }) { Text("取消") } },
        )
    }
}

/**
 * 渠道授权管理页（对接 `/api/v1/authorization`）：
 * - 支持一键生成 5 分钟短效绑定授权码（实时倒计时 + 复制验证码/复制绑定指令）；
 * - 支持查看已授权及待审批的机器人交互账号，管理员可直接批准或移除绑定。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChannelAuthorizationScreen(
    repository: MoviePilotRepository,
    isAdmin: Boolean = true,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current

    var bindingCode by remember { mutableStateOf<ChannelBindingCodeDto?>(null) }
    var remainingSeconds by remember { mutableIntStateOf(0) }
    var isGenerating by remember { mutableStateOf(false) }
    var codeError by remember { mutableStateOf<String?>(null) }

    var records by remember { mutableStateOf<List<ChannelAuthRecordDto>>(emptyList()) }
    var isLoadingRecords by remember { mutableStateOf(true) }
    var confirmRemoveRecord by remember { mutableStateOf<ChannelAuthRecordDto?>(null) }

    suspend fun reloadRecords() {
        isLoadingRecords = true
        records = repository.fetchChannelAuthorizations()
        isLoadingRecords = false
    }

    LaunchedEffect(Unit) { reloadRecords() }

    LaunchedEffect(bindingCode) {
        val codeSnap = bindingCode ?: return@LaunchedEffect
        while (true) {
            val elapsed = ((System.currentTimeMillis() - codeSnap.createdAtEpochMs) / 1000L).toInt()
            val left = (codeSnap.expiresInSeconds - elapsed).coerceAtLeast(0)
            remainingSeconds = left
            if (left <= 0) break
            delay(1_000L)
        }
    }

    ExpressiveTintedScaffold(
        title = "渠道授权",
        subtitle = "机器人 5 分钟绑定码与授权审批",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Refresh,
                contentDescription = "刷新授权列表",
                onClick = { scope.launch { reloadRecords() } },
            )
        },
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(key = "auth_code_generator") {
                CinematicPanel(padding = 18.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Box(
                                modifier = Modifier
                                    .size(40.dp)
                                    .clip(CircleShape)
                                    .background(colors.accent.copy(alpha = 0.16f)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.Key, contentDescription = null, tint = colors.accent, modifier = Modifier.size(21.dp))
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text("5 分钟短效绑定授权码", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Text("在机器人私聊中发送绑定指令即可关联当前 MoviePilot 账号", color = colors.textSecondary, fontSize = 12.sp)
                            }
                        }

                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf("telegram", "wechat", "feishu", "slack", "discord", "dingtalk", "qq", "vocechat", "clawbot").forEach { ch ->
                                NativeEntityLogo(kind = "notification", value = ch, size = 26.dp, cornerRadius = 7.dp)
                            }
                        }

                        val activeCode = bindingCode?.takeIf { remainingSeconds > 0 }
                        if (activeCode != null) {
                            val mm = remainingSeconds / 60
                            val ss = remainingSeconds % 60
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(colors.chipFill)
                                    .border(1.dp, colors.accent.copy(alpha = 0.45f), RoundedCornerShape(16.dp))
                                    .padding(16.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    text = activeCode.code,
                                    color = colors.accent,
                                    fontSize = 28.sp,
                                    fontWeight = FontWeight.ExtraBold,
                                    fontFamily = FontFamily.Monospace,
                                )
                                NativeAdaptiveBadge(
                                    text = String.format("有效期剩余 %02d:%02d", mm, ss),
                                    tint = if (remainingSeconds <= 60) colors.warning else colors.success,
                                )
                                Text(
                                    text = activeCode.commandHint,
                                    color = colors.textSecondary,
                                    fontSize = 12.5.sp,
                                    fontFamily = FontFamily.Monospace,
                                )
                                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    NativeAdaptivePill(
                                        title = "复制绑定码",
                                        selected = false,
                                        icon = Icons.Rounded.ContentCopy,
                                        onClick = {
                                            clipboard.setText(AnnotatedString(activeCode.code))
                                            scope.launch { snackbar?.showSnackbar("已复制绑定码 ${activeCode.code}") }
                                        },
                                    )
                                    NativeAdaptivePill(
                                        title = "复制完整指令",
                                        selected = true,
                                        icon = Icons.Rounded.ContentCopy,
                                        onClick = {
                                            clipboard.setText(AnnotatedString(activeCode.commandHint))
                                            scope.launch { snackbar?.showSnackbar("已复制指令 ${activeCode.commandHint}") }
                                        },
                                    )
                                }
                            }
                        }

                        codeError?.let { err ->
                            Text(err, color = colors.warning, fontSize = 12.5.sp)
                        }

                        Button(
                            enabled = !isGenerating,
                            onClick = {
                                scope.launch {
                                    isGenerating = true
                                    codeError = null
                                    repository.generateChannelBindingCode()
                                        .onSuccess { dto ->
                                            bindingCode = dto
                                            remainingSeconds = dto.expiresInSeconds
                                        }
                                        .onFailure { e ->
                                            codeError = e.message ?: "生成绑定码失败"
                                        }
                                    isGenerating = false
                                }
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                            shape = CircleShape,
                            modifier = Modifier.fillMaxWidth().height(48.dp),
                        ) {
                            if (isGenerating) {
                                CircularProgressIndicator(color = colors.primaryButtonFg, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(8.dp))
                            }
                            Text(
                                if (isGenerating) "正在生成…" else if (activeCode != null) "重新生成绑定码" else "生成 5 分钟绑定码",
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }
            }

            item(key = "auth_records_header") {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("已关联与待审批渠道账号", color = colors.textSecondary, fontSize = 13.sp)
                    Text("${records.size} 项", color = colors.textMuted, fontSize = 12.sp)
                }
            }

            if (isLoadingRecords && records.isEmpty()) {
                item(key = "auth_records_loading") {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 28.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = colors.accent)
                    }
                }
            } else if (records.isEmpty()) {
                item(key = "auth_records_empty") {
                    CinematicPanel(padding = 20.dp, showsShadow = false) {
                        Text(
                            "暂无已绑定的外部渠道账号。生成上方 5 分钟授权码后，在 Telegram / 微信 / 飞书等机器人对话框发送绑定指令即可完成授权。",
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                        )
                    }
                }
            } else {
                items(records, key = { it.id }) { rec ->
                    val isPending = rec.status == "pending"
                    CinematicPanel(padding = 15.dp) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            NativeEntityLogo(
                                kind = "notification",
                                value = rec.channel,
                                size = 40.dp,
                                cornerRadius = 11.dp,
                            )
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Text(
                                        text = rec.channelUsername.ifBlank { rec.channelUserId },
                                        color = colors.textPrimary,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Bold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    NativeAdaptiveBadge(
                                        text = if (isPending) "待审批" else "已授权",
                                        tint = if (isPending) colors.warning else colors.success,
                                    )
                                }
                                val sub = buildList {
                                    add(notificationTypeLabel(rec.channel))
                                    if (rec.boundUsername.isNotBlank()) add("绑定至 ${rec.boundUsername}")
                                    if (rec.createdAt.isNotBlank()) add(rec.createdAt)
                                }.joinToString(" · ")
                                Text(sub, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            if (isPending && isAdmin) {
                                NativeAdaptivePill(
                                    title = "批准",
                                    selected = true,
                                    onClick = {
                                        scope.launch {
                                            val (ok, msg) = repository.approveChannelAuthorization(rec.id)
                                            if (ok) reloadRecords()
                                            snackbar?.showSnackbar(msg)
                                        }
                                    },
                                )
                            }
                            if (isAdmin) {
                                IconButton(
                                    onClick = { confirmRemoveRecord = rec },
                                    modifier = Modifier.size(34.dp),
                                ) {
                                    Icon(Icons.Rounded.Delete, contentDescription = "解除绑定", tint = colors.danger, modifier = Modifier.size(18.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    confirmRemoveRecord?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmRemoveRecord = null },
            title = { Text("解除渠道授权？") },
            text = { Text("确定要移除「${target.channelUsername.ifBlank { target.channelUserId }}」的渠道绑定权限吗？") },
            dismissButton = {
                TextButton(onClick = { confirmRemoveRecord = null }) { Text("取消") }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val removing = target
                        confirmRemoveRecord = null
                        scope.launch {
                            val (ok, msg) = repository.deleteChannelAuthorization(removing.id)
                            if (ok) reloadRecords()
                            snackbar?.showSnackbar(msg)
                        }
                    },
                ) {
                    Text("解除绑定", color = colors.danger)
                }
            },
        )
    }
}

/**
 * 播放偏好原生配置页（统一采用 `ExpressiveTintedScaffold` + 表现力胶囊选择器，真实读写 `PlaybackPreferencesStore` 并联动 `NativePlayerScreen`）。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PlaybackPreferencesScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
    val store = remember(context) { PlaybackPreferencesStore(context) }
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current

    val qualities = remember { listOf("自适应原画", "4K 原盘", "1080p", "720p") }
    val speeds = remember { listOf(0.75f to "0.75x", 1.0f to "1.0x", 1.25f to "1.25x", 1.5f to "1.5x", 2.0f to "2.0x") }
    val resizeModes = remember { listOf(0 to "等比适应", 1 to "裁切铺满", 2 to "拉伸全屏") }

    ExpressiveTintedScaffold(
        title = "播放偏好",
        subtitle = store.summaryText,
        onBack = onBack,
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 14.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item(key = "playback_switches") {
                CinematicPanel(padding = 0.dp, showsShadow = false) {
                    Column {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("硬件加速解码（MediaCodec）", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                Text("优先使用设备硬解 HEVC / AV1 / 杜比视界", color = colors.textMuted, fontSize = 12.sp)
                            }
                            Switch(
                                checked = store.hwDecode,
                                onCheckedChange = { store.updateHwDecode(it) },
                                colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
                            )
                        }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text("切后台自动画中画（PiP）", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                Text("支持小窗画中画浮窗无缝续播", color = colors.textMuted, fontSize = 12.sp)
                            }
                            Switch(
                                checked = store.autoPip,
                                onCheckedChange = { store.updateAutoPip(it) },
                                colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
                            )
                        }
                    }
                }
            }
            item(key = "playback_pills") {
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("默认清晰度", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                qualities.forEach { q ->
                                    NativeAdaptivePill(
                                        title = q,
                                        selected = store.defaultQuality == q,
                                        onClick = { store.updateDefaultQuality(q) },
                                    )
                                }
                            }
                        }
                        HorizontalDivider(color = colors.divider)
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("默认播放倍速", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                speeds.forEach { (spd, label) ->
                                    NativeAdaptivePill(
                                        title = label,
                                        selected = kotlin.math.abs(store.defaultSpeed - spd) < 0.01f,
                                        onClick = { store.updateDefaultSpeed(spd) },
                                    )
                                }
                            }
                        }
                        HorizontalDivider(color = colors.divider)
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("默认画面比例", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                resizeModes.forEach { (modeIdx, label) ->
                                    NativeAdaptivePill(
                                        title = label,
                                        selected = store.defaultResizeMode == modeIdx,
                                        onClick = { store.updateDefaultResizeMode(modeIdx) },
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
            Icon(Icons.Rounded.Check, contentDescription = "已选", tint = colors.primaryButtonFg, modifier = Modifier.size(15.dp))
        }
    }
}
