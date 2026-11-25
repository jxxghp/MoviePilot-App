//! iOS（Swift 6）与 Android（Kotlin Coroutines / JNI）统一 UniFFI 导出层。

use mp_core_api::{
    ApiEndpoint, ResourceFilterCriteria, ResourceFilterEngine, ResourceItem, SseStreamParser,
};
use mp_core_model::{
    AgentMarkdownParser, AppDeepLink, CommunityMedalsModel, PendingPlaybackStop,
    PlayableMediaFormat, PlaybackProgressPlanner, PlaybackSyncInput, PlaybackSyncState,
    ServerAddress, SubscribeProgressModel,
};
use mp_core_plugin::{NativeCron, NativeFormExpression, PluginFormDraft, PluginUiDecoder};
use mp_core_session::{NativePermissions, classify_auth_status, decode_jwt_claims};
use std::sync::Mutex;
use thiserror::Error;

uniffi::setup_scaffolding!();

/// FFI 统一错误类型。
#[derive(Debug, Error, uniffi::Error)]
pub enum CoreFfiError {
    #[error("无效地址：{msg}")]
    InvalidAddress { msg: String },
    #[error("无效端点：{msg}")]
    InvalidEndpoint { msg: String },
    #[error("JSON 解析错误：{msg}")]
    InvalidJson { msg: String },
}

/// 跨端 FFI Markdown 块记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct MarkdownBlockFfi {
    pub kind: String,
    pub level: u8,
    pub language: Option<String>,
    pub text: String,
    pub items: Vec<String>,
    pub rows_json: String,
}

/// 跨端 FFI SSE 事件记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct SseEventFfi {
    pub event: String,
    pub data: String,
    pub id: Option<String>,
    pub is_done: bool,
}

/// 跨端 FFI JWT 声明记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct JwtClaimsFfi {
    pub subject: Option<String>,
    pub user_name: Option<String>,
    pub exp: Option<i64>,
    pub super_user: bool,
    pub is_expired: bool,
}

/// 跨端 FFI 权限矩阵记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct PermissionsFfi {
    pub discovery: bool,
    pub search: bool,
    pub subscribe: bool,
    pub manage: bool,
    pub admin: bool,
}

/// 跨端 FFI Cron 摘要记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct CronSummaryFfi {
    pub raw_value: String,
    pub format: String,
    pub fields: Vec<String>,
    pub has_ambiguous_weekday: bool,
    pub description_zh: String,
    pub is_valid_five_field: bool,
}

/// 跨端 FFI 社区勋章金属色板记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct MedalPaletteFfi {
    pub medal_id: String,
    pub base_hex: String,
    pub rim_hex: String,
    pub engrave_dark_hex: String,
    pub engrave_light_hex: String,
    pub tier: String,
}

/// 跨端 FFI 订阅进度记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct SubscribeProgressFfi {
    pub total: i32,
    pub completed: i32,
    pub lack: i32,
    pub ratio: f64,
    pub label: String,
}

/// 规范化 MoviePilot 实例地址（保留反向代理子路径，拒绝非法协议与内嵌凭据）。
#[uniffi::export]
pub fn normalize_server_address(raw: String) -> Result<String, CoreFfiError> {
    ServerAddress::parse(&raw)
        .map(|addr| addr.as_str().to_string())
        .map_err(|e| CoreFfiError::InvalidAddress { msg: e.to_string() })
}

/// 校验目标 URL 是否严格属于给定实例源及部署子路径。
#[uniffi::export]
pub fn server_address_contains(base_url: String, candidate_url: String) -> bool {
    ServerAddress::parse(&base_url).is_ok_and(|addr| addr.contains(&candidate_url))
}

