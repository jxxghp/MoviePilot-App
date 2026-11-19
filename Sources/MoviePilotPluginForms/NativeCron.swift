import Foundation

/// 原生 Cron 编辑器的五个字段；这里只描述输入，不在手机上运行任务调度器。
public enum NativeCronUnit: String, CaseIterable, Hashable, Sendable, Identifiable {
  case minute, hour, day, month, weekday

  /// 稳定字段身份也用于原生导航，不把用户表达式作为 ID。
  public var id: String { rawValue }

  /// 五段顺序与后端 from_crontab 一致。
  public var index: Int { Self.allCases.firstIndex(of: self)! }

  /// 数字星期沿用现有 APScheduler 3 的 0=周一，生成时改用明确名称。
  public var bounds: ClosedRange<Int> {
    switch self {
    case .minute: 0...59
    case .hour: 0...23
    case .day: 1...31
    case .month: 1...12
    case .weekday: 0...6
    }
  }

  /// 构造器的显式步长使用后端字段范围，不生成超过可用范围的增量。
  public var maximumStep: Int { bounds.upperBound - bounds.lowerBound }

  /// 星期生成 mon–sun，避免其它 cron 方言对数字星期的不同解释。
  public func token(for value: Int) throws -> String {
    guard bounds.contains(value) else { throw NativeCronError.invalidRange }
    return self == .weekday ? NativeCronSyntax.weekdays[value] : String(value)
  }
}

/// 原生检查只说明编辑器是否理解格式，不声称实际任务存在下一次执行时间。
public enum NativeCronFormat: Sendable, Equatable { case empty, fiveFields, custom }

/// 有界只读格式分析；自定义插件值始终保留原文，不强制变成五段或主机时区。
public struct NativeCronExpression: Sendable, Equatable {
  public let rawValue: String
  public let fields: [String]?
  public let format: NativeCronFormat

  /// nil fields 表示不能按五字段编辑，仍可原样显示/保存和显式使用预设。
  public init(_ source: String) {
    rawValue = source
    guard source.utf8.count <= 1024 else {
      fields = nil
      format = .custom
      return
    }
    let parts = source.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !parts.isEmpty else {
      fields = nil
      format = .empty
      return
    }
    guard parts.count == 5, parts.allSatisfy({ $0.utf8.count <= 256 }) else {
      fields = nil
      format = .custom
      return
    }
    fields = parts
    format =
      zip(NativeCronUnit.allCases, parts).allSatisfy { NativeCronSyntax.recognizes($1, unit: $0) }
      ? .fiveFields : .custom
  }

  /// 只在用户明确应用一个字段时重新拼接；原样应用保留空格、别名和数字词法。
  public func replacing(_ unit: NativeCronUnit, with token: String) throws -> String {
    guard var fields else { throw NativeCronError.notFiveFields }
    guard NativeCronSyntax.singleToken(token) else { throw NativeCronError.invalidToken }
    guard !fields[unit.index].utf8.elementsEqual(token.utf8) else { return rawValue }
    fields[unit.index] = token
    return fields.joined(separator: " ")
  }
}

/// 明确可操作的字段规则；自定义 token 保留高级/插件方言，没有脚本执行入口。
public enum NativeCronRule: Sendable, Equatable {
  case every
  case values([Int])
  case range(Int, Int)
  case step(start: Int?, every: Int)
  case lastDay
  case custom(String)

  /// 可视化生成器先验证边界；所有自动生成的星期名称都来自固定枚举。
  public func token(for unit: NativeCronUnit) throws -> String {
    switch self {
    case .every: return "*"
    case .values(let values):
      guard !values.isEmpty, values.count <= unit.bounds.count,
        values.allSatisfy(unit.bounds.contains)
      else {
        throw NativeCronError.invalidRange
      }
      return try Set(values).sorted().map(unit.token).joined(separator: ",")
    case .range(let first, let last):
      guard unit.bounds.contains(first), unit.bounds.contains(last), first <= last else {
        throw NativeCronError.invalidRange
      }
      return try unit.token(for: first) + "-" + unit.token(for: last)
    case .step(let start, let every):
      let first = start ?? unit.bounds.lowerBound
      guard unit.bounds.contains(first), every > 0, every <= unit.bounds.upperBound - first else {
        throw NativeCronError.invalidRange
      }
      // 命名范围的 /步长会被某些调度器忽略；星期直接展开为明确名称，避免数字方言歧义。
      if unit == .weekday {
        return try stride(from: first, through: unit.bounds.upperBound, by: every).map(unit.token)
          .joined(separator: ",")
      }
      return (start.map(String.init) ?? "*") + "/" + String(every)
    case .lastDay:
      guard unit == .day else { throw NativeCronError.invalidRange }
      return "last"
    case .custom(let text):
      guard NativeCronSyntax.singleToken(text) else { throw NativeCronError.invalidToken }
      return text
    }
  }
}

/// 一个可视化字段的独立草稿；不编辑/取消不会规范化已有表达式。
public struct NativeCronFieldDraft: Sendable, Equatable {
  public let unit: NativeCronUnit
  public let source: String
  public var rule: NativeCronRule
  private let initial: NativeCronRule

  /// 不认识的 token 进入原生自定义输入，不能静默选中第一个数字。
  public init(unit: NativeCronUnit, token: String) {
    self.unit = unit
    source = token
    let rule = NativeCronSyntax.rule(token, unit: unit)
    self.rule = rule
    initial = rule
  }

