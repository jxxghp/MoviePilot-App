//! HarmonyOS NEXT（ArkTS）ohos-rs / Node-API 导出层。
//! 与 `mp-ffi-uniffi` 保持 1:1 能力契约对齐，供 `harmony/commons/core_rust_bridge` 直接调用。

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use mp_core_api::{ApiEndpoint, ResourceFilterCriteria, ResourceFilterEngine, ResourceItem};
use mp_core_model::{
    AgentMarkdownParser, AppDeepLink, AudioEmbeddedMetadataJson, CommunityMedalsModel,
    EngineResolutionInput, PendingPlaybackStop, PlayableMediaFormat, PlaybackEngineRouter,
    PlaybackProgressPlanner, PlaybackRouteCandidate, PlaybackRoutePlanner, PlaybackRoutePreference,
    PlaybackSyncInput, PlaybackSyncState, RouteProbeOutcome, ServerAddress, SubscribeProgressModel,
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

/// 跨平台纯函数门面：供 `#[napi]`（target_env = "ohos"）与宿主机单元测试复用同一实现。
pub mod bridge {
    use super::*;

    pub fn core_version() -> String {
        env!("CARGO_PKG_VERSION").to_string()
    }

    pub fn normalize_server_address(raw: &str) -> Result<String, String> {
        ServerAddress::parse(raw)
            .map(|a| a.as_str().to_string())
            .map_err(|e| e.to_string())
    }

    pub fn server_address_contains(base_url: &str, candidate_url: &str) -> bool {
        ServerAddress::parse(base_url)
            .map(|addr| addr.contains(candidate_url))
            .unwrap_or(false)
    }

    pub fn build_v3_endpoint_url(
        base_url: &str,
        segments: Vec<String>,
        query_json: &str,
        trailing_slash: bool,
    ) -> Result<String, String> {
        let addr = ServerAddress::parse(base_url).map_err(|e| e.to_string())?;
        let query: Vec<(String, String)> = if query_json.trim().is_empty() {
            Vec::new()
        } else {
            serde_json::from_str(query_json).map_err(|e| e.to_string())?
        };
        let ep = ApiEndpoint::new(segments, query, trailing_slash).map_err(|e| e.to_string())?;
        ep.build_url(&addr).map_err(|e| e.to_string())
    }

    pub fn parse_deep_link_json(raw_url: &str) -> String {
        AppDeepLink::parse(raw_url)
            .and_then(|v| serde_json::to_string(&v).ok())
            .unwrap_or_default()
    }

    pub fn detect_playable_media_kind(path_or_ext: &str, include_streaming: bool) -> String {
        let kind = if path_or_ext.contains('.') && !path_or_ext.starts_with('.') {
            PlayableMediaFormat::kind_for_path(path_or_ext, include_streaming)
        } else {
            PlayableMediaFormat::kind_for_extension(path_or_ext, include_streaming)
        };
        match kind {
            Some(mp_core_model::PlayableMediaKind::Video) => "video".to_string(),
            Some(mp_core_model::PlayableMediaKind::Audio) => "audio".to_string(),
            None => String::new(),
        }
    }

    pub fn parse_strm_json(raw_text: &str, fallback_file_name: &str) -> Result<String, String> {
        let fallback = (!fallback_file_name.trim().is_empty()).then_some(fallback_file_name.trim());
        let spec = PlayableMediaFormat::parse_strm_content(raw_text, fallback)?;
        serde_json::to_string(&spec).map_err(|e| e.to_string())
    }

    pub fn parse_agent_markdown_json(markdown: &str) -> String {
        let blocks = AgentMarkdownParser::parse(markdown);
        serde_json::to_string(&blocks).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn filter_and_group_resources(
        resources_json: &str,
        criteria_json: &str,
    ) -> Result<String, String> {
        let items: Vec<ResourceItem> =
            serde_json::from_str(resources_json).map_err(|e| e.to_string())?;
        let criteria: ResourceFilterCriteria = if criteria_json.trim().is_empty() {
            ResourceFilterCriteria::default()
        } else {
            serde_json::from_str(criteria_json).map_err(|e| e.to_string())?
        };
        serde_json::to_string(&ResourceFilterEngine::evaluate(&items, &criteria))
            .map_err(|e| e.to_string())
    }

    pub fn decode_jwt_claims_json(token: &str, now_epoch_secs: i64) -> String {
        serde_json::to_string(&decode_jwt_claims(token, now_epoch_secs))
            .unwrap_or_else(|_| "{}".to_string())
    }

    pub fn evaluate_permissions_json(permissions_json: &str, is_superuser: bool) -> String {
        let val = serde_json::from_str(permissions_json).unwrap_or(serde_json::json!({}));
        serde_json::to_string(&NativePermissions::from_json(&val, is_superuser))
            .unwrap_or_else(|_| "{}".to_string())
    }

    pub fn classify_auth_status_str(status: u16, body: &str) -> String {
        match classify_auth_status(status, body) {
            mp_core_session::SessionAuthDecision::Valid => "valid",
            mp_core_session::SessionAuthDecision::UnauthorizedMustLogout => "logout",
            mp_core_session::SessionAuthDecision::ForbiddenKeepSession => "forbidden",
        }
        .to_string()
    }

    pub fn plan_plugin_form_json(document_json: &str) -> Result<String, String> {
        let doc: serde_json::Value =
            serde_json::from_str(document_json).map_err(|e| e.to_string())?;
        serde_json::to_string(&PluginUiDecoder::plan(&doc)).map_err(|e| e.to_string())
    }

    pub fn apply_plugin_form_patch(
        original_model_json: &str,
        patch_json: &str,
    ) -> Result<String, String> {
        let orig: serde_json::Value =
            serde_json::from_str(original_model_json).map_err(|e| e.to_string())?;
        let patch: serde_json::Value =
            serde_json::from_str(patch_json).map_err(|e| e.to_string())?;
        serde_json::to_string(&PluginFormDraft::apply_patch(&orig, &patch))
            .map_err(|e| e.to_string())
    }

    pub fn evaluate_plugin_expression(expr: &str, model_json: &str) -> bool {
        let model = serde_json::from_str(model_json).unwrap_or(serde_json::Value::Null);
        NativeFormExpression::evaluate(expr, &model)
    }

    pub fn analyze_cron_json(expr: &str) -> String {
        serde_json::to_string(&NativeCron::analyze(expr)).unwrap_or_else(|_| "{}".to_string())
    }

    pub fn compute_medal_palette_json(medal_id: &str) -> String {
        serde_json::to_string(&CommunityMedalsModel::palette_for_medal(medal_id))
            .unwrap_or_else(|_| "{}".to_string())
    }

    pub fn compute_subscribe_progress_json(total: i32, lack: i32) -> String {
        serde_json::to_string(&SubscribeProgressModel::compute(total, lack))
            .unwrap_or_else(|_| "{}".to_string())
    }

    pub fn plan_playback_sync_step_json(
        state_json: &str,
        input_json: &str,
    ) -> Result<String, String> {
        let state: PlaybackSyncState = if state_json.trim().is_empty() {
            PlaybackSyncState::default()
        } else {
            serde_json::from_str(state_json).map_err(|e| e.to_string())?
        };
        let input: PlaybackSyncInput =
            serde_json::from_str(input_json).map_err(|e| e.to_string())?;
        serde_json::to_string(&PlaybackProgressPlanner::step(&state, &input))
            .map_err(|e| e.to_string())
    }

    pub fn normalize_pending_playback_stops_json(
        entries_json: &str,
        now_epoch_ms: i64,
    ) -> Result<String, String> {
        let entries: Vec<PendingPlaybackStop> = if entries_json.trim().is_empty() {
            Vec::new()
        } else {
            serde_json::from_str(entries_json).map_err(|e| e.to_string())?
        };
        let normalized = PlaybackProgressPlanner::normalize_pending_stops(entries, now_epoch_ms);
        serde_json::to_string(&normalized).map_err(|e| e.to_string())
    }

    pub fn plan_playback_routes_json(
        routes_json: &str,
        prefs_json: &str,
        probes_json: &str,
    ) -> Result<String, String> {
        let routes: Vec<PlaybackRouteCandidate> = if routes_json.trim().is_empty() {
            Vec::new()
        } else {
            serde_json::from_str(routes_json).map_err(|e| e.to_string())?
        };
        let prefs: PlaybackRoutePreference = if prefs_json.trim().is_empty() {
            PlaybackRoutePreference::default()
        } else {
            serde_json::from_str(prefs_json).map_err(|e| e.to_string())?
        };
        let probes: Vec<RouteProbeOutcome> = if probes_json.trim().is_empty() {
            Vec::new()
        } else {
            serde_json::from_str(probes_json).map_err(|e| e.to_string())?
        };
        match PlaybackRoutePlanner::plan(&routes, &prefs, &probes) {
            Some(plan) => serde_json::to_string(&plan).map_err(|e| e.to_string()),
            None => Ok(String::new()),
        }
    }

    pub fn is_same_http_origin(url_a: &str, url_b: &str) -> bool {
        PlaybackRoutePlanner::is_same_http_origin(url_a, url_b)
    }

    pub fn resolve_playback_engine_json(input_json: &str) -> Result<String, String> {
        let input: EngineResolutionInput =
            serde_json::from_str(input_json).map_err(|e| e.to_string())?;
        serde_json::to_string(&PlaybackEngineRouter::resolve(&input)).map_err(|e| e.to_string())
    }

    pub fn build_external_player_url(
        template: &str,
        media_url: &str,
        title: &str,
    ) -> Result<String, String> {
        PlaybackEngineRouter::build_external_player_url(template, media_url, title)
    }

    pub fn validate_plugin_bridge_api_path(raw_path: &str) -> Result<String, String> {
        validate_plugin_api_path(raw_path)
    }

    pub fn validate_plugin_shell_asset(virtual_path: &str) -> Result<String, String> {
        validate_plugin_shell_asset_path(virtual_path)
    }

    pub fn build_plugin_remote_cache_key_json(
        instance_origin: &str,
        plugin_id: &str,
        version_or_hash: &str,
    ) -> Result<String, String> {
        let key = build_plugin_remote_cache_key(instance_origin, plugin_id, version_or_hash);
        serde_json::to_string(&key).map_err(|e| e.to_string())
    }

    pub fn normalize_plugin_remote_entry_json(
        plugin_id: &str,
        version_or_hash: &str,
        raw_remote_url: &str,
    ) -> Result<String, String> {
        let plan = normalize_plugin_remote_entry(plugin_id, version_or_hash, raw_remote_url)?;
        serde_json::to_string(&plan).map_err(|e| e.to_string())
    }

    pub fn resolve_plugin_remote_upstream_json(virtual_path: &str) -> Result<String, String> {
        let target = resolve_plugin_remote_upstream_path(virtual_path)?;
        serde_json::to_string(&target).map_err(|e| e.to_string())
    }

    pub fn prepare_danmaku_timeline_json(
        raw_payload_json: &str,
        filter_options_json: &str,
    ) -> Result<String, String> {
        model_prepare_danmaku_timeline_json(raw_payload_json, filter_options_json)
    }

    pub fn normalize_danmaku_query_title(
        series_name: &str,
        title: &str,
        season: i32,
        episode: i32,
        file_name: &str,
    ) -> String {
        model_normalize_danmaku_query_title(
            (!series_name.trim().is_empty()).then_some(series_name),
            (!title.trim().is_empty()).then_some(title),
            (season >= 0).then_some(season),
            (episode >= 0).then_some(episode),
            (!file_name.trim().is_empty()).then_some(file_name),
        )
    }

    pub fn detect_cloudflare_access_challenge_json(
        status: u16,
        headers_json: &str,
        body: &str,
        request_url: &str,
    ) -> String {
        let result =
            model_detect_cloudflare_access_challenge(status, headers_json, body, request_url);
        serde_json::to_string(&result)
            .unwrap_or_else(|_| r#"{"isChallenge":false,"reason":""}"#.into())
    }

    pub fn generate_pkce_pair_json(extra_entropy: &str) -> String {
        serde_json::to_string(&model_generate_pkce_pair(extra_entropy))
            .unwrap_or_else(|_| "{}".into())
    }

    pub fn compute_pkce_s256_challenge(code_verifier: &str) -> String {
        model_compute_pkce_s256_challenge(code_verifier)
    }

    pub fn build_oauth_discovery_urls_json(
        server_url: &str,
        resource_metadata_url: &str,
    ) -> String {
        let meta = (!resource_metadata_url.trim().is_empty()).then_some(resource_metadata_url);
        serde_json::to_string(&model_build_oauth_discovery_urls(server_url, meta))
            .unwrap_or_else(|_| "[]".into())
    }

    pub fn parse_protected_resource_metadata_json(json_str: &str) -> Result<String, String> {
        let urls = model_parse_protected_resource_metadata(json_str)?;
        serde_json::to_string(&urls).map_err(|e| e.to_string())
    }

    pub fn parse_protected_resource_metadata_detail_json(json_str: &str) -> Result<String, String> {
        let detail = model_parse_protected_resource_metadata_detail(json_str)?;
        serde_json::to_string(&detail).map_err(|e| e.to_string())
    }

    pub fn normalize_oauth_resource_url(raw_url: &str) -> String {
        model_normalize_oauth_resource_url(raw_url).unwrap_or_default()
    }

    pub fn parse_oauth_server_metadata_json(json_str: &str) -> Result<String, String> {
        let meta = model_parse_oauth_server_metadata(json_str)?;
        serde_json::to_string(&meta).map_err(|e| e.to_string())
    }

    pub fn build_oauth_authorize_url(
        authorization_endpoint: &str,
        client_id: &str,
        redirect_uri: &str,
        code_challenge: &str,
        state: &str,
        scope: &str,
        resource: &str,
    ) -> Result<String, String> {
        let opt_resource = (!resource.trim().is_empty()).then_some(resource);
        model_build_oauth_authorize_url(
            authorization_endpoint,
            client_id,
            redirect_uri,
            code_challenge,
            state,
            scope,
            opt_resource,
        )
    }

    pub fn parse_oauth_callback_url_json(callback_url: &str, expected_state: &str) -> String {
        serde_json::to_string(&model_parse_oauth_callback_url(
            callback_url,
            expected_state,
        ))
        .unwrap_or_else(|_| r#"{"valid":false,"stateMatched":false}"#.into())
    }

    pub fn merge_cf_access_cookie(existing_cookie_header: &str, cf_token: &str) -> String {
        model_merge_cf_access_cookie(existing_cookie_header, cf_token)
    }

    pub fn parse_audio_embedded_metadata_json(head_base64: &str, tail_base64: &str) -> String {
        let head = BASE64_STANDARD
            .decode(head_base64.trim().as_bytes())
            .unwrap_or_default();
        let tail_vec = if tail_base64.trim().is_empty() {
            Vec::new()
        } else {
            BASE64_STANDARD
                .decode(tail_base64.trim().as_bytes())
                .unwrap_or_default()
        };
        let tail = (!tail_vec.is_empty()).then_some(tail_vec.as_slice());
        let parsed = model_parse_audio_embedded_metadata(&head, tail);
        let json_payload: AudioEmbeddedMetadataJson = parsed.into();
        serde_json::to_string(&json_payload).unwrap_or_else(|_| "{}".into())
    }
}

#[cfg(target_env = "ohos")]
mod napi_exports {
    use super::bridge;
    use napi_derive_ohos::napi;
    use napi_ohos::Result;

    #[napi]
    pub fn core_version() -> String {
        bridge::core_version()
    }

    #[napi]
    pub fn normalize_server_address(raw: String) -> Result<String> {
        bridge::normalize_server_address(&raw).map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn server_address_contains(base_url: String, candidate_url: String) -> bool {
        bridge::server_address_contains(&base_url, &candidate_url)
    }

    #[napi]
    pub fn build_v3_endpoint_url(
        base_url: String,
        segments: Vec<String>,
        query_json: String,
        trailing_slash: bool,
    ) -> Result<String> {
        bridge::build_v3_endpoint_url(&base_url, segments, &query_json, trailing_slash)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn parse_deep_link_json(raw_url: String) -> String {
        bridge::parse_deep_link_json(&raw_url)
    }

    #[napi]
    pub fn detect_playable_media_kind(path_or_ext: String, include_streaming: bool) -> String {
        bridge::detect_playable_media_kind(&path_or_ext, include_streaming)
    }

    #[napi]
    pub fn parse_strm_json(raw_text: String, fallback_file_name: String) -> Result<String> {
        bridge::parse_strm_json(&raw_text, &fallback_file_name)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn parse_agent_markdown_json(markdown: String) -> String {
        bridge::parse_agent_markdown_json(&markdown)
    }

    #[napi]
    pub fn filter_and_group_resources(
        resources_json: String,
        criteria_json: String,
    ) -> Result<String> {
        bridge::filter_and_group_resources(&resources_json, &criteria_json)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn decode_jwt_claims_json(token: String, now_epoch_secs: i64) -> String {
        bridge::decode_jwt_claims_json(&token, now_epoch_secs)
    }

    #[napi]
    pub fn evaluate_permissions_json(permissions_json: String, is_superuser: bool) -> String {
        bridge::evaluate_permissions_json(&permissions_json, is_superuser)
    }

    #[napi]
    pub fn classify_auth_status_str(status: u16, body: String) -> String {
        bridge::classify_auth_status_str(status, &body)
    }

    #[napi]
    pub fn plan_plugin_form_json(document_json: String) -> Result<String> {
        bridge::plan_plugin_form_json(&document_json).map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn apply_plugin_form_patch(
        original_model_json: String,
        patch_json: String,
    ) -> Result<String> {
        bridge::apply_plugin_form_patch(&original_model_json, &patch_json)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn evaluate_plugin_expression(expr: String, model_json: String) -> bool {
        bridge::evaluate_plugin_expression(&expr, &model_json)
    }

    #[napi]
    pub fn analyze_cron_json(expr: String) -> String {
        bridge::analyze_cron_json(&expr)
    }

    #[napi]
    pub fn compute_medal_palette_json(medal_id: String) -> String {
        bridge::compute_medal_palette_json(&medal_id)
    }

    #[napi]
    pub fn compute_subscribe_progress_json(total: i32, lack: i32) -> String {
        bridge::compute_subscribe_progress_json(total, lack)
    }

    #[napi]
    pub fn plan_playback_sync_step_json(state_json: String, input_json: String) -> Result<String> {
        bridge::plan_playback_sync_step_json(&state_json, &input_json)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn normalize_pending_playback_stops_json(
        entries_json: String,
        now_epoch_ms: i64,
    ) -> Result<String> {
        bridge::normalize_pending_playback_stops_json(&entries_json, now_epoch_ms)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn plan_playback_routes_json(
        routes_json: String,
        prefs_json: String,
        probes_json: String,
    ) -> Result<String> {
        bridge::plan_playback_routes_json(&routes_json, &prefs_json, &probes_json)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn is_same_http_origin(url_a: String, url_b: String) -> bool {
        bridge::is_same_http_origin(&url_a, &url_b)
    }

    #[napi]
    pub fn resolve_playback_engine_json(input_json: String) -> Result<String> {
        bridge::resolve_playback_engine_json(&input_json).map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn build_external_player_url(
        template: String,
        media_url: String,
        title: String,
    ) -> Result<String> {
        bridge::build_external_player_url(&template, &media_url, &title)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn validate_plugin_bridge_api_path(raw_path: String) -> Result<String> {
        bridge::validate_plugin_bridge_api_path(&raw_path).map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn validate_plugin_shell_asset(virtual_path: String) -> Result<String> {
        bridge::validate_plugin_shell_asset(&virtual_path).map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn build_plugin_remote_cache_key_json(
        instance_origin: String,
        plugin_id: String,
        version_or_hash: String,
    ) -> Result<String> {
        bridge::build_plugin_remote_cache_key_json(&instance_origin, &plugin_id, &version_or_hash)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn normalize_plugin_remote_entry_json(
        plugin_id: String,
        version_or_hash: String,
        raw_remote_url: String,
    ) -> Result<String> {
        bridge::normalize_plugin_remote_entry_json(&plugin_id, &version_or_hash, &raw_remote_url)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn resolve_plugin_remote_upstream_json(virtual_path: String) -> Result<String> {
        bridge::resolve_plugin_remote_upstream_json(&virtual_path)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn prepare_danmaku_timeline_json(
        raw_payload_json: String,
        filter_options_json: String,
    ) -> Result<String> {
        bridge::prepare_danmaku_timeline_json(&raw_payload_json, &filter_options_json)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn normalize_danmaku_query_title(
        series_name: String,
        title: String,
        season: i32,
        episode: i32,
        file_name: String,
    ) -> String {
        bridge::normalize_danmaku_query_title(&series_name, &title, season, episode, &file_name)
    }

    #[napi]
    pub fn detect_cloudflare_access_challenge_json(
        status: u16,
        headers_json: String,
        body: String,
        request_url: String,
    ) -> String {
        bridge::detect_cloudflare_access_challenge_json(status, &headers_json, &body, &request_url)
    }

    #[napi]
    pub fn generate_pkce_pair_json(extra_entropy: String) -> String {
        bridge::generate_pkce_pair_json(&extra_entropy)
    }

    #[napi]
    pub fn compute_pkce_s256_challenge(code_verifier: String) -> String {
        bridge::compute_pkce_s256_challenge(&code_verifier)
    }

    #[napi]
    pub fn build_oauth_discovery_urls_json(
        server_url: String,
        resource_metadata_url: String,
    ) -> String {
        bridge::build_oauth_discovery_urls_json(&server_url, &resource_metadata_url)
    }

    #[napi]
    pub fn parse_protected_resource_metadata_json(json_str: String) -> Result<String> {
        bridge::parse_protected_resource_metadata_json(&json_str)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn parse_protected_resource_metadata_detail_json(json_str: String) -> Result<String> {
        bridge::parse_protected_resource_metadata_detail_json(&json_str)
            .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn normalize_oauth_resource_url(raw_url: String) -> String {
        bridge::normalize_oauth_resource_url(&raw_url)
    }

    #[napi]
    pub fn parse_oauth_server_metadata_json(json_str: String) -> Result<String> {
        bridge::parse_oauth_server_metadata_json(&json_str).map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn build_oauth_authorize_url(
        authorization_endpoint: String,
        client_id: String,
        redirect_uri: String,
        code_challenge: String,
        state: String,
        scope: String,
        resource: String,
    ) -> Result<String> {
        bridge::build_oauth_authorize_url(
            &authorization_endpoint,
            &client_id,
            &redirect_uri,
            &code_challenge,
            &state,
            &scope,
            &resource,
        )
        .map_err(napi_ohos::Error::from_reason)
    }

    #[napi]
    pub fn parse_oauth_callback_url_json(callback_url: String, expected_state: String) -> String {
        bridge::parse_oauth_callback_url_json(&callback_url, &expected_state)
    }

    #[napi]
    pub fn merge_cf_access_cookie(existing_cookie_header: String, cf_token: String) -> String {
        bridge::merge_cf_access_cookie(&existing_cookie_header, &cf_token)
    }

    #[napi]
    pub fn parse_audio_embedded_metadata_json(head_base64: String, tail_base64: String) -> String {
        bridge::parse_audio_embedded_metadata_json(&head_base64, &tail_base64)
    }
}

#[cfg(test)]
mod tests {
    use super::bridge;

    #[test]
    fn ohos_bridge_smoke_test() {
        assert_eq!(bridge::core_version(), env!("CARGO_PKG_VERSION"));
        let parsed = bridge::parse_deep_link_json("moviepilot://media/tmdb/550?type=movie");
        assert!(parsed.contains("\"media_id\":\"550\""));
        let palette = bridge::compute_medal_palette_json("gold_contributor");
        assert!(palette.contains("#D4AF37"));
    }
}
