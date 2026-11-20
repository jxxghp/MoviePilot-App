# 原生 v2 Rex 视觉预览检查

2026-11-19 开始，2026-11-20 收尾。范围仅为 P0.2 的已采集原生预览状态；这个结果不代表用户已批准页面定稿、真实业务已接通或长期 Goal 完成。

## 来源、实现与归一化

- 来源视觉真值：[用户提供的六张 Rex 参考](docs/native-v2/references/rex/README.md)，均为 588×1280px，来源的逻辑点数和系统版本未知。
- 实现：独立 MoviePilotDesignPreview SwiftUI App，固定 Rex 深色风格、中文、隔离演示数据；没有网页原型或仿制状态栏/设备框。
- iPhone：402×874pt，原始 1206×2622px、3×；文档等比降采样到 588×1278px。横屏实际为 874×402pt。
- iPad：834×1210pt，原始 1668×2420px、2×；文档为 834×1210px。横屏实际为 1210×834pt，文档按宽等比缩小。
- 原生实现没有 CSS 视口或浏览器缩放。来源与实现按 sRGB 像素处理，完整比较左右等宽 588px；不拉伸、重画或替换 UI，2px 高度差留底色。
- [截图索引、原始附件及 SHA-256](docs/native-v2/evidence/2026-11-20-rex/screenshots.json)、[源码摘要](docs/native-v2/evidence/2026-11-20-rex/source-hashes.json)、[运行记录](docs/native-v2/evidence/2026-11-20-rex.md)。原分辨率附件在外置盘 xcresult；文档图片去除设备元数据。

## 完整与局部比较

实际打开同一输入中的来源/实现左右画面后判断，未只读路径或分别凭记忆比较。

| 面 | 完整比较 | 局部证据 |
| --- | --- | --- |
| 发现 | [参考 6 / 原生发现](docs/native-v2/evidence/2026-11-20-rex/comparisons/discover.png) | [海报/字体](docs/native-v2/evidence/2026-11-20-rex/comparisons/focus-posters.png) |
| 九项网格 | [参考 2 / 原生网格](docs/native-v2/evidence/2026-11-20-rex/comparisons/grid.png) | 同上，图片等高、同排顶边对齐 |
| 详情 | [参考 6 的图像语言 / 原生详情](docs/native-v2/evidence/2026-11-20-rex/comparisons/detail.png) | 来源没有相同详情状态，本页是同体系延展 |
| 设置 | [参考 4 / 原生设置](docs/native-v2/evidence/2026-11-20-rex/comparisons/settings.png) | [导航玻璃](docs/native-v2/evidence/2026-11-20-rex/comparisons/focus-navigation.png) |
| 插件表单 | [参考 1 的分组表单 / 原生配置](docs/native-v2/evidence/2026-11-20-rex/comparisons/form.png) | [材质/开关/分隔/字重](docs/native-v2/evidence/2026-11-20-rex/comparisons/focus-form.png) |
| 工作台 | [参考 5 的统计卡 / 原生工作台](docs/native-v2/evidence/2026-11-20-rex/comparisons/dashboard.png) | MoviePilot 服务/下载/存储替换观看统计，非相同业务数据 |

## Findings 与修正历史

| 轮次 | 问题 | 修正与重采集 |
| --- | --- | --- |
| 1 | P1 设置行空白处不响应；P1 父层标识覆盖首页详情入口；完整网格证据不足 | 完整行设置 contentShape，移除无用途父层标识，增加从实际分区进入九项网格的测试。[早期设置](docs/native-v2/evidence/2026-11-20-rex/history/iteration-1-settings.png)。后续导航/保存/队列实际通过。 |
| 2 | P2 长标题挤压图片；P2 静态账户面板误带箭头 | 采用独立 2:3 图像容器；移除无动作箭头。[修正前网格](docs/native-v2/evidence/2026-11-20-rex/history/iteration-2-grid.png)，对照最终设置/网格。 |
| 3 | P2 比例已固定，但长标题项默认居中导致图片顶边上移 | GridItem 顶端对齐。[中间状态](docs/native-v2/evidence/2026-11-20-rex/history/iteration-3-grid.png) 对照最终 grid.png，图片等高且顶边一致，文字自然换行。 |
| 4 | P2 详情从导航栏下方开始，顶部分区削弱沉浸图像；预览方向声明不完整 | 图像延伸至顶部安全区，保留系统玻璃返回；补齐 iPhone 横竖屏/iPad 四方向。[修正前详情](docs/native-v2/evidence/2026-11-20-rex/history/iteration-4-detail.png) 对照最终 detail.png，顶端连续且主操作更早可见。 |
| 5 | 横屏快捷 swipe 未触达卡片，不能先判定布局通过 | 沿实际内容边缘定向拖动，保留窗口横向尺寸/hittable 断言；实际截图确认存储卡片可达，双设备测试通过。 |

