# P2.1 插件 JSON 模型验收

仅 MoviePilot-App / 本地 v2 分支。新增 Foundation-only 的 MoviePilotPluginUI 产品，不依赖主 App、WebKit、JavaScriptCore、旧桥或网络客户端；默认业务入口未变化。

## 已实现

- 有界 UTF-8 JSON 读取/编码，保留大整数、小数/指数词法、负零、类型和未知字段；保留原始响应 Data。重复键、Unicode 键冲突、无效语法、资源越界与取消整体失败。
- 显式 form/page/dashboard 文档；区别空配置、非法响应、Vue 远程模式和合法不可用仪表板。节点原始值、属性、槽、content/text/html、绑定、事件与未知扩展均保留。
- FormRender 原始键/隐式读取/全部绑定别名；数据页 GET/其它方法旧 POST 投影；各表面的事件/槽差异。脚本、表达式、HTML、未知组件带路径诊断，不执行、不宣称可渲染/保存。
- AppPage sidebar_nav 声明/权限原值/候选顺序，仪表板元信息与物理实例 ID 保留。现有 AppPage 正文仍是远程 Vue，没有虚构通用 JSON 内容接口。
- 七组固定官方源码派生样例，受控合成替换与源码/产物摘要；脚本不会导入插件。输入控制与设计依据见[协议说明](../plugin-json.md)。

## 实际验证

| 检查 | 真正运行的结果 |
| --- | --- |
| 新协议 Swift Testing | 33 项、3 个套件通过，包含参数化边界；大数/Unicode/100 组独立 Foundation 编码语料、深度/大小/值/节点/路径预算、取消/并发、七组源码样例、绑定/槽/事件/模式/导航 |
| 已有 Swift 回归 | 核心 166、会话/权限 45、API 19 项 Swift Testing，另 4 项 XCTest 通过；SwiftPM 各测试可执行程序的 XCTest 0 行不等于跳过，实际 Swift Testing 汇总分别存在 |
| Python | 17 项通过，其中新增 4 项覆盖生成器无执行、固定 Git 对象、合成符号、失败不产半套样例与选择器边界 |
| Node | 既有 3 项语言引导检查通过，0 跳过 |
| 夹具重放 | 从固定 Plugins SHA 重放七组夹具/provenance，逐字节与仓库一致，产物摘要验证通过 |
| 最低 SDK 编译 | 新模块以 Swift 6、arm64-apple-ios16.0-simulator 独立 emit-module 成功；这是模块编译，不是最低系统运行或整个 App 构建 |
| 格式/结构 | 变更范围 swift-format lint --strict、Python py_compile、git diff --check 通过；模块无 UI/脚本引擎/网络依赖 |

测试未使用真实账号、插件宿主或生产服务。完整 SwiftPM 命令：

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
CLANG_MODULE_CACHE_PATH=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/clang \
zsh scripts/test-core.sh --scratch-path /Volumes/DISK/TmpBuild/moviepilot-ios-v2/swiftpm
~~~

具体命令、源文件摘要和工具/结果事实见[机器记录](2026-11-20-plugin-json.json)。原日志保留在本机 `/Volumes/DISK/TmpBuild/moviepilot-ios-v2/plugin-json-evidence-20261120/`；iOS 模块一次性输出与夹具重放目录在保留摘要后清理，已有共享 SwiftPM/SourcePackages 缓存保留。

## 未覆盖与下一步

本叶子不接 UI/后端、不做保存/表达式求值/事件执行，不将源码样例当成真实插件生态通过。未知能力不会被当成已支持；下游必须建立真实组件注册、权限/会话和完整保存门禁。

P1.4a 接续真实原生账号/实例界面的 Cinematic 统一组件，随后 P2.2 连接原始字节响应和原生动态表单。API 接线必须复用现有受限传输，不能先用 Double 解码丢精度；长期 Goal 保持 active。
