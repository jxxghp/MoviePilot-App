import Foundation
import MoviePilotPluginUI

/// 仅执行有界 JSON 数据表达式，不存在 JS/DOM/函数/网络执行入口。
enum NativeFormExpression {
  /// 兼容旧表单的整段 {{}} 包装，普通字符串不在这里猜测为表达式。
  static func evaluate(_ source: String, model: [String: PluginJSONValue]) throws
    -> PluginJSONValue?
  {
    let text =
      source.hasPrefix("{{") && source.hasSuffix("}}")
      ? String(source.dropFirst(2).dropLast(2)) : source
    var parser = try ExpressionParser(text)
    let expression = try parser.parse()
    guard parser.atEnd else { throw NativeExpressionError.unsupported }
    var budget = 512
    return try expression.value(model, budget: &budget)
  }

  /// JSON 数字按原始词法判断零，避免大整数/极端指数转 Double 后改变真假。
  static func truth(_ value: PluginJSONValue?) -> Bool {
    switch value {
    case nil, .null: false
    case .bool(let flag): flag
    case .string(let text): !text.isEmpty
    case .number(let number):
      number.rawValue.prefix(while: { $0 != "e" && $0 != "E" }).contains {
        ("1"..."9").contains($0)
      }
    case .array, .object: true
    }
  }

  /// 只转换可显示的标量；对象不会被悄悄显示为无意义的字符串。
  static func text(_ value: PluginJSONValue?) -> String? {
    switch value {
    case nil, .null: ""
    case .string(let text): text
    case .number(let number): number.rawValue
    case .bool(let flag): flag ? "true" : "false"
    default: nil
    }
  }

  /// 字符串按 JS 的序列语义比较，数值按完整十进制比较，不进行 Double 舍入。
  static func compare(_ lhs: PluginJSONValue?, _ rhs: PluginJSONValue?) throws -> Int {
    if case .string(let a) = lhs, case .string(let b) = rhs {
      let x = Array(a.utf16)
      let y = Array(b.utf16)
      return x == y ? 0 : x.lexicographicallyPrecedes(y) ? -1 : 1
    }
    guard let a = number(lhs), let b = number(rhs) else { throw NativeExpressionError.unsupported }
    return a.compare(b)
  }

  /// 仅对 JSON 标量实施明确的严格/宽松相等；对象引用比较留待后续能力。
  static func equal(_ lhs: PluginJSONValue?, _ rhs: PluginJSONValue?, strict: Bool) throws -> Bool {
    switch (lhs, rhs) {
    case (nil, nil), (.null, .null): return true
    case (nil, .null), (.null, nil): return !strict
    case (.string(let a), .string(let b)): return a.utf8.elementsEqual(b.utf8)
    case (.bool(let a), .bool(let b)): return a == b
    case (.number, .number): return try compare(lhs, rhs) == 0
    case (.object, _), (.array, _), (_, .object), (_, .array):
      throw NativeExpressionError.unsupported
    default:
      if strict || lhs == nil || rhs == nil || lhs == .null || rhs == .null { return false }
      guard let a = number(lhs), let b = number(rhs) else { return false }
      return a.compare(b) == 0
    }
  }

  /// 宽松标量比较允许数字字符串/布尔，未知值与对象不被转换。
  private static func number(_ value: PluginJSONValue?) -> ExactFormNumber? {
    switch value {
    case .number(let number): ExactFormNumber(number.rawValue)
    case .string(let text): ExactFormNumber(text)
    case .bool(let flag): ExactFormNumber(flag ? "1" : "0")
    case .null: ExactFormNumber("0")
    default: nil
    }
  }
}

/// 受限语法失败只报告类型，不输出可能包含配置秘密的原始表达式。
enum NativeExpressionError: Error { case unsupported, exceeded, missingValue }

