# MoviePilot-App 三端全原生界面实测图册

本图册按平台归档直连真实 MoviePilot V3 后端实例运行的验收截图（共 **128 张**）：

- **[iOS / iPadOS（SwiftUI + Liquid Glass · 60 张）](#iosswiftui--liquid-glass--ios-26-实测验收)**：iPhone 17（iOS 26 模拟器）黄金基准界面
- **[Android（Jetpack Compose + Material 3 Expressive · 28 张）](#androidjetpack-compose--material-3-expressive--api-35-实测验收)**：Android 15（API 35 硬件加速模拟器）实测界面
- **[HarmonyOS NEXT（ArkUI + 动态光感 · 40 张）](#harmonyos-nextarkui--动态光感--api-26-实测验收)**：HarmonyOS 7（API 26 `Mate 90 Pro` 模拟器）实测界面

---

## iOS（SwiftUI + Liquid Glass · iOS 26 实测验收）

以下 60 张截图采集自 iPhone 17（iOS 26 模拟器）真实运行界面，展示全原生 SwiftUI 客户端（零主流程 WebView）的 4+1 Liquid Glass 导航、玻璃弹层、原生图表与完整业务交互。

### 连接服务、登录、主导航与全局搜索

| 连接服务 | 已保存服务与连接按钮 | 登录 |
| :---: | :---: | :---: |
| ![连接服务](ios/native-v2-01-connection.jpg) | ![已保存服务](ios/native-v2-01b-connection-saved.jpg) | ![登录](ios/native-v2-02-login.jpg) |

| 发现（透明片名 Logo） | 探索 | 我的（仪表盘） |
| :---: | :---: | :---: |
| ![发现](ios/native-v2-live-discover-phase-1.jpg) | ![探索](ios/native-v2-live-explore.jpg) | ![我的](ios/native-v2-live-dashboard.jpg) |

| 设置主中心 | 重复点击底栏快捷菜单 | 全局搜索 |
| :---: | :---: | :---: |
| ![设置主中心](ios/native-v2-live-settings-hub.jpg) | ![弹出菜单](ios/native-v2-live-overflow-menu.jpg) | ![全局搜索](ios/native-v2-live-search.jpg) |

### 发现滚动、模块编排、影视详情与演职员

| 发现滚动阶段 2 | 发现滚动阶段 3 | 发现滚动阶段 4 |
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

### 探索、豆瓣详情、音乐、订阅与资源下载

| 探索（豆瓣筛选） | 豆瓣作品详情 | 豆瓣演职员与推荐 |
| :---: | :---: | :---: |
| ![豆瓣探索](ios/native-v2-live-explore-douban.jpg) | ![豆瓣作品详情](ios/native-v2-live-douban-detail.jpg) | ![豆瓣演职员与推荐](ios/native-v2-live-douban-detail-cast.jpg) |

| 音乐发现 | 音乐专辑与曲目播放 | 站点资源（关键词搜索 / 浏览） |
| :---: | :---: | :---: |
| ![音乐发现](ios/native-v2-live-music.jpg) | ![音乐专辑](ios/native-v2-live-music-album.jpg) | ![站点资源](ios/native-v2-live-resources.jpg) |

| 我的订阅 | 订阅规则编辑 | 追剧日历 |
| :---: | :---: | :---: |
| ![我的订阅](ios/native-v2-live-subscriptions.jpg) | ![订阅编辑](ios/native-v2-live-subscribe-editor.jpg) | ![追剧日历](ios/native-v2-live-calendar.jpg) |

| 订阅广场（热门订阅） | 订阅广场（社区分享） | 正在下载 |
| :---: | :---: | :---: |
| ![热门订阅](ios/native-v2-live-community-popular.jpg) | ![社区分享](ios/native-v2-live-community-shares.jpg) | ![正在下载](ios/native-v2-live-downloads.jpg) |

### 消息中心、AI 智能助手与捷径诊断中心

| 消息中心（玻璃弹层） | 智能助手（SSE 流式对话） | 捷径菜单（玻璃弹层） |
| :---: | :---: | :---: |
| ![消息中心](ios/native-v2-live-messages.jpg) | ![智能助手](ios/native-v2-live-agent.jpg) | ![捷径菜单](ios/native-v2-live-shortcuts.jpg) |

| 捷径：词表与语法说明 | 捷径：定时服务 | 捷径：实时日志 |
| :---: | :---: | :---: |
| ![词表与语法说明](ios/native-v2-live-diag-words.jpg) | ![定时服务](ios/native-v2-live-diag-schedulers.jpg) | ![实时日志](ios/native-v2-live-diag-logs.jpg) |

### 整理历史、队列、文件管理与工作流

| 整理历史（相对时间 + 链式路径） | 整理队列弹窗 | 文件管理 |
| :---: | :---: | :---: |
| ![整理历史](ios/native-v2-live-history.jpg) | ![整理队列](ios/native-v2-live-transfer-queue.jpg) | ![文件管理](ios/native-v2-live-files.jpg) |

| 工作流列表 | 纯原生工作流节点画布 | 工作流社区分享 |
| :---: | :---: | :---: |
| ![工作流列表](ios/native-v2-live-workflows.jpg) | ![工作流画布](ios/native-v2-live-workflow-canvas.jpg) | ![工作流社区](ios/native-v2-live-workflow-shares.jpg) |

### 站点管理、系统配置、用户与插件生态

| 站点管理（上下行流量图示） | 站点数据（历史流量趋势图） | 订阅与搜索设置 |
| :---: | :---: | :---: |
| ![站点管理](ios/native-v2-live-sites.jpg) | ![站点数据图表](ios/native-v2-live-site-data.jpg) | ![订阅与搜索设置](ios/native-v2-live-sysmod-site-scope.jpg) |

| 媒体数据源配置 | 下载器管理 | 媒体服务器管理 |
| :---: | :---: | :---: |
| ![媒体数据源](ios/native-v2-live-settings.jpg) | ![下载器管理](ios/native-v2-live-sysmod-services.jpg) | ![媒体服务器](ios/native-v2-live-mediaservers.jpg) |

| 目录与存储 | 服务端通知渠道 | 主题与外观 |
| :---: | :---: | :---: |
| ![目录与存储](ios/native-v2-live-sysmod-directories.jpg) | ![通知渠道](ios/native-v2-live-sysmod-notifications.jpg) | ![主题与外观](ios/native-v2-live-appearance.jpg) |

| 用户管理 | 插件市场 | 已安装插件管理 |
| :---: | :---: | :---: |
| ![用户管理](ios/native-v2-live-users.jpg) | ![插件市场](ios/native-v2-live-plugin-market.jpg) | ![已安装插件](ios/native-v2-live-plugin-installed.jpg) |

| 仪表盘无缝插件图表 | 插件数据页（站点统计环形图） | 插件数据页（猫眼票房排行） |
| :---: | :---: | :---: |
| ![仪表盘插件](ios/native-v2-live-dashboard-plugins.jpg) | ![站点统计](ios/native-v2-live-plugin-page-statistic.jpg) | ![猫眼排行](ios/native-v2-live-plugin-page-maoyan.jpg) |

---

## Android（Jetpack Compose + Material 3 Expressive · API 35 实测验收）

以下 28 张截图采集自 Android 15（API 35 ARM64 硬件加速模拟器）直连真实 MoviePilot V3 后端实例运行界面：

- **Material 3 Expressive 视觉与统一导航**：圆角悬浮 5 Tab 胶囊底栏、染色顶栏配大圆角容器与统一 `ExpressivePillTabRow` 大胶囊分页栏、5 套深浅表现力色板 + Material You 动态取色 + AMOLED 纯黑模式、全场景 36 枚服务品牌 Logo 与自适应桌面图标；
- **全量核心业务闭环**：发现 10 大模块自定义开关排序、无遮挡媒体库浏览、全量订阅规则编辑器、PT 站点资源多维筛选与下载推送、手动识别整理（自动匹配目标路径与历史记录）、词表动态提示、AI 智能助手 SSE 流式对话，以及原生 JSON + Vue 模块联邦接管插件宿主。

### 桌面图标、发现、媒体库、探索与详情

| Android 自适应图标 | 发现首页（圆角悬浮底栏） | 发现滚动（无遮挡媒体库 + 分类浏览） |
| :---: | :---: | :---: |
| ![Android自适应图标](android/00-launcher-icon.png) | ![Android发现首页](android/01-discover-top.png) | ![Android发现滚动](android/02-discover-scrolled-emby.png) |

| Emby 媒体库（大胶囊分页） | 媒体详情（沉浸主视觉） | 人物独立详情页 |
| :---: | :---: | :---: |
| ![Android媒体库](android/03-emby-library.png) | ![Android媒体详情](android/04-media-detail.png) | ![Android人物详情](android/05-person-detail.png) |

| 探索片库（多源筛选网格） | 音乐探索（自动滚动页签） | 全局搜索（顶部热门标签） |
| :---: | :---: | :---: |
| ![Android探索](android/06-explore.png) | ![Android音乐探索](android/06b-explore-music.png) | ![Android全局搜索](android/06c-global-search.png) |

### 订阅、更多中心、我的仪表盘与设置

| 订阅列表（大胶囊分页） | 全量订阅规则编辑器 | 更多中心（资源与媒体流转） |
| :---: | :---: | :---: |
| ![Android订阅](android/07-subscribe-primary-tabs.png) | ![Android订阅编辑](android/07b-subscribe-editor.png) | ![Android更多中心](android/09-workspace-hub.png) |

| 更多中心（追剧与系统诊断分组） | 我的仪表盘 | 自定义我的模块 |
| :---: | :---: | :---: |
| ![Android更多下半部](android/09b-workspace-hub-bottom.png) | ![Android仪表盘](android/16-dashboard.png) | ![Android自定义我的模块](android/16b-dashboard-modules.png) |

| 设置中心 | 下载器新增与编辑 | 主题与外观（5 色板 + 纯黑模式） |
| :---: | :---: | :---: |
| ![Android设置中心](android/18-settings.png) | ![Android下载器新增](android/18b-downloaders-add.png) | ![Android主题外观](android/19-appearance-segmented.png) |

### 站点资源、词表、手动整理、AI 助手与插件生态

| 站点资源检索 | 多选搜索站点弹窗 | 全部筛选条件弹窗 |
| :---: | :---: | :---: |
| ![Android站点资源](android/21-resources-search.png) | ![Android多选站点](android/21b-resources-sites-multiselect.png) | ![Android全部筛选](android/21c-resources-filter-sheet.png) |

| 词表管理（分类动态示例与提示） | 全量手动识别整理 | AI 智能助手（工具折叠卡 + Markdown） |
| :---: | :---: | :---: |
| ![Android词表](android/22-word-lists.png) | ![Android手动整理](android/23-manual-transfer.png) | ![Android智能助手](android/24-agent-chat.png) |

| AI 历史会话管理 | 插件中心（大胶囊分页） | 插件数据页渲染 |
| :---: | :---: | :---: |
| ![Android历史会话](android/24b-agent-sessions.png) | ![Android插件中心](android/10-plugins-primary-tabs.png) | ![Android插件数据页](android/11-plugin-vuetify-datapage.png) |

| Vue 模块联邦插件零点击直开 | | |
| :---: | :---: | :---: |
| ![AndroidVue联邦接管](android/13-plugin-vue-zero-tap.png) | | |

---

## HarmonyOS NEXT（ArkUI + 动态光感 · API 26 实测验收）

以下 40 张截图采集自 HarmonyOS 7.0.0（API 26，`Mate 90 Pro` 模拟器）直连真实 MoviePilot V3 后端实例运行界面：

- **鸿蒙专属视觉与动态光感体系**：圆角悬浮一体式 5 Tab 导航栏、无遮挡渐进模糊沉浸顶栏、原生 `.bindSheet` 多档半模态弹窗、5 套鸿蒙色板（默认 **鸿蒙智蓝 `#317AF7`** + **AMOLED 纯黑** + **HarmonyOS 7 `uiMaterial.ImmersiveMaterial` 动态光感**及多代际自动回退）与全场景服务品牌 Logo；
- **全量核心业务闭环**：发现 10 大模块与自定义排序、Emby 媒体库无遮挡浏览、探索与全局搜索、全量订阅编辑器与追剧日历、站点资源多选站点与多维筛选、多存储文件管理与手动识别整理、3D 社区勋章与背面三遍凹雕、动态插件中心与 AI 智能助手流式对话。

### 桌面图标、连接登录、发现、媒体库与探索

| HarmonyOS 桌面图标 | 连接服务 | 账号登录 |
| :---: | :---: | :---: |
| ![HarmonyOS桌面图标](harmony/00-launcher-icon.jpg) | ![HarmonyOS连接服务](harmony/01-connect.jpg) | ![HarmonyOS账号登录](harmony/02-login.jpg) |

| 发现首页（全屏 Hero + 悬浮动态光感底栏） | 发现滚动（热门电影 + 剧集） | 无遮挡 Emby 媒体库 + 分类浏览 |
| :---: | :---: | :---: |
| ![HarmonyOS发现首页](harmony/03-discover-hero.jpg) | ![HarmonyOS发现滚动](harmony/04-discover-shelves.jpg) | ![HarmonyOS媒体库与分类](harmony/05-discover-libraries-categories.jpg) |

| 编辑发现模块（10 模块开关排序） | Emby 媒体库独立浏览（大胶囊分页） | 全局搜索（顶部热搜词） |
| :---: | :---: | :---: |
| ![HarmonyOS编辑发现模块](harmony/06-discover-customize.jpg) | ![HarmonyOS媒体库浏览](harmony/07-media-library-browser.jpg) | ![HarmonyOS全局搜索](harmony/08-global-search.jpg) |

| 探索片库（多源筛选网格） | 音乐探索（1:1 专辑封面网格） | 媒体详情（沉浸主视觉） |
| :---: | :---: | :---: |
| ![HarmonyOS探索片库](harmony/09-explore-movies.jpg) | ![HarmonyOS音乐探索](harmony/10-explore-music.jpg) | ![HarmonyOS媒体详情](harmony/11-media-detail.jpg) |

### 订阅、更多中心、站点资源、文件与手动整理

| 订阅列表（简洁操作行） | 全量订阅编辑器 | 更多中心（资源与媒体流转） |
| :---: | :---: | :---: |
| ![HarmonyOS订阅列表](harmony/12-subscribe-list.jpg) | ![HarmonyOS订阅编辑](harmony/13-subscribe-editor.jpg) | ![HarmonyOS更多上半部](harmony/14-more-hub-top.jpg) |

| 更多中心（插件、追剧与系统诊断） | 站点资源（明确排序与全部筛选） | 站点资源多维筛选弹窗 |
| :---: | :---: | :---: |
| ![HarmonyOS更多下半部](harmony/15-more-hub-lower.jpg) | ![HarmonyOS站点资源](harmony/16-site-resources.jpg) | ![HarmonyOS站点筛选](harmony/17-site-resources-filter.jpg) |

| 站点资源多选搜索站点 | 站点管理 | 多存储文件管理 |
| :---: | :---: | :---: |
| ![HarmonyOS多选站点](harmony/18-site-resources-sites.jpg) | ![HarmonyOS站点管理](harmony/19-sites-management.jpg) | ![HarmonyOS文件管理](harmony/20-file-manager.jpg) |

| 整理历史 | 全量手动识别整理 | 插件中心（大胶囊分页） |
| :---: | :---: | :---: |
| ![HarmonyOS整理历史](harmony/21-transfer-history.jpg) | ![HarmonyOS手动整理](harmony/22-manual-transfer.jpg) | ![HarmonyOS插件中心](harmony/23-plugins-center.jpg) |

| 插件配置表单（原生渲染） | 插件数据页 | 我的仪表盘（实时统计 + 存储环） |
| :---: | :---: | :---: |
| ![HarmonyOS插件配置](harmony/24-plugin-config-form.jpg) | ![HarmonyOS插件数据页](harmony/25-plugin-data-page.jpg) | ![HarmonyOS仪表盘](harmony/26-dashboard-top.jpg) |

### 3D 社区勋章、捷径词表、设置与 AI 智能助手

| 社区勋章墙 + 内存占用 | 3D 社区勋章检视与背面凹雕 | 快捷工具弹窗 |
| :---: | :---: | :---: |
| ![HarmonyOS勋章与内存](harmony/27-dashboard-medals-memory.jpg) | ![HarmonyOS3D勋章](harmony/28-dashboard-3d-medal.jpg) | ![HarmonyOS快捷工具](harmony/29-dashboard-shortcuts.jpg) |

| 编辑我的模块（8 模块开关排序） | 词表管理（识别词动态提示） | 词表管理（制作组动态示例） |
| :---: | :---: | :---: |
| ![HarmonyOS编辑我的模块](harmony/30-dashboard-customize.jpg) | ![HarmonyOS词表识别词](harmony/31-words-identify.jpg) | ![HarmonyOS词表制作组](harmony/32-words-release-group.jpg) |

| 设置中心（实时计数 + 鸿蒙分组） | 主题与外观（5 套鸿蒙色板 + 旗舰光感） | 下载器配置列表 |
| :---: | :---: | :---: |
| ![HarmonyOS设置中心](harmony/33-settings-hub.jpg) | ![HarmonyOS主题外观](harmony/34-harmony-theme-studio.jpg) | ![HarmonyOS下载器列表](harmony/35-downloaders-list.jpg) |

| 下载器编辑与删除 | AI 智能助手（工具折叠卡 + Markdown） | AI 历史会话管理 |
| :---: | :---: | :---: |
| ![HarmonyOS下载器编辑](harmony/36-downloader-editor.jpg) | ![HarmonyOS智能助手](harmony/37-agent-chat.jpg) | ![HarmonyOSAI历史会话](harmony/38-agent-history-sessions.jpg) |

| AI 附件与斜杠命令弹窗 | | |
| :---: | :---: | :---: |
| ![HarmonyOSAI附件命令](harmony/39-agent-attach-commands.jpg) | | |
