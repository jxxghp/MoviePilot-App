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
}
