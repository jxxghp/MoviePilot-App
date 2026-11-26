# 内部设计与实现记录

此目录收纳架构设计、实施方案与回归说明，供 App 维护者追溯背景和实现取舍。方案中的阶段划分、目标指标及历史现状保留编写时的上下文，不代表当前已向插件开放的接口。

插件开发者请从 [App 插件开发者接入指南](../plugin-development-guide.md) 和 [插件音频与系统播控接入指南](../plugin-audio-and-status-bar-guide.md) 开始，以当前 SDK、共享契约和三端源码为准。

| 文档 | 内容 |
| --- | --- |
| [Vue 联邦插件本地运行时](vue-plugin-local-runtime-design.md) | 本地联邦壳、预热池、虚拟同源、原生桥接和视觉融合方案 |
| [多内核播放](multi-engine-playback-design.md) | 原生与增强播放内核、切换和失败回退设计 |
| [媒体服务器直连播放](media-server-direct-play-design.md) | 直连优先、代理回退与安全边界 |
| [播放进度与实时会话同步](playback-progress-sync-design.md) | 播放会话、进度上报、账号绑定与离线补偿 |
| [弹幕支持](danmaku-support-design.md) | 弹幕接口、匹配和三端原生渲染设计 |
| [原生客户端 API 对接回归](api-integration-tests.md) | 身份隔离、后端接口语义与本地、CI 验证方法 |
