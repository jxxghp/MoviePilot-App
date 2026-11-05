import Foundation

/// 通知管理失败保留可恢复原因，未加载渠道不应被解释为账号未登录。
public struct NotificationFailure: LocalizedError, Sendable {
  public let message: String

  /// 将后端兼容错误转为具体配置步骤，其他服务错误继续保留原有含义。
  public init(message: String) {
    switch message {
    case "该通知渠道未启用或不支持此管理动作", "请先配置并启用 AppPush 私有通知渠道",
      "请先配置并启用 AppPush 通知渠道。":
      self.message = "请在 MoviePilot「设定 → 通知」中添加、启用并保存 AppPush 渠道；若已启用，请更新后端后重试。"
    default:
      self.message = message
    }
  }

  /// 设置页与系统提示框展示同一原因，不拼接认证信息或网络响应。
  public var errorDescription: String? { message }
}
