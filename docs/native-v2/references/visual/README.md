# 用户提供的 视觉参考

来源：2026-11-19 至 2026-11-20 当前长期任务中，用户上传十八张 既定视觉参考 截图，并明确要求“全局渐变背景，玻璃拟态的卡片和表单，大量应用海报图片”，使用 Apple 设计语言及 `swiftui-liquid-glass` 技能。用户已确认最终表单透光度可作为后续标准。最后四张是发现页的连续滚动状态，覆盖早先只根据单张主视觉推断的实现。

以下保存为去除 EXIF 的 PNG，保持原解码像素及各原图尺寸；原始上传文件的 SHA-256 见 [manifest.json](manifest.json)。这些是参考材料，不是 MoviePilot 已实现画面或发布资产。

| 参考 | 文件 | 要提取的设计规则 |
| --- | --- | --- |
| 1 播放设置表单 | [01-playback-form.png](01-playback-form.png) | 连续渐变、半透明分组表单、细分隔、原生开关/步进与说明层级 |
| 2 海报网格 | [02-poster-grid.png](02-poster-grid.png) | 大面积 2:3 海报、三列网格、紧凑标题/年份、圆形导航动作 |
| 3 发现分区 | [03-discovery-sections.png](03-discovery-sections.png) | 横向海报栏、横幅卡、清楚分区、悬浮导航与独立搜索入口 |
| 4 设置 | [04-settings.png](04-settings.png) | 玻璃卡片/模块入口、色彩透底、统一边缘和圆角、原生大标题 |
| 5 我的/仪表信息 | [05-personal-dashboard.png](05-personal-dashboard.png) | 玻璃状态卡、少量明确指标、日历/分页、克制信息密度 |
| 6 发现主视觉 | [06-featured-discovery.png](06-featured-discovery.png) | 电影背景大图、渐变融入页面、内容主导、继续观看横卡与浮动导航 |
| 7 下载列表 | [07-download-list.png](07-download-list.png) | 横向缩略图、任务来源/时间/集数、玻璃卡片和线性进度 |
| 8 媒体搜索列表 | [08-media-search-list.png](08-media-search-list.png) | 左侧竖版海报、来源平台、评分、摘要和紧凑玻璃卡片 |
| 9 发现页“更多”菜单 | [09-more-menu.png](09-more-menu.png) | 重复点击当前“发现”入口弹出模糊玻璃浮层，展示观看/收藏/下载/日历等快捷区 |
| 10 模块编排 | [10-module-arrangement.png](10-module-arrangement.png) | 玻璃列表中的模块显示开关和拖拽排序 |
| 11 全局搜索 | [11-global-search.png](11-global-search.png) | 顶部类型/分类/年份筛选、人物头像横栏、按电影/电视剧分组的媒体搜索结果和底部原生输入 |
| 12 仪表盘总览 | [12-dashboard-overview.png](12-dashboard-overview.png) | 收藏/在看数量卡和本月观看统计，使用少量醒目数字与海报叠片 |
| 13 日历仪表盘 | [13-calendar-dashboard.png](13-calendar-dashboard.png) | 周日期条、当天空态、周观看时间/片数统计、历史观看与待看分区 |
| 14 媒体库 | [14-library-categories.png](14-library-categories.png) | 播出平台横幅、分类卡和多行海报网格，图片优先且分区清楚 |
| 15 发现首屏 | [15-discover-scroll-1.png](15-discover-scroll-1.png) | 全宽海报进入顶部安全区，文字浮于背景前方，正文初始为近黑 |
| 16 发现上移 | [16-discover-scroll-2.png](16-discover-scroll-2.png) | 背景锚定顶部轻移，文字与栏目正常上滚，渐隐边界随前景上移 |
| 17 发现退场 | [17-discover-scroll-3.png](17-discover-scroll-3.png) | 整页底色逐步变为烟灰紫，顶部滚动边缘柔化，正文海报仍锐利 |
| 18 发现正文 | [18-discover-scroll-4.png](18-discover-scroll-4.png) | 主视觉退出后背景稳定，原生标签栏固定并采样当前内容颜色 |

连续图中，标题与继续观看栏目每段上移约 330、248、278px，而前两张的主视觉红缨仅上移约 20px。应采用独立背景或约 0.93 倍的反向视差补偿，不能把图片和文字捆成滚走的矩形卡片。正文空隙颜色依次约为 `#0A0A16 → #1C1A25 → #29262F`；这是滚动进度驱动的整页底色变化，不是一张固定长渐变背景。第三张背景可能发生轮播换图，不能据它推定整个画面需要模糊。

用户同时要求标签栏、独立搜索入口及顶部动作使用 iOS 原生外观；通过系统 TabView/Search role/Toolbar 承载，不人为压扁或重绘其材质、尺寸、边框和命中区域。媒体网格接近底部自动加载下一页，仅失败时提供明确重试。

保留 MoviePilot 品牌与真实功能语义，不复制 既定深色渐变玻璃的会员/服务功能。系统状态栏、Dynamic Island、键盘和 Home Indicator 由 iOS 绘制，不能从参考图裁下来伪造。单独海报/背景图仅可用作隔离预览素材，不能把整页 UI 切片当实现；生产媒体图片最终来自后端与受控图片加载链路。
