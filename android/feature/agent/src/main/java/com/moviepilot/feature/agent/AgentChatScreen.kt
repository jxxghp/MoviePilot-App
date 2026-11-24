package com.moviepilot.feature.agent

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.speech.tts.TextToSpeech
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.InsertDriveFile
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AttachFile
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Build
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.core.content.ContextCompat
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeCardListSkeleton
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.SkeletonCardStyle
import com.moviepilot.rustbridge.AgentAttachmentDto
import com.moviepilot.rustbridge.AgentChatMessageDto
import com.moviepilot.rustbridge.AgentChoiceButtonDto
import com.moviepilot.rustbridge.AgentChoiceCardDto
import com.moviepilot.rustbridge.AgentCommandDto
import com.moviepilot.rustbridge.AgentSessionSummaryDto
import com.moviepilot.rustbridge.AgentToolEntryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.io.File
import java.util.Locale
import java.util.UUID

/**
 * AI 智能助手全屏对话页（全量对齐 iOS Agent 接口能力）：
 * - 真实历史会话读写、切换、新建、删除与展示快照持久化；
 * - 实时 SSE 流式输出 + 结构化工具调用分组折叠卡片（运行中 / 完成 / 失败）；
 * - 完整 Markdown 渲染（标题、粗斜体、行内代码、可复制代码块、引用块、列表、表格、链接）；
 * - 图片选择 / 文件选择 / 麦克风 AAC 语音录制上传与图文预览；
 * - 交互选择卡回调与随时中断当前任务。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
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
    val listState = rememberLazyListState()
    val json = remember { Json { ignoreUnknownKeys = true; isLenient = true } }
    val prefs = remember(context) { context.getSharedPreferences("mp_agent_state_v3", Context.MODE_PRIVATE) }

    var activeSessionId by remember {
        mutableStateOf(
            prefs.getString("last_session_id", null)?.takeIf { it.isNotBlank() }
                ?: "android-${UUID.randomUUID().toString().take(12)}",
        )
    }
    var sessions by remember { mutableStateOf<List<AgentSessionSummaryDto>>(emptyList()) }
    var commands by remember { mutableStateOf<List<AgentCommandDto>>(emptyList()) }
    var isInitialLoading by remember { mutableStateOf(true) }
    var isLoadingSessions by remember { mutableStateOf(false) }

    var input by remember { mutableStateOf(initialPrompt) }
    var isStreaming by remember { mutableStateOf(false) }
    var streamJob by remember { mutableStateOf<Job?>(null) }
    var feedbackBanner by remember { mutableStateOf<Pair<Boolean, String>?>(null) } // isError to msg

    var showHistorySheet by remember { mutableStateOf(false) }
    var showAttachSheet by remember { mutableStateOf(false) }
    var previewImageUrl by remember { mutableStateOf<String?>(null) }

    val pendingUploads = remember { mutableStateListOf<AgentAttachmentDto>() }
    var isUploading by remember { mutableStateOf(false) }

    // 语音录音状态（MediaRecorder AAC .m4a）
    var isRecording by remember { mutableStateOf(false) }
    var recordingSeconds by remember { mutableIntStateOf(0) }
    var activeRecorder by remember { mutableStateOf<MediaRecorder?>(null) }
    var recordingFile by remember { mutableStateOf<File?>(null) }

    val messages = remember { mutableStateListOf<AgentChatMessageDto>() }

    fun welcomeMessage(): AgentChatMessageDto = AgentChatMessageDto(
        id = "welcome-${System.currentTimeMillis()}",
        role = "assistant",
        content = "## 智能助手\n\n我可以帮你搜索影片、管理追剧订阅、查看站点流量、上传图片或文件分析，并执行 `/skills` 命令。\n\n1. 发送 `/skills` 查看已安装技能与市场\n2. 询问「查看最近入库和下载队列状态」\n3. 点击左下角 `+` 上传图片/文件，或点击麦克风发送语音",
        quickOptions = listOf("/skills", "查看最近入库", "检查站点健康状态", "推荐高分 4K 电影"),
    )

    val tts = remember {
        var engine: TextToSpeech? = null
        engine = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                engine?.language = Locale.SIMPLIFIED_CHINESE
            }
        }
        engine
    }
    DisposableEffect(Unit) {
        onDispose {
            runCatching { activeRecorder?.stop(); activeRecorder?.release() }
            tts.stop()
            tts.shutdown()
        }
    }

    LaunchedEffect(isRecording) {
        if (isRecording) {
            recordingSeconds = 0
            while (isRecording) {
                delay(1000)
                recordingSeconds += 1
            }
        }
    }

    suspend fun refreshSessions() {
        isLoadingSessions = true
        sessions = repository.fetchAgentSessions()
        isLoadingSessions = false
    }

    suspend fun openSession(sessionId: String, silentOnEmpty: Boolean = false) {
        streamJob?.cancel()
        streamJob = null
        isStreaming = false
        val detail = repository.fetchAgentSessionDetail(sessionId)
        if (detail != null) {
            activeSessionId = sessionId
            prefs.edit().putString("last_session_id", sessionId).apply()
            messages.clear()
            if (detail.first.isEmpty()) {
                messages.add(welcomeMessage())
            } else {
                messages.addAll(detail.first)
            }
            isStreaming = detail.second
            feedbackBanner = null
        } else if (!silentOnEmpty) {
            feedbackBanner = true to "读取历史会话失败"
        }
    }

    fun startNewSession() {
        streamJob?.cancel()
        streamJob = null
        isStreaming = false
        activeSessionId = "android-${UUID.randomUUID().toString().take(12)}"
        prefs.edit().remove("last_session_id").apply()
        messages.clear()
        messages.add(welcomeMessage())
        pendingUploads.clear()
        feedbackBanner = null
    }

    suspend fun persistSnapshot() {
        val visible = messages.filter { !it.id.startsWith("welcome-") && !it.isProtected && (it.role == "user" || it.content.isNotBlank() || it.tools.isNotEmpty() || it.attachments.isNotEmpty()) }
        if (visible.isEmpty()) return
        val nowMs = System.currentTimeMillis()
        val arr = buildJsonArray {
            visible.forEachIndexed { index, msg ->
                add(
                    buildJsonObject {
                        put("id", msg.id)
                        put("role", msg.role)
                        put("content", msg.content)
                        put("createdAt", nowMs - (visible.size - index) * 1000L)
                        put("status", "done")
                        put(
                            "tools",
                            buildJsonArray {
                                msg.tools.forEach { t ->
                                    add(
                                        buildJsonObject {
                                            put("id", t.id)
                                            put("message", t.message)
                                            put("status", t.status)
                                            put("structured", t.structured)
                                            if (t.toolName.isNotBlank()) put("tool_name", t.toolName)
                                        },
                                    )
                                }
                            },
                        )
                        put(
                            "attachments",
                            buildJsonArray {
                                msg.attachments.forEach { a ->
                                    add(
                                        buildJsonObject {
                                            put("kind", a.kind)
                                            put("url", a.url)
                                            if (a.downloadUrl.isNotBlank()) put("download_url", a.downloadUrl)
                                            if (a.name.isNotBlank()) put("name", a.name)
                                            if (a.mimeType.isNotBlank()) put("mime_type", a.mimeType)
                                            if (a.size > 0L) put("size", a.size)
                                        },
                                    )
                                }
                            },
                        )
                    },
                )
            }
        }
        val title = visible.firstOrNull { it.role == "user" && it.content.isNotBlank() }?.content?.trim()?.take(40) ?: "新对话"
        repository.saveAgentSessionDisplay(activeSessionId, title, arr.toString())
    }

    LaunchedEffect(Unit) {
        coroutineScope {
            val cmdDef = async { repository.fetchAgentCommands() }
            val sessDef = async { refreshSessions() }
            commands = cmdDef.await()
            sessDef.await()
        }
        val savedId = prefs.getString("last_session_id", null)?.takeIf { it.isNotBlank() }
        val targetId = when {
            savedId != null && sessions.any { it.sessionId == savedId } -> savedId
            sessions.isNotEmpty() -> sessions.first().sessionId
            else -> null
        }
        if (targetId != null && initialPrompt.isBlank()) {
            openSession(targetId, silentOnEmpty = true)
        }
        if (messages.isEmpty()) {
            messages.add(welcomeMessage())
        }
        isInitialLoading = false
    }

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            runCatching { listState.animateScrollToItem(messages.lastIndex) }
        }
    }

    fun uploadUri(uri: Uri, fallbackMime: String) {
        scope.launch {
            isUploading = true
            feedbackBanner = null
            val (name, mime, bytes) = withContext(Dispatchers.IO) {
                val resolvedName = queryFileName(context, uri)
                val resolvedMime = context.contentResolver.getType(uri) ?: fallbackMime
                val data = runCatching {
                    context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                }.getOrNull()
                Triple(resolvedName, resolvedMime, data)
            }
            if (bytes != null && bytes.isNotEmpty()) {
                val uploaded = repository.uploadAgentAttachment(activeSessionId, name, mime, bytes)
                if (uploaded != null) {
                    pendingUploads.add(uploaded)
                } else {
                    feedbackBanner = true to "上传附件「$name」失败"
                }
            } else {
                feedbackBanner = true to "无法读取所选文件"
            }
            isUploading = false
        }
    }

    val imagePickerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) uploadUri(uri, "image/jpeg")
    }
    val filePickerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) uploadUri(uri, "application/octet-stream")
    }

    fun beginRecording() {
        runCatching {
            val outFile = File(context.cacheDir, "agent_voice_${UUID.randomUUID()}.m4a")
            val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioSamplingRate(24000)
            rec.setAudioChannels(1)
            rec.setOutputFile(outFile.absolutePath)
            rec.prepare()
            rec.start()
            activeRecorder = rec
            recordingFile = outFile
            isRecording = true
            feedbackBanner = null
        }.onFailure {
            feedbackBanner = true to "启动录音失败，请检查麦克风权限"
        }
    }

    fun finishRecording(sendImmediately: Boolean) {
        val file = recordingFile
        runCatching { activeRecorder?.stop(); activeRecorder?.release() }
        activeRecorder = null
        recordingFile = null
        isRecording = false
        if (!sendImmediately || file == null || !file.exists()) {
            file?.delete()
            return
        }
        scope.launch {
            isUploading = true
            val bytes = withContext(Dispatchers.IO) { runCatching { file.readBytes() }.getOrNull() }
            file.delete()
            if (bytes != null && bytes.isNotEmpty()) {
                val uploaded = repository.uploadAgentAttachment(activeSessionId, "voice_${System.currentTimeMillis()}.m4a", "audio/mp4", bytes)
                if (uploaded != null) {
                    pendingUploads.add(uploaded)
                    feedbackBanner = false to "语音已录制并上传，可点发送提交给智能助手"
                } else {
                    feedbackBanner = true to "语音上传失败，请稍后重试"
                }
            }
            isUploading = false
        }
    }

    val recordAudioPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) beginRecording() else feedbackBanner = true to "请授予麦克风权限后再使用语音输入"
    }

    fun sendPrompt(
        rawText: String,
        displayTextOverride: String? = null,
        originalMessageId: String? = null,
    ) {
        val clean = rawText.trim()
        val uploadsSnapshot = pendingUploads.toList()
        if (clean.isEmpty() && uploadsSnapshot.isEmpty()) return

        input = ""
        pendingUploads.clear()
        feedbackBanner = null

        val userDisplay = displayTextOverride ?: if (clean.isEmpty()) "（已发送附件）" else clean
        messages.add(
            AgentChatMessageDto(
                id = "u-${System.currentTimeMillis()}",
                role = "user",
                content = userDisplay,
                attachments = uploadsSnapshot,
            ),
        )

        val payloadObj = buildJsonObject {
            put("text", clean)
            put("display_text", userDisplay)
            put("session_id", activeSessionId)
            put("echo_user", true)
            val imgs = uploadsSnapshot.filter { it.kind == "image" }.map { it.ref }.filter { it.isNotBlank() }
            if (imgs.isNotEmpty()) put("images", buildJsonArray { imgs.forEach { add(JsonPrimitive(it)) } })
            val auds = uploadsSnapshot.filter { it.kind == "audio" }.map { it.ref }.filter { it.isNotBlank() }
            if (auds.isNotEmpty()) put("audio_refs", buildJsonArray { auds.forEach { add(JsonPrimitive(it)) } })
            val files = uploadsSnapshot.filter { it.kind != "image" && it.kind != "audio" }
            if (files.isNotEmpty()) {
                put(
                    "files",
                    buildJsonArray {
                        files.forEach { f ->
                            add(
                                buildJsonObject {
                                    put("ref", f.ref)
                                    if (f.name.isNotBlank()) put("name", f.name)
                                    if (f.mimeType.isNotBlank()) put("mime_type", f.mimeType)
                                    if (f.size > 0L) put("size", f.size)
                                    if (f.localPath.isNotBlank()) put("local_path", f.localPath)
                                    put("status", "ready")
                                },
                            )
                        }
                    },
                )
            }
            if (!originalMessageId.isNullOrBlank()) put("original_message_id", originalMessageId)
        }

        // 若任务正在运行中，作为追问补充发送
        if (isStreaming) {
            scope.launch {
                val flow = repository.streamAgentChatPayload(payloadObj.toString())
                flow?.catch {}?.collect { ev ->
                    if (ev.event.equals("steering", ignoreCase = true)) {
                        feedbackBanner = false to "已将补充指令传达给正在执行的智能助手"
                    }
                }
            }
            return
        }

        val assistantId = "a-${System.currentTimeMillis()}"
        messages.add(
            AgentChatMessageDto(
                id = assistantId,
                role = "assistant",
                content = "",
                thinkingText = "正在思考并连接智能助手...",
                isStreaming = true,
            ),
        )
        isStreaming = true

        streamJob?.cancel()
        streamJob = scope.launch {
            val flow = repository.streamAgentChatPayload(payloadObj.toString())
            val accumulated = StringBuilder()
            if (flow != null) {
                flow.catch {
                    feedbackBanner = true to "智能助手连接中断，请检查服务状态或模型配置"
                }.collect { ev ->
                    val idx = messages.indexOfFirst { it.id == assistantId }
                    if (idx < 0) return@collect
                    val dataObj = runCatching { json.parseToJsonElement(ev.data).jsonObject }.getOrNull()
                    val eventType = (dataObj?.get("type")?.jsonPrimitive?.contentOrNull ?: ev.event).lowercase()

                    when (eventType) {
                        "start" -> {
                            dataObj?.get("session_id")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }?.let { sid ->
                                activeSessionId = sid
                                prefs.edit().putString("last_session_id", sid).apply()
                            }
                        }
                        "thinking" -> {
                            val hint = dataObj?.get("message")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("content")?.jsonPrimitive?.contentOrNull
                                ?: ev.data.takeIf { it.isNotBlank() && !it.startsWith("{") }
                                ?: "正在深度思考..."
                            messages[idx] = messages[idx].copy(thinkingText = hint)
                        }
                        "tool", "tool_call" -> {
                            val rawId = dataObj?.get("tool_id")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("tool_call_id")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("id")?.jsonPrimitive?.contentOrNull
                            val tName = dataObj?.get("tool_name")?.jsonPrimitive?.contentOrNull.orEmpty()
                            val rawStatus = (dataObj?.get("status")?.jsonPrimitive?.contentOrNull ?: "running").lowercase()
                            val normStatus = when (rawStatus) {
                                "error", "failed" -> "error"
                                "done", "completed", "success" -> "done"
                                else -> "running"
                            }
                            val tMsg = dataObj?.get("message")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
                                ?: tName.ifBlank { ev.data.take(60).ifBlank { "调用工具" } }
                            val currentTools = messages[idx].tools.toMutableList()
                            if (!rawId.isNullOrBlank()) {
                                val existingIdx = currentTools.indexOfFirst { it.id == rawId }
                                if (existingIdx >= 0) {
                                    currentTools[existingIdx] = currentTools[existingIdx].copy(
                                        status = normStatus,
                                        message = currentTools[existingIdx].message.ifBlank { tMsg },
                                    )
                                } else {
                                    currentTools.add(AgentToolEntryDto(id = rawId, toolName = tName, message = tMsg, structured = true, status = normStatus))
                                }
                            } else if (normStatus == "running") {
                                for (i in currentTools.indices) {
                                    if (currentTools[i].status == "running") currentTools[i] = currentTools[i].copy(status = "done")
                                }
                                currentTools.add(AgentToolEntryDto(id = "tool-${UUID.randomUUID()}", toolName = tName, message = tMsg, structured = false, status = "running"))
                            }
                            messages[idx] = messages[idx].copy(tools = currentTools)
                        }
                        "delta" -> {
                            val chunk = dataObj?.get("content")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("delta")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("text")?.jsonPrimitive?.contentOrNull
                                ?: ""
                            if (chunk.isNotEmpty()) {
                                accumulated.append(chunk)
                                val updatedTools = messages[idx].tools.map { if (it.status == "running" && !it.structured) it.copy(status = "done") else it }
                                messages[idx] = messages[idx].copy(
                                    content = accumulated.toString(),
                                    thinkingText = null,
                                    tools = updatedTools,
                                )
                            }
                        }
                        "message_update" -> {
                            val target = dataObj?.get("target_message")?.jsonObject ?: dataObj
                            val full = target?.get("content")?.jsonPrimitive?.contentOrNull
                                ?: target?.get("message")?.jsonPrimitive?.contentOrNull
                            if (!full.isNullOrBlank()) {
                                accumulated.clear()
                                accumulated.append(full)
                                messages[idx] = messages[idx].copy(content = full, thinkingText = null)
                            }
                        }
                        "attachment" -> {
                            val attObj = dataObj?.get("attachment")?.jsonObject ?: dataObj
                            val rawUrl = attObj?.get("url")?.jsonPrimitive?.contentOrNull.orEmpty()
                            if (rawUrl.isNotBlank()) {
                                val resolvedUrl = repository.resolveImageUrl(rawUrl) ?: rawUrl
                                val att = AgentAttachmentDto(
                                    kind = attObj?.get("kind")?.jsonPrimitive?.contentOrNull ?: "file",
                                    url = resolvedUrl,
                                    downloadUrl = attObj?.get("download_url")?.jsonPrimitive?.contentOrNull?.let { repository.resolveImageUrl(it) ?: it } ?: resolvedUrl,
                                    name = attObj?.get("name")?.jsonPrimitive?.contentOrNull ?: "附件",
                                    mimeType = attObj?.get("mime_type")?.jsonPrimitive?.contentOrNull.orEmpty(),
                                    size = attObj?.get("size")?.jsonPrimitive?.longOrNull ?: 0L,
                                )
                                if (messages[idx].attachments.none { it.url == att.url }) {
                                    messages[idx] = messages[idx].copy(attachments = messages[idx].attachments + att)
                                }
                            }
                        }
                        "choice" -> {
                            val cObj = dataObj?.get("choice")?.jsonObject ?: dataObj
                            val btns = cObj?.get("buttons")?.let { el ->
                                runCatching {
                                    el.jsonArray.flatMap { row ->
                                        when (row) {
                                            is JsonArray -> row.mapNotNull { b ->
                                                val bo = b.jsonObject
                                                val lbl = bo["label"]?.jsonPrimitive?.contentOrNull ?: bo["text"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                                                AgentChoiceButtonDto(lbl, bo["callback_data"]?.jsonPrimitive?.contentOrNull ?: "")
                                            }
                                            is JsonObject -> listOfNotNull(
                                                row["label"]?.jsonPrimitive?.contentOrNull?.let {
                                                    AgentChoiceButtonDto(it, row["callback_data"]?.jsonPrimitive?.contentOrNull ?: "")
                                                },
                                            )
                                            else -> emptyList()
                                        }
                                    }
                                }.getOrNull()
                            }.orEmpty()
                            if (btns.isNotEmpty()) {
                                val card = AgentChoiceCardDto(
                                    id = cObj?.get("id")?.jsonPrimitive?.contentOrNull ?: UUID.randomUUID().toString(),
                                    title = cObj?.get("title")?.jsonPrimitive?.contentOrNull ?: cObj?.get("prompt")?.jsonPrimitive?.contentOrNull.orEmpty(),
                                    buttons = btns,
                                )
                                messages[idx] = messages[idx].copy(choices = messages[idx].choices.filterNot { it.id == card.id } + card)
                            }
                        }
                        "interaction-protected" -> {
                            val secret = dataObj?.get("content")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("message")?.jsonPrimitive?.contentOrNull
                                ?: ""
                            if (secret.isNotBlank()) {
                                if (accumulated.isNotEmpty()) accumulated.append("\n\n")
                                accumulated.append(secret)
                                messages[idx] = messages[idx].copy(content = accumulated.toString(), isProtected = true, thinkingText = null)
                            }
                        }
                        "error" -> {
                            val errMsg = dataObj?.get("message")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("error")?.jsonPrimitive?.contentOrNull
                                ?: "智能助手执行出错"
                            feedbackBanner = true to errMsg
                            messages[idx] = messages[idx].copy(
                                tools = messages[idx].tools.map { if (it.status == "running") it.copy(status = "error") else it },
                            )
                        }
                        "done" -> {
                            val finalMsg = dataObj?.get("message")?.jsonPrimitive?.contentOrNull
                                ?: dataObj?.get("content")?.jsonPrimitive?.contentOrNull
                            if (!finalMsg.isNullOrBlank() && accumulated.isEmpty()) {
                                accumulated.append(finalMsg)
                            }
                            messages[idx] = messages[idx].copy(
                                content = accumulated.toString(),
                                thinkingText = null,
                                tools = messages[idx].tools.map { if (it.status == "running") it.copy(status = "done") else it },
                                isStreaming = false,
                            )
                        }
                        else -> if (!ev.isDone) {
                            val fallbackText = dataObj?.get("content")?.jsonPrimitive?.contentOrNull
                                ?: ev.data.takeIf { it.isNotBlank() && !it.startsWith("{") }
                            if (!fallbackText.isNullOrBlank()) {
                                accumulated.append(fallbackText)
                                messages[idx] = messages[idx].copy(content = accumulated.toString(), thinkingText = null)
                            }
                        }
                    }
                }
            }
            val finalIdx = messages.indexOfFirst { it.id == assistantId }
            if (finalIdx >= 0) {
                val cur = messages[finalIdx]
                val finalContent = if (accumulated.isBlank() && cur.attachments.isEmpty() && cur.choices.isEmpty()) {
                    "已完成处理，若未返回内容请检查服务端 AI 模型配置。"
                } else {
                    accumulated.toString().ifBlank { cur.content }
                }
                messages[finalIdx] = cur.copy(
                    content = finalContent,
                    thinkingText = null,
                    tools = cur.tools.map { if (it.status == "running") it.copy(status = "done") else it },
                    isStreaming = false,
                )
            }
            isStreaming = false
            persistSnapshot()
            refreshSessions()
        }
    }

    val currentSessionTitle = remember(sessions, activeSessionId) {
        sessions.firstOrNull { it.sessionId == activeSessionId }?.title?.takeIf { it.isNotBlank() }
    }

    ExpressiveTintedScaffold(
        title = "智能助手",
        subtitle = currentSessionTitle,
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.EditNote,
                contentDescription = "新对话",
                onClick = { startNewSession() },
            )
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.History,
                contentDescription = "历史会话",
                onClick = {
                    isLoadingSessions = true
                    showHistorySheet = true
                    scope.launch { refreshSessions() }
                },
            )
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding(),
        ) {
            feedbackBanner?.let { (isErr, msg) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = margin, vertical = 6.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (isErr) colors.danger.copy(alpha = 0.16f) else colors.success.copy(alpha = 0.16f))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(msg, color = if (isErr) colors.danger else colors.success, fontSize = 12.5.sp, modifier = Modifier.weight(1f))
                    IconButton(onClick = { feedbackBanner = null }, modifier = Modifier.size(22.dp)) {
                        Icon(Icons.Rounded.Close, contentDescription = "关闭提示", tint = colors.textMuted, modifier = Modifier.size(15.dp))
                    }
                }
            }

            if (isInitialLoading && messages.isEmpty()) {
                NativeCardListSkeleton(
                    style = SkeletonCardStyle.ChatBubbles,
                    count = 4,
                    contentPadding = PaddingValues(horizontal = margin, vertical = 14.dp),
                    modifier = Modifier.weight(1f),
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = margin, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                items(messages, key = { it.id }) { msg ->
                    if (msg.role == "user") {
                        Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (msg.attachments.isNotEmpty()) {
                                AgentAttachmentsRow(msg.attachments, onImageClick = { previewImageUrl = it })
                            }
                            if (msg.content.isNotBlank()) {
                                val userMaxWidth = if (AdaptiveDeviceLayout.isWideCanvas()) 520.dp else 310.dp
                                Box(
                                    modifier = Modifier
                                        .widthIn(max = userMaxWidth)
                                        .clip(RoundedCornerShape(20.dp))
                                        .background(colors.accent)
                                        .padding(horizontal = 16.dp, vertical = 10.dp),
                                ) {
                                    Text(msg.content, color = colors.primaryButtonFg, fontSize = 14.5.sp, fontWeight = FontWeight.Medium)
                                }
                            }
                        }
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(colors.accent.copy(alpha = 0.20f))
                                    .border(0.7.dp, colors.accent.copy(alpha = 0.42f), CircleShape),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = colors.accent, modifier = Modifier.size(17.dp))
                            }

                            CinematicPanel(
                                padding = 14.dp,
                                showsShadow = false,
                                modifier = Modifier.weight(1f),
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    // 1. 思考态提示
                                    msg.thinkingText?.let { think ->
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
                                            Text(think, color = colors.textSecondary, fontSize = 12.5.sp)
                                        }
                                    }

                                    // 2. 结构化工具调用分组折叠提示卡
                                    if (msg.tools.isNotEmpty()) {
                                        AgentToolGroupCard(tools = msg.tools)
                                    }

                                    // 3. 完整 Markdown 渲染 + 语音朗读入口
                                    if (msg.content.isNotBlank()) {
                                        ExpressiveMarkdownContent(markdown = msg.content)
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                                            IconButton(
                                                onClick = { tts.speak(msg.content, TextToSpeech.QUEUE_FLUSH, null, msg.id) },
                                                modifier = Modifier.size(28.dp),
                                            ) {
                                                Icon(Icons.AutoMirrored.Rounded.VolumeUp, contentDescription = "朗读回复", tint = colors.textMuted, modifier = Modifier.size(16.dp))
                                            }
                                        }
                                    }

                                    // 4. 回复附件（图片/文件/语音）
                                    if (msg.attachments.isNotEmpty()) {
                                        AgentAttachmentsRow(msg.attachments, onImageClick = { previewImageUrl = it })
                                    }

                                    // 5. 服务端交互选择卡（支持 callback 回传）
                                    msg.choices.forEach { card ->
                                        Column(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(14.dp))
                                                .background(colors.chipFill)
                                                .padding(12.dp),
                                            verticalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            if (card.title.isNotBlank()) {
                                                Text(card.title, color = colors.textPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                                            }
                                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                                card.buttons.forEach { btn ->
                                                    val isSelected = card.selectedLabel == btn.label
                                                    NativeAdaptivePill(
                                                        title = btn.label,
                                                        selected = isSelected,
                                                        onClick = {
                                                            scope.launch {
                                                                val res = repository.triggerAgentCallback(activeSessionId, btn.callbackData, msg.id)
                                                                val mIdx = messages.indexOfFirst { it.id == msg.id }
                                                                if (mIdx >= 0) {
                                                                    val updatedChoices = messages[mIdx].choices.map { c ->
                                                                        if (c.id == card.id) c.copy(selectedLabel = btn.label) else c
                                                                    }
                                                                    messages[mIdx] = messages[mIdx].copy(choices = updatedChoices)
                                                                }
                                                                if (res != null && res.first.isNotBlank()) {
                                                                    sendPrompt(res.first, displayTextOverride = res.second.ifBlank { "选择：${btn.label}" }, originalMessageId = msg.id)
                                                                }
                                                            }
                                                        },
                                                    )
                                                }
                                            }
                                        }
                                    }

                                    // 6. 快捷引导动作按钮
                                    if (msg.quickOptions.isNotEmpty()) {
                                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            msg.quickOptions.forEach { opt ->
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxWidth()
                                                        .clip(RoundedCornerShape(12.dp))
                                                        .background(colors.accent.copy(alpha = 0.12f))
                                                        .border(0.8.dp, colors.accent.copy(alpha = 0.36f), RoundedCornerShape(12.dp))
                                                        .clickable { sendPrompt(opt) }
                                                        .padding(horizontal = 14.dp, vertical = 10.dp),
                                                ) {
                                                    Text(opt, color = colors.accent, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
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

            // 待发送附件预览条（图片/文件/语音芯片 + 删除按钮）
            if (pendingUploads.isNotEmpty() || isUploading) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = margin, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (isUploading) {
                        item {
                            Row(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(colors.surfaceContainerHigh)
                                    .padding(horizontal = 12.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(14.dp))
                                Text("上传中...", color = colors.textSecondary, fontSize = 12.sp)
                            }
                        }
                    }
                    items(pendingUploads, key = { it.ref.ifBlank { it.name } }) { att ->
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(14.dp))
                                .background(colors.surfaceContainerHigh)
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            if (att.kind == "image" && att.url.isNotBlank()) {
                                AsyncImage(
                                    model = att.url,
                                    contentDescription = att.name,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.size(28.dp).clip(RoundedCornerShape(6.dp)),
                                )
                            } else {
                                Icon(
                                    if (att.kind == "audio") Icons.Rounded.GraphicEq else Icons.AutoMirrored.Rounded.InsertDriveFile,
                                    contentDescription = null,
                                    tint = colors.accent,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                            Text(att.name.ifBlank { att.kind }, color = colors.textPrimary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 120.dp))
                            Icon(
                                Icons.Rounded.Close,
                                contentDescription = "移除附件",
                                tint = colors.textMuted,
                                modifier = Modifier.size(16.dp).clickable { pendingUploads.remove(att) },
                            )
                        }
                    }
                }
            }

            // 语音录制状态条
            AnimatedVisibility(visible = isRecording) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = margin, vertical = 6.dp)
                        .clip(CircleShape)
                        .background(colors.danger.copy(alpha = 0.18f))
                        .border(0.8.dp, colors.danger.copy(alpha = 0.5f), CircleShape)
                        .padding(horizontal = 14.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Rounded.GraphicEq, contentDescription = null, tint = colors.danger, modifier = Modifier.size(18.dp))
                        Text(
                            "正在录音 %02d:%02d".format(recordingSeconds / 60, recordingSeconds % 60),
                            color = colors.textPrimary,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NativeAdaptivePill("取消", selected = false, onClick = { finishRecording(sendImmediately = false) })
                        NativeAdaptivePill("完成上传", selected = true, onClick = { finishRecording(sendImmediately = true) })
                    }
                }
            }

            // 底部悬浮输入胶囊（+ 附件与命令 / 文本输入 / 麦克风录音 / 发送或停止）
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceContainer,
                tonalElevation = 0.dp,
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = margin, vertical = 10.dp)
                    .border(0.7.dp, colors.divider, CircleShape),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(colors.accent.copy(alpha = 0.22f))
                            .clickable { showAttachSheet = true },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Rounded.Add, contentDescription = "附件与命令", tint = colors.accent, modifier = Modifier.size(20.dp))
                    }
                    Box(modifier = Modifier.weight(1f)) {
                        if (input.isEmpty()) Text("输入消息、/ 命令或添加附件...", color = colors.textMuted, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        BasicTextField(
                            value = input,
                            onValueChange = { input = it },
                            textStyle = TextStyle(color = colors.textPrimary, fontSize = 15.sp),
                            cursorBrush = SolidColor(colors.accent),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(if (isRecording) colors.danger else colors.surfaceContainerHigh)
                            .clickable {
                                if (isRecording) {
                                    finishRecording(sendImmediately = true)
                                } else {
                                    val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                                    if (granted) beginRecording() else recordAudioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            if (isRecording) Icons.Rounded.Stop else Icons.Rounded.Mic,
                            contentDescription = if (isRecording) "停止录音" else "语音录音",
                            tint = if (isRecording) Color.White else colors.textPrimary,
                            modifier = Modifier.size(19.dp),
                        )
                    }
                    val canSend = input.isNotBlank() || pendingUploads.isNotEmpty()
                    IconButton(
                        onClick = {
                            if (isStreaming && !canSend) {
                                streamJob?.cancel()
                                streamJob = null
                                isStreaming = false
                                scope.launch {
                                    repository.stopAgentSession(activeSessionId)
                                    feedbackBanner = false to "已停止当前任务"
                                }
                            } else if (canSend) {
                                sendPrompt(input)
                            }
                        },
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(
                                when {
                                    isStreaming && !canSend -> colors.danger
                                    canSend -> colors.accent
                                    else -> colors.surfaceContainerHigh
                                },
                            ),
                    ) {
                        Icon(
                            imageVector = if (isStreaming && !canSend) Icons.Rounded.Stop else Icons.Rounded.ArrowUpward,
                            contentDescription = if (isStreaming && !canSend) "停止生成" else "发送",
                            tint = when {
                                isStreaming && !canSend -> Color.White
                                canSend -> colors.primaryButtonFg
                                else -> colors.textMuted
                            },
                            modifier = Modifier.size(19.dp),
                        )
                    }
                }
            }
        }
    }

            // 历史会话管理弹层（真实读取 / 切换 / 新建 / 删除）
    if (showHistorySheet) {
        NativeGlassSheet(onDismissRequest = { showHistorySheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = if (isLoadingSessions && sessions.isEmpty()) "历史会话" else "历史会话 (${sessions.size})",
                        color = colors.textPrimary,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                    )
                    NativeAdaptivePill(
                        title = "新对话",
                        selected = true,
                        icon = Icons.Rounded.EditNote,
                        onClick = {
                            showHistorySheet = false
                            startNewSession()
                        },
                    )
                }
                if (isLoadingSessions && sessions.isEmpty()) {
                    NativeCardListSkeleton(
                        style = SkeletonCardStyle.IconRow,
                        count = 4,
                        contentPadding = PaddingValues(0.dp),
                        scrollable = false,
                    )
                } else if (sessions.isEmpty()) {
                    CinematicPanel(padding = 20.dp, showsShadow = false) {
                        Text("暂无历史对话记录，发送首条消息后会自动保存会话。", color = colors.textSecondary, fontSize = 13.5.sp)
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(sessions, key = { it.sessionId }) { sess ->
                            val isActive = sess.sessionId == activeSessionId
                            CinematicPanel(
                                padding = 14.dp,
                                showsShadow = false,
                                modifier = Modifier
                                    .then(if (isActive) Modifier.border(1.2.dp, colors.accent, RoundedCornerShape(colors.cardRadiusDp.dp)) else Modifier)
                                    .clickable {
                                        showHistorySheet = false
                                        scope.launch { openSession(sess.sessionId) }
                                    },
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(sess.title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                                            if (isActive) NativeAdaptiveBadge("当前", tint = colors.accent)
                                            if (sess.isProcessing) NativeAdaptiveBadge("运行中", tint = colors.warning)
                                        }
                                        val meta = listOfNotNull(
                                            if (sess.messageCount > 0) "${sess.messageCount} 条消息" else null,
                                            sess.updatedAt.takeIf { it.isNotBlank() },
                                        ).joinToString(" · ")
                                        if (meta.isNotBlank()) {
                                            Text(meta, color = colors.textMuted, fontSize = 11.5.sp, maxLines = 1)
                                        }
                                    }
                                    IconButton(
                                        onClick = {
                                            scope.launch {
                                                val ok = repository.deleteAgentSession(sess.sessionId)
                                                if (ok) {
                                                    sessions = sessions.filterNot { it.sessionId == sess.sessionId }
                                                    if (activeSessionId == sess.sessionId) startNewSession()
                                                }
                                            }
                                        },
                                        modifier = Modifier.size(34.dp),
                                    ) {
                                        Icon(Icons.Rounded.Delete, contentDescription = "删除会话", tint = colors.danger, modifier = Modifier.size(18.dp))
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // 附件与斜杠命令面板（图片 / 文件 / 语音 / 命令列表）
    if (showAttachSheet) {
        NativeGlassSheet(onDismissRequest = { showAttachSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text("添加附件或快捷命令", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    AgentActionCard(
                        icon = Icons.Rounded.Image,
                        label = "发送图片",
                        tint = colors.accent,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            showAttachSheet = false
                            imagePickerLauncher.launch("image/*")
                        },
                    )
                    AgentActionCard(
                        icon = Icons.Rounded.AttachFile,
                        label = "发送文件",
                        tint = colors.info,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            showAttachSheet = false
                            filePickerLauncher.launch(arrayOf("*/*"))
                        },
                    )
                    AgentActionCard(
                        icon = Icons.Rounded.Mic,
                        label = "语音输入",
                        tint = colors.pink,
                        modifier = Modifier.weight(1f),
                        onClick = {
                            showAttachSheet = false
                            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                            if (granted) beginRecording() else recordAudioPermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        },
                    )
                }

                val cmdList = commands.ifEmpty {
                    listOf(
                        AgentCommandDto("/skills", "查看已安装技能与技能市场"),
                        AgentCommandDto("/clear", "清空当前会话上下文"),
                        AgentCommandDto("/help", "查看智能助手使用帮助"),
                    )
                }
                Text("快捷命令", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    cmdList.take(8).forEach { cmd ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(colors.chipFill)
                                .clickable {
                                    showAttachSheet = false
                                    sendPrompt(cmd.command)
                                }
                                .padding(horizontal = 14.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(Icons.Rounded.Terminal, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(cmd.command, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                                if (cmd.description.isNotBlank()) {
                                    Text(cmd.description, color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // 图片放大预览弹窗（高度自适应当前视口 82%，防止短屏横屏溢出裁切）
    previewImageUrl?.let { imgUrl ->
        val maxPreviewHeight = (LocalConfiguration.current.screenHeightDp * 0.82f).coerceIn(180f, 520f).dp
        Dialog(onDismissRequest = { previewImageUrl = null }) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color.Black)
                    .clickable { previewImageUrl = null }
                    .padding(10.dp),
                contentAlignment = Alignment.Center,
            ) {
                AsyncImage(
                    model = imgUrl,
                    contentDescription = "图片预览",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp, max = maxPreviewHeight),
                )
            }
        }
    }
}

/** 结构化工具调用分组折叠提示卡（运行中自动展开最新进度，完成后可一键折叠/展开详情）。 */
@Composable
private fun AgentToolGroupCard(tools: List<AgentToolEntryDto>) {
    val colors = LocalMoviePilotColors.current
    val runningCount = tools.count { it.status == "running" }
    val errorCount = tools.count { it.status == "error" }
    var expanded by remember(runningCount > 0) { mutableStateOf(runningCount > 0) }
    val headerText = when {
        runningCount > 0 -> "正在调用工具 (${tools.size}) · ${tools.lastOrNull { it.status == "running" }?.message.orEmpty()}"
        errorCount > 0 -> "工具调用完成（${tools.size} 项，${errorCount} 项异常）"
        else -> "已完成 ${tools.size} 项工具调用"
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.chipFill)
            .border(0.6.dp, colors.chipBorder, RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (runningCount > 0) {
                CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(15.dp))
            } else {
                Icon(
                    if (errorCount > 0) Icons.Rounded.ErrorOutline else Icons.Rounded.Build,
                    contentDescription = null,
                    tint = if (errorCount > 0) colors.warning else colors.success,
                    modifier = Modifier.size(16.dp),
                )
            }
            Text(
                headerText,
                color = colors.textPrimary,
                fontSize = 12.5.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Icon(
                if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                contentDescription = null,
                tint = colors.textMuted,
                modifier = Modifier.size(18.dp),
            )
        }
        AnimatedVisibility(visible = expanded) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 4.dp)) {
                tools.forEach { t ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        when (t.status) {
                            "running" -> CircularProgressIndicator(color = colors.accent, strokeWidth = 1.8.dp, modifier = Modifier.size(13.dp))
                            "error" -> Icon(Icons.Rounded.ErrorOutline, contentDescription = null, tint = colors.danger, modifier = Modifier.size(14.dp))
                            else -> Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = colors.success, modifier = Modifier.size(14.dp))
                        }
                        if (t.toolName.isNotBlank()) {
                            NativeAdaptiveBadge(t.toolName, tint = colors.accent)
                        }
                        Text(t.message, color = colors.textSecondary, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** 附件缩略图与文件芯片行。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AgentAttachmentsRow(
    attachments: List<AgentAttachmentDto>,
    onImageClick: (String) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val uriHandler = LocalUriHandler.current
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        attachments.forEach { att ->
            if (att.kind == "image" && att.url.isNotBlank()) {
                AsyncImage(
                    model = att.url,
                    contentDescription = att.name,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(104.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .border(0.7.dp, colors.divider, RoundedCornerShape(14.dp))
                        .clickable { onImageClick(att.url) },
                )
            } else {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(colors.surfaceContainerHigh)
                        .clickable {
                            val target = att.downloadUrl.ifBlank { att.url }
                            if (target.startsWith("http")) runCatching { uriHandler.openUri(target) }
                        }
                        .padding(horizontal = 10.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        if (att.kind == "audio") Icons.Rounded.GraphicEq else Icons.AutoMirrored.Rounded.InsertDriveFile,
                        contentDescription = null,
                        tint = colors.accent,
                        modifier = Modifier.size(16.dp),
                    )
                    Text(att.name.ifBlank { if (att.kind == "audio") "语音消息" else "文件附件" }, color = colors.textPrimary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun AgentActionCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(18.dp),
        color = colors.surfaceContainerHigh,
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier.padding(vertical = 14.dp, horizontal = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(24.dp))
            Text(label, color = colors.textPrimary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

/**
 * 完整 Markdown 渲染引擎：
 * 支持标题（H1~H3）、围栏代码块（带语言标签与一键复制）、引用块、表格、有序/无序列表、分割线，
 * 以及行内粗体、斜体、删除线、行内代码与链接高亮。
 */
@Composable
private fun ExpressiveMarkdownContent(markdown: String) {
    val colors = LocalMoviePilotColors.current
    val clipboard = LocalClipboardManager.current
    val lines = remember(markdown) { markdown.replace("\r\n", "\n").split("\n") }

    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        var i = 0
        while (i < lines.size) {
            val raw = lines[i]
            val trimmed = raw.trim()
            when {
                trimmed.isEmpty() -> i++

                trimmed.startsWith("```") -> {
                    val lang = trimmed.removePrefix("```").trim()
                    val codeLines = mutableListOf<String>()
                    i++
                    while (i < lines.size && !lines[i].trim().startsWith("```")) {
                        codeLines.add(lines[i])
                        i++
                    }
                    if (i < lines.size) i++
                    val codeBody = codeLines.joinToString("\n")
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (colors.isDark) Color(0xFF0A0D14) else colors.surfaceContainerHigh)
                            .border(0.6.dp, colors.divider, RoundedCornerShape(12.dp)),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 5.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(lang.ifBlank { "code" }, color = colors.textMuted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                            IconButton(
                                onClick = { clipboard.setText(AnnotatedString(codeBody)) },
                                modifier = Modifier.size(24.dp),
                            ) {
                                Icon(Icons.Rounded.ContentCopy, contentDescription = "复制代码", tint = colors.textSecondary, modifier = Modifier.size(14.dp))
                            }
                        }
                        HorizontalDivider(color = colors.divider)
                        Text(
                            text = codeBody,
                            color = colors.accent,
                            fontSize = 12.sp,
                            fontFamily = FontFamily.Monospace,
                            lineHeight = 18.sp,
                            modifier = Modifier.horizontalScroll(rememberScrollState()).padding(10.dp),
                        )
                    }
                }

                trimmed.startsWith("|") && i + 1 < lines.size && lines[i + 1].trim().contains("---") -> {
                    val tableRows = mutableListOf<List<String>>()
                    while (i < lines.size && lines[i].trim().startsWith("|")) {
                        val cells = lines[i].trim().trim('|').split("|").map { it.trim() }
                        if (!cells.all { c -> c.all { it == '-' || it == ':' || it == ' ' } }) {
                            tableRows.add(cells)
                        }
                        i++
                    }
                    if (tableRows.isNotEmpty()) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(colors.chipFill)
                                .horizontalScroll(rememberScrollState())
                                .padding(8.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            tableRows.forEachIndexed { rIdx, cells ->
                                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                                    cells.forEach { cell ->
                                        Text(
                                            text = buildInlineMarkdown(cell, colors.accent, colors.surfaceContainerHigh),
                                            color = if (rIdx == 0) colors.textPrimary else colors.textSecondary,
                                            fontSize = 12.sp,
                                            fontWeight = if (rIdx == 0) FontWeight.Bold else FontWeight.Normal,
                                            modifier = Modifier.widthIn(min = 64.dp, max = 160.dp),
                                        )
                                    }
                                }
                                if (rIdx == 0) HorizontalDivider(color = colors.divider)
                            }
                        }
                    }
                }

                trimmed.startsWith("### ") -> {
                    Text(buildInlineMarkdown(trimmed.removePrefix("### "), colors.accent, colors.chipFill), color = colors.textPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.Bold)
                    i++
                }
                trimmed.startsWith("## ") -> {
                    Text(buildInlineMarkdown(trimmed.removePrefix("## "), colors.accent, colors.chipFill), color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    i++
                }
                trimmed.startsWith("# ") -> {
                    Text(buildInlineMarkdown(trimmed.removePrefix("# "), colors.accent, colors.chipFill), color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.ExtraBold)
                    i++
                }

                trimmed == "---" || trimmed == "***" -> {
                    HorizontalDivider(color = colors.divider)
                    i++
                }

                trimmed.startsWith("> ") -> {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(colors.chipFill)
                            .padding(horizontal = 10.dp, vertical = 7.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(Modifier.width(3.dp).height(18.dp).clip(CircleShape).background(colors.accent))
                        Text(
                            buildInlineMarkdown(trimmed.removePrefix("> "), colors.accent, colors.surfaceContainerHigh),
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                            lineHeight = 19.sp,
                        )
                    }
                    i++
                }

                trimmed.startsWith("- ") || trimmed.startsWith("* ") -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("•", color = colors.accent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                        Text(
                            buildInlineMarkdown(trimmed.drop(2), colors.accent, colors.chipFill),
                            color = colors.textSecondary,
                            fontSize = 13.5.sp,
                            lineHeight = 20.sp,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    i++
                }

                Regex("^\\d+\\.\\s+.*").matches(trimmed) -> {
                    val dotIdx = trimmed.indexOf('.')
                    val num = trimmed.substring(0, dotIdx + 1)
                    val body = trimmed.substring(dotIdx + 1).trim()
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(num, color = colors.accent, fontSize = 13.5.sp, fontWeight = FontWeight.Bold)
                        Text(
                            buildInlineMarkdown(body, colors.accent, colors.chipFill),
                            color = colors.textSecondary,
                            fontSize = 13.5.sp,
                            lineHeight = 20.sp,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    i++
                }

                else -> {
                    Text(
                        text = buildInlineMarkdown(raw, colors.accent, colors.chipFill),
                        color = colors.textSecondary,
                        fontSize = 13.5.sp,
                        lineHeight = 20.sp,
                    )
                    i++
                }
            }
        }
    }
}

private fun buildInlineMarkdown(text: String, accentColor: Color, codeBg: Color): AnnotatedString = buildAnnotatedString {
    val pattern = Regex("(\\*\\*[^*]+\\*\\*|~~[^~]+~~|`[^`]+`|\\[[^\\]]+\\]\\([^)]+\\)|\\*[^*]+\\*)")
    var last = 0
    for (match in pattern.findAll(text)) {
        if (match.range.first > last) append(text.substring(last, match.range.first))
        val token = match.value
        when {
            token.startsWith("**") && token.endsWith("**") -> {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(token.removeSurrounding("**")) }
            }
            token.startsWith("~~") && token.endsWith("~~") -> {
                withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(token.removeSurrounding("~~")) }
            }
            token.startsWith("`") && token.endsWith("`") -> {
                withStyle(SpanStyle(fontFamily = FontFamily.Monospace, color = accentColor, background = codeBg)) {
                    append(" ${token.removeSurrounding("`")} ")
                }
            }
            token.startsWith("[") && token.contains("](") -> {
                val label = token.substringAfter("[").substringBefore("](")
                withStyle(SpanStyle(color = accentColor, textDecoration = TextDecoration.Underline, fontWeight = FontWeight.Medium)) {
                    append(label)
                }
            }
            token.startsWith("*") && token.endsWith("*") -> {
                withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(token.removeSurrounding("*")) }
            }
            else -> append(token)
        }
        last = match.range.last + 1
    }
    if (last < text.length) append(text.substring(last))
}

private fun queryFileName(context: Context, uri: Uri): String {
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
    return uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { "attachment_${System.currentTimeMillis()}" }
        ?: "attachment_${System.currentTimeMillis()}"
}
