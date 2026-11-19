# P2.2b.2a 原生 Cron 配置验收

本地 `MoviePilot-App / v2` 从 `350544d` 接续，2026-11-20。实施前先建立 [Cron 叶子方案](../plugin-cron.md)，复核用户固定 Rex 风格和指定 swiftui-liquid-glass 技能。仅本地开发，没有推送、发布或覆盖真机正式 App；默认入口仍为 1.x。

## 可用结果与兼容边界

- VCronField 接入真实 NativeFormPlan / SwiftUI / 保存验证分支。原生文本输入、清除、预设和分钟/小时/日期/月份/星期字段编辑共享 Rex 渐变、玻璃分组及系统导航；没有新增 WebView、网页桥或脚本执行器。
- 计划与字段各有独立本地草稿：应用字段只更新计划，应用计划只更新父表单；最终明确“保存”才通过现有会话 PUT 物理插件 ID。取消/原样应用不把数字、null、缺失键或已有词法变成字符串/默认周期；清除才写 null。
- 不复制插件调度规则。SiteUserDetail 等现有插件允许数字小时间隔；完整自定义值仍原样交给插件。五字段分析只服务编辑器，不强迫所有值通过标准 Cron，不根据手机时区承诺执行时间。星期新生成值使用 mon–sun；已有数字、别名、空格和前导零不自动规范化。
- 四个完整官方 get_form 为 LibraryScraper、DoubanRank、RSSSubscribe、AutoClean，均由固定 Git 对象 AST 提取，没有运行插件或精简为有利样例。来源见 [夹具记录](../../../Tests/MoviePilotPluginUITests/Fixtures/provenance.json)。回环服务另外明确加入分身、未知字段/大整数、数字/null/缺失等合成边界，不冒充生产实例。
- 原表单有 exclude_paths 绑定而默认 model 没有该键，用户输入后允许加入；未显示的 err_hosts、未来字段和数值类型继续完整保存。未知行为、规则、HTML/槽或编辑器仍阻止保存；隐藏未知夹具增加真正未实现的 VAceEditor，避免把已支持的 Cron 继续冒称未知。

## 实际检查

| 层次 | 实际结果 |
| --- | --- |
| 全部 Swift 包 | 331 项 Swift Testing（核心 166、会话 45、API 23、插件模型/草稿 40、表单 57）与 4 项 XCTest 通过；本轮新增 16 个纯模型/计划测试定义，含参数化边界 |
| 独立构造语料 | 783 组范围、值、步长、星期子集与月底构造，由工作区已安装 APScheduler 3.11.3 的真实 from_crontab 解析，Swift 输出逐字对照；重新生成与提交语料一致。只解析，不执行/注册任务或验证生产副作用 |
| 完整计划/保真 | 四个来源整表、数字/null/缺失/插件方言、精确模型键、大整数、未知字段、必填/长度/结构、disabled/readonly/clearable、未知行为禁存、Unicode 字节与原样应用 |
| Python / Node | 21 项 Python 脚本测试、3 项 Node 回归通过；Python 最终复测使用外置 TMPDIR。负例中的 Git missing 路径诊断是预期输入，测试总结果为 OK |
| iOS 编译 | App + UI 测试 build-for-testing 成功；最终二进制 LC_BUILD_VERSION 为 IOSSIMULATOR、minos 16.0、SDK 27.2；不等于最低系统运行或真机验收 |
| iPhone 17 Pro / iOS 26.1 | 完整来源表单月底编辑/保存/重读；数字/null/缺失保留、取消/清除/手工输入；间隔连续调整/取消/失败保留/显式重试；小时范围/月选值/自定义字段/整层取消；最大辅助字号/横屏星期空选禁用、选择/应用/完整保存；旧完整表单和隐藏未知能力门禁回归 |
| iPad 11 M5 / iOS 26.1 | 最终同一构建 3 项通过：完整来源表单、间隔取消/失败重试、最大字号横屏。降低透明度、减弱动态、提高对比度真实开启；runner 实际返回 reduceTransparency=true / reduceMotion=true，设备对比度为 enabled |
| 静态/范围 | 修改 Swift 的 swift-format lint --strict、三语 strings 的 plutil、diff 检查通过；XcodeGen 仅加入新原生源文件，版本/签名配置不变；继续使用现有会话、身份、完整草稿与管理员/物理 ID 门禁 |

## 批次与修正证据

不能把中间失败改称全绿。原始 xcresult、命令、源文件/二进制摘要与日志留存在 [机器记录](2026-11-20-plugin-cron/manifest.json) 指向的外置目录。

