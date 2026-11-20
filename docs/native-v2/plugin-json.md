# 原生插件 JSON 协议（P2.1）

## 本叶子边界

本地实现与模型验收已完成，见[结果记录](evidence/2026-11-20-plugin-json.md)。此完成仅表示下面的协议边界，不是动态 UI 或整个插件生态已原生化。

建立 Foundation-only 的 MoviePilotPluginUI 模块：有界、保真 JSON 值，已有表单/数据页/仪表板的文档模型、原始节点/属性/槽/绑定/事件和带路径诊断，以及现有 AppPage 导航声明。只解析数据，不执行 JS、网络、HTML 或任何动作；本叶子不宣称原生 UI、保存、事件或 Web 插件已完成。

该产品尚未接入主 App 默认运行链；回滚本叶子可移除新增 Swift Package 产品/目标、模块、测试与夹具生成器，不需回滚认证或既有 App 功能。

继续使用固定 Cinematic 唯一外观，后续 P2.2/P2.3 的原生组件复用 P1.4；本模块不定义另一套主题。

## 当前源码复核（2026-11-20）

| 仓库 | 最新已 fetch 的只读引用 | 与既有基线关系 |
| --- | --- | --- |
| App | v2；origin/main 682e9532c384af457a275ef5dfe66cbe0672a5cb | 保留本地原生迁移提交 |
| Frontend | origin/v3 db17d9cb349e1024e3f9190c0e888704cb62c8ab | 未变化；不切换实际工作分支 |
| Plugins | origin/main 5d473864ee9d3d036b28a124262f38f773a2a452 | 未变化；不读取或覆盖工作区未提交插件 |
| Backend | origin/v3 63d09b1c7299973a7b458ba897aa109085ca6948 | 已前进；相关 SDK 变化为通知说明，插件 UI 端点合同未变；用最新 Git 对象复核，不改运行时工作树 |

来源：Frontend 的 FormRender.vue、PageRender.vue、DashboardRender.vue、PluginConfigDialog.vue、PluginDataDialog.vue、federationLoader.ts、pages/plugin/app.vue；Backend 的 api/endpoints/plugin.py、schemas/plugin.py、sdk/plugin/base.py、runtime/extensions/plugin/projection.py。样例从固定 Plugins Git 对象只读提取，禁止导入/运行插件代码。

## 必须保留的已有语义

1. form/page 响应是原始对象，不猜测 success/data envelope。表单为 render_mode/conf/model，数据页为 render_mode/page；仪表板为 render_mode/attrs/cols/rows/elements 等；未知响应字段保留。
2. FormRender 的 model、v-model、modelvalue、model:xxx、v-model:xxx 都引用 **model 中的原始键**，并非点路径。普通属性的字符串若恰好是 model 键，则形成隐式读取。大写 modelValue 不能被误认作小写 modelvalue。
3. 表单 show/v-show、顶层 {{表达式}} 与 on* 处理器是不同要求。on* 字符串原先由 JS 动态构造函数；此处只保留/诊断，不执行。不得把 v-if 或冒号属性擅自解释为既有解析器没有的指令。
4. FormRender 支持对象/数组槽；DashboardRender 支持数组槽；PageRender 当前忽略槽。PageRender 的 events 是 API 声明，FormRender 和 DashboardRender 不会因此执行同一事件。不得抹平表面差异。
5. 原 PageRender 仅 GET 使用 GET，所有其它非空 method 走 POST。模型保留声明，记录这条旧规则；执行器在 P2.3 明确授权/范围和实例路由后实现，绝不凭声明发送任意方法或外部 URL。
6. AppPage 目前是 sidebar_nav + remotes 的 Vue 远程组件，不存在通用 JSON AppPage 内容接口。保存导航声明与 AppPage{Pascal} → AppPage → Page 的候选顺序；不能虚构已能原生解析现有 AppPage 内容。
7. 物理插件/源插件、权限和会话由外层请求上下文约束。不能从页面任意字段或事件文本推导认证身份；本模块不负责发请求或改写源插件路径。

## JSON 保真与限制

