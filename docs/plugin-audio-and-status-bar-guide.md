# MoviePilot App Vue 插件音频播放与系统状态栏 / 锁屏播控接入指南

本指南面向在 MoviePilot App（iOS / Android / HarmonyOS）中运行的 Vue 联邦插件开发者，说明两种音频播放方式与系统状态栏 / 锁屏播控中心的明确调用契约。

---

## 1. 插件内直接播放音频的两种方式

### 方式 A：标准 Web Audio / HTML5 `<audio>`（已放开手势限制）
MoviePilot App 在本地运行时（`PluginShell`）与兼容网页容器均已配置：
- iOS：`allowsInlineMediaPlayback = true`、`mediaTypesRequiringUserActionForPlayback = []`
- Android：`mediaPlaybackRequiresUserGesture = false`
- HarmonyOS：`.mediaPlayGestureAccess(false)`

因此插件可直接在 Vue 组件中使用 `<audio>` 或 Web Audio API 播放公开音频或已拉取的 Blob 音频；若需后台播放、访问受鉴权 `/api/v1/...` 音频接口、存储文件渐进流式播放，或对接系统状态栏播控，推荐使用 **方式 B（原生音频接口）**。

### 方式 B：调用宿主原生音频能力 `hostSdk.native.audio`（推荐）
在插件组件 `props` 中解构 `hostSdk`（由 MoviePilot App 本地运行时自动注入，同时兼容检查 `hostSdk?.supports('native.audio.play')` 与 `hostSdk?.supports('native.audio.nowPlaying')`）：

```ts
const props = defineProps<{
  api: any
  hostSdk?: import('@moviepilot/plugin-sdk').PluginHostSdk
}>()

const audio = props.hostSdk?.native?.audio
```

#### 播放音频（支持 `url` / `apiPath` / `storage + path` / `base64`）
当传入 `title` 且 `showInStatusBar !== false` 时，App 会**自动注册到系统状态栏 / 锁屏播控中心**（iOS `MPNowPlayingInfoCenter` / 灵动岛、Android `MediaSession` + `Notification.MediaStyle`、HarmonyOS `AVSession`）：

```ts
// 1. 播放受鉴权 MoviePilot API 音频（原生代附 Bearer Token 与资源 Cookie，WebView 零令牌暴露）
await audio?.play({
  apiPath: '/api/v1/plugin/my_music/stream?track_id=42',
  title: '夜曲',
  artist: '周杰伦',
  album: '十一月的萧邦',
  artworkUrl: 'https://example.com/cover.jpg',
  showInStatusBar: true, // 默认 true
})

// 2. 播放本地或远端存储音频（自动走 /api/v1/mediaserver/stream-ticket 渐进式 Range 边下边播）
await audio?.play({
  storage: 'smb', // 支持 local / smb / alist / alipan / u115 等
  path: '/music/demo.flac',
  title: 'Demo FLAC',
  artist: 'Artist',
})

// 3. 播放公开直链或 Base64 音频
await audio?.play({ url: 'https://cdn.example.com/audio.mp3', title: '播客单集' })
```

#### 常用播放控制
```ts
await audio?.pause()
await audio?.resume()
await audio?.seek(30_000)      // 毫秒
await audio?.setRate(1.25)     // 0.5 ~ 2.0
await audio?.setVolume(0.8)    // 0.0 ~ 1.0
await audio?.stop()
const status = await audio?.getStatus()
```

---

## 2. 显式注册与更新系统状态栏 / 锁屏播控信息

即使插件自行使用 `<audio>` / Web Audio 播放，或在切歌、进度变化时更新曲目元数据，也可显式调用 `setNowPlaying` / `clearNowPlaying`：

```ts
if (props.hostSdk?.supports('native.audio.nowPlaying')) {
  await audio?.setNowPlaying({
    title: '晴天',
    artist: '周杰伦',
    album: '叶惠美',
    artworkUrl: '/api/v1/system/img/0?imgurl=...',
    durationMs: 269_000,
    positionMs: 12_000,
    isPlaying: true,
    rate: 1.0,
    canNext: true,
    canPrevious: true,
    canSeek: true,
  })
}

// 停止播放或离开播放会话时清理状态栏播控卡片
await audio?.clearNowPlaying()
```

---

## 3. 监听进度、状态与系统状态栏远程控制按钮

用户在锁屏、控制中心、灵动岛、耳机线控或状态栏通知点击「播放 / 暂停 / 上一首 / 下一首 / 拖动进度条 / 停止」时，App 会通过 `hostSdk.native.onEvent('audio.remoteCommand', ...)` 回调给插件：

```ts
const offProgress = props.hostSdk?.native?.onEvent('audio.play.progress', (ev) => {
  // { playbackId, positionMs, durationMs, bufferedMs? }
})

const offState = props.hostSdk?.native?.onEvent('audio.play.state', (ev) => {
  // { playbackId, state: 'loading'|'playing'|'paused'|'ended'|'stopped'|'error', positionMs, durationMs }
})

const offRemote = props.hostSdk?.native?.onEvent('audio.remoteCommand', (ev) => {
  // ev.command: 'play' | 'pause' | 'togglePlayPause' | 'stop' | 'next' | 'previous' | 'seek'
  // 当 command === 'seek' 时附带 ev.positionMs
  if (ev.command === 'next') playNextTrack()
  if (ev.command === 'previous') playPrevTrack()
})

// 组件卸载时解绑（宿主也会在插件卸载时自动清理音频与状态栏卡片）
onBeforeUnmount(() => {
  offProgress?.()
  offState?.()
  offRemote?.()
})
```

---

## 4. 安全与生命周期边界

- **零令牌泄露**：鉴权 `apiPath` 与同源 `artworkUrl` 均由原生网络层自动附加 `Authorization` 与资源 Cookie，不向插件脚本暴露凭据。
- **自动回收**：当插件页面关闭、卸载或用户切换服务器实例时，App 会自动停止插件音频播放并注销系统状态栏播控卡片。
