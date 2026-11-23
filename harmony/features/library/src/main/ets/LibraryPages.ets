import { RustCoreBridge } from '../../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';
import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { HarmonyPlaybackRequest } from '../../../../commons/media_player/src/main/ets/NativeMediaPlayerView';

/** 鸿蒙多存储文件管理与整理历史页：点击音视频直放原生播放器，长按唤起原生 `bindSheet` 手动整理弹窗。 */
@Component
export struct HarmonyLibraryPage {
  @State private mode: string = 'files';
  @State private storage: string = '本地存储';
  @State private showTransferSheet: boolean = false;
  @State private selectedFile: string = '';
  onBack: () => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  @Builder
  manualTransferBuilder() {
    Column({ space: 12 }) {
      Text('手动整理与智能重命名').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      Text(this.selectedFile).fontSize(13).fontColor('#CCFFFFFF').width('100%')
      Button('执行硬链接智能整理')
        .width('100%').height(46).borderRadius(23).backgroundColor('#9E7AF5').fontColor(Color.White)
        .onClick(() => { this.showTransferSheet = false; })
    }.padding(20).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text(this.mode === 'files' ? '文件管理' : '整理历史').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('   ')
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Row({ space: 8 }) {
        NativeAdaptivePill({ title: '文件管理', selected: this.mode === 'files', onTap: () => { this.mode = 'files'; } })
        NativeAdaptivePill({ title: '整理历史', selected: this.mode === 'history', onTap: () => { this.mode = 'history'; } })
      }.width('100%').padding({ left: 20 })

      Scroll() {
        Column({ space: 10 }) {
          if (this.mode === 'files') {
            ForEach(['Dune.Part.Two.2160p.mkv', 'Fantasy.24bit.flac', 'movies/'], (name: string) => {
              CinematicPanel({ panelPadding: 14 }) {
                Row() {
                  Text(name).fontSize(15).fontColor(Color.White).layoutWeight(1)
                  NativeAdaptiveBadge({ text: name.endsWith('/') ? '目录' : (RustCoreBridge.detectPlayableMediaKind(name) === 'audio' ? '音频' : '播放') })
                }.width('100%')
              }
              .onClick(() => {
                const kind = RustCoreBridge.detectPlayableMediaKind(name);
                if (kind) {
                  this.onPlayMedia({
                    url: kind === 'audio'
                      ? 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'
                      : 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                    title: name,
                    subtitle: this.storage,
                    isAudio: kind === 'audio'
                  });
                } else {
                  this.selectedFile = name;
                  this.showTransferSheet = true;
                }
              })
            })
          } else {
            CinematicPanel({ panelPadding: 14 }) {
              Column({ space: 6 }) {
                Row() {
                  Text('合成追剧 S01E08').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Color.White).layoutWeight(1)
                  NativeAdaptiveBadge({ text: '硬链接', tintHex: '#75E6A3' })
                }.width('100%')
                Text('源：/downloads/tv/syn-s01e08.mkv').fontSize(12).fontColor('#B8FFFFFF').width('100%')
                Text('至：/video/tv/合成追剧/Season 1/S01E08.mkv').fontSize(12).fontColor('#75C7FF').width('100%')
              }
            }
          }
        }.padding({ left: 20, right: 20, bottom: 120 })
      }.layoutWeight(1)
    }
    .bindSheet($$this.showTransferSheet, this.manualTransferBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: '#CC2F2640'
    })
    .width('100%')
    .height('100%')
  }
}
