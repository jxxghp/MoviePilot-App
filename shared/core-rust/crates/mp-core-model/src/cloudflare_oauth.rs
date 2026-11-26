//! Cloudflare Access Managed OAuth（RFC 9728 / RFC 8414 / RFC 7591 / RFC 7636 PKCE）跨端共享协议内核。
//!
//! 职责边界：
//! - 统一识别 Cloudflare Access 拦截响应（401 `WWW-Authenticate` / 302 跳转 `*.cloudflareaccess.com/cdn-cgi/access/login` / 登录页 HTML）；
//! - 解析 RFC 9728 Protected Resource Metadata 与 RFC 8414 Authorization Server Metadata；
//! - 生成 RFC 7636 PKCE `S256` 校验对与防 CSRF `state`，构造标准 OAuth 2.0 授权地址并校验 `moviepilot://oauth/callback`；
//! - 安全合并 `CF_Authorization` 与现有同源资源 Cookie（如 `resource_token`），绝不覆盖 MoviePilot 自身的 `Authorization: Bearer`。

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use url::Url;

/// 默认 OAuth 回调地址（三端统一注册 `moviepilot://` Scheme）。
pub const DEFAULT_CF_OAUTH_REDIRECT_URI: &str = "moviepilot://oauth/callback";

/// Cloudflare Access 拦截探测结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudflareChallengeResult {
    pub is_challenge: bool,
    pub reason: String,
    pub resource_metadata_url: Option<String>,
    pub login_url: Option<String>,
}

/// RFC 7636 PKCE 校验对与防 CSRF `state`。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PkcePair {
    pub code_verifier: String,
    pub code_challenge: String,
    pub code_challenge_method: String,
    pub state: String,
}

/// RFC 9728 受保护资源元数据（含 RFC 8707 规范化 `resource` 标识与关联 `authorization_servers` 元数据地址列表）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProtectedResourceMetadata {
    pub resource: Option<String>,
    pub authorization_servers: Vec<String>,
}

/// RFC 8414 OAuth 授权服务器元数据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OAuthServerMetadata {
    pub issuer: String,
    pub authorization_endpoint: String,
    pub token_endpoint: String,
    pub registration_endpoint: Option<String>,
}

/// OAuth 回调解析与 `state` 校验结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OAuthCallbackResult {
    pub valid: bool,
    pub state_matched: bool,
    pub code: Option<String>,
    pub error: Option<String>,
    pub error_description: Option<String>,
}

static ENTROPY_COUNTER: AtomicU64 = AtomicU64::new(1);

