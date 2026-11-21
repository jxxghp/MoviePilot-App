import CryptoKit
import Foundation
import ImageIO
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 实体品牌图标分类：下载器、媒体服务器、通知渠道、媒体数据源与存储类型。
enum NativeBrandIconKind {
  case downloader
  case mediaServer
  case notification
  case storage
  case mediaSource
}

/// 真实品牌图标组件：复用 MoviePilot 官方前端一致的品牌 Logo 资产；仅限定圆角，不叠加额外背景与边框。
@MainActor
struct NativeBrandIcon: View {
  let kind: NativeBrandIconKind
  let type: String
  var size: CGFloat = 40
  var cornerRadius: CGFloat = 11

  var body: some View {
    Image(assetName)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .accessibilityHidden(true)
  }

  /// 将后端配置类型映射至内嵌真实品牌图标资源名。
  private var assetName: String {
    let key = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch kind {
    case .downloader:
      switch key {
      case "qbittorrent", "qb": return "logo-qbittorrent"
      case "transmission", "tr": return "logo-transmission"
      case "rtorrent": return "logo-rtorrent"
      default: return "logo-downloader"
      }
    case .mediaServer:
      switch key {
      case "emby": return "logo-emby"
      case "jellyfin": return "logo-jellyfin"
      case "plex": return "logo-plex"
      case "trimemedia", "fnos": return "logo-trimemedia"
      case "ugreen": return "logo-ugreen"
      case "zspace": return "logo-zspace"
      case "mediavault", "vyo": return "logo-vyo"
      default: return "logo-mediaserver"
      }
    case .notification:
      switch key {
      case "wechat", "微信", "企业微信": return "logo-wechat"
      case "wechatclawbot", "clawbot", "微信clawbot": return "logo-clawbot"
      case "feishu", "飞书": return "logo-feishu"
      case "telegram": return "logo-telegram"
      case "qqbot", "qq": return "logo-qq"
      case "vocechat": return "logo-vocechat"
      case "synologychat": return "logo-synologychat"
      case "slack": return "logo-slack"
      case "discord": return "logo-discord"
      case "dingtalk", "钉钉": return "logo-dingtalk"
      case "webpush", "web": return "logo-chrome"
      case "apppush", "webagent": return "BrandMark"
      default: return "logo-notification"
      }
    case .storage:
      switch key {
      case "u115", "115": return "logo-u115"
      case "alipan": return "logo-alipan"
      case "rclone": return "logo-rclone"
      case "smb": return "logo-smb"
      default: return "logo-storage"
      }
    case .mediaSource:
      switch key {
      case "themoviedb", "tmdb": return "logo-tmdb"
      case "douban", "doubanmusic", "douban_music": return "logo-douban"
      case "bangumi": return "logo-bangumi"
      case "musicbrainz": return "logo-musicbrainz"
      default: return "logo-mediaserver"
      }
    }
  }
}

/// 品牌图标可视化选项描述：用于下载器、媒体服务器、媒体数据源、通知渠道与存储类型的卡片选择。
struct NativeBrandChoiceItem: Identifiable, Hashable {
  let id: String
  let title: String
  var subtitle: String? = nil
  var iconType: String? = nil

  var resolvedIconType: String { iconType ?? id }
}

