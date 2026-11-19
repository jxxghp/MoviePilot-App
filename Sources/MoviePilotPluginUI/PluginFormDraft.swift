import Foundation

/// 完整配置的保真内存草稿；未展示的字段仍参与提交，不持久化或记录秘密配置。
public struct PluginFormDraft: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public private(set) var model: [String: PluginJSONValue]
  public private(set) var revision: UUID
  private var baseline: [String: PluginJSONValue]
  private var baselineData: Data
  private var data: Data
  private let limits: PluginJSONLimits

  /// 只能从结构正确的原生 form 建立，Vue/损坏响应不能伪装成空模型。
  public init(document: PluginUIDocument, limits: PluginJSONLimits = .standard) throws {
    guard document.surface == .form, document.renderMode == .vuetify,
      document.isStructurallyValid, let model = document.model
    else { throw PluginFormDraftError.invalidDocument }
    let data = try PluginJSONValue.object(model).encoded(limits: limits)
    self.model = model
    baseline = model
    baselineData = data
    self.data = data
    self.limits = limits
    revision = UUID()
  }

  /// 使用确定编码比较原始 Unicode/数字词法，避免 String 的规范等价掩盖真实修改。
  public var hasChanges: Bool { data != baselineData }

  /// 可读取隐藏/未知键，但不能按点号或 Swift 规范等价读取另一字段。
  public func value(forExactField field: String) -> PluginJSONValue? {
    PluginJSONValue.object(model)[exactKey: field]
  }

  /// 修改先检查完整候选模型，失败时不改变草稿、脏状态或代次。
  public mutating func setValue(_ value: PluginJSONValue, forExactField field: String) throws {
    try Task.checkCancellation()
    guard field.utf8.count <= 1024 else { throw PluginFormDraftError.invalidField }
    if let index = model.index(forKey: field), !model[index].key.utf8.elementsEqual(field.utf8) {
      throw PluginFormDraftError.conflictingField
    }
    var candidate = model
    candidate[field] = value
    let encoded = try PluginJSONValue.object(candidate).encoded(limits: limits)
    guard encoded != data else { return }
    model = candidate
    data = encoded
    revision = UUID()
  }

  /// 仅提交完整配置对象，不发送包含 conf/render_mode 的界面协议外壳。
  public func encodedModel() throws -> Data {
    try Task.checkCancellation()
    return data
  }

  /// 用户显式放弃本地修改时恢复上次确认的完整配置。
  public mutating func reset() {
    model = baseline
    data = baselineData
    revision = UUID()
  }

  /// 只由已确认保存的所有者推进基线；此纯值方法本身不代表网络已成功。
  public mutating func markSaved() {
    baseline = model
    baselineData = data
  }

  /// 草稿可能含密码/API Key，常规和调试描述均不展开值。
  public var description: String { "PluginFormDraft(<redacted>)" }

  /// 调试输出沿用同一遮盖规则。
  public var debugDescription: String { description }
}

/// 编辑失败仅保留类型，不把字段内容或模型放入异常。
public enum PluginFormDraftError: Error, Equatable, Sendable {
  case invalidDocument, invalidField, conflictingField
}
