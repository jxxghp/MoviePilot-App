# 原生插件表单接线（P2.2a）

本叶子建立真实会话 API、保真草稿与显式保存控制器，供 P2.2b 的 Rex 原生表单使用。它不把协议分类、测试验证器或成功 PUT 当成组件已经渲染；主体 UI、表达式/脚本、Web 插件兼容继续按路线验收。

## 固定输入与实际合同

2026-11-20 再次 fetch：App origin/main `682e9532`，本地 v2 从 `d1a81cf` 接续；Frontend origin/v3 `db17d9cb`、Backend origin/v3 `63d09b1c`、Plugins origin/main `5d473864`。读取固定 Git 对象，不切换其它仓分支或覆盖插件仓未提交内容。

- Backend `app/api/endpoints/plugin.py:plugin_form`：GET `plugin/form/{physicalID}` 返回原始 `render_mode/conf/model`，默认 model 与已存配置合并；只允许当前超级管理员。
- `set_plugin_config`：PUT `plugin/{physicalID}`，请求是完整配置对象，响应是标准 success/message/data。`app/application/plugin/config.py:update` 保存后重新初始化/刷新注册，不应自动重放；空对象不能覆盖已有非空配置。
- Frontend `PluginConfigDialog.vue:savePluginConf` 直接提交完整 model，成功后通知父列表并异步刷新插件导航；刷新失败不反转已成功的保存。控制器的 lastSave 提供接受事件，真实宿主在 P2.2b/P2.5 接入对应刷新，不在数据层耦合尚未实现的导航客户端。`FormRender.vue` 的字段键为原始完整键，隐藏字段仍留在同一对象；原生保存不包装成 model/conf。
- 物理插件 ID 沿用 `[A-Za-z][A-Za-z0-9_]{0,127}`，原大小写不变；源插件只用于组件来源，不能代替保存目标。当前配置 API 不沿用普通插件导航的宽松权限缺省。

## 实现决定

1. APIClient 增加显式 payload Data 投影，仍经过同一私有 receive：同源路径、拒绝跳转、MIME/状态/大小、分页、取消、无 Cookie/缓存和不自动重试。仅允许 `.payload`，不借原始字节绕过标准 envelope 失败判断。NativeSession 在前后检查同一代次/权限并沿用 401 失效处理。
2. Foundation-only PluginFormDraft 从合法 form/vuetify 文档建立完整 model 副本，编码仍用 PluginJSONValue。更新是原子操作，先检查整个候选模型预算；失败不改草稿。原始点号键、未知/隐藏字段、大整数和数值词法保留；规范等价但字节不同的键拒绝覆盖。脏状态按稳定编码字节比较，字符串的 Unicode 序列变化也不能被 Swift 规范等价误吞。
3. 新增 MoviePilotPluginForms 控制器，固定 NativeSession + 物理/源插件目标；没有第二套 URLSession/令牌/权限逻辑。读取和保存要求 admin；操作前、响应后以及发布前均检查。文档解析和初始编码放在归属当前操作的结构化子任务，取消随父任务传播；并发提交拒绝，关闭会取消自身任务并清掉文档/草稿，迟到响应不能重新发布。真实 UI 生命周期结束须显式 close。
4. 正常更新只改变草稿并清除旧成功提示；未确认写入不能因修改/放弃本地草稿而伪装成未发送。显式保存提交完整对象一次；同步校验改变了修订则要求重新校验，避免把旧值发送并覆盖新输入。成功只确认本次模型已被端点接受，不声称插件后台任务完成；失败/取消保留草稿并记录结果未确认，不自动 reload 或重发。重新加载有修改的草稿需调用方已经取得放弃修改的明确选择。
5. 渲染/校验由真实 UI 的验证器提供，不能仅凭模型 requirements 说已实现组件。默认验证器只允许合法空 conf；非空表单默认阻止保存。P2.2a 测试注入的窄验证器仅验证控制器时序/载荷，不成为产品 UI 的能力证明。P2.2b 需以实际组件注册、属性/绑定、条件、值校验和能力诊断替代它，不能直接传空报告放行未知界面；隐式读取/条件需依据当前 draft 重新解析，不能只使用加载时的绑定索引。
6. Vue 模式保留文档供专用兼容层接续，不能产生可保存的原生草稿。结构错误/资源越界不变成空配置成功页。错误仅保留安全类型/位置，不记录配置值或认证信息。

## 验收与回滚

边界测试覆盖原始响应无 Double 中转、传输限制与 401/权限；原始键/Unicode 冲突/值类型/完整未知字段/预算/取消；加载失败、显式放弃、保存失败/成功/取消、重复提交、关闭、实例切换、权限撤销、迟到响应及物理路径。使用 URLProtocol 的实际 URLSession，不连接生产账号。

本叶子不改 iOS 默认入口与 UI，因此只运行相关 Swift 测试、既有回归、格式与 iOS 16 SDK 模块编译；不重复无变化的模拟器视觉验收。回滚可移除独立表单产品及草稿/接线；原有 typed API 与账号入口继续工作。后续 UI 必须读取 Rex 唯一视觉约束并应用 swiftui-liquid-glass 技能。
