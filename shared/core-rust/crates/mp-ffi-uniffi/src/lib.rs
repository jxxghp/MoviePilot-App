//! iOS（Swift 6）与 Android（Kotlin Coroutines / JNI）统一 UniFFI 导出层。

use mp_core_api::{
    ApiEndpoint, ResourceFilterCriteria, ResourceFilterEngine, ResourceItem, SseStreamParser,
};
use mp_core_model::{
    AgentMarkdownParser, AppDeepLink, CommunityMedalsModel, EngineResolutionInput,
    PendingPlaybackStop, PlayableMediaFormat, PlaybackEngineRouter, PlaybackProgressPlanner,
    PlaybackRouteCandidate, PlaybackRoutePlanner, PlaybackRoutePreference, PlaybackSyncInput,
    PlaybackSyncState, RouteProbeOutcome, ServerAddress, SubscribeProgressModel,
    build_oauth_authorize_url as model_build_oauth_authorize_url,
    build_oauth_discovery_urls as model_build_oauth_discovery_urls,
    compute_pkce_s256_challenge as model_compute_pkce_s256_challenge,
    detect_cloudflare_access_challenge as model_detect_cloudflare_access_challenge,
    generate_pkce_pair as model_generate_pkce_pair,
    merge_cf_access_cookie as model_merge_cf_access_cookie,
    normalize_danmaku_query_title as model_normalize_danmaku_query_title,
    normalize_oauth_resource_url as model_normalize_oauth_resource_url,
    parse_audio_embedded_metadata as model_parse_audio_embedded_metadata,
    parse_oauth_callback_url as model_parse_oauth_callback_url,
    parse_oauth_server_metadata as model_parse_oauth_server_metadata,
    parse_protected_resource_metadata as model_parse_protected_resource_metadata,
    parse_protected_resource_metadata_detail as model_parse_protected_resource_metadata_detail,
    prepare_danmaku_timeline_json as model_prepare_danmaku_timeline_json,
};
use mp_core_plugin::{
    NativeCron, NativeFormExpression, PluginFormDraft, PluginUiDecoder,
    build_plugin_remote_cache_key, normalize_plugin_remote_entry,
    resolve_plugin_remote_upstream_path, validate_plugin_api_path,
    validate_plugin_shell_asset_path,
};
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

/// 根据用户直连偏好与轻量探测结果，规划主播放路由与降级队列，返回 `PlaybackRoutePlan` JSON（无可用路由返回 `None`）。
#[uniffi::export]
pub fn plan_playback_routes_json(
    routes_json: String,
    prefs_json: String,
    probes_json: String,
) -> Result<Option<String>, CoreFfiError> {
    let routes: Vec<PlaybackRouteCandidate> = if routes_json.trim().is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&routes_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let prefs: PlaybackRoutePreference = if prefs_json.trim().is_empty() {
        PlaybackRoutePreference::default()
    } else {
        serde_json::from_str(&prefs_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    let probes: Vec<RouteProbeOutcome> = if probes_json.trim().is_empty() {
        Vec::new()
    } else {
        serde_json::from_str(&probes_json)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?
    };
    match PlaybackRoutePlanner::plan(&routes, &prefs, &probes) {
        Some(plan) => serde_json::to_string(&plan)
            .map(Some)
            .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() }),
        None => Ok(None),
    }
}

/// 校验两条 HTTP(S) URL 是否严格同源（用于跨源 302 重定向时剥离直连令牌头）。
#[uniffi::export]
pub fn is_same_http_origin(url_a: String, url_b: String) -> bool {
    PlaybackRoutePlanner::is_same_http_origin(&url_a, &url_b)
}

/// 根据平台能力、用户内核偏好与媒体特征计算主播放内核及降级备选内核 JSON。
#[uniffi::export]
pub fn resolve_playback_engine_json(input_json: String) -> Result<String, CoreFfiError> {
    let input: EngineResolutionInput = serde_json::from_str(&input_json)
        .map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })?;
    let plan = PlaybackEngineRouter::resolve(&input);
    serde_json::to_string(&plan).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 安全构造自定义外部播放器启动 URL（拒绝危险协议与内嵌凭据链接）。
#[uniffi::export]
pub fn build_external_player_url(
    template: String,
    media_url: String,
    title: String,
) -> Result<String, CoreFfiError> {
    PlaybackEngineRouter::build_external_player_url(&template, &media_url, &title)
        .map_err(|msg| CoreFfiError::InvalidAddress { msg })
}

