//! 跨端共享弹幕解析、过滤、短窗重复合并、密度限流与查询标题规范化引擎。
//!
//! 职责边界：
//! - 加载弹幕或用户变更过滤偏好时调用一次 `prepare_danmaku_timeline_json` 离线批处理；
//! - 各端原生渲染层直接持有有序数组与游标进行 60/120fps 轨道防碰撞绘制，避免逐帧跨 FFI 通信。

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::collections::HashMap;

/// 弹幕显示模式（兼容弹弹play / B 站标准协议编号）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DanmakuMode {
    /// 滚动弹幕（编号 1）。
    Scroll = 1,
    /// 底部固定弹幕（编号 4）。
    Bottom = 4,
    /// 顶部固定弹幕（编号 5）。
    Top = 5,
}

impl DanmakuMode {
    /// 将原始协议整数归一为标准弹幕模式。
    pub fn from_code(code: i64) -> Self {
        match code {
            4 => Self::Bottom,
            5 => Self::Top,
            _ => Self::Scroll,
        }
    }

    /// 返回标准协议编号（`1` / `4` / `5`）。
    pub fn as_code(self) -> u8 {
        match self {
            Self::Scroll => 1,
            Self::Bottom => 4,
            Self::Top => 5,
        }
    }
}

impl Serialize for DanmakuMode {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_u8(self.as_code())
    }
}

impl<'de> Deserialize<'de> for DanmakuMode {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum RawMode {
            Code(i64),
            Label(String),
        }
        match RawMode::deserialize(deserializer)? {
            RawMode::Code(c) => Ok(Self::from_code(c)),
            RawMode::Label(s) => match s.trim().to_ascii_lowercase().as_str() {
                "bottom" | "4" => Ok(Self::Bottom),
                "top" | "5" => Ok(Self::Top),
                _ => Ok(Self::Scroll),
            },
        }
    }
}

/// 经过滤、去重与排序后的单条可渲染弹幕。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DanmakuItem {
    /// 相对视频起点的出现时间戳（毫秒，已叠加用户偏移且非负）。
    pub time_ms: i64,
    /// 显示模式（1=滚动，4=底部，5=顶部）。
    pub mode: DanmakuMode,
    /// 24 位 RGB 颜色整数（例如 `16777215` 表示 `#FFFFFF`）。
    pub color_rgb: u32,
    /// 清洗后的单行弹幕正文。
    pub text: String,
    /// 短时间窗口内相同刷屏弹幕合并计数（默认 1）。
    pub repeat_count: u32,
}

fn default_true() -> bool {
    true
}

fn default_merge_window_ms() -> i64 {
    3000
}

fn default_max_per_second() -> u32 {
    12
}

/// 跨端统一的弹幕离线过滤与限流参数。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DanmakuFilterOptions {
    #[serde(default = "default_true")]
    pub allow_scroll: bool,
    #[serde(default = "default_true")]
    pub allow_top: bool,
    #[serde(default = "default_true")]
    pub allow_bottom: bool,
    #[serde(default = "default_true")]
    pub allow_color: bool,
    #[serde(default = "default_true")]
    pub merge_duplicates: bool,
    #[serde(default = "default_merge_window_ms")]
    pub merge_window_ms: i64,
    #[serde(default = "default_max_per_second")]
    pub max_per_second: u32,
    #[serde(default)]
    pub block_keywords: Vec<String>,
    #[serde(default)]
    pub offset_ms: i64,
}

impl Default for DanmakuFilterOptions {
    fn default() -> Self {
        Self {
            allow_scroll: true,
            allow_top: true,
            allow_bottom: true,
            allow_color: true,
            merge_duplicates: true,
            merge_window_ms: default_merge_window_ms(),
            max_per_second: default_max_per_second(),
            block_keywords: Vec::new(),
            offset_ms: 0,
        }
    }
}

/// Rust 离线批处理输出的弹幕时间线及统计摘要。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PreparedDanmakuTimeline {
    /// 原始解析出的总弹幕数。
    pub raw_count: usize,
    /// 经过滤、去重与密度限流后保留的可渲染弹幕数。
    pub filtered_count: usize,
    /// 按 `time_ms` 升序排列的弹幕数组，可直接供原生层二分查找。
    pub items: Vec<DanmakuItem>,
}

const WHITE_RGB: u32 = 0x00FF_FFFF;
const MAX_PATTERN_CHARS: usize = 128;
const MAX_TEXT_CHARS: usize = 300;

