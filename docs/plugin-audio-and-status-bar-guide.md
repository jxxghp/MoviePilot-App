# MoviePilot App Vue 插件音频播放与系统状态栏 / 锁屏播控接入指南

本指南面向在 MoviePilot App（iOS / Android / HarmonyOS）中运行的 Vue 联邦插件开发者，说明原生音频播放、实时频谱分析、系统媒体音量控制，以及系统状态栏 / 锁屏播控中心与「正在播放」桌面小组件的完整调用契约。

完整的宿主 SDK、返回键、最小化胶囊、桌面小组件、录音与文件能力见 [App 插件开发者接入指南](plugin-development-guide.md)。本文按 App `2.0.7` 的本地联邦运行时说明；旧版本、普通浏览器及远程网页兼容容器应检测能力并降级。

---

## 1. 插件内直接播放音频的两种方式

### 方式 A：标准 Web Audio / HTML5 `<audio>`（已放开手势限制）

MoviePilot App 在本地运行时（`PluginShell`）与兼容网页容器均已配置：

- iOS：`allowsInlineMediaPlayback = true`、`mediaTypesRequiringUserActionForPlayback = []`
- Android：`mediaPlaybackRequiresUserGesture = false`
- HarmonyOS：`.mediaPlayGestureAccess(false)`

插件可在 Vue 组件中使用 `<audio>` 或 Web Audio API 播放公开音频或已拉取的 Blob 音频，但仍需处理播放失败、系统中断与后台限制。若需后台音频、受鉴权 `/api/v1/...` 音频接口、存储文件渐进流式播放、实时频谱分析或系统播控，优先使用 **方式 B（原生音频接口）**。本地壳会抑制 WebView 自行发布媒体会话，避免覆盖原生播控；不要依赖 `navigator.mediaSession` 注册另一份卡片。

### 方式 B：调用宿主原生音频能力 `hostSdk.native.audio`（推荐）

在插件组件 `props` 中接收宿主注入的 `hostSdk`，检查 `hostSdk?.supports('native.audio.play')` 与 `hostSdk?.supports('native.audio.nowPlaying')`。后代组件也可通过 `inject('moviepilot:sdk', null)` 获取同一个对象，无需自己构造原生桥接信封。

```js
const props = defineProps({ api: Function, hostSdk: Object, pluginId: String })

const sdk = props.hostSdk
const native = sdk?.native
const audio = native?.audio
const pluginId = encodeURIComponent(props.pluginId ?? sdk?.context.pluginId ?? '')
```

`supports()` 检查 SDK 封装是否存在。设备侧能力可另用 `native.device.getCapabilities()` 查询，其数组名称为 `audio.play`、`audio.nowPlaying`、`native.audio.systemVolume`、`native.audio.spectrum` 等。以下示例应在对应能力可用时调用，并使用 `try/catch` 把失败显示给用户。

#### 播放音频（支持 `url` / `apiPath` / `storage + path` / `base64` + 可选频谱分析）

每次只选一种来源。URL、API、存储音频在传入非空 `title` 且 `showInStatusBar !== false` 时，会自动尝试注册系统播控（iOS `MPNowPlayingInfoCenter`、Android `MediaSession` + 单色爱心状态栏媒体通知、HarmonyOS `AVSession`）。**Base64 音频请显式调用 `setNowPlaying()`**。卡片、按钮和灵动岛是否展示取决于系统与设备，不是跨平台展示承诺。

