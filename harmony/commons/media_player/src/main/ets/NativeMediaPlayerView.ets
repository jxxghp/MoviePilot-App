import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import {
  PlaybackScaleMode,
  PLAYBACK_SCALE_MODES,
  PlaybackPreferencesStore
} from '@moviepilot/design_system';
import {
  RustCoreBridge,
  MoviePilotRepository,
  MpRemoteImage,
  PlaybackRouteCandidate,
  HarmonyPlaybackSyncTracker,
  HarmonyPlaybackProgressReporter,
  HarmonyPlaybackRouteResolver,
  MpDanmakuEpisodeCandidate,
  MpDanmakuAnimeSearchItem,
  MpDanmakuBangumi,
  MpDanmakuMatchResponse,
  MpDanmakuCommentsRaw
} from '@moviepilot/core_rust_bridge';
import {
  HarmonySubtitleOption,
  HarmonyAudioTrackOption,
  HarmonyQueueItem,
  HarmonyRepeatMode,
  HarmonyPlaybackRequest,
  HARMONY_SPEED_ENUMS,
  HARMONY_SPEED_VALUES,
  HARMONY_SPEED_LABELS,
  DEFAULT_AUDIO_SPEED_INDEX,
  BOOST_2X_SPEED_INDEX,
  formatMediaDurationMs,
  formatSignedDeltaSec,
  buildPlaybackResumeKey,
  isChineseLanguageTrack,
  mapExternalSubtitlesToOptions
} from './MediaPlayerModels';
import {
  LyricLineCue,
  SubtitleCue,
  parseSubtitleText,
  findActiveSubtitleText
} from './SubtitleAndLyricsParser';
import { HarmonyPipController } from './HarmonyPipController';
import {
  HarmonyAudioSession,
  AudioStateListener,
  OpenedLocalMediaFd,
  attachSourceToAvPlayer,
  closeLocalPlaybackFd
} from './HarmonyAudioSession';
import {
  HarmonyEnhancedPlayerController,
  EnhancedLoadConfig
} from './engine/HarmonyEnhancedPlayerController';
import {
  launchHarmonyExternalPlayer,
  resolveSafeExternalUri
} from './engine/HarmonyExternalPlayerLauncher';
import { DanmakuPreferencesStore } from './danmaku/DanmakuPreferences';
import { HarmonyDanmakuController } from './danmaku/DanmakuController';
import { HarmonyDanmakuOverlay } from './danmaku/DanmakuOverlay';

export {
  HarmonyPlaybackRequest,
  HarmonySubtitleOption,
  HarmonyAudioTrackOption,
  HarmonyQueueItem,
  HarmonyRepeatMode,
  HarmonyAudioSession,
  AudioStateListener
};

type PlayerSheetKind = 'none' | 'subtitles' | 'audioTracks' | 'speed' | 'queue' | 'engine' | 'cast' | 'danmakuSettings' | 'danmakuMatch';
type PanGestureAxisMode = 'undecided' | 'scrub' | 'brightness' | 'volume';

/**
 * 鸿蒙原生全格式影院视频与全屏音乐播放器（`AVPlayer` + `XComponent` + `PiPWindow` + `HarmonyAudioSession`）：
 * - 视频影院支持：自适应/铺满裁剪/拉伸三档比例、内封+外挂字幕（SRT/VTT/ASS/SSA）与多音轨切换、6 档倍速、选集连播与 5 秒下一集浮卡、断点续播胶囊与 15s 进度回传、画中画（PiP）、双击快退/暂停/快进、水平滑动预览跳转、左半屏亮度/右半屏音量手势、长按 2.0x 倍速与横竖屏防误触锁；
 * - 音乐舞台支持：高清封面与高斯模糊背景、同步滚动可点击跳转的 LRC 歌词列表、4 种循环模式、6 档倍速与播放队列面板。
 */
@Component
export struct NativeMediaPlayerView {
  @StorageLink('mp_window_width_vp') windowWidthVp: number = 412;
  @StorageLink('mp_window_height_vp') windowHeightVp: number = 892;
  @StorageLink('mp_safe_top_vp') safeTopVp: number = 38;
  @StorageLink('mp_safe_bottom_vp') safeBottomVp: number = 16;
  @StorageLink('mp_safe_left_vp') safeLeftVp: number = 0;
  @StorageLink('mp_safe_right_vp') safeRightVp: number = 0;
  @StorageLink('mp_playback_auto_pip') @Watch('onAutoPipChanged') autoPipEnabled: boolean = true;
  @StorageLink(PlaybackPreferencesStore.KEY_SUBTITLE_SCALE) subtitleScalePref: number = 1.0;

