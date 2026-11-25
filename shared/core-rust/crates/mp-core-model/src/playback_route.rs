//! 跨端媒体服务器直连优先与自动回退路由规划器。
//!
//! 职责：
//! 1. 根据用户播放偏好（STRM 直链、媒体服务器直连优先）与轻量并发探测结果，
//!    计算有序的主播放路由与降级回退队列；
//! 2. 严格校验 HTTP(S) 同源关系（scheme + host + 有效端口），供三端播放器在
//!    跨源 302 重定向时剥离直连令牌头，防止个人凭据外泄。

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use url::Url;

/// 默认局域网直连优先的延迟阈值（毫秒）：在此范围内始终优先局域网直连。
pub const DEFAULT_LAN_PREFERRED_MAX_LATENCY_MS: u32 = 350;

fn default_priority() -> i32 {
    100
}

fn default_true() -> bool {
    true
}

fn default_lan_preferred_max_latency_ms() -> u32 {
    DEFAULT_LAN_PREFERRED_MAX_LATENCY_MS
}

/// 媒体流路由类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlaybackRouteKind {
    StrmDirect,
    ServerLan,
    ServerWan,
    MpProxy,
}

impl PlaybackRouteKind {
    /// 返回面向用户展示的默认简体中文路由角标文案（对应 `shared/l10n/app.strings.json`）。
    pub fn label_zh(self) -> &'static str {
        match self {
            Self::StrmDirect => "STRM 直链",
            Self::ServerLan => "局域网直连",
            Self::ServerWan => "外网直连",
            Self::MpProxy => "后台中转",
        }
    }
}

/// 后端下发的单条候选播放路由。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaybackRouteCandidate {
    pub kind: PlaybackRouteKind,
    pub url: String,
    #[serde(default)]
    pub probe_url: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
    #[serde(default = "default_priority")]
    pub priority: i32,
    #[serde(default)]
    pub requires_same_origin_auth: bool,
}

/// 客户端播放路由偏好设置。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaybackRoutePreference {
    #[serde(default = "default_true")]
    pub prefer_strm_direct: bool,
    #[serde(default = "default_true")]
    pub prefer_server_direct: bool,
    #[serde(default = "default_lan_preferred_max_latency_ms")]
    pub lan_preferred_max_latency_ms: u32,
}

impl Default for PlaybackRoutePreference {
    fn default() -> Self {
        Self {
            prefer_strm_direct: true,
            prefer_server_direct: true,
            lan_preferred_max_latency_ms: DEFAULT_LAN_PREFERRED_MAX_LATENCY_MS,
        }
    }
}

/// 单条候选直连路由的轻量可达性探测结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RouteProbeOutcome {
    pub url: String,
    pub reachable: bool,
    #[serde(default)]
    pub latency_ms: Option<u32>,
}

/// 规划完成的主路由与有序降级回退队列。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaybackRoutePlan {
    pub active: PlaybackRouteCandidate,
    pub fallbacks: Vec<PlaybackRouteCandidate>,
    pub route_label_zh: String,
}

/// 跨端无状态播放路由规划器。
pub struct PlaybackRoutePlanner;

impl PlaybackRoutePlanner {
    /// 校验两条 HTTP(S) URL 是否严格同源（scheme、host 大小写无关及默认/显式端口一致）。
    pub fn is_same_http_origin(url_a: &str, url_b: &str) -> bool {
        let (Ok(a), Ok(b)) = (Url::parse(url_a.trim()), Url::parse(url_b.trim())) else {
            return false;
        };
        if !matches!(a.scheme(), "http" | "https") || a.scheme() != b.scheme() {
            return false;
        }
        let (Some(host_a), Some(host_b)) = (a.host(), b.host()) else {
            return false;
        };
        if host_a != host_b {
            return false;
        }
        let (Some(port_a), Some(port_b)) = (a.port_or_known_default(), b.port_or_known_default())
        else {
            return false;
        };
        port_a == port_b
    }

