package com.moviepilot.medal3d

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.TouchApp
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.CinematicAmbientGradient
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeGlassSheet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 阶梯勋章金属档位铭牌（1:1 复刻 iOS `NativeMedalTierNameplate`）：
 * 1 青铜初光、2 白银共建、3 流金卓越、4 黑金核心。
 */
@Composable
fun NativeMedalTierNameplate(
    tier: Int,
    text: String,
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val style = CommunityMedalCatalog.tierStyle(tier)
    val metal = CommunityMedalCatalog.parseColor(style.metalHex)
    val ink = CommunityMedalCatalog.parseColor(if (colors.isDark) style.darkInkHex else style.lightInkHex)
    val borderAlpha = if (style.isObsidianGold) 0.54f else 0.38f
    val baseFill = if (style.isObsidianGold) {
        if (colors.isDark) Color(0xDB17191C) else metal.copy(alpha = 0.16f)
    } else {
        metal.copy(alpha = if (colors.isDark) 0.15f else 0.14f)
    }

    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(baseFill)
            .background(
                Brush.linearGradient(
                    listOf(
                        Color.Transparent,
                        Color.White.copy(alpha = if (style.isObsidianGold) 0.06f else 0.09f),
                        Color.Transparent,
                    ),
                ),
            )
            .border(0.75.dp, metal.copy(alpha = borderAlpha), CircleShape)
            .padding(horizontal = if (compact) 7.dp else 11.dp, vertical = if (compact) 2.5.dp else 4.5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = ink,
            fontSize = if (compact) 10.sp else 12.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
    }
}

/**
 * 「我的」仪表盘社区勋章陈列卡片（1:1 复刻 iOS `NativeCommunityMedalsWidget`）：
 * 4 列网格展示全部已获真实社区勋章（径向主色光晕 + 完整非圆裁浮雕艺术图 + 红点/佩戴角标 + 四档金属铭牌），
 * 轻点任意一枚直达全屏 3D OpenGL ES 互动舞台。
 */