/// 单选品牌 Logo 卡片网格：以品牌图标 + 名称 + 选中高光描边与勾选徽章替代纯文字下拉框。
@MainActor
struct NativeBrandOptionGrid: View {
  let kind: NativeBrandIconKind
  let items: [NativeBrandChoiceItem]
  @Binding var selection: String
  var columns: Int = 3
  var disabled: Bool = false

  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    let gridColumns = Array(
      repeating: GridItem(.flexible(), spacing: 10), count: max(columns, 1))
    LazyVGrid(columns: gridColumns, spacing: 10) {
      ForEach(items) { item in
        let isSelected = selection.lowercased() == item.id.lowercased()
        Button {
          guard !disabled else { return }
          withAnimation(.easeOut(duration: 0.16)) {
            selection = item.id
          }
        } label: {
          brandTile(item: item, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
      }
    }
    .opacity(disabled ? 0.72 : 1.0)
  }

  private func brandTile(item: NativeBrandChoiceItem, isSelected: Bool) -> some View {
    VStack(spacing: 8) {
      NativeBrandIcon(
        kind: kind, type: item.resolvedIconType, size: 36, cornerRadius: 10)
      VStack(spacing: 2) {
        Text(item.title)
          .font(.caption.weight(isSelected ? .semibold : .medium))
          .foregroundStyle(isSelected ? appearance.accentColor : .primary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        if let subtitle = item.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: item.subtitle == nil ? 80 : 92)
    .padding(.horizontal, 8)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(isSelected ? appearance.accentColor.opacity(0.14) : NativeTheme.chipFill)
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
              isSelected ? appearance.accentColor.opacity(0.75) : NativeTheme.chipBorder,
              lineWidth: isSelected ? 1.4 : 0.7
            )
        }
    }
    .overlay(alignment: .topTrailing) {
      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(appearance.accentColor)
          .padding(6)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

/// 多选品牌 Logo 卡片网格：用于媒体搜索数据源等可多选的品牌配置。
@MainActor
struct NativeBrandMultiOptionGrid: View {
  let kind: NativeBrandIconKind
  let items: [NativeBrandChoiceItem]
  @Binding var selection: Set<String>
  var columns: Int = 2

  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    let singleColumn = max(columns, 1) == 1
    let gridColumns = Array(
      repeating: GridItem(.flexible(), spacing: 10), count: max(columns, 1))
    LazyVGrid(columns: gridColumns, spacing: 10) {
      ForEach(items) { item in
        let isSelected = selection.contains(item.id)
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            if isSelected {
              selection.remove(item.id)
            } else {
              selection.insert(item.id)
            }
          }
        } label: {
          HStack(spacing: singleColumn ? 12 : 11) {
            NativeBrandIcon(
              kind: kind, type: item.resolvedIconType, size: 36, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 2) {
              Text(item.title)
                .font(
                  (singleColumn ? Font.body : Font.subheadline).weight(
                    isSelected ? .semibold : .medium)
                )
                .foregroundStyle(.primary)
                .lineLimit(singleColumn ? 2 : 1)
                .minimumScaleFactor(singleColumn ? 1.0 : 0.85)
                .multilineTextAlignment(.leading)
              if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                  .font(singleColumn ? .caption : .caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(singleColumn ? 2 : 1)
                  .multilineTextAlignment(.leading)
              }
            }
            Spacer(minLength: singleColumn ? 8 : 4)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
              .font(.system(size: singleColumn ? 19 : 18, weight: .medium))
              .foregroundStyle(isSelected ? appearance.accentColor : Color.secondary.opacity(0.45))
          }
          .padding(.horizontal, singleColumn ? 14 : 12)
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
          .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(isSelected ? appearance.accentColor.opacity(0.14) : NativeTheme.chipFill)
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .strokeBorder(
                    isSelected ? appearance.accentColor.opacity(0.75) : NativeTheme.chipBorder,
                    lineWidth: isSelected ? 1.4 : 0.7
                  )
              }
          }
          .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// 站点真实图标视图：调用 `GET /api/v1/site/icon/{id}` 加载并缓存真实站点图标，缺失时回退官方默认站点图标；统一裁剪为圆角方形轮廓。
@MainActor
struct NativeSiteIconView: View {
  let session: NativeSession
  let siteID: Int
  var size: CGFloat = 40
  var active: Bool = true
  @State private var image: UIImage?

  private var cornerRadius: CGFloat {
    max(6, (size * 0.24).rounded())
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    Group {
      if let resolved = image ?? NativeEntityIconCache.shared.image(for: cacheKey) {
        let ratio = resolved.size.height > 0 ? resolved.size.width / resolved.size.height : 1.0
        if abs(ratio - 1.0) <= 0.22 {
          Image(uiImage: resolved)
            .resizable()
            .scaledToFill()
        } else {
          Image(uiImage: resolved)
            .resizable()
            .scaledToFit()
        }
      } else {
        Image("logo-site")
          .resizable()
          .scaledToFill()
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .opacity(active ? 1.0 : 0.56)
    .task(id: cacheKey) { await load() }
    .accessibilityHidden(true)
  }

  private var cacheKey: String {
    "site|\(session.scope.instanceID.uuidString)|\(session.scope.userID)|\(siteID)"
  }

  private func load() async {
    let key = cacheKey
    let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
    if let cached = NativeEntityIconCache.shared.image(for: key) {
      image = cached
      return
    }
    if let disk = await NativeEntityIconCache.shared.diskImage(
      for: key, scopeDir: scopeDir, limit: Int(size * 3))
    {
      guard !Task.isCancelled else { return }
      image = disk
      return
    }
    guard let endpoint = try? APIEndpoint(path: ["site", "icon", String(siteID)]) else { return }
    guard
      let payload = try? await session.request(endpoint, as: NativeSiteIconPayload.self).value,
      let rawIcon = payload.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawIcon.isEmpty
    else { return }
    try? Task.checkCancellation()
    if let decoded = await NativeEntityIconLoader.loadImage(
      reference: rawIcon, session: session, maximumPixelSize: Int(size * 3))
    {
      guard !Task.isCancelled else { return }
      NativeEntityIconCache.shared.store(decoded, for: key, scopeDir: scopeDir)
      image = decoded
    }
  }
}

/// 插件真实图标视图：兼容绝对 URL、同源 `/plugin_icon/<name>` 与官方仓库回退图标；统一裁剪为圆角方形轮廓。
@MainActor
struct NativePluginIconView: View {
  let session: NativeSession
  let iconReference: String?
  var size: CGFloat = 44
  var cornerRadius: CGFloat = 12
  var inactive: Bool = false
  @State private var image: UIImage?

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    Group {
      if let resolved = image ?? NativeEntityIconCache.shared.image(for: cacheKey) {
        let ratio = resolved.size.height > 0 ? resolved.size.width / resolved.size.height : 1.0
        if abs(ratio - 1.0) <= 0.22 {
          Image(uiImage: resolved)
            .resizable()
            .scaledToFill()
        } else {
          Image(uiImage: resolved)
            .resizable()
            .scaledToFit()
        }
      } else {
        Image("logo-plugin")
          .resizable()
          .scaledToFill()
      }
    }
    .frame(width: size, height: size)
    .clipShape(shape)
    .saturation(inactive ? 0.35 : 1.0)
    .opacity(inactive ? 0.72 : 1.0)
    .task(id: cacheKey) { await load() }
    .accessibilityHidden(true)
  }

  private var cacheKey: String {
    "plugin|\(session.scope.instanceID.uuidString)|\(session.scope.userID)|\(iconReference ?? "")"
  }

  private func load() async {
    let key = cacheKey
    let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
    if let cached = NativeEntityIconCache.shared.image(for: key) {
      image = cached
      return
    }
    guard let raw = iconReference?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
    else { return }
    let pixelLimit = Int(size * 3)
    if let disk = await NativeEntityIconCache.shared.diskImage(
      for: key, scopeDir: scopeDir, limit: pixelLimit)
    {
      guard !Task.isCancelled else { return }
      image = disk
      return
    }
    if raw.hasPrefix("data:") || raw.lowercased().hasPrefix("http://")
      || raw.lowercased().hasPrefix("https://")
    {
      if let loaded = await NativeEntityIconLoader.loadImage(
        reference: raw, session: session, maximumPixelSize: pixelLimit)
      {
        guard !Task.isCancelled else { return }
        NativeEntityIconCache.shared.store(loaded, for: key, scopeDir: scopeDir)
        image = loaded
      }
      return
    }

    // 相对插件图标：先尝试当前服务实例 `/plugin_icon/<file>`，再回退官方插件仓库公开图标。
    let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
    let fileName =
      cleaned.hasPrefix("plugin_icon/")
      ? String(cleaned.dropFirst("plugin_icon/".count)) : cleaned
    guard !fileName.isEmpty, !fileName.contains("..") else { return }

    if let instanceURL = URL(
      string: "plugin_icon/\(fileName)", relativeTo: session.instance.address.url)?.absoluteURL,
      let loaded = await NativeEntityIconLoader.fetchEphemeralImage(
        url: instanceURL, maximumPixelSize: pixelLimit)
    {
      guard !Task.isCancelled else { return }
      NativeEntityIconCache.shared.store(loaded, for: key, scopeDir: scopeDir)
      image = loaded
      return
    }

    if let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
      let fallbackURL = URL(
        string: "https://raw.githubusercontent.com/jxxghp/MoviePilot-Plugins/main/icons/\(encoded)"),
      let loaded = await NativeEntityIconLoader.fetchEphemeralImage(
        url: fallbackURL, maximumPixelSize: pixelLimit)
    {
      guard !Task.isCancelled else { return }
      NativeEntityIconCache.shared.store(loaded, for: key, scopeDir: scopeDir)
      image = loaded
    }
  }
}

/// 插件作者圆形头像：按前端 `resolvePluginAuthorAvatar` 规则解析 GitHub 头像，缺失时显示柔和人物徽标。
@MainActor
struct NativePluginAuthorAvatarView: View {
  let authorURL: String?
  let authorName: String?
  var size: CGFloat = 20
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .clipShape(Circle())
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable()
          .scaledToFit()
          .foregroundStyle(.secondary.opacity(0.72))
      }
    }
    .frame(width: size, height: size)
    .task(id: resolvedAvatarURL?.absoluteString ?? "") { await load() }
    .accessibilityHidden(true)
  }

  private var resolvedAvatarURL: URL? {
    Self.resolveGitHubAvatarURL(authorURL: authorURL, authorName: authorName)
  }

  private func load() async {
    image = nil
    guard let url = resolvedAvatarURL else { return }
    let key = "author|\(url.absoluteString)"
    if let cached = NativeEntityIconCache.shared.image(for: key) {
      image = cached
      return
    }
    if let loaded = await NativeEntityIconLoader.fetchEphemeralImage(
      url: url, maximumPixelSize: Int(size * 3))
    {
      guard !Task.isCancelled else { return }
      NativeEntityIconCache.shared.store(loaded, for: key)
      image = loaded
    }
  }

  /// 解析 GitHub 用户名并返回 `https://github.com/<owner>.png?size=64`。
  private static func resolveGitHubAvatarURL(authorURL: String?, authorName: String?) -> URL? {
    let pattern = #"^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$"#
    if let raw = authorURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      let firstSegment = raw.split(separator: ",", maxSplits: 1).first.map(String.init) ?? raw
      if let parsed = URL(string: firstSegment.trimmingCharacters(in: .whitespacesAndNewlines)),
        let host = parsed.host?.lowercased(), host == "github.com"
      {
        let owner = parsed.pathComponents
          .filter { $0 != "/" && !$0.isEmpty }
          .first?
          .replacingOccurrences(of: ".png", with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if let owner, owner.range(of: pattern, options: .regularExpression) != nil {
          return URL(string: "https://github.com/\(owner).png?size=64")
        }
      }
    }
    if let name = authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      let candidate =
        name
        .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "/" || $0 == " " })
        .first
        .map(String.init)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let candidate, candidate.range(of: pattern, options: .regularExpression) != nil {
        return URL(string: "https://github.com/\(candidate).png?size=64")
      }
    }
    return nil
  }
}

