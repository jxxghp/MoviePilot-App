MoviePilot 现已全面提供 **iOS / iPadOS**、**Android** 与 **HarmonyOS NEXT** 三端全原生客户端（统一版本 **`2.0.9`**），基于 Rust 共享业务内核直连 MoviePilot V3 后端，带来一致的核心功能闭环与地道原生界面体验。

### 本版本核心亮点

- **三端全面支持通行密钥（Passkey）无密码登录**：
  - iOS / iPadOS、Android 与 HarmonyOS NEXT 统一接入 `moviepilot.passkey` v1 安全认证协议，自动探测服务端 `/api/v1/auth/providers` 启用状态并校验前端静态协议与安全来源。
  - 支持免输账号密码一键唤起系统通行密钥面板（或按已输入用户名精确发起挑战），事务令牌严格驻留客户端内存，完成浏览器同源与挑战签名校验后自动激活会话并遵循「保持登录」偏好。
- **三端登录界面视觉层级与按钮布局优化**：
  - 重构主「登录」实心胶囊与「使用通行密钥登录」玻璃描边次级按钮的视觉主次关系，无需填写表单即可直接点击通行密钥登录；Android 与鸿蒙在短宽横屏下自动切换为左右双列并排按钮布局。
  - 精简登录页冗余配置项，并在未触发网关拦截且未持有网关会话时将 `Cloudflare Access` 入口收敛为轻量胶囊按钮，消除多卡片堆叠感。
- **修复外挂字幕显示但提示加载失败的问题**：
  - 修复 Android 在媒体库详情等直链（`strm_direct` / `server_wan`）起播场景下未透传实例同源基准地址与鉴权头，导致外挂字幕请求缺失凭据触发加载失败的问题，并补齐 Cloudflare Access 同源网关头透传与跨源剥离。
  - 三端新增反向代理与子路径部署下的 `/api/v1/...` 实例地址安全重绑能力，解决反代环境下后端生成 `http://` 字幕或歌词地址引发的协议失配；同步修正 iOS 省略 `server` 参数时的字幕地址校验规则。

### 安装包说明

| 平台 | 版本 | 产物文件 | 适用设备与安装说明 |
| :--- | :--- | :--- | :--- |
| **iOS / iPadOS** | `2.0.9` | `MoviePilot-2.0.9-ios-unsigned.ipa` | 需要 **iOS 16+**（小组件需 iOS 17+），下载后使用个人或企业证书重签安装（重签小组件请保持一致的 App Groups）。 |
| **Android（推荐）** | `2.0.9` | `MoviePilot-2.0.9-android-arm64-v8a.apk` | 适用于绝大多数现代 64 位 ARM 手机与平板（**Android 10 / API 29+**），体积更小，可直接安装。 |
| **Android（通用）** | `2.0.9` | `MoviePilot-2.0.9-android-universal.apk` | 同时包含 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` 架构，兼容 32 位旧设备、电视盒子与桌面模拟器。 |
| **HarmonyOS NEXT** | `2.0.9` | `MoviePilot-2.0.9-harmony-unsigned.hap` | 适用于 **HarmonyOS NEXT（API 12+）**，供开发者使用 DevEco Studio / 签名工具配置证书后安装至真机或模拟器。 |

Release 同时提供统一校验文件 `SHA256SUMS`。
