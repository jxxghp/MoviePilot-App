import { UIAbility, Want, AbilityConstant, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { HarmonyAdaptiveLayout, HarmonyAppearanceStore } from '@moviepilot/design_system';
import { RustCoreBridge } from '@moviepilot/core_rust_bridge';

/**
 * MoviePilot HarmonyOS NEXT / HarmonyOS 7 主 EntryAbility：
 * - 开启全屏沉浸式布局（`setWindowLayoutFullScreen(true)`）与安全避让区感知；
 * - 实时追踪窗口宽度（vp）与折叠屏/平板/2in1 断点（`sm / md / lg`），驱动「一次开发、多端部署」导航转换；
 * - 跟随系统深浅色配置更新，拦截并分发 `moviepilot://` 深度链接与音视频文件直放请求。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    HarmonyAppearanceStore.initDefaults();
    this.syncSystemColorMode(this.context.config.colorMode);
    this.handleIncomingWant(want);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.handleIncomingWant(want);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncSystemColorMode(newConfig.colorMode);
  }

  private syncSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    const mode = AppStorage.get<string>(HarmonyAppearanceStore.KEY_MODE) ?? 'dark';
    if (mode === 'system' && colorMode !== undefined) {
      AppStorage.setOrCreate(
        HarmonyAppearanceStore.KEY_IS_DARK,
        colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      );
    }
  }

  private updateBreakpointFromPx(widthPx: number): void {
    try {
      const disp = display.getDefaultDisplaySync();
      const density = disp.densityPixels > 0 ? disp.densityPixels : 3;
      const widthVp = Math.round(widthPx / density);
      const bp = HarmonyAdaptiveLayout.resolveBreakpoint(widthVp);
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP, widthVp);
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BREAKPOINT, bp);
    } catch {
      // ignore display query failure
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((err, win) => {
      if (!err && win) {
        try {
          win.setWindowLayoutFullScreen(true);
          const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          AppStorage.setOrCreate('mp_top_avoid_px', avoid.topRect.height);
          AppStorage.setOrCreate('mp_bottom_avoid_px', avoid.bottomRect.height);
          const props = win.getWindowProperties();
          if (props && props.windowRect && props.windowRect.width > 0) {
            this.updateBreakpointFromPx(props.windowRect.width);
          }
          win.on('windowSizeChange', (size: window.Size) => {
            if (size && size.width > 0) {
              this.updateBreakpointFromPx(size.width);
            }
          });
        } catch {
          // ignore avoid area or listener setup failure
        }
      }
    });
    windowStage.loadContent('pages/Index', () => {});
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
