import { media } from '@kit.MediaKit';
import { MpExternalSubtitle, MpVideoStreamInfo } from '@moviepilot/core_rust_bridge';

/** 字幕轨道选项（同时覆盖内封轨道与服务端 `/stream-subtitle` 外挂轨道）。 */
export interface HarmonySubtitleOption {
  id: string;
  label: string;
  language: string;
  format?: string;
  isExternal: boolean;
  url?: string;
  trackIndex?: number;
}

/** 音轨选项模型（对应 `AVPlayer.getTrackDescription()` 中的音频流）。 */
export interface HarmonyAudioTrackOption {
  trackIndex: number;
  label: string;
  language: string;
  codec?: string;
}

/** 剧集连播队列或音乐播放列表队列项模型。 */
export interface HarmonyQueueItem {
  itemId: string;
  title: string;
  subtitle?: string;
  server?: string;
  artworkUrl?: string;
  artist?: string;
  album?: string;
  mediaSource?: string;
  mediaId?: string;
  mediaSourceId?: string;
  trackNumber?: number;
  durationMs?: number;
  resumePositionMs?: number;
  url?: string;
  fdPath?: string;
  headers?: Record<string, string>;
  lyricsUrl?: string;
  lyricsLrc?: string;
}

/** 音频队列循环模式：顺序播放 / 列表循环 / 单曲循环 / 随机播放。 */
export type HarmonyRepeatMode = 'sequence' | 'all' | 'one' | 'shuffle';

/** 鸿蒙原生音视频统一播放请求模型（向后兼容旧版四字段调用，同时覆盖鉴权头、字幕、音轨、断点与队列）。 */
export interface HarmonyPlaybackRequest {
  url: string;
  fdPath?: string;
  cleanupTempOnClose?: boolean;
  headers?: Record<string, string>;
  proxyFallbackUrl?: string;
  proxyFallbackHeaders?: Record<string, string>;
  title: string;
  subtitle: string;
  artist?: string;
  album?: string;
  artworkUrl?: string;
  isAudio: boolean;
  lyricsLrc?: string;
  lyricsUrl?: string;
  itemId?: string;
  server?: string;
  mediaSourceId?: string;
  resumePositionMs?: number;
  subtitles?: HarmonySubtitleOption[];
  preferredAudioLang?: string;
  preferredAudioIndex?: number;
  preferredSubLang?: string;
  preferredExternalSubUrl?: string;
  disableSubtitles?: boolean;
  isSessionBound?: boolean;
  queue?: HarmonyQueueItem[];
  queueIndex?: number;
}

/** 构建流式播放请求时的可选附加参数。 */
export interface StreamPlaybackBuildExtras {
  preferredAudioLang?: string;
  preferredAudioIndex?: number;
  preferredSubLang?: string;
  preferredExternalSubUrl?: string;
  disableSubtitles?: boolean;
  queue?: HarmonyQueueItem[];
  queueIndex?: number;
  overrideResumeMs?: number;
  overrideArtworkUrl?: string;
}

/** 6 档标准倍速对应的 `media.PlaybackSpeed` 枚举数组。 */
export const HARMONY_SPEED_ENUMS: media.PlaybackSpeed[] = [
  media.PlaybackSpeed.SPEED_FORWARD_0_50_X,
  media.PlaybackSpeed.SPEED_FORWARD_0_75_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_00_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_25_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_50_X,
  media.PlaybackSpeed.SPEED_FORWARD_2_00_X
];

/** 6 档标准倍速数值数组。 */
export const HARMONY_SPEED_VALUES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/** 6 档标准倍速展示文案数组。 */
export const HARMONY_SPEED_LABELS: string[] = ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x'];

/** `1.0x` 在 6 档倍速数组中的下标。 */
export const DEFAULT_AUDIO_SPEED_INDEX: number = 2;

/** `2.0x` 在 6 档倍速数组中的下标（用于长按二倍速加速）。 */
export const BOOST_2X_SPEED_INDEX: number = 5;

