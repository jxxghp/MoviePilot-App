//! MoviePilot 原生客户端通行密钥（`moviepilot.passkey` v1）跨端安全协议校验与构造器。
//!
//! 严格对齐前端 `native-passkey.html` / `native-passkey.json` 与后端 `/api/v1/mfa/passkey/authenticate/{start,finish}`：
//! - 事务令牌 `transaction_token` 仅保留在客户端内存中，绝不写入浏览器认证会话 URL；
//! - 严格验证 WebAuthn 挑战参数边界、`rpId` 域名归属、`clientDataJSON`（`type` / `challenge` / `origin` / `crossOrigin`）
//!   以及规范无填充 Base64URL 编码，拒绝一切额外字段或跨域回流。

use crate::server_address::ServerAddress;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use thiserror::Error;
use url::Url;

const ALLOWED_OPTION_KEYS: &[&str] = &[
    "challenge",
    "rpId",
    "timeout",
    "allowCredentials",
    "userVerification",
];
const ALLOWED_USER_VERIFICATION: &[&str] = &["required", "preferred", "discouraged"];
const ALLOWED_TRANSPORTS: &[&str] = &["ble", "hybrid", "internal", "nfc", "usb", "smart-card"];

/// 通行密钥认证固定错误码（不向界面泄露浏览器异常堆栈或认证原文）。
#[derive(Debug, Error, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PasskeyErrorCode {
    #[error("已取消通行密钥验证")]
    Canceled,
    #[error("通行密钥验证已过期，请重新尝试。")]
    Expired,
    #[error("当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。")]
    Unsupported,
    #[error("请更新实例的前端资源后，再使用 App 通行密钥登录。")]
    FrontendOutdated,
    #[error("通行密钥验证结果无效，请重新尝试。")]
    Invalid,
    #[error("未能完成通行密钥验证，请重新尝试。")]
    Failed,
}

impl PasskeyErrorCode {
    /// 返回稳定协议错误标识。
    pub fn as_code(self) -> &'static str {
        match self {
            Self::Canceled => "canceled",
            Self::Expired => "expired",
            Self::Unsupported => "unsupported",
            Self::FrontendOutdated => "frontend_outdated",
            Self::Invalid => "invalid",
            Self::Failed => "failed",
        }
    }

    /// 返回面向用户的中文提示（用户主动取消时返回 `None`，保持静默停留登录页）。
    pub fn message_zh(self) -> Option<&'static str> {
        match self {
            Self::Canceled => None,
            Self::Expired => Some("通行密钥验证已过期，请重新尝试。"),
            Self::Unsupported => {
                Some("当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。")
            }
            Self::FrontendOutdated => Some("请更新实例的前端资源后，再使用 App 通行密钥登录。"),
            Self::Invalid => Some("通行密钥验证结果无效，请重新尝试。"),
            Self::Failed => Some("未能完成通行密钥验证，请重新尝试。"),
        }
    }

    fn from_callback_error(raw: &str) -> Option<Self> {
        match raw {
            "canceled" => Some(Self::Canceled),
            "expired" => Some(Self::Expired),
            "unsupported" => Some(Self::Unsupported),
            "invalid" => Some(Self::Invalid),
            "failed" => Some(Self::Failed),
            _ => None,
        }
    }
}

/// 通行密钥 `authenticate/start` 解析与系统浏览器会话启动参数。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PreparedPasskeyRequest {
    /// 指向 `<server>/native-passkey.html#request=...` 的公开挑战跳转地址（绝不含 `transaction_token`）。
    pub authorization_url: String,
    /// 本次一次性 32 字节随机状态值（规范 Base64URL 无填充）。
    pub state: String,
    /// 服务端签发的 WebAuthn `challenge`（规范 Base64URL 无填充）。
    pub challenge: String,
    /// 仅保存在客户端内存中的短期事务令牌，回调校验通过后随 `finish` 提交。
    pub transaction_token: String,
    /// 本次挑战有效秒数上限（最高 120 秒）。
    pub timeout_secs: u64,
}

/// 通行密钥 `moviepilot://passkey/callback#result=...` 校验结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PasskeyCallbackOutcome {
    pub ok: bool,
    pub finish_body_json: Option<String>,
    pub error_code: Option<String>,
    pub error_message_zh: Option<String>,
}

