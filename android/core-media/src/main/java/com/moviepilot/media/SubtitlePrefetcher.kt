package com.moviepilot.media

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import com.moviepilot.rustbridge.NativeSecretStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.Closeable
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * 嗅探识别出的真实外挂字幕格式及对应的本地扩展名与 Media3 MIME 类型。
 */
@OptIn(UnstableApi::class)
enum class DetectedSubtitleFormat(
    val extension: String,
    val mimeType: String,
) {
    ASS("ass", MimeTypes.TEXT_SSA),
    SSA("ssa", MimeTypes.TEXT_SSA),
    VTT("vtt", MimeTypes.TEXT_VTT),
    SRT("srt", MimeTypes.APPLICATION_SUBRIP);

    /** 是否属于 ASS / SSA 特效字幕格式。 */
    val isAssOrSsa: Boolean
        get() = this == ASS || this == SSA
}

/**
 * 单条外挂字幕预取与真实格式嗅探结果。
 */
data class PrefetchedSubtitle(
    val key: String,
    val subtitleId: String,
    val file: File,
    val format: DetectedSubtitleFormat,
    val mimeType: String,
    val hasEmbeddedFonts: Boolean,
) {
    /** 供 Media3 `SubtitleConfiguration` 直接挂载的本地文件 `Uri`。 */
    val localUri: Uri
        get() = Uri.fromFile(file)

    /** 是否为 ASS / SSA 格式字幕。 */
    val isAssOrSsa: Boolean
        get() = format.isAssOrSsa
}

/**
 * 外挂字幕受控预取与真实格式嗅探器：
 * 1. 复用当前播放会话的 `PlaybackHttpDataSource.createOkHttpClient`（完整保留自签名 TLS、同源 Bearer/Cookie/CF Access 注入与跨源凭据剥离）；
 * 2. 强制不携带 `Range` / `If-Range` 请求头并声明 `Accept-Encoding: identity`，连接超时 15s、读取超时 90s、流式体积硬上限 64 MiB，
 *    避免动态字体子集化反代（如 `fontInAss`）返回 `200 OK` 时触发后端 `501`；
 * 3. 结合 `Content-Type` 与前 4KB 文本头（兼容 UTF-8 / UTF-16 BOM）精准识别无后缀 URL 或 SRT 实时转 ASS 的真实格式，
 *    并全流扫描是否内嵌 `[Fonts]` UUencode 字体段；
 * 4. 落盘至 `cacheDir/mp_subtitles/sub_<hash>.<ext>`，支持同一会话并发请求合并去重、内存/磁盘复用与退出清理。
 */