现有 Core 的桥 JSONValue 使用 Double，且位于旧桥契约；不把它作为插件配置保存格式。新值模型保留数字原始词法（包括超过 Double 精确整数范围的数）、布尔/字符串/空值差异、完整未知对象字段，并保留原始响应 Data。JSON 依据 [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html)，使用 UTF-8，拒绝重复键与不合法字符串/数字，错误仅包含代码/字节偏移，不复制正文。

读取前检查字节上限，读取中约束容器深度、总值数、字符串/键和数值词法长度；取消检查贯穿遍历。节点归一化另有数量限制。JSON 解析错误抛出受控错误；结构/未知能力问题保留文档和诊断，不能变成无配置的成功界面。

默认预算为输入/输出 4 MiB、JSON 深度 48、值数 100000、单字符串词法 256 KiB、数值词法 256 字节、UI 节点 10000。结构路径键最长 1024 字节、单路径 4096 字节、路径累计 4 MiB，避免长槽名在后代中放大内存。发现列表最多 10000 项。所有越界整体失败，不提供截断后的可保存结果。

字符串上限按转义后的词法字节计。Swift 字典会把规范等价的不同 Unicode 键视为相等，因此拒绝同一对象中的这类键冲突，不能悄悄覆盖；绑定使用 exactKey/forExactModelField 精确读取。节点树是结构索引，不是已求值的可见性或内容优先级计划，原始 text/html/content/slots 均保留。

P2.2a 已新增 PluginFormDraft：写入前检测规范等价但字节不同的字段名冲突，不能直接用 Dictionary 下标覆盖另一字段；整份候选模型先编码/检查资源预算再原子替换。脏状态按编码字节而非 Swift String 的规范等价比较，完整保留未知值。接线与保存门禁见[原生表单方案](plugin-forms.md)。

## 能力与保存边界

“能分类”不等于“已经有原生组件”。节点分类和所需能力只描述文档，未知组件、HTML、脚本、表达式、槽或不合法绑定都可定位。P2.2/P2.3 的实际渲染注册与语义验证通过前，不提供通用 canSave/canRender 成功开关，不允许删掉未知字段后保存。

空的合法 conf/page/elements 与缺字段、错误类型、无效 render_mode 要分开；vue 模式只表示交由受控兼容模块，不能被当作已原生化。

已有可空 content/events 按无内容/事件处理并保留 null；仪表板 elements=null 保留并给出信息诊断，与根响应 null（面板不可用）区分。HTML 能力同时覆盖节点 html 与 props.innerHTML，不能只检查一种写法。

P2.2a 已从现有受限 APIClient/NativeSession 取得**原始响应字节**，不经旧 Double JSONValue 中转。新产品 MoviePilotPluginForms 负责真实会话/物理目标与显式保存；不另建认证/Session 或绕过同源、响应上限与取消策略。真实组件/表达式和校验器仍由 P2.2b 接续。

## 验收合同

- 实际源码派生样例与自建异常夹具均离线运行，记录来源/变换；不伪称真实插件运行态。
- JSON 数字/类型/未知键往返，重复键、尾随内容、Unicode/转义、深度/大小/节点限制与取消。
- 三种原生 JSON 响应与 Vue/非法模式；节点/槽递归、所有绑定别名、原始键/隐式读取、脚本/条件/API 事件的表面差异，错误带精确 JSON Pointer。
- AppPage 导航身份/权限保留、候选顺序与未知字段，不把远程模式计为原生渲染。
- 全部现有 Swift 单测、变更范围格式与 iOS 最低目标编译；不因纯协议改动重复模拟器视觉门禁。

## 重放样例

~~~sh
/Users/jxxghp/MPProjects/MoviePilot/.venv/bin/python scripts/native-v2-plugin-fixtures.py \
  --plugins-repo /Users/jxxghp/MPProjects/MoviePilot-Plugins \
  --ref 5d473864ee9d3d036b28a124262f38f773a2a452 \
  --output Tests/MoviePilotPluginUITests/Fixtures
~~~

夹具覆盖 AutoSignIn 完整表单、AutoSports 编辑器、CertManager 脚本、AutoSubtitle 条件、AnimeUpscale 数据表、ChatGPT API 事件、SeedStats 图表。provenance.json 保存 Git SHA、源码/产物摘要、行号和明确合成替换。脚本只读 Git/AST；测试额外证明顶层副作用和工作树污染不会被运行/读取。它们不是实际插件运行态或真实账号验收。
