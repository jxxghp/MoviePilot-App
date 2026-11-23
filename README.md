# MoviePilot-App（iOS / Android / HarmonyOS NEXT 全原生多平台 Monorepo）

MoviePilot 官方全原生移动客户端 Monorepo，以统一视觉设计体系、单一事实源（`shared/`）与 Rust 共享业务内核（`shared/core-rust/`）同时驱动 **iOS（SwiftUI + Liquid Glass）**、**Android（Jetpack Compose + AGSL + Material 3）** 与 **HarmonyOS NEXT（ArkTS / ArkUI + 鸿蒙光效材质）** 三端全原生客户端，直接对接 MoviePilot V3 后端 API，拒绝主流程 WebView/套壳。[查看 iOS（60 张）与 Android（17 张）实测验收界面图册](screenshots/README.md)。

## 仓库目录结构

```text
MoviePilot-App/
├── VERSION / BUILD_NUMBER             # 三端统一版本号与构建号唯一真相源
├── shared/
│   ├── design-tokens/                 # 6 套深浅流光色板、强调色、玻璃材质、断点与图标 Token
│   ├── l10n/                          # 454 项主界面 + 15 项桌面小组件三语本地化词表
│   ├── assets/                        # 品牌图标、36 枚服务 Logo、73 份社区 3D 勋章资产
│   ├── fixtures/                      # 三端共享插件 UI/表单/DeepLink/Markdown 黄金夹具
│   ├── contracts/                     # V3 OpenAPI、moviepilot:// 路由与插件 JSON 契约
│   └── core-rust/                     # Rust 共享业务内核（UniFFI -> iOS/Android，ohos-rs NAPI -> HarmonyOS）
├── ios/                               # iOS 16+/26+ 全原生 SwiftUI 客户端（iPhone & iPad）
├── android/                           # Android 10+（API 29~35）17 模块 Jetpack Compose 客户端
├── harmony/                           # HarmonyOS NEXT（API 12+）纯血 ArkTS/ArkUI 多模块客户端
├── tools/                             # SSOT 同步器、Rust 跨端构建、APK/HAP 校验与 CI 工具
└── screenshots/                       # iOS / Android / HarmonyOS 验收截图图册
```

## 核心能力与三端原生特性

- **视觉统一 × 原生材质红线**：
  - **iOS**：iOS 26+ Liquid Glass 4+1 悬浮导航、动态紫玫流光、CoreGraphics 3D 勋章背面凹雕、VLCKit/AVKit/PiP 与 WidgetKit。
  - **Android**：Android 13+ AGSL `RuntimeShader` 15fps GPU 呼吸流光、Android 12+ `RenderEffect` 玻璃容器与 `ModalBottomSheet` 窗口级 `Window.setBackgroundBlurRadius`（`FLAG_BLUR_BEHIND`）、Media3 ExoPlayer + PiP、3D 勋章 Canvas 三遍金属凹雕与 Jetpack Glance 桌面微件。
  - **HarmonyOS NEXT**：ArkUI `backgroundEffect`/`backgroundBlurStyle` + `pointLight`/`lightUpEffect` 光效材质、原生 `bindSheet` 半模态、RCP 网络与 HUKS 密钥库、`AVPlayer` + `XComponent`、Canvas 三遍金属凹雕与 `FormExtensionAbility` 桌面卡片。
- **Rust 共享核心（`shared/core-rust/`）**：
  - `mp-core-model`：服务器地址归一化、全量 `moviepilot://` 深度链接解析、音视频后缀判定、Agent Markdown AST 解析、订阅进度与 3D 勋章金属色板。
  - `mp-core-api`：严格遵守 ADR-01（无 `reqwest`，复用三端原生网络栈）、V3 端点路径构造、SSE 字节流解析与 9 维级联站点资源筛选/同规格分组引擎。
  - `mp-core-session`：严格遵守 ADR-02（复用 Keychain / Android Keystore / HUKS）、JWT 载荷解析、权限矩阵与 401/403 分类。
  - `mp-core-plugin`：动态 Vuetify JSON 表单规划器、无损补丁合并器（保留未知键与 64 位大整数）、表达式求值、5 字段 Cron 中文解析与 Combobox 过滤。
- **全量业务闭环**：发现首页、多源探索片库、全局搜索、媒体/剧集/人物/豆瓣详情、音乐发现与迷你悬浮播放条、我的订阅/追剧日历/订阅广场、PT 站点资源搜索与下载器管理、多存储文件管理与整理历史、纯原生工作流节点画布、站点流量管理、AI 智能助手 SSE 流式对话、动态插件宿主（原生 JSON + 受控隔离 Vue WebView）、捷径与诊断中心、外观主题自定义与 3D 社区勋章。
- **跨应用联动与免登播放**：三端均支持 `moviepilot://` 全量深度链接路由，并支持在系统文件/共享菜单中直接用 MoviePilot 原生播放本地音视频（未登录实例也可直放）。

## 常用构建与验证命令

### 1. SSOT 同步与 Rust 共享内核

```zsh
# 同步版本号、设计 Token、多语言与共享资产并校验零漂移
python3 tools/sync-all.py && python3 tools/sync-all.py --check
python3 -m unittest discover -s tools/tests

# Rust 代码格式化、Clippy 与全量黄金夹具单测
cd shared/core-rust
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

### 2. Android（Jetpack Compose + Rust UniFFI）

```zsh
# 编译 Rust arm64-v8a 动态库 + UniFFI Kotlin 绑定
ANDROID_ABIS="arm64-v8a" bash tools/rust/build-android.sh

# 运行单元测试并构建 Debug APK（建议使用外置盘缓存）
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug --no-daemon

# 校验 APK 产物（版本、so 体积、73 份共享勋章资产）
python3 ../tools/android/verify-apk.py app/build/outputs/apk/debug/app-debug.apk --version $(cat ../VERSION)
```

### 3. iOS（SwiftUI + XcodeGen）

```zsh
# 运行 Swift 核心单元测试
zsh tools/ios/test-core.sh

# 构建 Rust XCFramework（可选更新）与 iOS 模拟器工程
bash tools/rust/build-ios.sh
(cd ios && xcodegen generate)
xcodebuild build \
  -project ios/MoviePilot.xcodeproj \
  -scheme MoviePilot \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

### 4. HarmonyOS NEXT（ArkTS / ArkUI + ohos-rs NAPI）

需先安装 **DevEco Studio（HarmonyOS NEXT API 12+ SDK / hvigorw / ohpm / hdc）** 与 `ohrs` CLI：

```zsh
# 1. 编译 Rust NAPI 动态库与 .d.ts 类型声明到 harmony/commons/core_rust_bridge/
OHOS_NDK_HOME="$DEVECO_SDK_HOME/default/openharmony/native" bash tools/rust/build-harmony.sh

# 2. 一键安装 HAR 依赖、编译 HAP 并校验产物
bash tools/harmony/build-harmony.sh artifacts

# 3. 安装至 HarmonyOS Phone 模拟器并截图验收
hdc install artifacts/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.moviepilot.harmony
```

## 架构与路线图文档

- [跨平台架构设计](multiplatform-architecture-design.md)
- [跨平台实施路线图](multiplatform-implementation-roadmap.md)
- [各平台模块 AGENTS 规则](AGENTS.md)

## 许可证

MoviePilot-App 采用 [GNU General Public License v3.0（GPL-3.0-only）](LICENSE)。

特别说明：UI设计风格参考了 [Rex iOS App](https://rexnow.tv)。
