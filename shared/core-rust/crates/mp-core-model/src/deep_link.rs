//! `moviepilot://` 全量深度链接、Web 路由别名与系统音视频文件扩展名判别。

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use url::Url;

/// 原生播放器可识别的媒体播放模式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PlayableMediaKind {
    Video,
    Audio,
}

/// 统一维护 MoviePilot 三端原生播放器支持的音视频扩展名。
pub struct PlayableMediaFormat;

impl PlayableMediaFormat {
    const VIDEO_EXTS: &'static [&'static str] = &[
        "mp4", "mkv", "mk3d", "mov", "m4v", "avi", "ts", "m2ts", "mts", "webm", "flv", "f4v",
        "wmv", "asf", "rmvb", "rm", "mpg", "mpeg", "vob", "3gp", "3g2", "ogv",
    ];
    const STREAMING_VIDEO_EXTS: &'static [&'static str] = &["m3u8", "mpd"];
    const AUDIO_EXTS: &'static [&'static str] = &[
        "mp3", "flac", "m4a", "aac", "wav", "ogg", "oga", "opus", "alac", "ape", "aiff", "aif",
        "wma", "mka", "caf", "dsf", "dff", "amr",
    ];

    /// 按扩展名推断播放模式；`include_streaming` 为真时额外识别 m3u8/mpd。
    pub fn kind_for_extension(raw_ext: &str, include_streaming: bool) -> Option<PlayableMediaKind> {
        let ext = raw_ext.trim().trim_start_matches('.').to_ascii_lowercase();
        if ext.is_empty() {
            return None;
        }
        if Self::AUDIO_EXTS.contains(&ext.as_str()) {
            return Some(PlayableMediaKind::Audio);
        }
        if Self::VIDEO_EXTS.contains(&ext.as_str()) {
            return Some(PlayableMediaKind::Video);
        }
        if include_streaming && Self::STREAMING_VIDEO_EXTS.contains(&ext.as_str()) {
            return Some(PlayableMediaKind::Video);
        }
        None
    }

    /// 根据路径或文件名推断可播放媒体类型。
    pub fn kind_for_path(path: &str, include_streaming: bool) -> Option<PlayableMediaKind> {
        let ext = path.rsplit('.').next()?;
        if ext.len() == path.len() {
            return None;
        }
        Self::kind_for_extension(ext, include_streaming)
    }
}

/// 经过严格白名单解析的 MoviePilot 深度链接枚举。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum AppDeepLink {
    Discover,
    Explore {
        source: Option<String>,
    },
    Dashboard,
    Settings,
    Search {
        query: Option<String>,
        search_kind: Option<String>,
    },
    MediaDetail {
        source: String,
        media_id: String,
        media_type: String,
    },
    Subscriptions {
        category: Option<String>,
    },
    SubscribeCommunity,
    Calendar,
    Resources {
        keyword: Option<String>,
        browse_home: bool,
    },
    Downloads,
    Files {
        storage: Option<String>,
        path: Option<String>,
    },
    History {
        search: Option<String>,
    },
    Workflows,
    Sites,
    Messages,
    Plugins {
        installed_only: bool,
    },
    Agent {
        prompt: Option<String>,
    },
    Music,
    Shortcuts,
    Users,
    Appearance,
    SystemSettings,
    PlaybackSettings,
    SystemModule {
        module: String,
    },
    Diagnostics {
        section: String,
    },
    PlayDirect {
        direct_url: String,
        title: Option<String>,
        media_kind: PlayableMediaKind,
    },
    PlayMediaServerItem {
        item_id: String,
        server: Option<String>,
    },
    PlayStorageFile {
        storage: String,
        path: String,
    },
}

impl AppDeepLink {
    /// 判断解析结果是否允许作为推送通知的内部导航目标（严禁在通知点击时拉起音视频播放）。
    pub fn is_allowed_for_notification(&self) -> bool {
        !matches!(
            self,
            Self::PlayDirect { .. }
                | Self::PlayMediaServerItem { .. }
                | Self::PlayStorageFile { .. }
        )
    }

