package com.moviepilot.pluginhost.runtime

import com.moviepilot.pluginhost.VuePluginSessionPayload
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.util.concurrent.TimeUnit

/** 为已校验的插件资源路径读取最新同源会话，资源 Cookie 失效时最多刷新重试一次。 */
internal class PluginResourceHttpClient(
    private val sessionProvider: () -> VuePluginSessionPayload?,
    private val refreshResourceCookie: (() -> Unit)? = null,
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .build()

    /** 每次回源重新取 Cookie；刷新期间会话发生变化时拒绝使用新账号凭据重试旧请求。 */
    fun execute(validatedApiPath: String): Response? {
        val owner = sessionProvider() ?: return null
        val response = fetch(owner, validatedApiPath)
        if (response.code != 401 || refreshResourceCookie == null) return response
        response.close()
        refreshResourceCookie.invoke()
        val latest = sessionProvider() ?: return null
        if (latest.serverUrl != owner.serverUrl || latest.authToken != owner.authToken ||
            latest.userId != owner.userId || latest.userName != owner.userName
        ) return null
        return fetch(latest, validatedApiPath)
    }

    /** 仅向当前实例的原生校验路径发送请求，禁止自动跳转携带凭据。 */
    private fun fetch(session: VuePluginSessionPayload, validatedApiPath: String): Response {
        val request = Request.Builder()
            .url("${session.serverUrl.trimEnd('/')}$validatedApiPath")
            .header("Authorization", "Bearer ${session.authToken}")
            .header("X-MoviePilot-Locale", "zh-CN")
        val cookies = session.originCookies.mapNotNull {
            it.substringBefore(';').trim().takeIf(String::isNotEmpty)
        }.joinToString("; ")
        if (cookies.isNotEmpty()) request.header("Cookie", cookies)
        return client.newCall(request.build()).execute()
    }
}