/// 检测一次 HTTP 响应是否被 Cloudflare Access（Managed OAuth 或 Access Login 网关）拦截。
pub fn detect_cloudflare_access_challenge(
    status: u16,
    headers_json: &str,
    body: &str,
    request_url: &str,
) -> CloudflareChallengeResult {
    let headers_map: HashMap<String, String> =
        serde_json::from_str(headers_json).unwrap_or_default();
    let mut lower_headers: HashMap<String, String> = HashMap::with_capacity(headers_map.len());
    for (k, v) in headers_map {
        lower_headers.insert(k.trim().to_ascii_lowercase(), v);
    }

    // 1. 3xx 重定向至 Cloudflare Access 登录门户
    if (300..400).contains(&status)
        && let Some(location) = lower_headers.get("location")
    {
        let loc_lower = location.to_ascii_lowercase();
        if loc_lower.contains("cloudflareaccess.com") || loc_lower.contains("/cdn-cgi/access/login")
        {
            let resolved = resolve_relative_url(request_url, location);
            return CloudflareChallengeResult {
                is_challenge: true,
                reason: "redirect_to_cloudflare_access".to_string(),
                resource_metadata_url: None,
                login_url: Some(resolved),
            };
        }
    }

    // 2. 401/403 带 WWW-Authenticate resource_metadata（Cloudflare Access Managed OAuth / RFC 9728）
    if (status == 401 || status == 403)
        && let Some(www_auth) = lower_headers.get("www-authenticate")
    {
        if let Some(meta_url) = extract_www_authenticate_param(www_auth, "resource_metadata") {
            return CloudflareChallengeResult {
                is_challenge: true,
                reason: "www_authenticate_resource_metadata".to_string(),
                resource_metadata_url: Some(resolve_relative_url(request_url, &meta_url)),
                login_url: None,
            };
        }
        let auth_lower = www_auth.to_ascii_lowercase();
        let has_cf_header = lower_headers.contains_key("cf-ray")
            || lower_headers
                .get("server")
                .is_some_and(|s| s.to_ascii_lowercase().contains("cloudflare"));
        if has_cf_header
            && (auth_lower.contains("cloudflareaccess")
                || auth_lower.contains("cf-access")
                || auth_lower.contains("oauth"))
        {
            return CloudflareChallengeResult {
                is_challenge: true,
                reason: "www_authenticate_cloudflare".to_string(),
                resource_metadata_url: None,
                login_url: None,
            };
        }
    }

    // 3. HTML 拦截页包含 Cloudflare Access 登录标记（常见于网关返回 200/401/403 HTML 而非 JSON）
    let body_prefix = &body[..body.len().min(8192)];
    let body_lower = body_prefix.to_ascii_lowercase();
    let looks_html = lower_headers
        .get("content-type")
        .is_some_and(|ct| ct.to_ascii_lowercase().contains("text/html"))
        || body_lower.contains("<!doctype html")
        || body_lower.contains("<html");
    if looks_html
        && (body_lower.contains("cloudflareaccess.com")
            || body_lower.contains("/cdn-cgi/access/login")
            || (body_lower.contains("cloudflare access") && body_lower.contains("sign in")))
    {
        return CloudflareChallengeResult {
            is_challenge: true,
            reason: "html_cloudflare_access_gate".to_string(),
            resource_metadata_url: None,
            login_url: None,
        };
    }

    CloudflareChallengeResult {
        is_challenge: false,
        reason: String::new(),
        resource_metadata_url: None,
        login_url: None,
    }
}

/// 生成 RFC 7636 PKCE `S256` 校验对；允许调用方注入额外硬件熵（十六进制或任意字符串）。
pub fn generate_pkce_pair(extra_entropy: &str) -> PkcePair {
    let seq = ENTROPY_COUNTER.fetch_add(1, Ordering::Relaxed);
    let now_ns = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id();
    let seed_a = format!("mp-pkce-v1:{now_ns}:{pid}:{seq}:a:{extra_entropy}");
    let seed_b = format!("mp-pkce-v1:{now_ns}:{pid}:{seq}:b:{extra_entropy}");
    let seed_s = format!("mp-state-v1:{now_ns}:{pid}:{seq}:s:{extra_entropy}");

    let digest_a = sha256_bytes(seed_a.as_bytes());
    let digest_b = sha256_bytes(seed_b.as_bytes());
    let mut verifier_raw = [0u8; 48];
    verifier_raw[..32].copy_from_slice(&digest_a);
    verifier_raw[32..48].copy_from_slice(&digest_b[..16]);

    let code_verifier = URL_SAFE_NO_PAD.encode(verifier_raw);
    let code_challenge = compute_pkce_s256_challenge(&code_verifier);
    let state_digest = sha256_bytes(seed_s.as_bytes());
    let state = URL_SAFE_NO_PAD.encode(&state_digest[..24]);

    PkcePair {
        code_verifier,
        code_challenge,
        code_challenge_method: "S256".to_string(),
        state,
    }
}

/// 根据 RFC 7636 `S256` 计算 `BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))`。
pub fn compute_pkce_s256_challenge(code_verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(sha256_bytes(code_verifier.as_bytes()))
}

