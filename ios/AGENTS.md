# MoviePilot-App iOS 端开发约定

- **视觉体系**：消费 `GeneratedTokens.swift`（来自 `shared/design-tokens/`）+ Apple iOS 26+ Liquid Glass / MeshGradient 原生导航；源码与文档禁止出现第三方竞品名称。
- **WebKit 边界**：主流程禁止新增 `WKWebView` 或 HTML/JS 桥接；仅保留 `PluginWeb/LegacyWebsiteStorage.swift` 与 `NativeV2/Pages/NativePluginDataPageView.swift`（受控 `render_mode == "vue"` 遗留插件隔离宿主）。
- **Swift 规范**：采用 Swift 6 严格并发与 `xcrun swift-format lint --strict`；所有新增类型与方法保持中文说明。
- **构建与缓存路径**：本地临时构建与 SwiftPM scratch 放于 `/Volumes/DISK/TmpBuild/`，模拟器测试缓存放于 `~/Library/Caches/MoviePilotSimulator/`（严禁写入 `/tmp`），共享依赖目录固定 `-clonedSourcePackagesDirPath /Volumes/DISK/Xcode/SourcePackages`。
