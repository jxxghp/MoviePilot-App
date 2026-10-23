# MoviePilot-App

使用系统原生导航的 MoviePilot iOS 客户端。Swift / UIKit 负责连接、登录、顶部与底部导航，WKWebView 继续加载现有 MoviePilot-Frontend 业务页面、弹窗和插件界面。

**当前为开发预览版，仅面向 iOS。已通过 iPhone 17 Pro 模拟器的登录、17 个页面入口、主要分类及菜单/弹窗验证；真实 iPhone、完整系统集成和原生推送仍待验收。**

## 界面

- iOS 26+ 使用系统 Liquid Glass 控件与柔和的滚动边缘渐变；更早系统使用标准 UIKit 外观。
- 页面标题统一由原生导航栏呈现，标题旁操作收进右上角三点菜单。
- 底部主导航与当前页面操作分组显示；“更多”提供分组目录和本地搜索。
- 原生连接、密码/OTP 登录，特殊认证可转入原网页登录。
- 启动时显示深色背景、透明 Logo、无文字的静态画面，首屏资源与导航就绪后再显示网页。
- HTML 菜单、筛选和设置弹窗保持原实现，与原生导航协调返回和安全区。

![所有页面总览](screenshots/all-pages.png)

![菜单与弹窗](screenshots/menus-and-dialogs.png)

[全部截图及分类索引](screenshots/README.md) · [可离线筛选和放大的截图册](screenshots/index.html)

截图来自 **iPhone 17 Pro / iOS 27.0 模拟器**，原图为 1206 × 2622。公开截图的配置密钥和实例地址使用演示值。GitHub 不直接运行 HTML，可下载仓库后在浏览器中打开截图册。

## 安装前准备

需要 Mac、**Xcode 26 或更新版本**、Apple 账户，以及运行 **iOS 17+** 的 iPhone。iOS 26+ 才会显示系统 Liquid Glass。本地构建验证使用 Xcode 27.1 / iOS SDK 27.1。

App 连接你自己的 MoviePilot 实例，不内置后端或业务前端。完整原生导航需要实例使用支持容器桥接的 MoviePilot-Frontend；不支持的前端会保留网页导航。当前适配源码通过本仓的 [前端补丁](integration/MoviePilot-Frontend-native.patch) 提供，构建方法见下文。

## 个人打包并安装到 iPhone

### 1. 下载并打开工程

```sh
git clone https://github.com/jxxghp/MoviePilot-App.git
cd MoviePilot-App
open ios/MoviePilot.xcodeproj
```

工程和共享 Scheme 已提交，直接打开即可；Swift 核心包位于仓库内，不需要 CocoaPods。

### 2. 配置个人签名

1. 在 Xcode 的 **Settings → Accounts** 中添加 Apple 账户。
2. 选择 `MoviePilot` 工程、`MoviePilot` Target，进入 **Signing & Capabilities**。
3. 打开 **Automatically manage signing**，将 **Team** 选为自己的 Personal Team 或开发者团队。
4. 将 **Bundle Identifier** 改为自己唯一的值，例如 `com.yourname.moviepilot`。只改本机配置，不提交团队信息、证书或描述文件。

