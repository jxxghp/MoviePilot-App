import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import {
  MoviePilotRepository,
  NativeHuksStore,
  MpDashboardStats,
  MpDownloadTask,
  MpTransferHistoryItem,
  MpSubscribeItem,
  formatByteSize,
  formatSpeed
} from '@moviepilot/core_rust_bridge';

interface ActiveFormBinding {
  formId: string;
  formName: string;
  dimension: string;
  content: string;
  showMediaNames: boolean;
  pluginIndex: number;
  pluginKey: string;
}

const SECURE_PREF_NAME: string = 'mp_harmony_secure_store';
const KEY_ACTIVE_BINDINGS: string = 'mp_active_form_bindings_v1';
const KEY_MAIN_SNAPSHOT: string = 'mp_widget_snapshot_v1';
const KEY_NOW_PLAYING: string = 'mp_now_playing_widget_v1';
const KEY_PLUGIN_SNAPSHOTS: string = 'mp_plugin_widgets_snapshots_v1';
const KEY_PLUGIN_RUNTIME_MAP: string = 'mp_plugin_runtime_widgets_v1';

function asRec(val: Object | null | undefined): Record<string, Object> | null {
  if (val !== null && val !== undefined && typeof val === 'object' && !Array.isArray(val)) {
    return val as Record<string, Object>;
  }
  return null;
}

function strVal(obj: Record<string, Object> | null, key: string, fallback: string = ''): string {
  if (!obj || obj[key] === undefined || obj[key] === null) {
    return fallback;
  }
  const s = String(obj[key]);
  return s === 'null' ? fallback : s;
}

function numVal(obj: Record<string, Object> | null, key: string, fallback: number = 0): number {
  if (!obj || obj[key] === undefined || obj[key] === null) {
    return fallback;
  }
  const n = Number(obj[key]);
  return Number.isFinite(n) ? n : fallback;
}

function boolVal(obj: Record<string, Object> | null, key: string, fallback: boolean = false): boolean {
  if (!obj || obj[key] === undefined || obj[key] === null) {
    return fallback;
  }
  if (typeof obj[key] === 'boolean') {
    return obj[key] as boolean;
  }
  return String(obj[key]).toLowerCase() === 'true';
}

function parseJson(raw: string): Object | null {
  try {
    if (!raw || raw.trim().length === 0) { return null; }
    return JSON.parse(raw) as Object;
  } catch {
    return null;
  }
}

function unwrapArray(parsed: Object | null): Object[] {
  if (!parsed) { return []; }
  if (Array.isArray(parsed)) { return parsed as Object[]; }
  const rec = asRec(parsed);
  if (!rec) { return []; }
  if (Array.isArray(rec['data'])) { return rec['data'] as Object[]; }
  return [];
}

function unwrapObject(parsed: Object | null): Record<string, Object> | null {
  const rec = asRec(parsed);
  if (!rec) { return null; }
  const inner = asRec(rec['data']);
  return inner ?? rec;
}

function currentHhMm(): string {
  const now = new Date();
  const hh = `${now.getHours()}`.padStart(2, '0');
  const mm = `${now.getMinutes()}`.padStart(2, '0');
  return `${hh}:${mm}`;
}

function makeMainMetric(id: string, title: string, value: string, tone: string = 'default'): Record<string, Object> {
  const m: Record<string, Object> = {};
  m['id'] = id;
  m['title'] = title;
  m['value'] = value;
  m['tone'] = tone;
  return m;
}

function makePluginMetric(id: string, label: string, value: string, tone: string = 'default'): Record<string, Object> {
  const m: Record<string, Object> = {};
  m['id'] = id;
  m['label'] = label;
  m['value'] = value;
  m['tone'] = tone;
  return m;
}

/**
 * 鸿蒙主应用侧桌面服务卡片全量同步服务：
 * - 在主应用启动、回到前台或收到播控指令时，静默拉取主体 4 类快照（`overview`/`downloads`/`imports`/`subscriptions`）
 *   与已启用插件小组件快照（融合运行态缓存与 `/api/v1/plugin/widgets/...` + 旧版仪表盘回退）；
 * - 写入 `mp_harmony_secure_store` 并通过 `formProvider.updateForm` 即时刷新全部已放置桌面卡片。
 */
export class HarmonyWidgetSyncService {
  private static instance: HarmonyWidgetSyncService | null = null;
  private syncing: boolean = false;
  private lastSyncEpochMs: number = 0;

