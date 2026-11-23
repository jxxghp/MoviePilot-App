/**
 * 鸿蒙端 Rust 共享内核桥接门面（消费 ohos-rs 生成的 `libmoviepilot_core_ohos.so`）：
 * 提供 DeepLink 解析、9 维站点资源筛选分组、Agent Markdown AST、JWT/权限计算、
 * 动态插件表单规划与无损补丁、5 字段 Cron 分析与 3D 勋章金属色板。
 */

export interface NativeCoreModule {
  coreVersion(): string;
  normalizeServerAddress(raw: string): string;
  parseDeepLinkJson(rawUrl: string): string;
  detectPlayableMediaKind(pathOrExt: string, includeStreaming: boolean): string;
  parseAgentMarkdownJson(markdown: string): string;
  filterAndGroupResources(resourcesJson: string, criteriaJson: string): string;
  decodeJwtClaimsJson(token: string, nowEpochSecs: number): string;
  evaluatePermissionsJson(permissionsJson: string, isSuperuser: boolean): string;
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

/** 鸿蒙 Rust 共享业务内核统一入口。 */
export class RustCoreBridge {
  private static nativeLib: NativeCoreModule | null = null;

  /** 绑定 ohos-rs 编译产出的原生 NAPI 模块实例。 */
  static bindNativeModule(mod: NativeCoreModule): void {
    RustCoreBridge.nativeLib = mod;
  }

  /** 返回 Rust 共享内核版本。 */
  static version(): string {
    return RustCoreBridge.nativeLib ? RustCoreBridge.nativeLib.coreVersion() : '2.0.2';
  }

