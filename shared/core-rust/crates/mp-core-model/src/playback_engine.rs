//! 跨端多内核媒体播放选核决策与外部播放器 URL 模板校验（iOS / Android / HarmonyOS NEXT 共享）。
//!
//! 职责：
//! 1. 根据平台能力、用户偏好（`auto` / `native` / `enhanced` / `legacy`）、解码模式（硬解/强软解）
//!    与媒体特征（封装、音视频编码、ASS/PGS 字幕、自签名 TLS），确定主播放内核与自动降级备选内核；
//! 2. 安全校验用户自定义的外部播放器 URL Scheme 模板，拒绝危险协议与实例凭据泄露。

use serde::{Deserialize, Serialize};
use url::Url;

/// 客户端平台类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlatformKind {
    Ios,
    Android,
    Harmony,
}

/// 用户在设置页选择的视频内核模式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PlaybackEngineChoice {
    #[default]
    Auto,
    Native,
    Enhanced,
    Legacy,
}

/// 路由决策后的实际播放内核类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResolvedPlaybackEngine {
    Native,
    Enhanced,
    Legacy,
}

impl ResolvedPlaybackEngine {
    /// 返回面向用户展示的默认简体中文内核名称（对应 `shared/l10n/app.strings.json`）。
    pub fn display_label_zh(self, platform: PlatformKind) -> &'static str {
        match (platform, self) {
            (PlatformKind::Ios, Self::Native) => "AVPlayer 原生",
            (PlatformKind::Ios, Self::Enhanced) => "MPV 全能",
            (PlatformKind::Ios, Self::Legacy) => "VLCKit 兼容",
            (PlatformKind::Android, Self::Native) => "Media3 原生",
            (PlatformKind::Android, Self::Enhanced) => "MPV 全能",
            (PlatformKind::Android, Self::Legacy) => "Media3 原生",
            (PlatformKind::Harmony, Self::Native) => "AVPlayer 原生",
            (PlatformKind::Harmony, Self::Enhanced) => "IJK 增强",
            (PlatformKind::Harmony, Self::Legacy) => "AVPlayer 原生",
        }
    }
}

/// 解码模式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum DecodeMode {
    #[default]
    HwAuto,
    SwForce,
}

/// 网络缓冲档位。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum BufferProfile {
    #[default]
    Standard,
    Large,
}

/// 选核决策输入。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EngineResolutionInput {
    pub platform: PlatformKind,
    #[serde(default)]
    pub preferred: PlaybackEngineChoice,
    #[serde(default)]
    pub is_audio: bool,
    #[serde(default)]
    pub decode_force_software: bool,
    #[serde(default = "default_true")]
    pub has_enhanced_engine: bool,
    #[serde(default)]
    pub has_legacy_engine: bool,
    #[serde(default)]
    pub url_or_filename: String,
    #[serde(default)]
    pub container_hint: Option<String>,
    #[serde(default)]
    pub audio_codec_hint: Option<String>,
    #[serde(default)]
    pub video_codec_hint: Option<String>,
    #[serde(default)]
    pub has_ass_or_pgs_subtitle: bool,
    #[serde(default)]
    pub ignore_ass_style: bool,
    #[serde(default)]
    pub allow_self_signed_tls: bool,
}

fn default_true() -> bool {
    true
}

/// 选核决策结果：主内核、自动降级备选内核、原因码与展示标签。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EngineResolutionPlan {
    pub primary: ResolvedPlaybackEngine,
    pub fallback: Option<ResolvedPlaybackEngine>,
    pub reason_code: String,
    pub engine_label_zh: String,
}

/// 跨端无状态播放内核路由器。
pub struct PlaybackEngineRouter;

