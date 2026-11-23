import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { HarmonyAppearanceStore } from '../../../commons/design_system/src/main/ets/store/AppearanceStore';
import { RustCoreBridge } from '../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';

/**
 * MoviePilot HarmonyOS NEXT 主 EntryAbility：
 * 开启全局全屏沉浸式布局（`setWindowLayoutFullScreen(true)`）+ 系统避让区感知，
 * 拦截并分发 `moviepilot://` 深度链接与未登录可直放的系统音视频文件打开请求。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    HarmonyAppearanceStore.initDefaults();
    this.handleIncomingWant(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.handleIncomingWant(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((err, win) => {
      if (!err && win) {
        win.setWindowLayoutFullScreen(true);
        const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        AppStorage.setOrCreate('mp_top_avoid_px', avoid.topRect.height);
        AppStorage.setOrCreate('mp_bottom_avoid_px', avoid.bottomRect.height);
      }
    });
    windowStage.loadContent('pages/Index');
  }

  private handleIncomingWant(want: Want): void {
    const uri = want.uri ?? '';
    if (!uri) { return; }
    if (uri.startsWith('moviepilot://')) {
      AppStorage.setOrCreate('mp_pending_deeplink', RustCoreBridge.parseDeepLinkJson(uri));
    } else if (RustCoreBridge.detectPlayableMediaKind(uri, true).length > 0) {
      AppStorage.setOrCreate('mp_pending_media_uri', uri);
    }
  }
}
