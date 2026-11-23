# MoviePilot-App 多平台原生客户端界面图册

本图册按平台目录归档真机/模拟器运行验收截图：
- `screenshots/ios/`：iOS 26 模拟器（iPhone 17）60 张黄金验收图
- `screenshots/android/`：Android 15（API 35 ARM64 硬件 GPU 模拟器）17 张真机链路实测验收图
- `screenshots/harmony/`：HarmonyOS NEXT 模拟器验收图（待 DevEco Studio 与鸿蒙模拟器就绪后补齐）

特别说明：UI设计风格参考了 [Rex iOS App](https://rexnow.tv)。

---

## Android（Jetpack Compose + AGSL + Rust UniFFI · API 35 实测验收）

以下 17 张截图均采集自 Android 15（API 35，`MoviePilot_API35` ARM64 模拟器，Apple M4 Vulkan `gfxstream` 硬件加速）真实运行界面，直连本地 MoviePilot V3 夹具实例并调用原生 `libmoviepilot_core.so`（884 KB），全程零崩溃（`AndroidRuntime:E` = 0）。

### 连接服务、登录与主导航体验

| 连接服务（AGSL 流光背景） | 登录页 | 发现首页（无接缝主视觉融合） |
| :---: | :---: | :---: |
| ![Android连接服务](android/01-connection.png) | ![Android登录](android/02-login.png) | ![Android发现首页](android/03-discover-dark.png) |

| 探索片库（多源筛选网格） | 重复点击底栏 8 项玻璃溢出菜单 | 我的仪表盘（深色模式） |
| :---: | :---: | :---: |
| ![Android探索](android/04-explore-dark.png) | ![Android溢出菜单](android/05-overflow-menu.png) | ![Android仪表盘深色](android/06-dashboard-dark.png) |

### 设置中心、订阅、资源筛选与站点

| 设置主中心（Rust 内核标识） | 我的订阅 | 站点资源（Rust 9 维筛选 + 同规格折叠） |
| :---: | :---: | :---: |
| ![Android设置中心](android/07-settings-hub-dark.png) | ![Android订阅](android/08-subscriptions.png) | ![Android站点资源](android/09-resources-rust9dim.png) |

| 站点管理（双向绿/玫红流量条） | 纯原生工作流节点画布 | AI 智能助手（Rust Markdown AST） |
| :---: | :---: | :---: |
| ![Android站点管理](android/10-sites-traffic.png) | ![Android工作流画布](android/11-workflow-canvas.png) | ![Android智能助手](android/12-agent-chat.png) |

### 插件生态、浅色模式与 3D 社区勋章

| 插件中心 | 动态插件表单（Window Blur 实测） | 我的仪表盘（浅色模式 + 暗色状态栏） |
| :---: | :---: | :---: |
| ![Android插件中心](android/13-plugins-installed.png) | ![Android插件表单弹层](android/16-plugin-form-sheet.png) | ![Android仪表盘浅色](android/14-dashboard-light.png) |

| 3D 社区勋章（正面浮雕与陈列墙） | 3D 社区勋章（180° 背面三遍凹雕铭文） | |
| :---: | :---: | :---: |
| ![Android3D勋章正面](android/15-medals-3d.png) | ![Android3D勋章背面凹雕](android/17-medal-3d-back-engraving.png) | |

---

## iOS（SwiftUI + Liquid Glass · iOS 26 模拟器）

以下全部 60 张截图采集自 iPhone 17（iOS 26 模拟器）真实运行界面，展示全原生 SwiftUI v2 客户端（零主流程 WebView）的 4+1 Liquid Glass 导航、玻璃弹层、原生图表与完整业务交互。

## 连接服务与登录

| 连接服务 | 已保存服务与连接按钮 | 登录 |
| :---: | :---: | :---: |
| ![连接服务](ios/native-v2-01-connection.jpg) | ![已保存服务](ios/native-v2-01b-connection-saved.jpg) | ![登录](ios/native-v2-02-login.jpg) |

## 4+1 底部导航、弹出菜单与设置中心

| 发现（透明片名 Logo） | 探索 | 我的（仪表盘） |
| :---: | :---: | :---: |
| ![发现](ios/native-v2-live-discover-phase-1.jpg) | ![探索](ios/native-v2-live-explore.jpg) | ![我的](ios/native-v2-live-dashboard.jpg) |

| 设置主中心 | 重复点击底栏弹出菜单 | 全局搜索（+1 默认回退） |
| :---: | :---: | :---: |
| ![设置主中心](ios/native-v2-live-settings-hub.jpg) | ![弹出菜单](ios/native-v2-live-overflow-menu.jpg) | ![全局搜索](ios/native-v2-live-search.jpg) |

## 发现滚动、模块编排、详情与人物

| 发现滚动阶段 2 | 发现滚动阶段 3 | 发现滚动阶段 4 |
| :---: | :---: | :---: |
| ![发现阶段2](ios/native-v2-live-discover-phase-2.jpg) | ![发现阶段3](ios/native-v2-live-discover-phase-3.jpg) | ![发现阶段4](ios/native-v2-live-discover-phase-4.jpg) |

| 发现模块编辑（独立媒体库/分类浏览） | 榜单网格（分页前） | 榜单网格（自动翻页） |
| :---: | :---: | :---: |
| ![发现模块](ios/native-v2-live-modules.jpg) | ![网格分页前](ios/native-v2-live-grid-before-pagination.jpg) | ![网格自动翻页](ios/native-v2-live-grid-automatic-page.jpg) |

| 媒体详情（订阅 + 搜索资源） | 媒体详情演职员 | 人物详情 |
| :---: | :---: | :---: |
| ![媒体详情](ios/native-v2-live-detail.jpg) | ![详情演职员](ios/native-v2-live-detail-cast.jpg) | ![人物详情](ios/native-v2-live-person.jpg) |

| 剧集详情 | 剧集分季 | 网格翻页状态 |
| :---: | :---: | :---: |
| ![剧集详情](ios/native-v2-live-tv-detail.jpg) | ![剧集分季](ios/native-v2-live-tv-seasons.jpg) | ![翻页状态](ios/native-v2-live-grid-pagination-state.jpg) |

## 探索、豆瓣详情、音乐、订阅与资源下载

| 探索（豆瓣筛选） | 豆瓣作品详情 | 豆瓣演职员与推荐 |
| :---: | :---: | :---: |
| ![豆瓣探索](ios/native-v2-live-explore-douban.jpg) | ![豆瓣作品详情](ios/native-v2-live-douban-detail.jpg) | ![豆瓣演职员与推荐](ios/native-v2-live-douban-detail-cast.jpg) |

| 音乐发现 | 音乐专辑与曲目播放 | 站点资源（关键词搜索 / 首页浏览） |
| :---: | :---: | :---: |
| ![音乐发现](ios/native-v2-live-music.jpg) | ![音乐专辑](ios/native-v2-live-music-album.jpg) | ![站点资源](ios/native-v2-live-resources.jpg) |

| 我的订阅 | 订阅规则编辑 | 追剧日历 |
| :---: | :---: | :---: |
| ![我的订阅](ios/native-v2-live-subscriptions.jpg) | ![订阅编辑](ios/native-v2-live-subscribe-editor.jpg) | ![追剧日历](ios/native-v2-live-calendar.jpg) |

| 订阅广场（热门订阅） | 订阅广场（社区分享） | 正在下载 |
| :---: | :---: | :---: |
| ![热门订阅](ios/native-v2-live-community-popular.jpg) | ![社区分享](ios/native-v2-live-community-shares.jpg) | ![正在下载](ios/native-v2-live-downloads.jpg) |

## 消息、智能助手与捷径诊断中心

| 消息中心（玻璃弹层） | 智能助手（SSE 流式对话） | 捷径菜单（玻璃弹层） |
| :---: | :---: | :---: |
| ![消息中心](ios/native-v2-live-messages.jpg) | ![智能助手](ios/native-v2-live-agent.jpg) | ![捷径菜单](ios/native-v2-live-shortcuts.jpg) |

| 捷径：词表与语法说明 | 捷径：定时服务 | 捷径：实时日志 |
| :---: | :---: | :---: |
| ![词表与语法说明](ios/native-v2-live-diag-words.jpg) | ![定时服务](ios/native-v2-live-diag-schedulers.jpg) | ![实时日志](ios/native-v2-live-diag-logs.jpg) |

## 整理历史、队列、文件管理与工作流

| 整理历史（相对时间 + 链式路径） | 整理队列弹窗 | 文件管理（长按删除 + 动态 +1 按钮） |
| :---: | :---: | :---: |
| ![整理历史](ios/native-v2-live-history.jpg) | ![整理队列](ios/native-v2-live-transfer-queue.jpg) | ![文件管理](ios/native-v2-live-files.jpg) |

| 工作流列表 | 纯原生工作流节点画布 | 工作流社区分享 |
| :---: | :---: | :---: |
| ![工作流列表](ios/native-v2-live-workflows.jpg) | ![工作流画布](ios/native-v2-live-workflow-canvas.jpg) | ![工作流社区](ios/native-v2-live-workflow-shares.jpg) |

## 站点、系统配置与外观

| 站点管理（上下行流量图示） | 站点数据（历史流量趋势图） | 订阅与搜索设置 |
| :---: | :---: | :---: |
| ![站点管理](ios/native-v2-live-sites.jpg) | ![站点数据图表](ios/native-v2-live-site-data.jpg) | ![订阅与搜索设置](ios/native-v2-live-sysmod-site-scope.jpg) |

| 媒体数据源配置 | 下载器管理 | 媒体服务器管理 |
| :---: | :---: | :---: |
| ![媒体数据源](ios/native-v2-live-settings.jpg) | ![下载器管理](ios/native-v2-live-sysmod-services.jpg) | ![媒体服务器](ios/native-v2-live-mediaservers.jpg) |

| 目录与存储 | 服务端通知渠道 | 主题与外观 |
| :---: | :---: | :---: |
| ![目录与存储](ios/native-v2-live-sysmod-directories.jpg) | ![通知渠道](ios/native-v2-live-sysmod-notifications.jpg) | ![主题与外观](ios/native-v2-live-appearance.jpg) |

## 用户管理与插件生态

| 用户管理 | 插件市场 | 已安装插件管理 |
| :---: | :---: | :---: |
| ![用户管理](ios/native-v2-live-users.jpg) | ![插件市场](ios/native-v2-live-plugin-market.jpg) | ![已安装插件](ios/native-v2-live-plugin-installed.jpg) |

| 仪表盘无缝插件图表 | 插件数据页（站点统计环形图） | 插件数据页（猫眼票房排行） |
| :---: | :---: | :---: |
| ![仪表盘插件](ios/native-v2-live-dashboard-plugins.jpg) | ![站点统计](ios/native-v2-live-plugin-page-statistic.jpg) | ![猫眼排行](ios/native-v2-live-plugin-page-maoyan.jpg) |