  /** 规范化 MoviePilot 实例地址（拒绝内嵌凭据并保留反代子路径）。 */
  static normalizeServerAddress(raw: string): string {
    if (RustCoreBridge.nativeLib) {
      return RustCoreBridge.nativeLib.normalizeServerAddress(raw);
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

  /** 构造 `/api/v1/...` 完整请求 URL。 */
  static buildV3EndpointUrl(
    baseUrl: string,
    segments: string[],
    query: Record<string, string> = {},
    trailingSlash: boolean = false
  ): string {
    const cleanBase = RustCoreBridge.normalizeServerAddress(baseUrl);
    const path = segments.map((s) => encodeURIComponent(s)).join('/');
    let url = `${cleanBase}/api/v1/${path}${trailingSlash ? '/' : ''}`;
    const pairs = Object.keys(query).map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`);
    if (pairs.length > 0) {
      url += `?${pairs.join('&')}`;
    }
    return url;
  }

  /** 解析 `moviepilot://` 或 Web 深度链接。 */
  static parseDeepLinkJson(rawUrl: string): string {
    if (RustCoreBridge.nativeLib) {
      return RustCoreBridge.nativeLib.parseDeepLinkJson(rawUrl);
    }
    const lower = rawUrl.trim().toLowerCase();
    if (lower.includes('subscribe')) { return JSON.stringify({ kind: 'subscriptions' }); }
    if (lower.includes('resource')) { return JSON.stringify({ kind: 'resources' }); }
    if (lower.includes('workflow')) { return JSON.stringify({ kind: 'workflows' }); }
    if (lower.includes('site')) { return JSON.stringify({ kind: 'sites' }); }
    if (lower.includes('plugin')) { return JSON.stringify({ kind: 'plugins', installed_only: true }); }
    if (lower.includes('agent')) { return JSON.stringify({ kind: 'agent' }); }
    if (lower.includes('explore')) { return JSON.stringify({ kind: 'explore' }); }
    if (lower.includes('dashboard')) { return JSON.stringify({ kind: 'dashboard' }); }
    if (lower.includes('setting')) { return JSON.stringify({ kind: 'settings' }); }
    return JSON.stringify({ kind: 'discover' });
  }

  /** 判别音视频扩展名是否支持原生播放器直放。 */
  static detectPlayableMediaKind(pathOrExt: string, includeStreaming: boolean = false): string {
    if (RustCoreBridge.nativeLib) {
      return RustCoreBridge.nativeLib.detectPlayableMediaKind(pathOrExt, includeStreaming);
    }
    const ext = pathOrExt.toLowerCase().split('.').pop() ?? '';
    if (['mp3', 'flac', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'alac', 'ape'].includes(ext)) {
      return 'audio';
    }
    if (['mp4', 'mkv', 'mov', 'avi', 'ts', 'm2ts', 'webm', 'flv', 'wmv'].includes(ext)) {
      return 'video';
    }
    if (includeStreaming && ['m3u8', 'mpd'].includes(ext)) {
      return 'video';
    }
    return '';
  }

  /** 调用 Rust 9 维级联筛选与同规格分组引擎。 */
  static filterAndGroupResources(resourcesJson: string, criteriaJson: string = '{}'): string {
    if (RustCoreBridge.nativeLib) {
      return RustCoreBridge.nativeLib.filterAndGroupResources(resourcesJson, criteriaJson);
    }
    return resourcesJson;
  }

  /** 解析动态插件 `get_form` 规划树。 */
  static planPluginFormJson(documentJson: string): string {
    if (RustCoreBridge.nativeLib) {
      return RustCoreBridge.nativeLib.planPluginFormJson(documentJson);
    }
    return documentJson;
  }

  /** 无损补丁合并插件表单模型。 */
  static applyPluginFormPatch(originalModelJson: string, patchJson: string): string {
    if (RustCoreBridge.nativeLib) {
      return RustCoreBridge.nativeLib.applyPluginFormPatch(originalModelJson, patchJson);
    }
    return originalModelJson;
  }

  /** 解析 5 字段 Cron 表达式并返回可读中文摘要。 */
  static analyzeCron(expr: string): CronSummary {
    if (RustCoreBridge.nativeLib) {
      return JSON.parse(RustCoreBridge.nativeLib.analyzeCronJson(expr)) as CronSummary;
    }
    const parts = expr.trim().split(/\s+/);
    const valid = parts.length === 5;
    return {
      rawValue: expr,
      format: valid ? 'fiveFields' : 'custom',
      fields: valid ? parts : [],
      hasAmbiguousWeekday: valid && /\d/.test(parts[4]),
      descriptionZh: expr.trim() === '*/15 * * * *' ? '每 15 分钟执行一次' : (valid ? `五字段 Cron：${expr}` : '自定义调度表达式'),
      isValidFiveField: valid,
    };
  }

  /** 计算社区 3D 勋章金属基色与凹雕配色。 */
  static computeMedalPalette(medalId: string): MedalPalette {
    if (RustCoreBridge.nativeLib) {
      return JSON.parse(RustCoreBridge.nativeLib.computeMedalPaletteJson(medalId)) as MedalPalette;
    }
    const lower = medalId.toLowerCase();
    if (lower.includes('gold') || lower.includes('legend')) {
      return {
        medal_id: medalId, base_hex: '#D4AF37', rim_hex: '#F6E27F',
        engrave_dark_hex: '#5C470D', engrave_light_hex: '#FFF4C2', tier: 'gold'
      };
    }
    return {
      medal_id: medalId, base_hex: '#8F7CE6', rim_hex: '#CBBFFF',
      engrave_dark_hex: '#362B66', engrave_light_hex: '#EFEAFF', tier: 'violet'
    };
  }

  /** 计算剧集订阅完成进度。 */
  static computeSubscribeProgress(total: number, lack: number): SubscribeProgress {
    if (RustCoreBridge.nativeLib) {
      return JSON.parse(RustCoreBridge.nativeLib.computeSubscribeProgressJson(total, lack)) as SubscribeProgress;
    }
    const safeTotal = Math.max(0, total);
    const safeLack = Math.min(safeTotal, Math.max(0, lack));
    const completed = Math.max(0, safeTotal - safeLack);
    return {
      total: safeTotal,
      completed,
      lack: safeLack,
      ratio: safeTotal > 0 ? completed / safeTotal : 0,
      label: safeTotal > 0 ? `${completed}/${safeTotal}` : '监控中',
    };
  }
}