    /// 规范化站内相对路径：拒绝跨站 `//`、反斜杠与危险协议，兼容 Vue Hash 路由前缀（`/#/...`、`/#?...`）。
    fn normalize_web_route(raw: &str) -> Option<String> {
        let trimmed = raw.trim();
        if trimmed.is_empty()
            || trimmed.len() > 2048
            || trimmed.starts_with("//")
            || trimmed.contains('\\')
            || trimmed.to_ascii_lowercase().starts_with("javascript:")
            || trimmed.chars().any(char::is_control)
        {
            return None;
        }
        let with_slash = if trimmed.starts_with('/') {
            trimmed.to_string()
        } else {
            format!("/{trimmed}")
        };
        let normalized = if let Some(rest) = with_slash.strip_prefix("/#/") {
            format!("/{rest}")
        } else if let Some(rest) = with_slash.strip_prefix("/#?") {
            format!("/?{rest}")
        } else if with_slash == "/#" {
            "/".to_string()
        } else {
            with_slash
        };
        let path_prefix = normalized.split('?').next().unwrap_or(&normalized);
        if path_prefix.starts_with("//") || path_prefix.contains("://") || normalized.contains('#')
        {
            return None;
        }
        Some(normalized)
    }

    /// 解析规范化后的站内相对路径并合并可选外层查询参数。
    fn parse_relative_route(
        raw_route: &str,
        outer_query: Option<&HashMap<String, String>>,
    ) -> Option<Self> {
        let normalized = Self::normalize_web_route(raw_route)?;
        let inner_url = Url::parse(&format!(
            "moviepilot://host/{}",
            normalized.trim_start_matches('/')
        ))
        .ok()?;
        let mut segments = Vec::new();
        if let Some(iter) = inner_url.path_segments() {
            for seg in iter.filter(|s| !s.is_empty()) {
                let decoded = Self::urlencoding_decode(seg);
                if decoded == "."
                    || decoded == ".."
                    || decoded.contains('/')
                    || decoded.contains('\\')
                {
                    return None;
                }
                segments.push(decoded);
            }
        }
        let mut query: HashMap<String, String> = inner_url
            .query_pairs()
            .map(|(k, v)| (k.to_ascii_lowercase(), v.into_owned()))
            .collect();
        if let Some(outer) = outer_query {
            for (k, v) in outer {
                if k == "path" || k == "route" {
                    continue;
                }
                query.entry(k.clone()).or_insert_with(|| v.clone());
            }
        }
        Self::route_segments(&segments, &query)
    }

    /// 解析主屏幕/Web 通知交接链接 `moviepilot-app://notification?origin=...&route=...&owner=...`。
    fn parse_notification_handoff(parsed: &Url) -> Option<Self> {
        if !parsed
            .host_str()
            .is_some_and(|h| h.eq_ignore_ascii_case("notification"))
            || !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.port().is_some()
            || parsed.fragment().is_some()
            || !matches!(parsed.path(), "" | "/")
        {
            return None;
        }
        let mut origin: Option<String> = None;
        let mut route: Option<String> = None;
        let mut owner: Option<String> = None;
        let mut count = 0usize;
        for (k, v) in parsed.query_pairs() {
            count += 1;
            match k.as_ref() {
                "origin" if origin.is_none() => origin = Some(v.into_owned()),
                "route" if route.is_none() => route = Some(v.into_owned()),
                "owner" if owner.is_none() => owner = Some(v.into_owned()),
                _ => return None,
            }
        }
        if count != 3 {
            return None;
        }
        let origin_str = origin?;
        let origin_url = Url::parse(&origin_str).ok()?;
        if !matches!(origin_url.scheme(), "http" | "https")
            || origin_url.host_str().unwrap_or_default().is_empty()
            || !origin_url.username().is_empty()
            || origin_url.password().is_some()
            || origin_url.query().is_some()
            || origin_url.fragment().is_some()
        {
            return None;
        }
        let owner_str = owner?;
        if !(16..=64).contains(&owner_str.len())
            || !owner_str
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        {
            return None;
        }
        let route_str = route?;
        if !route_str.starts_with('/') {
            return None;
        }
        let target = Self::parse_relative_route(&route_str, None)?;
        target.is_allowed_for_notification().then_some(target)
    }