    /// 按偏好与探测结果生成主播放路由和降级队列。
    pub fn plan(
        routes: &[PlaybackRouteCandidate],
        prefs: &PlaybackRoutePreference,
        probes: &[RouteProbeOutcome],
    ) -> Option<PlaybackRoutePlan> {
        let mut strm_routes: Vec<PlaybackRouteCandidate> = Vec::new();
        let mut lan_routes: Vec<(u32, PlaybackRouteCandidate)> = Vec::new();
        let mut wan_routes: Vec<(u32, PlaybackRouteCandidate)> = Vec::new();
        let mut proxy_routes: Vec<PlaybackRouteCandidate> = Vec::new();
        let mut seen: Vec<(PlaybackRouteKind, String)> = Vec::new();

        for route in routes {
            let trimmed_url = route.url.trim();
            if trimmed_url.is_empty() || !Self::is_valid_http_url(trimmed_url) {
                continue;
            }
            let dedup_key = (route.kind, trimmed_url.to_string());
            if seen.contains(&dedup_key) {
                continue;
            }
            seen.push(dedup_key);

            let mut normalized = route.clone();
            normalized.url = trimmed_url.to_string();

            match normalized.kind {
                PlaybackRouteKind::StrmDirect => {
                    if prefs.prefer_strm_direct {
                        strm_routes.push(normalized);
                    }
                }
                PlaybackRouteKind::ServerLan => {
                    if !prefs.prefer_server_direct {
                        continue;
                    }
                    if let Some(latency_ms) = Self::reachable_latency(&normalized, probes) {
                        lan_routes.push((latency_ms, normalized));
                    }
                }
                PlaybackRouteKind::ServerWan => {
                    if !prefs.prefer_server_direct {
                        continue;
                    }
                    if let Some(latency_ms) = Self::reachable_latency(&normalized, probes) {
                        wan_routes.push((latency_ms, normalized));
                    }
                }
                PlaybackRouteKind::MpProxy => {
                    proxy_routes.push(normalized);
                }
            }
        }

        strm_routes.sort_by_key(|r| r.priority);
        lan_routes.sort_by_key(|(latency, r)| (*latency, r.priority));
        wan_routes.sort_by_key(|(latency, r)| (*latency, r.priority));
        proxy_routes.sort_by_key(|r| r.priority);

        let mut ordered: Vec<PlaybackRouteCandidate> = Vec::new();
        ordered.extend(strm_routes);

        let best_lan_latency = lan_routes.first().map(|(latency, _)| *latency);
        let best_wan_latency = wan_routes.first().map(|(latency, _)| *latency);
        let prefer_wan_before_lan = match (best_lan_latency, best_wan_latency) {
            (Some(lan_ms), Some(wan_ms)) => {
                lan_ms > prefs.lan_preferred_max_latency_ms && wan_ms < lan_ms
            }
            _ => false,
        };

        if prefer_wan_before_lan {
            ordered.extend(wan_routes.into_iter().map(|(_, r)| r));
            ordered.extend(lan_routes.into_iter().map(|(_, r)| r));
        } else {
            ordered.extend(lan_routes.into_iter().map(|(_, r)| r));
            ordered.extend(wan_routes.into_iter().map(|(_, r)| r));
        }

        ordered.extend(proxy_routes);

        let mut iter = ordered.into_iter();
        let active = iter.next()?;
        let route_label_zh = active.kind.label_zh().to_string();
        let fallbacks: Vec<PlaybackRouteCandidate> = iter.collect();
        Some(PlaybackRoutePlan {
            active,
            fallbacks,
            route_label_zh,
        })
    }

    fn is_valid_http_url(raw: &str) -> bool {
        let Ok(parsed) = Url::parse(raw) else {
            return false;
        };
        matches!(parsed.scheme(), "http" | "https") && parsed.host().is_some()
    }

