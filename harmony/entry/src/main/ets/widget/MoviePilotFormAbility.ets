import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { Want } from '@kit.AbilityKit';

/** 单张已放置鸿蒙桌面卡片的持久化绑定记录。 */
interface ActiveFormBindingRecord {
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
const MAIN_CONTENT_ORDER: string[] = ['overview', 'downloads', 'imports', 'subscriptions'];

function asRecord(val: Object | null | undefined): Record<string, Object> | null {
  if (val !== null && val !== undefined && typeof val === 'object' && !Array.isArray(val)) {
    return val as Record<string, Object>;
  }
  return null;
}

function strField(obj: Record<string, Object> | null, key: string, fallback: string = ''): string {
  if (!obj || obj[key] === undefined || obj[key] === null) {
    return fallback;
  }
  return String(obj[key]);
}

function numField(obj: Record<string, Object> | null, key: string, fallback: number = 0): number {
  if (!obj || obj[key] === undefined || obj[key] === null) {
    return fallback;
  }
  const n = Number(obj[key]);
  return Number.isFinite(n) ? n : fallback;
}

function boolField(obj: Record<string, Object> | null, key: string, fallback: boolean = false): boolean {
  if (!obj || obj[key] === undefined || obj[key] === null) {
    return fallback;
  }
  if (typeof obj[key] === 'boolean') {
    return obj[key] as boolean;
  }
  return String(obj[key]).toLowerCase() === 'true';
}

function mapDimensionCode(rawDim: Object | undefined): string {
  const code = Number(rawDim);
  if (code === 2) {
    return '2*2';
  }
  if (code === 4) {
    return '4*4';
  }
  const rawStr = rawDim !== undefined ? String(rawDim) : '';
  if (rawStr === '2*2' || rawStr === '2*4' || rawStr === '4*4') {
    return rawStr;
  }
  return '2*4';
}

function titleForMainContent(content: string): string {
  if (content === 'downloads') { return '下载状态'; }
  if (content === 'imports') { return '近期入库'; }
  if (content === 'subscriptions') { return '订阅'; }
  return '系统概览';
}

function deepLinkForMainContent(content: string): string {
  if (content === 'downloads') { return 'moviepilot://downloading'; }
  if (content === 'imports') { return 'moviepilot://history'; }
  if (content === 'subscriptions') { return 'moviepilot://subscribe'; }
  return 'moviepilot://dashboard';
}

/**
 * 鸿蒙原生桌面服务卡片 FormExtensionAbility：
 * 统一管理 `MoviePilotWidget`（主体 4 类卡片）、`MoviePilotNowPlayingWidget`（正在播放）
 * 与 `MoviePilotPluginWidget`（插件预设与声明式自定义布局）的绑定登记、快照投影及卡片内事件交互。
 */
export default class MoviePilotFormAbility extends FormExtensionAbility {
  private openStore(): preferences.Preferences | null {
    try {
      return preferences.getPreferencesSync(this.context, { name: SECURE_PREF_NAME });
    } catch {
      return null;
    }
  }

  private readBindingsMap(pref: preferences.Preferences | null): Record<string, ActiveFormBindingRecord> {
    const empty: Record<string, ActiveFormBindingRecord> = {};
    if (!pref) { return empty; }
    try {
      const raw = String(pref.getSync(KEY_ACTIVE_BINDINGS, '') ?? '');
      if (raw.length < 2) { return empty; }
      const parsed = asRecord(JSON.parse(raw) as Object);
      if (!parsed) { return empty; }
      const keys = Object.keys(parsed);
      for (let i = 0; i < keys.length; i++) {
        const fid = keys[i];
        const rec = asRecord(parsed[fid]);
        if (!rec) { continue; }
        empty[fid] = {
          formId: fid,
          formName: strField(rec, 'formName', 'MoviePilotWidget'),
          dimension: strField(rec, 'dimension', '2*4'),
          content: strField(rec, 'content', 'overview'),
          showMediaNames: boolField(rec, 'showMediaNames', true),
          pluginIndex: Math.max(0, Math.trunc(numField(rec, 'pluginIndex', 0))),
          pluginKey: strField(rec, 'pluginKey', '')
        };
      }
    } catch {
      // ignore malformed binding map
    }
    return empty;
  }

  private saveBindingsMap(pref: preferences.Preferences | null, map: Record<string, ActiveFormBindingRecord>): void {
    if (!pref) { return; }
    try {
      pref.putSync(KEY_ACTIVE_BINDINGS, JSON.stringify(map));
      pref.flush();
    } catch {
      // ignore flush error in form sandbox
    }
  }