@OptIn(UnstableApi::class)
class SubtitlePrefetcher(
    context: Context,
    private val request: MediaPlaybackRequest,
    private val activeStreamProvider: (() -> Pair<String, Map<String, String>>)? = null,
) : Closeable {

    private val appContext = context.applicationContext
    private val closed = AtomicBoolean(false)
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val activeCalls = CopyOnWriteArraySet<Call>()
    private val cachedResults = ConcurrentHashMap<String, PrefetchedSubtitle>()
    private val inFlightTasks = ConcurrentHashMap<String, Deferred<PrefetchedSubtitle>>()
    private val ownedFiles = CopyOnWriteArraySet<File>()
    private val cacheDir = File(appContext.cacheDir, CACHE_SUBDIR_NAME)

    private val httpClient: OkHttpClient by lazy {
        val allowInsecureTls = request.allowSelfSignedTls ||
            runCatching { NativeSecretStore(appContext).allowSelfSignedTls }.getOrDefault(false)
        val effectiveOrigin = request.originUrl.ifBlank { request.url }
        val effectiveOriginHeaders = request.sameOriginHeaders.ifEmpty { request.headers }
        PlaybackHttpDataSource.createOkHttpClient(
            originUrl = effectiveOrigin,
            headers = effectiveOriginHeaders,
            allowSelfSignedTls = allowInsecureTls,
            streamUrl = request.url,
            streamHeaders = request.streamHeaders,
            activeStreamProvider = activeStreamProvider,
        ).newBuilder()
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }

    /** 读取当前会话已预取成功的字幕结果（不触发网络请求）。 */
    fun getCached(sub: SubtitleTrackItem): PrefetchedSubtitle? {
        val key = subtitleKey(sub)
        val cached = cachedResults[key] ?: return null
        return if (cached.file.exists() && cached.file.length() > 0L) cached else null
    }

    /**
     * 异步预取指定外挂字幕并返回本地文件与嗅探元数据。
     * 同一字幕并发调用会自动共享底层同一个下载任务，外层超时取消不会中断后台正在进行的子集化流传输。
     */
    suspend fun prefetch(sub: SubtitleTrackItem): Result<PrefetchedSubtitle> {
        if (closed.get()) {
            return Result.failure(IOException("字幕预取器已关闭"))
        }
        getCached(sub)?.let { return Result.success(it) }

        val key = subtitleKey(sub)
        val deferred = synchronized(inFlightTasks) {
            getCached(sub)?.let { ready ->
                return Result.success(ready)
            }
            val existing = inFlightTasks[key]
            if (existing != null && existing.isActive) {
                existing
            } else {
                ioScope.async {
                    try {
                        val loaded = loadAndSniffSubtitle(key, sub)
                        cachedResults[key] = loaded
                        loaded
                    } finally {
                        inFlightTasks.remove(key)
                    }
                }.also { created ->
                    inFlightTasks[key] = created
                }
            }
        }

        return try {
            Result.success(deferred.await())
        } catch (ce: CancellationException) {
            throw ce
        } catch (err: Throwable) {
            android.util.Log.w(
                "SubtitlePrefetcher",
                "Failed to load subtitle key=$key: ${err.message}",
            )
            Result.failure(err)
        }
    }

    /** 执行单条字幕的本地检查或无 Range HTTP 流式下载与格式嗅探。 */
    private fun loadAndSniffSubtitle(key: String, sub: SubtitleTrackItem): PrefetchedSubtitle {
        val rawUrl = sub.url.trim()
        if (rawUrl.isBlank()) {
            throw IOException("外挂字幕地址为空")
        }
        if (rawUrl.startsWith("file://", ignoreCase = true)) {
            val path = Uri.parse(rawUrl).path?.takeIf { it.isNotBlank() }
                ?: throw IOException("无效的本地字幕路径")
            return inspectExistingLocalFile(key, sub, File(path))
        }
        if (rawUrl.startsWith("/")) {
            return inspectExistingLocalFile(key, sub, File(rawUrl))
        }
        if (!rawUrl.startsWith("http://", ignoreCase = true) && !rawUrl.startsWith("https://", ignoreCase = true)) {
            throw IOException("不支持的外挂字幕协议")
        }

        if (!cacheDir.exists() && !cacheDir.mkdirs() && !cacheDir.exists()) {
            throw IOException("无法创建外挂字幕缓存目录")
        }

        val hashHex = sha256ShortHex(key)
        findReusableDiskCache(key, sub, hashHex)?.let { reused ->
            ownedFiles.add(reused.file)
            return reused
        }

        val httpRequest = Request.Builder()
            .url(rawUrl)
            .get()
            .removeHeader("Range")
            .removeHeader("If-Range")
            .header("Accept-Encoding", "identity")
            .build()

        val tempFile = File(cacheDir, "sub_${hashHex}_${tempSeq.incrementAndGet()}.tmp")
        val call = httpClient.newCall(httpRequest)
        activeCalls.add(call)
        try {
            call.execute().use { resp ->
                if (!resp.isSuccessful) {
                    throw IOException("外挂字幕响应异常 (${resp.code})")
                }
                val declaredLen = resp.body?.contentLength() ?: -1L
                if (declaredLen > MAX_SUBTITLE_BYTES) {
                    throw IOException("外挂字幕体积超出 64MB 安全上限")
                }
                val bodyStream = resp.body?.byteStream()
                    ?: throw IOException("外挂字幕响应体为空")
                val contentType = resp.header("Content-Type")
                val streamed = streamToTempFileWithSniff(
                    input = bodyStream,
                    tempFile = tempFile,
                    contentType = contentType,
                    idHint = sub.id,
                    urlHint = rawUrl,
                )
                val targetFile = File(cacheDir, "sub_${hashHex}.${streamed.first.extension}")
                if (targetFile.exists()) {
                    runCatching { targetFile.delete() }
                }
                val finalFile = if (tempFile.renameTo(targetFile)) {
                    targetFile
                } else {
                    tempFile.copyTo(targetFile, overwrite = true)
                    runCatching { tempFile.delete() }
                    targetFile
                }
                ownedFiles.add(finalFile)
                return PrefetchedSubtitle(
                    key = key,
                    subtitleId = sub.id,
                    file = finalFile,
                    format = streamed.first,
                    mimeType = streamed.first.mimeType,
                    hasEmbeddedFonts = streamed.second,
                )
            }
        } catch (err: Throwable) {
            runCatching { tempFile.delete() }
            throw err
        } finally {
            activeCalls.remove(call)
        }
    }

    /** 检查本地已有字幕文件并完成头部嗅探与内嵌字体段检测。 */
    private fun inspectExistingLocalFile(
        key: String,
        sub: SubtitleTrackItem,
        localFile: File,
    ): PrefetchedSubtitle {
        if (!localFile.exists() || !localFile.isFile || localFile.length() <= 0L) {
            throw IOException("本地外挂字幕文件不存在或为空")
        }
        if (localFile.length() > MAX_SUBTITLE_BYTES) {
            throw IOException("本地外挂字幕超出 64MB 上限")
        }
        var format = DetectedSubtitleFormat.SRT
        var hasFonts = false
        FileInputStream(localFile).use { fis ->
            val inspected = inspectInputStreamOnly(fis, idHint = sub.id, urlHint = localFile.name)
            format = inspected.first
            hasFonts = inspected.second
        }
        return PrefetchedSubtitle(
            key = key,
            subtitleId = sub.id,
            file = localFile,
            format = format,
            mimeType = format.mimeType,
            hasEmbeddedFonts = hasFonts,
        )
    }

    /** 复用磁盘上未过期的同哈希字幕文件并重新快速校验格式与 `[Fonts]` 标记。 */
    private fun findReusableDiskCache(
        key: String,
        sub: SubtitleTrackItem,
        hashHex: String,
    ): PrefetchedSubtitle? {
        for (fmt in DetectedSubtitleFormat.entries) {
            val candidate = File(cacheDir, "sub_${hashHex}.${fmt.extension}")
            if (candidate.exists() && candidate.isFile && candidate.length() in 1L..MAX_SUBTITLE_BYTES) {
                return runCatching { inspectExistingLocalFile(key, sub, candidate) }.getOrNull()
            }
        }
        return null
    }

    /**
     * 将网络字幕流受控写入临时文件，同时采集前 4KB 嗅探头、前 256KB UTF-16 探测缓冲以及全流 `[Fonts]` 段落标记。
     */
    private fun streamToTempFileWithSniff(
        input: InputStream,
        tempFile: File,
        contentType: String?,
        idHint: String,
        urlHint: String,
    ): Pair<DetectedSubtitleFormat, Boolean> {
        val headerBuf = ByteArray(HEADER_SNIFF_BYTES)
        var headerLen = 0
        val utf16ProbeBuf = ByteArray(EMBEDDED_FONTS_UTF16_PROBE_BYTES)
        var utf16ProbeLen = 0
        var totalBytes = 0L
        var sawAsciiFontsMarker = false
        val overlapTail = ByteArray(32)
        var overlapLen = 0
        val chunk = ByteArray(32 * 1024)

        FileOutputStream(tempFile).use { fos ->
            while (!closed.get()) {
                val read = input.read(chunk)
                if (read < 0) break
                if (read == 0) continue
                totalBytes += read
                if (totalBytes > MAX_SUBTITLE_BYTES) {
                    throw IOException("外挂字幕体积超出 64MB 安全上限")
                }
                fos.write(chunk, 0, read)

                if (headerLen < HEADER_SNIFF_BYTES) {
                    val copy = minOf(read, HEADER_SNIFF_BYTES - headerLen)
                    System.arraycopy(chunk, 0, headerBuf, headerLen, copy)
                    headerLen += copy
                }
                if (utf16ProbeLen < EMBEDDED_FONTS_UTF16_PROBE_BYTES) {
                    val copy = minOf(read, EMBEDDED_FONTS_UTF16_PROBE_BYTES - utf16ProbeLen)
                    System.arraycopy(chunk, 0, utf16ProbeBuf, utf16ProbeLen, copy)
                    utf16ProbeLen += copy
                }
                if (!sawAsciiFontsMarker) {
                    if (containsAsciiFontsLineBreak(overlapTail, overlapLen, chunk, read)) {
                        sawAsciiFontsMarker = true
                    } else {
                        val nextOverlap = minOf(read, overlapTail.size)
                        System.arraycopy(chunk, read - nextOverlap, overlapTail, 0, nextOverlap)
                        overlapLen = nextOverlap
                    }
                }
            }
            fos.flush()
        }

        if (closed.get()) {
            throw IOException("字幕预取已取消")
        }
        if (totalBytes <= 0L) {
            throw IOException("外挂字幕内容为空")
        }

        val format = sniffSubtitleFormat(
            headerBytes = headerBuf,
            headerLen = headerLen,
            contentType = contentType,
            idHint = idHint,
            urlHint = urlHint,
        )
        val hasEmbeddedFonts = format.isAssOrSsa && containsEmbeddedFontsSection(
            prefixBytes = utf16ProbeBuf,
            prefixLen = utf16ProbeLen,
            sawAsciiFontsMarkerInStream = sawAsciiFontsMarker,
        )
        return format to hasEmbeddedFonts
    }

    /** 仅读取本地输入流完成格式与 `[Fonts]` 扫描（不额外复制文件）。 */
    private fun inspectInputStreamOnly(
        input: InputStream,
        idHint: String,
        urlHint: String,
    ): Pair<DetectedSubtitleFormat, Boolean> {
        val headerBuf = ByteArray(HEADER_SNIFF_BYTES)
        var headerLen = 0
        val utf16ProbeBuf = ByteArray(EMBEDDED_FONTS_UTF16_PROBE_BYTES)
        var utf16ProbeLen = 0
        var sawAsciiFontsMarker = false
        val overlapTail = ByteArray(32)
        var overlapLen = 0
        val chunk = ByteArray(32 * 1024)

        while (true) {
            val read = input.read(chunk)
            if (read < 0) break
            if (read == 0) continue
            if (headerLen < HEADER_SNIFF_BYTES) {
                val copy = minOf(read, HEADER_SNIFF_BYTES - headerLen)
                System.arraycopy(chunk, 0, headerBuf, headerLen, copy)
                headerLen += copy
            }
            if (utf16ProbeLen < EMBEDDED_FONTS_UTF16_PROBE_BYTES) {
                val copy = minOf(read, EMBEDDED_FONTS_UTF16_PROBE_BYTES - utf16ProbeLen)
                System.arraycopy(chunk, 0, utf16ProbeBuf, utf16ProbeLen, copy)
                utf16ProbeLen += copy
            }
            if (!sawAsciiFontsMarker) {
                if (containsAsciiFontsLineBreak(overlapTail, overlapLen, chunk, read)) {
                    sawAsciiFontsMarker = true
                } else {
                    val nextOverlap = minOf(read, overlapTail.size)
                    System.arraycopy(chunk, read - nextOverlap, overlapTail, 0, nextOverlap)
                    overlapLen = nextOverlap
                }
            }
        }
        val format = sniffSubtitleFormat(
            headerBytes = headerBuf,
            headerLen = headerLen,
            contentType = null,
            idHint = idHint,
            urlHint = urlHint,
        )
        val hasEmbeddedFonts = format.isAssOrSsa && containsEmbeddedFontsSection(
            prefixBytes = utf16ProbeBuf,
            prefixLen = utf16ProbeLen,
            sawAsciiFontsMarkerInStream = sawAsciiFontsMarker,
        )
        return format to hasEmbeddedFonts
    }

    /** 关闭预取器并异步清理当前会话落地的外挂字幕缓存文件。 */
    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        activeCalls.forEach { runCatching { it.cancel() } }
        activeCalls.clear()
        inFlightTasks.values.forEach { runCatching { it.cancel() } }
        inFlightTasks.clear()
        cachedResults.clear()
        ioScope.cancel()
        val toDelete = ownedFiles.toList()
        ownedFiles.clear()
        val dirRef = cacheDir
        Thread({
            toDelete.forEach { runCatching { it.delete() } }
            // 顺带清理目录中超过 6 小时的陈旧残留临时字幕
            val cutoff = System.currentTimeMillis() - 6L * 3600_000L
            dirRef.listFiles()?.forEach { f ->
                if (f.isFile && (f.name.endsWith(".tmp") || f.lastModified() < cutoff)) {
                    runCatching { f.delete() }
                }
            }
        }, "mp-subtitle-cleanup").apply { isDaemon = true }.start()
    }

    companion object {
        /** 单条外挂字幕最大允许下载字节数（64 MiB，兼容内嵌子集化字体的 ASS）。 */
        const val MAX_SUBTITLE_BYTES: Long = 64L * 1024L * 1024L

        private const val CONNECT_TIMEOUT_SECONDS: Long = 15L
        private const val READ_TIMEOUT_SECONDS: Long = 90L
        private const val HEADER_SNIFF_BYTES: Int = 4 * 1024
        private const val EMBEDDED_FONTS_UTF16_PROBE_BYTES: Int = 256 * 1024
        private const val CACHE_SUBDIR_NAME: String = "mp_subtitles"
        private val tempSeq = AtomicLong(0L)

        /** 生成外挂字幕在当前播放会话中的唯一缓存键。 */
        fun subtitleKey(sub: SubtitleTrackItem): String =
            "${sub.id.trim()}|${sub.url.trim()}"

        /**
         * 综合前 4KB 文本头、`Content-Type` 响应头与原始后缀提示识别真实字幕格式。
         */
        fun sniffSubtitleFormat(
            headerBytes: ByteArray,
            headerLen: Int,
            contentType: String?,
            idHint: String,
            urlHint: String,
        ): DetectedSubtitleFormat {
            val headerText = decodeHeaderSample(headerBytes, headerLen)
                .trimStart('\uFEFF', ' ', '\t', '\r', '\n')
            val lowerHeader = headerText.lowercase()

            if (
                lowerHeader.contains("[script info]") ||
                lowerHeader.contains("scripttype:") ||
                lowerHeader.contains("[v4+ styles]") ||
                lowerHeader.contains("[v4 styles]")
            ) {
                val isLegacySsaOnly = lowerHeader.contains("[v4 styles]") &&
                    !lowerHeader.contains("[v4+ styles]") &&
                    !lowerHeader.contains("v4.00+") &&
                    (idHint.lowercase().endsWith(".ssa") || urlHint.substringBefore('?').lowercase().endsWith(".ssa"))
                return if (isLegacySsaOnly) DetectedSubtitleFormat.SSA else DetectedSubtitleFormat.ASS
            }
            if (lowerHeader.startsWith("webvtt")) {
                return DetectedSubtitleFormat.VTT
            }

            val cleanMime = contentType
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase()
                .orEmpty()
            when (cleanMime) {
                "text/x-ssa", "text/x-ass", "application/x-ssa", "application/x-ass" ->
                    return DetectedSubtitleFormat.ASS
                "text/vtt" ->
                    return DetectedSubtitleFormat.VTT
                "application/x-subrip", "text/srt" ->
                    return DetectedSubtitleFormat.SRT
            }

            val combinedTail = "${idHint.lowercase()} ${urlHint.substringBefore('?').lowercase()}"
            return when {
                combinedTail.endsWith(".ass") || combinedTail.contains(".ass ") -> DetectedSubtitleFormat.ASS
                combinedTail.endsWith(".ssa") || combinedTail.contains(".ssa ") -> DetectedSubtitleFormat.SSA
                combinedTail.endsWith(".vtt") || combinedTail.contains(".vtt ") -> DetectedSubtitleFormat.VTT
                else -> DetectedSubtitleFormat.SRT
            }
        }

        /**
         * 判断字幕流是否包含 ASS `[Fonts]` 内嵌字体段落（兼容 UTF-8 / GB18030 全流扫描及 UTF-16 前 256KB 文本检测）。
         */
        fun containsEmbeddedFontsSection(
            prefixBytes: ByteArray,
            prefixLen: Int,
            sawAsciiFontsMarkerInStream: Boolean,
        ): Boolean {
            if (sawAsciiFontsMarkerInStream) return true
            if (prefixLen <= 0) return false
            val isUtf16 = prefixLen >= 2 && (
                (prefixBytes[0] == 0xFF.toByte() && prefixBytes[1] == 0xFE.toByte()) ||
                    (prefixBytes[0] == 0xFE.toByte() && prefixBytes[1] == 0xFF.toByte())
                )
            val decoded = if (isUtf16 || prefixLen <= HEADER_SNIFF_BYTES) {
                decodeHeaderSample(prefixBytes, prefixLen).lowercase()
            } else {
                decodeHeaderSample(prefixBytes, minOf(prefixLen, HEADER_SNIFF_BYTES)).lowercase()
            }
            return decoded.startsWith("[fonts]") ||
                decoded.contains("\n[fonts]") ||
                decoded.contains("\r[fonts]")
        }

        /** 解码字节样本前部（自动识别 UTF-8 BOM、UTF-16 LE/BE，默认宽容 UTF-8 解码）。 */
        private fun decodeHeaderSample(bytes: ByteArray, length: Int): String {
            if (length <= 0) return ""
            return when {
                length >= 3 &&
                    bytes[0] == 0xEF.toByte() &&
                    bytes[1] == 0xBB.toByte() &&
                    bytes[2] == 0xBF.toByte() ->
                    String(bytes, 3, length - 3, Charsets.UTF_8)

                length >= 2 &&
                    bytes[0] == 0xFF.toByte() &&
                    bytes[1] == 0xFE.toByte() ->
                    String(bytes, 2, (length - 2) and -2, Charsets.UTF_16LE)

                length >= 2 &&
                    bytes[0] == 0xFE.toByte() &&
                    bytes[1] == 0xFF.toByte() ->
                    String(bytes, 2, (length - 2) and -2, Charsets.UTF_16BE)

                else -> String(bytes, 0, length, Charsets.UTF_8)
            }
        }

        /** 在跨分块滑动窗口中零拷贝检测 ASCII `\n[Fonts]`（兼容 `\r\n[Fonts]`，大小写不敏感）。 */
        private fun containsAsciiFontsLineBreak(
            tail: ByteArray,
            tailLen: Int,
            chunk: ByteArray,
            chunkLen: Int,
        ): Boolean {
            val total = tailLen + chunkLen
            // 目标模式 "\n[fonts]" 长度为 8 字节，且后续字符需为换行、回车、空白或流末尾
            if (total < 8) return false

            fun byteAt(idx: Int): Int {
                val b = if (idx < tailLen) tail[idx] else chunk[idx - tailLen]
                return b.toInt() and 0xFF
            }

            fun lowerAscii(c: Int): Int = if (c in 65..90) c + 32 else c

            val limit = total - 8
            var i = 0
            while (i <= limit) {
                val c0 = byteAt(i)
                if ((c0 == 0x0A || c0 == 0x0D) &&
                    byteAt(i + 1) == 0x5B && // '['
                    lowerAscii(byteAt(i + 2)) == 0x66 && // 'f'
                    lowerAscii(byteAt(i + 3)) == 0x6F && // 'o'
                    lowerAscii(byteAt(i + 4)) == 0x6E && // 'n'
                    lowerAscii(byteAt(i + 5)) == 0x74 && // 't'
                    lowerAscii(byteAt(i + 6)) == 0x73 && // 's'
                    byteAt(i + 7) == 0x5D // ']'
                ) {
                    if (i + 8 >= total) return true
                    val after = byteAt(i + 8)
                    if (after == 0x0A || after == 0x0D || after == 0x20 || after == 0x09) {
                        return true
                    }
                }
                i++
            }
            return false
        }

        private fun sha256ShortHex(input: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
            val sb = StringBuilder(24)
            for (i in 0 until 12) {
                sb.append("%02x".format(digest[i]))
            }
            return sb.toString()
        }
    }
}
