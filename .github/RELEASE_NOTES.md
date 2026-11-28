MoviePilot 现已全面提供 **iOS / iPadOS**、**Android** 与 **HarmonyOS NEXT** 三端全原生客户端（统一版本 **`2.0.13`**），基于 Rust 共享业务内核直连 MoviePilot V3 后端，带来一致的核心功能闭环与地道原生界面体验。

### 本版本核心亮点

- **播放器控制条更紧凑**：Android 与 Harmony 视频底栏采用图标按钮，减少遮挡并保留字幕、音轨、弹幕、比例、倍速与选集操作。
- **助手贴边与插件形象修复**：助手弹层关闭后保持显示；默认形象贴边时更靠近屏幕边缘，插件形象资源请求沿用当前登录会话。
- **插件与界面稳定性**：修复插件进度弹层更新、联邦资源加载与原生助手生命周期问题，并统一识别规则及词表切换按钮尺寸。

### 安装包说明

| 平台 | 版本 | 产物文件 | 适用设备与安装说明 |
| :--- | :--- | :--- | :--- |
| **iOS / iPadOS** | `2.0.13` | `MoviePilot-2.0.13-ios-unsigned.ipa` | 需要 **iOS 16+**（小组件需 iOS 17+），下载后使用个人或企业证书重签安装（重签小组件请保持一致的 App Groups）。 |
| **Android（推荐）** | `2.0.13` | `MoviePilot-2.0.13-android-arm64-v8a.apk` | 适用于绝大多数现代 64 位 ARM 手机与平板（**Android 10 / API 29+**），体积更小，可直接安装。 |
| **Android（通用）** | `2.0.13` | `MoviePilot-2.0.13-android-universal.apk` | 同时包含 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` 架构，兼容 32 位旧设备、电视盒子与桌面模拟器。 |
| **HarmonyOS NEXT** | `2.0.13` | `MoviePilot-2.0.13-harmony-unsigned.hap` | 适用于 **HarmonyOS NEXT（API 12+）**，供开发者使用 DevEco Studio / 签名工具配置证书后安装至真机或模拟器。 |

Release 同时提供统一校验文件 `SHA256SUMS`。
