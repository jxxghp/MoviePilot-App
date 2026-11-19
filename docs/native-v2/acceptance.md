# iOS v2 验收策略

## 证据分层

每项结果都记录代码 SHA、环境、命令/步骤、执行/通过/失败/跳过数量、产物位置与未验证事项。源码检查、单测、模拟器、真机、后端真实实例和发布产物是不同事实；某层通过不替代下一层。

| 层级 | 测什么 | 成立的证据 |
| --- | --- | --- |
| A 范围/架构 | 路由、弹窗、全局能力、插件契约、模块依赖、设计选择 | 固定 SHA 的范围清单、操作验收表与依赖检查 |
| B 单元/协议 | 地址/路径、响应、权限、会话代次、插件节点/绑定/条件/事件、状态机 | 可重复的离线测试；不是只测与实现同构的 happy path |
| C API 契约 | 实际请求方法/参数/身份/分页、业务失败、取消、超时和不自动重试 | URLProtocol 或回环 HTTP 服务捕获；敏感数据用合成值 |
| D 原生 UI | 真实按钮/表单/选择器/导航/恢复/可访问性 | XCTest 实际操作原生 App，截图与请求记录互证，不直接注入成功状态 |
| E 模拟器矩阵 | 统一 Rex 外观、动态字体、对比度/透明度辅助选项、iPhone/iPad、多窗口/旋转、系统版本 | 指定模拟器运行记录；缺少旧系统运行时则明确待验证；不制作多主题 |
| F 真机/真实实例 | 网络切换、登录/安全认证、播放器/PiP/后台、通知/Widget、性能与真实插件 | 经授权的隔离账号和设备实测；安装/启动不能冒充功能验收 |
| G 交付 | 最终 SHA、CI、IPA/签名/平台/架构/扩展、升级与回滚 | 最终提交的终态 CI 与独立包校验；只有授权后才发布 |

## 总体验收门

### G1 主体零 WebView

1. 最终主体源目标不得导入 WebKit、嵌入 WKWebView、调用旧 WebCoordinator/网页桥，或加载前端 HTML/JS 执行业务。
2. WebKit 只存在于明确的插件兼容目标。主体依赖插件展示协议，不依赖其实现细节；禁止“native wrapper + 内部隐藏 WebView”。
3. API-only 合成服务将 /、index.html、前端 JS/CSS、native-passkey.json 等前端入口全部设为不可用，所有主体功能闭环仍通过。
4. 冷启动、登录、导航与主体操作的运行时 WebView 创建数为 0；进入 Web 插件才允许创建，离开/会话失效后正确销毁或隔离。
5. 在 App 中成功调用一个 API、显示原生导航或从 AST 未搜到字符串都不足以单独证明本门。

### G2 身份、权限与多实例

覆盖管理员/普通用户、四类权限、features 缺省/禁用、会话到期/403、账号及实例切换、前后台恢复、取消/迟到响应。A→B→A 切换不能串用列表、图片、草稿、插件配置、Cookie 或等待确认的动作。

写入、下载、重置、删除、运行服务等动作，包含有副作用的旧 GET，默认均不自动重试。UI 重新确认前不重发。登录/OTP/Passkey 事务不自动重放。权限以当前服务器状态为准。

### G3 功能完整

每个功能按“入口→加载→正常操作→确认/取消→结果→刷新→失败恢复”执行。包括空数据、大数据、分页到尾、筛选无结果、上传/下载进度、部分失败、页面离开再回来。工作流可视化编辑、订阅的高级参数和全部设置项必须有实际记录。

### G4 插件兼容

先以脱敏运行态样本建黄金夹具，再对旧前端与原生的 model 输入输出、可见/禁用状态、校验、动作和最终保存 payload 做差分。

- 当前官方 V3 插件的实际 JSON 节点、绑定、表达式、slots、events 和图表均有覆盖结论；静态 73 类组件仅是起点。
- 全量配置往返保持未知键、数值/字符串/布尔/null、多选与隐藏字段；失败不丢草稿。
- 任意脚本或未知节点不得悄悄忽略后允许保存；明确诊断，受控进入插件兼容模式，并从“原生覆盖”里扣除。
- Web Config / Page / Dashboard / AppPage 多入口、分块资源、物理实例、SDK/旧 inject、主题/语言、宿主动作和销毁均通过。
- 第三方动态代码不能宣称穷尽；记录已测代表样本、未知能力处理和可复验兼容入口。

