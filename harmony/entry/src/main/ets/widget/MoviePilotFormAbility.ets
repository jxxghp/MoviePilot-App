import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';

/** 鸿蒙原生桌面服务卡片 FormExtensionAbility（共享 `WidgetData` 快照契约）。 */
export default class MoviePilotFormAbility extends FormExtensionAbility {
  onAddForm(_want: Want): formBindingData.FormBindingData {
    const data: Record<string, Object> = {
      server: 'MoviePilot',
      movies: 776,
      tvs: 1268,
      speed: '12.4 MB/s'
    };
    return formBindingData.createFormBindingData(data);
  }
}
