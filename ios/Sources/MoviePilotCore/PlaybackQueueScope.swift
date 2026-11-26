import CryptoKit
import Foundation

/// 离线播放终态的持久化归属，隔离部署子路径和账号且不存储访问令牌。
public enum PlaybackQueueScope {
  /// 用规范化实例和稳定用户 ID 派生 v2 队列键，不迁移无法确定归属的 v1 记录。
  public static func storageKey(address: ServerAddress, accountID: Int) -> String {
    let identity = "\(address.url.absoluteString)\u{0000}\(accountID)"
    let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    return "nativeV2.playback.pendingStops.v2.\(digest)"
  }
}