/// 标量数据 AST，左右逻辑分支保留短路和三元选择语义。
private indirect enum DataExpression {
  case literal(PluginJSONValue?)
  case name(String)
  case member(DataExpression, String)
  case not(DataExpression)
  case binary(String, DataExpression, DataExpression)
  case conditional(DataExpression, DataExpression, DataExpression)

  /// 求值仅访问完整模型中的数据，不查找 Swift/JS 原型或方法。
  func value(_ model: [String: PluginJSONValue], budget: inout Int) throws -> PluginJSONValue? {
    budget -= 1
    guard budget >= 0 else { throw NativeExpressionError.exceeded }
    try Task.checkCancellation()
    switch self {
    case .literal(let value): return value
    case .name(let name):
      if let value = PluginJSONValue.object(model)[exactKey: name] { return value }
      if name == "model" { return .object(model) }
      throw NativeExpressionError.missingValue
    case .member(let base, let key):
      let parent = try base.value(model, budget: &budget)
      switch parent {
      case .object: return parent?[exactKey: key]
      case .array(let values):
        if key == "length" { return .number(try PluginJSONNumber(String(values.count))) }
        guard let index = Int(key), index >= 0, String(index) == key else { return nil }
        return index < values.count ? values[index] : nil
      case .string(let text) where key == "length":
        return .number(try PluginJSONNumber(String(text.utf16.count)))
      case nil, .null: throw NativeExpressionError.missingValue
      default: return nil
      }
    case .not(let expression):
      return .bool(!NativeFormExpression.truth(try expression.value(model, budget: &budget)))
    case .conditional(let condition, let yes, let no):
      return try (NativeFormExpression.truth(condition.value(model, budget: &budget)) ? yes : no)
        .value(model, budget: &budget)
    case .binary(let op, let a, let b):
      let lhs = try a.value(model, budget: &budget)
      if op == "&&", !NativeFormExpression.truth(lhs) { return lhs }
      if op == "||", NativeFormExpression.truth(lhs) { return lhs }
      let rhs = try b.value(model, budget: &budget)
      if op == "&&" || op == "||" { return rhs }
      if ["==", "===", "!=", "!=="].contains(op) {
        let equal = try NativeFormExpression.equal(lhs, rhs, strict: op.count == 3)
        return .bool(op.hasPrefix("!") ? !equal : equal)
      }
      let comparison = try NativeFormExpression.compare(lhs, rhs)
      return .bool(
        op == ">"
          ? comparison > 0
          : op == "<" ? comparison < 0 : op == ">=" ? comparison >= 0 : comparison <= 0)
    }
  }
}

/// 小型递归下降解析器，长度/令牌/嵌套有硬边界，无法解析的代码不会降级为执行。
private struct ExpressionParser {
  private var tokens: [ExpressionToken]
  private var index = 0
  private var depth = 0
  var atEnd: Bool { index == tokens.count }

  /// 整段表达式最多 2048 UTF-8 字节和 256 个令牌。
  init(_ text: String) throws {
    guard text.utf8.count <= 2048 else { throw NativeExpressionError.exceeded }
    var lexer = ExpressionLexer(bytes: Array(text.utf8))
    tokens = try lexer.scan()
  }

  /// 三元分支右结合，不求值未选中的分支。
  mutating func parse() throws -> DataExpression {
    depth += 1
    defer { depth -= 1 }
    guard depth <= 24 else { throw NativeExpressionError.exceeded }
    let first = try logicalOr()
    if consume("?") {
      let yes = try parse()
      try expect(":")
      return .conditional(first, yes, try parse())
    }
    return first
  }

  /// 保留 || 的低优先级与左结合。
  private mutating func logicalOr() throws -> DataExpression {
    var expression = try logicalAnd()
    while consume("||") { expression = .binary("||", expression, try logicalAnd()) }
    return expression
  }

  /// 保留 && 的短路优先级。
  private mutating func logicalAnd() throws -> DataExpression {
    var expression = try comparison()
    while consume("&&") { expression = .binary("&&", expression, try comparison()) }
    return expression
  }

