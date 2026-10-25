# 前端兼容与自行构建

[返回首页](../README.md)

优先部署 [MoviePilot-Frontend v3.2.0](https://github.com/jxxghp/MoviePilot-Frontend/releases/tag/v3.2.0) 或更新的兼容版本，并同时更新 App IPA 与前端资源。容器适配已合入正式前端源码，自行构建使用其 `v3` 分支。

App 1.0.1 的系统快捷面板和业务 Sheet 需要本次更新后的兼容前端。旧前端仍可使用原 HTML 入口；普通浏览器与 PWA 的界面保持原有方式。面板只接收当前权限过滤后的展示声明，搜索、通知、插件和用户操作继续执行前端已有业务方法。业务弹窗在同一个 WebView 中保留 Vue 内容，由原生接管标题、关闭按钮与弹出动画，关闭和降级后恢复原宿主。

处理中使用紧凑的系统进度弹层，完成后关闭或切换到结果页；识别结果保留原网页内容，由 App 显示统一标题和关闭按钮。旧 App 继续显示 HTML 处理进度。

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

源码更新后应重新构建并部署前端。协议不兼容时会回退网页导航；这不表示原生导航已接管成功。
