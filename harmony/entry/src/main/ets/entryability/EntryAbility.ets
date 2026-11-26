import { UIAbility, Want, AbilityConstant, Configuration, ConfigurationConstant, common } from '@kit.AbilityKit';
import { display, window, KeyboardAvoidMode } from '@kit.ArkUI';
import { HarmonyAdaptiveLayout, HarmonyAppearanceStore, PlaybackPreferencesStore } from '@moviepilot/design_system';
import { RustCoreBridge, NativeHuksStore, CloudflareAccessOAuthManager } from '@moviepilot/core_rust_bridge';
import { HarmonyWidgetSyncService } from '../widget/HarmonyWidgetSyncService';

/**
 * MoviePilot HarmonyOS NEXT / HarmonyOS 7 主 EntryAbility：
 * - 初始化 `NativeHuksStore` 安全凭据与持久化存储，开启 `KeyboardAvoidMode.RESIZE` 软键盘避让；
 * - 实时追踪窗口宽高（vp）与多端自适应断点（`sm / md / lg`）；
 * - 拦截并分发 `moviepilot://` 深度链接、桌面卡片路由参数与音视频文件直放请求。
 */
export default class EntryAbility extends UIAbility {
  private static mainWin: window.Window | null = null;
  static mainWindow: window.Window | null = null;
  private static appCtx: common.UIAbilityContext | null = null;
  static storeInitPromise: Promise<void> | null = null;

