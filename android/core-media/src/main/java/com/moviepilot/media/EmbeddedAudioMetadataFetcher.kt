package com.moviepilot.media

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Metadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.flac.PictureFrame
import androidx.media3.extractor.metadata.flac.VorbisComment
import androidx.media3.extractor.metadata.id3.ApicFrame
import androidx.media3.extractor.metadata.id3.CommentFrame
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import com.moviepilot.rustbridge.AudioEmbeddedMetadataDto
import com.moviepilot.rustbridge.NativeSecretStore
import com.moviepilot.rustbridge.RustCoreBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest

/** 从音频流或本地文件解析出的内嵌标题、艺人、专辑、歌词与封面。 */
data class ResolvedEmbeddedAudioMetadata(
    val title: String? = null,
    val artist: String? = null,
    val album: String? = null,
    val lyrics: String? = null,
    val artworkFileUri: String? = null,
    val artworkBytes: ByteArray? = null,
) {
    val hasAnyContent: Boolean
        get() = !title.isNullOrBlank() ||
            !artist.isNullOrBlank() ||
            !album.isNullOrBlank() ||
            !lyrics.isNullOrBlank() ||
            !artworkFileUri.isNullOrBlank() ||
            (artworkBytes != null && artworkBytes.isNotEmpty())
}

/**
 * 音频内嵌封面与歌词提取器（支持本地文件与远端 HTTP Range 音频流）：
 * - 零额外后端版本依赖，直接通过有界 HTTP Range（首段 256 KiB，按需追加至多 6 MiB 或 M4A 尾部 512 KiB）
 *   委托 Rust 共享内核解析 FLAC / ID3v2 / MP4·M4A / Ogg Vorbis·Opus 内嵌封面与歌词；
 * - 同时支持直接消费 Media3 `ExoPlayer` 已解码的 `MediaMetadata` 与 `Format.metadata`（零额外网络请求）；
 * - 封面图缓存至 `cacheDir/mp_embedded_artwork/` 并限制容量，供 Coil、动态取色引擎、迷你条与系统 `MediaSession` 复用。
 */
object EmbeddedAudioMetadataFetcher {
    private const val INITIAL_HEAD_BYTES = 256 * 1024
    private const val MAX_HEAD_BYTES = 6 * 1024 * 1024
    private const val TAIL_BYTES = 512 * 1024
    private const val MAX_CACHED_ARTWORK_FILES = 60

    private val AUDIO_EXT_REGEX = Regex(
        """\.(flac|mp3|m4a|aac|ogg|oga|opus|wav|aiff|aif|alac|ape|wv|wma|dsf|dff|mka)$""",
        RegexOption.IGNORE_CASE,
    )

    private val LRC_META_TAG_REGEX = Regex(
        """^\[(ti|ar|al|au|by|offset|re|ve|length):.*]$""",
        RegexOption.IGNORE_CASE,
    )