impl PasskeyCallbackOutcome {
    fn success(finish_body_json: String) -> Self {
        Self {
            ok: true,
            finish_body_json: Some(finish_body_json),
            error_code: None,
            error_message_zh: None,
        }
    }

    fn failure(err: PasskeyErrorCode) -> Self {
        Self {
            ok: false,
            finish_body_json: None,
            error_code: Some(err.as_code().to_string()),
            error_message_zh: err.message_zh().map(str::to_string),
        }
    }
}

/// 解码 64 位十六进制随机种子为 32 字节 `state` 原始字节。
pub fn decode_state_hex_32(state_hex: &str) -> Result<[u8; 32], PasskeyErrorCode> {
    let trimmed = state_hex.trim();
    if trimmed.len() != 64 || !trimmed.is_ascii() {
        return Err(PasskeyErrorCode::Invalid);
    }
    let mut out = [0u8; 32];
    for (i, chunk) in trimmed.as_bytes().chunks_exact(2).enumerate() {
        let hi = (chunk[0] as char)
            .to_digit(16)
            .ok_or(PasskeyErrorCode::Invalid)?;
        let lo = (chunk[1] as char)
            .to_digit(16)
            .ok_or(PasskeyErrorCode::Invalid)?;
        out[i] = ((hi << 4) | lo) as u8;
    }
    Ok(out)
}

/// WebAuthn 需要安全上下文：`https://` 或浏览器认可的本机回环地址（`localhost` / `127.0.0.1` / `::1`）。
pub fn is_passkey_secure_origin(server_url: &str) -> bool {
    let Ok(addr) = ServerAddress::parse(server_url) else {
        return false;
    };
    let Ok(parsed) = Url::parse(addr.as_str()) else {
        return false;
    };
    if parsed.scheme() == "https" {
        return true;
    }
    let Some(raw_host) = parsed.host_str() else {
        return false;
    };
    let bare = raw_host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();
    matches!(bare.as_str(), "localhost" | "127.0.0.1" | "::1")
}

/// 解析 `GET /api/v1/auth/providers` 响应（兼容统一包装 `{"success":true,"data":[...]}` 与裸数组），
/// 仅当存在明确启用的系统级 `passkey` 提供方时返回 `Ok(true)`。
pub fn parse_passkey_provider_enabled(body: &str) -> Result<bool, PasskeyErrorCode> {
    if body.len() > 65_536 {
        return Err(PasskeyErrorCode::Invalid);
    }
    let root: Value = serde_json::from_str(body).map_err(|_| PasskeyErrorCode::Invalid)?;
    let providers = match &root {
        Value::Array(arr) => arr,
        Value::Object(map) => {
            if map.get("success") != Some(&Value::Bool(true)) {
                return Err(PasskeyErrorCode::Invalid);
            }
            match map.get("data") {
                Some(Value::Array(arr)) => arr,
                _ => return Err(PasskeyErrorCode::Invalid),
            }
        }
        _ => return Err(PasskeyErrorCode::Invalid),
    };
    if providers.len() > 128 {
        return Err(PasskeyErrorCode::Invalid);
    }
    Ok(providers.iter().any(|item| {
        let Some(obj) = item.as_object() else {
            return false;
        };
        obj.get("type").and_then(Value::as_str) == Some("system")
            && obj.get("method").and_then(Value::as_str) == Some("passkey")
            && obj.get("enabled") == Some(&Value::Bool(true))
    }))
}

/// 校验 `GET <server>/native-passkey.json` 静态协议标记是否精确声明 `moviepilot.passkey` v1。
pub fn supports_passkey_frontend_marker(body: &str) -> bool {
    let Ok(map) = parse_bounded_object(body.as_bytes(), 1024) else {
        return false;
    };
    if map.len() != 2 {
        return false;
    }
    let proto_ok = map.get("protocol").and_then(Value::as_str) == Some("moviepilot.passkey");
    let ver_ok = map
        .get("version")
        .and_then(Value::as_f64)
        .is_some_and(|v| (v - 1.0).abs() < f64::EPSILON);
    proto_ok && ver_ok
}

