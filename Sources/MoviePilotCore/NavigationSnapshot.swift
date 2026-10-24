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

/// 动作所属范围只影响菜单分组，不改变网页回调与权限校验。
public enum ActionScope: String, Codable, Sendable { case global, page }

/// 不含回调与认证凭据的导航动作及面板展示声明。
public struct ActionSnapshot: Codable, Equatable, Sendable {
  public let actionId: String
  public let ownerId: String
  public let title: String
  public let icon: String
  public let position: ActionPosition
  public let scope: ActionScope?
  public let enabled: Bool
  public let loading: Bool
  public let dataAttr: String?
  public let menu: [ActionMenuItem]?
  public let panel: NativePanelSnapshot?

  /// 旧前端沿用已发布的全局动作标识；新前端明确声明范围，未知动作归入当前页面。
  public var isGlobal: Bool {
    if let scope { return scope == .global }
    let parts = actionId.split(separator: ":", omittingEmptySubsequences: false)
    return parts.count == 3 && parts[0].hasPrefix("r") && parts[1] == "global"
  }
}

/// 系统快捷面板的纯展示声明，业务方法与权限仍留在当前网页组件中。
public struct NativePanelSnapshot: Codable, Equatable, Sendable {
  public let title: String
  public let layout: NativePanelLayout?
  public let subtitle: String?
  public let profile: NativePanelProfile?
  public let search: NativePanelSearch?
  public let sections: [NativePanelSection]
  public let loading: Bool?
  public let hasMore: Bool?
  public let emptyText: String?
}

/// 网格用于捷径和插件工具面板，旧版声明缺省时保持系统列表。
public enum NativePanelLayout: String, Codable, Sendable { case grid }

/// 账号卡片只展示当前网页提供的昵称、身份与头像，不接触原生认证或复制用户 API。
public struct NativePanelProfile: Codable, Equatable, Sendable {
  public let name: String
  public let detail: String?
  public let image: String?
}

/// 搜索词只由系统输入框和当前网页状态同步，不包含后端接口地址。
public struct NativePanelSearch: Codable, Equatable, Sendable {
  public let text: String
  public let placeholder: String
}

/// 原生面板按当前业务组件的分组顺序显示。
public struct NativePanelSection: Codable, Equatable, Sendable {
  public let id: String
  public let title: String?
  public let items: [NativePanelItem]
}

/// 有限层级的系统列表项；图片仅用于展示，点击只回传稳定标识。
public struct NativePanelItem: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let icon: String?
  public let image: String?
  public let enabled: Bool?
  public let selected: Bool?
  public let destructive: Bool?
  public let keepOpen: Bool?
  /// 当前子菜单唯一主要动作；缺省时保留旧版列表呈现。
  public let primary: Bool?
  public let children: [NativePanelItem]?
}

/// 纯命令菜单项；业务回调仍由当前网页处理。
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
  public let backgroundColor: String?
  public let surfaceColor: String?
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

/// 系统 Sheet 接管已有 Vue 弹窗的标题栏；内容与业务状态不离开原文档。
public struct NativeSheetSnapshot: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let fullscreen: Bool
  public let canDismiss: Bool
  /// 旧前端缺省时直接接管；支持准备的前端先保留原底页，再移交唯一 WebView。
  public let backdropReady: Bool?
  public let actions: [NativeSheetAction]
}

/// 标题栏只引用当前 DOM 按钮，不携带脚本、选择器或业务接口。
public struct NativeSheetAction: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let enabled: Bool
}

