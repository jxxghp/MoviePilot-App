MoviePilot 现已全面提供 **iOS / iPadOS**、**Android** 与 **HarmonyOS NEXT** 三端全原生客户端，基于 Rust 共享业务内核直连 MoviePilot V3 后端，带来一致的核心功能闭环与地道原生界面体验。

### 本版本核心亮点

- **iOS / iPadOS 全原生体验**：
  - 全面适配 **iPhone**（Liquid Glass 4+1 悬浮导航）、**iPad**（`sidebarAdaptable` 侧边栏工作台与多列 Bento 自适应栅格）及 **iPhone Duo** 竖向侧边操作区。
  - 原生支持 MobileVLCKit + AVKit 全格式音视频播放与画中画、SceneKit 3D 社区勋章与背面三遍凹雕、WidgetKit 桌面/锁屏小组件与 APNs 推送。
- **Android 全原生客户端（Jetpack Compose + Material 3 Expressive）**：
  - 采用 Material 3 Expressive 视觉体系、圆角悬浮/侧栏自适应导航、统一大胶囊分页栏（`ExpressivePillTabRow`）、Material You 动态取色与 AMOLED 纯黑模式。
  - 完整对齐发现模块编排、媒体库浏览、探索与全局搜索、全量订阅规则与追剧日历、PT 站点多维筛选与真实下载控制、多存储文件管理与手动识别整理、工作流管理与节点画布、AI 智能助手 SSE 流式对话、原生 JSON/Vue 插件生态、OpenGL ES 3D 社区勋章及全量 36 枚服务品牌 Logo。
- **HarmonyOS NEXT 全原生客户端（ArkTS / ArkUI + 动态光感）**：
  - 采用 HarmonyOS 动态光感材质（支持 API 26 旗舰沉浸材质与多代际平滑回退）、无遮挡渐进模糊沉浸顶栏、原生 `bindSheet` 半模态与一多宽屏侧栏。
  - 完整打通 HUKS 安全会话持久化、同源凭据隔离、发现/探索/详情/订阅/日历/站点资源/下载/手动整理/插件市场安装配置/AI 智能助手流式对话、常驻迷你音乐续播、3D 勋章检视佩戴与全场景品牌 Logo。

### 安装包说明

| 平台 | 产物文件 | 适用设备与安装说明 |
| :--- | :--- | :--- |
| **iOS / iPadOS** | `MoviePilot-2.0.2-ios-unsigned.ipa` | 需要 **iOS 16+**（小组件需 iOS 17+），下载后使用个人或企业证书重签安装（重签小组件请保持一致的 App Groups）。 |
| **Android（推荐）** | `MoviePilot-2.0.2-android-arm64-v8a.apk` | 适用于绝大多数现代 64 位 ARM 手机与平板（**Android 10 / API 29+**），体积更小，可直接安装。 |
| **Android（通用）** | `MoviePilot-2.0.2-android-universal.apk` | 同时包含 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` 架构，兼容 32 位旧设备、电视盒子与桌面模拟器。 |
| **HarmonyOS NEXT** | `MoviePilot-2.0.2-harmony-unsigned.hap` | 适用于 **HarmonyOS NEXT（API 12+）**，供开发者使用 DevEco Studio / 签名工具配置证书后安装至真机或模拟器。 |

Release 同时提供统一校验文件 `SHA256SUMS`。
