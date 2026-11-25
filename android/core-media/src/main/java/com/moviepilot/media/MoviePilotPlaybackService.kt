package com.moviepilot.media

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 队列感知转发播放器：
 * 向 Android 系统通知栏、锁屏播控、蓝牙车载与穿戴设备暴露「上一曲/集」「下一曲/集」能力，
 * 并将硬件按键与系统播控指令转发给应用层延迟解析队列协调器。
 */
@OptIn(UnstableApi::class)
class QueueForwardingPlayer(
    delegate: Player,
    private val canSkipPreviousProvider: () -> Boolean,
    private val canSkipNextProvider: () -> Boolean,
    private val onSkipPreviousAction: () -> Unit,
    private val onSkipNextAction: () -> Unit,
) : ForwardingPlayer(delegate) {

    override fun getAvailableCommands(): Player.Commands {
        val builder = super.getAvailableCommands().buildUpon()
        if (canSkipPreviousProvider()) {
            builder.add(Player.COMMAND_SEEK_TO_PREVIOUS)
            builder.add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
        }
        if (canSkipNextProvider()) {
            builder.add(Player.COMMAND_SEEK_TO_NEXT)
            builder.add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
        }
        return builder.build()
    }

    override fun isCommandAvailable(command: Int): Boolean {
        return when (command) {
            Player.COMMAND_SEEK_TO_PREVIOUS,
            Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
            -> canSkipPreviousProvider() || super.isCommandAvailable(command)

            Player.COMMAND_SEEK_TO_NEXT,
            Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            -> canSkipNextProvider() || super.isCommandAvailable(command)

            else -> super.isCommandAvailable(command)
        }
    }

    override fun hasPreviousMediaItem(): Boolean =
        canSkipPreviousProvider() || super.hasPreviousMediaItem()

    override fun hasNextMediaItem(): Boolean =
        canSkipNextProvider() || super.hasNextMediaItem()

    override fun seekToPrevious() {
        if (canSkipPreviousProvider()) {
            onSkipPreviousAction()
        } else {
            super.seekToPrevious()
        }
    }

    override fun seekToPreviousMediaItem() {
        if (canSkipPreviousProvider()) {
            onSkipPreviousAction()
        } else {
            super.seekToPreviousMediaItem()
        }
    }

    override fun seekToNext() {
        if (canSkipNextProvider()) {
            onSkipNextAction()
        } else {
            super.seekToNext()
        }
    }

    override fun seekToNextMediaItem() {
        if (canSkipNextProvider()) {
            onSkipNextAction()
        } else {
            super.seekToNextMediaItem()
        }
    }
}

/**
 * 基于全局 Coil 实例（自动复用同源 Bearer 令牌与图片代理 Cookie）的 Media3 封面位图加载器。
 */
@OptIn(UnstableApi::class)
private class CoilMediaBitmapLoader(
    private val appContext: Context,
) : BitmapLoader {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun supportsMimeType(mimeType: String): Boolean =
        mimeType.startsWith("image/")

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        ioScope.launch {
            val bmp = runCatching { BitmapFactory.decodeByteArray(data, 0, data.size) }.getOrNull()
            if (bmp != null) {
                future.set(bmp)
            } else {
                future.setException(IllegalArgumentException("封面字节解码失败"))
            }
        }
        return future
    }

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        ioScope.launch {
            val result = runCatching {
                val req = ImageRequest.Builder(appContext)
                    .data(uri)
                    .size(512)
                    .allowHardware(false)
                    .build()
                val res = appContext.imageLoader.execute(req) as? SuccessResult
                (res?.drawable as? BitmapDrawable)?.bitmap
            }.getOrNull()
            if (result != null) {
                future.set(result)
            } else {
                future.setException(IllegalStateException("无法加载媒体封面: $uri"))
            }
        }
        return future
    }

    override fun loadBitmapFromMetadata(metadata: MediaMetadata): ListenableFuture<Bitmap>? {
        metadata.artworkData?.takeIf { it.isNotEmpty() }?.let { return decodeBitmap(it) }
        metadata.artworkUri?.let { return loadBitmap(it) }
        return null
    }
}

/**
 * 应用内播放协调器与前台 `MoviePilotPlaybackService` 之间的轻量同步桥接中心。
 */
@OptIn(UnstableApi::class)
object PlaybackServiceBridge {
    private const val SESSION_ID = "moviepilot_primary_media_session"

