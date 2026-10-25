# 前端兼容与自行构建

[返回首页](../README.md)

优先部署 [MoviePilot-Frontend v3.2.0](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.0) 或更新的兼容版本，并同时更新 App IPA 与前端资源。容器适配已合入正式前端源码，自行构建使用其 `v3` 分支。

App 1.0.1 的系统快捷面板和业务 Sheet 需要本次更新后的兼容前端。App 不提供完整网页导航或网页登录退路；前端不兼容时显示原生恢复页。普通浏览器与 PWA 的界面保持原有方式。面板只接收当前权限过滤后的展示声明，搜索、通知、插件和用户操作继续执行前端已有业务方法。业务弹窗在同一个 WebView 中保留 Vue 内容，由原生接管标题、关闭按钮与弹出动画，关闭后恢复原宿主，桥接故障则进入原生恢复页。

处理中使用紧凑的系统进度弹层，完成后关闭或切换到结果页；识别结果保留原网页内容，由 App 显示统一标题和关闭按钮。旧 App 继续显示 HTML 处理进度。

兼容的 App 与前端同时更新后，内置卡片长按显示 iOS 上下文菜单，并悬浮预览当前卡片；原菜单的名称、图标、分隔、顺序与业务操作保持一致，卡片上的菜单三点入口隐藏。辅助功能用户可使用卡片的“操作菜单”入口，打开可滚动的原生列表。普通点击与滚动不变；旧 App、浏览器和 PWA 继续使用原菜单。远程插件自定义卡片需要按前端菜单契约显式注册。

文件工具栏、排序及添加服务等已登记的独立操作菜单使用原生列表，按内容与系统字号决定高度，最高三分之二屏，长列表可内部滚动。保留原菜单的子菜单、状态、禁用项和业务操作；关闭、导航、后台或来源失效后，旧菜单不能继续执行。

自行构建：

```sh
# 与 MoviePilot-App 放在同一父目录
git clone --branch v3 https://github.com/jxxghp/MoviePilot-Frontend.git
cd MoviePilot-Frontend

# 使用项目支持的 Node.js 与 Yarn Classic
yarn install --frozen-lockfile
yarn build
```

将 `dist/` 部署为你的 MoviePilot 前端，并继续代理同一实例的 `/api/` 等后端接口。App 应连接完整前端地址。

个人在局域网试用时，也可让 Mac 运行构建后的前端预览并代理现有实例：

```sh
MOVIEPILOT_DEV_PROXY_TARGET=https://your-moviepilot.example.com \
  yarn preview --host 0.0.0.0 --port 5186 --strictPort
```

在 App 中连接 `http://Mac的局域网IP:5186`，Mac 与 iPhone 保持同一局域网。该预览进程需持续运行，仅用于受信任的本地测试。正式使用时请部署 `dist/` 并配置 HTTPS。

源码更新后应重新构建并部署前端。协议不兼容时 App 会保留原生恢复页；更新前端后可重新打开，完成原生协商后再显示业务内容。