  private buildMainCardPayload(
    pref: preferences.Preferences | null,
    binding: ActiveFormBindingRecord
  ): Record<string, Object> {
    const content = MAIN_CONTENT_ORDER.includes(binding.content) ? binding.content : 'overview';
    const out: Record<string, Object> = {};
    out['formId'] = binding.formId;
    out['dimension'] = binding.dimension;
    out['content'] = content;
    out['title'] = titleForMainContent(content);
    out['deepLink'] = deepLinkForMainContent(content);
    out['showMediaNames'] = binding.showMediaNames;
    out['server'] = 'MoviePilot';
    out['movies'] = 0;
    out['tvs'] = 0;
    out['speed'] = '0 B/s';
    out['updatedAt'] = '';
    out['metricsJson'] = '[]';
    out['itemsJson'] = '[]';

    if (!pref) { return out; }
    try {
      const raw = String(pref.getSync(KEY_MAIN_SNAPSHOT, '') ?? '');
      if (raw.length > 2) {
        const snap = asRecord(JSON.parse(raw) as Object);
        if (snap) {
          const movies = Math.trunc(numField(snap, 'movies', 0));
          const tvs = Math.trunc(numField(snap, 'tvs', 0));
          const speed = strField(snap, 'speed', '0 B/s');
          out['server'] = strField(snap, 'server', 'MoviePilot');
          out['movies'] = movies;
          out['tvs'] = tvs;
          out['speed'] = speed;
          out['updatedAt'] = strField(snap, 'updatedAt', '');

          const sec = asRecord(snap[content]);
          if (sec) {
            out['title'] = strField(sec, 'title', titleForMainContent(content));
            out['updatedAt'] = strField(sec, 'updatedAt', strField(snap, 'updatedAt', ''));
            const metricsArr = Array.isArray(sec['metrics']) ? (sec['metrics'] as Object[]) : [];
            const rawItems = Array.isArray(sec['items']) ? (sec['items'] as Object[]) : [];
            const projectedItems: Record<string, Object>[] = [];
            for (let i = 0; i < rawItems.length; i++) {
              const itemRec = asRecord(rawItems[i]);
              if (!itemRec) { continue; }
              const row: Record<string, Object> = {};
              row['id'] = strField(itemRec, 'id', `item-${i}`);
              row['title'] = binding.showMediaNames ? strField(itemRec, 'title', `项目 ${i + 1}`) : `项目 ${i + 1}`;
              row['subtitle'] = binding.showMediaNames ? strField(itemRec, 'subtitle', '') : '';
              if (itemRec['progress'] !== undefined && itemRec['progress'] !== null) {
                row['progress'] = numField(itemRec, 'progress', 0);
              }
              projectedItems.push(row);
            }
            out['metricsJson'] = JSON.stringify(metricsArr);
            out['itemsJson'] = JSON.stringify(projectedItems);
          } else {
            const fallbackMetrics: Record<string, Object>[] = [
              { 'id': 'movies', 'title': '电影', 'value': `${movies}`, 'tone': 'default' },
              { 'id': 'tvs', 'title': '电视剧', 'value': `${tvs}`, 'tone': 'default' },
              { 'id': 'speed', 'title': '下载速度', 'value': speed, 'tone': 'success' }
            ];
            out['metricsJson'] = JSON.stringify(fallbackMetrics);
          }
        }
      }
    } catch {
      // keep safe fallback
    }
    return out;
  }

  private buildNowPlayingPayload(
    pref: preferences.Preferences | null,
    binding: ActiveFormBindingRecord
  ): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['formId'] = binding.formId;
    out['dimension'] = binding.dimension;
    out['active'] = false;
    out['pluginId'] = '';
    out['pluginName'] = '';
    out['title'] = '';
    out['artist'] = '';
    out['album'] = '';
    out['lyrics'] = '';
    out['artworkUrl'] = '';
    out['isPlaying'] = false;
    out['liked'] = false;
    out['hasLike'] = false;
    out['canNext'] = true;
    out['canPrevious'] = true;
    out['durationMs'] = 0;
    out['positionMs'] = 0;

    if (!pref) { return out; }
    try {
      const raw = String(pref.getSync(KEY_NOW_PLAYING, '') ?? '');
      if (raw.length > 2) {
        const snap = asRecord(JSON.parse(raw) as Object);
        if (snap) {
          out['active'] = boolField(snap, 'active', false);
          out['pluginId'] = strField(snap, 'pluginId', strField(snap, 'plugin_id', ''));
          out['pluginName'] = strField(snap, 'pluginName', strField(snap, 'plugin_name', ''));
          out['title'] = strField(snap, 'title', '');
          out['artist'] = strField(snap, 'artist', '');
          out['album'] = strField(snap, 'album', '');
          out['lyrics'] = strField(snap, 'lyrics', '');
          out['artworkUrl'] = strField(snap, 'artworkUrl', strField(snap, 'artwork_path', ''));
          out['isPlaying'] = boolField(snap, 'isPlaying', boolField(snap, 'is_playing', false));
          out['liked'] = boolField(snap, 'liked', false);
          out['hasLike'] = boolField(snap, 'hasLike', boolField(snap, 'has_like', false));
          out['canNext'] = boolField(snap, 'canNext', boolField(snap, 'can_next', true));
          out['canPrevious'] = boolField(snap, 'canPrevious', boolField(snap, 'can_prev', true));
          out['durationMs'] = Math.max(0, Math.trunc(numField(snap, 'durationMs', numField(snap, 'duration_ms', 0))));
          out['positionMs'] = Math.max(0, Math.trunc(numField(snap, 'positionMs', numField(snap, 'position_ms', 0))));
        }
      }
    } catch {
      // keep idle state
    }
    return out;
  }

