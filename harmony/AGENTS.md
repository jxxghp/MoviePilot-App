# MoviePilot-App 鸿蒙原生端（HarmonyOS NEXT API 12+）开发约定

本目录承载 MoviePilot 全原生 **ArkTS + ArkUI** 鸿蒙 NEXT 客户端，消费 `shared/` 单一事实源与 `shared/core-rust/crates/mp-ffi-ohos`（`ohos-rs` NAPI 内核）。

- **系统原生材质与动态光感红线**：
  - 玻璃卡片与 4+1 悬浮胶囊底栏必须使用 ArkUI 原生 `backgroundEffect` / `backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)`，并按规范克制叠加鸿蒙原生 **`pointLight` 动态点光源**（`IlluminatedType.BORDER_CONTENT`）与按压 **`lightUpEffect`**。
  - 半屏模态弹窗必须使用系统原生 **`bindSheet`**（配置多档 `detents`、`blurStyle: BlurStyle.COMPONENT_THIN`、`dragBar: true`），严禁使用 `Stack` 伪造弹窗。
  - 所有颜色、圆角、边距、光感强度参数必须消费 `commons/design_system/src/main/ets/tokens/GeneratedTokens.ets`，禁止硬编码。
- **一多适配与折叠屏**：全面启用 `setWindowLayoutFullScreen(true)` + 避让区监听，结合 `sm / md / lg` 断点与 `display.getFoldStatus()` 响应手机、阔折叠与平板布局。
- **网络与安全边界**：遵循 ADR-01/02，底层网络走 `@kit.RemoteCommunicationKit` (`rcp`)，安全凭据走 `@kit.UniversalKeystoreKit` (HUKS) + Preferences。
- **注释规范**：所有导出类、结构体与方法均编写清晰中文 JSDoc 注释。
