package com.moviepilot.rustbridge

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.Dispatcher
import java.net.URI
import java.io.ByteArrayInputStream
import java.lang.reflect.Proxy
import java.time.LocalDate
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

/** 在真实 Repository、OkHttp 和 Rust 内核边界回归实例隔离与当前后端合同。 */
class NativeApiRegressionTest {
    /** 跨源重定向不能携带任何实例凭据，包括自定义 Cloudflare 头和 Cookie。 */
    @Test fun redirectedImagesStripAllCredentials() {
        ApiFixture().use { target ->
            ApiFixture().use { origin ->
                val received = CopyOnWriteArrayList<Map<String, List<String>>>()
                target.route = { exchange -> received += exchange.requestHeaders.toMap(); exchange.reply(200, "image") }
                origin.route = { exchange ->
                    assertTrue(exchange.requestHeaders.keys.any { it.equals("cf-access-token", true) })
                    assertTrue(exchange.requestHeaders.keys.any { it.equals("Authorization", true) })
                    exchange.responseHeaders.add("Location", "${target.base}/foreign")
                    exchange.reply(302, "")
                }
                val transport = NativeHttpTransport(cfAccessTokenProvider = { "synthetic-cf" })
                val client = transport.buildImageClient({ origin.base }, { "synthetic-bearer" })
                client.newCall(okhttp3.Request.Builder().url("${origin.base}/image")
                    .header("Cookie", "resource_token=synthetic-resource; CF_Authorization=synthetic-cf")
                    .header("CF-Access-Client-Id", "synthetic-id")
                    .header("CF-Access-Client-Secret", "synthetic-secret")
                    .build()).execute().use { assertEquals(200, it.code) }
                assertEquals(1, received.size)
                for (header in listOf("Authorization", "Cookie", "cf-access-token", "CF-Access-Client-Id", "CF-Access-Client-Secret")) {
                    assertTrue("Foreign origin received $header", received.single().keys.none { it.equals(header, true) })
                }
            }
        }
    }

