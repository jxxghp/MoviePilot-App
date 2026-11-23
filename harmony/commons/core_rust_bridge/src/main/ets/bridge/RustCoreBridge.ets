import nativeCore from 'libmoviepilot_core_ohos.so';

/**
 * 鸿蒙端 Rust 共享内核桥接门面（直接消费 ohos-rs 编译的 `libmoviepilot_core_ohos.so`）：
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
    return '2.0.2';
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

  /** 构造 `/api/v1/...` 完整请求 URL（单次 UTF-8 编码，正确支持中文路径段如 `电视剧`）。 */
  static buildV3EndpointUrl(
    baseUrl: string,
    segments: string[],
    query: Record<string, string> = {},
    trailingSlash: boolean = false
  ): string {
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
    const parts = pathOrExt.toLowerCase().split('.');
    const ext = parts.length > 1 ? parts[parts.length - 1] : '';
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
