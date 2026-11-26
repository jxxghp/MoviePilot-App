# MoviePilot App Vue 插件音频播放与系统状态栏 / 锁屏播控接入指南

本指南面向在 MoviePilot App（iOS / Android / HarmonyOS）中运行的 Vue 联邦插件开发者，说明两种音频播放方式与系统状态栏 / 锁屏播控中心的明确调用契约。

完整的宿主 SDK、返回键、最小化胶囊、录音与文件能力见 [App 插件开发者接入指南](plugin-development-guide.md)。本文按 App `2.0.6` 的本地联邦运行时说明；旧版本、普通浏览器及远程网页兼容容器应检测能力并降级。

---

## 1. 插件内直接播放音频的两种方式

### 方式 A：标准 Web Audio / HTML5 `<audio>`（已放开手势限制）

MoviePilot App 在本地运行时（`PluginShell`）与兼容网页容器均已配置：

- iOS：`allowsInlineMediaPlayback = true`、`mediaTypesRequiringUserActionForPlayback = []`
- Android：`mediaPlaybackRequiresUserGesture = false`
- HarmonyOS：`.mediaPlayGestureAccess(false)`

插件可在 Vue 组件中使用 `<audio>` 或 Web Audio API 播放公开音频或已拉取的 Blob 音频，但仍需处理播放失败、系统中断与后台限制。若需后台音频、受鉴权 `/api/v1/...` 音频接口、存储文件渐进流式播放或系统播控，优先使用 **方式 B（原生音频接口）**。本地壳会抑制 WebView 自行发布媒体会话，避免覆盖原生播控；不要依赖 `navigator.mediaSession` 注册另一份卡片。

### 方式 B：调用宿主原生音频能力 `hostSdk.native.audio`（推荐）

在插件组件 `props` 中接收宿主注入的 `hostSdk`，检查 `hostSdk?.supports('native.audio.play')` 与 `hostSdk?.supports('native.audio.nowPlaying')`。后代组件也可通过 `inject('moviepilot:sdk', null)` 获取同一个对象，无需自己构造原生桥接信封。

```js
const props = defineProps({ api: Function, hostSdk: Object, pluginId: String })

const sdk = props.hostSdk
const native = sdk?.native
const audio = native?.audio
const pluginId = encodeURIComponent(props.pluginId ?? sdk?.context.pluginId ?? '')
```

`supports()` 检查 SDK 封装是否存在。设备侧能力可另用 `native.device.getCapabilities()` 查询，其数组名称为 `audio.play`、`audio.nowPlaying` 等，不能与 SDK 检测名混用。以下示例应在对应能力可用时调用，并使用 `try/catch` 把失败显示给用户。

#### 播放音频（支持 `url` / `apiPath` / `storage + path` / `base64`）

每次只选一种来源。URL、API、存储音频在传入非空 `title` 且 `showInStatusBar !== false` 时，会自动尝试注册系统播控（iOS `MPNowPlayingInfoCenter`、Android `MediaSession` + 媒体通知、HarmonyOS `AVSession`）。**Base64 音频请显式调用 `setNowPlaying()`**，当前 iOS 的 Base64 分支不自动注册元数据。卡片、按钮和灵动岛是否展示取决于系统与设备，不是跨平台展示承诺。

```js
// 1. 播放受鉴权插件音频；stream 接口由插件自己实现，鉴权由原生侧处理。
await audio?.play({
  apiPath: `/api/v1/plugin/${pluginId}/stream?track_id=42`,
  title: '夜曲',
  artist: '周杰伦',
  album: '十一月的萧邦',
  artworkUrl: 'https://example.com/cover.jpg',
  showInStatusBar: true, // 默认 true
})

// 2. 播放本地或远端存储音频（自动走 /api/v1/mediaserver/stream-ticket 渐进式 Range 边下边播）
await audio?.play({
  storage: 'smb', // 必须是当前后端已配置并支持的存储类型
  path: '/music/demo.flac',
  title: 'Demo FLAC',
  artist: 'Artist',
})

// 3. 播放公开直链
await audio?.play({ url: 'https://cdn.example.com/audio.mp3', title: '播客单集' })
```

`apiPath` 使用当前实例 `/api/v1/...` 相对路径；绝对公开 URL 不应要求附带实例凭据。`storage + path` 由 App 向后端 `/api/v1/mediaserver/stream-ticket` 申请播放入口，需要兼容的后端与可访问的文件。`base64` 用于短音频或 TTS，建议同时传 `mimeType`，不要把长音频完整下载后转成 Base64。

`play()` 还接受 `startPositionMs`、`volume`（0–1）、`rate`（0.5–2.0）、`loop`。倍速档位、容器格式和编码能力受平台限制。调用成功表示已受理播放，后续加载错误、进度和结束通过事件获知；新一次 `play()` 会替换当前插件音频。

#### 常用播放控制

```js
await audio?.pause()
await audio?.resume()
await audio?.seek(30_000)      // 毫秒
await audio?.setRate(1.25)     // 0.5 ~ 2.0
await audio?.setVolume(0.8)    // 0.0 ~ 1.0
await audio?.stop()
const status = await audio?.getStatus()
```

