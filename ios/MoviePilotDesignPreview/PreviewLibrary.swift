import Combine
import Foundation

/// 演示状态严格限于预览进程；导航和按钮可操作，但不读写主 App 或后端。
@MainActor
final class PreviewLibrary: ObservableObject {
  @Published var subscriptions: Set<String> = ["rings", "mobland"]
  @Published var downloads: Set<String> = ["rings", "voice", "simpsons"]
  @Published var notify = true
  @Published var pluginEnabled = true
  @Published var pluginOnce = false
  @Published var pluginSchedule = "0 9 * * *"
  @Published var savedNotice = false

  /// 订阅按钮与订阅页共享同一份内存状态，用于验证完整原生交互。
  func toggleSubscription(_ media: PreviewMedia) {
    if subscriptions.contains(media.id) {
      subscriptions.remove(media.id)
    } else {
      subscriptions.insert(media.id)
    }
  }
}