  private buildPluginCardPayload(
    pref: preferences.Preferences | null,
    binding: ActiveFormBindingRecord
  ): Record<string, Object> {
    const out: Record<string, Object> = {};
    out['formId'] = binding.formId;
    out['dimension'] = binding.dimension;
    out['hasWidget'] = false;
    out['totalWidgets'] = 0;
    out['pluginId'] = '';
    out['pluginName'] = 'MoviePilot 插件';
    out['widgetKey'] = '';
    out['title'] = 'MoviePilot 插件';
    out['subtitle'] = '打开 MoviePilot 自动同步已启用插件卡片';
    out['kind'] = 'metrics';
    out['accentHex'] = '#317AF7';
    out['updatedAt'] = '';
    out['metricsJson'] = '[]';
    out['itemsJson'] = '[]';
    out['layoutJson'] = '';

    if (!pref) { return out; }
    try {
      const raw = String(pref.getSync(KEY_PLUGIN_SNAPSHOTS, '') ?? '');
      if (raw.length > 2) {
        const parsed = JSON.parse(raw) as Object;
        const list = Array.isArray(parsed) ? (parsed as Object[]) : [];
        out['totalWidgets'] = list.length;
        if (list.length > 0) {
          let targetIdx = binding.pluginIndex % list.length;
          if (binding.pluginKey.length > 0) {
            for (let i = 0; i < list.length; i++) {
              const candidate = asRecord(list[i]);
              if (candidate && strField(candidate, 'compositeKey', '') === binding.pluginKey) {
                targetIdx = i;
                break;
              }
            }
          }
          const chosen = asRecord(list[targetIdx]);
          if (chosen) {
            out['hasWidget'] = true;
            out['pluginId'] = strField(chosen, 'pluginId', '');
            out['pluginName'] = strField(chosen, 'pluginName', '插件');
            out['widgetKey'] = strField(chosen, 'widgetKey', '');
            out['title'] = strField(chosen, 'title', strField(chosen, 'pluginName', '插件'));
            out['subtitle'] = strField(chosen, 'subtitle', '');
            out['kind'] = strField(chosen, 'kind', 'metrics');
            out['accentHex'] = strField(chosen, 'accentHex', '#317AF7');
            out['updatedAt'] = strField(chosen, 'updatedAt', '');
            out['metricsJson'] = strField(chosen, 'metricsJson', '[]');
            out['itemsJson'] = strField(chosen, 'itemsJson', '[]');

            const sizeKey = binding.dimension === '2*2' ? 'small' : (binding.dimension === '4*4' ? 'large' : 'medium');
            let resolvedLayout = strField(chosen, 'layoutJson', '');
            const layoutsRaw = strField(chosen, 'layoutsJson', '');
            if (layoutsRaw.length > 2) {
              const layoutsRec = asRecord(JSON.parse(layoutsRaw) as Object);
              if (layoutsRec && layoutsRec[sizeKey] !== undefined && layoutsRec[sizeKey] !== null) {
                resolvedLayout = JSON.stringify(layoutsRec[sizeKey]);
              }
            }
            out['layoutJson'] = resolvedLayout;
          }
        }
      }
    } catch {
      // keep default guidance state
    }
    return out;
  }

  private createBindingPayload(
    pref: preferences.Preferences | null,
    binding: ActiveFormBindingRecord
  ): Record<string, Object> {
    if (binding.formName === 'MoviePilotNowPlayingWidget') {
      return this.buildNowPlayingPayload(pref, binding);
    }
    if (binding.formName === 'MoviePilotPluginWidget') {
      return this.buildPluginCardPayload(pref, binding);
    }
    return this.buildMainCardPayload(pref, binding);
  }

