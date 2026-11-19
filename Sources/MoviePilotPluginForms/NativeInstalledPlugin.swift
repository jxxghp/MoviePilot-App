import Foundation

/// 已安装清单的最小原生投影；配置目标来自后端记录，不来自配置文档。
public struct NativeInstalledPlugin: Decodable, Sendable, Identifiable {
  public let target: PluginFormTarget
  public let name: String
  public let summary: String
  public let version: String

  /// 列表身份保持后端物理 ID，分身不能与源插件合并。
  public var id: String { target.physicalID }

  /// 对配置入口所需字段明确解码，损坏身份/非安装记录不被悄悄过滤。
  public init(from decoder: any Decoder) throws {
    let fields = try decoder.container(keyedBy: Keys.self)
    let id = try fields.decode(String.self, forKey: .id)
    target = try PluginFormTarget(
      physicalID: id, sourceID: fields.decodeIfPresent(String.self, forKey: .source))
    guard try fields.decodeIfPresent(Bool.self, forKey: .installed) == true else {
      throw PluginFormError.invalidTarget
    }
    name = try fields.decodeIfPresent(String.self, forKey: .name) ?? id
    summary = try fields.decodeIfPresent(String.self, forKey: .summary) ?? ""
    version = try fields.decodeIfPresent(String.self, forKey: .version) ?? ""
  }

  /// 仅映射现有插件 API 字段，不复制安装/卸载/市场业务逻辑。
  private enum Keys: String, CodingKey {
    case id, installed
    case source = "source_plugin_id"
    case name = "plugin_name"
    case summary = "plugin_desc"
    case version = "plugin_version"
  }
}
