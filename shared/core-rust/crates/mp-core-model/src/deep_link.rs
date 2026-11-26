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

/// 从 `.strm` 文本文件中解析出的客户端直链播放规格（含可选安全请求头与推断出的媒体类型）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StrmStreamSpec {
    pub url: String,
    pub headers: HashMap<String, String>,
    pub media_kind: PlayableMediaKind,
}

/// 统一维护 MoviePilot 三端原生播放器支持的音视频扩展名与 `.strm` 直链解析。
pub struct PlayableMediaFormat;

impl PlayableMediaFormat {
    const VIDEO_EXTS: &'static [&'static str] = &[
        "mp4", "mkv", "mk3d", "mov", "m4v", "avi", "ts", "m2ts", "mts", "webm", "flv", "f4v",
        "wmv", "asf", "rmvb", "rm", "mpg", "mpeg", "vob", "3gp", "3g2", "ogv", "strm",
    ];
    const STREAMING_VIDEO_EXTS: &'static [&'static str] = &["m3u8", "mpd"];
    const AUDIO_EXTS: &'static [&'static str] = &[
        "mp3", "flac", "m4a", "aac", "wav", "ogg", "oga", "opus", "alac", "ape", "aiff", "aif",
        "wma", "mka", "caf", "dsf", "dff", "amr",
    ];
    const MAX_STRM_BYTES: usize = 64 * 1024;

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

    /// 根据路径或文件名推断可播放媒体类型；对 `*.flac.strm` 等双扩展名优先识别内层音频后缀。
    pub fn kind_for_path(path: &str, include_streaming: bool) -> Option<PlayableMediaKind> {
        let trimmed = path.trim();
        let ext = trimmed.rsplit('.').next()?;
        if ext.len() == trimmed.len() {
            return None;
        }
        if ext.eq_ignore_ascii_case("strm") {
            let stem = &trimmed[..trimmed.len().saturating_sub(ext.len() + 1)];
            if let Some(inner_ext) = stem.rsplit('.').next()
                && inner_ext.len() < stem.len()
                && Self::AUDIO_EXTS.contains(&inner_ext.to_ascii_lowercase().as_str())
            {
                return Some(PlayableMediaKind::Audio);
            }
            return Some(PlayableMediaKind::Video);
        }
        Self::kind_for_extension(ext, include_streaming)
    }

    /// 判断路径或文件名是否为 `.strm` 虚拟流文件。
    pub fn is_strm_path(path_or_ext: &str) -> bool {
        let trimmed = path_or_ext.trim().trim_start_matches('.');
        if !trimmed.contains('.') {
            return trimmed.eq_ignore_ascii_case("strm");
        }
        trimmed
            .rsplit('.')
            .next()
            .is_some_and(|ext| ext.eq_ignore_ascii_case("strm"))
    }

    /// 解析 `.strm` 文件文本，提取规范化 HTTP(S) 直链、可选播放器请求头及音视频模式。
    pub fn parse_strm_content(
        raw_text: &str,
        fallback_file_name: Option<&str>,
    ) -> Result<StrmStreamSpec, String> {
        if raw_text.len() > Self::MAX_STRM_BYTES {
            return Err("STRM 文件体积超出 64KB 安全上限".to_string());
        }
        if raw_text.contains('\0') {
            return Err("STRM 文件包含二进制数据，非有效直链文本".to_string());
        }
        let body = raw_text.trim_start_matches('\u{feff}');
        let mut headers: HashMap<String, String> = HashMap::new();
        let mut target_line: Option<&str> = None;

        for raw_line in body.lines() {
            let line = raw_line.trim();
            if line.is_empty() {
                continue;
            }
            if let Some(rest) = line.strip_prefix('#') {
                Self::parse_strm_directive(rest.trim(), &mut headers);
                continue;
            }
            if target_line.is_none() {
                target_line = Some(line);
            }
        }

        let raw_target = target_line.ok_or_else(|| "STRM 文件未包含有效的播放地址".to_string())?;
        let (raw_url_part, pipe_headers) = match raw_target.split_once('|') {
            Some((u, h)) => (u.trim(), Some(h.trim())),
            None => (raw_target, None),
        };
        if let Some(pipe_raw) = pipe_headers {
            Self::parse_header_pairs(pipe_raw, &mut headers);
        }

        let normalized_input = Self::escape_raw_url_input(raw_url_part);
        let mut parsed = Url::parse(&normalized_input)
            .map_err(|_| "STRM 播放地址不是合法的 HTTP/HTTPS URL".to_string())?;
        if !matches!(parsed.scheme(), "http" | "https") {
            return Err("STRM 直链仅支持 http 或 https 协议".to_string());
        }
        if parsed.host_str().unwrap_or_default().is_empty() {
            return Err("STRM 播放地址缺少有效主机名".to_string());
        }
        if !parsed.username().is_empty() || parsed.password().is_some() {
            return Err("STRM 播放地址禁止内嵌账号或密码凭据".to_string());
        }
        parsed.set_fragment(None);

        let decoded_path = AppDeepLink::urlencoding_decode(parsed.path());
        let media_kind = if !Self::is_strm_path(&decoded_path) {
            Self::kind_for_path(&decoded_path, true)
        } else {
            None
        }
        .or_else(|| fallback_file_name.and_then(|name| Self::kind_for_path(name, true)))
        .unwrap_or(PlayableMediaKind::Video);

        Ok(StrmStreamSpec {
            url: parsed.into(),
            headers,
            media_kind,
        })
    }

    fn parse_strm_directive(directive: &str, headers: &mut HashMap<String, String>) {
        if let Some(rest) = directive
            .strip_prefix("EXTVLCOPT:")
            .or_else(|| directive.strip_prefix("extvlcopt:"))
        {
            if let Some((k, v)) = rest.trim().split_once('=') {
                let mapped = match k.trim().to_ascii_lowercase().as_str() {
                    "http-user-agent" => Some("User-Agent"),
                    "http-referrer" | "http-referer" => Some("Referer"),
                    "http-cookie" => Some("Cookie"),
                    _ => None,
                };
                if let Some(header_name) = mapped {
                    Self::insert_safe_header(headers, header_name, v.trim());
                }
            }
            return;
        }
        if let Some(rest) = directive.strip_prefix("KODIPROP:") {
            let trimmed = rest.trim();
            if let Some(pairs) = trimmed
                .strip_prefix("inputstream.adaptive.stream_headers=")
                .or_else(|| trimmed.strip_prefix("http-headers="))
            {
                Self::parse_header_pairs(pairs, headers);
            }
        }
    }

    fn parse_header_pairs(raw_pairs: &str, headers: &mut HashMap<String, String>) {
        for pair in raw_pairs.split('&') {
            let Some((raw_k, raw_v)) = pair.split_once('=') else {
                continue;
            };
            let canonical = match raw_k.trim().to_ascii_lowercase().as_str() {
                "user-agent" => Some("User-Agent"),
                "referer" | "referrer" => Some("Referer"),
                "cookie" => Some("Cookie"),
                "origin" => Some("Origin"),
                "authorization" => Some("Authorization"),
                _ => None,
            };
            if let Some(name) = canonical {
                let decoded = AppDeepLink::urlencoding_decode(raw_v.trim());
                Self::insert_safe_header(headers, name, &decoded);
            }
        }
    }

    fn insert_safe_header(headers: &mut HashMap<String, String>, name: &str, value: &str) {
        let clean = value.trim();
        if clean.is_empty() || clean.len() > 4096 || clean.chars().any(char::is_control) {
            return;
        }
        headers.insert(name.to_string(), clean.to_string());
    }

    /// 兼容网盘/NAS STRM 生成器输出的未编码空格、方括号与孤立百分号，避免重复编码已有 `%XX`。
    fn escape_raw_url_input(raw: &str) -> String {
        let Some((scheme_and_auth, rest)) = raw.split_once("://") else {
            return raw.to_string();
        };
        let authority_end = rest.find(['/', '?']).unwrap_or(rest.len());
        let authority = &rest[..authority_end];
        let path_and_query = &rest[authority_end..];
        let bytes = path_and_query.as_bytes();
        let mut out = String::with_capacity(raw.len() + 16);
        out.push_str(scheme_and_auth);
        out.push_str("://");
        out.push_str(authority);
        let mut i = 0;
        while i < bytes.len() {
            match bytes[i] {
                b' ' => out.push_str("%20"),
                b'[' => out.push_str("%5B"),
                b']' => out.push_str("%5D"),
                b'%' => {
                    if i + 2 < bytes.len()
                        && bytes[i + 1].is_ascii_hexdigit()
                        && bytes[i + 2].is_ascii_hexdigit()
                    {
                        out.push('%');
                        out.push(bytes[i + 1] as char);
                        out.push(bytes[i + 2] as char);
                        i += 3;
                        continue;
                    }
                    out.push_str("%25");
                }
                ch if ch < 0x80 => out.push(ch as char),
                _ => {
                    // 非 ASCII UTF-8 字符保留原样交由 `Url::parse` 按 RFC 3986 统一百分号编码
                    let slice = &path_and_query[i..];
                    if let Some(ch) = slice.chars().next() {
                        out.push(ch);
                        i += ch.len_utf8();
                        continue;
                    }
                }
            }
            i += 1;
        }
        out
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
    PluginDetail {
        plugin_id: String,
        surface: Option<String>,
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
            "plugin" | "plugins" => {
                if third.is_some() {
                    return None;
                }
                if let Some(ref seg) = second {
                    if seg.eq_ignore_ascii_case("installed") || seg.eq_ignore_ascii_case("local") {
                        return Some(Self::Plugins {
                            installed_only: true,
                        });
                    }
                    if seg.eq_ignore_ascii_case("market") {
                        return Some(Self::Plugins {
                            installed_only: false,
                        });
                    }
                    if Self::is_valid_plugin_id(seg) {
                        return Some(Self::PluginDetail {
                            plugin_id: seg.clone(),
                            surface: query.get("surface").cloned(),
                        });
                    }
                    return None;
                }
                if let Some(raw_id) = query.get("id").map(|s| s.trim()).filter(|s| !s.is_empty()) {
                    if Self::is_valid_plugin_id(raw_id) {
                        return Some(Self::PluginDetail {
                            plugin_id: raw_id.to_string(),
                            surface: query.get("surface").cloned(),
                        });
                    }
                    return None;
                }
                Some(Self::Plugins {
                    installed_only: query
                        .get("tab")
                        .is_some_and(|t| t.eq_ignore_ascii_case("installed")),
                })
            }
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

    fn is_valid_plugin_id(raw: &str) -> bool {
        let len = raw.len();
        (1..=128).contains(&len)
            && raw
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-' || b == b'.')
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

    #[test]
    fn recognizes_strm_extensions_and_parses_strm_direct_links() {
        assert_eq!(
            PlayableMediaFormat::kind_for_extension(".strm", false),
            Some(PlayableMediaKind::Video)
        );
        assert_eq!(
            PlayableMediaFormat::kind_for_path("/media/movies/Avatar (2009).strm", false),
            Some(PlayableMediaKind::Video)
        );
        assert_eq!(
            PlayableMediaFormat::kind_for_path("/media/music/晴天.flac.strm", false),
            Some(PlayableMediaKind::Audio)
        );

        let cloud_strm = "\u{feff}#EXTM3U\n#EXTVLCOPT:http-user-agent=Mozilla/5.0 (115Browser)\n#EXTVLCOPT:http-referrer=https://115.com/\nhttps://alist.example.test:5244/d/电影/阿凡达 [4K HDR]/Avatar 100% Pure.mkv?sign=abc%2B123\n";
        let spec = PlayableMediaFormat::parse_strm_content(cloud_strm, Some("Avatar.strm"))
            .expect("解析云盘 STRM 失败");
        assert_eq!(
            spec.url,
            "https://alist.example.test:5244/d/%E7%94%B5%E5%BD%B1/%E9%98%BF%E5%87%A1%E8%BE%BE%20%5B4K%20HDR%5D/Avatar%20100%25%20Pure.mkv?sign=abc%2B123"
        );
        assert_eq!(spec.media_kind, PlayableMediaKind::Video);
        assert_eq!(
            spec.headers.get("User-Agent").map(String::as_str),
            Some("Mozilla/5.0 (115Browser)")
        );
        assert_eq!(
            spec.headers.get("Referer").map(String::as_str),
            Some("https://115.com/")
        );

        let pipe_audio = "http://192.168.1.15:5244/d/Music/Track 01.flac|User-Agent=Kodi%2F21.0&Cookie=sid%3Dxyz";
        let audio_spec = PlayableMediaFormat::parse_strm_content(pipe_audio, Some("Track.strm"))
            .expect("解析管道请求头音频 STRM 失败");
        assert_eq!(
            audio_spec.url,
            "http://192.168.1.15:5244/d/Music/Track%2001.flac"
        );
        assert_eq!(audio_spec.media_kind, PlayableMediaKind::Audio);
        assert_eq!(
            audio_spec.headers.get("User-Agent").map(String::as_str),
            Some("Kodi/21.0")
        );
        assert_eq!(
            audio_spec.headers.get("Cookie").map(String::as_str),
            Some("sid=xyz")
        );

        assert!(PlayableMediaFormat::parse_strm_content("file:///etc/passwd", None).is_err());
        assert!(
            PlayableMediaFormat::parse_strm_content("http://admin:secret@192.168.1.1/v.mp4", None)
                .is_err()
        );
        assert!(PlayableMediaFormat::parse_strm_content("# only comments\n\n", None).is_err());
    }
}
