//! MoviePilot V3 协议大脑：严格遵循 ADR-01（原生 HttpTransport 注入，不绑 reqwest），
//! 提供端点构造、SSE 流式帧解析、9 维站点资源级联筛选与同规格分组。

pub mod endpoint;
pub mod resource_filter;
pub mod sse;
pub mod transport;

pub use endpoint::{ApiEndpoint, ApiEndpointError};
pub use resource_filter::{
    ResourceFilterCriteria, ResourceFilterEngine, ResourceFilterOptions, ResourceGroup,
    ResourceItem, ResourceSortBy,
};
pub use sse::{SseEvent, SseStreamParser};
pub use transport::{HttpMethod, HttpRequestSpec, HttpResponseData, HttpTransport, TransportError};
