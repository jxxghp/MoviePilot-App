# MoviePilot-App 鸿蒙原生端（HarmonyOS NEXT API 12~26）开发约定

本目录承载 MoviePilot 全原生 **ArkTS + ArkUI** 鸿蒙 NEXT 客户端，消费 `shared/` 单一事实源与 `shared/core-rust/crates/mp-ffi-ohos`（`ohos-rs` NAPI 内核）。

- **系统原生材质与交互规范**：
  - 统一采用 HarmonyOS 动态光感材质体系（支持 API 26 `ImmersiveMaterial` 动态光感与多代际平滑回退、5 套鸿蒙色板与 AMOLED 纯黑模式）、圆角悬浮 5 Tab 底栏 / 宽屏侧栏，以及无遮挡渐进模糊沉浸顶栏（`NativeTopStatusBarBlur`）。
  - 半屏模态弹窗统一使用系统原生 `bindSheet`，确认框统一使用系统原生 `showAlertDialog`，严禁使用 `Stack` 伪造模态确认框。
  - 涉及数据源、下载器、媒体服务器、通知渠道、存储目录与站点的卡片及选择项统一通过 `HarmonyEntityLogo` / `HarmonyEntityLogoPill` 展示品牌标识。
- **一多适配与安全区避让**：全面启用 `setWindowLayoutFullScreen(true)` 与 `KeyboardAvoidMode.RESIZE`，保留一级 `Tabs` 滚动状态与完整系统侧滑返回链（`onBackPress`），结合响应式断点适配手机、折叠屏与平板。
- **网络与安全边界**：会话与凭据通过 `@kit.UniversalKeystoreKit`（HUKS AES-256-GCM）安全持久化；所有带鉴权请求与图片加载必须经过 `RustCoreBridge.serverAddressContains` 同源边界校验，严禁向外部域名泄露 JWT 或 Cookie；登出时彻底释放图片缓存与 `ArkWeb` 存储。
- **注释规范**：所有导出类、结构体与方法均编写清晰中文 JSDoc 注释，严格遵守 ArkTS 静态类型约束。