struct RawEntry {
    time_ms: i64,
    mode: DanmakuMode,
    color_rgb: u32,
    text: String,
}

/// 安全编译的单条屏蔽规则（纯子串优先，`/pattern/` 仅支持线性时间通配与锚点，彻底杜绝 ReDoS）。
enum BlockRule {
    Substring(String),
    SafePattern { branches: Vec<PatternBranch> },
}

struct PatternBranch {
    anchor_start: bool,
    anchor_end: bool,
    segments: Vec<String>,
}

impl BlockRule {
    fn parse(raw: &str) -> Option<Self> {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            return None;
        }
        let limited: String = trimmed.chars().take(MAX_PATTERN_CHARS).collect();
        if limited.len() >= 2 && limited.starts_with('/') && limited.ends_with('/') {
            let inner = &limited[1..limited.len() - 1];
            if inner.trim().is_empty() {
                return None;
            }
            let branches: Vec<PatternBranch> = inner
                .split('|')
                .filter_map(|branch| {
                    let mut body = branch.trim().to_lowercase();
                    if body.is_empty() {
                        return None;
                    }
                    let anchor_start = body.starts_with('^');
                    if anchor_start {
                        body = body[1..].to_string();
                    }
                    let anchor_end = body.ends_with('$');
                    if anchor_end && !body.is_empty() {
                        body.pop();
                    }
                    let normalized = body.replace(".*", "*");
                    let segments: Vec<String> = normalized.split('*').map(str::to_string).collect();
                    if segments.iter().all(|s| s.is_empty()) {
                        return None;
                    }
                    Some(PatternBranch {
                        anchor_start,
                        anchor_end,
                        segments,
                    })
                })
                .collect();
            if branches.is_empty() {
                return None;
            }
            return Some(Self::SafePattern { branches });
        }
        Some(Self::Substring(limited.to_lowercase()))
    }

    fn matches(&self, lower_text: &str) -> bool {
        match self {
            Self::Substring(needle) => lower_text.contains(needle.as_str()),
            Self::SafePattern { branches } => branches.iter().any(|b| b.matches(lower_text)),
        }
    }
}

impl PatternBranch {
    /// 线性时间贪婪段匹配（O(n)），确保任何恶意输入都不会出现指数级回溯。
    fn matches(&self, text: &str) -> bool {
        if self.segments.len() == 1 {
            let seg = &self.segments[0];
            return match (self.anchor_start, self.anchor_end) {
                (true, true) => text == seg,
                (true, false) => text.starts_with(seg.as_str()),
                (false, true) => text.ends_with(seg.as_str()),
                (false, false) => text.contains(seg.as_str()),
            };
        }

        let mut cursor = 0usize;
        let last_idx = self.segments.len() - 1;
        for (idx, seg) in self.segments.iter().enumerate() {
            if seg.is_empty() {
                continue;
            }
            if idx == 0 && self.anchor_start {
                if !text.starts_with(seg.as_str()) {
                    return false;
                }
                cursor = seg.len();
            } else if idx == last_idx && self.anchor_end {
                if cursor > text.len() || !text[cursor..].ends_with(seg.as_str()) {
                    return false;
                }
                cursor = text.len();
            } else if let Some(pos) = text[cursor..].find(seg.as_str()) {
                cursor += pos + seg.len();
            } else {
                return false;
            }
        }
        true
    }
}

fn clean_text(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len().min(MAX_TEXT_CHARS));
    for ch in raw.chars() {
        if ch == '\r' || ch == '\n' || ch == '\t' {
            out.push(' ');
        } else if !ch.is_control() {
            out.push(ch);
        }
        if out.chars().count() >= MAX_TEXT_CHARS {
            break;
        }
    }
    out.trim().to_string()
}

fn normalize_color(raw: i64) -> u32 {
    if (0..=WHITE_RGB as i64).contains(&raw) {
        raw as u32
    } else {
        WHITE_RGB
    }
}

