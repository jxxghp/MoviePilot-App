# 视觉方案与设计交付

## 目标

保留 MoviePilot 的媒体海报、清晰分区、主题主色、卡片、壁纸与玻璃导航风格，改进信息密度和操作层级。主体是真实原生布局，不把网页截图切片做成界面。

参考现有 [推荐](../../screenshots/screens/06.png)、[仪表板](../../screenshots/screens/02.png)、[插件](../../screenshots/screens/07.png)、[订阅](../../screenshots/screens/13.png)、[文件管理](../../screenshots/screens/09.png) 和 [截图册](../../screenshots/README.md)。这些是已有 1.x 视觉参考，不是 v2 实现结果；部分截图来自较早版本，功能仍以本次固定源码为准。

原生导航、内容分层、搜索和可访问性参考：

- [Apple：Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)。
- [Apple：Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)。
- [Apple：Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) 与 [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)。

玻璃材质主要服务于导航和悬浮控件；内容区优先保证海报、正文、图表和表单的可读性。旧系统用受支持的系统材质，保持层次一致，不模拟不可用的系统 API。

## 主要页面的预览顺序

| 批次 | 预览 | 先解决的问题 |
| --- | --- | --- |
| D1 | 仪表板、推荐/探索 | 默认首页、导航层级、海报与状态密度、插件卡片位置、iPad 分栏 |
| D2 | 媒体详情、资源搜索、下载确认 | 主操作、季集、来源、筛选和长列表/长文案 |
| D3 | 订阅列表/编辑、下载管理 | 进度与异常、状态筛选、批操作和确认 |
| D4 | 插件列表、JSON 配置、数据页、Web 插件入口 | 原生与兼容的边界、复杂表单、配置/保存/失败反馈 |
| D5 | 文件/工作流/设置/Agent | 高信息密度、节点画布、输入与对话、多任务状态 |

每批展示 iPhone 主画面、关键状态和 iPad 适配示意；不在一张“功能墙”里挤进所有入口。主要页面视觉选定后再批量写页面代码，底层网络/模型/解析器可提前独立实施。

## 方向与默认约束

先在现有产品视觉内比较少量真实差异：保持现有层级的原生还原、更多使用系统分组的管理界面、以大海报/内容为主的浏览界面。展示实际预览后再选择，不要求用户仅凭文字猜效果，也不擅自把全 App 改成另一种风格。

- iPhone 预览按 390×844pt 布局思考，iPad 按 834×1194pt 思考；实际实现采用 safe area 与自适应布局，不写死设备坐标。
- 正文使用系统动态字体，主操作触控区至少 44pt；不靠缩字容纳复杂表格。
- 最多保留少量稳定的顶级入口；其它能力通过有名称的分类和上下文动作到达。管理员/普通用户的默认入口沿用权限语义。
- 同一个视觉方向必须有浅/深主题，保持既有壁纸/主色偏好；无壁纸时仍有清楚的层级。
- 表单、进度、确认、错误、空态和无权状态要与正常画面同时设计；截图上漂亮但操作闭环缺失不算完成。

## 首轮状态

本轮已查看现有产品截图并确认参考基线，尚未产出或批准新的设计图。当前会话未提供内置图像生成工具；不自动调用收费图像 API。可选 CLI 图生需要另行确认并在本机配置 OPENAI_API_KEY，本次未启用。

后续 P0.2 优先提供可审阅的原生预览截图；工具可用时也可生成概念图。预览、概念稿与已实现页面分别标注，不能把静态图当作原生功能完成。当前先推进不依赖视觉选择的 API、会话与插件协议底座。
