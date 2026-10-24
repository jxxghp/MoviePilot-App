/// 按当前面板会话合并有界分片；缓存仅供展示，业务权限和回调仍由网页复核。
public struct NativePanelFeedState {
  private var snapshot: NativePanelSnapshot?
  private var retained: [String: [NativePanelItem]] = [:]
  private var requestedRevision: Int?

  /// 每次打开面板建立独立内存状态，不跨页面、账号或面板生命周期保存内容。
  public init() {}

  /// 首片新消息置顶，历史片追加，重复行原位更新；工具菜单始终直接采用最新声明。
  public mutating func apply(_ next: NativePanelSnapshot) -> [NativePanelSection] {
    if snapshot?.feed?.id != next.feed?.id {
      retained.removeAll()
      requestedRevision = nil
    }
    if next.feed?.revision != requestedRevision || next.hasMore != true {
      requestedRevision = nil
    }
    snapshot = next
    guard let feed = next.feed else {
      retained.removeAll()
      return next.sections
    }
    retained = retained.filter { feed.sectionIds.contains($0.key) }
    return next.sections.map { section in
      guard feed.sectionIds.contains(section.id) else { return section }
      let previous = retained[section.id] ?? []
      let updates = Dictionary(uniqueKeysWithValues: section.items.map { ($0.id, $0) })
      let known = Set(previous.map(\.id))
      let merged =
        feed.offset == 0
        ? section.items + previous.filter { updates[$0.id] == nil }
        : previous.map { updates[$0.id] ?? $0 } + section.items.filter { !known.contains($0.id) }
      retained[section.id] = merged
      return NativePanelSection(id: section.id, title: section.title, items: merged)
    }
  }

  /// 空态只由连续内容判断，不把已读、清理等工具按钮计为通知。
  public var isEmpty: Bool { retained.values.allSatisfy(\.isEmpty) }

  /// 同一完成序号只允许一条在途请求；失败停止自动加载，显式重试仍受加载中和末尾状态保护。
  public mutating func requestMore(isNearEnd: Bool, retry: Bool = false) -> Bool {
    guard let snapshot, let feed = snapshot.feed, snapshot.hasMore == true,
      snapshot.loading != true, requestedRevision == nil,
      retry || isNearEnd && snapshot.loadError == nil
    else { return false }
    requestedRevision = feed.revision
    return true
  }
}
