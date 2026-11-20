# P2.2b.2b.1 原生组合框

## 当前叶子合同（2026-11-20）

在 App 本地 `v2` / `ee67be3` 上，补齐真实 `VCombobox` 的单选、多选、预设项和自定义输入，直接参与现有完整草稿/实际渲染计划/显式 PUT 保存。仍不切换 1.x 默认入口，不推送或更改生产插件。完整规则、更广表达式、槽、HTML/脚本和 Web 插件兼容仍在原路线内，不能因本叶子完成而宣称整个 P2 或全原生迁移完成。

已刷新四仓目标引用：App `682e9532c384af457a275ef5dfe66cbe0672a5cb`、Frontend `57ed574ab1e8ebce90701ef50d7a9db5f85742a3`、后端 `586c64ede104f9794dc4f32433be87411f92c5b8`、插件 `f49286841b00ca6617a430d369b6b5e8f49c875e`。App main 未变，v2 保留此前提交；其它仓库仅读取固定 Git 对象，保留插件仓已有脏文件。后端新变化涉及通知附件和插件目录组成，未改变配置 GET/PUT；插件新增修改为微信 IP 插件，与本叶子的来源节点无重叠。

## 生产者、消费者与值语义

- 当前前端锁定 Vuetify **3.7.3**；依据该标签 `VCombobox.tsx`、`list-items.ts` 和本机相同版本源码，而非最新版文档的猜测。
- `certmanager/__init__.py` 的 DNS 服务商节点使用实际 `_DNS_PROVIDERS` 对象数组和 `item-title` / `item-value`；没有显式关闭默认 `returnObject=true`。插件 `_normalize_provider` 同时兼容对象/字符串。静态夹具必须直接提取类常量，不以合成预设替代；其它 JS 按钮仍阻断整表保存。
- `libraryintegrity/page.py` 的 `libraries` 节点是 `multiple=true`、`chips=true`、`clearable=true`，没有 items（默认空数组），用户输入媒体库名称。来源节点与合成测试模型分开标识，不冒称整个动态 get_form 已静态提取或完成迁移。
- 模型保持 JSON 类型。预设对象默认输出 raw 对象；显式 `return-object=false` 输出投影 value；自定义输入保持原字符串（包括空白和 Unicode 字节），不自动转换为同名对象或数字。缺失/null、旧标量、多值、未知对象和精确数字不因打开/取消/无修改确认而被改写。
- 预设匹配基于投影 value 的精确结构/数值比较，字符串不采用 Unicode 规范等价。标题/值支持标准 JSON 键、点/方括号路径和路径数组；保留直接完整键优先级。标准项 props 的 title/value/disabled 需实际实现；未知行为、嵌套交互和函数比较器保持诊断，不能忽略后开放保存。选项和当前多值均受 1,000 项上限约束；达到上限时拒绝新项且保留选择草稿。

## 状态与原生界面

计划器构造与 UI 共用的纯 Swift 组合框草稿。独立编辑 Sheet 使用同一连续 Rex 渐变和低遮罩淡紫玻璃分组，系统输入、列表选项、勾选、删除和取消/应用按钮；不添加主题选择或 Web UI。预设较多时可按标题过滤，也允许直接添加输入值。单/多选当前项始终可见；删除/清空是明确动作。原始值没有编辑时不触发表单赋值；有未提交输入时，应用将其加入本地选择后再更新父草稿，不能静默丢失输入。父草稿预算失败时保留编辑器及修改并显示错误。达到项目上限时拒绝新选择、保留搜索文字并提示用户，满额选择仍可移除/替换旧项。

打开和编辑只改变本地状态，不调用保存 API。应用只回填所属字段，父页面原有保存按钮才发送完整模型。取消和交互式关闭均不回填；实例/会话归属继续由 NativePluginForm 管理。隐含在隐藏节点中的未知规则/事件仍阻断整个表单保存。

## 验收和退出条件

