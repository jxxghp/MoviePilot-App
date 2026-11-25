import nativeCore from 'libmoviepilot_core_ohos.so';

/**
 * 鸿蒙端 Rust 共享内核桥接门面（直接消费 ohos-rs 编译的 `libmoviepilot_core_ohos.so`）：
 * 提供 DeepLink 解析、9 维站点资源筛选分组、Agent Markdown AST、JWT/权限计算、
 * 动态插件表单规划与无损补丁、5 字段 Cron 分析与 3D 勋章金属色板。
 */
export interface NativeCoreModule {
  coreVersion(): string;
  normalizeServerAddress(raw: string): string;
  serverAddressContains?(baseUrl: string, candidateUrl: string): boolean;
  buildV3EndpointUrl?(baseUrl: string, segments: string[], queryJson: string, trailingSlash: boolean): string;
  parseDeepLinkJson(rawUrl: string): string;
  detectPlayableMediaKind(pathOrExt: string, includeStreaming: boolean): string;
  parseStrmJson?(rawText: string, fallbackFileName: string): string;
  parseAgentMarkdownJson(markdown: string): string;
  filterAndGroupResources(resourcesJson: string, criteriaJson: string): string;
  decodeJwtClaimsJson(token: string, nowEpochSecs: number): string;
  evaluatePermissionsJson(permissionsJson: string, isSuperuser: boolean): string;
  classifyAuthStatusStr?(status: number, body: string): string;
  planPluginFormJson(documentJson: string): string;
  applyPluginFormPatch(originalModelJson: string, patchJson: string): string;
  evaluatePluginExpression(expr: string, modelJson: string): boolean;
  analyzeCronJson(expr: string): string;
  computeMedalPaletteJson(medalId: string): string;
  computeSubscribeProgressJson(total: number, lack: number): string;
  planPlaybackSyncStepJson?(stateJson: string, inputJson: string): string;
  normalizePendingPlaybackStopsJson?(entriesJson: string, nowEpochMs: number): string;
  planPlaybackRoutesJson?(routesJson: string, prefsJson: string, probesJson: string): string;
  isSameHttpOrigin?(urlA: string, urlB: string): boolean;
  resolvePlaybackEngineJson?(inputJson: string): string;
  buildExternalPlayerUrl?(template: string, mediaUrl: string, title: string): string;
  validatePluginBridgeApiPath?(rawPath: string): string;
  validatePluginShellAsset?(virtualPath: string): string;
  buildPluginRemoteCacheKeyJson?(instanceOrigin: string, pluginId: string, versionOrHash: string): string;
  normalizePluginRemoteEntryJson?(pluginId: string, versionOrHash: string, rawRemoteUrl: string): string;
  resolvePluginRemoteUpstreamJson?(virtualPath: string): string;
}

export interface PluginRemoteCacheKey {
  instance_hash: string;
  plugin_id_lower: string;
  version_segment: string;
  relative_dir: string;
}

export interface PluginRemoteEntryPlan {
  plugin_id: string;
  version_tag: string;
  virtual_entry_path: string;
  upstream_file_path: string;
}

export interface PluginRemoteUpstreamTarget {
  plugin_id: string;
  version_tag: string;
  asset_rel_path: string;
  upstream_api_path: string;
}

export interface EngineResolutionInput {
  platform: string;
  preferred: string;
  is_audio: boolean;
  decode_force_software: boolean;
  has_enhanced_engine: boolean;
  has_legacy_engine: boolean;
  url_or_filename: string;
  container?: string | null;
  video_codec?: string | null;
  audio_codec?: string | null;
  has_ass_or_pgs_subtitle?: boolean;
  ignore_ass_style?: boolean;
  allow_self_signed_tls?: boolean;
  is_hdr?: boolean;
}

export interface EngineResolutionPlan {
  primary: string;
  fallback?: string | null;
  reason: string;
}

export interface PlaybackRouteCandidate {
  kind: string;
  url: string;
  probe_url?: string | null;
  headers: Record<string, string>;
  priority: number;
  requires_same_origin_auth: boolean;
}

export interface PlaybackRoutePreference {
  prefer_strm_direct: boolean;
  prefer_server_direct: boolean;
  lan_preferred_max_latency_ms: number;
}

export interface RouteProbeOutcome {
  url: string;
  reachable: boolean;
  latency_ms?: number | null;
}

export interface PlaybackRoutePlan {
  active: PlaybackRouteCandidate;
  fallbacks: PlaybackRouteCandidate[];
  route_label_zh: string;
}

export interface PlaybackSyncState {
  play_session_id: string;
  started_sent: boolean;
  stopped_sent: boolean;
  paused_since_ms?: number | null;
  last_report_at_ms?: number | null;
  last_playing_tick_at_ms?: number | null;
  last_seek_at_ms?: number | null;
  cumulative_playback_time_ms: number;
  seq: number;
  last_position_ms: number;
  last_audio_stream_index?: number | null;
  last_subtitle_stream_index?: number | null;
}

export interface PlaybackSyncInput {
  trigger: 'start' | 'tick' | 'pause' | 'resume' | 'seek' | 'track_change' | 'background' | 'stop' | 'finish';
  now_ms: number;
  position_ms: number;
  duration_ms?: number | null;
  is_paused: boolean;
  audio_stream_index?: number | null;
  subtitle_stream_index?: number | null;
}

export interface PlaybackSyncDecision {
  should_report: boolean;
  state: string;
  event_name?: string | null;
  is_paused: boolean;
  position_ms: number;
  playback_time_ms: number;
  seq: number;
  next_state: PlaybackSyncState;
}

export interface PendingPlaybackStop {
  server: string;
  item_id: string;
  media_source_id?: string | null;
  position_ms: number;
  duration_ms?: number | null;
  play_session_id?: string | null;
  playback_time_ms?: number | null;
  seq?: number | null;
  updated_at_ms: number;
}

export interface MedalPalette {
  medal_id: string;
  base_hex: string;
  rim_hex: string;
  engrave_dark_hex: string;
  engrave_light_hex: string;
  tier: string;
}

export interface SubscribeProgress {
  total: number;
  completed: number;
  lack: number;
  ratio: number;
  label: string;
}

export interface CronSummary {
  rawValue: string;
  format: string;
  fields: string[];
  hasAmbiguousWeekday: boolean;
  descriptionZh: string;
  isValidFiveField: boolean;
}

