# 消息通知

[返回首页](../README.md)

消息链路为 **MoviePilot → 你的 MoviePilot-Server → 系统推送服务 → 手机**。Server 保存设备绑定并负责投递；App 不保存中转密钥、VAPID 私钥或 Apple 私钥。沿用 MoviePilot 的通知渠道、消息类型开关和用户路由，按实例及用户隔离设备。

| 安装签名 | 使用方式 | 系统通知归属 |
| --- | --- | --- |
| 免费 Apple 账户自签 | 添加专用通知网页到主屏幕 | 主屏幕“MoviePilot 通知” |
| 具备 Push Notifications 权限的开发者签名 | App 原生 APNs | MoviePilot App |

免费签名没有原生 APNs 权限，Server 中转也不能补上该权限。主屏幕 Web Push 不需要付费开发者账号，不要求 App 常驻前台；通知由主屏幕网页接收，点击后可选择返回 App 或打开实例网页。WKWebView 不会继承 Safari/PWA 的订阅；原 PWA 的 Web Push 和其他通知渠道继续独立使用。[WebKit 平台说明](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)

## 免费自签：配置私有 Server 和主屏幕通知

1. 更新 MoviePilot 后端与兼容前端。App 默认使用 `https://movie-pilot.org` 通知服务中心，通常无需自行部署 Server；使用自建中心时可参考 [Server 部署说明](https://github.com/jxxghp/MoviePilot-Server/blob/main/docs/PUSH.md)。
2. 在 MoviePilot 的通知渠道中添加 **AppPush**，启用所需消息类型。消息中心地址留空使用 `MP_SERVER_HOST`，也可填写运营者提供的地址；后台自动创建并登记独立凭据，不需要向运营者索取密钥或在 Server 注册账号。已有手工接入保留在兼容设置中。默认通知路由使用管理员，需要其他本地用户接收时选择现有的用户路由。
3. 在 App 登录该实例，打开右上角 **三点 → 连接与显示 → 通知**。服务中心可修改并按实例保存；已有后台中心配置会自动沿用。更换时须与后台 AppPush 的消息中心地址一致。点击“生成绑定码”，绑定码十分钟有效、只能使用一次。
4. 点击“打开通知网页”，在 Safari 中打开该地址，使用 **分享 → 添加到主屏幕**。再从主屏幕启动通知网页，粘贴绑定码并允许通知。
5. 点击“发送测试通知”。之后下载、入库或订阅消息按已开启的通知类型经 Server 投递。点击通知后选择“在 App 中打开”，会返回当前实例的业务页面；默认进入 App 原生消息中心。

主屏幕通知要求 iOS 16.4+，本 App 最低要求 iOS 17。手机必须能访问 Server；点击业务页面还需要能访问 MoviePilot 实例。通知到达受网络、权限和专注模式影响。“测试通知已提交”表示推送服务接受请求，实际到达需在手机上检查。

当前 Server 即时投递，不持久排队或自动重发消息；失败会反馈到 MoviePilot 的通知渠道日志。

App 可解除本机及其配对网页绑定，通知网页也可自行解绑。在线退出登录时会请求撤销本机绑定；断网退出无法保证 Server 已撤销，应联网后在通知页解绑。已经进入系统推送服务的通知无法撤回。自动接入的凭据轮换保留设备；更换手工中转密钥、VAPID 密钥或清除主屏幕网页数据后需要重新绑定。

这里的“绑定”只表示通知设备归属哪个 MoviePilot 实例中的登录用户，Server 不创建普通用户账号。既有 `user_uid` 关联部署来源，独立随机凭据验证实例权限，容器内的不可变用户 ID 隔离本地账户；知道别人的 UID 不能取得其密钥或认领其设备。中心仍会接触消息正文和推送地址，应选择信任的运营者。

## 可选：原生 APNs

有有效开发者团队和 Push Notifications 描述文件时，在 Xcode 中为自己的 Bundle ID 开启该能力，并设置：

```text
CODE_SIGN_ENTITLEMENTS = MoviePilot/Resources/APNs.entitlements
MOVIEPILOT_APNS_ENVIRONMENT = development
```

开发签名使用 `development`（投递到 sandbox），正式分发签名使用 `production`。Server 按部署说明配置 `.p8` 文件、Team ID、Key ID 与允许的 Bundle ID；Apple 私钥只保存在 Server。App 通知页申请权限并注册设备，token 更新会同步覆盖旧绑定。

工程默认 `MOVIEPILOT_APNS_ENVIRONMENT=disabled`，不要求免费个人团队具备推送权限。请勿为免费签名启用 APNs entitlement。原生 APNs 已实现并通过服务端协议测试、模拟器点击及冷启动交接验证，真实 Apple 投递、后台和锁屏到达仍待有效签名及真机验收。

实现参考了 [MoviePilotLite](https://github.com/singleton-altman/MoviePilotLite) 的中转与设备绑定思路和 [MoviePilotAppPush](https://github.com/buzhengg/MoviePilotAppPush) 的 APNs 链路。本项目独立实现，使用自己的 Server；两个参考项目的 iOS 原生通知同样依赖 APNs 权限。

