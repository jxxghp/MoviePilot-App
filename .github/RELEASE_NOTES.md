MoviePilot iOS 1.2.0，支持 iOS 16+、iPad 与 iPhone Duo 可调整窗口布局。

本次为 **1.2.0 同版本重新打包**，请重新下载 IPA 后重签安装。

### 更新内容

- 主 App 最低系统版本调整为 iOS 16.0，主 App 与 UI 测试工程保持 iPhone/iPad 设备族配置。
- 统一 iPhone、iPad 和 iPhone Duo 的竖横屏、窄宽窗口、键盘、搜索、菜单、Sheet 和前后台恢复流程，保持实例与账号会话。
- 验证 iPhone Duo 合拢、半展开和完全展开三种姿态下的真实账号交互；iPad 与 iPhone 也完成相同关键流程回归。
- 小组件继续要求 iOS 17.0；iOS 26+ 继续使用系统 Liquid Glass。
- 修复 App 在后台时点击原生通知崩溃：通知代理的系统完成回调改为在主线程执行。
- 修复 iPad 底栏过窄、过矮及入口文案省略，图标与完整文案上下排列，并与动态动作对齐。
- iPhone Duo 的主入口和右下角动作注册到系统信号区域的操作栏，隐藏独立底栏；普通 iPhone 保留原有导航。

### 验收边界

本次发布使用 Xcode 27.1 的 iOS 26.1、iOS 27.1 模拟器完成 iPad、iPhone 和 iPhone Duo 的真实账号截图验收。当前 Xcode 安装中没有可用的 iOS 16 模拟器 Runtime，因此 iOS 16 由工程最低部署版本、归档产物和 API 兼容性检查证明；需要 iOS 16 Runtime 截图时，请使用包含该 Runtime 的 Xcode 14.3.1 或更高兼容版本补做验收。

通知点击崩溃已在系统通知横幅中复现，并以相同模拟器流程验证修复；合成载荷不代替 Apple APNs 真机投递。

### 安装

下载 `MoviePilot-1.2.0-unsigned.ipa` 后自行重签。本包没有 Apple 证书签名，不能直接安装；原生推送需要开发者团队为 `com.moviepilot.app` 启用 Push Notifications，并使用带该权限的生产描述文件，同时重签小组件、保留一致的 App Groups。免费账户须在重签时移除 `aps-environment`，继续使用主屏幕网页通知。

如果旧版使用 `org.moviepilot.app`，新版会作为独立 App 安装，需要重新登录及绑定通知；旧 App 和数据不会自动迁移或删除。重签后 Bundle ID 与已有安装一致时才能覆盖更新，原生推送还须与 Server 的 topics 允许名单一致。

MoviePilot 后台启用 AppPush 后，在 App **右上角三点 → 连接与显示 → 通知 → 开启系统通知** 中授权，再发送测试通知。Apple `.p8` 私钥、Team ID 与 Key ID 由 Server 配置，App 无需填写。开发签名须同时将 App 的 APNs 环境改为 `development`，不能仅替换描述文件。

此版本无需为此更新前端；独立搜索仍需 [MoviePilot-Frontend v3.2.4](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.4) 或更新的兼容版本。真实 Apple 投递、后台及锁屏接收需在具有推送权限的签名和真机上验证。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md)

Release 同时提供 `SHA256SUMS`。本包使用 iPhoneOS SDK 和 arm64 架构构建。
