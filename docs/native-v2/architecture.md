# iOS v2 架构与协议方案

## 决策

采用 Swift 6 + SwiftUI 实现新主体页面，系统集成与已有原生播放器继续使用适合的 UIKit/AVKit/VLCKit。最低 iOS 16 暂时不提高；iOS 17+ Widget 和 iOS 26+ Liquid Glass 分别按系统能力启用。最终系统矩阵以实际设备验证为准。

主体使用 MoviePilot 自有 API，后端继续拥有身份、权限、识别、搜索、订阅、下载、整理、工作流和插件执行。App 不复制这些业务规则。现有前端源码是行为、样式和请求协议的对照，不是主体运行依赖。

迁移采用“先独立底座、再原生功能片、最后默认切换”。过渡期间保留旧 1.x 入口仅作对照，避免用户在半成品里失去功能；不能因为过渡期保留代码而降低 P8 的移除要求。

## 模块边界

| 模块/归属 | 责任 | 约束与当前状态 |
| --- | --- | --- |
| MoviePilotCore（现有） | 可复用的地址、认证投影、语言、通知与 Widget 纯契约 | 混有旧网页桥模型；迁移时只提取需要的独立类型，最终拆离旧桥依赖 |
| MoviePilotAPI（P1.1，已实现底座） | URLSession、端点、显式响应契约、错误、分页元数据 | Foundation + 现有纯核心类型；不导入 WebKit，不管理 UI、Keychain 或自动登录；尚未接入默认 App |
| MoviePilotSession（P1.2，已实现底座） | 直接认证、实例、Keychain 存储协议、当前用户、权限、代次、任务取消 | Foundation/Combine；现有 TokenStore 已接线；默认 UI 未切换，不读取网页 Cookie 或 localStorage |
| 原生功能模块（P3–P7） | 强类型 DTO、仓库查询、页面状态、用户动作和导航 | 依赖 API/会话；不可通过 JS、网页桥或插件 Web 容器执行主体业务 |
| 原生设计组件（P1.4） | 海报、列表、表单、选择器、错误/空态、进度与图表 | SwiftUI/原生组件；固定 Rex 风格，支持可访问性、iPad 与旧系统，不提供多主题 |
| JSON 插件运行时（P2.1–3） | 旧 schema 适配、类型模型、绑定/条件、动作、原生渲染、能力报告 | MoviePilotPluginUI 已实现纯模型/诊断与有界保真值；UI/求值/保存/动作待后续；不依赖 WebKit，不执行任意 JS |
| 插件 Web 兼容模块（P2.4–5） | 既有 Vue/HTML/远程组件、SDK、独立数据容器与消息桥 | 唯一可引入 WebKit 的业务模块；只接受受信插件上下文 |
| 系统集成（P7） | APNs、Widget、深链、媒体播放、文件与通知授权 | 通过原生会话和用例接口工作，不继续依赖 WebCoordinator |

先在本仓 Swift Package 内形成独立目标，避免一次引入很多框架或额外代码生成服务。模块名和具体拆分可按真实体量细化；不得形成只有空协议、没有用户功能的无限框架工程。

## API 与数据

- 以配置的实例根地址拼接 api/v1，支持反向代理子路径、HTTP/HTTPS、IPv4/IPv6。路径段和查询分别编码；调用者不能用相对跳转、百分号二次编码或绝对 URL 逃出部署根目录。
- 每个 API 客户端只持有该会话的 Bearer；使用独立 ephemeral URLSession，禁用全局 Cookie、URLCredentialStorage 和 URLCache。私密模型与缓存按实例/账号隔离。
- 固定端点明确声明标准 envelope 或原始 payload。标准 success=false 是业务失败；插件自有 success/data 字段不能被误拆包。下载文件、SSE 和媒体流另有专用传输，不套 JSON 客户端。
- 401 进入会话失效流程；403 只影响无权操作，不假装登录过期。429 保留 Retry-After；不自动重发写入、密码、OTP 或带副作用的旧 GET 接口。取消与失败分别处理。
- 同源与跨源重定向默认均停止，避免把主令牌发往其它路径。需要重定向的媒体与外部协议单独设计凭据策略，不放宽通用客户端。
- 列表保留 X-Total-Count / X-Result-Count / X-Page / X-Page-Size 等当前实际分页头；字段名以实现前的后端源码核对为准，不把截断列表当完整结果。
- 原生用户设置通过现有 user/config 等接口读写，继承相同默认值和并发语义；未知插件配置键必须原样保留。不要在客户端“修正”后端业务状态。
- 每个业务片接入前核对实际 OpenAPI、前端 api 模块和响应样本，形成最小 DTO 与合成夹具。当前静态清单不代替运行态接口发现。

## 身份、权限和生命周期

保留 SavedInstance 身份、现有 Keychain 账户归属与多实例地址，不要求重输全部配置。令牌恢复必须先读取 user/current；权限不能只相信本地快照或自行解码的 JWT。

每次登录、注销、换实例、换用户形成新的会话代次。异步任务、图片/列表缓存、弹窗、确认操作和插件 SDK 均携带该代次；结束时取消请求、结算等待中的选择器，并在回写和确认后再次核对代次。不能让 A 实例迟到响应出现在 B 实例。

权限复用 discovery/search/subscribe/manage/admin 与 features 明细，以及 plugin.{plugin_id}.{nav_key} 对应的现有规则。admin 实际来自服务器 is_superuser。权限缺省继承规则以现有 permission.ts 与后端授权为准；隐藏按钮不代替后端授权。