impl PlaybackEngineRouter {
    /// 根据平台能力、用户设置和媒体特征计算最优主播放内核及降级备选内核。
    pub fn resolve(input: &EngineResolutionInput) -> EngineResolutionPlan {
        let is_available = |engine: ResolvedPlaybackEngine| -> bool {
            match engine {
                ResolvedPlaybackEngine::Native => true,
                ResolvedPlaybackEngine::Enhanced => input.has_enhanced_engine,
                ResolvedPlaybackEngine::Legacy => {
                    input.platform == PlatformKind::Ios && input.has_legacy_engine
                }
            }
        };

        let make_plan = |primary: ResolvedPlaybackEngine,
                         fallback: Option<ResolvedPlaybackEngine>,
                         reason: &str|
         -> EngineResolutionPlan {
            let eff_primary = if is_available(primary) {
                primary
            } else {
                ResolvedPlaybackEngine::Native
            };
            let eff_fallback = fallback.filter(|fb| *fb != eff_primary && is_available(*fb));
            EngineResolutionPlan {
                primary: eff_primary,
                fallback: eff_fallback,
                reason_code: reason.to_string(),
                engine_label_zh: eff_primary.display_label_zh(input.platform).to_string(),
            }
        };

        // 1. 用户显式锁定特定内核（音频始终优先原生除非用户锁定且该内核可用）
        match input.preferred {
            PlaybackEngineChoice::Native => {
                let fb = if input.has_enhanced_engine {
                    Some(ResolvedPlaybackEngine::Enhanced)
                } else if is_available(ResolvedPlaybackEngine::Legacy) {
                    Some(ResolvedPlaybackEngine::Legacy)
                } else {
                    None
                };
                return make_plan(ResolvedPlaybackEngine::Native, fb, "user_pinned_native");
            }
            PlaybackEngineChoice::Enhanced => {
                if input.has_enhanced_engine {
                    let fb = if is_available(ResolvedPlaybackEngine::Legacy) {
                        Some(ResolvedPlaybackEngine::Legacy)
                    } else {
                        Some(ResolvedPlaybackEngine::Native)
                    };
                    return make_plan(ResolvedPlaybackEngine::Enhanced, fb, "user_pinned_enhanced");
                }
                return make_plan(ResolvedPlaybackEngine::Native, None, "enhanced_unavailable");
            }
            PlaybackEngineChoice::Legacy => {
                if is_available(ResolvedPlaybackEngine::Legacy) {
                    let fb = if input.has_enhanced_engine {
                        Some(ResolvedPlaybackEngine::Enhanced)
                    } else {
                        Some(ResolvedPlaybackEngine::Native)
                    };
                    return make_plan(ResolvedPlaybackEngine::Legacy, fb, "user_pinned_legacy");
                }
                let fb = if input.has_enhanced_engine {
                    Some(ResolvedPlaybackEngine::Enhanced)
                } else {
                    None
                };
                return make_plan(
                    fb.unwrap_or(ResolvedPlaybackEngine::Native),
                    Some(ResolvedPlaybackEngine::Native),
                    "legacy_unavailable",
                );
            }
            PlaybackEngineChoice::Auto => {}
        }

        // 2. 音频自动分流：默认走系统原生省电，仅冷门无损/多声道格式切增强内核
        if input.is_audio {
            let ext = Self::extract_extension(&input.url_or_filename);
            let audio_codec = Self::normalize_hint(input.audio_codec_hint.as_deref());
            let exotic_audio = matches!(
                ext.as_str(),
                "ape" | "wv" | "dsf" | "dff" | "dts" | "ac3" | "eac3" | "mlp" | "thd"
            ) || matches!(
                audio_codec.as_str(),
                "ape" | "wavpack" | "dsd" | "dts" | "dca" | "ac3" | "eac3" | "truehd"
            );
            if exotic_audio && input.has_enhanced_engine {
                return make_plan(
                    ResolvedPlaybackEngine::Enhanced,
                    Some(ResolvedPlaybackEngine::Native),
                    "audio_exotic_enhanced",
                );
            }
            return make_plan(
                ResolvedPlaybackEngine::Native,
                if input.has_enhanced_engine {
                    Some(ResolvedPlaybackEngine::Enhanced)
                } else if is_available(ResolvedPlaybackEngine::Legacy) {
                    Some(ResolvedPlaybackEngine::Legacy)
                } else {
                    None
                },
                "audio_native",
            );
        }

        // 3. 视频强制软解：原生内核不支持完整视频软解，自动路由到增强内核
        if input.decode_force_software && input.has_enhanced_engine {
            return make_plan(
                ResolvedPlaybackEngine::Enhanced,
                Some(ResolvedPlaybackEngine::Native),
                "force_software_decode",
            );
        }

        let container = Self::resolve_container(input);
        let audio_codec = Self::normalize_hint(input.audio_codec_hint.as_deref());
        let video_codec = Self::normalize_hint(input.video_codec_hint.as_deref());
        let needs_rich_subtitle = input.has_ass_or_pgs_subtitle && !input.ignore_ass_style;

        match input.platform {
            PlatformKind::Ios => {
                let standard_native_container =
                    matches!(container.as_str(), "mp4" | "m4v" | "mov" | "m3u8" | "hls");
                let unsupported_audio =
                    matches!(audio_codec.as_str(), "dts" | "dca" | "truehd" | "mlp");
                let unsupported_video = matches!(
                    video_codec.as_str(),
                    "av1" | "vc1" | "mpeg2" | "mpeg2video" | "vp9" | "hi10p" | "rv40"
                );
                if standard_native_container
                    && !unsupported_audio
                    && !unsupported_video
                    && !needs_rich_subtitle
                    && !input.allow_self_signed_tls
                {
                    let fb = if input.has_enhanced_engine {
                        Some(ResolvedPlaybackEngine::Enhanced)
                    } else if is_available(ResolvedPlaybackEngine::Legacy) {
                        Some(ResolvedPlaybackEngine::Legacy)
                    } else {
                        None
                    };
                    make_plan(ResolvedPlaybackEngine::Native, fb, "ios_native_standard")
                } else if input.has_enhanced_engine {
                    let fb = if is_available(ResolvedPlaybackEngine::Legacy) {
                        Some(ResolvedPlaybackEngine::Legacy)
                    } else {
                        Some(ResolvedPlaybackEngine::Native)
                    };
                    make_plan(
                        ResolvedPlaybackEngine::Enhanced,
                        fb,
                        if needs_rich_subtitle {
                            "mkv_or_ass_enhanced"
                        } else if input.allow_self_signed_tls {
                            "ios_self_signed_tls_enhanced"
                        } else {
                            "ios_container_or_codec_enhanced"
                        },
                    )
                } else if is_available(ResolvedPlaybackEngine::Legacy) {
                    make_plan(
                        ResolvedPlaybackEngine::Legacy,
                        Some(ResolvedPlaybackEngine::Native),
                        "ios_legacy_fallback",
                    )
                } else {
                    make_plan(ResolvedPlaybackEngine::Native, None, "ios_native_only")
                }
            }
            PlatformKind::Android => {
                let hard_video = matches!(
                    video_codec.as_str(),
                    "vc1" | "mpeg2" | "mpeg2video" | "hi10p" | "rv40" | "wmv3"
                ) || matches!(container.as_str(), "rmvb" | "rm" | "avi" | "wmv");
                if (needs_rich_subtitle || hard_video) && input.has_enhanced_engine {
                    make_plan(
                        ResolvedPlaybackEngine::Enhanced,
                        Some(ResolvedPlaybackEngine::Native),
                        if needs_rich_subtitle {
                            "android_ass_or_pgs_enhanced"
                        } else {
                            "android_codec_enhanced"
                        },
                    )
                } else {
                    make_plan(
                        ResolvedPlaybackEngine::Native,
                        if input.has_enhanced_engine {
                            Some(ResolvedPlaybackEngine::Enhanced)
                        } else {
                            None
                        },
                        "android_media3_default",
                    )
                }
            }
            PlatformKind::Harmony => {
                let standard_native_container =
                    matches!(container.as_str(), "mp4" | "m4v" | "mov" | "m3u8" | "hls");
                let needs_enhanced_container = matches!(
                    container.as_str(),
                    "mkv" | "ts" | "m2ts" | "flv" | "rmvb" | "avi" | "wmv" | "webm"
                );
                let needs_enhanced_audio = matches!(
                    audio_codec.as_str(),
                    "dts" | "dca" | "truehd" | "ac3" | "eac3" | "mlp"
                );
                if input.has_enhanced_engine
                    && (needs_enhanced_container
                        || needs_enhanced_audio
                        || input.allow_self_signed_tls
                        || needs_rich_subtitle
                        || (!standard_native_container && !container.is_empty()))
                {
                    make_plan(
                        ResolvedPlaybackEngine::Enhanced,
                        Some(ResolvedPlaybackEngine::Native),
                        if input.allow_self_signed_tls {
                            "harmony_self_signed_tls"
                        } else if needs_enhanced_audio {
                            "harmony_audio_codec_enhanced"
                        } else {
                            "harmony_container_enhanced"
                        },
                    )
                } else {
                    make_plan(
                        ResolvedPlaybackEngine::Native,
                        if input.has_enhanced_engine {
                            Some(ResolvedPlaybackEngine::Enhanced)
                        } else {
                            None
                        },
                        "harmony_avplayer_default",
                    )
                }
            }
        }
    }

