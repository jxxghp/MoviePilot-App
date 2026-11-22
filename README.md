# MoviePilot-App (v2 全原生 iOS 客户端)

MoviePilot 官方全原生 SwiftUI iOS 客户端（`v2` 分支），直接对接 MoviePilot V3 后端 API，提供统一深色紫玫瑰渐变玻璃视觉体系、iOS 26+ Liquid Glass 导航及原生本地播放体验。[查看完整界面图册（60 张）](screenshots/README.md)。

## 核心能力

- **4+1 Liquid Glass 底部导航**：`发现`、`探索`、`我的`（无大标题仪表盘与无缝插件图表）、`设置`（多层次卡片与列表设置中心），右侧 `+1` 按钮按当前页动态切换主操作或默认全局搜索；重复点击底栏主图标弹出极简 8 项快捷菜单（`订阅`、`日历`、`资源`、`下载`、`文件`、`历史`、`工作流`、`插件`）。
- **影视发现、探索与详情**：精选透明片名 Logo 主视觉、发现模块显隐与排序编辑、TMDB/豆瓣/Bangumi 多来源探索片库、演职员/分季详情、添加订阅、资源搜索与原生本地播放。
- **订阅、下载与文件整理**：我的订阅与订阅广场、追剧日历、PT 资源搜索与下载确认、正在下载管理、整理历史（常驻搜索框、整理队列与长按菜单）、多存储文件浏览与本地音视频播放。
- **自动化与扩展生态**：纯 SwiftUI 工作流节点画布与社区分享、站点管理（双向绿/玫红上下行流量图示）与搜索/订阅站点范围（`IndexerSites`/`RssSites`）、AI 智能助手 SSE 流式对话、插件市场与原生 JSON 配置表单/数据页/仪表盘图表（遗留 Vue 插件提供受控隔离兼容宿主）。
- **捷径与诊断中心**：内置系统模块健康检查、网络测速、名称识别与过滤规则测试、实时日志及定时服务手动触发。
- **系统集成与本地播放**：原生 VLCKit/AVKit/PiP 音视频播放与字幕/歌词队列；脱离旧网页桥的原生 APNs 推送通知、WidgetKit 桌面小组件、深链与主屏幕快捷方式。

## 环境与自行构建

- **系统要求**：iOS 16+（桌面小组件需 iOS 17+，Liquid Glass 导航需 iOS 26+）。
- **构建依赖**：Xcode 26+、XcodeGen。

```zsh
# 运行 Swift 核心单元测试
zsh scripts/test-core.sh

# 运行脚本与夹具测试
python3 -m unittest discover -s scripts/tests

# 重新生成 Xcode 工程并构建模拟器目标
(cd ios && xcodegen generate)
xcodebuild build \
  -project ios/MoviePilot.xcodeproj \
  -scheme MoviePilot \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## 界面图册

完整 60 张实测截图（含连接服务/登录页、4+1 导航、设置中心、发现/探索/豆瓣与剧集详情、捷径词表与日志、站点历史流量图表、订阅/资源/下载/文件/整理历史、工作流画布与插件页面）请见 [screenshots/README.md](screenshots/README.md)。

## 许可证

MoviePilot-App 采用 [GNU General Public License v3.0（GPL-3.0-only）](LICENSE)。
