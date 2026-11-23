//! MoviePilot 会话状态机、JWT 过期解析、RBAC 权限矩阵与平台安全凭据 Trait（ADR-02）。

use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// 平台原生安全存储抽象（iOS Keychain / Android Keystore / 鸿蒙 HUKS）。
pub trait SecretStore: Send + Sync {
    fn get_secret(&self, key: &str) -> Option<String>;
    fn set_secret(&self, key: &str, value: &str) -> Result<(), String>;
    fn remove_secret(&self, key: &str) -> Result<(), String>;
}

/// JWT 声明解析结果（纯解码，不替代服务端验签，用于本地过期感知与自动登出）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct JwtClaims {
    pub subject: Option<String>,
    pub user_name: Option<String>,
    pub exp: Option<i64>,
    pub super_user: bool,
    pub is_expired: bool,
}

/// 解析 JWT payload 并基于当前 Unix 时间戳与安全提前量（默认 30 秒）判断是否过期。
pub fn decode_jwt_claims(token: &str, now_epoch_secs: i64) -> JwtClaims {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() < 2 {
        return JwtClaims {
            subject: None,
            user_name: None,
            exp: None,
            super_user: false,
            is_expired: false,
        };
    }
    let Ok(bytes) = URL_SAFE_NO_PAD.decode(parts[1]) else {
        return JwtClaims {
            subject: None,
            user_name: None,
            exp: None,
            super_user: false,
            is_expired: false,
        };
    };
    let Ok(val) = serde_json::from_slice::<serde_json::Value>(&bytes) else {
        return JwtClaims {
            subject: None,
            user_name: None,
            exp: None,
            super_user: false,
            is_expired: false,
        };
    };
    let exp = val.get("exp").and_then(|v| v.as_i64());
    let is_expired = exp.is_some_and(|e| now_epoch_secs + 30 >= e);
    JwtClaims {
        subject: val.get("sub").and_then(|v| v.as_str()).map(str::to_string),
        user_name: val
            .get("username")
            .or_else(|| val.get("user_name"))
            .and_then(|v| v.as_str())
            .map(str::to_string),
        exp,
        super_user: val
            .get("super_user")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        is_expired,
    }
}

/// 严格对齐 `ios/Sources/MoviePilotSession/NativePermissions.swift` 的权限矩阵。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NativePermissions {
    pub discovery: bool,
    pub search: bool,
    pub subscribe: bool,
    pub manage: bool,
    pub admin: bool,
    pub features: BTreeMap<String, bool>,
}

impl NativePermissions {
    /// 按与前端/iOS 一致的严格布尔语义解析权限 JSON；超级管理员自动获得全部权限。
    pub fn from_json(raw: &serde_json::Value, is_superuser: bool) -> Self {
        if is_superuser {
            return Self {
                discovery: true,
                search: true,
                subscribe: true,
                manage: true,
                admin: true,
                features: BTreeMap::new(),
            };
        }
        let flag = |key: &str, default_val: bool| -> bool {
            match raw.get(key) {
                None | Some(serde_json::Value::Null) => default_val,
                Some(serde_json::Value::Bool(b)) => *b,
                Some(_) => false,
            }
        };
        let mut features = BTreeMap::new();
        if let Some(obj) = raw.get("features").and_then(|v| v.as_object()) {
            for (k, v) in obj {
                if let Some(b) = v.as_bool() {
                    features.insert(k.clone(), b);
                }
            }
        }
        Self {
            discovery: flag("discovery", true),
            search: flag("search", true),
            subscribe: flag("subscribe", true),
            manage: flag("manage", false),
            admin: false,
            features,
        }
    }

    /// 检查细分功能项权限；缺省继承分类权限，明确 false 才收窄。
    pub fn allows_feature(&self, key: &str) -> bool {
        if self.admin || key.is_empty() {
            return true;
        }
        self.features.get(key).copied().unwrap_or(true)
    }
}

/// 401/403 响应后的会话状态转移决策：区分令牌失效（需清缓存退登录）与普通 RBAC 403。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionAuthDecision {
    Valid,
    UnauthorizedMustLogout,
    ForbiddenKeepSession,
}

/// 判定后端 HTTP 状态码与消息是否属于会话令牌失效。
pub fn classify_auth_status(status: u16, body_text: &str) -> SessionAuthDecision {
    if status == 401 {
        return SessionAuthDecision::UnauthorizedMustLogout;
    }
    if status == 403 {
        let lower = body_text.to_ascii_lowercase();
        if lower.contains("could not validate credentials")
            || lower.contains("token") && lower.contains("expired")
            || lower.contains("invalid token")
        {
            return SessionAuthDecision::UnauthorizedMustLogout;
        }
        return SessionAuthDecision::ForbiddenKeepSession;
    }
    SessionAuthDecision::Valid
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_jwt_expiry_and_evaluates_permissions() {
        let header = URL_SAFE_NO_PAD.encode(br#"{"alg":"HS256","typ":"JWT"}"#);
        let payload = URL_SAFE_NO_PAD
            .encode(br#"{"sub":"42","username":"demo","exp":2000,"super_user":false}"#);
        let token = format!("{header}.{payload}.sig");
        assert!(!decode_jwt_claims(&token, 1900).is_expired);
        assert!(decode_jwt_claims(&token, 1980).is_expired);

        let perms = NativePermissions::from_json(
            &serde_json::json!({"discovery": true, "search": false, "manage": "yes", "features": {"plugin.demo.main": false}}),
            false,
        );
        assert!(perms.discovery);
        assert!(!perms.search);
        assert!(!perms.manage);
        assert!(!perms.admin);
        assert!(!perms.allows_feature("plugin.demo.main"));

        let admin = NativePermissions::from_json(&serde_json::json!({"search": false}), true);
        assert!(admin.admin && admin.search && admin.manage);
    }

    #[test]
    fn distinguishes_token_rejected_403_from_rbac_403() {
        assert_eq!(
            classify_auth_status(403, r#"{"detail":"Could not validate credentials"}"#),
            SessionAuthDecision::UnauthorizedMustLogout
        );
        assert_eq!(
            classify_auth_status(403, r#"{"detail":"无权限访问插件"}"#),
            SessionAuthDecision::ForbiddenKeepSession
        );
    }
}
