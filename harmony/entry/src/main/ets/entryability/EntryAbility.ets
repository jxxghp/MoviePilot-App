import { UIAbility, Want, AbilityConstant, Configuration, ConfigurationConstant, common } from '@kit.AbilityKit';
import { display, window, KeyboardAvoidMode } from '@kit.ArkUI';
import { HarmonyAdaptiveLayout, HarmonyAppearanceStore } from '@moviepilot/design_system';
import { RustCoreBridge, NativeHuksStore } from '@moviepilot/core_rust_bridge';

/**
 * MoviePilot HarmonyOS NEXT / HarmonyOS 7 主 EntryAbility：
 * - 初始化 `NativeHuksStore` 安全凭据与持久化存储，开启 `KeyboardAvoidMode.RESIZE` 软键盘避让；
 * - 实时追踪窗口宽高（vp）与多端自适应断点（`sm / md / lg`）；
 * - 拦截并分发 `moviepilot://` 深度链接、桌面卡片路由参数与音视频文件直放请求。
 */
export default class EntryAbility extends UIAbility {
  private static mainWin: window.Window | null = null;
  private static appCtx: common.UIAbilityContext | null = null;
  static storeInitPromise: Promise<void> | null = null;

  static syncWindowAppearance(isDark: boolean): void {
    try {
      if (EntryAbility.mainWin) {
        const contentColor = isDark ? '#FFFFFF' : '#182431';
        EntryAbility.mainWin.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: contentColor,
          navigationBarColor: '#00000000',
          navigationBarContentColor: contentColor
        });
      }
      if (EntryAbility.appCtx) {
        EntryAbility.appCtx.getApplicationContext().setColorMode(
          isDark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        );
      }
    } catch {
      // ignore system bar sync error on unsupported targets
    }
  }

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    HarmonyAppearanceStore.initDefaults();
    EntryAbility.appCtx = this.context;
    EntryAbility.storeInitPromise = NativeHuksStore.shared().init(this.context);
    this.syncSystemColorMode(this.context.config.colorMode);
    EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
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

  private updateWindowMetricsFromPx(widthPx: number, heightPx: number = 0): void {
    try {
      const disp = display.getDefaultDisplaySync();
      const density = disp.densityPixels > 0 ? disp.densityPixels : 3;
      const widthVp = Math.round(widthPx / density);
      const bp = HarmonyAdaptiveLayout.resolveBreakpoint(widthVp);
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP, widthVp);
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BREAKPOINT, bp);
      if (heightPx > 0) {
        const heightVp = Math.round(heightPx / density);
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP, heightVp);
      }
    } catch {
      // ignore display query failure
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const syncWin = windowStage.getMainWindowSync();
      if (syncWin) {
        EntryAbility.mainWin = syncWin;
        syncWin.setWindowLayoutFullScreen(true).catch(() => {});
        EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
      }
    } catch {
      // fallback to async main window
    }
    windowStage.loadContent('pages/Index', () => {
      windowStage.getMainWindow((err, win) => {
        if (!err && win) {
          EntryAbility.mainWin = win;
          try {
            win.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
          } catch {
            // ignore keyboard avoid mode error on older runtimes
          }
          try {
            win.setWindowLayoutFullScreen(true).then(() => {
              EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
            }).catch(() => {});
            EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
            const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
            AppStorage.setOrCreate('mp_top_avoid_px', avoid.topRect.height);
            AppStorage.setOrCreate('mp_bottom_avoid_px', avoid.bottomRect.height);
            const props = win.getWindowProperties();
            if (props && props.windowRect && props.windowRect.width > 0) {
              this.updateWindowMetricsFromPx(props.windowRect.width, props.windowRect.height);
            }
            win.on('windowSizeChange', (size: window.Size) => {
              if (size && size.width > 0) {
                this.updateWindowMetricsFromPx(size.width, size.height);
              }
            });
          } catch {
            // ignore avoid area or listener setup failure
          }
        }
      });
    });
  }

  private handleIncomingWant(want: Want): void {
    let rawTarget = want.uri ?? '';
    if (rawTarget.length === 0 && want.parameters && want.parameters['uri'] !== undefined) {
      rawTarget = String(want.parameters['uri']);
    }
    if (!rawTarget) { return; }
    if (rawTarget.startsWith('moviepilot://')) {
      AppStorage.setOrCreate('mp_pending_deeplink', RustCoreBridge.parseDeepLinkJson(rawTarget));
    } else if (RustCoreBridge.detectPlayableMediaKind(rawTarget, true).length > 0) {
      AppStorage.setOrCreate('mp_pending_media_uri', rawTarget);
    }
  }
}
