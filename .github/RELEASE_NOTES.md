MoviePilot 现已全面提供 **iOS / iPadOS**、**Android** 与 **HarmonyOS NEXT** 三端全原生客户端（统一版本 **`2.0.8`**），基于 Rust 共享业务内核直连 MoviePilot V3 后端，带来一致的核心功能闭环与地道原生界面体验。

### 本版本核心亮点

- **三端流畅度、高刷滚动与页面秒开深度性能优化**：
  - **Android 全面减负提速**：引入全局 Compose Compiler 稳定性配置（`compose_stability.conf`），让跨模块 DTO 与列表项全面支持智能跳过无效重组；移除主壳与详情页全屏嵌套 `hazeSource` 离屏纹理拷贝及逐像素动态模糊半径重建，将首页与影视详情页的视差、顶栏柔化罩全部下沉至纯绘制层执行，实现零整页重组丝滑滚动；一级主导航（发现、订阅、我的、更多）升级为常驻内存保活并扩展设置与插件中心会话缓存，切换页签与返回上级达到 0ms 瞬开；Coil 图片管线补齐 256MB 磁盘缓存、25% 内存缓存、缩略图按需降采样与代理图片持久化缓存策略。
  - **iOS 与 HarmonyOS 渲染及并发优化**：iOS 海报与剧照缩略图在后台线程提前完成 `preparingForDisplay()` 位图解压并提升同源图片并发连接池上限，消除 120Hz ProMotion 滚动首帧解码卡顿；HarmonyOS 远程图片加载器新增有界并发队列与更大 LRU 容量，收敛发现页滚动状态更新阈值并为插件网格启用节点预缓存。
- **全面接入后端全局图片缓存（`GLOBAL_IMAGE_CACHE`）与代理链路**：
  - 三端登录后自动从 `/api/v1/system/global?token=moviepilot` 同步后端全局图片配置（含 `GLOBAL_IMAGE_CACHE`、`TMDB_IMAGE_DOMAIN`、`FANART_ENABLE` 等）；开启全局图片缓存时统一走后端 `/api/v1/system/cache/image?url=...` 缓存代理加载海报与剧照，未开启时优先公开源直连并在受限网络下自动回退 `/api/v1/system/img/1` 代理，行为与 Web 端完全一致。
- **插件市场与已安装插件体验修复**：
  - 三端插件市场与插件排序菜单补齐「最新发布」排序（对齐 Web 端 `add_time` 排序规则）。
  - 修复插件市场安装/重新安装弹窗主操作按钮对比度不足、视觉上误显灰态不可点的问题。
  - 已安装插件列表自动合并市场更新元数据，有新版本时直接展示醒目的「更新」按钮与可更新标识。
- **音乐播放界面精简优化**：
  - 移除三端全屏音乐播放界面右下角冗余的倍速胶囊按钮，播放倍速统一收纳于右上角 `…` 更多菜单中调节（并完善鸿蒙端菜单停止并关闭后台音频会话释放）。

### 安装包说明

| 平台 | 版本 | 产物文件 | 适用设备与安装说明 |
| :--- | :--- | :--- | :--- |
| **iOS / iPadOS** | `2.0.8` | `MoviePilot-2.0.8-ios-unsigned.ipa` | 需要 **iOS 16+**（小组件需 iOS 17+），下载后使用个人或企业证书重签安装（重签小组件请保持一致的 App Groups）。 |
| **Android（推荐）** | `2.0.8` | `MoviePilot-2.0.8-android-arm64-v8a.apk` | 适用于绝大多数现代 64 位 ARM 手机与平板（**Android 10 / API 29+**），体积更小，可直接安装。 |
| **Android（通用）** | `2.0.8` | `MoviePilot-2.0.8-android-universal.apk` | 同时包含 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` 架构，兼容 32 位旧设备、电视盒子与桌面模拟器。 |
| **HarmonyOS NEXT** | `2.0.8` | `MoviePilot-2.0.8-harmony-unsigned.hap` | 适用于 **HarmonyOS NEXT（API 12+）**，供开发者使用 DevEco Studio / 签名工具配置证书后安装至真机或模拟器。 |

Release 同时提供统一校验文件 `SHA256SUMS`。