免费 Apple 账户可通过 Personal Team 在自己的设备上运行。免费签名的描述文件通常 **7 天到期**，届时需重新连接 Xcode 构建安装；它不等于 TestFlight 或 App Store 分发资格。限制以 [Apple 个人团队说明](https://developer.apple.com/help/account/basics/about-your-developer-account#enable-a-personal-team-in-xcode) 为准。

### 3. 连接并安装

1. 用数据线连接 iPhone，解锁并选择“信任这台电脑”。
2. 按 Xcode 提示，在 iPhone 的 **设置 → 隐私与安全性 → 开发者模式**中启用开发者模式，并完成重启确认。
3. Xcode 顶部选择 `MoviePilot` Scheme 和自己的 **真实 iPhone**，等待设备准备完成。
4. 点击 **Run（⌘R）**。Xcode 会编译、签名、安装并启动 App。
5. 若系统提示开发者不受信任，按提示在 **设置 → 通用 → VPN 与设备管理**中信任自己的开发者签名，再打开 App。

首次安装建议先通过数据线运行成功，再按 Xcode 的设备设置启用无线调试。开发者模式见 [Apple 官方指引](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

### 4. 连接 MoviePilot

输入手机能够访问的 MoviePilot 地址并登录。同一局域网可使用服务器的私网 IP；手机里的 `localhost` 指向手机自身，连接 Mac 上的前端时应填写 Mac 的局域网地址。访问本地服务时允许 App 的“本地网络”权限。

推荐使用证书有效的 HTTPS。工程仅为本地名称、私网和回环地址配置 HTTP 例外，公网 HTTP 和不受信任证书可能被系统阻止。

### 5. 导出安装包（可选）

使用付费开发者团队时，可在 Xcode 中选择通用 iOS 设备，执行 **Product → Archive**，随后在 **Organizer → Distribute App** 中按账号和设备选择可用的开发、Ad Hoc 或 TestFlight 分发方式。接收设备必须满足所选签名方式的要求。

个人免费账户建议使用上面的 Xcode Run 安装。当前仓库不提供通用签名 IPA，也未提交 App Store；模拟器产物不能安装到真实 iPhone。

## 构建兼容前端

此步骤在 MoviePilot-Frontend 仓库进行。补丁仅增加默认关闭的容器适配、标题/操作交接和相关测试，继续复用原业务页面与认证接口。

使用固定基线构建，避免直接套到不同版本：

```sh
# 与 MoviePilot-App 放在同一父目录
git clone --branch v3 https://github.com/jxxghp/MoviePilot-Frontend.git
cd MoviePilot-Frontend
git switch -c native-ios 795c975850289ac2e0146b18c05cf63541cb352a
git apply --check ../MoviePilot-App/integration/MoviePilot-Frontend-native.patch
git apply ../MoviePilot-App/integration/MoviePilot-Frontend-native.patch

# 使用项目支持的 Node.js 与 Yarn Classic
yarn install --frozen-lockfile
yarn build
```

将 `dist/` 部署为你的 MoviePilot 前端，并继续代理同一实例的 `/api/` 等后端接口。App 应连接完整前端地址。

个人在局域网试用时，也可让 Mac 运行构建后的前端预览并代理现有实例：

```sh
MOVIEPILOT_DEV_PROXY_TARGET=https://your-moviepilot.example.com \
  yarn preview --host 0.0.0.0 --port 5186 --strictPort
```

在 App 中连接 `http://Mac的局域网IP:5186`，Mac 与 iPhone 保持同一局域网。该预览进程需持续运行，仅用于受信任的本地测试。正式使用时请部署 `dist/` 并配置 HTTPS。

补丁更新后应重新构建并部署前端。协议不兼容时会回退网页导航；这不表示原生导航已接管成功。

## 消息通知

**当前 App 尚未接入原生 APNs 推送，不能接收原 PWA 的后台、锁屏系统通知。** WKWebView 不会自动继承 PWA 的推送订阅和通知权限。原 PWA 的 Web Push 可继续独立使用；消息列表和现有其他通知渠道仍由 MoviePilot 提供。

原生推送接入正在后续阶段实施，需要 App 系统授权/APNs 注册、服务端设备绑定与投递，以及真实 iPhone 的前台、后台、锁屏、冷启动点击验收。模拟器测试不代表实际推送到达。[WebKit 平台说明](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)

## 开发与验证

```sh
# 核心协议、认证、地址与会话边界测试
zsh scripts/test-core.sh

# 无签名模拟器构建，仅用于编译检查
xcodebuild -project ios/MoviePilot.xcodeproj -scheme MoviePilot \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

UI 测试位于 `ios/MoviePilotUITests`，通过私有运行配置提供 `MOVIEPILOT_E2E_SERVER`、`MOVIEPILOT_E2E_USERNAME`、`MOVIEPILOT_E2E_PASSWORD`；未配置时跳过实例联调。凭据、签名材料、`DerivedData` 和结果包均不提交。

```text
ios/          UIKit / WKWebView App、资源与 UI 测试
Sources/      可独立编译的 Swift 核心
Tests/        核心边界测试
integration/  MoviePilot-Frontend 容器适配源码补丁
screenshots/  公开截图、索引和离线截图册
scripts/      本地验证入口
```

仍需完成真实 iPhone、横屏/键盘完整矩阵、文件/外链、前后台与内容进程恢复、OTP/签名 Keychain 和 APNs 的完整验收。Android 延后规划。

MoviePilot-Frontend 及 Logo 来自 [MoviePilot-Frontend](https://github.com/jxxghp/MoviePilot-Frontend)，沿用其 MIT 许可。