  /// 原样应用返回原始 token；只有明确修改的规则才生成新词法。
  public func token() throws -> String {
    switch (rule, initial) {
    case (.custom(let a), .custom(let b)):
      if a.utf8.elementsEqual(b.utf8) { return source }
    case (.values(let a), .values(let b)):
      if Set(a) == Set(b) { return source }
    default:
      if rule == initial { return source }
    }
    return try rule.token(for: unit)
  }
}

/// 常用计划只在用户点选时替换，不从空值/未知值自动推断默认。
public enum NativeCronPreset: String, CaseIterable, Sendable, Identifiable {
  case quarterHourly, hourly, daily, weekdays, monthly, yearly

  /// 使用语义 ID 而非本地化标题，方便保持导航与测试稳定。
  public var id: String { rawValue }

  /// 这些是构造器预设，不是任何插件的业务默认周期。
  public var expression: String {
    switch self {
    case .quarterHourly: "*/15 * * * *"
    case .hourly: "0 * * * *"
    case .daily: "0 9 * * *"
    case .weekdays: "0 9 * * mon-fri"
    case .monthly: "0 0 1 * *"
    case .yearly: "0 0 1 1 *"
    }
  }
}

/// 格式错误只携带固定类别，不把可能包含私有配置的原文拼入错误。
public enum NativeCronError: Error, Equatable, Sendable {
  case invalidRange, invalidToken, notFiveFields
}

/// 无正则回溯、无执行器的小型 token 分析；它只用于编辑提示，不替代插件解释。
private enum NativeCronSyntax {
  static let weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
  static let months = [
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
  ]

  /// 字段自定义值不能注入额外字段；完整表达式仍可在外层直接输入。
  static func singleToken(_ text: String) -> Bool {
    !text.isEmpty && text.utf8.count <= 256 && !text.contains(where: \.isWhitespace)
      && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }

  /// 识别常用五段字段；不认识的合法插件方言留在 custom，不改写/阻断原始值。
  static func recognizes(_ token: String, unit: NativeCronUnit) -> Bool {
    guard singleToken(token) else { return false }
    let terms = token.split(separator: ",", omittingEmptySubsequences: false)
    guard terms.count <= 64 else { return false }
    return terms.allSatisfy { term in
      let pieces = term.split(separator: "/", omittingEmptySubsequences: false)
      guard (1...2).contains(pieces.count) else { return false }
      let base = String(pieces[0])
      let start: Int
      let end: Int
      if base == "*" {
        start = unit.bounds.lowerBound
        end = unit.bounds.upperBound
      } else if unit == .day && base.lowercased() == "last" {
        return pieces.count == 1
      } else {
        let range = base.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...2).contains(range.count), let first = value(String(range[0]), unit: unit) else {
          return false
        }
        start = first
        if range.count == 2 {
          guard let last = value(String(range[1]), unit: unit), last >= first else { return false }
          end = last
        } else {
          end = pieces.count == 2 ? unit.bounds.upperBound : first
        }
        // 不把服务端会忽略步长的命名范围误标成已理解的增量。
        if pieces.count == 2,
          base.utf8.contains(where: { (65...90).contains($0) || (97...122).contains($0) })
        {
          return false
        }
      }
      if pieces.count == 1 { return true }
      guard let step = integer(String(pieces[1])), step > 0 else { return false }
      return step <= end - start
    }
  }

  /// 已知点/列表/范围/增量可以直接打开可视化；其它形式保留 token 原文。
  static func rule(_ token: String, unit: NativeCronUnit) -> NativeCronRule {
    guard recognizes(token, unit: unit) else { return .custom(token) }
    if token == "*" { return .every }
    if unit == .day && token.lowercased() == "last" { return .lastDay }
    let terms = token.split(separator: ",", omittingEmptySubsequences: false)
    let values = terms.compactMap { value(String($0), unit: unit) }
    if values.count == terms.count { return .values(values) }
    if terms.count == 1 {
      let range = token.split(separator: "-", omittingEmptySubsequences: false)
      if range.count == 2, let first = value(String(range[0]), unit: unit),
        let last = value(String(range[1]), unit: unit)
      {
        return .range(first, last)
      }
      let step = token.split(separator: "/", omittingEmptySubsequences: false)
      if step.count == 2, let every = integer(String(step[1])) {
        if step[0] == "*" { return .step(start: nil, every: every) }
        if let start = value(String(step[0]), unit: unit) {
          return .step(start: start, every: every)
        }
      }
    }
    return .custom(token)
  }

  /// 月/周的固定英文缩写与数值对应已有调度器，不查询用户时区或网络。
  private static func value(_ text: String, unit: NativeCronUnit) -> Int? {
    if let value = integer(text), unit.bounds.contains(value) { return value }
    if unit == .weekday { return weekdays.firstIndex(of: text.lowercased()) }
    if unit == .month, let index = months.firstIndex(of: text.lowercased()) { return index + 1 }
    return nil
  }

  /// 只转换有界 ASCII 整数，避免指数、符号或巨大数造成溢出。
  private static func integer(_ text: String) -> Int? {
    guard !text.isEmpty, text.utf8.count <= 20, text.utf8.allSatisfy({ (48...57).contains($0) })
    else { return nil }
    return Int(text)
  }
}