/** 将毫秒格式化为 `MM:SS` 或 `H:MM:SS`。 */
export function formatMediaDurationMs(ms: number): string {
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

/** 将秒数偏移格式化为带正负号的提示文案（如 `+15s`、`-10s`）。 */
export function formatSignedDeltaSec(deltaSec: number): string {
  const rounded = Math.round(deltaSec);
  if (rounded >= 0) {
    return `+${rounded}s`;
  }
  return `${rounded}s`;
}

/** 为给定播放请求生成稳定的本地断点持久化键。 */
export function buildPlaybackResumeKey(req: HarmonyPlaybackRequest): string {
  const itemId = (req.itemId ?? '').trim();
  const srv = (req.server ?? '').trim();
  if (itemId.length > 0 && !itemId.startsWith('file.')) {
    return srv.length > 0 ? `ms:${srv}:${itemId}` : `ms::_:${itemId}`;
  }
  const fd = (req.fdPath ?? '').trim();
  if (fd.length > 0) {
    return `fd:${fd}`;
  }
  const u = req.url.trim();
  if (u.length > 0) {
    const qIdx = u.indexOf('?');
    return `url:${qIdx >= 0 ? u.substring(0, qIdx) : u}`;
  }
  return '';
}

/** 判断语言代码或轨道标题是否属于中文（简/繁/国/粤）。 */
export function isChineseLanguageTrack(language: string, label: string): boolean {
  const lang = language.trim().toLowerCase();
  const lbl = label.trim().toLowerCase();
  if (
    lang === 'zh' ||
    lang === 'chi' ||
    lang === 'zho' ||
    lang === 'cmn' ||
    lang === 'chs' ||
    lang === 'cht' ||
    lang === 'yue' ||
    lang.startsWith('zh-') ||
    lang.startsWith('zh_')
  ) {
    return true;
  }
  return (
    lbl.includes('中文') ||
    lbl.includes('简体') ||
    lbl.includes('繁体') ||
    lbl.includes('简中') ||
    lbl.includes('繁中') ||
    lbl.includes('中字') ||
    lbl.includes('chinese') ||
    lbl.includes('chs') ||
    lbl.includes('cht')
  );
}

/** 判断请求头字典是否包含至少一个非空键值。 */
export function hasNonEmptyHeaders(headers?: Record<string, string>): boolean {
  if (!headers) {
    return false;
  }
  const keys = Object.keys(headers);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (k.length > 0 && (headers[k] ?? '').length > 0) {
      return true;
    }
  }
  return false;
}

/** 将服务端返回的 `MpExternalSubtitle[]` 转换为播放器统一 `HarmonySubtitleOption[]`。 */
export function mapExternalSubtitlesToOptions(subtitles: MpExternalSubtitle[]): HarmonySubtitleOption[] {
  const result: HarmonySubtitleOption[] = [];
  for (let i = 0; i < subtitles.length; i++) {
    const sub = subtitles[i];
    if (!sub.url || sub.url.trim().length === 0) {
      continue;
    }
    result.push({
      id: `ext_${sub.subtitleId || String(sub.index)}_${i}`,
      label: sub.label || `外挂字幕 ${i + 1}`,
      language: sub.language || '',
      format: sub.format || '',
      isExternal: true,
      url: sub.url
    });
  }
  return result;
}

/** 由 `MpVideoStreamInfo` 组装完整 `HarmonyPlaybackRequest`，确保鉴权头、字幕、断点与元数据零遗漏。 */
export function buildPlaybackRequestFromStreamInfo(
  stream: MpVideoStreamInfo,
  fallbackTitle: string,
  fallbackSubtitle: string,
  extras?: StreamPlaybackBuildExtras
): HarmonyPlaybackRequest {
  const isAudio = stream.mediaType === 'audio';
  const title = stream.title.trim().length > 0 ? stream.title : fallbackTitle;
  const artist = stream.artist.trim();
  const album = stream.album.trim();
  let subtitle = fallbackSubtitle;
  if (isAudio && (artist.length > 0 || album.length > 0)) {
    subtitle = artist.length > 0 && album.length > 0 ? `${artist} · ${album}` : (artist || album);
  }
  const resumeMs = extras?.overrideResumeMs !== undefined && extras.overrideResumeMs > 0
    ? extras.overrideResumeMs
    : stream.resumePositionMs;
  const artwork = (extras?.overrideArtworkUrl && extras.overrideArtworkUrl.length > 0)
    ? extras.overrideArtworkUrl
    : stream.artworkUrl;
  return {
    url: stream.contentUrl,
    headers: stream.headers,
    proxyFallbackUrl: stream.proxyFallbackUrl,
    proxyFallbackHeaders: stream.proxyFallbackHeaders,
    title: title,
    subtitle: subtitle,
    artist: artist,
    album: album,
    artworkUrl: artwork,
    isAudio: isAudio,
    lyricsUrl: stream.lyricsUrl,
    itemId: stream.itemId,
    server: stream.server,
    mediaSourceId: stream.mediaSourceId,
    resumePositionMs: resumeMs,
    subtitles: mapExternalSubtitlesToOptions(stream.subtitles),
    preferredAudioLang: extras?.preferredAudioLang,
    preferredAudioIndex: extras?.preferredAudioIndex,
    preferredSubLang: extras?.preferredSubLang,
    preferredExternalSubUrl: extras?.preferredExternalSubUrl,
    disableSubtitles: extras?.disableSubtitles,
    isSessionBound: true,
    queue: extras?.queue,
    queueIndex: extras?.queueIndex
  };
}
