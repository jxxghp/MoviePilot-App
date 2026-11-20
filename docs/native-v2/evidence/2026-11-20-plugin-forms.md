# P2.2a 插件表单接线验收

仅本地 `MoviePilot-App / v2`，从 `d1a81cf` 接续。新产品尚未接入主 App 默认入口；没有推送、发布、生产服务写入、真实凭据或设备替换。[实施方案](../plugin-forms.md) 先于代码建立，来源和保护边界均保留。

## 已实现与实际验证

| 边界 | 本地证据 |
| --- | --- |
| 保真 HTTP | APIClient 的 payload Data 投影经过原有 receive；NativeSession 在前后核对身份/权限/代次，沿用 401 处理；原始字节/大数/小数词法、显式 payload、流式上限/MIME/401/取消新增 4 项 API 测试 |
| 完整草稿 | 原始键/未知与隐藏值、大数/数值词法、Unicode 键冲突与字符串序列修改、值类型、原子资源预算、取消、重置/确认和遮盖描述；7 项新增，含固定官方源码派生的 AutoSignIn 配置 |
| 控制器 | 物理分身路径/完整对象、管理员权限、默认阻止非空表单、合法空表单、校验不发送、HTTP/业务/协议失败保留、显式重试、并发/取消/关闭隔离、重读放弃、Vue/损坏区分、权限撤销、401、旧代次、预取消、非法目标、校验改草稿和旧成功标记；22 项新增，含参数化场景 |
| 完整 Swift 回归 | 核心 166、会话 45、API 23、插件协议/草稿 40、插件表单 22，Swift Testing 总计 296 项通过；另 4 项 XCTest 通过，未报告跳过 |
| iOS SDK 编译 | MoviePilotPluginForms + 依赖对 `arm64-apple-ios16.0-simulator` 构建成功；本批没有运行模拟器 UI、旧系统或真机 |
| 格式/结构 | 变更 Package/源文件/测试的 `swift-format lint --strict` 与 diff 检查通过；新表单代码没有 WebKit/JS/桥调用，不新建第二个网络客户端；底层仍复用 Core 公共类型，旧版源码移除继续 P8 |

校验器在这个叶子是 UI 的明确依赖。默认策略只允许无待渲染能力的合法空 conf；测试用 FixtureSwitchValidator 精确检查一个合成开关的组件/属性/布尔值，只用于控制器/载荷验证，不能据此声称 VSwitch 已有原生 UI。P2.2b 必须以实际渲染与值/条件校验实现替换默认阻止策略，不能提交任意空报告放行。

配置读取、解析和草稿构造归属同一操作；CPU 解析放入结构化子任务，父取消传递，发布前再次核对会话。单元测试通过真正 URLSession/URLProtocol 验证请求边界及可控时序；认证和安全存储为内存夹具，不冒充生产认证或 Keychain 设备验收。

保存确认是服务器接受本次完整 PUT，插件重新初始化后的异步效果不在此确认范围。失败/取消保持未确认状态和完整草稿，无自动重放；再次显式调用才能再发送。继续编辑或再次提交清除旧成功标记，同步校验若改变修订则阻止旧快照发送。

## 重放与记录

实际命令与源文件/固定仓库 SHA、结果摘要及日志 SHA-256 见 [机器记录](2026-11-20-plugin-forms.json)。无 UI 改动，因此不重复上一叶子的视觉/模拟器门禁。测试使用后端虚拟环境仅处理只读 JSON/Git 证据，不需要 App 自身 Python 环境。

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
CLANG_MODULE_CACHE_PATH=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/clang \
zsh scripts/test-core.sh --scratch-path /Volumes/DISK/TmpBuild/moviepilot-ios-v2/swiftpm

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
CLANG_MODULE_CACHE_PATH=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/clang \
xcrun swift build --target MoviePilotPluginForms --triple arm64-apple-ios16.0-simulator \
  --sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk \
  --scratch-path /Volumes/DISK/TmpBuild/moviepilot-ios-v2/ios-swiftpm
~~~

日志保存在本机外置盘 `/Volumes/DISK/TmpBuild/moviepilot-ios-v2/plugin-forms-evidence-20261120/`，不是公开产物。复用既有 SwiftPM/SDK/module 缓存，未在主磁盘创建临时构建目录。

## 继续验收

本叶子不证明动态 UI 已渲染或插件生态已完整兼容；真实组件/属性/布局、条件/插值/脚本、槽、复杂选择/规则、真实后端插件、全部界面及可访问性继续 P2.2b 和后续叶子。UI 必须复用 单一深色渐变玻璃风格并使用 swiftui-liquid-glass；不新增主题或网页主体回退。长期 Goal 保持 active。
