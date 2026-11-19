# 首轮方案与 API 底座验收

日期：2026-11-19。范围：P0.1/P1.1，MoviePilot-App/v2 的文档、清单生成器及独立 MoviePilotAPI Swift Package 目标。实现、测试与本记录由同一聚焦代码提交保存；P0.1 方案提交为 31f8b8d。

## 已成立

- 已从 App origin/main 的 682e9532c384af457a275ef5dfe66cbe0672a5cb 建立 v2；其它三仓只 fetch 和读取固定 Git 对象，不读取它们未提交的产品修改作为基线。
- 35 个路由与 33 个页面源文件一一核对；90 个通用 dialog、8 个设置视图和插件静态清单保存在 baseline.json。不是运行态功能验收。
- 新 API 模块与旧 App 默认入口独立，源码只使用 Foundation 与现有 MoviePilotCore 的地址/语言/JSON 类型，没有 WebKit 或网页桥调用。
- 真实 URLSession + URLProtocol 验证部署子路径、尾斜杠、IPv6、查询编码、凭据/Cookie 隔离、JSON 写入、原始插件 payload、包装错误、分页头、大小上限、HTTP 错误、无重试、重定向拒绝、任务取消与客户端失效。
- 默认 App/UI、签名、真实实例/用户数据和前后端/插件仓产品代码均未变更；未推送或发布。

## 实际执行

| 检查 | 结果 |
| --- | --- |
| SwiftPM 全套测试 | 原有 Swift Testing 166 项/26 suites + XCTest 4 项；新 API 19 项/2 suites，全部通过；参数化场景随相应测试执行 |
| Python 脚本测试 | 9 项通过，包含新增范围扫描器的 4 项 |
| Node 语言桥测试 | 3 项通过、0 skipped |
| Swift 格式 | Sources、Tests、ios/MoviePilot、ios/MoviePilotUITests、ios/MoviePilotWidgets 的严格递归检查通过 |
| iOS 目标编译 | MoviePilotAPI 及其核心依赖针对 arm64-apple-ios16.0-simulator、使用当前本机 iPhoneSimulator SDK 编译通过 |
| 文档与 Git | 本地链接、范围统计、git diff --check 通过 |

首轮曾因测试用 URL.path 检查目录尾斜杠而失败；核对 Foundation 行为后改为检查实际 percentEncodedPath，保留严格的尾斜杠断言。另按 swift-format 规则删除等同自动合成的初始化器。修正后全套相关检查重新通过，没有降低断言或修改其它仓库来绕过失败。

审阅时还补充了服务端表单式查询解码对照：URLComponents 自身往返会漏掉字面量加号被后端解释为空格的问题。端点现在明确将加号编码为 %2B，测试按服务端先处理加号再百分号解码的顺序核对原始参数。

SwiftPM 使用 /Volumes/DISK/TmpBuild/moviepilot-ios-v2/ 下的外置 scratch/cache，避免污染内置盘；该缓存供长期任务继续复用。一次性范围盘点目录在证据整理后清理。

## 可重放命令

在 App 仓根目录执行。App 无 Python 虚拟环境，本次按工作区既有映射使用 MoviePilot/.venv 运行标准库脚本，不启动真实后端。

~~~sh
mkdir -p /Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
CLANG_MODULE_CACHE_PATH=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/clang \
zsh scripts/test-core.sh --scratch-path /Volumes/DISK/TmpBuild/moviepilot-ios-v2/swiftpm

/Users/jxxghp/MPProjects/MoviePilot/.venv/bin/python -m unittest discover -s scripts/tests
node --test scripts/tests/*.test.mjs
xcrun swift-format lint --strict --recursive Sources Tests \
  ios/MoviePilot ios/MoviePilotUITests ios/MoviePilotWidgets

native_sdk="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
TMPDIR=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/tmp \
CLANG_MODULE_CACHE_PATH=/Volumes/DISK/TmpBuild/moviepilot-ios-v2/clang \
xcrun swift build --target MoviePilotAPI --triple arm64-apple-ios16.0-simulator \
  --sdk "$native_sdk" --scratch-path /Volumes/DISK/TmpBuild/moviepilot-ios-v2/ios-swiftpm
~~~

## 仍未成立

尚未接入或运行原生 v2 主体界面；未执行全 App Xcode/UI 构建、模拟器实际操作、真实后端、真实插件、真机、APNs/PiP/Widget、最终 IPA、远端 CI 或发布验收。

基础模块编译时选择 iOS 16 部署目标，不代表在 iOS 16 运行时或旧设备实测通过。新的概念设计图也尚未生成或选定。总 Goal 保持 active，下一叶子为 P1.2 原生身份与实例会话。
