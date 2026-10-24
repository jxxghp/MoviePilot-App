# MoviePilot-App

使用系统原生导航的 MoviePilot iOS 客户端。Swift / UIKit 负责连接、登录、顶部与底部导航，WKWebView 继续加载现有 MoviePilot-Frontend 业务页面、弹窗和插件界面。

**当前为开发预览版，仅面向 iOS。已通过 iPhone 17 Pro 模拟器的登录、17 个页面入口、主要分类、菜单/弹窗及通知点击验证；真实 iPhone 和完整系统集成仍待验收。**

## 界面

- iOS 26+ 使用系统 Liquid Glass 控件与柔和的滚动边缘渐变；更早系统使用标准 UIKit 外观。
- 页面标题统一由原生导航栏呈现。右上角三点菜单将搜索等“常用入口”与随页面注册的“当前页面”操作分组显示，保留操作名称。
- 底部主导航与当前页面操作分组显示；“更多”提供分组目录和本地搜索。
- 捷径、全局搜索、消息中心、插件面板和用户菜单使用系统原生面板，选择项目后调用既有业务功能。
- 菜单按内容适配宽度，简单菜单收窄；用户菜单显示当前头像、昵称与身份。
- 主题设置直接排列在用户菜单的主题分组中，减少菜单层级。
- 普通菜单保留底部导航和原页面背景，菜单本体使用系统玻璃；Sheet 和提示框采用系统默认的背景压暗与转场，只有全屏弹窗隐藏底栏。
- 点击“更多”始终返回完整原生目录，没有页面动态操作时底栏居中显示。
- 原生连接、密码/OTP 登录，特殊认证可转入原网页登录。
- 启动时显示深色背景、透明 Logo、无文字的静态画面，首屏资源与导航就绪后再显示网页。
- 页面筛选菜单使用原生列表、搜索和多选；条件继续由前端业务逻辑处理。
- 业务弹窗使用系统 Sheet 的动画、标题和关闭按钮，内容复用原 Vue 页面，支持嵌套和安全区恢复。

页面、菜单与弹窗预览见 [界面截图](screenshots/README.md)，包含全部截图及离线截图册入口。

## 安装前准备

- 一台运行 **iOS 17+** 的 iPhone，以及自己的 Apple 账户；iOS 26+ 可显示系统 Liquid Glass。
- 自己的 MoviePilot 实例地址和登录账号。实例建议使用 [MoviePilot-Frontend v3.1.10](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.1.10) 或更新的兼容前端，以启用完整原生导航。
- 首次配置第三方安装工具时需要一台电脑；使用 SideStore 完成初始配置后，可在手机上安装和续签。

## 下载 IPA 并安装

