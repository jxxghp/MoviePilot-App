//! AI 智能助手流式 Markdown 块级 AST 解析器：支持未闭合代码块（SSE 流式场景）、标题、列表、引用与表格。

use serde::{Deserialize, Serialize};

/// Markdown 块级节点类型。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MarkdownBlockKind {
    Heading,
    Paragraph,
    BulletList,
    OrderedList,
    CodeBlock,
    Blockquote,
    Table,
    ThematicBreak,
}

/// 扁平化 Markdown 块级节点，供三端原生 UI 零解析损耗直接渲染。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MarkdownBlock {
    pub kind: MarkdownBlockKind,
    pub level: u8,
    pub language: Option<String>,
    pub text: String,
    pub items: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

/// 跨端统一 AI 流式 Markdown 解析器。
pub struct AgentMarkdownParser;

impl AgentMarkdownParser {
    /// 将流式或完整 Markdown 文本解析为块级节点列表。
    pub fn parse(source: &str) -> Vec<MarkdownBlock> {
        let owned: Vec<String> = source
            .replace("\r\n", "\n")
            .lines()
            .map(str::to_string)
            .collect();
        Self::parse_lines(&owned)
    }

    fn parse_lines(lines: &[String]) -> Vec<MarkdownBlock> {
        let mut blocks = Vec::new();
        let mut i = 0;
        let n = lines.len();

        while i < n {
            let line = lines[i].as_str();
            let trimmed = line.trim();
            if trimmed.is_empty() {
                i += 1;
                continue;
            }

            // 围栏代码块（容忍 SSE 流式输出时未闭合尾部）
            if let Some(rest) = trimmed.strip_prefix("```") {
                let lang = rest.trim();
                let language = if lang.is_empty() {
                    None
                } else {
                    Some(lang.to_string())
                };
                let mut code_lines = Vec::new();
                i += 1;
                while i < n && !lines[i].trim().starts_with("```") {
                    code_lines.push(lines[i].as_str());
                    i += 1;
                }
                if i < n {
                    i += 1;
                }
                blocks.push(MarkdownBlock {
                    kind: MarkdownBlockKind::CodeBlock,
                    level: 0,
                    language,
                    text: code_lines.join("\n"),
                    items: Vec::new(),
                    rows: Vec::new(),
                });
                continue;
            }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.push(MarkdownBlock {
                    kind: MarkdownBlockKind::ThematicBreak,
                    level: 0,
                    language: None,
                    text: String::new(),
                    items: Vec::new(),
                    rows: Vec::new(),
                });
                i += 1;
                continue;
            }

            // 标题 (# .. ######)
            if trimmed.starts_with('#') {
                let hashes = trimmed.chars().take_while(|&c| c == '#').count();
                if hashes <= 6 && trimmed.as_bytes().get(hashes) == Some(&b' ') {
                    blocks.push(MarkdownBlock {
                        kind: MarkdownBlockKind::Heading,
                        level: hashes as u8,
                        language: None,
                        text: trimmed[hashes + 1..].trim().to_string(),
                        items: Vec::new(),
                        rows: Vec::new(),
                    });
                    i += 1;
                    continue;
                }
            }

            // 引用块
            if trimmed.starts_with('>') {
                let mut quote_lines = Vec::new();
                while i < n && lines[i].trim().starts_with('>') {
                    quote_lines.push(lines[i].trim().trim_start_matches('>').trim().to_string());
                    i += 1;
                }
                blocks.push(MarkdownBlock {
                    kind: MarkdownBlockKind::Blockquote,
                    level: 0,
                    language: None,
                    text: quote_lines.join("\n"),
                    items: Vec::new(),
                    rows: Vec::new(),
                });
                continue;
            }

            // GFM 表格
            if trimmed.starts_with('|')
                && i + 1 < n
                && Self::is_table_separator(lines[i + 1].trim())
            {
                let mut rows = vec![Self::split_table_row(trimmed)];
                i += 2;
                while i < n && lines[i].trim().starts_with('|') {
                    rows.push(Self::split_table_row(lines[i].trim()));
                    i += 1;
                }
                blocks.push(MarkdownBlock {
                    kind: MarkdownBlockKind::Table,
                    level: 0,
                    language: None,
                    text: String::new(),
                    items: Vec::new(),
                    rows,
                });
                continue;
            }

            // 无序列表
            if Self::strip_bullet(trimmed).is_some() {
                let mut items = Vec::new();
                while i < n {
                    if let Some(item) = Self::strip_bullet(lines[i].trim()) {
                        items.push(item.to_string());
                        i += 1;
                    } else {
                        break;
                    }
                }
                blocks.push(MarkdownBlock {
                    kind: MarkdownBlockKind::BulletList,
                    level: 0,
                    language: None,
                    text: String::new(),
                    items,
                    rows: Vec::new(),
                });
                continue;
            }

            // 有序列表
            if Self::strip_ordered(trimmed).is_some() {
                let mut items = Vec::new();
                while i < n {
                    if let Some(item) = Self::strip_ordered(lines[i].trim()) {
                        items.push(item.to_string());
                        i += 1;
                    } else {
                        break;
                    }
                }
                blocks.push(MarkdownBlock {
                    kind: MarkdownBlockKind::OrderedList,
                    level: 0,
                    language: None,
                    text: String::new(),
                    items,
                    rows: Vec::new(),
                });
                continue;
            }

            // 普通段落
            let mut para = Vec::new();
            while i < n {
                let cur = lines[i].trim();
                if cur.is_empty()
                    || cur.starts_with("```")
                    || cur.starts_with('#')
                    || cur.starts_with('>')
                    || Self::strip_bullet(cur).is_some()
                    || Self::strip_ordered(cur).is_some()
                {
                    break;
                }
                para.push(cur.to_string());
                i += 1;
            }
            blocks.push(MarkdownBlock {
                kind: MarkdownBlockKind::Paragraph,
                level: 0,
                language: None,
                text: para.join("\n"),
                items: Vec::new(),
                rows: Vec::new(),
            });
        }

        blocks
    }

    fn strip_bullet(s: &str) -> Option<&str> {
        s.strip_prefix("- ")
            .or_else(|| s.strip_prefix("* "))
            .or_else(|| s.strip_prefix("• "))
    }

    fn strip_ordered(s: &str) -> Option<&str> {
        let digits = s.chars().take_while(|c| c.is_ascii_digit()).count();
        if digits == 0 {
            return None;
        }
        s[digits..].strip_prefix(". ")
    }

    fn is_table_separator(s: &str) -> bool {
        s.starts_with('|') && s.contains("---")
    }

    fn split_table_row(s: &str) -> Vec<String> {
        s.trim_matches('|')
            .split('|')
            .map(|cell| cell.trim().to_string())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn passes_shared_markdown_golden_fixtures() {
        let fixture_path =
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../fixtures/markdown/cases.json");
        let text = std::fs::read_to_string(&fixture_path).expect("读取 markdown 夹具失败");
        let root: serde_json::Value = serde_json::from_str(&text).unwrap();
        for case in root["cases"].as_array().unwrap() {
            let input = case["input"].as_str().unwrap();
            let blocks = AgentMarkdownParser::parse(input);
            let actual: Vec<String> = blocks
                .iter()
                .map(|b| {
                    serde_json::to_value(&b.kind)
                        .unwrap()
                        .as_str()
                        .unwrap()
                        .to_string()
                })
                .collect();
            let expected: Vec<String> = case["expectedKinds"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_str().unwrap().to_string())
                .collect();
            assert_eq!(actual, expected, "case={}", case["name"]);
        }
    }
}