/// 校验并规范化插件 Bridge 请求的 `/api/v1/...` 路径，拒绝外部主机与路径穿越。
#[uniffi::export]
pub fn validate_plugin_bridge_api_path(raw_path: String) -> Result<String, CoreFfiError> {
    validate_plugin_api_path(&raw_path).map_err(|msg| CoreFfiError::InvalidEndpoint { msg })
}

/// 校验本地运行时壳 `/shell/...` 资产路径并返回安全的包内相对路径。
#[uniffi::export]
pub fn validate_plugin_shell_asset(virtual_path: String) -> Result<String, CoreFfiError> {
    validate_plugin_shell_asset_path(&virtual_path)
        .map_err(|msg| CoreFfiError::InvalidEndpoint { msg })
}

/// 生成按实例源 SHA-256、插件 ID 与版本/哈希隔离的磁盘缓存键 JSON。
#[uniffi::export]
pub fn build_plugin_remote_cache_key_json(
    instance_origin: String,
    plugin_id: String,
    version_or_hash: String,
) -> Result<String, CoreFfiError> {
    let key = build_plugin_remote_cache_key(&instance_origin, &plugin_id, &version_or_hash);
    serde_json::to_string(&key).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 将后端联邦插件远程入口地址规划为虚拟源路径与上游文件路径 JSON。
#[uniffi::export]
pub fn normalize_plugin_remote_entry_json(
    plugin_id: String,
    version_or_hash: String,
    raw_remote_url: String,
) -> Result<String, CoreFfiError> {
    let plan = normalize_plugin_remote_entry(&plugin_id, &version_or_hash, &raw_remote_url)
        .map_err(|msg| CoreFfiError::InvalidEndpoint { msg })?;
    serde_json::to_string(&plan).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 将虚拟源 `/plugin-remote/...` 请求安全还原为上游 API 路径与缓存相对路径 JSON。
#[uniffi::export]
pub fn resolve_plugin_remote_upstream_json(virtual_path: String) -> Result<String, CoreFfiError> {
    let target = resolve_plugin_remote_upstream_path(&virtual_path)
        .map_err(|msg| CoreFfiError::InvalidEndpoint { msg })?;
    serde_json::to_string(&target).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 离线批处理单集弹幕载荷（解析、过滤、屏蔽词、短窗去重合并与每秒限流），返回 `PreparedDanmakuTimeline` JSON。
#[uniffi::export]
pub fn prepare_danmaku_timeline_json(
    raw_payload_json: String,
    filter_options_json: String,
) -> Result<String, CoreFfiError> {
    model_prepare_danmaku_timeline_json(&raw_payload_json, &filter_options_json)
        .map_err(|msg| CoreFfiError::InvalidJson { msg })
}

/// 跨端统一生成弹幕手动搜索默认关键词与规范化展示标题。
#[uniffi::export]
pub fn normalize_danmaku_query_title(
    series_name: Option<String>,
    title: Option<String>,
    season: Option<i32>,
    episode: Option<i32>,
    file_name: Option<String>,
) -> String {
    model_normalize_danmaku_query_title(
        series_name.as_deref(),
        title.as_deref(),
        season,
        episode,
        file_name.as_deref(),
    )
}

/// 检测 HTTP 响应是否为 Cloudflare Access 拦截（302 / 401 WWW-Authenticate / 登录页 HTML），返回 JSON。
#[uniffi::export]
pub fn detect_cloudflare_access_challenge_json(
    status: u16,
    headers_json: String,
    body: String,
    request_url: String,
) -> String {
    let result =
        model_detect_cloudflare_access_challenge(status, &headers_json, &body, &request_url);
    serde_json::to_string(&result).unwrap_or_else(|_| r#"{"isChallenge":false,"reason":""}"#.into())
}

/// 生成 RFC 7636 PKCE `S256` 校验对与 `state` JSON。
#[uniffi::export]
pub fn generate_pkce_pair_json(extra_entropy: String) -> String {
    let pair = model_generate_pkce_pair(&extra_entropy);
    serde_json::to_string(&pair).unwrap_or_else(|_| "{}".into())
}

/// 根据 RFC 7636 计算 PKCE `S256` challenge。
#[uniffi::export]
pub fn compute_pkce_s256_challenge(code_verifier: String) -> String {
    model_compute_pkce_s256_challenge(&code_verifier)
}

/// 构造 RFC 9728 / RFC 8414 元数据探测候选 URL 列表 JSON。
#[uniffi::export]
pub fn build_oauth_discovery_urls_json(
    server_url: String,
    resource_metadata_url: Option<String>,
) -> String {
    let urls = model_build_oauth_discovery_urls(&server_url, resource_metadata_url.as_deref());
    serde_json::to_string(&urls).unwrap_or_else(|_| "[]".into())
}

/// 解析 RFC 9728 Protected Resource Metadata，返回 `authorization_servers` 元数据地址列表 JSON。
#[uniffi::export]
pub fn parse_protected_resource_metadata_json(json_str: String) -> Result<String, CoreFfiError> {
    let urls = model_parse_protected_resource_metadata(&json_str)
        .map_err(|msg| CoreFfiError::InvalidJson { msg })?;
    serde_json::to_string(&urls).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 解析 RFC 9728 Protected Resource Metadata，完整返回 `resource` 与 `authorizationServers` JSON。
#[uniffi::export]
pub fn parse_protected_resource_metadata_detail_json(
    json_str: String,
) -> Result<String, CoreFfiError> {
    let detail = model_parse_protected_resource_metadata_detail(&json_str)
        .map_err(|msg| CoreFfiError::InvalidJson { msg })?;
    serde_json::to_string(&detail).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 将实例地址规范化为 RFC 8707 `resource` 默认回退值。
#[uniffi::export]
pub fn normalize_oauth_resource_url(raw_url: String) -> Option<String> {
    model_normalize_oauth_resource_url(&raw_url)
}

/// 解析 RFC 8414 Authorization Server Metadata JSON。
#[uniffi::export]
pub fn parse_oauth_server_metadata_json(json_str: String) -> Result<String, CoreFfiError> {
    let meta = model_parse_oauth_server_metadata(&json_str)
        .map_err(|msg| CoreFfiError::InvalidJson { msg })?;
    serde_json::to_string(&meta).map_err(|e| CoreFfiError::InvalidJson { msg: e.to_string() })
}

/// 构造 OAuth 2.0 + PKCE (`S256`) + RFC 8707 `resource` 授权跳转 URL。
#[uniffi::export]
pub fn build_oauth_authorize_url(
    authorization_endpoint: String,
    client_id: String,
    redirect_uri: String,
    code_challenge: String,
    state: String,
    scope: String,
    resource: Option<String>,
) -> Result<String, CoreFfiError> {
    model_build_oauth_authorize_url(
        &authorization_endpoint,
        &client_id,
        &redirect_uri,
        &code_challenge,
        &state,
        &scope,
        resource.as_deref(),
    )
    .map_err(|msg| CoreFfiError::InvalidAddress { msg })
}

/// 解析并校验 `moviepilot://oauth/callback` 回调 URL，返回校验结果 JSON。
#[uniffi::export]
pub fn parse_oauth_callback_url_json(callback_url: String, expected_state: String) -> String {
    let res = model_parse_oauth_callback_url(&callback_url, &expected_state);
    serde_json::to_string(&res).unwrap_or_else(|_| r#"{"valid":false,"stateMatched":false}"#.into())
}

/// 安全合并 `CF_Authorization=<token>` 与现有 Cookie 头（保留 `resource_token` 等其他同源 Cookie）。
#[uniffi::export]
pub fn merge_cf_access_cookie(existing_cookie_header: String, cf_token: String) -> String {
    model_merge_cf_access_cookie(&existing_cookie_header, &cf_token)
}

/// 音频内嵌元数据解析结果（FLAC / ID3v2 / MP4·M4A / Ogg Vorbis·Opus）。
#[derive(Debug, Clone, uniffi::Record)]
pub struct AudioEmbeddedMetadataFfi {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub lyrics: Option<String>,
    pub cover_mime: Option<String>,
    pub cover_bytes: Option<Vec<u8>>,
    pub needed_head_bytes: Option<u64>,
    pub needed_tail_bytes: Option<u64>,
}

/// 解析音频文件头部（及可选尾部）字节中的内嵌标题、歌手、专辑、歌词与封面字节。
#[uniffi::export]
pub fn parse_audio_embedded_metadata(
    head_bytes: Vec<u8>,
    tail_bytes: Vec<u8>,
) -> AudioEmbeddedMetadataFfi {
    let tail = (!tail_bytes.is_empty()).then_some(tail_bytes.as_slice());
    let parsed = model_parse_audio_embedded_metadata(&head_bytes, tail);
    AudioEmbeddedMetadataFfi {
        title: parsed.title,
        artist: parsed.artist,
        album: parsed.album,
        lyrics: parsed.lyrics,
        cover_mime: parsed.cover_mime,
        cover_bytes: parsed.cover_bytes,
        needed_head_bytes: parsed.needed_head_bytes,
        needed_tail_bytes: parsed.needed_tail_bytes,
    }
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
