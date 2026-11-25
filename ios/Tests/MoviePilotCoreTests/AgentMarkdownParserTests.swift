import Testing

@testable import MoviePilotCore

@Suite("AgentMarkdownParser GFM 表格与块级解析测试")
struct AgentMarkdownParserTests {
  @Test("混合文本、GFM 表格与围栏代码块准确切分并保留列对齐")
  func parsesMixedTextTableAndCodeBlocks() throws {
    let md = """
      以下是当前下载任务汇总：

      | 片名 | 进度 | 大小 |
      | :--- | :---: | ---: |
      | 沙丘 2 | **88%** | 12.4 GB |
      | 蜘蛛侠 | `100%` | 8.7 GB |

      ```json
      {"ok": true}
      ```
      """
    let blocks = AgentMarkdownParser.parse(md)
    #expect(blocks.count == 3)
    #expect(blocks[0] == .text("以下是当前下载任务汇总："))
    guard case .table(let table) = blocks[1] else {
      Issue.record("期望第二个块为表格")
      return
    }
    #expect(table.headers == ["片名", "进度", "大小"])
    #expect(table.alignments == [.leading, .center, .trailing])
    #expect(
      table.rows == [
        ["沙丘 2", "**88%**", "12.4 GB"],
        ["蜘蛛侠", "`100%`", "8.7 GB"],
      ])
    #expect(blocks[2] == .code(language: "json", content: "{\"ok\": true}"))
  }

  @Test("单元格内转义竖线与行内代码竖线不会误拆列")
  func preservesEscapedAndInlineCodePipes() throws {
    let md = """
      规则 | 正则 | 示例
      --- | --- | ---
      分辨率 | `2160p|4K` | A \\| B
      缺失列行 | 仅两列
      """
    let blocks = AgentMarkdownParser.parse(md)
    #expect(blocks.count == 1)
    guard case .table(let table) = blocks[0] else {
      Issue.record("期望解析为单个表格")
      return
    }
    #expect(table.headers == ["规则", "正则", "示例"])
    #expect(table.rows.count == 2)
    #expect(table.rows[0] == ["分辨率", "`2160p|4K`", "A | B"])
    #expect(table.rows[1] == ["缺失列行", "仅两列", ""])
  }

  @Test("围栏代码块内的表格语法保持原样不被误解析")
  func ignoresTableSyntaxInsideCodeFence() {
    let md = """
      ```markdown
      | A | B |
      | --- | --- |
      | 1 | 2 |
      ```
      """
    let blocks = AgentMarkdownParser.parse(md)
    #expect(blocks.count == 1)
    if case .code(let lang, let content) = blocks[0] {
      #expect(lang == "markdown")
      #expect(content.contains("| A | B |"))
    } else {
      Issue.record("代码块内表格不应解析为表格块")
    }
  }

  @Test("普通竖线文本或列数不匹配的分隔行回退为文本")
  func invalidTableFallsBackToPlainText() {
    let md = """
      状态：正常 | 在线
      --- | --- | ---
      普通段落
      """
    let blocks = AgentMarkdownParser.parse(md)
    #expect(blocks.count == 1)
    if case .text(let content) = blocks[0] {
      #expect(content.contains("状态：正常 | 在线"))
    } else {
      Issue.record("列数不匹配时应回退为文本")
    }
  }
}
