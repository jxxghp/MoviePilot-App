package com.moviepilot.pluginhost.runtime

import android.content.Context
import com.moviepilot.rustbridge.RustCoreBridge
import java.io.File

/**
 * Android 端联邦插件远程产物磁盘缓存（按实例源 SHA-256 / 插件 ID / 版本或产物哈希三级隔离，50MB LRU）。
 */
object PluginRemoteDiskCache {
    private const val ROOT_DIR = "plugin-remote-cache"
    private const val MAX_BYTES = 50L * 1024L * 1024L
    private val lock = Any()

    data class CachedEntry(
        val bytes: ByteArray,
        val mimeType: String,
    )

    fun read(
        context: Context,
        instanceOrigin: String,
        pluginId: String,
        versionTag: String,
        assetRelPath: String,
    ): CachedEntry? = synchronized(lock) {
        val file = resolveFile(context, instanceOrigin, pluginId, versionTag, assetRelPath) ?: return null
        if (!file.isFile) return null
        val bytes = runCatching { file.readBytes() }.getOrNull() ?: return null
        runCatching { file.setLastModified(System.currentTimeMillis()) }
        val metaFile = File(file.parentFile, "${file.name}.mime")
        val mime = runCatching {
            metaFile.takeIf { it.isFile }?.readText(Charsets.UTF_8)?.trim()
        }.getOrNull().takeUnless { it.isNullOrBlank() } ?: guessMimeType(assetRelPath)
        CachedEntry(bytes, mime)
    }

    fun write(
        context: Context,
        instanceOrigin: String,
        pluginId: String,
        versionTag: String,
        assetRelPath: String,
        bytes: ByteArray,
        mimeType: String,
    ) {
        synchronized(lock) {
            val file = resolveFile(context, instanceOrigin, pluginId, versionTag, assetRelPath) ?: return
            runCatching {
                file.parentFile?.mkdirs()
                val tmp = File(file.parentFile, "${file.name}.tmp")
                tmp.writeBytes(bytes)
                if (file.exists()) file.delete()
                tmp.renameTo(file)
                File(file.parentFile, "${file.name}.mime").writeText(mimeType, Charsets.UTF_8)
                pruneOlderVersions(context, instanceOrigin, pluginId, versionTag)
                enforceBudget(context)
            }
        }
    }

    fun diskUsageBytes(context: Context): Long = synchronized(lock) {
        val root = File(context.cacheDir, ROOT_DIR)
        if (!root.isDirectory) return 0L
        root.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    fun clearAll(context: Context) = synchronized(lock) {
        runCatching { File(context.cacheDir, ROOT_DIR).deleteRecursively() }
    }

    private fun resolveFile(
        context: Context,
        instanceOrigin: String,
        pluginId: String,
        versionTag: String,
        assetRelPath: String,
    ): File? {
        val key = RustCoreBridge.buildPluginRemoteCacheKey(instanceOrigin, pluginId, versionTag)
        val baseDir = File(File(context.cacheDir, ROOT_DIR), key.relativeDir).canonicalFile
        val target = File(baseDir, assetRelPath).canonicalFile
        if (!target.path.startsWith(baseDir.path + File.separator)) return null
        return target
    }

    private fun pruneOlderVersions(
        context: Context,
        instanceOrigin: String,
        pluginId: String,
        keepVersion: String,
    ) {
        val key = RustCoreBridge.buildPluginRemoteCacheKey(instanceOrigin, pluginId, keepVersion)
        val pluginDir = File(File(File(context.cacheDir, ROOT_DIR), key.instanceHash), key.pluginIdLower)
        pluginDir.listFiles()?.forEach { child ->
            if (child.name != key.versionSegment) {
                runCatching { child.deleteRecursively() }
            }
        }
    }

    private fun enforceBudget(context: Context) {
        val root = File(context.cacheDir, ROOT_DIR)
        if (!root.isDirectory) return
        val files = root.walkTopDown().filter { it.isFile && !it.name.endsWith(".mime") }.toList()
        var total = files.sumOf { it.length() }
        if (total <= MAX_BYTES) return
        val target = (MAX_BYTES * 4L) / 5L
        for (file in files.sortedBy { it.lastModified() }) {
            if (total <= target) break
            total -= file.length()
            runCatching { file.delete() }
            runCatching { File(file.parentFile, "${file.name}.mime").delete() }
        }
    }

    fun guessMimeType(path: String): String {
        val clean = path.substringBefore('#').substringBefore('?').lowercase()
        return when (clean.substringAfterLast('.', "")) {
            "html", "htm" -> "text/html"
            "js", "mjs", "cjs" -> "application/javascript"
            "css" -> "text/css"
            "json", "map" -> "application/json"
            "svg" -> "image/svg+xml"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "ico" -> "image/x-icon"
            "woff" -> "font/woff"
            "woff2" -> "font/woff2"
            "ttf" -> "font/ttf"
            "wasm" -> "application/wasm"
            else -> "application/octet-stream"
        }
    }
}