  @Prop request: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: false };
  @Prop isLandscape: boolean = false;

  @State private activeVideoReq: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: false };
  private didFallbackToProxy: boolean = false;
  @State private activeEngineKind: string = 'native';
  private didAutoFallbackEngine: boolean = false;
  private suppressStopForEngineSwitch: boolean = false;
  private enhancedPlayer: HarmonyEnhancedPlayerController = new HarmonyEnhancedPlayerController();
  private ijkSurfaceId: string = 'mp_harmony_ijk_surface';
  @State private activeRouteKind: string = '';
  @State private activeRouteServer: string = '';
  @State private displayTitle: string = '';
  @State private displaySubtitle: string = '';
  @State private displayArtworkUrl: string = '';
  @State private localCoverPixelMap: image.PixelMap | null = null;

  @State private isPlaying: boolean = true;
  @State private isBuffering: boolean = false;
  @State private controlsVisible: boolean = true;
  @State private isLocked: boolean = false;
  @State private showRemainingTime: boolean = false;

  @State private progress: number = 0;
  @State private positionMs: number = 0;
  @State private durationMs: number = 0;
  @State private isDraggingSlider: boolean = false;

  @State private speedIndex: number = DEFAULT_AUDIO_SPEED_INDEX;
  @State private isLongPressBoosting: boolean = false;
  private savedSpeedBeforeBoost: number = DEFAULT_AUDIO_SPEED_INDEX;

  // 视频比例与画布尺寸
  @State private scaleMode: PlaybackScaleMode = 'fit';
  @State private containerW: number = 0;
  @State private containerH: number = 0;
  @State private videoW: number = 1920;
  @State private videoH: number = 1080;

  // 字幕与音轨状态
  @State private subtitleOptions: HarmonySubtitleOption[] = [];
  @State private selectedSubId: string = 'off';
  @State private activeSubIsExternal: boolean = false;
  private activeEmbeddedSubTrackIndex: number = -1;
  private externalSubCues: SubtitleCue[] = [];
  private externalSubCueCache: Map<string, SubtitleCue[]> = new Map<string, SubtitleCue[]>();
  private subtitleLoadSeq: number = 0;
  @State private isSubtitleLoading: boolean = false;
  @State private failedSubId: string = '';
  @State private activeSubtitleText: string = '';

  @State private audioTrackOptions: HarmonyAudioTrackOption[] = [];
  @State private selectedAudioTrackIndex: number = -1;

  // 视频选集与下一集浮卡状态
  @State private videoQueue: HarmonyQueueItem[] = [];
  @State private videoQueueIdx: number = 0;
  @State private showUpNextCard: boolean = false;
  @State private upNextCountdownSec: number = 5;
  private upNextDismissedForCurrent: boolean = false;
  private upNextCountdownTimer: number = -1;

  // 断点续播提示胶囊
  @State private resumeBannerText: string = '';
  private resumeBannerTimer: number = -1;

  // 手势 HUD 状态
  @State private hudVisible: boolean = false;
  @State private hudSymbolName: string = 'play_fill';
  @State private hudText: string = '';
  private hudHideTimer: number = -1;

  private panMode: PanGestureAxisMode = 'undecided';
  private scrubStartMs: number = 0;
  private scrubTargetMs: number = 0;
  private gestureBrightness: number = 0.55;
  private brightnessStart: number = 0.55;
  private gestureVolume: number = 1.0;
  private volumeStart: number = 1.0;
  private lastTapLocalX: number = -1;

  // 画中画状态
  @State private pipSupported: boolean = false;
  @State private isPipActive: boolean = false;
  private pipController: HarmonyPipController = new HarmonyPipController();
  private viewDisappeared: boolean = false;

  // 弹幕引擎与交互状态
  private danmakuController: HarmonyDanmakuController = new HarmonyDanmakuController();
  @State private danmakuVisible: boolean = DanmakuPreferencesStore.getEnabled();
  @State private danmakuConfigVersion: number = 0;
  private danmakuRawJson: string = '';
  @State private danmakuEpisodeId: number = 0;
  private danmakuAnimeId: number | undefined = undefined;
  @State private danmakuAnimeTitle: string = '';
  @State private danmakuEpisodeTitle: string = '';
  @State private danmakuCandidates: MpDanmakuEpisodeCandidate[] = [];
  @State private danmakuFromBinding: boolean = false;
  @State private danmakuShiftMs: number = 0;
  @State private danmakuTotalCount: number = 0;
  @State private danmakuOpacity: number = DanmakuPreferencesStore.getOpacity();
  @State private danmakuFontScale: number = DanmakuPreferencesStore.getFontScale();
  @State private danmakuSpeed: number = DanmakuPreferencesStore.getSpeed();
  @State private danmakuAreaRatio: number = DanmakuPreferencesStore.getAreaRatio();
  @State private danmakuMaxOnScreen: number = DanmakuPreferencesStore.getMaxOnScreen();
  @State private danmakuAllowScroll: boolean = DanmakuPreferencesStore.getAllowScroll();
  @State private danmakuAllowTop: boolean = DanmakuPreferencesStore.getAllowTop();
  @State private danmakuAllowBottom: boolean = DanmakuPreferencesStore.getAllowBottom();
  @State private danmakuAllowColor: boolean = DanmakuPreferencesStore.getAllowColor();
  @State private danmakuMergeDup: boolean = DanmakuPreferencesStore.getMergeDuplicates();
  @State private danmakuBlockKeywords: string[] = DanmakuPreferencesStore.getBlockKeywords();
  @State private danmakuKeywordDraft: string = '';
  @State private danmakuSheetBusy: boolean = false;
  @State private danmakuSheetFeedback: string = '';
  @State private danmakuSearchQuery: string = '';
  @State private danmakuSearchLoading: boolean = false;
  @State private danmakuSearchError: string = '';
  @State private danmakuSearchResults: MpDanmakuAnimeSearchItem[] = [];
  @State private danmakuActiveBangumi: MpDanmakuBangumi | null = null;

  // 音乐舞台状态
  @State private showLyricsStage: boolean = false;
  @State private lyricCues: LyricLineCue[] = [];
  @State private plainLyricsLines: string[] = [];
  @State private activeLyricIdx: number = -1;
  @State private audioRepeatMode: HarmonyRepeatMode = 'sequence';
  @State private audioQueue: HarmonyQueueItem[] = [];
  @State private audioQueueIdx: number = 0;
  private lyricsScroller: Scroller = new Scroller();
  private lastScrolledLyricIdx: number = -1;

  // 统一半模态面板状态
  @State private showPlayerSheet: boolean = false;
  @State private activeSheetKind: PlayerSheetKind = 'none';

  private orientationOverridden: boolean = false;
  private xComponentController: XComponentController = new XComponentController();
  private videoPlayer: media.AVPlayer | null = null;
  private openedVideoFd: OpenedLocalMediaFd | null = null;
  private videoLoadGeneration: number = 0;
  private videoLoadFailed: boolean = false;
  private controlsHideTimer: number = -1;
  private videoProgressTimer: number = -1;
  private interruptedVideoWhilePlaying: boolean = false;

  private videoSyncTracker: HarmonyPlaybackSyncTracker = new HarmonyPlaybackSyncTracker();
  private videoStartedSent: boolean = false;
  private videoProgressTickCount: number = 0;

  private audioListener: AudioStateListener = () => {
    this.syncFromAudioSession();
  };

  onClose: () => void = () => {};
  onMinimizeToMiniBar: () => void = () => {};

  private onAutoPipChanged(): void {
    if (!this.request.isAudio) {
      this.pipController.setAutoStart(this.autoPipEnabled);
    }
  }

  private effectiveLandscape(): boolean {
    if (this.windowWidthVp > 0 && this.windowHeightVp > 0) {
      return this.windowWidthVp > this.windowHeightVp;
    }
    return this.isLandscape;
  }

  private isShortLandscape(): boolean {
    return this.effectiveLandscape() && this.windowHeightVp > 0 && this.windowHeightVp < 480;
  }

  private effectiveAreaWidth(): number {
    return this.containerW > 10 ? this.containerW : Math.max(1, this.windowWidthVp);
  }

  private effectiveAreaHeight(): number {
    return this.containerH > 10 ? this.containerH : Math.max(1, this.windowHeightVp);
  }

  private applyWindowOrientation(target: window.Orientation): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) { return; }
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setPreferredOrientation(target).catch(() => {});
      }).catch(() => {});
    } catch {
      // ignore orientation error
    }
  }

  private syncImmersiveSystemBars(showBars: boolean): void {
    if (this.request.isAudio) {
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) { return; }
      window.getLastWindow(ctx).then((win: window.Window) => {
        if (showBars) {
          win.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {});
        } else {
          win.setWindowSystemBarEnable([]).catch(() => {});
        }
      }).catch(() => {});
    } catch {
      // ignore system bar error
    }
  }

  private restoreWindowBarsAndBrightness(): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) { return; }
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowSystemBarEnable(['status', 'navigation']).catch(() => {});
        win.setWindowBrightness(-1).catch(() => {});
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  private applyWindowBrightness(val: number): void {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx) { return; }
      window.getLastWindow(ctx).then((win: window.Window) => {
        win.setWindowBrightness(val).catch(() => {});
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  private resetControlsAutoHideTimer(): void {
    this.clearControlsAutoHideTimer();
    if (this.request.isAudio || !this.controlsVisible || !this.isPlaying || this.showPlayerSheet) {
      return;
    }
    this.controlsHideTimer = setTimeout(() => {
      if (!this.isDraggingSlider && !this.showPlayerSheet && this.isPlaying) {
        this.controlsVisible = false;
        this.syncImmersiveSystemBars(false);
      }
    }, 5000);
  }

  private clearControlsAutoHideTimer(): void {
    if (this.controlsHideTimer !== -1) {
      clearTimeout(this.controlsHideTimer);
      this.controlsHideTimer = -1;
    }
  }

  private toggleControlsVisibility(): void {
    const next = !this.controlsVisible;
    this.controlsVisible = next;
    this.syncImmersiveSystemBars(next);
    if (next) {
      this.resetControlsAutoHideTimer();
    } else {
      this.clearControlsAutoHideTimer();
    }
  }

  private showTransientHud(symbolName: string, text: string, durationMs: number = 1100): void {
    this.hudSymbolName = symbolName;
    this.hudText = text;
    this.hudVisible = true;
    if (this.hudHideTimer !== -1) {
      clearTimeout(this.hudHideTimer);
      this.hudHideTimer = -1;
    }
    if (durationMs > 0) {
      this.hudHideTimer = setTimeout(() => {
        this.hudVisible = false;
      }, durationMs);
    }
  }

  private hideHudSoon(delayMs: number = 500): void {
    if (this.hudHideTimer !== -1) {
      clearTimeout(this.hudHideTimer);
    }
    this.hudHideTimer = setTimeout(() => {
      this.hudVisible = false;
    }, delayMs);
  }

  private handleToggleFullscreenOrientation(): void {
    if (this.isLocked) { return; }
    this.orientationOverridden = true;
    if (this.effectiveLandscape()) {
      this.applyWindowOrientation(window.Orientation.PORTRAIT);
    } else {
      this.applyWindowOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
    }
    this.resetControlsAutoHideTimer();
  }

  private handleToggleScreenLock(): void {
    const nextLocked = !this.isLocked;
    this.isLocked = nextLocked;
    this.controlsVisible = true;
    if (nextLocked) {
      this.orientationOverridden = true;
      this.applyWindowOrientation(
        this.effectiveLandscape()
          ? window.Orientation.AUTO_ROTATION_LANDSCAPE
          : window.Orientation.PORTRAIT
      );
      this.showTransientHud('lock_fill', '屏幕已锁定');
    } else {
      this.orientationOverridden = false;
      this.applyWindowOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
      this.showTransientHud('lock_open_fill', '屏幕已解锁');
    }
    this.resetControlsAutoHideTimer();
  }

  private videoSurfaceWidth(): Length {
    if (this.scaleMode === 'fill' || this.scaleMode === 'stretch') {
      return '100%';
    }
    const cw = this.effectiveAreaWidth();
    const ch = this.effectiveAreaHeight();
    const aspect = (this.videoW > 0 && this.videoH > 0) ? (this.videoW / this.videoH) : (16 / 9);
    if (cw <= 0 || ch <= 0) {
      return '100%';
    }
    if ((cw / ch) > aspect) {
      return Math.max(1, Math.round(ch * aspect));
    }
    return Math.round(cw);
  }

  private videoSurfaceHeight(): Length {
    if (this.scaleMode === 'fill' || this.scaleMode === 'stretch') {
      return '100%';
    }
    const cw = this.effectiveAreaWidth();
    const ch = this.effectiveAreaHeight();
    const aspect = (this.videoW > 0 && this.videoH > 0) ? (this.videoW / this.videoH) : (16 / 9);
    if (cw <= 0 || ch <= 0) {
      return '100%';
    }
    if ((cw / ch) > aspect) {
      return Math.round(ch);
    }
    return Math.max(1, Math.round(cw / aspect));
  }

  private applyPlayerScaleType(): void {
    if (!this.videoPlayer) {
      return;
    }
    try {
      if (this.scaleMode === 'fill') {
        this.videoPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP;
      } else {
        this.videoPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
      }
    } catch {
      // ignore on initial/idle state
    }
  }

  private handleCycleScaleMode(): void {
    const idx = PLAYBACK_SCALE_MODES.indexOf(this.scaleMode);
    const next = PLAYBACK_SCALE_MODES[(idx + 1) % PLAYBACK_SCALE_MODES.length];
    this.scaleMode = next;
    PlaybackPreferencesStore.setScaleMode(next);
    this.applyPlayerScaleType();
    this.showTransientHud('aspect_ratio', `画面比例：${PlaybackPreferencesStore.scaleModeLabel(next)}`);
    this.resetControlsAutoHideTimer();
  }

  aboutToAppear(): void {
    this.viewDisappeared = false;
    this.displayTitle = this.request.title;
    this.displaySubtitle = this.request.subtitle;
    this.displayArtworkUrl = this.request.artworkUrl ?? '';

    if (this.request.isAudio) {
      const audioSess = HarmonyAudioSession.shared();
      audioSess.subscribe(this.audioListener);
      const ctx = this.getUIContext().getHostContext() ?? undefined;
      audioSess.startOrAttach(this.request, ctx);
      this.syncFromAudioSession();
      if ((this.request.lyricsLrc ?? '').length > 0 || (this.request.lyricsUrl ?? '').length > 0) {
        this.showLyricsStage = false;
      }
    } else {
      this.scaleMode = PlaybackPreferencesStore.getScaleMode();
      this.speedIndex = PlaybackPreferencesStore.speedToIndex(PlaybackPreferencesStore.getDefaultVideoSpeed());
      this.pipSupported = HarmonyPipController.isSupported();
      this.activeVideoReq = this.request;
      if (this.request.queue && this.request.queue.length > 0) {
        this.videoQueue = this.request.queue;
        this.videoQueueIdx = (this.request.queueIndex !== undefined &&
          this.request.queueIndex >= 0 &&
          this.request.queueIndex < this.request.queue.length)
          ? this.request.queueIndex
          : 0;
      } else {
        this.videoQueue = [];
        this.videoQueueIdx = 0;
      }
      this.initVideoPlayer(this.activeVideoReq);
      this.resetControlsAutoHideTimer();
    }
  }

  aboutToDisappear(): void {
    this.viewDisappeared = true;
    this.clearControlsAutoHideTimer();
    this.clearResumeBannerTimer();
    this.clearUpNextTimer();
    if (this.hudHideTimer !== -1) {
      clearTimeout(this.hudHideTimer);
      this.hudHideTimer = -1;
    }
    this.restoreWindowBarsAndBrightness();
    if (this.orientationOverridden || this.isLocked) {
      this.applyWindowOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED);
      this.orientationOverridden = false;
    }

    if (this.request.isAudio) {
      HarmonyAudioSession.shared().unsubscribe(this.audioListener);
    } else {
      if (this.pipController.isActive()) {
        // 画中画小窗运行中：保持底层 AVPlayer 不断流续播，待小窗关闭时再释放
        return;
      }
      this.dispatchVideoSync('stop', true);
      this.pipController.destroy().catch(() => {});
      this.releaseVideoPlayerResources();
    }
  }

  private syncFromAudioSession(): void {
    const sess = HarmonyAudioSession.shared();
    const curReq = sess.currentRequest();
    if (curReq) {
      this.displayTitle = curReq.title;
      this.displaySubtitle = curReq.subtitle;
      this.displayArtworkUrl = curReq.artworkUrl ?? '';
      this.activeRouteKind = curReq.activeRouteKind ?? '';
      this.activeRouteServer = curReq.server ?? '';
    }
    this.localCoverPixelMap = sess.coverPixelMap();
    this.isPlaying = sess.isPlaying();
    this.isBuffering = sess.isBuffering();
    this.durationMs = sess.durationMs();
    this.speedIndex = sess.speedIndex();
    this.audioRepeatMode = sess.getRepeatMode();
    this.audioQueue = sess.queueItems();
    this.audioQueueIdx = sess.currentQueueIndex();
    this.lyricCues = sess.lyricsCues();
    this.plainLyricsLines = sess.plainLyrics();
    const nextLyricIdx = sess.activeLyricIndex();
    this.activeLyricIdx = nextLyricIdx;
    if (this.showLyricsStage && nextLyricIdx >= 0 && nextLyricIdx !== this.lastScrolledLyricIdx) {
      this.lastScrolledLyricIdx = nextLyricIdx;
      try {
        this.lyricsScroller.scrollToIndex(Math.max(0, nextLyricIdx - 2), true);
      } catch {
        // ignore scroller before mount
      }
    }
    if (!this.isDraggingSlider) {
      this.positionMs = sess.positionMs();
      this.progress = sess.progressPercent();
    }
  }

  private releaseVideoPlayerResources(): void {
    this.stopVideoProgressTimer();
    if (!this.suppressStopForEngineSwitch) {
      this.danmakuController.clearAll();
    }
    this.enhancedPlayer.release();
    const prev = this.videoPlayer;
    this.videoPlayer = null;
    if (prev) {
      try {
        prev.release().catch(() => {});
      } catch {
        // ignore
      }
    }
    const fdHandle = this.openedVideoFd;
    this.openedVideoFd = null;
    closeLocalPlaybackFd(fdHandle);
  }

  private startVideoProgressTimer(): void {
    if (this.videoProgressTimer !== -1) {
      return;
    }
    this.videoProgressTimer = setInterval(() => {
      if (this.request.isAudio || !this.activeVideoReq) {
        this.stopVideoProgressTimer();
        return;
      }
      this.videoProgressTickCount += 1;
      if (this.videoProgressTickCount % 10 === 0 && this.durationMs > 0) {
        const resumeKey = buildPlaybackResumeKey(this.activeVideoReq);
        if (resumeKey.length > 0) {
          PlaybackPreferencesStore.saveLocalResumeMs(resumeKey, this.positionMs, this.durationMs);
        }
      }
      this.dispatchVideoSync('tick', !this.isPlaying);
    }, 1000);
  }

  private stopVideoProgressTimer(): void {
    if (this.videoProgressTimer !== -1) {
      clearInterval(this.videoProgressTimer);
      this.videoProgressTimer = -1;
    }
  }

  private resolveCurrentSubtitleStreamIndex(): number | null {
    if (this.selectedSubId === 'off') {
      return -1;
    }
    if (this.activeEmbeddedSubTrackIndex >= 0) {
      return this.activeEmbeddedSubTrackIndex;
    }
    const idx = this.subtitleOptions.findIndex((o: HarmonySubtitleOption) => o.id === this.selectedSubId);
    return idx >= 0 ? idx : null;
  }

  private dispatchVideoSync(
    trigger: 'start' | 'tick' | 'pause' | 'resume' | 'seek' | 'track_change' | 'background' | 'stop' | 'finish',
    isPaused: boolean,
    posOverrideMs?: number
  ): void {
    const req = this.activeVideoReq;
    if (!req) {
      return;
    }
    const pos = posOverrideMs !== undefined ? Math.max(0, Math.round(posOverrideMs)) : this.positionMs;
    if ((trigger === 'pause' || trigger === 'stop') && this.durationMs > 0) {
      const resumeKey = buildPlaybackResumeKey(req);
      if (resumeKey.length > 0) {
        PlaybackPreferencesStore.saveLocalResumeMs(resumeKey, pos, this.durationMs);
      }
    }
    const itemId = (req.itemId ?? '').trim();
    const server = (req.server ?? '').trim();
    if (itemId.length === 0 || server.length === 0 || itemId.startsWith('file.') || itemId.startsWith('file:')) {
      return;
    }
    const audioIdx = this.selectedAudioTrackIndex >= 0 ? this.selectedAudioTrackIndex : null;
    const subIdx = this.resolveCurrentSubtitleStreamIndex();
    const decision = this.videoSyncTracker.step(trigger, pos, this.durationMs, isPaused, audioIdx, subIdx);
    if (decision.state === 'started') {
      this.videoStartedSent = true;
    }
    HarmonyPlaybackProgressReporter.shared().enqueueDecision(
      MoviePilotRepository.shared(),
      itemId,
      server,
      req.mediaSourceId ?? '',
      decision,
      req.playSessionId ?? this.videoSyncTracker.getPlaySessionId(),
      this.durationMs,
      audioIdx,
      subIdx
    );
  }

  private clearResumeBannerTimer(): void {
    if (this.resumeBannerTimer !== -1) {
      clearTimeout(this.resumeBannerTimer);
      this.resumeBannerTimer = -1;
    }
  }

  private showResumeBanner(resumeMs: number): void {
    this.resumeBannerText = `已从 ${formatMediaDurationMs(resumeMs)} 续播`;
    this.clearResumeBannerTimer();
    this.resumeBannerTimer = setTimeout(() => {
      this.resumeBannerText = '';
    }, 6000);
  }

  private handleRestartFromBeginning(): void {
    this.resumeBannerText = '';
    this.clearResumeBannerTimer();
    const key = buildPlaybackResumeKey(this.activeVideoReq);
    if (key.length > 0) {
      PlaybackPreferencesStore.clearLocalResumeMs(key);
    }
    this.seekVideoMs(0);
  }

  private clearUpNextTimer(): void {
    if (this.upNextCountdownTimer !== -1) {
      clearInterval(this.upNextCountdownTimer);
      this.upNextCountdownTimer = -1;
    }
  }

  private checkUpNextTrigger(): void {
    if (
      this.request.isAudio ||
      this.upNextDismissedForCurrent ||
      this.showUpNextCard ||
      this.videoQueue.length <= 1 ||
      this.videoQueueIdx + 1 >= this.videoQueue.length ||
      this.durationMs < 20000
    ) {
      return;
    }
    const remainingMs = this.durationMs - this.positionMs;
    const ratio = this.positionMs / this.durationMs;
    if (ratio >= 0.93 || remainingMs <= 3500) {
      this.showUpNextCard = true;
      this.upNextCountdownSec = 5;
      this.clearUpNextTimer();
      this.upNextCountdownTimer = setInterval(() => {
        if (!this.showUpNextCard) {
          this.clearUpNextTimer();
          return;
        }
        if (this.upNextCountdownSec <= 1) {
          this.clearUpNextTimer();
          this.showUpNextCard = false;
          this.playNextVideoEpisode();
        } else {
          this.upNextCountdownSec -= 1;
        }
      }, 1000);
    }
  }

  private dismissUpNextCard(): void {
    this.upNextDismissedForCurrent = true;
    this.showUpNextCard = false;
    this.clearUpNextTimer();
  }

  private routeSummaryLabel(): string {
    if (this.activeRouteKind === 'server_lan') { return '直流播放 · 局域网直连'; }
    if (this.activeRouteKind === 'server_wan') { return '直流播放 · 外网直连'; }
    if (this.activeRouteKind === 'strm_direct') { return '直流播放 · STRM 直链'; }
    if (this.activeRouteKind === 'mp_proxy') { return '非直流播放 · 后台中转'; }
    return '';
  }

  /** 播放器内一键热切换内核：保留当前进度与 `play_session_id`，绝不向媒体服务器发送 `stopped`。 */
  private switchVideoEngine(target: string, notice?: string): void {
    const normalized = target === 'enhanced' ? 'enhanced' : 'native';
    if (this.request.isAudio || normalized === this.activeEngineKind) {
      return;
    }
    const carryMs = Math.max(0, this.positionMs);
    this.suppressStopForEngineSwitch = true;
    this.showTransientHud('waveform', notice ?? `已切换至 ${normalized === 'enhanced' ? 'IJK 增强内核' : 'AVPlayer 原生'}`);
    this.initVideoPlayer(this.activeVideoReq, carryMs, normalized).catch(() => {});
  }

  private tryFallbackVideoRoute(req: HarmonyPlaybackRequest): boolean {
    const curKind = (req.activeRouteKind ?? '').trim();
    const serverName = (req.server ?? '').trim();
    if ((curKind === 'server_lan' || curKind === 'server_wan') && req.url.length > 0) {
      HarmonyPlaybackRouteResolver.shared().markRouteFailed(serverName, req.url);
    }
    const fallbacks: PlaybackRouteCandidate[] = req.fallbackRoutes ? req.fallbackRoutes.slice() : [];
    const legacyUrl = (req.proxyFallbackUrl ?? '').trim();
    if (legacyUrl.length > 0 && legacyUrl !== req.url && !fallbacks.some((f: PlaybackRouteCandidate) => f.url === legacyUrl)) {
      fallbacks.push({
        kind: 'mp_proxy',
        url: legacyUrl,
        probe_url: null,
        headers: req.proxyFallbackHeaders ?? {},
        priority: 100,
        requires_same_origin_auth: true
      });
    }
    while (fallbacks.length > 0) {
      const nextRoute = fallbacks.shift();
      if (!nextRoute || !nextRoute.url || nextRoute.url === req.url) { continue; }
      const nextHeaders = nextRoute.kind === 'mp_proxy'
        ? (req.proxyFallbackHeaders ?? nextRoute.headers)
        : nextRoute.headers;
      this.didFallbackToProxy = nextRoute.kind === 'mp_proxy';
      const fallbackReq: HarmonyPlaybackRequest = {
        url: nextRoute.url,
        headers: nextHeaders,
        proxyFallbackUrl: req.proxyFallbackUrl,
        proxyFallbackHeaders: req.proxyFallbackHeaders,
        activeRouteKind: nextRoute.kind,
        fallbackRoutes: fallbacks,
        title: req.title,
        subtitle: req.subtitle,
        artist: req.artist,
        album: req.album,
        artworkUrl: req.artworkUrl,
        isAudio: req.isAudio,
        lyricsLrc: req.lyricsLrc,
        lyricsUrl: req.lyricsUrl,
        itemId: req.itemId,
        server: req.server,
        serverType: req.serverType,
        mediaSourceId: req.mediaSourceId,
        playSessionId: req.playSessionId,
        progressSyncMode: req.progressSyncMode,
        resumePositionMs: req.resumePositionMs,
        subtitles: req.subtitles,
        preferredAudioLang: req.preferredAudioLang,
        preferredAudioIndex: req.preferredAudioIndex,
        preferredSubLang: req.preferredSubLang,
        preferredExternalSubUrl: req.preferredExternalSubUrl,
        disableSubtitles: req.disableSubtitles,
        isSessionBound: req.isSessionBound,
        queue: req.queue,
        queueIndex: req.queueIndex
      };
      this.initVideoPlayer(fallbackReq, undefined, this.activeEngineKind).catch(() => {});
      return true;
    }
    return false;
  }

  private resolveVideoEngineForRequest(req: HarmonyPlaybackRequest, engineOverride?: string): string {
    if (engineOverride === 'native' || engineOverride === 'enhanced') {
      return engineOverride;
    }
    const hasAssOrPgs = (req.subtitles ?? []).some((s: HarmonySubtitleOption) => {
      const probe = `${s.format ?? ''} ${s.url ?? ''}`.toLowerCase();
      return probe.includes('ass') || probe.includes('ssa') || probe.includes('pgs') || probe.includes('sup');
    });
    const plan = RustCoreBridge.resolvePlaybackEngine({
      platform: 'harmony',
      preferred: PlaybackPreferencesStore.getVideoEngine(),
      is_audio: false,
      decode_force_software: PlaybackPreferencesStore.getDecodeMode() === 'sw_force',
      has_enhanced_engine: true,
      has_legacy_engine: false,
      url_or_filename: (req.fdPath && req.fdPath.length > 0) ? req.fdPath : req.url,
      has_ass_or_pgs_subtitle: hasAssOrPgs,
      ignore_ass_style: PlaybackPreferencesStore.getIgnoreAssStyle()
    });
    return plan.primary === 'enhanced' ? 'enhanced' : 'native';
  }

  private async initVideoPlayer(
    req: HarmonyPlaybackRequest,
    startPosOverrideMs?: number,
    engineOverride?: string
  ): Promise<void> {
    const gen = ++this.videoLoadGeneration;
    const isHotSwitch = this.suppressStopForEngineSwitch;
    this.suppressStopForEngineSwitch = false;
    this.videoLoadFailed = false;
    this.releaseVideoPlayerResources();
    if (!isHotSwitch) {
      this.didAutoFallbackEngine = false;
      this.videoSyncTracker.reset(req.playSessionId ?? '');
      this.videoStartedSent = false;
      this.videoProgressTickCount = 0;
    }

    const resolvedEngine = this.resolveVideoEngineForRequest(req, engineOverride);
    this.activeEngineKind = resolvedEngine;

    this.activeVideoReq = req;
    this.activeRouteKind = req.activeRouteKind ?? '';
    this.activeRouteServer = req.server ?? '';
    this.displayTitle = req.title;
    this.displaySubtitle = req.subtitle;
    this.displayArtworkUrl = req.artworkUrl ?? '';
    const carriedStartMs = startPosOverrideMs !== undefined ? Math.max(0, startPosOverrideMs) : 0;
    this.positionMs = carriedStartMs;
    if (!isHotSwitch) {
      this.durationMs = 0;
      this.progress = 0;
      this.activeSubtitleText = '';
      this.externalSubCues = [];
      this.externalSubCueCache.clear();
      this.subtitleLoadSeq += 1;
      this.isSubtitleLoading = false;
      this.failedSubId = '';
      this.activeEmbeddedSubTrackIndex = -1;
      this.activeSubIsExternal = false;
      this.selectedSubId = 'off';
      this.audioTrackOptions = [];
      this.selectedAudioTrackIndex = -1;
      this.subtitleOptions = req.subtitles ? req.subtitles.slice() : [];
      this.showUpNextCard = false;
      this.upNextDismissedForCurrent = false;
      this.resumeBannerText = '';
      this.clearUpNextTimer();
      this.clearResumeBannerTimer();
      this.loadDanmakuForRequest(req, gen).catch(() => {});
    }
    this.isBuffering = true;
    this.isPlaying = true;

    if (resolvedEngine === 'enhanced') {
      const localResume = PlaybackPreferencesStore.getLocalResumeMs(buildPlaybackResumeKey(req));
      const initialResumeMs = isHotSwitch
        ? carriedStartMs
        : Math.max(localResume, req.resumePositionMs ?? 0);
      const effectiveStartMs = initialResumeMs > 30000 || isHotSwitch ? initialResumeMs : 0;
      const targetUrl = (req.fdPath && req.fdPath.length > 0) ? req.fdPath : req.url;
      const cfg: EnhancedLoadConfig = {
        url: targetUrl,
        headers: req.headers ?? {},
        startPositionMs: effectiveStartMs,
        speed: HARMONY_SPEED_VALUES[this.speedIndex] ?? 1.0,
        forceSoftwareDecode: PlaybackPreferencesStore.getDecodeMode() === 'sw_force',
        largeBuffer: PlaybackPreferencesStore.getBufferProfile() === 'large'
      };
      this.enhancedPlayer.load(cfg, {
        onPrepared: (durMs: number) => {
          if (gen !== this.videoLoadGeneration) { return; }
          this.isBuffering = false;
          this.isPlaying = true;
          if (durMs > 0) {
            this.durationMs = durMs;
          }
          if (!isHotSwitch && effectiveStartMs > 30000) {
            this.showResumeBanner(effectiveStartMs);
          }
          this.startVideoProgressTimer();
          this.dispatchVideoSync(this.videoStartedSent ? 'resume' : 'start', false);
          this.resetControlsAutoHideTimer();
          if (!isHotSwitch && this.subtitleOptions.length > 0 && !req.disableSubtitles) {
            this.applyInitialExternalSubtitleForEnhanced(req);
          }
        },
        onVideoSizeChanged: (w: number, h: number) => {
          if (gen !== this.videoLoadGeneration) { return; }
          if (w > 0 && h > 0) {
            this.videoW = w;
            this.videoH = h;
          }
        },
        onBufferingChanged: (buffering: boolean) => {
          if (gen !== this.videoLoadGeneration) { return; }
          this.isBuffering = buffering;
        },
        onProgress: (posMs: number, durMs: number, playing: boolean) => {
          if (gen !== this.videoLoadGeneration) { return; }
          this.isPlaying = playing;
          if (durMs > 0) {
            this.durationMs = durMs;
          }
          if (!this.isDraggingSlider && this.panMode !== 'scrub') {
            this.positionMs = posMs;
            if (this.durationMs > 0) {
              this.progress = Math.min(100, Math.max(0, (posMs / this.durationMs) * 100));
            }
          }
          if (this.activeSubIsExternal && this.selectedSubId !== 'off') {
            this.activeSubtitleText = findActiveSubtitleText(this.externalSubCues, this.positionMs);
          }
          this.syncDanmakuClock(this.positionMs, playing);
          this.checkUpNextTrigger();
        },
        onTimedText: (text: string) => {
          if (gen !== this.videoLoadGeneration) { return; }
          if (!this.activeSubIsExternal && this.selectedSubId !== 'off') {
            this.activeSubtitleText = text;
          }
        },
        onCompletion: () => {
          if (gen !== this.videoLoadGeneration) { return; }
          this.isPlaying = false;
          this.stopVideoProgressTimer();
          const resumeKey = buildPlaybackResumeKey(req);
          if (resumeKey.length > 0) {
            PlaybackPreferencesStore.clearLocalResumeMs(resumeKey);
          }
          this.dispatchVideoSync('finish', true, this.durationMs > 0 ? this.durationMs : this.positionMs);
          if (!this.upNextDismissedForCurrent && this.videoQueueIdx + 1 < this.videoQueue.length) {
            this.clearUpNextTimer();
            this.showUpNextCard = false;
            this.playNextVideoEpisode();
          } else {
            this.controlsVisible = true;
            this.syncImmersiveSystemBars(true);
          }
        },
        onError: () => {
          if (gen !== this.videoLoadGeneration) { return; }
          if (this.positionMs <= 3000 && this.tryFallbackVideoRoute(req)) {
            return;
          }
          if (
            PlaybackPreferencesStore.getVideoEngine() === 'auto' &&
            !this.didAutoFallbackEngine &&
            this.positionMs <= 3000
          ) {
            this.didAutoFallbackEngine = true;
            this.switchVideoEngine('native', '已自动切换至 AVPlayer 原生内核');
            return;
          }
          this.videoLoadFailed = true;
          this.isBuffering = false;
          this.isPlaying = false;
          this.stopVideoProgressTimer();
          this.showTransientHud('xmark', '无法加载当前媒体流，请在右上角菜单切换内核重试');
        }
      });
      return;
    }

    try {
      const player = await media.createAVPlayer();
      if (gen !== this.videoLoadGeneration) {
        try { await player.release(); } catch { /* ignore */ }
        return;
      }
      this.videoPlayer = player;

      player.on('videoSizeChange', (w: number, h: number) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (w > 0 && h > 0) {
          this.videoW = w;
          this.videoH = h;
          this.pipController.updateVideoSize(w, h);
        }
      });

      player.on('durationUpdate', (dur: number) => {
        if (gen !== this.videoLoadGeneration) { return; }
        this.durationMs = Math.max(0, dur);
      });

      player.on('bufferingUpdate', (infoType: media.BufferingInfoType, _val: number) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (infoType === media.BufferingInfoType.BUFFERING_START) {
          this.isBuffering = true;
        } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
          this.isBuffering = false;
        }
      });

      player.on('subtitleUpdate', (info: media.SubtitleInfo) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (!this.activeSubIsExternal && this.selectedSubId !== 'off') {
          this.activeSubtitleText = (info.text ?? '').trim();
        }
      });

      player.on('audioInterrupt', (ev: audio.InterruptEvent) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (ev.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
          if (
            ev.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
            ev.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP
          ) {
            this.interruptedVideoWhilePlaying = this.isPlaying;
            this.setVideoPlaying(false);
          }
        } else if (ev.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME && this.interruptedVideoWhilePlaying) {
          this.interruptedVideoWhilePlaying = false;
          this.setVideoPlaying(true);
        }
      });

      player.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (info.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE && this.isPlaying) {
          this.setVideoPlaying(false);
        }
      });

      player.on('timeUpdate', (time: number) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (!this.isDraggingSlider && this.panMode !== 'scrub') {
          this.positionMs = Math.max(0, time);
          if (this.durationMs > 0) {
            this.progress = Math.min(100, Math.max(0, (this.positionMs / this.durationMs) * 100));
          }
        }
        if (this.activeSubIsExternal && this.selectedSubId !== 'off') {
          this.activeSubtitleText = findActiveSubtitleText(this.externalSubCues, this.positionMs);
        }
        this.syncDanmakuClock(this.positionMs, this.isPlaying);
        this.checkUpNextTrigger();
      });

      player.on('error', () => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (this.positionMs <= 3000) {
          if (this.tryFallbackVideoRoute(req)) {
            return;
          }
          if (!this.didAutoFallbackEngine) {
            this.didAutoFallbackEngine = true;
            this.switchVideoEngine('enhanced', '当前格式不兼容，已自动切换至 IJK 增强内核');
            return;
          }
        }
        this.videoLoadFailed = true;
        this.isBuffering = false;
        this.isPlaying = false;
        this.stopVideoProgressTimer();
        this.showTransientHud('xmark', '无法加载当前媒体流，请在右上角菜单切换内核重试');
      });

      player.on('stateChange', (state: string) => {
        if (gen !== this.videoLoadGeneration) { return; }
        if (state === 'initialized') {
          try {
            const surfaceId = this.xComponentController.getXComponentSurfaceId();
            if (surfaceId && surfaceId.length > 0) {
              player.surfaceId = surfaceId;
            }
          } catch {
            // ignore in headless preview
          }
          player.prepare().catch(() => {});
        } else if (state === 'prepared') {
          this.isBuffering = false;
          if (this.durationMs <= 0 && player.duration > 0) {
            this.durationMs = player.duration;
          }
          if (player.width > 0 && player.height > 0) {
            this.videoW = player.width;
            this.videoH = player.height;
          }
          this.applyPlayerScaleType();
          try {
            player.setSpeed(HARMONY_SPEED_ENUMS[this.speedIndex]);
          } catch {
            // ignore
          }

          // 读取内封音轨与字幕轨道并应用播前偏好
          this.inspectTracksAndApplyDefaults(player, req, gen).catch(() => {});

          // 检查热切进度或本地 + 服务端断点续播
          const localResume = PlaybackPreferencesStore.getLocalResumeMs(buildPlaybackResumeKey(req));
          const resumeMs = isHotSwitch ? carriedStartMs : Math.max(localResume, req.resumePositionMs ?? 0);
          if ((isHotSwitch && resumeMs > 0) || (resumeMs > 30000 && (this.durationMs <= 0 || resumeMs < this.durationMs * 0.95))) {
            try {
              player.seek(resumeMs);
              this.positionMs = resumeMs;
              if (this.durationMs > 0) {
                this.progress = Math.min(100, (resumeMs / this.durationMs) * 100);
              }
              if (!isHotSwitch && resumeMs > 30000) {
                this.showResumeBanner(resumeMs);
              }
            } catch {
              // ignore
            }
          }

          // 挂载画中画控制器
          this.attachPipIfSupported();

          player.play().catch(() => {});
          this.isPlaying = true;
          this.pipController.updatePlayState(true);
          this.startVideoProgressTimer();
          this.resetControlsAutoHideTimer();
        } else if (state === 'playing') {
          this.isBuffering = false;
          this.isPlaying = true;
          this.pipController.updatePlayState(true);
          this.startVideoProgressTimer();
          this.dispatchVideoSync(this.videoStartedSent ? 'resume' : 'start', false);
          this.resetControlsAutoHideTimer();
        } else if (state === 'paused') {
          this.isPlaying = false;
          this.pipController.updatePlayState(false);
          // 保持 1 秒状态机心跳以支持暂停 12 秒保活与 15 分钟自动释放会话
          this.startVideoProgressTimer();
          this.dispatchVideoSync('pause', true);
          this.clearControlsAutoHideTimer();
        } else if (state === 'completed') {
          this.isPlaying = false;
          this.pipController.updatePlayState(false);
          this.stopVideoProgressTimer();
          const resumeKey = buildPlaybackResumeKey(req);
          if (resumeKey.length > 0) {
            PlaybackPreferencesStore.clearLocalResumeMs(resumeKey);
          }
          this.dispatchVideoSync('finish', true, this.durationMs > 0 ? this.durationMs : this.positionMs);
          if (!this.upNextDismissedForCurrent && this.videoQueueIdx + 1 < this.videoQueue.length) {
            this.clearUpNextTimer();
            this.showUpNextCard = false;
            this.playNextVideoEpisode();
          } else {
            this.controlsVisible = true;
            this.syncImmersiveSystemBars(true);
          }
        }
      });

      const isLargeBuffer = PlaybackPreferencesStore.getBufferProfile() === 'large';
      const strategy: media.PlaybackStrategy = {
        preferredBufferDuration: isLargeBuffer ? 60 : 20,
        showFirstFrameOnPrepare: true
      };
      if (req.preferredAudioLang && req.preferredAudioLang.length > 0) {
        strategy.preferredAudioLanguage = req.preferredAudioLang;
      }
      if (!req.disableSubtitles && req.preferredSubLang && req.preferredSubLang.length > 0) {
        strategy.preferredSubtitleLanguage = req.preferredSubLang;
      }

      const opened = await attachSourceToAvPlayer(player, req, strategy);
      if (gen !== this.videoLoadGeneration) {
        closeLocalPlaybackFd(opened);
        return;
      }
      this.openedVideoFd = opened;
    } catch {
      this.isBuffering = false;
      this.isPlaying = false;
    }
  }

  private attachPipIfSupported(): void {
    if (!this.pipSupported) {
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      return;
    }
    this.pipController.attach(
      ctx,
      this.xComponentController,
      this.videoQueue.length > 1,
      this.autoPipEnabled,
      this.videoW,
      this.videoH,
      {
        onTogglePlayPause: (shouldPlay?: boolean) => {
          if (shouldPlay !== undefined) {
            this.setVideoPlaying(shouldPlay);
          } else {
            this.setVideoPlaying(!this.isPlaying);
          }
        },
        onNext: () => {
          this.playNextVideoEpisode();
        },
        onPrevious: () => {
          this.playPreviousVideoEpisode();
        },
        onFastForward: () => {
          this.seekVideoRelativeMs(10000);
        },
        onFastBackward: () => {
          this.seekVideoRelativeMs(-10000);
        },
        onPipStateChanged: (active: boolean, stoppedWithoutRestore: boolean) => {
          this.isPipActive = active;
          this.danmakuConfigVersion += 1;
          if (stoppedWithoutRestore && this.viewDisappeared) {
            this.dispatchVideoSync('stop', true);
            this.pipController.destroy().catch(() => {});
            this.releaseVideoPlayerResources();
          }
        }
      }
    ).catch(() => {});
  }

  private async inspectTracksAndApplyDefaults(
    player: media.AVPlayer,
    req: HarmonyPlaybackRequest,
    gen: number
  ): Promise<void> {
    const audioList: HarmonyAudioTrackOption[] = [];
    const embeddedSubs: HarmonySubtitleOption[] = [];
    try {
      const descriptions = await player.getTrackDescription();
      if (gen !== this.videoLoadGeneration) {
        return;
      }
      for (let i = 0; i < descriptions.length; i++) {
        const desc = descriptions[i] as Record<string, Object>;
        const trackIdx = Number(desc['track_index'] ?? i);
        const trackType = Number(desc['track_type'] ?? -1);
        const lang = String(desc['language'] ?? '').trim();
        const rawName = String(desc['track_name'] ?? '').trim();
        const codec = String(desc['codec_mime'] ?? '').trim();

        if (trackType === 0) {
          const parts: string[] = [];
          if (rawName.length > 0) { parts.push(rawName); }
          if (lang.length > 0 && lang !== 'und') { parts.push(lang.toUpperCase()); }
          if (codec.length > 0) { parts.push(codec.replace('audio/', '').toUpperCase()); }
          audioList.push({
            trackIndex: trackIdx,
            label: parts.length > 0 ? parts.join(' · ') : `音轨 ${audioList.length + 1}`,
            language: lang,
            codec: codec
          });
        } else if (trackType === 2) {
          const parts: string[] = [];
          if (rawName.length > 0) { parts.push(rawName); }
          if (lang.length > 0 && lang !== 'und') { parts.push(lang); }
          embeddedSubs.push({
            id: `emb_${trackIdx}`,
            label: parts.length > 0 ? `${parts.join(' · ')} · 内封` : `内封字幕 ${embeddedSubs.length + 1}`,
            language: lang,
            format: codec,
            isExternal: false,
            trackIndex: trackIdx
          });
        }
      }
    } catch {
      // 部分直链流无多轨道描述，保持外挂字幕可用
    }

    if (gen !== this.videoLoadGeneration) {
      return;
    }

    this.audioTrackOptions = audioList;
    if (audioList.length > 0) {
      let chosenAudio = audioList[0];
      if (req.preferredAudioIndex !== undefined && req.preferredAudioIndex >= 0 && req.preferredAudioIndex < audioList.length) {
        chosenAudio = audioList[req.preferredAudioIndex];
      } else if (req.preferredAudioLang && req.preferredAudioLang.trim().length > 0) {
        const targetLang = req.preferredAudioLang.trim().toLowerCase();
        for (let i = 0; i < audioList.length; i++) {
          if (audioList[i].language.toLowerCase() === targetLang || audioList[i].label.toLowerCase().includes(targetLang)) {
            chosenAudio = audioList[i];
            break;
          }
        }
      }
      this.selectedAudioTrackIndex = chosenAudio.trackIndex;
      if (audioList.length > 1 && chosenAudio.trackIndex !== audioList[0].trackIndex) {
        try {
          await player.selectTrack(chosenAudio.trackIndex);
        } catch {
          // ignore
        }
      }
    }

    const externalSubs = req.subtitles ? req.subtitles.slice() : [];
    const mergedSubs: HarmonySubtitleOption[] = [];
    for (let i = 0; i < embeddedSubs.length; i++) {
      mergedSubs.push(embeddedSubs[i]);
    }
    for (let i = 0; i < externalSubs.length; i++) {
      mergedSubs.push(externalSubs[i]);
    }
    this.subtitleOptions = mergedSubs;

    if (req.disableSubtitles === true || mergedSubs.length === 0) {
      await this.selectSubtitleOption(null);
      return;
    }

    // 1. 显式指定外挂字幕 URL
    if (req.preferredExternalSubUrl && req.preferredExternalSubUrl.trim().length > 0) {
      for (let i = 0; i < mergedSubs.length; i++) {
        if (mergedSubs[i].url === req.preferredExternalSubUrl) {
          await this.selectSubtitleOption(mergedSubs[i]);
          return;
        }
      }
    }

    // 2. 显式指定字幕语言/名称
    if (req.preferredSubLang && req.preferredSubLang.trim().length > 0) {
      const targetSub = req.preferredSubLang.trim().toLowerCase();
      for (let i = 0; i < mergedSubs.length; i++) {
        if (
          mergedSubs[i].language.toLowerCase() === targetSub ||
          mergedSubs[i].label.toLowerCase().includes(targetSub)
        ) {
          await this.selectSubtitleOption(mergedSubs[i]);
          return;
        }
      }
    }

    // 3. 偏好中文字幕时优先匹配中文轨道（优先外挂 SRT/ASS 文本轨道以确保 100% 渲染保真，其次内封轨道）
    if (PlaybackPreferencesStore.getPreferZhSub()) {
      for (let i = 0; i < mergedSubs.length; i++) {
        if (mergedSubs[i].isExternal && isChineseLanguageTrack(mergedSubs[i].language, mergedSubs[i].label)) {
          await this.selectSubtitleOption(mergedSubs[i]);
          return;
        }
      }
      for (let i = 0; i < mergedSubs.length; i++) {
        if (isChineseLanguageTrack(mergedSubs[i].language, mergedSubs[i].label)) {
          await this.selectSubtitleOption(mergedSubs[i]);
          return;
        }
      }
    }
  }

  /** 为增强内核起播阶段匹配首选外挂字幕（遵循显式 URL -> 显式语言 -> 中文偏好优先级）。 */
  private applyInitialExternalSubtitleForEnhanced(req: HarmonyPlaybackRequest): void {
    const extList = this.subtitleOptions.filter((s: HarmonySubtitleOption) => s.isExternal && (s.url ?? '').trim().length > 0);
    if (extList.length === 0) {
      return;
    }
    if (req.preferredExternalSubUrl && req.preferredExternalSubUrl.trim().length > 0) {
      const matchedByUrl = extList.find((s: HarmonySubtitleOption) => s.url === req.preferredExternalSubUrl);
      if (matchedByUrl) {
        this.selectSubtitleOption(matchedByUrl).catch(() => {});
        return;
      }
    }
    if (req.preferredSubLang && req.preferredSubLang.trim().length > 0) {
      const targetLang = req.preferredSubLang.trim().toLowerCase();
      const matchedByLang = extList.find((s: HarmonySubtitleOption) =>
        s.language.toLowerCase() === targetLang || s.label.toLowerCase().includes(targetLang)
      );
      if (matchedByLang) {
        this.selectSubtitleOption(matchedByLang).catch(() => {});
        return;
      }
    }
    if (PlaybackPreferencesStore.getPreferZhSub()) {
      const zhSub = extList.find((s: HarmonySubtitleOption) => isChineseLanguageTrack(s.language, s.label));
      if (zhSub) {
        this.selectSubtitleOption(zhSub).catch(() => {});
      }
    }
  }

  /** 读取当前视频最精确的实时播放毫秒位置，确保慢速外挂字幕下载完瞬间与画面帧零偏差对齐。 */
  private resolveLiveVideoPositionMs(): number {
    if (this.activeEngineKind !== 'enhanced' && this.videoPlayer) {
      try {
        const live = this.videoPlayer.currentTime;
        if (Number.isFinite(live) && live >= 0) {
          return Math.max(0, live);
        }
      } catch {
        // ignore invalid state
      }
    }
    return Math.max(0, this.positionMs);
  }

  private async selectSubtitleOption(opt: HarmonySubtitleOption | null): Promise<void> {
    const subSeq = ++this.subtitleLoadSeq;
    const player = this.videoPlayer;
    if (this.activeEmbeddedSubTrackIndex >= 0 && player) {
      try {
        await player.deselectTrack(this.activeEmbeddedSubTrackIndex);
      } catch {
        // ignore
      }
      this.activeEmbeddedSubTrackIndex = -1;
    }

    this.activeSubtitleText = '';
    this.externalSubCues = [];

    if (!opt) {
      this.isSubtitleLoading = false;
      this.selectedSubId = 'off';
      this.activeSubIsExternal = false;
      if (this.videoStartedSent) {
        this.dispatchVideoSync('track_change', !this.isPlaying);
      }
      return;
    }

    this.selectedSubId = opt.id;
    if (opt.isExternal && opt.url && opt.url.trim().length > 0) {
      this.activeSubIsExternal = true;
      this.failedSubId = '';
      const cleanSubUrl = opt.url.trim();
      const cachedCues = this.externalSubCueCache.get(cleanSubUrl);
      if (cachedCues && cachedCues.length > 0) {
        this.isSubtitleLoading = false;
        this.externalSubCues = cachedCues;
        this.activeSubtitleText = findActiveSubtitleText(this.externalSubCues, this.resolveLiveVideoPositionMs());
        if (this.videoStartedSent) {
          this.dispatchVideoSync('track_change', !this.isPlaying);
        }
        return;
      }

      this.isSubtitleLoading = true;
      const gen = this.videoLoadGeneration;
      const targetId = opt.id;
      const raw = await MoviePilotRepository.shared().fetchSubtitleOrLyricsText(cleanSubUrl, false);
      if (gen !== this.videoLoadGeneration || subSeq !== this.subtitleLoadSeq || this.selectedSubId !== targetId) {
        return;
      }
      this.isSubtitleLoading = false;
      if (!raw || raw.trim().length === 0) {
        this.failedSubId = targetId;
        this.selectedSubId = 'off';
        this.activeSubIsExternal = false;
        this.activeSubtitleText = '';
        this.showTransientHud('xmark', '外挂字幕加载失败，可在字幕面板点击重试', 2400);
        return;
      }
      const parsedCues = parseSubtitleText(raw, opt.format ?? '');
      if (parsedCues.length > 0) {
        this.externalSubCueCache.set(cleanSubUrl, parsedCues);
      }
      this.externalSubCues = parsedCues;
      const livePos = this.resolveLiveVideoPositionMs();
      this.positionMs = livePos;
      this.activeSubtitleText = findActiveSubtitleText(this.externalSubCues, livePos);
    } else if (!opt.isExternal && opt.trackIndex !== undefined && player) {
      this.isSubtitleLoading = false;
      this.activeSubIsExternal = false;
      this.activeEmbeddedSubTrackIndex = opt.trackIndex;
      try {
        await player.selectTrack(opt.trackIndex);
      } catch {
        // ignore
      }
    } else {
      this.isSubtitleLoading = false;
    }
    if (this.videoStartedSent) {
      this.dispatchVideoSync('track_change', !this.isPlaying);
    }
  }

  private async selectAudioTrack(opt: HarmonyAudioTrackOption): Promise<void> {
    this.selectedAudioTrackIndex = opt.trackIndex;
    if (this.videoPlayer) {
      try {
        await this.videoPlayer.selectTrack(opt.trackIndex);
        this.showTransientHud('waveform', `已切换：${opt.label}`);
      } catch {
        // ignore
      }
    }
    if (this.videoStartedSent) {
      this.dispatchVideoSync('track_change', !this.isPlaying);
    }
  }

  private playNextVideoEpisode(): void {
    if (this.videoQueueIdx + 1 >= this.videoQueue.length) {
      return;
    }
    this.playVideoEpisodeAtIndex(this.videoQueueIdx + 1).catch(() => {});
  }

  private playPreviousVideoEpisode(): void {
    if (this.positionMs > 5000 || this.videoQueueIdx <= 0) {
      this.seekVideoMs(0);
      return;
    }
    this.playVideoEpisodeAtIndex(this.videoQueueIdx - 1).catch(() => {});
  }

  private async playVideoEpisodeAtIndex(index: number): Promise<void> {
    if (index < 0 || index >= this.videoQueue.length) {
      return;
    }
    this.dispatchVideoSync('stop', true);
    this.didFallbackToProxy = false;
    this.videoQueueIdx = index;
    const ep = this.videoQueue[index];
    this.isBuffering = true;

    if ((ep.fdPath ?? '').trim().length > 0 || (ep.url ?? '').trim().length > 0) {
      const directReq: HarmonyPlaybackRequest = {
        url: ep.url ?? '',
        fdPath: ep.fdPath,
        headers: ep.headers,
        title: ep.title,
        subtitle: ep.subtitle ?? this.displaySubtitle,
        artworkUrl: ep.artworkUrl,
        isAudio: false,
        itemId: ep.itemId,
        server: ep.server,
        mediaSourceId: ep.mediaSourceId,
        resumePositionMs: ep.resumePositionMs,
        isSessionBound: this.activeVideoReq.isSessionBound,
        queue: this.videoQueue,
        queueIndex: index
      };
      await this.initVideoPlayer(directReq);
      return;
    }

    const stream = await MoviePilotRepository.shared().fetchVideoStreamInfo(
      ep.itemId,
      ep.server ?? (this.activeVideoReq.server ?? ''),
      ep.mediaSourceId ?? ''
    );
    if (!stream || stream.contentUrl.length === 0) {
      this.isBuffering = false;
      this.showTransientHud('xmark', '无法获取该集播放流');
      return;
    }
    const nextReq: HarmonyPlaybackRequest = {
      url: stream.contentUrl,
      headers: stream.headers,
      title: stream.title.length > 0 ? stream.title : ep.title,
      subtitle: ep.subtitle ?? this.activeVideoReq.subtitle,
      artworkUrl: stream.artworkUrl.length > 0 ? stream.artworkUrl : (ep.artworkUrl ?? ''),
      isAudio: false,
      itemId: stream.itemId,
      server: stream.server,
      serverType: stream.serverType,
      mediaSourceId: stream.mediaSourceId,
      playSessionId: stream.playSessionId,
      progressSyncMode: stream.progressSyncMode,
      resumePositionMs: ep.resumePositionMs && ep.resumePositionMs > 0 ? ep.resumePositionMs : stream.resumePositionMs,
      subtitles: mapExternalSubtitlesToOptions(stream.subtitles),
      preferredAudioLang: this.activeVideoReq.preferredAudioLang,
      preferredSubLang: this.activeVideoReq.preferredSubLang,
      disableSubtitles: this.selectedSubId === 'off' && this.subtitleOptions.length > 0,
      isSessionBound: true,
      queue: this.videoQueue,
      queueIndex: index,
      danmakuEnabled: stream.danmakuEnabled,
      seriesName: stream.seriesName,
      seasonNumber: stream.seasonNumber,
      episodeNumber: stream.episodeNumber,
      year: stream.year,
      tmdbId: stream.tmdbId,
      fileName: stream.fileName,
      fileSize: stream.fileSize
    };
    await this.initVideoPlayer(nextReq);
  }

  private setVideoPlaying(nextPlaying: boolean): void {
    this.isPlaying = nextPlaying;
    this.syncDanmakuClock(this.positionMs, nextPlaying);
    this.pipController.updatePlayState(nextPlaying);
    if (this.activeEngineKind === 'enhanced') {
      if (nextPlaying) {
        this.enhancedPlayer.play();
        this.startVideoProgressTimer();
        this.resetControlsAutoHideTimer();
      } else {
        this.enhancedPlayer.pause();
        this.startVideoProgressTimer();
        this.dispatchVideoSync('pause', true);
        this.clearControlsAutoHideTimer();
      }
      return;
    }
    if (this.videoPlayer) {
      if (nextPlaying) {
        this.videoPlayer.play().catch(() => {});
        this.startVideoProgressTimer();
        this.resetControlsAutoHideTimer();
      } else {
        this.videoPlayer.pause().catch(() => {});
        this.startVideoProgressTimer();
        this.dispatchVideoSync('pause', true);
        this.clearControlsAutoHideTimer();
      }
    }
  }

  private handleTogglePlay(): void {
    if (this.request.isAudio) {
      HarmonyAudioSession.shared().togglePlayPause();
      return;
    }
    if (!this.isPlaying && this.videoLoadFailed) {
      this.initVideoPlayer(this.activeVideoReq, this.positionMs, this.activeEngineKind).catch(() => {});
      return;
    }
    this.setVideoPlaying(!this.isPlaying);
  }

  private seekVideoMs(targetMs: number): void {
    const clamped = this.durationMs > 0
      ? Math.min(this.durationMs, Math.max(0, Math.round(targetMs)))
      : Math.max(0, Math.round(targetMs));
    this.positionMs = clamped;
    if (this.durationMs > 0) {
      this.progress = Math.min(100, Math.max(0, (clamped / this.durationMs) * 100));
    }
    if (this.activeSubIsExternal && this.selectedSubId !== 'off') {
      this.activeSubtitleText = findActiveSubtitleText(this.externalSubCues, clamped);
    }
    if (this.activeEngineKind === 'enhanced') {
      this.enhancedPlayer.seekTo(clamped);
    } else if (this.videoPlayer) {
      try {
        this.videoPlayer.seek(clamped);
      } catch {
        // ignore
      }
    }
    this.syncDanmakuClock(clamped, this.isPlaying);
    this.dispatchVideoSync('seek', !this.isPlaying, clamped);
  }

  private seekVideoRelativeMs(deltaMs: number): void {
    const target = this.positionMs + deltaMs;
    this.seekVideoMs(target);
    const sec = Math.round(Math.abs(deltaMs) / 1000);
    this.showTransientHud(
      deltaMs >= 0 ? 'goforward_10' : 'gobackward_10',
      deltaMs >= 0 ? `快进 ${sec} 秒` : `快退 ${sec} 秒`
    );
    this.resetControlsAutoHideTimer();
  }

  private handleSliderChange(val: number, mode: SliderChangeMode): void {
    this.progress = val;
    if (this.durationMs > 0) {
      this.positionMs = Math.round((val / 100) * this.durationMs);
    }
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isDraggingSlider = true;
      this.clearControlsAutoHideTimer();
      return;
    }
    this.isDraggingSlider = false;
    if (this.request.isAudio) {
      HarmonyAudioSession.shared().seekPercent(val);
    } else if (this.durationMs > 0) {
      const targetMs = Math.round((val / 100) * this.durationMs);
      this.seekVideoMs(targetMs);
      this.resetControlsAutoHideTimer();
    }
  }

  private applySpeedIndex(idx: number): void {
    const clamped = Math.max(0, Math.min(HARMONY_SPEED_ENUMS.length - 1, idx));
    if (this.request.isAudio) {
      this.speedIndex = HarmonyAudioSession.shared().setSpeedIndex(clamped);
      return;
    }
    this.speedIndex = clamped;
    if (!this.isLongPressBoosting) {
      if (this.activeEngineKind === 'enhanced') {
        this.enhancedPlayer.setSpeed(HARMONY_SPEED_VALUES[clamped] ?? 1.0);
      } else if (this.videoPlayer) {
        try {
          this.videoPlayer.setSpeed(HARMONY_SPEED_ENUMS[clamped]);
        } catch {
          // ignore
        }
      }
    }
    this.syncDanmakuClock(this.positionMs, this.isPlaying);
    this.showTransientHud('timer', `倍速：${HARMONY_SPEED_LABELS[clamped]}`);
    this.resetControlsAutoHideTimer();
  }

  private syncDanmakuClock(posMs?: number, playing?: boolean): void {
    if (this.request.isAudio || !this.activeVideoReq.danmakuEnabled) {
      return;
    }
    const rate = this.isLongPressBoosting ? 2.0 : (HARMONY_SPEED_VALUES[this.speedIndex] ?? 1.0);
    this.danmakuController.syncPlayerClock(
      posMs !== undefined ? posMs : this.positionMs,
      playing !== undefined ? playing : this.isPlaying,
      rate
    );
  }

  private rebuildDanmakuTimeline(): void {
    if (this.danmakuRawJson.length === 0) {
      this.danmakuTotalCount = 0;
      this.danmakuController.clearAll();
      this.danmakuConfigVersion += 1;
      return;
    }
    const prepared = RustCoreBridge.prepareDanmakuTimeline(
      this.danmakuRawJson,
      DanmakuPreferencesStore.toFilterOptions(this.danmakuShiftMs)
    );
    this.danmakuTotalCount = prepared.items.length;
    this.danmakuController.load(prepared.items, this.positionMs);
    this.syncDanmakuClock(this.positionMs, this.isPlaying);
    this.danmakuConfigVersion += 1;
  }

  private async loadDanmakuCommentsByEpisode(episodeId: number, gen: number, forceRefresh: boolean = false): Promise<void> {
    if (episodeId <= 0) {
      return;
    }
    try {
      const payload: MpDanmakuCommentsRaw = await MoviePilotRepository.shared().fetchDanmakuComments(episodeId, forceRefresh);
      if (gen !== this.videoLoadGeneration) {
        return;
      }
      this.danmakuRawJson = payload.rawJson;
      this.rebuildDanmakuTimeline();
    } catch {
      // 弹幕加载失败绝不阻断视频播放
    }
  }

  private async loadDanmakuForRequest(req: HarmonyPlaybackRequest, gen: number): Promise<void> {
    this.danmakuRawJson = '';
    this.danmakuEpisodeId = 0;
    this.danmakuAnimeId = undefined;
    this.danmakuAnimeTitle = '';
    this.danmakuEpisodeTitle = '';
    this.danmakuCandidates = [];
    this.danmakuFromBinding = false;
    this.danmakuShiftMs = 0;
    this.danmakuTotalCount = 0;
    this.danmakuController.clearAll();
    this.danmakuConfigVersion += 1;
    if (req.isAudio || !req.danmakuEnabled) {
      return;
    }
    try {
      const resp: MpDanmakuMatchResponse = await MoviePilotRepository.shared().matchDanmaku({
        itemId: req.itemId,
        server: req.server,
        title: req.title,
        seriesName: req.seriesName,
        seasonNumber: req.seasonNumber,
        episodeNumber: req.episodeNumber,
        year: req.year,
        tmdbId: req.tmdbId,
        fileName: req.fileName,
        fileSize: req.fileSize,
        durationMs: this.durationMs > 1000 ? this.durationMs : undefined
      });
      if (gen !== this.videoLoadGeneration) {
        return;
      }
      this.danmakuFromBinding = resp.fromBinding;
      this.danmakuCandidates = resp.candidates;
      this.danmakuShiftMs = resp.shiftMs;
      if (resp.matched && resp.episode && resp.episode.episodeId > 0) {
        this.danmakuEpisodeId = resp.episode.episodeId;
        this.danmakuAnimeId = resp.episode.animeId;
        this.danmakuAnimeTitle = resp.episode.animeTitle;
        this.danmakuEpisodeTitle = resp.episode.episodeTitle;
        await this.loadDanmakuCommentsByEpisode(resp.episode.episodeId, gen, false);
      }
    } catch {
      // ignore danmaku network error
    }
  }

  private openDanmakuManualMatch(): void {
    const rawHint = (this.activeVideoReq.seriesName ?? '').trim() ||
      (this.activeVideoReq.title ?? '').trim() ||
      (this.activeVideoReq.fileName ?? '').trim();
    this.danmakuSearchQuery = RustCoreBridge.normalizeDanmakuTitle(rawHint);
    this.danmakuSearchError = '';
    this.danmakuActiveBangumi = null;
    this.danmakuSearchResults = [];
    this.openSheet('danmakuMatch');
    if (this.danmakuCandidates.length === 0 && this.danmakuSearchQuery.length > 0) {
      this.triggerDanmakuSearch();
    }
  }

  private triggerDanmakuSearch(): void {
    const kw = this.danmakuSearchQuery.trim();
    if (!kw || this.danmakuSearchLoading) {
      return;
    }
    this.danmakuSearchLoading = true;
    this.danmakuSearchError = '';
    this.danmakuActiveBangumi = null;
    MoviePilotRepository.shared().searchDanmaku(kw).then((items: MpDanmakuAnimeSearchItem[]) => {
      this.danmakuSearchResults = items;
      if (items.length === 0) {
        this.danmakuSearchError = '未搜索到匹配作品，请尝试简化关键词';
      }
      this.danmakuSearchLoading = false;
    }).catch((err: Error) => {
      this.danmakuSearchError = err.message || '搜索弹幕失败';
      this.danmakuSearchLoading = false;
    });
  }

  private selectDanmakuCandidate(cand: MpDanmakuEpisodeCandidate): void {
    const gen = this.videoLoadGeneration;
    this.danmakuEpisodeId = cand.episodeId;
    this.danmakuAnimeId = cand.animeId;
    this.danmakuAnimeTitle = cand.animeTitle;
    this.danmakuEpisodeTitle = cand.episodeTitle;
    this.danmakuShiftMs = cand.shiftMs;
    this.showPlayerSheet = false;
    this.showTransientHud('checkmark', `已切换弹幕：${cand.animeTitle}`);
    MoviePilotRepository.shared().saveDanmakuBinding({
      server: this.activeVideoReq.server,
      itemId: this.activeVideoReq.itemId,
      tmdbId: this.activeVideoReq.tmdbId,
      seasonNumber: this.activeVideoReq.seasonNumber,
      episodeNumber: this.activeVideoReq.episodeNumber,
      episodeId: cand.episodeId,
      animeId: cand.animeId,
      animeTitle: cand.animeTitle,
      episodeTitle: cand.episodeTitle,
      shiftMs: cand.shiftMs
    }).then(() => {
      this.danmakuFromBinding = true;
    }).catch(() => {});
    this.loadDanmakuCommentsByEpisode(cand.episodeId, gen, false).catch(() => {});
  }

  private danmakuMatchedSummaryText(): string {
    if (this.danmakuAnimeTitle.length > 0 && this.danmakuEpisodeTitle.length > 0) {
      return `${this.danmakuAnimeTitle} · ${this.danmakuEpisodeTitle}`;
    }
    if (this.danmakuAnimeTitle.length > 0) {
      return this.danmakuAnimeTitle;
    }
    return '暂未自动匹配到弹幕分集';
  }

  private openSheet(kind: PlayerSheetKind): void {
    this.activeSheetKind = kind;
    this.showPlayerSheet = true;
    this.clearControlsAutoHideTimer();
  }

  private openSystemCastOrBluetoothSettings(targetUri: string, fallbackHint: string): void {
    const ctx = this.getUIContext().getHostContext();
    if (!ctx) {
      this.showTransientHud('waveform', fallbackHint, 2400);
      return;
    }
    const abilityCtx = ctx as common.UIAbilityContext;
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: targetUri
    };
    abilityCtx.startAbility(want).catch(() => {
      this.showTransientHud('waveform', fallbackHint, 2600);
    });
  }

  private handleVideoDoubleTap(ev: GestureEvent): void {
    if (this.request.isAudio || this.isLocked) {
      return;
    }
    const areaW = this.effectiveAreaWidth();
    let tapX = this.lastTapLocalX >= 0 ? this.lastTapLocalX : (areaW * 0.5);
    if (ev.fingerList && ev.fingerList.length > 0 && ev.fingerList[0]) {
      tapX = ev.fingerList[0].localX;
    }
    if (tapX < areaW * 0.35) {
      this.seekVideoRelativeMs(-10000);
    } else if (tapX > areaW * 0.65) {
      this.seekVideoRelativeMs(10000);
    } else {
      const next = !this.isPlaying;
      this.setVideoPlaying(next);
      this.showTransientHud(next ? 'play_fill' : 'pause_fill', next ? '继续播放' : '已暂停');
    }
  }

  private handleLongPressStart(): void {
    if (this.request.isAudio || this.isLocked || !this.isPlaying) {
      return;
    }
    if (this.activeEngineKind !== 'enhanced' && !this.videoPlayer) {
      return;
    }
    this.savedSpeedBeforeBoost = this.speedIndex;
    this.isLongPressBoosting = true;
    if (this.activeEngineKind === 'enhanced') {
      this.enhancedPlayer.setSpeed(2.0);
    } else if (this.videoPlayer) {
      try {
        this.videoPlayer.setSpeed(HARMONY_SPEED_ENUMS[BOOST_2X_SPEED_INDEX]);
      } catch {
        // ignore
      }
    }
  }

  private handleLongPressEnd(): void {
    if (!this.isLongPressBoosting) {
      return;
    }
    this.isLongPressBoosting = false;
    if (this.activeEngineKind === 'enhanced') {
      this.enhancedPlayer.setSpeed(HARMONY_SPEED_VALUES[this.savedSpeedBeforeBoost] ?? 1.0);
    } else if (this.videoPlayer) {
      try {
        this.videoPlayer.setSpeed(HARMONY_SPEED_ENUMS[this.savedSpeedBeforeBoost]);
      } catch {
        // ignore
      }
    }
  }

  private handlePanStart(ev: GestureEvent): void {
    if (this.request.isAudio || this.isLocked) {
      return;
    }
    this.panMode = 'undecided';
    this.scrubStartMs = this.positionMs;
    this.scrubTargetMs = this.positionMs;
    this.brightnessStart = this.gestureBrightness;
    this.volumeStart = this.gestureVolume;
    if (ev.fingerList && ev.fingerList.length > 0 && ev.fingerList[0]) {
      this.lastTapLocalX = ev.fingerList[0].localX;
    }
  }

  private handlePanUpdate(ev: GestureEvent): void {
    if (this.request.isAudio || this.isLocked) {
      return;
    }
    const areaW = this.effectiveAreaWidth();
    const areaH = this.effectiveAreaHeight();

    if (this.panMode === 'undecided') {
      if (Math.abs(ev.offsetX) < 6 && Math.abs(ev.offsetY) < 6) {
        return;
      }
      if (Math.abs(ev.offsetX) >= Math.abs(ev.offsetY)) {
        this.panMode = 'scrub';
      } else {
        const startX = (ev.fingerList && ev.fingerList.length > 0 && ev.fingerList[0])
          ? ev.fingerList[0].localX - ev.offsetX
          : this.lastTapLocalX;
        this.panMode = startX < areaW * 0.5 ? 'brightness' : 'volume';
      }
    }

    if (this.panMode === 'scrub') {
      if (this.durationMs <= 0) {
        return;
      }
      const maxSpanMs = Math.min(this.durationMs, 180000);
      const deltaMs = (ev.offsetX / Math.max(180, areaW)) * maxSpanMs;
      this.scrubTargetMs = Math.min(this.durationMs, Math.max(0, Math.round(this.scrubStartMs + deltaMs)));
      this.positionMs = this.scrubTargetMs;
      this.progress = Math.min(100, Math.max(0, (this.scrubTargetMs / this.durationMs) * 100));
      const deltaSec = (this.scrubTargetMs - this.scrubStartMs) / 1000;
      this.showTransientHud(
        deltaSec >= 0 ? 'goforward_10' : 'gobackward_10',
        `${formatMediaDurationMs(this.scrubTargetMs)} (${formatSignedDeltaSec(deltaSec)})`,
        0
      );
    } else if (this.panMode === 'brightness') {
      const delta = -ev.offsetY / Math.max(160, areaH * 0.72);
      const nextB = Math.min(1.0, Math.max(0.05, this.brightnessStart + delta));
      this.gestureBrightness = nextB;
      this.applyWindowBrightness(nextB);
      this.showTransientHud('sun_max_fill', `亮度 ${Math.round(nextB * 100)}%`, 0);
    } else if (this.panMode === 'volume') {
      const delta = -ev.offsetY / Math.max(160, areaH * 0.72);
      const nextV = Math.min(1.0, Math.max(0.0, this.volumeStart + delta));
      this.gestureVolume = nextV;
      if (this.activeEngineKind === 'enhanced') {
        this.enhancedPlayer.setVolume(nextV);
      } else if (this.videoPlayer) {
        try {
          this.videoPlayer.setVolume(nextV);
        } catch {
          // ignore
        }
      }
      this.showTransientHud(
        nextV <= 0.01 ? 'speaker_slash_fill' : 'speaker_wave_2_fill',
        `音量 ${Math.round(nextV * 100)}%`,
        0
      );
    }
  }

  private handlePanEnd(): void {
    if (this.panMode === 'scrub' && this.durationMs > 0) {
      this.seekVideoMs(this.scrubTargetMs);
    }
    this.panMode = 'undecided';
    this.hideHudSoon(550);
    this.resetControlsAutoHideTimer();
  }

  private hudSymbolResource(): Resource {
    if (this.hudSymbolName === 'goforward_10') { return $r('sys.symbol.goforward_10'); }
    if (this.hudSymbolName === 'gobackward_10') { return $r('sys.symbol.gobackward_10'); }
    if (this.hudSymbolName === 'pause_fill') { return $r('sys.symbol.pause_fill'); }
    if (this.hudSymbolName === 'sun_max_fill') { return $r('sys.symbol.sun_max_fill'); }
    if (this.hudSymbolName === 'speaker_wave_2_fill') { return $r('sys.symbol.speaker_wave_2_fill'); }
    if (this.hudSymbolName === 'speaker_slash_fill') { return $r('sys.symbol.speaker_slash_fill'); }
    if (this.hudSymbolName === 'lock_fill') { return $r('sys.symbol.lock_fill'); }
    if (this.hudSymbolName === 'lock_open_fill') { return $r('sys.symbol.lock_open_fill'); }
    if (this.hudSymbolName === 'aspect_ratio') { return $r('sys.symbol.aspect_ratio'); }
    if (this.hudSymbolName === 'timer') { return $r('sys.symbol.timer'); }
    if (this.hudSymbolName === 'waveform') { return $r('sys.symbol.waveform'); }
    if (this.hudSymbolName === 'xmark') { return $r('sys.symbol.xmark'); }
    return $r('sys.symbol.play_fill');
  }

  private repeatModeSymbol(): Resource {
    if (this.audioRepeatMode === 'one') {
      return $r('sys.symbol.repeat_1');
    }
    if (this.audioRepeatMode === 'shuffle') {
      return $r('sys.symbol.shuffle');
    }
    return $r('sys.symbol.repeat');
  }

  private repeatModeLabel(): string {
    if (this.audioRepeatMode === 'one') {
      return '单曲循环';
    }
    if (this.audioRepeatMode === 'all') {
      return '列表循环';
    }
    if (this.audioRepeatMode === 'shuffle') {
      return '随机播放';
    }
    return '顺序播放';
  }

  private formatRightDurationLabel(): string {
    if (this.durationMs <= 0) {
      return '00:00';
    }
    if (this.showRemainingTime) {
      const rem = Math.max(0, this.durationMs - this.positionMs);
      return `-${formatMediaDurationMs(rem)}`;
    }
    return formatMediaDurationMs(this.durationMs);
  }

  @Builder
  private musicArtworkCard(sizeVp: number, radiusVp: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.displayArtworkUrl.length > 0) {
        MpRemoteImage({
          src: this.displayArtworkUrl,
          imgWidth: sizeVp,
          imgHeight: sizeVp,
          imgRadius: radiusVp,
          placeholderColor: '#22FFFFFF'
        })
      } else if (this.localCoverPixelMap) {
        Image(this.localCoverPixelMap)
          .width(sizeVp)
          .height(sizeVp)
          .objectFit(ImageFit.Cover)
          .borderRadius(radiusVp)
          .clip(true)
      } else {
        SymbolGlyph($r('sys.symbol.music'))
          .fontSize(Math.round(sizeVp * 0.34))
          .fontColor(['#317AF7'])
      }
    }
    .width(sizeVp)
    .height(sizeVp)
    .borderRadius(radiusVp)
    .backgroundColor('#22FFFFFF')
    .clip(true)
    .shadow({ radius: 28, color: '#55000000', offsetX: 0, offsetY: 12 })
  }

  @Builder
  private musicLyricsList(listHeight: Length) {
    if (this.lyricCues.length === 0 && this.plainLyricsLines.length === 0) {
      Column({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.lyrics_square'))
          .fontSize(34)
          .fontColor(['#66FFFFFF'])
        Text('当前曲目暂未附带歌词')
          .fontSize(14)
          .fontColor('#99FFFFFF')
      }
      .width('100%')
      .height(listHeight)
      .justifyContent(FlexAlign.Center)
    } else if (this.lyricCues.length > 0) {
      List({ space: 14, scroller: this.lyricsScroller }) {
        ForEach(this.lyricCues, (cue: LyricLineCue, idx: number) => {
          ListItem() {
            Text(cue.text)
              .width('100%')
              .fontSize(idx === this.activeLyricIdx ? 18 : 14.5)
              .fontWeight(idx === this.activeLyricIdx ? FontWeight.Bold : FontWeight.Regular)
              .fontColor(idx === this.activeLyricIdx ? Color.White : '#80FFFFFF')
              .textAlign(TextAlign.Center)
              .lineHeight(idx === this.activeLyricIdx ? 25 : 21)
              .padding({ left: 20, right: 20, top: 4, bottom: 4 })
              .onClick(() => {
                HarmonyAudioSession.shared().seekMs(cue.timeMs);
              })
          }
        }, (cue: LyricLineCue, idx: number) => `lyric_${idx}_${cue.timeMs}`)
      }
      .width('100%')
      .height(listHeight)
      .scrollBar(BarState.Off)
    } else {
      List({ space: 12 }) {
        ListItem() {
          Text('内嵌歌词（纯文本，无时间轴）')
            .width('100%')
            .fontSize(12)
            .fontColor('#80FFFFFF')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 6 })
        }
        ForEach(this.plainLyricsLines, (line: string, idx: number) => {
          ListItem() {
            Text(line)
              .width('100%')
              .fontSize(15.5)
              .fontColor('#E0FFFFFF')
              .textAlign(TextAlign.Center)
              .lineHeight(23)
              .padding({ left: 20, right: 20, top: 2, bottom: 2 })
          }
        }, (line: string, idx: number) => `plain_lyric_${idx}_${line.length}`)
      }
      .width('100%')
      .height(listHeight)
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private fullMusicStageBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      // 高斯模糊封面沉浸底图
      if (this.displayArtworkUrl.length > 0) {
        Stack() {
          MpRemoteImage({
            src: this.displayArtworkUrl,
            imgWidth: '100%',
            imgHeight: '100%',
            imgRadius: 0,
            placeholderColor: '#101829'
          })
        }
        .width('100%')
        .height('100%')
        .blur(54)
        .opacity(0.45)
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )
      } else if (this.localCoverPixelMap) {
        Image(this.localCoverPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(54)
          .opacity(0.45)
          .expandSafeArea(
            [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
          )
      }
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 165,
          colors: [['#CC0F172A', 0], ['#D9172542', 0.52], ['#F2080B12', 1]]
        })
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )

      Column() {
        // 顶栏：收起、曲名与歌手、歌词切换、队列面板
        Row({ space: 10 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(22)
              .fontColor([Color.White])
          }
          .width(38)
          .height(38)
          .borderRadius(19)
          .backgroundColor('#33FFFFFF')
          .accessibilityText('收起至迷你音乐条')
          .onClick(() => this.onMinimizeToMiniBar())

          Column({ space: 2 }) {
            Text(this.displayTitle)
              .fontSize(15.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.displaySubtitle.length > 0) {
              Text(this.displaySubtitle)
                .fontSize(12)
                .fontColor('#B3FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          Row({ space: 8 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.lyrics_square'))
                .fontSize(20)
                .fontColor([this.showLyricsStage ? '#317AF7' : Color.White])
            }
            .width(38)
            .height(38)
            .borderRadius(19)
            .backgroundColor(this.showLyricsStage ? '#33317AF7' : '#33FFFFFF')
            .accessibilityText(this.showLyricsStage ? '切换至专辑封面视图' : '切换至同步歌词视图')
            .onClick(() => {
              this.showLyricsStage = !this.showLyricsStage;
              if (this.showLyricsStage && this.activeLyricIdx >= 0) {
                setTimeout(() => {
                  try {
                    this.lyricsScroller.scrollToIndex(Math.max(0, this.activeLyricIdx - 2), false);
                  } catch {
                    // ignore
                  }
                }, 60);
              }
            })

            Stack() {
              SymbolGlyph($r('sys.symbol.TV_tv'))
                .fontSize(18)
                .fontColor([Color.White])
            }
            .width(38)
            .height(38)
            .borderRadius(19)
            .backgroundColor('#33FFFFFF')
            .accessibilityText('投屏与音频流转')
            .onClick(() => this.openSheet('cast'))

            Stack() {
              SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
                .fontSize(20)
                .fontColor([Color.White])
            }
            .width(38)
            .height(38)
            .borderRadius(19)
            .backgroundColor('#33FFFFFF')
            .accessibilityText('更多音乐选项')
            .bindMenu(this.musicOptionsMenuBuilder())
          }
        }
        .width('100%')
        .padding({
          left: 16 + this.safeLeftVp,
          right: 16 + this.safeRightVp,
          top: Math.max(12, this.safeTopVp + 6),
          bottom: 8
        })

        // 主舞台：横屏紧凑双栏 / 竖屏封面或歌词舞台
        if (this.isShortLandscape()) {
          Row({ space: 20 }) {
            Column({ space: 10 }) {
              this.musicArtworkCard(112, 22)
              Text(this.displayTitle)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.displaySubtitle)
                .fontSize(12)
                .fontColor('#B3FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('42%')
            .justifyContent(FlexAlign.Center)

            Column() {
              this.musicLyricsList('100%')
            }
            .layoutWeight(1)
            .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 20 + this.safeLeftVp, right: 20 + this.safeRightVp })
        } else if (this.showLyricsStage) {
          Column() {
            this.musicLyricsList('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 8, bottom: 8 })
        } else {
          Column({ space: 18 }) {
            this.musicArtworkCard(Math.min(268, Math.max(180, Math.round(this.windowWidthVp * 0.66))), 28)

            Column({ space: 6 }) {
              Text(this.displayTitle)
                .fontSize(21)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .maxLines(2)
                .textAlign(TextAlign.Center)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 24, right: 24 })
              if (this.displaySubtitle.length > 0) {
                Text(this.displaySubtitle)
                  .fontSize(14)
                  .fontColor('#B8FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 28, right: 28 })
              }
            }

            if (this.activeLyricIdx >= 0 && this.activeLyricIdx < this.lyricCues.length) {
              Text(this.lyricCues[this.activeLyricIdx].text)
                .fontSize(14)
                .fontColor('#E6FFFFFF')
                .maxLines(2)
                .textAlign(TextAlign.Center)
                .padding({ left: 28, right: 28, top: 6, bottom: 6 })
                .borderRadius(14)
                .backgroundColor('#22FFFFFF')
                .onClick(() => {
                  this.showLyricsStage = true;
                })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }

        // 底部音乐传输面板
        Column({ space: this.isShortLandscape() ? 4 : 10 }) {
          Column({ space: 2 }) {
            Slider({ value: this.progress, min: 0, max: 100 })
              .selectedColor('#317AF7')
              .trackColor('#38FFFFFF')
              .onChange((val: number, mode: SliderChangeMode) => this.handleSliderChange(val, mode))
            Row() {
              Text(formatMediaDurationMs(this.positionMs))
                .fontSize(11.5)
                .fontColor('#B8FFFFFF')
              Blank()
              Text(this.formatRightDurationLabel())
                .fontSize(11.5)
                .fontColor('#B8FFFFFF')
                .onClick(() => {
                  this.showRemainingTime = !this.showRemainingTime;
                })
            }
            .width('100%')
          }

          Row() {
            // 循环/随机切换
            Stack() {
              SymbolGlyph(this.repeatModeSymbol())
                .fontSize(21)
                .fontColor([this.audioRepeatMode === 'sequence' ? '#CCFFFFFF' : '#317AF7'])
            }
            .width(42)
            .height(42)
            .borderRadius(21)
            .accessibilityText(`切换循环模式，当前${this.repeatModeLabel()}`)
            .onClick(() => {
              const nextMode = HarmonyAudioSession.shared().cycleRepeatMode();
              this.audioRepeatMode = nextMode;
            })

            Blank()

            // 上一首
            Stack() {
              SymbolGlyph($r('sys.symbol.backward_end_fill'))
                .fontSize(25)
                .fontColor([Color.White])
            }
            .width(48)
            .height(48)
            .borderRadius(24)
            .accessibilityText('上一曲')
            .onClick(() => {
              HarmonyAudioSession.shared().playPrevious().catch(() => {});
            })

            Blank()

            // 播放 / 暂停 / 缓冲
            Stack() {
              if (this.isBuffering) {
                LoadingProgress()
                  .width(30)
                  .height(30)
                  .color(Color.White)
              } else {
                SymbolGlyph($r(this.isPlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
                  .fontSize(32)
                  .fontColor([Color.White])
              }
            }
            .width(66)
            .height(66)
            .borderRadius(33)
            .backgroundColor('#317AF7')
            .shadow({ radius: 18, color: '#66317AF7', offsetX: 0, offsetY: 6 })
            .accessibilityText(this.isPlaying ? '暂停' : '播放')
            .onClick(() => this.handleTogglePlay())

            Blank()

            // 下一首
            Stack() {
              SymbolGlyph($r('sys.symbol.forward_end_fill'))
                .fontSize(25)
                .fontColor([this.audioQueue.length > 1 ? Color.White : '#66FFFFFF'])
            }
            .width(48)
            .height(48)
            .borderRadius(24)
            .accessibilityText('下一曲')
            .onClick(() => {
              HarmonyAudioSession.shared().playNext(false).catch(() => {});
            })

            Blank()

            // 播放队列入口（播放速度统一收口至右上角菜单）
            if (this.audioQueue.length > 0) {
              Stack() {
                SymbolGlyph($r('sys.symbol.music_note_list'))
                  .fontSize(20)
                  .fontColor([Color.White])
              }
              .width(42)
              .height(42)
              .borderRadius(21)
              .backgroundColor('#22FFFFFF')
              .accessibilityText('播放列表')
              .onClick(() => this.openSheet('queue'))
            } else {
              Row()
                .width(42)
                .height(42)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: 22 + this.safeLeftVp,
          right: 22 + this.safeRightVp,
          bottom: Math.max(18, this.safeBottomVp + (this.isShortLandscape() ? 6 : 14))
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private musicOptionsMenuBuilder() {
    Menu() {
      MenuItem({ content: `播放速度 (${HARMONY_SPEED_LABELS[this.speedIndex]})` })
        .onClick(() => { this.openSheet('speed'); })
      MenuItem({ content: this.showLyricsStage ? '返回专辑封面' : '同步歌词视图' })
        .onClick(() => {
          this.showLyricsStage = !this.showLyricsStage;
          if (this.showLyricsStage && this.activeLyricIdx >= 0) {
            setTimeout(() => {
              try {
                this.lyricsScroller.scrollToIndex(Math.max(0, this.activeLyricIdx - 2), false);
              } catch {
                // ignore
              }
            }, 60);
          }
        })
      if (this.audioQueue.length > 0) {
        MenuItem({ content: `播放列表 (${this.audioQueue.length})` })
          .onClick(() => { this.openSheet('queue'); })
      }
      MenuItem({ content: '停止并关闭' })
        .onClick(() => {
          HarmonyAudioSession.shared().stopAndRelease();
          this.onClose();
        })
    }
  }

  /** 视频底栏图标按钮，保留原生点击反馈、选中状态和完整的无障碍说明。 */
  @Builder
  private videoControlIcon(symbol: Resource, label: string, active: boolean, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([active ? '#6099FF' : Color.White])
    }
    .width(44)
    .height(44)
    .padding(0)
    .backgroundColor(active ? '#26317AF7' : Color.Transparent)
    .accessibilityText(label)
    .onClick(onTap)
  }

  /** 根据当前面板类型构建系统原生播放设置弹层。 */
  @Builder
  private playerSheetBuilder() {
    Column({ space: 12 }) {
      Row() {
        Text(
          this.activeSheetKind === 'subtitles'
            ? '字幕轨道'
            : (this.activeSheetKind === 'audioTracks'
              ? '音轨选择'
              : (this.activeSheetKind === 'speed'
                ? '播放倍速'
                : (this.activeSheetKind === 'engine'
                  ? '更多播放选项'
                  : (this.activeSheetKind === 'cast'
                    ? '投屏与音频流转'
                    : (this.activeSheetKind === 'danmakuSettings'
                      ? '弹幕设置'
                      : (this.activeSheetKind === 'danmakuMatch'
                        ? '搜索弹幕剧集'
                        : (this.request.isAudio ? '播放队列' : '剧集选集')))))))
        )
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Blank()
        Stack() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor(['#CCFFFFFF'])
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor('#24FFFFFF')
        .onClick(() => {
          this.showPlayerSheet = false;
          this.resetControlsAutoHideTimer();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 4 })

      if (this.activeSheetKind === 'subtitles') {
        List({ space: 8 }) {
          ListItem() {
            Row() {
              Text('关闭字幕')
                .fontSize(15)
                .fontWeight(this.selectedSubId === 'off' ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.selectedSubId === 'off' ? '#317AF7' : Color.White)
              Blank()
              if (this.selectedSubId === 'off') {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(18)
                  .fontColor(['#317AF7'])
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 13, bottom: 13 })
            .borderRadius(14)
            .backgroundColor(this.selectedSubId === 'off' ? '#26317AF7' : '#18FFFFFF')
            .onClick(() => {
              this.selectSubtitleOption(null).catch(() => {});
              this.showPlayerSheet = false;
              this.resetControlsAutoHideTimer();
            })
          }

          ForEach(this.subtitleOptions, (opt: HarmonySubtitleOption) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(opt.label)
                    .fontSize(14.5)
                    .fontWeight(this.selectedSubId === opt.id ? FontWeight.Bold : FontWeight.Regular)
                    .fontColor(this.selectedSubId === opt.id ? '#317AF7' : Color.White)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.isSubtitleLoading && this.selectedSubId === opt.id) {
                    Text('正在加载字幕…')
                      .fontSize(11.5)
                      .fontColor('#317AF7')
                  } else if (this.failedSubId === opt.id) {
                    Text('加载失败 · 点击重试')
                      .fontSize(11.5)
                      .fontColor('#FF8A80')
                  } else {
                    Text(opt.isExternal ? `外挂字幕${opt.format ? ' · ' + opt.format.toUpperCase() : ''}` : '内封字幕轨')
                      .fontSize(11.5)
                      .fontColor('#99FFFFFF')
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (this.selectedSubId === opt.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor(['#317AF7'])
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 11, bottom: 11 })
              .borderRadius(14)
              .backgroundColor(this.selectedSubId === opt.id ? '#26317AF7' : '#18FFFFFF')
              .onClick(() => {
                this.selectSubtitleOption(opt).catch(() => {});
                this.showPlayerSheet = false;
                this.resetControlsAutoHideTimer();
              })
            }
          }, (opt: HarmonySubtitleOption) => opt.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 20 })
      } else if (this.activeSheetKind === 'audioTracks') {
        if (this.audioTrackOptions.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.waveform'))
              .fontSize(32)
              .fontColor(['#66FFFFFF'])
            Text('当前媒体包含默认主音轨，暂无其他可切换音轨')
              .fontSize(13.5)
              .fontColor('#99FFFFFF')
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.audioTrackOptions, (opt: HarmonyAudioTrackOption) => {
              ListItem() {
                Row() {
                  Text(opt.label)
                    .fontSize(14.5)
                    .fontWeight(this.selectedAudioTrackIndex === opt.trackIndex ? FontWeight.Bold : FontWeight.Regular)
                    .fontColor(this.selectedAudioTrackIndex === opt.trackIndex ? '#317AF7' : Color.White)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.selectedAudioTrackIndex === opt.trackIndex) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(18)
                      .fontColor(['#317AF7'])
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 13, bottom: 13 })
                .borderRadius(14)
                .backgroundColor(this.selectedAudioTrackIndex === opt.trackIndex ? '#26317AF7' : '#18FFFFFF')
                .onClick(() => {
                  this.selectAudioTrack(opt).catch(() => {});
                  this.showPlayerSheet = false;
                  this.resetControlsAutoHideTimer();
                })
              }
            }, (opt: HarmonyAudioTrackOption) => `aud_${opt.trackIndex}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 20 })
        }
      } else if (this.activeSheetKind === 'speed') {
        List({ space: 8 }) {
          ForEach(HARMONY_SPEED_LABELS, (lbl: string, idx: number) => {
            ListItem() {
              Row() {
                Text(lbl === '1.0x' ? '1.0x（标准倍速）' : lbl)
                  .fontSize(15)
                  .fontWeight(this.speedIndex === idx ? FontWeight.Bold : FontWeight.Regular)
                  .fontColor(this.speedIndex === idx ? '#317AF7' : Color.White)
                Blank()
                if (this.speedIndex === idx) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor(['#317AF7'])
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })
              .borderRadius(14)
              .backgroundColor(this.speedIndex === idx ? '#26317AF7' : '#18FFFFFF')
              .onClick(() => {
                this.applySpeedIndex(idx);
                this.showPlayerSheet = false;
              })
            }
          }, (lbl: string) => `spd_${lbl}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 20 })
      } else if (this.activeSheetKind === 'queue') {
        List({ space: 8 }) {
          ForEach(
            this.request.isAudio ? this.audioQueue : this.videoQueue,
            (item: HarmonyQueueItem, idx: number) => {
              ListItem() {
                Row({ space: 10 }) {
                  Text(String(idx + 1).padStart(2, '0'))
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(
                      (this.request.isAudio ? this.audioQueueIdx : this.videoQueueIdx) === idx
                        ? '#317AF7'
                        : '#88FFFFFF'
                    )
                    .width(26)

                  Column({ space: 2 }) {
                    Text(item.title)
                      .fontSize(14.5)
                      .fontWeight(
                        (this.request.isAudio ? this.audioQueueIdx : this.videoQueueIdx) === idx
                          ? FontWeight.Bold
                          : FontWeight.Regular
                      )
                      .fontColor(
                        (this.request.isAudio ? this.audioQueueIdx : this.videoQueueIdx) === idx
                          ? '#317AF7'
                          : Color.White
                      )
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if ((item.subtitle ?? '').length > 0 || (item.artist ?? '').length > 0) {
                      Text((item.subtitle && item.subtitle.length > 0) ? item.subtitle : (item.artist ?? ''))
                        .fontSize(11.5)
                        .fontColor('#99FFFFFF')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if ((this.request.isAudio ? this.audioQueueIdx : this.videoQueueIdx) === idx) {
                    SymbolGlyph($r('sys.symbol.waveform'))
                      .fontSize(18)
                      .fontColor(['#317AF7'])
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 11, bottom: 11 })
                .borderRadius(14)
                .backgroundColor(
                  (this.request.isAudio ? this.audioQueueIdx : this.videoQueueIdx) === idx
                    ? '#26317AF7'
                    : '#18FFFFFF'
                )
                .onClick(() => {
                  this.showPlayerSheet = false;
                  if (this.request.isAudio) {
                    HarmonyAudioSession.shared().playQueueIndex(idx).catch(() => {});
                  } else {
                    this.playVideoEpisodeAtIndex(idx).catch(() => {});
                  }
                })
              }
            },
            (item: HarmonyQueueItem, idx: number) => `q_${idx}_${item.itemId}_${item.title}`
          )
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 20 })
      } else if (this.activeSheetKind === 'engine') {
        Column({ space: 10 }) {
          if (this.activeRouteServer.length > 0 && this.routeSummaryLabel().length > 0) {
            Row() {
              Text('播放方式')
                .fontSize(13.5)
                .fontColor('#99FFFFFF')
                .layoutWeight(1)
              Text(this.routeSummaryLabel())
                .fontSize(13.5)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 11, bottom: 11 })
            .borderRadius(14)
            .backgroundColor('#18FFFFFF')
          }

          Text('切换内核时自动保留当前进度且不中断媒体服务器正在播放状态')
            .fontSize(12)
            .fontColor('#99FFFFFF')
            .width('100%')

          Row() {
            Column({ space: 3 }) {
              Text('AVPlayer 原生内核')
                .fontSize(15)
                .fontWeight(this.activeEngineKind === 'native' ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.activeEngineKind === 'native' ? '#317AF7' : Color.White)
              Text('系统硬解省电秒开，完整支持画中画小窗')
                .fontSize(12)
                .fontColor('#99FFFFFF')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.activeEngineKind === 'native') {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor(['#317AF7'])
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .borderRadius(14)
          .backgroundColor(this.activeEngineKind === 'native' ? '#26317AF7' : '#18FFFFFF')
          .onClick(() => {
            this.showPlayerSheet = false;
            this.switchVideoEngine('native');
          })

          Row() {
            Column({ space: 3 }) {
              Text('IJK 增强内核（FFmpeg）')
                .fontSize(15)
                .fontWeight(this.activeEngineKind === 'enhanced' ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.activeEngineKind === 'enhanced' ? '#317AF7' : Color.White)
              Text('补齐 MKV / TS / FLV 与 DTS / TrueHD / AC3 / EAC3 及软解')
                .fontSize(12)
                .fontColor('#99FFFFFF')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.activeEngineKind === 'enhanced') {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor(['#317AF7'])
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .borderRadius(14)
          .backgroundColor(this.activeEngineKind === 'enhanced' ? '#26317AF7' : '#18FFFFFF')
          .onClick(() => {
            this.showPlayerSheet = false;
            this.switchVideoEngine('enhanced');
          })

          if (resolveSafeExternalUri(this.activeVideoReq).length > 0) {
            Row() {
              Column({ space: 3 }) {
                Text('使用其他应用播放')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                Text('通过系统安全打开无凭据直链或本机媒体文件')
                  .fontSize(12)
                  .fontColor('#99FFFFFF')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(16).fontColor(['#CCFFFFFF'])
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 13, bottom: 13 })
            .borderRadius(14)
            .backgroundColor('#18FFFFFF')
            .onClick(() => {
              this.showPlayerSheet = false;
              this.setVideoPlaying(false);
              const ctx = this.getUIContext().getHostContext() ?? undefined;
              launchHarmonyExternalPlayer(ctx, this.activeVideoReq).then((ok: boolean) => {
                if (!ok) {
                  this.showTransientHud('xmark', '未找到可用的外部播放器');
                }
              }).catch(() => {});
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      } else if (this.activeSheetKind === 'cast') {
        Column({ space: 10 }) {
          Text('通过鸿蒙无线投屏（Cast+）或播控中心流转，可将音视频输出至智慧屏、电视或无线音箱。')
            .fontSize(12.5)
            .fontColor('#99FFFFFF')
            .width('100%')

          Row() {
            Column({ space: 3 }) {
              Text('无线投屏（Cast+ / 智慧屏镜像）')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text('兼容全部播放内核、外挂字幕与实时弹幕')
                .fontSize(12)
                .fontColor('#99FFFFFF')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.TV_tv')).fontSize(18).fontColor(['#317AF7'])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .borderRadius(14)
          .backgroundColor('#18FFFFFF')
          .onClick(() => {
            this.showPlayerSheet = false;
            this.openSystemCastOrBluetoothSettings(
              'multi_device_collaboration_settings',
              '请从右上角下拉控制中心开启「无线投屏」'
            );
          })

          Row() {
            Column({ space: 3 }) {
              Text('蓝牙与无线音频输出')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
              Text('切换至蓝牙耳机、华为音箱或播控中心音频设备')
                .fontSize(12)
                .fontColor('#99FFFFFF')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.speaker_wave_2_fill')).fontSize(18).fontColor(['#317AF7'])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 13, bottom: 13 })
          .borderRadius(14)
          .backgroundColor('#18FFFFFF')
          .onClick(() => {
            this.showPlayerSheet = false;
            this.openSystemCastOrBluetoothSettings(
              'bluetooth_entry',
              '请从右上角下拉播控中心切换音频输出设备'
            );
          })

          if (resolveSafeExternalUri(this.request.isAudio ? this.request : this.activeVideoReq).length > 0) {
            Row() {
              Column({ space: 3 }) {
                Text('使用外部 DLNA 投屏应用打开')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                Text('通过系统安全打开无凭据直链或本机媒体文件')
                  .fontSize(12)
                  .fontColor('#99FFFFFF')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(16).fontColor(['#CCFFFFFF'])
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 13, bottom: 13 })
            .borderRadius(14)
            .backgroundColor('#18FFFFFF')
            .onClick(() => {
              this.showPlayerSheet = false;
              if (this.request.isAudio) {
                if (HarmonyAudioSession.shared().isPlaying()) {
                  HarmonyAudioSession.shared().togglePlayPause();
                }
              } else {
                this.setVideoPlaying(false);
              }
              const ctx = this.getUIContext().getHostContext() ?? undefined;
              const targetReq = this.request.isAudio ? this.request : this.activeVideoReq;
              launchHarmonyExternalPlayer(ctx, targetReq).then((ok: boolean) => {
                if (!ok) {
                  this.showTransientHud('xmark', '未找到可用的外部投屏或播放应用');
                }
              }).catch(() => {});
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      } else if (this.activeSheetKind === 'danmakuSettings') {
        Scroll() {
          Column({ space: 12 }) {
            // 匹配信息与纠偏操作栏
            Column({ space: 8 }) {
              Text(this.danmakuMatchedSummaryText())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(`当前已加载 ${this.danmakuTotalCount} 条弹幕${this.danmakuFromBinding ? ' · 已手动绑定' : ''}`)
                .fontSize(12)
                .fontColor('#99FFFFFF')
                .width('100%')
              Row({ space: 8 }) {
                Text('搜索 / 换集')
                  .fontSize(12.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .borderRadius(14)
                  .backgroundColor('#317AF7')
                  .onClick(() => this.openDanmakuManualMatch())
                if (this.danmakuEpisodeId > 0) {
                  Text('强制刷新')
                    .fontSize(12.5)
                    .fontColor('#D9FFFFFF')
                    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                    .borderRadius(14)
                    .backgroundColor('#24FFFFFF')
                    .onClick(() => {
                      if (this.danmakuSheetBusy) { return; }
                      this.danmakuSheetBusy = true;
                      this.loadDanmakuCommentsByEpisode(this.danmakuEpisodeId, this.videoLoadGeneration, true).then(() => {
                        this.danmakuSheetBusy = false;
                        this.danmakuSheetFeedback = '已重新拉取最新弹幕';
                      }).catch(() => {
                        this.danmakuSheetBusy = false;
                      });
                    })
                }
              }.width('100%')
            }
            .width('100%')
            .padding(12)
            .borderRadius(14)
            .backgroundColor('#18FFFFFF')

            // 开关与透明度/字号/速度滑块
            Row() {
              Text('显示弹幕').fontSize(14.5).fontColor(Color.White).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.danmakuVisible }).selectedColor('#317AF7')
                .onChange((v: boolean) => {
                  DanmakuPreferencesStore.setEnabled(v);
                  this.danmakuVisible = v;
                  this.danmakuConfigVersion += 1;
                })
            }.width('100%')

            Column({ space: 2 }) {
              Row() {
                Text('不透明度').fontSize(13).fontColor('#CCFFFFFF').layoutWeight(1)
                Text(`${Math.round(this.danmakuOpacity * 100)}%`).fontSize(12.5).fontColor('#99FFFFFF')
              }.width('100%')
              Slider({ value: Math.round(this.danmakuOpacity * 100), min: 20, max: 100 })
                .selectedColor('#317AF7')
                .onChange((v: number) => {
                  const next = v / 100;
                  DanmakuPreferencesStore.setOpacity(next);
                  this.danmakuOpacity = DanmakuPreferencesStore.getOpacity();
                  this.danmakuConfigVersion += 1;
                })
            }.width('100%')

            Column({ space: 2 }) {
              Row() {
                Text('字号缩放').fontSize(13).fontColor('#CCFFFFFF').layoutWeight(1)
                Text(`${Math.round(this.danmakuFontScale * 100)}%`).fontSize(12.5).fontColor('#99FFFFFF')
              }.width('100%')
              Slider({ value: Math.round(this.danmakuFontScale * 100), min: 75, max: 150 })
                .selectedColor('#317AF7')
                .onChange((v: number) => {
                  DanmakuPreferencesStore.setFontScale(v / 100);
                  this.danmakuFontScale = DanmakuPreferencesStore.getFontScale();
                  this.danmakuConfigVersion += 1;
                })
            }.width('100%')

            Column({ space: 2 }) {
              Row() {
                Text('弹幕速度').fontSize(13).fontColor('#CCFFFFFF').layoutWeight(1)
                Text(`${this.danmakuSpeed.toFixed(1)}x`).fontSize(12.5).fontColor('#99FFFFFF')
              }.width('100%')
              Slider({ value: Math.round(this.danmakuSpeed * 100), min: 60, max: 160 })
                .selectedColor('#317AF7')
                .onChange((v: number) => {
                  DanmakuPreferencesStore.setSpeed(v / 100);
                  this.danmakuSpeed = DanmakuPreferencesStore.getSpeed();
                  this.danmakuConfigVersion += 1;
                })
            }.width('100%')

            // 显示区域与同屏上限
            Text('显示区域').fontSize(13).fontColor('#CCFFFFFF').width('100%')
            Row({ space: 8 }) {
              ForEach([0.25, 0.5, 0.75, 1.0], (ratio: number) => {
                Text(ratio === 0.25 ? '1/4屏' : (ratio === 0.5 ? '半屏' : (ratio === 0.75 ? '3/4屏' : '全屏')))
                  .fontSize(12)
                  .fontColor(Math.abs(this.danmakuAreaRatio - ratio) < 0.05 ? Color.White : '#B3FFFFFF')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(12)
                  .backgroundColor(Math.abs(this.danmakuAreaRatio - ratio) < 0.05 ? '#317AF7' : '#22FFFFFF')
                  .onClick(() => {
                    DanmakuPreferencesStore.setAreaRatio(ratio);
                    this.danmakuAreaRatio = ratio;
                    this.danmakuConfigVersion += 1;
                  })
              }, (r: number) => `area_${r}`)
            }.width('100%')

            Text('同屏弹幕上限').fontSize(13).fontColor('#CCFFFFFF').width('100%')
            Row({ space: 8 }) {
              ForEach([20, 40, 60, 100], (cap: number) => {
                Text(`${cap} 条`)
                  .fontSize(12)
                  .fontColor(this.danmakuMaxOnScreen === cap ? Color.White : '#B3FFFFFF')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(12)
                  .backgroundColor(this.danmakuMaxOnScreen === cap ? '#317AF7' : '#22FFFFFF')
                  .onClick(() => {
                    DanmakuPreferencesStore.setMaxOnScreen(cap);
                    this.danmakuMaxOnScreen = cap;
                    this.danmakuConfigVersion += 1;
                  })
              }, (c: number) => `cap_${c}`)
            }.width('100%')

            // 类型过滤与去重
            Row({ space: 8 }) {
              Text('滚动').fontSize(12).fontColor(this.danmakuAllowScroll ? Color.White : '#88FFFFFF')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(12)
                .backgroundColor(this.danmakuAllowScroll ? '#317AF7' : '#22FFFFFF')
                .onClick(() => {
                  this.danmakuAllowScroll = !this.danmakuAllowScroll;
                  DanmakuPreferencesStore.setAllowScroll(this.danmakuAllowScroll);
                  this.rebuildDanmakuTimeline();
                })
              Text('顶部').fontSize(12).fontColor(this.danmakuAllowTop ? Color.White : '#88FFFFFF')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(12)
                .backgroundColor(this.danmakuAllowTop ? '#317AF7' : '#22FFFFFF')
                .onClick(() => {
                  this.danmakuAllowTop = !this.danmakuAllowTop;
                  DanmakuPreferencesStore.setAllowTop(this.danmakuAllowTop);
                  this.rebuildDanmakuTimeline();
                })
              Text('底部').fontSize(12).fontColor(this.danmakuAllowBottom ? Color.White : '#88FFFFFF')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(12)
                .backgroundColor(this.danmakuAllowBottom ? '#317AF7' : '#22FFFFFF')
                .onClick(() => {
                  this.danmakuAllowBottom = !this.danmakuAllowBottom;
                  DanmakuPreferencesStore.setAllowBottom(this.danmakuAllowBottom);
                  this.rebuildDanmakuTimeline();
                })
              Text('彩色').fontSize(12).fontColor(this.danmakuAllowColor ? Color.White : '#88FFFFFF')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(12)
                .backgroundColor(this.danmakuAllowColor ? '#317AF7' : '#22FFFFFF')
                .onClick(() => {
                  this.danmakuAllowColor = !this.danmakuAllowColor;
                  DanmakuPreferencesStore.setAllowColor(this.danmakuAllowColor);
                  this.rebuildDanmakuTimeline();
                })
              Text('去重').fontSize(12).fontColor(this.danmakuMergeDup ? Color.White : '#88FFFFFF')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(12)
                .backgroundColor(this.danmakuMergeDup ? '#317AF7' : '#22FFFFFF')
                .onClick(() => {
                  this.danmakuMergeDup = !this.danmakuMergeDup;
                  DanmakuPreferencesStore.setMergeDuplicates(this.danmakuMergeDup);
                  this.rebuildDanmakuTimeline();
                })
            }.width('100%')

            // 时间轴偏移微调
            Row() {
              Text(`时间偏移：${this.danmakuShiftMs >= 0 ? '+' : ''}${(this.danmakuShiftMs / 1000).toFixed(1)}s`)
                .fontSize(13).fontColor('#CCFFFFFF').layoutWeight(1)
              if (this.danmakuEpisodeId > 0) {
                Text('保存偏移到服务端')
                  .fontSize(12).fontColor('#317AF7').fontWeight(FontWeight.Bold)
                  .onClick(() => {
                    MoviePilotRepository.shared().saveDanmakuBinding({
                      server: this.activeVideoReq.server,
                      itemId: this.activeVideoReq.itemId,
                      tmdbId: this.activeVideoReq.tmdbId,
                      seasonNumber: this.activeVideoReq.seasonNumber,
                      episodeNumber: this.activeVideoReq.episodeNumber,
                      episodeId: this.danmakuEpisodeId,
                      animeId: this.danmakuAnimeId,
                      animeTitle: this.danmakuAnimeTitle,
                      episodeTitle: this.danmakuEpisodeTitle,
                      shiftMs: this.danmakuShiftMs
                    }).then(() => {
                      this.danmakuFromBinding = true;
                      this.danmakuSheetFeedback = '已将时间偏移保存到服务端';
                    }).catch(() => {});
                  })
              }
            }.width('100%')

            Row({ space: 6 }) {
              ForEach([-5000, -1000, -500, 500, 1000, 5000], (delta: number) => {
                Text(`${delta > 0 ? '+' : ''}${delta / 1000}s`)
                  .fontSize(11.5)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                  .borderRadius(10)
                  .backgroundColor('#24FFFFFF')
                  .onClick(() => {
                    this.danmakuShiftMs += delta;
                    this.rebuildDanmakuTimeline();
                  })
              }, (d: number) => `sh_${d}`)
            }.width('100%')

            // 关键词屏蔽
            Text('关键词屏蔽（支持 /正则/）').fontSize(13).fontColor('#CCFFFFFF').width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.danmakuKeywordDraft, placeholder: '输入屏蔽词' })
                .layoutWeight(1)
                .fontColor(Color.White)
                .placeholderColor('#88FFFFFF')
                .backgroundColor('#22FFFFFF')
                .borderRadius(12)
                .onChange((v: string) => { this.danmakuKeywordDraft = v; })
              Text('添加')
                .fontSize(12.5).fontWeight(FontWeight.Bold).fontColor(Color.White)
                .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                .borderRadius(12).backgroundColor('#317AF7')
                .onClick(() => {
                  const next = DanmakuPreferencesStore.addBlockKeyword(this.danmakuKeywordDraft);
                  this.danmakuBlockKeywords = next;
                  this.danmakuKeywordDraft = '';
                  this.rebuildDanmakuTimeline();
                })
            }.width('100%')

            if (this.danmakuBlockKeywords.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.danmakuBlockKeywords, (kw: string) => {
                  Row({ space: 4 }) {
                    Text(kw).fontSize(11.5).fontColor(Color.White)
                    Text('×').fontSize(12).fontColor('#B3FFFFFF')
                  }
                  .padding({ left: 10, right: 8, top: 5, bottom: 5 })
                  .margin({ right: 6, bottom: 6 })
                  .borderRadius(12)
                  .backgroundColor('#26FFFFFF')
                  .onClick(() => {
                    this.danmakuBlockKeywords = DanmakuPreferencesStore.removeBlockKeyword(kw);
                    this.rebuildDanmakuTimeline();
                  })
                }, (kw: string) => `kw_${kw}`)
              }.width('100%')
            }

            if (this.danmakuSheetFeedback.length > 0) {
              Text(this.danmakuSheetFeedback).fontSize(12).fontColor('#34C759').width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 24 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      } else if (this.activeSheetKind === 'danmakuMatch') {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            TextInput({ text: this.danmakuSearchQuery, placeholder: '输入作品名搜索弹幕' })
              .layoutWeight(1)
              .fontColor(Color.White)
              .placeholderColor('#88FFFFFF')
              .backgroundColor('#22FFFFFF')
              .borderRadius(12)
              .onChange((v: string) => { this.danmakuSearchQuery = v; })
              .onSubmit(() => this.triggerDanmakuSearch())
            Text('搜索')
              .fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(12).backgroundColor('#317AF7')
              .onClick(() => this.triggerDanmakuSearch())
          }.width('100%')

          if (this.danmakuFromBinding) {
            Row() {
              Text('当前为手动绑定状态').fontSize(12).fontColor('#99FFFFFF').layoutWeight(1)
              Text('解绑并恢复自动匹配')
                .fontSize(12).fontColor('#FF6B6B').fontWeight(FontWeight.Bold)
                .onClick(() => {
                  MoviePilotRepository.shared().deleteDanmakuBinding({
                    server: this.activeVideoReq.server,
                    itemId: this.activeVideoReq.itemId,
                    tmdbId: this.activeVideoReq.tmdbId,
                    seasonNumber: this.activeVideoReq.seasonNumber,
                    episodeNumber: this.activeVideoReq.episodeNumber
                  }).then(() => {
                    this.showPlayerSheet = false;
                    this.showTransientHud('checkmark', '已解除手动绑定');
                    this.loadDanmakuForRequest(this.activeVideoReq, this.videoLoadGeneration).catch(() => {});
                  }).catch(() => {});
                })
            }.width('100%')
          }

          if (this.danmakuSearchLoading) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color('#317AF7')
              Text('正在搜索弹幕库…').fontSize(13).fontColor('#99FFFFFF')
            }.width('100%').padding({ top: 12 })
          } else if (this.danmakuSearchError.length > 0) {
            Text(this.danmakuSearchError).fontSize(12.5).fontColor('#FF8A80').width('100%')
          }

          if (this.danmakuActiveBangumi) {
            Row({ space: 8 }) {
              Text('← 返回作品列表')
                .fontSize(12.5).fontColor('#317AF7').fontWeight(FontWeight.Bold)
                .onClick(() => { this.danmakuActiveBangumi = null; })
              Text(this.danmakuActiveBangumi.animeTitle)
                .fontSize(13.5).fontColor(Color.White).fontWeight(FontWeight.Bold)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }.width('100%')

            List({ space: 8 }) {
              ForEach(this.danmakuActiveBangumi.episodes, (ep: MpDanmakuEpisodeCandidate) => {
                ListItem() {
                  Row() {
                    Text(ep.episodeTitle || `第 ${ep.episodeNumber ?? ep.episodeId} 集`)
                      .fontSize(14).fontColor(Color.White).layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('选用').fontSize(12).fontColor('#317AF7').fontWeight(FontWeight.Bold)
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  .borderRadius(12)
                  .backgroundColor('#18FFFFFF')
                  .onClick(() => this.selectDanmakuCandidate(ep))
                }
              }, (ep: MpDanmakuEpisodeCandidate) => `bg_ep_${ep.episodeId}`)
            }.width('100%').layoutWeight(1)
          } else if (this.danmakuSearchResults.length > 0) {
            List({ space: 8 }) {
              ForEach(this.danmakuSearchResults, (anime: MpDanmakuAnimeSearchItem) => {
                ListItem() {
                  Column({ space: 3 }) {
                    Text(anime.animeTitle)
                      .fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(Color.White)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(`${anime.animeType ?? '作品'}${anime.episodeCount ? ' · ' + anime.episodeCount + ' 集' : ''}`)
                      .fontSize(11.5).fontColor('#99FFFFFF').width('100%')
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 11, bottom: 11 })
                  .borderRadius(12)
                  .backgroundColor('#18FFFFFF')
                  .onClick(() => {
                    if (anime.episodes.length > 0) {
                      this.danmakuActiveBangumi = {
                        animeId: anime.animeId,
                        animeTitle: anime.animeTitle,
                        animeType: anime.animeType,
                        episodes: anime.episodes
                      };
                    } else {
                      this.danmakuSearchLoading = true;
                      MoviePilotRepository.shared().fetchDanmakuBangumi(anime.animeId).then((bg: MpDanmakuBangumi) => {
                        this.danmakuActiveBangumi = bg;
                        this.danmakuSearchLoading = false;
                      }).catch((err: Error) => {
                        this.danmakuSearchError = err.message || '加载分集列表失败';
                        this.danmakuSearchLoading = false;
                      });
                    }
                  })
                }
              }, (a: MpDanmakuAnimeSearchItem) => `an_${a.animeId}`)
            }.width('100%').layoutWeight(1)
          } else if (this.danmakuCandidates.length > 0) {
            Text('自动匹配候选').fontSize(12.5).fontColor('#99FFFFFF').width('100%')
            List({ space: 8 }) {
              ForEach(this.danmakuCandidates, (cand: MpDanmakuEpisodeCandidate) => {
                ListItem() {
                  Column({ space: 2 }) {
                    Text(cand.animeTitle).fontSize(14).fontColor(Color.White).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(cand.episodeTitle).fontSize(12).fontColor('#99FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 11, bottom: 11 })
                  .borderRadius(12)
                  .backgroundColor('#18FFFFFF')
                  .onClick(() => this.selectDanmakuCandidate(cand))
                }
              }, (c: MpDanmakuEpisodeCandidate) => `cd_${c.episodeId}`)
            }.width('100%').layoutWeight(1)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2151821')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.request.isAudio) {
        this.fullMusicStageBuilder()
      } else {
        // 视频渲染表面层（按活动内核挂载系统 AVPlayer XComponent 或 IJK NAPI XComponent）
        Stack({ alignContent: Alignment.Center }) {
          if (this.activeEngineKind === 'enhanced') {
            XComponent({
              id: this.ijkSurfaceId,
              type: XComponentType.SURFACE,
              libraryname: 'ijkplayer_napi'
            })
              .onLoad((ctx?: object) => {
                if (ctx) {
                  this.enhancedPlayer.bindSurfaceContext(this.ijkSurfaceId, ctx);
                }
              })
              .width(this.videoSurfaceWidth())
              .height(this.videoSurfaceHeight())
              .backgroundColor(Color.Black)
          } else {
            XComponent({
              id: 'mp_harmony_video_surface',
              type: XComponentType.SURFACE,
              controller: this.xComponentController
            })
              .width(this.videoSurfaceWidth())
              .height(this.videoSurfaceHeight())
              .backgroundColor(Color.Black)
          }
        }
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.containerW = Number(newArea.width);
          this.containerH = Number(newArea.height);
        })

        // 原生透明弹幕叠加层（置于视频渲染层之上、手势与控制栏之下，完全穿透触摸）
        if (this.activeVideoReq.danmakuEnabled && !this.isPipActive) {
          HarmonyDanmakuOverlay({
            controller: this.danmakuController,
            danmakuActive: this.danmakuVisible,
            isPlaying: this.isPlaying,
            pipActive: this.isPipActive,
            safeTopVp: Math.max(12, this.safeTopVp),
            configVersion: this.danmakuConfigVersion
          })
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
        }

        // 全屏手势捕获层（置于画布之上、控制按钮之下）
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor('#01000000')
          .onTouch((ev: TouchEvent) => {
            if (ev.touches && ev.touches.length > 0 && ev.touches[0]) {
              this.lastTapLocalX = ev.touches[0].x;
            }
          })
          .gesture(
            GestureGroup(
              GestureMode.Parallel,
              GestureGroup(
                GestureMode.Exclusive,
                TapGesture({ count: 2 })
                  .onAction((ev: GestureEvent) => {
                    this.handleVideoDoubleTap(ev);
                  }),
                TapGesture({ count: 1 })
                  .onAction(() => {
                    this.toggleControlsVisibility();
                  })
              ),
              LongPressGesture({ repeat: false, duration: 450 })
                .onAction(() => {
                  this.handleLongPressStart();
                })
                .onActionEnd(() => {
                  this.handleLongPressEnd();
                })
                .onActionCancel(() => {
                  this.handleLongPressEnd();
                }),
              PanGesture({ fingers: 1, distance: 8 })
                .onActionStart((ev: GestureEvent) => {
                  this.handlePanStart(ev);
                })
                .onActionUpdate((ev: GestureEvent) => {
                  this.handlePanUpdate(ev);
                })
                .onActionEnd(() => {
                  this.handlePanEnd();
                })
                .onActionCancel(() => {
                  this.handlePanEnd();
                })
            )
          )

        // 实时字幕浮层（控制栏展开时自动上移避让）
        if (this.activeSubtitleText.length > 0 && this.selectedSubId !== 'off') {
          Column() {
            Text(this.activeSubtitleText)
              .fontSize(Math.round((this.effectiveLandscape() ? 18 : 15) * this.subtitleScalePref))
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .lineHeight(Math.round((this.effectiveLandscape() ? 25 : 21) * this.subtitleScalePref))
              .textShadow({ radius: 4, color: '#E6000000', offsetX: 0, offsetY: 1 })
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(10)
              .backgroundColor('#AD000000')
          }
          .constraintSize({ maxWidth: '86%' })
          .position({
            x: '7%',
            bottom: (this.controlsVisible && !this.isLocked)
              ? Math.max(96, this.safeBottomVp + (this.isShortLandscape() ? 78 : 96))
              : Math.max(24, this.safeBottomVp + 16)
          })
          .width('86%')
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.None)
        }

        // 外挂字幕慢速加载（如实时字体子集化）非阻塞状态提示
        if (this.isSubtitleLoading && !this.isPipActive && !this.isLongPressBoosting) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(15)
              .height(15)
              .color('#317AF7')
            Text('正在加载字幕…')
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(18)
          .backgroundColor('#CC141824')
          .border({ width: 0.6, color: '#30FFFFFF', radius: 18 })
          .position({ x: '50%', top: Math.max(18, this.safeTopVp + 10) })
          .markAnchor({ x: '50%', y: 0 })
          .hitTestBehavior(HitTestMode.None)
        }

        // 长按 2.0x 倍速悬浮指示条
        if (this.isLongPressBoosting) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.fast_forward'))
              .fontSize(15)
              .fontColor(['#317AF7'])
            Text('2.0x 倍速播放中')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(18)
          .backgroundColor('#CC141824')
          .border({ width: 0.6, color: '#33FFFFFF', radius: 18 })
          .position({ x: '50%', top: Math.max(18, this.safeTopVp + 10) })
          .markAnchor({ x: '50%', y: 0 })
          .hitTestBehavior(HitTestMode.None)
        }

        // 断点续播提示胶囊（6 秒自动消隐，支持一键从头开始）
        if (this.resumeBannerText.length > 0 && !this.isLocked) {
          Row({ space: 10 }) {
            Text(this.resumeBannerText)
              .fontSize(12.5)
              .fontColor('#E6FFFFFF')
            Text('从头开始')
              .fontSize(12.5)
              .fontWeight(FontWeight.Bold)
              .fontColor('#317AF7')
              .onClick(() => this.handleRestartFromBeginning())
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor('#D9161A26')
          .border({ width: 0.6, color: '#30FFFFFF', radius: 18 })
          .position({
            left: 18 + this.safeLeftVp,
            top: Math.max(60, this.safeTopVp + 52)
          })
        }

        // 手势中央 HUD 浮窗（亮度 / 音量 / 进度预览 / 快进退）
        if (this.hudVisible) {
          Row({ space: 8 }) {
            SymbolGlyph(this.hudSymbolResource())
              .fontSize(20)
              .fontColor([Color.White])
            Text(this.hudText)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor('#CC111520')
          .border({ width: 0.6, color: '#2EFFFFFF', radius: 20 })
          .hitTestBehavior(HitTestMode.None)
        }

        // 5 秒「即将播放下一集」悬浮玻璃卡
        if (this.showUpNextCard && this.videoQueueIdx + 1 < this.videoQueue.length && !this.isLocked) {
          Column({ space: 8 }) {
            Text(`即将播放下一集（${this.upNextCountdownSec}s）`)
              .fontSize(11.5)
              .fontColor('#B3FFFFFF')
            Text(this.videoQueue[this.videoQueueIdx + 1].title)
              .fontSize(13.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 10 }) {
              Text('取消')
                .fontSize(12)
                .fontColor('#CCFFFFFF')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(12)
                .backgroundColor('#26FFFFFF')
                .onClick(() => this.dismissUpNextCard())

              Text('立即播放')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(12)
                .backgroundColor('#317AF7')
                .onClick(() => {
                  this.clearUpNextTimer();
                  this.showUpNextCard = false;
                  this.playNextVideoEpisode();
                })
            }
          }
          .width(236)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .borderRadius(18)
          .backgroundColor('#E6161B28')
          .border({ width: 0.7, color: '#33FFFFFF', radius: 18 })
          .position({
            right: 18 + this.safeRightVp,
            bottom: Math.max(96, this.safeBottomVp + 88)
          })
        }

        // 横竖屏通用屏幕锁定/解锁按钮（锁定时点击屏幕依然可以唤出解锁按钮！）
        if (this.controlsVisible) {
          Stack() {
            SymbolGlyph($r(this.isLocked ? 'sys.symbol.lock_fill' : 'sys.symbol.lock_open_fill'))
              .fontSize(21)
              .fontColor([this.isLocked ? '#317AF7' : Color.White])
          }
          .width(42)
          .height(42)
          .borderRadius(21)
          .backgroundColor('#78000000')
          .border({ width: 0.6, color: '#28FFFFFF', radius: 21 })
          .position({ right: 18 + this.safeRightVp, y: '44%' })
          .accessibilityText(this.isLocked ? '解锁屏幕控制' : '锁定屏幕控制')
          .onClick(() => this.handleToggleScreenLock())
        }

        // 视频主控面板（未锁定时可见）
        if (this.controlsVisible && !this.isLocked) {
          Column() {
            // 顶栏：返回、标题与副标题、画中画、横竖屏切换
            Row({ space: 10 }) {
              Stack() {
                SymbolGlyph($r('sys.symbol.chevron_left'))
                  .fontSize(22)
                  .fontColor([Color.White])
              }
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor('#55000000')
              .accessibilityText('返回')
              .onClick(() => this.onClose())

              Column({ space: 2 }) {
                Text(this.displayTitle)
                  .fontSize(15.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.displaySubtitle.length > 0) {
                  Text(this.displaySubtitle)
                    .fontSize(11.5)
                    .fontColor('#B3FFFFFF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.pipSupported && this.activeEngineKind === 'native') {
                Stack() {
                  SymbolGlyph($r('sys.symbol.dual_view_PIP'))
                    .fontSize(19)
                    .fontColor([Color.White])
                }
                .width(38)
                .height(38)
                .borderRadius(19)
                .backgroundColor('#55000000')
                .accessibilityText('开启画中画小窗播放')
                .onClick(() => {
                  this.pipController.startManualPip().catch(() => {});
                })
              }

              Stack() {
                SymbolGlyph($r('sys.symbol.TV_tv'))
                  .fontSize(19)
                  .fontColor([Color.White])
              }
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor('#55000000')
              .accessibilityText('投屏与无线流转')
              .onClick(() => this.openSheet('cast'))

              Stack() {
                SymbolGlyph($r('sys.symbol.full_screen_tv'))
                  .fontSize(20)
                  .fontColor([Color.White])
              }
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor('#55000000')
              .accessibilityText(this.effectiveLandscape() ? '切换竖屏播放' : '切换横屏全屏播放')
              .onClick(() => this.handleToggleFullscreenOrientation())

              Stack() {
                SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                  .fontSize(19)
                  .fontColor([Color.White])
              }
              .width(38)
              .height(38)
              .borderRadius(19)
              .backgroundColor('#55000000')
              .accessibilityText('更多播放选项')
              .onClick(() => this.openSheet('engine'))
            }
            .width('100%')
            .padding({
              left: 16 + this.safeLeftVp,
              right: 16 + this.safeRightVp,
              top: Math.max(12, this.safeTopVp + 4),
              bottom: this.isShortLandscape() ? 6 : 12
            })
            .linearGradient({
              angle: 180,
              colors: [['#B3000000', 0], ['#00000000', 1]]
            })

            Blank()

            // 中央播控：快退 10s · 缓冲/播放暂停 · 快进 10s
            Row({ space: 34 }) {
              Stack() {
                SymbolGlyph($r('sys.symbol.gobackward_10'))
                  .fontSize(24)
                  .fontColor([Color.White])
              }
              .width(48)
              .height(48)
              .borderRadius(24)
              .backgroundColor('#5C000000')
              .accessibilityText('快退 10 秒')
              .onClick(() => this.seekVideoRelativeMs(-10000))

              Stack() {
                if (this.isBuffering) {
                  LoadingProgress()
                    .width(34)
                    .height(34)
                    .color(Color.White)
                } else {
                  SymbolGlyph($r(this.isPlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
                    .fontSize(32)
                    .fontColor([Color.White])
                }
              }
              .width(66)
              .height(66)
              .borderRadius(33)
              .backgroundColor('#6E000000')
              .accessibilityText(this.isPlaying ? '暂停' : '播放')
              .onClick(() => this.handleTogglePlay())

              Stack() {
                SymbolGlyph($r('sys.symbol.goforward_10'))
                  .fontSize(24)
                  .fontColor([Color.White])
              }
              .width(48)
              .height(48)
              .borderRadius(24)
              .backgroundColor('#5C000000')
              .accessibilityText('快进 10 秒')
              .onClick(() => this.seekVideoRelativeMs(10000))
            }
            .alignItems(VerticalAlign.Center)

            Blank()

            // 底部控制坞：集数切换 + 进度条 + 字幕/音轨/选集/比例/倍速
            Column({ space: this.isShortLandscape() ? 4 : 8 }) {
              Row({ space: 8 }) {
                if (this.videoQueue.length > 1) {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.backward_end_fill'))
                      .fontSize(17)
                      .fontColor([this.videoQueueIdx > 0 ? Color.White : '#55FFFFFF'])
                  }
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .accessibilityText('上一集')
                  .onClick(() => this.playPreviousVideoEpisode())
                }

                Text(formatMediaDurationMs(this.positionMs))
                  .fontSize(11.5)
                  .fontColor('#D9FFFFFF')

                Slider({ value: this.progress, min: 0, max: 100 })
                  .layoutWeight(1)
                  .selectedColor('#317AF7')
                  .trackColor('#44FFFFFF')
                  .onChange((val: number, mode: SliderChangeMode) => this.handleSliderChange(val, mode))

                Text(this.formatRightDurationLabel())
                  .fontSize(11.5)
                  .fontColor('#D9FFFFFF')
                  .onClick(() => {
                    this.showRemainingTime = !this.showRemainingTime;
                    this.resetControlsAutoHideTimer();
                  })

                if (this.videoQueue.length > 1) {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.forward_end_fill'))
                      .fontSize(17)
                      .fontColor([this.videoQueueIdx + 1 < this.videoQueue.length ? Color.White : '#55FFFFFF'])
                  }
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .accessibilityText('下一集')
                  .onClick(() => this.playNextVideoEpisode())
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Scroll() {
                Row({ space: 2 }) {
                  if (this.activeVideoReq.danmakuEnabled) {
                    this.videoControlIcon(
                      $r('sys.symbol.message_on_message'),
                      this.danmakuVisible ? '关闭弹幕' : '开启弹幕',
                      this.danmakuVisible,
                      () => {
                        const next = !this.danmakuVisible;
                        DanmakuPreferencesStore.setEnabled(next);
                        this.danmakuVisible = next;
                        this.danmakuConfigVersion += 1;
                        this.showTransientHud('checkmark', next ? '已开启弹幕' : '已关闭弹幕');
                        this.resetControlsAutoHideTimer();
                      }
                    )
                    this.videoControlIcon(
                      $r('sys.symbol.slider_horizontal_2'), '打开弹幕设置', false,
                      () => {
                        this.danmakuSheetFeedback = '';
                        this.openSheet('danmakuSettings');
                      }
                    )
                  }
                  this.videoControlIcon(
                    $r('sys.symbol.AI_subtitles'), '选择字幕轨道', this.selectedSubId !== 'off',
                    () => this.openSheet('subtitles')
                  )
                  this.videoControlIcon(
                    $r('sys.symbol.waveform'), '选择音轨', this.audioTrackOptions.length > 1,
                    () => this.openSheet('audioTracks')
                  )
                  if (this.videoQueue.length > 1) {
                    this.videoControlIcon(
                      $r('sys.symbol.list_bullet'),
                      `打开选集列表，第 ${this.videoQueueIdx + 1} 集，共 ${this.videoQueue.length} 集`, false,
                      () => this.openSheet('queue')
                    )
                  }
                  this.videoControlIcon(
                    $r('sys.symbol.aspect_ratio'),
                    `切换画面比例，当前${PlaybackPreferencesStore.scaleModeLabel(this.scaleMode)}`,
                    this.scaleMode !== 'fit', () => this.handleCycleScaleMode()
                  )
                  this.videoControlIcon(
                    $r('sys.symbol.timer'), `选择播放倍速，当前 ${HARMONY_SPEED_LABELS[this.speedIndex]}`,
                    this.speedIndex !== DEFAULT_AUDIO_SPEED_INDEX, () => this.openSheet('speed')
                  )
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(44)
            }
            .width('100%')
            .padding({
              left: 16 + this.safeLeftVp,
              right: 16 + this.safeRightVp,
              top: 10,
              bottom: Math.max(14, this.safeBottomVp + (this.isShortLandscape() ? 4 : 10))
            })
            .linearGradient({
              angle: 0,
              colors: [['#BF000000', 0], ['#00000000', 1]]
            })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        } else if (this.isBuffering && !this.controlsVisible) {
          LoadingProgress()
            .width(38)
            .height(38)
            .color(Color.White)
            .hitTestBehavior(HitTestMode.None)
        }
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
    .bindSheet($$this.showPlayerSheet, this.playerSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      preferType: SheetType.BOTTOM,
      showClose: false,
      backgroundColor: '#F2151821',
      onDisappear: () => {
        this.resetControlsAutoHideTimer();
      }
    })
  }
}

/**
 * 鸿蒙全局常驻流体光感悬浮迷你音乐条：
 * - 实时订阅 `HarmonyAudioSession`，展示封面缩略图、曲名/歌手、底部细进度条、播放/暂停、下一曲（队列 > 1 时）与关闭按钮；
 * - 支持跨二级页面持续悬浮，点击平滑展开全屏音乐舞台。
 */
@Component
export struct FloatingMiniMusicBar {
  @Prop request: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: true };
  @Prop isPlaying: boolean = true;
  @State private liveTitle: string = '';
  @State private liveSubtitle: string = '';
  @State private liveArtworkUrl: string = '';
  @State private liveCoverPixelMap: image.PixelMap | null = null;
  @State private liveProgress: number = 0;
  @State private livePlaying: boolean = true;
  @State private canSkipNext: boolean = false;

  private audioListener: AudioStateListener = () => {
    this.syncSessionState();
  };

  onTogglePlay: () => void = () => {};
  onExpand: () => void = () => {};
  onClose: () => void = () => {};

  aboutToAppear(): void {
    HarmonyAudioSession.shared().subscribe(this.audioListener);
    this.syncSessionState();
  }

  aboutToDisappear(): void {
    HarmonyAudioSession.shared().unsubscribe(this.audioListener);
  }

  private syncSessionState(): void {
    const sess = HarmonyAudioSession.shared();
    const cur = sess.currentRequest();
    this.liveTitle = (cur && cur.title.length > 0) ? cur.title : this.request.title;
    this.liveSubtitle = (cur && cur.subtitle.length > 0) ? cur.subtitle : this.request.subtitle;
    this.liveArtworkUrl = (cur && cur.artworkUrl) ? cur.artworkUrl : (this.request.artworkUrl ?? '');
    this.liveCoverPixelMap = sess.coverPixelMap();
    this.liveProgress = sess.progressPercent();
    this.livePlaying = sess.hasActiveSession() ? sess.isPlaying() : this.isPlaying;
    this.canSkipNext = sess.canSkipQueue();
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.liveArtworkUrl.length > 0) {
            MpRemoteImage({
              src: this.liveArtworkUrl,
              imgWidth: 38,
              imgHeight: 38,
              imgRadius: 10,
              placeholderColor: '#33317AF7'
            })
          } else if (this.liveCoverPixelMap) {
            Image(this.liveCoverPixelMap)
              .width(38)
              .height(38)
              .objectFit(ImageFit.Cover)
              .borderRadius(10)
              .clip(true)
          } else {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(20)
              .fontColor(['#317AF7'])
          }
        }
        .width(38)
        .height(38)
        .borderRadius(10)
        .backgroundColor('#33317AF7')
        .clip(true)
        .onClick(() => this.onExpand())

        Column({ space: 2 }) {
          Text(this.liveTitle.length > 0 ? this.liveTitle : this.request.title)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.liveSubtitle.length > 0 ? this.liveSubtitle : this.request.subtitle)
            .fontSize(11)
            .fontColor('#A8FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => this.onExpand())

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.livePlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
            .fontSize(17)
            .fontColor([Color.White])
        }
        .width(34)
        .height(34)
        .backgroundColor('#24FFFFFF')
        .accessibilityText(this.livePlaying ? '暂停音乐' : '继续播放音乐')
        .onClick(() => this.onTogglePlay())

        if (this.canSkipNext) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.forward_end_fill'))
              .fontSize(15)
              .fontColor([Color.White])
          }
          .width(32)
          .height(32)
          .backgroundColor('#1EFFFFFF')
          .accessibilityText('下一首')
          .onClick(() => {
            HarmonyAudioSession.shared().playNext(false).catch(() => {});
          })
        }

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(14)
            .fontColor(['#CCFFFFFF'])
        }
        .width(30)
        .height(30)
        .backgroundColor(Color.Transparent)
        .accessibilityText('关闭音乐播放')
        .onClick(() => this.onClose())
      }
      .width('100%')
      .padding({ left: 12, right: 10, top: 8, bottom: 7 })

      // 底部纤细播放进度指示条
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(2.5)
          .backgroundColor('#1FFFFFFF')
        Row()
          .width(`${Math.min(100, Math.max(0, this.liveProgress)).toFixed(1)}%`)
          .height(2.5)
          .backgroundColor('#317AF7')
      }
      .width('100%')
      .padding({ left: 14, right: 14 })
    }
    .width('92%')
    .constraintSize({ maxWidth: 480 })
    .borderRadius(20)
    .clip(true)
    .backgroundColor('#E01A1A22')
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 0.6, color: '#24FFFFFF', radius: 20 })
  }
}