/// 构造 Cloudflare Access Managed OAuth 元数据探测候选 URL 列表（按 RFC 9728 -> RFC 8414 优先级）。
pub fn build_oauth_discovery_urls(
    server_url: &str,
    resource_metadata_url: Option<&str>,
) -> Vec<String> {
    let mut urls = Vec::new();
    if let Some(meta) = resource_metadata_url
        .map(str::trim)
        .filter(|s| !s.is_empty())
        && is_valid_http_url(meta)
    {
        urls.push(meta.to_string());
    }
    if let Ok(parsed) = Url::parse(server_url.trim())
        && let Some(host) = parsed.host_str()
    {
        let mut origin = format!("{}://{host}", parsed.scheme());
        if let Some(port) = parsed.port() {
            origin.push_str(&format!(":{port}"));
        }
        let prm = format!("{origin}/.well-known/oauth-protected-resource");
        if !urls.contains(&prm) {
            urls.push(prm);
        }
        let as_meta = format!("{origin}/.well-known/oauth-authorization-server");
        if !urls.contains(&as_meta) {
            urls.push(as_meta);
        }
    }
    urls
}

/// 解析 RFC 9728 Protected Resource Metadata，完整返回规范化 `resource` 标识与关联的 `authorization_servers` 元数据地址列表。
pub fn parse_protected_resource_metadata_detail(
    json_str: &str,
) -> Result<ProtectedResourceMetadata, String> {
    let value: serde_json::Value = serde_json::from_str(json_str)
        .map_err(|e| format!("Invalid resource metadata JSON: {e}"))?;
    let resource = value
        .get("resource")
        .and_then(|v| v.as_str())
        .and_then(sanitize_resource_indicator);
    let servers = value
        .get("authorization_servers")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "Missing authorization_servers array".to_string())?;
    let mut out = Vec::new();
    for entry in servers {
        if let Some(raw) = entry.as_str().map(str::trim).filter(|s| !s.is_empty())
            && is_valid_http_url(raw)
        {
            let trimmed = raw.trim_end_matches('/');
            if trimmed.contains("/.well-known/") {
                out.push(trimmed.to_string());
            } else {
                out.push(format!("{trimmed}/.well-known/oauth-authorization-server"));
            }
        }
    }
    if out.is_empty() {
        return Err("No valid authorization server URL found".to_string());
    }
    Ok(ProtectedResourceMetadata {
        resource,
        authorization_servers: out,
    })
}

/// 解析 RFC 9728 Protected Resource Metadata，返回关联的 `authorization_servers` 元数据地址列表。
pub fn parse_protected_resource_metadata(json_str: &str) -> Result<Vec<String>, String> {
    parse_protected_resource_metadata_detail(json_str).map(|d| d.authorization_servers)
}

/// 将 MoviePilot 实例地址规范化为 RFC 8707 `resource` 默认回退值（去除查询串、片段、默认端口与末尾 `/`）。
pub fn normalize_oauth_resource_url(raw_url: &str) -> Option<String> {
    let parsed = Url::parse(raw_url.trim()).ok()?;
    if !matches!(parsed.scheme(), "https" | "http") {
        return None;
    }
    let host = parsed.host_str()?;
    let mut out = format!("{}://{}", parsed.scheme(), host.to_ascii_lowercase());
    if let Some(port) = parsed.port() {
        out.push_str(&format!(":{port}"));
    }
    let clean_path = parsed.path().trim_end_matches('/');
    if !clean_path.is_empty() {
        out.push_str(clean_path);
    }
    Some(out)
}