/// 校验 `POST /api/v1/mfa/passkey/authenticate/start` 响应并构造公开认证页 URL 与内存态事务记录。
pub fn prepare_passkey_request(
    start_body: &str,
    server_url: &str,
    state_bytes: &[u8],
) -> Result<PreparedPasskeyRequest, PasskeyErrorCode> {
    let addr = ServerAddress::parse(server_url).map_err(|_| PasskeyErrorCode::Unsupported)?;
    if !is_passkey_secure_origin(addr.as_str()) || state_bytes.len() != 32 {
        return Err(PasskeyErrorCode::Unsupported);
    }
    let root = parse_bounded_object(start_body.as_bytes(), 131_072)?;
    if root.get("success") != Some(&Value::Bool(true)) {
        return Err(PasskeyErrorCode::Failed);
    }
    let data = root
        .get("data")
        .and_then(Value::as_object)
        .ok_or(PasskeyErrorCode::Failed)?;
    let token = data
        .get("transaction_token")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Failed)?;
    if token.is_empty() || token.len() > 8192 || token.chars().any(char::is_control) {
        return Err(PasskeyErrorCode::Failed);
    }
    let options: Map<String, Value> = match data.get("options") {
        Some(Value::String(serialized)) => parse_bounded_object(serialized.as_bytes(), 24_576)?,
        Some(Value::Object(obj)) => obj.clone(),
        _ => return Err(PasskeyErrorCode::Invalid),
    };
    let timeout_secs = validate_start_options(&options, &addr)?;
    let challenge = options
        .get("challenge")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?
        .to_string();
    let state = encode_base64url(state_bytes);
    let request_payload = json!({
        "version": 1,
        "state": state,
        "options": Value::Object(options),
    });
    let payload_bytes =
        serde_json::to_vec(&request_payload).map_err(|_| PasskeyErrorCode::Invalid)?;
    let encoded_request = encode_base64url(&payload_bytes);
    if encoded_request.len() > 32_768 {
        return Err(PasskeyErrorCode::Invalid);
    }
    let authorization_url = format!(
        "{}/native-passkey.html#request={encoded_request}",
        addr.as_str()
    );
    if Url::parse(&authorization_url).is_err() {
        return Err(PasskeyErrorCode::Invalid);
    }
    Ok(PreparedPasskeyRequest {
        authorization_url,
        state,
        challenge,
        transaction_token: token.to_string(),
        timeout_secs,
    })
}

/// 校验系统认证窗口回流的 `moviepilot://passkey/callback#result=...`，通过后返回可直接提交给
/// `POST /api/v1/mfa/passkey/authenticate/finish` 的 JSON 请求体。
pub fn verify_passkey_callback(
    callback_url: &str,
    server_url: &str,
    expected_state: &str,
    expected_challenge: &str,
    transaction_token: &str,
) -> PasskeyCallbackOutcome {
    match verify_passkey_callback_inner(
        callback_url,
        server_url,
        expected_state,
        expected_challenge,
        transaction_token,
    ) {
        Ok(body) => PasskeyCallbackOutcome::success(body),
        Err(err) => PasskeyCallbackOutcome::failure(err),
    }
}

