import Foundation
import MoviePilotAPI
import MoviePilotPluginUI
import MoviePilotSession

/// 从已安装插件记录取得物理/源身份，不允许配置文档自行改写保存目标。
public struct PluginFormTarget: Equatable, Sendable {
  public let physicalID: String
  public let sourceID: String

  /// 与后端物理 ID 的 ASCII/长度规则一致，保持大小写且不修剪非法输入。
  public init(physicalID: String, sourceID: String? = nil) throws {
    let source = sourceID ?? physicalID
    guard Self.valid(physicalID), Self.valid(source) else { throw PluginFormError.invalidTarget }
    self.physicalID = physicalID
    self.sourceID = source
  }

  /// 规则复核于后端 domain/plugin.py，不把自由 URL 或路径当作插件标识。
  private static func valid(_ value: String) -> Bool {
    let bytes = value.utf8
    guard (1...128).contains(bytes.count), let first = bytes.first,
      (65...90).contains(first) || (97...122).contains(first)
    else { return false }
    return bytes.allSatisfy {
      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
    }
  }
}

/// 非敏感的表单校验定位；UI 自行本地化代码，不拼接配置值。
public struct PluginFormValidationIssue: Equatable, Sendable {
  public let code: PluginFormValidationCode
  public let pointer: String

  /// 验证器应使用原始节点/模型的 JSON Pointer，而非配置正文。
  public init(code: PluginFormValidationCode, pointer: String) {
    self.code = code
    self.pointer = pointer
  }
}

/// 本阶段只定义实际门禁所需类型，具体组件规则由 P2.2b 的真实渲染器补充。
public enum PluginFormValidationCode: String, Equatable, Sendable {
  case rendererUnavailable, unsupported, invalidValue, requiredValue
}

/// 保存前由真正的原生渲染/校验计划检查完整界面与草稿；不能以组件分类代替实现。
@MainActor
public protocol PluginFormValidating {
  /// 返回全部阻断项；默认未实现能力应失败，不能过滤未知字段后返回成功。
  func validate(document: PluginUIDocument, draft: PluginFormDraft) throws
    -> [PluginFormValidationIssue]
}

/// P2.2b 接入真实渲染器前，非空表单默认不能保存；空 conf 保留现有无配置项语义。
public struct UnrenderedPluginFormValidator: PluginFormValidating {
  /// 无状态默认策略不宣称支持任何非空组件、表达式或脚本。
  public init() {}

  /// 合法空文档没有待渲染能力；其完整模型仍必须原样提交而非清空。
  public func validate(document: PluginUIDocument, draft: PluginFormDraft) throws
    -> [PluginFormValidationIssue]
  {
    document.nodes.isEmpty && document.requirements.isEmpty
      ? [] : [.init(code: .rendererUnavailable, pointer: "/conf")]
  }
}

/// 控制器只激活一个明确的读/写操作；关闭后不可复用到另一个插件或账号。
public enum PluginFormPhase: Equatable, Sendable { case idle, loading, ready, saving, closed }

/// 失败/取消可能发生在服务端已执行之后，未确认不能冒充已撤销或自动重试。
public enum PluginFormSaveOutcome: Equatable, Sendable { case notSubmitted, accepted, unconfirmed }

/// 门禁错误不包含地址、配置或身份载荷。
public enum PluginFormError: Error, Equatable, Sendable {
  case invalidTarget, invalidDocument, remoteUI, notLoaded, operationInProgress, closed
  case unsavedChanges, validationFailed, draftChanged
}

/// 发布给 UI 的受控失败类型；任意解析器或下层错误的正文不会进入显示状态。
public enum PluginFormFailure: Equatable, Sendable {
  case api(APIError)
  case session(NativeSessionFailure)
  case form(PluginFormError)
  case invalidData
}