/// 基于实例根地址构造安全的 `/api/v1/...` 完整请求 URL。
#[uniffi::export]
pub fn build_v3_endpoint_url(
    base_url: String,
    path_segments: Vec<String>,
    query_json: String,
    trailing_slash: bool,
) -> Result<String, CoreFfiError> {
    let addr = ServerAddress::parse(&base_url)
        .map_err(|e| CoreFfiError::InvalidAddress { msg: e.to_string() })?;
    let query: Vec<(String, String)> = if query_json.trim().is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&query_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let endpoint = ApiEndpoint::new(path_segments, query, trailing_slash)
        .map_err(|e| CoreFfiError::InvalidEndpoint { msg: e.to_string() })?;
    endpoint
        .build_url(&addr)
        .map_err(|e| CoreFfiError::InvalidEndpoint { msg: e.to_string() })
}

/// 解析 `moviepilot://` 或 Web 路由，返回强类型 JSON 结构（非法路由返回 `None`）。
#[uniffi::export]
pub fn parse_deep_link_json(raw_url: String) -> Option<String> {
    let parsed = AppDeepLink::parse(&raw_url)?;
    serde_json::to_string(&parsed).ok()
}

/// 跨端 FFI STRM 直链解析结果记录。
#[derive(Debug, Clone, uniffi::Record)]
pub struct StrmStreamFfi {
    pub url: String,
    pub headers_json: String,
    pub media_kind: String,
}

/// 根据文件扩展名或路径推断原生播放器媒体类型（`"video"` / `"audio"` / `None`）。
#[uniffi::export]
pub fn detect_playable_media_kind(path_or_ext: String, include_streaming: bool) -> Option<String> {
    let kind = if path_or_ext.contains('.') && !path_or_ext.starts_with('.') {
        PlayableMediaFormat::kind_for_path(&path_or_ext, include_streaming)
    } else {
        PlayableMediaFormat::kind_for_extension(&path_or_ext, include_streaming)
    }?;
    Some(
        match kind {
            mp_core_model::PlayableMediaKind::Video => "video",
            mp_core_model::PlayableMediaKind::Audio => "audio",
        }
        .to_string(),
    )
}

/// 解析 `.strm` 文本并返回规范化 HTTP(S) 直链、请求头 JSON 与媒体类型。
#[uniffi::export]
pub fn parse_strm_content(
    raw_text: String,
    fallback_file_name: Option<String>,
) -> Result<StrmStreamFfi, CoreFfiError> {
    let spec = PlayableMediaFormat::parse_strm_content(&raw_text, fallback_file_name.as_deref())
        .map_err(|msg| CoreFfiError::InvalidAddress { msg })?;
    let headers_json = serde_json::to_string(&spec.headers)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let media_kind = match spec.media_kind {
        mp_core_model::PlayableMediaKind::Video => "video".to_string(),
        mp_core_model::PlayableMediaKind::Audio => "audio".to_string(),
    };
    Ok(StrmStreamFfi {
        url: spec.url,
        headers_json,
        media_kind,
    })
}

/// 解析 AI 智能助手流式 Markdown 文本为块级渲染节点。
#[uniffi::export]
pub fn parse_agent_markdown(markdown: String) -> Vec<MarkdownBlockFfi> {
    AgentMarkdownParser::parse(&markdown)
        .into_iter()
        .map(|b| MarkdownBlockFfi {
            kind: serde_json::to_value(&b.kind)
                .ok()
                .and_then(|v| v.as_str().map(str::to_string))
                .unwrap_or_else(|| "paragraph".to_string()),
            level: b.level,
            language: b.language,
            text: b.text,
            items: b.items,
            rows_json: serde_json::to_string(&b.rows).unwrap_or_else(|_| "[]".to_string()),
        })
        .collect()
}

/// 有状态流式 SSE 解析器对象，供原生网络流逐块喂入字节并消费事件帧。
#[derive(uniffi::Object)]
pub struct NativeSseParser {
    inner: Mutex<SseStreamParser>,
}

impl Default for NativeSseParser {
    fn default() -> Self {
        Self::new()
    }
}