fn verify_passkey_callback_inner(
    callback_url: &str,
    server_url: &str,
    expected_state: &str,
    expected_challenge: &str,
    transaction_token: &str,
) -> Result<String, PasskeyErrorCode> {
    if transaction_token.is_empty()
        || transaction_token.len() > 8192
        || transaction_token.chars().any(char::is_control)
    {
        return Err(PasskeyErrorCode::Expired);
    }
    if expected_state.is_empty() || expected_challenge.is_empty() {
        return Err(PasskeyErrorCode::Invalid);
    }
    let addr = ServerAddress::parse(server_url).map_err(|_| PasskeyErrorCode::Expired)?;
    let trimmed = callback_url.trim();
    if trimmed.is_empty() || trimmed.chars().any(char::is_whitespace) {
        return Err(PasskeyErrorCode::Invalid);
    }
    let (before_hash, raw_fragment) = trimmed.split_once('#').ok_or(PasskeyErrorCode::Invalid)?;
    if before_hash != "moviepilot://passkey/callback" {
        let parsed = Url::parse(trimmed).map_err(|_| PasskeyErrorCode::Invalid)?;
        if parsed.scheme() != "moviepilot"
            || parsed.host_str() != Some("passkey")
            || parsed.path() != "/callback"
            || parsed.port().is_some()
            || !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.query().is_some()
        {
            return Err(PasskeyErrorCode::Invalid);
        }
    }
    if !raw_fragment.starts_with("result=")
        || raw_fragment.len() > 32_775
        || raw_fragment.contains('%')
    {
        return Err(PasskeyErrorCode::Invalid);
    }
    let encoded_result = &raw_fragment["result=".len()..];
    let decoded_bytes = decode_canonical_base64url(encoded_result, 1, 24_576)?;
    let result_obj = parse_bounded_object(&decoded_bytes, 24_576)?;

    let version_ok = result_obj
        .get("version")
        .and_then(Value::as_f64)
        .is_some_and(|v| (v - 1.0).abs() < f64::EPSILON);
    let state_ok = result_obj.get("state").and_then(Value::as_str) == Some(expected_state);
    if !version_ok || !state_ok {
        return Err(PasskeyErrorCode::Invalid);
    }

    if let Some(err_val) = result_obj.get("error") {
        let Some(err_code) = err_val.as_str() else {
            return Err(PasskeyErrorCode::Invalid);
        };
        if result_obj.len() != 3 {
            return Err(PasskeyErrorCode::Invalid);
        }
        let mapped =
            PasskeyErrorCode::from_callback_error(err_code).ok_or(PasskeyErrorCode::Invalid)?;
        return Err(mapped);
    }

    if result_obj.len() != 3 {
        return Err(PasskeyErrorCode::Invalid);
    }
    let credential = result_obj
        .get("credential")
        .and_then(Value::as_object)
        .ok_or(PasskeyErrorCode::Invalid)?;
    validate_credential(credential, &addr, expected_challenge)?;

    serde_json::to_string(&json!({
        "credential": Value::Object(credential.clone()),
        "transaction_token": transaction_token,
    }))
    .map_err(|_| PasskeyErrorCode::Invalid)
}

fn validate_start_options(
    options: &Map<String, Value>,
    addr: &ServerAddress,
) -> Result<u64, PasskeyErrorCode> {
    if !options
        .keys()
        .all(|k| ALLOWED_OPTION_KEYS.contains(&k.as_str()))
    {
        return Err(PasskeyErrorCode::Invalid);
    }
    let challenge = options
        .get("challenge")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?;
    let _ = decode_canonical_base64url(challenge, 16, 1024)?;

    let parsed_addr = Url::parse(addr.as_str()).map_err(|_| PasskeyErrorCode::Invalid)?;
    let raw_host = parsed_addr.host_str().ok_or(PasskeyErrorCode::Invalid)?;
    let bare_host = raw_host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_ascii_lowercase();

    if let Some(rp_val) = options.get("rpId") {
        let rp = rp_val.as_str().ok_or(PasskeyErrorCode::Invalid)?;
        if rp.is_empty() || rp.len() > 253 || rp != rp.to_lowercase() {
            return Err(PasskeyErrorCode::Invalid);
        }
        let rp_matches = rp == bare_host
            || (bare_host.contains(':') && rp == format!("[{bare_host}]"))
            || (rp.contains('.') && !rp.contains(':') && bare_host.ends_with(&format!(".{rp}")));
        if !rp_matches {
            return Err(PasskeyErrorCode::Invalid);
        }
    }

    let mut timeout_secs = 120.0_f64;
    if let Some(timeout_val) = options.get("timeout") {
        let ms = timeout_val.as_f64().ok_or(PasskeyErrorCode::Invalid)?;
        if !ms.is_finite() || ms < 1.0 {
            return Err(PasskeyErrorCode::Invalid);
        }
        timeout_secs = (ms / 1000.0).min(timeout_secs);
    }

    if let Some(uv_val) = options.get("userVerification") {
        let uv = uv_val.as_str().ok_or(PasskeyErrorCode::Invalid)?;
        if !ALLOWED_USER_VERIFICATION.contains(&uv) {
            return Err(PasskeyErrorCode::Invalid);
        }
    }

    if let Some(allow_val) = options.get("allowCredentials") {
        let creds = allow_val.as_array().ok_or(PasskeyErrorCode::Invalid)?;
        if creds.len() > 64 {
            return Err(PasskeyErrorCode::Invalid);
        }
        for item in creds {
            let cred_obj = item.as_object().ok_or(PasskeyErrorCode::Invalid)?;
            if !cred_obj
                .keys()
                .all(|k| matches!(k.as_str(), "id" | "type" | "transports"))
            {
                return Err(PasskeyErrorCode::Invalid);
            }
            if cred_obj.get("type").and_then(Value::as_str) != Some("public-key") {
                return Err(PasskeyErrorCode::Invalid);
            }
            let id = cred_obj
                .get("id")
                .and_then(Value::as_str)
                .ok_or(PasskeyErrorCode::Invalid)?;
            let _ = decode_canonical_base64url(id, 1, 1024)?;
            if let Some(transports_val) = cred_obj.get("transports") {
                let transports = transports_val.as_array().ok_or(PasskeyErrorCode::Invalid)?;
                if transports.len() > 8
                    || !transports.iter().all(|t| {
                        t.as_str()
                            .is_some_and(|name| ALLOWED_TRANSPORTS.contains(&name))
                    })
                {
                    return Err(PasskeyErrorCode::Invalid);
                }
            }
        }
    }

    Ok(timeout_secs.ceil().clamp(1.0, 120.0) as u64)
}

