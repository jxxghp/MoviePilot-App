package com.moviepilot.pluginhost.runtime

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.moviepilot.pluginhost.VuePluginSessionPayload
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.net.URLEncoder
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService
import kotlin.math.ln

/**
 * Activity 作用域交互回调接口：由 `LocalPluginShellWebView` 在 Compose 宿主中通过
 * `rememberLauncherForActivityResult` 实现并绑定到当前活跃 WebView 槽，释放时自动解绑。
 */
interface AndroidPluginActivityHost {
    fun requestPermission(permission: String, onResult: (Boolean) -> Unit)
    fun pickMedia(mediaType: String, multiple: Boolean, fromCamera: Boolean, onResult: (List<Uri>) -> Unit)
    fun pickFile(accept: List<String>, multiple: Boolean, onResult: (List<Uri>) -> Unit)
    fun setKeepAwake(enabled: Boolean)
    fun openDeepLink(deepLink: String)
    fun authenticate(reason: String, onResult: (Boolean, String) -> Unit)
}

/**
 * Android 端 Vue 联邦插件全量原生本地能力服务：
 * - 录音（`MediaRecorder` AAC `.m4a` + 实时音量分贝事件 + 暂停/恢复 + 15 MiB 限长 Base64 导出）
 * - 内联音频播放（`MediaPlayer`：支持 Base64、鉴权 `apiPath`、本地存储流票据边加载边播放及 HTTP(S) 直链）
 * - 全屏原生播放器（经 `moviepilot://play?...` 深度链接直达 MoviePilot 多内核原生播放器）
 * - 系统能力（设备信息、运行时权限、剪贴板读写、系统分享、屏幕常亮、本地通知、相册/相机/文件选取、保存相册、设备认证）
 */
