import Foundation

/// 网页保留链接与播放器协议的所有权，原生只判断能否交给系统打开。
public enum WebLink {
  /// 普通网页使用独立浏览器；已支持的系统和媒体协议由 iOS 选择对应 App。
  public enum Destination: Equatable, Sendable { case browser, application }

  /// 仅接受网页现有功能使用的协议，拒绝文件、脚本和带内嵌账号密码的链接。
  public static func destination(for url: URL) -> Destination? {
    guard url.user == nil, url.password == nil, let scheme = url.scheme?.lowercased() else {
      return nil
    }
    if ["http", "https"].contains(scheme) {
      return WebOrigin(url: url) == nil ? nil : .browser
    }
    if ["mailto", "tel", "magnet", "thunder", "plex", "jellyfin", "emby", "trimemedia", "douban"]
      .contains(scheme)
    {
      return .application
    }
    return nil
  }
}