fn decode_xml_entities(input: &str) -> String {
    if !input.contains('&') {
        return input.to_string();
    }
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        rest = &rest[amp + 1..];
        if let Some(semi) = rest.find(';') {
            let entity = &rest[..semi];
            let decoded = match entity {
                "lt" => Some('<'),
                "gt" => Some('>'),
                "amp" => Some('&'),
                "quot" => Some('"'),
                "apos" => Some('\''),
                _ if entity.starts_with("#x") || entity.starts_with("#X") => {
                    u32::from_str_radix(&entity[2..], 16)
                        .ok()
                        .and_then(char::from_u32)
                }
                _ if entity.starts_with('#') => {
                    entity[1..].parse::<u32>().ok().and_then(char::from_u32)
                }
                _ => None,
            };
            if let Some(ch) = decoded {
                out.push(ch);
                rest = &rest[semi + 1..];
            } else {
                out.push('&');
            }
        } else {
            out.push('&');
            break;
        }
    }
    out.push_str(rest);
    out
}

fn parse_xml_entries(raw: &str) -> Vec<RawEntry> {
    let mut entries = Vec::new();
    let mut rest = raw;
    while let Some(start) = rest.find("<d ") {
        rest = &rest[start + 3..];
        let Some(tag_end) = rest.find('>') else {
            break;
        };
        let attrs = &rest[..tag_end];
        rest = &rest[tag_end + 1..];
        let Some(close) = rest.find("</d>") else {
            break;
        };
        let body_raw = &rest[..close];
        rest = &rest[close + 4..];

        let p_val = extract_xml_attr(attrs, "p");
        let Some(p_attr) = p_val else {
            continue;
        };
        let parts: Vec<&str> = p_attr.split(',').collect();
        if parts.len() < 4 {
            continue;
        }
        let Ok(sec) = parts[0].trim().parse::<f64>() else {
            continue;
        };
        let Ok(mode_num) = parts[1].trim().parse::<f64>() else {
            continue;
        };
        let Ok(color_num) = parts[3].trim().parse::<f64>() else {
            continue;
        };
        let text = clean_text(&decode_xml_entities(body_raw));
        if text.is_empty() || !sec.is_finite() {
            continue;
        }
        entries.push(RawEntry {
            time_ms: (sec * 1000.0).round() as i64,
            mode: DanmakuMode::from_code(mode_num as i64),
            color_rgb: normalize_color(color_num as i64),
            text,
        });
    }
    entries
}

fn extract_xml_attr<'a>(attrs: &'a str, name: &str) -> Option<&'a str> {
    let pattern_dq = format!("{name}=\"");
    if let Some(pos) = attrs.find(&pattern_dq) {
        let after = &attrs[pos + pattern_dq.len()..];
        return after.find('"').map(|end| &after[..end]);
    }
    let pattern_sq = format!("{name}='");
    if let Some(pos) = attrs.find(&pattern_sq) {
        let after = &attrs[pos + pattern_sq.len()..];
        return after.find('\'').map(|end| &after[..end]);
    }
    None
}

fn parse_json_entries(raw: &str) -> Result<Vec<RawEntry>, String> {
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|e| format!("弹幕 JSON 解析失败：{e}"))?;

    let list_opt = if let Some(arr) = value.as_array() {
        Some(arr)
    } else if let Some(obj) = value.as_object() {
        obj.get("data")
            .and_then(|d| d.get("items"))
            .and_then(|v| v.as_array())
            .or_else(|| obj.get("items").and_then(|v| v.as_array()))
            .or_else(|| obj.get("comments").and_then(|v| v.as_array()))
    } else {
        None
    };

    let Some(list) = list_opt else {
        return Ok(Vec::new());
    };

    let mut entries = Vec::with_capacity(list.len());
    for item in list {
        if let Some(arr) = item.as_array() {
            if arr.len() < 4 {
                continue;
            }
            let Some(time_ms) = arr[0]
                .as_i64()
                .or_else(|| arr[0].as_f64().map(|v| v.round() as i64))
            else {
                continue;
            };
            let mode_code = arr[1].as_i64().unwrap_or(1);
            let color_raw = arr[2].as_i64().unwrap_or(WHITE_RGB as i64);
            let Some(raw_text) = arr[3].as_str() else {
                continue;
            };
            let text = clean_text(raw_text);
            if text.is_empty() {
                continue;
            }
            entries.push(RawEntry {
                time_ms,
                mode: DanmakuMode::from_code(mode_code),
                color_rgb: normalize_color(color_raw),
                text,
            });
            continue;
        }

        if let Some(obj) = item.as_object() {
            // 兼容 DandanPlay 原始 `{p: "sec,mode,color,user", m: "text"}` 与已结构化的 `{time_ms, mode, color_rgb, text}`
            if let (Some(p_str), Some(m_str)) = (
                obj.get("p").and_then(|v| v.as_str()),
                obj.get("m")
                    .or_else(|| obj.get("text"))
                    .and_then(|v| v.as_str()),
            ) {
                let parts: Vec<&str> = p_str.split(',').collect();
                if parts.len() < 3 {
                    continue;
                }
                let Ok(sec) = parts[0].trim().parse::<f64>() else {
                    continue;
                };
                let Ok(mode_num) = parts[1].trim().parse::<f64>() else {
                    continue;
                };
                let Ok(color_num) = parts[2].trim().parse::<f64>() else {
                    continue;
                };
                let text = clean_text(m_str);
                if text.is_empty() || !sec.is_finite() {
                    continue;
                }
                entries.push(RawEntry {
                    time_ms: (sec * 1000.0).round() as i64,
                    mode: DanmakuMode::from_code(mode_num as i64),
                    color_rgb: normalize_color(color_num as i64),
                    text,
                });
            } else if let (Some(time_ms), Some(raw_text)) = (
                obj.get("time_ms").and_then(|v| v.as_i64()),
                obj.get("text").and_then(|v| v.as_str()),
            ) {
                let text = clean_text(raw_text);
                if text.is_empty() {
                    continue;
                }
                let mode_code = obj.get("mode").and_then(|v| v.as_i64()).unwrap_or(1);
                let color_raw = obj
                    .get("color_rgb")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(WHITE_RGB as i64);
                entries.push(RawEntry {
                    time_ms,
                    mode: DanmakuMode::from_code(mode_code),
                    color_rgb: normalize_color(color_raw),
                    text,
                });
            }
        }
    }

    Ok(entries)
}