    /// 解析 `moviepilot://`、`moviepilot-app://notification` 或站内 Web 路径；严格白名单校验，非法链接返回 `None`。
    pub fn parse(raw: &str) -> Option<Self> {
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.len() > 4096 {
            return None;
        }
        if trimmed.starts_with('/') {
            let target = Self::parse_relative_route(trimmed, None)?;
            return target.is_allowed_for_notification().then_some(target);
        }
        let parsed = Url::parse(trimmed).ok()?;
        if parsed.scheme().eq_ignore_ascii_case("moviepilot-app") {
            return Self::parse_notification_handoff(&parsed);
        }
        if parsed.scheme().eq_ignore_ascii_case("moviepilot") {
            if !parsed.username().is_empty()
                || parsed.password().is_some()
                || parsed.port().is_some()
                || parsed.fragment().is_some_and(|f| !f.is_empty())
                || parsed.path().contains('\\')
            {
                return None;
            }
            let mut query: HashMap<String, String> = parsed
                .query_pairs()
                .map(|(k, v)| (k.to_ascii_lowercase(), v.into_owned()))
                .collect();

            let host = parsed.host_str().unwrap_or_default().to_ascii_lowercase();
            if host == "widget" || host == "passkey" {
                return None;
            }
            let segments: Vec<String> = parsed
                .path_segments()
                .map(|iter| {
                    iter.filter(|s| !s.is_empty())
                        .map(|s| s.to_string())
                        .collect()
                })
                .unwrap_or_default();
            if segments
                .iter()
                .any(|s| s == "." || s == ".." || s.contains('\\'))
            {
                return None;
            }

            // 兼容 moviepilot://open?path=/subscribe/movie 与 moviepilot://route?route=/?shotcut=message
            if (host == "open" || host == "route") && segments.is_empty() {
                if let Some(inner_path) = query.remove("path").or_else(|| query.remove("route")) {
                    return Self::parse_relative_route(&inner_path, Some(&query));
                }
                if host == "route" {
                    return None;
                }
            }

            let mut full = Vec::new();
            if !host.is_empty() && host != "open" {
                full.push(host);
            }
            full.extend(segments);
            return Self::route_segments(&full, &query);
        }
        None
    }

    /// 解析后端推送与 Web 端约定的首页快捷弹窗参数（`/?shotcut=message`、`/?shortcut=message` 等）。
    fn resolve_home_shortcut(raw_shortcut: &str) -> Option<Self> {
        match raw_shortcut.trim().to_ascii_lowercase().as_str() {
            "message" | "messages" | "notification" | "notifications" => Some(Self::Messages),
            "recognition" | "rule" | "ruletest" | "rule_test" => Some(Self::Diagnostics {
                section: "recognize".to_string(),
            }),
            "log" | "logs" | "livelog" | "live_log" => Some(Self::Diagnostics {
                section: "logs".to_string(),
            }),
            "network" | "nettest" => Some(Self::Diagnostics {
                section: "network".to_string(),
            }),
            "words" | "word" => Some(Self::Diagnostics {
                section: "words".to_string(),
            }),
            "scheduler" | "schedulers" | "schedule" | "jobs" => Some(Self::Diagnostics {
                section: "schedulers".to_string(),
            }),
            "system" | "health" | "check" => Some(Self::Diagnostics {
                section: "check".to_string(),
            }),
            _ => None,
        }
    }

