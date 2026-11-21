# P6.2b / P6.3b / P7.3 与 4+1 导航、设置中心及全量交互打磨验收记录

- 日期：2026-11-21
- 分支：`v2`
- 目标范围：4+1 底部导航与极简 8 项重复点击弹出菜单、动态 `+1` 上下文主操作按钮、多样化设置主中心与订阅/搜索站点范围（`IndexerSites`/`RssSites`）、系统专项设置、用户管理编辑、原生本地/媒体服务器播放链路（`NativeMediaPlaybackLauncher` + `MediaPlaybackController`）、发现页透明片名 Logo、仪表盘无缝插件渲染、站点上下行流量图示、插件作者/下载量/评分、整理历史常驻搜索与整理队列、隐藏外露删除与全卡片长按上下文菜单。

## 核心交付

1. **4+1 底部导航与极简 8 项弹出菜单**
   - 底部 4 个主标签定型为：`发现`、`探索`、`我的`（超级管理员直显无大标题仪表盘，无缝融合插件图表）、`设置`（多样化多层次设置主中心）。
   - 右侧独立 Liquid Glass `+1` 按钮接入 `NativeDynamicActionCenter`，当活动页面注册主操作（保存、新建目录、新增用户、添加节点、新建对话等）时自动切换图标与动作，否则默认回退全局搜索。
   - 重复点击任意底栏主图标弹出极简 8 项深色透色菜单：`订阅`、`日历`、`资源`、`下载`、`文件`、`历史`、`工作流`、`插件`；移除顶部冗余地址与标题；`站点管理` 与 `用户管理` 迁入「设置」页，`订阅广场` 位于「我的订阅」右上角，`消息中心`/`智能助手` 位于「我的」右上角，`音乐发现` 位于「探索」右上角。
2. **多样化设置中心与站点范围 / 专项系统设置**
   - `NativeSettingsHubPage` 采用六段层次：顶部实时存储空间分段条卡 → 双列状态方卡（`站点管理` / `用户管理`）→ 高亮横幅（白色胶囊 CTA `进入系统设置`）→ 4 列常用配置瓷砖（`站点范围`、`下载媒体`、`通知渠道`、`网络诊断`）→ 原生分组列表（`目录与存储映射`、`刮削开关`、`发现模块顺序`、`插件市场`、`已安装插件配置`）→ 账号与会话管理。
   - `NativeSystemModulesPage` 支持搜索站点范围（`IndexerSites`）与订阅站点范围（`RssSites`）可视化开关、全选/清空与单次保存，以及目录与存储、下载器与媒体服务器（`Downloaders`/`MediaServers` 脱敏）、通知渠道、过滤规则与识别词、刮削开关保存（`ScrapingSwitchs`）及网络延迟诊断（`nettest`）。
   - `NativeUsersPage` 新增 `NativeUserEditorSheet`（`POST/PUT /api/v1/user/`）。
3. **原生本地与媒体服务器播放（P7.3）**
   - `NativeMediaPlaybackLauncher` 脱离 `WebCoordinator`，通过 `NativeSession.playbackAuthorization()` 直接拉起既有 `MediaPlaybackViewController`（VLCKit/AVKit/PiP/字幕/歌词/队列）。
   - `MediaPlaybackController` 补齐音乐流（`POST /api/v1/mediaserver/stream-info/music`）与存储文件本地下载播放（`POST /api/v1/storage/download` + `file://` URL）。
   - 覆盖媒体详情「立即播放」、发现页「继续观看」、音乐专辑曲目、文件管理音视频及整理历史目标文件长按播放。
4. **细节体验与交互收口**
   - 发现页主视觉支持透明片名 Logo 渲染（后端代理优先 + 公开 Logo 域名无凭据无 Cookie 临时会话兜底），页面最底部保留发现模块排序与显隐编辑入口。
   - 媒体详情并列提供「添加订阅」与「搜索资源」玻璃胶囊按钮。
   - 站点管理卡片新增双向绿色上传/玫红下载比例条、分享率与做种数（`GET /api/v1/site/userdata/latest`）。
   - 插件卡片补齐作者、安装量与评分（`plugin/statistic` + `plugin/rating` 大小写兼容映射）。
   - 整理历史顶部新增常驻玻璃搜索框与右上角「整理队列」原生弹窗（`GET/DELETE /api/v1/transfer/queue`）；整理历史与文件管理移除外露删除按钮，统一收口至长按 `.contextMenu` 及二次确认。
   - 各核心页面卡片统一补齐原生 `.contextMenu`，右上角工具栏收口为场景主动作或 `···` 原生下拉菜单。

## 验证结果

- 格式与静态检查：`xcrun swift-format lint --strict` 全部新增/改动文件 0 警告；全仓敏感/禁用词扫描 0 命中。
- 脚本与 SwiftPM 测试：27/27 Python 测试通过；35/35 SwiftPM 单元测试通过。
- 合成端到端 UI 测试（API-only，零 WebView，`unexpected == [:]`）：
  - iPhone 17：`testNativeFourPlusOneNavOverflowDynamicActionAndSettingsHub`、`testNativeHistorySitesAndMessagesFlows`、`testNativeFileManagerAndWorkflowFlows`、`testNativeDashboardRetainsStatisticsDuringPartialFailure`、`testNativeMusicDiscoveryAlbumArtistAndSubscribe`、`testNativeAgentChatStreamAndSessionHistory`、`testNativePluginMarketInstallResetAndUninstall` 全部通过。
  - iPad Pro 11-inch (M5)：`testNativeFourPlusOneNavOverflowDynamicActionAndSettingsHub`、`testNativeHistorySitesAndMessagesFlows` 全部通过。
- 本机真实后端 `http://127.0.0.1:3001/` 只读验收：`passedTests: 1, failedTests: 0`，导出并逐张视觉核验 47 张实测截图（含发现页透明片名 Logo、极简弹出菜单、多样化设置中心、站点范围、整理历史搜索与整理队列、文件长按删除与动态 `+1` 按钮、无标题仪表盘无缝插件图表、站点双向流量条、媒体服务器 `Emby` 与 `Qbittorrent`）。

## 剩余接续项

- **P7.2**：小组件、APNs 推送通知、外部深链与主屏快捷方式彻底脱离 `WebCoordinator`，接入原生会话与路由。
- **P8**：切换 `NativeV2RootView` 为默认入口、移除旧主流程 WebKit/HTML/JS 桥接（仅保留受控插件 Vue 兼容宿主）、完成全矩阵与最终回归验收。