/// 离线批处理单集弹幕载荷：解析、应用偏移、类型/色彩/屏蔽词过滤、短窗重复合并、稳定排序与每秒限流。
pub fn prepare_danmaku_timeline(
    raw_payload: &str,
    options: &DanmakuFilterOptions,
) -> Result<PreparedDanmakuTimeline, String> {
    let trimmed = raw_payload.trim_start_matches('\u{feff}').trim();
    if trimmed.is_empty() {
        return Ok(PreparedDanmakuTimeline {
            raw_count: 0,
            filtered_count: 0,
            items: Vec::new(),
        });
    }

    let raw_entries = if trimmed.starts_with('<') {
        parse_xml_entries(trimmed)
    } else {
        parse_json_entries(trimmed)?
    };
    let raw_count = raw_entries.len();

    let block_rules: Vec<BlockRule> = options
        .block_keywords
        .iter()
        .filter_map(|kw| BlockRule::parse(kw))
        .collect();

    let mut filtered: Vec<DanmakuItem> = Vec::with_capacity(raw_entries.len());
    for entry in raw_entries {
        let adjusted_time = entry.time_ms.saturating_add(options.offset_ms);
        if adjusted_time < 0 {
            continue;
        }
        let mode_allowed = match entry.mode {
            DanmakuMode::Scroll => options.allow_scroll,
            DanmakuMode::Top => options.allow_top,
            DanmakuMode::Bottom => options.allow_bottom,
        };
        if !mode_allowed {
            continue;
        }
        if !block_rules.is_empty() {
            let lower = entry.text.to_lowercase();
            if block_rules.iter().any(|rule| rule.matches(&lower)) {
                continue;
            }
        }
        let color_rgb = if options.allow_color {
            entry.color_rgb
        } else {
            WHITE_RGB
        };
        filtered.push(DanmakuItem {
            time_ms: adjusted_time,
            mode: entry.mode,
            color_rgb,
            text: entry.text,
            repeat_count: 1,
        });
    }

    filtered.sort_by_key(|item| item.time_ms);

    let merged = if options.merge_duplicates && options.merge_window_ms > 0 {
        merge_short_window_duplicates(filtered, options.merge_window_ms)
    } else {
        filtered
    };

    let throttled = if options.max_per_second > 0 {
        throttle_per_second(merged, options.max_per_second as usize)
    } else {
        merged
    };

    let filtered_count = throttled.len();
    Ok(PreparedDanmakuTimeline {
        raw_count,
        filtered_count,
        items: throttled,
    })
}