fn validate_credential(
    credential: &Map<String, Value>,
    addr: &ServerAddress,
    expected_challenge: &str,
) -> Result<(), PasskeyErrorCode> {
    if credential.len() != 4
        || !credential
            .keys()
            .all(|k| matches!(k.as_str(), "id" | "rawId" | "type" | "response"))
    {
        return Err(PasskeyErrorCode::Invalid);
    }
    if credential.get("type").and_then(Value::as_str) != Some("public-key") {
        return Err(PasskeyErrorCode::Invalid);
    }
    let id = credential
        .get("id")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?;
    if credential.get("rawId").and_then(Value::as_str) != Some(id) {
        return Err(PasskeyErrorCode::Invalid);
    }
    let _ = decode_canonical_base64url(id, 1, 1024)?;

    let response = credential
        .get("response")
        .and_then(Value::as_object)
        .ok_or(PasskeyErrorCode::Invalid)?;
    if response.len() != 4
        || !response.keys().all(|k| {
            matches!(
                k.as_str(),
                "authenticatorData" | "clientDataJSON" | "signature" | "userHandle"
            )
        })
    {
        return Err(PasskeyErrorCode::Invalid);
    }
    let auth_data = response
        .get("authenticatorData")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?;
    let client_data_b64 = response
        .get("clientDataJSON")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?;
    let signature = response
        .get("signature")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?;

    let _ = decode_canonical_base64url(auth_data, 37, 2048)?;
    let _ = decode_canonical_base64url(signature, 1, 2048)?;
    let client_bytes = decode_canonical_base64url(client_data_b64, 1, 4096)?;
    let client_data = parse_bounded_object(&client_bytes, 4096)?;

    if client_data.get("type").and_then(Value::as_str) != Some("webauthn.get") {
        return Err(PasskeyErrorCode::Invalid);
    }
    if client_data.get("challenge").and_then(Value::as_str) != Some(expected_challenge) {
        return Err(PasskeyErrorCode::Invalid);
    }
    match client_data.get("crossOrigin") {
        None | Some(Value::Bool(false)) => {}
        _ => return Err(PasskeyErrorCode::Invalid),
    }

    let origin_str = client_data
        .get("origin")
        .and_then(Value::as_str)
        .ok_or(PasskeyErrorCode::Invalid)?;
    if !is_exact_browser_origin(origin_str, addr) {
        return Err(PasskeyErrorCode::Invalid);
    }

    match response.get("userHandle") {
        Some(Value::Null) => {}
        Some(Value::String(handle)) => {
            let _ = decode_canonical_base64url(handle, 1, 256)?;
        }
        _ => return Err(PasskeyErrorCode::Invalid),
    }
    Ok(())
}