    /** A 的取消请求稍后返回 401，不得注销 B；当前 B 的真实 401 仍应使 B 失效。 */
    @Test fun lateUnauthorizedOnlyExpiresOwningSession() = runBlocking {
        ApiFixture().use { api ->
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            api.route = { exchange ->
                if (exchange.requestURI.path.endsWith("/delayed")) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                    exchange.reply(401, "{}")
                } else exchange.reply(401, "{}")
            }
            val repo = repository()
            api.login(repo, "a")
            val old = async(kotlinx.coroutines.Dispatchers.IO) { repo.authedRequest(listOf("delayed")) }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            old.cancel()
            api.login(repo, "b")
            release.countDown()
            old.join()
            assertEquals("${api.base}/b", (repo.session.value as SessionState.Authenticated).serverUrl.trimEnd('/'))
            assertTrue(repo.authedRequest(listOf("unauthorized")).isFailure)
            assertTrue(repo.session.value is SessionState.NeedsLogin)
        }
    }

    /** A 的资料刷新晚于 B 的登录返回时，不能重新装回 A 的身份。 */
    @Test fun lateHydrationCannotRestoreOldInstance() = runBlocking {
        ApiFixture().use { api ->
            val repo = repository(); api.login(repo, "a")
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            api.currentUser = { exchange ->
                if (exchange.requestURI.path.startsWith("/a/")) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                }
                exchange.reply(200, """{"id":7,"name":"member-7","is_superuser":true,"permissions":{}}""")
            }
            val hydration = async(kotlinx.coroutines.Dispatchers.IO) { repo.hydrateAuthenticatedSession() }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            api.login(repo, "b")
            release.countDown()
            hydration.await()
            assertEquals("${api.base}/b", (repo.session.value as SessionState.Authenticated).serverUrl.trimEnd('/'))
        }
    }

    /** 同实例相同令牌的重新登录也属于新会话，不能仅比较 token 来处理旧失效事件。 */
    @Test fun reloginInvalidatesOldExpiryHandler() = runBlocking {
        ApiFixture().use { api ->
            val repo = repository(); api.login(repo, "a")
            val auth = repo.session.value as SessionState.Authenticated
            val old = repo.transport.authFailureHandlerProvider?.invoke("${api.base}/a/api/v1/user/current", auth.token)
            assertNotNull(old)
            api.login(repo, "a")
            old?.invoke()
            assertTrue(repo.session.value is SessionState.Authenticated)
        }
    }

    /** A 的离线终态不能发送给 B，回到原账号后可正常补报且不会丢失。 */
    @Test fun playbackQueueStaysWithInstanceAndUser() = runBlocking {
        ApiFixture().use { api ->
            val progressPaths = CopyOnWriteArrayList<String>()
            var online = false
            api.route = { exchange ->
                if (exchange.requestURI.path.endsWith("/mediaserver/progress")) {
                    progressPaths += exchange.requestURI.path
                    exchange.reply(if (online) 200 else 503, "{\"success\":$online}")
                } else exchange.reply(404, "{}")
            }
            val repo = repository()
            api.login(repo, "a")
            val tracker = PlaybackSyncSessionTracker("synthetic-session")
            tracker.step("start", 0, 100_000, false, nowMs = 1_000)
            val stop = tracker.step("stop", 30_000, 100_000, true, nowMs = 2_000)
            repo.playbackProgressReporter.enqueueDecision(repo, "old-item", "Emby", null, stop, "synthetic-session", 100_000)?.join()
            assertEquals(1, progressPaths.size)
            api.login(repo, "b")
            online = true
            repo.playbackProgressReporter.flushPendingStops(repo)?.join()
            assertEquals(1, progressPaths.size)
            api.login(repo, "a", account = 8)
            repo.playbackProgressReporter.flushPendingStops(repo)?.join()
            assertEquals(1, progressPaths.size)
            api.login(repo, "a")
            repo.playbackProgressReporter.flushPendingStops(repo)?.join()
            assertEquals(listOf("/a/api/v1/mediaserver/progress", "/a/api/v1/mediaserver/progress"), progressPaths.toList())
        }
    }

    /** 分页日历必须传日期窗口，解析嵌套订阅、分集与无分集电影，不截断为 16 条订阅。 */
    @Test fun calendarUsesWindowAndAllPages() = runBlocking {
        ApiFixture().use { api ->
            val pages = CopyOnWriteArrayList<String>()
            api.route = { exchange ->
                val path = exchange.requestURI.path
                if (path.endsWith("/subscribe/")) exchange.reply(200, "[]")
                else if (path.endsWith("/subscribe/calendar")) {
                    val query = exchange.requestURI.rawQuery
                    pages += query
                    assertTrue(query.contains("start=2026-11-01") && query.contains("end=2026-11-08"))
                    val second = query.contains("page=2")
                    val episodes = if (second) "[]" else "[{\"episode_number\":17,\"name\":\"Episode\"}]"
                    exchange.reply(200, """{"success":true,"data":{"items":[{"date":"2026-11-02","subscribe":{"id":17,"name":"Synthetic","type":"${if (second) "电影" else "电视剧"}"},"episodes":$episodes}],"total":2}}""")
                } else exchange.reply(404, "{}")
            }
            val repo = repository(); api.login(repo, "a")
            val events = repo.fetchSubscribeCalendar(LocalDate.parse("2026-11-01"), LocalDate.parse("2026-11-08"))
            assertEquals(2, pages.size)
            assertEquals(2, events.size)
            assertEquals(17, events.first().episode)
            assertEquals("电影", events.last().type)
        }
    }

    /** 渠道授权使用真实成员 envelope、关联码路径和 PUT 停用，角色能力不会被重置。 */
    @Test fun authorizationsPreserveRoleAndScopes() = runBlocking {
        ApiFixture().use { api ->
            val updates = CopyOnWriteArrayList<String>()
            api.route = { exchange ->
                when (exchange.requestURI.path.substringAfter("/api/v1/")) {
                    "authorization/" -> exchange.reply(200, """{"success":true,"data":{"members":[{"id":"member-1","sender_id":"external-1","display_name":"Synthetic","linked_username":"member","channel":"telegram","status":"pending","role":"admin","scopes":["schedule"]}],"channels":[]}}""")
                    "authorization/binding" -> exchange.reply(200, """{"success":true,"data":{"code":"synthetic-code","expires_at":${System.currentTimeMillis() / 1000 + 120}}}""")
                    "authorization/member-1" -> {
                        assertEquals("PUT", exchange.requestMethod)
                        updates += exchange.requestBody.bufferedReader().readText()
                        exchange.reply(200, "{\"success\":true}")
                    }
                    else -> exchange.reply(404, "{}")
                }
            }
            val repo = repository(); api.login(repo, "a")
            val member = repo.fetchChannelAuthorizations().single()
            assertEquals("external-1", member.channelUserId)
            assertEquals("pending", member.status)
            assertEquals("synthetic-code", repo.generateChannelBindingCode().getOrThrow().code)
            assertTrue(repo.approveChannelAuthorization(member.id).first)
            assertTrue(repo.deleteChannelAuthorization(member.id).first)
            assertEquals(2, updates.size)
            assertTrue(updates.all { it.contains("\"role\":\"admin\"") && it.contains("\"scopes\":[\"schedule\"]") })
            assertTrue(updates.last().contains("\"status\":\"disabled\""))
        }
    }

    /** 模块诊断保留目录元数据，读取失败时不能伪装成空列表。 */
    @Test fun modulesUseSystemNamespace() = runBlocking {
        ApiFixture().use { api ->
            var failed = false
            api.route = { exchange ->
                if (exchange.requestURI.path.endsWith("/system/modulelist")) {
                    exchange.reply(if (failed) 500 else 200, """{"success":true,"data":{"modules":[{"id":"synthetic","name":"Synthetic","name_i18n":"合成模块"}]}}""")
                } else if (exchange.requestURI.path.endsWith("/system/module-catalog")) {
                    exchange.reply(200, """{"success":true,"data":{"modules":[{"id":"synthetic","type":"media","subtype":"synthetic"}]}}""")
                } else if (exchange.requestURI.path.endsWith("/system/moduletest/synthetic")) {
                    exchange.reply(200, """{"success":true,"message":"合成检查通过"}""")
                } else exchange.reply(404, "{}")
            }
            val repo = repository(); api.login(repo, "a")
            val module = repo.fetchSystemModules().single()
            assertEquals("synthetic", module.id)
            assertEquals("合成模块", module.name)
            assertEquals("media", module.moduleType)
            assertEquals("synthetic", module.subType)
            assertTrue(repo.testSystemModule(module.id).first)
            failed = true
            assertTrue(runCatching { repo.fetchSystemModules() }.isFailure)
        }
    }

    /** 独立内存存储，关闭凭据持久化以避免调用宿主机不存在的 Android Keystore。 */
    private fun repository(): MoviePilotRepository = MoviePilotRepository(MemoryContext.create()).also {
        it.secretStore.keepLogin = false
        it.secretStore.rememberCredentials = false
    }
}

