# MoviePilot-App 三端全原生 Monorepo 开发约定

本仓库为 MoviePilot 官方单仓三端全原生客户端（**iOS SwiftUI + Android Jetpack Compose + HarmonyOS NEXT ArkTS/ArkUI + Rust 共享业务内核**），直接对接 MoviePilot V3 后端 REST/SSE API，不引入跨端 UI 壳，不在主流程使用 WebView。

- **单一事实源（`shared/`）**：统一版本号（`VERSION`）、视觉设计 Token（`shared/design-tokens/`）、多语言词条（`shared/l10n/`）、品牌图标、36 枚服务/平台 Logo 与 73 份社区 3D 勋章资产（`shared/assets/`）均由 `python3 tools/sync-all.py` 单向同步至三端；CI 通过 `python3 tools/sync-all.py --check` 拦截漂移。
- **Rust 共享业务内核（`shared/core-rust/`）**：协议 URL 构造（含中文 UTF-8 路径段安全编码与同源边界校验）、DeepLink 路由解析、AI SSE 与流式 Markdown AST、9 维站点资源筛选与同规格分组、JWT/RBAC 权限矩阵与 401/403 分类、动态插件 JSON 规划与表达式求值/无损补丁、5 字段 Cron 解析、3D 勋章金属配色统一沉淀于 Rust 内核，由三端注入各自原生网络与安全存储。
- **各端原生设计规范**：
  - iOS 详见 [ios/AGENTS.md](ios/AGENTS.md)（Swift 6 严格并发、Liquid Glass / MeshGradient、外置盘构建缓存）；
  - Android 详见 [android/AGENTS.md](android/AGENTS.md)（Material 3 Expressive、Compose 自适应导航、OpenGL ES 3D 勋章、Gradle 外置缓存）；
  - 鸿蒙详见 [harmony/AGENTS.md](harmony/AGENTS.md)（HarmonyOS 动态光感材质、`bindSheet` 半模态、一多断点与安全区避让）。
- **WebView 隔离与安全边界**：仅保留遗留 `render_mode == "vue"` 插件受控隔离容器；跨源请求严禁附带实例 Bearer Token 与 Cookie；真实凭据、令牌、Cookie、证书和个人数据严禁写入源码、日志、夹具或截图；源码与文档禁止出现第三方竞品名称。