```js
// 1. 播放受鉴权插件音频并开启实时频谱回调；stream 接口由插件自己实现，鉴权由原生侧处理。
const res = await audio?.play({
  apiPath: `/api/v1/plugin/${pluginId}/stream?track_id=42`,
  title: '夜曲',
  artist: '周杰伦',
  album: '十一月的萧邦',
  artworkUrl: `/api/v1/plugin/${pluginId}/cover?track_id=42`,
  showInStatusBar: true, // 默认 true
  spectrum: {
    enabled: true,
    bands: 64,       // 16 ~ 256，默认 64
    intervalMs: 50,  // 30 ~ 250ms，默认 50ms
  },
})
// res.spectrumActive 表示当前平台与权限下是否已实际启用原生频谱采集

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

`apiPath` 使用当前实例 `/api/v1/...` 相对路径（原生侧支持 HTTP Range 渐进式流式请求）；绝对公开 URL 不应要求附带实例凭据。`storage + path` 由 App 向后端 `/api/v1/mediaserver/stream-ticket` 申请播放入口，需要兼容的后端与可访问的文件。`base64` 用于短音频或 TTS，建议同时传 `mimeType`，不要把长音频完整下载后转成 Base64。

`play()` 还接受 `startPositionMs`、`volume`（0–1，播放器内部增益）、`rate`（0.5–2.0）、`loop` 以及 `spectrum`。倍速档位、容器格式和编码能力受平台限制。调用成功表示已受理播放，后续加载错误、进度、频谱和结束通过事件获知；新一次 `play()` 会替换当前插件音频。

#### 常用播放控制、系统媒体音量与频谱动态开关

```js
await audio?.pause()
await audio?.resume()
await audio?.seek(30_000)      // 毫秒
await audio?.setRate(1.25)     // 0.5 ~ 2.0
await audio?.setVolume(0.8)    // 0.0 ~ 1.0（当前音频实例增益）
await audio?.stop()
const status = await audio?.getStatus()

// 读取与调节系统硬件媒体音量（支持监听物理音量键变化）
if (sdk?.supports('native.audio.systemVolume')) {
  const sysVol = await audio?.getSystemVolume?.()
  // sysVol: { volume: 0.6, muted: false, currentSteps?: 9, maxSteps?: 15 }
  await audio?.setSystemVolume?.({ volume: 0.5, showUI: false })
}

// 播放中途按需开启或关闭频谱采集（切到后台或隐藏频谱视图时建议关闭以节省功耗）
if (sdk?.supports('native.audio.spectrum')) {
  await audio?.setSpectrum?.({ enabled: false })
}
```

状态通常包含 `playbackId`、`state`、`positionMs`、`durationMs` 等信息。时间单位统一为毫秒。`native.audio` 保留插件界面；需要打开 App 的完整音视频播放器时使用 [native.media.playNative()](plugin-development-guide.md#playback)，其参数和生命周期不同。

---

## 2. 显式注册与更新系统状态栏 / 锁屏播控及「正在播放」桌面小组件

即使插件自行使用 `<audio>` / Web Audio 播放，或在切歌、进度变化时更新曲目元数据，也可显式调用 `setNowPlaying` / `clearNowPlaying`。在 App `2.0.7+` 中，调用 `setNowPlaying` 还会**自动同步更新三端「MoviePilot 正在播放」桌面小组件**的封面、曲目、当前歌词行与播控状态：

```js
if (props.hostSdk?.supports('native.audio.nowPlaying')) {
  await audio?.setNowPlaying({
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    artworkUrl: `/api/v1/plugin/${pluginId}/cover?track_id=42`, // 支持相对鉴权路径
    durationMs: 269_000,
    positionMs: 12_000,
    isPlaying: true,
    rate: 1.0,
    canNext: true,
    canPrevious: true,
    canSeek: true,
    liked: false,
    lyricLines: [
      { timeMs: 0, text: '故事的小黄花' },
      { timeMs: 12000, text: '从出生那年就飘着' },
    ],
    customActions: [
      { id: 'play-mode', title: '单曲循环', icon: 'mdi-repeat-once', active: true },
    ],
  })
}

