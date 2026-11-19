import Foundation

/// 现有 AppPage 导航声明；正文仍为远程 Vue，不虚构通用 JSON 全页接口。
public struct PluginAppPageDeclaration: Equatable, Sendable {
  public let pluginID: String?
  public let navigationKey: String?
  public let title: String?
  public let permission: PluginJSONValue?
  public let pointer: String
  public let raw: PluginJSONValue

  /// 与 federationLoader 的候选顺序一致；这只是名称数据，不下载/执行模块。
  public var remoteComponentCandidates: [String] {
    let key = (navigationKey ?? "main").trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty || key.lowercased() == "main" { return ["AppPage", "Page"] }
    let parts = key.components(
      separatedBy: CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "-_"))
    ).filter { !$0.isEmpty }
    let pascal = parts.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
    return (pascal.isEmpty ? [] : ["AppPage" + pascal]) + ["AppPage", "Page"]
  }
}

/// 导航完整响应与诊断，包含未识别的字段、分组及权限，不替用户授予权限。
public struct PluginAppPageDocument: Equatable, Sendable {
  public let rawData: Data
  public let raw: PluginJSONValue
  public let items: [PluginAppPageDeclaration]
  public let diagnostics: [PluginUIDiagnostic]
}

/// 仪表板发现项只保存物理插件 ID 和 key，不能以同名源插件代替。
public struct PluginDashboardDeclaration: Equatable, Sendable {
  public let pluginID: String?
  public let key: String?
  public let name: String?
  public let pointer: String
  public let raw: PluginJSONValue
}

/// 仪表板元信息独立于面板内容/布局，保留源次序及未知数据。
public struct PluginDashboardIndex: Equatable, Sendable {
  public let rawData: Data
  public let raw: PluginJSONValue
  public let items: [PluginDashboardDeclaration]
  public let diagnostics: [PluginUIDiagnostic]
}

/// 只读解析既有发现响应，沿用相同 JSON 资源预算和取消规则。
public enum PluginNavigationDecoder {
  /// sidebar_nav 条目不包含 AppPage JSON 正文；所有声明仍需后端权限和远程宿主。
  public static func appPages(
    _ data: Data, limits: PluginJSONLimits = .standard
  ) throws -> PluginAppPageDocument {
    let raw = try PluginJSONReader.parse(data, limits: limits)
    var diagnostics: [PluginUIDiagnostic] = []
    let items = try declarations(
      raw, required: ["plugin_id", "nav_key", "title"], diagnostics: &diagnostics
    )
    .map { pointer, value in
      PluginAppPageDeclaration(
        pluginID: value.object?["plugin_id"]?.string,
        navigationKey: value.object?["nav_key"]?.string,
        title: value.object?["title"]?.string, permission: value.object?["permission"],
        pointer: pointer, raw: value)
    }
    return .init(rawData: data, raw: raw, items: items, diagnostics: diagnostics)
  }

  /// dashboard/meta 的空 key 合法；非法项目保留并诊断，不能悄悄过滤而误判完整列表。
  public static func dashboards(
    _ data: Data, limits: PluginJSONLimits = .standard
  ) throws -> PluginDashboardIndex {
    let raw = try PluginJSONReader.parse(data, limits: limits)
    var diagnostics: [PluginUIDiagnostic] = []
    let items = try declarations(raw, required: ["id", "key", "name"], diagnostics: &diagnostics)
      .map { pointer, value in
        PluginDashboardDeclaration(
          pluginID: value.object?["id"]?.string, key: value.object?["key"]?.string,
          name: value.object?["name"]?.string, pointer: pointer, raw: value)
      }
    return .init(rawData: data, raw: raw, items: items, diagnostics: diagnostics)
  }

  /// 使用 JSON Pointer 标明每个错误字段；不输出字段值或对未验证权限做缺省放行。
  private static func declarations(
    _ raw: PluginJSONValue, required: [String], diagnostics: inout [PluginUIDiagnostic]
  ) throws -> [(String, PluginJSONValue)] {
    guard let values = raw.array else {
      diagnostics.append(.init(code: .invalidRoot, severity: .error, pointer: ""))
      return []
    }
    guard values.count <= 10_000 else {
      throw PluginUIDecodingError.nodeLimitExceeded(pointer: "")
    }
    return try values.enumerated().map { index, value in
      try Task.checkCancellation()
      let pointer = "/" + String(index)
      if value.object == nil {
        diagnostics.append(.init(code: .invalidField, severity: .error, pointer: pointer))
      }
      for key in required where value.object?[key]?.string == nil {
        diagnostics.append(
          .init(
            code: .invalidField, severity: .error,
            pointer: PluginJSONPointer.appending(key, to: pointer)))
      }
      return (pointer, value)
    }
  }
}
