# MoviePilot-App v2 开发约定

本仓库 `v2` 分支为 MoviePilot 全原生 SwiftUI iOS 客户端，直接调用 MoviePilot 后端 REST/SSE API，不依赖前端构建产物或主流程 WebView。

- **视觉体系**：固定单一深色紫玫瑰渐变 + 低雾感透色玻璃（Cinematic 视觉体系）与 Apple iOS 26+ Liquid Glass 原生导航，不引入多主题切换器；源代码、注释与文档禁止出现第三方竞品名称。
- **WebKit 边界**：主流程禁止新增 `WKWebView` 或 HTML/JS 桥接；仅保留 `PluginWeb/LegacyWebsiteStorage.swift`（忘记旧实例清理残留）与 `NativeV2/Pages/NativePluginDataPageView.swift`（受控 `render_mode == "vue"` 遗留插件隔离宿主）。
- **权限与安全**：严格复用后端身份与权限门禁；真实凭据、令牌、Cookie、证书和个人数据绝不写入源码、日志、测试夹具或截图。
- **Swift 规范**：采用 Swift 6 严格并发与 `xcrun swift-format lint --strict`；所有新增类型与方法保持中文说明。
- **构建与缓存路径**：本地临时构建与 SwiftPM scratch 放于 `/Volumes/DISK/TmpBuild/`，模拟器测试缓存放于 `~/Library/Caches/MoviePilotSimulator/`（严禁写入 `/tmp`），共享依赖目录固定 `-clonedSourcePackagesDirPath /Volumes/DISK/Xcode/SourcePackages`。
