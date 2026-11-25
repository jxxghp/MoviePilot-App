//! MoviePilot 跨端共享领域模型：服务地址规范化、DeepLink 路由解析、AI 流式 Markdown AST、
//! 订阅进度计算、社区勋章配色、媒体播放格式与小组件数据模型。

pub mod cloudflare_oauth;
pub mod danmaku;
pub mod deep_link;
pub mod markdown;
pub mod medals;
pub mod playback_engine;
pub mod playback_route;
pub mod playback_sync;
pub mod server_address;
pub mod subscribe;

pub use cloudflare_oauth::{
    CloudflareChallengeResult, DEFAULT_CF_OAUTH_REDIRECT_URI, OAuthCallbackResult,
    OAuthServerMetadata, PkcePair, build_oauth_authorize_url, build_oauth_discovery_urls,
    compute_pkce_s256_challenge, detect_cloudflare_access_challenge, generate_pkce_pair,
    merge_cf_access_cookie, parse_oauth_callback_url, parse_oauth_server_metadata,
    parse_protected_resource_metadata,
};
pub use danmaku::{
    DanmakuFilterOptions, DanmakuItem, DanmakuMode, PreparedDanmakuTimeline,
    normalize_danmaku_query_title, prepare_danmaku_timeline, prepare_danmaku_timeline_json,
};
pub use deep_link::{AppDeepLink, PlayableMediaFormat, PlayableMediaKind, StrmStreamSpec};
pub use markdown::{AgentMarkdownParser, MarkdownBlock, MarkdownBlockKind};
pub use medals::{CommunityMedalPalette, CommunityMedalsModel};
pub use playback_engine::{
    BufferProfile, DecodeMode, EngineResolutionInput, EngineResolutionPlan, PlatformKind,
    PlaybackEngineChoice, PlaybackEngineRouter, ResolvedPlaybackEngine,
};
pub use playback_route::{
    DEFAULT_LAN_PREFERRED_MAX_LATENCY_MS, PlaybackRouteCandidate, PlaybackRouteKind,
    PlaybackRoutePlan, PlaybackRoutePlanner, PlaybackRoutePreference, RouteProbeOutcome,
};
pub use playback_sync::{
    PendingPlaybackStop, PlaybackProgressPlanner, PlaybackSyncDecision, PlaybackSyncInput,
    PlaybackSyncState, PlaybackSyncTrigger,
};
pub use server_address::{ServerAddress, ServerAddressError};
pub use subscribe::{SubscribeProgress, SubscribeProgressModel};
