import Foundation

/// 插件配置使用保真的 JSON 值；数字不经过 Double，未知字段也不依赖旧网页桥契约。
public indirect enum PluginJSONValue: Equatable, Sendable {
  case object([String: PluginJSONValue])
  case array([PluginJSONValue])
  case string(String)
  case number(PluginJSONNumber)
  case bool(Bool)
  case null

  /// 只投影正确的对象类型，不把空值或数组猜成空配置。
  public var object: [String: PluginJSONValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// 保留数组次序，错误类型由上层提供具体路径诊断。
  public var array: [PluginJSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  /// 不把数值、布尔或 null 自动转换为字符串。
  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  /// JSON 对象键按原始 Unicode 序列匹配，不能使用 Swift 的规范等价替代 JS 键语义。
  public subscript(exactKey key: String) -> PluginJSONValue? {
    guard case .object(let fields) = self, let index = fields.index(forKey: key),
      fields[index].key.utf8.elementsEqual(key.utf8)
    else { return nil }
    return fields[index].value
  }

  /// 以相同资源边界编码修改后的配置，未知键和数字词法保持完整。
  public func encoded(limits: PluginJSONLimits = .standard) throws -> Data {
    var writer = PluginJSONWriter(limits: limits)
    try writer.write(self, depth: 0)
    return writer.data
  }
}

/// 数字的合法 JSON 词法，保留大整数、指数、小数和负零，避免保存时静默舍入。
public struct PluginJSONNumber: Equatable, Hashable, Sendable {
  public let rawValue: String

  /// 只接受完整的标准数字，不接受 NaN、Infinity、前导加号或尾随字符。
  public init(_ rawValue: String) throws {
    guard rawValue.utf8.count <= 1024 else { throw PluginJSONError.invalidJSON(offset: 0) }
    let bytes = Array(rawValue.utf8)
    guard !bytes.isEmpty, bytes.count <= 1024,
      PluginJSONScanner.numberEnd(in: bytes, from: 0) == bytes.count
    else { throw PluginJSONError.invalidJSON(offset: 0) }
    self.rawValue = rawValue
  }

  /// 解析器已经验证词法与资源上限，无须再次扫描。
  init(validated rawValue: String) { self.rawValue = rawValue }
}

/// 解析及重新编码共用资源预算；上限本身也受硬边界约束。
public struct PluginJSONLimits: Equatable, Sendable {
  public let maximumBytes: Int
  public let maximumDepth: Int
  public let maximumValues: Int
  public let maximumStringBytes: Int
  public let maximumNumberBytes: Int

  public static let standard = PluginJSONLimits()

  /// 默认足够容纳插件表单和一般数据页，同时阻止无限递归和超大字段。
  private init() {
    maximumBytes = 4 * 1024 * 1024
    maximumDepth = 48
    maximumValues = 100_000
    maximumStringBytes = 256 * 1024
    maximumNumberBytes = 256
  }

  /// 调用方可缩小预算；不能用负数、零或超出硬上限的配置绕过保护。
  public init(
    maximumBytes: Int, maximumDepth: Int, maximumValues: Int,
    maximumStringBytes: Int, maximumNumberBytes: Int
  ) throws {
    guard (1...16 * 1024 * 1024).contains(maximumBytes),
      (1...128).contains(maximumDepth), (1...1_000_000).contains(maximumValues),
      (1...1024 * 1024).contains(maximumStringBytes),
      (1...1024).contains(maximumNumberBytes)
    else { throw PluginJSONError.invalidLimits }
    self.maximumBytes = maximumBytes
    self.maximumDepth = maximumDepth
    self.maximumValues = maximumValues
    self.maximumStringBytes = maximumStringBytes
    self.maximumNumberBytes = maximumNumberBytes
  }
}

/// 对外错误只携带位置与类别，不能把可能包含密码/令牌的 JSON 正文带入日志。
public enum PluginJSONError: Error, Equatable, Sendable {
  case invalidLimits
  case invalidUTF8
  case invalidJSON(offset: Int)
  case duplicateKey(offset: Int)
  case ambiguousUnicodeKey(offset: Int)
  case limitExceeded(PluginJSONLimit, offset: Int)
}

/// 明确指出预算类别，便于 UI 报错和调整，而不暴露字段值。
public enum PluginJSONLimit: String, Equatable, Sendable {
  case bytes, depth, values, stringBytes, numberBytes
}

/// 有界 UTF-8 JSON 入口；不执行插件、不导入脚本引擎，也不把大数交给浮点解码器。
public enum PluginJSONReader {
  /// 先限制内存输入，再完整解析；部分文档和尾随内容不能成为成功结果。
  public static func parse(
    _ data: Data, limits: PluginJSONLimits = .standard
  ) throws -> PluginJSONValue {
    try Task.checkCancellation()
    guard data.count <= limits.maximumBytes else {
      throw PluginJSONError.limitExceeded(.bytes, offset: 0)
    }
    guard String(data: data, encoding: .utf8) != nil else { throw PluginJSONError.invalidUTF8 }
    var scanner = PluginJSONScanner(bytes: Array(data), limits: limits)
    let value = try scanner.value(depth: 0)
    try scanner.whitespace()
    guard scanner.index == scanner.bytes.count else {
      throw PluginJSONError.invalidJSON(offset: scanner.index)
    }
    return value
  }
}

/// 只负责 JSON 语法与预算，字符串转义交由 Foundation 的标准字符串解码处理。
struct PluginJSONScanner {
  let bytes: [UInt8]
  let limits: PluginJSONLimits
  var index = 0
  var values = 0

  /// JSON 仅允许四种空白，不把其它 Unicode 空白当作合法分隔。
  mutating func whitespace() throws {
    while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) {
      if index % 1024 == 0 { try Task.checkCancellation() }
      index += 1
    }
  }

  /// 每个值在递归前消耗预算并检查取消；所有字段（包括未知字段）都计入。
  mutating func value(depth: Int) throws -> PluginJSONValue {
    try Task.checkCancellation()
    try whitespace()
    values += 1
    guard values <= limits.maximumValues else { throw exceeded(.values) }
    guard depth <= limits.maximumDepth else { throw exceeded(.depth) }
    guard index < bytes.count else { throw invalid() }
    switch bytes[index] {
    case 123: return try object(depth: depth)
    case 91: return try array(depth: depth)
    case 34: return .string(try string())
    case 116:
      try literal("true")
      return .bool(true)
    case 102:
      try literal("false")
      return .bool(false)
    case 110:
      try literal("null")
      return .null
    case 45, 48...57:
      let start = index
      while index < bytes.count,
        [45, 43, 46, 69, 101].contains(bytes[index])
          || (48...57).contains(bytes[index])
      {
        guard index - start < limits.maximumNumberBytes else { throw exceeded(.numberBytes) }
        index += 1
      }
      let token = Array(bytes[start..<index])
      guard Self.numberEnd(in: token, from: 0) == token.count else { throw invalid() }
      return .number(.init(validated: String(decoding: token, as: UTF8.self)))
    default: throw invalid()
    }
  }

  /// 重复键及 Swift 规范等价但字节不同的键均拒绝，避免字典静默覆盖配置。
  private mutating func object(depth: Int) throws -> PluginJSONValue {
    index += 1
    try whitespace()
    var result: [String: PluginJSONValue] = [:]
    if consume(125) { return .object(result) }
    while true {
      try whitespace()
      let keyOffset = index
      let key = try string()
      if result[key] != nil {
        let exact = result.keys.contains { Array($0.utf8) == Array(key.utf8) }
        if exact { throw PluginJSONError.duplicateKey(offset: keyOffset) }
        throw PluginJSONError.ambiguousUnicodeKey(offset: keyOffset)
      }
      try whitespace()
      guard consume(58) else { throw invalid() }
      result[key] = try value(depth: depth + 1)
      try whitespace()
      if consume(125) { return .object(result) }
      guard consume(44) else { throw invalid() }
    }
  }

  /// 数组只接受明确逗号和结束符，拒绝尾逗号或空洞。
  private mutating func array(depth: Int) throws -> PluginJSONValue {
    index += 1
    try whitespace()
    var result: [PluginJSONValue] = []
    if consume(93) { return .array(result) }
    while true {
      result.append(try value(depth: depth + 1))
      try whitespace()
      if consume(93) { return .array(result) }
      guard consume(44) else { throw invalid() }
    }
  }

  /// 扫描时即限制转义后的原始词法字节；不会先分配无限长度字符串。
  private mutating func string() throws -> String {
    let start = index
    guard consume(34) else { throw invalid() }
    while index < bytes.count {
      if index - start - 1 > limits.maximumStringBytes { throw exceeded(.stringBytes) }
      if (index - start) % 256 == 0 { try Task.checkCancellation() }
      let byte = bytes[index]
      index += 1
      if byte == 34 {
        do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) } catch
        { throw PluginJSONError.invalidJSON(offset: start) }
      }
      guard byte >= 32 else { throw invalid() }
      if byte == 92 {
        guard index < bytes.count else { throw invalid() }
        index += 1
      }
    }
    throw invalid()
  }

  /// 常量使用逐字节匹配，不允许 JavaScript 的非 JSON 值混入。
  private mutating func literal(_ text: String) throws {
    for byte in text.utf8 {
      guard consume(byte) else { throw invalid() }
    }
  }

  /// 在边界内消费一个指定字节。
  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  /// 语法失败不包含源文档片段。
  private func invalid() -> PluginJSONError { .invalidJSON(offset: index) }

  /// 预算失败只包含类别与偏移。
  private func exceeded(_ kind: PluginJSONLimit) -> PluginJSONError {
    .limitExceeded(kind, offset: index)
  }

  /// 标准 JSON 数字语法；保留词法而不求浮点值，非法小数/指数整体失败。
  static func numberEnd(in bytes: [UInt8], from start: Int) -> Int? {
    var i = start
    if i < bytes.count, bytes[i] == 45 { i += 1 }
    guard i < bytes.count else { return nil }
    if bytes[i] == 48 {
      i += 1
    } else {
      guard (49...57).contains(bytes[i]) else { return nil }
      repeat { i += 1 } while i < bytes.count && (48...57).contains(bytes[i])
    }
    if i < bytes.count, bytes[i] == 46 {
      i += 1
      let first = i
      while i < bytes.count, (48...57).contains(bytes[i]) { i += 1 }
      guard i > first else { return nil }
    }
    if i < bytes.count, bytes[i] == 69 || bytes[i] == 101 {
      i += 1
      if i < bytes.count, bytes[i] == 43 || bytes[i] == 45 { i += 1 }
      let first = i
      while i < bytes.count, (48...57).contains(bytes[i]) { i += 1 }
      guard i > first else { return nil }
    }
    return i
  }
}