fn merge_short_window_duplicates(items: Vec<DanmakuItem>, window_ms: i64) -> Vec<DanmakuItem> {
    let mut out: Vec<DanmakuItem> = Vec::with_capacity(items.len());
    let mut last_seen: HashMap<(String, DanmakuMode), usize> = HashMap::new();
    for item in items {
        let key = (item.text.to_lowercase(), item.mode);
        if let Some(&idx) = last_seen.get(&key)
            && item.time_ms.saturating_sub(out[idx].time_ms) <= window_ms
        {
            out[idx].repeat_count = out[idx].repeat_count.saturating_add(1);
            continue;
        }
        let next_idx = out.len();
        out.push(item);
        last_seen.insert(key, next_idx);
    }
    out
}

fn throttle_per_second(items: Vec<DanmakuItem>, max_per_second: usize) -> Vec<DanmakuItem> {
    if items.is_empty() || max_per_second == 0 {
        return items;
    }
    let mut out: Vec<DanmakuItem> = Vec::with_capacity(items.len());
    let mut start = 0usize;
    while start < items.len() {
        let sec_bucket = items[start].time_ms / 1000;
        let mut end = start + 1;
        while end < items.len() && items[end].time_ms / 1000 == sec_bucket {
            end += 1;
        }
        let bucket_len = end - start;
        if bucket_len <= max_per_second {
            out.extend_from_slice(&items[start..end]);
        } else {
            // 高能帧优先保留合并计数高的热梗弹幕，随后恢复原有时间顺序
            let mut indices: Vec<usize> = (start..end).collect();
            indices.sort_by(|&a, &b| {
                items[b]
                    .repeat_count
                    .cmp(&items[a].repeat_count)
                    .then_with(|| a.cmp(&b))
            });
            indices.truncate(max_per_second);
            indices.sort_unstable();
            for idx in indices {
                out.push(items[idx].clone());
            }
        }
        start = end;
    }
    out
}

/// FFI 入口包装：接收原始载荷文本与过滤选项 JSON，输出 `PreparedDanmakuTimeline` JSON。
pub fn prepare_danmaku_timeline_json(
    raw_payload_json: &str,
    filter_options_json: &str,
) -> Result<String, String> {
    let options: DanmakuFilterOptions = if filter_options_json.trim().is_empty() {
        DanmakuFilterOptions::default()
    } else {
        serde_json::from_str(filter_options_json)
            .map_err(|e| format!("弹幕过滤选项 JSON 解析失败：{e}"))?
    };
    let timeline = prepare_danmaku_timeline(raw_payload_json, &options)?;
    serde_json::to_string(&timeline).map_err(|e| format!("弹幕时间线序列化失败：{e}"))
}

/// 跨端统一规范化手动搜索弹幕默认关键词与展示标题，避免三端字符串拼接逻辑漂移。
pub fn normalize_danmaku_query_title(
    series_name: Option<&str>,
    title: Option<&str>,
    season: Option<i32>,
    _episode: Option<i32>,
    file_name: Option<&str>,
) -> String {
    if let Some(series) = series_name.map(str::trim).filter(|s| !s.is_empty()) {
        let base = strip_filename_noise(series);
        if !base.is_empty() {
            if let Some(s) = season
                && s > 1
                && !base.contains(&format!("第{s}季"))
                && !base.to_ascii_lowercase().contains(&format!("season {s}"))
            {
                return format!("{base} 第{s}季");
            }
            return base;
        }
    }

    if let Some(t) = title.map(str::trim).filter(|s| !s.is_empty()) {
        let cleaned = strip_filename_noise(t);
        if !cleaned.is_empty() {
            return cleaned;
        }
    }

    if let Some(fname) = file_name.map(str::trim).filter(|s| !s.is_empty()) {
        let basename = fname.rsplit(['/', '\\']).next().unwrap_or(fname);
        let cleaned = strip_filename_noise(basename);
        if !cleaned.is_empty() {
            return cleaned;
        }
    }

    String::new()
}

