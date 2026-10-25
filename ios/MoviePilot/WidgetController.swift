import MoviePilotCore
import UIKit

/// 小组件仅设置本机只读资料；业务内容继续由原有 HTML 与后端生成。
@MainActor
final class WidgetController: UITableViewController, UIAdaptivePresentationControllerDelegate {
  private let coordinator: WebCoordinator
  private var state: WidgetSettingsState?
  private var operation: Task<Void, Never>?
  private var status = "正在读取…"

  /// 控制器只关联打开时的实例，关闭后取消等待，不保存主认证或专用 secret。
  init(coordinator: WebCoordinator) {
    self.coordinator = coordinator
    super.init(style: .insetGrouped)
  }

  /// 设置不从 storyboard 恢复，避免旧实例在系统恢复后继续操作。
  required init?(coder: NSCoder) { fatalError("Use init(coordinator:)") }

  /// 继续使用 UIKit 默认材质与系统分组，不按弹窗高度调整文字颜色。
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "小组件"
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.close() })
    tableView.accessibilityIdentifier = "widget-settings"
    navigationController?.presentationController?.delegate = self
    NativeModalAppearance.apply(to: self)
    run { [weak self] in try await self?.reloadState() }
  }

  /// 拖动关闭或退出设置时同样结束相关桥等待，旧结果不能回写不可见界面。
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || navigationController?.isBeingDismissed == true {
      operation?.cancel()
      operation = nil
    }
  }

  /// 拖动完成关闭后接续等待中的系统跳转，不能在 Sheet 仍挡住页面时抢先路由。
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    WidgetService.shared.resumePending(with: coordinator)
  }

  /// 当前启用资料、有限操作和添加指引各使用一组。
  override func numberOfSections(in tableView: UITableView) -> Int { 3 }

  /// 未启用不显示无效的刷新、改名或删除操作。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case 0: return state?.profile == nil ? 1 : 3
    case 1: return state?.profile == nil ? 1 : 4
    default: return 1
    }
  }

  /// 分组标题交给系统渲染，保持原生 Sheet 的明暗与转场行为。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    ["当前服务", "本机资料", "添加小组件"][section]
  }

  /// 说明只读、系统调度及续期，不向用户暴露桥协议或 Keychain 实现。
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    guard section == 1 else { return nil }
    return "每个服务使用当前账号的只读资料。有效期为 30 天，届时需在 App 内续期；退出账号会移除资料。更新频率由 iOS 决定。"
  }

  /// 表格只显示白名单状态，数据源错误不能变成假的已启用或空内容。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.backgroundConfiguration = .clear()
    cell.textLabel?.numberOfLines = 0
    cell.detailTextLabel?.numberOfLines = 0
    cell.selectionStyle = .none
    cell.isUserInteractionEnabled = false
    switch (indexPath.section, indexPath.row) {
    case (0, 0):
      cell.textLabel?.text = state?.profile?.name ?? (state == nil ? "小组件" : "尚未启用")
      cell.detailTextLabel?.text = status
    case (0, 1):
      cell.textLabel?.text = "上次采样"
      cell.detailTextLabel?.text =
        state?.generatedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚无数据"
    case (0, 2):
      cell.textLabel?.text = "有效期至"
      cell.detailTextLabel?.text = state?.profile.map {
        Date(timeIntervalSince1970: $0.credentialExpiresAt).formatted(
          date: .abbreviated, time: .shortened)
      }
    case (1, 0):
      action(cell, title: state?.profile == nil ? "启用当前账号" : "续期", id: "widget-enable")
      cell.isUserInteractionEnabled =
        operation == nil && state?.context.availableContents.isEmpty == false
    case (1, 1):
      action(cell, title: "刷新", id: "widget-refresh")
    case (1, 2):
      action(cell, title: "修改显示名称", id: "widget-rename")
    case (1, 3):
      action(cell, title: "移除本机资料", id: "widget-remove")
      cell.textLabel?.textColor = .systemRed
    default:
      cell.textLabel?.text = "桌面、锁屏与今天视图"
      cell.detailTextLabel?.text =
        "长按主屏幕空白处，选择“编辑”→“添加小组件”，搜索 MoviePilot。锁屏可在自定中添加；向右滑到今天视图，也可添加。编辑小组件可选择服务和内容。"
    }
    return cell
  }

  /// 只允许设置页当前可用动作，不用网页传入的任意字符串执行命令。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard operation == nil, indexPath.section == 1 else { return }
    switch indexPath.row {
    case 0:
      editName(enabling: true)
    case 1:
      run { [weak self] in
        guard let self else { return }
        if let profile = self.state?.profile {
          let outcome = try await WidgetService.shared.refresh(self.coordinator, profile: profile)
          guard outcome != .unavailable && outcome != .discarded else {
            throw WidgetBridgeError.unavailable
          }
        }
        try await self.reloadState()
      }
    case 2: editName(enabling: false)
    case 3:
      let alert = UIAlertController(
        title: "移除本机资料？", message: "使用此资料的小组件将停止显示内容。", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "取消", style: .cancel))
      alert.addAction(
        UIAlertAction(title: "移除", style: .destructive) { [weak self] _ in
          self?.run { [weak self] in
            guard let self else { return }
            try await WidgetService.shared.disable(self.coordinator)
            try await self.reloadState()
          }
        })
      present(alert, animated: true)
    default: break
    }
  }

  /// 明确的系统输入框只收本机显示名，不读取主账号或服务器配置。
  private func editName(enabling: Bool) {
    let alert = UIAlertController(
      title: enabling ? "启用小组件" : "修改显示名称", message: "填写便于区分服务的名称。", preferredStyle: .alert)
    alert.addTextField { [state] field in
      field.text = state?.profile?.name ?? "MoviePilot"
      field.placeholder = "显示名称"
      field.autocorrectionType = .no
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
        guard let name = alert?.textFields?.first?.text else { return }
        self?.run { [weak self] in
          guard let self else { return }
          if enabling {
            try await WidgetService.shared.enable(self.coordinator, name: name)
          } else if let profile = self.state?.profile {
            try await WidgetService.shared.rename(self.coordinator, profile: profile, name: name)
          }
          try await self.reloadState()
        }
      })
    present(alert, animated: true)
  }

  /// 异步操作只有一个所有者；取消后不弹错误，也不让旧视图恢复按钮状态。
  private func run(_ body: @escaping @MainActor () async throws -> Void) {
    guard operation == nil else { return }
    operation = Task { [weak self] in
      guard let self else { return }
      defer {
        self.operation = nil
        self.tableView.reloadData()
      }
      do {
        try await body()
      } catch {
        guard !Task.isCancelled else { return }
        if let error = error as? WidgetBridgeError,
          error == .unauthorized || error == .identityChanged || error == .forbidden
        {
          self.state = nil
        }
        self.status = self.message(for: error)
      }
    }
    tableView.reloadData()
  }

  /// 重新加载不会登记、轮换或延长凭据；UI 只显示当前相关操作的结果。
  private func reloadState() async throws {
    let current = try await WidgetService.shared.settings(coordinator)
    try Task.checkCancellation()
    state = current
    status = current.profile == nil ? "启用后可在系统小组件中选择此服务。" : "已启用，只读显示当前账号允许的内容。"
    if current.context.availableContents.isEmpty { status = "当前账号没有可用的小组件内容。" }
  }

  /// 错误文案固定，不拼接后端响应、原始异常或凭据。
  private func message(for error: any Error) -> String {
    switch error {
    case WidgetBridgeError.unsupported: return "当前页面暂不支持，请更新 MoviePilot 后重试。"
    case WidgetBridgeError.unauthorized, WidgetBridgeError.identityChanged:
      return "登录状态已变化，请重新打开设置。"
    case WidgetBridgeError.forbidden: return "当前账号没有可用的小组件内容。"
    case WidgetPlatformError.sharedStorageUnavailable: return "当前安装的共享区域不可用，请检查安装或续签后重试。"
    case WidgetBridgeError.invalidRequest: return "请输入较短的显示名称，并移除特殊控制字符。"
    case WidgetBridgeError.requestLimit: return "请重新加载页面后再试。"
    default: return "暂时无法读取，请解锁设备、检查连接后重试。"
    }
  }

  /// 系统标签色和禁用状态统一处理，不添加跟随半屏或全屏的手动颜色逻辑。
  private func action(_ cell: UITableViewCell, title: String, id: String) {
    cell.textLabel?.text = title
    cell.textLabel?.textColor = .tintColor
    cell.accessibilityIdentifier = id
    cell.isUserInteractionEnabled = operation == nil
    cell.selectionStyle = .default
  }

  /// 显式关闭先撤销设置操作，再在转场完成后接续等待中的组件导航。
  private func close() {
    operation?.cancel()
    operation = nil
    dismiss(animated: true) { [weak coordinator] in
      if let coordinator { WidgetService.shared.resumePending(with: coordinator) }
    }
  }
}
