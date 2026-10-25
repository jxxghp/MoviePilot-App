MoviePilot iOS 1.0.1，同版本更新；支持 iOS 17+，iOS 26+ 使用系统 Liquid Glass。

### 本次更新

- 丰富系统小组件：概览显示 CPU、内存和网络；下载显示双向速度、剩余空间与任务状态。订阅合并电影、电视剧和音乐，入库按类型统计；大尺寸增加真实名称及明细，名称默认显示。
- 中、小组件保留统计，大组件按空间显示列表和进度；锁屏维持紧凑排版。每个组件可选择服务与内容，点击进入对应原页面。
- 登录会话失效后回到原生表单；连接与登录沿用实例主题，“更多”分组填充调整为接近搜索框的灰色。
- 修复媒体详情“在线播放”无法打开外部播放器，以及日志、种子下载误触发主界面恢复页；文件下载使用系统分享面板，保留原页面。
- 智能助手支持系统附件选择、音频播放和麦克风录音；关闭面板或进入后台及时释放录音。冷启动先展示启动屏，验证会话后再进入登录或首页。
- 配合 MoviePilot-Frontend **3.2.0**，仅在深色主题使用低亮度壁纸，保存配置立即生效；减轻网页导航阴影，并在后台重启后检查会话、恢复连接或返回原生登录。

### 安装

下载 `MoviePilot-1.0.1-unsigned.ipa`，通过 SideStore、AltStore Classic 或 Sideloadly，使用自己的 Apple 账户重签后覆盖安装。免费签名通常 7 天有效；免费自签的消息通知使用主屏幕 Web Push，默认中心为 `https://movie-pilot.org`。

使用小组件时，请保留并同时重签 `MoviePilotWidgets` 扩展与共享组。

[安装与续签](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/install.md) · [小组件](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/widgets.md) · [通知配置](https://github.com/jxxghp/MoviePilot-App/blob/main/guides/notifications.md) · [界面截图](https://github.com/jxxghp/MoviePilot-App/blob/main/screenshots/README.md)

同时下载 `SHA256SUMS`，在下载目录运行 `shasum -a 256 -c SHA256SUMS` 校验。本包由 GitHub Actions 构建并校验版本、真机平台与 arm64 架构；iPhone 的完整系统集成验收仍在进行。
