import MoviePilotCore
import UIKit

/// 固定通知接口的解码结果，认证数据始终留在现有 Web 会话中。
struct NotificationReply: Decodable, Sendable {
  let success: Bool
  let message: String?
  let data: [String: JSONValue]?
}

/// 向用户显示可恢复的通知错误，不拼接底层网络响应或认证数据。
struct NotificationFailure: LocalizedError, Sendable {
  let message: String
  var errorDescription: String? { message }
}

/// 原生系统集成设置；业务消息仍由既有 MoviePilot 通知渠道和通知中心处理。
@MainActor
final class NotificationController: UITableViewController {
  private let coordinator: WebCoordinator
  private let defaults: UserDefaults
  private let centerKey: String
  private var center: NotificationCenterAddress
  private var instanceCenter: NotificationCenterAddress?
  private var code: String?
  private var summary = "正在读取通知绑定…"
  private var busy = false

  /// 设置页只绑定当前协调器；切换实例后旧文档的请求不能回写新会话。
  init(coordinator: WebCoordinator, defaults: UserDefaults = .standard) {
    self.coordinator = coordinator
    self.defaults = defaults
    let key = "moviepilot.notification.center.\(coordinator.instance.id)"
    centerKey = key
    center =
      (try? NotificationCenterAddress(
        defaults.string(forKey: key) ?? NotificationCenterAddress.defaultAddress))
      ?? .defaultValue
    super.init(style: .insetGrouped)
  }

  /// 由当前实例显式创建，不支持 storyboard 恢复失效的会话。
  required init?(coder: NSCoder) { fatalError("Use init(coordinator:)") }