/// 解析 RFC 8414 Authorization Server Metadata 并校验端点协议安全性。
pub fn parse_oauth_server_metadata(json_str: &str) -> Result<OAuthServerMetadata, String> {
    let value: serde_json::Value = serde_json::from_str(json_str)
        .map_err(|e| format!("Invalid OAuth server metadata JSON: {e}"))?;
    let authorization_endpoint = value
        .get("authorization_endpoint")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| is_valid_http_url(s))
        .ok_or_else(|| "Missing or invalid authorization_endpoint".to_string())?
        .to_string();
    let token_endpoint = value
        .get("token_endpoint")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| is_valid_http_url(s))
        .ok_or_else(|| "Missing or invalid token_endpoint".to_string())?
        .to_string();
    let registration_endpoint = value
        .get("registration_endpoint")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| is_valid_http_url(s))
        .map(ToString::to_string);
    let issuer = value
        .get("issuer")
        .and_then(|v| v.as_str())
        .map(str::trim)
        .unwrap_or("")
        .to_string();
    Ok(OAuthServerMetadata {
        issuer,
        authorization_endpoint,
        token_endpoint,
        registration_endpoint,
    })
}

/// 构造标准 OAuth 2.0 + PKCE (`S256`) + RFC 8707 `resource` 授权跳转 URL。
pub fn build_oauth_authorize_url(
    authorization_endpoint: &str,
    client_id: &str,
    redirect_uri: &str,
    code_challenge: &str,
    state: &str,
    scope: &str,
    resource: Option<&str>,
) -> Result<String, String> {
    let mut url = Url::parse(authorization_endpoint.trim())
        .map_err(|e| format!("Invalid authorization endpoint URL: {e}"))?;
    if !matches!(url.scheme(), "https" | "http") {
        return Err("Authorization endpoint must use HTTP(S)".to_string());
    }
    let clean_client = client_id.trim();
    if clean_client.is_empty() {
        return Err("client_id must not be empty".to_string());
    }
    let clean_resource = match resource.map(str::trim).filter(|s| !s.is_empty()) {
        Some(raw) => Some(
            sanitize_resource_indicator(raw)
                .ok_or_else(|| format!("Invalid OAuth resource indicator URI: {raw}"))?,
        ),
        None => None,
    };
    let clean_redirect = if redirect_uri.trim().is_empty() {
        DEFAULT_CF_OAUTH_REDIRECT_URI
    } else {
        redirect_uri.trim()
    };
    {
        let mut pairs = url.query_pairs_mut();
        pairs.append_pair("response_type", "code");
        pairs.append_pair("client_id", clean_client);
        pairs.append_pair("redirect_uri", clean_redirect);
        pairs.append_pair("code_challenge", code_challenge.trim());
        pairs.append_pair("code_challenge_method", "S256");
        pairs.append_pair("state", state.trim());
        if !scope.trim().is_empty() {
            pairs.append_pair("scope", scope.trim());
        }
        if let Some(res) = clean_resource.as_deref() {
            pairs.append_pair("resource", res);
        }
    }
    Ok(url.to_string())
}

/// 解析并校验 `moviepilot://oauth/callback?code=...&state=...` 回调 URL。
pub fn parse_oauth_callback_url(callback_url: &str, expected_state: &str) -> OAuthCallbackResult {
    let parsed = match Url::parse(callback_url.trim()) {
        Ok(u) => u,
        Err(_) => {
            return OAuthCallbackResult {
                valid: false,
                state_matched: false,
                code: None,
                error: Some("invalid_callback_url".to_string()),
                error_description: None,
            };
        }
    };
    let mut code: Option<String> = None;
    let mut state: Option<String> = None;
    let mut error: Option<String> = None;
    let mut error_description: Option<String> = None;
    for (k, v) in parsed.query_pairs() {
        match k.as_ref() {
            "code" if !v.trim().is_empty() => code = Some(v.into_owned()),
            "state" if !v.trim().is_empty() => state = Some(v.into_owned()),
            "error" if !v.trim().is_empty() => error = Some(v.into_owned()),
            "error_description" if !v.trim().is_empty() => error_description = Some(v.into_owned()),
            _ => {}
        }
    }
    let state_matched = !expected_state.trim().is_empty()
        && state.as_deref().is_some_and(|s| s == expected_state.trim());
    let valid = state_matched && error.is_none() && code.is_some();
    OAuthCallbackResult {
        valid,
        state_matched,
        code: if state_matched { code } else { None },
        error,
        error_description,
    }
}