/// 用户真实头像组件：支持后端 `data:image/...;base64,...`、远程图片 URL 与同源相对路径，缺失时显示默认头像或首字徽标。
@MainActor
struct NativeUserAvatarView: View {
  let session: NativeSession
  let avatar: String?
  let name: String
  var isSuperuser: Bool = false
  var size: CGFloat = 40
  @State private var image: UIImage?

  var body: some View {
    ZStack {
      Circle()
        .fill(
          isSuperuser
            ? Color(red: 0.54, green: 0.38, blue: 0.80).opacity(0.65)
            : .white.opacity(0.14))
      if let resolved = image ?? NativeEntityIconCache.shared.image(for: cacheKey) {
        Image(uiImage: resolved)
          .resizable()
          .scaledToFill()
          .frame(width: size, height: size)
          .clipShape(Circle())
      } else {
        Image("logo-avatar-default")
          .resizable()
          .scaledToFill()
          .frame(width: size, height: size)
          .clipShape(Circle())
      }
    }
    .frame(width: size, height: size)
    .overlay {
      Circle()
        .strokeBorder(
          isSuperuser
            ? Color(red: 0.84, green: 0.72, blue: 1.0).opacity(0.45)
            : .white.opacity(0.22),
          lineWidth: 1)
    }
    .task(id: cacheKey) { await load() }
    .accessibilityHidden(true)
  }

