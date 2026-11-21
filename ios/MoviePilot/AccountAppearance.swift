import Foundation

/// 清理旧版 1.x 按实例存储的网页主题外观缓存，确保忘记实例后无历史残留。
@MainActor
enum AccountAppearance {
  /// 忘记实例时同步移除其旧版外观偏好，其他实例不受影响。
  static func forget(_ instance: UUID) {
    UserDefaults.standard.removeObject(forKey: "moviepilot.appearance.\(instance.uuidString).v1")
  }
}
