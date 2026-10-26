# 自行构建与开发

[返回首页](../README.md)

普通用户可直接[下载 Release IPA 并安装](../guides/install.md)，无需编译。本页适用于需要修改源码或使用 Xcode 的开发者。

需要 Mac、Xcode 26 或更新版本、Apple 账户和 iOS 17+ 设备。本地构建验证使用 Xcode 27.1 / iOS SDK 27.1。

## 使用 Xcode 安装

### 1. 下载并打开工程

```sh
git clone https://github.com/jxxghp/MoviePilot-App.git
cd MoviePilot-App
open ios/MoviePilot.xcodeproj
```

工程和共享 Scheme 已提交，直接打开即可；Swift 核心包位于仓库内，不需要 CocoaPods。

### 2. 配置个人签名

1. 在 Xcode 的 **Settings → Accounts** 中添加 Apple 账户。
2. 选择 `MoviePilot` 工程，分别为 `MoviePilot` 和 `MoviePilotWidgets` Target 配置 **Signing & Capabilities**。
3. 打开 **Automatically manage signing**，将 **Team** 选为自己的 Personal Team 或开发者团队。
4. 将主 App 的 **Bundle Identifier** 改为自己唯一的值，例如 `com.yourname.moviepilot`，扩展使用相同前缀，例如 `com.yourname.moviepilot.widgets`。
5. 两个 Target 使用同一个 **App Groups**。个人构建可在两份 `Widgets.entitlements` 中将组名改为 `group.org.moviepilot.widgets.你的10位TeamID`，并在两个 Target 的能力面板选中该组；不要只修改其中一个。小组件的启用与使用见[系统小组件](../guides/widgets.md)。只改本机签名配置，不提交团队信息、证书或描述文件。

免费 Apple 账户可通过 Personal Team 在自己的设备上运行。免费签名的描述文件通常 **7 天到期**，届时需重新连接 Xcode 构建安装；它不等于 TestFlight 或 App Store 分发资格。限制以 [Apple 个人团队说明](https://developer.apple.com/help/account/basics/about-your-developer-account#enable-a-personal-team-in-xcode) 为准。

### 3. 连接并安装

1. 用数据线连接 iPhone，解锁并选择“信任这台电脑”。
2. 按 Xcode 提示，在 iPhone 的 **设置 → 隐私与安全性 → 开发者模式**中启用开发者模式，并完成重启确认。
3. Xcode 顶部选择 `MoviePilot` Scheme 和自己的 **真实 iPhone**，等待设备准备完成。
4. 点击 **Run（⌘R）**。Xcode 会编译、签名、安装并启动 App。
5. 若系统提示开发者不受信任，按提示在 **设置 → 通用 → VPN 与设备管理**中信任自己的开发者签名，再打开 App。

首次安装建议先通过数据线运行成功，再按 Xcode 的设备设置启用无线调试。开发者模式见 [Apple 官方指引](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

### 4. 导出安装包（可选）

使用付费开发者团队时，可在 Xcode 中选择通用 iOS 设备，执行 **Product → Archive**，随后在 **Organizer → Distribute App** 中按账号和设备选择可用的开发、Ad Hoc 或 TestFlight 分发方式。接收设备必须满足所选签名方式的要求。

个人免费账户可使用上面的 Xcode Run 安装，或下载 Release 的未签名 IPA 后重签。本仓未提交 App Store；模拟器产物不能安装到真实 iPhone。

## 构建未签名 IPA

```sh
bash scripts/build-ipa.sh 1.0.2
```

从仓库根目录执行，产物位于 `artifacts/MoviePilot-1.0.2-unsigned.ipa`，同时生成 `SHA256SUMS`。脚本使用真机 iPhoneOS SDK 和 arm64 架构，校验版本、ZIP 及 Mach-O 平台；安装者仍须自行重签。

工程当前版本为 1.0.2、构建号为 1。发布新版本时先更新 `ios/project.yml` 与已提交工程中的版本号，再将 `v主版本.次版本.修订版本` 标签推到 GitHub。`Release IPA` 会复用现有检查，成功后构建对应版本并发布 IPA 和校验文件。

同版本修复在 `main` 的 Actions → `Release IPA` → `Run workflow` 中操作：填写现有标签，勾选同版本重建确认。检查与打包通过后，工作流将该标签和 Release 资产更新为本次 `main` 源码；若构建期间主分支或标签变化则停止发布。普通标签发布仍拒绝覆盖已有 Release。用户从同一 Release 重新下载 IPA 后覆盖安装即可。

## 测试与目录

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
integration/  前端兼容说明与本地联调
screenshots/  公开截图、索引和离线截图册
scripts/      本地验证入口
```

仍需完成真实 iPhone、横屏/键盘完整矩阵、文件/外链、前后台与内容进程恢复、OTP/签名 Keychain 和 APNs 的完整验收。Android 延后规划。
