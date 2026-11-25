//! Vuetify 3.7.3 Combobox 选择项归一化与值回写语义（无损保留原对象扩展字段）。

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Combobox 值模式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ComboboxMode {
    Single,
    Multiple,
}

/// 标准化候选条目。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ComboboxEntry {
    pub title: String,
    pub value: Value,
    pub raw_item: Value,
}

/// 跨端统一 Combobox 逻辑。
pub struct NativeCombobox;

impl NativeCombobox {
    /// 从 Vuetify `props.items` 解码标准化选项列表。
    pub fn normalize_items(props: &Value) -> Vec<ComboboxEntry> {
        let title_key = props
            .get("item-title")
            .or_else(|| props.get("itemTitle"))
            .and_then(|v| v.as_str())
            .unwrap_or("title");
        let value_key = props
            .get("item-value")
            .or_else(|| props.get("itemValue"))
            .and_then(|v| v.as_str())
            .unwrap_or("value");
        let Some(arr) = props.get("items").and_then(|v| v.as_array()) else {
            return Vec::new();
        };
        arr.iter()
            .map(|item| match item {
                Value::Object(obj) => {
                    let title = obj
                        .get(title_key)
                        .and_then(|v| v.as_str())
                        .or_else(|| obj.get("text").and_then(|v| v.as_str()))
                        .map(str::to_string)
                        .unwrap_or_else(|| item.to_string());
                    let value = obj.get(value_key).cloned().unwrap_or_else(|| item.clone());
                    ComboboxEntry {
                        title,
                        value,
                        raw_item: item.clone(),
                    }
                }
                Value::String(s) => ComboboxEntry {
                    title: s.clone(),
                    value: Value::String(s.clone()),
                    raw_item: item.clone(),
                },
                other => ComboboxEntry {
                    title: other.to_string(),
                    value: other.clone(),
                    raw_item: other.clone(),
                },
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn loads_vuetify_combobox_corpus() {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../fixtures/plugin-forms/combobox-vuetify-3.7.3.json");
        let text = std::fs::read_to_string(path).unwrap();
        let corpus: Value = serde_json::from_str(&text).unwrap();
        assert!(corpus.is_object() || corpus.is_array());
    }
}
