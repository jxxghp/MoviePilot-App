package com.moviepilot.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.moviepilot.designsystem.SystemNotificationPreferencesStore
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SentNotificationItemDto
import com.moviepilot.rustbridge.SessionState
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Android 原生系统通知栏同步协调器：
 * - 支持前台活跃会话实时增量拉取（30s）与后台 `WorkManager` 周期拉取（15m，零 GMS/FCM 依赖，全兼容国产 ROM）；
 * - 将 MoviePilot 系统消息（订阅、入库、下载、站点等）与插件 `post_message` 通知投递至手机系统状态栏；
 * - 点击通知自动携带同源实例校验参数拉起 `MainActivity` 并路由至目标页面或消息中心。
 */
object AndroidNotificationSyncManager {
    private const val WATERMARK_PREFS = "mp_android_notification_watermarks_v1"
    private const val WORK_UNIQUE_NAME = "moviepilot_periodic_notification_sync"
    private val syncMutex = Mutex()

    /** 检查当前设备是否具备在系统通知栏展示通知的权限与开关。 */
    fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    /** 根据用户偏好与登录态注册或取消后台周期同步任务。 */
    fun syncBackgroundWork(context: Context, enabled: Boolean) {
        val appContext = context.applicationContext
        val wm = runCatching { WorkManager.getInstance(appContext) }.getOrNull() ?: return
        if (!enabled) {
            wm.cancelUniqueWork(WORK_UNIQUE_NAME)
            return
        }
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = PeriodicWorkRequestBuilder<MoviePilotNotificationWorker>(15, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()
        wm.enqueueUniquePeriodicWork(
            WORK_UNIQUE_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    /** 执行一次增量通知同步并投递到 Android 状态栏（前台协程与后台 Worker 共用互斥锁防重）。 */
    suspend fun pollAndPostOnce(context: Context, repository: MoviePilotRepository): Int = syncMutex.withLock {
        val appContext = context.applicationContext
        val prefs = SystemNotificationPreferencesStore(appContext)
        if (!prefs.systemBarNotificationsEnabled) return 0
        if (!prefs.includePluginNotifications && !prefs.includeSystemNotifications) return 0
        if (!canPostNotifications(appContext)) return 0

        val auth = repository.session.value as? SessionState.Authenticated ?: return 0
        val normalizedOrigin = AndroidPushProvider.normalizeOrigin(auth.serverUrl) ?: auth.serverUrl.trim()
        if (normalizedOrigin.isEmpty()) return 0

        val fetched = repository.fetchSentNotifications(count = 20) ?: return 0
        val scopeKey = "${normalizedOrigin}|${auth.identity.name.lowercase()}"
        val currentWatermark = readWatermark(appContext, scopeKey)
        val batch = AndroidPushProvider.computeIncrementalNotifications(
            fetchedNewestFirst = fetched,
            current = currentWatermark,
            activeUserName = auth.identity.name,
            includePlugin = prefs.includePluginNotifications,
            includeSystem = prefs.includeSystemNotifications,
        )
        saveWatermark(appContext, scopeKey, batch.nextWatermark)
        if (batch.toDeliver.isEmpty()) return 0

        AndroidPushProvider.ensureChannels(appContext)
        batch.toDeliver.forEach { item ->
            postToStatusBar(appContext, normalizedOrigin, item)
        }
        return batch.toDeliver.size
    }

    /** 发送一条本机状态栏测试通知，便于用户立即核验系统通知权限与通知栏横幅展示。 */
    fun sendTestNotification(context: Context, activeServerUrl: String): Boolean {
        val appContext = context.applicationContext
        if (!canPostNotifications(appContext)) return false
        AndroidPushProvider.ensureChannels(appContext)
        val origin = AndroidPushProvider.normalizeOrigin(activeServerUrl).orEmpty()
        val sample = SentNotificationItemDto(
            numericId = System.currentTimeMillis(),
            stableKey = "test_${System.currentTimeMillis()}",
            title = "MoviePilot 手机通知栏已连接",
            text = "插件通知与 MoviePilot 系统消息将自动推送至安卓手机状态栏。",
            category = "系统与插件",
            route = "/?shotcut=message",
        )
        postToStatusBar(appContext, origin, sample)
        return true
    }

    /** 发送前显式检查通知权限，兼顾运行时撤权与 Lint 的调用点校验。 */
    private fun postToStatusBar(
        context: Context,
        normalizedOrigin: String,
        item: SentNotificationItemDto,
    ) {
        if (!canPostNotifications(context)) return
        val channelId = AndroidPushProvider.selectChannelForNotification(item)
        val notifId = item.numericId?.let { (it % 1_000_000L).toInt() + 20_000 }
            ?: (abs(item.stableKey.hashCode() % 1_000_000) + 20_000)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AndroidPushProvider.EXTRA_NOTIFICATION_ROUTE, item.route.ifBlank { "/?shotcut=message" })
            if (normalizedOrigin.isNotBlank()) {
                putExtra(AndroidPushProvider.EXTRA_NOTIFICATION_ORIGIN, normalizedOrigin)
            }
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = PendingIntent.getActivity(context, notifId, launchIntent, pendingFlags)

        val bodyText = item.text.ifBlank { item.title }
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setSubText(item.category.ifBlank { "MoviePilot" })
            .setContentTitle(item.title.ifBlank { "MoviePilot 通知" })
            .setContentText(bodyText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bodyText))
            .setPriority(
                if (channelId == AndroidPushProvider.CHANNEL_ID_DOWNLOAD) {
                    NotificationCompat.PRIORITY_LOW
                } else {
                    NotificationCompat.PRIORITY_DEFAULT
                },
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        if (android.os.Build.VERSION.SDK_INT >= 33 &&
            androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) return
        runCatching {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        }
    }

    private fun readWatermark(context: Context, scopeKey: String): NotificationWatermark {
        val sp = context.getSharedPreferences(WATERMARK_PREFS, Context.MODE_PRIVATE)
        val init = sp.getBoolean("init_$scopeKey", false)
        val maxId = sp.getLong("max_id_$scopeKey", 0L)
        val seen = sp.getStringSet("seen_$scopeKey", emptySet()).orEmpty()
        return NotificationWatermark(initialized = init, maxNumericId = maxId, seenKeys = seen)
    }

    private fun saveWatermark(context: Context, scopeKey: String, watermark: NotificationWatermark) {
        val sp = context.getSharedPreferences(WATERMARK_PREFS, Context.MODE_PRIVATE)
        sp.edit()
            .putBoolean("init_$scopeKey", watermark.initialized)
            .putLong("max_id_$scopeKey", watermark.maxNumericId)
            .putStringSet("seen_$scopeKey", watermark.seenKeys)
            .apply()
    }
}

/** 后台周期同步 MoviePilot 系统与插件通知的 `WorkManager` 任务。 */
class MoviePilotNotificationWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val prefs = SystemNotificationPreferencesStore(applicationContext)
        if (!prefs.systemBarNotificationsEnabled || !AndroidNotificationSyncManager.canPostNotifications(applicationContext)) {
            return Result.success()
        }
        val repository = MoviePilotRepository(applicationContext)
        if (repository.session.value !is SessionState.Authenticated) {
            return Result.success()
        }
        runCatching {
            AndroidNotificationSyncManager.pollAndPostOnce(applicationContext, repository)
        }
        return Result.success()
    }
}
