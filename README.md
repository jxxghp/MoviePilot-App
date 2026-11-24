# MoviePilot-App（iOS · Android · HarmonyOS NEXT 全原生客户端）

MoviePilot 官方单仓三端全原生移动与大屏客户端，基于单一事实源（`shared/`）与 Rust 共享业务内核（`shared/core-rust/`），同时驱动 **iOS / iPadOS（SwiftUI + Liquid Glass）**、**Android（Jetpack Compose + Material 3 Expressive）** 与 **HarmonyOS NEXT（ArkTS / ArkUI + 动态光感材质）**，直接对接 MoviePilot V3 后端 REST/SSE API，拒绝跨端套壳与主流程 WebView。

👉 **[查看三端实测界面图册（iOS 61 张 · Android 28 张 · HarmonyOS 41 张）](screenshots/README.md)**

## 仓库目录结构

```text
MoviePilot-App/
├── VERSION                            # 三端统一语义化版本号唯一真相源
├── shared/
│   ├── design-tokens/                 # 深浅主题色板、强调色、表面材质、响应式断点与语义图标 Token
│   ├── l10n/                          # 主界面与桌面小组件三语本地化词表（简体 / 繁体 / English）
│   ├── assets/                        # 品牌图标、36 枚服务/数据源/渠道 Logo、73 份社区 3D 勋章资产
│   ├── fixtures/                      # 三端共享插件 UI、表单、DeepLink 与 Markdown 黄金测试夹具
│   ├── contracts/                     # MoviePilot V3 API 端点、moviepilot:// 路由与动态插件 Schema
│   └── core-rust/                     # Rust 共享业务内核（UniFFI -> iOS/Android，ohos-rs NAPI -> HarmonyOS）
├── ios/                               # iOS 16+ / iPadOS / iOS 26+ 全原生 SwiftUI 客户端与 WidgetKit
├── android/                           # Android 10+（API 29~35）17 模块 Jetpack Compose 客户端与 Glance 微件
├── harmony/                           # HarmonyOS NEXT（API 12~26）16 模块纯血 ArkTS/ArkUI 客户端与服务卡片
├── tools/                             # SSOT 同步器、Rust 跨端交叉编译、IPA/APK/HAP 打包校验工具链
└── screenshots/                       # iOS / Android / HarmonyOS 真机与模拟器实测截图图册
```

## 核心特性与三端原生设计

- **地道原生视觉与交互**：
  - **iOS / iPadOS**：默认「深色 · 极简石墨」原生色板、iOS 26+ Liquid Glass 4+1 悬浮导航（发现、订阅、我的、更多 + 独立搜索）、iPad `sidebarAdaptable` 工作台与多列 Bento 栅格、SceneKit 3D 挤压社区勋章与背面三遍凹雕、MobileVLCKit + AVKit 全格式播放器与画中画、WidgetKit 多尺寸小组件与 APNs 推送。
  - **Android**：Material 3 Expressive 视觉与 4+1 分体式悬浮/侧栏自适应导航（发现、订阅、我的、更多 + 独立搜索）、染色顶栏与统一大胶囊分页栏（`ExpressivePillTabRow`）、Material You 动态壁纸取色与 AMOLED 纯黑模式、OpenGL ES 3D 勋章实时网格挤压与背面雕刻、Media3 + FFmpeg 全格式音视频播放与 `MediaSessionService` 锁屏播控 / 自动画中画、Jetpack Glance 桌面微件。
  - **HarmonyOS NEXT**：HarmonyOS 动态光感材质（API 26 `ImmersiveMaterial` / 点光源自动分级回退）与 4+1 分体式悬浮导航、5 套鸿蒙色板、无遮挡渐进模糊沉浸顶栏、原生 `bindSheet` 多档半模态、一多自适应侧栏、3D 透视勋章与背面凹雕、`AVPlayer` + `PiPWindow` 画中画与 `AVSession` 后台长时音视频续播、`FormExtensionAbility` 桌面卡片。