class AndroidPluginNativeCapabilities(
    private val appContext: Context,
    private val okHttp: OkHttpClient,
    private val executor: ExecutorService,
    private val sessionProvider: () -> VuePluginSessionPayload?,
    private val sendResponse: (requestId: String, ok: Boolean, data: JsonObject?, errorCode: String?, errorStatus: Int, errorMessage: String?) -> Unit,
    private val sendDeviceEvent: (event: String, data: JsonObject) -> Unit,
) {
    companion object {
        const val MAX_BASE64_BYTES = 15 * 1024 * 1024
        private const val NOTIF_CHANNEL_ID = "mp_plugin_local_channel"
        private const val MEDIA_NOTIF_CHANNEL_ID = "mp_plugin_media_channel"
        private const val MEDIA_NOTIF_ID = 0x4D505041
        private const val ACTION_MEDIA_TOGGLE = "com.moviepilot.plugin.MEDIA_TOGGLE"
        private const val ACTION_MEDIA_PREV = "com.moviepilot.plugin.MEDIA_PREV"
        private const val ACTION_MEDIA_NEXT = "com.moviepilot.plugin.MEDIA_NEXT"
        private const val ACTION_MEDIA_STOP = "com.moviepilot.plugin.MEDIA_STOP"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    @Volatile
    var activityHost: AndroidPluginActivityHost? = null

    // Recording state
    private var recorder: MediaRecorder? = null
    private var recordingId: String? = null
    private var recordingFile: File? = null
    private var recordingStartedAtMs: Long = 0L
    private var recordingPausedAccumMs: Long = 0L
    private var recordingPausedAtMs: Long? = null
    private var recordingMaxDurationMs: Long = 300_000L
    private var recordingMetering: Boolean = true
    private var isRecordingPaused: Boolean = false
    private var recordingTickRunnable: Runnable? = null

    // Inline audio playback state
    private var mediaPlayer: MediaPlayer? = null
    private var playbackId: String? = null
    private var playbackTempFile: File? = null
    private var playbackState: String = "idle"
    private var playbackLoop: Boolean = false
    private var playbackRate: Float = 1.0f
    private var playbackVolume: Float = 1.0f
    private var playbackProgressRunnable: Runnable? = null

    // Keep-awake state
    private var keepAwakeEnabled: Boolean = false

    // Status bar / MediaSession Now Playing state (#56)
    private var mediaSession: MediaSession? = null
    private var mediaActionReceiver: BroadcastReceiver? = null
    private var nowPlayingActive: Boolean = false
    private var nowPlayingTitle: String = ""
    private var nowPlayingArtist: String = ""
    private var nowPlayingAlbum: String = ""
    private var nowPlayingCanNext: Boolean = false
    private var nowPlayingCanPrevious: Boolean = false
    private var nowPlayingArtworkUrl: String = ""
    private var nowPlayingArtworkBitmap: Bitmap? = null

    fun cleanup() {
        mainHandler.post {
            cancelActiveRecording(emitEvent = false)
            stopInlinePlayback(emitEvent = false)
            clearNowPlayingNotification()
            if (keepAwakeEnabled) {
                keepAwakeEnabled = false
                activityHost?.setKeepAwake(false)
            }
            activityHost = null
        }
    }

    fun handle(type: String, requestId: String, payload: JsonObject): Boolean {
        when (type) {
            "device.capabilities" -> handleCapabilities(requestId)
            "device.info" -> handleDeviceInfo(requestId)
            "device.permission" -> handlePermission(requestId, payload)
            "device.clipboard.read" -> handleClipboardRead(requestId)
            "device.share" -> handleShare(requestId, payload)
            "device.keepAwake" -> handleKeepAwake(requestId, payload)
            "device.notify" -> handleNotify(requestId, payload)
            "device.pickMedia" -> handlePickMedia(requestId, payload)
            "device.pickFile" -> handlePickFile(requestId, payload)
            "device.saveMedia" -> executor.execute { handleSaveMedia(requestId, payload) }
            "device.scanCode" -> sendError(requestId, "UNSUPPORTED", 400, "Android 端暂未启用内置扫码器，可使用拍照选取替代")
            "device.authenticate" -> handleAuthenticate(requestId, payload)
            "audio.record.start" -> handleRecordStart(requestId, payload)
            "audio.record.pause" -> mainHandler.post { handleRecordPause(requestId) }
            "audio.record.resume" -> mainHandler.post { handleRecordResume(requestId) }
            "audio.record.stop" -> mainHandler.post { handleRecordStop(requestId, payload) }
            "audio.record.cancel" -> mainHandler.post {
                cancelActiveRecording(emitEvent = true)
                sendSuccess(requestId, buildJsonObject { put("cancelled", true) })
            }
            "audio.record.status" -> mainHandler.post {
                sendSuccess(requestId, currentRecordStatusJson())
            }
            "audio.play" -> executor.execute { handleAudioPlay(requestId, payload) }
            "audio.pause" -> mainHandler.post { handleAudioPause(requestId) }
            "audio.resume" -> mainHandler.post { handleAudioResume(requestId) }
            "audio.stop" -> mainHandler.post {
                stopInlinePlayback(emitEvent = true)
                sendSuccess(requestId, buildJsonObject { put("stopped", true) })
            }
            "audio.seek" -> mainHandler.post { handleAudioSeek(requestId, payload) }
            "audio.setRate" -> mainHandler.post { handleAudioSetRate(requestId, payload) }
            "audio.setVolume" -> mainHandler.post { handleAudioSetVolume(requestId, payload) }
            "audio.status" -> mainHandler.post { sendSuccess(requestId, currentPlaybackStatusJson()) }
            "audio.setNowPlaying" -> mainHandler.post { handleAudioSetNowPlaying(requestId, payload) }
            "audio.clearNowPlaying" -> mainHandler.post {
                clearNowPlayingNotification()
                sendSuccess(requestId, buildJsonObject { put("cleared", true) })
            }
            "media.playNative" -> handlePlayNativeMedia(requestId, payload)
            else -> return false
        }
        return true
    }

    // MARK: - Device Info & Permissions

    private fun handleCapabilities(requestId: String) {
        val hasCamera = appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        val caps = mutableListOf(
            "audio.record",
            "audio.play",
            "audio.nowPlaying",
            "native.audio.nowPlaying",
            "media.playNative",
            "device.info",
            "device.permission",
            "device.haptic",
            "device.clipboard",
            "device.clipboard.read",
            "device.share",
            "device.keepAwake",
            "device.notify",
            "device.pickMedia",
            "device.pickFile",
            "device.saveMedia",
            "device.authenticate",
        )
        if (hasCamera) caps += "device.camera"
        sendSuccess(
            requestId,
            buildJsonObject {
                put("platform", "android")
                put("osVersion", Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT.toString())
                put("appVersion", appVersionName())
                put("deviceModel", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                put("networkType", currentNetworkType())
                put("isDark", isSystemDark())
                put("capabilities", buildJsonArray { caps.forEach { add(JsonPrimitive(it)) } })
            },
        )
    }

    private fun handleDeviceInfo(requestId: String) {
        val dm = appContext.resources.displayMetrics
        val density = dm.density.takeIf { it > 0f } ?: 1f
        sendSuccess(
            requestId,
            buildJsonObject {
                put("platform", "android")
                put("osVersion", Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT.toString())
                put("appVersion", appVersionName())
                put("deviceModel", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                put("networkType", currentNetworkType())
                put("locale", Locale.getDefault().toLanguageTag())
                put("isDark", isSystemDark())
                put("screenWidth", (dm.widthPixels / density).toInt())
                put("screenHeight", (dm.heightPixels / density).toInt())
                put("pixelRatio", density.toDouble())
            },
        )
    }

    private fun handlePermission(requestId: String, payload: JsonObject) {
        val perm = payload["permission"]?.strOrNull()?.lowercase().orEmpty()
        val shouldRequest = (payload["request"] as? JsonPrimitive)?.booleanOrNull ?: false
        val manifestPerm = when (perm) {
            "microphone" -> Manifest.permission.RECORD_AUDIO
            "camera" -> Manifest.permission.CAMERA
            "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Manifest.permission.POST_NOTIFICATIONS
            } else {
                sendSuccess(requestId, buildJsonObject { put("permission", perm); put("status", "granted") })
                return
            }
            "photos" -> {
                // 系统照片/文件选择器（SAF/OpenDocument）与 MediaStore 写入在 Android 10+ 无需存储权限
                sendSuccess(requestId, buildJsonObject { put("permission", perm); put("status", "granted") })
                return
            }
            else -> {
                sendError(requestId, "INVALID_PERMISSION", 400, "Unsupported permission: $perm")
                return
            }
        }
        val granted = ContextCompat.checkSelfPermission(appContext, manifestPerm) == PackageManager.PERMISSION_GRANTED
        if (granted || !shouldRequest) {
            val status = if (granted) "granted" else "undetermined"
            sendSuccess(requestId, buildJsonObject { put("permission", perm); put("status", status) })
            return
        }
        val host = activityHost
        if (host == null) {
            sendSuccess(requestId, buildJsonObject { put("permission", perm); put("status", "denied") })
            return
        }
        mainHandler.post {
            host.requestPermission(manifestPerm) { ok ->
                sendSuccess(
                    requestId,
                    buildJsonObject {
                        put("permission", perm)
                        put("status", if (ok) "granted" else "denied")
                    },
                )
            }
        }
    }

    private fun handleClipboardRead(requestId: String) {
        mainHandler.post {
            val cm = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            val text = cm?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(appContext)?.toString().orEmpty()
            sendSuccess(requestId, buildJsonObject { put("text", text) })
        }
    }

    private fun handleKeepAwake(requestId: String, payload: JsonObject) {
        val enabled = (payload["enabled"] as? JsonPrimitive)?.booleanOrNull ?: false
        mainHandler.post {
            keepAwakeEnabled = enabled
            activityHost?.setKeepAwake(enabled)
            sendSuccess(requestId, buildJsonObject { put("enabled", enabled) })
        }
    }

    private fun handleShare(requestId: String, payload: JsonObject) {
        executor.execute {
            val title = payload["title"]?.strOrNull().orEmpty()
            val text = payload["text"]?.strOrNull().orEmpty()
            val url = payload["url"]?.strOrNull().orEmpty()
            val rawB64 = payload["base64"]?.strOrNull().orEmpty()
            val mimeType = payload["mimeType"]?.strOrNull().orEmpty().ifBlank { "*/*" }
            val fileName = payload["fileName"]?.strOrNull().orEmpty().ifBlank { "share_${UUID.randomUUID()}.bin" }

            val intent = Intent(Intent.ACTION_SEND).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (rawB64.isNotBlank()) {
                val bytes = runCatching { Base64.decode(stripDataUriPrefix(rawB64), Base64.DEFAULT) }.getOrNull()
                if (bytes == null || bytes.isEmpty() || bytes.size > MAX_BASE64_BYTES) {
                    sendError(requestId, "INVALID_SHARE_FILE", 400, "分享文件无效或超出 15MB 限制")
                    return@execute
                }
                val safeName = fileName.replace(Regex("[^a-zA-Z0-9._\\-\\u4e00-\\u9fa5]"), "_")
                val dir = File(appContext.cacheDir, "plugin_share").apply { mkdirs() }
                val file = File(dir, safeName)
                file.writeBytes(bytes)
                val uri = FileProvider.getUriForFile(appContext, "${appContext.packageName}.fileprovider", file)
                intent.type = mimeType
                intent.putExtra(Intent.EXTRA_STREAM, uri)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                if (text.isNotBlank()) intent.putExtra(Intent.EXTRA_TEXT, text)
            } else {
                val combined = listOf(text, url).filter { it.isNotBlank() }.joinToString("\n")
                if (combined.isBlank()) {
                    sendError(requestId, "EMPTY_SHARE", 400, "缺少可分享的内容")
                    return@execute
                }
                intent.type = "text/plain"
                if (title.isNotBlank()) intent.putExtra(Intent.EXTRA_SUBJECT, title)
                intent.putExtra(Intent.EXTRA_TEXT, combined)
            }
            mainHandler.post {
                val chooser = Intent.createChooser(intent, title.ifBlank { "分享" }).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                runCatching { appContext.startActivity(chooser) }
                    .onSuccess {
                        sendSuccess(requestId, buildJsonObject { put("completed", true); put("cancelled", false) })
                    }
                    .onFailure { err ->
                        sendError(requestId, "SHARE_FAILED", 500, err.message ?: "无法打开系统分享")
                    }
            }
        }
    }

    private fun handleNotify(requestId: String, payload: JsonObject) {
        val title = payload["title"]?.strOrNull().orEmpty().trim()
        val body = payload["body"]?.strOrNull().orEmpty().trim()
        val idStr = payload["id"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: "plugin_${UUID.randomUUID()}"
        val delayMs = (((payload["delaySec"] as? JsonPrimitive)?.doubleOrNull ?: 0.0) * 1000.0).toLong().coerceAtLeast(0L)
        if (title.isBlank() && body.isBlank()) {
            sendError(requestId, "INVALID_NOTIFICATION", 400, "通知标题和内容不能同时为空")
            return
        }

        val postNow: () -> Unit = {
            ensureNotificationChannel()
            val notif = NotificationCompat.Builder(appContext, NOTIF_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title.ifBlank { "MoviePilot" })
                .setContentText(body)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
            val emit = Runnable {
                runCatching {
                    NotificationManagerCompat.from(appContext).notify(idStr.hashCode(), notif)
                }
            }
            if (delayMs > 0L) mainHandler.postDelayed(emit, delayMs) else mainHandler.post(emit)
            sendSuccess(requestId, buildJsonObject { put("scheduled", true); put("id", idStr) })
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            val host = activityHost
            if (host == null) {
                sendError(requestId, "PERMISSION_DENIED", 403, "未获得系统通知权限")
                return
            }
            mainHandler.post {
                host.requestPermission(Manifest.permission.POST_NOTIFICATIONS) { granted ->
                    if (granted) postNow() else sendError(requestId, "PERMISSION_DENIED", 403, "未获得系统通知权限")
                }
            }
        } else {
            postNow()
        }
    }

    private fun handlePickMedia(requestId: String, payload: JsonObject) {
        val host = activityHost
        if (host == null) {
            sendError(requestId, "NO_ACTIVITY", 500, "当前界面无法打开媒体选择器")
            return
        }
        val source = payload["source"]?.strOrNull()?.lowercase() ?: "library"
        val mediaType = payload["mediaType"]?.strOrNull()?.lowercase() ?: "image"
        val multiple = (payload["multiple"] as? JsonPrimitive)?.booleanOrNull ?: false
        val includeBase64 = (payload["includeBase64"] as? JsonPrimitive)?.booleanOrNull ?: true
        val fromCamera = source == "camera"

        val startPick = {
            host.pickMedia(mediaType, multiple, fromCamera) { uris ->
                readPickedUris(requestId, uris, includeBase64)
            }
        }
        mainHandler.post {
            if (fromCamera &&
                ContextCompat.checkSelfPermission(appContext, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
            ) {
                host.requestPermission(Manifest.permission.CAMERA) { granted ->
                    if (granted) startPick() else sendError(requestId, "PERMISSION_DENIED", 403, "未获得相机权限")
                }
            } else {
                startPick()
            }
        }
    }

    private fun handlePickFile(requestId: String, payload: JsonObject) {
        val host = activityHost
        if (host == null) {
            sendError(requestId, "NO_ACTIVITY", 500, "当前界面无法打开文件选择器")
            return
        }
        val accept = (payload["accept"] as? JsonArray)?.mapNotNull { it.strOrNull() }.orEmpty()
        val multiple = (payload["multiple"] as? JsonPrimitive)?.booleanOrNull ?: false
        val includeBase64 = (payload["includeBase64"] as? JsonPrimitive)?.booleanOrNull ?: true
        mainHandler.post {
            host.pickFile(accept, multiple) { uris ->
                readPickedUris(requestId, uris, includeBase64)
            }
        }
    }

    private fun readPickedUris(requestId: String, uris: List<Uri>, includeBase64: Boolean) {
        if (uris.isEmpty()) {
            sendSuccess(
                requestId,
                buildJsonObject {
                    put("cancelled", true)
                    put("files", buildJsonArray {})
                },
            )
            return
        }
        executor.execute {
            val filesJson = buildJsonArray {
                uris.forEach { uri ->
                    val name = queryFileName(uri)
                    val mime = appContext.contentResolver.getType(uri) ?: "application/octet-stream"
                    val bytes = runCatching {
                        appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    }.getOrNull() ?: return@forEach
                    add(
                        buildJsonObject {
                            put("name", name)
                            put("mimeType", mime)
                            put("sizeBytes", bytes.size)
                            if (includeBase64 && bytes.size <= MAX_BASE64_BYTES) {
                                put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP))
                                put("truncated", false)
                            } else {
                                put("truncated", includeBase64 && bytes.size > MAX_BASE64_BYTES)
                            }
                        },
                    )
                }
            }
            sendSuccess(
                requestId,
                buildJsonObject {
                    put("cancelled", filesJson.isEmpty())
                    put("files", filesJson)
                },
            )
        }
    }

    private fun handleSaveMedia(requestId: String, payload: JsonObject) {
        val rawB64 = payload["base64"]?.strOrNull().orEmpty()
        val rawApi = payload["apiPath"]?.strOrNull().orEmpty()
        val rawUrl = payload["url"]?.strOrNull().orEmpty()
        val mime = payload["mimeType"]?.strOrNull().orEmpty().ifBlank { "image/png" }
        val fileName = payload["fileName"]?.strOrNull().orEmpty().ifBlank { "moviepilot_${System.currentTimeMillis()}.png" }

        val bytes: ByteArray? = when {
            rawB64.isNotBlank() -> runCatching { Base64.decode(stripDataUriPrefix(rawB64), Base64.DEFAULT) }.getOrNull()
            rawApi.isNotBlank() -> {
                val normalized = RustCoreBridge.validatePluginApiPath(rawApi)
                val sess = sessionProvider()
                if (normalized == null || sess == null) {
                    sendError(requestId, "FORBIDDEN_PATH", 403, "非法或未认证的 API 路径")
                    return
                }
                val req = Request.Builder()
                    .url("${sess.serverUrl.trimEnd('/')}$normalized")
                    .header("Authorization", "Bearer ${sess.authToken}")
                    .build()
                runCatching { okHttp.newCall(req).execute().use { if (it.isSuccessful) it.body?.bytes() else null } }.getOrNull()
            }
            rawUrl.startsWith("http://", true) || rawUrl.startsWith("https://", true) -> {
                val req = Request.Builder().url(rawUrl).build()
                runCatching { okHttp.newCall(req).execute().use { if (it.isSuccessful) it.body?.bytes() else null } }.getOrNull()
            }
            else -> null
        }

        if (bytes == null || bytes.isEmpty()) {
            sendError(requestId, "INVALID_MEDIA", 400, "无法获取待保存的媒体字节数据")
            return
        }

        runCatching {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mime)
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/MoviePilot")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val resolver = appContext.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: error("无法创建相册媒体记录")
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: error("无法写入相册文件")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }.onSuccess {
            sendSuccess(requestId, buildJsonObject { put("saved", true) })
        }.onFailure { err ->
            sendError(requestId, "SAVE_MEDIA_FAILED", 500, err.message ?: "保存媒体到相册失败")
        }
    }

    private fun handleAuthenticate(requestId: String, payload: JsonObject) {
        val host = activityHost
        if (host == null) {
            sendSuccess(requestId, buildJsonObject { put("authenticated", false); put("biometryType", "none") })
            return
        }
        val reason = payload["reason"]?.strOrNull()?.takeIf { it.isNotBlank() } ?: "验证设备身份以继续插件操作"
        mainHandler.post {
            host.authenticate(reason) { ok, biometryType ->
                sendSuccess(
                    requestId,
                    buildJsonObject {
                        put("authenticated", ok)
                        put("biometryType", biometryType)
                    },
                )
            }
        }
    }

    // MARK: - Audio Recording (`audio.record.*`)

    private fun handleRecordStart(requestId: String, payload: JsonObject) {
        val sampleRate = ((payload["sampleRate"] as? JsonPrimitive)?.intOrNull ?: 24_000).coerceIn(8_000, 48_000)
        val channels = ((payload["channels"] as? JsonPrimitive)?.intOrNull ?: 1).coerceIn(1, 2)
        val bitRate = ((payload["bitRate"] as? JsonPrimitive)?.intOrNull ?: 96_000).coerceIn(16_000, 256_000)
        val maxDurationMs = (((payload["maxDurationSec"] as? JsonPrimitive)?.doubleOrNull ?: 300.0).coerceIn(1.0, 1800.0) * 1000.0).toLong()
        val metering = (payload["metering"] as? JsonPrimitive)?.booleanOrNull ?: true

        val begin = {
            mainHandler.post {
                cancelActiveRecording(emitEvent = false)
                stopInlinePlayback(emitEvent = false)
                runCatching {
                    val recId = "rec_${UUID.randomUUID().toString().take(12)}"
                    val dir = File(appContext.cacheDir, "mp_plugin_recordings").apply { mkdirs() }
                    val file = File(dir, "$recId.m4a")
                    val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        MediaRecorder(appContext)
                    } else {
                        @Suppress("DEPRECATION")
                        MediaRecorder()
                    }
                    rec.setAudioSource(MediaRecorder.AudioSource.MIC)
                    rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    rec.setAudioSamplingRate(sampleRate)
                    rec.setAudioChannels(channels)
                    rec.setAudioEncodingBitRate(bitRate)
                    rec.setOutputFile(file.absolutePath)
                    rec.prepare()
                    rec.start()

                    val now = System.currentTimeMillis()
                    recorder = rec
                    recordingId = recId
                    recordingFile = file
                    recordingStartedAtMs = now
                    recordingPausedAccumMs = 0L
                    recordingPausedAtMs = null
                    recordingMaxDurationMs = maxDurationMs
                    recordingMetering = metering
                    isRecordingPaused = false
                    startRecordingTicker()

                    sendDeviceEvent(
                        "audio.record.state",
                        buildJsonObject {
                            put("recordingId", recId)
                            put("state", "recording")
                            put("durationMs", 0)
                        },
                    )
                    sendSuccess(
                        requestId,
                        buildJsonObject {
                            put("recordingId", recId)
                            put("mimeType", "audio/mp4")
                            put("format", "m4a")
                            put("startedAt", now)
                        },
                    )
                }.onFailure { err ->
                    cancelActiveRecording(emitEvent = false)
                    sendError(requestId, "RECORD_START_FAILED", 500, err.message ?: "无法启动原生录音")
                }
            }
        }

        val hasMic = ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (hasMic) {
            begin()
            return
        }
        val host = activityHost
        if (host == null) {
            sendError(requestId, "PERMISSION_DENIED", 403, "未获得麦克风权限")
            return
        }
        mainHandler.post {
            host.requestPermission(Manifest.permission.RECORD_AUDIO) { granted ->
                if (granted) begin() else sendError(requestId, "PERMISSION_DENIED", 403, "未获得麦克风权限")
            }
        }
    }

    private fun handleRecordPause(requestId: String) {
        val rec = recorder
        val recId = recordingId
        if (rec == null || recId == null) {
            sendError(requestId, "NOT_RECORDING", 400, "当前未在录音")
            return
        }
        if (!isRecordingPaused) {
            runCatching { rec.pause() }
            isRecordingPaused = true
            recordingPausedAtMs = System.currentTimeMillis()
        }
        val dur = currentRecordingDurationMs()
        sendDeviceEvent(
            "audio.record.state",
            buildJsonObject { put("recordingId", recId); put("state", "paused"); put("durationMs", dur) },
        )
        sendSuccess(
            requestId,
            buildJsonObject { put("recordingId", recId); put("state", "paused"); put("durationMs", dur) },
        )
    }

    private fun handleRecordResume(requestId: String) {
        val rec = recorder
        val recId = recordingId
        if (rec == null || recId == null) {
            sendError(requestId, "NOT_RECORDING", 400, "当前未在录音")
            return
        }
        if (isRecordingPaused) {
            recordingPausedAtMs?.let { recordingPausedAccumMs += (System.currentTimeMillis() - it).coerceAtLeast(0L) }
            recordingPausedAtMs = null
            isRecordingPaused = false
            runCatching { rec.resume() }
        }
        val dur = currentRecordingDurationMs()
        sendDeviceEvent(
            "audio.record.state",
            buildJsonObject { put("recordingId", recId); put("state", "recording"); put("durationMs", dur) },
        )
        sendSuccess(
            requestId,
            buildJsonObject { put("recordingId", recId); put("state", "recording"); put("durationMs", dur) },
        )
    }

    private fun handleRecordStop(requestId: String, payload: JsonObject) {
        val rec = recorder
        val recId = recordingId
        val file = recordingFile
        if (rec == null || recId == null || file == null) {
            sendError(requestId, "NOT_RECORDING", 400, "当前没有进行中的录音")
            return
        }
        val includeBase64 = (payload["includeBase64"] as? JsonPrimitive)?.booleanOrNull ?: true
        val dur = currentRecordingDurationMs()
        stopRecordingTicker()
        runCatching { rec.stop() }
        runCatching { rec.release() }
        recorder = null
        recordingId = null
        recordingFile = null
        recordingStartedAtMs = 0L
        recordingPausedAtMs = null
        recordingPausedAccumMs = 0L
        isRecordingPaused = false

        executor.execute {
            val bytes = runCatching { file.readBytes() }.getOrDefault(ByteArray(0))
            val name = file.name
            runCatching { file.delete() }
            sendDeviceEvent(
                "audio.record.state",
                buildJsonObject { put("recordingId", recId); put("state", "stopped"); put("durationMs", dur) },
            )
            sendSuccess(
                requestId,
                buildJsonObject {
                    put("recordingId", recId)
                    put("durationMs", dur)
                    put("sizeBytes", bytes.size)
                    put("mimeType", "audio/mp4")
                    put("fileName", name)
                    if (includeBase64 && bytes.size <= MAX_BASE64_BYTES) {
                        put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP))
                        put("truncated", false)
                    } else {
                        put("truncated", includeBase64 && bytes.size > MAX_BASE64_BYTES)
                    }
                },
            )
        }
    }

    private fun cancelActiveRecording(emitEvent: Boolean) {
        val recId = recordingId
        stopRecordingTicker()
        runCatching { recorder?.stop() }
        runCatching { recorder?.release() }
        recorder = null
        runCatching { recordingFile?.delete() }
        recordingFile = null
        recordingId = null
        recordingStartedAtMs = 0L
        recordingPausedAtMs = null
        recordingPausedAccumMs = 0L
        isRecordingPaused = false
        if (emitEvent && recId != null) {
            sendDeviceEvent(
                "audio.record.state",
                buildJsonObject { put("recordingId", recId); put("state", "cancelled"); put("durationMs", 0) },
            )
        }
    }

    private fun startRecordingTicker() {
        stopRecordingTicker()
        val r = object : Runnable {
            override fun run() {
                val rec = recorder ?: return
                val recId = recordingId ?: return
                if (!isRecordingPaused) {
                    val dur = currentRecordingDurationMs()
                    if (recordingMetering) {
                        val amp = runCatching { rec.maxAmplitude }.getOrDefault(0).coerceIn(0, 32767)
                        val normalized = (amp / 32767.0).coerceIn(0.0, 1.0)
                        val db = if (amp > 0) 20.0 * ln(amp / 32767.0) / ln(10.0) else -60.0
                        sendDeviceEvent(
                            "audio.record.level",
                            buildJsonObject {
                                put("recordingId", recId)
                                put("durationMs", dur)
                                put("meteringDb", db)
                                put("normalizedLevel", normalized)
                            },
                        )
                    }
                    if (dur >= recordingMaxDurationMs) {
                        runCatching { rec.pause() }
                        isRecordingPaused = true
                        recordingPausedAtMs = System.currentTimeMillis()
                        sendDeviceEvent(
                            "audio.record.state",
                            buildJsonObject {
                                put("recordingId", recId)
                                put("state", "paused")
                                put("durationMs", dur)
                                put("message", "已达最大录音时长上限")
                            },
                        )
                    }
                }
                mainHandler.postDelayed(this, 150L)
            }
        }
        recordingTickRunnable = r
        mainHandler.postDelayed(r, 150L)
    }

    private fun stopRecordingTicker() {
        recordingTickRunnable?.let { mainHandler.removeCallbacks(it) }
        recordingTickRunnable = null
    }

    private fun currentRecordingDurationMs(): Long {
        if (recordingStartedAtMs <= 0L) return 0L
        val endRef = recordingPausedAtMs ?: System.currentTimeMillis()
        return (endRef - recordingStartedAtMs - recordingPausedAccumMs).coerceAtLeast(0L)
    }

    private fun currentRecordStatusJson(): JsonObject {
        val recId = recordingId ?: return buildJsonObject { put("state", "idle"); put("durationMs", 0) }
        return buildJsonObject {
            put("state", if (isRecordingPaused) "paused" else "recording")
            put("recordingId", recId)
            put("durationMs", currentRecordingDurationMs())
        }
    }

    // MARK: - Inline Audio Playback (`audio.*`)

    private fun handleAudioPlay(requestId: String, payload: JsonObject) {
        val loop = (payload["loop"] as? JsonPrimitive)?.booleanOrNull ?: false
        val volume = ((payload["volume"] as? JsonPrimitive)?.doubleOrNull ?: 1.0).toFloat().coerceIn(0f, 1f)
        val rate = ((payload["rate"] as? JsonPrimitive)?.doubleOrNull ?: 1.0).toFloat().coerceIn(0.5f, 2.0f)
        val startPosMs = ((payload["startPositionMs"] as? JsonPrimitive)?.intOrNull ?: 0).coerceAtLeast(0)
        val showInStatusBar = (payload["showInStatusBar"] as? JsonPrimitive)?.booleanOrNull ?: true
        val playTitle = payload["title"]?.strOrNull()?.trim().orEmpty()
        val playArtist = payload["artist"]?.strOrNull()?.trim().orEmpty()
        val playAlbum = payload["album"]?.strOrNull()?.trim().orEmpty()
        val playArtworkUrl = payload["artworkUrl"]?.strOrNull()?.trim().orEmpty()

        val rawB64 = payload["base64"]?.strOrNull().orEmpty()
        val storage = payload["storage"]?.strOrNull().orEmpty()
        val path = payload["path"]?.strOrNull().orEmpty()
        val rawApi = payload["apiPath"]?.strOrNull().orEmpty()
        val rawUrl = payload["url"]?.strOrNull().orEmpty()

        var dataSourceUrl: String? = null
        var headers: Map<String, String>? = null
        var tempFile: File? = null

        when {
            rawB64.isNotBlank() -> {
                val bytes = runCatching { Base64.decode(stripDataUriPrefix(rawB64), Base64.DEFAULT) }.getOrNull()
                if (bytes == null || bytes.isEmpty()) {
                    sendError(requestId, "INVALID_AUDIO", 400, "无效的 Base64 音频数据")
                    return
                }
                val dir = File(appContext.cacheDir, "mp_plugin_audio").apply { mkdirs() }
                val ext = when {
                    payload["mimeType"]?.strOrNull()?.contains("wav", true) == true -> "wav"
                    payload["mimeType"]?.strOrNull()?.contains("mpeg", true) == true -> "mp3"
                    else -> "m4a"
                }
                tempFile = File(dir, "play_${UUID.randomUUID()}.$ext").apply { writeBytes(bytes) }
            }
            storage.isNotBlank() && path.isNotBlank() -> {
                val sess = sessionProvider()
                if (sess == null) {
                    sendError(requestId, "NO_SESSION", 401, "当前无活跃会话")
                    return
                }
                val resolved = resolveStorageStreamUrl(sess, storage, path)
                dataSourceUrl = resolved.first
                headers = resolved.second
            }
            rawApi.isNotBlank() -> {
                val normalized = RustCoreBridge.validatePluginApiPath(rawApi)
                val sess = sessionProvider()
                if (normalized == null || sess == null) {
                    sendError(requestId, "FORBIDDEN_PATH", 403, "非法或未认证的 API 路径")
                    return
                }
                dataSourceUrl = "${sess.serverUrl.trimEnd('/')}$normalized"
                headers = buildAuthHeaders(sess)
            }
            rawUrl.startsWith("http://", true) || rawUrl.startsWith("https://", true) -> {
                dataSourceUrl = rawUrl
            }
            else -> {
                sendError(requestId, "INVALID_AUDIO_SOURCE", 400, "请提供 url、base64、apiPath 或 storage+path 音频源")
                return
            }
        }

        mainHandler.post {
            stopInlinePlayback(emitEvent = false)
            val playId = "play_${UUID.randomUUID().toString().take(12)}"
            playbackId = playId
            playbackTempFile = tempFile
            playbackLoop = loop
            playbackVolume = volume
            playbackRate = rate
            playbackState = "loading"

            runCatching {
                val mp = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build(),
                    )
                    isLooping = loop
                    setVolume(volume, volume)
                    if (tempFile != null) {
                        setDataSource(tempFile.absolutePath)
                    } else if (headers != null && headers.isNotEmpty()) {
                        setDataSource(appContext, Uri.parse(dataSourceUrl!!), headers)
                    } else {
                        setDataSource(dataSourceUrl!!)
                    }
                    setOnPreparedListener { player ->
                        if (playbackId != playId) return@setOnPreparedListener
                        if (startPosMs > 0) runCatching { player.seekTo(startPosMs) }
                        if (rate != 1.0f) {
                            runCatching { player.playbackParams = player.playbackParams.setSpeed(rate) }
                        }
                        player.start()
                        playbackState = "playing"
                        startPlaybackProgressTicker()
                        if (showInStatusBar && playTitle.isNotBlank()) {
                            applyNowPlayingNotification(
                                title = playTitle,
                                artist = playArtist,
                                album = playAlbum,
                                artworkUrl = playArtworkUrl,
                                durationMs = player.duration.coerceAtLeast(0).toLong(),
                                positionMs = startPosMs.toLong(),
                                isPlaying = true,
                                rate = rate,
                                canNext = false,
                                canPrevious = false,
                                canSeek = true,
                            )
                        }
                        emitPlaybackState()
                        sendSuccess(
                            requestId,
                            buildJsonObject {
                                put("playbackId", playId)
                                put("state", "playing")
                                put("durationMs", player.duration.coerceAtLeast(0))
                            },
                        )
                    }
                    setOnCompletionListener { player ->
                        if (playbackId != playId) return@setOnCompletionListener
                        if (!playbackLoop) {
                            playbackState = "ended"
                            stopPlaybackProgressTicker()
                            sendDeviceEvent(
                                "audio.play.ended",
                                buildJsonObject {
                                    put("playbackId", playId)
                                    put("durationMs", player.duration.coerceAtLeast(0))
                                },
                            )
                            emitPlaybackState()
                        }
                    }
                    setOnErrorListener { _, what, extra ->
                        if (playbackId == playId) {
                            playbackState = "error"
                            stopPlaybackProgressTicker()
                            sendDeviceEvent(
                                "audio.play.error",
                                buildJsonObject {
                                    put("playbackId", playId)
                                    put("code", "MEDIA_ERROR_${what}_$extra")
                                    put("message", "音频播放异常 ($what/$extra)")
                                },
                            )
                            sendError(requestId, "AUDIO_PLAY_FAILED", 500, "音频播放异常 ($what/$extra)")
                        }
                        true
                    }
                    prepareAsync()
                }
                mediaPlayer = mp
            }.onFailure { err ->
                stopInlinePlayback(emitEvent = false)
                sendError(requestId, "AUDIO_PLAY_FAILED", 500, err.message ?: "无法启动原生音频播放")
            }
        }
    }

    private fun handleAudioPause(requestId: String) {
        mediaPlayer?.let {
            if (it.isPlaying) it.pause()
            playbackState = "paused"
        }
        emitPlaybackState()
        sendSuccess(requestId, currentPlaybackStatusJson())
    }

    private fun handleAudioResume(requestId: String) {
        mediaPlayer?.let {
            it.start()
            playbackState = "playing"
            startPlaybackProgressTicker()
        }
        emitPlaybackState()
        sendSuccess(requestId, currentPlaybackStatusJson())
    }

    private fun handleAudioSeek(requestId: String, payload: JsonObject) {
        val posMs = ((payload["positionMs"] as? JsonPrimitive)?.intOrNull ?: 0).coerceAtLeast(0)
        mediaPlayer?.let { runCatching { it.seekTo(posMs) } }
        sendSuccess(requestId, currentPlaybackStatusJson())
    }

    private fun handleAudioSetRate(requestId: String, payload: JsonObject) {
        val rate = ((payload["rate"] as? JsonPrimitive)?.doubleOrNull ?: 1.0).toFloat().coerceIn(0.5f, 2.0f)
        playbackRate = rate
        mediaPlayer?.let { mp ->
            runCatching { mp.playbackParams = mp.playbackParams.setSpeed(rate) }
        }
        sendSuccess(
            requestId,
            buildJsonObject {
                put("playbackId", playbackId.orEmpty())
                put("rate", rate.toDouble())
            },
        )
    }

    private fun handleAudioSetVolume(requestId: String, payload: JsonObject) {
        val vol = ((payload["volume"] as? JsonPrimitive)?.doubleOrNull ?: 1.0).toFloat().coerceIn(0f, 1f)
        playbackVolume = vol
        mediaPlayer?.setVolume(vol, vol)
        sendSuccess(
            requestId,
            buildJsonObject {
                put("playbackId", playbackId.orEmpty())
                put("volume", vol.toDouble())
            },
        )
    }

    private fun stopInlinePlayback(emitEvent: Boolean) {
        val oldId = playbackId
        stopPlaybackProgressTicker()
        runCatching { mediaPlayer?.stop() }
        runCatching { mediaPlayer?.release() }
        mediaPlayer = null
        runCatching { playbackTempFile?.delete() }
        playbackTempFile = null
        playbackId = null
        playbackState = "idle"
        if (emitEvent && oldId != null) {
            sendDeviceEvent(
                "audio.play.state",
                buildJsonObject {
                    put("playbackId", oldId)
                    put("state", "stopped")
                    put("positionMs", 0)
                    put("durationMs", 0)
                    put("rate", playbackRate.toDouble())
                    put("volume", playbackVolume.toDouble())
                },
            )
        }
    }

    private fun startPlaybackProgressTicker() {
        stopPlaybackProgressTicker()
        val r = object : Runnable {
            override fun run() {
                val mp = mediaPlayer ?: return
                val pid = playbackId ?: return
                if (playbackState == "playing") {
                    val pos = runCatching { mp.currentPosition }.getOrDefault(0).coerceAtLeast(0)
                    val dur = runCatching { mp.duration }.getOrDefault(0).coerceAtLeast(0)
                    sendDeviceEvent(
                        "audio.play.progress",
                        buildJsonObject {
                            put("playbackId", pid)
                            put("positionMs", pos)
                            put("durationMs", dur)
                        },
                    )
                    mainHandler.postDelayed(this, 250L)
                }
            }
        }
        playbackProgressRunnable = r
        mainHandler.postDelayed(r, 250L)
    }

    private fun stopPlaybackProgressTicker() {
        playbackProgressRunnable?.let { mainHandler.removeCallbacks(it) }
        playbackProgressRunnable = null
    }

    private fun currentPlaybackStatusJson(): JsonObject {
        val mp = mediaPlayer
        val pos = runCatching { mp?.currentPosition ?: 0 }.getOrDefault(0).coerceAtLeast(0)
        val dur = runCatching { mp?.duration ?: 0 }.getOrDefault(0).coerceAtLeast(0)
        return buildJsonObject {
            put("state", playbackState)
            playbackId?.let { put("playbackId", it) }
            put("positionMs", pos)
            put("durationMs", dur)
            put("rate", playbackRate.toDouble())
            put("volume", playbackVolume.toDouble())
        }
    }

    private fun emitPlaybackState() {
        sendDeviceEvent("audio.play.state", currentPlaybackStatusJson())
        if (nowPlayingActive && nowPlayingTitle.isNotBlank()) {
            updateNowPlayingPlaybackState()
        }
    }

    // MARK: - Status Bar / MediaSession Now Playing (`audio.setNowPlaying` / `audio.clearNowPlaying`)

    private fun handleAudioSetNowPlaying(requestId: String, payload: JsonObject) {
        val title = payload["title"]?.strOrNull()?.trim().orEmpty()
        if (title.isBlank()) {
            sendError(requestId, "INVALID_PARAMS", 400, "title 不能为空")
            return
        }
        val artist = payload["artist"]?.strOrNull()?.trim().orEmpty()
        val album = payload["album"]?.strOrNull()?.trim().orEmpty()
        val artworkUrl = payload["artworkUrl"]?.strOrNull()?.trim().orEmpty()
        val durationMs = (payload["durationMs"] as? JsonPrimitive)?.doubleOrNull?.toLong()
        val positionMs = (payload["positionMs"] as? JsonPrimitive)?.doubleOrNull?.toLong()
        val isPlaying = (payload["isPlaying"] as? JsonPrimitive)?.booleanOrNull ?: (playbackState == "playing")
        val rate = ((payload["rate"] as? JsonPrimitive)?.doubleOrNull ?: playbackRate.toDouble()).toFloat()
        val canNext = (payload["canNext"] as? JsonPrimitive)?.booleanOrNull ?: false
        val canPrevious = (payload["canPrevious"] as? JsonPrimitive)?.booleanOrNull ?: false
        val canSeek = (payload["canSeek"] as? JsonPrimitive)?.booleanOrNull ?: true

        applyNowPlayingNotification(
            title = title,
            artist = artist,
            album = album,
            artworkUrl = artworkUrl,
            durationMs = durationMs,
            positionMs = positionMs,
            isPlaying = isPlaying,
            rate = rate,
            canNext = canNext,
            canPrevious = canPrevious,
            canSeek = canSeek,
        )
        sendSuccess(requestId, buildJsonObject { put("registered", true) })
    }

    private fun ensureMediaSessionAndReceiver(): MediaSession {
        mediaSession?.let { return it }
        val session = MediaSession(appContext, "MoviePilotPluginAudio").apply {
            setCallback(
                object : MediaSession.Callback() {
                    override fun onPlay() {
                        mainHandler.post {
                            mediaPlayer?.let {
                                it.start()
                                playbackState = "playing"
                                startPlaybackProgressTicker()
                                emitPlaybackState()
                            }
                            sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "play") })
                        }
                    }

                    override fun onPause() {
                        mainHandler.post {
                            mediaPlayer?.let {
                                if (it.isPlaying) it.pause()
                                playbackState = "paused"
                                emitPlaybackState()
                            }
                            sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "pause") })
                        }
                    }

                    override fun onStop() {
                        mainHandler.post {
                            stopInlinePlayback(emitEvent = true)
                            clearNowPlayingNotification()
                            sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "stop") })
                        }
                    }

                    override fun onSkipToNext() {
                        sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "next") })
                    }

                    override fun onSkipToPrevious() {
                        sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "previous") })
                    }

                    override fun onSeekTo(pos: Long) {
                        val targetMs = pos.coerceAtLeast(0L)
                        mainHandler.post {
                            mediaPlayer?.let { runCatching { it.seekTo(targetMs.toInt()) } }
                            updateNowPlayingPlaybackState()
                            sendDeviceEvent(
                                "audio.remoteCommand",
                                buildJsonObject {
                                    put("command", "seek")
                                    put("positionMs", targetMs)
                                },
                            )
                        }
                    }
                },
            )
            isActive = true
        }
        mediaSession = session

        if (mediaActionReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        ACTION_MEDIA_TOGGLE -> {
                            if (playbackState == "playing") {
                                mediaPlayer?.let { if (it.isPlaying) it.pause(); playbackState = "paused"; emitPlaybackState() }
                                sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "pause") })
                            } else {
                                mediaPlayer?.let { it.start(); playbackState = "playing"; startPlaybackProgressTicker(); emitPlaybackState() }
                                sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "play") })
                            }
                        }
                        ACTION_MEDIA_PREV -> sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "previous") })
                        ACTION_MEDIA_NEXT -> sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "next") })
                        ACTION_MEDIA_STOP -> {
                            stopInlinePlayback(emitEvent = true)
                            clearNowPlayingNotification()
                            sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "stop") })
                        }
                    }
                }
            }
            val filter = IntentFilter().apply {
                addAction(ACTION_MEDIA_TOGGLE)
                addAction(ACTION_MEDIA_PREV)
                addAction(ACTION_MEDIA_NEXT)
                addAction(ACTION_MEDIA_STOP)
            }
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("DEPRECATION")
                    appContext.registerReceiver(receiver, filter)
                }
                mediaActionReceiver = receiver
            }
        }
        return session
    }

    private fun applyNowPlayingNotification(
        title: String,
        artist: String,
        album: String,
        artworkUrl: String,
        durationMs: Long?,
        positionMs: Long?,
        isPlaying: Boolean,
        rate: Float,
        canNext: Boolean,
        canPrevious: Boolean,
        canSeek: Boolean,
    ) {
        nowPlayingActive = true
        nowPlayingTitle = title
        nowPlayingArtist = artist
        nowPlayingAlbum = album
        nowPlayingCanNext = canNext
        nowPlayingCanPrevious = canPrevious

        val session = ensureMediaSessionAndReceiver()
        val effectiveDur = durationMs ?: runCatching { mediaPlayer?.duration?.toLong() ?: 0L }.getOrDefault(0L)
        val effectivePos = positionMs ?: runCatching { mediaPlayer?.currentPosition?.toLong() ?: 0L }.getOrDefault(0L)

        val metaBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
        if (artist.isNotBlank()) metaBuilder.putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
        if (album.isNotBlank()) metaBuilder.putString(MediaMetadata.METADATA_KEY_ALBUM, album)
        if (effectiveDur > 0L) metaBuilder.putLong(MediaMetadata.METADATA_KEY_DURATION, effectiveDur)
        if (artworkUrl == nowPlayingArtworkUrl && nowPlayingArtworkBitmap != null) {
            metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, nowPlayingArtworkBitmap)
        }
        session.setMetadata(metaBuilder.build())

        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP
        if (canNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (canPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        if (canSeek) actions = actions or PlaybackState.ACTION_SEEK_TO
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    effectivePos.coerceAtLeast(0L),
                    if (isPlaying) rate else 0f,
                )
                .build(),
        )
        postMediaStyleNotification(session, isPlaying)

        if (artworkUrl.isNotBlank() && artworkUrl != nowPlayingArtworkUrl) {
            nowPlayingArtworkUrl = artworkUrl
            executor.execute {
                runCatching {
                    val reqBuilder = Request.Builder().url(artworkUrl)
                    val sess = sessionProvider()
                    if (sess != null && RustCoreBridge.containsUrl(sess.serverUrl, artworkUrl)) {
                        buildAuthHeaders(sess).forEach { (k, v) -> reqBuilder.header(k, v) }
                    }
                    okHttp.newCall(reqBuilder.build()).execute().use { resp ->
                        if (resp.isSuccessful) {
                            val bytes = resp.body?.bytes()
                            val bmp = if (bytes != null && bytes.isNotEmpty()) {
                                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            } else null
                            if (bmp != null) {
                                mainHandler.post {
                                    if (nowPlayingActive && nowPlayingArtworkUrl == artworkUrl) {
                                        nowPlayingArtworkBitmap = bmp
                                        mediaSession?.let { activeSess ->
                                            val updatedMeta = MediaMetadata.Builder()
                                                .putString(MediaMetadata.METADATA_KEY_TITLE, nowPlayingTitle)
                                                .apply {
                                                    if (nowPlayingArtist.isNotBlank()) putString(MediaMetadata.METADATA_KEY_ARTIST, nowPlayingArtist)
                                                    if (nowPlayingAlbum.isNotBlank()) putString(MediaMetadata.METADATA_KEY_ALBUM, nowPlayingAlbum)
                                                    putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp)
                                                }
                                                .build()
                                            activeSess.setMetadata(updatedMeta)
                                            postMediaStyleNotification(activeSess, playbackState == "playing")
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

    private fun updateNowPlayingPlaybackState() {
        val session = mediaSession ?: return
        val isPlaying = playbackState == "playing"
        val pos = runCatching { mediaPlayer?.currentPosition?.toLong() ?: 0L }.getOrDefault(0L)
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or PlaybackState.ACTION_SEEK_TO
        if (nowPlayingCanNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (nowPlayingCanPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    pos.coerceAtLeast(0L),
                    if (isPlaying) playbackRate else 0f,
                )
                .build(),
        )
        postMediaStyleNotification(session, isPlaying)
    }

    @Suppress("DEPRECATION")
    private fun postMediaStyleNotification(session: MediaSession, isPlaying: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val nm = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                MEDIA_NOTIF_CHANNEL_ID,
                "插件音频播放控制",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) }
            nm.createNotificationChannel(ch)
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        fun actionIntent(action: String, reqCode: Int): PendingIntent =
            PendingIntent.getBroadcast(
                appContext,
                reqCode,
                Intent(action).setPackage(appContext.packageName),
                piFlags,
            )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(appContext, MEDIA_NOTIF_CHANNEL_ID)
        } else {
            Notification.Builder(appContext)
        }
        builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(nowPlayingTitle)
            .setContentText(listOf(nowPlayingArtist, nowPlayingAlbum).filter { it.isNotBlank() }.joinToString(" · ").ifBlank { "插件正在播放" })
            .setOngoing(isPlaying)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        nowPlayingArtworkBitmap?.let { builder.setLargeIcon(it) }

        val compactIndices = mutableListOf<Int>()
        var idx = 0
        if (nowPlayingCanPrevious) {
            builder.addAction(Notification.Action.Builder(android.R.drawable.ic_media_previous, "上一首", actionIntent(ACTION_MEDIA_PREV, 1)).build())
            compactIndices += idx++
        }
        builder.addAction(
            Notification.Action.Builder(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "暂停" else "播放",
                actionIntent(ACTION_MEDIA_TOGGLE, 2),
            ).build(),
        )
        compactIndices += idx++
        if (nowPlayingCanNext) {
            builder.addAction(Notification.Action.Builder(android.R.drawable.ic_media_next, "下一首", actionIntent(ACTION_MEDIA_NEXT, 3)).build())
            compactIndices += idx++
        }
        builder.addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "停止", actionIntent(ACTION_MEDIA_STOP, 4)).build())

        val style = Notification.MediaStyle()
            .setMediaSession(session.sessionToken)
            .setShowActionsInCompactView(*compactIndices.take(3).toIntArray())
        builder.setStyle(style)
        runCatching { nm.notify(MEDIA_NOTIF_ID, builder.build()) }
    }

    private fun clearNowPlayingNotification() {
        nowPlayingActive = false
        nowPlayingTitle = ""
        nowPlayingArtist = ""
        nowPlayingAlbum = ""
        nowPlayingArtworkUrl = ""
        nowPlayingArtworkBitmap = null
        mediaSession?.let {
            runCatching { it.isActive = false }
            runCatching { it.release() }
        }
        mediaSession = null
        mediaActionReceiver?.let {
            runCatching { appContext.unregisterReceiver(it) }
        }
        mediaActionReceiver = null
        val nm = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        runCatching { nm?.cancel(MEDIA_NOTIF_ID) }
    }

    private fun resolveStorageStreamUrl(
        session: VuePluginSessionPayload,
        storage: String,
        path: String,
    ): Pair<String, Map<String, String>?> {
        val origin = session.serverUrl.trimEnd('/')
        val fileName = path.substringAfterLast('/').ifBlank { "audio" }
        val ext = fileName.substringAfterLast('.', "")
        val authHeaders = buildAuthHeaders(session)

        // 通过真实后端 `POST /api/v1/mediaserver/stream-ticket` + `stream-info` 获取支持 HTTP Range 的渐进流地址（兼容 local/SMB/OpenList/网盘）
        val reqBody = buildJsonObject {
            put(
                "file",
                buildJsonObject {
                    put("storage", storage)
                    put("type", "file")
                    put("path", path)
                    put("name", fileName)
                    put("extension", ext)
                },
            )
            put("media_type", "audio")
        }.toString().toRequestBody("application/json; charset=utf-8".toMediaType())

        val ticketReq = Request.Builder()
            .url("$origin/api/v1/mediaserver/stream-ticket")
            .header("Authorization", "Bearer ${session.authToken}")
            .post(reqBody)
            .build()
        runCatching {
            okHttp.newCall(ticketReq).execute().use { resp ->
                if (resp.isSuccessful) {
                    val txt = resp.body?.string().orEmpty()
                    val root = json.parseToJsonElement(txt).jsonObject
                    val inner = (root["data"] as? JsonObject) ?: root
                    val ticketId = inner["item_id"]?.strOrNull().orEmpty()
                    if (ticketId.isNotBlank()) {
                        val encId = URLEncoder.encode(ticketId, "UTF-8")
                        val infoReq = Request.Builder()
                            .url("$origin/api/v1/mediaserver/stream-info?itemid=$encId")
                            .header("Authorization", "Bearer ${session.authToken}")
                            .get()
                            .build()
                        val contentUrl = runCatching {
                            okHttp.newCall(infoReq).execute().use { infoResp ->
                                if (infoResp.isSuccessful) {
                                    val infoTxt = infoResp.body?.string().orEmpty()
                                    val infoRoot = json.parseToJsonElement(infoTxt).jsonObject
                                    val infoData = (infoRoot["data"] as? JsonObject) ?: infoRoot
                                    infoData["content_url"]?.strOrNull().orEmpty()
                                } else ""
                            }
                        }.getOrDefault("")
                        if (contentUrl.isNotBlank()) {
                            val resolved = if (contentUrl.startsWith("http://", true) || contentUrl.startsWith("https://", true)) {
                                contentUrl
                            } else {
                                "$origin${if (contentUrl.startsWith("/")) contentUrl else "/$contentUrl"}"
                            }
                            return resolved to authHeaders
                        }
                        return "$origin/api/v1/mediaserver/stream?itemid=$encId" to authHeaders
                    }
                }
            }
        }
        throw IllegalStateException("当前存储暂不支持在线流式播放，请检查存储配置或升级后端")
    }

    // MARK: - Full-Screen Native Media Player (`media.playNative`)

    private fun handlePlayNativeMedia(requestId: String, payload: JsonObject) {
        val host = activityHost
        if (host == null) {
            sendError(requestId, "NO_ACTIVITY", 500, "当前界面无法启动原生播放器")
            return
        }
        val storage = payload["storage"]?.strOrNull().orEmpty()
        val path = payload["path"]?.strOrNull().orEmpty()
        val itemId = payload["itemId"]?.strOrNull().orEmpty()
        val server = payload["server"]?.strOrNull().orEmpty()
        val rawUrl = payload["url"]?.strOrNull().orEmpty()
        val title = payload["title"]?.strOrNull().orEmpty()
        val mediaType = payload["mediaType"]?.strOrNull()?.lowercase().orEmpty()

        val deepLink = when {
            storage.isNotBlank() && path.isNotBlank() -> {
                val q = mutableListOf(
                    "storage=${URLEncoder.encode(storage, "UTF-8")}",
                    "path=${URLEncoder.encode(path, "UTF-8")}",
                )
                if (title.isNotBlank()) q += "title=${URLEncoder.encode(title, "UTF-8")}"
                "moviepilot://play?${q.joinToString("&")}"
            }
            itemId.isNotBlank() -> {
                val q = mutableListOf("itemid=${URLEncoder.encode(itemId, "UTF-8")}")
                if (server.isNotBlank()) q += "server=${URLEncoder.encode(server, "UTF-8")}"
                if (title.isNotBlank()) q += "title=${URLEncoder.encode(title, "UTF-8")}"
                "moviepilot://play?${q.joinToString("&")}"
            }
            rawUrl.startsWith("http://", true) || rawUrl.startsWith("https://", true) -> {
                val q = mutableListOf("url=${URLEncoder.encode(rawUrl, "UTF-8")}")
                if (title.isNotBlank()) q += "title=${URLEncoder.encode(title, "UTF-8")}"
                if (mediaType == "audio" || mediaType == "video") q += "type=$mediaType"
                "moviepilot://play?${q.joinToString("&")}"
            }
            else -> {
                sendError(requestId, "INVALID_MEDIA", 400, "请提供 url、storage+path 或 itemId 媒体参数")
                return
            }
        }
        mainHandler.post {
            host.openDeepLink(deepLink)
            sendSuccess(requestId, buildJsonObject { put("launched", true) })
        }
    }

    // MARK: - Helpers

    private fun buildAuthHeaders(session: VuePluginSessionPayload): Map<String, String> {
        val map = mutableMapOf(
            "Authorization" to "Bearer ${session.authToken}",
            "X-MoviePilot-Locale" to "zh-CN",
        )
        val cookieHeader = session.originCookies
            .mapNotNull { it.substringBefore(';').trim().takeIf(String::isNotEmpty) }
            .joinToString("; ")
        if (cookieHeader.isNotEmpty()) map["Cookie"] = cookieHeader
        return map
    }

    private fun ensureNotificationChannel() {
        val nm = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (nm.getNotificationChannel(NOTIF_CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    NOTIF_CHANNEL_ID,
                    "插件本地通知",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
    }

    private fun queryFileName(uri: Uri): String {
        runCatching {
            appContext.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        cursor.getString(idx)?.takeIf { it.isNotBlank() }?.let { return it }
                    }
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "file_${System.currentTimeMillis()}"
    }

    private fun appVersionName(): String = runCatching {
        appContext.packageManager.getPackageInfo(appContext.packageName, 0).versionName
    }.getOrNull() ?: "2.0.0"

    private fun currentNetworkType(): String {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return "unknown"
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "none"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
    }

    private fun isSystemDark(): Boolean =
        (appContext.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    private fun stripDataUriPrefix(raw: String): String {
        val comma = raw.indexOf(',')
        return if (comma > 0 && raw.substring(0, comma).contains("base64", ignoreCase = true)) {
            raw.substring(comma + 1)
        } else {
            raw
        }
    }

    private fun sendSuccess(requestId: String, data: JsonObject) {
        if (requestId.isBlank()) return
        sendResponse(requestId, true, data, null, 200, null)
    }

    private fun sendError(requestId: String, code: String, status: Int, message: String) {
        if (requestId.isBlank()) return
        sendResponse(requestId, false, null, code, status, message)
    }

    private fun JsonElement.strOrNull(): String? = when (this) {
        is JsonNull -> null
        is JsonPrimitive -> content.takeIf { it != "null" }
        else -> toString()
    }
}
