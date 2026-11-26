package com.moviepilot.rustbridge

import android.content.Context
import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

/**
 * 单次播放会话状态机持有器：封装 `RustCoreBridge.planPlaybackSyncStep`，供视频与后台音频播放器统一驱动。
 */
class PlaybackSyncSessionTracker(
    val playSessionId: String = "",
) {
    private val lock = Any()
    private var state = PlaybackSyncStateDto(playSessionId = playSessionId)

    /** 在锁内推进一次共享状态机，防止播放器事件和后台终态并发修改序号。 */
    fun step(
        trigger: String,
        positionMs: Long,
        durationMs: Long?,
        isPaused: Boolean,
        nowMs: Long = System.currentTimeMillis(),
        audioStreamIndex: Int? = null,
        subtitleStreamIndex: Int? = null,
    ): PlaybackSyncDecisionDto = synchronized(lock) {
        val decision = RustCoreBridge.planPlaybackSyncStep(
            state = state,
            input = PlaybackSyncInputDto(
                trigger = trigger,
                nowMs = nowMs,
                positionMs = positionMs.coerceAtLeast(0L),
                durationMs = durationMs?.takeIf { it > 0L },
                isPaused = isPaused,
                audioStreamIndex = audioStreamIndex,
                subtitleStreamIndex = subtitleStreamIndex,
            ),
        )
        state = decision.nextState
        decision
    }

    /** 判断终态是否已发送，供播放生命周期避免重复停止。 */
    fun isStopped(): Boolean = synchronized(lock) { state.stoppedSent }
}

/**
 * App 级播放进度与实时会话上报器：
 * - 独立 `SupervisorJob` 作用域 + 串行 `Mutex`，退出播放页时绝不取消在途 `stopped` 终态上报；
 * - 持久化匿名 `client_id` 与离线待补报 `stopped` 队列（7 天过期 / 上限 30 条）；
 * - 每次成功上报终态 `stopped` 后通过 `playbackStoppedEvents` 通知详情页与发现页静默刷新进度。
 */
