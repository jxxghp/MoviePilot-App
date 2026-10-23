import Foundation

/// 网页已完成路由守卫后确认的业务位置，原生不自行推测浏览器历史。
public struct RouteSnapshot: Codable, Equatable, Sendable {
  public let fullPath: String
  public let rootId: String?
  public let title: String
  public let canGoBack: Bool
  public let backTarget: String?
}

/// 经过前端权限过滤的原生底部入口。
public struct RootSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let path: String
  public let title: String
  public let icon: String
}

/// 页内导航项；标识由当前网页注册宿主提供。
public struct HeaderTabItem: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
}

/// 当前页内标签注册与选中值；owner 改变后旧命令必须作废。
public struct HeaderTabsSnapshot: Codable, Equatable, Sendable {
  public let ownerId: String
  public let selectedId: String
  public let items: [HeaderTabItem]
}

/// 导航动作的显示位置；业务实现仍保存在网页回调表中。
public enum ActionPosition: String, Codable, Sendable { case leading, trailing, accessory }

/// 不含回调与业务数据的导航动作描述。
public struct ActionSnapshot: Codable, Equatable, Sendable {
  public let actionId: String
  public let ownerId: String
  public let title: String
  public let icon: String
  public let position: ActionPosition
  public let enabled: Bool
  public let loading: Bool
  public let dataAttr: String?
  public let menu: [ActionMenuItem]?
}

/// 纯命令菜单项；复杂 HTML 面板继续通过父动作打开。
public struct ActionMenuItem: Codable, Equatable, Sendable {
  public let actionId: String
  public let title: String
  public let icon: String
  public let enabled: Bool
}

/// 容器界面的主题偏好。
public enum ChromeTheme: String, Codable, Sendable { case system, light, dark }

/// 网页明确给出的导航显示状态，不直接透传 Vue route meta。
public struct ChromeSnapshot: Codable, Equatable, Sendable {
  public let topVisible: Bool
  public let bottomVisible: Bool
  public let theme: ChromeTheme
  public let content: ChromeContent?
  public let accentColor: String?
}

/// 业务 HTML 与原生框架菜单使用不同呈现，但共享同一个 Router 会话。
public enum ChromeContent: String, Codable, Sendable { case web, menu }

/// 由前端权限目录投影的原生更多菜单分组。
public struct MoreMenuSection: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let items: [MoreMenuItem]
}

/// 更多菜单仅包含导航声明，不能携带脚本、业务回调或外部 URL。
public struct MoreMenuItem: Codable, Equatable, Sendable {
  public let id: String
  public let path: String
  public let title: String
  public let icon: String
  public let subtitle: String?
}

/// 网页弹层仍由既有组件实现，原生限制其后方导航并提供关闭返回。
public struct PresentationSnapshot: Codable, Equatable, Sendable { public let overlayOpen: Bool }

/// 原生显示所需的完整原子快照，受大小、数量及修订约束。
public struct NavigationSnapshot: Codable, Equatable, Sendable {
  public let route: RouteSnapshot
  public let roots: [RootSnapshot]
  public let headerTabs: HeaderTabsSnapshot?
  public let actions: [ActionSnapshot]
  public let chrome: ChromeSnapshot
  public let moreMenu: [MoreMenuSection]?
  public let presentation: PresentationSnapshot?

  /// 验证所有路径、数量与标识唯一性；不把不完整快照提交到原生控件。
  public func validate() throws {
    guard Self.isRoute(route.fullPath), Self.isLabel(route.title),
      chrome.accentColor.map({
        $0.utf8.count == 7 && $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
      }) ?? true,
      route.backTarget.map(Self.isRoute) ?? true,
      !route.canGoBack || route.backTarget != nil,
      roots.count <= 4, actions.count <= 16,
      Set(roots.map(\.id)).count == roots.count,
      Set(actions.map(\.actionId)).count == actions.count,
      route.rootId.map({ id in roots.contains { $0.id == id } }) ?? true,
      roots.allSatisfy({
        BridgeValidator.isIdentifier($0.id) && Self.isRoute($0.path)
          && Self.isLabel($0.title) && Self.isLabel($0.icon)
      })
    else {
      throw BridgeError.invalidMessage
    }
    if let tabs = headerTabs {
      guard BridgeValidator.isIdentifier(tabs.ownerId), !tabs.items.isEmpty, tabs.items.count <= 32,
        Set(tabs.items.map(\.id)).count == tabs.items.count,
        tabs.items.contains(where: { $0.id == tabs.selectedId }),
        tabs.items.allSatisfy({ BridgeValidator.isIdentifier($0.id) && Self.isLabel($0.title) })
      else {
        throw BridgeError.invalidMessage
      }
    }
    var actionIds = Set(actions.map(\.actionId))
    let sections = moreMenu ?? []
    let entries = sections.flatMap(\.items)
    guard sections.count <= 32, entries.count <= 128,
      Set(sections.map(\.id)).count == sections.count,
      Set(entries.map(\.id)).count == entries.count,
      chrome.content != .menu || moreMenu != nil,
      sections.allSatisfy({ BridgeValidator.isIdentifier($0.id) && Self.isLabel($0.title) }),
      entries.allSatisfy({
        BridgeValidator.isIdentifier($0.id) && Self.isRoute($0.path)
          && Self.isLabel($0.title) && Self.isLabel($0.icon)
          && ($0.subtitle.map(Self.isLabel) ?? true)
      })
    else { throw BridgeError.invalidMessage }
    for action in actions {
      guard BridgeValidator.isIdentifier(action.actionId),
        BridgeValidator.isIdentifier(action.ownerId),
        Self.isLabel(action.title), Self.isLabel(action.icon),
        action.dataAttr.map({ BridgeValidator.isIdentifier($0) }) ?? true,
        (action.menu?.count ?? 0) <= 32
      else { throw BridgeError.invalidMessage }
      for item in action.menu ?? [] {
        guard BridgeValidator.isIdentifier(item.actionId), Self.isLabel(item.title),
          Self.isLabel(item.icon), actionIds.insert(item.actionId).inserted
        else {
          throw BridgeError.invalidMessage
        }
      }
    }
  }

  /// 只接受 Vue 内部路径，禁止绝对来源、反斜杠与控制字符。
  public static func isRoute(_ value: String) -> Bool {
    value.hasPrefix("/") && !value.hasPrefix("//") && !value.contains("\\")
      && value.utf8.count <= 4096
      && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }

  /// 展示文本保持简短，不接受控制字符；内容只交给 UIKit 文本属性。
  private static func isLabel(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 512
      && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }
}