当前已检查状态没有待处理的 P0/P1/P2 视觉或交互问题。编译/资源配置排错未计作视觉迭代。

## 五个必查面

| 面 | 观察与处理 |
| --- | --- |
| 字体/排版 | 系统动态文字/SF Symbols；大标题、分区、正文和元信息层级清楚。海报标题前缘对齐、最多两行以保留可读性，与来源的居中单行有意不同。最大辅助字号允许表单增高/换行/滚动，未缩字塞入。 |
| 间距/布局 | 页边距 20pt、连续圆角 24pt、表单边距 18pt、轻分隔；圆形动作 46pt、分区至少 44pt。三列 2:3 网格，长标题不挤压图片；iPad 自适应列数和阅读宽度。横屏有实际窗口与滚动证据。 |
| 色彩/材质 | 连续深蓝紫/烟紫/玫瑰底；内容原生 Material、导航/浮动动作原生 Liquid Glass。当前系统的折射/紫色透底比参考略强，保留系统材质行为。仅一套 Rex 风格，没有浅色/皮肤/主题入口。 |
| 图片 | 裁自用户参考中的独立电影艺术区域，未用图形/色块替代，UI 文本/控件均原生。原始海报约 171×258px，预览受来源清晰度限制；正式高清 poster/backdrop 与缓存属于业务图片管线。 |
| 文案/内容 | MoviePilot 服务、订阅、下载和插件语义替换 Rex PRO/iCloud/Trakt 等其它产品字段。独立名称“MoviePilot预览”，“关于本预览”说明演示数据/内存状态；未把用户设计指令塞进产品正文。 |

## 交互、辅助设置与范围

- 7 个 XCTest 在 iPhone/iPad 各执行一次，共 14 次通过、零失败/跳过；详情最终改动后另跑 3 项媒体路径 × 两设备，共 6 次通过。
- 最终辅助设置补充两项通过：专用 iPhone 开启提高对比度、降低透明度和减弱动态。UIKit 公共状态后两项实际返回 true；截图可见同色不透明分组与系统不透明导航，表单保存仍可达。随后恢复原设置。
- 系统浅色启动参数下根 preferredColorScheme 仍为固定深色，与最大辅助字号同跑，未制作第二主题。iPad 竖屏/横屏均有实际截图。
- 三份最终 xcresult 摘要 runtimeWarnings 为空。较早的方向声明警告已修正；主机诊断/调试器日志不代表已完成性能或崩溃诊断门禁。
- 覆盖路径可访问性树 WebView=0；预览源码/目标依赖/直接链接无 WebKit。不将此结果推广为旧主 App 全进程分配计数或 P8 移除已完成。
- 仅在 iOS 26.1 模拟器运行。最低系统、真机、完整 VoiceOver、所有页面的大字/长文案、真实后端/JSON/插件生态继续由后续阶段验收。

## Implementation Checklist

- [x] 固定一套 Rex 渐变/材质/海报/原生导航，应用指定 swiftui-liquid-glass 技能。
- [x] 修复海报比例/顶边、整行触控、静态箭头、详情顶部分区和方向声明。
- [x] 完整与局部并排检查字体、间距、颜色、图像及内容。
- [x] 保存实际测试、原附件/源码摘要、修正历史，更新后续门槛。
- [x] 高清图/完整可访问性/真实业务/最低系统仍列入后续叶子，未冒记完成。

final result: passed

## P1.4a 真实账号/实例入口的追加检查

本段独立于前述媒体演示预览，输入与技术证据见 [真实入口验收](docs/native-v2/evidence/2026-11-20-rex-entry.md)。API-only 合成服务驱动真实会话/Keychain；不把本机夹具当作生产验收。