状态通常包含 `playbackId`、`state`、`positionMs`、`durationMs` 等信息。时间单位统一为毫秒。`native.audio` 保留插件界面；需要打开 App 的完整音视频播放器时使用 [native.media.playNative()](plugin-development-guide.md#playback)，其参数和生命周期不同。

---

## 2. 显式注册与更新系统状态栏 / 锁屏播控信息

即使插件自行使用 `<audio>` / Web Audio 播放，或在切歌、进度变化时更新曲目元数据，也可显式调用 `setNowPlaying` / `clearNowPlaying`：

```js
if (props.hostSdk?.supports('native.audio.nowPlaying')) {
  await audio?.setNowPlaying({
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    artworkUrl: `/api/v1/plugin/${pluginId}/cover?track_id=42`, // 由插件提供的封面接口
    durationMs: 269_000,
    positionMs: 12_000,
    isPlaying: true,
    rate: 1.0,
    canNext: true,
    canPrevious: true,
    canSeek: true,
    liked: false,
    lyricLines: [
      { timeMs: 0, text: '第一行歌词' },
      { timeMs: 12000, text: '第二行歌词' },
    ],
    customActions: [
      { id: 'play-mode', title: '切换播放模式', icon: 'mdi-repeat', active: false },
    ],
  })
}

// 停止播放或离开播放会话时清理状态栏播控卡片
await audio?.clearNowPlaying()
```

`title` 必填；`lyrics` 可提供无时间轴的歌词，`lyricLines` 为 `{ timeMs, text }[]`。切歌时重新提交完整曲目元数据；需要上一首、下一首和拖动入口时设置 `canPrevious`、`canNext`、`canSeek`。`liked` 只同步展示状态，收藏持久化仍由插件完成。

三端对扩展字段的实际处理不同：

- iOS / Android 会结合进度选择逐行歌词；HarmonyOS 当前按每次 `setNowPlaying()` 的 `positionMs` 选取当前行，插件需要按歌词变化更新。
- iOS 只把 `customActions` 第一项映射到系统书签命令；Android 支持媒体自定义动作，但通知上的按钮数量与位置由系统布局决定。
- HarmonyOS 已转发收藏和系统 `commonCommand` 事件，但当前不消费 `customActions` 描述数组，不能据此创建任意自定义按钮。SDK 或设备报告 `native.audio.customActions` 也不表示所有平台消费完全一致。
- `setNowPlaying()` 只注册播控信息，不负责开始播放；`clearNowPlaying()` 清除卡片，不应被当作停止音频的替代。结束会话时显式调用 `stop()` 和 `clearNowPlaying()`。

---

## 3. 监听进度、状态与系统状态栏远程控制按钮

用户在系统播控或耳机线控中操作时，App 通过 `hostSdk.native.onEvent(handler)` 回调给插件。**只传一个回调，回调接收 `{ event, data }`；不支持 `onEvent('事件名', handler)`。** `audio.onEvent(handler)` 也使用相同结构，只过滤出 `audio.*` 事件。

```js
// 在 <script setup> 中引入 onBeforeUnmount，并沿用前面取得的 native / sdk。
const offEvent = native?.onEvent?.(({ event, data }) => {
  if (event === 'audio.play.progress') {
    // data: { playbackId, positionMs, durationMs, bufferedMs? }
    // 用它更新插件自己的进度 UI。
  }
  if (event === 'audio.play.state') {
    // data.state: loading | playing | paused | ended | stopped | error
  }
  if (event === 'audio.play.error') {
    sdk?.ui?.toast.error('音频播放出错，请重试')
  }
  if (event === 'audio.remoteCommand') {
    // data.command: play | pause | togglePlayPause | stop | next | previous | seek
    //                toggleLike | custom
    // seek 带 positionMs；toggleLike 带 liked；custom 带 actionId。
    // 在这里连接插件的播放队列、收藏持久化和自定义业务动作。
  }
})

onBeforeUnmount(() => offEvent?.())
```

事件分工：

- 使用原生 `audio.play()` 时，宿主已经处理播放、暂停、停止、Seek 等基础控制；插件同步 UI，避免把收到的 `togglePlayPause` 再反向切一次。
- 上一首 / 下一首、收藏写回以及自定义动作由插件自己执行，宿主不会自动管理插件的播放列表或更新后端收藏。
- 使用 `<audio>` / Web Audio 自行播放时，插件需把系统命令映射到自己的播放器，并持续同步元数据和进度；仅注册播控不会替代网页播放器，也不会消除系统后台限制。
- `audio.play.ended` 表示当前曲目自然结束，可据此接入连播；`audio.play.error` 应展示失败并允许重试。不要把注册卡片成功当作音频播放成功。

---

## 4. 安全与生命周期边界

- **原生托管鉴权**：`apiPath` 与同实例 `artworkUrl` 由原生层处理鉴权。封面可以是相对 `/api/v1/...` 路径，不能依赖虚拟 `window.location.origin` 拼接实例地址；外部 URL 不应携带实例主令牌或 Cookie。
- **最小化继续运行**：[胶囊最小化](plugin-development-guide.md#capsule)保留容器，不触发插件卸载，音频可继续。不要在最小化时主动调用 `stop()`。
- **关闭后回收**：真正关闭、卸载插件或切换服务器 / 账号时释放音频、录音、播控和监听。组件自己注册的事件应在卸载时注销，避免重复回调。
- **系统限制**：后台音频与系统卡片仍受权限、音频焦点、系统中断及进程存活影响；调用成功不是永久后台运行、所有格式可播或所有设备可见按钮的保证。
