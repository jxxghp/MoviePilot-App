package com.moviepilot.media.danmaku

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.rustbridge.DanmakuAnimeSearchItemDto
import com.moviepilot.rustbridge.DanmakuBangumiDto
import com.moviepilot.rustbridge.DanmakuEpisodeCandidateDto
import com.moviepilot.rustbridge.MoviePilotRepository
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** Material 3 Expressive 弹幕渲染设置半弹窗。 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DanmakuSettingsBottomSheet(
    prefs: DanmakuPreferencesStore,
    matchedSummary: String,
    totalCount: Int,
    fromBinding: Boolean,
    shiftMs: Int,
    onPreferencesChanged: () -> Unit,
    onShiftChanged: (Int) -> Unit,
    onSaveShiftToServer: suspend () -> Unit,
    onOpenManualMatch: () -> Unit,
    onForceRefresh: suspend () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    var keywordInput by remember { mutableStateOf("") }
    var feedback by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    val areaOptions = listOf(0.25f to "1/4 屏", 0.5f to "半屏", 0.75f to "3/4 屏", 1.0f to "全屏")
    val maxOptions = listOf(20, 40, 60, 100)
    val shiftButtons = listOf(-5000 to "-5s", -1000 to "-1s", -500 to "-0.5s", 500 to "+0.5s", 1000 to "+1s", 5000 to "+5s")

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("弹幕设置", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Switch(
                    checked = prefs.enabled,
                    onCheckedChange = {
                        prefs.updateEnabled(it)
                        onPreferencesChanged()
                    },
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg),
                )
            }

            Surface(
                shape = RoundedCornerShape(16.dp),
                color = colors.surfaceContainerLow,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = matchedSummary.ifBlank { "未匹配到弹幕" },
                            color = colors.textPrimary,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (totalCount > 0) {
                            Text(
                                text = if (fromBinding) "手动绑定 · 共 $totalCount 条弹幕" else "自动匹配 · 共 $totalCount 条弹幕",
                                color = colors.textMuted,
                                fontSize = 12.sp,
                            )
                        }
                    }
                    OutlinedButton(
                        onClick = {
                            onDismiss()
                            onOpenManualMatch()
                        },
                        shape = CircleShape,
                    ) {
                        Text("更换匹配", fontSize = 12.sp)
                    }
                    IconButton(
                        enabled = !busy,
                        onClick = {
                            scope.launch {
                                busy = true
                                onForceRefresh()
                                busy = false
                                feedback = "已强制刷新服务端弹幕"
                            }
                        },
                    ) {
                        Icon(Icons.Rounded.Refresh, contentDescription = "强制刷新弹幕", tint = colors.accent)
                    }
                }
            }

            DanmakuSliderRow(
                label = "不透明度",
                valueLabel = "${(prefs.opacity * 100f).roundToInt()}%",
                value = prefs.opacity,
                range = 0.2f..1.0f,
                onValueChange = {
                    prefs.updateOpacity(it)
                    onPreferencesChanged()
                },
            )
            DanmakuSliderRow(
                label = "字号大小",
                valueLabel = "%.2fx".format(prefs.fontScale),
                value = prefs.fontScale,
                range = 0.75f..1.5f,
                onValueChange = {
                    prefs.updateFontScale(it)
                    onPreferencesChanged()
                },
            )
            DanmakuSliderRow(
                label = "滚动速度",
                valueLabel = "%.1fx".format(prefs.speed),
                value = prefs.speed,
                range = 0.6f..1.6f,
                onValueChange = {
                    prefs.updateSpeed(it)
                    onPreferencesChanged()
                },
            )

            Text("显示区域", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                areaOptions.forEach { (ratio, label) ->
                    val selected = kotlin.math.abs(prefs.areaRatio - ratio) < 0.05f
                    DanmakuChip(label = label, selected = selected) {
                        prefs.updateAreaRatio(ratio)
                        onPreferencesChanged()
                    }
                }
            }

            Text("同屏上限", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                maxOptions.forEach { cap ->
                    DanmakuChip(label = "$cap 条", selected = prefs.maxOnScreen == cap) {
                        prefs.updateMaxOnScreen(cap)
                        onPreferencesChanged()
                    }
                }
            }

            HorizontalDivider(color = colors.divider)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val offsetLabel = if (shiftMs == 0) "0.0s" else "%+.1fs".format(shiftMs / 1000.0)
                Text("时间偏移：$offsetLabel", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (shiftMs != 0) {
                        DanmakuChip(label = "重置", selected = false) { onShiftChanged(0) }
                    }
                    DanmakuChip(label = "保存到服务端", selected = true) {
                        if (!busy) {
                            scope.launch {
                                busy = true
                                onSaveShiftToServer()
                                busy = false
                                feedback = "时间偏移已保存到服务端"
                            }
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                shiftButtons.forEach { (delta, label) ->
                    DanmakuChip(label = label, selected = false) {
                        onShiftChanged((shiftMs + delta).coerceIn(-600_000, 600_000))
                    }
                }
            }

            HorizontalDivider(color = colors.divider)
            Text("类型过滤", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DanmakuChip(label = "滚动弹幕", selected = prefs.allowScroll) {
                    prefs.updateAllowScroll(!prefs.allowScroll)
                    onPreferencesChanged()
                }
                DanmakuChip(label = "顶部弹幕", selected = prefs.allowTop) {
                    prefs.updateAllowTop(!prefs.allowTop)
                    onPreferencesChanged()
                }
                DanmakuChip(label = "底部弹幕", selected = prefs.allowBottom) {
                    prefs.updateAllowBottom(!prefs.allowBottom)
                    onPreferencesChanged()
                }
                DanmakuChip(label = "彩色弹幕", selected = prefs.allowColor) {
                    prefs.updateAllowColor(!prefs.allowColor)
                    onPreferencesChanged()
                }
                DanmakuChip(label = "合并重复", selected = prefs.mergeDuplicates) {
                    prefs.updateMergeDuplicates(!prefs.mergeDuplicates)
                    onPreferencesChanged()
                }
            }

            HorizontalDivider(color = colors.divider)
            Text("关键词屏蔽", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = keywordInput,
                    onValueChange = { keywordInput = it },
                    placeholder = { Text("输入屏蔽词（支持 /正则/）", fontSize = 13.sp) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = {
                        val trimmed = keywordInput.trim()
                        if (trimmed.isNotEmpty()) {
                            prefs.addBlockKeyword(trimmed)
                            keywordInput = ""
                            onPreferencesChanged()
                        }
                    },
                ) {
                    Icon(Icons.Rounded.Add, contentDescription = "添加屏蔽词", tint = colors.accent)
                }
            }
            if (prefs.blockKeywords.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    prefs.blockKeywords.forEach { kw ->
                        Surface(
                            shape = CircleShape,
                            color = colors.surfaceContainerLow,
                        ) {
                            Row(
                                modifier = Modifier.padding(start = 12.dp, end = 6.dp, top = 5.dp, bottom = 5.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Text(kw, color = colors.textPrimary, fontSize = 12.sp)
                                Icon(
                                    Icons.Rounded.Close,
                                    contentDescription = "移除屏蔽词",
                                    tint = colors.textMuted,
                                    modifier = Modifier
                                        .size(16.dp)
                                        .clickable {
                                            prefs.removeBlockKeyword(kw)
                                            onPreferencesChanged()
                                        },
                                )
                            }
                        }
                    }
                }
            }

            if (!feedback.isNullOrBlank()) {
                Text(feedback.orEmpty(), color = colors.accent, fontSize = 12.sp)
            }
            Spacer(Modifier.height(10.dp))
        }
    }
}

