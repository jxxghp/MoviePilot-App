package com.moviepilot.media.engine

import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.LoudnessEnhancer
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.EngineResolutionInputDto
import com.moviepilot.rustbridge.EngineResolutionPlanDto
import com.moviepilot.rustbridge.RustCoreBridge

/** Android 端实际生效的播放内核标识（`native` = Media3 ExoPlayer，`enhanced` = libmpv 全能内核）。 */
enum class ResolvedAndroidEngine(
    val id: String,
    val displayName: String,
    val shortBadge: String,
) {
    NATIVE("native", "Media3 原生", "Media3"),
    ENHANCED("enhanced", "MPV 全能", "MPV");

    companion object {
        fun fromId(raw: String?): ResolvedAndroidEngine =
            entries.firstOrNull { it.id == raw?.lowercase() } ?: NATIVE
    }
}

/** 跨内核统一音轨 / 字幕轨道模型。 */
data class EngineTrackItem(
    val id: String,
    val label: String,
    val language: String?,
    val isSelected: Boolean,
)

/** Android 端统一选核入口：调用 Rust `resolvePlaybackEngine` 决定主内核与失败自动回退内核。 */
object AndroidPlaybackEngineRouter {

    /** 结合用户播放偏好与当前媒体特征生成选核决策计划。 */
    fun resolvePlan(
        request: MediaPlaybackRequest,
        prefs: PlaybackPreferencesStore,
        preferredOverride: String? = null,
    ): EngineResolutionPlanDto {
        val hasAssOrPgs = request.subtitles.any { sub ->
            val probe = "${sub.id} ${sub.url}".lowercase()
            probe.contains(".ass") || probe.contains(".ssa") || probe.contains(".sup") || probe.contains(".pgs")
        }
        val input = EngineResolutionInputDto(
            platform = "android",
            preferred = preferredOverride ?: prefs.videoEngine,
            isAudio = request.isAudio,
            decodeForceSoftware = prefs.decodeMode == "sw_force",
            hasEnhancedEngine = true,
            hasLegacyEngine = false,
            urlOrFilename = request.tempFilePath?.takeIf { it.isNotBlank() } ?: request.url,
            hasAssOrPgsSubtitle = hasAssOrPgs,
            ignoreAssStyle = prefs.ignoreAssStyle,
            allowSelfSignedTls = request.allowSelfSignedTls,
        )
        return RustCoreBridge.resolvePlaybackEngine(input)
    }
}

/**
 * Media3 原生内核夜间模式 / 人声增强音频后处理管理器：
 * 优先使用 API 28+ `DynamicsProcessing` 启用轻量单段动态压缩（抬升对白、抑制爆炸峰值），
 * 机型驱动不支持时安全降级到 `LoudnessEnhancer`，绝不阻塞或中断播放。
 */
class AudioNightModeEffect {
    private var dynamics: DynamicsProcessing? = null
    private var loudness: LoudnessEnhancer? = null
    private var boundSessionId: Int = 0

    /** 将夜间模式动态压缩绑定到指定 `audioSessionId`；若关闭或会话无效则安全释放。 */
    fun apply(audioSessionId: Int, enabled: Boolean) {
        if (!enabled || audioSessionId <= 0) {
            release()
            return
        }
        if (boundSessionId == audioSessionId && (dynamics != null || loudness != null)) {
            return
        }
        release()
        boundSessionId = audioSessionId
        val attachedDynamics = runCatching {
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                2,
                false,
                0,
                true,
                1,
                false,
                0,
                true,
            ).build()
            DynamicsProcessing(0, audioSessionId, config).apply {
                val mbc = DynamicsProcessing.Mbc(true, true, 1)
                val band = DynamicsProcessing.MbcBand(
                    true,
                    20_000f,
                    5f,
                    150f,
                    3.5f,
                    -22f,
                    6f,
                    -60f,
                    1.0f,
                    3.5f,
                    4.0f,
                )
                mbc.setBand(0, band)
                setMbcAllChannelsTo(mbc)
                val limiter = DynamicsProcessing.Limiter(true, true, 0, 2f, 60f, 4f, -1.5f, 0f)
                setLimiterAllChannelsTo(limiter)
                this.enabled = true
            }
        }.getOrNull()
        if (attachedDynamics != null) {
            dynamics = attachedDynamics
            return
        }
        loudness = runCatching {
            LoudnessEnhancer(audioSessionId).apply {
                setTargetGain(450)
                this.enabled = true
            }
        }.getOrNull()
    }

    /** 释放底层音频效果器资源。 */
    fun release() {
        runCatching { dynamics?.release() }
        runCatching { loudness?.release() }
        dynamics = null
        loudness = null
        boundSessionId = 0
    }
}