  /** 获取桌面卡片同步服务全局单例。 */
  static shared(): HarmonyWidgetSyncService {
    if (!HarmonyWidgetSyncService.instance) {
      HarmonyWidgetSyncService.instance = new HarmonyWidgetSyncService();
    }
    return HarmonyWidgetSyncService.instance;
  }

  /** 在主应用已登录态下执行节流静默全量同步并刷新全部桌面卡片。 */
  async syncAll(context: common.Context, force: boolean = false): Promise<void> {
    if (this.syncing) { return; }
    const nowMs = Date.now();
    if (!force && nowMs - this.lastSyncEpochMs < 20000) {
      await this.refreshAllActiveForms(context);
      return;
    }
    this.syncing = true;
    try {
      const store = NativeHuksStore.shared();
      await store.init(context);
      const repo = MoviePilotRepository.shared();
      if (repo.token.length === 0 || repo.baseUrl.length === 0) {
        const active = await store.loadActiveSession();
        if (!active || !active.keepLogin || active.token.length === 0 || active.serverUrl.length === 0) {
          await this.refreshAllActiveForms(context);
          return;
        }
        repo.configureServer(active.serverUrl, active.allowSelfSigned);
        repo.setAuthToken(active.token);
        repo.isSuperuser = active.isSuperuser;
      }

      const pref = await preferences.getPreferences(context, SECURE_PREF_NAME);
      await Promise.all([
        this.syncMainSnapshot(repo, pref),
        this.syncPluginSnapshots(repo, pref)
      ]);
      await pref.flush();
      this.lastSyncEpochMs = Date.now();
      await this.refreshAllActiveForms(context);
    } catch {
      // 后台卡片同步静默容错，不影响主界面交互
    } finally {
      this.syncing = false;
    }
  }

  /** 乐观翻转正在播放卡片状态并立即刷新桌面卡片。 */
  async applyNowPlayingCommand(context: common.Context, audioCmd: string, pluginId: string = ''): Promise<void> {
    try {
      const pref = await preferences.getPreferences(context, SECURE_PREF_NAME);
      const raw = String(await pref.get(KEY_NOW_PLAYING, '') ?? '');
      if (raw.length > 2) {
        const obj = asRec(parseJson(raw));
        if (obj && boolVal(obj, 'active', false)) {
          const curPid = strVal(obj, 'pluginId', strVal(obj, 'plugin_id', ''));
          if (pluginId.length === 0 || curPid.length === 0 || curPid === pluginId) {
            if (audioCmd === 'togglePlayPause') {
              obj['isPlaying'] = !boolVal(obj, 'isPlaying', boolVal(obj, 'is_playing', false));
            } else if (audioCmd === 'toggleLike' && boolVal(obj, 'hasLike', boolVal(obj, 'has_like', false))) {
              obj['liked'] = !boolVal(obj, 'liked', false);
            }
            obj['updatedAt'] = Date.now();
            await pref.put(KEY_NOW_PLAYING, JSON.stringify(obj));
            await pref.flush();
          }
        }
      }
      await this.refreshAllActiveForms(context);
    } catch {
      // ignore optimistic sync failure
    }
  }

  /** 遍历 `'mp_active_form_bindings_v1'` 中记录的全部桌面卡片并触发 `formProvider.updateForm`。 */
  async refreshAllActiveForms(context: common.Context): Promise<void> {
    try {
      const pref = await preferences.getPreferences(context, SECURE_PREF_NAME);
      const rawBindings = String(await pref.get(KEY_ACTIVE_BINDINGS, '') ?? '');
      if (rawBindings.length < 2) { return; }
      const mapObj = asRec(parseJson(rawBindings));
      if (!mapObj) { return; }
      const mainRaw = String(await pref.get(KEY_MAIN_SNAPSHOT, '') ?? '');
      const npRaw = String(await pref.get(KEY_NOW_PLAYING, '') ?? '');
      const pluginRaw = String(await pref.get(KEY_PLUGIN_SNAPSHOTS, '') ?? '');

      const formIds = Object.keys(mapObj);
      for (let i = 0; i < formIds.length; i++) {
        const fid = formIds[i];
        const rec = asRec(mapObj[fid]);
        if (!rec) { continue; }
        const binding: ActiveFormBinding = {
          formId: fid,
          formName: strVal(rec, 'formName', 'MoviePilotWidget'),
          dimension: strVal(rec, 'dimension', '2*4'),
          content: strVal(rec, 'content', 'overview'),
          showMediaNames: boolVal(rec, 'showMediaNames', true),
          pluginIndex: Math.max(0, Math.trunc(numVal(rec, 'pluginIndex', 0))),
          pluginKey: strVal(rec, 'pluginKey', '')
        };
        const payload = this.buildPayloadForBinding(binding, mainRaw, npRaw, pluginRaw);
        formProvider.updateForm(fid, formBindingData.createFormBindingData(payload)).catch(() => {});
      }
    } catch {
      // ignore form refresh failure
    }
  }

