# P1.3 原生入口实现设计

当前只实施连接、初始化、密码/OTP、会话恢复与账号/服务管理。它是可运行的基础入口，不冒充尚未迁移的媒体首页。主要媒体页面继续按 P0.2 提供预览后定稿。

- Info.plist 仍指向稳定的 SceneDelegate；每次场景连接时由 DEBUG 参数 `--native-v2` 选择原生驱动，其余进入保留的 LegacyWebSceneDelegate。不依赖场景恢复时可能沿用的 delegate 类选择。Release 暂不启用此参数，最终默认切换属于 P8。
- 原生驱动只创建 SwiftUI/UIHostingController；原生连接、登录与初始化均不复用 WebCoordinator、旧 LoginController 或 ConnectionController。网络只经过 NativeSessionManager 与直接 API 客户端。API 错误展示重试/换地址，不能回退网页。
- 原生表单沿用现有品牌色、动态字体、分组和账号页限宽风格；支持系统键盘、深浅外观、语言和大字。身份确认后的首个页面只展示真实当前账号和服务，可刷新身份、退出或切换。
- 复用 InstanceStore/TokenStore 的 UUID 和既有 Keychain 服务。可选密码记忆仅在显式成功登录后保存，OTP 从不保存；恢复令牌先由服务器确认。换实例、离开认证、后台清理明文草稿，迟到 UI 更新另有操作代次检查。
- 初始化重新 GET 状态后才 POST；采用完整 username/password/confirm_password/api_key JSON。固定用户名不可编辑。创建成功返回登录页，要求明确再次登录；409/超时等不自动重发创建。GitHub 设备授权、Passkey/OIDC 完整流程另属 P6/P7，当前不能宣称已迁移。
- 退出/认证失效清理对应 Widget 资料，普通切换只停止旧代次；通知服务解除旧 coordinator，不把原生身份送入旧桥。完整通知/Widget/深链入口仍属 P7。
- 忘记服务需要用户确认，再调用隔离的兼容存储清理器移除其旧 WebKit 数据和既有凭据。清理器不能创建 WebView、加载网页或承接主体页面。
- API-only 测试服务只监听回环地址，拒绝全部 HTML/JS 和未知路径，只记录方法/路径/计数，不记录密码/令牌。模拟器使用独立设备，不覆盖现有真机或模拟器的配置。UI 按钮、请求证据和画面互证；真实服务器、真机与最低系统另记。

验收材料应明确区分运行中的视图检查与整个进程的 WebView 创建审计，不能仅凭一张无 WebView 的截图声称所有运行路径均已完成迁移。