export interface ParsedStrmStream {
  url: string;
  headers: Record<string, string>;
  mediaKind: string;
}

/** 鸿蒙 Rust 共享业务内核统一入口（优先直接调用原生 .so NAPI）。 */
export class RustCoreBridge {
  private static nativeLib: NativeCoreModule | null = nativeCore as NativeCoreModule;

  static bindNativeModule(mod: NativeCoreModule): void {
    RustCoreBridge.nativeLib = mod;
  }

  static isNativeLoaded(): boolean {
    try {
      return RustCoreBridge.nativeLib !== null && RustCoreBridge.nativeLib.coreVersion().length > 0;
    } catch {
      return false;
    }
  }

  /** 返回 Rust 共享内核版本。 */
  static version(): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.coreVersion();
      }
    } catch {
      // fallback
    }
    return '2.0.3';
  }

  /** 规范化 MoviePilot 实例地址（拒绝内嵌凭据并保留反代子路径）。 */
  static normalizeServerAddress(raw: string): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.normalizeServerAddress(raw);
      }
    } catch (e) {
      throw new Error(String(e));
    }
    const trimmed = raw.trim().replace(/\/+$/, '');
    if (!trimmed) {
      throw new Error('服务地址不能为空');
    }
    const normalized = trimmed.includes('://') ? trimmed : `http://${trimmed}`;
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      throw new Error('仅支持 http 或 https 协议');
    }
    if (normalized.includes('@')) {
      throw new Error('服务地址不允许内嵌用户名或密码');
    }
    return normalized;
  }

  /** 校验候选 URL 是否严格归属于当前 MoviePilot 实例同源与子路径边界（防跨源泄露 JWT/Cookie）。 */
  static serverAddressContains(baseUrl: string, candidateUrl: string): boolean {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.serverAddressContains) {
        return RustCoreBridge.nativeLib.serverAddressContains(baseUrl, candidateUrl);
      }
    } catch {
      // fallback
    }
    try {
      const cleanBase = RustCoreBridge.normalizeServerAddress(baseUrl);
      return candidateUrl === cleanBase || candidateUrl.startsWith(`${cleanBase}/`) || candidateUrl.startsWith(`${cleanBase}?`);
    } catch {
      return false;
    }
  }

  /** 构造 `/api/v1/...` 完整请求 URL（优先委托 Rust 内核校验边界并编码 UTF-8 中文路径段）。 */
  static buildV3EndpointUrl(
    baseUrl: string,
    segments: string[],
    query: Record<string, string> = {},
    trailingSlash: boolean = false
  ): string {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.buildV3EndpointUrl) {
        const pairs: Array<[string, string]> = Object.keys(query).map((k: string): [string, string] => [k, query[k]]);
        return RustCoreBridge.nativeLib.buildV3EndpointUrl(baseUrl, segments, JSON.stringify(pairs), trailingSlash);
      }
    } catch {
      // fallback
    }
    const cleanBase = RustCoreBridge.normalizeServerAddress(baseUrl);
    const path = segments.map((s: string) => encodeURIComponent(s)).join('/');
    let url = `${cleanBase}/api/v1/${path}${trailingSlash ? '/' : ''}`;
    const keys = Object.keys(query);
    if (keys.length > 0) {
      const pairs: string[] = [];
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`);
      }
      url += `?${pairs.join('&')}`;
    }
    return url;
  }

  /** 识别 HTTP 401 或令牌失效型 403（区分越权 403 与必须登出的过期令牌）。 */
  static classifyAuthStatus(status: number, body: string): string {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.classifyAuthStatusStr) {
        return RustCoreBridge.nativeLib.classifyAuthStatusStr(status, body);
      }
    } catch {
      // fallback
    }
    if (status === 401) { return 'logout'; }
    if (status === 403) {
      const lower = body.toLowerCase();
      if (lower.includes('could not validate credentials') || lower.includes('token校验不通过') || lower.includes('凭据验证失败')) {
        return 'logout';
      }
      return 'forbidden';
    }
    return 'valid';
  }

  /** 动态评估插件表单 `v-if` / `v-show` 表达式。 */
  static evaluatePluginExpression(expr: string, modelJson: string): boolean {
    if (!expr || expr.trim().length === 0) { return true; }
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.evaluatePluginExpression(expr, modelJson);
      }
    } catch {
      // fallback
    }
    return true;
  }

  static parseDeepLinkJson(rawUrl: string): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.parseDeepLinkJson(rawUrl);
      }
    } catch {
      // fallback
    }
    return '{"kind":"discover"}';
  }

  static detectPlayableMediaKind(pathOrExt: string, includeStreaming: boolean = false): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.detectPlayableMediaKind(pathOrExt, includeStreaming);
      }
    } catch {
      // fallback
    }
    const clean = pathOrExt.trim().toLowerCase();
    const parts = clean.split('.');
    const ext = parts.length > 1 ? parts[parts.length - 1] : clean.replace(/^\.+/, '');
    if (ext === 'strm') {
      if (parts.length > 2 && ['mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'alac', 'ape'].includes(parts[parts.length - 2])) {
        return 'audio';
      }
      return 'video';
    }
    if (['mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'alac', 'ape'].includes(ext)) {
      return 'audio';
    }
    if (['mp4', 'mkv', 'mov', 'avi', 'ts', 'm2ts', 'webm', 'flv', 'wmv', 'strm'].includes(ext)) {
      return 'video';
    }
    if (includeStreaming && ['m3u8', 'mpd'].includes(ext)) {
      return 'video';
    }
    return '';
  }

  /** 判断文件名或路径是否为 `.strm` 直链描述文件。 */
  static isStrmPath(pathOrName: string): boolean {
    const clean = (pathOrName ?? '').trim().replace(/^\.+/, '').toLowerCase();
    if (!clean) {
      return false;
    }
    const dotIdx = clean.lastIndexOf('.');
    const ext = dotIdx >= 0 ? clean.substring(dotIdx + 1) : clean;
    return ext === 'strm';
  }

  /** 解析 `.strm` 文本，提取客户端 HTTP(S) 直链、可选播放器请求头及音视频模式。 */
  static parseStrmContent(rawText: string, fallbackFileName: string = ''): ParsedStrmStream | null {
    if (!rawText || rawText.length > 65536 || rawText.indexOf('\u0000') >= 0) {
      return null;
    }
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.parseStrmJson) {
        const rawJson = RustCoreBridge.nativeLib.parseStrmJson(rawText, fallbackFileName);
        if (rawJson && rawJson.length > 0) {
          const parsed = JSON.parse(rawJson) as Record<string, Object>;
          const url = typeof parsed['url'] === 'string' ? (parsed['url'] as string) : '';
          const mediaKind = typeof parsed['mediaKind'] === 'string' ? (parsed['mediaKind'] as string) : 'video';
          const headers: Record<string, string> = {};
          if (parsed['headers'] && typeof parsed['headers'] === 'object') {
            const hdrObj = parsed['headers'] as Record<string, string>;
            const keys = Object.keys(hdrObj);
            for (let i = 0; i < keys.length; i++) {
              const k = keys[i];
              if (typeof hdrObj[k] === 'string' && hdrObj[k].length > 0) {
                headers[k] = hdrObj[k];
              }
            }
          }
          if (url.length > 0) {
            return { url: url, headers: headers, mediaKind: mediaKind };
          }
        }
      }
    } catch {
      // fallback
    }
    const headers: Record<string, string> = {};
    const body = rawText.startsWith('\uFEFF') ? rawText.substring(1) : rawText;
    const lines = body.split(/\r?\n/);
    let targetLine = '';
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) {
        continue;
      }
      if (line.startsWith('#')) {
        const rest = line.substring(1).trim();
        if (rest.toLowerCase().startsWith('extvlcopt:')) {
          const kv = rest.substring(10).trim();
          const eq = kv.indexOf('=');
          if (eq > 0) {
            const k = kv.substring(0, eq).trim().toLowerCase();
            const v = kv.substring(eq + 1).trim();
            if (v.length > 0 && !/[\r\n]/.test(v)) {
              if (k === 'http-user-agent') { headers['User-Agent'] = v; }
              else if (k === 'http-referrer' || k === 'http-referer') { headers['Referer'] = v; }
              else if (k === 'http-cookie') { headers['Cookie'] = v; }
            }
          }
        }
        continue;
      }
      if (!targetLine) {
        targetLine = line;
      }
    }
    if (!targetLine) {
      return null;
    }
    const pipeIdx = targetLine.indexOf('|');
    const urlPart = (pipeIdx >= 0 ? targetLine.substring(0, pipeIdx) : targetLine).trim();
    const pipePart = pipeIdx >= 0 ? targetLine.substring(pipeIdx + 1).trim() : '';
    if (pipePart.length > 0) {
      const pairs = pipePart.split('&');
      for (let i = 0; i < pairs.length; i++) {
        const eq = pairs[i].indexOf('=');
        if (eq > 0) {
          const k = pairs[i].substring(0, eq).trim().toLowerCase();
          let v = pairs[i].substring(eq + 1).trim();
          try { v = decodeURIComponent(v); } catch { /* keep raw */ }
          if (v.length > 0 && !/[\r\n]/.test(v)) {
            if (k === 'user-agent') { headers['User-Agent'] = v; }
            else if (k === 'referer' || k === 'referrer') { headers['Referer'] = v; }
            else if (k === 'cookie') { headers['Cookie'] = v; }
            else if (k === 'origin') { headers['Origin'] = v; }
            else if (k === 'authorization') { headers['Authorization'] = v; }
          }
        }
      }
    }
    const normalized = RustCoreBridge.normalizeStrmHttpUrl(urlPart);
    if (!normalized) {
      return null;
    }
    const pathPart = normalized.split('?')[0];
    const kind = (!RustCoreBridge.isStrmPath(pathPart) ? RustCoreBridge.detectPlayableMediaKind(pathPart, true) : '') ||
      (fallbackFileName ? RustCoreBridge.detectPlayableMediaKind(fallbackFileName, true) : '') ||
      'video';
    return { url: normalized, headers: headers, mediaKind: kind };
  }

  /** 规范化并校验单条 HTTP(S) 直链地址（拒绝内嵌账号密码，编码未转义空格与中文）。 */
  static normalizeStrmHttpUrl(raw: string): string {
    const trimmed = (raw ?? '').trim().split('|')[0].trim();
    const sep = trimmed.indexOf('://');
    if (sep <= 0) {
      return '';
    }
    const scheme = trimmed.substring(0, sep).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') {
      return '';
    }
    const rest = trimmed.substring(sep + 3);
    let authEnd = rest.length;
    const slashIdx = rest.indexOf('/');
    const qIdx = rest.indexOf('?');
    if (slashIdx >= 0 && slashIdx < authEnd) { authEnd = slashIdx; }
    if (qIdx >= 0 && qIdx < authEnd) { authEnd = qIdx; }
    const authority = rest.substring(0, authEnd);
    if (!authority || authority.includes('@')) {
      return '';
    }
    const pathAndQuery = rest.substring(authEnd).split('#')[0];
    const encoded = encodeURI(pathAndQuery).replace(/\[/g, '%5B').replace(/\]/g, '%5D');
    return `${scheme}://${authority}${encoded}`;
  }

  static parseAgentMarkdownJson(markdown: string): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.parseAgentMarkdownJson(markdown);
      }
    } catch {
      // fallback
    }
    return '[]';
  }

  static filterAndGroupResources(resourcesJson: string, criteriaJson: string = '{}'): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.filterAndGroupResources(resourcesJson, criteriaJson);
      }
    } catch {
      // fallback
    }
    return resourcesJson;
  }

  static planPluginFormJson(documentJson: string): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.planPluginFormJson(documentJson);
      }
    } catch {
      // fallback
    }
    return documentJson;
  }

  static applyPluginFormPatch(originalModelJson: string, patchJson: string): string {
    try {
      if (RustCoreBridge.nativeLib) {
        return RustCoreBridge.nativeLib.applyPluginFormPatch(originalModelJson, patchJson);
      }
    } catch {
      // fallback
    }
    return originalModelJson;
  }

  static analyzeCron(expr: string): CronSummary {
    try {
      if (RustCoreBridge.nativeLib) {
        return JSON.parse(RustCoreBridge.nativeLib.analyzeCronJson(expr)) as CronSummary;
      }
    } catch {
      // fallback
    }
    const parts = expr.trim().split(/\s+/);
    const valid = parts.length === 5;
    return {
      rawValue: expr,
      format: valid ? 'fiveFields' : 'custom',
      fields: valid ? parts : [],
      hasAmbiguousWeekday: valid && /\d/.test(parts[4]),
      descriptionZh: valid ? `五字段 Cron：${expr}` : '自定义调度表达式',
      isValidFiveField: valid,
    };
  }

  static computeMedalPalette(medalId: string): MedalPalette {
    try {
      if (RustCoreBridge.nativeLib) {
        return JSON.parse(RustCoreBridge.nativeLib.computeMedalPaletteJson(medalId)) as MedalPalette;
      }
    } catch {
      // fallback
    }
    return {
      medal_id: medalId,
      base_hex: '#8F7CE6',
      rim_hex: '#CBBFFF',
      engrave_dark_hex: '#362B66',
      engrave_light_hex: '#EFEAFF',
      tier: 'violet',
    };
  }

  static computeSubscribeProgress(total: number, lack: number): SubscribeProgress {
    try {
      if (RustCoreBridge.nativeLib) {
        return JSON.parse(RustCoreBridge.nativeLib.computeSubscribeProgressJson(total, lack)) as SubscribeProgress;
      }
    } catch {
      // fallback
    }
    const safeTotal = Math.max(0, total);
    const safeLack = Math.min(safeTotal, Math.max(0, lack));
    const completed = Math.max(0, safeTotal - safeLack);
    return {
      total: safeTotal,
      completed: completed,
      lack: safeLack,
      ratio: safeTotal > 0 ? completed / safeTotal : 0,
      label: safeTotal > 0 ? `${completed}/${safeTotal}` : '监控中',
    };
  }

  /** 构造空播放进度同步状态快照。 */
  static createInitialPlaybackSyncState(playSessionId: string = ''): PlaybackSyncState {
    return {
      play_session_id: playSessionId,
      started_sent: false,
      stopped_sent: false,
      paused_since_ms: null,
      last_report_at_ms: null,
      last_playing_tick_at_ms: null,
      last_seek_at_ms: null,
      cumulative_playback_time_ms: 0,
      seq: 0,
      last_position_ms: 0,
      last_audio_stream_index: null,
      last_subtitle_stream_index: null
    };
  }

  /** 调用 Rust 播放进度与会话上报状态机（优先走原生 NAPI，异常时回退同构 ArkTS 实现）。 */
  static planPlaybackSyncStep(state: PlaybackSyncState, input: PlaybackSyncInput): PlaybackSyncDecision {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.planPlaybackSyncStepJson) {
        const raw = RustCoreBridge.nativeLib.planPlaybackSyncStepJson(JSON.stringify(state), JSON.stringify(input));
        if (raw && raw.length > 0) {
          return JSON.parse(raw) as PlaybackSyncDecision;
        }
      }
    } catch {
      // fallback
    }
    return RustCoreBridge.fallbackPlanPlaybackSyncStep(state, input);
  }

  /** 整理离线待补报 `stopped` 队列（去重留新、清理 7 天过期、上限 30 条）。 */
  static normalizePendingPlaybackStops(entries: PendingPlaybackStop[], nowEpochMs: number): PendingPlaybackStop[] {
    if (entries.length === 0) {
      return [];
    }
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.normalizePendingPlaybackStopsJson) {
        const raw = RustCoreBridge.nativeLib.normalizePendingPlaybackStopsJson(JSON.stringify(entries), Math.round(nowEpochMs));
        if (raw && raw.length > 0) {
          return JSON.parse(raw) as PendingPlaybackStop[];
        }
      }
    } catch {
      // fallback
    }
    const cutoff = nowEpochMs - 7 * 24 * 60 * 60 * 1000;
    const dedup = new Map<string, PendingPlaybackStop>();
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      const srv = (e.server ?? '').trim();
      const id = (e.item_id ?? '').trim();
      if (!srv || !id || e.updated_at_ms < cutoff) {
        continue;
      }
      const key = `${srv}\u0000${id}`;
      const existing = dedup.get(key);
      if (!existing || e.updated_at_ms >= existing.updated_at_ms) {
        dedup.set(key, {
          server: srv,
          item_id: id,
          media_source_id: e.media_source_id,
          position_ms: Math.max(0, Math.round(e.position_ms)),
          duration_ms: e.duration_ms,
          play_session_id: e.play_session_id,
          playback_time_ms: e.playback_time_ms,
          seq: e.seq,
          updated_at_ms: e.updated_at_ms
        });
      }
    }
    const result: PendingPlaybackStop[] = [];
    dedup.forEach((v: PendingPlaybackStop) => { result.push(v); });
    result.sort((a: PendingPlaybackStop, b: PendingPlaybackStop) => b.updated_at_ms - a.updated_at_ms);
    return result.slice(0, 30);
  }

  private static fallbackPlanPlaybackSyncStep(current: PlaybackSyncState, input: PlaybackSyncInput): PlaybackSyncDecision {
    const now = Math.max(0, Math.round(input.now_ms));
    const next: PlaybackSyncState = {
      play_session_id: current.play_session_id,
      started_sent: current.started_sent,
      stopped_sent: current.stopped_sent,
      paused_since_ms: current.paused_since_ms ?? null,
      last_report_at_ms: current.last_report_at_ms ?? null,
      last_playing_tick_at_ms: current.last_playing_tick_at_ms ?? null,
      last_seek_at_ms: current.last_seek_at_ms ?? null,
      cumulative_playback_time_ms: current.cumulative_playback_time_ms,
      seq: current.seq,
      last_position_ms: current.last_position_ms,
      last_audio_stream_index: current.last_audio_stream_index ?? null,
      last_subtitle_stream_index: current.last_subtitle_stream_index ?? null
    };
    if (!input.is_paused && input.trigger !== 'pause' && input.trigger !== 'background') {
      if (next.last_playing_tick_at_ms !== null && next.last_playing_tick_at_ms !== undefined && now > next.last_playing_tick_at_ms) {
        next.cumulative_playback_time_ms += Math.min(60000, now - next.last_playing_tick_at_ms);
      }
      next.last_playing_tick_at_ms = now;
    } else {
      next.last_playing_tick_at_ms = null;
    }

    let resolvedPos = Math.max(0, Math.round(input.position_ms));
    if (input.trigger === 'finish' && input.duration_ms && input.duration_ms > 0) {
      resolvedPos = Math.round(input.duration_ms);
    } else if (
      input.trigger !== 'seek' &&
      resolvedPos <= 0 &&
      next.last_position_ms > 0 &&
      (input.trigger === 'stop' || input.trigger === 'pause' || input.trigger === 'background')
    ) {
      resolvedPos = next.last_position_ms;
    }
    next.last_position_ms = resolvedPos;
    if (input.audio_stream_index !== undefined && input.audio_stream_index !== null) {
      next.last_audio_stream_index = input.audio_stream_index;
    }
    if (input.subtitle_stream_index !== undefined && input.subtitle_stream_index !== null) {
      next.last_subtitle_stream_index = input.subtitle_stream_index;
    }

    const emit = (stateStr: string, eventName: string | null, paused: boolean): PlaybackSyncDecision => {
      next.seq += 1;
      next.last_report_at_ms = now;
      return {
        should_report: true,
        state: stateStr,
        event_name: eventName,
        is_paused: paused,
        position_ms: resolvedPos,
        playback_time_ms: next.cumulative_playback_time_ms,
        seq: next.seq,
        next_state: next
      };
    };
    const skip = (stateStr: string, paused: boolean): PlaybackSyncDecision => ({
      should_report: false,
      state: stateStr,
      event_name: null,
      is_paused: paused,
      position_ms: resolvedPos,
      playback_time_ms: next.cumulative_playback_time_ms,
      seq: next.seq,
      next_state: next
    });

    if (input.trigger === 'start') {
      if (next.started_sent && !next.stopped_sent) {
        return skip(input.is_paused ? 'paused' : 'playing', input.is_paused);
      }
      next.started_sent = true;
      next.stopped_sent = false;
      next.paused_since_ms = input.is_paused ? now : null;
      return emit('started', null, input.is_paused);
    }
    if (input.trigger === 'pause') {
      if (next.stopped_sent) { return skip('stopped', true); }
      next.started_sent = true;
      if (next.paused_since_ms === null || next.paused_since_ms === undefined) {
        next.paused_since_ms = now;
      }
      return emit('paused', 'pause', true);
    }
    if (input.trigger === 'resume') {
      next.started_sent = true;
      next.paused_since_ms = null;
      next.last_playing_tick_at_ms = now;
      if (next.stopped_sent) {
        next.stopped_sent = false;
        return emit('started', null, false);
      }
      return emit('playing', 'unpause', false);
    }
    if (input.trigger === 'seek') {
      if (next.stopped_sent) { return skip('stopped', true); }
      if (next.last_seek_at_ms !== null && next.last_seek_at_ms !== undefined && now - next.last_seek_at_ms >= 0 && now - next.last_seek_at_ms < 300) {
        return skip(input.is_paused ? 'paused' : 'playing', input.is_paused);
      }
      next.started_sent = true;
      next.last_seek_at_ms = now;
      return emit(input.is_paused ? 'paused' : 'playing', 'timeupdate', input.is_paused);
    }
    if (input.trigger === 'track_change') {
      if (next.stopped_sent) { return skip('stopped', true); }
      next.started_sent = true;
      return emit(input.is_paused ? 'paused' : 'playing', 'trackchange', input.is_paused);
    }
    if (input.trigger === 'background') {
      if (next.stopped_sent) { return skip('stopped', true); }
      next.started_sent = true;
      next.paused_since_ms = input.is_paused ? (next.paused_since_ms ?? now) : null;
      return emit(input.is_paused ? 'paused' : 'playing', input.is_paused ? 'pause' : 'timeupdate', input.is_paused);
    }
    if (input.trigger === 'stop' || input.trigger === 'finish') {
      if (next.stopped_sent) { return skip('stopped', true); }
      next.stopped_sent = true;
      next.paused_since_ms = null;
      next.last_playing_tick_at_ms = null;
      return emit('stopped', null, true);
    }
    // tick
    if (next.stopped_sent) { return skip('stopped', true); }
    if (!next.started_sent) {
      next.started_sent = true;
      next.stopped_sent = false;
      next.paused_since_ms = input.is_paused ? now : null;
      return emit('started', null, input.is_paused);
    }
    if (input.is_paused) {
      if (next.paused_since_ms === null || next.paused_since_ms === undefined) {
        next.paused_since_ms = now;
      }
      if (now - next.paused_since_ms >= 15 * 60 * 1000) {
        next.stopped_sent = true;
        next.paused_since_ms = null;
        next.last_playing_tick_at_ms = null;
        return emit('stopped', null, true);
      }
      const elapsed = next.last_report_at_ms !== null && next.last_report_at_ms !== undefined ? now - next.last_report_at_ms : 999999;
      if (elapsed >= 12000) {
        return emit('paused', 'timeupdate', true);
      }
      return skip('paused', true);
    }
    next.paused_since_ms = null;
    const elapsed = next.last_report_at_ms !== null && next.last_report_at_ms !== undefined ? now - next.last_report_at_ms : 999999;
    if (elapsed >= 10000) {
      return emit('playing', 'timeupdate', false);
    }
    return skip('playing', false);
  }

  /** 根据用户直连偏好与探测结果规划最优主路由及有序降级队列（优先调用 Rust NAPI 内核）。 */
  static planPlaybackRoutes(
    routes: PlaybackRouteCandidate[],
    prefs: PlaybackRoutePreference,
    probes: RouteProbeOutcome[]
  ): PlaybackRoutePlan | null {
    if (routes.length === 0) {
      return null;
    }
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.planPlaybackRoutesJson) {
        const raw = RustCoreBridge.nativeLib.planPlaybackRoutesJson(
          JSON.stringify(routes),
          JSON.stringify(prefs),
          JSON.stringify(probes)
        );
        if (raw && raw.length > 0) {
          return JSON.parse(raw) as PlaybackRoutePlan;
        }
        return null;
      }
    } catch {
      // fallback to ArkTS implementation
    }
    return RustCoreBridge.fallbackPlanPlaybackRoutes(routes, prefs, probes);
  }

  /** 校验两条 HTTP(S) URL 是否严格同源（scheme + 大小写无关 host + 有效端口）。 */
  static isSameHttpOrigin(urlA: string, urlB: string): boolean {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.isSameHttpOrigin) {
        return RustCoreBridge.nativeLib.isSameHttpOrigin(urlA, urlB);
      }
    } catch {
      // fallback
    }
    return RustCoreBridge.fallbackIsSameHttpOrigin(urlA, urlB);
  }

  private static parseOriginParts(raw: string): string[] | null {
    const trimmed = raw.trim();
    const schemeIdx = trimmed.indexOf('://');
    if (schemeIdx <= 0) {
      return null;
    }
    const scheme = trimmed.substring(0, schemeIdx).toLowerCase();
    if (scheme !== 'http' && scheme !== 'https') {
      return null;
    }
    const rest = trimmed.substring(schemeIdx + 3);
    const slashIdx = rest.indexOf('/');
    const queryIdx = rest.indexOf('?');
    let endIdx = rest.length;
    if (slashIdx >= 0 && slashIdx < endIdx) { endIdx = slashIdx; }
    if (queryIdx >= 0 && queryIdx < endIdx) { endIdx = queryIdx; }
    const authority = rest.substring(0, endIdx);
    if (!authority || authority.indexOf('@') >= 0) {
      return null;
    }
    let host = authority;
    let port = scheme === 'https' ? '443' : '80';
    if (authority.startsWith('[')) {
      const closeBracket = authority.indexOf(']');
      if (closeBracket < 0) { return null; }
      host = authority.substring(0, closeBracket + 1).toLowerCase();
      if (closeBracket + 1 < authority.length && authority.charAt(closeBracket + 1) === ':') {
        port = authority.substring(closeBracket + 2);
      }
    } else {
      const colonIdx = authority.lastIndexOf(':');
      if (colonIdx > 0) {
        host = authority.substring(0, colonIdx).toLowerCase();
        port = authority.substring(colonIdx + 1);
      } else {
        host = authority.toLowerCase();
      }
    }
    if (!host) { return null; }
    return [scheme, host, port];
  }

  private static fallbackIsSameHttpOrigin(urlA: string, urlB: string): boolean {
    const a = RustCoreBridge.parseOriginParts(urlA);
    const b = RustCoreBridge.parseOriginParts(urlB);
    if (!a || !b) {
      return false;
    }
    return a[0] === b[0] && a[1] === b[1] && a[2] === b[2];
  }

  private static fallbackPlanPlaybackRoutes(
    routes: PlaybackRouteCandidate[],
    prefs: PlaybackRoutePreference,
    probes: RouteProbeOutcome[]
  ): PlaybackRoutePlan | null {
    const strm: PlaybackRouteCandidate[] = [];
    const lan: Array<[number, PlaybackRouteCandidate]> = [];
    const wan: Array<[number, PlaybackRouteCandidate]> = [];
    const proxy: PlaybackRouteCandidate[] = [];
    const seen: Set<string> = new Set<string>();

    const lookupLatency = (route: PlaybackRouteCandidate): number | null => {
      const probeKey = (route.probe_url ?? '').trim();
      for (let i = 0; i < probes.length; i++) {
        const p = probes[i];
        const t = p.url.trim();
        if ((probeKey.length > 0 && t === probeKey) || t === route.url) {
          if (!p.reachable) {
            return null;
          }
          return p.latency_ms !== undefined && p.latency_ms !== null ? p.latency_ms : 999999;
        }
      }
      return null;
    };

    for (let i = 0; i < routes.length; i++) {
      const r = routes[i];
      const trimmedUrl = (r.url ?? '').trim();
      if (!RustCoreBridge.parseOriginParts(trimmedUrl)) {
        continue;
      }
      const key = `${r.kind}|${trimmedUrl}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const norm: PlaybackRouteCandidate = {
        kind: r.kind,
        url: trimmedUrl,
        probe_url: r.probe_url ? r.probe_url.trim() : null,
        headers: r.headers,
        priority: r.priority,
        requires_same_origin_auth: r.requires_same_origin_auth
      };
      if (norm.kind === 'strm_direct') {
        if (prefs.prefer_strm_direct) { strm.push(norm); }
      } else if (norm.kind === 'server_lan') {
        if (prefs.prefer_server_direct) {
          const ms = lookupLatency(norm);
          if (ms !== null) { lan.push([ms, norm]); }
        }
      } else if (norm.kind === 'server_wan') {
        if (prefs.prefer_server_direct) {
          const ms = lookupLatency(norm);
          if (ms !== null) { wan.push([ms, norm]); }
        }
      } else if (norm.kind === 'mp_proxy') {
        proxy.push(norm);
      }
    }

    strm.sort((a: PlaybackRouteCandidate, b: PlaybackRouteCandidate) => a.priority - b.priority);
    lan.sort((a: [number, PlaybackRouteCandidate], b: [number, PlaybackRouteCandidate]) =>
      a[0] !== b[0] ? a[0] - b[0] : a[1].priority - b[1].priority
    );
    wan.sort((a: [number, PlaybackRouteCandidate], b: [number, PlaybackRouteCandidate]) =>
      a[0] !== b[0] ? a[0] - b[0] : a[1].priority - b[1].priority
    );
    proxy.sort((a: PlaybackRouteCandidate, b: PlaybackRouteCandidate) => a.priority - b.priority);

    const ordered: PlaybackRouteCandidate[] = [];
    for (let i = 0; i < strm.length; i++) { ordered.push(strm[i]); }
    const preferWan = lan.length > 0 && wan.length > 0 &&
      lan[0][0] > prefs.lan_preferred_max_latency_ms && wan[0][0] < lan[0][0];
    if (preferWan) {
      for (let i = 0; i < wan.length; i++) { ordered.push(wan[i][1]); }
      for (let i = 0; i < lan.length; i++) { ordered.push(lan[i][1]); }
    } else {
      for (let i = 0; i < lan.length; i++) { ordered.push(lan[i][1]); }
      for (let i = 0; i < wan.length; i++) { ordered.push(wan[i][1]); }
    }
    for (let i = 0; i < proxy.length; i++) { ordered.push(proxy[i]); }

    if (ordered.length === 0) {
      return null;
    }
    const active = ordered[0];
    const fallbacks = ordered.slice(1);
    let label = '后台中转';
    if (active.kind === 'strm_direct') { label = 'STRM 直链'; }
    else if (active.kind === 'server_lan') { label = '局域网直连'; }
    else if (active.kind === 'server_wan') { label = '外网直连'; }
    return {
      active: active,
      fallbacks: fallbacks,
      route_label_zh: label
    };
  }

  /** 调用 Rust 共享选核路由决定鸿蒙端主播放内核及起播失败回退内核。 */
  static resolvePlaybackEngine(input: EngineResolutionInput): EngineResolutionPlan {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.resolvePlaybackEngineJson) {
        const raw = RustCoreBridge.nativeLib.resolvePlaybackEngineJson(JSON.stringify(input));
        if (raw && raw.length > 0) {
          const parsed = JSON.parse(raw) as EngineResolutionPlan;
          if (parsed && typeof parsed.primary === 'string' && parsed.primary.length > 0) {
            return parsed;
          }
        }
      }
    } catch {
      // fallback
    }
    return RustCoreBridge.fallbackResolvePlaybackEngine(input);
  }

  /** 安全渲染外部播放器 URL 模板，拒绝危险协议与控制字符。 */
  static buildExternalPlayerUrl(template: string, mediaUrl: string, title: string = ''): string {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.buildExternalPlayerUrl) {
        const built = RustCoreBridge.nativeLib.buildExternalPlayerUrl(template, mediaUrl, title);
        if (built && built.length > 0) {
          return built;
        }
      }
    } catch {
      // fallback
    }
    const tmpl = (template ?? '').trim();
    const media = (mediaUrl ?? '').trim();
    if (!tmpl || !media || (!tmpl.includes('{url}') && !tmpl.includes('{raw_url}'))) {
      return '';
    }
    const sep = tmpl.indexOf('://');
    if (sep <= 0) {
      return '';
    }
    const scheme = tmpl.substring(0, sep).toLowerCase();
    if (scheme === 'javascript' || scheme === 'data' || scheme === 'file' || scheme === 'vbscript' || scheme === 'blob' || scheme === 'about') {
      return '';
    }
    return tmpl
      .replace(/\{url\}/g, encodeURIComponent(media))
      .replace(/\{raw_url\}/g, media)
      .replace(/\{title\}/g, encodeURIComponent((title ?? '').trim()));
  }

  /** 校验并规范化插件 Bridge `/api/v1/...` 路径，拒绝外部主机与路径穿越。 */
  static validatePluginApiPath(rawPath: string): string {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.validatePluginBridgeApiPath) {
        return RustCoreBridge.nativeLib.validatePluginBridgeApiPath(rawPath);
      }
    } catch {
      return '';
    }
    const trimmed = (rawPath ?? '').trim();
    if (!trimmed || trimmed.includes('\\') || /[\x00-\x1f\x7f]/.test(trimmed)) {
      return '';
    }
    const lower = trimmed.toLowerCase();
    if (lower.includes('://') || lower.startsWith('//') || lower.startsWith('javascript:') || lower.startsWith('data:') || lower.startsWith('file:')) {
      return '';
    }
    const noFrag = trimmed.split('#')[0];
    const qIdx = noFrag.indexOf('?');
    const pathPart = qIdx >= 0 ? noFrag.substring(0, qIdx) : noFrag;
    const queryPart = qIdx >= 0 ? noFrag.substring(qIdx + 1) : '';
    const stripped = pathPart.replace(/^\/+/, '');
    const rel = stripped.startsWith('api/v1/') ? stripped.substring(7) : (stripped === 'api/v1' ? '' : stripped);
    const segs = RustCoreBridge.validateSafePluginSegments(rel);
    if (!segs) {
      return '';
    }
    const norm = `/api/v1/${segs.join('/')}`;
    return queryPart.length > 0 ? `${norm}?${queryPart}` : norm;
  }

  /** 校验本地运行时壳 `/shell/...` 资产路径并返回安全包内相对路径。 */
  static validatePluginShellAssetPath(virtualPath: string): string {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.validatePluginShellAsset) {
        return RustCoreBridge.nativeLib.validatePluginShellAsset(virtualPath);
      }
    } catch {
      return '';
    }
    const clean = (virtualPath ?? '').trim().split('#')[0].split('?')[0].replace(/^\/+/, '');
    const rel = clean.startsWith('shell/') ? clean.substring(6) : clean;
    const segs = RustCoreBridge.validateSafePluginSegments(rel);
    return segs ? segs.join('/') : '';
  }

  /** 生成按实例源 SHA-256、插件 ID 与版本/产物哈希隔离的磁盘缓存键。 */
  static buildPluginRemoteCacheKey(
    instanceOrigin: string,
    pluginId: string,
    versionOrHash: string
  ): PluginRemoteCacheKey {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.buildPluginRemoteCacheKeyJson) {
        const raw = RustCoreBridge.nativeLib.buildPluginRemoteCacheKeyJson(instanceOrigin, pluginId, versionOrHash);
        if (raw && raw.length > 0) {
          return JSON.parse(raw) as PluginRemoteCacheKey;
        }
      }
    } catch {
      // fallback
    }
    let hashVal = 2166136261;
    const norm = (instanceOrigin ?? '').trim().replace(/\/+$/, '').toLowerCase();
    for (let i = 0; i < norm.length; i++) {
      hashVal ^= norm.charCodeAt(i);
      hashVal = Math.imul(hashVal, 16777619) >>> 0;
    }
    const instHash = hashVal.toString(16).padStart(8, '0');
    const pid = RustCoreBridge.sanitizePluginSegment((pluginId ?? '').toLowerCase(), 'plugin');
    const ver = RustCoreBridge.sanitizePluginSegment(versionOrHash ?? '', 'default');
    return {
      instance_hash: instHash,
      plugin_id_lower: pid,
      version_segment: ver,
      relative_dir: `${instHash}/${pid}/${ver}`
    };
  }

  /** 规划联邦插件虚拟源入口与上游路径。 */
  static normalizePluginRemoteEntry(
    pluginId: string,
    versionOrHash: string,
    rawRemoteUrl: string
  ): PluginRemoteEntryPlan | null {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.normalizePluginRemoteEntryJson) {
        const raw = RustCoreBridge.nativeLib.normalizePluginRemoteEntryJson(pluginId, versionOrHash, rawRemoteUrl);
        if (raw && raw.length > 0) {
          return JSON.parse(raw) as PluginRemoteEntryPlan;
        }
      }
    } catch {
      return null;
    }
    const trimmed = (rawRemoteUrl ?? '').trim();
    if (!trimmed || trimmed.includes('\\')) {
      return null;
    }
    const noFrag = trimmed.split('#')[0];
    const qIdx = noFrag.indexOf('?');
    const pathOrUrl = qIdx >= 0 ? noFrag.substring(0, qIdx) : noFrag;
    const query = qIdx >= 0 ? noFrag.substring(qIdx + 1) : '';
    let pathOnly = pathOrUrl;
    const schemePos = pathOrUrl.indexOf('://');
    if (schemePos >= 0) {
      const slash = pathOrUrl.indexOf('/', schemePos + 3);
      if (slash < 0) {
        return null;
      }
      pathOnly = pathOrUrl.substring(slash);
    }
    const marker = 'plugin/file/';
    const mIdx = pathOnly.toLowerCase().indexOf(marker);
    if (mIdx < 0) {
      return null;
    }
    const segs = RustCoreBridge.validateSafePluginSegments(pathOnly.substring(mIdx + marker.length));
    if (!segs || segs.length < 2) {
      return null;
    }
    const filePid = segs[0];
    const rel = segs.slice(1).join('/');
    let qVer = '';
    const pairs = query.split('&');
    for (let i = 0; i < pairs.length; i++) {
      if (pairs[i].startsWith('v=')) {
        qVer = pairs[i].substring(2).trim();
        break;
      }
    }
    const verTag = RustCoreBridge.sanitizePluginSegment((versionOrHash ?? '').trim() || qVer || 'default', 'default');
    return {
      plugin_id: filePid,
      version_tag: verTag,
      virtual_entry_path: `/plugin-remote/${filePid}/${verTag}/${rel}`,
      upstream_file_path: `/api/v1/plugin/file/${filePid}/${rel}`
    };
  }

  /** 将虚拟源 `/plugin-remote/...` 还原为上游 API 路径与缓存相对路径。 */
  static resolvePluginRemoteUpstream(virtualPath: string): PluginRemoteUpstreamTarget | null {
    try {
      if (RustCoreBridge.nativeLib && RustCoreBridge.nativeLib.resolvePluginRemoteUpstreamJson) {
        const raw = RustCoreBridge.nativeLib.resolvePluginRemoteUpstreamJson(virtualPath);
        if (raw && raw.length > 0) {
          return JSON.parse(raw) as PluginRemoteUpstreamTarget;
        }
      }
    } catch {
      return null;
    }
    const stripped = (virtualPath ?? '').trim().split('#')[0].split('?')[0].replace(/^\/+/, '');
    if (!stripped.startsWith('plugin-remote/')) {
      return null;
    }
    const segs = RustCoreBridge.validateSafePluginSegments(stripped.substring('plugin-remote/'.length));
    if (!segs || segs.length < 3) {
      return null;
    }
    const pid = segs[0];
    const ver = RustCoreBridge.sanitizePluginSegment(segs[1], 'default');
    const rel = segs.slice(2).join('/');
    return {
      plugin_id: pid,
      version_tag: ver,
      asset_rel_path: rel,
      upstream_api_path: `/api/v1/plugin/file/${pid}/${rel}`
    };
  }

  private static sanitizePluginSegment(raw: string, fallback: string): string {
    const cleaned = (raw ?? '').trim().replace(/[^A-Za-z0-9._-]/g, '_').replace(/^[._]+|[._]+$/g, '').substring(0, 64);
    if (!cleaned || cleaned === '.' || cleaned === '..' || cleaned.includes('..')) {
      return fallback;
    }
    return cleaned;
  }

  private static validateSafePluginSegments(raw: string): string[] | null {
    const trimmed = (raw ?? '').replace(/^\/+|\/+$/g, '');
    if (!trimmed) {
      return null;
    }
    const parts = trimmed.split('/');
    for (let i = 0; i < parts.length; i++) {
      const seg = parts[i];
      if (!seg || seg === '.' || seg === '..') {
        return null;
      }
      let decoded = seg.toLowerCase();
      try {
        decoded = decodeURIComponent(seg).toLowerCase();
      } catch {
        // keep raw
      }
      if (decoded === '.' || decoded === '..' || decoded.includes('..') || decoded.includes('/') || decoded.includes('\\')) {
        return null;
      }
    }
    return parts;
  }

  private static fallbackResolvePlaybackEngine(input: EngineResolutionInput): EngineResolutionPlan {
    const pref = (input.preferred ?? 'auto').toLowerCase();
    const hasEnh = Boolean(input.has_enhanced_engine);
    if (pref === 'native') {
      return { primary: 'native', fallback: null, reason: 'user_pinned_native' };
    }
    if (pref === 'enhanced') {
      return hasEnh
        ? { primary: 'enhanced', fallback: 'native', reason: 'user_pinned_enhanced' }
        : { primary: 'native', fallback: null, reason: 'enhanced_unavailable_fallback_native' };
    }
    const rawPath = (input.url_or_filename ?? '').trim().split('#')[0].split('?')[0].toLowerCase();
    const slashIdx = rawPath.lastIndexOf('/');
    const fileName = slashIdx >= 0 ? rawPath.substring(slashIdx + 1) : rawPath;
    const dotIdx = fileName.lastIndexOf('.');
    const ext = dotIdx > 0 ? fileName.substring(dotIdx + 1) : '';
    const container = (input.container ?? '').trim().toLowerCase().replace(/^\.+/, '') || ext;
    const audioCodec = (input.audio_codec ?? '').trim().toLowerCase();

    if (input.is_audio) {
      const exoticAudio = container === 'ape' || container === 'wv' || container === 'dsf' ||
        container === 'dff' || container === 'wma' || container === 'opus' || container === 'ogg' ||
        audioCodec === 'ape' || audioCodec === 'wavpack' || audioCodec === 'dsd' || audioCodec === 'wma';
      if (exoticAudio && hasEnh) {
        return { primary: 'enhanced', fallback: 'native', reason: 'auto_audio_exotic_enhanced' };
      }
      return { primary: 'native', fallback: hasEnh ? 'enhanced' : null, reason: 'auto_audio_native' };
    }
    if (input.decode_force_software && hasEnh) {
      return { primary: 'enhanced', fallback: 'native', reason: 'auto_force_software_enhanced' };
    }
    if (input.has_ass_or_pgs_subtitle && !input.ignore_ass_style && hasEnh) {
      return { primary: 'enhanced', fallback: 'native', reason: 'auto_ass_or_pgs_enhanced' };
    }
    const preferEnh = container === 'mkv' || container === 'avi' || container === 'rmvb' ||
      container === 'rm' || container === 'wmv' || container === 'ts' || container === 'm2ts' ||
      container === 'mts' || container === 'flv' || container === 'webm' || container === 'vob' ||
      container === 'iso' || audioCodec === 'dts' || audioCodec === 'dca' || audioCodec === 'truehd' ||
      audioCodec === 'mlp' || audioCodec === 'ac3' || audioCodec === 'eac3';
    if (preferEnh && hasEnh) {
      return { primary: 'enhanced', fallback: 'native', reason: 'auto_container_or_audio_enhanced' };
    }
    return { primary: 'native', fallback: hasEnh ? 'enhanced' : null, reason: 'auto_native_default' };
  }
}