在 [最新 Release](https://github.com/jxxghp/MoviePilot-App/releases/latest) 下载 `MoviePilot-版本号-unsigned.ipa`，当前版本为 **1.0.1**。安装包由 GitHub Actions 构建，**需要使用自己的 Apple 账户重签安装，不能下载后直接点开安装**。免费账户即可，无需付费开发者账号或 Xcode。

### 通过 SideStore 安装并自动续签

1. 按 [SideStore 准备指南](https://docs.sidestore.io/docs/installation/prerequisites) 和 [安装指南](https://docs.sidestore.io/docs/installation/install) 完成首次设置。当前官方流程使用电脑上的 **iloader** 安装 SideStore，并在 iPhone 上配置 **LocalDevVPN**、信任个人签名和开启开发者模式。
2. 在手机上打开 SideStore，使用首次配置时的同一 Apple 账户登录。在 **My Apps（我的 App）** 中先刷新 SideStore 自身一次，完成初始化。
3. 将下载的 MoviePilot IPA 保存到 iPhone 的“文件”App，在 SideStore 的 **My Apps** 页面导入该文件，等待签名和安装完成。
4. 安装、更新和续签时，连接 **Wi-Fi** 并开启 **LocalDevVPN**；在 iPhone **设置 → 通用 → 后台 App 刷新**中允许 SideStore 刷新。SideStore 会周期性在后台为自己和已安装的 App 续签，日常续签不需要连接电脑。
5. 定期查看 **My Apps** 中的剩余有效天数。自动续签失败时，在到期前点击剩余天数或 **Refresh All（全部刷新）**手动续签。升级 MoviePilot 时，从 Release 下载新版 IPA，使用同一平台和 Apple 账户覆盖安装。

免费账户的签名通常有效 **7 天**，同时激活的 App 一般最多 **3 个（包含 SideStore 自身）**。具体限制、后台刷新和故障处理以 [SideStore 官方 FAQ](https://docs.sidestore.io/docs/faq) 为准。

### 其他安装工具

也可使用 [AltStore Classic](https://altstore.io/) 或 [Sideloadly](https://sideloadly.io/) 导入同一个 IPA。AltStore Classic 的日常刷新通常需要可连接的 AltServer；Sideloadly 的自动续签需要电脑上的刷新组件运行。按所选工具的官方指南完成签名、安装和自动刷新设置。

Release 同时提供 `SHA256SUMS`。将它与 IPA 放在同一目录，在 macOS 运行 `shasum -a 256 -c SHA256SUMS`；Windows 可用 `Get-FileHash .\MoviePilot-1.0.1-unsigned.ipa -Algorithm SHA256` 对照校验。

## 连接 MoviePilot

输入手机能够访问的 MoviePilot 地址并登录。同一局域网可使用服务器的私网 IP；手机里的 `localhost` 指向手机自身，连接 Mac 上的前端时应填写 Mac 的局域网地址。访问本地服务时允许 App 的“本地网络”权限。

推荐使用证书有效的 HTTPS。工程仅为本地名称、私网和回环地址配置 HTTP 例外，公网 HTTP 和不受信任证书可能被系统阻止。

连接失败时，登录页与网页恢复页会提示证书、地址解析、超时或服务不可达等具体原因。局域网服务无法连接时，也请在 iPhone 的 **设置 → 隐私与安全性 → 本地网络**中检查 MoviePilot 的权限。

IPv6 地址可使用 `http://[fd00::1234]:3000/` 这样的写法。带 `%en0` 等网卡标识的 IPv6 地址不受网页 URL 支持，请改用实例的 `.local` 主机名或其他可访问地址。

完整原生导航需要兼容的前端。不支持容器桥接的旧前端会保留网页导航；需要自行适配时，见[前端兼容与构建说明](integration/README.md)。

## 消息通知

消息链路为 **MoviePilot → 你的 MoviePilot-Server → 系统推送服务 → 手机**。Server 保存设备绑定并负责投递；App 不保存中转密钥、VAPID 私钥或 Apple 私钥。沿用 MoviePilot 的通知渠道、消息类型开关和用户路由，按实例及用户隔离设备。

| 安装签名 | 使用方式 | 系统通知归属 |
| --- | --- | --- |
| 免费 Apple 账户自签 | 添加专用通知网页到主屏幕 | 主屏幕“MoviePilot 通知” |
| 具备 Push Notifications 权限的开发者签名 | App 原生 APNs | MoviePilot App |

免费签名没有原生 APNs 权限，Server 中转也不能补上该权限。主屏幕 Web Push 不需要付费开发者账号，不要求 App 常驻前台；通知由主屏幕网页接收，点击后可选择返回 App 或打开实例网页。WKWebView 不会继承 Safari/PWA 的订阅；原 PWA 的 Web Push 和其他通知渠道继续独立使用。[WebKit 平台说明](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)

### 免费自签：配置私有 Server 和主屏幕通知

1. 更新 MoviePilot 后端与兼容前端。App 默认内置 `https://movie-pilot.org` 通知服务中心，通常无需自行部署 Server；使用自建中心时可参考 [Server 部署说明](https://github.com/jxxghp/MoviePilot-Server/blob/main/docs/PUSH.md)。
2. 在 MoviePilot 的通知渠道中添加 **AppPush**，启用所需消息类型。消息中心地址留空使用 `MP_SERVER_HOST`，也可填写运营者提供的地址；后台自动创建并登记独立凭据，不需要向运营者索取密钥或在 Server 注册账号。已有手工接入保留在兼容设置中。默认通知路由使用管理员，需要其他本地用户接收时选择现有的用户路由。
3. 在 App 登录该实例，打开右上角 **三点 → 连接与显示 → 通知**。服务中心默认内置为 `https://movie-pilot.org`，可修改并按实例保存；已有后台中心配置会自动沿用。更换时须与后台 AppPush 的消息中心地址一致。点击“生成绑定码”，绑定码十分钟有效、只能使用一次。
4. 点击“打开通知网页”，在 Safari 中打开该地址，使用 **分享 → 添加到主屏幕**。再从主屏幕启动通知网页，粘贴绑定码并允许通知。
5. 点击“发送测试通知”。之后下载、入库或订阅消息按已开启的通知类型经 Server 投递。点击通知后选择“在 App 中打开”，会返回当前实例的业务页面；默认进入 App 原生消息中心。

主屏幕通知要求 iOS 16.4+，本 App 最低要求 iOS 17。手机必须能访问 Server；点击业务页面还需要能访问 MoviePilot 实例。通知到达受网络、权限和专注模式影响。“测试通知已提交”表示推送服务接受请求，实际到达需在手机上检查。

当前 Server 即时投递，不持久排队或自动重发消息；失败会反馈到 MoviePilot 的通知渠道日志。

App 可解除本机及其配对网页绑定，通知网页也可自行解绑。在线退出登录时会请求撤销本机绑定；断网退出无法保证 Server 已撤销，应联网后在通知页解绑。已经进入系统推送服务的通知无法撤回。自动接入的凭据轮换保留设备；更换手工中转密钥、VAPID 密钥或清除主屏幕网页数据后需要重新绑定。

这里的“绑定”只表示通知设备归属哪个 MoviePilot 实例中的登录用户，Server 不创建普通用户账号。既有 `user_uid` 关联部署来源，独立随机凭据验证实例权限，容器内的不可变用户 ID 隔离本地账户；知道别人的 UID 不能取得其密钥或认领其设备。中心仍会接触消息正文和推送地址，应选择信任的运营者。

### 可选：原生 APNs

有有效开发者团队和 Push Notifications 描述文件时，在 Xcode 中为自己的 Bundle ID 开启该能力，并设置：

```text
CODE_SIGN_ENTITLEMENTS = MoviePilot/Resources/APNs.entitlements
MOVIEPILOT_APNS_ENVIRONMENT = development
```

开发签名使用 `development`（投递到 sandbox），正式分发签名使用 `production`。Server 按部署说明配置 `.p8` 文件、Team ID、Key ID 与允许的 Bundle ID；Apple 私钥只保存在 Server。App 通知页申请权限并注册设备，token 更新会同步覆盖旧绑定。

工程默认 `MOVIEPILOT_APNS_ENVIRONMENT=disabled`，不要求免费个人团队具备推送权限。请勿为免费签名启用 APNs entitlement。原生 APNs 已实现并通过服务端协议测试、模拟器点击及冷启动交接验证，真实 Apple 投递、后台和锁屏到达仍待有效签名及真机验收。

实现参考了 [MoviePilotLite](https://github.com/singleton-altman/MoviePilotLite) 的中转与设备绑定思路和 [MoviePilotAppPush](https://github.com/buzhengg/MoviePilotAppPush) 的 APNs 链路。本项目独立实现，使用自己的 Server；两个参考项目的 iOS 原生通知同样依赖 APNs 权限。

## 开发

自行构建、Xcode 安装和测试见 [iOS 开发说明](ios/README.md)；前端源码适配见 [集成说明](integration/README.md)。

MoviePilot-Frontend 及 Logo 来自 [MoviePilot-Frontend](https://github.com/jxxghp/MoviePilot-Frontend)，沿用其 MIT 许可。
