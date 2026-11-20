# 数字星期方言修正验收

从本地 v2 `14542f4` 接续。[实施方案](../cron-dialects.md)记录真实 LibraryIntegrity 的标准 crontab 包装与通用 APScheduler 数字星期差异。没有按插件名/hint 猜方言，没有新增后端协议；数字点/列表/范围/步长保持原文与原类型，只有主动选择星期才生成名称。

## 功能证据

- 新回归先在现有实现复现：1 个参数化测试、9 组输入，产生 14 处断言失败。修正通用解释器并撤销原先错误的 `0 -> 周一` 测试假设后，全部 **334 项 Swift Testing + 4 项 XCTest** 通过，表单目标 60 项；783 组命名构造语料仍通过。21 项 Python 测试、Swift 严格格式与三语资源检查通过。
- 使用固定 Plugins `be185c5e` 中 `libraryintegrity/page.py` 的完整 Cron 节点与真实 hint；外层模型明确为合成，**不是完整 LibraryIntegrity 表单**。未支持的 Combobox/其它行为仍禁存，不借单节点测试宣布全插件已迁移。
- [iPhone 最终](2026-11-20-cron-dialects/phone-2-tests.json)正常字号、最大字号横屏两项通过，0 跳过；[iPad 基线](2026-11-20-cron-dialects/ipad-baseline-tests.json)最大字号数字星期与既有完整 LibraryScraper 表单两项通过，0 跳过。
- 真实原生入口分别完成无改应用/完整保存、重新打开、指定值初始空选禁用、明确选择周日/再次完整保存；服务端确认第一份原文为带空格的 ` 0 3 * * 0  `，第二份为 `0 3 * * sun`，未来大整数保留，恰好两次明确 PUT，无额外请求或 WebView。
- [最初 iPhone 批次](2026-11-20-cron-dialects/phone-initial-tests.json)为 0 通过、2 失败、0 跳过：测试助手假设所有表单都有 enabled 开关，而来源节点没有。改为等待调用方指定的真实首控件后复测通过，未给夹具伪造开关。产品代码没有因此改动；中间失败保留。

实际截图见 [原文/说明](2026-11-20-cron-dialects/phone-2/cinematic-weekday-dialect-expression-normal.png)、[自定义数字字段](2026-11-20-cron-dialects/phone-2/cinematic-weekday-dialect-custom-normal.png)、[最大字号明确选值](2026-11-20-cron-dialects/ipad-baseline/cinematic-weekday-dialect-choice-largest.png)。原始 xcresult、日志、来源/二进制摘要见 [机器记录](2026-11-20-cron-dialects/manifest.json)。图片只做 EXIF 转正、去元数据与等比缩小。

## 视觉反馈与接续

用户在本轮明确指出共享表单卡片偏灰、不够通透。此反馈重新打开材质验收：上述功能通过**不是 Cinematic 视觉获得认可**。马上优先处理 [P1.4b 玻璃通透度](../glass-clarity.md)，复杂选择 2b 后移；不改用户只做 Cinematic 一套风格的要求。

编译/界面证据仍是 iOS 26.1 模拟器，不冒充生产插件任务、最低系统或真机。既有 Form/键盘工具栏布局警告不关闭、不冒记修复。专用构建缓存与 API-only 夹具继续供紧接着的材质验收使用，结束后清理；长期 Goal 保持 active，默认 1.x 不切换。
