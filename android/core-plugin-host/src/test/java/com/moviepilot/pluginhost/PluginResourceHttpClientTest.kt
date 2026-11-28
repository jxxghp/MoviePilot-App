package com.moviepilot.pluginhost

import com.moviepilot.pluginhost.runtime.PluginResourceHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

/** 通过真实 HTTP 请求覆盖助手脚本冷加载、Cookie 轮换和会话隔离。 */
class PluginResourceHttpClientTest {
    /** 首次入口和之后的分块都应读取原生 Cookie 的最新值，并兼容自定义 Cookie 名。 */
    @Test fun coldEntryAndChunksReadCurrentResourceCookie() {
        MockWebServer().use { server ->
            server.start()
            var cookies = listOf("CustomProject=first; Path=/; HttpOnly")
            val client = PluginResourceHttpClient({ session(server, cookies) })
            server.enqueue(MockResponse().setBody("entry"))
            client.execute("/api/v1/plugin/AgentPets/frontend/assets/remoteEntry.js")!!.use {
                assertEquals("entry", it.body!!.string())
            }
            assertEquals("CustomProject=first", server.takeRequest().getHeader("Cookie"))
            cookies = listOf("CustomProject=rotated; Path=/; HttpOnly")
            server.enqueue(MockResponse().setBody("chunk"))
            client.execute("/api/v1/plugin/AgentPets/frontend/assets/chunk.js")!!.close()
            val chunk = server.takeRequest()
            assertEquals("CustomProject=rotated", chunk.getHeader("Cookie"))
            assertEquals("Bearer synthetic-token", chunk.getHeader("Authorization"))
        }
    }

    /** 资源 401 只刷新一次；第二次 401 保持可诊断的原始状态而不无限重试。 */
    @Test fun unauthorizedResourceRefreshesOnce() {
        MockWebServer().use { server ->
            server.start()
            var cookies = listOf("CustomProject=expired")
            var refreshes = 0
            val client = PluginResourceHttpClient({ session(server, cookies) }, {
                refreshes++
                cookies = listOf("CustomProject=fresh")
            })
            repeat(2) { server.enqueue(MockResponse().setResponseCode(401)) }
            client.execute("/api/v1/plugin/AgentPets/frontend/assets/remoteEntry.js")!!.use {
                assertEquals(401, it.code)
            }
            assertEquals(1, refreshes)
            assertEquals("CustomProject=expired", server.takeRequest().getHeader("Cookie"))
            assertEquals("CustomProject=fresh", server.takeRequest().getHeader("Cookie"))
            assertEquals(2, server.requestCount)
        }
    }

    /** 登出或刷新期间切换账号后，旧容器不能携带新会话凭据重试。 */
    @Test fun changedSessionStopsOldRequest() {
        MockWebServer().use { server ->
            server.start()
            var active: VuePluginSessionPayload? = session(server, listOf("CustomProject=old"))
            val client = PluginResourceHttpClient({ active }, {
                active = session(server, listOf("CustomProject=new")).copy(authToken = "other-token", userId = 2)
            })
            server.enqueue(MockResponse().setResponseCode(401))
            assertNull(client.execute("/api/v1/plugin/AgentPets/frontend/assets/remoteEntry.js"))
            server.takeRequest()
            assertNull(server.takeRequest(100, TimeUnit.MILLISECONDS))
            active = null
            assertNull(client.execute("/api/v1/plugin/AgentPets/frontend/assets/chunk.js"))
            assertEquals(1, server.requestCount)
        }
    }

    /** 上游跳转不得把实例 Token 或 Cookie 带往其他来源。 */
    @Test fun redirectsDoNotForwardCredentials() {
        MockWebServer().use { server ->
            MockWebServer().use { other ->
                server.start()
                other.start()
                server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", other.url("/foreign")))
                val client = PluginResourceHttpClient({ session(server, listOf("CustomProject=private")) })
                client.execute("/api/v1/plugin/AgentPets/frontend/assets/remoteEntry.js")!!.use {
                    assertEquals(302, it.code)
                }
                assertEquals(0, other.requestCount)
            }
        }
    }

    /** 创建仅包含合成凭据的测试会话。 */
    private fun session(server: MockWebServer, cookies: List<String>) = VuePluginSessionPayload(
        serverUrl = server.url("/").toString(),
        authToken = "synthetic-token",
        originCookies = cookies,
    )
}