/// 普通菜单保留底栏，业务弹窗可由具备可选能力的系统 Sheet 承载。
public struct PresentationSnapshot: Codable, Equatable, Sendable {
  public let overlayOpen: Bool
  public let fullscreen: Bool?
  public let requestedPanel: String?
  public let sheet: NativeSheetSnapshot?
}

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
      [chrome.accentColor, chrome.backgroundColor, chrome.surfaceColor].allSatisfy({ color in
        color.map(Self.isColor) ?? true
      }),
      presentation?.requestedPanel.map(BridgeValidator.isIdentifier) ?? true,
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
    if let sheet = presentation?.sheet {
      guard presentation?.overlayOpen == true, BridgeValidator.isIdentifier(sheet.id),
        Self.isLabel(sheet.title), sheet.actions.count <= 8,
        Set(sheet.actions.map(\.id)).count == sheet.actions.count,
        sheet.actions.allSatisfy({ BridgeValidator.isIdentifier($0.id) && Self.isLabel($0.title) })
      else { throw BridgeError.invalidMessage }
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
      if let panel = action.panel { try Self.validatePanel(panel) }
    }
  }

  /// 面板限制层级、数量、文本和唯一标识，防止失控声明进入系统控件。
  private static func validatePanel(_ panel: NativePanelSnapshot) throws {
    guard isLabel(panel.title), panel.subtitle.map(isLabel) ?? true,
      panel.emptyText.map(isLabel) ?? true, panel.sections.count <= 16,
      Set(panel.sections.map(\.id)).count == panel.sections.count
    else { throw BridgeError.invalidMessage }
    if let profile = panel.profile {
      guard isLabel(profile.name), profile.detail.map(isLabel) ?? true,
        profile.image.map(isProfileImageReference) ?? true
      else { throw BridgeError.invalidMessage }
    }
    if let search = panel.search {
      guard search.text.utf8.count <= 1024, isLabel(search.placeholder),
        !search.text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { throw BridgeError.invalidMessage }
    }
    var ids = Set<String>()
    /// 递归检查每行，所有分组和子菜单共享同一标识空间。
    func validateRows(_ rows: [NativePanelItem], depth: Int) throws {
      guard depth <= 2, rows.filter({ $0.primary == true }).count <= 1 else {
        throw BridgeError.invalidMessage
      }
      for row in rows {
        guard ids.count < 96, BridgeValidator.isIdentifier(row.id), ids.insert(row.id).inserted,
          isLabel(row.title), row.icon.map(isLabel) ?? true,
          row.image.map(isImageReference) ?? true,
          row.primary != true || depth > 0 && (row.children ?? []).isEmpty && row.keepOpen != true,
          row.subtitle.map({
            $0.utf8.count <= 2048 && !$0.isEmpty
              && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
          }) ?? true
        else { throw BridgeError.invalidMessage }
        if let children = row.children, !children.isEmpty {
          try validateRows(children, depth: depth + 1)
        }
      }
    }
    for section in panel.sections {
      guard BridgeValidator.isIdentifier(section.id), section.title.map(isLabel) ?? true
      else { throw BridgeError.invalidMessage }
      try validateRows(section.items, depth: 0)
    }
  }

  /// 图片仅接受有界 HTTP(S) 地址，不接受脚本、本机文件或 URL 中的用户凭据。
  public static func isImageReference(_ value: String) -> Bool {
    guard value.utf8.count <= 4096,
      !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      let url = URL(string: value), let scheme = url.scheme?.lowercased(),
      ["https", "http"].contains(scheme), url.host != nil, url.user == nil, url.password == nil
    else { return false }
    return true
  }

  /// 内联头像限定为前端生成的八 KiB JPEG，其他图片沿用无凭据的 HTTP(S) 资源规则。
  public static func isProfileImageReference(_ value: String) -> Bool {
    if isImageReference(value) { return true }
    let prefix = "data:image/jpeg;base64,"
    guard value.utf8.count <= 8192, value.hasPrefix(prefix),
      let data = Data(base64Encoded: String(value.dropFirst(prefix.count))), !data.isEmpty
    else { return false }
    return true
  }

  /// 颜色仅允许六位十六进制值，不能透传 CSS 指令。
  private static func isColor(_ value: String) -> Bool {
    value.utf8.count == 7
      && value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
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