  private var cacheKey: String {
    "user|\(session.scope.instanceID.uuidString)|\(session.scope.userID)|\(avatar ?? "")"
  }

  private func load() async {
    let key = cacheKey
    let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
    if let cached = NativeEntityIconCache.shared.image(for: key) {
      image = cached
      return
    }
    guard let raw = avatar?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
    else { return }
    if let disk = await NativeEntityIconCache.shared.diskImage(
      for: key, scopeDir: scopeDir, limit: Int(size * 3))
    {
      guard !Task.isCancelled else { return }
      image = disk
      return
    }
    if let loaded = await NativeEntityIconLoader.loadImage(
      reference: raw, session: session, maximumPixelSize: Int(size * 3))
    {
      guard !Task.isCancelled else { return }
      NativeEntityIconCache.shared.store(loaded, for: key, scopeDir: scopeDir)
      image = loaded
    }
  }
}

/// 底部导航栏「我的」圆形用户头像渲染器：仅当用户实际设置了头像时返回原色圆形位图。
enum NativeUserAvatarRenderer {
  @MainActor
  static func loadTabAvatar(
    session: NativeSession,
    avatar: String?,
    pointSize: CGFloat = 25
  ) async -> UIImage? {
    guard let raw = avatar?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
    else { return nil }
    let cacheKey =
      "tab-avatar|\(session.scope.instanceID.uuidString)|\(session.scope.generation.uuidString)|\(raw)"
    if let cached = NativeEntityIconCache.shared.image(for: cacheKey) {
      return cached
    }
    guard
      let source = await NativeEntityIconLoader.loadImage(
        reference: raw, session: session, maximumPixelSize: Int(pointSize * 3))
    else { return nil }
    let rendered = renderCircularTabIcon(source, pointSize: pointSize)
    NativeEntityIconCache.shared.store(rendered, for: cacheKey)
    return rendered
  }

