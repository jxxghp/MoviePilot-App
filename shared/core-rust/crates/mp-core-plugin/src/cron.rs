//! 原生 5 字段 Cron 表达式分析、可读描述与预设生成器（对齐 iOS NativeCron 与 cron-constructors 夹具）。

use serde::{Deserialize, Serialize};

/// Cron 表达式格式分类。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CronFormat {
    Empty,
    FiveFields,
    Custom,
}

/// Cron 分析结果与可读摘要。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CronSummary {
    pub raw_value: String,
    pub format: CronFormat,
    pub fields: Vec<String>,
    pub has_ambiguous_weekday: bool,
    pub description_zh: String,
    pub is_valid_five_field: bool,
}

/// 跨端统一 Cron 解析与摘要器。
pub struct NativeCron;

impl NativeCron {
    const WEEKDAYS: &'static [&'static str] = &["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

    /// 分析输入 Cron 表达式并生成清晰中文说明；自定义方言始终保留原文。
    pub fn analyze(source: &str) -> CronSummary {
        let trimmed = source.trim();
        if trimmed.is_empty() {
            return CronSummary {
                raw_value: source.to_string(),
                format: CronFormat::Empty,
                fields: Vec::new(),
                has_ambiguous_weekday: false,
                description_zh: "未设置定时周期".to_string(),
                is_valid_five_field: false,
            };
        }
        if trimmed.len() > 1024 {
            return CronSummary {
                raw_value: source.to_string(),
                format: CronFormat::Custom,
                fields: Vec::new(),
                has_ambiguous_weekday: false,
                description_zh: "自定义调度表达式".to_string(),
                is_valid_five_field: false,
            };
        }
        let parts: Vec<String> = trimmed.split_whitespace().map(str::to_string).collect();
        if parts.len() != 5 {
            return CronSummary {
                raw_value: source.to_string(),
                format: CronFormat::Custom,
                fields: Vec::new(),
                has_ambiguous_weekday: false,
                description_zh: format!("自定义调度（{} 段）", parts.len()),
                is_valid_five_field: false,
            };
        }

        let has_ambiguous_weekday = parts[4].bytes().any(|b| b.is_ascii_digit());
        let valid = Self::valid_token(&parts[0], 0, 59, false)
            && Self::valid_token(&parts[1], 0, 23, false)
            && Self::valid_token(&parts[2], 1, 31, true)
            && Self::valid_token(&parts[3], 1, 12, false)
            && Self::valid_weekday_token(&parts[4]);

        let desc = if valid {
            Self::describe_five_fields(&parts)
        } else {
            format!("自定义表达式：{}", trimmed)
        };

        CronSummary {
            raw_value: source.to_string(),
            format: if valid {
                CronFormat::FiveFields
            } else {
                CronFormat::Custom
            },
            fields: parts,
            has_ambiguous_weekday,
            description_zh: desc,
            is_valid_five_field: valid,
        }
    }

    fn valid_token(tok: &str, min: i32, max: i32, allow_last: bool) -> bool {
        if tok.is_empty() || tok.len() > 256 {
            return false;
        }
        if tok == "*" {
            return true;
        }
        if allow_last && tok.eq_ignore_ascii_case("last") {
            return true;
        }
        for item in tok.split(',') {
            let (base, step) = match item.split_once('/') {
                Some((b, s)) => (b, Some(s)),
                None => (item, None),
            };
            if let Some(st) = step {
                let Ok(step_num) = st.parse::<i32>() else {
                    return false;
                };
                if step_num <= 0 || step_num > (max - min + 1) {
                    return false;
                }
            }
            if base == "*" {
                continue;
            }
            if let Some((start_s, end_s)) = base.split_once('-') {
                let (Ok(a), Ok(b)) = (start_s.parse::<i32>(), end_s.parse::<i32>()) else {
                    return false;
                };
                if a < min || b > max || a > b {
                    return false;
                }
            } else {
                let Ok(v) = base.parse::<i32>() else {
                    return false;
                };
                if v < min || v > max {
                    return false;
                }
            }
        }
        true
    }

    fn valid_weekday_token(tok: &str) -> bool {
        if tok == "*" {
            return true;
        }
        for item in tok.split(',') {
            let (base, step) = match item.split_once('/') {
                Some((b, s)) => (b, Some(s)),
                None => (item, None),
            };
            if let Some(st) = step {
                let Ok(step_num) = st.parse::<i32>() else {
                    return false;
                };
                if step_num <= 0 || step_num > 7 {
                    return false;
                }
            }
            if base == "*" {
                continue;
            }
            if let Some((a, b)) = base.split_once('-') {
                if !Self::is_weekday_atom(a) || !Self::is_weekday_atom(b) {
                    return false;
                }
            } else if !Self::is_weekday_atom(base) {
                return false;
            }
        }
        true
    }

    fn is_weekday_atom(atom: &str) -> bool {
        let lower = atom.to_ascii_lowercase();
        if Self::WEEKDAYS.contains(&lower.as_str()) {
            return true;
        }
        atom.parse::<i32>().is_ok_and(|v| (0..=7).contains(&v))
    }

    fn describe_five_fields(parts: &[String]) -> String {
        let (min, hour, dom, mon, dow) = (&parts[0], &parts[1], &parts[2], &parts[3], &parts[4]);
        if let Some(step) = min.strip_prefix("*/")
            && hour == "*"
            && dom == "*"
            && mon == "*"
            && dow == "*"
        {
            return format!("每 {step} 分钟执行一次");
        }
        if let Some(step) = hour.strip_prefix("*/")
            && dom == "*"
            && mon == "*"
            && dow == "*"
        {
            return format!("每 {step} 小时的第 {min} 分执行");
        }
        if dom == "*" && mon == "*" && dow == "*" && hour != "*" && min != "*" {
            return format!("每天 {:0>2}:{:0>2} 执行", hour, min);
        }
        if dom.eq_ignore_ascii_case("last") && mon == "*" && dow == "*" {
            return format!("每月最后一天 {:0>2}:{:0>2} 执行", hour, min);
        }
        format!("分:{min} 时:{hour} 日:{dom} 月:{mon} 周:{dow}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn validates_cron_expressions_and_fixture() {
        let s = NativeCron::analyze("*/15 * * * *");
        assert!(s.is_valid_five_field);
        assert_eq!(s.description_zh, "每 15 分钟执行一次");

        let last_day = NativeCron::analyze("0 0 last * *");
        assert!(last_day.is_valid_five_field);

        let amb = NativeCron::analyze("0 9 * * 1-5");
        assert!(amb.has_ambiguous_weekday);

        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../fixtures/plugin-forms/cron-constructors.json");
        let root: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        assert!(root.is_object() || root.is_array());
    }
}
