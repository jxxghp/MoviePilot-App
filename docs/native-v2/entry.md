# P1.3 原生入口实现设计

当前只实施连接、初始化、密码/OTP、会话恢复与账号/服务管理。它是可运行的基础入口，不冒充尚未迁移的媒体首页。主要媒体页面继续按 P0.2 提供预览后定稿。

- Info.plist 仍指向稳定的 SceneDelegate；每次场景连接时由 DEBUG 参数 `--native-v2` 选择原生驱动，其余进入保留的 LegacyWebSceneDelegate。不依赖场景恢复时可能沿用的 delegate 类选择。Release 暂不启用此参数，最终默认切换属于 P8。
- 原生驱动只创建 SwiftUI/UIHostingController；原生连接、登录与初始化均不复用 WebCoordinator、旧 LoginController 或 ConnectionController。网络只经过 NativeSessionManager 与直接 API 客户端。API 错误展示重试/换地址，不能回退网页。
- P1.4a 将原生表单统一为用户指定的 单一深色渐变玻璃风格：共享连续渐变、半透明分组、白色胶囊主动作和系统导航；固定深色，不读取旧版主题偏好。保留原生 Form 的键盘避让、左滑删除、语言和大字，并限制 iPad 表单宽度。身份确认后的首个页面只展示真实当前账号和服务，可刷新身份、退出或切换。
- 复用 InstanceStore/TokenStore 的 UUID 和既有 Keychain 服务。可选密码记忆仅在显式成功登录后保存，OTP 从不保存；恢复令牌先由服务器确认。换实例、离开认证、后台清理明文草稿，迟到 UI 更新另有操作代次检查。
- 初始化重新 GET 状态后才 POST；采用完整 username/password/confirm_password/api_key JSON。固定用户名不可编辑。创建成功返回登录页，要求明确再次登录；409/超时等不自动重发创建。GitHub 设备授权、Passkey/OIDC 完整流程另属 P6/P7，当前不能宣称已迁移。
- 退出/认证失效清理对应 Widget 资料，普通切换只停止旧代次；通知服务解除旧 coordinator，不把原生身份送入旧桥。完整通知/Widget/深链入口仍属 P7。
- 忘记服务需要用户确认，再调用隔离的兼容存储清理器移除其旧 WebKit 数据和既有凭据。清理器不能创建 WebView、加载网页或承接主体页面。
- API-only 测试服务只监听回环地址，拒绝全部 HTML/JS 和未知路径，只记录方法/路径/计数，不记录密码/令牌。模拟器使用独立设备，不覆盖现有真机或模拟器的配置。UI 按钮、请求证据和画面互证；真实服务器、真机与最低系统另记。

验收材料应明确区分运行中的视图检查与整个进程的 WebView 创建审计，不能仅凭一张无 WebView 的截图声称所有运行路径均已完成迁移。

本地功能与画面证据见 [2026-11-19 原生入口验收](evidence/2026-11-19-entry.md)。在 Xcode 的 MoviePilot / Debug Scheme → Run Arguments 添加 `--native-v2` 可进入当前原生基础入口；无参数默认继续进入既有客户端。测试后端是本机 API-only 合成夹具，不是生产服务。

## P1.4a 实施与验收边界

- 共用组件从 `ios/NativeDesignSystem` 编入真实 App 与隔离预览；表单行、细分隔、材质分组不依赖业务模型，供 P2.2 复用。正文卡片采用系统材质，导航/主动作使用原生 Liquid Glass；不在每个输入上重复叠玻璃。
- 仅改视图、原生窗口外观、工程源文件及相应 UI 检查；认证/实例状态机、Keychain、请求与权限不变。后台隐私遮盖仍不透明，颜色来自统一设计体系。
- 复跑 API-only 实例切换/恢复、OTP、初始化、错误/取消/大字横屏及三语/旧入口路由；补普通/降低透明度/提高对比度画面与 iPad 检查。删除服务仍有系统左滑和二次确认。
- 实际渲染截图与 Cinematic 表单参考并排检查背景、材质、排版、触控与状态。旧布局警告需复查；编译或截图不能冒充完整功能/真机通过。默认 1.x 入口不切换。

本地实施与最终画面见 [P1.4a 验收](evidence/2026-11-20-cinematic-entry.md)。共享组件已接入真实入口；键盘工具栏相关警告在独立系统表单中可复现，但未记为解决，继续保留 P8 门禁。

## P2.2b.1 插件配置入口

管理员登录 v2 后，可从“账号与服务 → 插件 → 已安装插件”进入真实原生 JSON 配置页面。列表 GET `plugin/?state=installed`，配置 GET `plugin/form/{physicalID}`，保存 PUT `plugin/{physicalID}`；均使用同一实例/账号/代次的 NativeSession。普通账号不显示入口，过期和换代次退出旧导航。支持度、失败/完整草稿与 Web 插件待迁移边界见 [原生插件 UI](plugin-rendering.md)。这不等于插件市场、安装/管理、数据页或全部配置组件已经迁移。