  static syncWindowAppearance(isDark: boolean): void {
    try {
      const win = EntryAbility.mainWindow ?? EntryAbility.mainWin;
      if (win) {
        try {
          win.setWindowBackgroundColor(isDark ? '#000000' : '#F4F6FA');
        } catch {
          // ignore window background color sync error on unsupported targets
        }
        const contentColor = isDark ? '#FFFFFF' : '#182431';
        win.setWindowSystemBarProperties({
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
    HarmonyAppearanceStore.ensureAppStorageDefaults();
    PlaybackPreferencesStore.ensureAppStorageDefaults();
    EntryAbility.appCtx = this.context;
    EntryAbility.storeInitPromise = Promise.all([
      NativeHuksStore.shared().init(this.context),
      PlaybackPreferencesStore.init(this.context)
    ]).then(() => {
      HarmonyWidgetSyncService.shared().syncAll(this.context).catch(() => {});
    });
    this.syncSystemColorMode(this.context.config.colorMode);
    EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
    this.handleIncomingWant(want);
  }

  onForeground(): void {
    HarmonyWidgetSyncService.shared().syncAll(this.context).catch(() => {});
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

  private pxToVp(px: number, win?: window.Window | null): number {
    if (!Number.isFinite(px) || px <= 0) {
      return 0;
    }
    if (win) {
      try {
        const vpVal = win.getUIContext().px2vp(px);
        if (Number.isFinite(vpVal) && vpVal > 0) {
          return Math.round(vpVal);
        }
      } catch {
        // UIContext 尚未就绪时回退至屏幕像素密度换算
      }
    }
    try {
      const disp = display.getDefaultDisplaySync();
      const density = disp.densityPixels > 0 ? disp.densityPixels : 3;
      return Math.round(px / density);
    } catch {
      return Math.round(px / 3);
    }
  }

  private updateWindowMetricsFromPx(widthPx: number, heightPx: number = 0, win?: window.Window | null): void {
    try {
      const widthVp = this.pxToVp(widthPx, win);
      if (widthVp > 0) {
        const bp = HarmonyAdaptiveLayout.resolveBreakpoint(widthVp);
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP, widthVp);
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BREAKPOINT, bp);
      }
      if (heightPx > 0) {
        const heightVp = this.pxToVp(heightPx, win);
        if (heightVp > 0) {
          AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP, heightVp);
        }
      }
    } catch {
      // ignore display query failure
    }
  }

  private updateAvoidAreas(win: window.Window): void {
    try {
      const types: window.AvoidAreaType[] = [
        window.AvoidAreaType.TYPE_SYSTEM,
        window.AvoidAreaType.TYPE_CUTOUT,
        window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR
      ];
      let topPx = 0;
      let bottomPx = 0;
      let leftPx = 0;
      let rightPx = 0;
      for (let i = 0; i < types.length; i++) {
        try {
          const area = win.getWindowAvoidArea(types[i]);
          if (area) {
            topPx = Math.max(topPx, area.topRect ? area.topRect.height : 0);
            bottomPx = Math.max(bottomPx, area.bottomRect ? area.bottomRect.height : 0);
            leftPx = Math.max(leftPx, area.leftRect ? area.leftRect.width : 0);
            rightPx = Math.max(rightPx, area.rightRect ? area.rightRect.width : 0);
          }
        } catch {
          // ignore unsupported avoid area type on older runtimes
        }
      }
      AppStorage.setOrCreate('mp_top_avoid_px', topPx);
      AppStorage.setOrCreate('mp_bottom_avoid_px', bottomPx);
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SAFE_TOP_VP, this.pxToVp(topPx, win));
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP, this.pxToVp(bottomPx, win));
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP, this.pxToVp(leftPx, win));
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP, this.pxToVp(rightPx, win));
    } catch {
      // ignore avoid area query failure
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const syncWin = windowStage.getMainWindowSync();
      if (syncWin) {
        EntryAbility.mainWin = syncWin;
        EntryAbility.mainWindow = syncWin;
        const isDarkInit = AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true;
        try {
          syncWin.setWindowBackgroundColor(isDarkInit ? '#000000' : '#F4F6FA');
        } catch {
          // ignore window background color error
        }
        syncWin.setWindowLayoutFullScreen(true).catch(() => {});
        EntryAbility.syncWindowAppearance(isDarkInit);
        const syncProps = syncWin.getWindowProperties();
        if (syncProps && syncProps.windowRect && syncProps.windowRect.width > 0) {
          this.updateWindowMetricsFromPx(syncProps.windowRect.width, syncProps.windowRect.height, syncWin);
        }
        this.updateAvoidAreas(syncWin);
      }
    } catch {
      // fallback to async main window
    }
    windowStage.loadContent('pages/Index', () => {
      windowStage.getMainWindow((err, win) => {
        if (!err && win) {
          EntryAbility.mainWin = win;
          EntryAbility.mainWindow = win;
          try {
            win.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
          } catch {
            // ignore keyboard avoid mode error on older runtimes
          }
          try {
            win.setWindowLayoutFullScreen(true).then(() => {
              EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
              this.updateAvoidAreas(win);
            }).catch(() => {});
            EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
            const props = win.getWindowProperties();
            if (props && props.windowRect && props.windowRect.width > 0) {
              this.updateWindowMetricsFromPx(props.windowRect.width, props.windowRect.height, win);
            }
            this.updateAvoidAreas(win);
            win.on('windowSizeChange', (size: window.Size) => {
              if (size && size.width > 0) {
                this.updateWindowMetricsFromPx(size.width, size.height, win);
                this.updateAvoidAreas(win);
              }
            });
            win.on('avoidAreaChange', (_opts: window.AvoidAreaOptions) => {
              this.updateAvoidAreas(win);
            });
          } catch {
            // ignore avoid area or listener setup failure
          }
        }
      });
    });
  }

  private handleIncomingWant(want: Want): void {
    const params = want.parameters;
    if (params) {
      const audioCmd = params['audioCmd'] !== undefined ? String(params['audioCmd']).trim() : '';
      const widgetAction = params['widgetAction'] !== undefined ? String(params['widgetAction']).trim() : '';
      const pluginId = params['pluginId'] !== undefined ? String(params['pluginId']).trim() : '';
      const widgetKey = params['widgetKey'] !== undefined ? String(params['widgetKey']).trim() : '';
      if (audioCmd.length > 0 || widgetAction.length > 0) {
        const eventPayload: Record<string, Object> = {
          'kind': audioCmd.length > 0 ? 'audio' : 'widget',
          'type': audioCmd.length > 0 ? 'nowPlaying' : 'pluginAction',
          'command': audioCmd.length > 0 ? audioCmd : widgetAction,
          'actionId': widgetAction.length > 0 ? widgetAction : audioCmd,
          'pluginId': pluginId,
          'widgetKey': widgetKey,
          'timestamp': Date.now()
        };
        AppStorage.setOrCreate('mp_pending_widget_plugin_event', JSON.stringify(eventPayload));
        if (audioCmd.length > 0) {
          HarmonyWidgetSyncService.shared().applyNowPlayingCommand(this.context, audioCmd, pluginId).catch(() => {});
        }
      }
    }

    let rawTarget = want.uri ?? '';
    if (rawTarget.length === 0 && params) {
      if (params['uri'] !== undefined) {
        rawTarget = String(params['uri']);
      } else if (params['route'] !== undefined) {
        rawTarget = String(params['route']);
      } else if (params['pluginId'] !== undefined && String(params['pluginId']).trim().length > 0
        && params['audioCmd'] === undefined) {
        const pid = encodeURIComponent(String(params['pluginId']).trim());
        const surf = params['surface'] !== undefined && String(params['surface']).trim() === 'config'
          ? 'config'
          : 'data';
        rawTarget = `moviepilot://plugin/${pid}?surface=${surf}`;
      }
    }
    if (!rawTarget) { return; }
    if (rawTarget.toLowerCase().startsWith('moviepilot://oauth/')) {
      CloudflareAccessOAuthManager.shared().handleCallbackUrl(rawTarget);
      return;
    }
    if (rawTarget.startsWith('moviepilot-app://notification')) {
      const originMatch = /[?&]origin=([^&]+)/i.exec(rawTarget);
      const decodedOrigin = originMatch ? decodeURIComponent(originMatch[1]) : '';
      AppStorage.setOrCreate('mp_pending_deeplink_origin', decodedOrigin);
      AppStorage.setOrCreate('mp_pending_deeplink', RustCoreBridge.parseDeepLinkJson(rawTarget));
    } else if (rawTarget.startsWith('moviepilot://') || rawTarget.startsWith('/')) {
      const originParam = want.parameters && want.parameters['origin'] !== undefined
        ? String(want.parameters['origin'])
        : '';
      AppStorage.setOrCreate('mp_pending_deeplink_origin', originParam);
      AppStorage.setOrCreate('mp_pending_deeplink', RustCoreBridge.parseDeepLinkJson(rawTarget));
    } else if (RustCoreBridge.detectPlayableMediaKind(rawTarget, true).length > 0) {
      AppStorage.setOrCreate('mp_pending_media_uri', rawTarget);
    }
  }
}
