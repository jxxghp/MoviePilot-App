import Combine
import Foundation
import MoviePilotAPI
import MoviePilotPluginUI
import MoviePilotSession

/// 同一实例/用户/代次下的插件配置所有者；网络复用原生会话，草稿不写本机存储。
@MainActor
public final class NativePluginForm: ObservableObject {
  public let target: PluginFormTarget
  public let scope: NativeSessionScope
  @Published public private(set) var phase: PluginFormPhase = .idle
  @Published public private(set) var document: PluginUIDocument?
  @Published public private(set) var draft: PluginFormDraft?
  @Published public private(set) var validationIssues: [PluginFormValidationIssue] = []
  @Published public private(set) var failure: PluginFormFailure?
  @Published public private(set) var saveOutcome: PluginFormSaveOutcome = .notSubmitted
  /// 当前草稿最近被确认接受的操作；继续编辑或再次提交后不沿用旧成功标记。
  @Published public private(set) var lastSave: UUID?
  private let session: NativeSession
  private let validator: any PluginFormValidating
  private let limits: PluginJSONLimits
  private var pending: Task<Void, any Error>?
  private var operationID = UUID()
  private static let permission = PermissionRequirement(category: .admin)

  /// 默认阻止所有尚未接入真实 UI 的非空表单，不从插件导航缺省权限推导配置权限。
  public init(
    session: NativeSession, target: PluginFormTarget,
    validator: any PluginFormValidating = UnrenderedPluginFormValidator(),
    limits: PluginJSONLimits = .standard
  ) throws {
    try session.checkActive(requiring: Self.permission)
    self.session = session
    self.target = target
    scope = session.scope
    self.validator = validator
    self.limits = limits
  }

  /// 最终释放时清理请求句柄；视图结束应显式 close，不取消其它业务共享的整个会话。
  deinit { pending?.cancel() }

  /// 加载完整 UI/配置；重新加载不会未经确认覆盖本地修改，失败保留原草稿。
  public func load(discardChanges: Bool = false) async throws {
    try checkAvailable()
    guard discardChanges || draft?.hasChanges != true else { throw PluginFormError.unsavedChanges }
    try await run(.loading) { [self] id in
      let result = try await session.requestPayload(
        APIEndpoint(
          path: ["plugin", "form", target.physicalID], responseContract: .payload,
          maximumResponseBytes: limits.maximumBytes), requiring: Self.permission)
      try checkOperation(id)
      let loaded = try await Self.decode(result.value, limits: limits)
      try checkOperation(id)
      self.document = loaded.document
      self.draft = loaded.draft
      validationIssues = []
      saveOutcome = .notSubmitted
      lastSave = nil
    }
  }

  /// 绑定只修改原始字段草稿；请求中禁用编辑，避免成功回应把更新草稿误标为已保存。
  public func setValue(_ value: PluginJSONValue, forExactField field: String) throws {
    try checkAvailable()
    guard var draft else { throw missingDraftError }
    let previousRevision = draft.revision
    try draft.setValue(value, forExactField: field)
    self.draft = draft
    if previousRevision != draft.revision { clearAcceptance() }
    validationIssues = []
    failure = nil
  }

  /// 显式放弃恢复上次接受的完整模型，不删除未知/隐藏字段。
  public func resetChanges() throws {
    try checkAvailable()
    guard var draft else { throw missingDraftError }
    draft.reset()
    self.draft = draft
    clearAcceptance()
    validationIssues = []
    failure = nil
  }

  /// 明确保存只发送一次完整 PUT；验证失败不发请求，失败/取消保留草稿且不自动重放。
  public func save() async throws {
    try checkAvailable()
    guard let document, var draft else { throw missingDraftError }
    clearAcceptance()
    validationIssues = try validator.validate(document: document, draft: draft)
    guard validationIssues.isEmpty else { throw PluginFormError.validationFailed }
    try checkAvailable()
    guard self.draft?.revision == draft.revision else { throw PluginFormError.draftChanged }
    let body = try draft.encodedModel()
    try await run(.saving) { [self] id in
      saveOutcome = .unconfirmed
      try await session.perform(
        APIEndpoint(path: ["plugin", target.physicalID], method: .put, body: body),
        requiring: Self.permission)
      try checkOperation(id)
      draft.markSaved()
      self.draft = draft
      saveOutcome = .accepted
      lastSave = id
    }
  }

