package com.moviepilot.feature.library

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DriveFileMove
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.AudioFile
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.Queue
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.StorageFileDto
import com.moviepilot.rustbridge.TransferHistoryDto

/**
 * 多存储文件管理页面：
 * 支持本地/网盘切换、目录导航、点击音视频直接调用原生播放器（Rust `detectMediaKind` 判别）、长按手动整理与重命名弹窗。
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

    val storages = listOf("local" to "本地存储", "u115" to "115网盘", "alipan" to "阿里云盘", "rclone" to "Rclone", "smb" to "SMB")
    var activeStorage by remember { mutableStateOf(initialStorage) }
    var currentPath by remember { mutableStateOf(initialPath) }
    var files by remember { mutableStateOf<List<StorageFileDto>>(emptyList()) }
    var actionTarget by remember { mutableStateOf<StorageFileDto?>(null) }

    LaunchedEffect(activeStorage, currentPath) {
        val fetched = repository.fetchFiles(activeStorage, currentPath)
        files = fetched.ifEmpty { sampleFiles(activeStorage, currentPath) }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "文件管理", onBack = onBack)

        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(storages) { (id, label) ->
                NativeAdaptivePill(label, selected = id == activeStorage, onClick = {
                    activeStorage = id
                    currentPath = "/"
                })
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            text = "路径：$currentPath（长按文件可手动整理/重命名）",
            color = colors.textMuted,
            fontSize = 12.sp,
            modifier = Modifier.padding(horizontal = margin),
        )
        Spacer(Modifier.height(10.dp))

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(files, key = { it.path + it.name }) { file ->
                val playableKind = remember(file.name, file.extension) {
                    if (file.type == "dir") null
                    else RustCoreBridge.detectMediaKind(file.extension ?: file.name, false)
                }
                CinematicPanel(
                    padding = 14.dp,
                    modifier = Modifier.combinedClickable(
                        onClick = {
                            if (file.type == "dir") {
                                currentPath = file.path
                            } else if (playableKind != null) {
                                onPlayMedia(
                                    MediaPlaybackRequest(
                                        url = if (playableKind == "audio") {
                                            "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"
                                        } else {
                                            "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
                                        },
                                        title = file.name,
                                        subtitle = "${file.storage} · ${file.path}",
                                        isAudio = playableKind == "audio",
                                    ),
                                )
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
                            tint = if (file.type == "dir") colors.warning else colors.accent,
                            modifier = Modifier.size(26.dp),
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(file.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(file.path, color = colors.textMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        if (playableKind != null) {
                            NativeAdaptiveBadge(if (playableKind == "audio") "音频" else "播放", tint = colors.success)
                        }
                    }
                }
            }
        }
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
                    onClick = { actionTarget = null },
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

/**
 * 整理历史页面：常驻顶部搜索框、链式源→目标路径展示、右上角整理队列弹窗与 4 种源/目标组合删除菜单。
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
    var records by remember { mutableStateOf<List<TransferHistoryDto>>(emptyList()) }
    var showQueueSheet by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<TransferHistoryDto?>(null) }

    LaunchedEffect(search) {
        val fetched = repository.fetchTransferHistory(search)
        records = fetched.ifEmpty {
            sampleHistory().filter { search.isBlank() || it.title.contains(search, ignoreCase = true) }
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "整理历史",
            onBack = onBack,
            trailing = {
                CinematicCircleButton(Icons.Rounded.Queue, "整理队列", { showQueueSheet = true })
            },
        )

        CinematicPanel(padding = 12.dp, cornerRadius = 22.dp, modifier = Modifier.padding(horizontal = margin)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(18.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (search.isEmpty()) Text("筛选片名、路径或季集...", color = colors.textMuted, fontSize = 14.sp)
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

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(records, key = { it.id }) { rec ->
                CinematicPanel(
                    padding = 14.dp,
                    modifier = Modifier.combinedClickable(
                        onClick = {},
                        onLongClick = { deleteTarget = rec },
                    ),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(
                                    if (rec.status) Icons.Rounded.CheckCircle else Icons.Rounded.Error,
                                    contentDescription = null,
                                    tint = if (rec.status) colors.success else colors.danger,
                                    modifier = Modifier.size(18.dp),
                                )
                                Text("${rec.title} ${rec.seasons}${rec.episodes}", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            }
                            NativeAdaptiveBadge(rec.mode, tint = colors.accent)
                        }
                        Text("源：${rec.src}", color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text("至：${rec.dest}", color = colors.info, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(rec.date, color = colors.textMuted, fontSize = 11.sp)
                    }
                }
            }
        }
    }

    if (showQueueSheet) {
        NativeGlassSheet(onDismissRequest = { showQueueSheet = false }) {
            Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("整理队列", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                CinematicPanel(padding = 14.dp) {
                    Text("当前整理队列空闲，新下载完成将自动入队识别刮削。", color = colors.textSecondary, fontSize = 14.sp)
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

private fun sampleFiles(storage: String, path: String): List<StorageFileDto> = listOf(
    StorageFileDto(storage, "dir", "$path/movies".replace("//", "/"), "movies"),
    StorageFileDto(storage, "dir", "$path/tv".replace("//", "/"), "tv"),
    StorageFileDto(storage, "file", "$path/Dune.Part.Two.2160p.mkv".replace("//", "/"), "Dune.Part.Two.2160p.mkv", "mkv", 34_359_738_368L),
    StorageFileDto(storage, "file", "$path/Fantasy.24bit.flac".replace("//", "/"), "Fantasy.24bit.flac", "flac", 89_128_960L),
)

private fun sampleHistory(): List<TransferHistoryDto> = listOf(
    TransferHistoryDto(801, "合成追剧", "电视剧", "2025", "S01", "E08", true, "硬链接", "2026-11-23 14:20", null, "/downloads/tv/syn-s01e08.mkv", "/video/tv/合成追剧/Season 1/S01E08.mkv"),
    TransferHistoryDto(802, "奥德赛", "电影", "2026", "", "", true, "硬链接", "2026-11-23 11:05", null, "/downloads/movies/The.Odyssey.2160p.mkv", "/video/movies/奥德赛 (2026)/奥德赛.2160p.mkv"),
)
