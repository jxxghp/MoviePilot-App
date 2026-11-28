import Foundation

/// 轻量插件更新投影条目，供已安装列表与市场列表在更新/刷新前后无损对账，避免其他插件的更新标记丢失。
public struct PluginUpdateProjectionItem: Sendable, Equatable {
  public let id: String
  public let sourcePluginID: String?
  public var hasUpdate: Bool
  public var repoURL: String?

  public init(id: String, sourcePluginID: String? = nil, hasUpdate: Bool, repoURL: String? = nil) {
    self.id = id
    self.sourcePluginID = sourcePluginID
    self.hasUpdate = hasUpdate
    self.repoURL = repoURL
  }
}

/// 已安装插件与插件市场之间的更新标记投影规则（对齐 Web `mergeMarketMetadataIntoInstalled` 并防网络抖动丢失）。
public enum PluginUpdateProjection {
  /// 归一分身插件与其源插件 ID，统一按小写匹配市场更新元数据。
  public static func canonicalID(id: String, sourcePluginID: String?) -> String {
    let trimmedSource = sourcePluginID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let raw = trimmedSource.isEmpty ? id.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedSource
    return raw.lowercased()
  }

  /// 单个插件完成更新后，仅清除该插件（及同源分身）在市场缓存中的 `hasUpdate`，保留其余插件的更新状态。
  public static func markUpdatedInMarket(
    _ market: [PluginUpdateProjectionItem],
    pluginID: String,
    sourcePluginID: String? = nil
  ) -> [PluginUpdateProjectionItem] {
    let targetKeys = normalizedTargetKeys(pluginID: pluginID, sourcePluginID: sourcePluginID)
    guard !targetKeys.isEmpty else { return market }
    return market.map { item in
      let itemID = item.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let itemCanonical = canonicalID(id: item.id, sourcePluginID: item.sourcePluginID)
      guard targetKeys.contains(itemID) || targetKeys.contains(itemCanonical) else { return item }
      var copy = item
      copy.hasUpdate = false
      return copy
    }
  }

  /// 在拿到 `state=installed`（后端固定返回 `has_update=false`）且新市场响应尚未返回或失败前，
  /// 先基于市场缓存或上一帧已安装快照承接其余插件的 `hasUpdate` 与 `repoURL`，并确保刚更新完的插件立即消标。
  public static func carryOverBeforeMarketSync(
    freshInstalled: [PluginUpdateProjectionItem],
    previousInstalled: [PluginUpdateProjectionItem],
    cachedMarket: [PluginUpdateProjectionItem]?,
    completedUpdateIDs: Set<String>
  ) -> [PluginUpdateProjectionItem] {
    let normalizedCompleted = Set(
      completedUpdateIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    )
    let sourceList = cachedMarket ?? previousInstalled
    let updatableByKey = buildUpdatableLookup(from: sourceList, excluding: normalizedCompleted)

    return freshInstalled.map { item in
      let itemID = item.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let itemCanonical = canonicalID(id: item.id, sourcePluginID: item.sourcePluginID)
      var copy = item
      if normalizedCompleted.contains(itemID) || normalizedCompleted.contains(itemCanonical) {
        copy.hasUpdate = false
        return copy
      }
      if let match = updatableByKey[itemCanonical] ?? updatableByKey[itemID] {
        copy.hasUpdate = true
        if (copy.repoURL ?? "").isEmpty, let repo = match.repoURL, !repo.isEmpty {
          copy.repoURL = repo
        }
      }
      return copy
    }
  }

  /// 使用服务端最新返回的 `state=market` 快照权威投影 `hasUpdate` 与缺省 `repoURL`。
  public static func applyAuthoritativeMarket(
    installed: [PluginUpdateProjectionItem],
    market: [PluginUpdateProjectionItem]
  ) -> [PluginUpdateProjectionItem] {
    let updatableByKey = buildUpdatableLookup(from: market, excluding: [])
    return installed.map { item in
      let itemID = item.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let itemCanonical = canonicalID(id: item.id, sourcePluginID: item.sourcePluginID)
      let match = updatableByKey[itemCanonical] ?? updatableByKey[itemID]
      var copy = item
      copy.hasUpdate = (match != nil)
      if let repo = match?.repoURL, !repo.isEmpty, (copy.repoURL ?? "").isEmpty {
        copy.repoURL = repo
      }
      return copy
    }
  }

  private static func normalizedTargetKeys(pluginID: String, sourcePluginID: String?) -> Set<String> {
    var keys: Set<String> = []
    let trimmedID = pluginID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if !trimmedID.isEmpty { keys.insert(trimmedID) }
    let trimmedSource = sourcePluginID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if !trimmedSource.isEmpty { keys.insert(trimmedSource) }
    return keys
  }

  private static func buildUpdatableLookup(
    from items: [PluginUpdateProjectionItem],
    excluding excludedKeys: Set<String>
  ) -> [String: PluginUpdateProjectionItem] {
    var lookup: [String: PluginUpdateProjectionItem] = [:]
    for item in items where item.hasUpdate {
      let itemID = item.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let itemCanonical = canonicalID(id: item.id, sourcePluginID: item.sourcePluginID)
      if excludedKeys.contains(itemID) || excludedKeys.contains(itemCanonical) {
        continue
      }
      if !itemID.isEmpty { lookup[itemID] = item }
      if !itemCanonical.isEmpty { lookup[itemCanonical] = item }
    }
    return lookup
  }
}
