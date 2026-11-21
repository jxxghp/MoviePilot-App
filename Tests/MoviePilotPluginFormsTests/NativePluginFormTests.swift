import Foundation
import MoviePilotAPI
import MoviePilotPluginForms
import MoviePilotPluginUI
import MoviePilotSession
import Testing

/// 使用真实会话/API/保真模型检查控制器；测试校验器不计为已实现 UI。
@Suite(.serialized)
@MainActor
struct NativePluginFormTests {
  /// 新编辑/失败尝试不能沿用较早成功标记，修改相同值则不伪造一次新修订。
  @Test func clearsStaleAcceptanceWhenDraftChanges() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try await form.save()
    let accepted = try #require(form.lastSave)
    try form.setValue(.bool(false), forExactField: "enabled")
    #expect(form.lastSave == accepted && form.saveOutcome == .accepted)
    try form.setValue(.bool(true), forExactField: "enabled")
    #expect(
      form.lastSave == nil && form.saveOutcome == .notSubmitted && form.draft?.hasChanges == true)
    FormHTTPProtocol.state.configure(.init(status: 503))
    await #expect(throws: APIError.httpStatus(503)) { try await form.save() }
    try form.resetChanges()
    #expect(form.lastSave == nil && form.saveOutcome == .unconfirmed)
    #expect(form.draft?.hasChanges == false && FormHTTPProtocol.state.captured().count == 3)
  }

  /// 同步校验器改变输入后拒绝旧快照，避免发送旧值并覆盖用户的新草稿。
  @Test func detectsDraftChangesDuringValidation() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let validator = EditingDraftValidator()
    let form = try harness.form(validator: validator)
    defer { form.close() }
    validator.edit = { [weak form] in try form?.setValue(.bool(true), forExactField: "enabled") }
    try await form.load()
    await #expect(throws: PluginFormError.draftChanged) { try await form.save() }
    #expect(
      form.draft?.value(forExactField: "enabled") == .bool(true) && form.draft?.hasChanges == true)
    #expect(FormHTTPProtocol.state.captured().count == 1)
    validator.edit = nil
    try await form.save()
    #expect(FormHTTPProtocol.state.captured().count == 2 && form.saveOutcome == .accepted)
  }
  /// 未加载/解析失败不能发送空配置，错误状态也不展示原始配置正文。
  @Test func refusesSavingUnloadedOrMalformedConfiguration() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    await #expect(throws: PluginFormError.notLoaded) { try await form.save() }
    #expect(throws: PluginFormError.notLoaded) {
      try form.setValue(.bool(true), forExactField: "enabled")
    }
    #expect(FormHTTPProtocol.state.captured().isEmpty)
    FormHTTPProtocol.state.configure(.init(body: Data("{not-json-synthetic-private-value".utf8)))
    await #expect(throws: PluginJSONError.self) { try await form.load() }
    #expect(form.phase == .idle && form.document == nil && form.draft == nil)
    #expect(form.failure == .invalidData)
    await #expect(throws: PluginFormError.notLoaded) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 1)
  }

  /// 文档超限在真实传输读取阶段整体失败，不留下可保存的截断数据。
  @Test func boundsRawDocumentWithoutCreatingPartialDraft() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let limits = try PluginJSONLimits(
      maximumBytes: 64, maximumDepth: 8, maximumValues: 30, maximumStringBytes: 48,
      maximumNumberBytes: 16)
    let form = try NativePluginForm(
      session: harness.session, target: PluginFormTarget(physicalID: "Clone_2"), limits: limits)
    defer { form.close() }
    await #expect(throws: APIError.responseTooLarge) { try await form.load() }
    #expect(form.failure == .api(.responseTooLarge) && form.draft == nil && form.document == nil)
    await #expect(throws: PluginFormError.notLoaded) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 1)
  }
  /// 读取/保存物理实例的完整配置，未知值与超出 Double 精度的大数不会被前端桥改写。
  @Test func savesWholeConfigurationToPhysicalInstance() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    #expect(form.document?.rawData == FormHTTPState.form)
    #expect(form.scope == harness.session.scope && form.target.sourceID == "Source")
    try form.setValue(.bool(true), forExactField: "enabled")
    try await form.save()
    let requests = FormHTTPProtocol.state.captured()
    #expect(requests.count == 2)
    #expect(requests[0].0.url?.path == "/moviepilot/api/v1/plugin/form/Clone_2")
    #expect(requests[1].0.url?.path == "/moviepilot/api/v1/plugin/Clone_2")
    #expect(requests[1].0.httpMethod == "PUT")
    #expect(
      requests[1].0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic.form.token")
    let model = try PluginJSONReader.parse(requests[1].1)
    #expect(model[exactKey: "enabled"] == .bool(true))
    #expect(model[exactKey: "hidden"] == .object(["value": .string("synthetic-only")]))
    #expect(model[exactKey: "big"] == .number(try PluginJSONNumber("9007199254740993")))
    #expect(model[exactKey: "ratio"] == .number(try PluginJSONNumber("1.2300")))
    #expect(model[exactKey: "conf"] == nil && model[exactKey: "model"] == nil)
    #expect(form.phase == .ready && form.draft?.hasChanges == false)
    #expect(form.saveOutcome == .accepted && form.lastSave != nil && form.failure == nil)
  }

  /// 插件配置端点的标准 MoviePilot envelope 必须解到完整原生表单，同时保留大数字词法。
  @Test func loadsStandardPluginResponseEnvelopeWithoutChangingModelValues() async throws {
    FormHTTPProtocol.state.reset()
    FormHTTPProtocol.state.configure(
      .init(
        body: Data(
          #"{"success":true,"message":"","data":{"render_mode":"vuetify","conf":[{"component":"VSwitch","props":{"model":"enabled","label":"Enable"}}],"model":{"enabled":false,"hidden":{"value":"synthetic-only"},"big":9007199254740993,"ratio":1.2300,"success":false,"data":{"retained":true}}}}"#
            .utf8)))
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }

    try await form.load()

    #expect(form.phase == .ready && form.failure == nil)
    #expect(form.draft?.value(forExactField: "enabled") == .bool(false))
    #expect(
      form.draft?.value(forExactField: "hidden") == .object(["value": .string("synthetic-only")]))
    #expect(
      form.draft?.value(forExactField: "big") == .number(try PluginJSONNumber("9007199254740993")))
    #expect(form.draft?.value(forExactField: "ratio") == .number(try PluginJSONNumber("1.2300")))
    #expect(form.draft?.value(forExactField: "success") == .bool(false))
    #expect(form.draft?.value(forExactField: "data") == .object(["retained": .bool(true)]))
    #expect(form.document?.nodes.first?.component == "VSwitch")
  }

  /// 默认门禁不能把可分类的非空表单误认作已实现组件并发送保存。
  @Test func defaultValidatorBlocksNonemptyForms() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form(validator: UnrenderedPluginFormValidator())
    defer { form.close() }
    try await form.load()
    await #expect(throws: PluginFormError.validationFailed) { try await form.save() }
    #expect(form.validationIssues == [.init(code: .rendererUnavailable, pointer: "/conf")])
    #expect(FormHTTPProtocol.state.captured().count == 1 && form.saveOutcome == .notSubmitted)
  }

  /// 没有配置项的合法插件仍按完整模型保存，不能把已有未知项清空。
  @Test func defaultValidatorAcceptsOnlyLegitimateEmptyForm() async throws {
    FormHTTPProtocol.state.reset()
    FormHTTPProtocol.state.configure(
      .init(
        body: Data(
          #"{"render_mode":"vuetify","conf":[],"model":{"retained":9007199254740993}}"#.utf8)))
    let harness = try await FormHarness.make()
    let form = try harness.form(validator: UnrenderedPluginFormValidator())
    defer { form.close() }
    try await form.load()
    FormHTTPProtocol.state.configure()
    try await form.save()
    #expect(
      FormHTTPProtocol.state.captured().last?.1 == Data(#"{"retained":9007199254740993}"#.utf8))
  }

  /// 值校验失败阻止网络，用户修改和所有未知字段仍留在草稿。
  @Test func validationFailureRetainsDraftWithoutSending() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.string("true"), forExactField: "enabled")
    await #expect(throws: PluginFormError.validationFailed) { try await form.save() }
    #expect(form.draft?.hasChanges == true && form.validationIssues.first?.code == .invalidValue)
    #expect(FormHTTPProtocol.state.captured().count == 1)
  }

  /// HTTP/业务/协议失败都不重发，完整草稿保留，只有再次明确调用才能发第二个 PUT。
  @Test(arguments: [500, 200, 201])
  func preservesDraftOnUnconfirmedSave(_ variant: Int) async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.bool(true), forExactField: "enabled")
    let body =
      variant == 200
      ? Data(#"{"success":false,"message":"rejected","data":null}"#.utf8) : Data("{}".utf8)
    FormHTTPProtocol.state.configure(.init(status: variant == 500 ? 500 : 200, body: body))
    let expected: APIError =
      variant == 500 ? .httpStatus(500) : variant == 200 ? .businessFailure : .invalidResponse
    await #expect(throws: expected) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 2 && form.draft?.hasChanges == true)
    #expect(form.phase == .ready && form.saveOutcome == .unconfirmed && form.lastSave == nil)
    #expect(form.failure == .api(expected))
    FormHTTPProtocol.state.configure()
    try await form.save()
    #expect(FormHTTPProtocol.state.captured().count == 3 && form.draft?.hasChanges == false)
  }

  /// 在途写入禁止编辑/重复提交，调用方取消传到 URLSession 后仍保留草稿与未确认结果。
  @Test func cancelsSaveWithoutReplayingOrMarkingItSaved() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.bool(true), forExactField: "enabled")
    FormHTTPProtocol.state.configure(.init(hold: true))
    let task = Task { try await form.save() }
    try await FormHTTPProtocol.state.waitForRequest(2)
    #expect(form.phase == .saving)
    #expect(throws: PluginFormError.operationInProgress) {
      try form.setValue(.bool(false), forExactField: "enabled")
    }
    await #expect(throws: PluginFormError.operationInProgress) { try await form.save() }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(form.phase == .ready && form.failure == nil && form.saveOutcome == .unconfirmed)
    #expect(form.draft?.hasChanges == true && FormHTTPProtocol.state.captured().count == 2)
  }

  /// 关闭取消自身读取并清空配置，不销毁同会话的客户端或让迟到请求重新发布。
  @Test func closingOnlyCancelsItsOwnRequest() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    FormHTTPProtocol.state.configure(.init(hold: true))
    let task = Task { try await form.load() }
    try await FormHTTPProtocol.state.waitForRequest(1)
    form.close()
    await #expect(throws: CancellationError.self) { try await task.value }
    FormHTTPProtocol.state.complete()
    #expect(
      form.phase == .closed && form.document == nil && form.draft == nil && form.failure == nil)
    await #expect(throws: PluginFormError.closed) { try await form.load() }
    try harness.session.checkActive()
    FormHTTPProtocol.state.configure()
    let other = try harness.form()
    defer { other.close() }
    try await other.load()
    #expect(other.draft != nil && FormHTTPProtocol.state.captured().count == 2)
  }

  /// 重新读取必须先取得放弃选择，失败时保留旧草稿；成功后才替换完整模型。
  @Test func reloadRequiresDiscardAndPreservesDraftOnFailure() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.bool(true), forExactField: "enabled")
    await #expect(throws: PluginFormError.unsavedChanges) { try await form.load() }
    #expect(FormHTTPProtocol.state.captured().count == 1)
    FormHTTPProtocol.state.configure(.init(status: 503))
    await #expect(throws: APIError.httpStatus(503)) { try await form.load(discardChanges: true) }
    #expect(
      form.draft?.hasChanges == true && form.draft?.value(forExactField: "enabled") == .bool(true))
    FormHTTPProtocol.state.configure()
    try await form.load(discardChanges: true)
    #expect(
      form.draft?.hasChanges == false && form.draft?.value(forExactField: "enabled") == .bool(false)
    )
  }

  /// Vue 只交付兼容文档，损坏数据保留失败，不产生可保存的空原生配置。
  @Test func distinguishesRemoteAndMalformedDocuments() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    FormHTTPProtocol.state.configure(
      .init(body: Data(#"{"render_mode":"vue","model":{"enabled":true}}"#.utf8)))
    try await form.load()
    #expect(form.document?.renderMode == .vue && form.draft == nil)
    await #expect(throws: PluginFormError.remoteUI) { try await form.save() }
    FormHTTPProtocol.state.configure(.init(body: Data("{}".utf8)))
    await #expect(throws: PluginFormError.invalidDocument) { try await form.load() }
    #expect(form.draft == nil && form.document?.renderMode == .vue)
    #expect(form.failure == .form(.invalidDocument) && FormHTTPProtocol.state.captured().count == 2)
  }

  /// 普通账号的宽松导航权限不能用于管理员配置 API，拒绝发生在任何读取之前。
  @Test func rejectsNonAdministratorWithoutNetwork() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make(admin: false)
    #expect(throws: NativeSessionFailure.permissionDenied) { try harness.form() }
    #expect(FormHTTPProtocol.state.captured().isEmpty)
  }

  /// raw payload 返回前撤销权限，也不能发布已不允许读取的表单。
  @Test func rechecksPermissionAfterRawResponse() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    FormHTTPProtocol.state.configure(.init(hold: true))
    let task = Task { try await form.load() }
    try await FormHTTPProtocol.state.waitForRequest(1)
    try harness.auth.revokeAdmin()
    _ = try await harness.session.refreshUser()
    FormHTTPProtocol.state.complete()
    await #expect(throws: NativeSessionFailure.permissionDenied) { try await task.value }
    #expect(form.document == nil && form.draft == nil && form.phase == .idle)
    #expect(form.failure == .session(.permissionDenied))
  }

  /// 写入回应之前失去权限不能把草稿标成保存，API 已发出则明确保留未确认状态。
  @Test func rechecksPermissionAfterSaveResponse() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.bool(true), forExactField: "enabled")
    FormHTTPProtocol.state.configure(.init(hold: true))
    let task = Task { try await form.save() }
    try await FormHTTPProtocol.state.waitForRequest(2)
    try harness.auth.revokeAdmin()
    _ = try await harness.session.refreshUser()
    FormHTTPProtocol.state.complete(body: FormHTTPState.accepted)
    await #expect(throws: NativeSessionFailure.permissionDenied) { try await task.value }
    #expect(
      form.draft?.hasChanges == true && form.lastSave == nil && form.saveOutcome == .unconfirmed)
    await #expect(throws: NativeSessionFailure.permissionDenied) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 2)
  }

  /// 服务端 401 沿用真实协调器的过期处理，旧控制器不能继续发送草稿。
  @Test func expiresOwningSessionOnUnauthorizedResponse() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.bool(true), forExactField: "enabled")
    FormHTTPProtocol.state.configure(.init(status: 401))
    await #expect(throws: APIError.unauthorized) { try await form.save() }
    #expect(harness.manager.currentSession == nil)
    #expect(harness.manager.state == .loginRequired(harness.instance, reason: .expired))
    await #expect(throws: NativeSessionFailure.invalidated) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 2 && form.draft?.hasChanges == true)
  }

  /// 同实例同账号重新登录也有新代次，旧草稿不能复用新会话令牌发送。
  @Test func invalidatesDraftAccessAcrossGenerations() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    try await form.load()
    try form.setValue(.bool(true), forExactField: "enabled")
    let next = try await harness.manager.login(
      to: harness.instance, username: "synthetic-admin", password: "synthetic-only", remember: false
    )
    #expect(next.scope != form.scope)
    await #expect(throws: NativeSessionFailure.invalidated) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 1)
    let fresh = try NativePluginForm(
      session: next, target: form.target, validator: FixtureSwitchValidator())
    defer { fresh.close() }
    try await fresh.load()
    #expect(fresh.draft?.value(forExactField: "enabled") == .bool(false))
  }

  /// 读取期间切换登录代次，旧请求结束后也不能发布到新身份的表单。
  @Test func generationChangeDuringReadCannotPublishOldDocument() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    FormHTTPProtocol.state.configure(.init(hold: true))
    let oldRead = Task { try await form.load() }
    try await FormHTTPProtocol.state.waitForRequest(1)
    let next = try await harness.manager.login(
      to: harness.instance, username: "synthetic-admin", password: "synthetic-only", remember: false
    )
    do {
      try await oldRead.value
      Issue.record("旧代次读取不应成功")
    } catch {
      #expect(error is CancellationError || (error as? NativeSessionFailure) == .invalidated)
    }
    FormHTTPProtocol.state.complete()
    #expect(form.document == nil && form.draft == nil && next.scope != form.scope)
    try next.checkActive()
  }

  /// 校验引起同步注销后也不能依靠较早检查继续发出保存。
  @Test func rechecksSessionAfterValidation() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form(
      validator: EndingSessionValidator(end: { harness.manager.disconnect() }))
    defer { form.close() }
    try await form.load()
    await #expect(throws: NativeSessionFailure.invalidated) { try await form.save() }
    #expect(FormHTTPProtocol.state.captured().count == 1)
  }

  /// 预取消不启动子任务或网络，不把失败当作空配置成功。
  @Test func preCancelledLoadDoesNotStartNetwork() async throws {
    FormHTTPProtocol.state.reset()
    let harness = try await FormHarness.make()
    let form = try harness.form()
    defer { form.close() }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      try await form.load()
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(form.phase == .idle && FormHTTPProtocol.state.captured().isEmpty)
  }

  /// 非法目标在构造前拒绝，源 ID 不合法也不能回退成合法物理 ID。
  @Test(arguments: [
    "", "1Bad", "../Plugin", "Source/Clone", "Plugin-2", " 插件", "Plugin ",
    String(repeating: "A", count: 129),
  ])
  func rejectsInvalidTargets(_ id: String) {
    #expect(throws: PluginFormError.invalidTarget) { try PluginFormTarget(physicalID: id) }
    #expect(throws: PluginFormError.invalidTarget) {
      try PluginFormTarget(physicalID: "Valid", sourceID: id)
    }
  }
}
