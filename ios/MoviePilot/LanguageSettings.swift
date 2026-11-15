import MoviePilotCore
import UIKit
import WidgetKit

/// 原生语言入口仅修改本机偏好及当前实例 MP_LOCALE，不复制业务设置或认证。
@MainActor
enum LanguageSettings {
  /// 三种语言始终使用自身名称，当前选择用系统勾选标记呈现。
  static func menu(select: @escaping (AppLanguage) -> Void) -> UIMenu {
    UIMenu(
      title: L10n.text("语言"), image: UIImage(systemName: "globe"),
      children: AppLanguage.allCases.map { language in
        UIAction(
          title: language.title, identifier: UIAction.Identifier("language-\(language.rawValue)"),
          state: AppLanguage.current == language ? .on : .off
        ) { _ in select(language) }
      })
  }

  /// 更新快捷动作标题并刷新依赖共享语言的系统小组件，不更改动作标识或权限路径。
  static func refreshShortcuts() {
    let titles = ["搜索", "通知中心", "插件面板"]
    let symbols = ["magnifyingglass", "bell", "puzzlepiece.extension"]
    UIApplication.shared.shortcutItems = HomeShortcut.allCases.enumerated().map { index, shortcut in
      UIApplicationShortcutItem(
        type: shortcut.type, localizedTitle: L10n.text(titles[index]),
        localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: symbols[index]),
        userInfo: nil)
    }
    WidgetCenter.shared.reloadAllTimelines()
  }
}