    fn route_segments(segments: &[String], query: &HashMap<String, String>) -> Option<Self> {
        let first = segments
            .first()
            .map(|s| s.to_ascii_lowercase())
            .unwrap_or_default();
        let second = segments.get(1).cloned();
        let third = segments.get(2).cloned();

        match first.as_str() {
            "" | "discover" | "recommend" | "home" => {
                if segments.len() > 1 {
                    return None;
                }
                if let Some(raw_shortcut) = query
                    .get("shotcut")
                    .or_else(|| query.get("shortcut"))
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                {
                    return Self::resolve_home_shortcut(raw_shortcut);
                }
                Some(Self::Discover)
            }
            "explore" => Some(Self::Explore { source: second }),
            "dashboard" | "mine" => Some(Self::Dashboard),
            "setting" | "settings" => {
                match second.as_deref().map(str::to_ascii_lowercase).as_deref() {
                    None => Some(Self::Settings),
                    Some("system") => Some(Self::SystemSettings),
                    Some("playback") => Some(Self::PlaybackSettings),
                    Some("appearance") => Some(Self::Appearance),
                    Some("users") => Some(Self::Users),
                    Some(module) => Some(Self::SystemModule {
                        module: module.to_string(),
                    }),
                }
            }
            "search" => Some(Self::Search {
                query: query.get("q").or_else(|| query.get("keyword")).cloned(),
                search_kind: query.get("type").or_else(|| query.get("kind")).cloned(),
            }),
            "media" => Self::parse_media(second.as_deref(), third.as_deref(), query),
            "subscribe" | "subscriptions" => {
                match second.as_deref().map(str::to_ascii_lowercase).as_deref() {
                    Some("popular") | Some("share") | Some("shares") | Some("community") => {
                        Some(Self::SubscribeCommunity)
                    }
                    Some(cat @ ("movie" | "tv" | "music")) => Some(Self::Subscriptions {
                        category: Some(cat.to_string()),
                    }),
                    _ => Some(Self::Subscriptions {
                        category: query.get("type").cloned(),
                    }),
                }
            }
            "calendar" => Some(Self::Calendar),
            "resource" | "resources" => {
                let browse_home = second
                    .as_deref()
                    .is_some_and(|s| s.eq_ignore_ascii_case("browse"))
                    || query.get("browse").is_some_and(|v| v == "1" || v == "true");
                Some(Self::Resources {
                    keyword: query.get("keyword").or_else(|| query.get("q")).cloned(),
                    browse_home,
                })
            }
            "downloading" | "downloads" => Some(Self::Downloads),
            "files" | "filemanager" => Some(Self::Files {
                storage: query.get("storage").cloned(),
                path: query.get("path").cloned(),
            }),
            "history" | "transfer" => Some(Self::History {
                search: query.get("search").or_else(|| query.get("q")).cloned(),
            }),
            "workflow" | "workflows" => Some(Self::Workflows),
            "site" | "sites" => Some(Self::Sites),
            "message" | "messages" | "notification" | "notifications" => Some(Self::Messages),
            "plugin" | "plugins" => Some(Self::Plugins {
                installed_only: second
                    .as_deref()
                    .is_some_and(|s| s.eq_ignore_ascii_case("installed")),
            }),
            "agent" => Some(Self::Agent {
                prompt: query.get("prompt").cloned(),
            }),
            "music" => Some(Self::Music),
            "shortcuts" => Some(Self::Shortcuts),
            "users" => Some(Self::Users),
            "appearance" => Some(Self::Appearance),
            "diagnostics" => Some(Self::Diagnostics {
                section: second.unwrap_or_else(|| "health".to_string()),
            }),
            "play" => Self::parse_play(query),
            _ => None,
        }
    }

    fn normalize_source(raw: &str) -> String {
        match raw.trim().to_ascii_lowercase().as_str() {
            "tmdb" | "themoviedb" => "themoviedb".to_string(),
            "douban" => "douban".to_string(),
            "bangumi" => "bangumi".to_string(),
            other => other.to_string(),
        }
    }

    fn normalize_media_type(raw: Option<&str>) -> String {
        match raw.unwrap_or("movie").trim().to_ascii_lowercase().as_str() {
            "tv" | "series" | "电视剧" => "电视剧".to_string(),
            _ => "电影".to_string(),
        }
    }

    fn parse_media(
        second: Option<&str>,
        third: Option<&str>,
        query: &HashMap<String, String>,
    ) -> Option<Self> {
        let media_type = Self::normalize_media_type(query.get("type").map(String::as_str));
        if let (Some(src), Some(id)) = (second, third) {
            return Some(Self::MediaDetail {
                source: Self::normalize_source(src),
                media_id: id.to_string(),
                media_type,
            });
        }
        if let Some(compound) = query.get("mediaid") {
            let (src, id) = compound.split_once(':')?;
            if !id.trim().is_empty() {
                return Some(Self::MediaDetail {
                    source: Self::normalize_source(src),
                    media_id: id.trim().to_string(),
                    media_type,
                });
            }
        }
        None
    }

