# 原生客户端 API 对接回归

三端消费当前 V3 后端接口；`shared/contracts/v3-endpoints.yaml` 是入口索引，路由、响应和权限仍须与实际后端核对。不能通过枚举猜测旧路径或把 422/500 变成空列表来掩盖对接问题。

## 身份与安全边界

- 用户管理采用完整更新：只编辑姓名、邮箱或分类权限时，保留原始 OTP、头像、设置以及 `permissions.features`。只读元数据和密码摘要不回传；空密码不覆盖现有密码。
- 图片每次重定向都重新检查实例源和部署子路径，非受信目标不携带 Bearer、资源 Cookie、Cloudflare Cookie 或自定义鉴权头。
- Android 请求发出前捕获会话代次；旧请求的 401、失效型 403 不能注销后来登录的会话，即使重新登录签发了相同令牌。
- 离线播放终态按规范化实例地址与不可变用户 ID 隔离。切换实例或账号后，仅重试属于当前身份的记录；队列中的网络请求固定使用原身份。旧版没有归属信息的全局队列不自动迁移，避免误写另一账号的播放进度。
- 鸿蒙社区勋章佩戴是同样按实例与用户隔离的本地偏好；强制同步使用 `GET /github/community?refresh=true`。

## 真实后端合同

- 渠道成员：`GET /authorization/` 的 `data.members`；关联码：`POST /authorization/binding`，到期字段是绝对时间 `expires_at`。审批与撤销使用 `PUT /authorization/{member_id}`，撤销对应 `status=disabled`，并保留成员的 `role/scopes`。
- 日历：`GET /subscribe/calendar?start=YYYY-MM-DD&end=YYYY-MM-DD&page=1&count=200`。窗口左闭右开，最多 93 天；响应为 `items/total`，每项关联 `subscribe` 与 `episodes`，电影可能没有分集。Android 跟随可见周切换窗口，鸿蒙展示未来 31 天；两端都读取完整分页。
- 模块诊断：`GET /system/modulelist` 的 `data.modules` 与 `GET /system/moduletest/{module_id}`；合并 `GET /system/module-catalog` 的类型元数据，列表请求失败时显示错误。
- 站点和工作流入口遵循 manage 分类权限，用户管理等超级管理员入口仍要求 admin。

## 本地与 CI 验证

先使用 `tools/rust/build-android.sh` 构建与当前源码一致的宿主 Rust 库和 Android 产物，再运行 `:core-rust-bridge:testDebugUnitTest`。测试使用桌面 JNA 和本机随机端口的 MockWebServer，覆盖真实 Repository 登录、过期响应、图片传输、离线队列及接口解析。`MOVIEPILOT_RUST_HOST_LIB_DIR` 指向宿主动态库目录；`tools/android/build-android.sh` 会自动设置并执行桥接测试、App 单测、完整 Lint 和 APK 校验。

iOS 先执行 `tools/ios/test-core.sh`，再通过 `xcodebuild build-for-testing` 生成签名的模拟器 App（`CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`）。运行：

```bash
python3 tools/ios/test-api-smoke.py \
  --derived-data /Volumes/DISK/TmpBuild/<任务>/ios-derived \
  --output-dir /Volumes/DISK/TmpBuild/<任务>/ios-smoke
```

所有本机 xcodebuild 命令复用 `-clonedSourcePackagesDirPath /Volumes/DISK/Xcode/SourcePackages`。smoke 脚本复用 Products，在专用模拟器上运行 Agent、权限、OTP/不记住登录和保留用户字段四项交互测试；不访问真实后端、账号或媒体库。为使 XCTest 可稳定等待空闲，测试启动参数关闭动态背景。脚本只清理自己创建的服务、设备和缓存，保留汇总 JSON，并在失败时导出结果包。

`tools/ios/native-v2-fixture.py` 必须保持真实接口命名空间、日期必填及完整用户更新语义；未知路径仍返回 404 并计数。工具单测负责验证夹具不会替客户端兜底。Multiplatform CI 在 iOS 构建后实际执行上述 smoke，失败证据通过 Actions artifact 保留。
