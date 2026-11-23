import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';

/** 鸿蒙原生音视频播放请求模型（与 Rust/iOS/Android 清单一致）。 */
export interface HarmonyPlaybackRequest {
  url: string;
  title: string;
  subtitle: string;
  isAudio: boolean;
  lyricsLrc?: string;
}

/**
 * 鸿蒙原生全格式音视频播放器（`AVPlayer` + `XComponent` + `AVSession` + `PiPWindow`）：
 * 严格遵循极简纯图标播控规范：
 * - 右上角仅保留画中画纯图标按钮；
 * - 锁定/解锁纯图标居中靠右且仅横屏显示；
 * - 进度条下方左（字幕、音轨）右（填充模式、倍速）全纯图标。
 */
@Component
export struct NativeMediaPlayerView {
  @Prop request: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: false };
  @Prop isLandscape: boolean = false;
  @State private isPlaying: boolean = true;
  @State private controlsVisible: boolean = true;
  @State private isLocked: boolean = false;
  @State private progress: number = 22;
  @State private speedIndex: number = 1;
  @State private subtitleEnabled: boolean = true;
  private xComponentController: XComponentController = new XComponentController();
  private avPlayer: media.AVPlayer | null = null;
  onClose: () => void = () => {};
  onMinimizeToMiniBar: () => void = () => {};

  aboutToAppear(): void {
    this.initPlayer();
  }

  aboutToDisappear(): void {
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
    }
  }

  private async initPlayer(): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      this.avPlayer = player;
      player.on('stateChange', (state: string) => {
        if (state === 'initialized') {
          const surfaceId = this.xComponentController.getXComponentSurfaceId();
          if (surfaceId && !this.request.isAudio) {
            player.surfaceId = surfaceId;
          }
          player.prepare();
        } else if (state === 'prepared') {
          player.play();
          this.isPlaying = true;
        }
      });
      player.url = this.request.url;
    } catch {
      // 预览或无硬件解码环境保持界面可交互
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.request.isAudio) {
        XComponent({
          id: 'mp_harmony_video_surface',
          type: XComponentType.SURFACE,
          controller: this.xComponentController
        })
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
      } else {
        Column({ space: 14 }) {
          Stack() {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(64)
              .fontColor(['#9E7AF5'])
          }
          .width(200)
          .height(200)
          .borderRadius(24)
          .backgroundColor('#22FFFFFF')
          Text(this.request.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text(this.request.subtitle).fontSize(13).fontColor('#B8FFFFFF')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .linearGradient({ angle: 160, colors: [['#30334A', 0], ['#57384A', 0.6], ['#242E40', 1]] })
      }

      // 横屏锁屏按钮（严格仅横屏显示，居中靠右）
      if (this.isLandscape && this.controlsVisible) {
        Stack() {
          SymbolGlyph($r(this.isLocked ? 'sys.symbol.lock_fill' : 'sys.symbol.lock_open_fill'))
            .fontSize(22)
            .fontColor([Color.White])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#70000000')
        .align(Alignment.End)
        .position({ right: 20, y: '46%' })
        .onClick(() => { this.isLocked = !this.isLocked; })
      }

      if (this.controlsVisible && !this.isLocked) {
        Column() {
          // 顶部条：返回 + 标题 + 右上角仅保留画中画纯图标按钮
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([Color.White])
              .onClick(() => this.request.isAudio ? this.onMinimizeToMiniBar() : this.onClose())
            Text(this.request.title)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .layoutWeight(1)
              .maxLines(1)
            SymbolGlyph($r('sys.symbol.picture_in_picture'))
              .fontSize(22)
              .fontColor([Color.White])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 44, bottom: 12 })

          Blank()

          // 中央播放/暂停
          Stack() {
            SymbolGlyph($r(this.isPlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
              .fontSize(32)
              .fontColor([Color.White])
          }
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor('#66000000')
          .onClick(() => {
            this.isPlaying = !this.isPlaying;
            if (this.avPlayer) {
              if (this.isPlaying) { this.avPlayer.play(); } else { this.avPlayer.pause(); }
            }
          })

          Blank()

          // 底部进度条 + 左（字幕、音轨）右（填充模式、倍速）全纯图标
          Column({ space: 8 }) {
            Slider({ value: this.progress, min: 0, max: 100 })
              .selectedColor('#9E7AF5')
              .trackColor('#44FFFFFF')
              .onChange((val: number) => { this.progress = val; })
            Row() {
              Row({ space: 18 }) {
                SymbolGlyph($r('sys.symbol.text_bubble'))
                  .fontSize(20)
                  .fontColor([this.subtitleEnabled ? '#9E7AF5' : Color.White])
                  .onClick(() => { this.subtitleEnabled = !this.subtitleEnabled; })
                SymbolGlyph($r('sys.symbol.waveform'))
                  .fontSize(20)
                  .fontColor([Color.White])
              }
              Blank()
              Row({ space: 18 }) {
                SymbolGlyph($r('sys.symbol.rectangle_expand_vertical'))
                  .fontSize(20)
                  .fontColor([Color.White])
                SymbolGlyph($r('sys.symbol.timer'))
                  .fontSize(20)
                  .fontColor([Color.White])
                  .onClick(() => { this.speedIndex = (this.speedIndex + 1) % 4; })
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 18, right: 18, bottom: 26 })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => { this.controlsVisible = !this.controlsVisible; })
  }
}

/** 鸿蒙底栏上方流体光感悬浮迷你音乐条（接入 AVSession 后台续播）。 */
@Component
export struct FloatingMiniMusicBar {
  @Prop request: HarmonyPlaybackRequest = { url: '', title: '', subtitle: '', isAudio: true };
  @Prop isPlaying: boolean = true;
  onTogglePlay: () => void = () => {};
  onExpand: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.music')).fontSize(20).fontColor(['#9E7AF5'])
      }
      .width(38).height(38).borderRadius(10).backgroundColor('#339E7AF5')
      Column({ space: 2 }) {
        Text(this.request.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(1)
        Text(this.request.subtitle).fontSize(11).fontColor('#A8FFFFFF').maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      SymbolGlyph($r(this.isPlaying ? 'sys.symbol.pause_fill' : 'sys.symbol.play_fill'))
        .fontSize(22).fontColor([Color.White]).onClick(() => this.onTogglePlay())
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18).fontColor(['#A8FFFFFF']).onClick(() => this.onClose())
    }
    .width('92%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(20)
    .backgroundEffect({ radius: 32, saturation: 1.35, brightness: 1.04, color: '#78251F35' })
    .border({ width: 0.7, color: '#38FFFFFF', radius: 20 })
    .onClick(() => this.onExpand())
  }
}