- 在同一输入中实际打开 [Rex / 原生登录完整比较](docs/native-v2/evidence/2026-11-20-rex-entry/comparisons/login.png)、[局部分组](docs/native-v2/evidence/2026-11-20-rex-entry/comparisons/focus-form.png) 和 [初始化/降低透明度](docs/native-v2/evidence/2026-11-20-rex-entry/comparisons/initialization.png)。颜色、材质、文字/分隔、按钮/开关与页面背景保持唯一 Rex 体系；参考是播放表单，其字段语义不复制。
- 修正了默认 prompt/禁用主按钮过暗、秘密图标的实际 44pt 标签边界、最大字号图标列宽和 UIKit 场景显隐重置。最终 prompt 与禁用态修正后重新采集常规、辅助设置及 iPad 画面；[历史比较](docs/native-v2/evidence/2026-11-20-rex-entry/history/login-before-contrast.png) 保留修正前输入，不冒充最终版本。
- 正常连接/登录/账号有 [三屏总览](docs/native-v2/evidence/2026-11-20-rex-entry/entry-board.png)；iPad 限宽、大字横屏、辅助错误重试均有实际截图。动态字体自然增高；仅表单图标/44pt 秘密动作保留合适尺寸，没有通过缩字强塞字段。
- 图像按原附件 EXIF 方向转正、去元数据后等比缩小，没有旋转屏幕内容来伪造真实横屏或拼接状态栏。入口没有媒体语义，不加入演示海报来填空；主体媒体页仍需真实数据和后续验收。
- 两设备完整 14 次入口测试、最终对比度输入 6 次入口定向、共享组件 3 项预览通过，0 跳过。提高对比度/降低透明度/减弱动态开启后实测，随后恢复原设置；完整 VoiceOver 和最低系统/真机仍未完成。
- 仍有 `Invalid frame dimension` 运行警告，独立系统 Form/键盘工具栏程序也可复现；未关闭诊断或记为已修复，保留 P8 系统兼容门禁。

已检查画面与交互的 P1.4a 视觉结果：passed；系统运行警告、真实环境与完整产品范围不包含在此视觉结论中。

## P2.2b.1 动态插件配置追加检查

输入与来源见 [插件配置 UI 验收](docs/native-v2/evidence/2026-11-20-plugin-rendering.md)。本轮按指定 swiftui-liquid-glass 复核技能/官方 API，并复用同一 Cinematic 组件。固定 Rex 一种风格，不添加主题开关。

- 同次打开 [Rex / 原生配置完整比较](docs/native-v2/evidence/2026-11-20-plugin-rendering/rex-comparison.png)、[局部分组](docs/native-v2/evidence/2026-11-20-plugin-rendering/rex-form-detail.png) 和 [设备总览](docs/native-v2/evidence/2026-11-20-plugin-rendering/device-board.png)，核对渐变、材质、字体/层次、间距和实际字段。统一圆角/细分隔/原生开关，内容与导航玻璃保持适当层次。
- 完整 get_form 生成真实控件，不以静态截图或演示固定表单替代解析；多行编辑、单多选弹层、保存/失败/未知能力/放弃确认均有真实交互状态。输入绑定修正后，用快速键入两行目录与服务端完整模型互证，非只检查截图。
- iPhone 常规与最大字号横屏、iPad 正常限宽/弹层，以及 iPad 降低透明度/提高对比度/减弱动态下的多选和最大字号保存已操作。正常材质透底，降低透明度时同色实面；不通过缩字实现大字检查。秘密显隐与后台恢复不泄露到最终画面。
- 截图仅做方向转正、去元数据、等比缩小；最大字号原图可滚动浏览，顶部已滚出的内容不伪装为裁切缺陷。配置页不放装饰海报，媒体页的海报要求继续 P3。
- 中间失败批次及测试辅助定位修正逐项记录，未把它们改写为整体成功。既有键盘工具栏运行警告、最低系统/真机、完整 VoiceOver/性能与全生态仍继续验收。

本批配置页面的实际视觉/可用性检查：passed；结论不覆盖全部产品或生产插件执行结果。

## P2.2b.2a 原生 Cron 追加检查

按指定 swiftui-liquid-glass 技能继续复用同一套 Rex 渐变、玻璃分组和原生导航。固定一种风格，未增加主题选择。来源、批次与完整边界见 [Cron 验收](docs/native-v2/evidence/2026-11-20-plugin-cron.md)。

