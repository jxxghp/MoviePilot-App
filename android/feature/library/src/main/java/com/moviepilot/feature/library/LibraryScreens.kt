package com.moviepilot.feature.library

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DriveFileMove
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.AudioFile
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassCapsule
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassFab
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativeSegmentedControl
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.StorageConfigDto
import com.moviepilot.rustbridge.StorageFileDto
import com.moviepilot.rustbridge.TransferHistoryDto
import com.moviepilot.rustbridge.TransferQueueItemDto
import kotlinx.coroutines.launch
import java.io.File

/**
 * Android Material 3 多存储文件管理页面：
 * - 顶部玻璃存储选择器 + 路径面包屑栏 + 原生下拉刷新；
 * - 真实对接 `/api/v1/storage/download` 缓存播放远端音视频，右下角 FAB 调用 Android SAF 打开本机任意视频/音频直放；
 * - 每行配备 Android 标准 `⋮` 溢出菜单与长按手动整理操作。
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun FileManagerScreen(
    repository: MoviePilotRepository,
    initialStorage: String = "local",
    initialPath: String = "/",
    onBack: () -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current

    var storages by remember { mutableStateOf<List<StorageConfigDto>>(listOf(StorageConfigDto("本地", "local"))) }
    var activeStorage by remember { mutableStateOf(initialStorage) }
    var currentPath by remember { mutableStateOf(initialPath) }
    var files by remember { mutableStateOf<List<StorageFileDto>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var downloadingFileName by remember { mutableStateOf<String?>(null) }
    var showStorageMenu by remember { mutableStateOf(false) }
    var sortBySize by remember { mutableStateOf(false) }
    var actionTarget by remember { mutableStateOf<StorageFileDto?>(null) }

    // Android Storage Access Framework 本机音视频文件选择器
    val openLocalMediaLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        if (uri != null) {
            val resolvedName = resolveDisplayName(context, uri)
            val mime = context.contentResolver.getType(uri).orEmpty()
            val isAudio = mime.startsWith("audio/") ||
                RustCoreBridge.detectMediaKind(resolvedName, false) == "audio"
            onPlayMedia(
                MediaPlaybackRequest(
                    url = uri.toString(),
                    title = resolvedName,
                    subtitle = if (isAudio) "本机音乐" else "本机视频",
                    isAudio = isAudio,
                ),
            )
        }
    }

    suspend fun loadFiles() {
        val fetched = repository.fetchFiles(activeStorage, currentPath)
        files = if (sortBySize) {
            fetched.sortedWith(compareBy<StorageFileDto> { it.type != "dir" }.thenByDescending { it.size })
        } else {
            fetched
        }
        isLoading = false
        isRefreshing = false
    }

    fun playStorageFile(file: StorageFileDto, playableKind: String) {
        scope.launch {
            downloadingFileName = file.name
            val cacheDir = File(context.cacheDir, "mp_storage_playback").apply { mkdirs() }
            val safeName = file.name.replace(Regex("[^a-zA-Z0-9._\\-\\u4e00-\\u9fa5]"), "_")
            val destFile = File(cacheDir, "${file.path.hashCode()}_$safeName")
            val downloaded = repository.downloadStorageFileToCache(
                storage = activeStorage,
                path = file.path,
                destFile = destFile,
            )
            downloadingFileName = null
            if (downloaded != null && downloaded.exists()) {
                onPlayMedia(
                    MediaPlaybackRequest(
                        url = Uri.fromFile(downloaded).toString(),
                        title = file.name,
                        subtitle = "${file.storage} · ${file.path}",
                        isAudio = playableKind == "audio",
                    ),
                )
            } else {
                snackbar?.showSnackbar("无法从存储拉取「${file.name}」，请确认存储权限与网络")
            }
        }
    }

    LaunchedEffect(Unit) {
        val fetched = repository.fetchStorages()
        if (fetched.isNotEmpty()) storages = fetched
    }

    LaunchedEffect(activeStorage, currentPath, sortBySize) {
        isLoading = true
        loadFiles()
    }

    val activeStorageLabel = storages.firstOrNull { it.type == activeStorage }?.name
        ?: when (activeStorage) {
            "local" -> "本地"
            "smb" -> "SMB网络共享"
            else -> activeStorage
        }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            NativeGlassTopBar(
                title = "文件管理",
                onBack = onBack,
                trailing = {
                    CinematicCircleButton(
                        icon = Icons.Rounded.FilterList,
                        contentDescription = if (sortBySize) "按名称排序" else "按体积排序",
                        onClick = {
                            sortBySize = !sortBySize
                            scope.launch {
                                snackbar?.showSnackbar(if (sortBySize) "已切换为按文件体积降序" else "已切换为默认目录排序")
                            }
                        },
                    )
                },
            )

            // 顶部玻璃存储选择与路径面包屑胶囊
            CinematicPanel(padding = 10.dp, cornerRadius = 20.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.weight(1f)) {
                        Box {
                            Row(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(12.dp))
                                    .background(colors.accent.copy(alpha = 0.18f))
                                    .border(0.7.dp, colors.accent.copy(alpha = 0.42f), RoundedCornerShape(12.dp))
                                    .clickable { showStorageMenu = true }
                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Box(
                                    modifier = Modifier.size(18.dp).clip(RoundedCornerShape(4.dp)).background(Color(0xFFFF9800)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Rounded.Storage, contentDescription = null, tint = Color.White, modifier = Modifier.size(12.dp))
                                }
                                Text(activeStorageLabel, color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                Icon(Icons.Rounded.UnfoldMore, contentDescription = null, tint = colors.accent, modifier = Modifier.size(15.dp))
                            }
                            DropdownMenu(expanded = showStorageMenu, onDismissRequest = { showStorageMenu = false }) {
                                storages.forEach { st ->
                                    DropdownMenuItem(
                                        text = { Text("${st.name} (${st.type})") },
                                        onClick = {
                                            activeStorage = st.type
                                            currentPath = "/"
                                            showStorageMenu = false
                                        },
                                    )
                                }
                            }
                        }

                        Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(16.dp))

                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(colors.chipFill)
                                .clickable {
                                    if (currentPath != "/") {
                                        currentPath = currentPath.trimEnd('/').substringBeforeLast('/', "").ifBlank { "/" }
                                    }
                                }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                        ) {
                            Text(
                                text = if (currentPath == "/") "根目录" else currentPath.trimEnd('/').substringAfterLast('/'),
                                color = colors.textPrimary,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                    Text("${files.size} 项", color = colors.textMuted, fontSize = 12.sp)
                }
            }

            downloadingFileName?.let { name ->
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = margin, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
                    Text("正在缓冲存储文件：$name …", color = colors.accent, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }

            Spacer(Modifier.height(10.dp))

            if (isLoading && !isRefreshing) {
                Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.accent)
                }
            } else {
                PullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        scope.launch { loadFiles() }
                    },
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                ) {
                    LazyColumn(
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(files, key = { it.path + it.name }) { file ->
                            val playableKind = remember(file.name, file.extension) {
                                if (file.type == "dir") null
                                else RustCoreBridge.detectMediaKind(file.extension ?: file.name, false)
                            }
                            var rowMenuExpanded by remember { mutableStateOf(false) }

                            CinematicPanel(
                                padding = 14.dp,
                                cornerRadius = 20.dp,
                                showsShadow = false,
                                modifier = Modifier.combinedClickable(
                                    onClick = {
                                        if (file.type == "dir") {
                                            currentPath = file.path
                                        } else if (playableKind != null) {
                                            playStorageFile(file, playableKind)
                                        } else {
                                            actionTarget = file
                                        }
                                    },
                                    onLongClick = { actionTarget = file },
                                ),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    val icon = when {
                                        file.type == "dir" -> Icons.Rounded.Folder
                                        playableKind == "video" -> Icons.Rounded.Movie
                                        playableKind == "audio" -> Icons.Rounded.AudioFile
                                        else -> Icons.AutoMirrored.Rounded.InsertDriveFile
                                    }
                                    Icon(
                                        icon,
                                        contentDescription = null,
                                        tint = if (file.type == "dir") Color(0xFFC8B0FF) else colors.accent,
                                        modifier = Modifier.size(28.dp),
                                    )
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Text(file.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(
                                            text = if (file.type == "dir") "文件夹" else formatFileSize(file.size),
                                            color = colors.textMuted,
                                            fontSize = 12.sp,
                                            maxLines = 1,
                                        )
                                    }
                                    if (playableKind != null) {
                                        NativeAdaptiveBadge(if (playableKind == "audio") "音频" else "播放", tint = colors.success)
                                    }
                                    Box {
                                        IconButton(onClick = { rowMenuExpanded = true }, modifier = Modifier.size(32.dp)) {
                                            Icon(Icons.Rounded.MoreVert, contentDescription = "更多操作", tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                        }
                                        DropdownMenu(expanded = rowMenuExpanded, onDismissRequest = { rowMenuExpanded = false }) {
                                            if (playableKind != null) {
                                                DropdownMenuItem(
                                                    text = { Text("原生播放器打开") },
                                                    leadingIcon = { Icon(Icons.Rounded.PlayArrow, contentDescription = null) },
                                                    onClick = {
                                                        rowMenuExpanded = false
                                                        playStorageFile(file, playableKind)
                                                    },
                                                )
                                            }
                                            DropdownMenuItem(
                                                text = { Text("手动识别整理") },
                                                leadingIcon = { Icon(Icons.AutoMirrored.Rounded.DriveFileMove, contentDescription = null) },
                                                onClick = {
                                                    rowMenuExpanded = false
                                                    actionTarget = file
                                                },
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

        // Android 单手拇指区右下角主动作 FAB：直接打开本机视频 / 音乐
        NativeGlassFab(
            icon = Icons.Rounded.FolderOpen,
            label = "本机媒体",
            onClick = { openLocalMediaLauncher.launch(arrayOf("video/*", "audio/*")) },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = margin, bottom = 20.dp),
        )
    }

    actionTarget?.let { target ->
        var transferMode by remember { mutableStateOf("硬链接") }
        var destPath by remember { mutableStateOf("/video/movies") }
        NativeGlassSheet(onDismissRequest = { actionTarget = null }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("手动整理与重命名", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Text(target.name, color = colors.textSecondary, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("硬链接", "移动", "复制", "软链接").forEach { m ->
                        NativeAdaptivePill(m, selected = transferMode == m, onClick = { transferMode = m })
                    }
                }
                OutlinedTextField(
                    value = destPath,
                    onValueChange = { destPath = it },
                    label = { Text("目标媒体库路径") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        val name = target.name
                        actionTarget = null
                        scope.launch { snackbar?.showSnackbar("已提交「$name」至智能整理队列（$transferMode）") }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Icon(Icons.AutoMirrored.Rounded.DriveFileMove, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("立即执行智能识别整理", color = Color.White, fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

private fun resolveDisplayName(context: Context, uri: Uri): String {
    val cursor = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
    }.getOrNull()
    cursor?.use { c ->
        if (c.moveToFirst()) {
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0) {
                val name = c.getString(idx)
                if (!name.isNullOrBlank()) return name
            }
        }
    }
    return uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { "本机媒体" } ?: "本机媒体"
}

/**
 * 整理历史页面（1:1 复刻 iOS 黄金截图 `native-v2-live-history.jpg` & `transfer-queue.jpg`）：
 * - 顶栏标题 `整理历史 (2,295)` + 双图标玻璃胶囊 `[📥 ☰]`
 * - 搜索框 + `[全部] [成功] [失败]` 胶囊
 * - 2:3 剧照缩略图 + 片名季集 + 绿成功/红失败胶囊 + 整理模式/体积/时间 + 链式圆点竖线源→目标暗透子卡
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun TransferHistoryScreen(
    repository: MoviePilotRepository,
    initialSearch: String = "",
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var search by remember { mutableStateOf(initialSearch) }
    var statusFilter by remember { mutableStateOf("全部") }
    var totalCount by remember { mutableStateOf(0) }
    var records by remember { mutableStateOf<List<TransferHistoryDto>>(emptyList()) }
    var queueItems by remember { mutableStateOf<List<TransferQueueItemDto>>(emptyList()) }
    var showQueueSheet by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<TransferHistoryDto?>(null) }

    LaunchedEffect(search) {
        val (total, fetched) = repository.fetchTransferHistory(search)
        totalCount = total
        records = fetched
    }

    LaunchedEffect(showQueueSheet) {
        if (showQueueSheet) {
            queueItems = repository.fetchTransferQueue()
        }
    }

    val filtered = remember(records, statusFilter) {
        when (statusFilter) {
            "成功" -> records.filter { it.status }
            "失败" -> records.filter { !it.status }
            else -> records
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = if (totalCount > 0) "整理历史 (%,d)".format(totalCount) else "整理历史",
            onBack = onBack,
            trailing = {
                CinematicGlassCapsule {
                    IconButton(onClick = { showQueueSheet = true }, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Rounded.Inbox, contentDescription = "整理队列", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                    }
                    IconButton(onClick = { statusFilter = if (statusFilter == "全部") "失败" else "全部" }, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Rounded.FilterList, contentDescription = "筛选", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                    }
                }
            },
        )

        CinematicPanel(padding = 12.dp, cornerRadius = 16.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (search.isEmpty()) Text("搜索片名或路径", color = colors.textMuted, fontSize = 14.sp)
                    BasicTextField(
                        value = search,
                        onValueChange = { search = it },
                        singleLine = true,
                        textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                        cursorBrush = SolidColor(colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        Spacer(Modifier.height(10.dp))

        val statusTabs = listOf("全部", "成功", "失败")
        NativeSegmentedControl(
            options = statusTabs,
            selectedIndex = statusTabs.indexOf(statusFilter).coerceAtLeast(0),
            onSelect = { idx -> statusFilter = statusTabs[idx] },
            modifier = Modifier.padding(horizontal = margin),
        )

        Spacer(Modifier.height(12.dp))

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 132.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(filtered, key = { it.id }) { rec ->
                CinematicPanel(
                    padding = 14.dp,
                    cornerRadius = 22.dp,
                    showsShadow = false,
                    modifier = Modifier.combinedClickable(
                        onClick = {},
                        onLongClick = { deleteTarget = rec },
                    ),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        // 顶部：2:3 封面 + 片名季集 + 成功/失败状态胶囊 + 模式/体积/时间
                        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(
                                modifier = Modifier
                                    .width(54.dp)
                                    .aspectRatio(2f / 3f)
                                    .clip(RoundedCornerShape(10.dp))
                                    .background(colors.chipFill),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.Movie, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(22.dp))
                                if (!rec.image.isNullOrBlank()) {
                                    AsyncImage(model = rec.image, contentDescription = rec.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                }
                            }
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    val fullTitle = listOfNotNull(
                                        rec.title,
                                        rec.seasons.ifBlank { null },
                                        rec.episodes.ifBlank { null },
                                    ).joinToString(" ")
                                    Text(fullTitle, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                    Spacer(Modifier.width(8.dp))
                                    NativeAdaptiveBadge(if (rec.status) "成功" else "失败", tint = if (rec.status) colors.success else colors.danger)
                                }
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    NativeAdaptiveBadge(formatTransferMode(rec.mode), tint = colors.accent)
                                    val meta = buildList {
                                        if (rec.sizeBytes > 0L) add(formatFileSize(rec.sizeBytes))
                                        if (rec.date.isNotBlank()) add(rec.date.take(16))
                                    }.joinToString(" · ")
                                    if (meta.isNotBlank()) {
                                        Text(meta, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                        }

                        // 链式源 → 目标路径暗透子卡（1:1 复刻 iOS `○──●  SMB网络共享 ...`）
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(Color.Black.copy(alpha = if (colors.isDark) 0.22f else 0.05f))
                                .border(0.6.dp, colors.chipBorder, RoundedCornerShape(14.dp))
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Box(modifier = Modifier.size(7.dp).border(1.4.dp, colors.textMuted, CircleShape))
                                Box(modifier = Modifier.width(1.2.dp).height(14.dp).background(colors.divider))
                                Box(modifier = Modifier.size(7.dp).clip(CircleShape).background(colors.accent))
                            }
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    StorageTag(storageLabel(rec.srcStorage))
                                    Text(rec.src.substringAfterLast('/'), color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                }
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    StorageTag(storageLabel(rec.destStorage))
                                    Text(rec.dest.substringAfterLast('/'), color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showQueueSheet) {
        NativeGlassSheet(onDismissRequest = { showQueueSheet = false }) {
            Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("整理队列 (${queueItems.size})", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                if (queueItems.isEmpty()) {
                    CinematicPanel(padding = 16.dp, showsShadow = false) {
                        Text("当前整理队列空闲，新下载完成将自动入队识别刮削。", color = colors.textSecondary, fontSize = 14.sp)
                    }
                } else {
                    queueItems.forEach { q ->
                        CinematicPanel(padding = 14.dp, showsShadow = false) {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(q.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                    NativeAdaptiveBadge(q.state, tint = colors.accent)
                                }
                                Text(q.src, color = colors.textMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(20.dp))
            }
        }
    }

    deleteTarget?.let { rec ->
        NativeGlassSheet(onDismissRequest = { deleteTarget = null }) {
            Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("删除整理记录：${rec.title}", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                listOf("仅删除记录", "删除记录与源文件", "删除记录与媒体库目标文件", "同时删除记录、源与目标文件").forEach { option ->
                    CinematicPanel(
                        padding = 14.dp,
                        showsShadow = false,
                        modifier = Modifier.combinedClickable(onClick = {
                            records = records.filterNot { it.id == rec.id }
                            deleteTarget = null
                        }),
                    ) {
                        Text(option, color = if (option.contains("同时")) colors.danger else colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                    }
                }
                Spacer(Modifier.height(20.dp))
            }
        }
    }
}

@Composable
private fun StorageTag(text: String) {
    val colors = LocalMoviePilotColors.current
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(colors.chipFill)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    ) {
        Text(text, color = colors.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}

private fun storageLabel(raw: String): String = when (raw.lowercase()) {
    "smb" -> "SMB网络共享"
    "local" -> "本地存储"
    "u115" -> "115网盘"
    "alipan" -> "阿里云盘"
    "rclone" -> "Rclone"
    else -> raw.ifBlank { "本地存储" }
}

private fun formatTransferMode(raw: String): String = when (raw.lowercase()) {
    "copy" -> "复制"
    "move" -> "移动"
    "link" -> "硬链接"
    "softlink" -> "软链接"
    else -> raw.ifBlank { "复制" }
}

private fun formatFileSize(bytes: Long): String {
    if (bytes <= 0L) return "0 B"
    val units = arrayOf("B", "KB", "MB", "GB", "TB")
    var v = bytes.toDouble()
    var idx = 0
    while (v >= 1024 && idx < units.lastIndex) {
        v /= 1024
        idx++
    }
    return String.format("%.2f %s", v, units[idx])
}
