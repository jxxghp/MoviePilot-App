package com.moviepilot.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf

/** 在系统广播结束后可靠同步插件小组件，避免与 Glance 争用 PendingResult。 */
class PluginWidgetUpdateWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {

    /** 同步仍存在且已配置的小组件，再通知 Glance 重绘最新快照。 */
    override suspend fun doWork(): Result {
        val appWidgetId = inputData.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId <= AppWidgetManager.INVALID_APPWIDGET_ID) return Result.failure()
        val glanceId = runCatching {
            GlanceAppWidgetManager(applicationContext).getGlanceIdBy(appWidgetId)
        }.getOrNull() ?: return Result.success()
        PluginDesktopWidgetStore.syncWidgetData(applicationContext, appWidgetId)
            ?: return Result.success()
        updatePluginWidget(applicationContext, glanceId)
        return Result.success()
    }

    /** 按桌面实例合并尚未完成的更新，避免系统短时间重复广播产生并行同步。 */
    companion object {
        /** 每个有效小组件安排一项独立任务，其他实例的失败不会阻断本实例。 */
        fun enqueue(context: Context, appWidgetIds: IntArray) {
            val manager = WorkManager.getInstance(context)
            appWidgetIds.filter { it > AppWidgetManager.INVALID_APPWIDGET_ID }.distinct().forEach { id ->
                val request = OneTimeWorkRequestBuilder<PluginWidgetUpdateWorker>()
                    .setInputData(workDataOf(AppWidgetManager.EXTRA_APPWIDGET_ID to id))
                    .build()
                manager.enqueueUniqueWork("mp-plugin-widget-sync-$id", ExistingWorkPolicy.KEEP, request)
            }
        }
    }
}
