# MoviePilot-App

MoviePilot 的 iOS 客户端。使用系统原生导航、搜索和快捷面板，业务页面、弹窗内容和插件界面继续复用 MoviePilot-Frontend。

iOS 26+ 支持系统 Liquid Glass；提供侧滑返回、原生弹窗及前后台恢复。[查看界面截图](screenshots/README.md)。

## 下载与安装

需要 **iOS 17+**、自己的 Apple 账户和 MoviePilot 实例。实例前端请更新至 [3.2.0 或更新的兼容版本](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.0)。

在 [最新 Release](https://github.com/jxxghp/MoviePilot-App/releases/latest) 下载未签名 IPA，通过 SideStore、AltStore Classic 或 Sideloadly 重签安装。免费账户可用，签名通常每 7 天续签；配置步骤见[安装与自动续签](guides/install.md)。

## 使用与开发文档

| 文档 | 内容 |
| --- | --- |
| [连接与兼容性](guides/connection.md) | 实例地址、登录、局域网与连接故障 |
| [消息通知](guides/notifications.md) | 默认通知中心、免费自签 Web Push、可选 APNs |
| [界面截图](screenshots/README.md) | 页面、菜单、弹窗及离线截图册 |
| [自行构建与开发](ios/README.md) | Xcode 安装、签名、IPA 构建与测试 |
| [前端集成](integration/README.md) | 兼容版本与本地联调 |

## 许可证

[MIT License](LICENSE)。MoviePilot-Frontend 与 Logo 来自 [MoviePilot-Frontend](https://github.com/jxxghp/MoviePilot-Frontend)，沿用其 MIT 许可。
