import { CinematicPanel, NativeAdaptiveBadge } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { HarmonyMediaItem } from '../../../discover/src/main/ets/DiscoverPages';
import { HarmonyPlaybackRequest } from '../../../../commons/media_player/src/main/ets/NativeMediaPlayerView';

/** 鸿蒙沉浸式影视/剧集详情页（支持一键订阅、资源搜索与原生直放）。 */
@Component
export struct HarmonyMediaDetailPage {
  @Prop item: HarmonyMediaItem = { id: '101', title: '奥德赛', year: '2026', type: '电影', overview: '', vote: 8.4, source: 'themoviedb', inLibrary: true };
  @State private subscribed: boolean = false;
  onBack: () => void = () => {};
  onSearchResource: (kw: string) => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          Column()
            .width('100%')
            .height(340)
            .linearGradient({ angle: 165, colors: [['#543F7A', 0], ['#2D223F', 0.75], ['#30334A', 1]] })
          Button('‹ 返回')
            .backgroundColor('#44000000')
            .fontColor(Color.White)
            .position({ left: 16, top: 44 })
            .onClick(() => this.onBack())
          Column({ space: 6 }) {
            Text(this.item.title).fontSize(26).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Row({ space: 8 }) {
              NativeAdaptiveBadge({ text: this.item.type, tintHex: '#9E7AF5', filled: true })
              NativeAdaptiveBadge({ text: this.item.year })
              NativeAdaptiveBadge({ text: `★ ${this.item.vote.toFixed(1)}`, tintHex: '#FFC845' })
            }
          }.padding(20)
        }

        Row({ space: 10 }) {
          Button(this.subscribed ? '已订阅 ✓' : '添加订阅')
            .layoutWeight(1)
            .height(46)
            .borderRadius(23)
            .backgroundColor(this.subscribed ? '#34D058' : '#9E7AF5')
            .fontColor(Color.White)
            .onClick(() => { this.subscribed = true; })
          Button('搜索资源')
            .layoutWeight(1)
            .height(46)
            .borderRadius(23)
            .backgroundColor('#22FFFFFF')
            .fontColor(Color.White)
            .onClick(() => this.onSearchResource(this.item.title))
        }.padding({ left: 20, right: 20 })

        if (this.item.inLibrary) {
          Button('立即原生播放')
            .width('90%')
            .height(46)
            .borderRadius(23)
            .backgroundColor(Color.White)
            .fontColor('#1C1A24')
            .onClick(() => this.onPlayMedia({
              url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
              title: this.item.title,
              subtitle: `${this.item.year} · ${this.item.type}`,
              isAudio: false
            }))
        }

        CinematicPanel({ panelPadding: 16 }) {
          Column({ space: 8 }) {
            Text('简介').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Text(this.item.overview || '暂无剧情简介，可添加自动追剧订阅或检索 4K 高清片源。')
              .fontSize(14).fontColor('#CCFFFFFF').lineHeight(21)
          }.alignItems(HorizontalAlign.Start)
        }.padding({ left: 20, right: 20 })
      }.padding({ bottom: 120 })
    }
    .width('100%')
    .height('100%')
  }
}
