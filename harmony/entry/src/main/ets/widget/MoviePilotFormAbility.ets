import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';

interface FormWidgetPayload {
  server: string;
  movies: number;
  tvs: number;
  speed: string;
}

/** 鸿蒙原生桌面服务卡片 FormExtensionAbility（共享 `WidgetData` 快照契约）。 */
export default class MoviePilotFormAbility extends FormExtensionAbility {
  onAddForm(_want: Want): formBindingData.FormBindingData {
    const data: FormWidgetPayload = {
      server: 'MoviePilot',
      movies: 0,
      tvs: 0,
      speed: '0 B/s'
    };
    return formBindingData.createFormBindingData(data);
  }
}