  /// 关系比较优先于相等，不能把 a == b > c 当作同级链。
  private mutating func comparison() throws -> DataExpression {
    var expression = try relation()
    while let op = symbol, ["==", "===", "!=", "!=="].contains(op) {
      index += 1
      expression = .binary(op, expression, try relation())
    }
    return expression
  }

  /// 只开放数据关系运算，不接受赋值/算术/调用等其它代码。
  private mutating func relation() throws -> DataExpression {
    var expression = try atom()
    while let op = symbol, [">", "<", ">=", "<="].contains(op) {
      index += 1
      expression = .binary(op, expression, try atom())
    }
    return expression
  }

  /// 成员访问只接收静态键/索引，原型方法调用不在语法中。
  private mutating func atom() throws -> DataExpression {
    depth += 1
    defer { depth -= 1 }
    guard depth <= 24, index < tokens.count else { throw NativeExpressionError.unsupported }
    if consume("!") { return .not(try atom()) }
    var result: DataExpression
    if consume("(") {
      result = try parse()
      try expect(")")
    } else {
      switch tokens[index] {
      case .literal(let value): result = .literal(value)
      case .name(let name): result = .name(name)
      default: throw NativeExpressionError.unsupported
      }
      index += 1
    }
    while true {
      if consume(".") {
        guard index < tokens.count, case .name(let name) = tokens[index] else {
          throw NativeExpressionError.unsupported
        }
        index += 1
        result = .member(result, name)
      } else if consume("[") {
        guard index < tokens.count else { throw NativeExpressionError.unsupported }
        let key: String
        switch tokens[index] {
        case .literal(.string(let value)): key = value
        case .literal(.number(let value)): key = value.rawValue
        default: throw NativeExpressionError.unsupported
        }
        index += 1
        try expect("]")
        result = .member(result, key)
      } else {
        break
      }
    }
    return result
  }

  /// 只识别当前令牌的运算符文本。
  private var symbol: String? {
    guard index < tokens.count, case .symbol(let value) = tokens[index] else { return nil }
    return value
  }

  /// 消费一个明确运算符，不跳过未知语法。
  private mutating func consume(_ value: String) -> Bool {
    guard symbol == value else { return false }
    index += 1
    return true
  }

  /// 配对符号不完整时整体失败。
  private mutating func expect(_ value: String) throws {
    guard consume(value) else { throw NativeExpressionError.unsupported }
  }
}

/// 令牌中的 undefined 与 null 保持不同，数字不经浮点中转。
private enum ExpressionToken {
  case literal(PluginJSONValue?)
  case name(String)
  case symbol(String)
}

/// ASCII 语法/UTF-8 字符串的受限词法器。
private struct ExpressionLexer {
  let bytes: [UInt8]
  private var index = 0

  /// 每次只扫描这一段已限制长度的 UTF-8，不继承上次游标。
  init(bytes: [UInt8]) { self.bytes = bytes }

