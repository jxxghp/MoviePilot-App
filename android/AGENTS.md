# MoviePilot-App Android 原生端开发约定

本目录承载 MoviePilot 全原生 **Kotlin + Jetpack Compose（Material 3 Expressive）** Android 客户端，与 iOS / 鸿蒙共享 `shared/` 设计 Token、多语言、36 枚服务品牌 Logo、73 份社区勋章资产及 `shared/core-rust/` 共享内核。

- **视觉与交互一致性**：
  - 统一采用 Material 3 Expressive 视觉语言（5 套深浅表现力色板 + Material You 动态取色 + AMOLED 纯黑模式）、自适应导航（窄屏圆角悬浮 5 Tab 底栏 / 宽屏侧边常驻 `FloatingNavigationRail`）以及 `ExpressiveTintedScaffold` + `ExpressivePillTabRow` 大胶囊分页栏。
  - 涉及数据源、下载器、媒体服务器、通知渠道、存储目录与站点的列表、卡片与选择项统一通过 `NativeEntityLogo` / `NativeNetworkEntityLogo` 展示对应品牌标识。
  - 模态半屏弹窗统一使用原生 `ModalBottomSheet`（`NativeGlassSheet`，内置软键盘 `imePadding` 避让），各一级 Tab 保持独立导航栈与滚动位置状态。
- **业务内核与安全边界**：DeepLink 解析、UTF-8 行缓冲 SSE 帧解析、9 维站点资源筛选分组、JWT/RBAC 权限判定与 401/403 令牌失效识别、插件 JSON 表单规划与动态 `v-if`/`v-show` 求值、Cron 解析统一走 `:core-rust-bridge`（UniFFI `libmoviepilot_core.so`）；登出或会话失效时同步清空隔离 WebView Cookie 与存储。
- **构建与缓存路径**：本地 Gradle 缓存优先使用 `GRADLE_USER_HOME=/Volumes/DISK/Android/gradle-home`，SDK 位于 `/Volumes/DISK/Android/sdk`（CI 自动回退标准运行器路径），严禁向 `/tmp` 写入大型构建缓存；APK 打包通过 `MOVIEPILOT_ABI_FILTERS` 严格锁定与 Rust `.so` 一致的架构目录。
- **注释规范**：所有新增类型与公共方法保持清晰中文 KDoc 注释。
