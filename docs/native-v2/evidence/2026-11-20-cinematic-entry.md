# P1.4a 真实原生入口的 Cinematic 外观

本地 `MoviePilot-App / v2`；基于 `419255b`，没有推送、发布或替换正式设备。这里的画面来自真实 NativeV2 入口与回环 API-only 服务，区别于 P0.2 的媒体演示预览；仍不代表完整业务客户端已迁移。

## 实现

- 主 App 与隔离预览共用 `NativeDesignSystem`。真实连接、保存服务、初始化、账号/密码/OTP、恢复/错误、已登录账号及服务动作采用连续烟紫/玫瑰/深蓝渐变、半透明面板、细分隔和系统原生导航/主按钮。
- 新增可复用的表单行/分组/分隔，维持 Form 的原生键盘、滚动、左滑删除和二次确认。图标列随 Dynamic Type 增宽，密码/API Key 显隐与复制按钮的实际标签覆盖 44pt；内容卡片与悬浮主动作不重复叠重玻璃。
- v2 的 SwiftUI 根与 UIKit 窗口固定深色，不读取旧版主题/主色/壁纸；旧版偏好未删除。后台遮盖使用统一不透明底色；UIKit 场景通知补充 SwiftUI scenePhase，暂离后可靠重置秘密显示选项。
- 身份/表单切换重置滚动位置；UI 检查同时验证实际视口与命中点，不能把导航栏后面的 SwiftUI 后代误报 hittable 当作按钮已点击。
- 并排检查后增强原生空字段 prompt 与禁用主按钮的可读性；不改变字段名称、自动填充、焦点、认证、会话、Keychain、权限或 API 语义。主 App 的无参数/Release 默认仍为 1.x。

## 测试与输入版本

Xcode 27.2（27B52）、iOS 26.1（23B86）模拟器。专用 iPhone 17 Pro：402×874pt；专用 iPad Pro 11-inch：834×1210pt。App 最低部署版本仍为 iOS 16，本批只证明 SDK 可用性编译，不冒称在旧系统或真机运行。

- 入口完整七项测试在 iPhone/iPad 各通过一次，共 14 次，0 失败/跳过：实例/Keychain 隔离与恢复、OTP、不保持登录、后台内存会话、初始化后单独登录、错误重试/取消/大字横屏、三语/旧入口路由，以及新增秘密显隐/暂离/触控区检查。
- 完整批次输入见 [full-suite-source-hashes.json](2026-11-20-cinematic-entry/full-suite-source-hashes.json)。其后只有 prompt 与禁用按钮前景色调整，最终输入另见 [source-hashes.json](2026-11-20-cinematic-entry/source-hashes.json)；对应定向视觉/交互复核单独保存，不把较早输入写成最后代码全量通过。
- 全部 Swift 包回归通过：263 项 Swift Testing（核心 166、会话 45、API 19、插件协议 33）与 4 项 XCTest。变更文件的 `swift-format lint --strict`、XcodeGen 源文件接线与 `git diff --check` 通过。
- 最后对比度修正后，iPad 的秘密控件、实例隔离/恢复、大字错误/取消/横屏三项通过；iPhone 常规状态的实例/账号/登录路径一项通过，辅助设置下秘密控件和大字错误/横屏两项通过，均 0 失败/跳过。共六次定向入口复核，分别见 [iPad](2026-11-20-cinematic-entry/contrast-ipad-tests.json)、[iPhone 常规](2026-11-20-cinematic-entry/contrast-iphone-tests.json)、[辅助设置](2026-11-20-cinematic-entry/accessibility-tests.json)。
- 最终共享材质/主按钮组件另外运行原生预览的发现/详情/队列、设置/表单保存和最大字号保存三项，全部通过、0 跳过，见 [预览回归](2026-11-20-cinematic-entry/preview-tests.json)。入口与预览两份辅助运行的 UIKit 公共状态实际返回 reduceTransparency=true、reduceMotion=true；提高对比度偏好已开启，截图可见增强分隔/边缘。结束后逐键核对恢复原辅助设置。

| 输入批次 | 真正运行的检查 | 结论与边界 |
| --- | --- | --- |
| 完整入口输入 | iPhone 7 + iPad 7 | 两份完整摘要均 Passed，0 失败/跳过；[iPhone](2026-11-20-cinematic-entry/iphone-tests.json) / [iPad](2026-11-20-cinematic-entry/ipad-tests.json) |
| 最终对比度输入 | 入口 6 次定向 + 预览 3 项 | 均 Passed，0 失败/跳过；源文件与已安装/新编译二进制摘要分开保存，没有把并行构建当作设备已更新 |
| 既有 Swift 包 | 263 项 Swift Testing + 4 项 XCTest | 全部通过；UIKit 视图修改不借此宣称已通过 UI |

较早排错运行中的 44pt 标签边界、43.99999999999994 浮点比较、秘密暂离遮盖及滚动误命中均已修正；这些失败/较早截图不算最终通过。主机日志还带有测试结束后的 simctl 查询失败和调试器版本查询提示，结果包/实际设备运行及零跳过计数独立核对，不将其写成产品编译错误，也不声称所有日志完全无警告。

## 最终视觉检查

