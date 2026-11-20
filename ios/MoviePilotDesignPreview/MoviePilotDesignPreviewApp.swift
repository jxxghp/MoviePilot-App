import SwiftUI

/// 独立原生预览程序；不依赖主 App、WebKit、账号、后端、插件宿主或真实数据。
@main
@MainActor
struct MoviePilotDesignPreviewApp: App {
  @StateObject private var library = PreviewLibrary()
  /// 单一 Cinematic 深色风格固定在根部，不读取系统/旧版主题偏好。
  var body: some Scene {
    WindowGroup { PreviewRoot().environmentObject(library).preferredColorScheme(.dark) }
  }
}

/// 预览导航状态只保存在此 App 内存中，与正式实例和 Keychain 完全隔离。
@MainActor
struct PreviewRoot: View {
  @State private var selected: Int

  /// 测试可冷启动到指定页面，仍使用真实原生导航和相同视觉组件。
  init() {
    let arguments = ProcessInfo.processInfo.arguments
    let index = arguments.firstIndex(of: "--screen")
    let value = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    _selected = State(
      initialValue: ["dashboard": 1, "subscriptions": 2, "settings": 3, "search": 4][value ?? ""]
        ?? 0)
  }

  /// iOS 18+ 搜索角色在当前系统使用独立搜索入口，早期系统保留标准原生底栏。
  var body: some View {
    ZStack {
      CinematicBackground()
      if #available(iOS 18, *) {
        TabView(selection: $selected) {
          Tab("发现", systemImage: "sparkles.tv", value: 0) { PreviewDiscover() }
          Tab("工作台", systemImage: "square.grid.2x2", value: 1) { PreviewDashboard() }
          Tab("订阅", systemImage: "bookmark", value: 2) { PreviewSubscriptions() }
          Tab("设置", systemImage: "gearshape", value: 3) { PreviewSettings() }
          Tab("搜索", systemImage: "magnifyingglass", value: 4, role: .search) { PreviewSearch() }
        }
      } else {
        TabView(selection: $selected) {
          PreviewDiscover().tabItem { Label("发现", systemImage: "sparkles.tv") }.tag(0)
          PreviewDashboard().tabItem { Label("工作台", systemImage: "square.grid.2x2") }.tag(1)
          PreviewSubscriptions().tabItem { Label("订阅", systemImage: "bookmark") }.tag(2)
          PreviewSettings().tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
          PreviewSearch().tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(4)
        }
      }
    }.tint(.white)
  }
}
