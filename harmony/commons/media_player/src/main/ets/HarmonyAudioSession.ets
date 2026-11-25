import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';
import { audio } from '@kit.AudioKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { PlaybackPreferencesStore } from '@moviepilot/design_system';
import {
  MoviePilotRepository,
  RustCoreBridge,
  AudioEmbeddedMetadataResult,
  ParsedStrmStream,
  PlaybackRouteCandidate,
  HarmonyPlaybackSyncTracker,
  HarmonyPlaybackProgressReporter,
  HarmonyPlaybackRouteResolver
} from '@moviepilot/core_rust_bridge';
import {
  HarmonyPlaybackRequest,
  HarmonyQueueItem,
  HarmonyRepeatMode,
  HARMONY_SPEED_ENUMS,
  HARMONY_SPEED_VALUES,
  DEFAULT_AUDIO_SPEED_INDEX,
  buildPlaybackResumeKey,
  hasNonEmptyHeaders
} from './MediaPlayerModels';
import {
  LyricLineCue,
  parseLrcLyrics,
  extractPlainLyricsLines,
  findActiveLyricIndex
} from './SubtitleAndLyricsParser';

/** 音频会话状态变更监听器签名。 */
export type AudioStateListener = () => void;

/** 已打开的本地文件描述符与待清理临时路径记录。 */
export interface OpenedLocalMediaFd {
  fd: number;
  resolvedPath: string;
  cleanupOnClose: boolean;
}

/** 本地音频文件提取出的内嵌 ID3/Vorbis 元数据。 */
export interface LocalAudioMetadataResult {
  title: string;
  artist: string;
  album: string;
  coverPixelMap: image.PixelMap | null;
}

/**
 * 以只读模式打开本地沙盒路径或授权 `file://` URI，供 `AVPlayer.fdSrc` 使用。
 */
export function openLocalPlaybackFd(rawTarget: string, cleanupOnClose: boolean): OpenedLocalMediaFd | null {
  const clean = rawTarget.trim();
  if (clean.length === 0) {
    return null;
  }
  try {
    const file = fileIo.openSync(clean, fileIo.OpenMode.READ_ONLY);
    return {
      fd: file.fd,
      resolvedPath: clean,
      cleanupOnClose: cleanupOnClose
    };
  } catch {
    if (clean.startsWith('file:///')) {
      try {
        const stripped = decodeURIComponent(clean.substring(7));
        const file2 = fileIo.openSync(stripped, fileIo.OpenMode.READ_ONLY);
        return {
          fd: file2.fd,
          resolvedPath: stripped,
          cleanupOnClose: cleanupOnClose
        };
      } catch {
        return null;
      }
    }
    return null;
  }
}

/**
 * 安全关闭本地播放句柄，并在 `cleanupOnClose` 为 `true` 时删除缓存临时文件。
 */
export function closeLocalPlaybackFd(handle: OpenedLocalMediaFd | null): void {
  if (!handle) {
    return;
  }
  if (handle.fd >= 0) {
    try {
      fileIo.closeSync(handle.fd);
    } catch {
      // ignore close error
    }
  }
  if (handle.cleanupOnClose && handle.resolvedPath.length > 0 && !handle.resolvedPath.startsWith('file://')) {
    try {
      fileIo.unlinkSync(handle.resolvedPath);
    } catch {
      // ignore temp unlink error
    }
  }
}

/**
 * 使用独立文件描述符通过 `AVMetadataExtractor` 提取本地音频文件的标题、艺术家、专辑与内嵌封面（严禁与 `AVPlayer` 共用同一 `fd`）。
 */
export async function extractLocalAudioMetadata(rawTarget: string): Promise<LocalAudioMetadataResult | null> {
  const tempFd = openLocalPlaybackFd(rawTarget, false);
  if (!tempFd) {
    return null;
  }
  let extractor: media.AVMetadataExtractor | null = null;
  try {
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: tempFd.fd };
    const meta = await extractor.fetchMetadata();
    let cover: image.PixelMap | null = null;
    try {
      cover = await extractor.fetchAlbumCover();
    } catch {
      cover = null;
    }
    const result: LocalAudioMetadataResult = {
      title: (meta?.title ?? '').trim(),
      artist: (meta?.artist ?? meta?.albumArtist ?? meta?.author ?? '').trim(),
      album: (meta?.album ?? '').trim(),
      coverPixelMap: cover
    };
    try {
      await extractor.release();
    } catch {
      // ignore
    }
    closeLocalPlaybackFd(tempFd);
    return result;
  } catch {
    if (extractor) {
      try {
        await extractor.release();
      } catch {
        // ignore
      }
    }
    closeLocalPlaybackFd(tempFd);
    return null;
  }
}

/**
 * 为 `AVPlayer` 绑定播放源：
 * - 本地文件（`fdPath` 或 `file://`）走只读 `fdSrc`；
 * - 携带鉴权请求头的远程流走 API 12 `media.createMediaSourceWithUrl` + `setMediaSource`；
 * - 无额外请求头的公开直链回退 `player.url`。
 */
/**
 * 从本地 `.strm` 文件句柄读取文本（上限 64KB）并解析出客户端 HTTP(S) 直链与可选请求头，随后立即关闭句柄并清理临时文件。
 */
export function resolveLocalStrmFile(rawTarget: string, cleanupOnClose: boolean): ParsedStrmStream | null {
  if (!RustCoreBridge.isStrmPath(rawTarget)) {
    return null;
  }
  const opened = openLocalPlaybackFd(rawTarget, cleanupOnClose);
  if (!opened) {
    return null;
  }
  try {
    const buf = new ArrayBuffer(65536);
    const bytesRead = fileIo.readSync(opened.fd, buf);
    closeLocalPlaybackFd(opened);
    if (bytesRead <= 0 || bytesRead >= 65536) {
      return null;
    }
    const slice = new Uint8Array(buf, 0, bytesRead);
    let text = '';
    if (slice.length >= 2 && slice[0] === 0xff && slice[1] === 0xfe) {
      text = util.TextDecoder.create('utf-16le', { ignoreBOM: true }).decodeToString(slice);
    } else if (slice.length >= 2 && slice[0] === 0xfe && slice[1] === 0xff) {
      text = util.TextDecoder.create('utf-16be', { ignoreBOM: true }).decodeToString(slice);
    } else {
      text = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(slice);
    }
    return RustCoreBridge.parseStrmContent(text, rawTarget);
  } catch {
    closeLocalPlaybackFd(opened);
    return null;
  }
}

