package com.moviepilot.media.engine

import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * 面向 `libmpv` 的单会话一次性令牌本地环回代理（仅绑定 `127.0.0.1:0`）：
 * 1. 复用 `PlaybackHttpDataSource.createOkHttpClient` 的全部安全策略（自签名 TLS、同源 Cookie/Bearer 隔离、跨源 302 令牌剥离）；
 * 2. 强制要求路径携带 128-bit 随机一次性会话令牌，拒绝任何非法路径或外部网络访问；
 * 3. 支持 HTTP `GET` / `HEAD` 与 `Range` 字节区间请求，完整透传 `200`/`206` 与流式分块转发；
 * 4. 支持运行期热更新主目标路由（直连 -> 代理降级）以及注册外挂字幕路径，销毁时立即断开所有上游连接。
 */
class LoopbackAuthProxy(
    private val okHttpClient: OkHttpClient,
    initialTargetUrl: String,
    private val streamHeadersRef: AtomicReference<Pair<String, Map<String, String>>>? = null,
) : Closeable {

    private val sessionToken: String = generateRandomHexToken()
    private val targetUrlRef = AtomicReference(initialTargetUrl)
    private val extraRoutes = ConcurrentHashMap<String, String>()
    private val closed = AtomicBoolean(false)
    private val activeCalls = CopyOnWriteArraySet<Call>()
    private val serverSocket = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
    private val acceptExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "mp-loopback-accept").apply { isDaemon = true }
    }
    private val workerExecutor = Executors.newCachedThreadPool { r ->
        Thread(r, "mp-loopback-worker").apply { isDaemon = true }
    }

    /** 监听的本机环回随机端口。 */
    val port: Int
        get() = serverSocket.localPort

    /** 供 `libmpv` 加载的主流本机环回地址（含单会话随机令牌，绝不暴露实例主凭据）。 */
    val streamUrl: String
        get() = "http://127.0.0.1:$port/$sessionToken/stream"

    init {
        acceptExecutor.execute { acceptLoop() }
    }

    /** 热更新主媒体目标地址（例如直连失败降级回代理流时，无需重建环回端口）。 */
    fun updatePrimaryTarget(url: String, headers: Map<String, String> = emptyMap()) {
        targetUrlRef.set(url)
        streamHeadersRef?.set(url to headers)
    }

    /** 为外挂字幕注册独立的本机环回访问地址，沿用同一受控 OkHttp 鉴权通道。 */
    fun registerAuxiliaryTarget(key: String, remoteUrl: String): String {
        val safeKey = key.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "sub" }
        extraRoutes[safeKey] = remoteUrl
        return "http://127.0.0.1:$port/$sessionToken/aux/$safeKey"
    }

    private fun acceptLoop() {
        while (!closed.get() && !serverSocket.isClosed) {
            val socket = runCatching { serverSocket.accept() }.getOrNull() ?: break
            if (closed.get()) {
                runCatching { socket.close() }
                break
            }
            workerExecutor.execute { handleClient(socket) }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { sock ->
            sock.soTimeout = 30_000
            val input = BufferedInputStream(sock.getInputStream())
            val output = sock.getOutputStream()

            val requestLine = readAsciiLine(input) ?: return
            val parts = requestLine.split(' ')
            if (parts.size < 2) {
                writeSimpleStatus(output, 400, "Bad Request")
                return
            }
            val method = parts[0].uppercase()
            if (method != "GET" && method != "HEAD") {
                writeSimpleStatus(output, 405, "Method Not Allowed")
                return
            }
            val rawPath = parts[1].substringBefore('?')
            var rangeHeader: String? = null
            var ifRangeHeader: String? = null
            while (true) {
                val line = readAsciiLine(input) ?: break
                if (line.isEmpty()) break
                val colon = line.indexOf(':')
                if (colon > 0) {
                    val name = line.substring(0, colon).trim().lowercase()
                    val value = line.substring(colon + 1).trim()
                    when (name) {
                        "range" -> rangeHeader = value
                        "if-range" -> ifRangeHeader = value
                    }
                }
            }

            val remoteUrl = resolveRemoteUrl(rawPath)
            if (remoteUrl == null) {
                writeSimpleStatus(output, 403, "Forbidden")
                return
            }

            val reqBuilder = Request.Builder().url(remoteUrl)
            if (method == "HEAD") {
                reqBuilder.head()
            } else {
                reqBuilder.get()
            }
            rangeHeader?.takeIf { it.isNotBlank() }?.let { reqBuilder.header("Range", it) }
            ifRangeHeader?.takeIf { it.isNotBlank() }?.let { reqBuilder.header("If-Range", it) }

            val call = okHttpClient.newCall(reqBuilder.build())
            activeCalls.add(call)
            try {
                call.execute().use { resp ->
                    val statusLine = "HTTP/1.1 ${resp.code} ${resp.message.ifBlank { "OK" }}\r\n"
                    val headersBuf = StringBuilder(statusLine)
                    resp.header("Content-Type")?.let { headersBuf.append("Content-Type: ").append(it).append("\r\n") }
                    resp.header("Content-Length")?.let { headersBuf.append("Content-Length: ").append(it).append("\r\n") }
                    resp.header("Content-Range")?.let { headersBuf.append("Content-Range: ").append(it).append("\r\n") }
                    val acceptRanges = resp.header("Accept-Ranges") ?: "bytes"
                    headersBuf.append("Accept-Ranges: ").append(acceptRanges).append("\r\n")
                    headersBuf.append("Connection: close\r\n\r\n")
                    output.write(headersBuf.toString().toByteArray(Charsets.ISO_8859_1))
                    output.flush()

                    if (method != "HEAD") {
                        val bodyStream = resp.body?.byteStream()
                        if (bodyStream != null) {
                            val buffer = ByteArray(64 * 1024)
                            while (!closed.get()) {
                                val read = bodyStream.read(buffer)
                                if (read <= 0) break
                                output.write(buffer, 0, read)
                            }
                            output.flush()
                        }
                    }
                }
            } catch (_: Throwable) {
                runCatching { writeSimpleStatus(output, 502, "Bad Gateway") }
            } finally {
                activeCalls.remove(call)
            }
        }
    }

    private fun resolveRemoteUrl(path: String): String? {
        val streamPrefix = "/$sessionToken/stream"
        if (path == streamPrefix) {
            return targetUrlRef.get().takeIf { it.isNotBlank() }
        }
        val auxPrefix = "/$sessionToken/aux/"
        if (path.startsWith(auxPrefix)) {
            val key = path.removePrefix(auxPrefix)
            return extraRoutes[key]
        }
        return null
    }

    private fun readAsciiLine(input: BufferedInputStream): String? {
        val baos = ByteArrayOutputStream(128)
        var sawAny = false
        while (baos.size() < 8192) {
            val b = input.read()
            if (b == -1) break
            sawAny = true
            if (b == '\n'.code) break
            if (b != '\r'.code) baos.write(b)
        }
        return if (!sawAny) null else baos.toString(Charsets.ISO_8859_1.name())
    }

    private fun writeSimpleStatus(output: OutputStream, code: Int, reason: String) {
        val payload = "HTTP/1.1 $code $reason\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        runCatching {
            output.write(payload.toByteArray(Charsets.ISO_8859_1))
            output.flush()
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        activeCalls.forEach { runCatching { it.cancel() } }
        activeCalls.clear()
        runCatching { serverSocket.close() }
        acceptExecutor.shutdownNow()
        workerExecutor.shutdownNow()
    }

    companion object {
        private fun generateRandomHexToken(): String {
            val bytes = ByteArray(16)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