- **全场景品牌标识识别**：内置 36 枚高清品牌与服务 Logo（TMDB、豆瓣、Bangumi、MusicBrainz、Emby、Jellyfin、Plex、飞牛、绿联、极空间、qBittorrent、Transmission、rTorrent、微信、飞书、Telegram、钉钉、Slack、Discord、115、阿里云盘、Rclone、SMB 等），全面覆盖数据源、下载器、媒体服务器、通知渠道、存储目录及选择弹窗。
- **Rust 共享核心（`shared/core-rust/`）**：
  - `mp-core-model`：实例地址规范化与同源边界校验、`moviepilot://` 全路由深度链接解析、音视频后缀判定、Agent Markdown AST 解析、订阅进度与 3D 勋章金属色板。
  - `mp-core-api`：复用各平台原生网络栈（`URLSession` / `OkHttp` / HarmonyOS 网络栈，兼容 NAS 自签名 HTTPS 与系统代理）、V3 端点安全编码、SSE 流式帧解析与 9 维站点资源筛选/同规格分组引擎。
  - `mp-core-session`：对接各端安全存储（Keychain / Android Keystore / HUKS）、JWT 载荷解析、RBAC 权限矩阵与 401/403 令牌失效精准识别。
  - `mp-core-plugin`：动态 Vuetify JSON 表单规划器、实时 `v-if`/`v-show` 条件表达式求值、无损补丁合并、5 字段 Cron 解析与 Combobox 词表处理。
- **全量业务闭环**：发现首页与模块自定义编排、多源探索片库、全局多域搜索、影视/剧集/人物详情、音乐探索与悬浮迷你播放条、我的订阅/追剧日历/订阅广场、PT 站点多维筛选与下载器管理、多存储文件管理与手动识别整理、原生工作流管理与节点画布、站点流量管理、AI 智能助手 SSE 流式对话（含历史会话、工具调用折叠卡、附件与语音）、动态插件中心（原生 JSON 表单/数据页 + 受控隔离 Vue 容器）、系统诊断与词表中心、渠道授权与用户管理。

## 本地构建与验证指南

### 1. SSOT 同步与 Rust 共享内核

```zsh
# 同步版本号、Design Tokens、多语言与共享资产并校验零漂移
python3 tools/sync-all.py && python3 tools/sync-all.py --check
python3 -m unittest discover -s tools/tests

# Rust 代码格式化、Clippy 静态检查与黄金夹具单元测试
cd shared/core-rust
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

### 2. iOS（SwiftUI + Xcode）

```zsh
# 运行 Swift 核心单元测试
zsh tools/ios/test-core.sh

# 构建并校验无签名真机 IPA 安装包
bash tools/ios/build-ipa.sh "$(cat VERSION)" artifacts
```

### 3. Android（Jetpack Compose + Rust UniFFI）

```zsh
# 一键交叉编译 Rust 内核、运行单测并构建校验 Release APK
bash tools/android/build-android.sh artifacts

# 如需同时产出 arm64-v8a 单架构包与多架构通用包（arm64-v8a + armeabi-v7a + x86_64）
BUILD_UNIVERSAL=1 bash tools/android/build-android.sh artifacts
```

### 4. HarmonyOS NEXT（ArkTS / ArkUI + ohos-rs NAPI）

需安装 **DevEco Studio** 或 **HarmonyOS Command Line Tools**（含 `hvigorw` / `ohpm` / OpenHarmony Native NDK）：

```zsh
# 一键编译 Rust NAPI .so、打包 Release HAP 并校验字节码与共享资产
bash tools/harmony/build-harmony.sh artifacts

# 安装已签名包至鸿蒙设备或模拟器运行
hdc install artifacts/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.moviepilot.app
```

## GitHub Actions CI 与三端联合发布

- **持续集成（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）**：代码提交或 PR 时自动并行校验 SSOT 零漂移、Rust Clippy/单测、iOS 核心测试与模拟器编译、Android 单测与 APK 校验、以及 HarmonyOS NEXT HAP 构建校验，不会自动创建或覆盖 Release。
- **三端打包发布（[`.github/workflows/release.yml`](.github/workflows/release.yml)）**：仅在推送 `vMAJOR.MINOR.PATCH` 标签或手动触发 `workflow_dispatch` 时运行，自动并行产出并合并校验以下四份产物与统一 `SHA256SUMS`：
  - `MoviePilot-{version}-ios-unsigned.ipa`
  - `MoviePilot-{version}-android-arm64-v8a.apk`
  - `MoviePilot-{version}-android-universal.apk`
  - `MoviePilot-{version}-harmony-unsigned.hap`

开发规范详见 [AGENTS.md](AGENTS.md)。

## 许可证

MoviePilot-App 采用 [GNU General Public License v3.0（GPL-3.0-only）](LICENSE)。

特别说明：UI 设计风格参考了 [Rex iOS App](https://rexnow.tv)。
