# MoviePilot-App 三端全原生界面实测图册

本图册按平台归档直连真实 MoviePilot V3 后端实例运行的验收截图（全部采用压缩 JPG 格式，共 **130 张**）：

- **[iOS / iPadOS（SwiftUI + Liquid Glass · 61 张）](#iosswiftui--liquid-glass--ios-26-实测验收)**：iPhone 17（iOS 26 模拟器 · 默认「极简石墨」主题）黄金基准界面
- **[Android（Jetpack Compose + Material 3 Expressive · 28 张）](#androidjetpack-compose--material-3-expressive--api-35-实测验收)**：Android 15（API 35 硬件加速模拟器）实测界面
- **[HarmonyOS NEXT（ArkUI + 动态光感 · 41 张）](#harmonyos-nextarkui--动态光感--api-26-实测验收)**：HarmonyOS 7（API 26 `Mate 90 Pro` 模拟器）实测界面

---

## iOS（SwiftUI + Liquid Glass · iOS 26 实测验收）

以下 61 张截图采集自 iPhone 17（iOS 26 模拟器）真实运行界面，默认启用「深色 · 极简石墨」主题，展示全原生 SwiftUI 客户端（零主流程 WebView）的 4+1 Liquid Glass 统一导航（发现、订阅、我的、更多 + 搜索）、玻璃弹层、原生图表与完整业务交互。

### 连接服务、登录、4+1 主导航与设置

| 连接服务 | 已保存服务与连接按钮 | 登录 |
| :---: | :---: | :---: |
| ![连接服务](ios/native-v2-01-connection.jpg) | ![已保存服务](ios/native-v2-01b-connection-saved.jpg) | ![登录](ios/native-v2-02-login.jpg) |

| 发现首页 | 我的订阅（旗舰主页面） | 我的（身份卡 + 社区勋章） |
| :---: | :---: | :---: |
| ![发现](ios/native-v2-live-discover-phase-1.jpg) | ![我的订阅](ios/native-v2-live-subscriptions.jpg) | ![我的](ios/native-v2-live-dashboard.jpg) |

| 更多（分组卡片上半部） | 更多（快捷工具与系统诊断） | 全局搜索 |
| :---: | :---: | :---: |
| ![更多上半部](ios/native-v2-live-more.jpg) | ![更多下半部](ios/native-v2-live-more-bottom.jpg) | ![全局搜索](ios/native-v2-live-search.jpg) |

| 设置主中心（由更多右上角进入） | 分类探索（由发现分类浏览进入） | 渠道授权管理 |
| :---: | :---: | :---: |
| ![设置主中心](ios/native-v2-live-settings-hub.jpg) | ![探索](ios/native-v2-live-explore.jpg) | ![渠道授权](ios/native-v2-live-channel-auth.jpg) |

### 发现滚动、模块编排、影视详情与演职员

| 发现滚动阶段 2 | 发现滚动阶段 3 | 发现滚动阶段 4（媒体库与分类浏览） |
| :---: | :---: | :---: |
| ![发现阶段2](ios/native-v2-live-discover-phase-2.jpg) | ![发现阶段3](ios/native-v2-live-discover-phase-3.jpg) | ![发现阶段4](ios/native-v2-live-discover-phase-4.jpg) |

| 发现模块编辑 | 榜单网格（分页前） | 榜单网格（自动翻页） |
| :---: | :---: | :---: |
| ![发现模块](ios/native-v2-live-modules.jpg) | ![网格分页前](ios/native-v2-live-grid-before-pagination.jpg) | ![网格自动翻页](ios/native-v2-live-grid-automatic-page.jpg) |

| 媒体详情（订阅 + 搜索资源） | 媒体详情演职员 | 人物详情 |
| :---: | :---: | :---: |
| ![媒体详情](ios/native-v2-live-detail.jpg) | ![详情演职员](ios/native-v2-live-detail-cast.jpg) | ![人物详情](ios/native-v2-live-person.jpg) |

| 剧集详情 | 剧集分季 | 网格翻页状态 |
| :---: | :---: | :---: |
| ![剧集详情](ios/native-v2-live-tv-detail.jpg) | ![剧集分季](ios/native-v2-live-tv-seasons.jpg) | ![翻页状态](ios/native-v2-live-grid-pagination-state.jpg) |

### 分类探索、豆瓣详情、音乐、订阅生态与资源下载

| 分类探索（豆瓣筛选） | 豆瓣作品详情 | 豆瓣演职员与推荐 |
| :---: | :---: | :---: |
| ![豆瓣探索](ios/native-v2-live-explore-douban.jpg) | ![豆瓣作品详情](ios/native-v2-live-douban-detail.jpg) | ![豆瓣演职员与推荐](ios/native-v2-live-douban-detail-cast.jpg) |

| 音乐探索 | 音乐专辑与曲目播放 | 站点资源（关键词搜索 / 浏览） |
| :---: | :---: | :---: |
| ![音乐探索](ios/native-v2-live-music.jpg) | ![音乐专辑](ios/native-v2-live-music-album.jpg) | ![站点资源](ios/native-v2-live-resources.jpg) |

| 订阅规则编辑 | 追剧日历（订阅右上角入口） | 正在下载 |
| :---: | :---: | :---: |
| ![订阅编辑](ios/native-v2-live-subscribe-editor.jpg) | ![追剧日历](ios/native-v2-live-calendar.jpg) | ![正在下载](ios/native-v2-live-downloads.jpg) |

| 订阅广场（热门订阅） | 订阅广场（社区分享） | 消息中心（玻璃弹层） |
| :---: | :---: | :---: |
| ![热门订阅](ios/native-v2-live-community-popular.jpg) | ![社区分享](ios/native-v2-live-community-shares.jpg) | ![消息中心](ios/native-v2-live-messages.jpg) |

### AI 智能助手与系统诊断工具

| 智能助手（机器人悬浮入口） | 快捷诊断：词表管理 | 快捷诊断：定时服务 |
| :---: | :---: | :---: |
| ![智能助手](ios/native-v2-live-agent.jpg) | ![词表与语法说明](ios/native-v2-live-diag-words.jpg) | ![定时服务](ios/native-v2-live-diag-schedulers.jpg) |

| 快捷诊断：实时日志 | 整理历史（相对时间 + 链式路径） | 整理队列弹窗 |
| :---: | :---: | :---: |
| ![实时日志](ios/native-v2-live-diag-logs.jpg) | ![整理历史](ios/native-v2-live-history.jpg) | ![整理队列](ios/native-v2-live-transfer-queue.jpg) |

### 文件管理与原生工作流

| 文件管理 | 工作流列表 | 纯原生工作流节点画布 |
| :---: | :---: | :---: |
| ![文件管理](ios/native-v2-live-files.jpg) | ![工作流列表](ios/native-v2-live-workflows.jpg) | ![工作流画布](ios/native-v2-live-workflow-canvas.jpg) |

| 工作流社区分享 | 站点管理（上下行流量图示） | 站点数据（历史流量趋势图） |
| :---: | :---: | :---: |
| ![工作流社区](ios/native-v2-live-workflow-shares.jpg) | ![站点管理](ios/native-v2-live-sites.jpg) | ![站点数据图表](ios/native-v2-live-site-data.jpg) |

### 系统配置、用户与插件生态

| 订阅与搜索设置 | 媒体数据源配置 | 下载器管理 |
| :---: | :---: | :---: |
| ![订阅与搜索设置](ios/native-v2-live-sysmod-site-scope.jpg) | ![媒体数据源](ios/native-v2-live-settings.jpg) | ![下载器管理](ios/native-v2-live-sysmod-services.jpg) |

| 媒体服务器管理 | 目录与存储 | 服务端通知渠道 |
| :---: | :---: | :---: |
| ![媒体服务器](ios/native-v2-live-mediaservers.jpg) | ![目录与存储](ios/native-v2-live-sysmod-directories.jpg) | ![通知渠道](ios/native-v2-live-sysmod-notifications.jpg) |

| 主题与外观（默认极简石墨） | 用户管理 | 插件中心（默认已安装插件） |
| :---: | :---: | :---: |
| ![主题与外观](ios/native-v2-live-appearance.jpg) | ![用户管理](ios/native-v2-live-users.jpg) | ![已安装插件](ios/native-v2-live-plugin-installed.jpg) |

| 插件商店（右上角切换） | 仪表盘无缝插件图表 | 插件数据页（站点统计环形图） |
| :---: | :---: | :---: |
| ![插件市场](ios/native-v2-live-plugin-market.jpg) | ![仪表盘插件](ios/native-v2-live-dashboard-plugins.jpg) | ![站点统计](ios/native-v2-live-plugin-page-statistic.jpg) |

| 插件数据页（猫眼票房排行） | | |
| :---: | :---: | :---: |
| ![猫眼排行](ios/native-v2-live-plugin-page-maoyan.jpg) | | |

---

## Android（Jetpack Compose + Material 3 Expressive · API 35 实测验收）

以下 28 张截图采集自 Android 15（API 35 ARM64 硬件加速模拟器）直连真实 MoviePilot V3 后端实例运行界面：

- **Material 3 Expressive 视觉与 4+1 统一导航**：圆角悬浮 4+1 分体式毛玻璃底栏（发现、订阅、我的、更多 + 独立搜索）、染色顶栏配大圆角容器与统一 `ExpressivePillTabRow` 大胶囊分页栏、5 套深浅表现力色板 + Material You 动态取色 + AMOLED 纯黑模式、全场景 36 枚服务品牌 Logo 与自适应桌面图标；
- **全量核心业务闭环**：发现 10 大模块自定义开关排序、分类浏览直达多源探索、无遮挡媒体库浏览、全量订阅规则编辑器、PT 站点资源多维筛选与下载推送、手动识别整理、词表动态提示、AI 智能助手 SSE 流式对话，以及原生 JSON + Vue 模块联邦接管插件宿主。

### 桌面图标、发现、媒体库、分类探索与详情

| Android 自适应图标 | 发现首页（4+1 分体悬浮底栏） | 发现滚动（无遮挡媒体库 + 分类浏览） |
| :---: | :---: | :---: |
| ![Android自适应图标](android/00-launcher-icon.jpg) | ![Android发现首页](android/01-discover-top.jpg) | ![Android发现滚动](android/02-discover-scrolled-emby.jpg) |

| Emby 媒体库（大胶囊分页） | 媒体详情（沉浸主视觉） | 人物独立详情页 |
| :---: | :---: | :---: |
| ![Android媒体库](android/03-emby-library.jpg) | ![Android媒体详情](android/04-media-detail.jpg) | ![Android人物详情](android/05-person-detail.jpg) |

| 分类探索（多源筛选网格） | 音乐探索（自动滚动页签） | 全局搜索（底部独立搜索入口） |
| :---: | :---: | :---: |
| ![Android探索](android/06-explore.jpg) | ![Android音乐探索](android/06b-explore-music.jpg) | ![Android全局搜索](android/06c-global-search.jpg) |

### 订阅、更多中心、我的仪表盘与设置

| 订阅列表（大胶囊分页） | 全量订阅规则编辑器 | 更多中心（资源、插件与右上角设置） |
| :---: | :---: | :---: |
| ![Android订阅](android/07-subscribe-primary-tabs.jpg) | ![Android订阅编辑](android/07b-subscribe-editor.jpg) | ![Android更多中心](android/09-workspace-hub.jpg) |

| 更多中心（追剧与系统诊断长方卡片） | 我的（顶部用户身份卡 + 仪表盘） | 自定义我的模块 |
| :---: | :---: | :---: |
| ![Android更多下半部](android/09b-workspace-hub-bottom.jpg) | ![Android仪表盘](android/16-dashboard.jpg) | ![Android自定义我的模块](android/16b-dashboard-modules.jpg) |

| 设置中心 | 下载器新增与编辑 | 主题与外观（5 色板 + 纯黑模式） |
| :---: | :---: | :---: |
| ![Android设置中心](android/18-settings.jpg) | ![Android下载器新增](android/18b-downloaders-add.jpg) | ![Android主题外观](android/19-appearance-segmented.jpg) |

### 站点资源、词表、手动整理、AI 助手与插件生态

| 站点资源检索 | 多选搜索站点弹窗 | 全部筛选条件弹窗 |
| :---: | :---: | :---: |
| ![Android站点资源](android/21-resources-search.jpg) | ![Android多选站点](android/21b-resources-sites-multiselect.jpg) | ![Android全部筛选](android/21c-resources-filter-sheet.jpg) |

| 词表管理（分类动态示例与提示） | 全量手动识别整理 | AI 智能助手（工具折叠卡 + Markdown） |
| :---: | :---: | :---: |
| ![Android词表](android/22-word-lists.jpg) | ![Android手动整理](android/23-manual-transfer.jpg) | ![Android智能助手](android/24-agent-chat.jpg) |

| AI 历史会话管理 | 插件中心（大胶囊分页） | 插件数据页渲染 |
| :---: | :---: | :---: |
| ![Android历史会话](android/24b-agent-sessions.jpg) | ![Android插件中心](android/10-plugins-primary-tabs.jpg) | ![Android插件数据页](android/11-plugin-vuetify-datapage.jpg) |

| Vue 模块联邦插件零点击直开 | | |
| :---: | :---: | :---: |
| ![AndroidVue联邦接管](android/13-plugin-vue-zero-tap.jpg) | | |

---

## HarmonyOS NEXT（ArkUI + 动态光感 · API 26 实测验收）

以下 41 张截图采集自 HarmonyOS 7.0.0（API 26，`Mate 90 Pro` 模拟器）直连真实 MoviePilot V3 后端实例运行界面：

- **鸿蒙专属视觉与动态光感体系**：圆角悬浮 4+1 分体式动态光感导航栏（发现、订阅、我的、更多 + 独立搜索）、无遮挡渐进模糊沉浸顶栏、原生 `.bindSheet` 多档半模态弹窗、5 套鸿蒙色板（默认 **鸿蒙智蓝 `#317AF7`** + **AMOLED 纯黑** + **HarmonyOS 7 `uiMaterial.ImmersiveMaterial` 动态光感**及多代际自动回退）与全场景服务品牌 Logo；
- **全量核心业务闭环**：发现 10 大模块与自定义排序、分类浏览直达多源探索、Emby 媒体库无遮挡浏览、全局搜索、全量订阅编辑器与追剧日历、站点资源多选站点与多维筛选、多存储文件管理与手动识别整理、3D 社区勋章与背面三遍凹雕、动态插件中心与 AI 智能助手流式对话。

### 桌面图标、连接登录、发现、媒体库与分类探索

| HarmonyOS 桌面图标 | 连接服务 | 账号登录 |
| :---: | :---: | :---: |
| ![HarmonyOS桌面图标](harmony/00-launcher-icon.jpg) | ![HarmonyOS连接服务](harmony/01-connect.jpg) | ![HarmonyOS账号登录](harmony/02-login.jpg) |

| 发现首页（全屏 Hero + 4+1 悬浮底栏） | 发现滚动（热门电影 + 剧集） | 无遮挡 Emby 媒体库 + 6 宫格分类浏览 |
| :---: | :---: | :---: |
| ![HarmonyOS发现首页](harmony/03-discover-hero.jpg) | ![HarmonyOS发现滚动](harmony/04-discover-shelves.jpg) | ![HarmonyOS媒体库与分类](harmony/05-discover-libraries-categories.jpg) |

| 编辑发现模块（10 模块开关排序） | Emby 媒体库独立浏览（大胶囊分页） | 全局搜索（底部独立搜索入口） |
| :---: | :---: | :---: |
| ![HarmonyOS编辑发现模块](harmony/06-discover-customize.jpg) | ![HarmonyOS媒体库浏览](harmony/07-media-library-browser.jpg) | ![HarmonyOS全局搜索](harmony/08-global-search.jpg) |

| 分类探索（多源筛选网格） | 音乐探索（1:1 专辑封面网格） | 媒体详情（沉浸主视觉） |
| :---: | :---: | :---: |
| ![HarmonyOS探索片库](harmony/09-explore-movies.jpg) | ![HarmonyOS音乐探索](harmony/10-explore-music.jpg) | ![HarmonyOS媒体详情](harmony/11-media-detail.jpg) |

### 订阅、更多中心、站点资源、文件与手动整理

| 订阅列表（胶囊分页） | 全量订阅编辑器 | 更多中心（资源、插件与右上角设置） |
| :---: | :---: | :---: |
| ![HarmonyOS订阅列表](harmony/12-subscribe-list.jpg) | ![HarmonyOS订阅编辑](harmony/13-subscribe-editor.jpg) | ![HarmonyOS更多上半部](harmony/14-more-hub-top.jpg) |

| 更多中心（追剧与系统诊断长方卡片） | 站点资源（明确排序与全部筛选） | 站点资源多维筛选弹窗 |
| :---: | :---: | :---: |
| ![HarmonyOS更多下半部](harmony/15-more-hub-lower.jpg) | ![HarmonyOS站点资源](harmony/16-site-resources.jpg) | ![HarmonyOS站点筛选](harmony/17-site-resources-filter.jpg) |

| 站点资源多选搜索站点 | 站点管理 | 多存储文件管理 |
| :---: | :---: | :---: |
| ![HarmonyOS多选站点](harmony/18-site-resources-sites.jpg) | ![HarmonyOS站点管理](harmony/19-sites-management.jpg) | ![HarmonyOS文件管理](harmony/20-file-manager.jpg) |

| 整理历史 | 全量手动识别整理 | 插件中心（大胶囊分页） |
| :---: | :---: | :---: |
| ![HarmonyOS整理历史](harmony/21-transfer-history.jpg) | ![HarmonyOS手动整理](harmony/22-manual-transfer.jpg) | ![HarmonyOS插件中心](harmony/23-plugins-center.jpg) |

| 插件配置表单（原生渲染） | 插件数据页 | 我的（顶部用户身份卡 + 实时统计） |
| :---: | :---: | :---: |
| ![HarmonyOS插件配置](harmony/24-plugin-config-form.jpg) | ![HarmonyOS插件数据页](harmony/25-plugin-data-page.jpg) | ![HarmonyOS仪表盘](harmony/26-dashboard-top.jpg) |

### 3D 社区勋章、词表、设置与 AI 智能助手

| 社区勋章墙 + 内存占用 | 3D 社区勋章检视与背面凹雕 | 编辑我的模块（8 模块开关排序） |
| :---: | :---: | :---: |
| ![HarmonyOS勋章与内存](harmony/27-dashboard-medals-memory.jpg) | ![HarmonyOS3D勋章](harmony/28-dashboard-3d-medal.jpg) | ![HarmonyOS编辑我的模块](harmony/30-dashboard-customize.jpg) |

| 词表管理（识别词动态提示） | 词表管理（制作组动态示例） | 设置中心（由更多右上角进入） |
| :---: | :---: | :---: |
| ![HarmonyOS词表识别词](harmony/31-words-identify.jpg) | ![HarmonyOS词表制作组](harmony/32-words-release-group.jpg) | ![HarmonyOS设置中心](harmony/33-settings-hub.jpg) |

| 主题与外观（5 套鸿蒙色板 + 旗舰光感） | 下载器配置列表 | 下载器编辑与删除 |
| :---: | :---: | :---: |
| ![HarmonyOS主题外观](harmony/34-harmony-theme-studio.jpg) | ![HarmonyOS下载器列表](harmony/35-downloaders-list.jpg) | ![HarmonyOS下载器编辑](harmony/36-downloader-editor.jpg) |

| AI 智能助手（工具折叠卡 + Markdown） | AI 历史会话管理 | AI 附件与斜杠命令弹窗 |
| :---: | :---: | :---: |
| ![HarmonyOS智能助手](harmony/37-agent-chat.jpg) | ![HarmonyOSAI历史会话](harmony/38-agent-history-sessions.jpg) | ![HarmonyOSAI附件命令](harmony/39-agent-attach-commands.jpg) |

| Emby 媒体库详情（相似 / 链接 / 媒体信息） | 订阅文件详情与入库播放 | |
| :---: | :---: | :---: |
| ![HarmonyOS媒体库详情](harmony/40-mediaserver-detail.jpg) | ![HarmonyOS订阅文件详情](harmony/41-subscribe-files.jpg) | |
