# MoviePilot-App

使用系统原生导航的 MoviePilot iOS 客户端。Swift / UIKit 负责连接、登录、顶部与底部导航，WKWebView 继续加载现有 MoviePilot-Frontend 业务页面、弹窗和插件界面。

**当前为开发预览版，仅面向 iOS。已通过 iPhone 17 Pro 模拟器的登录、17 个页面入口、主要分类、菜单/弹窗及通知点击验证；真实 iPhone 和完整系统集成仍待验收。**

## 界面

- iOS 26+ 使用系统 Liquid Glass 控件与柔和的滚动边缘渐变；更早系统使用标准 UIKit 外观。
- 页面标题统一由原生导航栏呈现，标题旁操作收进右上角三点菜单。
- 底部主导航与当前页面操作分组显示；“更多”提供分组目录和本地搜索。
- 原生连接、密码/OTP 登录，特殊认证可转入原网页登录。
- 启动时显示深色背景、透明 Logo、无文字的静态画面，首屏资源与导航就绪后再显示网页。
- HTML 菜单、筛选和设置弹窗保持原实现，与原生导航协调返回和安全区。

页面、菜单与弹窗预览见 [界面截图](screenshots/README.md)，包含全部截图及离线截图册入口。

## 安装前准备

需要 Mac、**Xcode 26 或更新版本**、Apple 账户，以及运行 **iOS 17+** 的 iPhone。iOS 26+ 才会显示系统 Liquid Glass。本地构建验证使用 Xcode 27.1 / iOS SDK 27.1。

App 连接你自己的 MoviePilot 实例，不内置后端或业务前端。完整原生导航需要实例使用支持容器桥接的 MoviePilot-Frontend；不支持的前端会保留网页导航。适配源码也通过本仓的 [前端补丁](integration/MoviePilot-Frontend-native.patch) 提供，构建方法见下文。

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

连接失败时，登录页与网页恢复页会提示证书、地址解析、超时或服务不可达等具体原因。局域网服务无法连接时，也请在 iPhone 的 **设置 → 隐私与安全性 → 本地网络**中检查 MoviePilot 的权限。

IPv6 地址可使用 `http://[fd00::1234]:3000/` 这样的写法。带 `%en0` 等网卡标识的 IPv6 地址不受网页 URL 支持，请改用实例的 `.local` 主机名或其他可访问地址。

### 5. 导出安装包（可选）

使用付费开发者团队时，可在 Xcode 中选择通用 iOS 设备，执行 **Product → Archive**，随后在 **Organizer → Distribute App** 中按账号和设备选择可用的开发、Ad Hoc 或 TestFlight 分发方式。接收设备必须满足所选签名方式的要求。

个人免费账户建议使用上面的 Xcode Run 安装。当前仓库不提供通用签名 IPA，也未提交 App Store；模拟器产物不能安装到真实 iPhone。

## 构建兼容前端

优先部署 [MoviePilot-Frontend v3.1.10](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.1.10) 或更新的兼容版本。需要自行构建时，在 MoviePilot-Frontend 仓库应用以下补丁；补丁增加默认关闭的容器适配、标题/操作交接、私有通知配置和相关测试，继续复用原业务页面与认证接口。

使用固定基线构建，避免直接套到不同版本：

```sh
# 与 MoviePilot-App 放在同一父目录
git clone --branch v3 https://github.com/jxxghp/MoviePilot-Frontend.git
cd MoviePilot-Frontend
git switch -c native-ios 5a451cac
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

消息链路为 **MoviePilot → 你的 MoviePilot-Server → 系统推送服务 → 手机**。Server 保存设备绑定并负责投递；App 不保存中转密钥、VAPID 私钥或 Apple 私钥。沿用 MoviePilot 的通知渠道、消息类型开关和用户路由，按实例及用户隔离设备。

| 安装签名 | 使用方式 | 系统通知归属 |
| --- | --- | --- |
| 免费 Personal Team 自签 | 添加专用通知网页到主屏幕 | 主屏幕“MoviePilot 通知” |
| 具备 Push Notifications 权限的开发者签名 | App 原生 APNs | MoviePilot App |

免费签名没有原生 APNs 权限，Server 中转也不能补上该权限。主屏幕 Web Push 不需要付费开发者账号，不要求 App 常驻前台；通知由主屏幕网页接收，点击后可选择返回 App 或打开实例网页。WKWebView 不会继承 Safari/PWA 的订阅；原 PWA 的 Web Push 和其他通知渠道继续独立使用。[WebKit 平台说明](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)

### 免费自签：配置私有 Server 和主屏幕通知

1. 更新 MoviePilot 后端与兼容前端，使用运营者提供的 MoviePilot-Server 消息中心。中心统一维护 HTTPS、数据库、Redis 和 VAPID 私钥，并开启自动接入；个人也可按 [Server 部署说明](https://github.com/jxxghp/MoviePilot-Server#私有-app-消息推送) 自行部署，无需为每个用户另建一套服务。
2. 在 MoviePilot 的通知渠道中添加 **AppPush**，启用所需消息类型。消息中心地址留空使用 `MP_SERVER_HOST`，也可填写运营者提供的地址；后台自动创建并登记独立凭据，不需要向运营者索取密钥或在 Server 注册账号。已有手工接入保留在兼容设置中。默认通知路由使用管理员，需要其他本地用户接收时选择现有的用户路由。
3. 在 App 登录该实例，打开右上角 **三点 → 连接与显示 → 通知**，点击“生成绑定码”。绑定码十分钟有效、只能使用一次。
4. 点击“打开通知网页”，在 Safari 中打开该地址，使用 **分享 → 添加到主屏幕**。再从主屏幕启动通知网页，粘贴绑定码并允许通知。
5. 点击“发送测试通知”。之后下载、入库或订阅消息按已开启的通知类型经 Server 投递。点击通知后选择“在 App 中打开”，会返回当前实例原有的业务页面；默认进入现有 HTML 通知中心。

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
