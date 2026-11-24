package com.moviepilot.feature.library

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DriveFileMove
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.AudioFile
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Preview
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeCardListSkeleton
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeGlassFab
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeSkeletonBlock
import com.moviepilot.designsystem.ProvideSkeletonShimmer
import com.moviepilot.designsystem.SkeletonCardStyle
import com.moviepilot.designsystem.SkeletonSurfaceRole
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.DirectoryConfigDto
import com.moviepilot.rustbridge.ManualTransferPreviewItemDto
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.StorageConfigDto
import com.moviepilot.rustbridge.StorageFileDto
import com.moviepilot.rustbridge.TransferHistoryDto
import com.moviepilot.rustbridge.TransferQueueItemDto
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
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
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    val listState = rememberLazyListState()

    var storages by remember { mutableStateOf<List<StorageConfigDto>>(listOf(StorageConfigDto("本地", "local"))) }
    var activeStorage by rememberSaveable { mutableStateOf(initialStorage) }
    var currentPath by rememberSaveable { mutableStateOf(initialPath) }
    var files by remember { mutableStateOf<List<StorageFileDto>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var downloadingFileName by remember { mutableStateOf<String?>(null) }
    var showStorageMenu by remember { mutableStateOf(false) }
    var sortBySize by rememberSaveable { mutableStateOf(false) }
    var actionTarget by remember { mutableStateOf<StorageFileDto?>(null) }

    // 子目录下拦截返回手势逐级返回父目录，根目录再退出文件管理页
    BackHandler(enabled = currentPath != "/") {
        currentPath = currentPath.trimEnd('/').substringBeforeLast('/', "").ifBlank { "/" }
    }

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
        ?: storageLabel(activeStorage)

    Box(modifier = Modifier.fillMaxSize()) {
        ExpressiveTintedScaffold(
            title = "文件管理",
            subtitle = activeStorageLabel,
            onBack = onBack,
            actions = {
                ExpressiveHeaderActionButton(
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
        ) {
            ProvideSkeletonShimmer {
                Column(modifier = Modifier.fillMaxSize()) {
                    Spacer(Modifier.height(14.dp))

                    // 顶部玻璃存储选择（带 SMB / 115 / 阿里云盘 / Rclone / 本地 品牌图标）与路径面包屑胶囊
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
                                        NativeEntityLogo(
                                            kind = "storage",
                                            value = activeStorage,
                                            size = 18.dp,
                                            cornerRadius = 5.dp,
                                        )
                                        Text(activeStorageLabel, color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                        Icon(Icons.Rounded.UnfoldMore, contentDescription = null, tint = colors.accent, modifier = Modifier.size(15.dp))
                                    }
                                    DropdownMenu(expanded = showStorageMenu, onDismissRequest = { showStorageMenu = false }) {
                                        storages.forEach { st ->
                                            DropdownMenuItem(
                                                leadingIcon = {
                                                    NativeEntityLogo(
                                                        kind = "storage",
                                                        value = st.type.ifBlank { st.name },
                                                        size = 20.dp,
                                                        cornerRadius = 5.dp,
                                                    )
                                                },
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
                            if (isLoading && !isRefreshing) {
                                NativeSkeletonBlock(
                                    cornerRadius = 4.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 36.dp, height = 13.dp),
                                )
                            } else {
                                Text("${files.size} 项", color = colors.textMuted, fontSize = 12.sp)
                            }
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
                        NativeCardListSkeleton(
                            style = SkeletonCardStyle.IconRow,
                            count = 7,
                            contentPadding = PaddingValues(start = margin, end = margin, bottom = 96.dp + bottomOverlayInset),
                            modifier = Modifier.weight(1f),
                        )
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
                                state = listState,
                                contentPadding = PaddingValues(start = margin, end = margin, bottom = 96.dp + bottomOverlayInset),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                                modifier = Modifier.fillMaxSize(),
                            ) {
                                if (files.isEmpty()) {
                                    item {
                                        CinematicPanel(padding = 28.dp, showsShadow = false) {
                                            Column(
                                                modifier = Modifier.fillMaxWidth(),
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                                verticalArrangement = Arrangement.spacedBy(8.dp),
                                            ) {
                                                Icon(Icons.Rounded.FolderOpen, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(36.dp))
                                                Text("当前目录为空", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                                Text("可下拉刷新或切换其他存储目录浏览。", color = colors.textSecondary, fontSize = 12.5.sp, textAlign = TextAlign.Center)
                                            }
                                        }
                                    }
                                }
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
                                                    text = { Text("播放媒体") },
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
                .padding(end = margin, bottom = 20.dp + bottomOverlayInset),
        )
    }

    actionTarget?.let { target ->
        ManualTransferSheet(
            repository = repository,
            fileItem = target,
            historyLogId = null,
            sourceStorageHint = activeStorage,
            sourceTitleHint = target.name,
            sourcePathHint = target.path,
            initialStorages = storages,
            onDismiss = { actionTarget = null },
            onCompleted = { msg ->
                actionTarget = null
                scope.launch { snackbar?.showSnackbar(msg) }
            },
        )
    }
}

/**
 * 1:1 对齐 iOS `NativeManualTransferSheet` 的全量手动识别整理弹窗：
 * - 自动匹配目标媒体库路径（`POST /api/v1/transfer/manual/target-path`）与历史记录（`POST /api/v1/transfer/manual/history`）
 * - 支持全量参数：目标存储/路径、7 种整理方式、4 种覆盖策略、媒体类型/数据源/媒体搜索指定 ID、
 *   剧集季/集/格式/偏移/分段/剧集组、音乐类型与匹配模式、三态刮削与分类目录、最小体积、重新整理、跳过已成功、后台执行
 * - 支持「预览整理」查看目标路径映射与「立即整理」真实提交。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun ManualTransferSheet(
    repository: MoviePilotRepository,
    fileItem: StorageFileDto?,
    historyLogId: Int?,
    sourceStorageHint: String,
    sourceTitleHint: String,
    sourcePathHint: String,
    initialStorages: List<StorageConfigDto> = emptyList(),
    onDismiss: () -> Unit,
    onCompleted: (String) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()

    var storages by remember { mutableStateOf(initialStorages) }
    var libraryDirs by remember { mutableStateOf<List<DirectoryConfigDto>>(emptyList()) }
    var targetStorage by remember { mutableStateOf(sourceStorageHint.ifBlank { "local" }) }
    var targetPath by remember { mutableStateOf("") }
    var matchedTargetHint by remember { mutableStateOf<String?>(null) }
    var matchedHistoryCount by remember { mutableStateOf(0) }
    var skipSuccess by remember { mutableStateOf(false) }
    var reorganize by remember { mutableStateOf(false) }

    var transferType by remember { mutableStateOf("") }
    var overwriteMode by remember { mutableStateOf("never") }
    var mediaType by remember { mutableStateOf("") }
    var mediaSource by remember { mutableStateOf("") }
    var mediaId by remember { mutableStateOf("") }
    var selectedMediaTitle by remember { mutableStateOf<String?>(null) }
    var seasonText by remember { mutableStateOf("") }
    var episodeDetail by remember { mutableStateOf("") }
    var episodeFormat by remember { mutableStateOf("") }
    var episodeOffset by remember { mutableStateOf("") }
    var episodePart by remember { mutableStateOf("") }
    var episodeGroup by remember { mutableStateOf("") }
    var musicType by remember { mutableStateOf("") }
    var musicTrackMatch by remember { mutableStateOf("strict") }
    var minFilesizeText by remember { mutableStateOf("0") }

    // 三态选择：null = 自动（跟随目录配置），true = 开启，false = 关闭
    var scrapeChoice by remember { mutableStateOf<Boolean?>(null) }
    var typeFolderChoice by remember { mutableStateOf<Boolean?>(null) }
    var categoryFolderChoice by remember { mutableStateOf<Boolean?>(null) }
    var fromHistory by remember { mutableStateOf(historyLogId != null) }
    var runInBackground by remember { mutableStateOf(true) }

    var showAdvanced by remember { mutableStateOf(false) }
    var showMediaSearch by remember { mutableStateOf(false) }
    var mediaSearchQuery by remember { mutableStateOf(sourceTitleHint.substringBeforeLast('.').take(24)) }
    var mediaSearchResults by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var isSearchingMedia by remember { mutableStateOf(false) }

    var isPreviewing by remember { mutableStateOf(false) }
    var isSubmitting by remember { mutableStateOf(false) }
    var previewItems by remember { mutableStateOf<List<ManualTransferPreviewItemDto>>(emptyList()) }
    var feedbackText by remember { mutableStateOf<String?>(null) }
    var feedbackIsError by remember { mutableStateOf(false) }

    fun buildPayloadJson(preview: Boolean, onlyForMatch: Boolean = false): String {
        val map = linkedMapOf<String, kotlinx.serialization.json.JsonElement>()
        if (fileItem != null) {
            val fMap = linkedMapOf<String, kotlinx.serialization.json.JsonElement>(
                "storage" to JsonPrimitive(fileItem.storage.ifBlank { sourceStorageHint }),
                "type" to JsonPrimitive(fileItem.type),
                "path" to JsonPrimitive(fileItem.path),
                "name" to JsonPrimitive(fileItem.name),
                "size" to JsonPrimitive(fileItem.size),
            )
            fileItem.extension?.takeIf { it.isNotBlank() }?.let { fMap["extension"] = JsonPrimitive(it) }
            map["fileitem"] = JsonObject(fMap)
        }
        if (historyLogId != null) map["logid"] = JsonPrimitive(historyLogId)
        if (targetStorage.isNotBlank()) map["target_storage"] = JsonPrimitive(targetStorage)
        if (!onlyForMatch && targetPath.trim().isNotBlank()) map["target_path"] = JsonPrimitive(targetPath.trim())
        if (mediaSource.isNotBlank()) map["media_source"] = JsonPrimitive(mediaSource)
        if (mediaId.trim().isNotBlank()) map["media_id"] = JsonPrimitive(mediaId.trim())
        if (mediaType == "音乐" && musicType.isNotBlank()) map["music_type"] = JsonPrimitive(musicType)
        if (mediaType == "音乐" && musicType == "album") map["music_track_match"] = JsonPrimitive(musicTrackMatch)
        if (mediaType.isNotBlank()) map["type_name"] = JsonPrimitive(mediaType)
        seasonText.trim().toIntOrNull()?.let { map["season"] = JsonPrimitive(it) }
        if (transferType.isNotBlank()) map["transfer_type"] = JsonPrimitive(transferType)
        if (overwriteMode.isNotBlank()) map["overwrite_mode"] = JsonPrimitive(overwriteMode)
        if (episodeFormat.trim().isNotBlank()) map["episode_format"] = JsonPrimitive(episodeFormat.trim())
        if (episodeDetail.trim().isNotBlank()) map["episode_detail"] = JsonPrimitive(episodeDetail.trim())
        if (episodePart.trim().isNotBlank()) map["episode_part"] = JsonPrimitive(episodePart.trim())
        if (episodeOffset.trim().isNotBlank()) map["episode_offset"] = JsonPrimitive(episodeOffset.trim())
        if (episodeGroup.trim().isNotBlank()) map["episode_group"] = JsonPrimitive(episodeGroup.trim())
        map["min_filesize"] = JsonPrimitive((minFilesizeText.trim().toIntOrNull() ?: 0).coerceAtLeast(0))
        scrapeChoice?.let { map["scrape"] = JsonPrimitive(it) }
        typeFolderChoice?.let { map["library_type_folder"] = JsonPrimitive(it) }
        categoryFolderChoice?.let { map["library_category_folder"] = JsonPrimitive(it) }
        map["from_history"] = JsonPrimitive(fromHistory)
        map["preview"] = JsonPrimitive(preview)
        map["reorganize"] = JsonPrimitive(if (skipSuccess) false else reorganize)
        map["skip_success"] = JsonPrimitive(skipSuccess)
        return JsonObject(map).toString()
    }

    LaunchedEffect(Unit) {
        if (storages.isEmpty()) storages = repository.fetchStorages()
        libraryDirs = repository.fetchDirectories()
        val matchPayload = buildPayloadJson(preview = false, onlyForMatch = true)
        repository.matchManualTransferTargetPath(matchPayload)?.let { hint ->
            if (hint.targetStorage.isNotBlank()) targetStorage = hint.targetStorage
            if (hint.targetPath.isNotBlank()) {
                matchedTargetHint = hint.targetPath
                if (targetPath.isBlank()) targetPath = hint.targetPath
            }
            if (hint.transferType.isNotBlank() && transferType.isBlank()) transferType = hint.transferType
            if (hint.overwriteMode.isNotBlank()) overwriteMode = hint.overwriteMode
        }
        repository.matchManualTransferHistory(matchPayload)?.let { h ->
            matchedHistoryCount = h.historyCount
            if (h.reorganize) reorganize = true
        }
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = colors.textPrimary,
        unfocusedTextColor = colors.textPrimary,
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.fieldBorder,
    )
    val storageNames = remember(storages) { (storages.map { it.type } + "local").distinct() }

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("手动识别整理", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            CinematicPanel(padding = 12.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(sourceTitleHint, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        NativeEntityLogo("storage", sourceStorageHint, size = 16.dp, cornerRadius = 4.dp)
                        Text("${storageLabel(sourceStorageHint)} · $sourcePathHint", color = colors.textMuted, fontSize = 11.5.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    if (matchedHistoryCount > 0) {
                        NativeAdaptiveBadge("已匹配历史整理 $matchedHistoryCount 条", tint = colors.warning)
                    }
                }
            }

            // 1. 目标存储与路径（带 SMB / 115 / 阿里云盘 / Rclone / 本地 品牌图标）
            Text("目标存储", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                storageNames.forEach { st ->
                    NativeAdaptivePill(
                        title = storageLabel(st),
                        leadingContent = {
                            NativeEntityLogo("storage", st, size = 16.dp, cornerRadius = 4.dp)
                        },
                        selected = targetStorage == st,
                        onClick = { targetStorage = st },
                    )
                }
            }
            if (libraryDirs.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    libraryDirs.filter { it.libraryPath.isNotBlank() }.take(6).forEach { dir ->
                        NativeAdaptivePill(
                            title = dir.name,
                            leadingContent = {
                                NativeEntityLogo("storage", dir.libraryStorage, size = 15.dp, cornerRadius = 4.dp)
                            },
                            selected = targetPath == dir.libraryPath,
                            onClick = {
                                targetStorage = dir.libraryStorage.ifBlank { targetStorage }
                                targetPath = dir.libraryPath
                            },
                        )
                    }
                }
            }
            OutlinedTextField(
                value = targetPath,
                onValueChange = { targetPath = it },
                label = { Text(matchedTargetHint?.let { "目标路径（自动匹配：$it）" } ?: "目标媒体库路径（留空按目录规则自动匹配）") },
                singleLine = true,
                colors = fieldColors,
                modifier = Modifier.fillMaxWidth(),
            )

            // 2. 整理方式 & 覆盖模式
            Text("整理方式", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "" to "自动",
                    "link" to "硬链接",
                    "softlink" to "软链接",
                    "copy" to "复制",
                    "move" to "移动",
                    "rclone_copy" to "Rclone 复制",
                    "rclone_move" to "Rclone 移动",
                ).forEach { (k, lbl) ->
                    NativeAdaptivePill(lbl, selected = transferType == k, onClick = { transferType = k })
                }
            }
            Text("覆盖模式", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "never" to "从不覆盖",
                    "size" to "按大小覆盖",
                    "always" to "总是覆盖",
                    "latest" to "仅保留最新",
                ).forEach { (k, lbl) ->
                    NativeAdaptivePill(lbl, selected = overwriteMode == k, onClick = { overwriteMode = k })
                }
            }

            // 3. 媒体识别与指定
            HorizontalDivider(color = colors.divider)
            Text("媒体识别", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("" to "自动识别", "电影" to "电影", "电视剧" to "电视剧", "音乐" to "音乐").forEach { (k, lbl) ->
                    NativeAdaptivePill(lbl, selected = mediaType == k, onClick = { mediaType = k })
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(
                    "" to "自动源",
                    "themoviedb" to "TheMovieDB",
                    "douban" to "豆瓣",
                    "bangumi" to "Bangumi",
                    "musicbrainz" to "MusicBrainz",
                ).forEach { (k, lbl) ->
                    NativeAdaptivePill(
                        title = lbl,
                        leadingContent = if (k.isNotBlank()) {
                            {
                                NativeEntityLogo("datasource", k, size = 16.dp, cornerRadius = 4.dp)
                            }
                        } else null,
                        selected = mediaSource == k,
                        onClick = { mediaSource = k },
                    )
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = mediaId,
                    onValueChange = { mediaId = it },
                    label = { Text(selectedMediaTitle?.let { "媒体 ID（已选：$it）" } ?: "指定 TMDB / 豆瓣 / Bangumi ID（可选）") },
                    singleLine = true,
                    colors = fieldColors,
                    modifier = Modifier.weight(1f),
                )
                NativeAdaptivePill(
                    title = "搜索指定",
                    selected = showMediaSearch,
                    icon = Icons.Rounded.Search,
                    onClick = { showMediaSearch = !showMediaSearch },
                )
            }
            if (showMediaSearch) {
                CinematicPanel(padding = 12.dp, showsShadow = false) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(
                                value = mediaSearchQuery,
                                onValueChange = { mediaSearchQuery = it },
                                label = { Text("搜索片名匹配 ID") },
                                singleLine = true,
                                colors = fieldColors,
                                modifier = Modifier.weight(1f),
                            )
                            Button(
                                onClick = {
                                    scope.launch {
                                        isSearchingMedia = true
                                        mediaSearchResults = repository.searchMedia(mediaSearchQuery, if (mediaType == "音乐") "music" else "media", 1).take(6)
                                        isSearchingMedia = false
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                                shape = CircleShape,
                            ) { Text("搜索", fontWeight = FontWeight.Bold) }
                        }
                        if (isSearchingMedia) {
                            NativeCardListSkeleton(
                                style = SkeletonCardStyle.IconRow,
                                count = 3,
                                contentPadding = PaddingValues(0.dp),
                                scrollable = false,
                                compact = true,
                            )
                        } else {
                            mediaSearchResults.forEach { m ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(10.dp))
                                        .background(colors.chipFill)
                                        .clickable {
                                            mediaSource = m.source.ifBlank { "themoviedb" }
                                            mediaId = m.tmdbId?.toString() ?: m.doubanId ?: m.mediaId ?: m.resolvedId
                                            if (m.type.isNotBlank()) mediaType = m.type
                                            selectedMediaTitle = "${m.title} (${m.year})"
                                            showMediaSearch = false
                                        }
                                        .padding(horizontal = 10.dp, vertical = 8.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Text("${m.title} (${m.year})", color = colors.textPrimary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                    NativeAdaptiveBadge(m.type.ifBlank { m.source }, tint = colors.accent)
                                }
                            }
                        }
                    }
                }
            }

            // 电视剧专属参数
            if (mediaType == "电视剧" || mediaType.isBlank()) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = seasonText, onValueChange = { seasonText = it.filter(Char::isDigit) }, label = { Text("季号 (如 1)") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1f))
                    OutlinedTextField(value = episodeDetail, onValueChange = { episodeDetail = it }, label = { Text("指定集数 (如 1-12)") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1.4f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = episodeOffset, onValueChange = { episodeOffset = it }, label = { Text("集数偏移 (如 EP-12)") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1f))
                    OutlinedTextField(value = episodePart, onValueChange = { episodePart = it }, label = { Text("Part 分段 (如 part1)") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = episodeFormat, onValueChange = { episodeFormat = it }, label = { Text("自定义集数格式") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1f))
                    OutlinedTextField(value = episodeGroup, onValueChange = { episodeGroup = it }, label = { Text("剧集组 ID") }, singleLine = true, colors = fieldColors, modifier = Modifier.weight(1f))
                }
            }

            // 音乐专属参数
            if (mediaType == "音乐") {
                Text("音乐整理模式", color = colors.textSecondary, fontSize = 12.5.sp)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("" to "自动", "album" to "按专辑", "track" to "按单曲").forEach { (k, lbl) ->
                        NativeAdaptivePill(lbl, selected = musicType == k, onClick = { musicType = k })
                    }
                }
                if (musicType == "album") {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("strict" to "严格音轨匹配", "loose" to "宽松音轨匹配").forEach { (k, lbl) ->
                            NativeAdaptivePill(lbl, selected = musicTrackMatch == k, onClick = { musicTrackMatch = k })
                        }
                    }
                }
            }

            // 4. 更多高级参数（三态刮削/目录分类/最小体积/历史与后台选项）
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.chipFill)
                    .clickable { showAdvanced = !showAdvanced }
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("更多高级参数（刮削 / 分类子目录 / 历史策略）", color = colors.textPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                Icon(if (showAdvanced) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, contentDescription = null, tint = colors.textSecondary)
            }
            if (showAdvanced) {
                CinematicPanel(padding = 14.dp, showsShadow = false) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        TriStateRow("刮削元数据", scrapeChoice) { scrapeChoice = it }
                        TriStateRow("按类型分类子目录", typeFolderChoice) { typeFolderChoice = it }
                        TriStateRow("按二级分类子目录", categoryFolderChoice) { categoryFolderChoice = it }
                        OutlinedTextField(
                            value = minFilesizeText,
                            onValueChange = { minFilesizeText = it.filter(Char::isDigit) },
                            label = { Text("最小文件大小 (MB，0 不限制)") },
                            singleLine = true,
                            colors = fieldColors,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text("跳过已成功整理文件", color = colors.textPrimary, fontSize = 13.5.sp)
                            Switch(checked = skipSuccess, onCheckedChange = { skipSuccess = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                        }
                        if (!skipSuccess) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text("覆盖历史记录重新整理", color = colors.textPrimary, fontSize = 13.5.sp)
                                Switch(checked = reorganize, onCheckedChange = { reorganize = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                            }
                        }
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text("提交至后台异步执行", color = colors.textPrimary, fontSize = 13.5.sp)
                            Switch(checked = runInBackground, onCheckedChange = { runInBackground = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                        }
                    }
                }
            }

            // 预览结果列表
            if (previewItems.isNotEmpty()) {
                CinematicPanel(padding = 12.dp, showsShadow = false) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("整理预览（共 ${previewItems.size} 项）", color = colors.accent, fontSize = 13.5.sp, fontWeight = FontWeight.Bold)
                        previewItems.take(8).forEach { pv ->
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(pv.title.ifBlank { pv.src.substringAfterLast('/') }, color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                if (pv.dest.isNotBlank()) {
                                    Text("→ ${pv.dest}", color = colors.success, fontSize = 11.5.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                } else if (pv.message.isNotBlank()) {
                                    Text(pv.message, color = colors.warning, fontSize = 11.5.sp)
                                }
                            }
                        }
                    }
                }
            }

            feedbackText?.let { fb ->
                Text(fb, color = if (feedbackIsError) colors.danger else colors.success, fontSize = 12.5.sp)
            }

            // 双动作：预览整理 + 立即整理
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(
                    enabled = !isPreviewing && !isSubmitting,
                    onClick = {
                        scope.launch {
                            isPreviewing = true
                            feedbackText = null
                            val (ok, msg, items) = repository.executeManualTransfer(buildPayloadJson(preview = true), preview = true, background = false)
                            previewItems = items
                            if (!ok || items.isEmpty()) {
                                feedbackIsError = !ok
                                feedbackText = msg
                            }
                            isPreviewing = false
                        }
                    },
                    shape = CircleShape,
                    modifier = Modifier.weight(1f).height(48.dp),
                ) {
                    Icon(Icons.Rounded.Preview, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(if (isPreviewing) "预览中..." else "预览整理", fontWeight = FontWeight.SemiBold)
                }
                Button(
                    enabled = !isSubmitting && !isPreviewing,
                    onClick = {
                        scope.launch {
                            isSubmitting = true
                            feedbackText = null
                            val (ok, msg, _) = repository.executeManualTransfer(buildPayloadJson(preview = false), preview = false, background = runInBackground)
                            isSubmitting = false
                            if (ok) {
                                onCompleted(msg)
                            } else {
                                feedbackIsError = true
                                feedbackText = msg
                            }
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                    shape = CircleShape,
                    modifier = Modifier.weight(1.2f).height(48.dp),
                ) {
                    Icon(Icons.AutoMirrored.Rounded.DriveFileMove, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(if (isSubmitting) "提交中..." else "立即整理", fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(18.dp))
        }
    }
}

@Composable
private fun TriStateRow(label: String, value: Boolean?, onChange: (Boolean?) -> Unit) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = colors.textPrimary, fontSize = 13.5.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            NativeAdaptivePill("自动", selected = value == null, onClick = { onChange(null) })
            NativeAdaptivePill("开启", selected = value == true, onClick = { onChange(true) })
            NativeAdaptivePill("关闭", selected = value == false, onClick = { onChange(false) })
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
 * 整理历史页面（统一升级为 `ExpressiveTintedScaffold` + `ExpressivePillTabRow`）：
 * - 每张整理卡片显示源/目标存储品牌图标（SMB / 115 / 阿里云盘 / Rclone / 本地）与显式 `⋮` 溢出菜单；
 * - 全部 4 种删除选项真实调用 `DELETE /api/v1/history/transfer?deletesrc=...&deletedest=...`（携带服务端完整记录 JSON 请求体）。
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun TransferHistoryScreen(
    repository: MoviePilotRepository,
    initialSearch: String = "",
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    val listState = rememberLazyListState()
    var search by rememberSaveable { mutableStateOf(initialSearch) }
    var statusFilter by rememberSaveable { mutableStateOf("全部") }
    var totalCount by remember { mutableStateOf(0) }
    var records by remember { mutableStateOf<List<TransferHistoryDto>>(emptyList()) }
    var queueItems by remember { mutableStateOf<List<TransferQueueItemDto>>(emptyList()) }
    var showQueueSheet by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var isLoadingQueue by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    var isDeleting by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<TransferHistoryDto?>(null) }
    var retransferTarget by remember { mutableStateOf<TransferHistoryDto?>(null) }

    suspend fun reloadHistory() {
        val (total, fetched) = repository.fetchTransferHistory(search)
        totalCount = total
        records = fetched
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(search) {
        if (records.isEmpty()) isLoading = true
        reloadHistory()
    }

    LaunchedEffect(showQueueSheet) {
        if (showQueueSheet) {
            isLoadingQueue = true
            queueItems = repository.fetchTransferQueue()
            isLoadingQueue = false
        }
    }

    val statusTabs = listOf("全部", "成功", "失败")
    val filtered = remember(records, statusFilter) {
        when (statusFilter) {
            "成功" -> records.filter { it.status }
            "失败" -> records.filter { !it.status }
            else -> records
        }
    }

    ExpressiveTintedScaffold(
        title = if (totalCount > 0) "整理历史 (%,d)".format(totalCount) else "整理历史",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Inbox,
                contentDescription = "整理队列",
                onClick = {
                    isLoadingQueue = true
                    showQueueSheet = true
                },
            )
        },
        headerExtra = {
            ExpressivePillTabRow(
                tabs = statusTabs,
                selectedIndex = statusTabs.indexOf(statusFilter).coerceAtLeast(0),
                onSelect = { idx -> statusFilter = statusTabs[idx] },
                onTintedHeader = true,
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(14.dp))

            CinematicPanel(padding = 12.dp, cornerRadius = 20.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
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

            Spacer(Modifier.height(12.dp))

            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { reloadHistory() }
                },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                if (isLoading && records.isEmpty()) {
                    NativeCardListSkeleton(
                        style = SkeletonCardStyle.PosterRow,
                        count = 5,
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = 64.dp + bottomOverlayInset),
                    )
                } else {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = 64.dp + bottomOverlayInset),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        if (filtered.isEmpty()) {
                            item {
                                CinematicPanel(padding = 28.dp, showsShadow = false) {
                                    Column(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Icon(Icons.AutoMirrored.Rounded.DriveFileMove, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(36.dp))
                                        Text("暂无匹配的整理记录", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                        Text("完成自动或手动识别刮削整理后，历史记录将汇总于此。", color = colors.textSecondary, fontSize = 12.5.sp, textAlign = TextAlign.Center)
                                    }
                                }
                            }
                        }
                        items(filtered, key = { it.id }) { rec ->
                        var rowMenuOpen by remember { mutableStateOf(false) }
                        CinematicPanel(
                            padding = 14.dp,
                            cornerRadius = 22.dp,
                            showsShadow = false,
                            modifier = Modifier.combinedClickable(
                                onClick = { retransferTarget = rec },
                                onLongClick = { deleteTarget = rec },
                            ),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                // 顶部：2:3 封面 + 片名季集 + 成功/失败状态胶囊 + 显式 `⋮` 更多菜单
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
                                            Spacer(Modifier.width(6.dp))
                                            NativeAdaptiveBadge(if (rec.status) "成功" else "失败", tint = if (rec.status) colors.success else colors.danger)
                                            Box {
                                                IconButton(onClick = { rowMenuOpen = true }, modifier = Modifier.size(28.dp)) {
                                                    Icon(Icons.Rounded.MoreVert, contentDescription = "更多操作", tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                                }
                                                DropdownMenu(expanded = rowMenuOpen, onDismissRequest = { rowMenuOpen = false }) {
                                                    DropdownMenuItem(
                                                        text = { Text("重新手动识别整理") },
                                                        leadingIcon = { Icon(Icons.AutoMirrored.Rounded.DriveFileMove, contentDescription = null) },
                                                        onClick = {
                                                            rowMenuOpen = false
                                                            retransferTarget = rec
                                                        },
                                                    )
                                                    DropdownMenuItem(
                                                        text = { Text("删除记录…", color = colors.danger) },
                                                        leadingIcon = { Icon(Icons.Rounded.Delete, contentDescription = null, tint = colors.danger) },
                                                        onClick = {
                                                            rowMenuOpen = false
                                                            deleteTarget = rec
                                                        },
                                                    )
                                                }
                                            }
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
                                        if (!rec.status && !rec.errmsg.isNullOrBlank()) {
                                            Text(rec.errmsg!!, color = colors.danger, fontSize = 11.5.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                        }
                                    }
                                }

                                // 链式源 → 目标路径暗透子卡（带真实存储品牌 Logo）
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
                                            StorageTag(rec.srcStorage)
                                            Text(rec.src.substringAfterLast('/'), color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                        }
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            StorageTag(rec.destStorage)
                                            Text(rec.dest.substringAfterLast('/'), color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
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

    if (showQueueSheet) {
        NativeGlassSheet(onDismissRequest = { showQueueSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    text = if (isLoadingQueue && queueItems.isEmpty()) "整理队列" else "整理队列 (${queueItems.size})",
                    color = colors.textPrimary,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                )
                if (isLoadingQueue && queueItems.isEmpty()) {
                    NativeCardListSkeleton(
                        style = SkeletonCardStyle.IconRow,
                        count = 3,
                        contentPadding = PaddingValues(0.dp),
                        scrollable = false,
                    )
                } else if (queueItems.isEmpty()) {
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

    retransferTarget?.let { rec ->
        ManualTransferSheet(
            repository = repository,
            fileItem = null,
            historyLogId = rec.id,
            sourceStorageHint = rec.srcStorage.ifBlank { "local" },
            sourceTitleHint = rec.title.ifBlank { rec.src.substringAfterLast('/') },
            sourcePathHint = rec.src,
            onDismiss = { retransferTarget = null },
            onCompleted = { msg ->
                retransferTarget = null
                scope.launch {
                    reloadHistory()
                    snackbar?.showSnackbar(msg)
                }
            },
        )
    }

    // 4 种删除模式全部真实对接 `DELETE /api/v1/history/transfer?deletesrc=...&deletedest=...`
    deleteTarget?.let { rec ->
        val deleteModes = listOf(
            Triple("仅删除记录", false, false),
            Triple("删除记录与源文件", true, false),
            Triple("删除记录与媒体库目标文件", false, true),
            Triple("同时删除记录、源与目标文件", true, true),
        )
        NativeGlassSheet(onDismissRequest = { if (!isDeleting) deleteTarget = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("删除整理记录：${rec.title}", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Text("操作将同步至 MoviePilot 服务端，请谨慎选择是否连带清理磁盘/网盘文件。", color = colors.textMuted, fontSize = 12.sp)
                deleteModes.forEach { (optionLabel, deleteSrc, deleteDest) ->
                    CinematicPanel(
                        padding = 14.dp,
                        showsShadow = false,
                        modifier = Modifier.clickable(enabled = !isDeleting) {
                            isDeleting = true
                            scope.launch {
                                val (ok, msg) = repository.deleteTransferHistory(
                                    record = rec,
                                    deleteSrc = deleteSrc,
                                    deleteDest = deleteDest,
                                )
                                isDeleting = false
                                if (ok) {
                                    records = records.filterNot { it.id == rec.id }
                                    totalCount = (totalCount - 1).coerceAtLeast(0)
                                    deleteTarget = null
                                }
                                snackbar?.showSnackbar(msg)
                            }
                        },
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = optionLabel,
                                color = if (deleteSrc && deleteDest) colors.danger else if (deleteSrc || deleteDest) colors.warning else colors.textPrimary,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                            )
                            if (isDeleting) {
                                CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
                            }
                        }
                    }
                }
                Spacer(Modifier.height(20.dp))
            }
        }
    }
}

@Composable
private fun StorageTag(rawStorage: String) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(colors.chipFill)
            .padding(horizontal = 6.dp, vertical = 2.5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        NativeEntityLogo(
            kind = "storage",
            value = rawStorage,
            size = 13.dp,
            cornerRadius = 3.dp,
        )
        Text(storageLabel(rawStorage), color = colors.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Medium)
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