  @MainActor
  private static func renderCircularTabIcon(_ source: UIImage, pointSize: CGFloat) -> UIImage {
    let targetSize = CGSize(width: pointSize, height: pointSize)
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let circular = renderer.image { context in
      let rect = CGRect(origin: .zero, size: targetSize)
      let path = UIBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
      context.cgContext.saveGState()
      path.addClip()

      let imageSize = source.size
      let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
      let drawWidth = imageSize.width * scale
      let drawHeight = imageSize.height * scale
      let drawRect = CGRect(
        x: (rect.width - drawWidth) / 2,
        y: (rect.height - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight)
      source.draw(in: drawRect)
      context.cgContext.restoreGState()

      UIColor.white.withAlphaComponent(0.32).setStroke()
      path.lineWidth = 0.8
      path.stroke()
    }
    return circular.withRenderingMode(.alwaysOriginal)
  }
}

/// 站点图标响应载体。
private struct NativeSiteIconPayload: Decodable, Sendable {
  let icon: String?
}

/// 统一实体图标加载工具：支持 data URI Base64 解码、后端同源图片代理与无凭据公开图标源回退。
enum NativeEntityIconLoader {
  private static let publicIconHosts: Set<String> = [
    "raw.githubusercontent.com",
    "github.com",
    "avatars.githubusercontent.com",
    "cdn.jsdelivr.net",
    "fastly.jsdelivr.net",
    "assets.fanart.tv",
    "image.tmdb.org",
  ]

  /// 按引用格式加载真实图标位图（`data:image/...`、HTTP(S) 代理/公开图源或同源相对路径）。
  @MainActor
  static func loadImage(
    reference: String,
    session: NativeSession,
    maximumPixelSize: Int
  ) async -> UIImage? {
    let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.lowercased().hasPrefix("data:image/") {
      return decodeDataURI(trimmed, maximumPixelSize: maximumPixelSize)
    }

    if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", url.host?.isEmpty == false
    {
      if let proxied = try? await session.requestImage(url, maximumWidth: maximumPixelSize),
        let decoded = decodeThumbnail(proxied.data, maximumPixelSize: maximumPixelSize)
      {
        return decoded
      }
      if let host = url.host?.lowercased(),
        scheme == "https",
        publicIconHosts.contains(host) || host == session.instance.address.url.host?.lowercased()
      {
        return await fetchEphemeralImage(url: url, maximumPixelSize: maximumPixelSize)
      }
      if let host = url.host?.lowercased(),
        host == session.instance.address.url.host?.lowercased()
      {
        return await fetchEphemeralImage(url: url, maximumPixelSize: maximumPixelSize)
      }
      return nil
    }

    // 相对路径（如 `/assets/...` 或 `avatars/...`）尝试相对实例地址读取。
    let normalized = trimmed.hasPrefix("./") ? String(trimmed.dropFirst(2)) : trimmed
    if !normalized.contains(".."),
      let resolved = URL(string: normalized, relativeTo: session.instance.address.url)?.absoluteURL
    {
      return await fetchEphemeralImage(url: resolved, maximumPixelSize: maximumPixelSize)
    }
    return nil
  }