### G5 视觉、可访问性与性能

- 主要页面先确认视觉预览，分别保留现有参考与选定目标。实现需有正常数据、空态、加载、错误与无权状态。
- iPhone 紧凑宽度与 iPad 分栏/旋转均验收；固定 Rex 一套风格，Dynamic Type、VoiceOver、44pt 触控区域、Reduce Motion、降低透明度和提高对比度继续适用。
- 关键指标在同一设备/系统/数据量/网络条件下比较：冷/热首屏、列表滚动、图片峰值、长会话内存、切换后资源释放、后台流量。先记录基线再固定具体预算，不能无测量宣称“更流畅”。
- 模式切换、壁纸、玻璃导航、播放/弹窗返回不闪白、不串色；不靠全局透明或缩小字体掩盖问题。

## 本地验证命令与产物

批量完成一个相关变更后再构建。基础模块优先运行 SwiftPM，避免每次牵动播放器和全部 iOS 依赖：

~~~sh
mkdir -p /Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
zsh scripts/test-core.sh --scratch-path /Volumes/DISK/TmpBuild/moviepilot-ios-v2/swiftpm

xcrun swift-format lint --strict --recursive Sources Tests
~~~

UI 需要实际安装到模拟器时，使用工作区规定的独立内置缓存目录例外，不能放 /tmp：

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ios/MoviePilot.xcodeproj -scheme MoviePilot \
  -destination 'platform=iOS Simulator,id=明确的测试设备UUID' \
  -clonedSourcePackagesDirPath /Volumes/DISK/Xcode/SourcePackages \
  -derivedDataPath "$HOME/Library/Caches/MoviePilotSimulator/native-v2/DerivedData" \
  -resultBundlePath "$HOME/Library/Caches/MoviePilotSimulator/native-v2/Acceptance.xcresult" \
  -only-testing:MoviePilotUITests/具体已实现的测试类 CODE_SIGN_IDENTITY=-
~~~

不安装的编译/打包使用 /Volumes/DISK/TmpBuild/ 内 derivedData/resultBundle；依赖仍共用 /Volumes/DISK/Xcode/SourcePackages。测试任务目录不得覆盖其它工作；完成后清理一次性产物，保留必要的脱敏证据和用户模拟器状态。

已有 XCTest 某些实例验收通过 TEST_RUNNER_MOVIEPILOT_E2E_* 映射运行参数；执行前按该测试实际约定核对。必须查看 executed/passed/skipped，exit 0 或 skipped 不能写成通过。

## 每个叶子交付前

1. 核对当前叶子合同、修改清单与实际接口；更新该叶子的操作/插件兼容矩阵。
2. 运行覆盖风险的单元/契约检查，以及被修改范围要求的格式、结构和 UI 测试。无 UI 变更不虚构截图验收。
3. 审阅完整 diff、注释、新旧行为与未验证项；执行 git diff --check。
4. 精确暂存本叶子文件，验证暂存内容，保存聚焦本地提交；不顺带提交其它仓库或个人签名。
5. 在 ROADMAP.md 中记录本地完成、交付/外部验收等待状态和下一叶子。只在全部总验收门成立后关闭长期 Goal。

## 当前未覆盖事项

原生账号入口已完成 API-only 模拟器验证，见[入口证据](evidence/2026-11-19-entry.md)；Rex 单一风格预览及其 iPhone/iPad/表单辅助设置已完成本地检查，见[视觉证据](evidence/2026-11-20-rex.md)。它们分别属于功能底座和隔离演示，不能互相替代。

真实后端业务写入、全插件生态、iOS 16 设备、物理 iPhone、完整 VoiceOver、APNs/PiP/Widget 真机回归、最终 IPA 与发布仍未完成。演示画面不增加业务覆盖率；旧普通账号表单的图片也不是认可的视觉基线。