#[uniffi::export]
impl NativeSseParser {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(SseStreamParser::new()),
        }
    }

    pub fn push_chunk(&self, chunk: String) -> Vec<SseEventFfi> {
        let mut guard = self.inner.lock().expect("sse lock");
        guard
            .push_chunk(&chunk)
            .into_iter()
            .map(|e| SseEventFfi {
                event: e.event,
                data: e.data,
                id: e.id,
                is_done: e.is_done,
            })
            .collect()
    }

    pub fn finish(&self) -> Vec<SseEventFfi> {
        let mut guard = self.inner.lock().expect("sse lock");
        guard
            .finish()
            .into_iter()
            .map(|e| SseEventFfi {
                event: e.event,
                data: e.data,
                id: e.id,
                is_done: e.is_done,
            })
            .collect()
    }
}

/// 执行站点资源 9 维级联筛选与同规格分组，返回完整结果 JSON。
#[uniffi::export]
pub fn filter_and_group_resources(
    resources_json: String,
    criteria_json: String,
) -> Result<String, CoreFfiError> {
    let items: Vec<ResourceItem> = serde_json::from_str(&resources_json)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let criteria: ResourceFilterCriteria = if criteria_json.trim().is_empty() {
        ResourceFilterCriteria::default()
    } else {
        serde_json::from_str(&criteria_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let result = ResourceFilterEngine::evaluate(&items, &criteria);
    serde_json::to_string(&result).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 解码 JWT 声明并判断是否过期。
#[uniffi::export]
pub fn decode_jwt_token_claims(token: String, now_epoch_secs: i64) -> JwtClaimsFfi {
    let c = decode_jwt_claims(&token, now_epoch_secs);
    JwtClaimsFfi {
        subject: c.subject,
        user_name: c.user_name,
        exp: c.exp,
        super_user: c.super_user,
        is_expired: c.is_expired,
    }
}

/// 解析用户权限 JSON（严格对齐前端与 iOS 语义）。
#[uniffi::export]
pub fn evaluate_user_permissions(
    permissions_json: String,
    is_superuser: bool,
) -> Result<PermissionsFfi, CoreFfiError> {
    let val: serde_json::Value = if permissions_json.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&permissions_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let perms = NativePermissions::from_json(&val, is_superuser);
    Ok(PermissionsFfi {
        discovery: perms.discovery,
        search: perms.search,
        subscribe: perms.subscribe,
        manage: perms.manage,
        admin: perms.admin,
    })
}

/// 分类 401/403 响应决策：`"valid"` / `"logout"` / `"forbidden"`。
#[uniffi::export]
pub fn classify_http_auth_status(status: u16, body_text: String) -> String {
    match classify_auth_status(status, &body_text) {
        mp_core_session::SessionAuthDecision::Valid => "valid",
        mp_core_session::SessionAuthDecision::UnauthorizedMustLogout => "logout",
        mp_core_session::SessionAuthDecision::ForbiddenKeepSession => "forbidden",
    }
    .to_string()
}

/// 解码动态插件 `get_form`/`get_page` JSON 并输出跨端统一渲染规划树 JSON。
#[uniffi::export]
pub fn plan_plugin_form_json(document_json: String) -> Result<String, CoreFfiError> {
    let doc: serde_json::Value = serde_json::from_str(&document_json)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let plan = PluginUiDecoder::plan(&doc);
    serde_json::to_string(&plan).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 无损合并插件表单补丁到服务端原始模型（保留未知键与 64 位大整数）。
#[uniffi::export]
pub fn apply_plugin_form_patch(
    original_model_json: String,
    patch_json: String,
) -> Result<String, CoreFfiError> {
    let orig: serde_json::Value = serde_json::from_str(&original_model_json)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let patch: serde_json::Value = serde_json::from_str(&patch_json)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let merged = PluginFormDraft::apply_patch(&orig, &patch);
    serde_json::to_string(&merged).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 安全评估插件表单条件表达式（`v-show` / `v-if`）。
#[uniffi::export]
pub fn evaluate_plugin_expression(expr: String, model_json: String) -> bool {
    let model = serde_json::from_str(&model_json).unwrap_or(serde_json::Value::Null);
    NativeFormExpression::evaluate(&expr, &model)
}

/// 分析 5 字段 Cron 表达式并返回中文说明。
#[uniffi::export]
pub fn analyze_cron_expression(expr: String) -> CronSummaryFfi {
    let s = NativeCron::analyze(&expr);
    CronSummaryFfi {
        raw_value: s.raw_value,
        format: match s.format {
            mp_core_plugin::CronFormat::Empty => "empty",
            mp_core_plugin::CronFormat::FiveFields => "fiveFields",
            mp_core_plugin::CronFormat::Custom => "custom",
        }
        .to_string(),
        fields: s.fields,
        has_ambiguous_weekday: s.has_ambiguous_weekday,
        description_zh: s.description_zh,
        is_valid_five_field: s.is_valid_five_field,
    }
}

/// 计算社区 3D 勋章的金属基色与背面凹雕配色方案。
#[uniffi::export]
pub fn compute_medal_palette(medal_id: String) -> MedalPaletteFfi {
    let p = CommunityMedalsModel::palette_for_medal(&medal_id);
    MedalPaletteFfi {
        medal_id: p.medal_id,
        base_hex: p.base_hex,
        rim_hex: p.rim_hex,
        engrave_dark_hex: p.engrave_dark_hex,
        engrave_light_hex: p.engrave_light_hex,
        tier: p.tier,
    }
}

/// 计算剧集订阅完成进度。
#[uniffi::export]
pub fn compute_subscribe_progress(total_episode: i32, lack_episode: i32) -> SubscribeProgressFfi {
    let p = SubscribeProgressModel::compute(total_episode, lack_episode);
    SubscribeProgressFfi {
        total: p.total,
        completed: p.completed,
        lack: p.lack,
        ratio: p.ratio,
        label: p.label,
    }
}

/// 执行一次跨端播放进度与实时会话上报状态机推演，返回决策及下一状态 JSON。
#[uniffi::export]
pub fn plan_playback_sync_step_json(
    state_json: String,
    input_json: String,
) -> Result<String, CoreFfiError> {
    let state: PlaybackSyncState = if state_json.trim().is_empty() {
        PlaybackSyncState::default()
    } else {
        serde_json::from_str(&state_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let input: PlaybackSyncInput = serde_json::from_str(&input_json)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let decision = PlaybackProgressPlanner::step(&state, &input);
    serde_json::to_string(&decision).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 规整离线待补报 `stopped` 队列（去重、清理 7 天过期项并裁剪至上限）。
#[uniffi::export]
pub fn normalize_pending_playback_stops_json(
    entries_json: String,
    now_epoch_ms: i64,
) -> Result<String, CoreFfiError> {
    let entries: Vec<PendingPlaybackStop> = if entries_json.trim().is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&entries_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let normalized = PlaybackProgressPlanner::normalize_pending_stops(entries, now_epoch_ms);
    serde_json::to_string(&normalized).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 返回 Rust 共享内核版本号，用于三端 FFI 冒烟健康检查。
#[uniffi::export]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ffi_smoke_test_roundtrip() {
        assert_eq!(core_version(), env!("CARGO_PKG_VERSION"));
        let parsed = parse_deep_link_json("moviepilot://media/tmdb/550?type=movie".into()).unwrap();
        assert!(parsed.contains("\"media_id\":\"550\""));
        let cron = analyze_cron_expression("*/15 * * * *".into());
        assert!(cron.is_valid_five_field);
        assert_eq!(cron.description_zh, "每 15 分钟执行一次");
    }
}