  /** 添加桌面卡片时登记活跃 `formId` 并按卡片种类与尺寸生成初始绑定数据。 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params = want.parameters ?? {};
    const formId = String(params['ohos.extra.param.key.form_identity'] ?? '');
    const formName = String(params['ohos.extra.param.key.form_name'] ?? 'MoviePilotWidget');
    const dimension = mapDimensionCode(params['ohos.extra.param.key.form_dimension']);

    const pref = this.openStore();
    const map = this.readBindingsMap(pref);
    const existing = formId.length > 0 ? map[formId] : undefined;
    const record: ActiveFormBindingRecord = {
      formId: formId,
      formName: formName,
      dimension: dimension,
      content: existing ? existing.content : 'overview',
      showMediaNames: existing ? existing.showMediaNames : true,
      pluginIndex: existing ? existing.pluginIndex : 0,
      pluginKey: existing ? existing.pluginKey : ''
    };
    if (formId.length > 0) {
      map[formId] = record;
      this.saveBindingsMap(pref, map);
    }
    return formBindingData.createFormBindingData(this.createBindingPayload(pref, record));
  }

  /** 定时或系统请求更新指定桌面卡片。 */
  onUpdateForm(formId: string): void {
    const pref = this.openStore();
    const map = this.readBindingsMap(pref);
    const record: ActiveFormBindingRecord = map[formId] ?? {
      formId: formId,
      formName: 'MoviePilotWidget',
      dimension: '2*4',
      content: 'overview',
      showMediaNames: true,
      pluginIndex: 0,
      pluginKey: ''
    };
    try {
      const payload = this.createBindingPayload(pref, record);
      formProvider.updateForm(formId, formBindingData.createFormBindingData(payload)).catch(() => {});
    } catch {
      // ignore form update error
    }
  }

  /** 卡片从桌面移除时清理持久化活跃登记。 */
  onRemoveForm(formId: string): void {
    const pref = this.openStore();
    const map = this.readBindingsMap(pref);
    if (map[formId] !== undefined) {
      const next: Record<string, ActiveFormBindingRecord> = {};
      const keys = Object.keys(map);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (k !== formId) {
          next[k] = map[k];
        }
      }
      this.saveBindingsMap(pref, next);
    }
  }

  /** 处理桌面卡片内直接点击事件（主体四视图循环切换、隐私脱敏开关、插件卡片轮换与乐观播控）。 */
  onFormEvent(formId: string, message: string): void {
    const pref = this.openStore();
    const map = this.readBindingsMap(pref);
    const current = map[formId];
    let actionType = '';
    try {
      const msgObj = asRecord(JSON.parse(message) as Object);
      actionType = strField(msgObj, 'action', message);
    } catch {
      actionType = message.trim();
    }

    if (current && actionType === 'cycleContent') {
      const curIdx = MAIN_CONTENT_ORDER.indexOf(current.content);
      const nextContent = MAIN_CONTENT_ORDER[(curIdx + 1) % MAIN_CONTENT_ORDER.length];
      current.content = nextContent;
      map[formId] = current;
      this.saveBindingsMap(pref, map);
      const payload = this.createBindingPayload(pref, current);
      formProvider.updateForm(formId, formBindingData.createFormBindingData(payload)).catch(() => {});
      return;
    }

    if (current && actionType === 'togglePrivacy') {
      current.showMediaNames = !current.showMediaNames;
      map[formId] = current;
      this.saveBindingsMap(pref, map);
      const payload = this.createBindingPayload(pref, current);
      formProvider.updateForm(formId, formBindingData.createFormBindingData(payload)).catch(() => {});
      return;
    }

    if (current && actionType === 'cyclePlugin') {
      current.pluginIndex = current.pluginIndex + 1;
      current.pluginKey = '';
      map[formId] = current;
      this.saveBindingsMap(pref, map);
      const payload = this.createBindingPayload(pref, current);
      formProvider.updateForm(formId, formBindingData.createFormBindingData(payload)).catch(() => {});
      return;
    }

    if (pref && (actionType === 'togglePlayPause' || actionType === 'toggleLike')) {
      try {
        const rawNp = String(pref.getSync(KEY_NOW_PLAYING, '') ?? '');
        if (rawNp.length > 2) {
          const npObj = asRecord(JSON.parse(rawNp) as Object);
          if (npObj && boolField(npObj, 'active', false)) {
            if (actionType === 'togglePlayPause') {
              const curPlay = boolField(npObj, 'isPlaying', boolField(npObj, 'is_playing', false));
              npObj['isPlaying'] = !curPlay;
            } else if (boolField(npObj, 'hasLike', boolField(npObj, 'has_like', false))) {
              npObj['liked'] = !boolField(npObj, 'liked', false);
            }
            npObj['updatedAt'] = Date.now();
            pref.putSync(KEY_NOW_PLAYING, JSON.stringify(npObj));
            pref.flush();
          }
        }
      } catch {
        // ignore optimistic write failure
      }
      this.onUpdateForm(formId);
      return;
    }

    this.onUpdateForm(formId);
  }
}