/// 将 `CF_Authorization=<token>` 安全合并到现有 `Cookie` 请求头中，保留 `resource_token` 等其它同源 Cookie。
pub fn merge_cf_access_cookie(existing_cookie_header: &str, cf_token: &str) -> String {
    let clean_token = cf_token.trim();
    let mut parts: Vec<String> = existing_cookie_header
        .split(';')
        .map(str::trim)
        .filter(|segment| !segment.is_empty())
        .filter(|segment| {
            let name = segment.split('=').next().unwrap_or("").trim();
            !name.eq_ignore_ascii_case("CF_Authorization")
        })
        .map(ToString::to_string)
        .collect();
    if !clean_token.is_empty() {
        parts.push(format!("CF_Authorization={clean_token}"));
    }
    parts.join("; ")
}

fn is_valid_http_url(raw: &str) -> bool {
    Url::parse(raw.trim())
        .map(|u| matches!(u.scheme(), "https" | "http") && u.host_str().is_some())
        .unwrap_or(false)
}

/// 校验并清理 RFC 8707 `resource` 标识：要求有效绝对 HTTP(S) URI 且不含 `#fragment`，保留服务端原始末尾斜杠形态以确保精确匹配。
fn sanitize_resource_indicator(raw: &str) -> Option<String> {
    let without_fragment = raw.trim().split('#').next()?.trim();
    if without_fragment.is_empty() || !is_valid_http_url(without_fragment) {
        return None;
    }
    Some(without_fragment.to_string())
}

fn resolve_relative_url(base_url: &str, candidate: &str) -> String {
    let trimmed = candidate.trim();
    if is_valid_http_url(trimmed) {
        return trimmed.to_string();
    }
    if let Ok(base) = Url::parse(base_url.trim())
        && let Ok(joined) = base.join(trimmed)
    {
        return joined.to_string();
    }
    trimmed.to_string()
}

fn extract_www_authenticate_param(header: &str, key: &str) -> Option<String> {
    let lower = header.to_ascii_lowercase();
    let needle = format!("{}=", key.to_ascii_lowercase());
    let idx = lower.find(&needle)?;
    let rest = header[idx + needle.len()..].trim_start();
    if let Some(after_quote) = rest.strip_prefix('"') {
        let end = after_quote.find('"')?;
        let val = after_quote[..end].trim();
        return (!val.is_empty()).then(|| val.to_string());
    }
    let end = rest
        .find(|c: char| c == ',' || c.is_whitespace())
        .unwrap_or(rest.len());
    let val = rest[..end].trim();
    (!val.is_empty()).then(|| val.to_string())
}

