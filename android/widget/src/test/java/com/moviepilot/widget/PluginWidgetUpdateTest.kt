package com.moviepilot.widget

import android.app.Application
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Looper
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.testing.WorkManagerTestInitHelper
import androidx.work.workDataOf
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** 回归真实 Glance 广播的 PendingResult 所有权，以及插件小组件的后台同步边界。 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29, 35], manifest = Config.NONE)
class PluginWidgetUpdateTest {
    private lateinit var context: Application
    private lateinit var receiver: MoviePilotPluginWidgetReceiver
    private lateinit var factory: RecordingWorkerFactory

    /** 使用内存 WorkManager，保留真实接收器与同步代码，隔离长驻 Glance 渲染任务。 */
    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        factory = RecordingWorkerFactory()
        val configuration = Configuration.Builder()
            .setExecutor(SynchronousExecutor())
            .setWorkerFactory(factory)
            .build()
        WorkManagerTestInitHelper.initializeTestWorkManager(context, configuration)
        receiver = MoviePilotPluginWidgetReceiver()
        context.registerReceiver(receiver, IntentFilter(AppWidgetManager.ACTION_APPWIDGET_UPDATE))
    }

    /** 结束测试暂挂任务并关闭内存数据库，避免向后续用例泄漏广播或工作。 */
    @After
    fun tearDown() {
        context.unregisterReceiver(receiver)
        factory.completeHeldWork()
        WorkManager.getInstance(context).cancelAllWork().result.get(5, TimeUnit.SECONDS)
        WorkManagerTestInitHelper.closeWorkDatabase()
    }

    /** 父类必须是 PendingResult 的唯一持有者，各桌面实例独立进入后台同步。 */
    @Test
    fun updateBroadcastKeepsGlancePendingResultAndSchedulesEachWidget() {
        receiveUpdate(intArrayOf(71, 72))

        assertEquals(listOf(71, 72), factory.widgetIds.toList())
    }

    /** 连续广播分别结束一次，不能复用已完成的广播结果。 */
    @Test
    fun repeatedUpdateBroadcastsFinishIndependently() {
        val first = receiveUpdate(intArrayOf(81))
        val second = receiveUpdate(intArrayOf(82))

        assertTrue(first !== second)
        assertEquals(listOf(81, 82), factory.widgetIds.toList())
    }

    /** 无实例的系统广播仍交给 Glance 正常结束，但不创建业务同步任务。 */
    @Test
    fun emptyUpdateBroadcastDoesNotSchedulePluginSync() {
        receiveUpdate(intArrayOf())

        assertTrue(factory.widgetIds.isEmpty())
    }

    /** 同一实例尚在同步时合并重复请求，其他实例仍可独立执行。 */
    @Test
    fun duplicateUpdatesKeepOnlyOneRunningSyncPerWidget() {
        factory.holdPluginSync = true
        receiveUpdate(intArrayOf(83, 83))
        receiveUpdate(intArrayOf(83, 84))

        assertEquals(listOf(83, 84), factory.widgetIds.toList())
    }

    /** 暂时无法访问后端时保留仪表盘指标，完成同步后仍通知 Glance 重读快照。 */
    @Test
    fun workerSynchronizesSnapshotAndAdvancesGlanceState() = runBlocking {
        bindWidget(91)
        val original = PluginDesktopWidgetConfig(
            91,
            "plugin_dashboard",
            pluginId = "SyntheticPlugin",
            pluginName = "Synthetic dashboard",
            lines = listOf("已下载：42", "剩余：8"),
            updatedAt = "old",
        )
        PluginDesktopWidgetStore.saveConfig(context, original)

        assertEquals(ListenableWorker.Result.success(), worker(91).doWork())

        val config = requireNotNull(PluginDesktopWidgetStore.loadConfig(context, 91))
        assertEquals(original.lines, config.lines)
        assertEquals(original.pluginName, config.pluginName)
        assertTrue(config.updatedAt.isNotBlank() && config.updatedAt != original.updatedAt)
        assertEquals(1L, revision(91))
        assertTrue(factory.workerNames.any { it.endsWith(".SessionWorker") })
    }

    /** 配置保存和手动刷新复用同一重绘入口，连续刷新也必须产生新的可观察状态。 */
    @Test
    fun consecutiveRedrawsAdvanceTheActiveGlanceSession() = runBlocking {
        bindWidget(92)
        val glanceId = GlanceAppWidgetManager(context).getGlanceIdBy(92)

        updatePluginWidget(context, glanceId)
        updatePluginWidget(context, glanceId)

        assertEquals(2L, revision(92))
    }

    /** 手动刷新直接走 Glance ActionCallback，不依赖或再次结束系统广播。 */
    @Test
    fun manualRefreshSynchronizesTheConfiguredWidget() = runBlocking {
        bindWidget(95)
        val original = PluginDesktopWidgetConfig(
            95,
            "plugin_dashboard",
            pluginId = "SyntheticPlugin",
            lines = listOf("指标：42"),
            updatedAt = "old",
        )
        PluginDesktopWidgetStore.saveConfig(context, original)

        RefreshPluginWidgetAction().onAction(
            context,
            GlanceAppWidgetManager(context).getGlanceIdBy(95),
            actionParametersOf(),
        )

        val config = requireNotNull(PluginDesktopWidgetStore.loadConfig(context, 95))
        assertEquals(original.lines, config.lines)
        assertTrue(config.updatedAt != original.updatedAt)
        assertEquals(1L, revision(95))
        assertTrue(factory.widgetIds.isEmpty())
    }

    /** 未完成配置的小组件由 Glance 展示配置入口，后台同步不能创建虚假快照。 */
    @Test
    fun unconfiguredWidgetIsSkipped() = runBlocking {
        bindWidget(93)

        assertEquals(ListenableWorker.Result.success(), worker(93).doWork())
        assertEquals(null, PluginDesktopWidgetStore.loadConfig(context, 93))
        assertTrue(factory.workerNames.isEmpty())
    }

    /** 小组件排队后被移除时安全结束，不再同步或重建已失效实例的数据。 */
    @Test
    fun removedWidgetDoesNotRefreshItsSnapshot() = runBlocking {
        val original = PluginDesktopWidgetConfig(94, "overview", lines = listOf("cached"))
        PluginDesktopWidgetStore.saveConfig(context, original)

        assertEquals(ListenableWorker.Result.success(), worker(94).doWork())
        assertEquals(original, PluginDesktopWidgetStore.loadConfig(context, 94))
        assertTrue(factory.workerNames.isEmpty())
    }

    /** 缺失或无效的 ID 不能被误当作真实桌面实例执行。 */
    @Test
    fun invalidWidgetIdsAreRejected() = runBlocking {
        for (id in listOf(0, -1)) {
            assertEquals(ListenableWorker.Result.failure(), worker(id).doWork())
        }
        PluginWidgetUpdateWorker.enqueue(context, intArrayOf(0, -1))
        assertTrue(factory.widgetIds.isEmpty())
    }

    /** 验证声明式自定义布局树 `PluginWidgetNode` 兼容字符串型 `metric.value`、浮点型 `progress.value` 及 5 层深度裁剪。 */
    @Test
    fun customLayoutDslParsesNodesAndEnforcesDepthAndNodeBounds() {
        val rawSnapshot = """
            {
              "kind": "custom",
              "title": "站点保种工作台",
              "subtitle": "实时速率监控",
              "accentHex": "#10B981",
              "updatedAt": 1730000120.0,
              "layout": {
                "type": "column",
                "gap": 8,
                "padding": 10,
                "children": [
                  {
                    "type": "row",
                    "align": "spaceBetween",
                    "children": [
                      { "type": "metric", "label": "今日上传", "value": "64.2 GB", "subValue": "+12%", "tone": "success" },
                      { "type": "badge", "text": "正常", "tone": "accent" }
                    ]
                  },
                  { "type": "progress", "label": "考核目标", "value": 0.78, "valueText": "78%", "tone": "accent" },
                  {
                    "type": "button",
                    "label": "立即签到",
                    "filled": true,
                    "action": { "type": "pluginAction", "actionId": "sign_now" }
                  }
                ]
              }
            }
        """.trimIndent()

        val parsed = requireNotNull(PluginWidgetPayloadParser.parseSnapshot(rawSnapshot))
        assertEquals("custom", parsed.kind)
        assertEquals("站点保种工作台", parsed.title)
        assertEquals("#10B981", parsed.accentHex)
        val root = requireNotNull(parsed.resolveLayout("medium"))
        assertEquals("column", root.type)
        assertEquals(3, root.children.size)
        val metricNode = root.children[0].children[0]
        assertEquals("metric", metricNode.type)
        assertEquals("64.2 GB", metricNode.valueText)
        val progressNode = root.children[1]
        assertEquals("progress", progressNode.type)
        assertEquals(0.78f, requireNotNull(progressNode.progressValue), 0.001f)
        assertEquals("78%", progressNode.valueText)
        val btnNode = root.children[2]
        assertEquals("pluginAction", btnNode.action?.type)
        assertEquals("sign_now", btnNode.action?.actionId)

        // 构造 7 层嵌套节点树，验证超过第 5 层（depth > 5）的后代被严格截断
        val overDeepJson = """
            {"type":"column","children":[{"type":"column","children":[{"type":"column","children":[
            {"type":"column","children":[{"type":"column","children":[{"type":"column","children":[
            {"type":"text","text":"too-deep"}]}]}]}]}]}]}
        """.trimIndent()
        val bounded = requireNotNull(PluginWidgetPayloadParser.parseNodeTreeFromJson(overDeepJson))
        var cursor = bounded
        var depthReached = 0
        while (cursor.children.isNotEmpty()) {
            cursor = cursor.children.first()
            depthReached++
        }
        assertEquals(5, depthReached)
    }

    /** 验证运行态推送快照（`"rt_${pluginId}_${key}"`）优先融合进小组件缓存与摘要。 */
    @Test
    fun syncWidgetDataFusesFreshRuntimeSnapshot() = runBlocking {
        bindWidget(96)
        context.getSharedPreferences(PluginDesktopWidgetStore.PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(
                "rt_MusicBox_card_main",
                """{"kind":"metrics","title":"云音实时榜","updatedAt":1890000000,"metrics":[{"id":"m1","label":"在听曲目","value":"18 首","tone":"accent"}]}""",
            )
            .commit()

        PluginDesktopWidgetStore.saveConfig(
            context,
            PluginDesktopWidgetConfig(
                appWidgetId = 96,
                kind = "plugin_dashboard",
                pluginId = "MusicBox",
                pluginName = "MusicBox",
                widgetKey = "card_main",
            ),
        )

        val synced = requireNotNull(PluginDesktopWidgetStore.syncWidgetData(context, 96))
        assertEquals("云音实时榜", synced.dashboardName)
        assertEquals(listOf("在听曲目：18 首"), synced.lines)
        assertTrue(synced.payloadJson.contains("云音实时榜"))
    }

    /** 验证主体小组件的隐私投影与正在播放小组件的乐观状态翻转。 */
    @Test
    fun mainWidgetPrivacyMaskAndNowPlayingOptimisticToggleWork() {
        context.getSharedPreferences(AppDesktopWidgetStore.SNAPSHOT_PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString("server", "HomeNAS")
            .putString(
                "downloads",
                """{"content":"downloads","title":"下载状态","updatedAt":"12:30","metrics":[{"id":"downloadSpeed","title":"下载速度","value":"12.4 MB/s"}],"items":[{"id":"d1","title":"星际穿越 2160p","subtitle":"剩余 5 分钟","progress":0.6}]}""",
            )
            .commit()

        val visible = AppDesktopWidgetStore.loadSectionSnapshot(context, "downloads", showMediaNames = true)
        assertEquals("星际穿越 2160p", visible.items.single().title)

        val masked = AppDesktopWidgetStore.loadSectionSnapshot(context, "downloads", showMediaNames = false)
        assertEquals("项目 1", masked.items.single().title)
        assertEquals("", masked.items.single().subtitle)
        assertEquals(0.6f, requireNotNull(masked.items.single().progress), 0.001f)

        context.getSharedPreferences(NowPlayingWidgetStore.PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean("active", true)
            .putString("plugin_id", "MusicBox")
            .putString("title", "夜航星")
            .putBoolean("is_playing", true)
            .putBoolean("has_like", true)
            .putBoolean("liked", false)
            .commit()

        val afterToggle = NowPlayingWidgetStore.applyOptimisticBroadcastAction(
            context,
            NowPlayingWidgetStore.ACTION_MEDIA_TOGGLE,
        )
        assertEquals(false, afterToggle.isPlaying)
        val afterLike = NowPlayingWidgetStore.applyOptimisticBroadcastAction(
            context,
            NowPlayingWidgetStore.ACTION_MEDIA_LIKE,
        )
        assertEquals(true, afterLike.liked)
    }

    /** 经系统广播分发设置真实 PendingResult，并等待 Glance 成功结束该广播。 */
    private fun receiveUpdate(ids: IntArray): BroadcastReceiver.PendingResult {
        context.sendBroadcast(
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .setPackage(context.packageName)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
        )
        shadowOf(Looper.getMainLooper()).idle()
        val pending = shadowOf(receiver).originalPendingResult
        assertNotNull("Glance must retain the broadcast's only PendingResult", pending)
        val result = requireNotNull(pending)
        shadowOf(result).future.get(5, TimeUnit.SECONDS)
        return result
    }

    /** 注册桌面宿主绑定信息，仅隔离远端界面渲染而保留真实 ID 校验。 */
    private fun bindWidget(id: Int) {
        val info = AppWidgetProviderInfo().apply {
            provider = ComponentName(context, MoviePilotPluginWidgetReceiver::class.java)
            minWidth = 110
            minHeight = 110
        }
        shadowOf(AppWidgetManager.getInstance(context)).addBoundWidget(id, info)
    }

    /** 构造真实业务 Worker，直接验证同步和刷新状态写入。 */
    private fun worker(id: Int): PluginWidgetUpdateWorker =
        TestListenableWorkerBuilder<PluginWidgetUpdateWorker>(context)
            .setInputData(workDataOf(AppWidgetManager.EXTRA_APPWIDGET_ID to id))
            .build()

    /** 读取 Glance 持久化的刷新版本，验证当前渲染会话能观察到数据变化。 */
    private suspend fun revision(id: Int): Long? = getAppWidgetState(
        context,
        PreferencesGlanceStateDefinition,
        GlanceAppWidgetManager(context).getGlanceIdBy(id),
    )[PluginWidgetRevisionKey]

    /** 记录调度边界并替代长驻渲染任务；业务 Worker 由用例单独直接执行。 */
    private class RecordingWorkerFactory : WorkerFactory() {
        val widgetIds = CopyOnWriteArrayList<Int>()
        val workerNames = CopyOnWriteArrayList<String>()
        var holdPluginSync = false
        private val heldWork = CopyOnWriteArrayList<SettableFuture<ListenableWorker.Result>>()

        /** 保留实际 WorkManager 调度过程，按需暂挂业务任务以验证重复请求合并。 */
        override fun createWorker(
            appContext: Context,
            workerClassName: String,
            workerParameters: WorkerParameters,
        ): ListenableWorker {
            workerNames += workerClassName
            val pluginSync = workerClassName == PluginWidgetUpdateWorker::class.java.name
            if (pluginSync) {
                widgetIds += workerParameters.inputData.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, 0)
            }
            return object : ListenableWorker(appContext, workerParameters) {
                /** 立即结束渲染任务，仅暂挂用例指定的业务同步。 */
                override fun startWork(): ListenableFuture<Result> = SettableFuture.create<Result>().also {
                    if (pluginSync && holdPluginSync) heldWork += it else it.set(Result.success())
                }
            }
        }

        /** 释放用例暂挂的工作，保证数据库关闭前所有回调均已完成。 */
        fun completeHeldWork() {
            heldWork.forEach { it.set(ListenableWorker.Result.success()) }
            heldWork.clear()
        }
    }
}