export async function attachSourceToAvPlayer(
  player: media.AVPlayer,
  req: HarmonyPlaybackRequest,
  strategy?: media.PlaybackStrategy
): Promise<OpenedLocalMediaFd | null> {
  const fdCandidate = (req.fdPath ?? '').trim();
  const urlCandidate = req.url.trim();
  const isLocal = fdCandidate.length > 0 || urlCandidate.startsWith('file://') || urlCandidate.startsWith('/');

  if (isLocal) {
    const target = fdCandidate.length > 0 ? fdCandidate : urlCandidate;
    if (RustCoreBridge.isStrmPath(target)) {
      const strmSpec = resolveLocalStrmFile(target, req.cleanupTempOnClose === true);
      if (!strmSpec) {
        throw new Error('STRM 文件内容无效');
      }
      if (hasNonEmptyHeaders(strmSpec.headers)) {
        try {
          const src = media.createMediaSourceWithUrl(strmSpec.url, strmSpec.headers);
          const playStrategy: media.PlaybackStrategy = strategy ?? { preferredBufferDuration: 20 };
          await player.setMediaSource(src, playStrategy);
          return null;
        } catch {
          // fallback to direct url
        }
      }
      player.url = strmSpec.url;
      return null;
    }
    const opened = openLocalPlaybackFd(target, req.cleanupTempOnClose === true);
    if (opened) {
      player.fdSrc = { fd: opened.fd };
      return opened;
    }
  }

  if (urlCandidate.length > 0) {
    if (hasNonEmptyHeaders(req.headers)) {
      try {
        const src = media.createMediaSourceWithUrl(urlCandidate, req.headers);
        const playStrategy: media.PlaybackStrategy = strategy ?? {
          preferredBufferDuration: req.isAudio ? 8 : 20
        };
        await player.setMediaSource(src, playStrategy);
        return null;
      } catch {
        // 降级回退至直链赋值，保障极端系统环境下不抛未捕获异常
      }
    }
    player.url = urlCandidate;
  }
  return null;
}

/**
 * 鸿蒙全局持久化音频播控会话控制器（`AVPlayer` + `AVSession` + `backgroundTaskManager`）：
 * - 支持音乐专辑/歌单完整队列、4 种循环模式、3 秒重播/上一曲、完播自动连播；
 * - 支持 LRC 同步歌词拉取与逐行高亮定位、15 秒媒体服务器进度同步；
 * - 支持锁屏播控中心 `AVSession`（封面 `PixelMap`、歌词、进度、上/下一首）与后台长时任务 `AUDIO_PLAYBACK`；
 * - 响应系统音频焦点打断（来电/闹钟暂停与恢复）及有线/蓝牙耳机拔出自动暂停。
 */
export class HarmonyAudioSession {
  private static instance: HarmonyAudioSession | null = null;

  private player: media.AVPlayer | null = null;
  private session: avSession.AVSession | null = null;
  private hostContext: common.BaseContext | null = null;
  private openedFd: OpenedLocalMediaFd | null = null;
  private bgTaskRunning: boolean = false;
  private interruptedWhilePlaying: boolean = false;

  private activeSourceKey: string = '';
  private activeReq: HarmonyPlaybackRequest | null = null;
  private queue: HarmonyQueueItem[] = [];
  private queueIdx: number = 0;
  private repeatMode: HarmonyRepeatMode = 'sequence';

  private playing: boolean = false;
  private buffering: boolean = false;
  private posMs: number = 0;
  private durMs: number = 0;
  private speedIdx: number = DEFAULT_AUDIO_SPEED_INDEX;

  private rawLyricsText: string = '';
  private lyricCues: LyricLineCue[] = [];
  private plainLyricsLines: string[] = [];
  private currentLyricIdx: number = -1;
  private artworkPixelMap: image.PixelMap | null = null;

  private progressTimerId: number = -1;
  private progressTickCount: number = 0;
  private audioSyncTracker: HarmonyPlaybackSyncTracker = new HarmonyPlaybackSyncTracker();
  private audioStartedSent: boolean = false;
  private loadGeneration: number = 0;
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

  hasActiveSession(): boolean {
    return this.activeReq !== null;
  }

  currentRequest(): HarmonyPlaybackRequest | null {
    return this.activeReq;
  }

  isSessionBound(): boolean {
    if (!this.activeReq) {
      return true;
    }
    return this.activeReq.isSessionBound !== false;
  }

  isPlaying(): boolean {
    return this.playing;
  }

  isBuffering(): boolean {
    return this.buffering;
  }

  positionMs(): number {
    return this.posMs;
  }

  durationMs(): number {
    return this.durMs;
  }

  progressPercent(): number {
    if (this.durMs <= 0) {
      return 0;
    }
    return Math.min(100, Math.max(0, (this.posMs / this.durMs) * 100));
  }

  speedIndex(): number {
    return this.speedIdx;
  }

  getRepeatMode(): HarmonyRepeatMode {
    return this.repeatMode;
  }

  queueItems(): HarmonyQueueItem[] {
    return this.queue;
  }

  currentQueueIndex(): number {
    return this.queueIdx;
  }

  canSkipQueue(): boolean {
    return this.queue.length > 1;
  }

  lyricsCues(): LyricLineCue[] {
    return this.lyricCues;
  }

  plainLyrics(): string[] {
    return this.plainLyricsLines;
  }

  activeLyricIndex(): number {
    return this.currentLyricIdx;
  }

  activeLyricLine(): string {
    if (this.currentLyricIdx >= 0 && this.currentLyricIdx < this.lyricCues.length) {
      return this.lyricCues[this.currentLyricIdx].text;
    }
    return '';
  }

  coverPixelMap(): image.PixelMap | null {
    return this.artworkPixelMap;
  }

  private computeSourceKey(req: HarmonyPlaybackRequest): string {
    const fd = (req.fdPath ?? '').trim();
    if (fd.length > 0) {
      return `fd:${fd}`;
    }
    return `url:${req.url.trim()}`;
  }

