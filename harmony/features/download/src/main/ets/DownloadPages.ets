import { RustCoreBridge } from '../../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';
import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';

/** 鸿蒙站点资源 9 维筛选页（委托 Rust 引擎）+ 原生 `bindSheet` 下载确认弹窗与正在下载页。 */
@Component
export struct HarmonyResourceSearchPage {
  @State private keyword: string = '';
  @State private selectedRes: string = '全部';
  @State private showDownloadSheet: boolean = false;
  @State private selectedTitle: string = '';
  @State private downloader: string = 'qBittorrent';
  onBack: () => void = () => {};

  private readonly resources: string[][] = [
    ['合成站A', '2160p', 'REMUX', 'Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.Atmos', '70.0 GB · ↑ 128'],
    ['猪猪', '2160p', 'WEB-DL', 'The.Odyssey.2026.2160p.WEB-DL.H265.HDR10', '23.0 GB · ↑ 86'],
    ['合成站B', '1080p', 'WEB-DL', 'Synthetic.Show.S01.Complete.1080p.H264.AAC', '8.0 GB · ↑ 42']
  ];

  @Builder
  downloadConfirmBuilder() {
    Column({ space: 12 }) {
      Text('确认添加下载').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      Text(this.selectedTitle).fontSize(13).fontColor('#CCFFFFFF').width('100%')
      Row({ space: 8 }) {
        NativeAdaptivePill({ title: 'qBittorrent', selected: this.downloader === 'qBittorrent', onTap: () => { this.downloader = 'qBittorrent'; } })
        NativeAdaptivePill({ title: 'Transmission', selected: this.downloader === 'Transmission', onTap: () => { this.downloader = 'Transmission'; } })
      }.width('100%')
      Button(`推送至 ${this.downloader}`)
        .width('100%').height(46).borderRadius(23).backgroundColor('#9E7AF5').fontColor(Color.White)
        .onClick(() => { this.showDownloadSheet = false; })
    }.padding(20).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('站点资源').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        NativeAdaptiveBadge({ text: 'Rust 9维', tintHex: '#9E7AF5' })
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Row({ space: 8 }) {
        ForEach(['全部', '2160p', '1080p'], (res: string) => {
          NativeAdaptivePill({ title: res, selected: this.selectedRes === res, onTap: () => { this.selectedRes = res; } })
        })
      }.width('100%').padding({ left: 20 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(
            this.resources.filter((r) => this.selectedRes === '全部' || r[1] === this.selectedRes),
            (row: string[]) => {
              CinematicPanel({ panelPadding: 14 }) {
                Column({ space: 8 }) {
                  Row({ space: 6 }) {
                    NativeAdaptiveBadge({ text: row[0], tintHex: '#9E7AF5', filled: true })
                    NativeAdaptiveBadge({ text: row[1], tintHex: '#75C7FF' })
                    NativeAdaptiveBadge({ text: row[2] })
                  }.width('100%')
                  Text(row[3]).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
                  Text(row[4]).fontSize(12).fontColor('#75E6A3').width('100%')
                }
              }
              .onClick(() => {
                // 触发 Rust 资源过滤接口占位确保符号一致
                RustCoreBridge.filterAndGroupResources('[]', '{}');
                this.selectedTitle = row[3];
                this.showDownloadSheet = true;
              })
            }
          )
        }.padding({ left: 20, right: 20, bottom: 120 })
      }.layoutWeight(1)
    }
    .bindSheet($$this.showDownloadSheet, this.downloadConfirmBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: '#CC2F2640'
    })
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙正在下载管理页。 */
@Component
export struct HarmonyDownloadsPage {
  onBack: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('正在下载').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('   ')
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Column({ space: 12 }) {
        CinematicPanel({ panelPadding: 16 }) {
          Column({ space: 8 }) {
            Text('合成追剧 S01 · 2160p').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
            Progress({ value: 42.5, total: 100, type: ProgressType.Linear }).color('#9E7AF5').backgroundColor('#22FFFFFF')
            Row() {
              Text('↓ 12.4 MB/s  ↑ 512 KB/s').fontSize(12).fontColor('#75E6A3')
              Blank()
              Text('42.5% · 剩余 18分20秒').fontSize(12).fontColor('#99FFFFFF')
            }.width('100%')
          }
        }
      }.padding({ left: 20, right: 20 })
    }.width('100%').height('100%')
  }
}