1. 纯模型验证真实来源节点、默认对象/显式标量输出、自定义字符串、多选增删/替换、同名对象与字符串区分、旧值/未知值/精确数字、缺失/null、直接完整键/嵌套路径、disabled/readonly、必填和未知能力门禁；UI 与保存验证仍是同一计划。
2. API-only 合成服务上走真实原生连接/登录/插件入口：预设对象、自定义单值和多值、取消、清空、失败保留/显式重试、重读完整未知模型；不得获取前端页面或执行插件副作用。
3. iPhone/iPad、最大字号等适用状态实际截图，和已修正 Rex 材质/原图检查，确认输入/滚动/键盘/操作可达。只按实际 xcresult passed/failed/skipped 计数，截图与模型测试不互相替代。
4. 聚焦测试后统一编译和必要回归；继续保留既有 Form/键盘警告、真机、最低系统、VoiceOver/性能及全生态未验收项。保存一个聚焦本地提交、更新路线和证据，再进入相邻控件/规则。

## 本地验收结果

- 完整 Swift 回归：350 项 Swift Testing、4 项 XCTest；本叶子 16 项新参数/边界测试。23 项 Python、3 项 Node，swift-format、三语 strings、diff 检查通过；iOS App/UI 测试目标 build-for-testing 使用 iOS 26.1 模拟器、SDK 27.2，最低目标仍 16.0。
- 独立从锁定 Vuetify 3.7.3 模块生成 365 例选择/投影语料，与本机真实 `transformIn/transformOut/select` 比较，预设对象/自定义值/单多选/空值/未知值/路径样例均匹配。新增满额替换与数组投影安全回归后，ComboBox 测试 16/16 通过。
- 最终构建在 iPhone API-only 服务实测 3/3：对象预设取消不写入/应用后显式完整 PUT 与重读、自定义空白字符串、多选加入/删除/取消/失败保留/明确重试/清空、标量数字与字符串、null/缺失、完整未来大整数及零 WebView；所有用例 0 失败/跳过。另在 iPad 最大字号横屏和运行时已核实的“降低透明度/减弱动态”两项为 true 时 1/1 通过。UI 摘要保留原 Form `Invalid frame dimension` 系统警告，不据此宣称 P8 已处理。
- Rex 实机渲染截图：[iPhone 对象预设](evidence/2026-11-20-plugin-combobox/iphone-object-preset.png)、[iPhone 自定义输入](evidence/2026-11-20-plugin-combobox/iphone-custom-input.png)、[iPhone 多值](evidence/2026-11-20-plugin-combobox/iphone-multiple-values.png)、[iPad 大字横屏](evidence/2026-11-20-plugin-combobox/ipad-largest-landscape.png)。这些输入页继续透出连续烟紫/玫瑰渐变，使用既有淡紫高光玻璃卡片；使用系统键盘和控件，不增加新主题。真实 CertManager 全表仍由其脚本按钮规则阻断保存，单节点检验不冒充完整插件完成。
- 中间尝试均予保留：iPhone 初始临时签名关闭造成 Keychain/原实例清理失败；签名修正后的首轮夹具又因新清单缺少必要 `installed` 布尔字段，被真实客户端拒绝；第一次 iPad 最终构建复跑时 API-only 夹具刚好已经停止，登录网络请求因此失败。恢复模拟器临时签名、补齐列表字段和重新启动夹具后，最终 iPhone/iPad 都通过；未改生产存储或安全回退逻辑。Xcode 附加诊断采集仍提示找不到 `simctl`，但 xcresult 明确记录 UI 用例终态及计数。
- API-only 不是生产服务/真实插件副作用验收；运行环境为 iOS 26.1 模拟器，不代表最低 iOS 16 真机；未做完整 VoiceOver、性能或真实设备检查。正式来源文件、逐项 xcresult、外部构建缓存与命令日志位于 `/Volumes/DISK/TmpBuild/moviepilot-ios-v2/combobox-evidence-20261120/`；P8 门槛继续有效。

本叶子保存为 App 本地 `v2` 提交，不推送、开 PR、发布或覆盖正式 App。下一步接续动态 rules/剩余表达式/槽及其它复杂控件，不将其从长期目标里删去。

回滚只移除组合框计划/纯状态/原生 Sheet 与其接线，恢复原未知能力禁存；不改既有 Cron、普通选择、会话、共享 Rex 表面或后端协议。

官方源码参考：
- https://github.com/vuetifyjs/vuetify/blob/v3.7.3/packages/vuetify/src/components/VCombobox/VCombobox.tsx
- https://github.com/vuetifyjs/vuetify/blob/v3.7.3/packages/vuetify/src/composables/list-items.ts
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