@Composable
fun NativeCommunityMedalsWidget(
    profile: CommunityProfile,
    onSelectMedal: (CommunityMedalRecord) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
    val store = remember(context) { CommunityMedalsPrefsStore(context) }
    @Suppress("UNUSED_VARIABLE")
    val rev = store.revision
    val medals = remember(profile) { profile.orderedKnownMedals }
    if (medals.isEmpty()) return

    val unseen = store.unseenCount(medals, profile.userId)
    val wornKey = store.wornMedalKey(profile.userId)

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "社区勋章",
                color = colors.textPrimary,
                fontSize = 19.sp,
                fontWeight = FontWeight.Bold,
            )
            if (unseen > 0) {
                Spacer(Modifier.width(8.dp))
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color(0xDBE53935))
                        .padding(horizontal = 7.dp, vertical = 2.dp),
                ) {
                    Text("$unseen 枚新勋章", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.weight(1f))
            val rightText = if (!profile.login.isNullOrBlank()) {
                "@${profile.login} · 共 ${medals.size} 枚"
            } else {
                "共 ${medals.size} 枚"
            }
            Text(rightText, color = colors.textSecondary, fontSize = 12.sp)
        }

        CinematicPanel(padding = 14.dp) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                medals.chunked(4).forEach { rowItems ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        rowItems.forEach { record ->
                            MedalDashboardTile(
                                record = record,
                                isUnseen = store.isUnseen(record, profile.userId),
                                isWorn = wornKey == record.key,
                                onClick = { onSelectMedal(record) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                        repeat(4 - rowItems.size) {
                            Spacer(Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MedalDashboardTile(
    record: CommunityMedalRecord,
    isUnseen: Boolean,
    isWorn: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val spec = record.spec
    val tone = CommunityMedalCatalog.parseColor(spec?.toneHex ?: "#9b7bff")
    val artwork = remember(record.key, record.normalizedTier) {
        CommunityMedalAssetEngine.loadFrontBitmap(context, record)
            ?: CommunityMedalAssetEngine.loadBadgeBitmap(context, record)
    }

    Column(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(modifier = Modifier.size(64.dp), contentAlignment = Alignment.Center) {
            // 径向氛围光晕（禁止把非圆形雕刻勋章裁成圆）
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            tone.copy(alpha = if (colors.isDark) 0.34f else 0.24f),
                            tone.copy(alpha = 0.02f),
                        ),
                        center = center,
                        radius = size.minDimension * 0.5f,
                    ),
                )
            }
            if (artwork != null) {
                Image(
                    bitmap = artwork.asImageBitmap(),
                    contentDescription = spec?.name ?: record.key,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(58.dp),
                )
            } else {
                Icon(Icons.Rounded.WorkspacePremium, contentDescription = null, tint = tone, modifier = Modifier.size(34.dp))
            }

            if (isUnseen) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = (-2).dp, y = 2.dp)
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(Color(0xFFFF3B30))
                        .border(1.dp, Color.White.copy(alpha = 0.85f), CircleShape),
                )
            } else if (isWorn) {
                Icon(
                    imageVector = Icons.Rounded.Verified,
                    contentDescription = "已佩戴",
                    tint = tone,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(15.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.65f)),
                )
            }
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                text = spec?.name ?: record.key,
                color = colors.textPrimary,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val tier = record.normalizedTier
            if (tier != null) {
                NativeMedalTierNameplate(
                    tier = tier,
                    text = CommunityMedalCatalog.tierStyle(tier).name,
                    compact = true,
                )
            } else {
                Text(
                    text = if (spec?.isAutomatic == true) "自动" else "荣誉",
                    color = colors.textMuted,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * 全屏沉浸式 3D 社区勋章互动舞台（1:1 复刻 iOS `NativeCommunityMedalShowcaseView`）：
 * 支持拖动 3D 倾斜回弹、轻点翻面查看背面三遍凹雕铭文、左上操作菜单（佩戴/保存分享图/详情）、
 * 中央 OpenGL ES 3D 雕刻金属舞台、标题/金属铭牌/致敬文案、底部流式居中 `-badge.webp` 胶囊切换栏。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun NativeCommunityMedalShowcaseOverlay(
    profile: CommunityProfile,
    initialKey: String,
    onDismiss: () -> Unit,
    onRefreshProfile: (suspend () -> CommunityProfile?)? = null,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val store = remember(context) { CommunityMedalsPrefsStore(context) }
    @Suppress("UNUSED_VARIABLE")
    val rev = store.revision

    var currentProfile by remember(profile) { mutableStateOf(profile) }
    val medals = remember(currentProfile) { currentProfile.orderedKnownMedals }
    var activeKey by remember(initialKey) { mutableStateOf(initialKey) }
    val activeRecord = medals.firstOrNull { it.key == activeKey } ?: medals.firstOrNull()
    val spec = activeRecord?.spec
    val rawTone = CommunityMedalCatalog.parseColor(spec?.toneHex ?: "#9b7bff")
    val tone by animateColorAsState(rawTone, tween(420), label = "medalTone")
    val isWorn = activeRecord != null && store.wornMedalKey(currentProfile.userId) == activeRecord.key

    var showMenu by remember { mutableStateOf(false) }
    var showDetailSheet by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    var noticeText by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(activeRecord?.key) {
        activeRecord?.let { store.markSeen(it, currentProfile.userId) }
    }

    val config = LocalConfiguration.current
    val stageSizeDp = minOf(config.screenWidthDp - 24, (config.screenHeightDp * 0.44f).toInt(), 380).dp

    Box(modifier = Modifier.fillMaxSize()) {
        // 深浅自适应通透暗幕
        CinematicAmbientGradient()
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    if (colors.isDark) Color.Black.copy(alpha = 0.58f)
                    else Color.White.copy(alpha = 0.42f),
                ),
        )

        // 勋章背后径向主色氛围光晕
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 110.dp)
                .size(stageSizeDp * 1.15f)
                .blur(26.dp)
                .background(
                    Brush.radialGradient(
                        listOf(
                            tone.copy(alpha = if (colors.isDark) 0.28f else 0.32f),
                            tone.copy(alpha = 0.08f),
                            Color.Transparent,
                        ),
                    ),
                    CircleShape,
                ),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 顶部栏：左上 @login 菜单胶囊，右上 X 关闭按钮
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Box {
                    if (activeRecord != null) {
                        CinematicGlassSurface(
                            shape = CircleShape,
                            blurRadiusDp = 18.dp,
                            useLiveBackdropBlur = false,
                            modifier = Modifier.clickable { showMenu = true },
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Icon(
                                    imageVector = if (isWorn) Icons.Rounded.Verified else Icons.Rounded.WorkspacePremium,
                                    contentDescription = null,
                                    tint = if (isWorn) tone else colors.textPrimary.copy(alpha = 0.82f),
                                    modifier = Modifier.size(16.dp),
                                )
                                if (!currentProfile.login.isNullOrBlank()) {
                                    Text(
                                        text = "@${currentProfile.login}",
                                        color = colors.textPrimary.copy(alpha = 0.88f),
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.Medium,
                                    )
                                }
                                Icon(
                                    imageVector = Icons.Rounded.MoreHoriz,
                                    contentDescription = "勋章操作菜单",
                                    tint = colors.textSecondary,
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                        }

                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            DropdownMenuItem(
                                text = { Text(if (isWorn) "取消佩戴" else "佩戴勋章") },
                                leadingIcon = { Icon(Icons.Rounded.Verified, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    store.toggleWear(activeRecord.key, currentProfile.userId)
                                    noticeText = if (isWorn) "已取消佩戴勋章" else "已佩戴「${spec?.name ?: activeRecord.key}」勋章"
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("保存荣誉海报 (1080×1350)") },
                                leadingIcon = { Icon(Icons.Rounded.Share, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    scope.launch {
                                        val poster = withContext(Dispatchers.Default) {
                                            CommunityMedalAssetEngine.renderSharePoster(context, activeRecord, currentProfile.login)
                                        }
                                        if (poster != null) {
                                            val savedUri = withContext(Dispatchers.IO) {
                                                persistHonorPosterBitmap(context, poster, activeRecord.key)
                                            }
                                            if (savedUri != null) {
                                                noticeText = "已保存 1080×1350 荣誉海报至相册"
                                                runCatching {
                                                    val caption = "我在 MoviePilot 获得了「${spec?.name ?: activeRecord.key}」社区勋章！"
                                                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                                        type = "image/png"
                                                        putExtra(Intent.EXTRA_STREAM, savedUri)
                                                        putExtra(Intent.EXTRA_TEXT, caption)
                                                        clipData = ClipData.newRawUri("MoviePilot Honor Poster", savedUri)
                                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                    }
                                                    context.startActivity(Intent.createChooser(shareIntent, "分享社区荣誉海报"))
                                                }
                                            } else {
                                                noticeText = "海报保存失败，请稍后重试"
                                            }
                                        }
                                    }
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("勋章详情") },
                                leadingIcon = { Icon(Icons.Outlined.Info, contentDescription = null) },
                                onClick = {
                                    showMenu = false
                                    showDetailSheet = true
                                },
                            )
                        }
                    }
                }

                CinematicGlassSurface(
                    shape = CircleShape,
                    blurRadiusDp = 18.dp,
                    useLiveBackdropBlur = false,
                    modifier = Modifier.size(38.dp).clickable(onClick = onDismiss),
                ) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.Close, contentDescription = "关闭", tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                    }
                }
            }

            noticeText?.let {
                Text(it, color = tone, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }

            Spacer(Modifier.weight(0.5f))

            // 中央 OpenGL ES 真 3D 雕刻勋章舞台
            if (activeRecord != null) {
                NativeMedal3DStageView(
                    record = activeRecord,
                    login = currentProfile.login,
                    modifier = Modifier.size(stageSizeDp),
                )
            }

            // 交互提示
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.padding(top = 4.dp),
            ) {
                Icon(Icons.Rounded.TouchApp, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(14.dp))
                Text("轻点翻面 · 拖动转动", color = colors.textMuted, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }

            // 标题、金属档位铭牌与致敬文案
            if (activeRecord != null) {
                Column(
                    modifier = Modifier.padding(top = 12.dp, start = 28.dp, end = 28.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = spec?.name ?: activeRecord.key,
                        color = colors.textPrimary,
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    val tier = activeRecord.normalizedTier
                    val tierLine = CommunityMedalCatalog.tierLine(activeRecord)
                    val timeLine = CommunityMedalCatalog.timeLine(activeRecord)
                    if (tier != null && tierLine != null) {
                        NativeMedalTierNameplate(tier = tier, text = tierLine, compact = false)
                    } else if (timeLine != null) {
                        Text(timeLine, color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    }
                    spec?.summary?.let {
                        Text(
                            text = it,
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                            maxLines = 2,
                        )
                    }
                }
            }

            Spacer(Modifier.weight(1f))

            // 底部流式居中多枚勋章胶囊切换栏（带 -badge.webp 微型图标）
            if (medals.size > 1) {
                FlowRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 18.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    medals.forEach { item ->
                        val selected = item.key == activeKey
                        val itemTone = CommunityMedalCatalog.parseColor(item.spec?.toneHex ?: "#9b7bff")
                        val badgeBmp = remember(item.key, item.normalizedTier) {
                            CommunityMedalAssetEngine.loadBadgeBitmap(context, item)
                        }
                        val itemUnseen = store.isUnseen(item, currentProfile.userId)
                        Row(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(
                                    if (selected) itemTone.copy(alpha = if (colors.isDark) 0.28f else 0.22f)
                                    else colors.chipFill,
                                )
                                .border(
                                    width = 0.75.dp,
                                    color = if (selected) itemTone.copy(alpha = 0.65f) else colors.chipBorder,
                                    shape = CircleShape,
                                )
                                .clickable {
                                    activeKey = item.key
                                    store.markSeen(item, currentProfile.userId)
                                }
                                .padding(horizontal = 11.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            if (badgeBmp != null) {
                                Image(
                                    bitmap = badgeBmp.asImageBitmap(),
                                    contentDescription = null,
                                    contentScale = ContentScale.Fit,
                                    modifier = Modifier.size(19.dp),
                                )
                            }
                            Text(
                                text = item.spec?.name ?: item.key,
                                color = colors.textPrimary.copy(alpha = if (selected) 0.98f else 0.76f),
                                fontSize = 12.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            )
                            if (itemUnseen) {
                                Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFFFF3B30)))
                            }
                        }
                    }
                }
            }
        }
    }

    if (showDetailSheet && activeRecord != null) {
        NativeCommunityMedalDetailSheet(
            record = activeRecord,
            profile = currentProfile,
            isRefreshing = isRefreshing,
            onRefresh = {
                if (!isRefreshing && onRefreshProfile != null) {
                    scope.launch {
                        isRefreshing = true
                        onRefreshProfile()?.let { currentProfile = it }
                        isRefreshing = false
                    }
                }
            },
            onDismiss = { showDetailSheet = false },
        )
    }
}