    /**
     * 提取无时间轴的纯文本歌词行（供未携带 `[mm:ss]` 时间标签的内嵌 `USLT` / `LYRICS` / `©lyr` 展示）。
     */
    fun extractPlainLyricsLines(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        return raw.replace("\r\n", "\n")
            .replace("\r", "\n")
            .split("\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() && !LRC_META_TAG_REGEX.matches(it) }
    }

    /**
     * 判断当前播放请求是否缺失封面、歌词或标题仍为原始带后缀文件名，需要执行内嵌元数据探测。
     */
    fun needsExtraction(request: MediaPlaybackRequest): Boolean {
        if (!request.isAudio || request.url.isBlank()) return false
        val missingArt = request.artworkUrl.isNullOrBlank() && (request.artworkBytes == null || request.artworkBytes.isEmpty())
        val missingLyrics = request.lyricsLrc.isNullOrBlank()
        val rawFileTitle = AUDIO_EXT_REGEX.containsMatchIn(request.title.trim())
        return missingArt || missingLyrics || rawFileTitle
    }

    /**
     * 将提取到的内嵌元数据无损合并至 `MediaPlaybackRequest`：
     * 绝不覆盖已有远端封面或外挂同步 LRC 歌词；当标题为原始文件名时升级为可读曲名并补全艺人/专辑副标题。
     */
    fun applyToRequest(
        request: MediaPlaybackRequest,
        meta: ResolvedEmbeddedAudioMetadata?,
    ): MediaPlaybackRequest {
        if (meta == null || !meta.hasAnyContent) return request
        val rawTitle = request.title.trim()
        val shouldReplaceTitle = rawTitle.isBlank() || AUDIO_EXT_REGEX.containsMatchIn(rawTitle)
        val newTitle = if (shouldReplaceTitle && !meta.title.isNullOrBlank()) {
            meta.title.trim()
        } else {
            request.title
        }
        val tagSub = listOfNotNull(
            meta.artist?.trim()?.takeIf { it.isNotEmpty() },
            meta.album?.trim()?.takeIf { it.isNotEmpty() },
        ).joinToString(" · ")
        val newSubtitle = when {
            request.subtitle.isBlank() && tagSub.isNotEmpty() -> tagSub
            (request.subtitle.contains(" · /") || request.subtitle.startsWith("local ·") || request.subtitle.startsWith("smb ·")) && tagSub.isNotEmpty() ->
                tagSub
            else -> request.subtitle
        }
        val newAlbum = request.albumTitle.ifBlank { meta.album?.trim().orEmpty() }
        val newArtworkUrl = request.artworkUrl?.takeIf { it.isNotBlank() } ?: meta.artworkFileUri
        val newArtworkBytes = request.artworkBytes?.takeIf { it.isNotEmpty() } ?: meta.artworkBytes
        val newLyrics = request.lyricsLrc?.takeIf { it.isNotBlank() } ?: meta.lyrics?.takeIf { it.isNotBlank() }

        return request.copy(
            title = newTitle,
            subtitle = newSubtitle,
            albumTitle = newAlbum,
            artworkUrl = newArtworkUrl,
            artworkBytes = newArtworkBytes,
            lyricsLrc = newLyrics,
        )
    }

    /**
     * 零网络快路径：从 Media3 `ExoPlayer` 已解析的 `mediaMetadata` 与当前音轨 `Format.metadata` 中提取内嵌封面与歌词。
     */
    @OptIn(UnstableApi::class)
    fun extractFromExoPlayer(
        context: Context,
        player: Player,
        cacheKey: String,
    ): ResolvedEmbeddedAudioMetadata? {
        val mm = player.mediaMetadata
        var title = mm.title?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        var artist = (mm.artist ?: mm.albumArtist)?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        var album = mm.albumTitle?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        var lyrics: String? = null
        var coverBytes: ByteArray? = mm.artworkData?.takeIf { it.isNotEmpty() }
        var coverMime: String? = null

        fun inspectMetadata(metadata: Metadata?) {
            if (metadata == null) return
            for (i in 0 until metadata.length()) {
                when (val entry = metadata.get(i)) {
                    is VorbisComment -> {
                        val key = entry.key.trim().uppercase()
                        val value = entry.value.trim()
                        if (value.isEmpty()) continue
                        when (key) {
                            "TITLE" -> if (title == null) title = value
                            "ARTIST", "ALBUMARTIST", "ALBUM ARTIST" -> if (artist == null) artist = value
                            "ALBUM" -> if (album == null) album = value
                            "SYNCEDLYRICS", "LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "LYRIC", "SLT", "LRC" -> {
                                if (lyrics == null || (parseLrcLyrics(lyrics).isEmpty() && parseLrcLyrics(value).isNotEmpty())) {
                                    lyrics = value
                                }
                            }
                        }
                    }

                    is PictureFrame -> {
                        if (entry.pictureData.isNotEmpty() && (coverBytes == null || entry.pictureType == 3)) {
                            coverBytes = entry.pictureData
                            coverMime = entry.mimeType
                        }
                    }

                    is ApicFrame -> {
                        if (entry.pictureData.isNotEmpty() && (coverBytes == null || entry.pictureType == 3)) {
                            coverBytes = entry.pictureData
                            coverMime = entry.mimeType
                        }
                    }

                    is TextInformationFrame -> {
                        val id = entry.id.uppercase()
                        val value = entry.values.firstOrNull()?.trim().orEmpty()
                        if (value.isEmpty()) continue
                        when (id) {
                            "USLT", "ULT" -> {
                                if (lyrics == null || (parseLrcLyrics(lyrics).isEmpty() && parseLrcLyrics(value).isNotEmpty())) {
                                    lyrics = value
                                }
                            }

                            "TXXX" -> {
                                val desc = entry.description?.trim()?.uppercase().orEmpty()
                                if (desc in setOf("LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "SYNCEDLYRICS", "LYRIC", "LRC")) {
                                    if (lyrics == null || (parseLrcLyrics(lyrics).isEmpty() && parseLrcLyrics(value).isNotEmpty())) {
                                        lyrics = value
                                    }
                                }
                            }
                        }
                    }

                    is CommentFrame -> {
                        val desc = entry.description.trim().uppercase()
                        val value = entry.text.trim()
                        if (value.isNotEmpty() && (desc.contains("LYRIC") || parseLrcLyrics(value).isNotEmpty())) {
                            if (lyrics == null || (parseLrcLyrics(lyrics).isEmpty() && parseLrcLyrics(value).isNotEmpty())) {
                                lyrics = value
                            }
                        }
                    }
                }
            }
        }

        for (group in player.currentTracks.groups) {
            if (group.type != C.TRACK_TYPE_AUDIO) continue
            for (idx in 0 until group.length) {
                inspectMetadata(group.getTrackFormat(idx).metadata)
            }
        }

        val artUri = coverBytes?.let { persistArtworkToCache(context, cacheKey, it, coverMime) }
        val result = ResolvedEmbeddedAudioMetadata(
            title = title,
            artist = artist,
            album = album,
            lyrics = lyrics,
            artworkFileUri = artUri,
            artworkBytes = coverBytes,
        )
        return result.takeIf { it.hasAnyContent }
    }

    /**
     * 通过本地文件句柄或有界 HTTP Range 拉取音频头部（按需追加至多 6 MiB 或 M4A 尾部 512 KiB），
     * 委托 Rust 共享内核提取内嵌封面与歌词。
     */
    suspend fun fetchEmbeddedMetadata(
        context: Context,
        request: MediaPlaybackRequest,
    ): ResolvedEmbeddedAudioMetadata? = withContext(Dispatchers.IO) {
        if (!request.isAudio || request.url.isBlank()) return@withContext null
        val parsed = runCatching {
            val uri = Uri.parse(request.url)
            val scheme = uri.scheme?.lowercase().orEmpty()
            when {
                scheme == "http" || scheme == "https" -> fetchFromHttpRange(context, request)
                scheme == "file" || request.url.startsWith("/") -> {
                    val filePath = if (scheme == "file") uri.path.orEmpty() else request.url
                    readFromLocalFile(File(filePath))
                }

                scheme == "content" -> readFromContentUri(context, uri)
                else -> null
            }
        }.getOrNull() ?: return@withContext null

        val coverBytes = parsed.coverBytes?.takeIf { it.isNotEmpty() }
        val artworkUri = coverBytes?.let {
            persistArtworkToCache(context, request.localResumeId.ifBlank { request.url }, it, parsed.coverMime)
        }
        ResolvedEmbeddedAudioMetadata(
            title = parsed.title?.takeIf { it.isNotBlank() },
            artist = parsed.artist?.takeIf { it.isNotBlank() },
            album = parsed.album?.takeIf { it.isNotBlank() },
            lyrics = parsed.lyrics?.takeIf { it.isNotBlank() },
            artworkFileUri = artworkUri,
            artworkBytes = coverBytes,
        ).takeIf { it.hasAnyContent }
    }

    /** 仅针对本机 URI 同步提取内嵌歌词与元数据（供 `LocalMediaMetadataExtractor` 使用）。 */
    fun extractFromLocalUriBlocking(context: Context, uri: Uri): AudioEmbeddedMetadataDto? = runCatching {
        when (uri.scheme?.lowercase()) {
            "file" -> uri.path?.let { readFromLocalFile(File(it)) }
            "content" -> readFromContentUri(context, uri)
            null, "" -> readFromLocalFile(File(uri.toString()))
            else -> null
        }
    }.getOrNull()

    private fun readFromLocalFile(file: File): AudioEmbeddedMetadataDto? {
        if (!file.isFile || !file.canRead()) return null
        val fileLen = file.length()
        if (fileLen <= 4L) return null
        return RandomAccessFile(file, "r").use { raf ->
            val firstLen = minOf(fileLen, INITIAL_HEAD_BYTES.toLong()).toInt()
            var head = ByteArray(firstLen)
            raf.seek(0L)
            raf.readFully(head)
            var parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head)

            val neededHead = parsed.neededHeadBytes
            if (neededHead != null && neededHead > head.size.toLong() && fileLen > head.size.toLong()) {
                val targetLen = minOf(fileLen, neededHead, MAX_HEAD_BYTES.toLong()).toInt()
                if (targetLen > head.size) {
                    val expanded = head.copyOf(targetLen)
                    raf.seek(head.size.toLong())
                    raf.readFully(expanded, head.size, targetLen - head.size)
                    head = expanded
                    parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head)
                }
            }

            val neededTail = parsed.neededTailBytes
            if (neededTail != null && fileLen > head.size.toLong()) {
                val tailLen = minOf(fileLen, neededTail.coerceAtLeast(TAIL_BYTES.toLong()), (2 * 1024 * 1024).toLong()).toInt()
                val tailStart = (fileLen - tailLen).coerceAtLeast(0L)
                val tail = ByteArray(tailLen)
                raf.seek(tailStart)
                raf.readFully(tail)
                parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head, tail)
            }
            parsed
        }
    }

    private fun readFromContentUri(context: Context, uri: Uri): AudioEmbeddedMetadataDto? {
        val head = readBoundedPrefix(context, uri, INITIAL_HEAD_BYTES) ?: return null
        var parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head)
        val neededHead = parsed.neededHeadBytes
        if (neededHead != null && neededHead > head.size.toLong()) {
            val target = minOf(neededHead, MAX_HEAD_BYTES.toLong()).toInt()
            val larger = readBoundedPrefix(context, uri, target)
            if (larger != null && larger.size > head.size) {
                parsed = RustCoreBridge.parseAudioEmbeddedMetadata(larger)
            }
        }
        return parsed
    }

    private fun readBoundedPrefix(context: Context, uri: Uri, maxBytes: Int): ByteArray? {
        return context.contentResolver.openInputStream(uri)?.use { input ->
            val out = java.io.ByteArrayOutputStream(minOf(maxBytes, 65_536))
            val buf = ByteArray(16_384)
            var remaining = maxBytes
            while (remaining > 0) {
                val n = input.read(buf, 0, minOf(buf.size, remaining))
                if (n <= 0) break
                out.write(buf, 0, n)
                remaining -= n
            }
            out.toByteArray().takeIf { it.isNotEmpty() }
        }
    }

    private data class RangeFetchResult(
        val bytes: ByteArray,
        val totalSize: Long?,
        val partial: Boolean,
    )

    private fun fetchFromHttpRange(
        context: Context,
        request: MediaPlaybackRequest,
    ): AudioEmbeddedMetadataDto? {
        val allowInsecureTls = request.allowSelfSignedTls ||
            runCatching { NativeSecretStore(context).allowSelfSignedTls }.getOrDefault(false)
        val effectiveOrigin = request.originUrl.ifBlank { request.url }
        val effectiveOriginHeaders = request.sameOriginHeaders.ifEmpty { request.headers }
        val client = PlaybackHttpDataSource.createOkHttpClient(
            originUrl = effectiveOrigin,
            headers = effectiveOriginHeaders,
            allowSelfSignedTls = allowInsecureTls,
            streamUrl = request.url,
            streamHeaders = request.streamHeaders,
        )

        val first = fetchRangeChunk(client, request.url, 0L, (INITIAL_HEAD_BYTES - 1).toLong(), INITIAL_HEAD_BYTES)
            ?: return null
        var head = first.bytes
        var parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head)

        // 若内嵌封面（如 FLAC Picture 或 ID3 APIC）大于首段 256 KiB，执行一次有界追加 Range 拉取
        val neededHead = parsed.neededHeadBytes
        if (first.partial && neededHead != null && neededHead > head.size.toLong()) {
            val targetTotal = minOf(neededHead, MAX_HEAD_BYTES.toLong())
            val maxBySize = first.totalSize?.let { minOf(targetTotal, it) } ?: targetTotal
            if (maxBySize > head.size.toLong()) {
                val extraLen = (maxBySize - head.size.toLong()).toInt()
                val more = fetchRangeChunk(
                    client = client,
                    url = request.url,
                    start = head.size.toLong(),
                    endInclusive = maxBySize - 1L,
                    maxAcceptBytes = extraLen + 4096,
                )
                if (more != null && more.bytes.isNotEmpty()) {
                    head = head + more.bytes
                    parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head)
                }
            }
        }

        // 若为非 faststart M4A（moov 在末尾），拉取文件末尾 512 KiB 解析 ilst 原子
        val neededTail = parsed.neededTailBytes
        val totalSize = first.totalSize
        if (first.partial && neededTail != null && totalSize != null && totalSize > head.size.toLong()) {
            val tailLen = minOf(totalSize, maxOf(neededTail, TAIL_BYTES.toLong()), (2 * 1024 * 1024).toLong())
            val tailStart = (totalSize - tailLen).coerceAtLeast(0L)
            val tail = fetchRangeChunk(
                client = client,
                url = request.url,
                start = tailStart,
                endInclusive = totalSize - 1L,
                maxAcceptBytes = tailLen.toInt() + 4096,
            )
            if (tail != null && tail.bytes.isNotEmpty()) {
                parsed = RustCoreBridge.parseAudioEmbeddedMetadata(head, tail.bytes)
            }
        }

        return parsed
    }

    private fun fetchRangeChunk(
        client: OkHttpClient,
        url: String,
        start: Long,
        endInclusive: Long,
        maxAcceptBytes: Int,
    ): RangeFetchResult? {
        val req = Request.Builder()
            .url(url)
            .get()
            .header("Range", "bytes=$start-$endInclusive")
            .header("Accept-Encoding", "identity")
            .build()
        return runCatching {
            client.newCall(req).execute().use { resp ->
                if (resp.code != 206 && resp.code != 200) return@use null
                val partial = resp.code == 206
                val contentRange = resp.header("Content-Range")
                val totalSize = parseContentRangeTotal(contentRange)
                    ?: if (!partial) resp.header("Content-Length")?.toLongOrNull() else null
                val body = resp.body ?: return@use null
                val source = body.byteStream()
                val out = java.io.ByteArrayOutputStream(minOf(maxAcceptBytes, 65_536))
                val buf = ByteArray(16_384)
                var remaining = maxAcceptBytes
                while (remaining > 0) {
                    val n = source.read(buf, 0, minOf(buf.size, remaining))
                    if (n <= 0) break
                    out.write(buf, 0, n)
                    remaining -= n
                }
                val bytes = out.toByteArray()
                if (bytes.isEmpty()) null else RangeFetchResult(bytes, totalSize, partial)
            }
        }.getOrNull()
    }

    private fun parseContentRangeTotal(header: String?): Long? {
        if (header.isNullOrBlank()) return null
        val slash = header.lastIndexOf('/')
        if (slash < 0 || slash + 1 >= header.length) return null
        return header.substring(slash + 1).trim().toLongOrNull()
    }

    private fun persistArtworkToCache(
        context: Context,
        cacheKey: String,
        bytes: ByteArray,
        mime: String?,
    ): String? = runCatching {
        val ext = when {
            mime?.contains("png", ignoreCase = true) == true -> "png"
            mime?.contains("webp", ignoreCase = true) == true -> "webp"
            mime?.contains("gif", ignoreCase = true) == true -> "gif"
            else -> "jpg"
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(cacheKey.toByteArray(Charsets.UTF_8))
            .take(12)
            .joinToString("") { "%02x".format(it) }
        val artDir = File(context.cacheDir, "mp_embedded_artwork").apply { mkdirs() }
        val files = artDir.listFiles()
        if (files != null && files.size > MAX_CACHED_ARTWORK_FILES) {
            files.sortedBy { it.lastModified() }
                .take(files.size - MAX_CACHED_ARTWORK_FILES + 10)
                .forEach { runCatching { it.delete() } }
        }
        val target = File(artDir, "art_$digest.$ext")
        if (!target.exists() || target.length() != bytes.size.toLong()) {
            target.writeBytes(bytes)
        } else {
            target.setLastModified(System.currentTimeMillis())
        }
        Uri.fromFile(target).toString()
    }.getOrNull()
}
