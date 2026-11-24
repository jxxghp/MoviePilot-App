import { PiPWindow } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/** 画中画控制面板交互回调集合。 */
export interface HarmonyPipActionCallbacks {
  onTogglePlayPause: (shouldPlay?: boolean) => void;
  onNext: () => void;
  onPrevious: () => void;
  onFastForward: () => void;
  onFastBackward: () => void;
  onPipStateChanged: (active: boolean, stoppedWithoutRestore: boolean) => void;
}

/**
 * 鸿蒙原生视频画中画控制器（基于 `@kit.ArkUI` `PiPWindow`）：
 * - 绑定播放器 `XComponentController` 与 `PiPTemplateType.VIDEO_PLAY` 模板；
 * - 联动设置项 `mp_playback_auto_pip` 控制退后台自动启动画中画；
 * - 精确区分「从画中画恢复全屏」与「直接关闭画中画小窗」，避免切换小窗时误释放 `AVPlayer`。
 */
export class HarmonyPipController {
  private controller: PiPWindow.PiPController | null = null;
  private pipActive: boolean = false;
  private restoring: boolean = false;
  private callbacks: HarmonyPipActionCallbacks | null = null;

  /** 检测当前设备与系统窗口管理器是否支持画中画能力。 */
  static isSupported(): boolean {
    try {
      return PiPWindow.isPiPEnabled();
    } catch {
      return false;
    }
  }

  /** 当前是否处于画中画小窗启动中或运行中。 */
  isActive(): boolean {
    return this.pipActive;
  }

  /** 当前是否正从画中画恢复回主窗口。 */
  isRestoring(): boolean {
    return this.restoring;
  }

  /** 创建并绑定画中画控制器实例。 */
  async attach(
    context: common.BaseContext,
    xComponentController: XComponentController,
    hasEpisodeQueue: boolean,
    autoStart: boolean,
    videoWidth: number,
    videoHeight: number,
    callbacks: HarmonyPipActionCallbacks
  ): Promise<boolean> {
    if (!HarmonyPipController.isSupported()) {
      return false;
    }
    this.callbacks = callbacks;
    await this.destroy();
    try {
      const groups: PiPWindow.VideoPlayControlGroup[] = hasEpisodeQueue
        ? [PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT]
        : [PiPWindow.VideoPlayControlGroup.FAST_FORWARD_BACKWARD];
      const config: PiPWindow.PiPConfiguration = {
        context: context,
        componentController: xComponentController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: videoWidth > 0 ? Math.round(videoWidth) : 1920,
        contentHeight: videoHeight > 0 ? Math.round(videoHeight) : 1080,
        controlGroups: groups
      };
      const ctrl = await PiPWindow.create(config);
      this.controller = ctrl;
      ctrl.setAutoStartEnabled(autoStart);

      ctrl.on('stateChange', (state: PiPWindow.PiPState, _reason: string) => {
        if (state === PiPWindow.PiPState.ABOUT_TO_START || state === PiPWindow.PiPState.STARTED) {
          this.pipActive = true;
          this.restoring = false;
          this.callbacks?.onPipStateChanged(true, false);
        } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
          this.restoring = true;
          this.pipActive = false;
          this.callbacks?.onPipStateChanged(false, false);
        } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
          const stoppedWithoutRestore = !this.restoring;
          this.pipActive = false;
          this.restoring = false;
          this.callbacks?.onPipStateChanged(false, stoppedWithoutRestore);
        }
      });

      ctrl.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
        if (event === 'playbackStateChanged') {
          if (status === 1) {
            this.callbacks?.onTogglePlayPause(true);
          } else if (status === 0) {
            this.callbacks?.onTogglePlayPause(false);
          } else {
            this.callbacks?.onTogglePlayPause(undefined);
          }
        } else if (event === 'nextVideo') {
          this.callbacks?.onNext();
        } else if (event === 'previousVideo') {
          this.callbacks?.onPrevious();
        } else if (event === 'fastForward') {
          this.callbacks?.onFastForward();
        } else if (event === 'fastBackward') {
          this.callbacks?.onFastBackward();
        }
      });
      return true;
    } catch {
      this.controller = null;
      return false;
    }
  }

  /** 动态更新退后台自动进入画中画开关。 */
  setAutoStart(enabled: boolean): void {
    if (!this.controller) {
      return;
    }
    try {
      this.controller.setAutoStartEnabled(enabled);
    } catch {
      // ignore
    }
  }

  /** 同步视频原始宽高至画中画窗口比例。 */
  updateVideoSize(width: number, height: number): void {
    if (!this.controller || width <= 0 || height <= 0) {
      return;
    }
    try {
      this.controller.updateContentSize(Math.round(width), Math.round(height));
    } catch {
      // ignore
    }
  }

  /** 同步播放/暂停按钮状态至画中画小窗控制栏。 */
  updatePlayState(playing: boolean): void {
    if (!this.controller) {
      return;
    }
    try {
      this.controller.updatePiPControlStatus(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE
      );
    } catch {
      // ignore
    }
  }

  /** 手动触发开启画中画浮窗。 */
  async startManualPip(): Promise<boolean> {
    if (!this.controller) {
      return false;
    }
    try {
      await this.controller.startPiP();
      return true;
    } catch {
      return false;
    }
  }

  /** 停止画中画并解绑所有系统事件监听。 */
  async destroy(): Promise<void> {
    const prev = this.controller;
    this.controller = null;
    this.pipActive = false;
    this.restoring = false;
    if (!prev) {
      return;
    }
    try {
      prev.setAutoStartEnabled(false);
    } catch {
      // ignore
    }
    try {
      prev.off('stateChange');
      prev.off('controlPanelActionEvent');
    } catch {
      // ignore
    }
    try {
      await prev.stopPiP();
    } catch {
      // ignore when PiP is not currently shown
    }
  }
}
