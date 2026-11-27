//! MoviePilot 服务地址严格校验与规范化，保留反向代理子路径前缀并拒绝内嵌凭据。

use serde::{Deserialize, Serialize};
use thiserror::Error;
use url::Url;

/// 服务地址解析错误类型。
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ServerAddressError {
    #[error("服务地址不能为空")]
    Empty,
    #[error("仅支持 http 或 https 协议")]
    UnsupportedScheme,
    #[error("服务地址缺少合法主机名")]
    MissingHost,
    #[error("服务地址不允许内嵌用户名或密码")]
    ContainsCredentials,
    #[error("服务地址格式无效：{0}")]
    InvalidFormat(String),
}

/// 经过严格规范化的 MoviePilot 实例根地址（无尾斜杠，保留部署子路径）。
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ServerAddress {
    normalized: String,
    origin: String,
    base_path: String,
}

impl ServerAddress {
    /// 解析并规范化用户输入的实例地址；缺省协议时默认补全 `http://`。
    pub fn parse(raw: &str) -> Result<Self, ServerAddressError> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return Err(ServerAddressError::Empty);
        }
        let candidate = if trimmed.contains("://") {
            trimmed.to_string()
        } else {
            format!("http://{trimmed}")
        };
        let mut parsed =
            Url::parse(&candidate).map_err(|e| ServerAddressError::InvalidFormat(e.to_string()))?;
        match parsed.scheme() {
            "http" | "https" => {}
            _ => return Err(ServerAddressError::UnsupportedScheme),
        }
        if !parsed.username().is_empty() || parsed.password().is_some() {
            return Err(ServerAddressError::ContainsCredentials);
        }
        let host = parsed.host_str().ok_or(ServerAddressError::MissingHost)?;
        if host.is_empty() {
            return Err(ServerAddressError::MissingHost);
        }
        parsed.set_query(None);
        parsed.set_fragment(None);
        let clean_path = parsed.path().trim_end_matches('/').to_string();
        parsed.set_path(&clean_path);
        let origin = parsed.origin().ascii_serialization();
        let normalized = parsed.as_str().trim_end_matches('/').to_string();
        Ok(Self {
            normalized,
            origin,
            base_path: clean_path,
        })
    }

    /// 规范化后的无尾斜杠地址字符串。
    pub fn as_str(&self) -> &str {
        &self.normalized
    }

    /// 协议 + 主机 + 端口源标识。
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// 反代部署子路径前缀（根部署为空字符串）。
    pub fn base_path(&self) -> &str {
        &self.base_path
    }

    /// 校验目标 URL 是否严格属于本实例源及部署子路径，防止凭据跨实例或跨域泄漏。
    pub fn contains(&self, candidate_url: &str) -> bool {
        let Ok(parsed) = Url::parse(candidate_url) else {
            return false;
        };
        if parsed.origin().ascii_serialization() != self.origin {
            return false;
        }
        if self.base_path.is_empty() {
            return true;
        }
        let path = parsed.path();
        path == self.base_path || path.starts_with(&format!("{}/", self.base_path))
    }

    /// 将服务端返回的相对路径或反向代理协议失配（如 HTTPS 反代后 `url_for` 生成 `http://.../api/v1/...`）
    /// 安全重绑到当前已验证的实例根地址；非 `/api/v1/` 跨源直链（如网盘 CDN、Emby 直连流）返回 `None`。
    pub fn rebase_instance_api_url(&self, raw_url: &str) -> Option<String> {
        let trimmed = raw_url.trim();
        if trimmed.is_empty() || trimmed.chars().any(char::is_whitespace) || trimmed.contains('#') {
            return None;
        }
        if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
            let parsed = Url::parse(trimmed).ok()?;
            if !parsed.username().is_empty()
                || parsed.password().is_some()
                || parsed.fragment().is_some()
            {
                return None;
            }
            if self.contains(trimmed) {
                return Some(trimmed.to_string());
            }
            let path = parsed.path();
            if path.split('/').any(|seg| seg == "..") {
                return None;
            }
            let api_suffix = if !self.base_path.is_empty()
                && path.starts_with(&format!("{}/api/v1/", self.base_path))
            {
                &path[self.base_path.len()..]
            } else if path.starts_with("/api/v1/") {
                path
            } else {
                return None;
            };
            let mut rebased = format!("{}{}", self.normalized, api_suffix);
            if let Some(q) = parsed.query() {
                rebased.push('?');
                rebased.push_str(q);
            }
            return self.contains(&rebased).then_some(rebased);
        }
        if trimmed.starts_with("//") || trimmed.contains("://") {
            return None;
        }
        let (rel_path, query) = match trimmed.split_once('?') {
            Some((p, q)) => (p, Some(q)),
            None => (trimmed, None),
        };
        let with_slash = if rel_path.starts_with('/') {
            rel_path.to_string()
        } else {
            format!("/{rel_path}")
        };
        if with_slash.split('/').any(|seg| seg == "..") {
            return None;
        }
        let suffix = if !self.base_path.is_empty()
            && (with_slash == self.base_path
                || with_slash.starts_with(&format!("{}/", self.base_path)))
        {
            &with_slash[self.base_path.len()..]
        } else {
            with_slash.as_str()
        };
        let mut rebased = format!("{}{}", self.normalized, suffix);
        if let Some(q) = query {
            rebased.push('?');
            rebased.push_str(q);
        }
        let parsed = Url::parse(&rebased).ok()?;
        if !parsed.username().is_empty()
            || parsed.password().is_some()
            || parsed.fragment().is_some()
        {
            return None;
        }
        self.contains(&rebased).then_some(rebased)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_and_checks_subpath_containment() {
        let addr = ServerAddress::parse("https://nas.example.test/mp/").unwrap();
        assert_eq!(addr.as_str(), "https://nas.example.test/mp");
        assert_eq!(addr.base_path(), "/mp");
        assert!(addr.contains("https://nas.example.test/mp/api/v1/user/current"));
        assert!(!addr.contains("https://nas.example.test/other/api/v1/user/current"));
        assert!(!addr.contains("https://evil.test/mp/api/v1/user/current"));
    }

    #[test]
    fn rejects_embedded_credentials_and_bad_schemes() {
        assert_eq!(
            ServerAddress::parse("http://user:pass@nas.local:3000"),
            Err(ServerAddressError::ContainsCredentials)
        );
        assert_eq!(
            ServerAddress::parse("ftp://nas.local"),
            Err(ServerAddressError::UnsupportedScheme)
        );
    }

    #[test]
    fn rebases_reverse_proxy_api_urls_without_touching_external_streams() {
        let https_addr = ServerAddress::parse("https://mp.example.test:8443").unwrap();
        assert_eq!(
            https_addr.rebase_instance_api_url(
                "http://mp.example.test:8443/api/v1/mediaserver/stream-subtitle?itemid=42&subtitle_id=ms%3A1%3A2.ass&server=Emby"
            ),
            Some(
                "https://mp.example.test:8443/api/v1/mediaserver/stream-subtitle?itemid=42&subtitle_id=ms%3A1%3A2.ass&server=Emby"
                    .to_string()
            )
        );
        assert_eq!(
            https_addr.rebase_instance_api_url("https://cdn.example.net/d/movie.mkv?sign=abc"),
            None
        );

        let subpath_addr = ServerAddress::parse("https://nas.example.test/mp/").unwrap();
        assert_eq!(
            subpath_addr.rebase_instance_api_url(
                "http://172.17.0.2:3001/api/v1/mediaserver/stream-subtitle?itemid=9&subtitle_id=Movie.zh.ass"
            ),
            Some(
                "https://nas.example.test/mp/api/v1/mediaserver/stream-subtitle?itemid=9&subtitle_id=Movie.zh.ass"
                    .to_string()
            )
        );
        assert_eq!(
            subpath_addr.rebase_instance_api_url("/api/v1/mediaserver/stream?itemid=9"),
            Some("https://nas.example.test/mp/api/v1/mediaserver/stream?itemid=9".to_string())
        );
    }
}
