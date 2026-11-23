//! MoviePilot V3 端点 URL 构造器：保留部署子路径、显式尾斜杠与 `+` 编码，拒绝路径穿越。

use mp_core_model::ServerAddress;
use thiserror::Error;
use url::Url;

/// 端点校验错误。
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ApiEndpointError {
    #[error("端点路径不能为空或超过 64 段")]
    InvalidPathLength,
    #[error("端点路径包含非法段：{0}")]
    InvalidSegment(String),
    #[error("构造后的地址超出了实例源路径边界")]
    EscapedServerBoundary,
}

/// 相对 `/api/v1` 的 V3 端点构造器。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiEndpoint {
    pub segments: Vec<String>,
    pub query: Vec<(String, String)>,
    pub trailing_slash: bool,
}

impl ApiEndpoint {
    /// 构造并校验端点路径段。
    pub fn new(
        segments: Vec<String>,
        query: Vec<(String, String)>,
        trailing_slash: bool,
    ) -> Result<Self, ApiEndpointError> {
        if segments.is_empty() || segments.len() > 64 {
            return Err(ApiEndpointError::InvalidPathLength);
        }
        for seg in &segments {
            if !Self::valid_segment(seg) {
                return Err(ApiEndpointError::InvalidSegment(seg.clone()));
            }
        }
        Ok(Self {
            segments,
            query,
            trailing_slash,
        })
    }

    fn valid_segment(value: &str) -> bool {
        !value.is_empty()
            && value.len() <= 1024
            && value != "."
            && value != ".."
            && value
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~' | b':'))
    }

    /// 基于规范化实例地址拼接最终 V3 请求 URL。
    pub fn build_url(&self, address: &ServerAddress) -> Result<String, ApiEndpointError> {
        let mut base = format!("{}/api/v1", address.as_str());
        for seg in &self.segments {
            base.push('/');
            base.push_str(seg);
        }
        if self.trailing_slash {
            base.push('/');
        }
        let mut parsed = Url::parse(&base).map_err(|_| ApiEndpointError::EscapedServerBoundary)?;
        if !self.query.is_empty() {
            {
                let mut pairs = parsed.query_pairs_mut();
                for (k, v) in &self.query {
                    pairs.append_pair(k, v);
                }
            }
            // 与 iOS APIEndpoint 对齐：把表单式编码中的 '+' 规范化为 %2B 避免后端误解为空格
            if let Some(q) = parsed.query().map(|q| q.replace('+', "%20")) {
                parsed.set_query(Some(&q));
            }
        }
        let final_url = parsed.to_string();
        if !address.contains(&final_url) {
            return Err(ApiEndpointError::EscapedServerBoundary);
        }
        Ok(final_url)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_subpath_url_with_trailing_slash_and_query() {
        let addr = ServerAddress::parse("http://127.0.0.1:3001/a").unwrap();
        let ep = ApiEndpoint::new(
            vec!["plugin".into()],
            vec![("state".into(), "installed".into())],
            true,
        )
        .unwrap();
        assert_eq!(
            ep.build_url(&addr).unwrap(),
            "http://127.0.0.1:3001/a/api/v1/plugin/?state=installed"
        );
    }

    #[test]
    fn rejects_traversal_segment() {
        let err = ApiEndpoint::new(vec!["..".into(), "secret".into()], vec![], false).unwrap_err();
        assert!(matches!(err, ApiEndpointError::InvalidSegment(_)));
    }
}