  private notify(): void {
    AppStorage.setOrCreate('mp_audio_is_playing', this.playing);
    AppStorage.setOrCreate('mp_audio_title', this.activeReq?.title ?? '');
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i]();
      } catch {
        // ignore listener exception
      }
    }
  }

  /** 启动新曲目或无缝挂载正在播放的同一音频流。 */
  async startOrAttach(req: HarmonyPlaybackRequest, hostCtx?: common.BaseContext): Promise<void> {
    if (hostCtx) {
      this.hostContext = hostCtx;
    }
    const incomingKey = this.computeSourceKey(req);
    if (this.player && incomingKey.length > 4 && this.activeSourceKey === incomingKey) {
      if (req.queue && req.queue.length > 0) {
        this.queue = req.queue;
        if (req.queueIndex !== undefined && req.queueIndex >= 0 && req.queueIndex < req.queue.length) {
          this.queueIdx = req.queueIndex;
        }
      }
      this.notify();
      return;
    }

    if (req.queue && req.queue.length > 0) {
      this.queue = req.queue;
      this.queueIdx = (req.queueIndex !== undefined && req.queueIndex >= 0 && req.queueIndex < req.queue.length)
        ? req.queueIndex
        : 0;
    } else {
      this.queue = [];
      this.queueIdx = 0;
    }

    // 新音频流按规范固定以 1.0x 倍速启动
    this.speedIdx = DEFAULT_AUDIO_SPEED_INDEX;
    await this.loadTrackInternal(req, true);
  }

  private async loadTrackInternal(req: HarmonyPlaybackRequest, resetSpeedToNormal: boolean): Promise<void> {
    const gen = ++this.loadGeneration;
    if (this.activeReq) {
      this.dispatchAudioSync('stop', true);
    }
    await this.releasePlayerOnly();
    this.releaseArtworkPixelMap();
    this.audioSyncTracker.reset(req.playSessionId ?? '');
    this.audioStartedSent = false;
    this.progressTickCount = 0;

    if (resetSpeedToNormal) {
      this.speedIdx = DEFAULT_AUDIO_SPEED_INDEX;
    }

    const enrichedReq: HarmonyPlaybackRequest = {
      url: req.url,
      fdPath: req.fdPath,
      cleanupTempOnClose: req.cleanupTempOnClose,
      headers: req.headers,
      proxyFallbackUrl: req.proxyFallbackUrl,
      proxyFallbackHeaders: req.proxyFallbackHeaders,
      activeRouteKind: req.activeRouteKind,
      fallbackRoutes: req.fallbackRoutes ? req.fallbackRoutes.slice() : undefined,
      title: req.title,
      subtitle: req.subtitle,
      artist: req.artist,
      album: req.album,
      artworkUrl: req.artworkUrl,
      isAudio: true,
      lyricsLrc: req.lyricsLrc,
      lyricsUrl: req.lyricsUrl,
      itemId: req.itemId,
      server: req.server,
      serverType: req.serverType,
      mediaSourceId: req.mediaSourceId,
      playSessionId: req.playSessionId,
      progressSyncMode: req.progressSyncMode,
      resumePositionMs: req.resumePositionMs,
      isSessionBound: req.isSessionBound,
      queue: this.queue,
      queueIndex: this.queueIdx
    };

    this.activeSourceKey = this.computeSourceKey(enrichedReq);
    this.activeReq = enrichedReq;
    this.posMs = 0;
    this.durMs = 0;
    this.playing = true;
    this.buffering = true;
    this.interruptedWhilePlaying = false;
    this.rawLyricsText = '';
    this.lyricCues = [];
    this.plainLyricsLines = [];
    this.currentLyricIdx = -1;
    this.notify();

    // 本机音频文件在后台并行解析内嵌 ID3/Vorbis 元数据与封面，绝不阻塞 AVPlayer 首帧起播
    const localTarget = (enrichedReq.fdPath ?? '').trim() ||
      (enrichedReq.url.startsWith('file://') || enrichedReq.url.startsWith('/') ? enrichedReq.url.trim() : '');
    if (localTarget.length > 0) {
      extractLocalAudioMetadata(localTarget).then((localMeta: LocalAudioMetadataResult | null) => {
        if (gen !== this.loadGeneration) {
          if (localMeta?.coverPixelMap) {
            try { localMeta.coverPixelMap.release(); } catch { /* ignore */ }
          }
          return;
        }
        if (localMeta) {
          if (localMeta.title.length > 0 && (enrichedReq.title.length === 0 || enrichedReq.title === '外部直链媒体' || enrichedReq.title.includes('.'))) {
            enrichedReq.title = localMeta.title;
          }
          if (localMeta.artist.length > 0 && !(enrichedReq.artist ?? '').trim()) {
            enrichedReq.artist = localMeta.artist;
          }
          if (localMeta.album.length > 0 && !(enrichedReq.album ?? '').trim()) {
            enrichedReq.album = localMeta.album;
          }
          if ((enrichedReq.artist ?? '').length > 0 || (enrichedReq.album ?? '').length > 0) {
            const a = (enrichedReq.artist ?? '').trim();
            const b = (enrichedReq.album ?? '').trim();
            enrichedReq.subtitle = a.length > 0 && b.length > 0 ? `${a} · ${b}` : (a || b);
          }
          if (localMeta.coverPixelMap) {
            this.artworkPixelMap = localMeta.coverPixelMap;
          }
          this.syncAvSessionMetadata();
          this.notify();
        }
      }).catch(() => {});
    }

    // 异步加载歌词、锁屏封面 PixelMap 以及内嵌封面与歌词（支持本地与远端 HTTP Range 流）
    this.loadLyricsForTrack(enrichedReq, gen).catch(() => {});
    if (!this.artworkPixelMap && (enrichedReq.artworkUrl ?? '').trim().length > 0) {
      this.loadRemoteArtwork(enrichedReq.artworkUrl ?? '', gen).catch(() => {});
    }
    this.loadEmbeddedAudioMetadata(enrichedReq, gen).catch(() => {});

    if (this.hostContext) {
      this.ensureAvSession(this.hostContext, enrichedReq).catch(() => {});
    }

    try {
      const av = await media.createAVPlayer();
      if (gen !== this.loadGeneration) {
        try { await av.release(); } catch { /* ignore */ }
        return;
      }
      this.player = av;

      av.on('durationUpdate', (dur: number) => {
        if (gen !== this.loadGeneration) { return; }
        this.durMs = Math.max(0, dur);
        this.syncAvSessionMetadata();
        this.notify();
      });

      av.on('timeUpdate', (time: number) => {
        if (gen !== this.loadGeneration) { return; }
        this.posMs = Math.max(0, time);
        const nextLyricIdx = findActiveLyricIndex(this.lyricCues, this.posMs);
        const lyricChanged = nextLyricIdx !== this.currentLyricIdx;
        this.currentLyricIdx = nextLyricIdx;
        if (lyricChanged) {
          this.syncAvSessionSingleLyric();
        }
        this.notify();
      });

      av.on('bufferingUpdate', (infoType: media.BufferingInfoType, _val: number) => {
        if (gen !== this.loadGeneration) { return; }
        if (infoType === media.BufferingInfoType.BUFFERING_START) {
          this.buffering = true;
          this.notify();
        } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
          this.buffering = false;
          this.notify();
        }
      });

      av.on('audioInterrupt', (ev: audio.InterruptEvent) => {
        if (gen !== this.loadGeneration) { return; }
        if (ev.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
          if (
            ev.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
            ev.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP
          ) {
            this.interruptedWhilePlaying = this.playing;
            this.setPlaying(false);
          }
        } else if (ev.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME && this.interruptedWhilePlaying) {
          this.interruptedWhilePlaying = false;
          this.setPlaying(true);
        }
      });

      av.on('audioOutputDeviceChangeWithInfo', (info: audio.AudioStreamDeviceChangeInfo) => {
        if (gen !== this.loadGeneration) { return; }
        if (info.changeReason === audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE && this.playing) {
          this.setPlaying(false);
        }
      });

      av.on('error', () => {
        if (gen !== this.loadGeneration) { return; }
        if (this.posMs <= 1000) {
          const serverName = (enrichedReq.server ?? '').trim();
          const curKind = (enrichedReq.activeRouteKind ?? '').trim();
          if ((curKind === 'server_lan' || curKind === 'server_wan') && enrichedReq.url.length > 0) {
            HarmonyPlaybackRouteResolver.shared().markRouteFailed(serverName, enrichedReq.url);
          }
          const fallbacks: PlaybackRouteCandidate[] = enrichedReq.fallbackRoutes ? enrichedReq.fallbackRoutes.slice() : [];
          const legacyUrl = (enrichedReq.proxyFallbackUrl ?? '').trim();
          if (legacyUrl.length > 0 && legacyUrl !== enrichedReq.url && !fallbacks.some((f: PlaybackRouteCandidate) => f.url === legacyUrl)) {
            fallbacks.push({
              kind: 'mp_proxy',
              url: legacyUrl,
              probe_url: null,
              headers: enrichedReq.proxyFallbackHeaders ?? {},
              priority: 100,
              requires_same_origin_auth: true
            });
          }
          while (fallbacks.length > 0) {
            const nextRoute = fallbacks.shift();
            if (!nextRoute || !nextRoute.url || nextRoute.url === enrichedReq.url) { continue; }
            const nextHeaders = nextRoute.kind === 'mp_proxy'
              ? (enrichedReq.proxyFallbackHeaders ?? nextRoute.headers)
              : nextRoute.headers;
            const fallbackReq: HarmonyPlaybackRequest = {
              url: nextRoute.url,
              headers: nextHeaders,
              proxyFallbackUrl: enrichedReq.proxyFallbackUrl,
              proxyFallbackHeaders: enrichedReq.proxyFallbackHeaders,
              activeRouteKind: nextRoute.kind,
              fallbackRoutes: fallbacks,
              title: enrichedReq.title,
              subtitle: enrichedReq.subtitle,
              artist: enrichedReq.artist,
              album: enrichedReq.album,
              artworkUrl: enrichedReq.artworkUrl,
              isAudio: true,
              lyricsLrc: enrichedReq.lyricsLrc,
              lyricsUrl: enrichedReq.lyricsUrl,
              itemId: enrichedReq.itemId,
              server: enrichedReq.server,
              serverType: enrichedReq.serverType,
              mediaSourceId: enrichedReq.mediaSourceId,
              playSessionId: enrichedReq.playSessionId,
              progressSyncMode: enrichedReq.progressSyncMode,
              resumePositionMs: enrichedReq.resumePositionMs,
              isSessionBound: enrichedReq.isSessionBound,
              queue: this.queue,
              queueIndex: this.queueIdx
            };
            this.loadTrackInternal(fallbackReq, false).catch(() => {});
            return;
          }
        }
        this.buffering = false;
        this.playing = false;
        this.stopProgressTimer();
        this.syncAvSessionPlaybackState();
        this.notify();
      });

      av.on('stateChange', (state: string) => {
        if (gen !== this.loadGeneration) { return; }
        if (state === 'initialized') {
          av.prepare().catch(() => {});
        } else if (state === 'prepared') {
          this.buffering = false;
          if (this.durMs <= 0 && av.duration > 0) {
            this.durMs = av.duration;
          }
          try {
            av.setSpeed(HARMONY_SPEED_ENUMS[this.speedIdx]);
          } catch {
            // ignore
          }
          const resumeCandidate = Math.max(
            enrichedReq.resumePositionMs ?? 0,
            PlaybackPreferencesStore.getLocalResumeMs(buildPlaybackResumeKey(enrichedReq))
          );
          if (resumeCandidate > 30000 && (this.durMs <= 0 || resumeCandidate < this.durMs * 0.95)) {
            try {
              av.seek(resumeCandidate);
              this.posMs = resumeCandidate;
            } catch {
              // ignore
            }
          }
          av.play().catch(() => {});
          this.playing = true;
          this.startBackgroundPlaybackIfNeeded();
          this.startProgressTimer();
          this.syncAvSessionMetadata();
          this.syncAvSessionPlaybackState();
          this.notify();
        } else if (state === 'playing') {
          this.buffering = false;
          this.playing = true;
          this.startBackgroundPlaybackIfNeeded();
          this.startProgressTimer();
          this.dispatchAudioSync(this.audioStartedSent ? 'resume' : 'start', false);
          this.syncAvSessionPlaybackState();
          this.notify();
        } else if (state === 'paused') {
          this.playing = false;
          // 保持 1 秒状态机心跳计时器运行以发送 12 秒暂停保活和 15 分钟自动释放
          this.startProgressTimer();
          this.dispatchAudioSync('pause', true);
          this.syncAvSessionPlaybackState();
          this.notify();
        } else if (state === 'completed') {
          this.playing = false;
          this.stopProgressTimer();
          if (this.activeReq) {
            PlaybackPreferencesStore.clearLocalResumeMs(buildPlaybackResumeKey(this.activeReq));
          }
          this.dispatchAudioSync('finish', true, this.durMs > 0 ? this.durMs : this.posMs);
          this.syncAvSessionPlaybackState();
          this.notify();
          this.handleTrackCompleted().catch(() => {});
        } else if (state === 'stopped') {
          this.playing = false;
          this.stopProgressTimer();
          this.syncAvSessionPlaybackState();
          this.notify();
        }
      });

      const opened = await attachSourceToAvPlayer(av, enrichedReq);
      if (gen !== this.loadGeneration) {
        closeLocalPlaybackFd(opened);
        return;
      }
      this.openedFd = opened;
    } catch {
      this.buffering = false;
      this.playing = false;
      this.notify();
    }
  }

  private async loadLyricsForTrack(req: HarmonyPlaybackRequest, gen: number): Promise<void> {
    let raw = (req.lyricsLrc ?? '').trim();
    if (raw.length === 0 && (req.lyricsUrl ?? '').trim().length > 0) {
      raw = await MoviePilotRepository.shared().fetchSubtitleOrLyricsText(req.lyricsUrl ?? '', true);
    }
    if (gen !== this.loadGeneration || !raw) {
      return;
    }
    this.rawLyricsText = raw;
    this.lyricCues = parseLrcLyrics(raw);
    this.plainLyricsLines = this.lyricCues.length === 0 ? extractPlainLyricsLines(raw) : [];
    this.currentLyricIdx = findActiveLyricIndex(this.lyricCues, this.posMs);
    this.syncAvSessionMetadata();
    this.notify();
  }

  private async decodeCoverBase64ToPixelMap(base64Str: string): Promise<image.PixelMap | null> {
    if (!base64Str || base64Str.length === 0) {
      return null;
    }
    try {
      const helper = new util.Base64Helper();
      const u8 = helper.decodeSync(base64Str);
      if (!u8 || u8.byteLength === 0) {
        return null;
      }
      const buf = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength);
      const source = image.createImageSource(buf);
      if (!source) {
        return null;
      }
      let decodeOpts: image.DecodingOptions = {
        desiredSize: { width: 512, height: 512 }
      };
      try {
        const info = await source.getImageInfo();
        if (info && info.size && info.size.width > 0 && info.size.height > 0) {
          const maxDim = Math.max(info.size.width, info.size.height);
          if (maxDim > 512) {
            const scale = 512 / maxDim;
            decodeOpts = {
              desiredSize: {
                width: Math.max(1, Math.round(info.size.width * scale)),
                height: Math.max(1, Math.round(info.size.height * scale))
              }
            };
          } else {
            decodeOpts = {
              desiredSize: { width: info.size.width, height: info.size.height }
            };
          }
        }
      } catch {
        // fallback 512x512
      }
      const pm = await source.createPixelMap(decodeOpts);
      try { source.release(); } catch { /* ignore */ }
      return pm;
    } catch {
      return null;
    }
  }

  private isRawAudioFilename(title: string): boolean {
    return /\.(flac|mp3|m4a|aac|ogg|oga|opus|wav|aiff|aif|alac|ape|wv|wma|dsf|dff|mka)$/i.test(title.trim());
  }

  /**
   * 异步从本地文件或远端 HTTP Range 音频头/尾字节提取内嵌封面与歌词（委托 Rust 核心解析 FLAC / ID3v2 / MP4·M4A / Ogg）。
   */
  private async loadEmbeddedAudioMetadata(req: HarmonyPlaybackRequest, gen: number): Promise<void> {
    const needsArt = (req.artworkUrl ?? '').trim().length === 0 && !this.artworkPixelMap;
    const needsLyrics = (req.lyricsLrc ?? '').trim().length === 0 && this.lyricCues.length === 0 && this.plainLyricsLines.length === 0;
    const rawTitle = this.isRawAudioFilename(req.title);
    if (!needsArt && !needsLyrics && !rawTitle) {
      return;
    }

    const INITIAL_HEAD = 256 * 1024;
    const MAX_HEAD = 6 * 1024 * 1024;
    const TAIL_SIZE = 512 * 1024;
    const b64 = new util.Base64Helper();

    let parsed: AudioEmbeddedMetadataResult | null = null;
    const localTarget = (req.fdPath ?? '').trim() ||
      (req.url.startsWith('file://') || req.url.startsWith('/') ? req.url.trim() : '');

    if (localTarget.length > 0) {
      const opened = openLocalPlaybackFd(localTarget, false);
      if (opened) {
        try {
          const stat = fileIo.statSync(opened.fd);
          const fileSize = stat.size;
          if (fileSize > 4) {
            const firstLen = Math.min(fileSize, INITIAL_HEAD);
            let headBuf = new ArrayBuffer(firstLen);
            const n1 = fileIo.readSync(opened.fd, headBuf, { offset: 0, length: firstLen });
            if (n1 > 0) {
              let headU8 = new Uint8Array(headBuf, 0, n1);
              let headB64 = b64.encodeToStringSync(headU8);
              parsed = RustCoreBridge.parseAudioEmbeddedMetadata(headB64, '');

              const neededHead = parsed.needed_head_bytes ?? 0;
              if (neededHead > headU8.byteLength && fileSize > headU8.byteLength) {
                const targetLen = Math.min(fileSize, Math.min(neededHead, MAX_HEAD));
                if (targetLen > headU8.byteLength) {
                  const fullBuf = new ArrayBuffer(targetLen);
                  const nFull = fileIo.readSync(opened.fd, fullBuf, { offset: 0, length: targetLen });
                  if (nFull > headU8.byteLength) {
                    headU8 = new Uint8Array(fullBuf, 0, nFull);
                    headB64 = b64.encodeToStringSync(headU8);
                    parsed = RustCoreBridge.parseAudioEmbeddedMetadata(headB64, '');
                  }
                }
              }

              const neededTail = parsed.needed_tail_bytes ?? 0;
              if (neededTail > 0 && fileSize > headU8.byteLength) {
                const tailLen = Math.min(fileSize, Math.min(Math.max(neededTail, TAIL_SIZE), 2 * 1024 * 1024));
                const tailStart = Math.max(0, fileSize - tailLen);
                const tailBuf = new ArrayBuffer(tailLen);
                const nTail = fileIo.readSync(opened.fd, tailBuf, { offset: tailStart, length: tailLen });
                if (nTail > 0) {
                  const tailB64 = b64.encodeToStringSync(new Uint8Array(tailBuf, 0, nTail));
                  parsed = RustCoreBridge.parseAudioEmbeddedMetadata(headB64, tailB64);
                }
              }
            }
          }
        } catch {
          // ignore local tag read failure
        } finally {
          closeLocalPlaybackFd(opened);
        }
      }
    } else if (req.url.startsWith('http://') || req.url.startsWith('https://')) {
      const repo = MoviePilotRepository.shared();
      const first = await repo.fetchAudioByteRange(req.url, 0, INITIAL_HEAD - 1, req.headers);
      if (gen !== this.loadGeneration || !first || first.data.byteLength === 0) {
        return;
      }
      let headU8 = new Uint8Array(first.data);
      let headB64 = b64.encodeToStringSync(headU8);
      parsed = RustCoreBridge.parseAudioEmbeddedMetadata(headB64, '');

      const neededHead = parsed.needed_head_bytes ?? 0;
      if (first.isPartial && neededHead > headU8.byteLength) {
        const capped = Math.min(neededHead, MAX_HEAD);
        const targetEnd = first.totalSize > 0 ? Math.min(capped, first.totalSize) : capped;
        if (targetEnd > headU8.byteLength) {
          const more = await repo.fetchAudioByteRange(req.url, headU8.byteLength, targetEnd - 1, req.headers);
          if (gen !== this.loadGeneration) {
            return;
          }
          if (more && more.data.byteLength > 0) {
            const moreU8 = new Uint8Array(more.data);
            const combined = new Uint8Array(headU8.byteLength + moreU8.byteLength);
            combined.set(headU8, 0);
            combined.set(moreU8, headU8.byteLength);
            headU8 = combined;
            headB64 = b64.encodeToStringSync(headU8);
            parsed = RustCoreBridge.parseAudioEmbeddedMetadata(headB64, '');
          }
        }
      }

      const neededTail = parsed.needed_tail_bytes ?? 0;
      if (first.isPartial && neededTail > 0 && first.totalSize > headU8.byteLength) {
        const tailLen = Math.min(first.totalSize, Math.min(Math.max(neededTail, TAIL_SIZE), 2 * 1024 * 1024));
        const tailStart = Math.max(0, first.totalSize - tailLen);
        const tail = await repo.fetchAudioByteRange(req.url, tailStart, first.totalSize - 1, req.headers);
        if (gen !== this.loadGeneration) {
          return;
        }
        if (tail && tail.data.byteLength > 0) {
          const tailB64 = b64.encodeToStringSync(new Uint8Array(tail.data));
          parsed = RustCoreBridge.parseAudioEmbeddedMetadata(headB64, tailB64);
        }
      }
    }

    if (gen !== this.loadGeneration || !parsed) {
      return;
    }

    let changed = false;
    const tagTitle = (parsed.title ?? '').trim();
    const tagArtist = (parsed.artist ?? '').trim();
    const tagAlbum = (parsed.album ?? '').trim();
    const tagLyrics = (parsed.lyrics ?? '').trim();
    const tagCoverB64 = (parsed.cover_base64 ?? '').trim();

    if (tagTitle.length > 0 && (req.title.trim().length === 0 || this.isRawAudioFilename(req.title))) {
      req.title = tagTitle;
      changed = true;
    }
    if (tagArtist.length > 0 && (req.artist ?? '').trim().length === 0) {
      req.artist = tagArtist;
      changed = true;
    }
    if (tagAlbum.length > 0 && (req.album ?? '').trim().length === 0) {
      req.album = tagAlbum;
      changed = true;
    }
    const artistNow = (req.artist ?? '').trim();
    const albumNow = (req.album ?? '').trim();
    if (
      (artistNow.length > 0 || albumNow.length > 0) &&
      (req.subtitle.trim().length === 0 || req.subtitle.includes(' · /') || req.subtitle.startsWith('local ·') || req.subtitle.startsWith('smb ·'))
    ) {
      req.subtitle = artistNow.length > 0 && albumNow.length > 0 ? `${artistNow} · ${albumNow}` : (artistNow || albumNow);
      changed = true;
    }

    if (tagLyrics.length > 0 && this.lyricCues.length === 0 && this.plainLyricsLines.length === 0) {
      this.rawLyricsText = tagLyrics;
      this.lyricCues = parseLrcLyrics(tagLyrics);
      this.plainLyricsLines = this.lyricCues.length === 0 ? extractPlainLyricsLines(tagLyrics) : [];
      this.currentLyricIdx = findActiveLyricIndex(this.lyricCues, this.posMs);
      changed = true;
    }

    if (tagCoverB64.length > 0 && !this.artworkPixelMap && (req.artworkUrl ?? '').trim().length === 0) {
      const pm = await this.decodeCoverBase64ToPixelMap(tagCoverB64);
      if (gen !== this.loadGeneration) {
        if (pm) {
          try { pm.release(); } catch { /* ignore */ }
        }
        return;
      }
      if (pm) {
        this.releaseArtworkPixelMap();
        this.artworkPixelMap = pm;
        changed = true;
      }
    }

    if (changed) {
      this.syncAvSessionMetadata();
      this.notify();
    }
  }

  private async loadRemoteArtwork(artworkUrl: string, gen: number): Promise<void> {
    const pm = await MoviePilotRepository.shared().fetchArtworkPixelMap(artworkUrl);
    if (gen !== this.loadGeneration) {
      if (pm) {
        try { pm.release(); } catch { /* ignore */ }
      }
      return;
    }
    if (pm) {
      this.releaseArtworkPixelMap();
      this.artworkPixelMap = pm;
      this.syncAvSessionMetadata();
      this.notify();
    }
  }

  private releaseArtworkPixelMap(): void {
    const prev = this.artworkPixelMap;
    this.artworkPixelMap = null;
    if (prev) {
      try {
        prev.release();
      } catch {
        // ignore
      }
    }
  }

  private async handleTrackCompleted(): Promise<void> {
    if (this.repeatMode === 'one') {
      this.seekMs(0);
      this.setPlaying(true);
      return;
    }
    if (this.queue.length <= 1) {
      if (this.repeatMode === 'all' && this.queue.length === 1) {
        this.seekMs(0);
        this.setPlaying(true);
      }
      return;
    }
    await this.playNext(true);
  }

  /** 播放下一首曲目（支持顺序、列表循环、单曲循环与随机模式）。 */
  async playNext(fromAutoComplete: boolean = false): Promise<void> {
    if (this.queue.length === 0) {
      return;
    }
    let nextIdx = this.queueIdx;
    if (this.repeatMode === 'shuffle' && this.queue.length > 1) {
      let candidate = Math.floor(Math.random() * this.queue.length);
      if (candidate === this.queueIdx) {
        candidate = (candidate + 1) % this.queue.length;
      }
      nextIdx = candidate;
    } else if (this.queueIdx + 1 < this.queue.length) {
      nextIdx = this.queueIdx + 1;
    } else if (!fromAutoComplete || this.repeatMode === 'all') {
      nextIdx = 0;
    } else {
      // 顺序播放且已到队列末尾
      return;
    }
    await this.playQueueIndex(nextIdx);
  }

  /** 播放上一首曲目（当前曲目已播放超过 3 秒时回到片头重播，否则切回上一首）。 */
  async playPrevious(): Promise<void> {
    if (this.posMs > 3000 || this.queue.length <= 1) {
      this.seekMs(0);
      if (!this.playing) {
        this.setPlaying(true);
      }
      return;
    }
    const prevIdx = this.queueIdx > 0 ? this.queueIdx - 1 : this.queue.length - 1;
    await this.playQueueIndex(prevIdx);
  }

  /** 跳转播放队列中指定下标的曲目。 */
  async playQueueIndex(index: number): Promise<void> {
    if (index < 0 || index >= this.queue.length) {
      return;
    }
    this.queueIdx = index;
    const item = this.queue[index];
    const resolved = await this.resolveQueueItem(item, index);
    if (!resolved) {
      return;
    }
    await this.loadTrackInternal(resolved, false);
  }

  private async resolveQueueItem(item: HarmonyQueueItem, index: number): Promise<HarmonyPlaybackRequest | null> {
    const artist = (item.artist ?? '').trim();
    const album = (item.album ?? '').trim();
    const fallbackSub = item.subtitle && item.subtitle.trim().length > 0
      ? item.subtitle
      : (artist.length > 0 && album.length > 0 ? `${artist} · ${album}` : (artist || album || '音乐连播'));

    if ((item.fdPath ?? '').trim().length > 0 || (item.url ?? '').trim().length > 0) {
      return {
        url: item.url ?? '',
        fdPath: item.fdPath,
        headers: item.headers,
        title: item.title,
        subtitle: fallbackSub,
        artist: artist,
        album: album,
        artworkUrl: item.artworkUrl,
        isAudio: true,
        lyricsUrl: item.lyricsUrl,
        lyricsLrc: item.lyricsLrc,
        itemId: item.itemId,
        server: item.server,
        mediaSourceId: item.mediaSourceId,
        resumePositionMs: item.resumePositionMs,
        isSessionBound: this.activeReq?.isSessionBound ?? true,
        queue: this.queue,
        queueIndex: index
      };
    }

    const repo = MoviePilotRepository.shared();
    if (item.itemId.trim().length > 0) {
      const info = await repo.fetchVideoStreamInfo(item.itemId, item.server ?? '', item.mediaSourceId ?? '');
      if (info && info.contentUrl.length > 0) {
        return {
          url: info.contentUrl,
          headers: info.headers,
          title: info.title.length > 0 ? info.title : item.title,
          subtitle: fallbackSub,
          artist: info.artist.length > 0 ? info.artist : artist,
          album: info.album.length > 0 ? info.album : album,
          artworkUrl: info.artworkUrl.length > 0 ? info.artworkUrl : item.artworkUrl,
          isAudio: true,
          lyricsUrl: info.lyricsUrl,
          itemId: info.itemId,
          server: info.server,
          mediaSourceId: info.mediaSourceId,
          resumePositionMs: info.resumePositionMs,
          isSessionBound: true,
          queue: this.queue,
          queueIndex: index
        };
      }
    }

    const musicStream = await repo.fetchMusicStreamInfo(
      item.title,
      artist,
      album,
      item.mediaSource ?? '',
      item.mediaId ?? '',
      item.trackNumber ?? 0
    );
    if (!musicStream || musicStream.contentUrl.length === 0) {
      return null;
    }
    return {
      url: musicStream.contentUrl,
      headers: musicStream.headers,
      title: musicStream.title.length > 0 ? musicStream.title : item.title,
      subtitle: fallbackSub,
      artist: musicStream.artist.length > 0 ? musicStream.artist : artist,
      album: musicStream.album.length > 0 ? musicStream.album : album,
      artworkUrl: musicStream.artworkUrl.length > 0 ? musicStream.artworkUrl : item.artworkUrl,
      isAudio: true,
      lyricsUrl: musicStream.lyricsUrl,
      itemId: musicStream.itemId,
      server: musicStream.server,
      mediaSourceId: musicStream.mediaSourceId,
      resumePositionMs: musicStream.resumePositionMs,
      isSessionBound: true,
      queue: this.queue,
      queueIndex: index
    };
  }

  /** 循环切换播放队列模式：顺序 -> 列表循环 -> 单曲循环 -> 随机。 */
  cycleRepeatMode(): HarmonyRepeatMode {
    const order: HarmonyRepeatMode[] = ['sequence', 'all', 'one', 'shuffle'];
    const idx = order.indexOf(this.repeatMode);
    this.repeatMode = order[(idx + 1) % order.length];
    this.syncAvSessionPlaybackState();
    this.notify();
    return this.repeatMode;
  }

  setRepeatMode(mode: HarmonyRepeatMode): void {
    this.repeatMode = mode;
    this.syncAvSessionPlaybackState();
    this.notify();
  }

  private async ensureAvSession(ctx: common.BaseContext, req: HarmonyPlaybackRequest): Promise<void> {
    try {
      if (!this.session) {
        const s = await avSession.createAVSession(ctx, 'MoviePilotAudio', 'audio');
        s.on('play', () => { this.setPlaying(true); });
        s.on('pause', () => { this.setPlaying(false); });
        s.on('stop', () => { this.stopAndRelease(); });
        s.on('seek', (timeMs: number) => { this.seekMs(timeMs); });
        s.on('playNext', () => { this.playNext(false).catch(() => {}); });
        s.on('playPrevious', () => { this.playPrevious().catch(() => {}); });
        s.on('setLoopMode', (mode: avSession.LoopMode) => {
          if (mode === avSession.LoopMode.LOOP_MODE_SINGLE) {
            this.setRepeatMode('one');
          } else if (mode === avSession.LoopMode.LOOP_MODE_LIST) {
            this.setRepeatMode('all');
          } else if (mode === avSession.LoopMode.LOOP_MODE_SHUFFLE) {
            this.setRepeatMode('shuffle');
          } else {
            this.setRepeatMode('sequence');
          }
        });
        await s.activate();
        this.session = s;
      }
      this.syncAvSessionMetadata(req);
      this.syncAvSessionPlaybackState();
    } catch {
      // 预览器或受限沙盒忽略 AVSession 异常
    }
  }

  private syncAvSessionMetadata(overrideReq?: HarmonyPlaybackRequest): void {
    const req = overrideReq ?? this.activeReq;
    if (!this.session || !req) {
      return;
    }
    try {
      const meta: avSession.AVMetadata = {
        assetId: req.itemId || req.fdPath || req.url || 'mp_audio',
        title: req.title,
        artist: (req.artist && req.artist.length > 0) ? req.artist : req.subtitle,
        album: req.album ?? '',
        duration: this.durMs > 0 ? this.durMs : undefined
      };
      if (this.artworkPixelMap) {
        meta.mediaImage = this.artworkPixelMap;
      }
      if (this.rawLyricsText.length > 0) {
        meta.lyric = this.rawLyricsText;
      }
      const line = this.activeLyricLine();
      if (line.length > 0) {
        meta.singleLyricText = line;
      }
      this.session.setAVMetadata(meta).catch(() => {});
    } catch {
      // ignore
    }
  }

  private syncAvSessionSingleLyric(): void {
    if (!this.session || !this.activeReq) {
      return;
    }
    const line = this.activeLyricLine();
    if (!line) {
      return;
    }
    this.syncAvSessionMetadata();
  }

  private mapLoopMode(): avSession.LoopMode {
    if (this.repeatMode === 'one') {
      return avSession.LoopMode.LOOP_MODE_SINGLE;
    }
    if (this.repeatMode === 'all') {
      return avSession.LoopMode.LOOP_MODE_LIST;
    }
    if (this.repeatMode === 'shuffle') {
      return avSession.LoopMode.LOOP_MODE_SHUFFLE;
    }
    return avSession.LoopMode.LOOP_MODE_SEQUENCE;
  }

  private syncAvSessionPlaybackState(): void {
    if (!this.session) {
      return;
    }
    try {
      this.session.setAVPlaybackState({
        state: this.playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: HARMONY_SPEED_VALUES[this.speedIdx] ?? 1.0,
        loopMode: this.mapLoopMode(),
        position: {
          elapsedTime: this.posMs,
          updateTime: Date.now()
        }
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  private startBackgroundPlaybackIfNeeded(): void {
    if (this.bgTaskRunning || !this.hostContext) {
      return;
    }
    const ctx = this.hostContext;
    try {
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'com.moviepilot.app',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      wantAgent.getWantAgent(agentInfo).then((agent: Object) => {
        if (!this.playing) {
          return;
        }
        backgroundTaskManager.startBackgroundRunning(
          ctx,
          backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
          agent
        ).then(() => {
          this.bgTaskRunning = true;
        }).catch(() => {});
      }).catch(() => {});
    } catch {
      // 模拟器或无后台权限场景静默降级
    }
  }

  private stopBackgroundPlaybackIfNeeded(): void {
    if (!this.bgTaskRunning || !this.hostContext) {
      this.bgTaskRunning = false;
      return;
    }
    this.bgTaskRunning = false;
    try {
      backgroundTaskManager.stopBackgroundRunning(this.hostContext).catch(() => {});
    } catch {
      // ignore
    }
  }

  private startProgressTimer(): void {
    if (this.progressTimerId !== -1) {
      return;
    }
    this.progressTimerId = setInterval(() => {
      if (!this.activeReq) {
        this.stopProgressTimer();
        return;
      }
      this.progressTickCount += 1;
      if (this.progressTickCount % 10 === 0 && this.durMs > 60000) {
        const resumeKey = buildPlaybackResumeKey(this.activeReq);
        if (resumeKey.length > 0) {
          PlaybackPreferencesStore.saveLocalResumeMs(resumeKey, this.posMs, this.durMs);
        }
      }
      this.dispatchAudioSync('tick', !this.playing);
    }, 1000);
  }

  private stopProgressTimer(): void {
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
  }

  private dispatchAudioSync(
    trigger: 'start' | 'tick' | 'pause' | 'resume' | 'seek' | 'track_change' | 'background' | 'stop' | 'finish',
    isPaused: boolean,
    posOverrideMs?: number
  ): void {
    const req = this.activeReq;
    if (!req) {
      return;
    }
    const pos = posOverrideMs !== undefined ? Math.max(0, Math.round(posOverrideMs)) : this.posMs;
    if ((trigger === 'pause' || trigger === 'stop') && this.durMs > 60000) {
      const resumeKey = buildPlaybackResumeKey(req);
      if (resumeKey.length > 0) {
        PlaybackPreferencesStore.saveLocalResumeMs(resumeKey, pos, this.durMs);
      }
    }
    const itemId = (req.itemId ?? '').trim();
    const server = (req.server ?? '').trim();
    if (itemId.length === 0 || server.length === 0 || itemId.startsWith('file.') || itemId.startsWith('file:')) {
      return;
    }
    const decision = this.audioSyncTracker.step(trigger, pos, this.durMs, isPaused);
    if (decision.state === 'started') {
      this.audioStartedSent = true;
    }
    HarmonyPlaybackProgressReporter.shared().enqueueDecision(
      MoviePilotRepository.shared(),
      itemId,
      server,
      req.mediaSourceId ?? '',
      decision,
      req.playSessionId ?? this.audioSyncTracker.getPlaySessionId(),
      this.durMs
    );
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
          this.startBackgroundPlaybackIfNeeded();
          this.startProgressTimer();
        } else {
          this.player.pause().catch(() => {});
          this.startProgressTimer();
          this.dispatchAudioSync('pause', true);
        }
      } catch {
        // ignore
      }
    }
    this.syncAvSessionPlaybackState();
    this.notify();
  }

  /** 按毫秒精确定位播放进度。 */
  seekMs(targetMs: number): void {
    const clamped = this.durMs > 0
      ? Math.min(this.durMs, Math.max(0, Math.round(targetMs)))
      : Math.max(0, Math.round(targetMs));
    this.posMs = clamped;
    this.currentLyricIdx = findActiveLyricIndex(this.lyricCues, this.posMs);
    if (this.player) {
      try {
        this.player.seek(clamped);
      } catch {
        // ignore
      }
    }
    this.dispatchAudioSync('seek', !this.playing, clamped);
    this.syncAvSessionPlaybackState();
    this.notify();
  }

  /** 按百分比定位播放进度。 */
  seekPercent(pct: number): void {
    if (this.durMs <= 0) {
      return;
    }
    const targetMs = Math.round((Math.min(100, Math.max(0, pct)) / 100) * this.durMs);
    this.seekMs(targetMs);
  }

  /** 循环切换音频倍速（0.5x ~ 2.0x）。 */
  cycleSpeed(): number {
    return this.setSpeedIndex((this.speedIdx + 1) % HARMONY_SPEED_ENUMS.length);
  }

  /** 指定音频倍速档位下标（0 ~ 5）。 */
  setSpeedIndex(index: number): number {
    const clamped = Math.max(0, Math.min(HARMONY_SPEED_ENUMS.length - 1, index));
    this.speedIdx = clamped;
    if (this.player) {
      try {
        this.player.setSpeed(HARMONY_SPEED_ENUMS[this.speedIdx]);
      } catch {
        // ignore
      }
    }
    this.syncAvSessionPlaybackState();
    this.notify();
    return this.speedIdx;
  }

  private async releasePlayerOnly(): Promise<void> {
    this.stopProgressTimer();
    const prev = this.player;
    this.player = null;
    if (prev) {
      try {
        await prev.release();
      } catch {
        // ignore
      }
    }
    const fdHandle = this.openedFd;
    this.openedFd = null;
    closeLocalPlaybackFd(fdHandle);
  }

  /** 仅当当前音频绑定登录会话时停止释放（用于退出登录或切换实例，不影响本地外部文件播放）。 */
  stopIfSessionBound(): boolean {
    if (!this.isSessionBound()) {
      return false;
    }
    this.stopAndRelease();
    return true;
  }

  /** 彻底停止并释放后台音频、`AVSession` 与后台长时任务。 */
  stopAndRelease(): void {
    this.loadGeneration++;
    this.dispatchAudioSync('stop', true);
    this.playing = false;
    this.buffering = false;
    this.activeSourceKey = '';
    this.activeReq = null;
    this.queue = [];
    this.queueIdx = 0;
    this.posMs = 0;
    this.durMs = 0;
    this.rawLyricsText = '';
    this.lyricCues = [];
    this.plainLyricsLines = [];
    this.currentLyricIdx = -1;
    this.releasePlayerOnly();
    this.releaseArtworkPixelMap();
    this.stopBackgroundPlaybackIfNeeded();
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
