package com.moviepilot.feature.agent

import android.speech.tts.TextToSpeech
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassCapsule
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.rustbridge.AgentChatMessageDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * AI 智能助手全屏玻璃对话页（1:1 复刻 iOS 黄金截图 `native-v2-live-agent.jpg`）：
 * - 顶栏：左上 `✕` 玻璃圆钮 + 居中「智能助手」+ 右上 `[📝 🕒]` 双图标玻璃胶囊
 * - 消息流：右侧紫色用户胶囊、左侧紫色星光小圆头像 + 玻璃卡片（Rust Markdown AST + 全宽描边交互按钮）
 * - 底栏：`[+  输入消息或 / 命令...  🎤  ↑]` 悬浮玻璃胶囊
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AgentChatScreen(
    repository: MoviePilotRepository,
    initialPrompt: String = "",
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var input by remember { mutableStateOf(initialPrompt) }
    var isStreaming by remember { mutableStateOf(false) }

    val tts = remember {
        var engine: TextToSpeech? = null
        engine = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                engine?.language = Locale.SIMPLIFIED_CHINESE
            }
        }
        engine
    }
    DisposableEffect(tts) {
        onDispose { tts.stop(); tts.shutdown() }
    }

    val messages = remember {
        mutableStateListOf(
            AgentChatMessageDto(
                id = "welcome",
                role = "assistant",
                content = "## 智能助手\n\n我可以帮你搜索影片、管理追剧订阅、查看站点流量与执行 `/skills` 命令。\n\n1. 发送 `/skills` 查看已安装技能与技能市场\n2. 询问「查看最近入库和下载队列状态」\n3. 让我帮你寻找 4K HDR 免费资源",
                quickOptions = listOf("/skills", "查看最近入库", "检查站点健康状态", "推荐高分 4K 电影"),
            ),
        )
    }

    fun sendPrompt(text: String) {
        val clean = text.trim()
        if (clean.isEmpty() || isStreaming) return
        input = ""
        messages.add(AgentChatMessageDto(id = "u-${System.currentTimeMillis()}", role = "user", content = clean))
        val assistantId = "a-${System.currentTimeMillis()}"
        messages.add(
            AgentChatMessageDto(
                id = assistantId,
                role = "assistant",
                content = "",
                thinkingText = "正在调用 MoviePilot V3 Agent SSE 通道...",
                isStreaming = true,
            ),
        )
        isStreaming = true

        scope.launch {
            val flow = repository.streamAgentChat(clean)
            val accumulated = StringBuilder()
            val tools = mutableListOf<String>()
            if (flow != null) {
                flow.catch {
                    accumulated.append("已收到指令「$clean」。当前实例未启用实时 Agent SSE 流或模型未配置，可在服务端完成模型配置后直接执行技能交互。")
                }.collect { ev ->
                    when (ev.event) {
                        "thinking" -> {
                            val idx = messages.indexOfFirst { it.id == assistantId }
                            if (idx >= 0) messages[idx] = messages[idx].copy(thinkingText = ev.data)
                        }
                        "tool_call" -> {
                            tools.add(ev.data.take(40))
                            val idx = messages.indexOfFirst { it.id == assistantId }
                            if (idx >= 0) messages[idx] = messages[idx].copy(toolCalls = tools.toList())
                        }
                        else -> if (!ev.isDone) {
                            accumulated.append(ev.data)
                            val idx = messages.indexOfFirst { it.id == assistantId }
                            if (idx >= 0) messages[idx] = messages[idx].copy(content = accumulated.toString())
                        }
                    }
                }
            }
            if (accumulated.isEmpty()) {
                accumulated.append("已收到「$clean」，请前往对应模块或检查后端 Agent 模型配置。")
            }
            val idx = messages.indexOfFirst { it.id == assistantId }
            if (idx >= 0) {
                messages[idx] = messages[idx].copy(
                    content = accumulated.toString(),
                    thinkingText = null,
                    isStreaming = false,
                )
            }
            isStreaming = false
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .imePadding(),
    ) {
        // 顶栏（1:1 复刻 iOS `✕  智能助手  [📝 🕒]`）
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .height(48.dp),
        ) {
            CinematicCircleButton(
                icon = Icons.Rounded.Close,
                contentDescription = "关闭",
                onClick = onBack,
                modifier = Modifier.align(Alignment.CenterStart),
            )
            Text(
                text = "智能助手",
                color = colors.textPrimary,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.Center),
            )
            CinematicGlassCapsule(modifier = Modifier.align(Alignment.CenterEnd)) {
                IconButton(
                    onClick = {
                        messages.clear()
                        messages.add(
                            AgentChatMessageDto(
                                id = "fresh-${System.currentTimeMillis()}",
                                role = "assistant",
                                content = "已开启新对话，输入消息或 `/skills` 开始交互。",
                                quickOptions = listOf("/skills", "查看最近入库"),
                            ),
                        )
                    },
                    modifier = Modifier.size(38.dp),
                ) {
                    Icon(Icons.Rounded.EditNote, contentDescription = "新对话", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                }
                IconButton(onClick = {}, modifier = Modifier.size(38.dp)) {
                    Icon(Icons.Rounded.History, contentDescription = "历史会话", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                }
            }
        }

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = margin, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(messages, key = { it.id }) { msg ->
                if (msg.role == "user") {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Box(
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(colors.accent)
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                        ) {
                            Text(msg.content, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        // 左侧紫色星光圆徽标（1:1 对齐 iOS）
                        Box(
                            modifier = Modifier
                                .size(30.dp)
                                .clip(CircleShape)
                                .background(colors.accent.copy(alpha = 0.24f))
                                .border(0.7.dp, colors.accent.copy(alpha = 0.45f), CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
                        }

                        CinematicPanel(
                            padding = 14.dp,
                            cornerRadius = 20.dp,
                            showsShadow = false,
                            modifier = Modifier.weight(1f),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                msg.thinkingText?.let { NativeAdaptiveBadge(it, tint = colors.info) }
                                if (msg.toolCalls.isNotEmpty()) {
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        msg.toolCalls.forEach { tc -> NativeAdaptiveBadge(tc, tint = colors.warning) }
                                    }
                                }
                                val blocks = remember(msg.content) { RustCoreBridge.parseMarkdown(msg.content) }
                                blocks.forEach { block ->
                                    when (block.kind) {
                                        "heading" -> Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                            Text(block.text, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                            if (msg.content.isNotBlank()) {
                                                IconButton(onClick = { tts.speak(msg.content, TextToSpeech.QUEUE_FLUSH, null, msg.id) }, modifier = Modifier.size(24.dp)) {
                                                    Icon(Icons.AutoMirrored.Rounded.VolumeUp, contentDescription = "朗读", tint = colors.textMuted, modifier = Modifier.size(16.dp))
                                                }
                                            }
                                        }
                                        "bulletList", "orderedList" -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                            block.items.forEachIndexed { i, item ->
                                                val prefix = if (block.kind == "orderedList") "${i + 1}. " else "• "
                                                Text("$prefix$item", color = colors.textSecondary, fontSize = 13.sp, lineHeight = 20.sp)
                                            }
                                        }
                                        "codeBlock" -> Box(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(10.dp))
                                                .background(Color.Black.copy(alpha = 0.35f))
                                                .padding(10.dp),
                                        ) {
                                            Text(block.text, color = Color(0xFFD6BDFF), fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                                        }
                                        else -> Text(block.text, color = colors.textSecondary, fontSize = 13.sp, lineHeight = 20.sp)
                                    }
                                }
                                // 1:1 复刻 iOS 卡片内全宽描边紫色交互技能按钮
                                if (msg.quickOptions.isNotEmpty()) {
                                    Spacer(Modifier.height(2.dp))
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        msg.quickOptions.forEach { opt ->
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .clip(RoundedCornerShape(12.dp))
                                                    .background(colors.accent.copy(alpha = 0.12f))
                                                    .border(0.8.dp, colors.accent.copy(alpha = 0.38f), RoundedCornerShape(12.dp))
                                                    .clickable { sendPrompt(opt) }
                                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                            ) {
                                                Text(opt, color = colors.accent, fontSize = 14.sp, fontWeight = FontWeight.Medium)
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

        // 底部悬浮输入胶囊（1:1 复刻 iOS `[+  输入消息或 / 命令...  🎤  ↑]`）
        CinematicGlassSurface(
            shape = CircleShape,
            blurRadiusDp = 22.dp,
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = margin, vertical = 10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(colors.accent.copy(alpha = 0.30f))
                        .clickable { input = "/skills" },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Add, contentDescription = "快捷命令", tint = Color.White, modifier = Modifier.size(18.dp))
                }
                Box(modifier = Modifier.weight(1f)) {
                    if (input.isEmpty()) Text("输入消息或 / 命令...", color = colors.textMuted, fontSize = 14.sp)
                    BasicTextField(
                        value = input,
                        onValueChange = { input = it },
                        textStyle = TextStyle(color = colors.textPrimary, fontSize = 15.sp),
                        cursorBrush = SolidColor(colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Box(
                    modifier = Modifier.size(34.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.85f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Mic, contentDescription = "语音输入", tint = Color(0xFF1A1625), modifier = Modifier.size(18.dp))
                }
                IconButton(
                    onClick = { sendPrompt(input) },
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(if (input.isNotBlank()) colors.accent else colors.chipFill),
                ) {
                    Icon(
                        Icons.Rounded.ArrowUpward,
                        contentDescription = "发送",
                        tint = if (input.isNotBlank()) Color.White else colors.textMuted,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}