  /// 免费自签以主屏幕通知为主要入口，签名支持 APNs 时补充原生开关。
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "通知"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
    tableView.accessibilityIdentifier = "notification-settings"
    NativeModalAppearance.apply(to: self)
    Task { [weak self] in await self?.perform("status") }
  }

  /// 单页展示明确的操作步骤，不在容器内重写通知业务页面。
  override func numberOfSections(in tableView: UITableView) -> Int { 4 }

  /// 主屏幕绑定、系统通知和设备管理分别沿用各自系统生命周期。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case 0: return instanceCenter.map { $0 != center } == true ? 3 : 2
    case 1: return code == nil ? 3 : 4
    case 2: return NotificationService.shared.environment == nil ? 1 : 2
    default: return 3
    }
  }

  /// 系统分组标题说明通知归属，避免用户把免费自签与 APNs 混淆。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    ["通知服务中心", "主屏幕通知", "系统通知", "当前安装"][section]
  }

  /// 设备选择的中心须与后台签发绑定码的中心一致，避免将绑定码交给其他服务。
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    guard section == 0 else { return nil }
    if let instanceCenter, instanceCenter != center {
      return "实例 AppPush 当前使用 \(instanceCenter.displayURL)。请在后台配置相同地址，或选择“使用实例配置”后绑定。"
    }
    return "默认使用 https://movie-pilot.org。更换服务中心时，实例的 AppPush 渠道也须使用相同地址。"
  }

  /// 绑定码只在当前设置页短暂显示，退出页面不写入日志或持久配置。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.backgroundConfiguration = .clear()
    cell.textLabel?.numberOfLines = 0
    cell.detailTextLabel?.numberOfLines = 0
    cell.selectionStyle = .none
    cell.isUserInteractionEnabled = !busy
    switch (indexPath.section, indexPath.row) {
    case (0, 0):
      button(cell, title: "服务地址", id: "notification-service-center")
      cell.detailTextLabel?.text = center.displayURL
      cell.accessibilityValue = center.displayURL
      cell.accessoryType = .disclosureIndicator
    case (0, 1): button(cell, title: "使用默认服务中心", id: "notification-center-reset")
    case (0, 2): button(cell, title: "使用实例配置", id: "notification-center-instance")
    case (1, 0):
      cell.textLabel?.text = "免费自签也可接收通知"
      cell.detailTextLabel?.text = "在 Safari 打开通知网页，添加到主屏幕，再从主屏幕打开并输入绑定码。通知由主屏幕网页接收，点击后可返回 App。"
    case (1, 1): button(cell, title: "生成绑定码", id: "notification-generate")
    case (1, 2): button(cell, title: "打开通知网页", id: "notification-open-page")
    case (1, 3):
      button(cell, title: "复制绑定码", id: "notification-copy-code")
      cell.detailTextLabel?.text = "\(code ?? "")\n十分钟内有效，仅可使用一次。请只粘贴到你自己的通知网页。"
      cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    case (2, 0):
      cell.textLabel?.text =
        NotificationService.shared.environment == nil ? "当前签名使用主屏幕通知" : "原生通知需要系统授权"
      cell.detailTextLabel?.text =
        NotificationService.shared.registrationError
        ?? (NotificationService.shared.environment == nil
          ? "免费 Apple 个人签名没有 APNs 能力。主屏幕通知使用相同的私有 Server，无需开发者账号。"
          : "使用带 Push Notifications 能力的签名和已配置的 Server 后开启。")
    case (2, 1): button(cell, title: "开启系统通知", id: "notification-enable-native")
    case (3, 0): cell.textLabel?.text = summary
    case (3, 1): button(cell, title: "发送测试通知", id: "notification-test")
    default:
      button(cell, title: "解除本机及配对网页绑定", id: "notification-remove")
      cell.textLabel?.textColor = .systemRed
    }
    return cell
  }

  /// 可点击行保留系统字体、触控高度和辅助功能，不制造自定义弹出菜单。
  private func button(_ cell: UITableViewCell, title: String, id: String) {
    cell.textLabel?.text = title
    cell.textLabel?.textColor = busy ? .secondaryLabel : .tintColor
    cell.selectionStyle = .default
    cell.accessibilityIdentifier = id
    cell.accessibilityTraits.insert(.button)
  }

  /// 只有显式点击才申请权限、生成能力码或发送测试消息。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !busy else { return }
    switch (indexPath.section, indexPath.row) {
    case (0, 0): editCenter()
    case (0, 1): selectCenter(.defaultValue)
    case (0, 2):
      if let instanceCenter { selectCenter(instanceCenter) }
    case (1, 1): Task { await perform("pair") }
    case (1, 2): UIApplication.shared.open(center.pageURL)
    case (1, 3):
      UIPasteboard.general.string = code
      show("绑定码已复制。请在主屏幕通知网页中粘贴。")
    case (2, 1):
      Task { show(await NotificationService.shared.enable()) }
    case (3, 1): Task { await perform("test") }
    case (3, 2): Task { await perform("unregister") }
    default: break
    }
  }

  /// 只保存当前实例的非敏感中心地址，切换中心后不继续显示旧绑定码。
  private func selectCenter(_ value: NotificationCenterAddress) {
    center = value
    defaults.set(value.displayURL, forKey: centerKey)
    code = nil
    summary = "通知服务中心已更新，请重新生成绑定码。"
    tableView.reloadData()
  }

  /// 系统输入框允许修改中心；无效、明文公网或带凭据的地址不能保存。
  private func editCenter() {
    let alert = UIAlertController(
      title: "通知服务中心", message: "请输入 HTTPS 服务地址，并与实例的 AppPush 消息中心保持一致。",
      preferredStyle: .alert)
    alert.addTextField { [center] field in
      field.text = center.displayURL
      field.placeholder = NotificationCenterAddress.defaultAddress
      field.keyboardType = .URL
      field.autocapitalizationType = .none
      field.autocorrectionType = .no
      field.accessibilityIdentifier = "notification-center-address"
    }
    let save = UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
      guard let raw = alert?.textFields?.first?.text,
        let value = try? NotificationCenterAddress(raw)
      else { return }
      self?.selectCenter(value)
    }
    if let field = alert.textFields?.first {
      field.addAction(
        UIAction { [weak field, weak save] _ in
          save?.isEnabled = (try? NotificationCenterAddress(field?.text ?? "")) != nil
        }, for: .editingChanged)
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(save)
    present(alert, animated: true)
  }

  /// 用户操作串行执行；响应只用于本页，失败后保留可重试入口。
  private func perform(_ action: String) async {
    guard !busy else { return }
    busy = true
    tableView.reloadData()
    defer {
      busy = false
      tableView.reloadData()
    }
    do {
      let data = try await coordinator.notificationRequest(action)
      if action == "status" || action == "pair" {
        instanceCenter = nil
        if case .string(let raw) = data["relay_url"],
          let value = NotificationCenterAddress(notificationPage: raw)
        {
          instanceCenter = value
          if defaults.string(forKey: centerKey) == nil { center = value }
        }
      }
      if case .string(let owner) = data["owner"] { NotificationService.shared.identified(owner) }
      switch action {
      case "pair":
        guard instanceCenter == center else {
          code = nil
          throw NotificationFailure(message: "通知服务中心与实例 AppPush 配置不一致，请先统一服务地址后重新生成绑定码。")
        }
        if case .string(let value) = data["code"] { code = value }
        summary = "绑定码已生成，完成主屏幕网页绑定后可发送测试通知。"
      case "unregister":
        NotificationService.shared.disable()
        code = nil
        summary = "当前安装已解除绑定。"
      case "test":
        if case .number(let count) = data["total"], case .number(let accepted) = data["accepted"] {
          show(count == 0 ? "当前账号还没有绑定通知设备。" : "已提交 \(Int(accepted))/\(Int(count)) 个设备，请检查系统通知。")
        }
      default:
        if case .array(let devices) = data["devices"] {
          summary = "当前账号已绑定 \(devices.count) 个通知设备。"
        }
      }
    } catch {
      summary = error.localizedDescription
      if action != "status" { show(error.localizedDescription) }
    }
  }

  /// 操作结果使用系统提示框；不回显服务器原始响应。
  private func show(_ message: String) {
    guard presentedViewController == nil else { return }
    let alert = UIAlertController(title: "通知", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }
}