/** 只监听本机随机端口的合同夹具，默认提供真实登录和当前用户协议。 */
private class ApiFixture : AutoCloseable {
    private val server = MockWebServer()
    val base: String get() = "http://127.0.0.1:${server.port}"
    private val handlerErrors = CopyOnWriteArrayList<Throwable>()
    var currentUser: ((TestExchange) -> Unit)? = null
    var account = 7
    var route: (TestExchange) -> Unit = { it.reply(404, "{}") }

    init {
        server.dispatcher = object : Dispatcher() {
          /** 每个真实 HTTP 请求交由当前案例的合成合同处理。 */
          override fun dispatch(request: RecordedRequest): MockResponse {
            try {
            val exchange = TestExchange(request)
            val instance = exchange.requestURI.path.split('/').getOrNull(1).orEmpty()
            when {
                exchange.requestURI.path.endsWith("/login/access-token") -> exchange.reply(200,
                    """{"access_token":"synthetic-$instance-$account","user_name":"member-$account","user_id":$account,"super_user":true,"permissions":{}}""")
                exchange.requestURI.path.endsWith("/user/current") -> {
                    val handler = currentUser
                    if (handler != null) handler(exchange) else exchange.reply(200,
                        """{"id":$account,"name":"member-$account","is_superuser":true,"permissions":{}}""")
                }
                exchange.requestURI.path.endsWith("/media/source") -> exchange.reply(200, "{}")
                else -> route(exchange)
            }
            return exchange.response
            } catch (error: Throwable) {
                handlerErrors += error
                return MockResponse().setResponseCode(500).setBody("synthetic-handler-failed")
            }
          }
        }
        server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
    }

