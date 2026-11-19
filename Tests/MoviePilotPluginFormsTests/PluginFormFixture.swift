import Foundation
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotPluginUI

@testable import MoviePilotAPI
@testable import MoviePilotSession

/// 仅供控制器时序验证的窄校验器；不是已交付原生渲染器的证明。
struct FixtureSwitchValidator: PluginFormValidating {
  /// 精确检查测试所用组件/属性与布尔绑定，不用任意空报告绕过未知能力。
  func validate(document: PluginUIDocument, draft: PluginFormDraft) throws
    -> [PluginFormValidationIssue]
  {
    let allowed: Set<PluginUIRequirement> = [
      .component("VSwitch"), .property(component: "VSwitch", name: "model"),
      .property(component: "VSwitch", name: "label"), .modelBinding,
    ]
    guard document.requirements.isSubset(of: allowed) else {
      return [.init(code: .unsupported, pointer: "/conf")]
    }
    guard case .bool = draft.value(forExactField: "enabled") else {
      return [.init(code: .invalidValue, pointer: "/model/enabled")]
    }
    return []
  }
}

/// 测试确认权限变化可以发生在同步验证期间，最终发送前仍须再检查会话。
struct EndingSessionValidator: PluginFormValidating {
  let end: @MainActor () -> Void

  /// 模拟 UI 交互导致注销，不执行网络或处理真实配置。
  func validate(document: PluginUIDocument, draft: PluginFormDraft) throws
    -> [PluginFormValidationIssue]
  {
    end()
    return []
  }
}

/// 模拟校验器同步规整草稿，确保保存不会丢掉校验期间产生的新输入。
@MainActor
final class EditingDraftValidator: PluginFormValidating {
  var edit: (() throws -> Void)?

  /// 此测试不提供真实渲染能力，只触发受控重入后让控制器核对修订。
  func validate(document: PluginUIDocument, draft: PluginFormDraft) throws
    -> [PluginFormValidationIssue]
  {
    try edit?()
    return try FixtureSwitchValidator().validate(document: document, draft: draft)
  }
}

/// 夹具使用真实 NativeSessionManager/APIClient，只有认证身份与本进程 HTTP 被替换。
@MainActor
struct FormHarness {
  let instance: NativeInstance
  let auth: FormAuthentication
  let manager: NativeSessionManager
  let session: NativeSession

  /// 每个调用产生独立实例/代次；不读取 Keychain、环境凭据或真实后端。
  static func make(admin: Bool = true, host: String = "forms.test") async throws -> Self {
    let instance = NativeInstance(
      id: UUID(), address: try ServerAddress("https://\(host)/moviepilot/"))
    let auth = try FormAuthentication(instance: instance, admin: admin)
    let manager = NativeSessionManager(
      tokens: FormTokenStore(), makeAuthentication: { _ in auth },
      makeAPI: { identity in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FormHTTPProtocol.self]
        return try APIClient(
          address: identity.address, token: identity.accessToken, configuration: configuration)
      })
    let session = try await manager.login(
      to: instance, username: "synthetic-admin", password: "synthetic-only", remember: false)
    return Self(instance: instance, auth: auth, manager: manager, session: session)
  }

  /// 创建测试的物理分身，所有网络必须指向 Clone_2 而不是 Source。
  func form(validator: any PluginFormValidating = FixtureSwitchValidator()) throws
    -> NativePluginForm
  {
    try NativePluginForm(
      session: session, target: PluginFormTarget(physicalID: "Clone_2", sourceID: "Source"),
      validator: validator)
  }
}

/// 认证值受锁保护，权限刷新由真正的 NativeSession.refreshUser 执行。
final class FormAuthentication: NativeAuthenticating, @unchecked Sendable {
  let address: ServerAddress
  private let lock = NSLock()
  private var identity: SessionIdentity

  /// 身份只包含固定合成账号，令牌绑定当前实例地址。
  init(instance: NativeInstance, admin: Bool) throws {
    address = instance.address
    identity = try SessionIdentity(
      address: address, user: SessionUser(id: 7, name: "synthetic-admin", isSuperuser: admin),
      accessToken: "synthetic.form.token")
  }

  /// 不需通过产品认证网络重复初始化。
  func initialization() async throws -> NativeInitialization { .ready }

  /// 此夹具不提供创建用户的捷径。
  func initialize(username: String, password: String, confirmation: String, apiKey: String)
    async throws
  {
    throw FormFixtureError.unexpectedInitialization
  }

  /// 既有会话协调器仍须核对来源并交付新代次。
  func login(username: String, password: String, otp: String?) async throws -> SessionIdentity {
    lock.withLock { identity }
  }

  /// 固定身份通过正常刷新入口传回，不直接篡改控制器权限缓存。
  func restore(accessToken: String) async throws -> SessionIdentity { lock.withLock { identity } }

  /// 没有独立认证网络，不借取消去影响配置 HTTP。
  func cancel() {}

  /// 在读/写等待期间撤销管理员身份，验证提交/发布两端的权限检查。
  func revokeAdmin() throws {
    let user = try SessionUser(id: 7, name: "synthetic-admin", isSuperuser: false)
    let next = try SessionIdentity(
      address: address, user: user, accessToken: "synthetic.form.token")
    lock.withLock { identity = next }
  }
}

