package com.moviepilot.media.engine

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.view.Surface
import android.view.SurfaceHolder
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.media.ChineseSubtitleMatcher
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.PlaybackHttpDataSource
import com.moviepilot.media.PrefetchedSubtitle
import com.moviepilot.media.SubtitlePrefetcher
import com.moviepilot.rustbridge.NativeSecretStore
import dev.jdtech.mpv.MPVLib
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.roundToLong

/**
 * Android 端全能增强内核（基于 `dev.jdtech.mpv:libmpv:0.5.1`，兼容 `compileSdk 35`）：
 * - 通过 `LoopbackAuthProxy` 走本地 `127.0.0.1` 单会话随机令牌环回转发，完整复用自签名 TLS、
 *   同源 Cookie/Bearer 隔离与跨源 302 令牌剥离安全红线；
 * - 支持硬解 `mediacodec-copy` / 真正视频软解 `hwdec=no`、完整 `libass` 动漫特效字幕、PGS 图形字幕、
 *   大缓冲档位（64MiB / 180MiB）、人声压缩增强（`acompressor`）与 `0.5x~3.0x` 倍速；
 * - 内置 `SimpleBasePlayer` 桥接器接入 `MoviePilotPlaybackService`，保障通知栏/锁屏/蓝牙播控一致；
 * - 所有 `MPVLib.EventObserver` 回调统一派发回 `Looper.getMainLooper()`，原生生命周期通过串行锁防止重复初始化竞态。
 */