    /** 使用生产登录流程切换实例和用户，不直接改写 Repository 会话。 */
    suspend fun login(repo: MoviePilotRepository, instance: String, account: Int = 7) {
        this.account = account
        val url = repo.connectServer("$base/$instance").getOrThrow()
        check(repo.login(url, "member-$account", "synthetic") is LoginOutcome.Success)
    }

    /** 停止本案例全部 HTTP 工作线程。 */
    override fun close() {
        server.shutdown()
        if (handlerErrors.isNotEmpty()) throw AssertionError("回环合同处理失败", handlerErrors.first())
    }
}

/** 将回环请求投影为简单的合成处理上下文，不替换客户端协议逻辑。 */
private class TestExchange(request: RecordedRequest) {
    val requestURI: URI = URI(request.path.orEmpty())
    val requestMethod: String = request.method.orEmpty()
    val requestHeaders: Map<String, List<String>> = request.headers.toMultimap()
    val requestBody = ByteArrayInputStream(request.body.readByteArray())
    val responseHeaders = okhttp3.Headers.Builder()
    var response = MockResponse()

    /** 设置本次合成响应，头和响应体由 MockWebServer 经真实 HTTP 发送。 */
    fun reply(status: Int, body: String) {
        response = MockResponse().setResponseCode(status).setHeaders(responseHeaders.build()).setBody(body)
    }
}

/** JVM 平台替身只替换 Context/偏好接口，网络、会话和 Rust 算法仍使用生产实现。 */
private class MemoryContext : ContextWrapper(null) {
    private lateinit var stores: MutableMap<String, SharedPreferences>
    /** 返回本案例自身，避免委托到无 Android Runtime 的父上下文。 */
    override fun getApplicationContext(): Context = this
    /** 按偏好文件隔离内存值，与 Android SharedPreferences 的立即可见语义一致。 */
    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        stores.getOrPut(name) { memoryPreferences() }

    companion object {
        /** 绕过 android.jar 的占位构造器；实际测试不执行任何 Android 系统服务。 */
        fun create(): MemoryContext {
            val type = Class.forName("sun.misc.Unsafe")
            val field = type.getDeclaredField("theUnsafe").apply { isAccessible = true }
            return (type.getMethod("allocateInstance", Class::class.java)
                .invoke(field.get(null), MemoryContext::class.java) as MemoryContext).also {
                it.stores = java.util.concurrent.ConcurrentHashMap()
            }
        }
    }
}

/** 用动态接口替身实现偏好读写，不模拟生产认证或传输逻辑。 */
private fun memoryPreferences(): SharedPreferences {
    val values = java.util.concurrent.ConcurrentHashMap<String, Any>()
    lateinit var editor: SharedPreferences.Editor
    editor = Proxy.newProxyInstance(SharedPreferences.Editor::class.java.classLoader,
        arrayOf(SharedPreferences.Editor::class.java)) { _, method, args ->
        when (method.name) {
            "apply" -> null
            "commit" -> true
            "clear" -> { values.clear(); editor }
            "remove" -> { values.remove(args!![0]); editor }
            else -> { if (method.name.startsWith("put")) {
                if (args!![1] == null) values.remove(args[0]) else values[args[0] as String] = args[1]
            }; editor }
        }
    } as SharedPreferences.Editor
    return Proxy.newProxyInstance(SharedPreferences::class.java.classLoader,
        arrayOf(SharedPreferences::class.java)) { _, method, args ->
        when (method.name) {
            "edit" -> editor
            "getAll" -> values.toMap()
            "contains" -> values.containsKey(args!![0])
            else -> if (method.name.startsWith("get")) values[args!![0]] ?: args[1] else null
        }
    } as SharedPreferences
}