  /// 有界扫描，不接收注释、模板字符串、函数或未声明运算符。
  mutating func scan() throws -> [ExpressionToken] {
    var result: [ExpressionToken] = []
    while index < bytes.count {
      try Task.checkCancellation()
      let byte = bytes[index]
      if byte == 32 || (9...13).contains(byte) {
        index += 1
        continue
      }
      if byte == 34 || byte == 39 {
        result.append(.literal(.string(try string())))
      } else if (48...57).contains(byte) || byte == 45 {
        let start = index
        index += 1
        while index < bytes.count,
          (48...57).contains(bytes[index]) || [46, 69, 101, 43, 45].contains(bytes[index])
        { index += 1 }
        result.append(
          .literal(
            .number(try PluginJSONNumber(String(decoding: bytes[start..<index], as: UTF8.self)))))
      } else if nameByte(byte) {
        let start = index
        index += 1
        while index < bytes.count, nameByte(bytes[index]) || (48...57).contains(bytes[index]) {
          index += 1
        }
        let word = String(decoding: bytes[start..<index], as: UTF8.self)
        result.append(
          word == "true"
            ? .literal(.bool(true))
            : word == "false"
              ? .literal(.bool(false))
              : word == "null" ? .literal(.null) : word == "undefined" ? .literal(nil) : .name(word)
        )
      } else {
        let remaining = bytes[index...]
        guard
          let op = [
            "===", "!==", "&&", "||", "==", "!=", ">=", "<=", "!", ">", "<", "(", ")", ".", "[",
            "]", "?", ":",
          ].first(where: { remaining.starts(with: $0.utf8) })
        else { throw NativeExpressionError.unsupported }
        index += op.utf8.count
        result.append(.symbol(op))
      }
      guard result.count <= 256 else { throw NativeExpressionError.exceeded }
    }
    return result
  }

  /// 普通字段名保留常见字母/下划线/$，其它键可用 model['原始键'] 访问。
  private func nameByte(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte == 36
  }

  /// 字符串只接受 JSON 兼容转义及单引号转义，拒绝 JS 特有执行/模板语法。
  private mutating func string() throws -> String {
    let quote = bytes[index]
    index += 1
    var json: [UInt8] = [34]
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      if byte == quote {
        json.append(34)
        guard let value = try PluginJSONReader.parse(Data(json)).string else {
          throw NativeExpressionError.unsupported
        }
        return value
      }
      if byte == 92 {
        guard index < bytes.count else { throw NativeExpressionError.unsupported }
        let next = bytes[index]
        index += 1
        if next == 39 { json.append(39) } else { json.append(contentsOf: [92, next]) }
      } else {
        if byte == 34 { json.append(92) }
        json.append(byte)
      }
    }
    throw NativeExpressionError.unsupported
  }
}

/// 任意受限长度十进制数的比较，不因 Double/Decimal 位数限制而丢失整数精度。
struct ExactFormNumber {
  private let negative: Bool
  private let digits: String
  private let exponent: Int

  /// 接受 JSON 数字及输入框常见十进制前导形式，不分配指数长度的零串。
  init?(_ source: String) {
    var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.utf8.count <= 256 else { return nil }
    if text.isEmpty { text = "0" }
    if text.hasPrefix("+") { text.removeFirst() }
    var negative = text.hasPrefix("-")
    if negative { text.removeFirst() }
    let parts = text.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), let power = parts.count == 2 ? Int(parts[1]) : 0,
      (-1_000_000...1_000_000).contains(power)
    else { return nil }
    let pieces = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard (1...2).contains(pieces.count) else { return nil }
    let raw = pieces.joined()
    guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    let digits = String(raw.drop(while: { $0 == "0" }))
    if digits.isEmpty { negative = false }
    self.negative = negative
    self.digits = digits.isEmpty ? "0" : digits
    exponent = digits.isEmpty ? 0 : power - (pieces.count == 2 ? pieces[1].count : 0)
  }

  /// 比较有效位数量和有限补零后的位序，不转浮点数。
  func compare(_ other: Self) -> Int {
    if negative != other.negative { return negative ? -1 : 1 }
    if digits == "0" || other.digits == "0" {
      if digits == other.digits { return 0 }
      let order = digits == "0" ? -1 : 1
      return negative ? -order : order
    }
    let size = digits.count + exponent
    let otherSize = other.digits.count + other.exponent
    var order: Int
    if size != otherSize {
      order = size < otherSize ? -1 : 1
    } else {
      let count = max(digits.count, other.digits.count)
      let a = digits + String(repeating: "0", count: count - digits.count)
      let b = other.digits + String(repeating: "0", count: count - other.digits.count)
      order = a == b ? 0 : a.lexicographicallyPrecedes(b) ? -1 : 1
    }
    return negative ? -order : order
  }
}
