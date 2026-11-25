MoviePilot 现已全面提供 **iOS / iPadOS**、**Android** 与 **HarmonyOS NEXT** 三端全原生客户端（统一版本 **`2.0.3`**），基于 Rust 共享业务内核直连 MoviePilot V3 后端，带来一致的核心功能闭环与地道原生界面体验。

### 本版本核心亮点

- **三端 `.strm` 直链播放与全链路音视频对齐**：
  - iOS、Android、HarmonyOS NEXT 全面支持媒体服务器（Emby / Jellyfin / 绿联影视 / 极空间 / 本地库）、文件管理、整理历史、订阅文件、`moviepilot://play` DeepLink 及系统外部打开 `.strm` 直链播放，支持请求头提取、跨源鉴权隔离与服务端代理流自动兜底。
  - Android（Media3 ExoPlayer + MediaSessionService）与 HarmonyOS NEXT（AVPlayer + AVSession + PiPWindow）音视频播放能力与 iOS 1:1 对齐，涵盖音轨/外挂与内封字幕切换、LRC 同步歌词、锁屏与通知栏播控、画中画、手势调节及双端播放进度同步。
- **三端信息架构精简与统一**：
  - 移除三端「更多」页面中重复的「站点管理」（归属「设置」页）、「追剧日历」与「订阅广场」（归属「订阅」页）入口，聚焦资源媒体流转、插件工作流与系统诊断三大核心分区。
- **iOS / iPadOS 全原生体验**：
  - 默认主题切换为「极简石墨」，并深度校准「星夜紫玫」深丝绒渐变与中性通透玻璃卡片质感；订阅页顶部排期与筛选交互去重，订阅广场与日历收敛至右上角快捷入口。
  - 全面适配 **iPhone**（Liquid Glass 4+1 悬浮导航）、**iPad**（`sidebarAdaptable` 侧边栏工作台与多列 Bento 自适应栅格）及 **iPhone Duo** 竖向侧边操作区。
- **Android 全原生客户端（Jetpack Compose + Material 3 Expressive）**：
  - 采用 Material 3 Expressive 视觉体系、圆角悬浮/侧栏自适应导航、统一大胶囊分页栏（`ExpressivePillTabRow`）、Material You 动态取色与 AMOLED 纯黑模式。
  - 完整对齐发现模块编排、媒体库浏览、探索与全局搜索、全量订阅规则与追剧日历、PT 站点多维筛选与下载控制、多存储文件管理与手动整理、工作流画布、AI 智能助手流式对话、原生 JSON/Vue 插件生态及「我的」页置顶 3D 社区勋章。
- **HarmonyOS NEXT 全原生客户端（ArkTS / ArkUI + 动态光感）**：
  - 采用 HarmonyOS 动态光感材质（支持 API 26 旗舰沉浸材质与多代际平滑回退）、无遮挡渐进模糊沉浸顶栏、原生 `bindSheet` 半模态与一多宽屏侧栏。
  - 完整打通 HUKS 安全会话持久化、同源凭据隔离、全业务场景闭环、常驻迷你音乐续播、「我的」页置顶 3D 社区勋章检视佩戴与全场景品牌 Logo。

### 安装包说明

| 平台 | 版本 | 产物文件 | 适用设备与安装说明 |
| :--- | :--- | :--- | :--- |
| **iOS / iPadOS** | `2.0.3` | `MoviePilot-2.0.3-ios-unsigned.ipa` | 需要 **iOS 16+**（小组件需 iOS 17+），下载后使用个人或企业证书重签安装（重签小组件请保持一致的 App Groups）。 |
| **Android（推荐）** | `2.0.3` | `MoviePilot-2.0.3-android-arm64-v8a.apk` | 适用于绝大多数现代 64 位 ARM 手机与平板（**Android 10 / API 29+**），体积更小，可直接安装。 |
| **Android（通用）** | `2.0.3` | `MoviePilot-2.0.3-android-universal.apk` | 同时包含 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` 架构，兼容 32 位旧设备、电视盒子与桌面模拟器。 |
| **HarmonyOS NEXT** | `2.0.3` | `MoviePilot-2.0.3-harmony-unsigned.hap` | 适用于 **HarmonyOS NEXT（API 12+）**，供开发者使用 DevEco Studio / 签名工具配置证书后安装至真机或模拟器。 |

Release 同时提供统一校验文件 `SHA256SUMS`。