    fn reachable_latency(
        route: &PlaybackRouteCandidate,
        probes: &[RouteProbeOutcome],
    ) -> Option<u32> {
        let probe_key = route
            .probe_url
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty());
        let outcome = probes.iter().find(|item| {
            let target = item.url.trim();
            probe_key.is_some_and(|key| key == target) || route.url == target
        })?;
        if !outcome.reachable {
            return None;
        }
        Some(outcome.latency_ms.unwrap_or(u32::MAX / 2))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_routes() -> Vec<PlaybackRouteCandidate> {
        vec![
            PlaybackRouteCandidate {
                kind: PlaybackRouteKind::StrmDirect,
                url: "https://cdn.example.com/movie.mkv".into(),
                probe_url: None,
                headers: BTreeMap::new(),
                priority: 10,
                requires_same_origin_auth: false,
            },
            PlaybackRouteCandidate {
                kind: PlaybackRouteKind::ServerLan,
                url: "http://192.168.1.10:8096/emby/Videos/1/stream?Static=true".into(),
                probe_url: Some("http://192.168.1.10:8096/emby/System/Ping".into()),
                headers: BTreeMap::from([("X-Emby-Token".into(), "tok".into())]),
                priority: 20,
                requires_same_origin_auth: false,
            },
            PlaybackRouteCandidate {
                kind: PlaybackRouteKind::ServerWan,
                url: "https://emby.example.com/emby/Videos/1/stream?Static=true".into(),
                probe_url: Some("https://emby.example.com/emby/System/Ping".into()),
                headers: BTreeMap::from([("X-Emby-Token".into(), "tok".into())]),
                priority: 30,
                requires_same_origin_auth: false,
            },
            PlaybackRouteCandidate {
                kind: PlaybackRouteKind::MpProxy,
                url: "https://mp.example.com/api/v1/mediaserver/stream?itemid=1".into(),
                probe_url: None,
                headers: BTreeMap::new(),
                priority: 100,
                requires_same_origin_auth: true,
            },
        ]
    }

    #[test]
    fn strm_takes_priority_with_full_fallback_chain() {
        let routes = sample_routes();
        let probes = vec![
            RouteProbeOutcome {
                url: "http://192.168.1.10:8096/emby/System/Ping".into(),
                reachable: true,
                latency_ms: Some(15),
            },
            RouteProbeOutcome {
                url: "https://emby.example.com/emby/System/Ping".into(),
                reachable: true,
                latency_ms: Some(60),
            },
        ];
        let plan =
            PlaybackRoutePlanner::plan(&routes, &PlaybackRoutePreference::default(), &probes)
                .unwrap();
        assert_eq!(plan.active.kind, PlaybackRouteKind::StrmDirect);
        assert_eq!(plan.route_label_zh, "STRM 直链");
        let kinds: Vec<_> = plan.fallbacks.iter().map(|r| r.kind).collect();
        assert_eq!(
            kinds,
            vec![
                PlaybackRouteKind::ServerLan,
                PlaybackRouteKind::ServerWan,
                PlaybackRouteKind::MpProxy
            ]
        );
    }

    #[test]
    fn lan_preferred_within_threshold_even_when_wan_is_slightly_faster() {
        let routes: Vec<_> = sample_routes()
            .into_iter()
            .filter(|r| r.kind != PlaybackRouteKind::StrmDirect)
            .collect();
        let probes = vec![
            RouteProbeOutcome {
                url: "http://192.168.1.10:8096/emby/System/Ping".into(),
                reachable: true,
                latency_ms: Some(120),
            },
            RouteProbeOutcome {
                url: "https://emby.example.com/emby/System/Ping".into(),
                reachable: true,
                latency_ms: Some(40),
            },
        ];
        let plan =
            PlaybackRoutePlanner::plan(&routes, &PlaybackRoutePreference::default(), &probes)
                .unwrap();
        assert_eq!(plan.active.kind, PlaybackRouteKind::ServerLan);
        assert_eq!(plan.route_label_zh, "局域网直连");
        assert_eq!(plan.fallbacks[0].kind, PlaybackRouteKind::ServerWan);
        assert_eq!(plan.fallbacks[1].kind, PlaybackRouteKind::MpProxy);
    }

