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
    /// 解析 `moviepilot://` URL 或 Web 路径；严格白名单校验，非法链接返回 `None`。
    pub fn parse(raw: &str) -> Option<Self> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return None;
        }
        if trimmed.starts_with('/') {
            let synthetic = format!("moviepilot://open{}", trimmed);
            return Self::parse(&synthetic);
        }
        let parsed = Url::parse(trimmed).ok()?;
        if parsed.scheme().eq_ignore_ascii_case("moviepilot") {
            let mut query: HashMap<String, String> = parsed
                .query_pairs()
                .map(|(k, v)| (k.to_ascii_lowercase(), v.into_owned()))
                .collect();

            let host = parsed.host_str().unwrap_or_default().to_ascii_lowercase();
            let mut segments: Vec<String> = parsed
                .path_segments()
                .map(|iter| {
                    iter.filter(|s| !s.is_empty())
                        .map(|s| s.to_string())
                        .collect()
                })
                .unwrap_or_default();

            // 兼容 moviepilot://open?path=/subscribe/movie
            if host == "open"
                && segments.is_empty()
                && let Some(inner_path) = query.remove("path")
            {
                let inner_url = Url::parse(&format!(
                    "moviepilot://host/{}",
                    inner_path.trim_start_matches('/')
                ))
                .ok()?;
                segments = inner_url
                    .path_segments()
                    .map(|it| it.filter(|s| !s.is_empty()).map(str::to_string).collect())
                    .unwrap_or_default();
                for (k, v) in inner_url.query_pairs() {
                    query
                        .entry(k.to_ascii_lowercase())
                        .or_insert_with(|| v.into_owned());
                }
                return Self::route_segments(&segments, &query);
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

    fn route_segments(segments: &[String], query: &HashMap<String, String>) -> Option<Self> {
        let first = segments
            .first()
            .map(|s| s.to_ascii_lowercase())
            .unwrap_or_default();
        let second = segments.get(1).cloned();
        let third = segments.get(2).cloned();

        match first.as_str() {
            "" | "discover" | "home" => Some(Self::Discover),
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
            "history" => Some(Self::History {
                search: query.get("search").or_else(|| query.get("q")).cloned(),
            }),
            "workflow" | "workflows" => Some(Self::Workflows),
            "site" | "sites" => Some(Self::Sites),
            "message" | "messages" => Some(Self::Messages),
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
}
