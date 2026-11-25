//! MoviePilot 动态插件跨端引擎：完整实现 Vuetify JSON UI 树解码、安全条件表达式求值、
//! 5 字段 Cron 语法解析/描述、Vuetify 3.7.3 Combobox 归一化与无损全模型补丁提交。

pub mod combobox;
pub mod cron;
pub mod expression;
pub mod form;
pub mod remote_runtime;

pub use combobox::{ComboboxEntry, ComboboxMode, NativeCombobox};
pub use cron::{CronFormat, CronSummary, NativeCron};
pub use expression::NativeFormExpression;
pub use form::{
    NativeFormPlan, PluginFieldSpec, PluginFormDraft, PluginNode, PluginRenderMode, PluginUiDecoder,
};
pub use remote_runtime::{
    PluginRemoteCacheKey, PluginRemoteEntryPlan, PluginRemoteUpstreamTarget,
    build_plugin_remote_cache_key, normalize_plugin_remote_entry,
    resolve_plugin_remote_upstream_path, sanitize_cache_segment, validate_plugin_api_path,
    validate_plugin_shell_asset_path,
};