fn strip_filename_noise(raw: &str) -> String {
    let mut s = raw.trim().to_string();
    // 剥离常见媒体扩展名
    for ext in [
        ".mkv", ".mp4", ".avi", ".mov", ".m4v", ".ts", ".m2ts", ".flv", ".webm", ".strm", ".iso",
    ] {
        let bytes = s.as_bytes();
        if bytes.len() > ext.len()
            && bytes[bytes.len() - ext.len()..].eq_ignore_ascii_case(ext.as_bytes())
        {
            s.truncate(bytes.len() - ext.len());
            break;
        }
    }

    // 剥离方括号/全角括号制作组标签
    let mut no_brackets = String::with_capacity(s.len());
    let mut depth_sq = 0usize;
    let mut depth_full = 0usize;
    for ch in s.chars() {
        match ch {
            '[' => depth_sq += 1,
            ']' => depth_sq = depth_sq.saturating_sub(1),
            '【' => depth_full += 1,
            '】' => depth_full = depth_full.saturating_sub(1),
            _ if depth_sq == 0 && depth_full == 0 => no_brackets.push(ch),
            _ => {}
        }
    }

    let replaced = no_brackets.replace(['.', '_'], " ");
    let mut tokens: Vec<&str> = Vec::new();
    for tok in replaced.split_whitespace() {
        let upper = tok.to_ascii_uppercase();
        if is_episode_or_release_token(&upper) {
            if !tokens.is_empty() {
                break;
            }
            continue;
        }
        tokens.push(tok);
    }

    let joined = tokens.join(" ").trim().to_string();
    if joined.is_empty() {
        s.trim().to_string()
    } else {
        joined
    }
}

