import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { Want } from '@kit.AbilityKit';

interface FormWidgetPayload {
  server: string;
  movies: number;
  tvs: number;
  speed: string;
}

/**
 * 鸿蒙原生桌面服务卡片 FormExtensionAbility：
 * 读取主应用写入 `mp_harmony_secure_store` 的 `mp_widget_snapshot_v1` 缓存快照并在添加/定时刷新时更新卡片。
 */
export default class MoviePilotFormAbility extends FormExtensionAbility {
  private readCachedSnapshot(): FormWidgetPayload {
    const fallback: FormWidgetPayload = {
      server: 'MoviePilot',
      movies: 0,
      tvs: 0,
      speed: '0 B/s'
    };
    try {
      const pref = preferences.getPreferencesSync(this.context, { name: 'mp_harmony_secure_store' });
      const raw = String(pref.getSync('mp_widget_snapshot_v1', '') ?? '');
      if (raw.length > 2) {
        const parsed = JSON.parse(raw) as Record<string, Object>;
        return {
          server: String(parsed['server'] ?? 'MoviePilot'),
          movies: Number(parsed['movies'] ?? 0) || 0,
          tvs: Number(parsed['tvs'] ?? 0) || 0,
          speed: String(parsed['speed'] ?? '0 B/s')
        };
      }
    } catch {
      // ignore preferences read error in form sandbox
    }
    return fallback;
  }

  onAddForm(_want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(this.readCachedSnapshot());
  }

  onUpdateForm(formId: string): void {
    try {
      const binding = formBindingData.createFormBindingData(this.readCachedSnapshot());
      formProvider.updateForm(formId, binding).catch(() => {});
    } catch {
      // ignore form update error
    }
  }
}
