import { connection, http } from '@kit.NetworkKit';
import {
  PlaybackRouteCandidate,
  PlaybackRoutePlan,
  PlaybackRoutePreference,
  RouteProbeOutcome,
  RustCoreBridge
} from '../bridge/RustCoreBridge';

interface CachedProbeEntry {
  outcome: RouteProbeOutcome;
  expiresAtMs: number;
}

/**
 * HarmonyOS NEXT 媒体服务器直连并发探测与网络指纹缓存中心：
 * - 通过 `@kit.NetworkKit` `connection.createNetConnection()` 监听网络变化，自动递增 `networkEpoch` 失效旧探测缓存；
 * - 使用 700ms 短超时并发探测 `server_lan` / `server_wan` 轻量端点，按 `(server, networkEpoch)` 缓存 5 分钟；
 * - 对起播失败的直连路由写入 60 秒短时负缓存，避免切集反复踩坑。
 */
export class HarmonyPlaybackRouteResolver {
  private static instance: HarmonyPlaybackRouteResolver | null = null;
  private static readonly PROBE_TTL_MS: number = 5 * 60 * 1000;
  private static readonly NEGATIVE_TTL_MS: number = 60 * 1000;

  private networkEpoch: number = 0;
  private probeCache: Map<string, CachedProbeEntry> = new Map<string, CachedProbeEntry>();
  private failedUntil: Map<string, number> = new Map<string, number>();
  private netConn: connection.NetConnection | null = null;

  static shared(): HarmonyPlaybackRouteResolver {
    if (!HarmonyPlaybackRouteResolver.instance) {
      HarmonyPlaybackRouteResolver.instance = new HarmonyPlaybackRouteResolver();
    }
    return HarmonyPlaybackRouteResolver.instance;
  }

  private constructor() {
    this.startNetworkMonitoring();
  }

  private startNetworkMonitoring(): void {
    try {
      const conn = connection.createNetConnection();
      this.netConn = conn;
      conn.on('netAvailable', () => {
        this.invalidateForNetworkChange();
      });
      conn.on('netLost', () => {
        this.invalidateForNetworkChange();
      });
      conn.on('netCapabilitiesChange', () => {
        this.invalidateForNetworkChange();
      });
      conn.register(() => {});
    } catch {
      // 预览或无网络管理权限环境下保持基础探测可用
    }
  }

  private invalidateForNetworkChange(): void {
    this.networkEpoch += 1;
    this.probeCache.clear();
    this.failedUntil.clear();
  }

  /** 将起播失败的直连路由记入 60 秒短时负缓存。 */
  markRouteFailed(server: string, url: string): void {
    const key = this.failureKey(server, url);
    this.failedUntil.set(key, Date.now() + HarmonyPlaybackRouteResolver.NEGATIVE_TTL_MS);
  }

  /** 并发探测直连候选并通过共享 Rust 路由规划器输出主播放路由与有序降级队列。 */
  async resolve(
    server: string,
    routes: PlaybackRouteCandidate[],
    preferStrmDirect: boolean,
    preferServerDirect: boolean
  ): Promise<PlaybackRoutePlan | null> {
    const prefs: PlaybackRoutePreference = {
      prefer_strm_direct: preferStrmDirect,
      prefer_server_direct: preferServerDirect,
      lan_preferred_max_latency_ms: 350
    };
    const now = Date.now();
    const probes: RouteProbeOutcome[] = [];
    const toProbe: string[] = [];

    if (preferServerDirect) {
      for (let i = 0; i < routes.length; i++) {
        const route = routes[i];
        if (route.kind !== 'server_lan' && route.kind !== 'server_wan') {
          continue;
        }
        const failExp = this.failedUntil.get(this.failureKey(server, route.url)) ?? 0;
        const probeUrl = (route.probe_url ?? '').trim();
        if (failExp > now) {
          probes.push({
            url: probeUrl.length > 0 ? probeUrl : route.url,
            reachable: false,
            latency_ms: null
          });
          continue;
        }
        if (probeUrl.length === 0) {
          continue;
        }
        const cached = this.probeCache.get(this.cacheKey(server, probeUrl));
        if (cached && cached.expiresAtMs > now) {
          probes.push(cached.outcome);
        } else if (toProbe.indexOf(probeUrl) < 0) {
          toProbe.push(probeUrl);
        }
      }
    }

    if (toProbe.length > 0) {
      const epochBefore = this.networkEpoch;
      const tasks: Array<Promise<RouteProbeOutcome>> = [];
      for (let i = 0; i < toProbe.length; i++) {
        tasks.push(this.probeSingle(toProbe[i]));
      }
      const fresh = await Promise.all(tasks);
      if (epochBefore === this.networkEpoch) {
        const expiresAt = Date.now() + HarmonyPlaybackRouteResolver.PROBE_TTL_MS;
        for (let i = 0; i < fresh.length; i++) {
          this.probeCache.set(this.cacheKey(server, fresh[i].url), {
            outcome: fresh[i],
            expiresAtMs: expiresAt
          });
        }
      }
      for (let i = 0; i < fresh.length; i++) {
        probes.push(fresh[i]);
      }
    }

    return RustCoreBridge.planPlaybackRoutes(routes, prefs, probes);
  }

  private async probeSingle(url: string): Promise<RouteProbeOutcome> {
    const req = http.createHttp();
    const startedAt = Date.now();
    try {
      const res = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 700,
        readTimeout: 700,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      });
      const ok = res.responseCode >= 200 && res.responseCode < 500 && res.responseCode !== 404;
      const elapsedMs = Math.max(1, Date.now() - startedAt);
      return {
        url: url,
        reachable: ok,
        latency_ms: ok ? elapsedMs : null
      };
    } catch {
      return {
        url: url,
        reachable: false,
        latency_ms: null
      };
    } finally {
      try {
        req.destroy();
      } catch {
        // ignore
      }
    }
  }

  private cacheKey(server: string, probeUrl: string): string {
    return `${server}|${this.networkEpoch}|${probeUrl}`;
  }

  private failureKey(server: string, url: string): string {
    return `${server}|${this.networkEpoch}|${url}`;
  }
}