  /// 使用无 Cookie、无凭据的临时会话拉取静态图标资源。
  static func fetchEphemeralImage(url: URL, maximumPixelSize: Int) async -> UIImage? {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCredentialStorage = nil
    config.timeoutIntervalForRequest = 8
    config.timeoutIntervalForResource = 12
    let client = URLSession(configuration: config)
    defer { client.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.setValue("image/*", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await client.data(for: request),
      let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode),
      data.count > 16,
      data.count <= 2 * 1024 * 1024
    else { return nil }
    return decodeThumbnail(data, maximumPixelSize: maximumPixelSize)
  }

  /// 解码 `data:image/...;base64,...` 图标字符串。
  private static func decodeDataURI(_ raw: String, maximumPixelSize: Int) -> UIImage? {
    guard let commaIndex = raw.firstIndex(of: ",") else { return nil }
    let header = raw[..<commaIndex].lowercased()
    guard header.contains("base64") else { return nil }
    let payload = String(raw[raw.index(after: commaIndex)...])
    guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
      data.count > 16,
      data.count <= 2 * 1024 * 1024
    else { return nil }
    return decodeThumbnail(data, maximumPixelSize: maximumPixelSize)
  }

  /// 使用 ImageIO 安全缩放到图标显示像素上限。
  private static func decodeThumbnail(_ data: Data, maximumPixelSize: Int) -> UIImage? {
    let limit = max(maximumPixelSize, 48)
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as CFDictionary)
    {
      return UIImage(cgImage: cgImage)
    }
    return UIImage(data: data)
  }
}

/// 二级实体图标缓存（L1 内存 + L2 本地磁盘），按实例与用户隔离，退出登录时同步清理。
@MainActor
final class NativeEntityIconCache {
  static let shared = NativeEntityIconCache()
  private let storage = NSCache<NSString, UIImage>()

  private init() {
    storage.totalCostLimit = 24 * 1024 * 1024
  }

  func image(for key: String) -> UIImage? {
    storage.object(forKey: key as NSString)
  }

  func diskImage(for key: String, scopeDir: String, limit: Int) async -> UIImage? {
    let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
      guard let url = Self.diskFileURL(for: key, scopeDir: scopeDir),
        let data = try? Data(contentsOf: url), !data.isEmpty
      else { return nil }
      return NativeMediaArtworkCache.decodeThumbnail(data, limit: limit)
    }.value
    if let decoded {
      store(decoded, for: key, scopeDir: nil)
    }
    return decoded
  }

  func store(_ image: UIImage, for key: String, scopeDir: String? = nil) {
    let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    storage.setObject(image, forKey: key as NSString, cost: max(cost, 1024))
    if let scopeDir, let png = image.pngData() {
      Task.detached(priority: .utility) {
        if let url = Self.diskFileURL(for: key, scopeDir: scopeDir) {
          let dir = url.deletingLastPathComponent()
          try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
          try? png.write(to: url, options: .atomic)
        }
      }
    }
  }

  func clearSession(_ session: NativeSession) {
    storage.removeAllObjects()
    let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
    Task.detached(priority: .utility) {
      if let dir = Self.cacheDirectory(scopeDir: scopeDir) {
        try? FileManager.default.removeItem(at: dir)
      }
    }
  }

  nonisolated private static func cacheDirectory(scopeDir: String) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("MoviePilotIconCache", isDirectory: true)
      .appendingPathComponent(scopeDir, isDirectory: true)
  }

  nonisolated private static func diskFileURL(for key: String, scopeDir: String) -> URL? {
    guard let dir = cacheDirectory(scopeDir: scopeDir) else { return nil }
    let digest = SHA256.hash(data: Data(key.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return dir.appendingPathComponent("\(hex).png")
  }
}
