import Foundation
import MoviePilotPluginUI
import Testing

@testable import MoviePilotPluginForms

/// 原生 Cron 只构造/保留输入，不在手机调度任务或强制所有插件使用同一种语法。
@Suite struct NativeCronTests {
  /// 构造器每个语料先经 APScheduler 3 独立解析，Swift 输出必须逐字相同。
  @Test func matchesBackendValidatedConstructorCorpus() throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "cron-constructors", withExtension: "json", subdirectory: "Fixtures"))
    let corpus = try JSONDecoder().decode(CronCorpus.self, from: Data(contentsOf: url))
    #expect(corpus.version.hasPrefix("3."))
    #expect(corpus.cases.count > 500)
    for item in corpus.cases {
      let unit = try #require(NativeCronUnit(rawValue: item.unit))
      let token = try item.rule().token(for: unit)
      #expect(token == item.token)
      var parts = ["0", "0", "*", "*", "*"]
      parts[unit.index] = token
      #expect(parts.joined(separator: " ") == item.expression)
      #expect(NativeCronExpression(item.expression).format == .fiveFields)
    }
  }

  /// 默认、别名、前导零、重复值和混合范围原样应用不能被规范化。
  @Test(arguments: [
    (NativeCronUnit.minute, "001,003,001"), (.day, "*/7"), (.month, "JAN-MAR"),
    (.weekday, "MoN-FrI"), (.weekday, "0,2,6"), (.minute, "0-30/5,45"),
    (.day, "last"), (.minute, "plugin-specific"),
  ])
  func preservesUneditedField(_ unit: NativeCronUnit, _ token: String) throws {
    let draft = NativeCronFieldDraft(unit: unit, token: token)
    #expect(try draft.token().utf8.elementsEqual(token.utf8))
  }

  /// 取消/原样应用可视化字段保留完整表达式的空格、大小写和前导零。
  @Test func preservesRawExpressionUntilExplicitFieldChange() throws {
    let text = "  001\t09  *  JAN-MAR  MoN-FrI \n"
    let expression = NativeCronExpression(text)
    #expect(expression.format == .fiveFields)
    let fields = try #require(expression.fields)
    for unit in NativeCronUnit.allCases {
      let draft = NativeCronFieldDraft(unit: unit, token: fields[unit.index])
      #expect(try expression.replacing(unit, with: draft.token()).utf8.elementsEqual(text.utf8))
    }
    let changed = try expression.replacing(
      .weekday, with: NativeCronRule.values([6, 0]).token(for: .weekday))
    #expect(changed == "001 09 * JAN-MAR mon,sun")
  }

  /// 选择恢复到相同集合后，仍返回原始顺序/重复/词法而非重排父配置。
  @Test func restoresOriginalTokenWhenSelectionReturnsToOriginalSet() throws {
    var draft = NativeCronFieldDraft(unit: .minute, token: "005,001,005")
    draft.rule = .values([1, 5])
    #expect(try draft.token() == "005,001,005")
    draft.rule = .values([1, 5, 10])
    #expect(try draft.token() == "1,5,10")
  }

  /// 生成器用内部 Monday=0 索引发出名称；原始数字 token 仍由插件方言解释。
  @Test func usesExplicitWeekdayNames() throws {
    #expect(try NativeCronRule.values([0, 6]).token(for: .weekday) == "mon,sun")
    #expect(try NativeCronRule.range(0, 4).token(for: .weekday) == "mon-fri")
    #expect(try NativeCronRule.step(start: 0, every: 2).token(for: .weekday) == "mon,wed,fri,sun")
    #expect(NativeCronFieldDraft(unit: .weekday, token: "0").rule == .custom("0"))
    #expect(NativeCronFieldDraft(unit: .weekday, token: "sun").rule == .values([6]))
  }

  /// 实际插件存在 Sunday=0/7 与 Monday=0 两种解释，不能将数字原文预选为某一天。
  @Test(arguments: ["0", "1", "6", "7", "0,2,6", "1-5", "*/2", "0-7", "mon,2"])
  func keepsNumericWeekdayAsCustom(_ token: String) throws {
    let draft = NativeCronFieldDraft(unit: .weekday, token: token)
    #expect(draft.rule == .custom(token))
    #expect(try draft.token().utf8.elementsEqual(token.utf8))
    #expect(NativeCronExpression("0 3 * * " + token).format == .custom)
    #expect(NativeCronExpression("0 3 * * " + token).hasAmbiguousWeekday)
  }

  /// 只有数字星期需要方言说明；无改应用保留整个空白/原数字，明确选择才生成新名称。
  @Test func preservesAmbiguousWeekdayAndSeparatesExplicitChoice() throws {
    let source = "  0  3 * * 0  "
    let expression = NativeCronExpression(source)
    #expect(try expression.replacing(.weekday, with: "0").utf8.elementsEqual(source.utf8))
    #expect(
      try expression.replacing(.weekday, with: NativeCronRule.values([6]).token(for: .weekday))
        == "0 3 * * sun")
    for token in ["*", "mon", "sun", "mon-fri", "mon,wed,fri"] {
      let named = NativeCronExpression("0 3 * * " + token)
      #expect(!named.hasAmbiguousWeekday)
      #expect(named.format == .fiveFields)
    }
    #expect(!NativeCronExpression("6").hasAmbiguousWeekday)
  }

  /// 范围/步长/空选集在构造器内被拒绝，不等到网络请求后才发现。
  @Test func rejectsInvalidConstructedRules() throws {
    let cases: [(NativeCronUnit, NativeCronRule)] = [
      (.minute, .values([])), (.minute, .values([-1])), (.minute, .values([60])),
      (.hour, .range(20, 10)), (.month, .range(0, 12)), (.weekday, .values([7])),
      (.minute, .step(start: nil, every: 0)), (.minute, .step(start: nil, every: 60)),
      (.minute, .step(start: 59, every: 1)), (.day, .step(start: 0, every: 1)),
      (.month, .step(start: nil, every: 12)), (.minute, .lastDay),
      (.day, .custom("1 2")), (.day, .custom("")), (.day, .custom("last\u{0}")),
    ]
    for (unit, rule) in cases { #expect(throws: (any Error).self) { try rule.token(for: unit) } }
    #expect(try NativeCronRule.lastDay.token(for: .day) == "last")
  }

  /// 插件间隔、特殊方言、过长值和未知输入不被当成五字段，也不能被丢弃。
  @Test(arguments: [
    "6", "1.5", "@daily", "0 0 ? * *", "0 0 * * 7", "0 0 * * mon-fri/2", "Cron(x)",
    String(repeating: "*", count: 2048),
  ])
  func keepsCustomOriginalText(_ text: String) throws {
    let expression = NativeCronExpression(text)
    #expect(expression.rawValue.utf8.elementsEqual(text.utf8))
    #expect(expression.format == .custom)
  }

  /// 空白表达式仅显示默认提示，不生成通配周期；非五段值不能局部改写。
  @Test func distinguishesEmptyAndNonFiveFieldValues() throws {
    for text in ["", " \t\n"] {
      let expression = NativeCronExpression(text)
      #expect(expression.format == .empty)
      #expect(expression.fields == nil)
      #expect(expression.rawValue == text)
    }
    #expect(throws: NativeCronError.notFiveFields) {
      try NativeCronExpression("6").replacing(.minute, with: "1")
    }
    #expect(throws: NativeCronError.invalidToken) {
      try NativeCronExpression("* * * * *").replacing(.minute, with: "1 2")
    }
  }

  /// Unicode 规范等价不能掩盖用户真的改变了自定义 token 的字节。
  @Test func preservesCustomUnicodeByteChanges() throws {
    var draft = NativeCronFieldDraft(unit: .minute, token: "é")
    draft.rule = .custom("e\u{301}")
    #expect(try draft.token().utf8.elementsEqual("e\u{301}".utf8))
    let expression = NativeCronExpression("é * * * *")
    #expect(
      try expression.replacing(.minute, with: "e\u{301}").utf8.elementsEqual(
        "e\u{301} * * * *".utf8))
  }

  /// 全部预设均为明确五段表达式；构造器解析不执行或注册任何任务。
  @Test func recognizesEveryExplicitPreset() {
    for preset in NativeCronPreset.allCases {
      #expect(NativeCronExpression(preset.expression).format == .fiveFields)
      #expect(NativeCronExpression(preset.expression).fields?.count == 5)
    }
  }
}

/// 语料仅含公开格式数据与参考解析器摘要，没有用户配置或运行时间。
private struct CronCorpus: Decodable {
  let version: String
  let cases: [CronConstructorCase]
}

/// 用例输入先转换成真正原生规则，再与独立参考输出比较。
private struct CronConstructorCase: Decodable {
  let unit: String
  let kind: String
  let values: [Int]?
  let first: Int?
  let last: Int?
  let start: Int?
  let every: Int?
  let token: String
  let expression: String

  /// 缺参数或未知用例直接失败，不能过滤坏语料而获得假通过。
  func rule() throws -> NativeCronRule {
    switch kind {
    case "every": return .every
    case "values": return .values(try #require(values))
    case "range": return .range(try #require(first), try #require(last))
    case "step": return .step(start: start, every: try #require(every))
    case "lastDay": return .lastDay
    default: throw NativeCronError.invalidToken
    }
  }
}
