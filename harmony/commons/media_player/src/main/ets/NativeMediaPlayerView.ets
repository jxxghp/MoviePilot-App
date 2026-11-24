import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** 鸿蒙原生音视频播放请求模型（与 Rust/iOS/Android 清单一致）。 */
export interface HarmonyPlaybackRequest {
  url: string;
  title: string;
  subtitle: string;
  isAudio: boolean;
  lyricsLrc?: string;
}

const PLAYBACK_SPEED_ENUMS: media.PlaybackSpeed[] = [
  media.PlaybackSpeed.SPEED_FORWARD_0_75_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_00_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_25_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_50_X,
  media.PlaybackSpeed.SPEED_FORWARD_2_00_X
];

const PLAYBACK_SPEED_LABELS: string[] = ['0.75x', '1.0x', '1.25x', '1.5x', '2.0x'];

function formatDurationMs(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) {
    return '00:00';
  }
  const totalSec = Math.floor(ms / 1000);
  const hrs = Math.floor(totalSec / 3600);
  const mins = Math.floor((totalSec % 3600) / 60);
  const secs = totalSec % 60;
  const pad = (n: number): string => String(n).padStart(2, '0');
  if (hrs > 0) {
    return `${hrs}:${pad(mins)}:${pad(secs)}`;
  }
  return `${pad(mins)}:${pad(secs)}`;
}

export type AudioStateListener = () => void;

/**
 * 鸿蒙全局持久化音频播控会话控制器（`AVPlayer` + `AVSession`）：
 * - 当全屏音乐界面收起至 `FloatingMiniMusicBar` 时保持底层 `AVPlayer` 不断流续播；
 * - 实时同步播放状态、进度与系统播控中心元数据，并在关闭音乐条或退出登录时安全释放。
 */
export class HarmonyAudioSession {
  private static instance: HarmonyAudioSession | null = null;
  private player: media.AVPlayer | null = null;
  private session: avSession.AVSession | null = null;
  private activeUrl: string = '';
  private activeReq: HarmonyPlaybackRequest | null = null;
  private playing: boolean = false;
  private posMs: number = 0;
  private durMs: number = 0;
  private speedIdx: number = 1;
  private listeners: AudioStateListener[] = [];

  /** 获取全局音频会话单例。 */
  static shared(): HarmonyAudioSession {
    if (!HarmonyAudioSession.instance) {
      HarmonyAudioSession.instance = new HarmonyAudioSession();
    }
    return HarmonyAudioSession.instance;
  }

  subscribe(fn: AudioStateListener): void {
    if (!this.listeners.includes(fn)) {
      this.listeners.push(fn);
    }
  }

  unsubscribe(fn: AudioStateListener): void {
    this.listeners = this.listeners.filter((x: AudioStateListener) => x !== fn);
  }

  isPlaying(): boolean {
    return this.playing;
  }

  positionMs(): number {
    return this.posMs;
  }

  durationMs(): number {
    return this.durMs;
  }

  progressPercent(): number {
    if (this.durMs <= 0) { return 0; }
    return Math.min(100, Math.max(0, (this.posMs / this.durMs) * 100));
  }

  speedIndex(): number {
    return this.speedIdx;
  }

