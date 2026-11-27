package com.moviepilot.rustbridge

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.security.SecureRandom

/**
 * Android 端通行密钥（`moviepilot.passkey` v1）系统浏览器会话协调器：
 * - 生成 32 字节 `SecureRandom` 状态种子（64 位十六进制）；
 * - 单次接收 `MainActivity.handleIntent` 投递的 `moviepilot://passkey/callback#result=...`；
 * - 若用户在浏览器标签页中直接点击返回而未触发深链回调，`MainActivity.onResume` 经短暂宽限期后自动解除等待，避免界面卡死加载态。
 */
object PasskeyAuthManager {

    private data class PendingSession(
        val deferred: CompletableDeferred<Result<String>>,
        val launchedAtMs: Long,
        @Volatile var resumeGraceJob: Job? = null,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @Volatile
    private var pending: PendingSession? = null

    /** 生成 32 字节密码学安全随机数的 64 位十六进制字符串。 */
    fun generateStateHex32(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /** 由 `MainActivity.handleIntent` 在收到 `moviepilot://passkey/callback#result=...` 时调用。 */
    fun handleCallbackUri(rawUri: String): Boolean {
        val current = pending ?: return false
        pending = null
        current.resumeGraceJob?.cancel()
        return current.deferred.complete(Result.success(rawUri))
    }

    /**
     * 由 `MainActivity.onResume` 调用：若浏览器拉起已超过 1.2s，且回到前台 900ms 后仍未收到深链回调，
     * 判定为用户关闭了浏览器并主动取消等待。
     */
    fun notifyActivityResumed() {
        val current = pending ?: return
        if (System.currentTimeMillis() - current.launchedAtMs < 1_200L) return
        current.resumeGraceJob?.cancel()
        current.resumeGraceJob = scope.launch {
            delay(900L)
            if (pending === current && !current.deferred.isCompleted) {
                pending = null
                current.deferred.complete(Result.failure(PasskeyCanceledException()))
            }
        }
    }

    /** 主动取消尚未完成的浏览器回调等待。 */
    fun cancelPending() {
        val current = pending ?: return
        pending = null
        current.resumeGraceJob?.cancel()
        current.deferred.complete(Result.failure(PasskeyCanceledException()))
    }

    /** 拉起系统浏览器访问公开认证页 `authorizeUrl` 并等待一次性回调。 */
    suspend fun awaitBrowserCallback(
        authorizeUrl: String,
        timeoutSecs: Long,
        launchBrowser: (String) -> Unit,
    ): Result<String> {
        cancelPending()
        val deferred = CompletableDeferred<Result<String>>()
        val session = PendingSession(
            deferred = deferred,
            launchedAtMs = System.currentTimeMillis(),
        )
        pending = session
        val launched = runCatching { launchBrowser(authorizeUrl) }
        if (launched.isFailure) {
            if (pending === session) pending = null
            return Result.failure(IllegalStateException("failed"))
        }
        val timeoutMs = (timeoutSecs.coerceIn(5L, 120L)) * 1_000L
        val awaited = withTimeoutOrNull(timeoutMs) {
            deferred.await()
        }
        if (pending === session) {
            pending = null
            session.resumeGraceJob?.cancel()
        }
        return awaited ?: Result.failure(IllegalStateException("expired"))
    }
}

/** 标记用户主动取消通行密钥验证（不作为错误横幅展示）。 */
class PasskeyCanceledException : Exception("canceled")
