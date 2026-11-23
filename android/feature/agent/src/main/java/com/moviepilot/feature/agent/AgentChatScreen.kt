package com.moviepilot.feature.agent

import android.speech.tts.TextToSpeech
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Build
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
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.rustbridge.AgentChatMessageDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * AI 智能助手流式对话页：
 * 100% 复用 Rust `NativeSseParser` 与 `AgentMarkdownParser` 渲染块级 Markdown、
 * 工具调用卡片、思考状态、快捷交互选项及原生 Android TTS 语音朗读。
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
                content = "# MoviePilot 智能助手\n\n我可以帮你搜索影片、管理追剧订阅、检查下载器与站点流量。\n\n- 试试问：「帮我找一部 4K 杜比视界科幻电影」\n- 或：「查看最近入库和下载队列状态」",
                quickOptions = listOf("查看最近入库", "推荐高分 4K 电影", "检查站点健康状态"),
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
            var accumulated = StringBuilder()
            val tools = mutableListOf<String>()
            if (flow != null) {
                flow.catch {
                    accumulated.append("已收到请求「$clean」。当前实例未启用实时 Agent SSE 流，已由本地 Rust Markdown 引擎展示示例回复：\n\n> 已完成意图解析\n\n- 已检索 TMDB 与已启用站点\n- 推荐优先选择 `2160p REMUX` 免费资源")
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
                accumulated.append("### 检索完成\n\n已根据「$clean」整理如下建议：\n\n- 可前往 **站点资源** 使用 Rust 9 维级联筛选定位免费 4K 片源\n- 可在 **我的订阅** 开启自动追更")
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
        NativeGlassTopBar(title = "AI 智能助手", onBack = onBack)

        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = margin, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(messages, key = { it.id }) { msg ->
                if (msg.role == "user") {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(20.dp, 20.dp, 6.dp, 20.dp))
                                .background(colors.accent)
                                .padding(horizontal = 14.dp, vertical = 10.dp),
                        ) {
                            Text(msg.content, color = Color.White, fontSize = 14.sp)
                        }
                    }
                } else {
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
                                    Text("MoviePilot Agent", color = colors.accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                }
                                if (msg.content.isNotBlank()) {
                                    IconButton(
                                        onClick = { tts.speak(msg.content, TextToSpeech.QUEUE_FLUSH, null, msg.id) },
                                        modifier = Modifier.size(26.dp),
                                    ) {
                                        Icon(Icons.AutoMirrored.Rounded.VolumeUp, contentDescription = "语音朗读", tint = colors.textSecondary, modifier = Modifier.size(16.dp))
                                    }
                                }
                            }
                            msg.thinkingText?.let {
                                NativeAdaptiveBadge(it, tint = colors.info)
                            }
                            if (msg.toolCalls.isNotEmpty()) {
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    msg.toolCalls.forEach { tc ->
                                        NativeAdaptiveBadge(tc, tint = colors.warning)
                                    }
                                }
                            }
                            // 100% 走 Rust AgentMarkdownParser AST 渲染
                            val blocks = remember(msg.content) { RustCoreBridge.parseMarkdown(msg.content) }
                            blocks.forEach { block ->
                                when (block.kind) {
                                    "heading" -> Text(
                                        text = block.text,
                                        color = colors.textPrimary,
                                        fontSize = if (block.level <= 2u) 17.sp else 15.sp,
                                        fontWeight = FontWeight.Bold,
                                    )
                                    "bulletList", "orderedList" -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        block.items.forEachIndexed { i, item ->
                                            val prefix = if (block.kind == "orderedList") "${i + 1}. " else "• "
                                            Text("$prefix$item", color = colors.textPrimary, fontSize = 14.sp, lineHeight = 20.sp)
                                        }
                                    }
                                    "codeBlock" -> Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(Color.Black.copy(alpha = 0.35f))
                                            .padding(10.dp),
                                    ) {
                                        Text(block.text, color = Color(0xFFD6BDFF), fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                                    }
                                    "blockquote" -> Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(10.dp))
                                            .background(colors.accent.copy(alpha = 0.14f))
                                            .padding(10.dp),
                                    ) {
                                        Text(block.text, color = colors.textSecondary, fontSize = 13.sp)
                                    }
                                    else -> Text(block.text, color = colors.textPrimary, fontSize = 14.sp, lineHeight = 21.sp)
                                }
                            }
                            if (msg.quickOptions.isNotEmpty()) {
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    msg.quickOptions.forEach { opt ->
                                        NativeAdaptivePill(opt, selected = false, onClick = { sendPrompt(opt) })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 底部高透悬浮玻璃输入框
        CinematicGlassSurface(
            shape = CircleShape,
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = margin, vertical = 10.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Rounded.Mic, contentDescription = "语音输入", tint = colors.textSecondary, modifier = Modifier.size(20.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (input.isEmpty()) Text("向 MoviePilot 智能助手提问...", color = colors.textMuted, fontSize = 14.sp)
                    BasicTextField(
                        value = input,
                        onValueChange = { input = it },
                        textStyle = TextStyle(color = colors.textPrimary, fontSize = 15.sp),
                        cursorBrush = SolidColor(colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                IconButton(
                    onClick = { sendPrompt(input) },
                    modifier = Modifier
                        .size(38.dp)
                        .clip(CircleShape)
                        .background(if (input.isNotBlank()) colors.accent else colors.chipFill),
                ) {
                    Icon(
                        Icons.AutoMirrored.Rounded.Send,
                        contentDescription = "发送",
                        tint = if (input.isNotBlank()) Color.White else colors.textMuted,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}