- [连接/登录/账号总览](2026-11-20-cinematic-entry/entry-board.png)、[Cinematic 与原生登录完整并排](2026-11-20-cinematic-entry/comparisons/login.png)、[分组细节](2026-11-20-cinematic-entry/comparisons/focus-form.png)、[初始化与降低透明度](2026-11-20-cinematic-entry/comparisons/initialization.png)。实际在同一图中检查来源与实现，来源业务是播放表单，提取其样式而非复制功能。
- [iPad 登录](2026-11-20-cinematic-entry/ipad/native-v2-02-login.png) 与 [大字横屏](2026-11-20-cinematic-entry/ipad/native-v2-07-landscape-large-text.png) 保留真实旋转布局与限宽；[iPhone 辅助错误状态](2026-11-20-cinematic-entry/accessibility/native-v2-06-large-text-error.png) 仍能操作重试/换地址。
- 文字采用原生动态字体；44pt 秘密控件、随字号增宽的图标列、连续圆角/分隔和原生开关保持一致。全背景颜色贯通安全区；正文 Material 与系统 Liquid Glass 各按其层级使用。空字段和禁用按钮的可读性经过并排后修正。
- 本批账号入口不加入演示海报；媒体页仍由 P0.2 预览与 P3 真实数据页面推进。没有伪造状态栏、替换整个截图 UI 或新增主题。
- 图片按原附件的 EXIF 方向转正、去元数据、等比缩小，未拉伸/重画。原分辨率、附件名、设备、测试、SHA-256 与文档尺寸见三份截图索引；完整批次的旧对比度画面只保留必要修正历史。

## 记录与重放

检查汇总、原日志 SHA-256、执行参数及未验证项目见 [manifest.json](2026-11-20-cinematic-entry/manifest.json)。[iPhone 截图](2026-11-20-cinematic-entry/iphone-screenshots.json)、[iPad 截图](2026-11-20-cinematic-entry/ipad-screenshots.json)、[辅助状态截图](2026-11-20-cinematic-entry/accessibility-screenshots.json) 只包含明确命名的合成测试画面。[请求快照](2026-11-20-cinematic-entry/requests.json) 标明最后一次测试范围；每批正常/失败请求语义由各自测试内部断言。

原始通过结果包和日志保留到本机外置盘 `/Volumes/DISK/TmpBuild/moviepilot-ios-v2/cinematic-entry-evidence-20261120/`。任务专用的内置模拟器构建/导图与独立诊断 App 在取证后清理；共享依赖不清理，模拟器设备与数据保留。

重放时先在另一终端用项目约定的后端虚拟环境启动 `scripts/native-v2-fixture.py --port 5330`，仅使用专用模拟器与不存在的新结果包路径。例如：

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
TEST_RUNNER_MOVIEPILOT_NATIVE_V2_E2E=1 \
xcodebuild -project ios/MoviePilot.xcodeproj -scheme MoviePilot -configuration Debug \
  -destination 'platform=iOS Simulator,id=77E90161-AC2B-4930-8B76-436FF2E85FD8' \
  -derivedDataPath /Users/jxxghp/Library/Caches/MoviePilotSimulator/native-v2-cinematic-entry-replay/DerivedData \
  -resultBundlePath /Users/jxxghp/Library/Caches/MoviePilotSimulator/native-v2-cinematic-entry-replay/entry.xcresult \
  -clonedSourcePackagesDirPath /Volumes/DISK/Xcode/SourcePackages \
  -parallel-testing-enabled NO -only-testing:MoviePilotUITests/NativeV2EntryTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
~~~

UIKit 公共状态须与测试运行时的辅助设置互证；仅传启动参数或看到 xcodebuild exit 0 不能替代实际执行/零跳过检查。公开发布、真实服务写入和真机安装不在本叶子授权内。

## 布局警告复核

完整入口测试仍记录 `Invalid frame dimension (negative or non-finite)`，不能写成 runtimeWarnings 为空或布局警告已修复。原始测试导出的调用栈仅含零地址，没有足够信息归因到产品代码。

在专用 iPad 安装独立、无 MoviePilot 依赖的最小 SwiftUI App，仅含系统 Form、TextField、NavigationStack 和键盘 ToolbarItemGroup，定时切换焦点，同样记录该警告。去掉键盘工具栏的对照程序完成三次焦点切换且该次日志未出现警告。代码与日志见 [diagnostics](2026-11-20-cinematic-entry/diagnostics/FrameProbe.swift) / [对照](2026-11-20-cinematic-entry/diagnostics/FrameControl.swift)、[复现日志](2026-11-20-cinematic-entry/diagnostics/frame-probe.log)、[对照日志](2026-11-20-cinematic-entry/diagnostics/frame-control.log)。这支持继续隔离系统键盘工具栏相关行为，不等于 Apple 已确认根因或全部布局问题均来自系统。

独立程序已卸载，产品继续保留原生键盘完成动作，不通过关闭诊断、隐藏警告或删除用户功能来冒报通过。该兼容事项继续保留在 P8 门禁。

## 验收范围

覆盖路径检查可访问性树 WebView=0，API-only 夹具拒绝 HTML/JS/未知路径，并逐次断言请求次数、无隐式密码重发和身份归属。这不等于全进程 WebView 分配审计或 P8 移除完成。仅旧网页存储清理由既有隔离清理器承担，没有把网页当作失败回退。

未覆盖真实后端/账号、真机、最低系统运行、完整 VoiceOver/对比度全矩阵、性能、媒体业务、JSON 动态表单实际渲染/保存和 Web 插件兼容。上述项目继续在路线图中逐项推进，长期 Goal 保持 active。
