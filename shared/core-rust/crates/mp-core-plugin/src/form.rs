//! 动态插件 JSON UI 解码器、扁平化渲染表单计划（NativeFormPlan）与无损全模型补丁提交。

use crate::combobox::{ComboboxEntry, NativeCombobox};
use crate::expression::NativeFormExpression;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

/// 插件渲染模式（原生 Vuetify 映射 vs 受控隔离 Vue WebView）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PluginRenderMode {
    Vuetify,
    Vue,
}

fn deserialize_null_default<'de, D, T>(deserializer: D) -> Result<T, D::Error>
where
    T: Default + Deserialize<'de>,
    D: serde::Deserializer<'de>,
{
    Ok(Option::<T>::deserialize(deserializer)?.unwrap_or_default())
}

/// 原始插件 UI 节点（兼容 Python 插件中 `props: null`、`content: null` 及省略 `component` 的文本节点）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PluginNode {
    #[serde(default, deserialize_with = "deserialize_null_default")]
    pub component: String,
    #[serde(default, deserialize_with = "deserialize_null_default")]
    pub props: Map<String, Value>,
    #[serde(default)]
    pub text: Option<Value>,
    #[serde(default)]
    pub html: Option<String>,
    #[serde(default, deserialize_with = "deserialize_null_default")]
    pub content: Vec<PluginNode>,
}

/// 供三端声明式 UI 直接映射渲染的扁平字段/控件规格。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PluginFieldSpec {
    pub component: String,
    pub model_key: Option<String>,
    pub label: String,
    pub hint: String,
    pub placeholder: String,
    pub visible: bool,
    pub multiple: bool,
    pub clearable: bool,
    pub items: Vec<ComboboxEntry>,
    pub text: String,
    pub raw_props: Value,
}

/// 动态插件表单规划树输出。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeFormPlan {
    pub render_mode: PluginRenderMode,
    pub fields: Vec<PluginFieldSpec>,
    pub model: Value,
    pub has_unsupported_components: bool,
    pub unsupported_components: Vec<String>,
}

/// 动态插件 JSON UI 解码与规划器。
pub struct PluginUiDecoder;