  private async syncMainSnapshot(repo: MoviePilotRepository, pref: preferences.Preferences): Promise<void> {
    const pair = await Promise.all([
      repo.fetchDashboardStats().catch((): MpDashboardStats | null => null),
      repo.get(['dashboard', 'cpu']).catch(() => null),
      repo.fetchDownloads().catch((): MpDownloadTask[] => []),
      repo.fetchTransferHistory(1, 20).catch((): MpTransferHistoryItem[] => []),
      repo.fetchSubscriptions().catch((): MpSubscribeItem[] => [])
    ]);

    const stats = pair[0];
    if (!stats) { return; }
    let cpuPercent = 0;
    if (pair[1] && pair[1].status === 200) {
      const cpuParsed = parseJson(pair[1].body);
      if (typeof cpuParsed === 'number') {
        cpuPercent = cpuParsed;
      } else {
        const cpuRec = asRec(cpuParsed);
        cpuPercent = numVal(cpuRec, 'data', 0);
      }
    }
    const downloads = pair[2];
    const history = pair[3];
    const subscriptions = pair[4];

    const nowTime = currentHhMm();
    const serverName = repo.baseUrl.replace(/^https?:\/\//, '').split('/')[0] || 'MoviePilot';
    const freeBytes = Math.max(0, stats.storageTotalBytes - stats.storageUsedBytes);

    const overview: Record<string, Object> = {};
    overview['title'] = '系统概览';
    overview['updatedAt'] = nowTime;
    const overviewMetrics: Record<string, Object>[] = [
      makeMainMetric('cpu', 'CPU 占用', `${cpuPercent.toFixed(1)}%`, cpuPercent >= 85 ? 'warning' : 'accent'),
      makeMainMetric('memory', '内存占用', `${stats.memoryPercent.toFixed(1)}%`, stats.memoryPercent >= 85 ? 'warning' : 'default'),
      makeMainMetric('dl', '下载速度', formatSpeed(stats.downloadSpeed), 'success'),
      makeMainMetric('ul', '上传速度', formatSpeed(stats.uploadSpeed), 'default'),
      makeMainMetric('used', '已用存储', formatByteSize(stats.storageUsedBytes), 'default'),
      makeMainMetric('free', '剩余空间', stats.storageTotalBytes > 0 ? formatByteSize(freeBytes) : '—', 'default')
    ];
    const emptyItems: Record<string, Object>[] = [];
    overview['metrics'] = overviewMetrics;
    overview['items'] = emptyItems;

    const dlItems: Record<string, Object>[] = [];
    for (let i = 0; i < Math.min(6, downloads.length); i++) {
      const t = downloads[i];
      const normProg = Math.max(0, Math.min(1, t.progress > 1 ? t.progress / 100 : t.progress));
      const subParts: string[] = [];
      if (t.dlspeed.length > 0) { subParts.push(t.dlspeed); }
      if (t.leftTime.length > 0) { subParts.push(`剩余 ${t.leftTime}`); }
      dlItems.push({
        'id': t.hash || `dl-${i}`,
        'title': t.name || t.title,
        'subtitle': subParts.join(' · '),
        'progress': normProg
      });
    }
    const downloadsSec: Record<string, Object> = {};
    downloadsSec['title'] = '下载状态';
    downloadsSec['updatedAt'] = nowTime;
    const dlMetrics: Record<string, Object>[] = [
      makeMainMetric('dlSpeed', '下载速度', formatSpeed(stats.downloadSpeed), 'success'),
      makeMainMetric('ulSpeed', '上传速度', formatSpeed(stats.uploadSpeed), 'default'),
      makeMainMetric('freeSpace', '剩余空间', stats.storageTotalBytes > 0 ? formatByteSize(freeBytes) : '—', 'default'),
      makeMainMetric('count', '活跃任务', `${downloads.length}`, 'accent')
    ];
    downloadsSec['metrics'] = dlMetrics;
    downloadsSec['items'] = dlItems;

    const okHistory = history.filter((h: MpTransferHistoryItem) => h.status);
    const importItems: Record<string, Object>[] = [];
    for (let i = 0; i < Math.min(6, okHistory.length); i++) {
      const h = okHistory[i];
      const parts: string[] = [];
      if (h.year.length > 0) { parts.push(h.year); }
      if (h.type.length > 0) { parts.push(h.type); }
      const se = `${h.seasons} ${h.episodes}`.trim();
      if (se.length > 0) { parts.push(se); }
      if (h.date.length > 0) { parts.push(h.date); }
      importItems.push({
        'id': `imp-${h.id}-${i}`,
        'title': h.title,
        'subtitle': parts.join(' · ')
      });
    }
    const totalMedia = stats.movieCount + stats.tvCount + (stats.musicCount ?? 0);
    const importsSec: Record<string, Object> = {};
    importsSec['title'] = '近期入库';
    importsSec['updatedAt'] = nowTime;
    const importMetrics: Record<string, Object>[] = [
      makeMainMetric('count', '总入库', `${totalMedia}`, 'accent'),
      makeMainMetric('movie', '电影', `${stats.movieCount}`, 'default'),
      makeMainMetric('tv', '电视剧', `${stats.tvCount}`, 'default'),
      makeMainMetric('music', '音乐', `${stats.musicCount ?? 0}`, 'default')
    ];
    importsSec['metrics'] = importMetrics;
    importsSec['items'] = importItems;

    let movieSubs = 0;
    let tvSubs = 0;
    for (let i = 0; i < subscriptions.length; i++) {
      const s = subscriptions[i];
      const lower = s.type.toLowerCase();
      if (lower.includes('电视') || lower === 'tv' || lower === 'series') {
        tvSubs++;
      } else {
        movieSubs++;
      }
    }
    const subItems: Record<string, Object>[] = [];
    for (let i = 0; i < Math.min(6, subscriptions.length); i++) {
      const s = subscriptions[i];
      const done = Math.max(0, s.totalEpisode - s.lackEpisode);
      const row: Record<string, Object> = {};
      row['id'] = `sub-${s.id}-${i}`;
      row['title'] = s.name;
      row['subtitle'] = s.totalEpisode > 0 ? `${s.type || '剧集'} · ${done}/${s.totalEpisode} 集` : (s.type || '电影');
      if (s.totalEpisode > 0) {
        row['progress'] = Math.max(0, Math.min(1, done / s.totalEpisode));
      }
      subItems.push(row);
    }
    const subscriptionsSec: Record<string, Object> = {};
    subscriptionsSec['title'] = '订阅';
    subscriptionsSec['updatedAt'] = nowTime;
    const subMetrics: Record<string, Object>[] = [
      makeMainMetric('count', '总订阅', `${subscriptions.length}`, 'accent'),
      makeMainMetric('movie', '电影', `${movieSubs}`, 'default'),
      makeMainMetric('tv', '电视剧', `${tvSubs}`, 'default')
    ];
    subscriptionsSec['metrics'] = subMetrics;
    subscriptionsSec['items'] = subItems;

    const fullSnap: Record<string, Object> = {};
    fullSnap['server'] = serverName;
    fullSnap['movies'] = stats.movieCount;
    fullSnap['tvs'] = stats.tvCount;
    fullSnap['music'] = stats.musicCount ?? 0;
    fullSnap['speed'] = formatSpeed(stats.downloadSpeed);
    fullSnap['updatedAt'] = nowTime;
    fullSnap['overview'] = overview;
    fullSnap['downloads'] = downloadsSec;
    fullSnap['imports'] = importsSec;
    fullSnap['subscriptions'] = subscriptionsSec;

    await pref.put(KEY_MAIN_SNAPSHOT, JSON.stringify(fullSnap));
  }

  private async syncPluginSnapshots(repo: MoviePilotRepository, pref: preferences.Preferences): Promise<void> {
    const nowTime = currentHhMm();
    const runtimeRaw = String(await pref.get(KEY_PLUGIN_RUNTIME_MAP, '') ?? '');
    const runtimeMap = asRec(parseJson(runtimeRaw));

    let metaList: Object[] = [];
    const metaResp = await repo.get(['plugin', 'widgets', 'meta']).catch(() => null);
    if (metaResp && metaResp.status >= 200 && metaResp.status < 300) {
      metaList = unwrapArray(parseJson(metaResp.body));
    }
    if (metaList.length === 0) {
      const dashMetaResp = await repo.get(['plugin', 'dashboard', 'meta']).catch(() => null);
      if (dashMetaResp && dashMetaResp.status >= 200 && dashMetaResp.status < 300) {
        metaList = unwrapArray(parseJson(dashMetaResp.body));
      }
    }

    const entries: Record<string, Object>[] = [];
    const seenKeys = new Set<string>();

    // 先合并运行态推送的小组件快照
    if (runtimeMap) {
      const rtKeys = Object.keys(runtimeMap);
      for (let i = 0; i < rtKeys.length; i++) {
        const compKey = rtKeys[i];
        const snapRec = asRec(runtimeMap[compKey]);
        if (!snapRec) { continue; }
        const normalized = this.normalizePluginSnapshotEntry(compKey, snapRec, nowTime);
        if (normalized) {
          seenKeys.add(compKey);
          entries.push(normalized);
        }
      }
    }

    // 拉取后端前 8 个已启用插件小组件快照
    const cap = Math.min(8, metaList.length);
    for (let i = 0; i < cap; i++) {
      const meta = asRec(metaList[i]);
      if (!meta) { continue; }
      const pid = strVal(meta, 'plugin_id', strVal(meta, 'pluginId', strVal(meta, 'id', '')));
      if (pid.length === 0) { continue; }
      const pname = strVal(meta, 'plugin_name', strVal(meta, 'pluginName', pid));
      const wkey = strVal(meta, 'key', strVal(meta, 'widgetKey', ''));
      const compKey = `${pid}::${wkey}`;
      if (seenKeys.has(compKey)) { continue; }

      const q: Record<string, string> = {};
      if (wkey.length > 0) { q['key'] = wkey; }
      let snapObj: Record<string, Object> | null = null;
      const widgetResp = await repo.get(['plugin', 'widgets', pid], q).catch(() => null);
      if (widgetResp && widgetResp.status >= 200 && widgetResp.status < 300) {
        snapObj = unwrapObject(parseJson(widgetResp.body));
      }
      if (!snapObj) {
        const dashSegs = wkey.length > 0 ? ['plugin', 'dashboard', pid, wkey] : ['plugin', 'dashboard', pid];
        const dashResp = await repo.get(dashSegs).catch(() => null);
        if (dashResp && dashResp.status >= 200 && dashResp.status < 300) {
          const dashObj = unwrapObject(parseJson(dashResp.body));
          if (dashObj) {
            const dashMetrics: Record<string, Object>[] = [
              makePluginMetric('status', '插件状态', '运行中', 'success')
            ];
            const fallbackSnap: Record<string, Object> = {};
            fallbackSnap['pluginId'] = pid;
            fallbackSnap['pluginName'] = pname;
            fallbackSnap['widgetKey'] = wkey;
            fallbackSnap['title'] = strVal(meta, 'name', pname);
            fallbackSnap['subtitle'] = '已连接插件仪表盘 · 点击直达详情';
            fallbackSnap['kind'] = 'metrics';
            fallbackSnap['metrics'] = dashMetrics;
            snapObj = fallbackSnap;
          }
        }
      }
      if (snapObj) {
        snapObj['pluginId'] = pid;
        snapObj['pluginName'] = strVal(snapObj, 'pluginName', strVal(snapObj, 'plugin_name', pname));
        snapObj['widgetKey'] = wkey;
        if (strVal(snapObj, 'title', '').length === 0) {
          snapObj['title'] = strVal(meta, 'name', pname);
        }
        const normalized = this.normalizePluginSnapshotEntry(compKey, snapObj, nowTime);
        if (normalized) {
          seenKeys.add(compKey);
          entries.push(normalized);
        }
      }
    }

    await pref.put(KEY_PLUGIN_SNAPSHOTS, JSON.stringify(entries));
  }

  private normalizePluginSnapshotEntry(
    compositeKey: string,
    raw: Record<string, Object>,
    fallbackTime: string
  ): Record<string, Object> | null {
    const pid = strVal(raw, 'pluginId', strVal(raw, 'plugin_id', ''));
    if (pid.length === 0) { return null; }
    const pname = strVal(raw, 'pluginName', strVal(raw, 'plugin_name', pid));
    const wkey = strVal(raw, 'widgetKey', strVal(raw, 'key', ''));
    const entry: Record<string, Object> = {};
    entry['compositeKey'] = compositeKey;
    entry['pluginId'] = pid;
    entry['pluginName'] = pname;
    entry['widgetKey'] = wkey;
    entry['title'] = strVal(raw, 'title', pname);
    entry['subtitle'] = strVal(raw, 'subtitle', strVal(raw, 'message', ''));
    entry['kind'] = strVal(raw, 'kind', 'metrics');
    entry['accentHex'] = strVal(raw, 'accentHex', strVal(raw, 'accent_hex', '#317AF7'));
    entry['updatedAt'] = fallbackTime;
    entry['metricsJson'] = Array.isArray(raw['metrics']) ? JSON.stringify(raw['metrics']) : '[]';
    entry['itemsJson'] = Array.isArray(raw['items']) ? JSON.stringify(raw['items']) : '[]';
    entry['layoutJson'] = raw['layout'] && typeof raw['layout'] === 'object' ? JSON.stringify(raw['layout']) : '';
    entry['layoutsJson'] = raw['layouts'] && typeof raw['layouts'] === 'object' ? JSON.stringify(raw['layouts']) : '';
    return entry;
  }

  private buildPayloadForBinding(
    binding: ActiveFormBinding,
    mainRaw: string,
    npRaw: string,
    pluginRaw: string
  ): Record<string, Object> {
    if (binding.formName === 'MoviePilotNowPlayingWidget') {
      const out: Record<string, Object> = {
        'formId': binding.formId,
        'dimension': binding.dimension,
        'active': false,
        'pluginId': '',
        'pluginName': '',
        'title': '',
        'artist': '',
        'album': '',
        'lyrics': '',
        'artworkUrl': '',
        'isPlaying': false,
        'liked': false,
        'hasLike': false,
        'canNext': true,
        'canPrevious': true,
        'durationMs': 0,
        'positionMs': 0
      };
      const snap = asRec(parseJson(npRaw));
      if (snap) {
        out['active'] = boolVal(snap, 'active', false);
        out['pluginId'] = strVal(snap, 'pluginId', strVal(snap, 'plugin_id', ''));
        out['pluginName'] = strVal(snap, 'pluginName', strVal(snap, 'plugin_name', ''));
        out['title'] = strVal(snap, 'title', '');
        out['artist'] = strVal(snap, 'artist', '');
        out['album'] = strVal(snap, 'album', '');
        out['lyrics'] = strVal(snap, 'lyrics', '');
        out['artworkUrl'] = strVal(snap, 'artworkUrl', strVal(snap, 'artwork_path', ''));
        out['isPlaying'] = boolVal(snap, 'isPlaying', boolVal(snap, 'is_playing', false));
        out['liked'] = boolVal(snap, 'liked', false);
        out['hasLike'] = boolVal(snap, 'hasLike', boolVal(snap, 'has_like', false));
        out['canNext'] = boolVal(snap, 'canNext', boolVal(snap, 'can_next', true));
        out['canPrevious'] = boolVal(snap, 'canPrevious', boolVal(snap, 'can_prev', true));
        out['durationMs'] = Math.max(0, Math.trunc(numVal(snap, 'durationMs', numVal(snap, 'duration_ms', 0))));
        out['positionMs'] = Math.max(0, Math.trunc(numVal(snap, 'positionMs', numVal(snap, 'position_ms', 0))));
      }
      return out;
    }

    if (binding.formName === 'MoviePilotPluginWidget') {
      const out: Record<string, Object> = {
        'formId': binding.formId,
        'dimension': binding.dimension,
        'hasWidget': false,
        'totalWidgets': 0,
        'pluginId': '',
        'pluginName': 'MoviePilot 插件',
        'widgetKey': '',
        'title': 'MoviePilot 插件',
        'subtitle': '打开 MoviePilot 自动同步已启用插件卡片',
        'kind': 'metrics',
        'accentHex': '#317AF7',
        'updatedAt': '',
        'metricsJson': '[]',
        'itemsJson': '[]',
        'layoutJson': ''
      };
      const list = unwrapArray(parseJson(pluginRaw));
      out['totalWidgets'] = list.length;
      if (list.length > 0) {
        const chosen = asRec(list[binding.pluginIndex % list.length]);
        if (chosen) {
          out['hasWidget'] = true;
          out['pluginId'] = strVal(chosen, 'pluginId', '');
          out['pluginName'] = strVal(chosen, 'pluginName', '插件');
          out['widgetKey'] = strVal(chosen, 'widgetKey', '');
          out['title'] = strVal(chosen, 'title', '插件');
          out['subtitle'] = strVal(chosen, 'subtitle', '');
          out['kind'] = strVal(chosen, 'kind', 'metrics');
          out['accentHex'] = strVal(chosen, 'accentHex', '#317AF7');
          out['updatedAt'] = strVal(chosen, 'updatedAt', '');
          out['metricsJson'] = strVal(chosen, 'metricsJson', '[]');
          out['itemsJson'] = strVal(chosen, 'itemsJson', '[]');
          const sizeKey = binding.dimension === '2*2' ? 'small' : (binding.dimension === '4*4' ? 'large' : 'medium');
          let layoutJson = strVal(chosen, 'layoutJson', '');
          const layoutsRec = asRec(parseJson(strVal(chosen, 'layoutsJson', '')));
          if (layoutsRec && layoutsRec[sizeKey] !== undefined && layoutsRec[sizeKey] !== null) {
            layoutJson = JSON.stringify(layoutsRec[sizeKey]);
          }
          out['layoutJson'] = layoutJson;
        }
      }
      return out;
    }

    // 主体卡片
    const content = ['overview', 'downloads', 'imports', 'subscriptions'].includes(binding.content)
      ? binding.content
      : 'overview';
    const deepLink = content === 'downloads'
      ? 'moviepilot://downloading'
      : (content === 'imports' ? 'moviepilot://history' : (content === 'subscriptions' ? 'moviepilot://subscribe' : 'moviepilot://dashboard'));
    const title = content === 'downloads'
      ? '下载状态'
      : (content === 'imports' ? '近期入库' : (content === 'subscriptions' ? '订阅' : '系统概览'));

    const out: Record<string, Object> = {
      'formId': binding.formId,
      'dimension': binding.dimension,
      'content': content,
      'title': title,
      'deepLink': deepLink,
      'showMediaNames': binding.showMediaNames,
      'server': 'MoviePilot',
      'movies': 0,
      'tvs': 0,
      'speed': '0 B/s',
      'updatedAt': '',
      'metricsJson': '[]',
      'itemsJson': '[]'
    };
    const snap = asRec(parseJson(mainRaw));
    if (snap) {
      out['server'] = strVal(snap, 'server', 'MoviePilot');
      out['movies'] = Math.trunc(numVal(snap, 'movies', 0));
      out['tvs'] = Math.trunc(numVal(snap, 'tvs', 0));
      out['speed'] = strVal(snap, 'speed', '0 B/s');
      out['updatedAt'] = strVal(snap, 'updatedAt', '');
      const sec = asRec(snap[content]);
      if (sec) {
        out['title'] = strVal(sec, 'title', title);
        out['updatedAt'] = strVal(sec, 'updatedAt', strVal(snap, 'updatedAt', ''));
        out['metricsJson'] = Array.isArray(sec['metrics']) ? JSON.stringify(sec['metrics']) : '[]';
        const rawItems = Array.isArray(sec['items']) ? (sec['items'] as Object[]) : [];
        const items: Record<string, Object>[] = [];
        for (let i = 0; i < rawItems.length; i++) {
          const r = asRec(rawItems[i]);
          if (!r) { continue; }
          const row: Record<string, Object> = {
            'id': strVal(r, 'id', `item-${i}`),
            'title': binding.showMediaNames ? strVal(r, 'title', `项目 ${i + 1}`) : `项目 ${i + 1}`,
            'subtitle': binding.showMediaNames ? strVal(r, 'subtitle', '') : ''
          };
          if (r['progress'] !== undefined && r['progress'] !== null) {
            row['progress'] = numVal(r, 'progress', 0);
          }
          items.push(row);
        }
        out['itemsJson'] = JSON.stringify(items);
      }
    }
    return out;
  }
}