/** 播放器内手动搜索剧名与选集纠偏半弹窗。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DanmakuManualMatchBottomSheet(
    repository: MoviePilotRepository,
    initialKeyword: String,
    initialCandidates: List<DanmakuEpisodeCandidateDto>,
    fromBinding: Boolean,
    onSelectEpisode: suspend (DanmakuEpisodeCandidateDto) -> Unit,
    onUnbind: suspend () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    var keyword by remember(initialKeyword) { mutableStateOf(initialKeyword) }
    var results by remember { mutableStateOf<List<DanmakuAnimeSearchItemDto>>(emptyList()) }
    var activeBangumi by remember { mutableStateOf<DanmakuBangumiDto?>(null) }
    var loading by remember { mutableStateOf(false) }
    var errorMsg by remember { mutableStateOf<String?>(null) }

    fun triggerSearch() {
        val q = keyword.trim()
        if (q.isEmpty()) return
        scope.launch {
            loading = true
            errorMsg = null
            activeBangumi = null
            repository.searchDanmaku(q)
                .onSuccess {
                    results = it
                    if (it.isEmpty()) errorMsg = "未搜索到匹配作品，请尝试简化剧名关键词"
                }
                .onFailure { errorMsg = it.message ?: "搜索弹幕失败" }
            loading = false
        }
    }

    LaunchedEffect(initialKeyword) {
        if (initialCandidates.isEmpty() && initialKeyword.isNotBlank()) {
            triggerSearch()
        }
    }

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 560.dp)
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("搜索弹幕剧集", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                if (fromBinding) {
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                onUnbind()
                                onDismiss()
                            }
                        },
                        shape = CircleShape,
                    ) {
                        Icon(Icons.Rounded.DeleteOutline, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.size(4.dp))
                        Text("解绑恢复自动", fontSize = 12.sp)
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = keyword,
                    onValueChange = { keyword = it },
                    placeholder = { Text("输入作品名搜索弹幕", fontSize = 13.sp) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                Button(
                    enabled = !loading && keyword.isNotBlank(),
                    onClick = { triggerSearch() },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                ) {
                    Icon(Icons.Rounded.Search, contentDescription = "搜索", modifier = Modifier.size(18.dp))
                }
            }

            if (loading) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = colors.accent)
                    Spacer(Modifier.size(10.dp))
                    Text("正在查询弹幕库…", color = colors.textMuted, fontSize = 13.sp)
                }
            }

            if (!errorMsg.isNullOrBlank()) {
                Text(errorMsg.orEmpty(), color = colors.danger, fontSize = 12.5.sp)
            }

            val bangumi = activeBangumi
            if (bangumi != null) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { activeBangumi = null }
                        .padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "返回作品列表", tint = colors.accent, modifier = Modifier.size(18.dp))
                    Text(bangumi.animeTitle, color = colors.textPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
                }
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(bangumi.episodes, key = { it.episodeId }) { ep ->
                        DanmakuEpisodePickRow(ep) {
                            scope.launch {
                                onSelectEpisode(ep)
                                onDismiss()
                            }
                        }
                    }
                }
            } else if (results.isNotEmpty()) {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(results, key = { it.animeId }) { anime ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(colors.surfaceContainerLow)
                                .clickable {
                                    if (anime.episodes.isNotEmpty()) {
                                        activeBangumi = DanmakuBangumiDto(
                                            animeId = anime.animeId,
                                            animeTitle = anime.animeTitle,
                                            animeType = anime.animeType,
                                            episodes = anime.episodes,
                                        )
                                    } else {
                                        scope.launch {
                                            loading = true
                                            errorMsg = null
                                            repository.fetchDanmakuBangumi(anime.animeId)
                                                .onSuccess { activeBangumi = it }
                                                .onFailure { errorMsg = it.message ?: "获取分集失败" }
                                            loading = false
                                        }
                                    }
                                }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Text(anime.animeTitle, color = colors.textPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
                            val meta = listOfNotNull(anime.animeType, anime.episodeCount?.let { "共 $it 集" }).joinToString(" · ")
                            if (meta.isNotBlank()) {
                                Text(meta, color = colors.textMuted, fontSize = 12.sp)
                            }
                        }
                    }
                }
            } else if (initialCandidates.isNotEmpty()) {
                Text("推荐候选", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(initialCandidates, key = { it.episodeId }) { ep ->
                        DanmakuEpisodePickRow(ep) {
                            scope.launch {
                                onSelectEpisode(ep)
                                onDismiss()
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun DanmakuEpisodePickRow(
    ep: DanmakuEpisodeCandidateDto,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.surfaceContainerLow)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            text = ep.episodeTitle.ifBlank { "第 ${ep.episodeNumber ?: ep.episodeId} 集" },
            color = colors.textPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
        if (ep.animeTitle.isNotBlank()) {
            Text(ep.animeTitle, color = colors.textMuted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun DanmakuSliderRow(
    label: String,
    valueLabel: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, color = colors.textPrimary, fontSize = 14.sp)
            Text(valueLabel, color = colors.textMuted, fontSize = 13.sp)
        }
        Slider(value = value, onValueChange = onValueChange, valueRange = range)
    }
}

@Composable
private fun DanmakuChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = if (selected) colors.accent else colors.surfaceContainerLow,
    ) {
        Text(
            text = label,
            color = if (selected) colors.primaryButtonFg else colors.textPrimary,
            fontSize = 12.5.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
}