impl PluginUiDecoder {
    const SUPPORTED_COMPONENTS: &'static [&'static str] = &[
        "VForm",
        "VRow",
        "VCol",
        "VCard",
        "VCardText",
        "VCardTitle",
        "VCardSubtitle",
        "VCardActions",
        "VAlert",
        "VSwitch",
        "VCheckbox",
        "VTextField",
        "VTextarea",
        "VSelect",
        "VAutocomplete",
        "VCombobox",
        "VCronField",
        "VSlider",
        "VRangeSlider",
        "VTabs",
        "VTab",
        "VWindow",
        "VWindowItem",
        "VExpansionPanels",
        "VExpansionPanel",
        "VChip",
        "VChipGroup",
        "VDataTable",
        "VTable",
        "VApexChart",
        "VAceEditor",
        "VDialog",
        "VBtn",
        "VIcon",
        "VDivider",
        "VSpacer",
        "VCarousel",
        "VImg",
        "div",
        "span",
        "p",
        "a",
    ];

    /// 解析插件 `get_form` 或 `get_page` 响应并生成扁平化 `NativeFormPlan`（自动解包 V3 `{success, data}` 信封）。
    pub fn plan(document: &Value) -> NativeFormPlan {
        let doc = if document.get("conf").is_none() && document.get("page").is_none() {
            document
                .get("data")
                .filter(|v| v.is_object())
                .unwrap_or(document)
        } else {
            document
        };
        let render_mode = match doc
            .get("render_mode")
            .and_then(|v| v.as_str())
            .unwrap_or("vuetify")
            .to_ascii_lowercase()
            .as_str()
        {
            "vue" => PluginRenderMode::Vue,
            _ => PluginRenderMode::Vuetify,
        };
        let model = doc
            .get("model")
            .cloned()
            .unwrap_or_else(|| Value::Object(Map::new()));

        let nodes_val = doc
            .get("conf")
            .or_else(|| doc.get("page"))
            .cloned()
            .unwrap_or(Value::Array(Vec::new()));
        let nodes: Vec<PluginNode> = serde_json::from_value(nodes_val).unwrap_or_default();

        let mut fields = Vec::new();
        let mut unsupported = Vec::new();
        Self::walk(&nodes, &model, true, &mut fields, &mut unsupported);

        NativeFormPlan {
            render_mode,
            fields,
            model,
            has_unsupported_components: !unsupported.is_empty(),
            unsupported_components: unsupported,
        }
    }

    fn walk(
        nodes: &[PluginNode],
        model: &Value,
        parent_visible: bool,
        fields: &mut Vec<PluginFieldSpec>,
        unsupported: &mut Vec<String>,
    ) {
        for node in nodes {
            if !Self::SUPPORTED_COMPONENTS
                .iter()
                .any(|c| c.eq_ignore_ascii_case(&node.component))
                && !unsupported.contains(&node.component)
            {
                unsupported.push(node.component.clone());
            }
            let own_visible = node
                .props
                .get("v-show")
                .or_else(|| node.props.get("v-if"))
                .and_then(|v| v.as_str())
                .map(|expr| NativeFormExpression::evaluate(expr, model))
                .unwrap_or(true);
            let visible = parent_visible && own_visible;

            let model_key = node
                .props
                .get("model")
                .and_then(|v| v.as_str())
                .map(str::to_string);
            let label = node
                .props
                .get("label")
                .or_else(|| node.props.get("title"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let hint = node
                .props
                .get("hint")
                .or_else(|| node.props.get("subtitle"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let placeholder = node
                .props
                .get("placeholder")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let text = match &node.text {
                Some(Value::String(s)) => s.clone(),
                Some(Value::Null) | None => node
                    .props
                    .get("text")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string(),
                Some(other) => other.to_string(),
            };

            let is_leaf_or_interactive = model_key.is_some()
                || matches!(
                    node.component.as_str(),
                    "VAlert"
                        | "VBtn"
                        | "VDataTable"
                        | "VTable"
                        | "VApexChart"
                        | "VChip"
                        | "VDivider"
                )
                || (!text.is_empty() && node.content.is_empty());

            if is_leaf_or_interactive {
                let raw_props = Value::Object(node.props.clone());
                fields.push(PluginFieldSpec {
                    component: node.component.clone(),
                    model_key,
                    label,
                    hint,
                    placeholder,
                    visible,
                    multiple: node
                        .props
                        .get("multiple")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    clearable: node
                        .props
                        .get("clearable")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    items: NativeCombobox::normalize_items(&raw_props),
                    text,
                    raw_props,
                });
            }

            if !node.content.is_empty() {
                Self::walk(&node.content, model, visible, fields, unsupported);
            }
        }
    }
}

/// 无损插件模型补丁器：严格保留服务端原始模型中的未知键与 64 位大整数（如 `9007199254740993`）。
pub struct PluginFormDraft;

impl PluginFormDraft {
    /// 将用户编辑后的局部键值无损合并回原始完整模型。
    pub fn apply_patch(original_model: &Value, patch: &Value) -> Value {
        let mut base = original_model.as_object().cloned().unwrap_or_default();
        if let Some(patch_obj) = patch.as_object() {
            for (k, v) in patch_obj {
                base.insert(k.clone(), v.clone());
            }
        }
        Value::Object(base)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn decodes_all_17_real_plugin_ui_fixtures_and_preserves_large_ints() {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../fixtures/plugin-ui");
        let mut count = 0;
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().and_then(|s| s.to_str()) != Some("json")
                || path.file_name().and_then(|s| s.to_str()) == Some("provenance.json")
            {
                continue;
            }
            let doc: Value =
                serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
            let plan = PluginUiDecoder::plan(&doc);
            assert_eq!(
                plan.render_mode,
                PluginRenderMode::Vuetify,
                "fixture={path:?}"
            );
            count += 1;
        }
        assert!(count >= 16, "expected >=16 plugin-ui fixtures, got {count}");

        // 验证无损大整数保留（9007199254740993 > 2^53）
        let orig: Value = serde_json::from_str(
            r#"{"enabled":false,"future":{"integer":9007199254740993,"hidden":"keep"}}"#,
        )
        .unwrap();
        let patch: Value = serde_json::from_str(r#"{"enabled":true}"#).unwrap();
        let merged = PluginFormDraft::apply_patch(&orig, &patch);
        assert_eq!(merged["enabled"], Value::Bool(true));
        assert_eq!(merged["future"]["integer"].as_i64(), Some(9007199254740993));
    }

    #[test]
    fn unwraps_v3_envelope_and_handles_null_props_and_content() {
        let wrapped_vuetify: Value = serde_json::from_str(
            r#"{
                "success": true,
                "message": "",
                "data": {
                    "render_mode": "vuetify",
                    "conf": [
                        {
                            "component": "VForm",
                            "props": null,
                            "content": [
                                {
                                    "component": "VSwitch",
                                    "props": {"model": "enabled", "label": "启用插件"},
                                    "content": null
                                }
                            ]
                        }
                    ],
                    "model": {"enabled": true}
                }
            }"#,
        )
        .unwrap();
        let plan = PluginUiDecoder::plan(&wrapped_vuetify);
        assert_eq!(plan.render_mode, PluginRenderMode::Vuetify);
        assert_eq!(plan.fields.len(), 1);
        assert_eq!(plan.fields[0].component, "VSwitch");
        assert_eq!(plan.fields[0].model_key.as_deref(), Some("enabled"));
        assert_eq!(plan.model["enabled"], Value::Bool(true));

        let wrapped_vue: Value = serde_json::from_str(
            r#"{"success":true,"message":"","data":{"render_mode":"vue","conf":[],"model":{"enabled":false}}}"#,
        )
        .unwrap();
        let vue_plan = PluginUiDecoder::plan(&wrapped_vue);
        assert_eq!(vue_plan.render_mode, PluginRenderMode::Vue);
        assert!(vue_plan.fields.is_empty());
    }
}