    /// 安全构建自定义外部播放器启动链接：
    /// - 仅接受无内嵌凭据的 `http://` / `https://` 媒体 URL（或受控无凭据流）；
    /// - 拒绝危险目标协议（`javascript:` / `file:` / `data:` / `vbscript:` / `about:` / `blob:`）；
    /// - 对 `{url}`、`{title}` 与 `{raw_url}` 占位符执行安全替换（`{url}` / `{title}` 自动 URL 编码）。
    pub fn build_external_player_url(
        template: &str,
        media_url: &str,
        title: &str,
    ) -> Result<String, String> {
        let clean_tpl = template.trim();
        if clean_tpl.is_empty() {
            return Err("外部播放器 URL 模板不能为空".into());
        }
        let clean_media = media_url.trim();
        let parsed_media = Url::parse(clean_media).map_err(|_| "无效的媒体播放链接".to_string())?;
        if !matches!(parsed_media.scheme(), "http" | "https") || parsed_media.host().is_none() {
            return Err("外部播放器仅支持安全 HTTP(S) 媒体链接".into());
        }
        if !parsed_media.username().is_empty() || parsed_media.password().is_some() {
            return Err("禁止向外部播放器传递包含内嵌凭据的链接".into());
        }

        let scheme_end = clean_tpl
            .find("://")
            .ok_or_else(|| "模板必须以合法 URL Scheme（如 player://）开头".to_string())?;
        let scheme = clean_tpl[..scheme_end].trim().to_ascii_lowercase();
        if scheme.is_empty()
            || !scheme
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'-' || b == b'.')
            || !scheme.as_bytes()[0].is_ascii_alphabetic()
        {
            return Err("外部播放器 URL Scheme 格式非法".into());
        }
        if matches!(
            scheme.as_str(),
            "javascript" | "vbscript" | "data" | "file" | "about" | "blob" | "tel" | "sms"
        ) {
            return Err("不允许使用该危险协议呼起外部应用".into());
        }

