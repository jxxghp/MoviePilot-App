# P1.4b Rex 卡片通透度修正

用户指出原生表单偏灰、缺少 Rex 的通透和玻璃感后，重新检查共享 CinematicPanel。[方案与修正边界](../glass-clarity.md)先记录反馈，再以真实运行截图迭代。此项仅修正卡片表面，不把整个产品或插件迁移记为完成。

## 逐图检查

1. **修正前：确认缺陷。** [Rex / 修正前 / 当前同屏图](2026-11-20-glass-clarity/comparison.png)中，原卡片呈均匀中性灰，背景的紫/玫瑰色被压弱。原配方是较重的系统材质叠均匀白层，仅有细边与投影；此前内部 passed 未充分识别这个差异，不能当作用户认可。
2. **整卡 clear 试验：拒绝。** 将正文整体放入系统 Liquid Glass 容器后，实际 [iPad 截图](2026-11-20-glass-clarity/attempt-1-rejected/rejected-cross-page-glass.png)出现背页串影、相邻卡片粘连。该版 6 项交互测试虽通过，视觉仍失败；相关接线全部撤回，没有交付该方案。
3. **轻材质试验：继续调整。** 降低遮罩后灰雾消退，但表面 [过于淡薄](2026-11-20-glass-clarity/attempt-2-too-faint/comparison.png)，接近透明描边。对照 Rex 后补回淡紫色方向高光，保留卡片厚度与明确边界。
4. **初次修正：仅内部比较通过。** 正文用低遮罩原生 ultraThinMaterial、淡紫色亮面、渐变细边与轻阴影。用户再次并排检查后仍觉得偏灰，原先的视觉判断被重新打开，并调整中性材质遮罩与紫/玫瑰色相。导航/实际动作继续既有系统 Liquid Glass；没有跨页面混合正文、手写模糊或新主题。

同时实际打开 [iPad 设置](2026-11-20-glass-clarity/final/rex-native-settings.png)、[工作台](2026-11-20-glass-clarity/final/rex-native-dashboard.png)、[表单](2026-11-20-glass-clarity/final/rex-native-plugin-form.png) 和 [iPhone 字段](2026-11-20-glass-clarity/final/phone-weekday-custom.png)。颜色随背景贯通，卡片没有串影或粘连，文字、细分隔与开关仍清楚。预览中的媒体/图表为演示数据；真实表单操作使用 API-only 合成服务，均不冒充生产实例。

## 验证边界

| 证据 | 结果与适用范围 |
| --- | --- |
| App / 预览编译 | 最终两 Scheme 的 build-for-testing 均成功，minos 16.0 / SDK 27.2；实际运行是 iOS 26.1 模拟器 |
| [最终 iPhone](2026-11-20-glass-clarity/glass-phone-final-tests.json) | 1 项通过、0 失败/跳过；真实连接/登录、字段选择、两次完整保存及服务端模型检查，截图采用当前淡紫亮面 |
| [最终 iPad 预览](2026-11-20-glass-clarity/glass-preview-final-tests.json) | 设置/表单开关与保存、工作台各一项，通过 2 项，0 失败/跳过；当前表面真实截图 |
| [完整来源表单](2026-11-20-glass-clarity/glass-phone-2-tests.json) | 淡材质阶段完整 LibraryScraper 与数字星期两项通过；最终只调整普通状态的亮面/细边颜色，输入/导航结构未变，相关交互证据保留 |
| 最大字号 / 系统浅色 | [正常辅助设置下的最大字号](2026-11-20-glass-clarity/glass-accessibility-tests.json)通过；固定 Rex 风格不随系统浅色设置切换 |
| [实际辅助设置](2026-11-20-glass-clarity/glass-accessibility-2-tests.json) | 最大字号、降低透明度、减弱动态、提高对比度开启后通过 1 项；runner 返回 true/true。该分支的同色实底与增强边缘未受最后的普通状态亮面调整影响，故不重复运行 |
| 格式 / 范围 | 最终共享 Swift 源文件严格格式与 diff 检查通过；其余尝试时的页面/容器改动全部撤回。纯模型/后端/脚本未改变，沿用前一叶子的 334 项 Swift Testing + 4 项 XCTest、21 项 Python 基线，不虚构为本次重跑 |

有一次辅助设置准备时，设备已被 Xcode 自动关闭，设置命令未生效；随后的用例只能计为普通最大字号。重新显式启动设备、核实键是否存在、设置并重启后再执行，实际 true/true 记录才用于辅助设置结论；没有把第一次成功的测试误记为设置已启用。

各轮共 15 次操作执行通过，但其中 6 次属于视觉被拒的 clear 试验；另有淡薄版和后续配色复核。**这不是最终单一构建的 15 项全绿声明。** 当前构建直接复核 3 项，未受配色影响的分支/完整表单保留独立证据，全部原始批次见 [机器记录](2026-11-20-glass-clarity/manifest.json)。

截图只做 EXIF 方向转正、去元数据与等比缩小；比较图标签放在截图外，没有后期调色、拉伸、重画状态栏或拼造页面。正文静态表面与导航交互玻璃分别使用合适的原生组件，执行了指定 swiftui-liquid-glass 技能的层级/可用性/交互检查；[Apple Glass 文档](https://developer.apple.com/documentation/swiftui/glass)为官方参考。

## 留存与接续

原始 xcresult、命令/日志、最终源文件/二进制摘要和设置恢复记录位于机器记录标明的外置目录。专用 iPad 的三个辅助设置键逐键恢复原先的不存在状态，专用模拟器关闭、夹具停止；内部临时构建/结果缓存已删除，共享依赖与模拟器数据保留。

此处保存的是初次修正记录；视觉验收以 [2026-11-20 用户确认及复测](2026-11-20-glass-revision/)为准。它不代替真机、最低系统运行、完整 VoiceOver 或性能验收。既有 Form/键盘工具栏 `Invalid frame dimension` 未关闭诊断、未记为已修复，仍在 P8。当前只在 v2 本地实施，默认 1.x 未切换，长期 Goal 保持 active；复杂选择/规则继续后续叶子，共享材质继续受 Rex 单一风格约束。
