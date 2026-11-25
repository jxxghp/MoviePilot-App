//! ADR-01 原生网络传输注入契约：Rust 输出标准请求规格，三端原生网络栈执行实际 TLS/代理传输。

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use thiserror::Error;

/// HTTP 方法枚举。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Delete,
    Patch,
}

/// Rust 构造给各端原生网络层（URLSession / OkHttp / NetworkKit rcp）执行的请求规格。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HttpRequestSpec {
    pub url: String,
    pub method: HttpMethod,
    pub headers: BTreeMap<String, String>,
    pub body: Option<Vec<u8>>,
    pub timeout_secs: u64,
}

/// 原生网络层回传给 Rust 解码器的响应数据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HttpResponseData {
    pub status: u16,
    pub headers: BTreeMap<String, String>,
    pub body: Vec<u8>,
}

/// 平台网络传输错误。
#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum TransportError {
    #[error("网络连接失败：{0}")]
    Network(String),
    #[error("请求超时")]
    Timeout,
    #[error("请求已取消")]
    Cancelled,
    #[error("拒绝跨源重定向")]
    RedirectRefused,
}

/// 由三端原生实现并注入的同步传输 Trait（便于单元测试与无 Tokio 重型依赖）。
pub trait HttpTransport: Send + Sync {
    fn execute(&self, request: &HttpRequestSpec) -> Result<HttpResponseData, TransportError>;
}
