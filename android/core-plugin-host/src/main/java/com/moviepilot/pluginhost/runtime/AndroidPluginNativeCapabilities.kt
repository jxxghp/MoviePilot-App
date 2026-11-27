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
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.audiofx.Visualizer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.moviepilot.pluginhost.R
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
import java.io.FileOutputStream
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * 计算系统状态栏 `MediaSession` 的播放状态码与推进倍速（`#89`）：
 * 当原生内联音频处于 `loading` / `buffering` 或插件显式声明缓冲态时，强制下发 `STATE_BUFFERING` 与 `0f` 倍速，
 * 确保未真正出声或弱网缓冲期间系统通知栏/锁屏进度条停住不空跑。
 */
internal fun buildResolvedMediaSessionStateParams(
    playbackState: String,
    hasInlineSession: Boolean,
    explicitBuffering: Boolean,
    requestedIsPlaying: Boolean,
    rate: Float,
): Pair<Int, Float> {
    val isInlineBuffering = hasInlineSession && (playbackState == "loading" || playbackState == "buffering")
    if (isInlineBuffering || explicitBuffering || playbackState == "buffering") {
        return PlaybackState.STATE_BUFFERING to 0f
    }
    return if (requestedIsPlaying) {
        PlaybackState.STATE_PLAYING to rate
    } else {
        PlaybackState.STATE_PAUSED to 0f
    }
}

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
        private const val ACTION_MEDIA_LIKE = "com.moviepilot.plugin.MEDIA_LIKE"
        private const val ACTION_MEDIA_CUSTOM = "com.moviepilot.plugin.MEDIA_CUSTOM"
        private const val EXTRA_CUSTOM_ACTION_ID = "custom_action_id"
        private const val CUSTOM_ACTION_TOGGLE_LIKE = "mp_toggle_like"
        private const val CUSTOM_ACTION_PREFIX = "mp_custom:"
        private const val VOLUME_CHANGED_ACTION = "android.media.VOLUME_CHANGED_ACTION"
        private const val EXTRA_VOLUME_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE"
        private const val ACTION_WIDGET_COMMAND = "com.moviepilot.plugin.WIDGET_ACTION"
        private const val ACTION_PLUGIN_WIDGET_RUNTIME_UPDATED = "com.moviepilot.widget.ACTION_PLUGIN_WIDGET_RUNTIME_UPDATED"
        private const val ACTION_NOW_PLAYING_UPDATED = "com.moviepilot.widget.ACTION_NOW_PLAYING_UPDATED"
        private const val PREF_PLUGIN_WIDGETS = "mp_plugin_widgets_v1"
        private const val PREF_NOW_PLAYING_WIDGET = "mp_now_playing_widget_v1"
        private const val MAX_WIDGET_PAYLOAD_BYTES = 32 * 1024
        private const val MAX_WIDGET_LAYOUT_DEPTH = 5
        private const val MAX_WIDGET_LAYOUT_NODES = 40
        private const val MEDIA_INFO_AUDIO_RENDERING_START_CODE = 4
    }

    private data class NowPlayingLyricLine(
        val timeMs: Long,
        val text: String,
    )

    private data class NowPlayingCustomAction(
        val id: String,
        val title: String,
        val icon: String? = null,
        val active: Boolean = false,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    @Volatile
    var activityHost: AndroidPluginActivityHost? = null

    @Volatile
    var activePluginId: String = ""

    @Volatile
    var activePluginName: String = ""

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

    // Inline audio playback & real-time spectrum state (#79 / #89)
    private var mediaPlayer: MediaPlayer? = null
    private var playbackId: String? = null
    private var playbackTempFile: File? = null
    private var playbackState: String = "idle"
    private var playbackDesiredPlaying: Boolean = false
    private var isMediaBuffering: Boolean = false
    private var isSeekPending: Boolean = false
    private var hasRenderedAudioSinceStartOrSeek: Boolean = false
    private var playbackAnchorPositionMs: Int = 0
    private var pinnedBufferingPositionMs: Int = 0
    private var nowPlayingExplicitBuffering: Boolean = false
    private var playbackLoop: Boolean = false
    private var playbackRate: Float = 1.0f
    private var playbackVolume: Float = 1.0f
    private var playbackProgressRunnable: Runnable? = null
    private var spectrumEnabled: Boolean = false
    private var spectrumBands: Int = 64
    private var spectrumIntervalMs: Long = 50L
    private var visualizer: Visualizer? = null
    private var lastSpectrumEmitElapsedMs: Long = 0L
    @Volatile
    private var latestLeftLevel: Int = 0
    @Volatile
    private var latestRightLevel: Int = 0

    // System volume & desktop widget broadcast state (#82)
    private var systemEventReceiver: BroadcastReceiver? = null
    private var lastObservedVolumeSteps: Int = -1
    private var lastObservedVolumeMuted: Boolean? = null

    // Keep-awake state
    private var keepAwakeEnabled: Boolean = false

    // Status bar / MediaSession Now Playing state (#56 / #82)
    private var mediaSession: MediaSession? = null
    private var mediaActionReceiver: BroadcastReceiver? = null
    private var nowPlayingActive: Boolean = false
    private var nowPlayingTitle: String = ""
    private var nowPlayingArtist: String = ""
    private var nowPlayingAlbum: String = ""
    private var nowPlayingCanNext: Boolean = false
    private var nowPlayingCanPrevious: Boolean = false
    private var nowPlayingCanSeek: Boolean = true
    private var nowPlayingDurationMs: Long = 0L
    private var nowPlayingPositionMs: Long = 0L
    private var nowPlayingLyrics: String = ""
    private var nowPlayingLyricLines: List<NowPlayingLyricLine> = emptyList()
    private var lastDisplayedLyricLine: String = ""
    private var nowPlayingHasLike: Boolean = false
    private var nowPlayingLiked: Boolean = false
    private var nowPlayingCustomActions: List<NowPlayingCustomAction> = emptyList()
    private var nowPlayingArtworkUrl: String = ""
    private var nowPlayingArtworkBitmap: Bitmap? = null
    private var nowPlayingWidgetArtworkPath: String = ""

    fun cleanup() {
        mainHandler.post {
            cancelActiveRecording(emitEvent = false)
            stopInlinePlayback(emitEvent = false)
            clearNowPlayingNotification()
            unregisterSystemReceivers()
            if (keepAwakeEnabled) {
                keepAwakeEnabled = false
                activityHost?.setKeepAwake(false)
            }
            activityHost = null
            activePluginId = ""
            activePluginName = ""
        }
    }

    fun handle(type: String, requestId: String, payload: JsonObject): Boolean {
        ensureSystemReceiversRegistered()
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
            "audio.getSystemVolume" -> mainHandler.post { handleGetSystemVolume(requestId) }
            "audio.setSystemVolume" -> mainHandler.post { handleSetSystemVolume(requestId, payload) }
            "audio.setSpectrum" -> mainHandler.post { handleAudioSetSpectrum(requestId, payload) }
            "audio.status" -> mainHandler.post { sendSuccess(requestId, currentPlaybackStatusJson()) }
            "audio.setNowPlaying" -> mainHandler.post { handleAudioSetNowPlaying(requestId, payload) }
            "audio.clearNowPlaying" -> mainHandler.post {
                clearNowPlayingNotification()
                sendSuccess(requestId, buildJsonObject { put("cleared", true) })
            }
            "media.playNative" -> handlePlayNativeMedia(requestId, payload)
            "widget.update" -> executor.execute { handleWidgetUpdate(requestId, payload) }
            "widget.remove" -> executor.execute { handleWidgetRemove(requestId, payload) }
            "widget.list" -> executor.execute { handleWidgetList(requestId) }
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
            "native.audio.lyrics",
            "native.audio.customActions",
            "native.audio.systemVolume",
            "native.audio.spectrum",
            "native.widget",
            "media.playNative",
            "device.info",
            "device.permission",
            "device.overlay",
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
            "overlay" -> {
                val canDraw = AndroidPluginCapsuleManager.canDrawSystemOverlays(appContext)
                if (!canDraw && shouldRequest) {
                    AndroidPluginCapsuleManager.openOverlayPermissionSettings(appContext)
                }
                sendSuccess(
                    requestId,
                    buildJsonObject {
                        put("permission", perm)
                        put("status", if (canDraw) "granted" else "denied")
                    },
                )
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
        val specConfig = payload["spectrum"] as? JsonObject
        val reqSpecEnabled = (specConfig?.get("enabled") as? JsonPrimitive)?.booleanOrNull ?: false
        val reqSpecBands = ((specConfig?.get("bands") as? JsonPrimitive)?.intOrNull ?: 64).coerceIn(16, 256)
        val reqSpecIntervalMs = ((specConfig?.get("intervalMs") as? JsonPrimitive)?.intOrNull ?: 50).coerceIn(30, 250).toLong()

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
            rawApi.isNotBlank() || rawUrl.startsWith("/") -> {
                val candidatePath = rawApi.ifBlank { rawUrl }
                val normalized = RustCoreBridge.validatePluginApiPath(candidatePath)
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
                val sess = sessionProvider()
                if (sess != null && RustCoreBridge.containsUrl(sess.serverUrl, rawUrl)) {
                    headers = buildAuthHeaders(sess)
                }
            }
            else -> {
                sendError(requestId, "INVALID_AUDIO_SOURCE", 400, "请提供 url、base64、apiPath 或 storage+path 音频源")
                return
            }
        }

        mainHandler.post {
            stopInlinePlayback(emitEvent = false)
            val playId = "play_${UUID.randomUUID().toString().take(12)}"
            val isLocalTempSource = tempFile != null
            playbackId = playId
            playbackTempFile = tempFile
            playbackLoop = loop
            playbackVolume = volume
            playbackRate = rate
            playbackDesiredPlaying = true
            isMediaBuffering = !isLocalTempSource
            isSeekPending = false
            hasRenderedAudioSinceStartOrSeek = isLocalTempSource
            playbackAnchorPositionMs = startPosMs
            pinnedBufferingPositionMs = startPosMs
            playbackState = "buffering"
            spectrumEnabled = reqSpecEnabled
            spectrumBands = reqSpecBands
            spectrumIntervalMs = reqSpecIntervalMs

            // 起播缓冲阶段先把状态栏播控与前端状态置于 buffering（speed=0f），防止未出声期间进度条提前空跑。
            if (showInStatusBar && playTitle.isNotBlank()) {
                applyNowPlayingNotification(
                    title = playTitle,
                    artist = playArtist,
                    album = playAlbum,
                    artworkUrl = playArtworkUrl,
                    durationMs = null,
                    positionMs = startPosMs.toLong(),
                    isPlaying = true,
                    rate = rate,
                    canNext = false,
                    canPrevious = false,
                    canSeek = true,
                )
            }
            emitPlaybackState()

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
                    setOnInfoListener { player, what, _ ->
                        if (playbackId != playId) return@setOnInfoListener false
                        when (what) {
                            MediaPlayer.MEDIA_INFO_BUFFERING_START -> {
                                if (playbackDesiredPlaying) {
                                    isMediaBuffering = true
                                    pinnedBufferingPositionMs = runCatching { player.currentPosition }
                                        .getOrDefault(pinnedBufferingPositionMs)
                                        .coerceAtLeast(0)
                                    if (playbackState != "buffering") {
                                        playbackState = "buffering"
                                        releaseVisualizer()
                                        emitPlaybackState()
                                    }
                                }
                            }
                            MediaPlayer.MEDIA_INFO_BUFFERING_END -> {
                                isMediaBuffering = false
                                maybePromoteBufferingToPlaying(player)
                            }
                            MEDIA_INFO_AUDIO_RENDERING_START_CODE -> {
                                hasRenderedAudioSinceStartOrSeek = true
                                isMediaBuffering = false
                                maybePromoteBufferingToPlaying(player)
                            }
                        }
                        false
                    }
                    setOnSeekCompleteListener { player ->
                        if (playbackId != playId) return@setOnSeekCompleteListener
                        isSeekPending = false
                        val settledPos = runCatching { player.currentPosition }
                            .getOrDefault(pinnedBufferingPositionMs)
                            .coerceAtLeast(0)
                        playbackAnchorPositionMs = settledPos
                        pinnedBufferingPositionMs = settledPos
                        maybePromoteBufferingToPlaying(player)
                    }
                    setOnPreparedListener { player ->
                        if (playbackId != playId) return@setOnPreparedListener
                        isMediaBuffering = false
                        if (startPosMs > 0) {
                            isSeekPending = !isLocalTempSource
                            playbackAnchorPositionMs = startPosMs
                            pinnedBufferingPositionMs = startPosMs
                            runCatching { player.seekTo(startPosMs) }
                        } else {
                            playbackAnchorPositionMs = 0
                            pinnedBufferingPositionMs = 0
                        }
                        if (rate != 1.0f) {
                            runCatching { player.playbackParams = player.playbackParams.setSpeed(rate) }
                        }
                        if (playbackDesiredPlaying) {
                            player.start()
                        }
                        playbackState = when {
                            !playbackDesiredPlaying -> "paused"
                            isLocalTempSource -> "playing"
                            hasRenderedAudioSinceStartOrSeek && !isSeekPending && !isMediaBuffering -> "playing"
                            else -> "buffering"
                        }
                        startPlaybackProgressTicker()
                        val specActive = syncVisualizerState()
                        val durMs = player.duration.coerceAtLeast(0)
                        if (showInStatusBar && playTitle.isNotBlank()) {
                            applyNowPlayingNotification(
                                title = playTitle,
                                artist = playArtist,
                                album = playAlbum,
                                artworkUrl = playArtworkUrl,
                                durationMs = durMs.toLong(),
                                positionMs = pinnedBufferingPositionMs.toLong(),
                                isPlaying = playbackDesiredPlaying,
                                rate = rate,
                                canNext = nowPlayingCanNext,
                                canPrevious = nowPlayingCanPrevious,
                                canSeek = true,
                            )
                        }
                        emitPlaybackState()
                        sendSuccess(
                            requestId,
                            buildJsonObject {
                                put("playbackId", playId)
                                put("state", playbackState)
                                put("durationMs", durMs)
                                put("spectrumActive", specActive)
                            },
                        )
                    }
                    setOnCompletionListener { player ->
                        if (playbackId != playId) return@setOnCompletionListener
                        if (!playbackLoop) {
                            playbackDesiredPlaying = false
                            isMediaBuffering = false
                            isSeekPending = false
                            playbackState = "ended"
                            stopPlaybackProgressTicker()
                            releaseVisualizer()
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
                            playbackDesiredPlaying = false
                            isMediaBuffering = false
                            isSeekPending = false
                            playbackState = "error"
                            stopPlaybackProgressTicker()
                            releaseVisualizer()
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

    /** 当网络流完成缓冲且真正开始消费 PCM 音频帧后，将状态从 `buffering` 切换为 `playing` 并恢复通知栏进度推进。 */
    private fun maybePromoteBufferingToPlaying(player: MediaPlayer) {
        if (!playbackDesiredPlaying || isMediaBuffering || isSeekPending) return
        val isActuallyPlaying = runCatching { player.isPlaying }.getOrDefault(false)
        if (!isActuallyPlaying) return
        val curPos = runCatching { player.currentPosition }.getOrDefault(pinnedBufferingPositionMs).coerceAtLeast(0)
        val hasAdvanced = curPos > playbackAnchorPositionMs + 15
        if (hasRenderedAudioSinceStartOrSeek || playbackTempFile != null || hasAdvanced) {
            hasRenderedAudioSinceStartOrSeek = true
            pinnedBufferingPositionMs = curPos
            if (playbackState != "playing") {
                playbackState = "playing"
                syncVisualizerState()
                emitPlaybackState()
            }
        }
    }

    private fun handleAudioPause(requestId: String) {
        playbackDesiredPlaying = false
        mediaPlayer?.let {
            pinnedBufferingPositionMs = runCatching { it.currentPosition }.getOrDefault(pinnedBufferingPositionMs).coerceAtLeast(0)
            if (runCatching { it.isPlaying }.getOrDefault(false)) {
                runCatching { it.pause() }
            }
            playbackState = "paused"
        }
        releaseVisualizer()
        emitPlaybackState()
        sendSuccess(requestId, currentPlaybackStatusJson())
    }

    private fun handleAudioResume(requestId: String) {
        playbackDesiredPlaying = true
        mediaPlayer?.let {
            val curPos = runCatching { it.currentPosition }.getOrDefault(pinnedBufferingPositionMs).coerceAtLeast(0)
            playbackAnchorPositionMs = curPos
            pinnedBufferingPositionMs = curPos
            runCatching { it.start() }
            playbackState = if (isMediaBuffering || isSeekPending) "buffering" else "playing"
            startPlaybackProgressTicker()
            syncVisualizerState()
        }
        emitPlaybackState()
        sendSuccess(requestId, currentPlaybackStatusJson())
    }

    private fun handleAudioSeek(requestId: String, payload: JsonObject) {
        val posMs = ((payload["positionMs"] as? JsonPrimitive)?.intOrNull ?: 0).coerceAtLeast(0)
        performInlineSeek(posMs)
        sendSuccess(requestId, currentPlaybackStatusJson())
    }

    /** 执行音频跳转：在线流跳转未完成前钉住 `pinnedBufferingPositionMs` 并置为 `buffering`，防止通知栏与前端提前空走。 */
    private fun performInlineSeek(posMs: Int) {
        val clampedPos = posMs.coerceAtLeast(0)
        pinnedBufferingPositionMs = clampedPos
        playbackAnchorPositionMs = clampedPos
        nowPlayingPositionMs = clampedPos.toLong()
        val mp = mediaPlayer
        if (mp != null) {
            val isRemoteStream = playbackTempFile == null
            if (isRemoteStream && playbackDesiredPlaying) {
                isSeekPending = true
                hasRenderedAudioSinceStartOrSeek = false
                playbackState = "buffering"
                releaseVisualizer()
            }
            runCatching { mp.seekTo(clampedPos) }
            if (playbackDesiredPlaying) {
                startPlaybackProgressTicker()
            }
            emitPlaybackState()
        }
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
        releaseVisualizer()
        spectrumEnabled = false
        playbackDesiredPlaying = false
        isMediaBuffering = false
        isSeekPending = false
        hasRenderedAudioSinceStartOrSeek = false
        playbackAnchorPositionMs = 0
        pinnedBufferingPositionMs = 0
        nowPlayingExplicitBuffering = false
        runCatching { mediaPlayer?.stop() }
        runCatching { mediaPlayer?.release() }
        mediaPlayer = null
        runCatching { playbackTempFile?.delete() }
        playbackTempFile = null
        playbackId = null
        playbackState = "idle"
        AndroidPluginCapsuleManager.syncAudioPlaybackState(
            context = appContext,
            pluginId = activePluginId,
            isPlaying = false,
        )
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

    /** 动态开启、关闭或更新实时音频频谱分析配置（`audio.setSpectrum`）。 */
    private fun handleAudioSetSpectrum(requestId: String, payload: JsonObject) {
        val nextEnabled = (payload["enabled"] as? JsonPrimitive)?.booleanOrNull ?: spectrumEnabled
        val nextBands = ((payload["bands"] as? JsonPrimitive)?.intOrNull ?: spectrumBands).coerceIn(16, 256)
        val nextIntervalMs = ((payload["intervalMs"] as? JsonPrimitive)?.intOrNull ?: spectrumIntervalMs.toInt())
            .coerceIn(30, 250)
            .toLong()
        val intervalChanged = nextIntervalMs != spectrumIntervalMs
        spectrumEnabled = nextEnabled
        spectrumBands = nextBands
        spectrumIntervalMs = nextIntervalMs
        if (intervalChanged && visualizer != null) {
            releaseVisualizer()
        }
        val active = syncVisualizerState()
        sendSuccess(
            requestId,
            buildJsonObject {
                put("spectrumActive", active)
                put("bands", spectrumBands)
                put("intervalMs", spectrumIntervalMs.toInt())
            },
        )
    }

    /**
     * 按当前播放状态与 `RECORD_AUDIO` 权限挂载或释放系统 `Visualizer`：
     * 未获麦克风权限或系统音效驱动异常时静默降级返回 `false`，绝不主动弹窗或打断正常音频播放。
     */
    private fun syncVisualizerState(): Boolean {
        if (!spectrumEnabled || playbackState != "playing") {
            releaseVisualizer()
            return false
        }
        val mp = mediaPlayer ?: run {
            releaseVisualizer()
            return false
        }
        val hasMicPerm = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasMicPerm) {
            releaseVisualizer()
            return false
        }
        visualizer?.let { existing ->
            val ok = runCatching {
                if (!existing.enabled) existing.enabled = true
                true
            }.getOrDefault(false)
            if (ok) return true
            releaseVisualizer()
        }
        val sessionId = runCatching { mp.audioSessionId }.getOrDefault(0)
        if (sessionId <= 0) return false

        return runCatching {
            val vis = Visualizer(sessionId)
            vis.enabled = false
            val sizeRange = Visualizer.getCaptureSizeRange()
            val targetSize = 1024.coerceIn(sizeRange[0], sizeRange[1])
            vis.captureSize = targetSize
            val maxRate = Visualizer.getMaxCaptureRate().coerceAtLeast(4_000)
            val desiredRateMilliHz = (1_000_000L / spectrumIntervalMs.coerceIn(30L, 250L))
                .toInt()
                .coerceIn(4_000, maxRate)
            vis.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        v: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int,
                    ) {
                        if (waveform == null || waveform.isEmpty()) return
                        val levels = computeStereoLevelsFromWaveform(waveform)
                        latestLeftLevel = levels.first
                        latestRightLevel = levels.second
                    }

                    override fun onFftDataCapture(
                        v: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int,
                    ) {
                        if (fft == null || fft.size < 4 || !spectrumEnabled) return
                        val nowElapsed = SystemClock.elapsedRealtime()
                        if (nowElapsed - lastSpectrumEmitElapsedMs < spectrumIntervalMs) return
                        lastSpectrumEmitElapsedMs = nowElapsed
                        val bands = resampleFftMagnitudes(fft, spectrumBands)
                        val left = latestLeftLevel
                        val right = latestRightLevel
                        mainHandler.post {
                            val pid = playbackId ?: return@post
                            if (!spectrumEnabled || playbackState != "playing") return@post
                            val pos = runCatching { mediaPlayer?.currentPosition ?: 0 }
                                .getOrDefault(0)
                                .coerceAtLeast(0)
                            sendDeviceEvent(
                                "audio.play.spectrum",
                                buildJsonObject {
                                    put("playbackId", pid)
                                    put("positionMs", pos)
                                    put("fft", buildJsonArray { bands.forEach { add(JsonPrimitive(it)) } })
                                    put("left", left)
                                    put("right", right)
                                },
                            )
                        }
                    }
                },
                desiredRateMilliHz,
                true,
                true,
            )
            vis.enabled = true
            visualizer = vis
            true
        }.getOrElse {
            releaseVisualizer()
            false
        }
    }

    /** 安全停止并释放底层 `Visualizer` 实例，避免后台空转耗电。 */
    private fun releaseVisualizer() {
        val vis = visualizer
        visualizer = null
        latestLeftLevel = 0
        latestRightLevel = 0
        if (vis != null) {
            runCatching { vis.enabled = false }
            runCatching { vis.setDataCaptureListener(null, 0, false, false) }
            runCatching { vis.release() }
        }
    }

    /** 从 `Visualizer` 无符号 8-bit 波形缓冲计算左右声道 RMS 电平（映射至 `0..255`）。 */
    private fun computeStereoLevelsFromWaveform(waveform: ByteArray): Pair<Int, Int> {
        var sumLeftSq = 0.0
        var sumRightSq = 0.0
        var countLeft = 0
        var countRight = 0
        for (i in waveform.indices) {
            val centered = ((waveform[i].toInt() and 0xFF) - 128) / 128.0
            if ((i and 1) == 0) {
                sumLeftSq += centered * centered
                countLeft++
            } else {
                sumRightSq += centered * centered
                countRight++
            }
        }
        val leftRms = if (countLeft > 0) sqrt(sumLeftSq / countLeft) else 0.0
        val rightRms = if (countRight > 0) sqrt(sumRightSq / countRight) else leftRms
        val leftInt = (leftRms.pow(0.65) * 320.0).roundToInt().coerceIn(0, 255)
        val rightInt = (rightRms.pow(0.65) * 320.0).roundToInt().coerceIn(0, 255)
        return leftInt to rightInt
    }

    /** 将 `Visualizer` 复数 FFT 字节数组对数分频重采样为 `bandCount` 个 `0..255` 频段幅值。 */
    private fun resampleFftMagnitudes(fft: ByteArray, bandCount: Int): IntArray {
        val numBins = (fft.size / 2).coerceAtLeast(2)
        val mags = FloatArray(numBins)
        mags[0] = kotlin.math.abs(fft[0].toInt()).toFloat()
        mags[numBins - 1] = kotlin.math.abs(fft[1].toInt()).toFloat()
        for (k in 1 until (numBins - 1)) {
            val re = fft[2 * k].toFloat()
            val im = fft[2 * k + 1].toFloat()
            mags[k] = hypot(re, im)
        }
        val out = IntArray(bandCount)
        val usableBins = (numBins - 1).coerceAtLeast(1)
        val logMax = ln((usableBins + 1).toDouble())
        for (b in 0 until bandCount) {
            val t0 = b.toDouble() / bandCount.toDouble()
            val t1 = (b + 1).toDouble() / bandCount.toDouble()
            val startBin = (kotlin.math.exp(t0 * logMax) - 1.0).toInt().coerceIn(1, usableBins)
            val endBin = (kotlin.math.exp(t1 * logMax) - 1.0).toInt().coerceAtLeast(startBin).coerceAtMost(usableBins)
            var peak = 0f
            for (idx in startBin..endBin) {
                if (mags[idx] > peak) peak = mags[idx]
            }
            val db = if (peak > 0.5f) 20.0 * log10(peak / 128.0 + 1e-4) else -60.0
            val normalized = ((db + 42.0) / 42.0).coerceIn(0.0, 1.0)
            out[b] = (normalized * 255.0).roundToInt().coerceIn(0, 255)
        }
        return out
    }

    // MARK: - System Media Volume (`audio.getSystemVolume` / `audio.setSystemVolume` / `audio.systemVolume`)

    /** 读取系统 `STREAM_MUSIC` 当前媒体音量与静音状态。 */
    private fun readSystemVolumeJson(): JsonObject {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return buildJsonObject {
                put("volume", 1.0)
                put("muted", false)
                put("currentSteps", 15)
                put("maxSteps", 15)
            }
        val maxSteps = runCatching { am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(15).coerceAtLeast(1)
        val minSteps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            runCatching { am.getStreamMinVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(0).coerceAtLeast(0)
        } else {
            0
        }
        val currentSteps = runCatching { am.getStreamVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(0)
        val muted = runCatching { am.isStreamMute(AudioManager.STREAM_MUSIC) }.getOrDefault(false) || currentSteps <= minSteps
        val span = (maxSteps - minSteps).coerceAtLeast(1)
        val normalized = if (muted && currentSteps <= minSteps) {
            0.0
        } else {
            ((currentSteps - minSteps).toDouble() / span.toDouble()).coerceIn(0.0, 1.0)
        }
        return buildJsonObject {
            put("volume", normalized)
            put("muted", muted)
            put("currentSteps", currentSteps)
            put("maxSteps", maxSteps)
        }
    }

    /** 处理前端读取系统媒体音量请求。 */
    private fun handleGetSystemVolume(requestId: String) {
        sendSuccess(requestId, readSystemVolumeJson())
    }

    /** 处理前端调节系统媒体音量请求（支持可选弹出系统音量条）。 */
    private fun handleSetSystemVolume(requestId: String, payload: JsonObject) {
        val target = ((payload["volume"] as? JsonPrimitive)?.doubleOrNull ?: 0.5).coerceIn(0.0, 1.0)
        val showUI = (payload["showUI"] as? JsonPrimitive)?.booleanOrNull ?: false
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (am != null) {
            val maxSteps = runCatching { am.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(15).coerceAtLeast(1)
            val minSteps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                runCatching { am.getStreamMinVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(0).coerceAtLeast(0)
            } else {
                0
            }
            val span = (maxSteps - minSteps).coerceAtLeast(1)
            val targetIndex = (minSteps + (target * span).roundToInt()).coerceIn(minSteps, maxSteps)
            val flags = if (showUI) AudioManager.FLAG_SHOW_UI else 0
            runCatching {
                am.setStreamVolume(AudioManager.STREAM_MUSIC, targetIndex, flags)
            }
        }
        sendSuccess(requestId, readSystemVolumeJson())
    }

    /** 注册系统硬件音量键变化与桌面小组件自定义动作广播监听。 */
    private fun ensureSystemReceiversRegistered() {
        if (systemEventReceiver != null) return
        mainHandler.post {
            if (systemEventReceiver != null) return@post
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        VOLUME_CHANGED_ACTION -> {
                            val streamType = intent.getIntExtra(EXTRA_VOLUME_STREAM_TYPE, -1)
                            if (streamType == AudioManager.STREAM_MUSIC) {
                                val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
                                val steps = runCatching { am.getStreamVolume(AudioManager.STREAM_MUSIC) }.getOrDefault(-1)
                                val muted = runCatching { am.isStreamMute(AudioManager.STREAM_MUSIC) }.getOrDefault(false)
                                if (steps != lastObservedVolumeSteps || muted != lastObservedVolumeMuted) {
                                    lastObservedVolumeSteps = steps
                                    lastObservedVolumeMuted = muted
                                    sendDeviceEvent("audio.systemVolume", readSystemVolumeJson())
                                }
                            }
                        }
                        ACTION_WIDGET_COMMAND -> {
                            val targetPlugin = intent.getStringExtra("plugin_id")
                                ?.ifBlank { intent.getStringExtra("pluginId") }
                                ?.trim()
                                .orEmpty()
                            val currentPlugin = activePluginId.trim()
                            if (currentPlugin.isNotEmpty() &&
                                (targetPlugin.isEmpty() || targetPlugin.equals(currentPlugin, ignoreCase = true))
                            ) {
                                val widgetKey = intent.getStringExtra("widget_key")
                                    ?.ifBlank { intent.getStringExtra("widgetKey") }
                                    ?.trim()
                                    .orEmpty()
                                    .ifEmpty { "default" }
                                val actionId = intent.getStringExtra("action_id")
                                    ?.ifBlank { intent.getStringExtra("actionId") }
                                    ?.trim()
                                    .orEmpty()
                                if (actionId.isNotEmpty()) {
                                    sendDeviceEvent(
                                        "widget.action",
                                        buildJsonObject {
                                            put("pluginId", currentPlugin)
                                            put("widgetKey", widgetKey)
                                            put("actionId", actionId)
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
            val filter = IntentFilter().apply {
                addAction(VOLUME_CHANGED_ACTION)
                addAction(ACTION_WIDGET_COMMAND)
            }
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("DEPRECATION")
                    appContext.registerReceiver(receiver, filter)
                }
                systemEventReceiver = receiver
            }
        }
    }

    /** 注销系统音量与小组件动作广播监听。 */
    private fun unregisterSystemReceivers() {
        val rec = systemEventReceiver ?: return
        systemEventReceiver = null
        lastObservedVolumeSteps = -1
        lastObservedVolumeMuted = null
        runCatching { appContext.unregisterReceiver(rec) }
    }

    private fun startPlaybackProgressTicker() {
        stopPlaybackProgressTicker()
        val r = object : Runnable {
            override fun run() {
                val mp = mediaPlayer ?: return
                val pid = playbackId ?: return
                if (playbackState == "buffering" && playbackDesiredPlaying) {
                    maybePromoteBufferingToPlaying(mp)
                    mainHandler.postDelayed(this, 120L)
                    return
                }
                if (playbackState == "playing") {
                    val isActuallyPlaying = runCatching { mp.isPlaying }.getOrDefault(false)
                    if (!isActuallyPlaying || isMediaBuffering || isSeekPending) {
                        if (playbackDesiredPlaying && (isMediaBuffering || isSeekPending)) {
                            playbackState = "buffering"
                            emitPlaybackState()
                        }
                        mainHandler.postDelayed(this, 150L)
                        return
                    }
                    val pos = runCatching { mp.currentPosition }.getOrDefault(pinnedBufferingPositionMs).coerceAtLeast(0)
                    val dur = runCatching { mp.duration }.getOrDefault(0).coerceAtLeast(0)
                    pinnedBufferingPositionMs = pos
                    sendDeviceEvent(
                        "audio.play.progress",
                        buildJsonObject {
                            put("playbackId", pid)
                            put("positionMs", pos)
                            put("durationMs", dur)
                        },
                    )
                    if (nowPlayingActive && nowPlayingLyricLines.isNotEmpty()) {
                        val matched = resolveCurrentLyricLine(pos.toLong())
                        if (matched != lastDisplayedLyricLine) {
                            lastDisplayedLyricLine = matched
                            nowPlayingPositionMs = pos.toLong()
                            mediaSession?.let { sess ->
                                sess.setMetadata(buildNowPlayingMediaMetadata(dur.toLong()))
                                postMediaStyleNotification(sess, true)
                            }
                            syncNowPlayingWidgetPrefs(active = true, isPlaying = true)
                        }
                    }
                    mainHandler.postDelayed(this, 250L)
                }
            }
        }
        playbackProgressRunnable = r
        mainHandler.postDelayed(r, 120L)
    }

    private fun stopPlaybackProgressTicker() {
        playbackProgressRunnable?.let { mainHandler.removeCallbacks(it) }
        playbackProgressRunnable = null
    }

    private fun currentEffectivePlaybackPositionMs(): Int {
        if (playbackState == "buffering" || playbackState == "loading" || isSeekPending) {
            return pinnedBufferingPositionMs.coerceAtLeast(0)
        }
        val mp = mediaPlayer ?: return pinnedBufferingPositionMs.coerceAtLeast(0)
        return runCatching { mp.currentPosition }.getOrDefault(pinnedBufferingPositionMs).coerceAtLeast(0)
    }

    private fun currentPlaybackStatusJson(): JsonObject {
        val mp = mediaPlayer
        val pos = currentEffectivePlaybackPositionMs()
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
        AndroidPluginCapsuleManager.syncAudioPlaybackState(
            context = appContext,
            pluginId = activePluginId,
            isPlaying = playbackState == "playing" || (playbackDesiredPlaying && playbackState == "buffering"),
        )
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
        val capsuleTitle = payload["capsuleTitle"]?.strOrNull()?.trim()?.takeIf { it.isNotEmpty() }
        val capsuleArtist = payload["capsuleArtist"]?.strOrNull()?.trim()?.takeIf { it.isNotEmpty() }
        val artworkUrl = payload["artworkUrl"]?.strOrNull()?.trim().orEmpty()
        val durationMs = (payload["durationMs"] as? JsonPrimitive)?.doubleOrNull?.toLong()
        val positionMs = (payload["positionMs"] as? JsonPrimitive)?.doubleOrNull?.toLong()
        val explicitBuffering = (payload["isBuffering"] as? JsonPrimitive)?.booleanOrNull == true ||
            payload["state"]?.strOrNull()?.equals("buffering", ignoreCase = true) == true
        nowPlayingExplicitBuffering = explicitBuffering
        val isPlaying = (payload["isPlaying"] as? JsonPrimitive)?.booleanOrNull
            ?: (playbackState == "playing" || (playbackDesiredPlaying && playbackState == "buffering"))
        val rate = ((payload["rate"] as? JsonPrimitive)?.doubleOrNull ?: playbackRate.toDouble()).toFloat()
        val canNext = (payload["canNext"] as? JsonPrimitive)?.booleanOrNull ?: false
        val canPrevious = (payload["canPrevious"] as? JsonPrimitive)?.booleanOrNull ?: false
        val canSeek = (payload["canSeek"] as? JsonPrimitive)?.booleanOrNull ?: true
        val lyrics = payload["lyrics"]?.strOrNull()?.trim().orEmpty()
        val lyricLines = (payload["lyricLines"] as? JsonArray)?.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val tMs = (obj["timeMs"] as? JsonPrimitive)?.doubleOrNull?.toLong() ?: return@mapNotNull null
            val txt = obj["text"]?.strOrNull()?.trim().orEmpty()
            if (txt.isEmpty()) null else NowPlayingLyricLine(tMs.coerceAtLeast(0L), txt)
        }?.sortedBy { it.timeMs }.orEmpty()
        val likedExplicit = (payload["liked"] as? JsonPrimitive)?.booleanOrNull
        val customActions = (payload["customActions"] as? JsonArray)?.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val id = obj["id"]?.strOrNull()?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val label = obj["title"]?.strOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                ?: obj["label"]?.strOrNull()?.trim()?.takeIf { it.isNotEmpty() }
                ?: id
            NowPlayingCustomAction(
                id = id,
                title = label,
                icon = obj["icon"]?.strOrNull()?.trim(),
                active = (obj["active"] as? JsonPrimitive)?.booleanOrNull ?: false,
            )
        }.orEmpty()

        applyNowPlayingNotification(
            title = title,
            artist = artist,
            album = album,
            capsuleTitle = capsuleTitle,
            capsuleArtist = capsuleArtist,
            artworkUrl = artworkUrl,
            durationMs = durationMs,
            positionMs = positionMs,
            isPlaying = isPlaying,
            rate = rate,
            canNext = canNext,
            canPrevious = canPrevious,
            canSeek = canSeek,
            lyrics = lyrics,
            lyricLines = lyricLines,
            liked = likedExplicit,
            customActions = customActions,
        )
        sendSuccess(requestId, buildJsonObject { put("registered", true) })
    }

    private fun resolveCurrentLyricLine(positionMs: Long): String {
        if (nowPlayingLyricLines.isNotEmpty()) {
            val matched = nowPlayingLyricLines.lastOrNull { it.timeMs <= positionMs }?.text
            if (!matched.isNullOrBlank()) return matched
        }
        return nowPlayingLyrics
    }

    private fun resolveCustomActionIconRes(iconHint: String?, active: Boolean): Int {
        val lower = iconHint?.lowercase().orEmpty()
        return when {
            lower.contains("repeat-one") ||
                lower.contains("repeat_one") ||
                lower.contains("repeat-once") ||
                lower.contains("repeat_once") ||
                lower.contains("loop-one") ||
                lower.contains("loop_one") ||
                lower == "one" ||
                lower.endsWith("-one") ||
                lower.endsWith("_one") -> R.drawable.ic_plugin_media_repeat_one
            lower.contains("shuffle") || lower.contains("random") -> R.drawable.ic_plugin_media_shuffle
            lower.contains("repeat") || lower.contains("loop") -> R.drawable.ic_plugin_media_repeat
            lower.contains("heart") || lower.contains("like") || lower.contains("fav") ->
                if (active) R.drawable.ic_plugin_media_heart_filled else R.drawable.ic_plugin_media_heart_outline
            lower.contains("lyric") || lower.contains("lrc") -> R.drawable.ic_plugin_media_lyrics
            else -> R.drawable.ic_plugin_media_queue
        }
    }

    private fun buildNowPlayingMediaMetadata(effectiveDurationMs: Long): MediaMetadata {
        val lyricLine = lastDisplayedLyricLine
        val metaBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, nowPlayingTitle)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, nowPlayingTitle)
        if (nowPlayingArtist.isNotBlank()) metaBuilder.putString(MediaMetadata.METADATA_KEY_ARTIST, nowPlayingArtist)
        if (nowPlayingAlbum.isNotBlank()) metaBuilder.putString(MediaMetadata.METADATA_KEY_ALBUM, nowPlayingAlbum)
        if (lyricLine.isNotBlank()) {
            metaBuilder.putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, lyricLine)
            val secondaryDesc = listOf(nowPlayingArtist, nowPlayingAlbum).filter { it.isNotBlank() }.joinToString(" · ")
            if (secondaryDesc.isNotBlank()) {
                metaBuilder.putString(MediaMetadata.METADATA_KEY_DISPLAY_DESCRIPTION, secondaryDesc)
            }
        }
        if (effectiveDurationMs > 0L) metaBuilder.putLong(MediaMetadata.METADATA_KEY_DURATION, effectiveDurationMs)
        nowPlayingArtworkBitmap?.let { metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it) }
        return metaBuilder.build()
    }

    private fun buildNowPlayingPlaybackState(isPlaying: Boolean, positionMs: Long, rate: Float): PlaybackState {
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP
        if (nowPlayingCanNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (nowPlayingCanPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        if (nowPlayingCanSeek) actions = actions or PlaybackState.ACTION_SEEK_TO
        val (resolvedState, resolvedSpeed) = buildResolvedMediaSessionStateParams(
            playbackState = playbackState,
            hasInlineSession = playbackId != null,
            explicitBuffering = nowPlayingExplicitBuffering,
            requestedIsPlaying = isPlaying,
            rate = rate,
        )
        val stateBuilder = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                resolvedState,
                positionMs.coerceAtLeast(0L),
                resolvedSpeed,
            )
        if (nowPlayingHasLike) {
            stateBuilder.addCustomAction(
                PlaybackState.CustomAction.Builder(
                    CUSTOM_ACTION_TOGGLE_LIKE,
                    if (nowPlayingLiked) "取消喜欢" else "喜欢",
                    if (nowPlayingLiked) R.drawable.ic_plugin_media_heart_filled else R.drawable.ic_plugin_media_heart_outline,
                ).build(),
            )
        }
        nowPlayingCustomActions.take(3).forEach { act ->
            stateBuilder.addCustomAction(
                PlaybackState.CustomAction.Builder(
                    "$CUSTOM_ACTION_PREFIX${act.id}",
                    act.title,
                    resolveCustomActionIconRes(act.icon, act.active),
                ).build(),
            )
        }
        return stateBuilder.build()
    }

    private fun dispatchToggleLikeFromRemote() {
        nowPlayingLiked = !nowPlayingLiked
        updateNowPlayingPlaybackState()
        sendDeviceEvent(
            "audio.remoteCommand",
            buildJsonObject {
                put("command", "toggleLike")
                put("liked", nowPlayingLiked)
            },
        )
    }

    private fun dispatchCustomRemoteAction(actionId: String) {
        if (actionId.isBlank()) return
        sendDeviceEvent(
            "audio.remoteCommand",
            buildJsonObject {
                put("command", "custom")
                put("actionId", actionId)
            },
        )
    }

    /**
     * 构建指向当前运行插件页（`moviepilot://plugin/{id}?surface=data`）的 `PendingIntent`：
     * 供 `MediaSession.setSessionActivity` 与媒体通知 `contentIntent` 共用，确保点击系统状态栏/锁屏媒体卡片直达 App 内插件页面而非外部浏览器。
     */
    private fun buildPluginSessionPendingIntent(): PendingIntent? {
        val pid = activePluginId.trim()
        val intent = if (pid.isNotEmpty()) {
            Intent(Intent.ACTION_VIEW, Uri.parse("moviepilot://plugin/${Uri.encode(pid)}?surface=data"))
                .setPackage(appContext.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } else {
            appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        } ?: return null
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return runCatching { PendingIntent.getActivity(appContext, MEDIA_NOTIF_ID, intent, flags) }.getOrNull()
    }

    /**
     * 解析插件资源地址（如 `artworkUrl`）：若以 `/` 开头则使用当前会话 `serverUrl` 拼接为绝对地址并标记需附带鉴权头。
     */
    private fun resolvePluginAssetUrl(rawUrl: String): Pair<String, Boolean> {
        val trimmed = rawUrl.trim()
        if (trimmed.isEmpty()) return "" to false
        if (trimmed.startsWith("http://", ignoreCase = true) || trimmed.startsWith("https://", ignoreCase = true)) {
            val sess = sessionProvider()
            val sameOrigin = sess != null && RustCoreBridge.containsUrl(sess.serverUrl, trimmed)
            return trimmed to sameOrigin
        }
        if (trimmed.startsWith("/")) {
            val sess = sessionProvider() ?: return "" to false
            val base = sess.serverUrl.trim().trimEnd('/')
            if (base.isEmpty()) return "" to false
            return "$base$trimmed" to true
        }
        return "" to false
    }

    private fun ensureMediaSessionAndReceiver(): MediaSession {
        mediaSession?.let { existing ->
            buildPluginSessionPendingIntent()?.let { existing.setSessionActivity(it) }
            return existing
        }
        val session = MediaSession(appContext, "MoviePilotPluginAudio").apply {
            buildPluginSessionPendingIntent()?.let { setSessionActivity(it) }
            setCallback(
                object : MediaSession.Callback() {
                    override fun onPlay() {
                        mainHandler.post {
                            if (mediaPlayer != null) {
                                handleAudioResume("")
                            }
                            sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "play") })
                        }
                    }

                    override fun onPause() {
                        mainHandler.post {
                            if (mediaPlayer != null) {
                                handleAudioPause("")
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
                            nowPlayingPositionMs = targetMs
                            if (mediaPlayer != null) {
                                performInlineSeek(targetMs.toInt())
                            } else {
                                if (nowPlayingLyricLines.isNotEmpty()) {
                                    lastDisplayedLyricLine = resolveCurrentLyricLine(targetMs)
                                    mediaSession?.setMetadata(buildNowPlayingMediaMetadata(nowPlayingDurationMs))
                                }
                                updateNowPlayingPlaybackState()
                            }
                            sendDeviceEvent(
                                "audio.remoteCommand",
                                buildJsonObject {
                                    put("command", "seek")
                                    put("positionMs", targetMs)
                                },
                            )
                        }
                    }

                    override fun onCustomAction(action: String, extras: android.os.Bundle?) {
                        mainHandler.post {
                            when {
                                action == CUSTOM_ACTION_TOGGLE_LIKE -> dispatchToggleLikeFromRemote()
                                action.startsWith(CUSTOM_ACTION_PREFIX) ->
                                    dispatchCustomRemoteAction(action.removePrefix(CUSTOM_ACTION_PREFIX))
                            }
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
                            if (playbackState == "playing" || (playbackDesiredPlaying && playbackState == "buffering")) {
                                if (mediaPlayer != null) handleAudioPause("")
                                sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "pause") })
                            } else {
                                if (mediaPlayer != null) handleAudioResume("")
                                sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "play") })
                            }
                        }
                        ACTION_MEDIA_PREV -> sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "previous") })
                        ACTION_MEDIA_NEXT -> sendDeviceEvent("audio.remoteCommand", buildJsonObject { put("command", "next") })
                        ACTION_MEDIA_LIKE -> dispatchToggleLikeFromRemote()
                        ACTION_MEDIA_CUSTOM -> dispatchCustomRemoteAction(intent.getStringExtra(EXTRA_CUSTOM_ACTION_ID).orEmpty())
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
                addAction(ACTION_MEDIA_LIKE)
                addAction(ACTION_MEDIA_CUSTOM)
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
        capsuleTitle: String? = null,
        capsuleArtist: String? = null,
        artworkUrl: String,
        durationMs: Long?,
        positionMs: Long?,
        isPlaying: Boolean,
        rate: Float,
        canNext: Boolean,
        canPrevious: Boolean,
        canSeek: Boolean,
        lyrics: String = "",
        lyricLines: List<NowPlayingLyricLine> = emptyList(),
        liked: Boolean? = null,
        customActions: List<NowPlayingCustomAction> = emptyList(),
    ) {
        nowPlayingActive = true
        nowPlayingTitle = title
        nowPlayingArtist = artist
        nowPlayingAlbum = album
        nowPlayingCanNext = canNext
        nowPlayingCanPrevious = canPrevious
        nowPlayingCanSeek = canSeek
        if (lyrics.isNotEmpty() || lyricLines.isNotEmpty()) {
            nowPlayingLyrics = lyrics
            if (lyricLines.isNotEmpty()) {
                nowPlayingLyricLines = lyricLines
            }
        }
        if (liked != null) {
            nowPlayingHasLike = true
            nowPlayingLiked = liked
        }
        if (customActions.isNotEmpty()) {
            nowPlayingCustomActions = customActions
        }

        val session = ensureMediaSessionAndReceiver()
        val effectiveDur = durationMs ?: runCatching { mediaPlayer?.duration?.toLong() ?: nowPlayingDurationMs }.getOrDefault(nowPlayingDurationMs)
        val effectivePos = positionMs ?: runCatching { mediaPlayer?.currentPosition?.toLong() ?: nowPlayingPositionMs }.getOrDefault(nowPlayingPositionMs)
        nowPlayingDurationMs = effectiveDur
        nowPlayingPositionMs = effectivePos
        lastDisplayedLyricLine = resolveCurrentLyricLine(effectivePos)

        val (resolvedArtworkUrl, attachArtworkAuth) = resolvePluginAssetUrl(artworkUrl)
        if (resolvedArtworkUrl.isBlank() || resolvedArtworkUrl != nowPlayingArtworkUrl) {
            if (resolvedArtworkUrl.isBlank()) {
                nowPlayingArtworkUrl = ""
                nowPlayingArtworkBitmap = null
                nowPlayingWidgetArtworkPath = ""
            }
        }
        session.setMetadata(buildNowPlayingMediaMetadata(effectiveDur))
        session.setPlaybackState(buildNowPlayingPlaybackState(isPlaying, effectivePos, rate))
        postMediaStyleNotification(session, isPlaying)
        AndroidPluginCapsuleManager.syncAudioPlaybackState(
            context = appContext,
            pluginId = activePluginId,
            isPlaying = isPlaying,
            title = title,
            subtitle = artist,
            capsuleTitle = capsuleTitle,
            capsuleArtist = capsuleArtist,
            iconUrl = artworkUrl,
        )
        syncNowPlayingWidgetPrefs(active = true, isPlaying = isPlaying)

        if (resolvedArtworkUrl.isNotBlank() && resolvedArtworkUrl != nowPlayingArtworkUrl) {
            nowPlayingArtworkUrl = resolvedArtworkUrl
            executor.execute {
                runCatching {
                    val reqBuilder = Request.Builder().url(resolvedArtworkUrl)
                    val sess = sessionProvider()
                    if (sess != null && (attachArtworkAuth || RustCoreBridge.containsUrl(sess.serverUrl, resolvedArtworkUrl))) {
                        buildAuthHeaders(sess).forEach { (k, v) -> reqBuilder.header(k, v) }
                    }
                    okHttp.newCall(reqBuilder.build()).execute().use { resp ->
                        if (resp.isSuccessful) {
                            val bytes = resp.body?.bytes()
                            val bmp = if (bytes != null && bytes.isNotEmpty()) {
                                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            } else null
                            if (bmp != null) {
                                val savedPath = saveWidgetArtworkJpeg(bmp, "now_playing.jpg")
                                mainHandler.post {
                                    if (nowPlayingActive && nowPlayingArtworkUrl == resolvedArtworkUrl) {
                                        nowPlayingArtworkBitmap = bmp
                                        nowPlayingWidgetArtworkPath = savedPath
                                        val currentlyPlaying = mediaSession?.controller?.playbackState?.state == PlaybackState.STATE_PLAYING ||
                                            playbackState == "playing"
                                        mediaSession?.let { activeSess ->
                                            activeSess.setMetadata(buildNowPlayingMediaMetadata(nowPlayingDurationMs))
                                            postMediaStyleNotification(activeSess, currentlyPlaying)
                                        }
                                        syncNowPlayingWidgetPrefs(active = true, isPlaying = currentlyPlaying)
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
        val isActiveOrBufferingPlay = playbackState == "playing" || (playbackDesiredPlaying && playbackState == "buffering")
        val pos = if (playbackId != null) {
            currentEffectivePlaybackPositionMs().toLong()
        } else {
            nowPlayingPositionMs
        }
        nowPlayingPositionMs = pos
        session.setPlaybackState(buildNowPlayingPlaybackState(isActiveOrBufferingPlay, pos, playbackRate))
        postMediaStyleNotification(session, isActiveOrBufferingPlay)
        syncNowPlayingWidgetPrefs(active = nowPlayingActive, isPlaying = playbackState == "playing")
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
        fun actionIntent(action: String, reqCode: Int, extraActionId: String? = null): PendingIntent =
            PendingIntent.getBroadcast(
                appContext,
                reqCode,
                Intent(action).setPackage(appContext.packageName).apply {
                    if (!extraActionId.isNullOrBlank()) putExtra(EXTRA_CUSTOM_ACTION_ID, extraActionId)
                },
                piFlags,
            )

        val artistAlbumLine = listOf(nowPlayingArtist, nowPlayingAlbum).filter { it.isNotBlank() }.joinToString(" · ")
        val contentLine = lastDisplayedLyricLine.ifBlank { artistAlbumLine.ifBlank { "插件正在播放" } }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(appContext, MEDIA_NOTIF_CHANNEL_ID)
        } else {
            Notification.Builder(appContext)
        }
        builder.setSmallIcon(R.drawable.ic_plugin_media_heart_filled)
            .setContentTitle(nowPlayingTitle)
            .setContentText(contentLine)
            .apply {
                buildPluginSessionPendingIntent()?.let { setContentIntent(it) }
                if (lastDisplayedLyricLine.isNotBlank() && artistAlbumLine.isNotBlank()) {
                    setSubText(artistAlbumLine)
                }
            }
            .setOngoing(isPlaying)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        nowPlayingArtworkBitmap?.let { builder.setLargeIcon(it) }

        val compactIndices = mutableListOf<Int>()
        var idx = 0
        if (nowPlayingHasLike) {
            builder.addAction(
                Notification.Action.Builder(
                    if (nowPlayingLiked) R.drawable.ic_plugin_media_heart_filled else R.drawable.ic_plugin_media_heart_outline,
                    if (nowPlayingLiked) "已喜欢" else "喜欢",
                    actionIntent(ACTION_MEDIA_LIKE, 10),
                ).build(),
            )
            idx++
        }
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
        if (nowPlayingHasLike && compactIndices.size < 3) {
            compactIndices.add(0, 0)
        }
        nowPlayingCustomActions.take(2).forEachIndexed { cIdx, cAct ->
            builder.addAction(
                Notification.Action.Builder(
                    resolveCustomActionIconRes(cAct.icon, cAct.active),
                    cAct.title,
                    actionIntent(ACTION_MEDIA_CUSTOM, 20 + cIdx, cAct.id),
                ).build(),
            )
        }
        builder.addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "停止", actionIntent(ACTION_MEDIA_STOP, 4)).build())

        val style = Notification.MediaStyle()
            .setMediaSession(session.sessionToken)
            .setShowActionsInCompactView(*compactIndices.take(3).toIntArray())
        builder.setStyle(style)
        runCatching { nm.notify(MEDIA_NOTIF_ID, builder.build()) }
    }

    private fun clearNowPlayingNotification() {
        val hadActiveNowPlaying = nowPlayingActive
        nowPlayingActive = false
        nowPlayingExplicitBuffering = false
        nowPlayingTitle = ""
        nowPlayingArtist = ""
        nowPlayingAlbum = ""
        nowPlayingDurationMs = 0L
        nowPlayingPositionMs = 0L
        nowPlayingLyrics = ""
        nowPlayingLyricLines = emptyList()
        lastDisplayedLyricLine = ""
        nowPlayingHasLike = false
        nowPlayingLiked = false
        nowPlayingCustomActions = emptyList()
        nowPlayingArtworkUrl = ""
        nowPlayingArtworkBitmap = null
        nowPlayingWidgetArtworkPath = ""
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
        if (hadActiveNowPlaying) {
            AndroidPluginCapsuleManager.syncAudioPlaybackState(
                context = appContext,
                pluginId = activePluginId,
                isPlaying = playbackState == "playing",
            )
            syncNowPlayingWidgetPrefs(active = false, isPlaying = false)
        }
    }

    /**
     * 供最小化胶囊（Compose 应用内浮条与系统 `WindowManager` 悬浮窗）异步加载插件封面：
     * 对 `/` 开头的相对受保护路径或同源地址自动附加当前会话凭据，解码并降采样返回 `Bitmap`。
     */
    internal fun fetchAuthenticatedBitmap(
        rawUrl: String,
        maxSidePx: Int = 192,
        onResult: (Bitmap?) -> Unit,
    ) {
        val (resolvedUrl, attachAuth) = resolvePluginAssetUrl(rawUrl)
        if (resolvedUrl.isBlank()) {
            mainHandler.post { onResult(null) }
            return
        }
        executor.execute {
            val bitmap = runCatching {
                val reqBuilder = Request.Builder().url(resolvedUrl)
                val sess = sessionProvider()
                if (sess != null && (attachAuth || RustCoreBridge.containsUrl(sess.serverUrl, resolvedUrl))) {
                    buildAuthHeaders(sess).forEach { (k, v) -> reqBuilder.header(k, v) }
                }
                okHttp.newCall(reqBuilder.build()).execute().use { resp ->
                    if (!resp.isSuccessful) return@use null
                    val bytes = resp.body?.bytes() ?: return@use null
                    if (bytes.isEmpty()) return@use null
                    decodeDownsampledBitmap(bytes, maxSidePx)
                }
            }.getOrNull()
            mainHandler.post { onResult(bitmap) }
        }
    }

    /** 按目标最大边长解码图片字节，避免大图占满内存。 */
    private fun decodeDownsampledBitmap(bytes: ByteArray, maxSidePx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w <= 0 || h <= 0) return null
        var sampleSize = 1
        while ((w / sampleSize) > maxSidePx * 2 || (h / sampleSize) > maxSidePx * 2) {
            sampleSize *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }

    /** 将位图缩放至不超过 512px 并压缩保存为小组件可读的 JPEG 文件。 */
    private fun saveWidgetArtworkJpeg(bitmap: Bitmap, fileName: String): String = runCatching {
        val dir = File(appContext.filesDir, "widget_art").apply { mkdirs() }
        val targetFile = File(dir, fileName)
        val maxDim = maxOf(bitmap.width, bitmap.height)
        val scaled = if (maxDim > 512 && maxDim > 0) {
            val ratio = 512f / maxDim.toFloat()
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * ratio).roundToInt().coerceAtLeast(1),
                (bitmap.height * ratio).roundToInt().coerceAtLeast(1),
                true,
            )
        } else {
            bitmap
        }
        FileOutputStream(targetFile).use { out ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 84, out)
        }
        if (scaled !== bitmap) {
            runCatching { scaled.recycle() }
        }
        targetFile.absolutePath
    }.getOrDefault("")

    /** 解析当前活跃插件显示名称。 */
    private fun resolveActivePluginDisplayName(): String {
        val explicit = activePluginName.trim()
        if (explicit.isNotEmpty()) return explicit
        val capsuleMatch = AndroidPluginCapsuleManager.currentSession
            ?.takeIf { it.pluginId.equals(activePluginId, ignoreCase = true) }
            ?.pluginName
            .orEmpty()
        if (capsuleMatch.isNotBlank()) return capsuleMatch
        return activePluginId.trim()
    }

    /** 同步当前播放元数据与状态至「正在播放」桌面小组件共享存储并发送广播刷新。 */
    private fun syncNowPlayingWidgetPrefs(active: Boolean, isPlaying: Boolean) {
        val pid = activePluginId.trim()
        val pname = resolveActivePluginDisplayName()
        val title = if (active) nowPlayingTitle else ""
        val artist = if (active) nowPlayingArtist else ""
        val album = if (active) nowPlayingAlbum else ""
        val lyrics = if (active) lastDisplayedLyricLine.ifBlank { nowPlayingLyrics } else ""
        val artPath = if (active) nowPlayingWidgetArtworkPath else ""
        val liked = if (active) nowPlayingLiked else false
        val hasLike = if (active) nowPlayingHasLike else false
        val canNext = if (active) nowPlayingCanNext else false
        val canPrev = if (active) nowPlayingCanPrevious else false
        val durMs = if (active) nowPlayingDurationMs.coerceAtLeast(0L) else 0L
        val posMs = if (active) {
            runCatching { mediaPlayer?.currentPosition?.toLong() ?: nowPlayingPositionMs }
                .getOrDefault(nowPlayingPositionMs)
                .coerceAtLeast(0L)
        } else {
            0L
        }
        val nowSec = System.currentTimeMillis() / 1000L
        executor.execute {
            runCatching {
                val prefs = appContext.getSharedPreferences(PREF_NOW_PLAYING_WIDGET, Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("active", active)
                    .putString("plugin_id", pid)
                    .putString("plugin_name", pname)
                    .putString("title", title)
                    .putString("artist", artist)
                    .putString("album", album)
                    .putString("lyrics", lyrics)
                    .putString("artwork_path", artPath)
                    .putBoolean("is_playing", active && isPlaying)
                    .putBoolean("liked", liked)
                    .putBoolean("has_like", hasLike)
                    .putBoolean("can_next", canNext)
                    .putBoolean("can_prev", canPrev)
                    .putLong("duration_ms", durMs)
                    .putLong("position_ms", posMs)
                    .putLong("updated_at", nowSec)
                    .apply()
                appContext.sendBroadcast(
                    Intent(ACTION_NOW_PLAYING_UPDATED).setPackage(appContext.packageName),
                )
            }
        }
    }

    // MARK: - Desktop Plugin Widget Bridge (`widget.update` / `widget.remove` / `widget.list`)

    /** 校验并规范化小组件键名。 */
    private fun normalizeWidgetKey(raw: JsonElement?): String {
        val candidate = when (raw) {
            is JsonPrimitive -> raw.content.takeIf { it != "null" }.orEmpty()
            is JsonObject -> raw["widgetKey"]?.strOrNull().orEmpty()
            else -> ""
        }.trim()
        if (candidate.isEmpty()) return "default"
        return candidate.replace(Regex("[^a-zA-Z0-9_.\\-]"), "_").take(64).ifEmpty { "default" }
    }

    /** 下载受鉴权或同源小组件图片并落盘至 `filesDir/widget_art/`。 */
    private fun cacheWidgetImageIfNeeded(rawUrl: String, filePrefix: String): String {
        val (resolvedUrl, attachAuth) = resolvePluginAssetUrl(rawUrl)
        if (resolvedUrl.isBlank()) return ""
        return runCatching {
            val reqBuilder = Request.Builder().url(resolvedUrl)
            val sess = sessionProvider()
            if (sess != null && (attachAuth || RustCoreBridge.containsUrl(sess.serverUrl, resolvedUrl))) {
                buildAuthHeaders(sess).forEach { (k, v) -> reqBuilder.header(k, v) }
            }
            okHttp.newCall(reqBuilder.build()).execute().use { resp ->
                if (!resp.isSuccessful) return@use ""
                val bytes = resp.body?.bytes() ?: return@use ""
                if (bytes.isEmpty() || bytes.size > 5 * 1024 * 1024) return@use ""
                val bmp = decodeDownsampledBitmap(bytes, 512) ?: return@use ""
                val hash = MessageDigest.getInstance("SHA-256")
                    .digest(resolvedUrl.toByteArray())
                    .take(6)
                    .joinToString("") { "%02x".format(it) }
                val saved = saveWidgetArtworkJpeg(bmp, "${filePrefix}_$hash.jpg")
                runCatching { bmp.recycle() }
                saved
            }
        }.getOrDefault("")
    }

    /** 递归校验自定义小组件布局树深度与节点上限，并预缓存图片节点。 */
    private fun validateAndTransformWidgetLayout(
        node: JsonObject,
        filePrefix: String,
        depth: Int,
        counter: IntArray,
    ): JsonObject {
        if (depth > MAX_WIDGET_LAYOUT_DEPTH) {
            throw IllegalArgumentException("小组件 layout 嵌套深度不能超过 $MAX_WIDGET_LAYOUT_DEPTH 层")
        }
        counter[0] += 1
        if (counter[0] > MAX_WIDGET_LAYOUT_NODES) {
            throw IllegalArgumentException("小组件 layout 节点总数不能超过 $MAX_WIDGET_LAYOUT_NODES 个")
        }
        val type = node["type"]?.strOrNull()?.trim().orEmpty()
        return buildJsonObject {
            for ((k, v) in node) {
                if (k == "children" && v is JsonArray) {
                    put(
                        "children",
                        buildJsonArray {
                            v.forEach { child ->
                                val childObj = child as? JsonObject
                                    ?: throw IllegalArgumentException("小组件 layout 子节点必须为对象")
                                add(validateAndTransformWidgetLayout(childObj, filePrefix, depth + 1, counter))
                            }
                        },
                    )
                } else {
                    put(k, v)
                }
            }
            if (type.equals("image", ignoreCase = true)) {
                val imgUrl = node["url"]?.strOrNull()?.trim().orEmpty()
                if (imgUrl.startsWith("/")) {
                    val localPath = cacheWidgetImageIfNeeded(imgUrl, "${filePrefix}_img")
                    if (localPath.isNotEmpty()) {
                        put("artworkPath", localPath)
                        put("localPath", localPath)
                    }
                }
            }
        }
    }

    /** 处理插件运行态推送桌面小组件数据（`widget.update`）。 */
    private fun handleWidgetUpdate(requestId: String, payload: JsonObject) {
        val pluginId = activePluginId.trim()
        if (pluginId.isEmpty()) {
            sendError(requestId, "NO_ACTIVE_PLUGIN", 400, "当前无活跃插件上下文")
            return
        }
        val widgetKey = normalizeWidgetKey(payload["widgetKey"])
        val title = payload["title"]?.strOrNull()?.trim().orEmpty()
        if (title.isEmpty()) {
            sendError(requestId, "INVALID_PARAMS", 400, "小组件 title 不能为空")
            return
        }
        val subtitle = payload["subtitle"]?.strOrNull()?.trim().orEmpty()
        val rawKind = payload["kind"]?.strOrNull()?.trim().orEmpty()
        val allowedKinds = setOf("metrics", "list", "poster", "nowPlaying", "custom")
        val kind = if (rawKind in allowedKinds) {
            rawKind
        } else if (payload["layout"] is JsonObject) {
            "custom"
        } else {
            "metrics"
        }
        val badgeText = payload["badgeText"]?.strOrNull()?.trim().orEmpty()
        val accentHex = payload["accentHex"]?.strOrNull()?.trim().orEmpty()
        val tapAction = payload["tapAction"]
        val metricsArr = buildJsonArray {
            (payload["metrics"] as? JsonArray)?.take(8)?.forEach { add(it) }
        }
        val itemsArr = buildJsonArray {
            (payload["items"] as? JsonArray)?.take(8)?.forEach { add(it) }
        }
        val safePrefix = "rt_${pluginId.replace(Regex("[^a-zA-Z0-9_]"), "_")}_$widgetKey"
        val processedLayout: JsonObject? = try {
            (payload["layout"] as? JsonObject)?.let { rawLayout ->
                validateAndTransformWidgetLayout(rawLayout, safePrefix, depth = 1, counter = intArrayOf(0))
            }
        } catch (e: IllegalArgumentException) {
            sendError(requestId, "INVALID_WIDGET_LAYOUT", 400, e.message ?: "小组件布局校验失败")
            return
        }

        val rawArtworkUrl = payload["artworkUrl"]?.strOrNull()?.trim().orEmpty()
        val cachedArtworkPath = if (rawArtworkUrl.isNotEmpty()) {
            cacheWidgetImageIfNeeded(rawArtworkUrl, safePrefix)
        } else {
            ""
        }
        val nowSec = System.currentTimeMillis() / 1000L
        val record = buildJsonObject {
            put("pluginId", pluginId)
            put("pluginName", resolveActivePluginDisplayName())
            put("widgetKey", widgetKey)
            put("title", title)
            if (subtitle.isNotEmpty()) put("subtitle", subtitle)
            put("kind", kind)
            if (badgeText.isNotEmpty()) put("badgeText", badgeText)
            if (accentHex.isNotEmpty()) put("accentHex", accentHex)
            if (tapAction != null && tapAction !is JsonNull) put("tapAction", tapAction)
            put("metrics", metricsArr)
            put("items", itemsArr)
            if (processedLayout != null) put("layout", processedLayout)
            if (rawArtworkUrl.isNotEmpty()) put("artworkUrl", rawArtworkUrl)
            if (cachedArtworkPath.isNotEmpty()) put("artworkPath", cachedArtworkPath)
            put("updatedAt", nowSec)
        }
        val encoded = record.toString()
        if (encoded.toByteArray(Charsets.UTF_8).size > MAX_WIDGET_PAYLOAD_BYTES) {
            sendError(requestId, "PAYLOAD_TOO_LARGE", 400, "小组件序列化数据超过 32 KiB 上限")
            return
        }

        val prefs = appContext.getSharedPreferences(PREF_PLUGIN_WIDGETS, Context.MODE_PRIVATE)
        val catalog = HashSet(prefs.getStringSet("rt_catalog", emptySet()) ?: emptySet())
        catalog.add("$pluginId::$widgetKey")
        prefs.edit()
            .putString("rt_${pluginId}_$widgetKey", encoded)
            .putStringSet("rt_catalog", catalog)
            .apply()

        appContext.sendBroadcast(
            Intent(ACTION_PLUGIN_WIDGET_RUNTIME_UPDATED).setPackage(appContext.packageName),
        )
        sendSuccess(
            requestId,
            buildJsonObject {
                put("updated", true)
                put("pluginId", pluginId)
                put("widgetKey", widgetKey)
                put("updatedAt", nowSec)
            },
        )
    }

    /** 移除当前插件指定的运行态桌面小组件缓存（`widget.remove`）。 */
    private fun handleWidgetRemove(requestId: String, payload: JsonObject) {
        val pluginId = activePluginId.trim()
        if (pluginId.isEmpty()) {
            sendError(requestId, "NO_ACTIVE_PLUGIN", 400, "当前无活跃插件上下文")
            return
        }
        val widgetKey = normalizeWidgetKey(payload["widgetKey"])
        val prefs = appContext.getSharedPreferences(PREF_PLUGIN_WIDGETS, Context.MODE_PRIVATE)
        val catalog = HashSet(prefs.getStringSet("rt_catalog", emptySet()) ?: emptySet())
        catalog.removeAll { it.equals("$pluginId::$widgetKey", ignoreCase = true) }
        prefs.edit()
            .remove("rt_${pluginId}_$widgetKey")
            .putStringSet("rt_catalog", catalog)
            .apply()
        appContext.sendBroadcast(
            Intent(ACTION_PLUGIN_WIDGET_RUNTIME_UPDATED).setPackage(appContext.packageName),
        )
        sendSuccess(
            requestId,
            buildJsonObject {
                put("removed", true)
                put("pluginId", pluginId)
                put("widgetKey", widgetKey)
            },
        )
    }

    /** 列出当前活跃插件已注册的所有运行态桌面小组件摘要（`widget.list`）。 */
    private fun handleWidgetList(requestId: String) {
        val pluginId = activePluginId.trim()
        if (pluginId.isEmpty()) {
            sendSuccess(requestId, buildJsonObject { put("widgets", buildJsonArray {}) })
            return
        }
        val prefs = appContext.getSharedPreferences(PREF_PLUGIN_WIDGETS, Context.MODE_PRIVATE)
        val catalog = prefs.getStringSet("rt_catalog", emptySet()) ?: emptySet()
        val prefix = "$pluginId::"
        val summaries = buildJsonArray {
            catalog.filter { it.startsWith(prefix, ignoreCase = true) }.sorted().forEach { entry ->
                val wKey = entry.substringAfter("::")
                val raw = prefs.getString("rt_${pluginId}_$wKey", null) ?: return@forEach
                val obj = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return@forEach
                add(
                    buildJsonObject {
                        put("widgetKey", obj["widgetKey"]?.strOrNull() ?: wKey)
                        put("title", obj["title"]?.strOrNull().orEmpty())
                        obj["subtitle"]?.strOrNull()?.takeIf { it.isNotEmpty() }?.let { put("subtitle", it) }
                        put("kind", obj["kind"]?.strOrNull() ?: "metrics")
                        obj["badgeText"]?.strOrNull()?.takeIf { it.isNotEmpty() }?.let { put("badgeText", it) }
                        (obj["updatedAt"] as? JsonPrimitive)?.doubleOrNull?.toLong()?.let { put("updatedAt", it) }
                    },
                )
            }
        }
        sendSuccess(requestId, buildJsonObject { put("widgets", summaries) })
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
            .apply { authHeaders.forEach { (k, v) -> header(k, v) } }
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
                            .apply { authHeaders.forEach { (k, v) -> header(k, v) } }
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
        val cookiePairs = session.originCookies
            .mapNotNull { it.substringBefore(';').trim().takeIf(String::isNotEmpty) }
        val cookieHeader = cookiePairs.joinToString("; ")
        if (cookieHeader.isNotEmpty()) map["Cookie"] = cookieHeader
        cookiePairs.firstOrNull { it.startsWith("CF_Authorization=", ignoreCase = true) }
            ?.substringAfter('=')
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.let { map["cf-access-token"] = it }
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