- 实际打开 [Rex / 原生计划 / 模式选择并排图](docs/native-v2/evidence/2026-11-20-plugin-cron/rex-comparison.png)，比较背景、材质透底、圆角/分隔、字体/提示、间距与导航。模式页保持同一原生外观，未退回纯灰/白列表底。
- 实操发现同一 Form 玻璃分组的多个 NavigationLink 会整行联动，改为明确的逐项按钮与按单位隔离草稿；真实 UI 分别验证五个单位的导航/编辑，取消和父表单保存边界分明。
- 最大辅助字号横屏暴露模式菜单溢出视口，改为可滚动原生选择页。最终 iPhone 和 iPad 均完成星期空选禁用、选择/应用/保存；没有缩字、坐标点击或删除该状态来绕过。
- 检查 [iPad 降低透明度/分钟间隔](docs/native-v2/evidence/2026-11-20-plugin-cron/ipad-accessibility/rex-cron-minute-step.png) 和 [最大字号选值](docs/native-v2/evidence/2026-11-20-plugin-cron/ipad-accessibility/rex-cron-largest-weekday.png)。真实辅助设置开启，同色实面、分隔与系统按钮保持可用，长表单自然滚动。
- 图片仅方向转正、去元数据、等比缩小；并排标签置于截图外。配置界面不加入装饰海报，媒体页海报要求继续后续阶段。保留全部中间失败，不以局部通过代替完整产品、真机、最低系统或 VoiceOver 验收。

此叶子的实际视觉与操作检查：passed；既有 Form/键盘工具栏布局警告继续 P8，未冒记为已解决。

## 2026-11-20 P2.2b.2b.1 原生组合框

- [iPhone 来源对象预设](docs/native-v2/evidence/2026-11-20-plugin-combobox/iphone-object-preset.png)、[自定义值和系统键盘](docs/native-v2/evidence/2026-11-20-plugin-combobox/iphone-custom-input.png)、[保留对象的多值编辑](docs/native-v2/evidence/2026-11-20-plugin-combobox/iphone-multiple-values.png)和 [iPad 大字横屏](docs/native-v2/evidence/2026-11-20-plugin-combobox/ipad-largest-landscape.png)为 API-only 合成夹具上的真实模拟器截图。它们保留修正后的 Rex 渐变与通透玻璃卡片，不引入第二主题或 Web 内容。
- 最终 iPhone 构建的对象预设/取消/重新选择/自定义输入、多值增删/取消/清空与失败保存重试三项 UI 测试，及同一最终构建的 iPad 最大字号/横屏和降低透明度/减弱动态检查一项，均通过且零跳过。VoiceOver 全量、iOS 16 真机和性能仍为 P8 门槛。
- 模拟器保留并恢复原本缺失的辅助设置键；测试完成后设备均关闭。原图未调色，仅直接从 xcresult 导出。

## 2026-11-20 用户反馈重新打开玻璃材质验收

用户明确指出当前表单卡片偏灰，不如 Rex 通透、有玻璃感。此前各叶子的 passed 是当时内部判断，不代表用户认可此材质；本项重新打开，优先执行 [P1.4b](docs/native-v2/glass-clarity.md)。修正前截图保留，后续必须将参考/修正前/修正后同屏，实际检查透底的紫/玫瑰渐变、灰雾、边缘与可读性，不能只凭 API 名称或测试绿勾判定。仍只做 Rex 一套风格。

### P1.4b 本地修正结果

实际打开 [参考/修正前/当前同屏](docs/native-v2/evidence/2026-11-20-glass-clarity/comparison.png)、最终 iPad 设置/工作台/表单与 iPhone 字段。较重中性灰雾改为低遮罩原生材质与淡紫方向亮面，背景色贯通，边缘有轻薄层次；文字、分隔和开关仍清楚。完整记录见 [修正验收](docs/native-v2/evidence/2026-11-20-glass-clarity.md)。

- 整卡 clear 试验即使操作测试绿，也因背页串影/卡片粘连被视觉拒绝，相关接线全部撤回。
- 过淡版本继续补回可辨识的淡紫亮面；没有以纯透明描边代替玻璃，不改字体、间距、布局或控件。
- 最终构建直接验证 3 项，最大字号/实际辅助设置和完整来源表单保留独立适用证据；辅助设置第一次未生效的批次没有冒记为启用。
- 本地比较检查通过、图片交用户查看；不宣称用户已批准。真机、最低系统、完整 VoiceOver/性能及既有布局警告仍属 P8。