    #[test]
    fn wan_wins_when_lan_is_unreachable_or_slow() {
        let routes: Vec<_> = sample_routes()
            .into_iter()
            .filter(|r| r.kind != PlaybackRouteKind::StrmDirect)
            .collect();
        let probes = vec![
            RouteProbeOutcome {
                url: "http://192.168.1.10:8096/emby/System/Ping".into(),
                reachable: true,
                latency_ms: Some(480),
            },
            RouteProbeOutcome {
                url: "https://emby.example.com/emby/System/Ping".into(),
                reachable: true,
                latency_ms: Some(55),
            },
        ];
        let plan =
            PlaybackRoutePlanner::plan(&routes, &PlaybackRoutePreference::default(), &probes)
                .unwrap();
        assert_eq!(plan.active.kind, PlaybackRouteKind::ServerWan);
        assert_eq!(plan.route_label_zh, "外网直连");
        assert_eq!(plan.fallbacks[0].kind, PlaybackRouteKind::ServerLan);
        assert_eq!(plan.fallbacks[1].kind, PlaybackRouteKind::MpProxy);
    }

    #[test]
    fn falls_back_to_mp_proxy_when_direct_probes_fail_or_disabled() {
        let routes: Vec<_> = sample_routes()
            .into_iter()
            .filter(|r| r.kind != PlaybackRouteKind::StrmDirect)
            .collect();
        let failed_probes = vec![
            RouteProbeOutcome {
                url: "http://192.168.1.10:8096/emby/System/Ping".into(),
                reachable: false,
                latency_ms: None,
            },
            RouteProbeOutcome {
                url: "https://emby.example.com/emby/System/Ping".into(),
                reachable: false,
                latency_ms: None,
            },
        ];
        let plan = PlaybackRoutePlanner::plan(
            &routes,
            &PlaybackRoutePreference::default(),
            &failed_probes,
        )
        .unwrap();
        assert_eq!(plan.active.kind, PlaybackRouteKind::MpProxy);
        assert_eq!(plan.route_label_zh, "后台中转");
        assert!(plan.fallbacks.is_empty());

        let disabled_prefs = PlaybackRoutePreference {
            prefer_strm_direct: false,
            prefer_server_direct: false,
            lan_preferred_max_latency_ms: 350,
        };
        let healthy_probes = vec![RouteProbeOutcome {
            url: "http://192.168.1.10:8096/emby/System/Ping".into(),
            reachable: true,
            latency_ms: Some(5),
        }];
        let plan_disabled =
            PlaybackRoutePlanner::plan(&sample_routes(), &disabled_prefs, &healthy_probes).unwrap();
        assert_eq!(plan_disabled.active.kind, PlaybackRouteKind::MpProxy);
        assert!(plan_disabled.fallbacks.is_empty());
    }

    #[test]
    fn same_http_origin_handles_default_ports_and_rejects_cross_origin() {
        assert!(PlaybackRoutePlanner::is_same_http_origin(
            "https://Emby.Example.COM:443/emby/Videos/1/stream",
            "https://emby.example.com/emby/System/Ping"
        ));
        assert!(PlaybackRoutePlanner::is_same_http_origin(
            "http://192.168.1.10:80/a",
            "http://192.168.1.10/b"
        ));
        assert!(!PlaybackRoutePlanner::is_same_http_origin(
            "https://emby.example.com/emby/Videos/1/stream",
            "https://cdn.115.com/file.mkv"
        ));
        assert!(!PlaybackRoutePlanner::is_same_http_origin(
            "http://emby.example.com:8096/a",
            "https://emby.example.com:8096/a"
        ));
        assert!(!PlaybackRoutePlanner::is_same_http_origin(
            "http://emby.example.com:8096/a",
            "http://emby.example.com:8097/a"
        ));
        assert!(!PlaybackRoutePlanner::is_same_http_origin(
            "file:///tmp/a.mp4",
            "file:///tmp/b.mp4"
        ));
    }
}