/// 纯 Rust FIPS 180-4 SHA-256 实现，零额外加密依赖。
fn sha256_bytes(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut padded = Vec::with_capacity(data.len() + 72);
    padded.extend_from_slice(data);
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.as_chunks::<64>().0 {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (idx, word) in h.iter().enumerate() {
        out[idx * 4..idx * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc7636_pkce_s256_matches_official_vector() {
        // RFC 7636 Appendix B test vector
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        let challenge = compute_pkce_s256_challenge(verifier);
        assert_eq!(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
    }

    #[test]
    fn detects_cf_access_redirect_and_www_authenticate_challenges() {
        let r302 = detect_cloudflare_access_challenge(
            302,
            r#"{"Location":"https://demo.cloudflareaccess.com/cdn-cgi/access/login/mp.example.com"}"#,
            "",
            "https://mp.example.com/api/v1/system/env",
        );
        assert!(r302.is_challenge);
        assert_eq!(r302.reason, "redirect_to_cloudflare_access");

        let r401 = detect_cloudflare_access_challenge(
            401,
            r#"{"WWW-Authenticate":"Bearer resource_metadata=\"https://mp.example.com/.well-known/oauth-protected-resource\""}"#,
            "",
            "https://mp.example.com/api/v1/user/current",
        );
        assert!(r401.is_challenge);
        assert_eq!(
            r401.resource_metadata_url.as_deref(),
            Some("https://mp.example.com/.well-known/oauth-protected-resource")
        );

        let normal_401 = detect_cloudflare_access_challenge(
            401,
            r#"{"Content-Type":"application/json"}"#,
            r#"{"detail":"Not authenticated"}"#,
            "https://mp.example.com/api/v1/user/current",
        );
        assert!(!normal_401.is_challenge);
    }

    #[test]
    fn parses_metadata_builds_authorize_url_and_validates_callback() {
        let prm_detail = parse_protected_resource_metadata_detail(
            r#"{
              "resource": "https://moviepilot.example.com",
              "authorization_servers": ["https://team.cloudflareaccess.com/cdn-cgi/access/sso/oauth"]
            }"#,
        )
        .unwrap();
        assert_eq!(
            prm_detail.resource.as_deref(),
            Some("https://moviepilot.example.com")
        );
        assert_eq!(
            prm_detail.authorization_servers,
            vec![
                "https://team.cloudflareaccess.com/cdn-cgi/access/sso/oauth/.well-known/oauth-authorization-server"
            ]
        );
        assert_eq!(
            normalize_oauth_resource_url("https://moviepilot.example.com:443/"),
            Some("https://moviepilot.example.com".to_string())
        );
        assert_eq!(
            normalize_oauth_resource_url("https://moviepilot.example.com:8443/mp/"),
            Some("https://moviepilot.example.com:8443/mp".to_string())
        );

        let meta = parse_oauth_server_metadata(
            r#"{
              "issuer":"https://team.cloudflareaccess.com",
              "authorization_endpoint":"https://team.cloudflareaccess.com/authorize",
              "token_endpoint":"https://team.cloudflareaccess.com/token",
              "registration_endpoint":"https://team.cloudflareaccess.com/register"
            }"#,
        )
        .unwrap();
        let pkce = generate_pkce_pair("test-seed");
        let auth_url = build_oauth_authorize_url(
            &meta.authorization_endpoint,
            "client-123",
            DEFAULT_CF_OAUTH_REDIRECT_URI,
            &pkce.code_challenge,
            &pkce.state,
            "openid email profile offline_access",
            prm_detail.resource.as_deref(),
        )
        .unwrap();
        assert!(auth_url.contains("code_challenge_method=S256"));
        assert!(auth_url.contains("client_id=client-123"));
        assert!(auth_url.contains("resource=https%3A%2F%2Fmoviepilot.example.com"));

        let cb_ok = parse_oauth_callback_url(
            &format!(
                "moviepilot://oauth/callback?code=auth_code_99&state={}",
                pkce.state
            ),
            &pkce.state,
        );
        assert!(cb_ok.valid && cb_ok.state_matched);
        assert_eq!(cb_ok.code.as_deref(), Some("auth_code_99"));

        let cb_bad = parse_oauth_callback_url(
            "moviepilot://oauth/callback?code=auth_code_99&state=wrong",
            &pkce.state,
        );
        assert!(!cb_bad.valid && !cb_bad.state_matched);
        assert!(cb_bad.code.is_none());
    }

    #[test]
    fn merges_cf_authorization_cookie_preserving_resource_token() {
        assert_eq!(
            merge_cf_access_cookie("resource_token=abc; theme=dark", "cf-jwt-1"),
            "resource_token=abc; theme=dark; CF_Authorization=cf-jwt-1"
        );
        assert_eq!(
            merge_cf_access_cookie("CF_Authorization=old; resource_token=abc", "new-jwt"),
            "resource_token=abc; CF_Authorization=new-jwt"
        );
        assert_eq!(
            merge_cf_access_cookie("CF_Authorization=old; resource_token=abc", ""),
            "resource_token=abc"
        );
    }
}