/** 社区勋章详情玻璃弹窗（1:1 复刻 `NativeCommunityMedalDetailSheet`）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NativeCommunityMedalDetailSheet(
    record: CommunityMedalRecord,
    profile: CommunityProfile,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val spec = record.spec
    val tone = CommunityMedalCatalog.parseColor(spec?.toneHex ?: "#9b7bff")
    val badge = remember(record.key, record.normalizedTier) {
        CommunityMedalAssetEngine.loadBadgeBitmap(context, record)
    }
    var showAllPlugins by remember { mutableStateOf(false) }

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("勋章详情", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Text(
                    text = "完成",
                    color = colors.accent,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clickable(onClick = onDismiss).padding(4.dp),
                )
            }

            // 头部概览
            CinematicPanel(padding = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (badge != null) {
                        Image(bitmap = badge.asImageBitmap(), contentDescription = null, modifier = Modifier.size(44.dp))
                    } else {
                        Icon(Icons.Rounded.WorkspacePremium, contentDescription = null, tint = tone, modifier = Modifier.size(40.dp))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(spec?.name ?: record.key, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            val tier = record.normalizedTier
                            val tierLine = CommunityMedalCatalog.tierLine(record)
                            if (tier != null && tierLine != null) {
                                NativeMedalTierNameplate(tier = tier, text = tierLine, compact = true)
                            }
                        }
                        val sub = listOfNotNull(spec?.howLabel, CommunityMedalCatalog.timeLine(record)).joinToString(" · ")
                        if (sub.isNotBlank()) {
                            Text(sub, color = colors.textSecondary, fontSize = 12.sp)
                        }
                    }
                }
            }

            // 规则
            spec?.let {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("规则", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(it.rule, color = colors.textPrimary.copy(alpha = 0.90f), fontSize = 14.sp)
                            record.note?.takeIf { n -> n.isNotBlank() }?.let { note ->
                                Text("贡献 · $note", color = tone, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }

            // 阶梯四档进度条
            val progress = CommunityMedalCatalog.tierProgress(record)
            if (spec != null && progress != null) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("档位进度", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Canvas(modifier = Modifier.fillMaxWidth().height(16.dp)) {
                                val trackStart = size.width * 0.125f
                                val trackW = size.width * 0.75f
                                val cy = size.height * 0.5f
                                drawLine(
                                    color = colors.textPrimary.copy(alpha = 0.14f),
                                    start = Offset(trackStart, cy),
                                    end = Offset(trackStart + trackW, cy),
                                    strokeWidth = 4.dp.toPx(),
                                )
                                drawLine(
                                    color = tone,
                                    start = Offset(trackStart, cy),
                                    end = Offset(trackStart + trackW * progress.trackFill.toFloat(), cy),
                                    strokeWidth = 4.dp.toPx(),
                                )
                                for (t in 1..4) {
                                    val cx = trackStart + trackW * ((t - 1) / 3f)
                                    val reached = t <= progress.currentTier
                                    drawCircle(
                                        color = if (reached) tone else colors.textPrimary.copy(alpha = 0.24f),
                                        radius = if (reached) 5.5.dp.toPx() else 4.dp.toPx(),
                                        center = Offset(cx, cy),
                                    )
                                }
                            }
                            Row(modifier = Modifier.fillMaxWidth()) {
                                for (t in 1..4) {
                                    val reached = t <= progress.currentTier
                                    Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                                        Text(
                                            CommunityMedalCatalog.tierStyle(t).name,
                                            color = if (reached) colors.textPrimary else colors.textSecondary,
                                            fontSize = 12.sp,
                                            fontWeight = if (reached) FontWeight.SemiBold else FontWeight.Normal,
                                        )
                                        Text(
                                            spec.thresholdLabels.getOrElse(t - 1) { "" },
                                            color = colors.textMuted,
                                            fontSize = 11.sp,
                                        )
                                    }
                                }
                            }
                            Text(progress.statusText, color = tone, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }

            // 编剧官方仓贡献证据
            if (record.key == "code" && record.facts != null && record.facts.repositories.isNotEmpty()) {
                val repos = record.facts.repositories.sortedByDescending { it.effectiveCount }
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "已采纳贡献 ${CommunityMedalCatalog.formatCount(record.facts.total ?: 0)} 次",
                        color = colors.textSecondary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("仅列出有贡献的仓库。同一仓库的 PR 与提交，只按其中较多的一项计算。", color = colors.textMuted, fontSize = 11.sp)
                            repos.forEach { repo ->
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Column {
                                        Text(repo.repository, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                        Text(
                                            "PR ${repo.mergedPRs} · 提交 ${repo.commits}",
                                            color = colors.textSecondary,
                                            fontSize = 11.sp,
                                        )
                                    }
                                    Text(
                                        CommunityMedalCatalog.formatCount(repo.effectiveCount),
                                        color = tone,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Bold,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // 布景插件安装量明细
            if (record.key == "plugin" && record.facts != null && record.facts.plugins.isNotEmpty()) {
                val sorted = record.facts.plugins.sortedByDescending { it.installs }
                val visible = if (showAllPlugins) sorted else sorted.take(5)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        "累计安装 ${CommunityMedalCatalog.formatCount(record.facts.installs ?: 0)} 次",
                        color = colors.textSecondary,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            visible.forEachIndexed { idx, p ->
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(p.name, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                                        Text(p.id, color = colors.textMuted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                                    }
                                    Text(CommunityMedalCatalog.formatCount(p.installs), color = tone, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                }
                                if (idx < visible.lastIndex) HorizontalDivider(color = colors.divider)
                            }
                            if (sorted.size > 5) {
                                Text(
                                    text = if (showAllPlugins) "收起" else "查看全部 ${sorted.size} 个",
                                    color = tone,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.fillMaxWidth().clickable { showAllPlugins = !showAllPlugins }.padding(vertical = 4.dp),
                                )
                            }
                        }
                    }
                }
            }

            // 底部数据来源与刷新
            CinematicPanel(padding = 12.dp) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("数据来自 MoviePilot Wiki 社区荣誉名单。", color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.chipFill)
                            .clickable(enabled = !isRefreshing, onClick = onRefresh)
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(Icons.Rounded.Refresh, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(14.dp))
                        Text(if (isRefreshing) "刷新中…" else "刷新", color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/**
 * 将 1080×1350 荣誉海报 Bitmap 写入系统相册（`Pictures/MoviePilot`）并返回可分享的 `image/png` URI；
 * 若设备外部存储不可用，自动回退至应用受管 `cacheDir/medal_posters` 经 `FileProvider` 授权分享。
 */
private fun persistHonorPosterBitmap(context: Context, bitmap: Bitmap, medalKey: String): Uri? {
    val fileName = "moviepilot_medal_${medalKey}_${System.currentTimeMillis()}.png"
    val mediaStoreUri = runCatching {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/MoviePilot")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return@runCatching null
        val wrote = resolver.openOutputStream(uri)?.use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        } ?: false
        if (!wrote) {
            resolver.delete(uri, null, null)
            return@runCatching null
        }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        uri
    }.getOrNull()
    if (mediaStoreUri != null) return mediaStoreUri

    return runCatching {
        val dir = File(context.cacheDir, "medal_posters").apply { mkdirs() }
        val file = File(dir, fileName)
        file.outputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }.getOrNull()
}
