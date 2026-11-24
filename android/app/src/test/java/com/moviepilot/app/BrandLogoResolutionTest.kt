package com.moviepilot.app

import com.moviepilot.designsystem.resolveEntityLogoDrawable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 验证全套 36 枚官方品牌/服务徽标解析规则与浅色模式文本无障碍对比度。
 */
class BrandLogoResolutionTest {

    @Test
    fun resolvesAll36OfficialBrandLogoDrawables() {
        val cases = listOf(
            // 数据源 (4)
            Triple("datasource", "themoviedb", "logo_tmdb"),
            Triple("datasource", "douban", "logo_douban"),
            Triple("datasource", "bangumi", "logo_bangumi"),
            Triple("datasource", "musicbrainz", "logo_musicbrainz"),
            // 媒体服务器 (8)
            Triple("mediaserver", "emby", "logo_emby"),
            Triple("mediaserver", "jellyfin", "logo_jellyfin"),
            Triple("mediaserver", "plex", "logo_plex"),
            Triple("mediaserver", "trimemedia", "logo_trimemedia"),
            Triple("mediaserver", "ugreen", "logo_ugreen"),
            Triple("mediaserver", "zspace", "logo_zspace"),
            Triple("mediaserver", "vyo", "logo_vyo"),
            Triple("mediaserver", "custom_server", "logo_mediaserver"),
            // 下载器 (4)
            Triple("downloader", "qbittorrent", "logo_qbittorrent"),
            Triple("downloader", "transmission", "logo_transmission"),
            Triple("downloader", "rtorrent", "logo_rtorrent"),
            Triple("downloader", "default", "logo_downloader"),
            // 通知渠道 (12)
            Triple("notification", "wechat", "logo_wechat"),
            Triple("notification", "clawbot", "logo_clawbot"),
            Triple("notification", "feishu", "logo_feishu"),
            Triple("notification", "telegram", "logo_telegram"),
            Triple("notification", "qq", "logo_qq"),
            Triple("notification", "vocechat", "logo_vocechat"),
            Triple("notification", "synologychat", "logo_synologychat"),
            Triple("notification", "slack", "logo_slack"),
            Triple("notification", "discord", "logo_discord"),
            Triple("notification", "dingtalk", "logo_dingtalk"),
            Triple("notification", "webpush", "logo_chrome"),
            Triple("notification", "other", "logo_notification"),
            // 存储与网盘 (5)
            Triple("storage", "u115", "logo_u115"),
            Triple("storage", "alipan", "logo_alipan"),
            Triple("storage", "rclone", "logo_rclone"),
            Triple("storage", "smb", "logo_smb"),
            Triple("storage", "local", "logo_storage"),
            // 站点、插件与默认头像 (3)
            Triple("site", "mteam", "logo_site"),
            Triple("plugin", "AutoSignIn", "logo_plugin"),
            Triple("avatar", "admin", "logo_avatar_default"),
        )

        assertEquals(36, cases.map { it.third }.toSet().size)
        for ((kind, value, expected) in cases) {
            assertEquals("Mismatch for ($kind, $value)", expected, resolveEntityLogoDrawable(kind, value))
        }
    }

    @Test
    fun lightModeMutedTextMeetsWcagAaContrastOnWhiteSurface() {
        fun channelLum(c: Int): Double {
            val s = c / 255.0
            return if (s <= 0.03928) s / 12.92 else Math.pow((s + 0.055) / 1.055, 2.4)
        }
        // #5B647A on #FFFFFF
        val lumMuted = 0.2126 * channelLum(0x5B) + 0.7152 * channelLum(0x64) + 0.0722 * channelLum(0x7A)
        val lumWhite = 1.0
        val ratio = (lumWhite + 0.05) / (lumMuted + 0.05)
        assertTrue("Expected WCAG AA >= 4.5 contrast ratio, got $ratio", ratio >= 4.5)
    }
}