  /// 关闭只取消自身任务并清空敏感配置，旧响应不能重新打开或污染另一界面。
  public func close() {
    operationID = UUID()
    pending?.cancel()
    pending = nil
    document = nil
    draft = nil
    validationIssues = []
    failure = nil
    lastSave = nil
    saveOutcome = .notSubmitted
    phase = .closed
  }

  /// Vue 文档与未加载不同，前者交给专用插件兼容模块而非保存空配置。
  private var missingDraftError: PluginFormError {
    document?.renderMode == .vue ? .remoteUI : .notLoaded
  }

  /// 草稿变化不能继承旧成功提示；已有未确认写入仍需保留，不能伪装成未发送。
  private func clearAcceptance() {
    lastSave = nil
    if saveOutcome == .accepted { saveOutcome = .notSubmitted }
  }

  /// 即使确认框后或权限刷新后也检查原会话，不根据已缓存的用户快照发送动作。
  private func checkAvailable() throws {
    guard phase != .closed else { throw PluginFormError.closed }
    try session.checkActive(requiring: Self.permission)
    guard pending == nil else { throw PluginFormError.operationInProgress }
  }

  /// API 返回后还需检查本视图是否已关闭及该代次当前权限。
  private func checkOperation(_ id: UUID) throws {
    guard phase != .closed, operationID == id else { throw PluginFormError.closed }
    try session.checkActive(requiring: Self.permission)
  }

  /// 所有异步工作归属单一可取消句柄；调用方取消同步传递给真实 API，不创建后台重试。
  private func run(
    _ phase: PluginFormPhase, operation: @escaping @MainActor (UUID) async throws -> Void
  ) async throws {
    try checkAvailable()
    let id = UUID()
    operationID = id
    let task = Task { @MainActor [self] in
      do {
        try checkOperation(id)
        try await operation(id)
        try checkOperation(id)
        pending = nil
        self.phase = .ready
      } catch {
        if operationID == id, self.phase != .closed {
          pending = nil
          self.phase = document == nil ? .idle : .ready
          failure = Self.failure(error)
        }
        throw error
      }
    }
    pending = task
    self.phase = phase
    failure = nil
    try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  /// 结构化子任务解析/编码有界配置，取消随父任务传播，CPU 工作不占用界面的主执行器。
  private nonisolated static func decode(_ data: Data, limits: PluginJSONLimits) async throws
    -> LoadedPluginForm
  {
    try await withThrowingTaskGroup(of: LoadedPluginForm.self) { group in
      group.addTask {
        let document = try PluginUIDecoder.decode(data, surface: .form, limits: limits)
        guard document.isStructurallyValid else { throw PluginFormError.invalidDocument }
        let draft: PluginFormDraft?
        switch document.renderMode {
        case .vuetify: draft = try PluginFormDraft(document: document, limits: limits)
        case .vue: draft = nil
        default: throw PluginFormError.invalidDocument
        }
        return LoadedPluginForm(document: document, draft: draft)
      }
      guard let loaded = try await group.next() else { throw PluginFormError.invalidDocument }
      return loaded
    }
  }

  /// 取消无错误横幅，其它失败只保留稳定分类，不把模型或服务器正文带进 UI。
  private static func failure(_ error: any Error) -> PluginFormFailure? {
    if error is CancellationError { return nil }
    if let error = error as? APIError { return .api(error) }
    if let error = error as? NativeSessionFailure { return .session(error) }
    if let error = error as? PluginFormError { return .form(error) }
    return .invalidData
  }
}

/// 解析结果整体返回后才允许发布，界面不会看到只更新了一半的文档/草稿。
private struct LoadedPluginForm: Sendable {
  let document: PluginUIDocument
  let draft: PluginFormDraft?
}