        let encoded_url = Self::percent_encode(clean_media);
        let encoded_title = Self::percent_encode(title.trim());

        let result = if clean_tpl.contains("{url}") || clean_tpl.contains("{raw_url}") {
            clean_tpl
                .replace("{url}", &encoded_url)
                .replace("{raw_url}", clean_media)
                .replace("{title}", &encoded_title)
        } else {
            format!("{clean_tpl}{encoded_url}")
        };
        Ok(result)
    }

    fn normalize_hint(raw: Option<&str>) -> String {
        raw.unwrap_or_default().trim().to_ascii_lowercase()
    }

    fn extract_extension(raw: &str) -> String {
        let trimmed = raw.trim();
        let path_part = if let Ok(parsed) = Url::parse(trimmed) {
            parsed.path().to_string()
        } else {
            trimmed.split(['?', '#']).next().unwrap_or("").to_string()
        };
        let file_name = path_part.rsplit('/').next().unwrap_or("");
        if let Some((_, ext)) = file_name.rsplit_once('.') {
            ext.trim().to_ascii_lowercase()
        } else {
            String::new()
        }
    }

    fn resolve_container(input: &EngineResolutionInput) -> String {
        let hint = Self::normalize_hint(input.container_hint.as_deref());
        if !hint.is_empty() {
            return hint;
        }
        Self::extract_extension(&input.url_or_filename)
    }

    fn percent_encode(input: &str) -> String {
        let mut out = String::with_capacity(input.len() * 2);
        for byte in input.as_bytes() {
            let unreserved =
                byte.is_ascii_alphanumeric() || matches!(*byte, b'-' | b'_' | b'.' | b'~');
            if unreserved {
                out.push(*byte as char);
            } else {
                out.push('%');
                const HEX: &[u8; 16] = b"0123456789ABCDEF";
                out.push(HEX[(byte >> 4) as usize] as char);
                out.push(HEX[(byte & 0x0F) as usize] as char);
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base_input(platform: PlatformKind) -> EngineResolutionInput {
        EngineResolutionInput {
            platform,
            preferred: PlaybackEngineChoice::Auto,
            is_audio: false,
            decode_force_software: false,
            has_enhanced_engine: true,
            has_legacy_engine: platform == PlatformKind::Ios,
            url_or_filename: "https://media.example.com/movie.mp4".into(),
            container_hint: None,
            audio_codec_hint: None,
            video_codec_hint: None,
            has_ass_or_pgs_subtitle: false,
            ignore_ass_style: false,
            allow_self_signed_tls: false,
        }
    }

    #[test]
    fn audio_defaults_to_native_and_routes_exotic_to_enhanced() {
        let mut standard_audio = base_input(PlatformKind::Ios);
        standard_audio.is_audio = true;
        standard_audio.url_or_filename = "https://media.example.com/song.flac".into();
        let plan = PlaybackEngineRouter::resolve(&standard_audio);
        assert_eq!(plan.primary, ResolvedPlaybackEngine::Native);
        assert_eq!(plan.fallback, Some(ResolvedPlaybackEngine::Enhanced));
        assert_eq!(plan.engine_label_zh, "AVPlayer 原生");

        let mut dsf_audio = standard_audio;
        dsf_audio.url_or_filename = "https://media.example.com/hi-res.dsf".into();
        let exotic = PlaybackEngineRouter::resolve(&dsf_audio);
        assert_eq!(exotic.primary, ResolvedPlaybackEngine::Enhanced);
        assert_eq!(exotic.fallback, Some(ResolvedPlaybackEngine::Native));
    }

    #[test]
    fn ios_auto_routes_standard_mp4_to_avplayer_and_mkv_or_ass_to_mpv() {
        let mp4_plan = PlaybackEngineRouter::resolve(&base_input(PlatformKind::Ios));
        assert_eq!(mp4_plan.primary, ResolvedPlaybackEngine::Native);
        assert_eq!(mp4_plan.fallback, Some(ResolvedPlaybackEngine::Enhanced));

        let mut mkv_input = base_input(PlatformKind::Ios);
        mkv_input.url_or_filename = "https://media.example.com/remux.mkv".into();
        let mkv_plan = PlaybackEngineRouter::resolve(&mkv_input);
        assert_eq!(mkv_plan.primary, ResolvedPlaybackEngine::Enhanced);
        assert_eq!(mkv_plan.fallback, Some(ResolvedPlaybackEngine::Legacy));
        assert_eq!(mkv_plan.engine_label_zh, "MPV 全能");

        let mut proxy_unknown = base_input(PlatformKind::Ios);
        proxy_unknown.url_or_filename =
            "https://mp.example.com/api/v1/mediaserver/stream?itemid=123".into();
        let proxy_plan = PlaybackEngineRouter::resolve(&proxy_unknown);
        assert_eq!(proxy_plan.primary, ResolvedPlaybackEngine::Enhanced);
    }

    #[test]
    fn android_auto_uses_media3_by_default_and_mpv_for_ass_or_sw_decode() {
        let mut mkv = base_input(PlatformKind::Android);
        mkv.url_or_filename = "https://media.example.com/movie.mkv".into();
        mkv.audio_codec_hint = Some("dts".into());
        let plan = PlaybackEngineRouter::resolve(&mkv);
        assert_eq!(plan.primary, ResolvedPlaybackEngine::Native);
        assert_eq!(plan.fallback, Some(ResolvedPlaybackEngine::Enhanced));
        assert_eq!(plan.engine_label_zh, "Media3 原生");

        mkv.has_ass_or_pgs_subtitle = true;
        let ass_plan = PlaybackEngineRouter::resolve(&mkv);
        assert_eq!(ass_plan.primary, ResolvedPlaybackEngine::Enhanced);
        assert_eq!(ass_plan.engine_label_zh, "MPV 全能");

        mkv.ignore_ass_style = true;
        let ignored_plan = PlaybackEngineRouter::resolve(&mkv);
        assert_eq!(ignored_plan.primary, ResolvedPlaybackEngine::Native);

        mkv.decode_force_software = true;
        let sw_plan = PlaybackEngineRouter::resolve(&mkv);
        assert_eq!(sw_plan.primary, ResolvedPlaybackEngine::Enhanced);
        assert_eq!(sw_plan.reason_code, "force_software_decode");
    }

    #[test]
    fn harmony_auto_routes_mkv_dts_and_self_signed_tls_to_enhanced() {
        let mp4 = PlaybackEngineRouter::resolve(&base_input(PlatformKind::Harmony));
        assert_eq!(mp4.primary, ResolvedPlaybackEngine::Native);
        assert_eq!(mp4.fallback, Some(ResolvedPlaybackEngine::Enhanced));

        let mut mkv = base_input(PlatformKind::Harmony);
        mkv.url_or_filename = "https://nas.local/movie.mkv".into();
        let mkv_plan = PlaybackEngineRouter::resolve(&mkv);
        assert_eq!(mkv_plan.primary, ResolvedPlaybackEngine::Enhanced);
        assert_eq!(mkv_plan.engine_label_zh, "IJK 增强");

        let mut tls = base_input(PlatformKind::Harmony);
        tls.allow_self_signed_tls = true;
        let tls_plan = PlaybackEngineRouter::resolve(&tls);
        assert_eq!(tls_plan.primary, ResolvedPlaybackEngine::Enhanced);
        assert_eq!(tls_plan.reason_code, "harmony_self_signed_tls");
    }

    #[test]
    fn user_pinned_engine_and_external_template_security() {
        let mut pinned = base_input(PlatformKind::Ios);
        pinned.preferred = PlaybackEngineChoice::Legacy;
        let legacy_plan = PlaybackEngineRouter::resolve(&pinned);
        assert_eq!(legacy_plan.primary, ResolvedPlaybackEngine::Legacy);
        assert_eq!(legacy_plan.engine_label_zh, "VLCKit 兼容");

        let ok = PlaybackEngineRouter::build_external_player_url(
            "mpplayer://play?url={url}&title={title}",
            "https://cdn.example.com/video.mkv?sign=1",
            "星际穿越",
        )
        .unwrap();
        assert!(ok.starts_with("mpplayer://play?url=https%3A%2F%2Fcdn.example.com"));
        assert!(ok.contains("&title=%E6%98%9F%E9%99%85%E7%A9%BF%E8%B6%8A"));

        assert!(
            PlaybackEngineRouter::build_external_player_url(
                "javascript://alert(1)?url={url}",
                "https://cdn.example.com/v.mp4",
                "t",
            )
            .is_err()
        );
        assert!(
            PlaybackEngineRouter::build_external_player_url(
                "mpplayer://play?url={url}",
                "https://user:pass@cdn.example.com/v.mp4",
                "t",
            )
            .is_err()
        );
    }
}
