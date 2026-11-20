# P0.2 Cinematic 原生视觉预览验收

本批于 2026-11-19 开始，2026-11-20 收尾；仅本地 v2 分支。范围是隔离 SwiftUI 预览与共用设计组件，不把演示媒体/指标记为 P3 业务迁移完成。

## 实现

- 独立 Scheme `MoviePilotDesignPreview` / Bundle ID `com.moviepilot.app.v2preview`，显示“MoviePilot预览”，不替换主 App。
- 发现、九项海报网格、媒体详情/资源弹层、工作台、订阅、设置和插件表单均由原生视图构成；导航、搜索、开关、选择器与保存可操作。
- 固定一套 Cinematic 深色视觉：全局连续渐变、玻璃分组卡片/表单、真实海报艺术图。系统浅色启动参数仍保持固定风格。
- 遵循 `swiftui-liquid-glass`：iOS 26 原生 glassEffect/glassProminent、成组 GlassEffectContainer、效果置于布局后、interactive 用于真正动作；内容采用 Material，降低透明度时使用同色不透明降级。
- 新目标无主 App、Core、VLC、Widget、WebKit 依赖；直接链接只有系统原生框架/Swift 库，源码没有网页或网络客户端。覆盖路径可访问性树 WebView=0。这不是全进程分配计数，也不把旧主 App 的 WebKit 移除记为完成。

## 实际运行结果

Xcode 27.2（27B52）、Swift 6，iOS 26.1（23B86）模拟器；iPhone 17 Pro 402×874pt，iPad Pro 11-inch 834×1210pt。

| 结果包 | 真正执行范围 | 结果 |
| --- | --- | --- |
| `cinematic-preview-acceptance.xcresult` | 7 个不同测试在 iPhone/iPad 各执行一次：发现→详情→资源队列、网格、工作台、订阅切换、设置/保存、固定风格/最大辅助字号、横屏/滚动 | 14 次执行通过；两设备各 7，0 失败/跳过。[摘要](2026-11-20-cinematic/ui-tests.json) |
| `cinematic-preview-detail-check.xcresult` | 详情最后延伸至顶部安全区后，重跑 3 项受影响媒体路径 × 两设备 | 6 次执行通过，0 跳过。[摘要](2026-11-20-cinematic/detail-tests.json) |
| `cinematic-preview-accessibility-final.xcresult` | 最终代码在专用 iPhone 开启提高对比度、降低透明度、减弱动态，运行设置/表单与最大字号保存 | 2 项通过，0 跳过；UIKit 公共状态实际返回 reduceTransparency=true、reduceMotion=true，画面确实使用不透明降级。[摘要](2026-11-20-cinematic/accessibility-tests.json) |

三份最终摘要 runtimeWarnings 为空。早期缺少完整方向声明的警告已修正；横屏快捷 swipe 路径问题经截图定位后改用内容边缘拖动，窗口尺寸和 hittable 断言均保留。较早的资源/测试编译排错与失败运行不作为通过证据。

原始结果包/日志在本机外置盘 `/Volumes/DISK/TmpBuild/moviepilot-ios-v2/cinematic-evidence-20261120/`，不是发布产物或下载地址。一次性模拟器构建缓存、旧失败结果与中间导图在保留证据后清理；共享 SourcePackages 不清理，专用设备状态保留，辅助设置恢复。

## 视觉证据

- [预览总览](2026-11-20-cinematic/preview-board.png)、[源参考](../references/visual/README.md)、[裁切清单](../references/visual/preview-assets.json)。
- [设计 QA](../../../design-qa.md) 包含完整/局部并排、问题、修正和重采集，最终 passed 只对已检查状态成立。
- [截图索引](2026-11-20-cinematic/screenshots.json) 记录附件、尺寸、设备、测试、结果包与 SHA-256。文档仅做 sRGB 等比降采样，不重画状态栏、文字或控件。
- [代码输入摘要](2026-11-20-cinematic/source-hashes.json) 可核对后续源码是否仍属于这批验收；文档更新不改变代码摘要。

本批三个源码目录的 `swift-format lint --strict`、`git diff --check` 通过；XcodeGen 只增加独立目标及其源码/资源/配置。主 App Bundle ID、版本、签名、源文件和依赖未调整。

## 后续门槛

1. 数据/操作仅在预览进程内存，真实媒体流程与 JSON 动态表单/数据页/AppPage/仪表板、Web 插件兼容继续分阶段验收。
2. P1.4 将同套组件接入真实入口与业务。首次普通账号表单图片只保留功能历史，不代表认可的外观。
3. 只运行 iOS 26.1 模拟器；App 仍声明 iOS 16，旧系统降级经编译可用性隔离，尚未完成旧系统/真机运行。
4. 大字/对比度/透明度已查设置与表单；完整 VoiceOver、所有页面长内容、真实后端/权限/性能/升级/系统集成仍有后续门槛。
5. 艺术图源于用户低分辨率参考，仅供本地评审；正式高清图片/缓存/来源由业务管线处理。本批未推送、发布或替换真机正式 App。长期 Goal 仍为 active。