| 批次 | 通过 / 失败 / 跳过 | 观察与处理 |
| --- | --- | --- |
| [iPhone 1](2026-11-20-plugin-cron/phone-1-tests.json) | 3 / 3 / 0 | 数字/空值/取消/清除与两个旧表单门禁通过；字段卡片中的多个 NavigationLink 被整行同时触发，实际进入星期而非点击字段；另有大字横屏预设定位失败 |
| [iPhone 2](2026-11-20-plugin-cron/phone-2-tests.json) | 2 / 1 / 0 | 改为显式普通按钮/单位隔离导航后，月底完整保存、分钟间隔取消/失败重试通过；剩余失败是测试助手在矮视口惯性滚动中反复越过目标，未用坐标点击绕过 |
| [iPhone 3](2026-11-20-plugin-cron/phone-3-tests.json) | 2 / 1 / 0 | 测试滚动改为按实际距离短拖停稳，先检查可见几何再查询命中；预设可用，进一步暴露系统模式 Picker 菜单在最大字号横屏下把“指定值”放到屏幕外。数字兼容与范围/月份/自定义取消通过 |
| [iPhone 最终 4](2026-11-20-plugin-cron/phone-4-tests.json) | 3 / 0 / 0 | 模式改为可滚动原生选择页，完整来源表单、范围/月/自定义、大字横屏全部通过；真实命中/服务端完整模型互证 |
| [iPad 辅助设置](2026-11-20-plugin-cron/ipad-accessibility-tests.json) | 3 / 0 / 0 | 最终构建在实际辅助设置下验证正常表单、步长、最大字号横屏，保存/取消/失败重试均通过 |

合并有效证据覆盖 **10 个不同设备/用例组合**、13 次成功执行（含重复复核），保留 5 次中间失败。最终两个批次专门重验改变过的页面/模式；未受改动影响的类型兼容与旧表单门禁保留此前通过证据。这不是单一“10 项全绿”批次。所有批次实际执行，0 跳过。

## Rex 视觉与原生交互

实际打开 [Rex / 原生计划 / 模式页并排图](2026-11-20-plugin-cron/rex-comparison.png)，检查连续深蓝紫/玫瑰渐变、透底玻璃、圆角与细分隔、文字/提示层级、间距和系统导航。内容用共享 Material 面板，导航用系统 Liquid Glass；不在每个字段重叠玻璃，不新增主题。

同时检查 [iPhone 最大字号横屏](2026-11-20-plugin-cron/iphone/rex-cron-largest-expression.png)、[iPad 最大字号选值](2026-11-20-plugin-cron/ipad-accessibility/rex-cron-largest-weekday.png) 和 [iPad 降低透明度/间隔编辑](2026-11-20-plugin-cron/ipad-accessibility/rex-cron-minute-step.png)。大字自然增高并通过原生滚动访问；降低透明度保持同色实面和对比度分隔。被滚出视口的下方字段没有裁掉或拼成假屏。模式选择从溢出菜单改成有实际按钮/选中语义的完整选择页，取消/返回仍保持独立草稿。

截图只做 EXIF 方向转正、去元数据和等比缩小，比较图的标签在截图之外。额外模式页由 simctl 在真实 XCTest 等待该页时直接抓取；来源原图摘要单独记录。配置页没有媒体内容，不塞装饰海报；发现/详情等页面的真实海报要求继续 P3。此叶子的视觉与操作检查通过，不代替全产品或完整 VoiceOver 验收。

## 留存与继续

既有系统 Form/键盘工具栏 `Invalid frame dimension` 运行警告仍存在，未关闭诊断或宣称修复；独立复现与 P8 门禁继续见 [P1.4a](2026-11-20-rex-entry.md)。XCTest 16→17 链接提示、无 AppIntents 提取提示以及诊断收集器找不到 simctl 的环境错误留在原始日志，测试状态按 xcresult 实际计数判断。

结果/日志归档至外置盘；结束后恢复专用 iPad 的逐键辅助设置、关闭两台专用模拟器并清理本任务内部构建/结果缓存，保留模拟器数据和共享依赖。回滚边界见 [叶子方案](../plugin-cron.md)。

P2.2b.2b 继续复杂选择/完整规则、更广真实表达式/槽/编辑器；P2.3 数据/图表/仪表板、P2.4 Web 插件专用兼容、P2.5 AppPage/SDK、第三方生态与生产插件副作用均未完成。真机、最低系统、完整 VoiceOver/性能、既有布局警告与主体全部 WebView 的最终移除继续 P8。长期 Goal 保持 active。
