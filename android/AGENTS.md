# MoviePilot-App Android 原生端开发约定

本目录承载 MoviePilot 全原生 **Kotlin + Jetpack Compose** Android 客户端，与 iOS / 鸿蒙共享 `shared/` 设计 Token、多语言、静态资产及 `shared/core-rust/` 共享内核。

- **视觉与系统原生材质红线**：
  - 所有颜色、渐变、圆角、边距、语义色必须来自 `design-system/.../GeneratedTokens.kt`，禁止在业务页面硬编码色值。
  - 动态流光背景在 API 33+ 必须使用原生 **AGSL `RuntimeShader`**（15fps，低电量/减弱动画/退后台自动暂停），API 31–32 平滑回退端点漂移渐变。
  - 玻璃卡片与悬浮底栏在 API 31+ 使用硬件 **`RenderEffect`** 背景模糊叠加轻透色紫玫高光描边；模态半屏弹窗使用 Material 3 `ModalBottomSheet` + **`Window.setBackgroundBlurRadius`**，严禁灰雾黑底或用 `Box` 伪造弹窗。
- **业务内核边界**：DeepLink 解析、SSE 帧解析、9 维站点资源筛选分组、JWT/RBAC 权限判定、插件 JSON 表单规划与无损补丁、Cron 解析与勋章金属配色统一走 `:core-rust-bridge`（UniFFI `libmoviepilot_core.so`）。
- **构建与缓存路径**：Gradle 缓存统一使用 `GRADLE_USER_HOME=/Volumes/DISK/Android/gradle-home`，SDK 位于 `/Volumes/DISK/Android/sdk`，严禁向 `/tmp` 写入大型构建缓存。
- **注释规范**：所有新增类型与公共方法保持清晰中文 KDoc 注释。
