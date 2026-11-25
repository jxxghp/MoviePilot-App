//! MoviePilot 跨端共享领域模型：服务地址规范化、DeepLink 路由解析、AI 流式 Markdown AST、
//! 订阅进度计算、社区勋章配色、媒体播放格式与小组件数据模型。

pub mod deep_link;
pub mod markdown;
pub mod medals;
pub mod playback_sync;
pub mod server_address;
pub mod subscribe;

pub use deep_link::{AppDeepLink, PlayableMediaFormat, PlayableMediaKind, StrmStreamSpec};
pub use markdown::{AgentMarkdownParser, MarkdownBlock, MarkdownBlockKind};
pub use medals::{CommunityMedalPalette, CommunityMedalsModel};
pub use playback_sync::{
    PendingPlaybackStop, PlaybackProgressPlanner, PlaybackSyncDecision, PlaybackSyncInput,
    PlaybackSyncState, PlaybackSyncTrigger,
};
pub use server_address::{ServerAddress, ServerAddressError};
pub use subscribe::{SubscribeProgress, SubscribeProgressModel};
