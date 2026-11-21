import Foundation

/// 已安装清单的最小原生投影；配置目标来自后端记录，不来自配置文档。
public struct NativeInstalledPlugin: Decodable, Sendable, Identifiable {
  public let target: PluginFormTarget
  public let name: String
  public let summary: String
  public let version: String
  public let icon: String?
  public let author: String?
  public let authorURL: String?
  public let state: Bool?
  public let hasPage: Bool

  /// 列表身份保持后端物理 ID，分身不能与源插件合并。
  public var id: String { target.physicalID }

  /// 直接构造已校验的已安装插件记录。
  public init(
    target: PluginFormTarget,
    name: String,
    summary: String = "",
    version: String = "",
    icon: String? = nil,
    author: String? = nil,
    authorURL: String? = nil,
    state: Bool? = nil,
    hasPage: Bool = false
  ) {
    self.target = target
    self.name = name
    self.summary = summary
    self.version = version
    self.icon = icon
    self.author = author
    self.authorURL = authorURL
    self.state = state
    self.hasPage = hasPage
  }

  /// 对配置入口所需字段明确解码，损坏身份/非安装记录不被悄悄过滤。
  public init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: Keys.self)
    let id = try fields.decode(String.self, forKey: .id)
    let rawSource = try fields.decodeIfPresent(String.self, forKey: .source)
    let normalizedSource = (rawSource?.isEmpty == true) ? nil : rawSource
    target = try PluginFormTarget(physicalID: id, sourceID: normalizedSource)
    guard try fields.decodeIfPresent(Bool.self, forKey: .installed) == true else {
      throw PluginFormError.invalidTarget
    }
    name = try fields.decodeIfPresent(String.self, forKey: .name) ?? id
    summary = try fields.decodeIfPresent(String.self, forKey: .summary) ?? ""
    version = try fields.decodeIfPresent(String.self, forKey: .version) ?? ""
    icon = try? fields.decodeIfPresent(String.self, forKey: .icon)
    author = try? fields.decodeIfPresent(String.self, forKey: .author)
    authorURL = try? fields.decodeIfPresent(String.self, forKey: .authorURL)
    state = try? fields.decodeIfPresent(Bool.self, forKey: .state)
    hasPage = (try? fields.decodeIfPresent(Bool.self, forKey: .hasPage)) ?? false
  }

  /// 仅映射现有插件 API 字段，不复制安装/卸载/市场业务逻辑。
  private enum Keys: String, CodingKey {
    case id, installed, state
    case source = "source_plugin_id"
    case name = "plugin_name"
    case summary = "plugin_desc"
    case version = "plugin_version"
    case icon = "plugin_icon"
    case author = "plugin_author"
    case authorURL = "author_url"
    case hasPage = "has_page"
  }
}
