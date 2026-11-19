# 用户提供的 Rex 视觉参考

来源：2026-11-19 当前长期任务中，用户上传六张 Rex App 截图，并明确要求“全局渐变背景，玻璃拟态的卡片和表单，大量应用海报图片”，使用 Apple 设计语言及 `swiftui-liquid-glass` 技能。

以下保存为去除 EXIF 的 PNG，保持原解码像素与 588×1280 尺寸；原始上传文件的 SHA-256 见 [manifest.json](manifest.json)。这些是参考材料，不是 MoviePilot 已实现画面或发布资产。

| 参考 | 文件 | 要提取的设计规则 |
| --- | --- | --- |
| 1 播放设置表单 | [01-playback-form.png](01-playback-form.png) | 连续渐变、半透明分组表单、细分隔、原生开关/步进与说明层级 |
| 2 海报网格 | [02-poster-grid.png](02-poster-grid.png) | 大面积 2:3 海报、三列网格、紧凑标题/年份、圆形导航动作 |
| 3 发现分区 | [03-discovery-sections.png](03-discovery-sections.png) | 横向海报栏、横幅卡、清楚分区、悬浮导航与独立搜索入口 |
| 4 设置 | [04-settings.png](04-settings.png) | 玻璃卡片/模块入口、色彩透底、统一边缘和圆角、原生大标题 |
| 5 我的/仪表信息 | [05-personal-dashboard.png](05-personal-dashboard.png) | 玻璃状态卡、少量明确指标、日历/分页、克制信息密度 |
| 6 发现主视觉 | [06-featured-discovery.png](06-featured-discovery.png) | 电影背景大图、渐变融入页面、内容主导、继续观看横卡与浮动导航 |

保留 MoviePilot 品牌与真实功能语义，不复制 Rex 的会员/服务功能。系统状态栏、Dynamic Island、键盘和 Home Indicator 由 iOS 绘制，不能从参考图裁下来伪造。单独海报/背景图仅可用作隔离预览素材，不能把整页 UI 切片当实现；生产媒体图片最终来自后端与受控图片加载链路。