fn is_episode_or_release_token(upper: &str) -> bool {
    if matches!(
        upper,
        "1080P"
            | "2160P"
            | "720P"
            | "4K"
            | "UHD"
            | "HDR"
            | "HDR10"
            | "DV"
            | "BLURAY"
            | "BDRIP"
            | "WEB-DL"
            | "WEBDL"
            | "WEBRIP"
            | "REMUX"
            | "X264"
            | "X265"
            | "H264"
            | "H265"
            | "HEVC"
            | "AV1"
            | "AAC"
            | "FLAC"
            | "DDP"
    ) {
        return true;
    }
    // 匹配 S01E02 / S1E1 / E01 等常见季集标记
    let bytes = upper.as_bytes();
    if bytes.len() >= 4
        && bytes[0] == b'S'
        && let Some(e_pos) = upper.find('E')
        && e_pos >= 2
        && e_pos + 1 < bytes.len()
        && upper[1..e_pos].bytes().all(|b| b.is_ascii_digit())
        && upper[e_pos + 1..].bytes().all(|b| b.is_ascii_digit())
    {
        return true;
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_compact_payload_applies_offset_and_filters_modes_and_color() {
        let payload = r#"{
            "success": true,
            "data": {
                "schema_version": 1,
                "episode_id": 1001,
                "count": 4,
                "items": [
                    [5000, 1, 16711680, "滚动红字", "bilibili"],
                    [1000, 5, 65280, "顶部绿字", "tencent"],
                    [3000, 4, 255, "底部蓝字", "iqiyi"],
                    [500, 1, 16777215, "偏移后变负被丢弃", ""]
                ]
            }
        }"#;
        let opts = DanmakuFilterOptions {
            allow_scroll: true,
            allow_top: true,
            allow_bottom: false,
            allow_color: false,
            merge_duplicates: false,
            max_per_second: 12,
            offset_ms: -600,
            ..Default::default()
        };
        let tl = prepare_danmaku_timeline(payload, &opts).unwrap();
        assert_eq!(tl.raw_count, 4);
        assert_eq!(tl.filtered_count, 2);
        assert_eq!(tl.items[0].time_ms, 400);
        assert_eq!(tl.items[0].mode, DanmakuMode::Top);
        assert_eq!(tl.items[0].color_rgb, WHITE_RGB);
        assert_eq!(tl.items[1].time_ms, 4400);
        assert_eq!(tl.items[1].mode, DanmakuMode::Scroll);
        assert_eq!(tl.items[1].color_rgb, WHITE_RGB);
    }

    #[test]
    fn parses_raw_dandanplay_json_and_bilibili_xml() {
        let dandan = r#"{
            "comments": [
                {"cid": 1, "p": "12.5,1,16777215,u1", "m": "前方高能"},
                {"cid": 2, "p": "2.25,5,16766720,u2", "m": "打卡"}
            ]
        }"#;
        let tl_json = prepare_danmaku_timeline(dandan, &DanmakuFilterOptions::default()).unwrap();
        assert_eq!(tl_json.filtered_count, 2);
        assert_eq!(tl_json.items[0].time_ms, 2250);
        assert_eq!(tl_json.items[0].mode, DanmakuMode::Top);
        assert_eq!(tl_json.items[1].time_ms, 12500);
        assert_eq!(tl_json.items[1].text, "前方高能");

        let xml = r#"<?xml version="1.0"?><i>
            <d p="3.5,4,25,16711680,1700000000,0,abc,1">A &amp; B &lt;3</d>
            <d p="1.0,1,25,16777215,1700000000,0,def,2">滚动XML</d>
        </i>"#;
        let tl_xml = prepare_danmaku_timeline(xml, &DanmakuFilterOptions::default()).unwrap();
        assert_eq!(tl_xml.filtered_count, 2);
        assert_eq!(tl_xml.items[0].time_ms, 1000);
        assert_eq!(tl_xml.items[0].text, "滚动XML");
        assert_eq!(tl_xml.items[1].time_ms, 3500);
        assert_eq!(tl_xml.items[1].mode, DanmakuMode::Bottom);
        assert_eq!(tl_xml.items[1].text, "A & B <3");
    }

    #[test]
    fn merges_short_window_duplicates_and_throttles_preferring_hot_items() {
        let payload = r#"[
            [1000, 1, 16777215, "普通1"],
            [1050, 1, 16777215, "普通2"],
            [1100, 1, 16777215, "哈哈哈"],
            [1200, 1, 16777215, "哈哈哈"],
            [1300, 1, 16777215, "哈哈哈"],
            [1400, 1, 16777215, "普通3"],
            [5000, 1, 16777215, "哈哈哈"]
        ]"#;
        let opts = DanmakuFilterOptions {
            merge_duplicates: true,
            merge_window_ms: 3000,
            max_per_second: 2,
            ..Default::default()
        };
        let tl = prepare_danmaku_timeline(payload, &opts).unwrap();
        // 第 1 秒桶内合并后剩 4 条（普通1x1, 普通2x1, 哈哈哈x3, 普通3x1），限流 2 条应优先保留 哈哈哈(x3) 与 普通1(x1)
        assert_eq!(tl.filtered_count, 3);
        assert_eq!(tl.items[0].text, "普通1");
        assert_eq!(tl.items[0].repeat_count, 1);
        assert_eq!(tl.items[1].text, "哈哈哈");
        assert_eq!(tl.items[1].repeat_count, 3);
        // 5000ms 超出 3000ms 窗口，作为新条保留
        assert_eq!(tl.items[2].time_ms, 5000);
        assert_eq!(tl.items[2].repeat_count, 1);
    }

    #[test]
    fn blocks_substrings_and_safe_regex_patterns() {
        let payload = r#"[
            [1000, 1, 16777215, "剧透警告：凶手是管家"],
            [2000, 1, 16777215, "SPAM-123-AD"],
            [3000, 1, 16777215, "正常观影弹幕"],
            [4000, 1, 16777215, "欢迎来到2026"]
        ]"#;
        let opts = DanmakuFilterOptions {
            block_keywords: vec!["剧透".to_string(), "/^spam*ad$|欢迎*2026$/".to_string()],
            ..Default::default()
        };
        let tl = prepare_danmaku_timeline(payload, &opts).unwrap();
        assert_eq!(tl.filtered_count, 1);
        assert_eq!(tl.items[0].text, "正常观影弹幕");
    }

    #[test]
    fn normalizes_query_title_across_series_movie_and_filename() {
        assert_eq!(
            normalize_danmaku_query_title(
                Some("葬送的芙莉莲"),
                Some("冒险的终点"),
                Some(1),
                Some(1),
                None
            ),
            "葬送的芙莉莲"
        );
        assert_eq!(
            normalize_danmaku_query_title(Some("鬼灭之刃"), None, Some(2), Some(3), None),
            "鬼灭之刃 第2季"
        );
        assert_eq!(
            normalize_danmaku_query_title(
                None,
                None,
                None,
                None,
                Some("/vol/[SubGroup] Frieren.S01E01.1080p.WEB-DL.mkv")
            ),
            "Frieren"
        );
    }

    #[test]
    fn ffi_json_wrapper_roundtrip() {
        let raw = r#"[[1500, 1, 16777215, "测试弹幕", "bilibili"]]"#;
        let out = prepare_danmaku_timeline_json(raw, "").unwrap();
        let parsed: PreparedDanmakuTimeline = serde_json::from_str(&out).unwrap();
        assert_eq!(parsed.filtered_count, 1);
        assert_eq!(parsed.items[0].mode, DanmakuMode::Scroll);
    }
}
