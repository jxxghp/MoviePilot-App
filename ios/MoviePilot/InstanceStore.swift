import Foundation
import MoviePilotCore

/// 非敏感实例配置；每个实例拥有独立的持久化 WebKit 数据容器。
struct SavedInstance: Codable, Equatable {
  let id: UUID
  let address: ServerAddress
}

/// 在应用沙箱内保存实例地址与容器标识，不读写网页密码、token 或 Cookie。
@MainActor
final class InstanceStore {
  private let defaults: UserDefaults
  private let key = "moviepilot.instances.v1"
  private let selectedKey = "moviepilot.instance.selected.v1"

  /// 可注入隔离的 defaults，避免配置操作依赖全局单例。
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  /// 读取已经校验的历史地址，损坏配置不作为可连接实例。
  var instances: [SavedInstance] {
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode([SavedInstance].self, from: data)) ?? []
  }

  /// 恢复上次选择；已忘记或损坏的实例回到连接页。
  var selected: SavedInstance? {
    guard let value = defaults.string(forKey: selectedKey) else { return nil }
    return instances.first { $0.id.uuidString == value }
  }

  /// 相同标准地址复用自己的容器，切换地址不能继承另一个实例的浏览器数据。
  func select(_ address: ServerAddress) throws -> SavedInstance {
    var values = instances
    let instance =
      values.first { $0.address == address } ?? SavedInstance(id: UUID(), address: address)
    if !values.contains(instance) { values.append(instance) }
    defaults.set(try JSONEncoder().encode(values), forKey: key)
    defaults.set(instance.id.uuidString, forKey: selectedKey)
    return instance
  }

  /// 仅清除当前选择，历史实例容器留存直到用户明确选择忘记。
  func deselect() { defaults.removeObject(forKey: selectedKey) }

  /// 与 WebKit 容器删除配合使用，移除指定实例的非敏感配置。
  func forget(_ instance: SavedInstance) throws {
    let wasSelected = selected?.id == instance.id
    defaults.set(try JSONEncoder().encode(instances.filter { $0.id != instance.id }), forKey: key)
    if wasSelected { deselect() }
    WidgetService.shared.endSession(instanceId: instance.id, clear: true)
  }
}
