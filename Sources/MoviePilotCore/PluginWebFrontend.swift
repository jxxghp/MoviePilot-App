import Foundation

/// 联邦（`render_mode == "vue"`）插件兼容宿主需要加载的 Web 前端入口。
///
/// 原生 App 可以直接连接后端 API 端口（默认 3001），该端口只提供 `/api`，不提供前端页面；
/// 联邦插件必须借助前端运行时渲染，因此需要按「当前地址 → 同主机前端端口 → 访问域名」的顺序
/// 找到真正返回前端 `index.html` 的入口。前端会把 `/api` 反向代理到同一后端，令牌与资源 Cookie 可直接复用。
public enum PluginWebFrontend {
  /// 生成按优先级排列且去重的候选入口。
  /// - Parameters:
  ///   - api: 用户配置的实例地址（可能是前端，也可能是后端 API 端口）。
  ///   - frontendPort: 后端系统配置中的 `NGINX_PORT`（前端监听端口）。
  ///   - appDomain: 后端系统配置中的 `APP_DOMAIN`（用户对外访问域名）。
  public static func candidates(
    api: ServerAddress, frontendPort: Int?, appDomain: String?
  ) -> [ServerAddress] {
    var result: [ServerAddress] = [api]
    func append(_ candidate: ServerAddress?) {
      guard let candidate, !result.contains(where: { $0.origin == candidate.origin }) else {
        return
      }
      result.append(candidate)
    }
    if let frontendPort, (1...65535).contains(frontendPort),
      var components = URLComponents(url: api.url, resolvingAgainstBaseURL: false)
    {
      // 前端与后端同主机部署时只替换端口；路径前缀保持一致（反向代理子路径部署）。
      components.port = frontendPort
      append(components.url.flatMap { try? ServerAddress($0.absoluteString) })
    }
    if let domain = appDomain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
      let normalized = domain.contains("://") ? domain : "\(api.origin.scheme)://\(domain)"
      if let address = try? ServerAddress(normalized),
        // 访问域名只接受与当前连接同等或更安全的协议，避免把令牌带到明文远端。
        address.origin.scheme == "https" || api.origin.scheme == "http"
      {
        append(address)
      }
    }
    return result
  }

  /// 判断探测响应是否为 MoviePilot 前端入口文档（HTML 且包含 Vue 挂载点）。
  public static func isFrontendDocument(statusCode: Int, contentType: String?, body: Data) -> Bool {
    guard (200..<300).contains(statusCode),
      contentType?.lowercased().contains("text/html") == true
    else { return false }
    let text = String(decoding: body.prefix(256 * 1024), as: UTF8.self)
    return text.contains("id=\"app\"") || text.contains("id='app'")
  }
}