// 停止播放或离开播放会话时清理状态栏播控卡片与正在播放桌面小组件活跃态
await audio?.clearNowPlaying()
```

`title` 必填；`lyrics` 可提供无时间轴的歌词，`lyricLines` 为 `{ timeMs, text }[]`。切歌时重新提交完整曲目元数据；需要上一首、下一首和拖动入口时设置 `canPrevious`、`canNext`、`canSeek`。`liked` 只同步展示状态，收藏持久化仍由插件完成。

三端对扩展字段的实际处理：

- **Android 媒体通知图标与动作映射**：状态栏小图标统一采用单色实心爱心图标，`liked` 采用实心 / 空心爱心图标；`customActions` 的 `icon` 支持精确映射 `repeat` / `loop`（列表循环）、`repeat-one` / `repeat_one` / `loop-one`（单曲循环）、`shuffle` / `random`（随机播放）、`heart` / `like`（红心）、`lyric`（歌词）等专属单色矢量图标。
- **歌词同步**：iOS / Android 会结合播放进度自动推进逐行歌词并同步至桌面小组件；HarmonyOS 按 `setNowPlaying()` 传入的 `positionMs` 匹配当前歌词行。
- **平台控制中心差异**：iOS 将 `customActions` 第一项映射到系统书签命令；HarmonyOS 已转发收藏和系统 `commonCommand` 事件，当前不直接把 `customActions` 渲染为系统播控中心额外按钮。
- `setNowPlaying()` 只注册播控信息，不负责开始播放；结束会话时显式调用 `stop()` 和 `clearNowPlaying()`。

---

## 3. 监听进度、实时频谱、系统音量与远程控制按钮

用户在系统播控、耳机线控、物理音量键或「正在播放」桌面小组件中操作时，App 通过 `hostSdk.native.onEvent(handler)` 回调给插件。**只传一个回调，回调接收 `{ event, data }`；不支持 `onEvent('事件名', handler)`。** `audio.onEvent(handler)` 也使用相同结构，只过滤出 `audio.*` 事件。

```js
// 在 <script setup> 中引入 onBeforeUnmount，并沿用前面取得的 native / sdk。
const offEvent = native?.onEvent?.(({ event, data }) => {
  if (event === 'audio.play.progress') {
    // data: { playbackId, positionMs, durationMs, bufferedMs? }
  }
  if (event === 'audio.play.spectrum') {
    // data: { playbackId, positionMs, fft: number[], left: number, right: number }
    // fft 为长度等于 bands 的 0..255 频段幅值数组；left / right 为 0..255 左右声道电平（VU 表 / 复古磁带机表头可直接消费）。
  }
  if (event === 'audio.systemVolume') {
    // data: { volume: 0..1, muted: boolean, currentSteps?: number, maxSteps?: number }
  }
  if (event === 'audio.play.state') {
    // data.state: loading | buffering | playing | paused | ended | stopped | error
  }
  if (event === 'audio.play.error') {
    sdk?.ui?.toast.error('音频播放出错，请重试')
  }
  if (event === 'audio.remoteCommand') {
    // data.command: play | pause | togglePlayPause | stop | next | previous | seek
    //                toggleLike | custom
    // seek 带 positionMs；toggleLike 带 liked；custom 带 actionId。
  }
})

onBeforeUnmount(() => offEvent?.())
```

频谱与事件注意事项：

- **频谱平台与权限**：iOS 基于 `MTAudioProcessingTap`（及 `AVAudioPlayer` 电平包络）无需麦克风权限即可采集；Android 系统底层 `Visualizer` 依赖 `RECORD_AUDIO` 权限（宿主不会在 `play()` 时强弹麦克风授权窗，若用户未授权麦克风或设备音效驱动限制，`play()` / `setSpectrum()` 会平缓返回 `spectrumActive: false`，音频正常播放不受任何影响，前端可根据 `spectrumActive` 决定是否请求 `microphone` 权限或展示模拟动效）；HarmonyOS 当前平缓返回 `spectrumActive: false`。
- **自动节能**：频谱事件仅在音频处于 `playing` 状态时按 `intervalMs` 推送，暂停、结束或销毁时自动停止采集。
- **播控分工**：使用原生 `audio.play()` 时，宿主已经处理播放、暂停、停止、Seek 等基础控制；上一首 / 下一首、收藏写回以及自定义动作由插件自己执行。

---

## 4. 安全与生命周期边界

- **原生托管鉴权**：`apiPath` 与同实例 `artworkUrl`（含最小化胶囊 `iconUrl` 及小组件图片）由原生层自动拼接实例地址并附加鉴权头；外部 URL 绝不附带实例主令牌或 Cookie。
- **最小化继续运行与状态同步**：[胶囊最小化](plugin-development-guide.md#capsule)保留容器不断连，原生播放状态与 `setNowPlaying` 会自动同步更新最小化胶囊的播放 / 暂停按钮状态。不要在最小化时主动调用 `stop()`。
- **关闭后回收**：真正关闭、卸载插件或切换服务器 / 账号时自动释放音频、频谱采集器、音量监听、录音与播控会话。组件自己注册的事件应在卸载时注销。