fn is_exact_browser_origin(origin_str: &str, addr: &ServerAddress) -> bool {
    if origin_str.is_empty()
        || origin_str.chars().any(char::is_whitespace)
        || origin_str.ends_with('/')
    {
        return false;
    }
    let Some((_scheme, after_scheme)) = origin_str.split_once("://") else {
        return false;
    };
    if after_scheme.is_empty()
        || after_scheme.contains('/')
        || after_scheme.contains('?')
        || after_scheme.contains('#')
        || after_scheme.contains('@')
    {
        return false;
    }
    let Ok(parsed_origin) = Url::parse(origin_str) else {
        return false;
    };
    parsed_origin.origin().ascii_serialization() == addr.origin()
}

fn parse_bounded_object(
    bytes: &[u8],
    maximum: usize,
) -> Result<Map<String, Value>, PasskeyErrorCode> {
    if bytes.len() > maximum {
        return Err(PasskeyErrorCode::Invalid);
    }
    match serde_json::from_slice::<Value>(bytes) {
        Ok(Value::Object(map)) => Ok(map),
        _ => Err(PasskeyErrorCode::Invalid),
    }
}

fn encode_base64url(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

fn decode_canonical_base64url(
    value: &str,
    minimum: usize,
    maximum: usize,
) -> Result<Vec<u8>, PasskeyErrorCode> {
    let max_chars = (maximum * 4).div_ceil(3);
    if value.is_empty()
        || value.len() > max_chars
        || !value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
    {
        return Err(PasskeyErrorCode::Invalid);
    }
    let decoded = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| PasskeyErrorCode::Invalid)?;
    if decoded.len() < minimum || decoded.len() > maximum {
        return Err(PasskeyErrorCode::Invalid);
    }
    if encode_base64url(&decoded) != value {
        return Err(PasskeyErrorCode::Invalid);
    }
    Ok(decoded)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_state() -> [u8; 32] {
        [42u8; 32]
    }

    fn test_challenge() -> String {
        encode_base64url(&[7u8; 32])
    }

    fn make_start_body(extra_opt: Option<(&str, Value)>, legacy_string: bool) -> String {
        let mut opts = Map::new();
        opts.insert("challenge".into(), Value::String(test_challenge()));
        opts.insert("rpId".into(), Value::String("example.com".into()));
        opts.insert("timeout".into(), json!(60_000));
        opts.insert("userVerification".into(), Value::String("preferred".into()));
        if let Some((k, v)) = extra_opt {
            opts.insert(k.into(), v);
        }
        let options_val = if legacy_string {
            Value::String(serde_json::to_string(&Value::Object(opts)).unwrap())
        } else {
            Value::Object(opts)
        };
        serde_json::to_string(&json!({
            "success": true,
            "data": {
                "transaction_token": "private-transaction-token",
                "options": options_val,
            }
        }))
        .unwrap()
    }

    fn make_callback(
        state: &str,
        error: Option<&str>,
        client_override: Option<(&str, Value)>,
        response_override: Option<(&str, Value)>,
    ) -> String {
        let mut client = Map::new();
        client.insert("type".into(), Value::String("webauthn.get".into()));
        client.insert("challenge".into(), Value::String(test_challenge()));
        client.insert("origin".into(), Value::String("https://example.com".into()));
        client.insert("crossOrigin".into(), Value::Bool(false));
        if let Some((k, v)) = client_override {
            client.insert(k.into(), v);
        }
        let client_b64 = encode_base64url(&serde_json::to_vec(&Value::Object(client)).unwrap());

        let mut resp = Map::new();
        resp.insert("clientDataJSON".into(), Value::String(client_b64));
        resp.insert(
            "authenticatorData".into(),
            Value::String(encode_base64url(&[0u8; 37])),
        );
        resp.insert(
            "signature".into(),
            Value::String(encode_base64url(&[1u8; 70])),
        );
        resp.insert("userHandle".into(), Value::Null);
        if let Some((k, v)) = response_override {
            resp.insert(k.into(), v);
        }

        let payload = if let Some(err) = error {
            json!({
                "version": 1,
                "state": state,
                "error": err,
            })
        } else {
            json!({
                "version": 1,
                "state": state,
                "credential": {
                    "id": "AQID",
                    "rawId": "AQID",
                    "type": "public-key",
                    "response": Value::Object(resp),
                }
            })
        };
        let encoded = encode_base64url(&serde_json::to_vec(&payload).unwrap());
        format!("moviepilot://passkey/callback#result={encoded}")
    }

    #[test]
    fn provider_and_frontend_capabilities_accept_both_formats() {
        for enveloped in [false, true] {
            for (raw, expected) in [
                (
                    r#"[{"type":"system","method":"passkey","enabled":true}]"#,
                    true,
                ),
                (
                    r#"[{"type":"system","method":"passkey","enabled":false}]"#,
                    false,
                ),
                (
                    r#"[{"type":"oidc","method":"passkey","enabled":true}]"#,
                    false,
                ),
                (
                    r#"[{"type":"system","method":"passkey","enabled":"true"}]"#,
                    false,
                ),
                ("[]", false),
            ] {
                let body = if enveloped {
                    format!(r#"{{"success":true,"message":"","data":{raw}}}"#)
                } else {
                    raw.to_string()
                };
                assert_eq!(parse_passkey_provider_enabled(&body).unwrap(), expected);
            }
        }
        assert!(parse_passkey_provider_enabled(r#"{"success":false,"data":[]}"#).is_err());
        assert!(supports_passkey_frontend_marker(
            r#"{"protocol":"moviepilot.passkey","version":1}"#
        ));
        assert!(!supports_passkey_frontend_marker(
            r#"{"protocol":"moviepilot.passkey","version":2}"#
        ));
        assert!(!supports_passkey_frontend_marker("<html>login</html>"));
    }

    #[test]
    fn separates_transaction_token_and_verifies_subpath_callback() {
        for legacy in [false, true] {
            let prep = prepare_passkey_request(
                &make_start_body(None, legacy),
                "https://example.com/mp/",
                &test_state(),
            )
            .unwrap();
            assert!(
                prep.authorization_url
                    .starts_with("https://example.com/mp/native-passkey.html#request=")
            );
            assert!(!prep.authorization_url.contains("private-transaction-token"));
            assert_eq!(prep.timeout_secs, 60);

            let cb = make_callback(&prep.state, None, None, None);
            let outcome = verify_passkey_callback(
                &cb,
                "https://example.com/mp/",
                &prep.state,
                &prep.challenge,
                &prep.transaction_token,
            );
            assert!(outcome.ok);
            let finish_json: Value =
                serde_json::from_str(outcome.finish_body_json.as_deref().unwrap()).unwrap();
            assert_eq!(
                finish_json.get("transaction_token").and_then(Value::as_str),
                Some("private-transaction-token")
            );
        }
    }

    #[test]
    fn rejects_insecure_origin_and_client_tampering() {
        assert!(!is_passkey_secure_origin("http://192.168.1.20:3000"));
        assert!(is_passkey_secure_origin("http://localhost:5173"));
        assert_eq!(
            prepare_passkey_request(
                &make_start_body(None, false),
                "http://192.168.1.20:3000",
                &test_state()
            ),
            Err(PasskeyErrorCode::Unsupported)
        );

        let prep = prepare_passkey_request(
            &make_start_body(None, false),
            "https://example.com/mp/",
            &test_state(),
        )
        .unwrap();
        for (field, val) in [
            ("origin", json!("https://evil.example")),
            ("type", json!("webauthn.create")),
            ("challenge", json!("AQIDBAUGBwgJCgsMDQ4PEA")),
            ("crossOrigin", json!(true)),
        ] {
            let cb = make_callback(&prep.state, None, Some((field, val)), None);
            let out = verify_passkey_callback(
                &cb,
                "https://example.com/mp/",
                &prep.state,
                &prep.challenge,
                &prep.transaction_token,
            );
            assert!(!out.ok);
            assert_eq!(out.error_code.as_deref(), Some("invalid"));
        }

        let canceled_cb = make_callback(&prep.state, Some("canceled"), None, None);
        let canceled_out = verify_passkey_callback(
            &canceled_cb,
            "https://example.com/mp/",
            &prep.state,
            &prep.challenge,
            &prep.transaction_token,
        );
        assert!(!canceled_out.ok);
        assert_eq!(canceled_out.error_code.as_deref(), Some("canceled"));
        assert_eq!(canceled_out.error_message_zh, None);
    }
}
