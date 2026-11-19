import Foundation
import WebKit

/// 仅清理既有网页/插件存储的兼容适配，不创建视图或加载任何网页。
@MainActor
enum LegacyWebsiteStorage {
  /// iOS 17 持久化容器按旧实例 UUID 删除；iOS 16 原有容器本来就是非持久化。
  static func erase(for instanceID: UUID) async {
    if #available(iOS 17.0, *) {
      let store = WKWebsiteDataStore(forIdentifier: instanceID)
      await store.removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
  }
}