class PlaybackProgressReporter(
    private val appContext: Context,
) {
    private val prefs by lazy {
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }
    private val reporterScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val submitMutex = Mutex()
    private val pendingLock = Any()

    private val _playbackStoppedEvents = MutableSharedFlow<Pair<String, String>>(extraBufferCapacity = 16)
    val playbackStoppedEvents: SharedFlow<Pair<String, String>> = _playbackStoppedEvents.asSharedFlow()

    val clientId: String
        get() {
            val existing = runCatching { prefs.getString(KEY_CLIENT_ID, null) }.getOrNull()
            if (!existing.isNullOrBlank()) return existing
            val generated = UUID.randomUUID().toString().lowercase()
            runCatching { prefs.edit().putString(KEY_CLIENT_ID, generated).apply() }
            return generated
        }

    val deviceName: String
        get() {
            val manufacturer = Build.MANUFACTURER.orEmpty().trim()
            val model = Build.MODEL.orEmpty().trim()
            return when {
                model.isBlank() -> "Android"
                manufacturer.isNotBlank() && !model.startsWith(manufacturer, ignoreCase = true) ->
                    "$manufacturer $model"
                else -> model
            }
        }

    val appVersion: String
        get() = runCatching {
            val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
            info.versionName?.takeIf { it.isNotBlank() } ?: "2.0.3"
        }.getOrDefault("2.0.3")

    /** 请求 `/stream-info` 时附加的客户端设备上下文请求头。 */
    fun clientHeaders(): Map<String, String> = mapOf(
        "X-MP-Client-Id" to clientId,
        "X-MP-Device-Name" to deviceName,
        "X-MP-Platform" to "Android",
        "X-MP-App-Version" to appVersion,
    )

    /** 将状态机产出的一条待上报决策串行发送至后端，失败的 `stopped` 自动落入离线补报队列。 */
    fun enqueueDecision(
        repository: MoviePilotRepository,
        itemId: String,
        server: String,
        mediaSourceId: String?,
        decision: PlaybackSyncDecisionDto,
        playSessionId: String?,
        durationMs: Long?,
        playMethod: String = "DirectPlay",
        audioStreamIndex: Int? = null,
        subtitleStreamIndex: Int? = null,
    ): Job? {
        if (!decision.shouldReport) return null
        val cleanItem = itemId.trim()
        val cleanServer = server.trim()
        if (
            cleanItem.isEmpty() ||
            cleanServer.isEmpty() ||
            cleanItem.startsWith("file.") ||
            cleanItem.startsWith("file:") ||
            cleanItem.startsWith("local:") ||
            cleanItem.startsWith("external:")
        ) {
            return null
        }
        val auth = repository.session.value as? SessionState.Authenticated ?: return null
        val storageKey = repository.playbackStorageKey(auth) ?: return null
        val cid = clientId
        val dev = deviceName
        val ver = appVersion
        val isStop = decision.state == "stopped"
        return reporterScope.launch {
            submitMutex.withLock {
                val ok = repository.reportMediaPlaybackProgress(
                    itemId = cleanItem,
                    server = cleanServer,
                    positionMs = decision.positionMs,
                    durationMs = durationMs ?: 0L,
                    isPaused = decision.isPaused,
                    state = decision.state,
                    mediaSourceId = mediaSourceId?.takeIf { it.isNotBlank() },
                    eventName = decision.eventName,
                    playSessionId = playSessionId?.takeIf { it.isNotBlank() },
                    clientId = cid,
                    deviceName = dev,
                    platform = "Android",
                    appVersion = ver,
                    playMethod = playMethod,
                    playbackTimeMs = decision.playbackTimeMs,
                    audioStreamIndex = audioStreamIndex,
                    subtitleStreamIndex = subtitleStreamIndex,
                    seq = decision.seq,
                    expectedSession = auth,
                )
                if (isStop) {
                    if (ok) {
                        _playbackStoppedEvents.tryEmit(cleanServer to cleanItem)
                    } else {
                        recordPendingStop(
                            PendingPlaybackStopDto(
                                server = cleanServer,
                                itemId = cleanItem,
                                mediaSourceId = mediaSourceId?.takeIf { it.isNotBlank() },
                                positionMs = decision.positionMs,
                                durationMs = durationMs?.takeIf { it > 0L },
                                playSessionId = playSessionId?.takeIf { it.isNotBlank() },
                                playbackTimeMs = decision.playbackTimeMs,
                                seq = decision.seq,
                                updatedAtMs = System.currentTimeMillis(),
                            ), storageKey,
                        )
                    }
                }
            }
        }
    }

    /** 在下次起播或网络恢复时串行补报此前离线失败的 `stopped` 终态记录。 */
    fun flushPendingStops(repository: MoviePilotRepository): Job? {
        val auth = repository.session.value as? SessionState.Authenticated ?: return null
        val storageKey = repository.playbackStorageKey(auth) ?: return null
        val cid = clientId
        val dev = deviceName
        val ver = appVersion
        return reporterScope.launch {
            submitMutex.withLock {
                val currentPending = loadPendingStops(storageKey)
                if (currentPending.isEmpty()) return@withLock
                val remaining = mutableListOf<PendingPlaybackStopDto>()
                var flushedLast: Pair<String, String>? = null
                for (entry in currentPending) {
                    val ok = repository.reportMediaPlaybackProgress(
                        itemId = entry.itemId,
                        server = entry.server,
                        positionMs = entry.positionMs,
                        durationMs = entry.durationMs ?: 0L,
                        isPaused = true,
                        state = "stopped",
                        mediaSourceId = entry.mediaSourceId,
                        eventName = null,
                        playSessionId = entry.playSessionId,
                        clientId = cid,
                        deviceName = dev,
                        platform = "Android",
                        appVersion = ver,
                        playMethod = "DirectPlay",
                        playbackTimeMs = entry.playbackTimeMs,
                        audioStreamIndex = null,
                        subtitleStreamIndex = null,
                        seq = entry.seq,
                        expectedSession = auth,
                    )
                    if (ok) {
                        flushedLast = entry.server to entry.itemId
                    } else {
                        remaining += entry
                    }
                }
                savePendingStops(remaining, storageKey)
                flushedLast?.let { _playbackStoppedEvents.tryEmit(it) }
            }
        }
    }

    /** 只读当前实例账号桶，拒绝把旧版无归属记录归给当前登录人。 */
    private fun loadPendingStops(storageKey: String): List<PendingPlaybackStopDto> = synchronized(pendingLock) {
        prefs.edit().remove(KEY_PENDING_STOPS).apply()
        val raw = runCatching { prefs.getString(storageKey, null) }.getOrNull()
            ?: return emptyList()
        val parsed = runCatching { json.decodeFromString<List<PendingPlaybackStopDto>>(raw) }
            .getOrDefault(emptyList())
        RustCoreBridge.normalizePendingPlaybackStops(parsed, System.currentTimeMillis())
    }

    /** 按归属分别持久化，串行补报不会清除其他账号的记录。 */
    private fun savePendingStops(entries: List<PendingPlaybackStopDto>, storageKey: String) = synchronized(pendingLock) {
        val normalized = RustCoreBridge.normalizePendingPlaybackStops(entries, System.currentTimeMillis())
        runCatching {
            if (normalized.isEmpty()) {
                prefs.edit().remove(storageKey).apply()
            } else {
                prefs.edit().putString(storageKey, json.encodeToString(normalized)).apply()
            }
        }
    }

    /** 记录到播放发起时固定的账号桶，失败重试不随当前实例漂移。 */
    private fun recordPendingStop(stop: PendingPlaybackStopDto, storageKey: String) = synchronized(pendingLock) {
        val existing = loadPendingStops(storageKey)
        savePendingStops(existing + stop, storageKey)
    }

    companion object {
        private const val PREFS_NAME = "mp_playback_sync_v1"
        private const val KEY_CLIENT_ID = "client_id"
        private const val KEY_PENDING_STOPS = "pending_stops"
    }
}
