import Foundation
import MoviePilotCore
import UIKit

/// iOS 外部播放器安全拉起工具：
/// - 仅允许传递无实例主凭据的 STRM 直链或本机文件 URI，绝不向外部应用泄露 MoviePilot Cookie / JWT；
/// - 若用户配置了合法自定义 `externalPlayerTemplate` 则按模板渲染呼起，否则通过系统分享/打开面板交由用户选择。
@MainActor
enum ExternalPlayerLauncher {
  /// 判断给定来源是否可安全交给外部播放器打开。
  static func safeExternalURL(for manifest: MediaPlaybackManifest, activeURL: URL) -> URL? {
    if activeURL.isFileURL {
      return activeURL
    }
    if let strmURL = manifest.strmUrl,
      PlaybackRoutePlanner.isSafeHttpURL(strmURL.absoluteString)
    {
      return strmURL
    }
    // 媒体服务器直连或代理地址可能携带实例/个人会话状态，仅当明确为无认证外部直链时放行。
    if manifest.server == nil, PlaybackRoutePlanner.isSafeHttpURL(activeURL.absoluteString) {
      return activeURL
    }
    return nil
  }

  /// 拉起外部播放器；若配置了自定义 URL 模板则优先校验后拉起，否则弹出系统 `UIActivityViewController`。
  @discardableResult
  static func open(
    url: URL,
    title: String,
    from presenter: UIViewController,
    sourceView: UIView?
  ) -> Bool {
    let template = PlaybackEnginePreferences.externalPlayerTemplate
    if !template.isEmpty,
      !url.isFileURL,
      let customURL = PlaybackEngineRouter.buildExternalPlayerURL(
        template: template,
        mediaURL: url.absoluteString,
        title: title
      ),
      UIApplication.shared.canOpenURL(customURL)
    {
      UIApplication.shared.open(customURL, options: [:], completionHandler: nil)
      return true
    }

    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = activity.popoverPresentationController {
      popover.sourceView = sourceView ?? presenter.view
      popover.sourceRect = sourceView?.bounds ?? CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    presenter.present(activity, animated: true)
    return true
  }
}
