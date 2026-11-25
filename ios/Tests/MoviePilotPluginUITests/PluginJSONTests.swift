import Foundation
import Testing

@testable import MoviePilotPluginUI

/// 配置保真和不可信输入边界，不使用 Double 近似数值或把错误文档当作空值。
struct PluginJSONTests {
  /// 类型、未知字段、超大整数、小数词法、指数和负零均保持可编码/重读。
  @Test func preservesValuesAndNumberLexemes() throws {
    let input =
      #"{"unknown":{"array":[false,null,"false",9007199254740993,-0,1.2300,1e+400]},"空":"","unicode":"电影🎬"}"#
    let value = try PluginJSONReader.parse(Data(input.utf8))
    let items = try #require(value.object?["unknown"]?.object?["array"]?.array)
    #expect(
      items == [
        .bool(false), .null, .string("false"), .number(try .init("9007199254740993")),
        .number(try .init("-0")), .number(try .init("1.2300")), .number(try .init("1e+400")),
      ])
    let encoded = try value.encoded()
    #expect(try PluginJSONReader.parse(encoded) == value)
    let output = try #require(String(data: encoded, encoding: .utf8))
    for number in ["9007199254740993", "-0", "1.2300", "1e+400"] {
      #expect(output.contains(number))
    }
  }

  /// 标准字符串转义、代理对和嵌套空容器完整保留。
  @Test func supportsEscapesAndUnicode() throws {
    let input = #"["\"\\\/\b\f\n\r\t\u0000\uD83C\uDFAC",{},[],true,false,null]"#
    let value = try PluginJSONReader.parse(Data(input.utf8))
    #expect(value.array?.first == .string("\"\\/\u{8}\u{c}\n\r\t\u{0}🎬"))
    #expect(try PluginJSONReader.parse(value.encoded()) == value)
  }

  /// 不是 JSON 的常量、数字、分隔、尾随内容和不成对 Unicode 不能进入模型。
  @Test(arguments: [
    "", " ", "NaN", "Infinity", "+1", "01", "-.1", "1.", "1e", "1e+", "--1", "1-2",
    "[1,]", "[,1]", "[1 2]", "{\"a\":1,}", "{a:1}", "true false", "nullx",
    "\"\\x20\"", "\"\\uD800\"", "\"\\uDC00\"", "\"line\nfeed\"", "\"unterminated",
    "\u{feff}{}",
  ])
  func rejectsMalformedJSON(_ input: String) {
    #expect(throws: PluginJSONError.self) { try PluginJSONReader.parse(Data(input.utf8)) }
  }

  /// 非 UTF-8 在语法扫描前失败。
  @Test func rejectsInvalidUTF8() {
    #expect(throws: PluginJSONError.invalidUTF8) {
      try PluginJSONReader.parse(Data([0x22, 0xFF, 0x22]))
    }
  }

  /// 转义后相同的键仍是重复键，不能被 Dictionary 静默覆盖。
  @Test(arguments: [#"{"a":null,"a":1}"#, #"{"a":1,"\u0061":2}"#, #"[{"x":1,"x":2}]"#])
  func rejectsDuplicateKeys(_ input: String) {
    do {
      _ = try PluginJSONReader.parse(Data(input.utf8))
      Issue.record("重复键未被拒绝")
    } catch PluginJSONError.duplicateKey {} catch { Issue.record("错误类别不正确：\(type(of: error))") }
  }

  /// Swift 规范等价键发生冲突时整体拒绝，绑定查询仍按原始序列区分。
  @Test func treatsObjectKeysExactly() throws {
    let input = "{\"é\":1,\"e\\u0301\":2}"
    do {
      _ = try PluginJSONReader.parse(Data(input.utf8))
      Issue.record("规范等价键冲突未被拒绝")
    } catch PluginJSONError.ambiguousUnicodeKey {}
    let value = try PluginJSONReader.parse(Data("{\"é\":1}".utf8))
    #expect(value[exactKey: "é"] != nil)
    #expect(value[exactKey: "e\u{301}"] == nil)
  }

  /// 预算在精确边界处成立，多一个字节、值、深度或词法字符即拒绝。
  @Test func enforcesEveryBudgetOnReadAndWrite() throws {
    let limit = try PluginJSONLimits(
      maximumBytes: 9, maximumDepth: 1, maximumValues: 3,
      maximumStringBytes: 2, maximumNumberBytes: 2)
    #expect(try PluginJSONReader.parse(Data("[12,\"ab\"]".utf8), limits: limit).array?.count == 2)
    try expectLimit(.bytes, input: "[12,\"abc\"]", limits: limit)
    try expectLimit(.depth, input: "[[0]]", limits: limit)
    try expectLimit(.values, input: "[0,1,2]", limits: limit)
    try expectLimit(.stringBytes, input: "\"abc\"", limits: limit)
    try expectLimit(.numberBytes, input: "123", limits: limit)
    try expectLimit(.stringBytes, input: #""\u0061""#, limits: limit)
    let safe = try PluginJSONReader.parse(Data("[12,\"ab\"]".utf8))
    #expect(try safe.encoded(limits: limit).count == 9)
    let cases: [(PluginJSONLimit, PluginJSONValue)] = [
      (.bytes, .array([.string("ab"), .string("ab")])),
      (.depth, .array([.array([.null])])),
      (
        .values,
        .array([.number(try .init("0")), .number(try .init("0")), .number(try .init("0"))])
      ),
      (.stringBytes, .string("abc")), (.stringBytes, .string("\u{0}")),
      (.numberBytes, .number(try .init("123"))),
    ]
    for (expected, value) in cases {
      do {
        _ = try value.encoded(limits: limit)
        Issue.record("编码预算未生效")
      } catch PluginJSONError.limitExceeded(let actual, _) { #expect(actual == expected) }
    }
  }

  /// 不可信深嵌套在进入系统通用 JSON 解码器前被有界扫描器截断。
  @Test func boundsVeryDeepInput() throws {
    let input = String(repeating: "[", count: 10_000) + "0" + String(repeating: "]", count: 10_000)
    try expectLimit(.depth, input: input, limits: .standard)
  }

  /// 不能通过自定义负数/超大预算或伪造数值词法绕过标准边界。
  @Test func validatesLimitConfigurationAndNumberConstruction() throws {
    #expect(throws: PluginJSONError.invalidLimits) {
      try PluginJSONLimits(
        maximumBytes: 0, maximumDepth: 1, maximumValues: 1,
        maximumStringBytes: 1, maximumNumberBytes: 1)
    }
    #expect(throws: PluginJSONError.invalidLimits) {
      try PluginJSONLimits(
        maximumBytes: 1, maximumDepth: 129, maximumValues: 1,
        maximumStringBytes: 1, maximumNumberBytes: 1)
    }
    for number in ["", "01", "+1", "1e+", "1 2", "NaN", String(repeating: "1", count: 1025)] {
      #expect(throws: PluginJSONError.self) { try PluginJSONNumber(number) }
    }
    for number in ["0", "-0", "0.0", "-1.2E-4", "9007199254740993"] {
      #expect(try PluginJSONNumber(number).rawValue == number)
    }
  }

  /// 已取消任务必须由解析/编码入口本身拒绝，不依赖测试睡眠或外围超时。
  @Test func checksTaskCancellation() async throws {
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try PluginJSONReader.parse(Data("{}".utf8))
        return false
      } catch is CancellationError {
        do {
          _ = try PluginJSONValue.null.encoded()
          return false
        } catch is CancellationError { return true }
      }
    }
    #expect(try await task.value)
  }

  /// 错误不能包含敏感正文，调用方只拿到类别和偏移。
  @Test func errorDoesNotEchoContent() {
    do {
      _ = try PluginJSONReader.parse(Data(#"{"token":"private-fixture","x":]}"#.utf8))
      Issue.record("非法 JSON 未被拒绝")
    } catch {
      #expect(!String(describing: error).contains("private-fixture"))
    }
  }

  /// 空白长循环也响应取消，不仅依靠外层网络任务停止。
  @Test func checksCancellationWithinWhitespace() async throws {
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      var scanner = PluginJSONScanner(
        bytes: Array(String(repeating: " ", count: 2048).utf8), limits: .standard)
      try scanner.whitespace()
    }
    do {
      try await task.value
      Issue.record("空白扫描取消未生效")
    } catch is CancellationError {}
  }

  /// 独立系统编码器生成的容器/Unicode/控制字符语料，再由系统解析器反向核对。
  @Test func acceptsIndependentFoundationEncodedCorpus() throws {
    for index in 0..<100 {
      let object: [String: Any] = [
        "index": index, "enabled": index % 2 == 0, "nil": NSNull(),
        "array": ["电影🎬", "é", "e\u{301}", "\"\\\n\u{0}", String(index)],
        "nested": ["a/~": [index, -index, index + 1], "object": [:]] as [String: Any],
      ]
      let input = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
      let value = try PluginJSONReader.parse(input)
      let output = try value.encoded()
      let reference = try JSONSerialization.jsonObject(with: output) as? NSDictionary
      #expect(reference?.isEqual(to: object) == true)
      #expect(try PluginJSONReader.parse(output) == value)
    }
  }

  /// 确认失败确实来自对应预算而不是其它语法问题。
  private func expectLimit(_ kind: PluginJSONLimit, input: String, limits: PluginJSONLimits) throws
  {
    do {
      _ = try PluginJSONReader.parse(Data(input.utf8), limits: limits)
      Issue.record("预算未生效")
    } catch PluginJSONError.limitExceeded(let actual, _) { #expect(actual == kind) }
  }
}
