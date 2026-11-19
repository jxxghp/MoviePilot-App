import Foundation
import MoviePilotPluginUI
import Testing

@testable import MoviePilotPluginForms

/// 有界数据表达式不引入 JavaScript 引擎，同时验证常用旧条件的实际语义。
@Suite struct NativeFormExpressionTests {
  /// 优先级、短路、三元与 undefined/null 区分均来自明确数据语法。
  @Test(arguments: [
    "true || missing", "!false && (1 < 2)", "false ? missing : true",
    "null == undefined", "null !== undefined", "null != false", "null >= 0",
    "'1' == 1", "'1' !== 1", "false == 0", "'' == false",
    "9007199254740993 > 9007199254740992", "1e10 == 10000000000",
    "1 == 2 > 0", "'b' > 'a'", "false || true && true",
  ])
  func preservesSupportedScalarSemantics(_ source: String) throws {
    #expect(try NativeFormExpression.evaluate(source, model: [:]) == .bool(true))
  }

  /// 完整键、静态成员与 UTF-16 长度是数据访问，不会查询原型或调用方法。
  @Test func readsDataMembersAndExactOriginalKeys() throws {
    let model: [String: PluginJSONValue] = [
      "a.b": .bool(true), "names": .array([.string("😀")]),
      "nested": .object(["enabled": .bool(true)]),
    ]
    #expect(
      try NativeFormExpression.evaluate(
        "{{model['a.b'] && nested.enabled && names.length === 1 && names[0].length === 2}}",
        model: model) == .bool(true))
    #expect(
      try NativeFormExpression.evaluate("nested.__proto__ === undefined", model: model)
        == .bool(true))
    #expect(try NativeFormExpression.evaluate("'é' !== 'e\\u0301'", model: model) == .bool(true))
  }

  /// 任意调用、赋值、函数、模板和超界语法整体失败，未选逻辑分支也不能夹带执行代码。
  @Test(arguments: [
    "fetch('https://example.test')", "value = 1", "value++", "new Function('x')", "(()=>true)()",
    "`template`", "true || window.alert('x')", "model[x]", "a + b", "true; false",
    "model.constructor.constructor('x')()", "'unterminated", "/*comment*/ true", "missing", "",
    "(true",
  ])
  func rejectsExecutableOrUnknownSyntax(_ source: String) throws {
    #expect(throws: (any Error).self) { try NativeFormExpression.evaluate(source, model: [:]) }
  }

  /// 字节/令牌/深度和数字指数边界不会导致崩溃或按指数分配巨量内存。
  @Test func boundsResourceUseAndExtremeNumbers() throws {
    for text in [
      String(repeating: "!", count: 80) + "true", String(repeating: " ", count: 2049),
      Array(repeating: "true", count: 260).joined(separator: "||"),
    ] {
      #expect(throws: (any Error).self) { try NativeFormExpression.evaluate(text, model: [:]) }
    }
    #expect(ExactFormNumber("1e-9223372036854775808") == nil)
    #expect(ExactFormNumber("1e1000001") == nil)
    #expect(ExactFormNumber("1e1000000")?.compare(ExactFormNumber("9e999999")!) == 1)
    #expect(ExactFormNumber("-0.000")?.compare(ExactFormNumber("0")!) == 0)
    #expect(ExactFormNumber("-1e-1000000")?.compare(ExactFormNumber("-1")!) == 1)
  }

  /// 数字真假按原始尾数，极大/极小指数不因溢出/下溢改变条件。
  @Test func evaluatesNumericTruthWithoutFloatingPoint() throws {
    #expect(NativeFormExpression.truth(.number(try PluginJSONNumber("1e-999999"))))
    #expect(!NativeFormExpression.truth(.number(try PluginJSONNumber("-0e999999"))))
    #expect(!NativeFormExpression.truth(.string("")))
    #expect(NativeFormExpression.truth(.array([])))
  }

  /// 预先取消的计划/词法扫描不继续消耗 CPU。
  @Test func respectsTaskCancellation() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try NativeFormExpression.evaluate("true", model: [:])
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
