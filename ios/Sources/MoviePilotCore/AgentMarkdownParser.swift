import Foundation

/// GFM 表格列对齐方式。
public enum AgentMarkdownColumnAlignment: String, Equatable, Sendable {
  case leading
  case center
  case trailing
}

/// 解析后的 GFM 表格结构，所有行已按表头列数归一化。
public struct AgentMarkdownTable: Equatable, Sendable {
  /// 表头单元格文本列表。
  public let headers: [String]
  /// 各列对齐方式，长度与 `headers` 一致。
  public let alignments: [AgentMarkdownColumnAlignment]
  /// 数据行列表，每行长度均与 `headers` 一致。
  public let rows: [[String]]

  public init(
    headers: [String],
    alignments: [AgentMarkdownColumnAlignment],
    rows: [[String]]
  ) {
    self.headers = headers
    self.alignments = alignments
    self.rows = rows
  }
}

/// Agent 对话消息的块级 Markdown 元素。
public enum AgentMarkdownBlock: Equatable, Sendable {
  case text(String)
  case code(language: String, content: String)
  case table(AgentMarkdownTable)
}

/// 将 Agent 对话 Markdown 拆分为文本段落、围栏代码块与 GFM 表格块。
public enum AgentMarkdownParser {
  /// 解析完整或流式进行中的 Markdown 文本。
  public static func parse(_ markdown: String) -> [AgentMarkdownBlock] {
    let lines = splitLines(markdown)
    var blocks: [AgentMarkdownBlock] = []
    var textBuffer: [String] = []
    var codeBuffer: [String] = []
    var inCode = false
    var codeLang = ""

    func flushText() {
      let joined = textBuffer.joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !joined.isEmpty {
        blocks.append(.text(joined))
      }
      textBuffer.removeAll()
    }

    var index = 0
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("```") {
        if inCode {
          blocks.append(.code(language: codeLang, content: codeBuffer.joined(separator: "\n")))
          codeBuffer.removeAll()
          codeLang = ""
          inCode = false
        } else {
          flushText()
          codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          inCode = true
        }
        index += 1
        continue
      }

      if inCode {
        codeBuffer.append(line)
        index += 1
        continue
      }

      if let parsed = parseTable(lines: lines, startIndex: index) {
        flushText()
        blocks.append(.table(parsed.table))
        index = parsed.nextIndex
        continue
      }

      textBuffer.append(line)
      index += 1
    }

    if inCode {
      blocks.append(.code(language: codeLang, content: codeBuffer.joined(separator: "\n")))
    } else {
      flushText()
    }
    return blocks
  }

  /// 兼容 `\r\n`、`\r` 与 `\n` 换行符拆行。
  private static func splitLines(_ raw: String) -> [String] {
    let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    return normalized.components(separatedBy: "\n")
  }

  /// 尝试从 `startIndex` 起解析标准 GFM 表格（表头行 + 对齐分隔行 + 0..N 数据行）。
  private static func parseTable(
    lines: [String],
    startIndex: Int
  ) -> (table: AgentMarkdownTable, nextIndex: Int)? {
    guard startIndex + 1 < lines.count else { return nil }
    let headerLine = lines[startIndex]
    let delimiterLine = lines[startIndex + 1]

    guard looksLikePipeRow(headerLine), looksLikePipeRow(delimiterLine) else {
      return nil
    }

    let headers = splitTableCells(headerLine)
    guard !headers.isEmpty,
      let alignments = parseDelimiterCells(delimiterLine),
      alignments.count == headers.count
    else {
      return nil
    }

    var rows: [[String]] = []
    var cursor = startIndex + 2
    while cursor < lines.count {
      let candidate = lines[cursor]
      let trimmed = candidate.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty
        || trimmed.hasPrefix("```")
        || trimmed.hasPrefix("#")
        || trimmed.hasPrefix(">")
        || !looksLikePipeRow(candidate)
      {
        break
      }
      var cells = splitTableCells(candidate)
      if cells.count < headers.count {
        cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
      } else if cells.count > headers.count {
        cells = Array(cells.prefix(headers.count))
      }
      rows.append(cells)
      cursor += 1
    }

    return (AgentMarkdownTable(headers: headers, alignments: alignments, rows: rows), cursor)
  }

  /// 判断单行是否包含未转义的表格竖线分隔符。
  private static func looksLikePipeRow(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.contains("|") else { return false }
    var escaped = false
    var inInlineCode = false
    for ch in trimmed {
      if escaped {
        escaped = false
        continue
      }
      if ch == "\\" {
        escaped = true
        continue
      }
      if ch == "`" {
        inInlineCode.toggle()
        continue
      }
      if ch == "|" && !inInlineCode {
        return true
      }
    }
    return false
  }

  /// 按 GFM 规则拆分单行单元格，正确忽略反引号代码内及 `\|` 转义的竖线。
  private static func splitTableCells(_ line: String) -> [String] {
    var trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("|") {
      trimmed.removeFirst()
    }
    if trimmed.hasSuffix("|") && !hasUnescapedTrailingBackslashBeforePipe(trimmed) {
      trimmed.removeLast()
    }

    var cells: [String] = []
    var current = ""
    var escaped = false
    var inInlineCode = false

    for ch in trimmed {
      if escaped {
        if ch == "|" {
          current.append("|")
        } else {
          current.append("\\")
          current.append(ch)
        }
        escaped = false
        continue
      }
      if ch == "\\" {
        escaped = true
        continue
      }
      if ch == "`" {
        inInlineCode.toggle()
        current.append(ch)
        continue
      }
      if ch == "|" && !inInlineCode {
        cells.append(current.trimmingCharacters(in: .whitespaces))
        current.removeAll(keepingCapacity: true)
      } else {
        current.append(ch)
      }
    }
    if escaped {
      current.append("\\")
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
  }

  /// 检查末尾 `|` 是否被奇数个反斜杠转义（如 `foo\|` 属于单元格内容而非外边框）。
  private static func hasUnescapedTrailingBackslashBeforePipe(_ text: String) -> Bool {
    guard text.hasSuffix("|") else { return false }
    var backslashes = 0
    var idx = text.index(before: text.endIndex)
    while idx > text.startIndex {
      idx = text.index(before: idx)
      if text[idx] == "\\" {
        backslashes += 1
      } else {
        break
      }
    }
    return backslashes % 2 == 1
  }

  /// 解析分隔行单元格并提取列对齐方式；任意一列非法则返回 `nil`。
  private static func parseDelimiterCells(_ line: String) -> [AgentMarkdownColumnAlignment]? {
    let rawCells = splitTableCells(line)
    guard !rawCells.isEmpty else { return nil }
    var alignments: [AgentMarkdownColumnAlignment] = []
    alignments.reserveCapacity(rawCells.count)

    for cell in rawCells {
      guard !cell.isEmpty else { return nil }
      let hasLeadingColon = cell.hasPrefix(":")
      let hasTrailingColon = cell.hasSuffix(":")
      var inner = cell[...]
      if hasLeadingColon { inner = inner.dropFirst() }
      if hasTrailingColon && !inner.isEmpty { inner = inner.dropLast() }
      guard !inner.isEmpty, inner.allSatisfy({ $0 == "-" }) else {
        return nil
      }
      if hasLeadingColon && hasTrailingColon {
        alignments.append(.center)
      } else if hasTrailingColon {
        alignments.append(.trailing)
      } else {
        alignments.append(.leading)
      }
    }
    return alignments
  }
}
