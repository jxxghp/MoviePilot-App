# MoviePilot App 插件开发者接入指南

本文面向 MoviePilot 插件开发者，说明现有插件如何接入 App，以及如何调用 App 为插件提供的原生交互、导航、最小化、音视频与设备扩展。

本文对应本仓库 `v2` 分支、App `2.0.7` 代码中的实现：本地桥接协议为 `moviepilot.pluginHost` major `2`，注入的 `hostSdk.apiVersion` 为 `1`。这两个版本属于不同层次。旧版 App、浏览器和远程网页兼容容器可能缺少部分方法，接入时必须检测能力并处理调用失败；不要仅凭版本号放行。

## 目录

- [1. 选择接入方式](#integration)
- [2. 最小 Vue 接入示例](#quick-start)
- [3. 能力检测、权限与错误处理](#capabilities)
- [4. 请求插件后端 API](#api)
- [5. 提示、弹窗、环境与导航](#host-services)
- [6. 返回键与关闭](#back)
- [7. 最小化胶囊与保活](#capsule)
- [8. 音频播放与原生播放器](#playback)
- [9. 录音](#recording)
- [10. 设备、文件与系统交互](#device)
- [11. 原生 JSON 表单、数据页与插件入口](#native-ui)
- [12. 三端差异与接入检查](#compatibility)
- [13. 契约与源码入口](#references)

<a id="integration"></a>

## 1. 选择接入方式

| 插件界面 | App 如何处理 | 插件开发者需要做什么 |
| --- | --- | --- |
| `render_mode: "vuetify"` 的 JSON 配置表单、数据页 | 使用原生组件呈现常用表单、列表、表格、图表等内容 | 沿用后端的 `conf` / `model`、`page` / `elements` 协议，无需调用 JS SDK |
| `render_mode: "vue"` 的模块联邦插件 | 在隔离的本地 `plugin-shell` 中挂载 Vue 组件，由原生桥接提供网络和设备能力 | 接收宿主传入的 `api`、`hostSdk` 等 props，按能力检测结果调用扩展 |
| 导航声明的插件全页入口 | 根据 `nav_key` 加载对应的联邦组件 | 正确声明导航、权限和模块暴露名；全页仍是 Vue 组件，不是另一套 JSON 全页协议 |

Vue 插件继续使用原有模块联邦构建，App 兼容现有两种联邦构建方式，无需把原生代码打进插件。宿主共享 Vue / Vuetify；插件不要另起一套根应用、路由或登录流程。

| 场景 | 联邦暴露名 | 宿主额外传入的 props |
| --- | --- | --- |
| 配置 | `./Config` | `initialConfig`；组件通过 `save` 事件提交完整配置对象 |
| 数据页 | `./Page` | `show_switch`；需要时通过 `switch` 事件切换配置页 |
| 仪表盘联邦组件 | `./Dashboard` | 具体嵌入位置由宿主决定；不能假设三端都直接内嵌执行 |
| 插件全页，`nav_key` 为空或 `main` | `./AppPage` → `./Page` | `navKey` |
| 插件全页，其他 `nav_key` | `./AppPage{PascalCase}` → `./AppPage` → `./Page` | `navKey`；如 `music-library` 对应 `./AppPageMusicLibrary` |

联邦壳实际挂载上述组件时，会提供 `api`、`hostSdk`、`nativeHost`、`pluginId`、`sourcePluginId`。`pluginId` 是当前安装实例的物理插件 ID；克隆插件的源 ID 另存于 `sourcePluginId`，不能用源 ID 覆盖当前实例的读写目标。

<a id="quick-start"></a>

## 2. 最小 Vue 接入示例

下面的组件可以作为插件 `Page.vue` 的接入起点。`example.com` 地址仅作占位，使用时替换成插件自己的可用音频源；后端鉴权音频应按[音频指南](plugin-audio-and-status-bar-guide.md)使用 `apiPath`。

```vue
<script setup>
import { computed, inject, onBeforeUnmount, ref } from 'vue'

const props = defineProps({
  api: Function,
  hostSdk: Object,
  pluginId: String,
  sourcePluginId: String,
})

// props 适合入口组件；后代组件也可以使用同一个注入键。
const sdk = props.hostSdk ?? inject('moviepilot:sdk', null)
const native = sdk?.native
const audio = native?.audio
const message = ref('尚未播放')
const canPlay = computed(() => Boolean(sdk?.supports?.('native.audio.play')))

/** 在用户点击后启动原生音频，并把失败原因显示在插件界面。 */
async function play() {
  if (!canPlay.value || !audio?.play) {
    message.value = '当前客户端不支持原生音频'
    return
  }
  try {
    await audio.play({
      url: 'https://example.com/demo.mp3',
      title: '演示音频',
    })
  } catch (error) {
    message.value = error?.message ?? '播放失败'
  }
}

// onEvent 接收一个回调，回调参数为 { event, data }。
const offEvent = native?.onEvent?.(({ event, data }) => {
  if (event === 'audio.play.state') message.value = data.state
  if (event === 'audio.play.error') message.value = '音频播放出错'
})

onBeforeUnmount(() => offEvent?.())
</script>

<template>
  <VCard variant="tonal">
    <VCardText>{{ message }}</VCardText>
    <VCardActions>
      <VBtn :disabled="!canPlay" @click="play">播放演示音频</VBtn>
    </VCardActions>
  </VCard>
</template>
```

宿主还提供以下兼容入口，优先选用 `hostSdk`，不要自行访问 WebView 的平台桥接对象：

| 入口 | 含义 |
| --- | --- |
| `props.nativeHost` 或 `inject('moviepilot:native', null)` | 与 `hostSdk.native` 相同的原生扩展对象 |
| `inject('moviepilot:toast', null)` | `hostSdk.ui.toast` |
| `inject('moviepilot:confirm', null)` | `hostSdk.ui.confirm` |
| `inject('moviepilot:dialog', null)` | `hostSdk.ui.dialog` |
| `props.nativeSubscribe`、`props.subscriptionManager` | 兼容的订阅入口；新代码优先使用 `hostSdk.subscriptions` |

`hostSdk.hostVersion` 是随本地联邦壳打包的宿主 SDK 版本，**不是 App 版本，也不是当前后端版本**。查询 App 版本请使用 `native.device.getInfo()` 的 `appVersion`。

Web 宿主 SDK 中定义过的能力不一定在 App 本地壳中启用。当前本地壳未注入 `resources`、`files`、`catalogs`、`events`、`workflows`、`agent`、`pet` 或 `shell.registerTabs`，不要仅根据公共类型声明调用。需要设备文件选择时使用 `native.device.pickFile()`；其他入口先用 `supports()` 或方法存在性判断。

<a id="capabilities"></a>

## 3. 能力检测、权限与错误处理

能力检测分为两层：

1. `sdk.supports(name)`：SDK 是否提供这一组调用封装，例如 `shell.minimize`、`navigation.back`、`native.audio.play`、`native.device`。
2. `await native.device.getCapabilities()`：设备端报告的平台、系统和 App 版本，以及 `capabilities` 数组，例如 `audio.play`、`audio.record`、`media.playNative`、`device.scanCode`、`device.overlay`。

两层名称不是统一加减 `native.` 前缀的关系。例如播放检测分别是 `native.audio.play` 和 `audio.play`；扫码应检查设备返回的 `device.scanCode`，不能调用 `sdk.supports('native.device.scanCode')` 推断支持。SDK 的通用封装、设备上报的分组能力也不保证每个可选字段都实现，仍需参考[三端差异](#compatibility)并处理失败。

```js
// 本节及后续 JS 片段沿用最小示例中的 sdk、native、audio 和 props。
const report = await native.device.getCapabilities()
const deviceCaps = new Set(report.capabilities ?? [])

if (deviceCaps.has('device.scanCode')) {
  const result = await native.device.scanCode({ prompt: '扫描二维码' })
  if (!result.cancelled) sdk.ui.toast.info(result.value)
}

const permission = await native.device.checkPermission('microphone', { request: true })
if (permission.status !== 'granted') {
  sdk.ui.toast.warning('请先允许麦克风权限')
}
```

`checkPermission(name, { request })` 支持 `microphone`、`camera`、`photos`、`notifications`；`overlay` 用于 Android 系统悬浮窗。省略 `request` 或传 `false` 只查询，传 `true` 才请求授权或打开相应设置页。返回 `{ permission, status }`，状态可能为 `granted`、`denied`、`undetermined`、`restricted`、`limited`、`unsupported`，具体以平台为准；拒绝授权后不要循环弹窗。

调用失败通常通过 Promise reject 返回 `PluginBridgeError`，可读 `message`、`code`、`status`、`data`。常见 `code` 包括 `PERMISSION_DENIED`、`UNSUPPORTED`、`NO_SESSION`、`INVALID_PARAMS`、`FORBIDDEN_PATH`、`TIMEOUT`、`NO_TRANSPORT`、`ABORTED`。用户取消选择或身份认证也可能正常 resolve 为 `cancelled: true` 或 `authenticated: false`，不能只靠 `catch` 判断成功。

底层入口为 `native.invoke(type, payload?, timeoutMs?)`，例如 `native.invoke('device.keepAwake', { enabled: true }, 10000)`。它使用桥接消息名；没有对应平台实现的消息可能超时，不是任意原生方法调用器。常规接入优先使用下面列出的封装方法。

<a id="api"></a>

## 4. 请求插件后端 API

使用 `props.api` 或 `sdk.api`。这是兼容常见请求用法的宿主代理，鉴权请求由原生网络层发往当前 MoviePilot 实例。插件运行在虚拟源下，不能用 `window.location.origin` 拼接 NAS 地址。

```js
const api = props.api ?? sdk.api
const pluginId = encodeURIComponent(props.pluginId ?? sdk.context.pluginId)
const controller = new AbortController()

const response = await api.get(`plugin/${pluginId}/items`, {
  params: { page: 1, count: 20 },
  signal: controller.signal,
  timeout: 15000,
  feedback: 'silent',
})

// 返回的是后端响应体；是否还有 response.data 由该后端接口自己的协议决定。
// POST/PUT/PATCH 的第二个参数为请求体，第三个参数为选项。
await api.post(`plugin/${pluginId}/action`, { action: 'refresh' })
```

- 上面的 `items`、`action` 是示例插件需要自行实现的后端接口，并非 App 内置路由。
- 路径可以用 `plugin/...` 或 `/api/v1/plugin/...`，最终只允许当前实例 `/api/v1/` 下的安全路径；禁止跨源 URL、协议相对地址、路径穿越或传入实例登录令牌。
- 当前原生代理允许 `GET`、`POST`、`PUT`、`PATCH`、`DELETE`、`HEAD`。不要因为请求对象上存在 `options()` 就假定原生代理支持 `OPTIONS`。
- `FormData`、文本、JSON、Blob / ArrayBuffer 请求体会被桥接封装；响应可使用默认 JSON，或 `responseType: 'text' | 'blob' | 'arraybuffer'`。它不是完整浏览器网络栈，不承诺流式 SSE、任意请求拦截器或完整请求库实例行为。
- 取消请求使用 `AbortController`。`feedback: 'silent'` 可抑制代理自动错误提示，由插件自行显示。
- 优先从 props / `sdk.context.pluginId` 取得物理 ID。宿主对源插件路径做克隆映射，但插件自行保存 ID、拼接业务参数时仍需正确区分源与克隆实例。
- 相对 `/api/v1/...` 图片、插件静态资源由宿主受控加载；封面等原生资源参数也优先使用相对 API 路径。

插件不应读取或写入 `localStorage.auth`，也不应传递 `Authorization`、Cookie 或自定义实例鉴权头。外部公开资源使用无实例凭据的 URL；不要把主令牌放到查询参数、日志、截图或外部分享链接中。

<a id="host-services"></a>

## 5. 提示、弹窗、环境与导航

### 5.1 提示与确认

```js
sdk.ui.toast.success('保存成功')
sdk.ui.toast.info('正在刷新')
sdk.ui.toast.warning('请检查配置')
sdk.ui.toast.error('操作失败')

const confirmed = await sdk.ui.confirm({
  title: '清空记录',
  content: '清空后无法恢复，是否继续？',
  type: 'warn',
  confirmText: '清空',
  cancelText: '取消',
})
if (confirmed) {
  // 在这里执行插件自己的操作。
}
```

注意 SDK 确认框使用 `content` 字段；桥接内部才转换成 `message`。`type: 'warn'` 或 `'error'` 会标记破坏性确认。`ui.dialog(Component, props?, events?, options?)` 用于挂载 Vue 子组件弹窗，返回 `{ id, close(), updateProps(patch) }`；`options.closeOn` 默认是 `['close', 'done', 'cancel']`，`replace: true` 替换当前弹窗栈。它仍是联邦壳中的 Vue 弹窗，不是任意原生页面构造器。

`shell.registerButton({ title, icon?, disabled?, action })` 注册宿主操作按钮，返回注销函数；是否显示取决于当前容器是否展示宿主标题栏。联邦全页默认隐藏外层退出顶栏，插件应提供清楚的自身导航。不要依赖 DOM 扫描代替显式接入。

### 5.2 环境、权限快照与偏好

| 方法 | 用途 |
| --- | --- |
| `environment.getSnapshot()` | 读取 `locale`、`theme`、`isMobile`、`online`、`user`、`permissions`、`features` |
| `environment.subscribe(handler)` | 立即收到一次快照，之后接收环境变化；返回取消订阅函数 |
| `environment.hasPermission(category, feature?)` | UI 展示时参考宿主提供的权限快照；后端仍执行最终鉴权 |
| `preferences.get(key)` | 读取当前用户的插件偏好，缺省返回 `null` |
| `preferences.set(key, value)` / `remove(key)` | 写入或清空当前实例后端的用户配置键 `plugin_{pluginId}_{key}` |

环境快照只包含宿主提供的字段，不能假设包含所有后端细粒度权限。偏好接口用于轻量、可序列化设置，不是密钥库、音频缓存或大文件存储。

本地壳会同步 Vuetify 主题及 CSS 变量，例如 `--mp-accent`、`--mp-text-primary`、`--mp-text-secondary`、`--mp-surface-glass`、`--mp-surface-elevated`、`--mp-surface-border`、`--mp-panel-radius`。优先使用主题组件和这些变量，避免硬编码整屏背景、固定文字颜色或覆盖宿主安全区。支持窄屏、平板及横竖屏变化，不要把设备屏幕尺寸等同于当前插件容器尺寸。

### 5.3 导航与业务入口

| 方法 | 当前本地壳行为 |
| --- | --- |
| `navigation.push({ path, query? })`、`replace({ path, query? })` | 转换为 `moviepilot://` 原生路由；当前两者都委托宿主打开，不保证 Web Router 的历史替换语义 |
| `media.detail({ media_source, media_id, type?, title? })` | 打开媒体详情 |
| `media.recognize({ path })` | 打开手动识别入口 |
| `media.select()` | 当前本地壳返回取消结果，不提供媒体选择界面 |
| `subscriptions.create(...)`、`createMusic(...)` | 校验 `media_source`、`media_id` 后打开媒体详情，由用户继续操作；返回成功不代表订阅已创建 |
| `subscriptions.manage({ subscriptionId, action })` | 打开对应订阅管理入口；支持的动作仍受原生路由和权限约束 |
| `native.device.openExternal(url)` | 委托系统打开 HTTP / HTTPS 外链，不附带实例凭据 |

例如 `await sdk.navigation.push({ path: 'plugin/MyPlugin', query: { surface: 'data' } })` 打开插件数据页，`await sdk.media.detail({ media_source: 'tmdb', media_id: '123', type: '电影' })` 打开媒体详情。`opened` 等结果表示已委托导航，不能作为服务端业务完成的证明。

<a id="back"></a>

## 6. 返回键与关闭

插件可以消费系统返回键、返回手势：

```js
const editorVisible = ref(false)

// 返回 true 表示已处理，false 表示交还给宿主。
const offBack = sdk.navigation.onBack(() => {
  if (!editorVisible.value) return false
  editorVisible.value = false
  return true
})

onBeforeUnmount(() => offBack())
```

监听按后注册优先执行，也支持组件 `defineExpose({ onBack })` 作为兼容入口。单个处理器只有约 **300ms** 的等待预算，应立即关闭内部面板或切换内部状态；不要等待网络、长动画或确认框后才决定是否消费返回。未消费时，壳会继续处理自己的弹窗、活动遮罩，再把返回交给原生容器。

主动退出使用 `sdk.navigation.close()`、`sdk.shell.close()` 或入口组件 `emit('close')`。这会结束插件页面；需要保留运行状态时使用最小化接口。

<a id="capsule"></a>

## 7. 最小化胶囊与保活

`shell.minimize()` 把正在运行的插件转为紧凑单行横向悬浮胶囊，保留该联邦容器与 JS 上下文：左侧显示圆形封面 / 插件图标，中部显示标题与副标题（点击直接恢复打开完整插件窗口），右侧最多显示 3 个内联快捷图标按钮与关闭按钮。

```js
if (sdk.supports('shell.minimize')) {
  const result = await sdk.shell.minimize({
    mode: 'mini',
    title: '演示音频',
    subtitle: '周杰伦',
    statusText: '正在播放',
    iconUrl: `/api/v1/plugin/${encodeURIComponent(props.pluginId ?? sdk.context.pluginId)}/cover?id=1`,
    isPlaying: true,
    keepOutsideApp: false,
    actions: [
      { id: 'prev', label: '上一首', icon: 'mdi-skip-previous' },
      { id: 'toggle', label: '暂停', icon: 'mdi-pause', active: true },
      { id: 'next', label: '下一首', icon: 'mdi-skip-next' },
    ],
  })
  if (!result.minimized) sdk.ui.toast.info('当前容器未进入最小化状态')
}

const offCapsule = sdk.shell.onCapsuleAction(({ actionId }) => {
  if (actionId === 'toggle') {
    // 处理播放 / 暂停切换
  }
})

sdk.shell.updateCapsule({ statusText: '已暂停', isPlaying: false })
onBeforeUnmount(() => offCapsule())
```

胶囊字段包括 `mode`、`title`、`subtitle`、`capsuleTitle`（可选，胶囊专用短标题）、`capsuleArtist`（可选，胶囊专用短副标题/歌手）、`statusText`、`iconUrl`（支持 `/api/v1/...` 同实例受鉴权相对路径，由原生侧自动附带鉴权头加载）、`isPlaying`、`keepOutsideApp`、`edgeSnapThresholdDp`（可选，默认 `24`，范围 `0..72`）和 `actions`；动作包含 `id`、`label`（兼容 `title`）、`icon`、`active`、`destructive`。更新时传补丁即可，传 `actions: []` 清空快捷操作。入口组件也可 `emit('minimize', options)`，需要确认结果时使用 SDK Promise。

- 固定紧凑宽度与短标题防抖：单行胶囊文字区固定为 `64dp` 紧凑宽度（约 5 个汉字宽，超出自动省略截断），总宽在同组按钮下恒定在 `~206dp`，切歌、刷新歌词或切换播放状态均不会引起胶囊忽长忽短；插件也可通过 `capsuleTitle` / `capsuleArtist`（同时支持在 `minimize`、`updateCapsule` 与 `audio.setNowPlaying` 中传入）为胶囊单独指定短文案，而系统通知栏与锁屏继续展示完整的 `title` / `artist`。
- 拖动与贴边「超级最小化」：三端应用内悬浮胶囊与 Android `TYPE_APPLICATION_OVERLAY` 系统悬浮窗均会将胶囊严格限制在屏幕安全区内（避开状态栏、手势条与刘海/灵动岛），并持久化安全坐标；当拖至距左/右安全边缘小于 `edgeSnapThresholdDp` 松手时自动吸附并收缩为贴边半圆胶囊，点击半圆立即恢复完整单行胶囊。

- 点击胶囊标题与信息区域直接恢复完整插件窗口，无需先展开二级小窗；内联快捷按钮直接派发 `onCapsuleAction({ actionId })`，并且播放类按钮会根据 `isPlaying`（含原生 `audio.play` / `setNowPlaying` 状态变化）实时同步切换播放 / 暂停图标。
- `shell.updateCapsule(patch)` 是单向更新；`shell.restore()` 返回恢复结果；`shell.onCapsuleAction(handler)` 的参数是 `{ actionId }`，与原生音频事件的 `{ event, data }` 不同。
- Android 的 `keepOutsideApp: true` 允许退到桌面后显示单行系统悬浮胶囊，需要 `overlay` 权限；授权要先经过用户操作，打开设置页后应在回到 App 时重新查询。没有权限时不要把设置页已打开当作授权完成。
- iOS、HarmonyOS 当前提供应用内胶囊，不提供此 Android 系统悬浮窗能力。该字段不能使插件跨 App 永久在线。
- 最小化不是 `unmount`，插件音频可以继续；关闭胶囊、关闭插件、退出登录或切换实例会触发资源释放。保活不承诺进程被系统终止后仍继续运行，也不能用于可靠后台定时任务。

<a id="playback"></a>

## 8. 音频播放与原生播放器

### 8.1 保留插件界面的原生音频

`native.audio` 控制插件自己的原生音频会话，支持公开 HTTP / HTTPS 直链、同实例 `apiPath`（支持 Range 渐进流式）、后端存储 `storage + path` 以及内联 Base64。`play()` 会替换该插件当前的音频，不是多轨混音器。

| 方法 | 参数 / 用途 |
| --- | --- |
| `play(options)` | 音频源与 `title`、`artist`、`album`、`artworkUrl`、`showInStatusBar`、`startPositionMs`、`volume`、`rate`、`loop`、`spectrum` |
| `pause()`、`resume()`、`stop()` | 控制当前音频；结束整个会话时另行清理播控信息 |
| `seek(positionMs)` | 跳转，毫秒 |
| `setRate(rate)`、`setVolume(volume)` | 倍速 `0.5–2.0`；播放器内部音量 `0–1`，具体倍速档位受平台限制 |
| `getSystemVolume()`、`setSystemVolume(volOrOpts)` | 读取或调节系统硬件媒体音量（`0–1`），并可通过 `audio.systemVolume` 监听硬件音量键变化 |
| `setSpectrum({ enabled, bands?, intervalMs? })` | 播放期间动态开关或调整实时频谱与双声道电平回调（`audio.play.spectrum`） |
| `getStatus()` | 查询 `playbackId`、`state`、`positionMs`、`durationMs` 等状态 |
| `setNowPlaying(metadata)`、`clearNowPlaying()` | 注册、更新或清除系统播控信息，并自动联动三端「MoviePilot 正在播放」桌面小组件 |
| `onEvent(handler)` | 只接收音频事件的订阅入口，参数同样是 `{ event, data }`；返回取消订阅函数 |

`play()` 的 Promise 完成不代表音频已经完整加载或播放结束，继续监听 `audio.play.state`、`audio.play.progress`、`audio.play.ended`、`audio.play.error`。锁屏、耳机及媒体通知的命令通过 `audio.remoteCommand` 发送给插件。歌词、收藏、自定义动作、鉴权封面与完整代码见[插件音频与系统播控接入指南](plugin-audio-and-status-bar-guide.md)。

### 8.2 打开 App 完整播放器

使用 `native.media.playNative(options)`，三种来源任选一种：

```js
await native.media.playNative({
  storage: 'local',
  path: '/media/demo.mkv',
  title: '演示视频',
})

await native.media.playNative({ itemId: '123', server: '我的媒体服务器', title: '演示影片' })

await native.media.playNative({
  url: 'https://example.com/demo.mp4',
  mediaType: 'video', // 'audio' | 'video'；公开直链按需指定
  title: '演示视频',
})
```

`storage` 必须是后端实际配置的存储类型，`path` 是后端可访问路径；`server` 用于选择已配置的媒体服务器。返回 `{ launched: true }` 表示已委托播放器，不能当作播放完成回调。这个接口不接收 `apiPath`、Base64 或任意鉴权头；需要播放受鉴权插件音频时选 `native.audio.play({ apiPath })`。

<a id="recording"></a>

## 9. 录音

录音使用 `native.audio`，由原生侧请求麦克风权限；不要同时依赖网页 `getUserMedia`。

| 方法 | 说明 |
| --- | --- |
| `startRecord(options?)` | 开始录音，返回 `recordingId`、`mimeType` 等信息 |
| `pauseRecord()`、`resumeRecord()` | 暂停、继续 |
| `getRecordStatus()` | 查询当前录音状态与时长 |
| `stopRecord({ includeBase64: true })` | 结束并返回录音字节信息，`includeBase64` 默认 `true` |
| `cancelRecord()` | 放弃当前录音 |

`startRecord` 可选参数：`sampleRate`（8000–48000）、`channels`（1–2）、`bitRate`（16000–256000）、`maxDurationSec`（1–1800，默认 300）、`metering`。建议显式使用 `format: 'm4a'`；iOS 额外支持 `wav`，Android / HarmonyOS 当前输出 AAC / M4A，不承诺按 `format: 'wav'` 录制。设备不支持的采样参数可能导致失败，应读取实际返回的 MIME 类型。

```js
await audio.startRecord({
  format: 'm4a', sampleRate: 24000, channels: 1,
  bitRate: 96000, maxDurationSec: 60, metering: true,
})

// 实际界面应把 start / stop 分别绑定到用户的开始、结束操作。
const recording = await audio.stopRecord({ includeBase64: true })
if (recording.truncated || !recording.base64) {
  sdk.ui.toast.warning('录音未返回完整字节，请缩短录音时长')
} else {
  const bytes = Uint8Array.from(atob(recording.base64), (char) => char.charCodeAt(0))
  const body = new FormData()
  body.append('file', new Blob([bytes], { type: recording.mimeType }), recording.fileName)
  const id = encodeURIComponent(props.pluginId ?? sdk.context.pluginId)
  await (props.api ?? sdk.api).post(`plugin/${id}/upload`, body)
}
```

这里的 `upload` 同样需要插件自行实现。录音结果包含 `durationMs`、`sizeBytes`、`fileName`、`mimeType`、`base64?`、`truncated`；返回 Base64 的原始字节上限为 **15 MiB**。超过上限不会返回完整音频，不可忽略 `truncated` 后继续上传。`includeBase64: false` 不是获取可持久访问的文件句柄，停止后不能假定还可读取临时录音。

音量与状态事件分别为 `audio.record.level`、`audio.record.state`，通过 `native.onEvent(handler)` 或 `audio.onEvent(handler)` 订阅。开始新的录音会结束原有录音，并停止当前插件原生音频；不要假定录放并行。

<a id="device"></a>

## 10. 设备、文件与系统交互

以下方法位于 `native.device`，先检测 SDK / 设备能力，再在用户操作时调用。

| 方法 | 参数与返回要点 |
| --- | --- |
| `getInfo()` | 平台、系统版本、`appVersion`、设备型号、语言、网络类型、屏幕尺寸和像素比等快照 |
| `getCapabilities()` | 设备能力报告，见[能力检测](#capabilities) |
| `checkPermission(name, options?)` | 查询 / 请求授权 |
| `haptic(style?)` | 触感反馈，默认 `light`，具体反馈受硬件和系统限制 |
| `copyText(text)`、`readClipboard()` | 写入文本；读取返回 `{ text }`，系统可能显示隐私提示 |
| `share({ title?, text?, url?, base64?, mimeType?, fileName? })` | iOS / Android 打开系统分享，文件分享使用 Base64；HarmonyOS 当前退化为复制文本 / URL |
| `keepAwake(enabled)` | 控制插件持有的屏幕常亮状态；结束使用后传 `false` |
| `notify({ title, body, id?, delaySec? })` | 本地通知；返回 `{ scheduled, id }`，不代表一定展示，也不是后端推送接口 |
| `pickMedia({ source?, mediaType?, multiple?, maxCount?, includeBase64? })` | 媒体选择；`source: 'library' \| 'camera'`，`mediaType: 'image' \| 'video' \| 'any'`，具体支持见下表 |
| `pickFile({ accept?, multiple?, includeBase64? })` | 文件选择；`accept` 建议用 MIME 字符串数组，如 `['application/pdf']` |
| `saveMedia({ base64? , apiPath?, url?, mimeType?, fileName? })` | 保存媒体字节，来源任选一种；返回 `{ saved }` |
| `scanCode({ prompt? })` | 扫码，返回 `{ cancelled, value?, format? }`；Android 当前不支持 |
| `authenticate({ reason? })` | 系统身份验证，返回 `{ authenticated, biometryType }`；`false` 不能继续受保护操作 |
| `openExternal(url)` | 打开 HTTP / HTTPS 外链 |

媒体和文件选择共用 `{ cancelled, files }` 响应。每个文件包含 `name`、`mimeType`、`sizeBytes`、`base64?`、`truncated`；`includeBase64` 默认 `true`，每个文件最多返回 15 MiB 原始字节的 Base64。收到取消、空文件列表、`truncated: true` 或缺少字节时应停止后续上传，不要把它们当成空文件提交。

```js
const picked = await native.device.pickFile({
  accept: ['application/pdf'], multiple: false, includeBase64: true,
})
if (!picked.cancelled) {
  const file = picked.files?.[0]
  if (!file || file.truncated || !file.base64) {
    sdk.ui.toast.warning('未取得完整文件，请选择较小的文件')
  } else {
    sdk.ui.toast.success(`已选取 ${file.name}`)
    // 按实际文件类型验证内容后，参照录音示例构造 FormData 上传。
  }
}
```

<a id="native-ui"></a>

## 11. 原生 JSON 表单、数据页与插件入口

### 11.1 不使用 Vue 的插件

现有插件无需为 App 单独写 UI：配置入口读取 `GET /api/v1/plugin/form/{pluginId}`，数据页读取 `GET /api/v1/plugin/page/{pluginId}`。例如配置响应：

```json
{
  "render_mode": "vuetify",
  "conf": [
    { "component": "VSwitch", "props": { "model": "enabled", "label": "启用" } },
    { "component": "VTextField", "props": { "model": "endpoint", "label": "服务地址", "v-if": "enabled" } }
  ],
  "model": { "enabled": false, "endpoint": "" }
}
```

- `props.model` 指向配置字段；`model` 提供完整配置。保存目标是 `PUT /api/v1/plugin/{pluginId}` 的完整配置对象，不是把 `conf`、`render_mode` 一起提交。
- App 已适配常用输入、选择、多选、Combobox、自定义词条、五字段 Cron、条件显示及数据页列表 / 表格 / 图表等。条件使用受支持的表达式语法；任意 JS、DOM 脚本、自定义 Web 组件不等于可原生执行。
- 隐藏或未展示字段仍须保留，不能只提交界面上出现的字段。插件后端也应保留自身完整配置语义。
- 如果配置页是 Vue `./Config`，宿主传入 `initialConfig`，入口组件通过 `emit('save', completeConfig)` 交给宿主保存；`emit('close')` 关闭，`emit('switch')` 切换到数据页。不要重复发一次保存请求又发一次 `save`。
- 需要复杂脚本或自定义交互的插件继续使用 Vue 隔离运行时；不要从原生 JSON 表单尝试调用 `hostSdk`。

### 11.2 导航、仪表盘与三端桌面小组件

App 沿用后端的导航声明（`sidebar_nav`），读取 `plugin_id`、`nav_key`、`title`、权限等字段；插件全页组件的解析顺序见[接入方式](#integration)。导航显示仍取决于用户权限，不能仅暴露 `./AppPage` 就假定一定出现入口。

插件仪表盘通过 `GET /api/v1/plugin/dashboard/meta` 发现，按物理 ID 与 `key` 读取 `GET /api/v1/plugin/dashboard/{pluginId}/{key}`；空 `key` 使用不带末尾 key 的路径。原生面板消费 `elements` 与 `attrs`（如 `title`、`subtitle`、`border`）。

自 App `2.0.7` 与 MoviePilot `v3.2.15` 起，**iOS、Android 与 HarmonyOS 三端统一提供三类桌面小组件**：

1. **MoviePilot 主体小组件**：展示系统概览、下载状态、近期入库与订阅进度（无需插件接入）。
2. **MoviePilot 正在播放小组件**：固定音频播控形态，插件只需按[音频指南](plugin-audio-and-status-bar-guide.md)调用 `native.audio.setNowPlaying()` 即可自动联动展示封面、曲目、同步歌词及「喜欢 / 上一首 / 播放暂停 / 下一首」控制按钮。
3. **MoviePilot 插件小组件（支持预设模板与自定义布局树 DSL）**：同时支持**后端静态 / 定时拉取**与**前端运行态实时推送**双通道：
   - **后端协议（推荐提供，App 未运行时系统也能后台静默刷新）**：插件继承 `_PluginBase` 后可实现可选方法 `get_widgets() -> list[dict]` 与 `get_widget_data(key: str = "default") -> dict | None`；未实现该方法的旧插件，后端会自动提取其 Vuetify `get_dashboard()` 结构作为桌面小组件兜底。
   - **前端运行态推送（`hostSdk.native.widget`）**：Vue 插件可在运行期间通过 `sdk.supports('native.widget')` 检测并调用 `native.widget.update(payload)`、`native.widget.remove(widgetKey?)`、`native.widget.list()`，以及通过 `native.widget.onEvent`（或 `native.onEvent` 的 `'widget.action'` 事件）响应桌面自定义按钮点击：

```js
if (sdk?.supports('native.widget')) {
  await native.widget.update({
    widgetKey: 'brush-overview',
    title: '刷流助手',
    subtitle: '运行中 · 3 个站点',
    kind: 'custom', // 'metrics' | 'list' | 'poster' | 'nowPlaying' | 'custom'
    accentHex: '#3B82F6',
    layout: {
      type: 'column',
      gap: 6,
      children: [
        {
          type: 'row',
          align: 'spaceBetween',
          children: [
            { type: 'metric', label: '今日上传', value: '128.4 GB', tone: 'success' },
            { type: 'metric', label: '今日下载', value: '14.2 GB', tone: 'accent' },
          ],
        },
        { type: 'progress', label: '目标达成率', value: 0.78, valueText: '78%', tone: 'accent' },
        {
          type: 'button',
          label: '立即巡检',
          tone: 'accent',
          action: { type: 'pluginAction', actionId: 'run-now' },
        },
      ],
    },
  })
}
```

- 自定义布局树 `PluginWidgetNode` 支持 `column`、`row`、`text`、`metric`、`progress`、`badge`、`image`（仅限 `/api/v1/plugin/file/...` 插件静态资源路径）、`button`、`divider`、`spacer`，最大嵌套深度 `5` 层、节点上限 `40` 个、总载荷上限 `32 KiB`。桌面小组件全部由系统原生组件安全渲染，不在桌面进程执行任意 JS。

<a id="compatibility"></a>

## 12. 三端差异与接入检查

| 能力 / 可选字段 | iOS | Android | HarmonyOS NEXT |
| --- | --- | --- | --- |
| 原生音频、录音、系统播控、单行悬浮胶囊 | 已接入，仍受设备权限与系统限制 | 同左 | 同左 |
| `audio.getSystemVolume()` / `setSystemVolume()` | 支持读取、监听物理音量键与离屏滑块调节 | 支持 `STREAM_MUSIC` 读写与系统广播监听 | 支持读取与音量变化监听；写入受系统权限约束时自动降级 |
| `audio.play({ spectrum })` / `setSpectrum()` | 基于 `MTAudioProcessingTap` / 电平实时推送 `fft` + `left` / `right` | 基于系统 `Visualizer` 实时推送（需已获 `RECORD_AUDIO` 权限，未授权平缓返回 `spectrumActive: false`） | 当前返回 `spectrumActive: false` |
| `scanCode()` | 相机可用时上报能力 | 当前返回 `UNSUPPORTED`，能力列表不含扫码 | 调用系统扫码；可取消 |
| `pickMedia({ source: 'camera' })` | 相机拍摄 | 相机拍摄 | 当前使用系统相册选择器，忽略 `source`，不能据此拍摄 |
| 录音格式 | M4A，另支持 WAV | AAC / M4A | AAC / M4A |
| 选择器 `maxCount` / 文件 `accept` | 按系统支持处理 | `maxCount` 当前未消费，`accept` 交给系统文件选择器 | 媒体 `maxCount` 可用，文件选择当前未消费 `accept` |
| `share()` | 支持 Base64 文件与文本 / URL 的系统分享 | 支持 Base64 文件与文本 / URL 的系统分享 | 当前复制文本 / URL 到剪贴板，不拉起分享面板、不消费 Base64 文件 |
| `saveMedia()` | 保存到相册，需相册写权限 | 写入图片媒体库 | 打开系统保存选择器，可能返回 `saved: false` |
| `notify({ delaySec })` | 系统安排延时通知 | App 进程内延时后发送，不保证杀进程后执行 | 当前立即发送，不消费 `delaySec` |
| `keepOutsideApp` / `overlay` | 无 Android 系统悬浮窗能力 | 授权后提供系统单行悬浮胶囊 | 无此系统悬浮窗能力 |
| 歌词 / 自定义媒体动作 | 逐行歌词；自定义动作只映射首项到系统书签命令 | 逐行歌词；单色爱心状态栏图标与循环 / 随机 / 红心矢量动作图标 | 歌词按 `setNowPlaying` 时进度选取，当前不消费 `customActions` 描述数组 |
| 桌面小组件（主体 / 正在播放 / 插件预设与自定义 DSL） | WidgetKit（iOS 17+，需在 App 内启用只读凭据并保持 App Groups 一致） | Jetpack Glance（支持重配置、实时广播刷新与后台 WorkManager 同步） | FormExtensionAbility 服务卡片（支持多尺寸与主应用联动刷新） |

插件发布前建议至少检查：

1. 在普通浏览器、支持扩展的 App 以及缺少扩展的旧容器中，都能正确降级；不因 `hostSdk` 缺失而白屏。
2. 用户拒绝权限、取消选择、身份验证失败、断网和 API 超时都有明确结果；不吞异常伪装成功。
3. 克隆插件的配置、API 和偏好写入当前物理 ID；切换实例或退出账号后不继续发出旧请求。
4. 返回键先处理内部面板；关闭页面和最小化具有符合预期的资源生命周期。
5. 用 `{ event, data }` 接收原生事件，在组件卸载时注销监听；不要使用 `native.onEvent('事件名', handler)`。
6. 检查 15 MiB 限制、`truncated` 与实际 MIME 类型；录音、媒体字节和身份信息不写日志。
7. 音频覆盖切歌、暂停、进度跳转、结束、锁屏操作与关闭胶囊；系统播控显示以真实设备为准。
8. 深浅主题、窄屏、横屏、平板和键盘弹出后仍可操作。

<a id="references"></a>

## 13. 契约与源码入口

更新插件时应以实际 SDK 封装和三端消费代码为准；设计方案记录的是实现背景，不能当作接口已开放的证明。

- [音频与系统播控接入指南](plugin-audio-and-status-bar-guide.md)
- [桥接消息与事件契约](../shared/contracts/plugin-host-bridge-v2.json)
- [JSON UI Schema](../shared/contracts/plugin-ui-schema.json)
- [当前随 App 分发的联邦壳清单](../shared/plugin-shell/manifest.json)
- [iOS 桥接](../ios/MoviePilot/PluginWeb/PluginHostBridgeV2.swift) / [原生能力](../ios/MoviePilot/PluginWeb/PluginNativeCapabilitiesService.swift)
- [Android 桥接](../android/core-plugin-host/src/main/java/com/moviepilot/pluginhost/runtime/AndroidPluginHostBridgeV2.kt) / [原生能力](../android/core-plugin-host/src/main/java/com/moviepilot/pluginhost/runtime/AndroidPluginNativeCapabilities.kt)
- [HarmonyOS 桥接](../harmony/commons/plugin_host/src/main/ets/runtime/HarmonyPluginHostBridgeV2.ets) / [原生能力](../harmony/commons/plugin_host/src/main/ets/runtime/HarmonyPluginNativeCapabilities.ets)
- [Android 插件桌面小组件](../android/widget/src/main/java/com/moviepilot/widget/MoviePilotPluginGlanceWidget.kt)
- [内部设计与实现记录](design/README.md)