/// 保真数字编码不能走 Double/Decimal 的隐式转换，按合法 JSON 词法直接写入。
private struct PluginJSONWriter {
  let limits: PluginJSONLimits
  var data = Data()
  var values = 0

  /// 修改后的值再次完整检查预算，不能借公开值模型绕过输入限制。
  mutating func write(_ value: PluginJSONValue, depth: Int) throws {
    try Task.checkCancellation()
    values += 1
    guard values <= limits.maximumValues else { throw exceeded(.values) }
    guard depth <= limits.maximumDepth else { throw exceeded(.depth) }
    switch value {
    case .null: try append(Data("null".utf8))
    case .bool(let value): try append(Data((value ? "true" : "false").utf8))
    case .number(let number):
      guard number.rawValue.utf8.count <= limits.maximumNumberBytes else {
        throw exceeded(.numberBytes)
      }
      try append(Data(number.rawValue.utf8))
    case .string(let value): try string(value)
    case .array(let values):
      try append(Data("[".utf8))
      for (index, item) in values.enumerated() {
        if index > 0 { try append(Data(",".utf8)) }
        try write(item, depth: depth + 1)
      }
      try append(Data("]".utf8))
    case .object(let values):
      try append(Data("{".utf8))
      for (index, key) in values.keys.sorted().enumerated() {
        if index > 0 { try append(Data(",".utf8)) }
        try string(key)
        try append(Data(":".utf8))
        if let item = values[key] { try write(item, depth: depth + 1) }
      }
      try append(Data("}".utf8))
    }
  }

  /// 字符串由标准编码器转义，输出词法仍需符合相同字符串预算。
  private mutating func string(_ value: String) throws {
    guard value.utf8.count <= limits.maximumStringBytes else { throw exceeded(.stringBytes) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let encoded = try encoder.encode(value)
    guard encoded.count - 2 <= limits.maximumStringBytes else { throw exceeded(.stringBytes) }
    try append(encoded)
  }

  /// 每次追加前检查总输出，避免最后才发现结果已经超限。
  private mutating func append(_ bytes: Data) throws {
    guard bytes.count <= limits.maximumBytes - data.count else { throw exceeded(.bytes) }
    data.append(bytes)
  }

  /// 编码器同样不把任何配置值放入错误。
  private func exceeded(_ kind: PluginJSONLimit) -> PluginJSONError {
    .limitExceeded(kind, offset: data.count)
  }
}
