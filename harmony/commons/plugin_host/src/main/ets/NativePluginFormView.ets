import { webview } from '@kit.ArkWeb';
import { RustCoreBridge } from '../../../../../core_rust_bridge/src/main/ets/bridge/RustCoreBridge';
import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../../design_system/src/main/ets/components/CinematicSurfaces';

export interface PluginFieldPlan {
  component: string;
  modelKey?: string;
  label: string;
  hint: string;
  visible: boolean;
  text: string;
}

/**
 * 鸿蒙原生动态插件表单/数据页宿主：
 * - 100% 消费 Rust `planPluginFormJson` + `applyPluginFormPatch` + `analyzeCron`；
 * - 仅对 `render_mode == 'vue'` 遗留插件启用严格隔离的 ArkWeb 容器并锁定同源导航、退出清 Cookie。
 */
@Component
export struct NativePluginHostView {
  @Prop pluginName: string = '';
  @Prop documentJson: string = '{}';
  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @State private renderMode: string = 'vuetify';
  @State private fields: PluginFieldPlan[] = [];
  @State private draftModel: Record<string, Object> = {};
  private originalModelJson: string = '{}';
  private webController: webview.WebviewController = new webview.WebviewController();
  onSaveFullModel: (fullJson: string) => void = () => {};

  aboutToAppear(): void {
    try {
      const planned = JSON.parse(RustCoreBridge.planPluginFormJson(this.documentJson)) as Record<string, Object>;
      this.renderMode = (planned['renderMode'] as string) ?? 'vuetify';
      this.fields = (planned['fields'] as PluginFieldPlan[]) ?? [];
      const modelObj = (planned['model'] as Record<string, Object>) ?? {};
      this.originalModelJson = JSON.stringify(modelObj);
      this.draftModel = modelObj;
    } catch {
      this.fields = [];
    }
  }

  aboutToDisappear(): void {
    if (this.renderMode === 'vue') {
      try {
        webview.WebCookieManager.clearAllCookiesSync();
      } catch {
        // 清理受控隔离宿主残留 Cookie
      }
    }
  }

  build() {
    if (this.renderMode === 'vue') {
      Web({ src: `${this.serverUrl}/#/plugins/${this.pluginName}`, controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onLoadIntercept((ev) => {
          const target = ev.data.getRequestUrl();
          return !target.startsWith(this.serverUrl);
        })
        .width('100%')
        .height('100%')
    } else {
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.fields.filter((f) => f.visible), (field: PluginFieldPlan) => {
            if (field.component === 'VSwitch' || field.component === 'VCheckbox') {
              CinematicPanel({ panelPadding: 14 }) {
                Row() {
                  Text(field.label || field.modelKey || '开关')
                    .fontSize(15)
                    .fontColor(Color.White)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: Boolean(this.draftModel[field.modelKey ?? '']) })
                    .selectedColor('#9E7AF5')
                    .onChange((v: boolean) => {
                      if (field.modelKey) { this.draftModel[field.modelKey] = v; }
                    })
                }.width('100%')
              }
            } else if (field.component === 'VCronField') {
              CinematicPanel({ panelPadding: 14 }) {
                Column({ space: 8 }) {
                  Row() {
                    Text(field.label || '定时周期 (Cron)').fontSize(14).fontColor(Color.White).layoutWeight(1)
                    NativeAdaptiveBadge({ text: RustCoreBridge.analyzeCron(String(this.draftModel[field.modelKey ?? ''] ?? '')).descriptionZh })
                  }.width('100%')
                  TextInput({ text: String(this.draftModel[field.modelKey ?? ''] ?? '*/15 * * * *') })
                    .fontColor(Color.White)
                    .backgroundColor('#18FFFFFF')
                    .onChange((val: string) => {
                      if (field.modelKey) { this.draftModel[field.modelKey] = val; }
                    })
                  Row({ space: 8 }) {
                    NativeAdaptivePill({ title: '每15分', selected: false, onTap: () => { if (field.modelKey) { this.draftModel[field.modelKey] = '*/15 * * * *'; } } })
                    NativeAdaptivePill({ title: '每天9点', selected: false, onTap: () => { if (field.modelKey) { this.draftModel[field.modelKey] = '0 9 * * *'; } } })
                  }
                }.width('100%')
              }
            } else if (field.component === 'VAlert') {
              CinematicPanel({ panelPadding: 14 }) {
                Text(field.text || field.label).fontSize(13).fontColor('#75C7FF')
              }
            } else {
              CinematicPanel({ panelPadding: 14 }) {
                Column({ space: 6 }) {
                  Text(field.label || field.modelKey || field.component).fontSize(14).fontColor(Color.White)
                  TextInput({ text: String(this.draftModel[field.modelKey ?? ''] ?? '') })
                    .fontColor(Color.White)
                    .backgroundColor('#18FFFFFF')
                    .onChange((val: string) => {
                      if (field.modelKey) { this.draftModel[field.modelKey] = val; }
                    })
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            }
          })

          Button('保存插件配置')
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor('#9E7AF5')
            .fontColor(Color.White)
            .onClick(() => {
              const merged = RustCoreBridge.applyPluginFormPatch(this.originalModelJson, JSON.stringify(this.draftModel));
              this.onSaveFullModel(merged);
            })
        }
        .padding({ left: 16, right: 16, top: 10, bottom: 28 })
      }
    }
  }
}