@OptIn(UnstableApi::class)
class MpvPlaybackEngine(
    context: Context,
    private val request: MediaPlaybackRequest,
    private val prefs: PlaybackPreferencesStore,
    initialStartPositionMs: Long,
    private val activeStreamRouteRef: AtomicReference<Pair<String, Map<String, String>>>,
    private val onStateSnapshot: (isPlaying: Boolean, positionMs: Long, durationMs: Long) -> Unit,
    private val onVideoSizeChanged: (width: Int, height: Int) -> Unit,
    private val onTracksUpdated: (audio: List<EngineTrackItem>, subtitles: List<EngineTrackItem>) -> Unit,
    private val onEnded: () -> Unit,
    private val onError: (errorCode: Int) -> Unit,
    private val prefetchedSubtitlesProvider: () -> Map<String, PrefetchedSubtitle> = { emptyMap() },
    private val selectedExternalSubKeyProvider: () -> String? = { null },
    private val deferRemoteSubtitlesToPrefetcher: Boolean = false,
) {
    private data class PendingLocalSub(
        val filePath: String,
        val title: String,
        val language: String,
        val select: Boolean,
    )

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val released = AtomicBoolean(false)
    private val engineId: Long = nextEngineId.incrementAndGet()
    private var attachedSurface: Surface? = null
    private var openContentPfd: ParcelFileDescriptor? = null

    @Volatile private var currentPlaying: Boolean = false
    @Volatile private var currentPaused: Boolean = false
    @Volatile private var currentPositionMs: Long = initialStartPositionMs.coerceAtLeast(0L)
    @Volatile private var currentDurationMs: Long = 0L
    @Volatile private var currentSpeed: Float = if (request.isAudio) 1.0f else prefs.defaultSpeed.coerceIn(0.5f, 3.0f)
    @Volatile private var enginePlaybackState: Int = Player.STATE_BUFFERING
    @Volatile private var hasLoadedFile: Boolean = false
    @Volatile private var eofObserved: Boolean = false

    private var externalSubtitlesQueued: Boolean = false
    private var initialAudioApplied: Boolean = false
    private var initialSubtitleApplied: Boolean = false
    private val pendingLocalSubs = mutableListOf<PendingLocalSub>()
    private val externalPathToTrackId = ConcurrentHashMap<String, String>()
    private var pendingSeekMs: Long = initialStartPositionMs.coerceAtLeast(0L)
    private var loopbackProxy: LoopbackAuthProxy? = null

    private inner class MpvSessionPlayer(
        private val bridgeMediaItem: MediaItem,
        private val mediaMeta: MediaMetadata,
    ) : SimpleBasePlayer(Looper.getMainLooper()) {
        fun notifyStateChanged() {
            invalidateState()
        }

        override fun getState(): State {
            val commands = Player.Commands.Builder()
                .addAll(
                    Player.COMMAND_PLAY_PAUSE,
                    Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                    Player.COMMAND_SEEK_BACK,
                    Player.COMMAND_SEEK_FORWARD,
                    Player.COMMAND_SET_SPEED_AND_PITCH,
                    Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
                    Player.COMMAND_GET_METADATA,
                )
                .build()
            val durationUs = if (this@MpvPlaybackEngine.currentDurationMs > 0L) {
                this@MpvPlaybackEngine.currentDurationMs * 1000L
            } else {
                androidx.media3.common.C.TIME_UNSET
            }
            val itemData = MediaItemData.Builder(this@MpvPlaybackEngine.request.localResumeId.ifBlank { this@MpvPlaybackEngine.request.url })
                .setMediaItem(bridgeMediaItem)
                .setMediaMetadata(mediaMeta)
                .setDurationUs(durationUs)
                .setIsSeekable(this@MpvPlaybackEngine.currentDurationMs > 0L)
                .build()
            return State.Builder()
                .setAvailableCommands(commands)
                .setPlayWhenReady(!this@MpvPlaybackEngine.currentPaused, Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
                .setPlaybackState(this@MpvPlaybackEngine.enginePlaybackState)
                .setPlaybackParameters(PlaybackParameters(this@MpvPlaybackEngine.currentSpeed))
                .setPlaylist(listOf(itemData))
                .setCurrentMediaItemIndex(0)
                .setContentPositionMs { this@MpvPlaybackEngine.currentPositionMs }
                .build()
        }

        override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
            if (playWhenReady) this@MpvPlaybackEngine.play() else this@MpvPlaybackEngine.pause()
            return Futures.immediateVoidFuture()
        }

        override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
            this@MpvPlaybackEngine.seekTo(positionMs.coerceAtLeast(0L))
            return Futures.immediateVoidFuture()
        }

        override fun handleSetPlaybackParameters(playbackParameters: PlaybackParameters): ListenableFuture<*> {
            this@MpvPlaybackEngine.setSpeed(playbackParameters.speed)
            return Futures.immediateVoidFuture()
        }
    }

    private val mpvSessionPlayer: MpvSessionPlayer

    /** 供 `PlaybackServiceBridge` 注册到系统 `MediaSession` 的 `SimpleBasePlayer` 桥接实例。 */
    val sessionPlayer: SimpleBasePlayer
        get() = mpvSessionPlayer

    private val trackJson = Json { ignoreUnknownKeys = true }

    private val observer = object : MPVLib.EventObserver {
        override fun event(eventId: Int) {
            mainHandler.post {
                if (released.get()) return@post
                when (eventId) {
                    MPVLib.MPV_EVENT_FILE_LOADED -> {
                        hasLoadedFile = true
                        eofObserved = false
                        enginePlaybackState = Player.STATE_READY
                        if (pendingSeekMs > 0L) {
                            val target = pendingSeekMs
                            pendingSeekMs = 0L
                            seekTo(target)
                        }
                        if (!externalSubtitlesQueued) {
                            externalSubtitlesQueued = true
                            attachManifestExternalSubtitles()
                        }
                        if (pendingLocalSubs.isNotEmpty()) {
                            val queued = pendingLocalSubs.toList()
                            pendingLocalSubs.clear()
                            queued.forEach { item ->
                                if (item.select) {
                                    initialSubtitleApplied = true
                                }
                                executeSubAddNow(item.filePath, item.title, item.language, item.select)
                            }
                        }
                        refreshTracksNow()
                        notifySessionAndUi()
                    }
                    MPVLib.MPV_EVENT_VIDEO_RECONFIG -> {
                        val (w, h) = withActiveMpv(0 to 0) {
                            (MPVLib.getPropertyInt("video-params/w") ?: 0) to
                                (MPVLib.getPropertyInt("video-params/h") ?: 0)
                        }
                        if (w > 0 && h > 0) {
                            onVideoSizeChanged(w, h)
                        }
                    }
                    MPVLib.MPV_EVENT_PLAYBACK_RESTART -> {
                        enginePlaybackState = Player.STATE_READY
                        notifySessionAndUi()
                    }
                    MPVLib.MPV_EVENT_END_FILE -> {
                        val nearEnd = currentDurationMs > 3_000L && currentPositionMs >= currentDurationMs - 2_000L
                        if (eofObserved || nearEnd) {
                            currentPlaying = false
                            enginePlaybackState = Player.STATE_ENDED
                            notifySessionAndUi()
                            onEnded()
                        } else if (!hasLoadedFile) {
                            currentPlaying = false
                            enginePlaybackState = Player.STATE_IDLE
                            notifySessionAndUi()
                            onError(-1)
                        }
                    }
                }
            }
        }

        override fun eventProperty(property: String) = Unit

        override fun eventProperty(property: String, value: Long) = Unit

        override fun eventProperty(property: String, value: Double) {
            mainHandler.post {
                if (released.get()) return@post
                when (property) {
                    "time-pos" -> {
                        if (value.isFinite() && value >= 0.0) {
                            currentPositionMs = (value * 1000.0).roundToLong()
                            onStateSnapshot(currentPlaying, currentPositionMs, currentDurationMs)
                        }
                    }
                    "duration" -> {
                        if (value.isFinite() && value > 0.0) {
                            currentDurationMs = (value * 1000.0).roundToLong()
                            notifySessionAndUi()
                        }
                    }
                }
            }
        }

        override fun eventProperty(property: String, value: Boolean) {
            mainHandler.post {
                if (released.get()) return@post
                when (property) {
                    "pause" -> {
                        currentPaused = value
                        currentPlaying = !value && enginePlaybackState != Player.STATE_ENDED
                        notifySessionAndUi()
                    }
                    "paused-for-cache" -> {
                        if (value && enginePlaybackState == Player.STATE_READY) {
                            enginePlaybackState = Player.STATE_BUFFERING
                        } else if (!value && hasLoadedFile && enginePlaybackState == Player.STATE_BUFFERING) {
                            enginePlaybackState = Player.STATE_READY
                        }
                        notifySessionAndUi()
                    }
                    "eof-reached" -> {
                        eofObserved = value
                        if (value && hasLoadedFile) {
                            currentPlaying = false
                            enginePlaybackState = Player.STATE_ENDED
                            notifySessionAndUi()
                            onEnded()
                        }
                    }
                }
            }
        }

        override fun eventProperty(property: String, value: String) {
            mainHandler.post {
                if (released.get()) return@post
                if (property == "track-list") {
                    parseAndDispatchTracks(value)
                }
            }
        }
    }

    init {
        val mediaMeta = MediaMetadata.Builder()
            .setTitle(request.title)
            .setDisplayTitle(request.title)
            .apply {
                if (request.subtitle.isNotBlank()) {
                    setArtist(request.subtitle)
                    setSubtitle(request.subtitle)
                }
                if (request.albumTitle.isNotBlank()) {
                    setAlbumTitle(request.albumTitle)
                }
                request.artworkUrl?.takeIf { it.isNotBlank() }?.let {
                    setArtworkUri(Uri.parse(it))
                }
            }
            .build()
        val bridgeMediaItem = MediaItem.Builder()
            .setUri(Uri.parse(request.url))
            .setMediaMetadata(mediaMeta)
            .build()

        mpvSessionPlayer = MpvSessionPlayer(
            bridgeMediaItem = bridgeMediaItem,
            mediaMeta = mediaMeta,
        )

        val initOk = synchronized(mpvLifecycleLock) {
            runCatching {
                if (mpvInitialized) {
                    runCatching { MPVLib.destroy() }
                    mpvInitialized = false
                    activeEngineId = 0L
                }
                MPVLib.create(appContext)
                configureMpvOptions()
                MPVLib.init()
                mpvInitialized = true
                activeEngineId = engineId
                MPVLib.addObserver(observer)
                MPVLib.observeProperty("time-pos", MPVLib.MPV_FORMAT_DOUBLE)
                MPVLib.observeProperty("duration", MPVLib.MPV_FORMAT_DOUBLE)
                MPVLib.observeProperty("pause", MPVLib.MPV_FORMAT_FLAG)
                MPVLib.observeProperty("paused-for-cache", MPVLib.MPV_FORMAT_FLAG)
                MPVLib.observeProperty("eof-reached", MPVLib.MPV_FORMAT_FLAG)
                MPVLib.observeProperty("track-list", MPVLib.MPV_FORMAT_STRING)
                true
            }.getOrDefault(false)
        }

        if (initOk) {
            loadCurrentTarget(request.url)
        } else {
            released.set(true)
            enginePlaybackState = Player.STATE_IDLE
            mainHandler.post { onError(-2) }
        }
    }

    private inline fun <T> withActiveMpv(default: T, block: () -> T): T {
        if (released.get()) return default
        return synchronized(mpvLifecycleLock) {
            if (released.get() || !mpvInitialized || activeEngineId != engineId) {
                default
            } else {
                runCatching(block).getOrDefault(default)
            }
        }
    }

    private inline fun runWithActiveMpv(block: () -> Unit) {
        withActiveMpv(Unit, block)
    }

    private fun configureMpvOptions() {
        val isLargeBuffer = prefs.bufferProfile == "large"
        val isForceSw = prefs.decodeMode == "sw_force"

        MPVLib.setOptionString("vo", if (request.isAudio) "null" else "gpu")
        MPVLib.setOptionString("gpu-context", "android")
        MPVLib.setOptionString("opengl-es", "yes")
        MPVLib.setOptionString("hwdec", if (isForceSw) "no" else "mediacodec-copy")
        MPVLib.setOptionString("hwdec-codecs", "all")
        MPVLib.setOptionString("ao", "audiotrack,opensles")
        MPVLib.setOptionString("keep-open", "yes")
        MPVLib.setOptionString("force-window", "yes")
        MPVLib.setOptionString("cache", "yes")
        MPVLib.setOptionString("demuxer-max-bytes", if (isLargeBuffer) "180MiB" else "64MiB")
        MPVLib.setOptionString("demuxer-max-back-bytes", if (isLargeBuffer) "64MiB" else "32MiB")
        MPVLib.setOptionString("sub-auto", "no")
        MPVLib.setOptionString("embeddedfonts", "yes")
        MPVLib.setOptionString("sub-ass-override", if (prefs.ignoreAssStyle) "strip" else "no")
        MPVLib.setOptionString("sub-scale", "%.2f".format(prefs.subtitleScale.coerceIn(0.75f, 1.5f)))
        MPVLib.setOptionString("speed", "%.2f".format(currentSpeed))
        if (prefs.audioNightMode) {
            MPVLib.setOptionString("af", "lavfi=[acompressor=ratio=4:makeup=4]")
        }
        if (request.isAudio) {
            MPVLib.setOptionString("vid", "no")
        }
    }

    private fun loadCurrentTarget(targetUrl: String) {
        val lower = targetUrl.trim().lowercase()
        val playableUri = when {
            lower.startsWith("http://") || lower.startsWith("https://") -> {
                val proxy = ensureLoopbackProxy(targetUrl)
                proxy.updatePrimaryTarget(targetUrl, activeStreamRouteRef.get().second)
                proxy.streamUrl
            }
            lower.startsWith("content://") -> {
                runCatching {
                    openContentPfd?.close()
                    val pfd = appContext.contentResolver.openFileDescriptor(Uri.parse(targetUrl), "r")
                    openContentPfd = pfd
                    if (pfd != null) "fd://${pfd.fd}" else targetUrl
                }.getOrDefault(targetUrl)
            }
            lower.startsWith("file://") -> Uri.parse(targetUrl).path ?: targetUrl
            else -> targetUrl
        }
        enginePlaybackState = Player.STATE_BUFFERING
        currentPaused = false
        currentPlaying = true
        runWithActiveMpv {
            MPVLib.setPropertyBoolean("pause", false)
            MPVLib.command(arrayOf("loadfile", playableUri, "replace"))
        }
    }

    private fun ensureLoopbackProxy(initialUrl: String): LoopbackAuthProxy {
        loopbackProxy?.let { return it }
        val allowInsecureTls = request.allowSelfSignedTls ||
            runCatching { NativeSecretStore(appContext).allowSelfSignedTls }.getOrDefault(false)
        val effectiveOrigin = request.originUrl.ifBlank { request.url }
        val effectiveOriginHeaders = request.sameOriginHeaders.ifEmpty { request.headers }
        val okHttp = PlaybackHttpDataSource.createOkHttpClient(
            originUrl = effectiveOrigin,
            headers = effectiveOriginHeaders,
            allowSelfSignedTls = allowInsecureTls,
            streamUrl = initialUrl,
            streamHeaders = request.streamHeaders,
            activeStreamProvider = { activeStreamRouteRef.get() },
        )
        return LoopbackAuthProxy(okHttp, initialUrl, activeStreamRouteRef).also {
            loopbackProxy = it
        }
    }

    private fun attachManifestExternalSubtitles() {
        if (request.isAudio || request.subtitles.isEmpty()) return
        val prefetchedMap = prefetchedSubtitlesProvider()
        val selectedExtKey = selectedExternalSubKeyProvider()
        var proxy: LoopbackAuthProxy? = null

        val preferredNonDeferredIdx: Int? = if (!deferRemoteSubtitlesToPrefetcher && !request.disableSubtitles) {
            pickPreferredManifestSubtitleIndex()
        } else {
            null
        }

        request.subtitles.forEachIndexed { idx, sub ->
            val subUrl = sub.url.trim()
            if (subUrl.isBlank()) return@forEachIndexed
            val subKey = SubtitlePrefetcher.subtitleKey(sub)
            val prefetched = prefetchedMap[subKey]
            val localDirectPath = when {
                prefetched != null && prefetched.file.exists() -> normalizeLocalPath(prefetched.file.absolutePath)
                subUrl.startsWith("file://", ignoreCase = true) -> normalizeLocalPath(subUrl)
                subUrl.startsWith("/") -> normalizeLocalPath(subUrl)
                else -> null
            }
            val target = when {
                !localDirectPath.isNullOrBlank() -> localDirectPath
                deferRemoteSubtitlesToPrefetcher &&
                    (subUrl.startsWith("http://", ignoreCase = true) || subUrl.startsWith("https://", ignoreCase = true)) -> {
                    // 远端外挂字幕由预取器按需下载为本地真实后缀文件后动态注入，避免并发触发多次慢速字体子集化
                    return@forEachIndexed
                }
                subUrl.startsWith("http://", ignoreCase = true) || subUrl.startsWith("https://", ignoreCase = true) -> {
                    val p = proxy ?: ensureLoopbackProxy(activeStreamRouteRef.get().first).also { proxy = it }
                    p.registerAuxiliaryTarget("sub_${idx}_${sub.id}", subUrl)
                }
                else -> subUrl
            }
            val shouldSelect = !request.disableSubtitles && (
                (selectedExtKey != null && selectedExtKey == subKey) ||
                    (selectedExtKey == null && preferredNonDeferredIdx == idx)
                )
            val title = sub.title.ifBlank { sub.language.ifBlank { "外挂字幕 ${idx + 1}" } }
            val lang = sub.language.ifBlank { "und" }
            if (shouldSelect) {
                initialSubtitleApplied = true
            }
            executeSubAddNow(target, title, lang, shouldSelect)
        }
    }

    /** 按 `preferredSubtitleId` -> `preferredSubtitleLang` -> 中文偏好匹配清单中的最佳外挂字幕下标。 */
    private fun pickPreferredManifestSubtitleIndex(): Int? {
        if (!request.preferredSubtitleId.isNullOrBlank()) {
            val targetId = request.preferredSubtitleId.trim()
            val idx = request.subtitles.indexOfFirst { it.id == targetId || it.title == targetId }
            if (idx >= 0) return idx
        }
        if (!request.preferredSubtitleLang.isNullOrBlank()) {
            val targetLang = request.preferredSubtitleLang.trim().lowercase()
            val idx = request.subtitles.indexOfFirst {
                it.language.trim().lowercase() == targetLang || it.title.lowercase().contains(targetLang)
            }
            if (idx >= 0) return idx
        }
        if (prefs.preferChineseSub) {
            return request.subtitles.indices
                .map { i ->
                    val s = request.subtitles[i]
                    i to ChineseSubtitleMatcher.scoreChineseSubtitle(
                        language = s.language,
                        label = s.title,
                        isExternal = true,
                    )
                }
                .filter { it.second > 0 }
                .maxByOrNull { it.second }
                ?.first
        }
        return null
    }

    private fun normalizeLocalPath(rawPathOrUri: String): String {
        val trimmed = rawPathOrUri.trim()
        if (trimmed.isBlank()) return ""
        val path = if (trimmed.startsWith("file://", ignoreCase = true)) {
            Uri.parse(trimmed).path ?: trimmed
        } else {
            trimmed
        }
        return if (path.startsWith("/")) {
            runCatching { File(path).canonicalPath }.getOrDefault(path)
        } else {
            path
        }
    }

    private fun executeSubAddNow(
        normalizedPath: String,
        safeTitle: String,
        safeLang: String,
        select: Boolean,
    ) {
        val existingId = externalPathToTrackId[normalizedPath]
        if (existingId != null) {
            if (select) {
                runWithActiveMpv { MPVLib.setPropertyString("sid", existingId) }
            }
            return
        }
        runWithActiveMpv {
            MPVLib.command(
                arrayOf(
                    "sub-add",
                    normalizedPath,
                    if (select) "select" else "auto",
                    safeTitle,
                    safeLang,
                ),
            )
        }
    }

    /**
     * 动态挂载已预取落盘的外挂字幕文件并立即刷新轨道状态；
     * 若主媒体文件尚未完成 `MPV_EVENT_FILE_LOADED`，自动入队并在文件就绪瞬间执行挂载。
     */
    fun addExternalSubtitleFile(
        localFilePath: String,
        title: String,
        language: String,
        select: Boolean,
    ) {
        if (released.get()) return
        val normalizedPath = normalizeLocalPath(localFilePath)
        if (normalizedPath.isBlank()) return
        val safeTitle = title.ifBlank { language.ifBlank { "外挂字幕" } }
        val safeLang = language.ifBlank { "und" }
        val action = Runnable {
            if (released.get()) return@Runnable
            if (!hasLoadedFile) {
                pendingLocalSubs.removeAll { it.filePath == normalizedPath }
                if (select) {
                    for (idx in pendingLocalSubs.indices) {
                        if (pendingLocalSubs[idx].select) {
                            pendingLocalSubs[idx] = pendingLocalSubs[idx].copy(select = false)
                        }
                    }
                }
                pendingLocalSubs += PendingLocalSub(normalizedPath, safeTitle, safeLang, select)
                return@Runnable
            }
            if (select) {
                initialSubtitleApplied = true
            }
            executeSubAddNow(normalizedPath, safeTitle, safeLang, select)
            refreshTracksNow()
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action.run()
        } else {
            mainHandler.post(action)
        }
    }

    /** 根据本地字幕路径查询其在 `libmpv` 中已分配的轨道数字 ID（未挂载时返回 `null`）。 */
    fun findTrackIdForExternalFile(localFilePath: String): String? {
        val normalized = normalizeLocalPath(localFilePath)
        if (normalized.isBlank()) return null
        return externalPathToTrackId[normalized]
    }

    /** 切换至新的降级路由并重新加载流（用于直连失败自动回退后台中转）。 */
    fun reloadWithRoute(url: String, headers: Map<String, String>) {
        if (released.get()) return
        activeStreamRouteRef.set(url to headers)
        hasLoadedFile = false
        eofObserved = false
        externalSubtitlesQueued = false
        initialAudioApplied = false
        initialSubtitleApplied = false
        externalPathToTrackId.clear()
        loadCurrentTarget(url)
    }

    /** 若 `SurfaceView` 的底层表面在注册监听前已创建就绪，立即补挂渲染表面。 */
    fun attachExistingSurfaceIfReady(holder: SurfaceHolder) {
        val surface = holder.surface ?: return
        if (!surface.isValid || released.get() || request.isAudio) return
        runWithActiveMpv {
            if (attachedSurface !== surface) {
                attachedSurface = surface
                MPVLib.attachSurface(surface)
                MPVLib.setOptionString("force-window", "yes")
                MPVLib.setPropertyString("vo", "gpu")
                MPVLib.setPropertyString("vid", "auto")
                val frame = holder.surfaceFrame
                if (frame != null && frame.width() > 0 && frame.height() > 0) {
                    MPVLib.setPropertyString("android-surface-size", "${frame.width()}x${frame.height()}")
                }
            }
        }
    }

    /** 创建与 `SurfaceView` 绑定的 `SurfaceHolder.Callback`，负责 GPU 表面挂载、尺寸同步与安全解绑。 */
    fun createSurfaceCallback(): SurfaceHolder.Callback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            if (released.get() || request.isAudio) return
            val surface = holder.surface ?: return
            if (!surface.isValid) return
            runWithActiveMpv {
                attachedSurface = surface
                MPVLib.attachSurface(surface)
                MPVLib.setOptionString("force-window", "yes")
                MPVLib.setPropertyString("vo", "gpu")
                MPVLib.setPropertyString("vid", "auto")
            }
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            if (released.get() || request.isAudio) return
            if (width > 0 && height > 0) {
                runWithActiveMpv {
                    MPVLib.setPropertyString("android-surface-size", "${width}x${height}")
                }
            }
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            if (released.get() || request.isAudio) return
            runWithActiveMpv {
                if (attachedSurface === holder.surface) {
                    attachedSurface = null
                }
                MPVLib.setPropertyString("vid", "no")
                MPVLib.setPropertyString("vo", "null")
                MPVLib.setOptionString("force-window", "no")
                MPVLib.detachSurface()
            }
        }
    }

    /** 当前是否正在播放。 */
    val isPlaying: Boolean
        get() = currentPlaying

    /** 当前播放位置（毫秒）。 */
    val positionMs: Long
        get() = currentPositionMs

    /** 当前媒体总时长（毫秒）。 */
    val durationMs: Long
        get() = currentDurationMs

    /** 开始或继续播放。 */
    fun play() {
        if (released.get()) return
        currentPaused = false
        currentPlaying = true
        runWithActiveMpv { MPVLib.setPropertyBoolean("pause", false) }
        notifySessionAndUi()
    }

    /** 暂停播放。 */
    fun pause() {
        if (released.get()) return
        currentPaused = true
        currentPlaying = false
        runWithActiveMpv { MPVLib.setPropertyBoolean("pause", true) }
        notifySessionAndUi()
    }

    /** 精确跳转至指定毫秒位置。 */
    fun seekTo(targetMs: Long) {
        if (released.get()) return
        val clamped = targetMs.coerceAtLeast(0L)
        currentPositionMs = clamped
        val seconds = "%.3f".format(clamped / 1000.0)
        runWithActiveMpv { MPVLib.command(arrayOf("seek", seconds, "absolute", "exact")) }
        notifySessionAndUi()
    }

    /** 设置播放倍速（支持 `0.5x ~ 3.0x`）。 */
    fun setSpeed(speed: Float) {
        if (released.get()) return
        val clamped = speed.coerceIn(0.25f, 3.0f)
        currentSpeed = clamped
        runWithActiveMpv { MPVLib.setPropertyDouble("speed", clamped.toDouble()) }
        notifySessionAndUi()
    }

    /** 设置视频画面比例模式（`0` = 自适应，`1` = 铺满裁剪，`2` = 拉伸填充）。 */
    fun setResizeMode(modeIndex: Int) {
        if (released.get() || request.isAudio) return
        runWithActiveMpv {
            when (modeIndex) {
                1 -> {
                    MPVLib.setPropertyDouble("panscan", 1.0)
                    MPVLib.setPropertyString("keepaspect", "yes")
                }
                2 -> {
                    MPVLib.setPropertyDouble("panscan", 0.0)
                    MPVLib.setPropertyString("keepaspect", "no")
                }
                else -> {
                    MPVLib.setPropertyDouble("panscan", 0.0)
                    MPVLib.setPropertyString("keepaspect", "yes")
                }
            }
        }
    }

    /** 切换内嵌/外挂音轨（传轨道数字 ID）。 */
    fun selectAudioTrack(trackId: String) {
        if (released.get()) return
        runWithActiveMpv { MPVLib.setPropertyString("aid", trackId) }
        refreshTracksNow()
    }

    /** 切换内嵌/外挂字幕轨道（传轨道数字 ID）。 */
    fun selectSubtitleTrack(trackId: String) {
        if (released.get()) return
        runWithActiveMpv { MPVLib.setPropertyString("sid", trackId) }
        refreshTracksNow()
    }

    /** 关闭所有字幕显示。 */
    fun disableSubtitles() {
        if (released.get()) return
        runWithActiveMpv { MPVLib.setPropertyString("sid", "no") }
        refreshTracksNow()
    }

    /** 主动刷新轨道列表。 */
    fun refreshTracksNow() {
        if (released.get()) return
        val raw = withActiveMpv<String?>(null) { MPVLib.getPropertyString("track-list") } ?: return
        parseAndDispatchTracks(raw)
    }

    private fun parseAndDispatchTracks(rawJson: String, allowInitialSelection: Boolean = true) {
        val arr = runCatching { trackJson.parseToJsonElement(rawJson).jsonArray }.getOrNull() ?: return
        val audioList = mutableListOf<EngineTrackItem>()
        val subList = mutableListOf<EngineTrackItem>()
        val nextExtMap = HashMap<String, String>()
        for (el in arr) {
            val obj = runCatching { el.jsonObject }.getOrNull() ?: continue
            val type = obj["type"]?.jsonPrimitive?.content ?: continue
            val id = obj["id"]?.jsonPrimitive?.intOrNull?.toString() ?: continue
            val lang = obj["lang"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() && it != "und" }
            val title = obj["title"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
            val codec = obj["codec"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
            val selected = obj["selected"]?.jsonPrimitive?.booleanOrNull == true
            val extFile = obj["external-filename"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
            if (type == "sub" && extFile != null) {
                nextExtMap[normalizeLocalPath(extFile)] = id
            }
            val label = listOfNotNull(title, lang, codec?.uppercase()).joinToString(" · ")
                .ifBlank { if (type == "audio") "音轨 $id" else "字幕 $id" }
            when (type) {
                "audio" -> audioList += EngineTrackItem(id = id, label = label, language = lang, isSelected = selected)
                "sub" -> subList += EngineTrackItem(id = id, label = label, language = lang, isSelected = selected)
            }
        }
        externalPathToTrackId.clear()
        externalPathToTrackId.putAll(nextExtMap)

        if (allowInitialSelection && hasLoadedFile && !request.isAudio) {
            var mutatedSelection = false
            if (!initialAudioApplied && audioList.isNotEmpty()) {
                initialAudioApplied = true
                val chosenAudio = when {
                    request.preferredAudioIndex != null && request.preferredAudioIndex in audioList.indices ->
                        audioList[request.preferredAudioIndex]
                    !request.preferredAudioLang.isNullOrBlank() -> {
                        val targetLang = request.preferredAudioLang.trim().lowercase()
                        audioList.firstOrNull {
                            it.language?.lowercase() == targetLang || it.label.lowercase().contains(targetLang)
                        }
                    }
                    else -> null
                }
                if (chosenAudio != null && !chosenAudio.isSelected) {
                    runWithActiveMpv { MPVLib.setPropertyString("aid", chosenAudio.id) }
                    mutatedSelection = true
                }
            }
            if (!initialSubtitleApplied) {
                if (request.disableSubtitles) {
                    initialSubtitleApplied = true
                    if (subList.any { it.isSelected }) {
                        runWithActiveMpv { MPVLib.setPropertyString("sid", "no") }
                        mutatedSelection = true
                    }
                } else if (selectedExternalSubKeyProvider() == null && subList.isNotEmpty()) {
                    initialSubtitleApplied = true
                    val explicitSub = when {
                        !request.preferredSubtitleId.isNullOrBlank() -> {
                            val targetId = request.preferredSubtitleId.trim()
                            subList.firstOrNull { it.id == targetId || it.label.contains(targetId) }
                        }
                        !request.preferredSubtitleLang.isNullOrBlank() -> {
                            val targetLang = request.preferredSubtitleLang.trim().lowercase()
                            subList.firstOrNull {
                                it.language?.lowercase() == targetLang || it.label.lowercase().contains(targetLang)
                            }
                        }
                        else -> null
                    }
                    val chosenSub = explicitSub ?: if (prefs.preferChineseSub) {
                        val extIds = nextExtMap.values.toSet()
                        subList
                            .map { item ->
                                item to ChineseSubtitleMatcher.scoreChineseSubtitle(
                                    language = item.language,
                                    label = item.label,
                                    isExternal = item.id in extIds,
                                )
                            }
                            .filter { it.second > 0 }
                            .maxByOrNull { it.second }
                            ?.first
                    } else {
                        null
                    }
                    if (chosenSub != null && !chosenSub.isSelected) {
                        runWithActiveMpv { MPVLib.setPropertyString("sid", chosenSub.id) }
                        mutatedSelection = true
                    }
                }
            }
            if (mutatedSelection) {
                val refreshed = withActiveMpv<String?>(null) { MPVLib.getPropertyString("track-list") }
                if (refreshed != null) {
                    parseAndDispatchTracks(refreshed, allowInitialSelection = false)
                    return
                }
            }
        }

        onTracksUpdated(audioList, subList)
    }

    private fun notifySessionAndUi() {
        onStateSnapshot(currentPlaying, currentPositionMs, currentDurationMs)
        runCatching { mpvSessionPlayer.notifyStateChanged() }
    }

    /** 异步安全销毁 `libmpv` 与本地环回代理，通过代际号隔离防止新实例被旧异步销毁误伤（ABA 竞态保护）。 */
    fun release() {
        if (!released.compareAndSet(false, true)) return
        val proxyToClose = loopbackProxy
        loopbackProxy = null
        val pfdToClose = openContentPfd
        openContentPfd = null
        // 先关闭本地环回代理以立即中断起播期挂起的网络读阻塞，确保后续 MPVLib.destroy() 毫秒级返回不死锁
        runCatching { proxyToClose?.close() }
        synchronized(mpvLifecycleLock) {
            if (mpvInitialized && activeEngineId == engineId) {
                runCatching { MPVLib.removeObserver(observer) }
                if (attachedSurface != null) {
                    attachedSurface = null
                    runCatching {
                        MPVLib.setPropertyString("vid", "no")
                        MPVLib.setPropertyString("vo", "null")
                        MPVLib.detachSurface()
                    }
                }
            } else {
                attachedSurface = null
            }
        }
        teardownExecutor.execute {
            synchronized(mpvLifecycleLock) {
                if (mpvInitialized && activeEngineId == engineId) {
                    runCatching { MPVLib.command(arrayOf("stop")) }
                    runCatching { MPVLib.destroy() }
                    mpvInitialized = false
                    activeEngineId = 0L
                }
            }
            runCatching { pfdToClose?.close() }
        }
    }

    companion object {
        private val mpvLifecycleLock = Any()
        private val nextEngineId = AtomicLong(0L)
        @Volatile private var mpvInitialized: Boolean = false
        @Volatile private var activeEngineId: Long = 0L
        private val teardownExecutor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "mp-mpv-teardown").apply { isDaemon = true }
        }
    }
}