    @Volatile
    private var mediaSession: MediaSession? = null

    @Volatile
    private var serviceRef: MoviePilotPlaybackService? = null

    private var controllerFuture: ListenableFuture<MediaController>? = null

    /**
     * 将当前活跃的 `Player`（`ExoPlayer` 或 MPV `SimpleBasePlayer` 桥接器）绑定到系统 `MediaSession` 并唤醒前台通知。
     */
    @Synchronized
    fun attachActivePlayer(
        context: Context,
        exoPlayer: Player,
        canSkipPrevious: () -> Boolean = { true },
        canSkipNext: () -> Boolean = { false },
        onSkipPrevious: () -> Unit = { exoPlayer.seekTo(0L) },
        onSkipNext: () -> Unit = {},
    ) {
        val appContext = context.applicationContext
        val wrapped = QueueForwardingPlayer(
            delegate = exoPlayer,
            canSkipPreviousProvider = canSkipPrevious,
            canSkipNextProvider = canSkipNext,
            onSkipPreviousAction = onSkipPrevious,
            onSkipNextAction = onSkipNext,
        )
        val existing = mediaSession
        if (existing != null) {
            existing.player = wrapped
        } else {
            val launchIntent = appContext.packageManager
                .getLaunchIntentForPackage(appContext.packageName)
                ?.apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
            val sessionBuilder = MediaSession.Builder(appContext, wrapped)
                .setId(SESSION_ID)
                .setBitmapLoader(CoilMediaBitmapLoader(appContext))
            if (launchIntent != null) {
                val pi = PendingIntent.getActivity(
                    appContext,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                sessionBuilder.setSessionActivity(pi)
            }
            val created = sessionBuilder.build()
            mediaSession = created
            serviceRef?.registerSessionIfNeeded(created)
        }
        ensureServiceControllerBound(appContext)
    }

    /** 当关联的播放器真正关闭释放时，解绑并清理 `MediaSession` 与前台通知。 */
    @Synchronized
    fun detachIfMatching(exoPlayer: Player?) {
        val current = mediaSession ?: return
        val unwrapped = (current.player as? QueueForwardingPlayer)?.wrappedPlayer ?: current.player
        if (exoPlayer == null || unwrapped === exoPlayer) {
            releaseAll()
        }
    }

    /** 彻底释放媒体会话与前台控制器连接。 */
    @Synchronized
    fun releaseAll() {
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
        mediaSession?.let { session ->
            serviceRef?.removeSessionSafe(session)
            runCatching { session.release() }
        }
        mediaSession = null
    }

    @Synchronized
    internal fun onServiceCreated(service: MoviePilotPlaybackService) {
        serviceRef = service
        mediaSession?.let { service.registerSessionIfNeeded(it) }
    }

    @Synchronized
    internal fun onServiceDestroyed(service: MoviePilotPlaybackService) {
        if (serviceRef === service) {
            serviceRef = null
        }
    }

    @Synchronized
    internal fun currentSession(): MediaSession? = mediaSession

    private fun ensureServiceControllerBound(appContext: Context) {
        val currentFuture = controllerFuture
        if (currentFuture != null && !currentFuture.isCancelled) return
        runCatching {
            val token = SessionToken(
                appContext,
                ComponentName(appContext, MoviePilotPlaybackService::class.java),
            )
            controllerFuture = MediaController.Builder(appContext, token).buildAsync()
        }
    }
}

/**
 * MoviePilot Media3 前台媒体会话服务：
 * 托管系统通知栏媒体卡片、锁屏播控、快捷设置面板、蓝牙车载 AVRCP 与穿戴设备控制。
 */
@OptIn(UnstableApi::class)
class MoviePilotPlaybackService : MediaSessionService() {

    override fun onCreate() {
        super.onCreate()
        PlaybackServiceBridge.onServiceCreated(this)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return PlaybackServiceBridge.currentSession()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = PlaybackServiceBridge.currentSession()?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            PlaybackServiceBridge.releaseAll()
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        PlaybackServiceBridge.onServiceDestroyed(this)
        super.onDestroy()
    }

    internal fun registerSessionIfNeeded(session: MediaSession) {
        if (!sessions.contains(session)) {
            addSession(session)
        }
    }

    internal fun removeSessionSafe(session: MediaSession) {
        if (sessions.contains(session)) {
            removeSession(session)
        }
    }
}