密码/OTP 使用现有原生认证路径起步；登录成功后不再把浏览器 store 注入作为可用条件。初始化也列入原生迁移，不能永远提示“先去网页初始化”。OIDC/Passkey 的自托管域名、关联域和一次性事务需单独验证：允许系统认证会话承接协议必需的外部授权，不嵌入业务网页，不假造 RP ID，也不沿用必须探测前端 native-passkey.json 的主体依赖。

## 插件兼容：先适配旧协议

已确认的现有接口如下，相对 /api/v1：

| 界面 | 当前协议事实 | v2 方案 |
| --- | --- | --- |
| 配置表单 | GET plugin/form/{physicalID} 返回 render_mode/conf/model；后端合并默认值与已保存配置；PUT plugin/{physicalID} 保存 | JSON 直接原生生成；保留完整 model 和值类型；Vue Config 进入插件兼容模块 |
| 数据页 | GET plugin/page/{physicalID} 返回 render_mode/page；JSON 节点可带 events | JSON 原生渲染与动作；Vue Page 兼容 |
| 仪表板 | plugin/dashboard/meta 与 plugin/dashboard/{physicalID}/{key}；包含 attrs/cols/rows/elements/render_mode | 主体仪表板和 JSON 卡片原生；已有远程 Dashboard 仅卡片内部兼容 |
| 插件 AppPage | sidebar_nav + remotes + AppPage / AppPage{Pascal} 远程组件；当前没有通用 JSON AppPage 接口 | 既有 AppPage 保留兼容；以后按能力检测增补可选 JSON AppPage，不能伪称现有插件已经支持 |
| AgentPet | 现有远程插件形象及 SDK | 主体 Agent 对话原生；插件特有远程形象与交互仅在插件边界内处理，能力不可冒报 |

### JSON 原生适配层

继续理解 component / props / content / slots / text / html / events，不要求插件把 Vuetify 节点改写成新格式。内部可归一化为有界的 NativeNode 树，包含来源路径、绑定、动作与能力诊断。

- 布局：VForm/VRow/VCol/VContainer/VCard 等映射原生分组、自适应网格与区块；cols/breakpoints 控制窄屏降级，不能照搬桌面列宽导致截断。
- 输入：VSwitch/VCheckbox/VTextField/VTextarea/VSelect/VCombobox/VRangeSlider/VCronField 等保留类型、multiple、items 标题/值映射、禁用/只读、校验和默认值。
- 展示：VAlert/VChip/VList/VImg/VTable/VDataTable、slots、分页、展开面板和 tabs 保留数据与动作；图表优先原生 Charts。代码编辑、复杂 HTML、自定义组件有显式能力记录。
- model / v-model / modelvalue / model:xxx 与 v-model:xxx 保留旧表单语义；隐藏字段仍保留值。保存失败保留用户草稿；不自动重试 PUT。
- 条件与插值先实现经过 AST 校验的有限表达式；任意 JavaScript 函数、DOM、style 注入不进入原生执行。无法支持的整个插件界面给出诊断与受控兼容入口，不能只漏掉出问题的字段再允许破坏性保存。
- events.api/method/params 解析为受控动作；物理插件 ID 与源插件 ID 分开处理，沿用现有实例 API 路径映射，不让克隆实例写回源插件。系统操作走显式 SDK 能力与后端授权。
- 限制 schema 字节数、节点数、深度、单字段长度、数据表/图表数据量；支持任务取消。未知节点先诊断，不崩溃、不假成功。

静态基线扫描了 V1/V2/V3 官方源码中的 73 类字面量组件；该数字不包括继承、辅助文件和第三方动态生成组件。优先保证当前 V3 官方及实际安装生态，旧代际按宿主实际兼容性验证，不承诺让不支持 V3 的插件越过宿主限制。

### 既有 Web 插件的受控宿主

兼容目标包含 Config / Page / Dashboard / AppPage 多入口、分块资源、主题/语言、SDK v1、旧 inject、原生宿主动作与销毁结算。不能只加载 remoteEntry.js 就认定插件兼容。

先验证现有前端插件专用入口能否作为隔离微宿主；必要时从现有前端抽取最小兼容宿主并完整保留许可证。主体不加载其 index.html，也不能让其导航接管主体路由。前端资源缺失时只影响 Web 插件界面，并给出可操作错误。

Web 数据容器按实例隔离，桥再绑定用户/会话代次/插件/界面；登出与换用户清理身份数据。只公布已实现且当前有权使用的 SDK 能力。插件不能自行提交主令牌、任意宿主 URL 或确认结果来绕过用户操作。网络最终授权继续在后端，客户端限制只是额外边界。

## 尚需在对应叶子解决的决定

1. 微宿主复用远端插件页与打包最小运行时的体积、升级和兼容成本；P2.4 用真实远程插件夹具决定。
2. 复杂表达式/代码编辑器/HTML 的原生覆盖边界与剩余兼容清单；P2.1 不以猜测承诺全部 JS 原生解释。
3. 工作流画布的大量节点、连线、缩放、撤销和无障碍导航；P5.5 单独设计与性能验收。
4. 自托管 Passkey/OIDC 的系统认证方案；P1.2/P6.3 验证平台约束，不能通过降低认证安全性完成迁移。
5. API 版本漂移与运行态能力发现；功能接入时分别核实版本和可用端点，旧服务明确显示未支持，不回退主体网页。
