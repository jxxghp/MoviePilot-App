//! 跨端统一 SSE（Server-Sent Events）流式帧解析器，服务 AI 智能助手与系统健康检查流。

use serde::{Deserialize, Serialize};

/// 单条已解析的 SSE 事件帧。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SseEvent {
    pub event: String,
    pub data: String,
    pub id: Option<String>,
    pub is_done: bool,
}

/// 增量式 SSE 流解析器，可容忍任意 TCP/HTTP 分块切割。
#[derive(Debug, Default)]
pub struct SseStreamParser {
    buffer: String,
}

impl SseStreamParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// 推入新接收的 UTF-8 片段，返回所有已完整闭合的事件帧。
    pub fn push_chunk(&mut self, chunk: &str) -> Vec<SseEvent> {
        self.buffer.push_str(&chunk.replace("\r\n", "\n"));
        let mut events = Vec::new();
        while let Some(pos) = self.buffer.find("\n\n") {
            let raw_frame = self.buffer[..pos].to_string();
            self.buffer.drain(..pos + 2);
            if let Some(ev) = Self::parse_frame(&raw_frame) {
                events.push(ev);
            }
        }
        events
    }

    /// 冲刷尾部剩余缓冲（连接自然关闭时调用）。
    pub fn finish(&mut self) -> Vec<SseEvent> {
        if self.buffer.trim().is_empty() {
            self.buffer.clear();
            return Vec::new();
        }
        let raw = std::mem::take(&mut self.buffer);
        Self::parse_frame(&raw).into_iter().collect()
    }

    fn parse_frame(frame: &str) -> Option<SseEvent> {
        let mut event_name = "message".to_string();
        let mut data_lines: Vec<&str> = Vec::new();
        let mut id: Option<String> = None;

        for line in frame.lines() {
            if line.is_empty() || line.starts_with(':') {
                continue;
            }
            if let Some(val) = line.strip_prefix("event:") {
                event_name = val.trim().to_string();
            } else if let Some(val) = line.strip_prefix("data:") {
                data_lines.push(val.strip_prefix(' ').unwrap_or(val));
            } else if let Some(val) = line.strip_prefix("id:") {
                id = Some(val.trim().to_string());
            }
        }

        if data_lines.is_empty() && event_name == "message" {
            return None;
        }
        let data = data_lines.join("\n");
        let is_done = event_name == "done" || data.trim() == "[DONE]";
        Some(SseEvent {
            event: event_name,
            data,
            id,
            is_done,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn parses_split_sse_frames_from_shared_fixture() {
        let path =
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../fixtures/api/cases.json");
        let root: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let mut parser = SseStreamParser::new();
        let mut all = Vec::new();
        for frame in root["sseFrames"].as_array().unwrap() {
            let s = frame.as_str().unwrap();
            // 故意按中间切片验证流式缓冲拼接
            let mid = s.len() / 2;
            let split = s.floor_char_boundary(mid);
            all.extend(parser.push_chunk(&s[..split]));
            all.extend(parser.push_chunk(&s[split..]));
        }
        assert_eq!(all.len(), 4);
        assert_eq!(all[0].event, "thinking");
        assert_eq!(all[1].event, "tool_call");
        assert_eq!(all[2].event, "message");
        assert!(all[3].is_done);
    }
}
