//! HarmonyOS NEXT（ArkTS）ohos-rs / Node-API 导出层。
//! 与 `mp-ffi-uniffi` 保持 1:1 能力契约对齐，供 `harmony/commons/core_rust_bridge` 直接调用。

use mp_core_api::{ApiEndpoint, ResourceFilterCriteria, ResourceFilterEngine, ResourceItem};
use mp_core_model::{
    AgentMarkdownParser, AppDeepLink, CommunityMedalsModel, EngineResolutionInput,
    PendingPlaybackStop, PlayableMediaFormat, PlaybackEngineRouter, PlaybackProgressPlanner,
    PlaybackRouteCandidate, PlaybackRoutePlanner, PlaybackRoutePreference, PlaybackSyncInput,
    PlaybackSyncState, RouteProbeOutcome, ServerAddress, SubscribeProgressModel,
};
use mp_core_plugin::{NativeCron, NativeFormExpression, PluginFormDraft, PluginUiDecoder};
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