  private notify(): void {
    AppStorage.setOrCreate('mp_audio_is_playing', this.playing);
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i]();
      } catch {
        // ignore listener exception
      }
    }
  }

  /** 启动或无缝接续指定音频流。 */
  async startOrAttach(req: HarmonyPlaybackRequest, hostCtx?: common.BaseContext): Promise<void> {
    if (this.player && this.activeUrl === req.url && req.url.length > 0) {
      this.activeReq = req;
      if (!this.playing) {
        try {
          await this.player.play();
          this.playing = true;
        } catch {
          // ignore
        }
      }
      this.notify();
      return;
    }

    await this.releasePlayerOnly();
    this.activeUrl = req.url;
    this.activeReq = req;
    this.posMs = 0;
    this.durMs = 0;
    this.playing = true;
    this.notify();

    if (hostCtx) {
      this.ensureAvSession(hostCtx, req).catch(() => {});
    }

    try {
      const av = await media.createAVPlayer();
      this.player = av;
      av.on('durationUpdate', (dur: number) => {
        this.durMs = Math.max(0, dur);
        this.notify();
      });
      av.on('timeUpdate', (time: number) => {
        this.posMs = Math.max(0, time);
        this.notify();
      });
      av.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          av.prepare().catch(() => {});
        } else if (state === 'prepared') {
          if (this.durMs <= 0 && av.duration > 0) {
            this.durMs = av.duration;
          }
          av.setSpeed(PLAYBACK_SPEED_ENUMS[this.speedIdx]);
          av.play().catch(() => {});
          this.playing = true;
          this.syncAvSessionPlaybackState();
          this.notify();
        } else if (state === 'playing') {
          this.playing = true;
          this.syncAvSessionPlaybackState();
          this.notify();
        } else if (state === 'paused' || state === 'completed' || state === 'stopped') {
          this.playing = false;
          this.syncAvSessionPlaybackState();
          this.notify();
        }
      });
      av.url = req.url;
    } catch {
      // 无解码器或预览环境保持 UI 状态可控
    }
  }

  private async ensureAvSession(ctx: common.BaseContext, req: HarmonyPlaybackRequest): Promise<void> {
    try {
      if (!this.session) {
        const s = await avSession.createAVSession(ctx, 'MoviePilotAudio', 'audio');
        s.on('play', () => { this.setPlaying(true); });
        s.on('pause', () => { this.setPlaying(false); });
        await s.activate();
        this.session = s;
      }
      await this.session.setAVMetadata({
        assetId: req.url || 'mp_audio',
        title: req.title,
        artist: req.subtitle
      });
      this.syncAvSessionPlaybackState();
    } catch {
      // 模拟器或受限上下文忽略 AVSession 错误
    }
  }

  private syncAvSessionPlaybackState(): void {
    if (!this.session) { return; }
    try {
      this.session.setAVPlaybackState({
        state: this.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: this.posMs,
          updateTime: Date.now()
        }
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  /** 切换音频播放/暂停。 */
  togglePlayPause(): void {
    this.setPlaying(!this.playing);
  }

  setPlaying(nextPlaying: boolean): void {
    this.playing = nextPlaying;
    if (this.player) {
      try {
        if (nextPlaying) {
          this.player.play().catch(() => {});
        } else {
          this.player.pause().catch(() => {});
        }
      } catch {
        // ignore
      }
    }
    this.syncAvSessionPlaybackState();
    this.notify();
  }

  /** 按百分比定位播放进度。 */
  seekPercent(pct: number): void {
    if (this.durMs <= 0) { return; }
    const targetMs = Math.round((Math.min(100, Math.max(0, pct)) / 100) * this.durMs);
    this.posMs = targetMs;
    if (this.player) {
      try {
        this.player.seek(targetMs);
      } catch {
        // ignore
      }
    }
    this.notify();
  }

  /** 循环切换音频倍速。 */
  cycleSpeed(): number {
    this.speedIdx = (this.speedIdx + 1) % PLAYBACK_SPEED_ENUMS.length;
    if (this.player) {
      try {
        this.player.setSpeed(PLAYBACK_SPEED_ENUMS[this.speedIdx]);
      } catch {
        // ignore
      }
    }
    this.notify();
    return this.speedIdx;
  }

  private async releasePlayerOnly(): Promise<void> {
    const prev = this.player;
    this.player = null;
    if (prev) {
      try {
        await prev.release();
      } catch {
        // ignore
      }
    }
  }

  /** 彻底停止并释放后台音频与 AVSession。 */
  stopAndRelease(): void {
    this.playing = false;
    this.activeUrl = '';
    this.activeReq = null;
    this.posMs = 0;
    this.durMs = 0;
    this.releasePlayerOnly();
    const sess = this.session;
    this.session = null;
    if (sess) {
      try {
        sess.destroy().catch(() => {});
      } catch {
        // ignore
      }
    }
    this.notify();
  }
}

/**
 * 鸿蒙原生全格式音视频播放器（`AVPlayer` + `XComponent` + `HarmonyAudioSession`）：
 * - 音频模式接入持久化 `HarmonyAudioSession`，收起至迷你音乐条不断流；
 * - 真实绑定 `timeUpdate`、`durationUpdate`、`Slider.onChange` 拖动 `seek()` 与 `setSpeed()` 倍速控制。
 */
@Component
export struct NativeMediaPlayerView {
  @StorageLink('mp_window_width_vp') windowWidthVp: number = 412;
  @StorageLink('mp_window_height_vp') windowHeightVp: number = 892;
  @StorageLink('mp_safe_top_vp') safeTopVp: number = 38;
  @StorageLink('mp_safe_bottom_vp') safeBottomVp: number = 16;
  @StorageLink('mp_safe_left_vp') safeLeftVp: number = 0;
  @StorageLink('mp_safe_right_vp') safeRightVp: number = 0;
  @Prop request: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: false };
  @Prop isLandscape: boolean = false;
  @State private isPlaying: boolean = true;
  @State private controlsVisible: boolean = true;
  @State private isLocked: boolean = false;
  @State private progress: number = 0;
  @State private positionMs: number = 0;
  @State private durationMs: number = 0;
  @State private isDraggingSlider: boolean = false;
  @State private speedIndex: number = 1;
  @State private subtitleEnabled: boolean = true;
  @State private videoAspect: number = 16 / 9;
  @State private videoFillMode: boolean = false;
  private orientationOverridden: boolean = false;
  private xComponentController: XComponentController = new XComponentController();
  private videoPlayer: media.AVPlayer | null = null;
  private audioListener: AudioStateListener = () => {
    this.syncFromAudioSession();
  };
  onClose: () => void = () => {};
  onMinimizeToMiniBar: () => void = () => {};

  private effectiveLandscape(): boolean {
    if (this.windowWidthVp > 0 && this.windowHeightVp > 0) {
      return this.windowWidthVp > this.windowHeightVp;
    }
    return this.isLandscape;
  }

  private isShortLandscape(): boolean {
    return this.effectiveLandscape() && this.windowHeightVp > 0 && this.windowHeightVp < 480;
  }

  private applyWindowOrientation(target: window.Orientation): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) { return; }
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setPreferredOrientation(target).catch(() => {});
      }).catch(() => {});
    } catch {
      // ignore orientation error on unsupported targets
    }
  }

  private handleToggleFullscreenOrientation(): void {
    if (this.isLocked) { return; }
    this.orientationOverridden = true;
    if (this.effectiveLandscape()) {
      this.applyWindowOrientation(window.Orientation.PORTRAIT);
    } else {
      this.applyWindowOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    }
  }

  private handleToggleScreenLock(): void {
    const nextLocked = !this.isLocked;
    this.isLocked = nextLocked;
    if (nextLocked) {
      this.orientationOverridden = true;
      this.applyWindowOrientation(
        this.effectiveLandscape()
          ? window.Orientation.AUTO_ROTATION_LANDSCAPE
          : window.Orientation.PORTRAIT
      );
    } else {
      this.orientationOverridden = false;
      this.applyWindowOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
    }
  }

  private isWiderThanVideo(): boolean {
    const vw = Math.max(1, this.windowWidthVp);
    const vh = Math.max(1, this.windowHeightVp);
    const aspect = this.videoAspect > 0.1 ? this.videoAspect : (16 / 9);
    return (vw / vh) > aspect;
  }

  private videoSurfaceWidth(): Length {
    const aspect = this.videoAspect > 0.1 ? this.videoAspect : (16 / 9);
    const wider = this.isWiderThanVideo();
    if (!this.videoFillMode) {
      if (wider && this.windowHeightVp > 0) {
        return Math.round(this.windowHeightVp * aspect);
      }
      return '100%';
    }
    if (!wider && this.windowHeightVp > 0) {
      return Math.round(this.windowHeightVp * aspect);
    }
    return '100%';
  }

  private videoSurfaceHeight(): Length {
    const aspect = this.videoAspect > 0.1 ? this.videoAspect : (16 / 9);
    const wider = this.isWiderThanVideo();
    if (!this.videoFillMode) {
      if (!wider && this.windowWidthVp > 0) {
        return Math.round(this.windowWidthVp / aspect);
      }
      return '100%';
    }
    if (wider && this.windowWidthVp > 0) {
      return Math.round(this.windowWidthVp / aspect);
    }
    return '100%';
  }

  aboutToAppear(): void {
    if (this.request.isAudio) {
      const audioSess = HarmonyAudioSession.shared();
      audioSess.subscribe(this.audioListener);
      const ctx = this.getUIContext().getHostContext() ?? undefined;
      audioSess.startOrAttach(this.request, ctx);
      this.syncFromAudioSession();
    } else {
      this.initVideoPlayer();
    }
  }

  aboutToDisappear(): void {
    if (this.orientationOverridden || this.isLocked) {
      this.applyWindowOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
      this.orientationOverridden = false;
    }
    if (this.request.isAudio) {
      // 仅解绑 UI 监听，保持后台音频在迷你音乐条中无缝续播
      HarmonyAudioSession.shared().unsubscribe(this.audioListener);
    } else if (this.videoPlayer) {
      try {
        this.videoPlayer.release().catch(() => {});
      } catch {
        // ignore
      }
      this.videoPlayer = null;
    }
  }

  private syncFromAudioSession(): void {
    const sess = HarmonyAudioSession.shared();
    this.isPlaying = sess.isPlaying();
    this.durationMs = sess.durationMs();
    this.speedIndex = sess.speedIndex();
    if (!this.isDraggingSlider) {
      this.positionMs = sess.positionMs();
      this.progress = sess.progressPercent();
    }
  }

  private async initVideoPlayer(): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      this.videoPlayer = player;
      player.on('videoSizeChange', (w: number, h: number) => {
        if (w > 0 && h > 0) {
          this.videoAspect = w / h;
        }
      });
      player.on('durationUpdate', (dur: number) => {
        this.durationMs = Math.max(0, dur);
      });
      player.on('timeUpdate', (time: number) => {
        if (!this.isDraggingSlider) {
          this.positionMs = Math.max(0, time);
          if (this.durationMs > 0) {
            this.progress = Math.min(100, Math.max(0, (this.positionMs / this.durationMs) * 100));
          }
        }
      });
      player.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          const surfaceId = this.xComponentController.getXComponentSurfaceId();
          if (surfaceId) {
            player.surfaceId = surfaceId;
          }
          player.prepare().catch(() => {});
        } else if (state === 'prepared') {
          if (this.durationMs <= 0 && player.duration > 0) {
            this.durationMs = player.duration;
          }
          player.setSpeed(PLAYBACK_SPEED_ENUMS[this.speedIndex]);
          player.play().catch(() => {});
          this.isPlaying = true;
        } else if (state === 'playing') {
          this.isPlaying = true;
        } else if (state === 'paused' || state === 'completed') {
          this.isPlaying = false;
        }
      });
      player.url = this.request.url;
    } catch {
      // 预览或无硬件解码环境保持界面可交互
    }
  }

  private handleTogglePlay(): void {
    if (this.request.isAudio) {
      HarmonyAudioSession.shared().togglePlayPause();
      return;
    }
    this.isPlaying = !this.isPlaying;
    if (this.videoPlayer) {
      if (this.isPlaying) {
        this.videoPlayer.play().catch(() => {});
      } else {
        this.videoPlayer.pause().catch(() => {});
      }
    }
  }

  private handleSliderChange(val: number, mode: SliderChangeMode): void {
    this.progress = val;
    if (this.durationMs > 0) {
      this.positionMs = Math.round((val / 100) * this.durationMs);
    }
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isDraggingSlider = true;
      return;
    }
    this.isDraggingSlider = false;
    if (this.request.isAudio) {
      HarmonyAudioSession.shared().seekPercent(val);
    } else if (this.videoPlayer && this.durationMs > 0) {
      const targetMs = Math.round((val / 100) * this.durationMs);
      try {
        this.videoPlayer.seek(targetMs);
      } catch {
        // ignore seek error
      }
    }
  }

  private handleCycleSpeed(): void {
    if (this.request.isAudio) {
      this.speedIndex = HarmonyAudioSession.shared().cycleSpeed();
      return;
    }
    this.speedIndex = (this.speedIndex + 1) % PLAYBACK_SPEED_ENUMS.length;
    if (this.videoPlayer) {
      try {
        this.videoPlayer.setSpeed(PLAYBACK_SPEED_ENUMS[this.speedIndex]);
      } catch {
        // ignore
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.request.isAudio) {
        XComponent({
          id: 'mp_harmony_video_surface',
          type: XComponentType.SURFACE,
          controller: this.xComponentController
        })
          .width(this.videoSurfaceWidth())
          .height(this.videoSurfaceHeight())
          .backgroundColor(Color.Black)
      } else if (this.isShortLandscape()) {
        Row() {
          Row({ space: 16 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(40)
                .fontColor(['#317AF7'])
            }
            .width(96)
            .height(96)
            .borderRadius(20)
            .backgroundColor('#22FFFFFF')

            Column({ space: 6 }) {
              Text(this.request.title)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.request.subtitle)
                .fontSize(12.5)
                .fontColor('#B8FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('50%')
          .padding({ left: Math.max(24, 16 + this.safeLeftVp), right: 44, bottom: 20 })
          Blank()
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .linearGradient({ angle: 160, colors: [['#13203A', 0], ['#1D3461', 0.55], ['#0B0E14', 1]] })
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )
      } else {
        Column({ space: 14 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(64)
              .fontColor(['#317AF7'])
          }
          .width(200)
          .height(200)
          .borderRadius(28)
          .backgroundColor('#22FFFFFF')
          Text(this.request.title)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .padding({ left: 24, right: 24 })
          Text(this.request.subtitle).fontSize(13).fontColor('#B8FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .linearGradient({ angle: 160, colors: [['#13203A', 0], ['#1D3461', 0.55], ['#0B0E14', 1]] })
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )
      }

      if (this.effectiveLandscape() && this.controlsVisible) {
        Stack() {
          SymbolGlyph($r(this.isLocked ? 'sys.symbol.lock_fill' : 'sys.symbol.lock_open_fill'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#70000000')
        .align(Alignment.End)
        .position({ right: 20 + this.safeRightVp, y: '44%' })
        .accessibilityText(this.isLocked ? '解锁屏幕控制' : '锁定屏幕控制')
        .onClick(() => this.handleToggleScreenLock())
      }

      if (this.controlsVisible && !this.isLocked) {
        Column() {
          Row({ space: 10 }) {
            Stack() {
              SymbolGlyph($r(this.request.isAudio ? 'sys.symbol.chevron_down' : 'sys.symbol.chevron_left'))
                .fontSize(22)
                .fontColor([Color.White])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor('#42000000')
            .accessibilityText(this.request.isAudio ? '收起至迷你播放条' : '返回')
            .onClick(() => this.request.isAudio ? this.onMinimizeToMiniBar() : this.onClose())

            Text(this.request.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Stack() {
              SymbolGlyph($r('sys.symbol.full_screen_tv'))
                .fontSize(20)
                .fontColor([Color.White])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor('#42000000')
            .accessibilityText(this.effectiveLandscape() ? '切换竖屏播放' : '切换横屏全屏播放')
            .onClick(() => this.handleToggleFullscreenOrientation())
          }
          .width('100%')
          .padding({
            left: 16 + this.safeLeftVp,
            right: 16 + this.safeRightVp,
            top: Math.max(12, this.safeTopVp + 4),
            bottom: this.isShortLandscape() ? 6 : 12
          })

          Blank()

          Stack() {
            SymbolGlyph($r(this.isPlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
              .fontSize(32)
              .fontColor([Color.White])
          }
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor('#66000000')
          .accessibilityText(this.isPlaying ? '暂停' : '播放')
          .onClick(() => this.handleTogglePlay())

          Blank()

          Column({ space: this.isShortLandscape() ? 2 : 6 }) {
            Row() {
              Text(formatDurationMs(this.positionMs)).fontSize(11.5).fontColor('#CCFFFFFF')
              Blank()
              Text(formatDurationMs(this.durationMs)).fontSize(11.5).fontColor('#CCFFFFFF')
            }.width('100%')

            Slider({ value: this.progress, min: 0, max: 100 })
              .selectedColor('#317AF7')
              .trackColor('#44FFFFFF')
              .onChange((val: number, mode: SliderChangeMode) => this.handleSliderChange(val, mode))

            Row() {
              Row({ space: 18 }) {
                SymbolGlyph($r('sys.symbol.AI_subtitles'))
                  .fontSize(20)
                  .fontColor([this.subtitleEnabled ? '#317AF7' : Color.White])
                  .onClick(() => { this.subtitleEnabled = !this.subtitleEnabled; })
                SymbolGlyph($r('sys.symbol.waveform'))
                  .fontSize(20)
                  .fontColor([Color.White])
              }
              Blank()
              Row({ space: 14 }) {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.aspect_ratio'))
                    .fontSize(20)
                    .fontColor([this.videoFillMode ? '#317AF7' : Color.White])
                  if (this.videoFillMode) {
                    Text('铺满')
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#317AF7')
                  }
                }
                .accessibilityText(this.videoFillMode ? '切换原始比例适应' : '切换铺满裁切模式')
                .onClick(() => { this.videoFillMode = !this.videoFillMode; })

                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.timer'))
                    .fontSize(19)
                    .fontColor([this.speedIndex !== 1 ? '#317AF7' : Color.White])
                  Text(PLAYBACK_SPEED_LABELS[this.speedIndex])
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.speedIndex !== 1 ? '#317AF7' : Color.White)
                }
                .onClick(() => this.handleCycleSpeed())
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding({
            left: 18 + this.safeLeftVp,
            right: 18 + this.safeRightVp,
            bottom: Math.max(14, this.safeBottomVp + (this.isShortLandscape() ? 4 : 10))
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
    )
    .onClick(() => { this.controlsVisible = !this.controlsVisible; })
  }
}

/** 鸿蒙底栏上方流体光感悬浮迷你音乐条（接入 `HarmonyAudioSession` 后台续播）。 */
@Component
export struct FloatingMiniMusicBar {
  @Prop request: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: true };
  @Prop isPlaying: boolean = true;
  onTogglePlay: () => void = () => {};
  onExpand: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.music')).fontSize(20).fontColor(['#317AF7'])
      }
      .width(38).height(38).borderRadius(10).backgroundColor('#33317AF7')
      Column({ space: 2 }) {
        Text(this.request.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.request.subtitle).fontSize(11).fontColor('#A8FFFFFF').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => this.onExpand())

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r(this.isPlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
          .fontSize(18).fontColor([Color.White])
      }
      .width(34).height(34)
      .backgroundColor('#24FFFFFF')
      .onClick(() => this.onTogglePlay())

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15).fontColor(['#CCFFFFFF'])
      }
      .width(30).height(30)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.onClose())
    }
    .width('92%')
    .constraintSize({ maxWidth: 480 })
    .padding({ left: 12, right: 10, top: 8, bottom: 8 })
    .borderRadius(20)
    .backgroundColor('#E01A1A22')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 0.6, color: '#24FFFFFF', radius: 20 })
  }
}