    fn parse_play(query: &HashMap<String, String>) -> Option<Self> {
        if let Some(raw_url) = query.get("url") {
            let parsed = Url::parse(raw_url).ok()?;
            if !matches!(parsed.scheme(), "http" | "https") {
                return None;
            }
            let explicit = query
                .get("type")
                .and_then(|t| match t.to_ascii_lowercase().as_str() {
                    "audio" => Some(PlayableMediaKind::Audio),
                    "video" => Some(PlayableMediaKind::Video),
                    _ => None,
                });
            let inferred = PlayableMediaFormat::kind_for_path(parsed.path(), true)
                .unwrap_or(PlayableMediaKind::Video);
            return Some(Self::PlayDirect {
                direct_url: raw_url.clone(),
                title: query.get("title").cloned(),
                media_kind: explicit.unwrap_or(inferred),
            });
        }
        if let Some(item_id) = query.get("itemid")
            && !item_id.trim().is_empty()
        {
            return Some(Self::PlayMediaServerItem {
                item_id: item_id.clone(),
                server: query.get("server").cloned(),
            });
        }
        if let (Some(storage), Some(path)) = (query.get("storage"), query.get("path"))
            && !storage.trim().is_empty()
            && !path.trim().is_empty()
        {
            return Some(Self::PlayStorageFile {
                storage: storage.clone(),
                path: path.clone(),
            });
        }
        None
    }
    /// 百分号解码单个路径段，保留非 ASCII UTF-8 内容。
    fn urlencoding_decode(input: &str) -> String {
        let bytes = input.as_bytes();
        let mut out = Vec::with_capacity(bytes.len());
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b'%'
                && i + 2 < bytes.len()
                && let (Some(hi), Some(lo)) = (
                    (bytes[i + 1] as char).to_digit(16),
                    (bytes[i + 2] as char).to_digit(16),
                )
            {
                out.push(((hi << 4) | lo) as u8);
                i += 3;
                continue;
            }
            out.push(bytes[i]);
            i += 1;
        }
        String::from_utf8(out).unwrap_or_else(|_| input.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn passes_all_shared_deeplink_golden_fixtures() {
        let fixture_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../fixtures/deeplinks/cases.json");
        let text = std::fs::read_to_string(&fixture_path).expect("读取 deeplinks 夹具失败");
        let root: serde_json::Value = serde_json::from_str(&text).unwrap();
        for case in root["cases"].as_array().unwrap() {
            let url = case["url"].as_str().unwrap();
            let parsed =
                AppDeepLink::parse(url).unwrap_or_else(|| panic!("DeepLink 解析失败: {url}"));
            let encoded = serde_json::to_value(&parsed).unwrap();
            assert_eq!(
                encoded["kind"].as_str().unwrap(),
                case["kind"].as_str().unwrap(),
                "URL={url}"
            );
            if let Some(source) = case.get("source").and_then(|v| v.as_str()) {
                assert_eq!(encoded["source"].as_str(), Some(source), "URL={url}");
            }
            if let Some(mid) = case.get("mediaId").and_then(|v| v.as_str()) {
                assert_eq!(encoded["media_id"].as_str(), Some(mid), "URL={url}");
            }
            if let Some(prompt) = case.get("prompt").and_then(|v| v.as_str()) {
                assert_eq!(encoded["prompt"].as_str(), Some(prompt), "URL={url}");
            }
        }
    }

    #[test]
    fn parses_push_notification_shortcut_and_hash_routes() {
        assert_eq!(
            AppDeepLink::parse("/?shotcut=message"),
            Some(AppDeepLink::Messages)
        );
        assert_eq!(
            AppDeepLink::parse("/?shortcut=messages"),
            Some(AppDeepLink::Messages)
        );
        assert_eq!(
            AppDeepLink::parse("/#/?shotcut=message"),
            Some(AppDeepLink::Messages)
        );
        assert_eq!(
            AppDeepLink::parse("/#/history?search=Dune"),
            Some(AppDeepLink::History {
                search: Some("Dune".to_string()),
            })
        );
        assert_eq!(
            AppDeepLink::parse(
                "moviepilot-app://notification?origin=https%3A%2F%2Fmp.example.test&route=%2F%3Fshotcut%3Dmessage&owner=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            Some(AppDeepLink::Messages)
        );
        assert_eq!(AppDeepLink::parse("/?shotcut=unknown"), None);
        assert_eq!(AppDeepLink::parse("//evil.example/messages"), None);
        assert_eq!(
            AppDeepLink::parse("/play?url=https%3A%2F%2Fmedia.example.test%2Fdemo.mp4"),
            None
        );
        assert_eq!(
            AppDeepLink::parse(
                "moviepilot-app://notification?origin=https%3A%2F%2Fmp.example.test&route=%2Fplay%3Fitemid%3D1&owner=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            None
        );
    }
}