/// 仅内存令牌端口用于调用真实协调器，无真实安全存储读写。
@MainActor
final class FormTokenStore: SessionTokenStoring {
  /// 此夹具只用显式登录，无恢复令牌。
  func read(_ instanceID: UUID) -> String? { nil }
  /// 测试不保持登录，意外保存直接失败。
  func save(_ token: String, for instanceID: UUID) throws {
    throw FormFixtureError.unexpectedPersistence
  }
  /// 清理不存在的合成记录不影响其它数据。
  func remove(_ instanceID: UUID) -> Bool { true }
}

/// 传输回调通过锁持有实际请求，保留方法/路径/正文以供断言。
final class FormHTTPState: @unchecked Sendable {
  private let lock = NSLock()
  private var reply = FormHTTPReply()
  private var requests: [(URLRequest, Data)] = []
  private var held: [ObjectIdentifier: FormHTTPProtocol] = [:]
  static let form = Data(
    #"{"render_mode":"vuetify","conf":[{"component":"VSwitch","props":{"model":"enabled","label":"Enable"}}],"model":{"enabled":false,"hidden":{"value":"synthetic-only"},"big":9007199254740993,"ratio":1.2300,"items":[null,true,"a"]}}"#
      .utf8)
  static let accepted = Data(#"{"success":true,"message":"","data":null}"#.utf8)

  /// 清理上个测试的观测值，串行 suite 不共用运行中任务。
  func reset() {
    lock.withLock {
      reply = FormHTTPReply()
      requests = []
      held = [:]
    }
  }

  /// 响应只影响下一次实际请求，不修改已发出请求或清空观测历史。
  func configure(_ reply: FormHTTPReply = FormHTTPReply()) { lock.withLock { self.reply = reply } }

  /// 原始 HTTP 方法决定默认响应，错误路径仍被记录且必须由测试显式核对。
  func answer(_ request: URLRequest, body: Data) -> FormHTTPReply {
    lock.withLock {
      requests.append((request, body))
      var value = reply
      if value.body == nil { value.body = request.httpMethod == "PUT" ? Self.accepted : Self.form }
      return value
    }
  }

  /// 返回不可变快照，不在产品日志或异常中输出请求正文。
  func captured() -> [(URLRequest, Data)] { lock.withLock { requests } }

  /// 保留真正已开始的 URLProtocol 请求，后续可显式完成或取消。
  func hold(_ value: FormHTTPProtocol) { lock.withLock { held[ObjectIdentifier(value)] = value } }

  /// URLSession 取消后不会再向失效协议实例追加回调。
  func stop(_ value: FormHTTPProtocol) {
    _ = lock.withLock { held.removeValue(forKey: ObjectIdentifier(value)) }
  }

  /// 原子取出仍活跃的挂起请求，模拟响应在权限/视图状态变化后才到达。
  func complete(body: Data = FormHTTPState.form, status: Int = 200) {
    let values = lock.withLock {
      let values = Array(held.values)
      held = [:]
      return values
    }
    for value in values { value.deliver(FormHTTPReply(status: status, body: body)) }
  }

  /// 必须等到具体请求到达/挂起才继续测试，不用长 sleep 猜测先后顺序。
  func waitForRequest(_ count: Int, held: Bool = true) async throws {
    for _ in 0..<200 {
      if lock.withLock({ requests.count >= count && (!held || !self.held.isEmpty) }) { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw FormFixtureError.requestNotStarted
  }
}

/// 合成响应状态独立于业务模型，不在 fixture 内修复请求。
struct FormHTTPReply: Sendable {
  var status: Int = 200
  var body: Data?
  var hold = false
  var headers = ["Content-Type": "application/json"]
}

/// 拦截所有来源，意外构造外部 URL 也不会访问生产网络。
final class FormHTTPProtocol: URLProtocol, @unchecked Sendable {
  static let state = FormHTTPState()

  /// 全部 URL 都留在本进程。
  override class func canInit(with request: URLRequest) -> Bool { true }
  /// 保留被测方法和完整部署子路径。
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  /// 用真实 URLSession 回调开始读取，挂起请求等待测试显式结算。
  override func startLoading() {
    let reply = Self.state.answer(request, body: Self.body(request))
    if reply.hold { Self.state.hold(self) } else { deliver(reply) }
  }
  /// 结束只移除该请求，不取消同会话其它控制器的网络。
  override func stopLoading() { Self.state.stop(self) }

  /// 交付 HTTP/正文，不绕过 APIClient 或直接设置产品成功状态。
  func deliver(_ reply: FormHTTPReply) {
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body ?? Data())
    client?.urlProtocolDidFinishLoading(self)
  }

  /// URLSession 可能把 body 转成流，仍读取真实请求字节而非重建预期对象。
  private static func body(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      result.append(buffer, count: count)
    }
    return result
  }
}

/// fixture 失败单独分类，不把观察超时伪装成产品取消或成功。
enum FormFixtureError: Error {
  case unexpectedInitialization, unexpectedPersistence, requestNotStarted
}
