import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { GeneratedDesignTokens } from '../../../../commons/design_system/src/main/ets/tokens/GeneratedTokens';
import { HarmonyAppearanceStore } from '../../../../commons/design_system/src/main/ets/store/AppearanceStore';

/**
 * 鸿蒙「我的」无大标题仪表盘（1:1 复刻 iOS 黄金截图 + 原生 `bindSheet` 消息中心与捷径诊断入口）：
 * 2×2 媒体库统计、存储空间环形进度条、下载器绿↓蓝↑双速子卡与 7 天整理趋势。
 */
@Component
export struct HarmonyDashboardPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private showMessagesSheet: boolean = false;
  onOpenShortcuts: () => void = () => {};

  @Builder
  messagesSheetBuilder() {
    Column({ space: 12 }) {
      Text('消息中心').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      CinematicPanel({ panelPadding: 14 }) {
        Column({ space: 4 }) {
          Text('整理入库成功').fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White)
          Text('《奥德赛》2160p REMUX 已完成刮削并刷新 Emby 媒体库。').fontSize(12).fontColor('#CCFFFFFF')
        }.alignItems(HorizontalAlign.Start)
      }
      CinematicPanel({ panelPadding: 14 }) {
        Column({ space: 4 }) {
          Text('订阅命中推送').fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White)
          Text('《合成追剧 S01E09》已自动推送至 qBittorrent。').fontSize(12).fontColor('#CCFFFFFF')
        }.alignItems(HorizontalAlign.Start)
      }
    }.padding(20).width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        // 顶部右上角双图标光感胶囊
        Row() {
          Blank()
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.bell')).fontSize(20).fontColor([Color.White])
              .onClick(() => { this.showMessagesSheet = true; })
            SymbolGlyph($r('sys.symbol.bolt')).fontSize(20).fontColor([Color.White])
              .onClick(() => this.onOpenShortcuts())
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(20)
          .backgroundEffect({ radius: 28, saturation: 1.3, brightness: 1.05, color: '#60251E35' })
        }
        .width('100%')
        .margin({ top: 44 })
        .bindSheet($$this.showMessagesSheet, this.messagesSheetBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          blurStyle: BlurStyle.COMPONENT_THIN,
          dragBar: true,
          backgroundColor: '#CC2F2640'
        })

        // 1. 媒体库统计 2×2
        Text('媒体库统计').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
        Row({ space: 12 }) {
          CinematicPanel({ panelPadding: 15 }) {
            Column({ space: 6 }) {
              Text('776').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('电影').fontSize(12).fontColor('#B8FFFFFF')
              NativeAdaptiveBadge({ text: '本月 +9', tintHex: '#FFCC6B' })
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)
          CinematicPanel({ panelPadding: 15 }) {
            Column({ space: 6 }) {
              Text('1,268').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('剧集').fontSize(12).fontColor('#B8FFFFFF')
              NativeAdaptiveBadge({ text: '本月 +49', tintHex: '#D6BDFF' })
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)
        }
        Row({ space: 12 }) {
          CinematicPanel({ panelPadding: 15 }) {
            Column({ space: 6 }) {
              Text('31,532').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('剧集单集').fontSize(12).fontColor('#B8FFFFFF')
              NativeAdaptiveBadge({ text: '本月 +792', tintHex: '#75D6E6' })
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)
          CinematicPanel({ panelPadding: 15 }) {
            Column({ space: 6 }) {
              Text('128').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('音乐').fontSize(12).fontColor('#B8FFFFFF')
              NativeAdaptiveBadge({ text: '本月 +14', tintHex: '#F58FBD' })
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)
        }

        // 2. 存储空间环形进度卡
        Text('存储空间').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
        CinematicPanel({ panelPadding: 16 }) {
          Row({ space: 18 }) {
            Stack() {
              Progress({ value: 76.6, total: 100, type: ProgressType.Ring })
                .width(86).height(86).color(this.accentHex).backgroundColor('#22FFFFFF')
                .style({ strokeWidth: 9 })
              Text('76.6%').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
            }
            Column({ space: 4 }) {
              Text('26.47 TB / 34.56 TB').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text('已用 / 总容量').fontSize(12).fontColor('#B8FFFFFF')
              Text('剩余 8.08 TB').fontSize(13).fontColor(GeneratedDesignTokens.semanticColor('success', this.isDark))
            }.alignItems(HorizontalAlign.Start)
          }.width('100%')
        }

        // 3. 下载器双速卡片
        Text('下载器').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
        CinematicPanel({ panelPadding: 16 }) {
          Column({ space: 10 }) {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('↓ 12.4 MB/s').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#75E6A3')
                Text('实时下载').fontSize(11).fontColor('#99FFFFFF')
              }
              .layoutWeight(1).padding(12).borderRadius(14).backgroundColor('#18FFFFFF').alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Text('↑ 21.0 KB/s').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#75C7FF')
                Text('实时上传').fontSize(11).fontColor('#99FFFFFF')
              }
              .layoutWeight(1).padding(12).borderRadius(14).backgroundColor('#18FFFFFF').alignItems(HorizontalAlign.Start)
            }
            Text('累计下载 3.93 TB').fontSize(12).fontColor('#99FFFFFF').width('100%')
          }
        }
      }
      .padding({ left: 20, right: 20, bottom: 128 })
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙捷径与诊断中心页（健康检查 / 名称识别 / 实时日志 / 定时服务 / 词表）。 */
@Component
export struct HarmonyDiagnosticsPage {
  @State private tab: string = '健康检查';
  onBack: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('捷径与诊断中心').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('   ')
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(['健康检查', '名称识别', '实时日志', '定时服务', '词表规则'], (t: string) => {
            NativeAdaptivePill({ title: t, selected: this.tab === t, onTap: () => { this.tab = t; } })
          })
        }.padding({ left: 20, right: 20 })
      }.scrollable(ScrollDirection.Horizontal)

      Column({ space: 10 }) {
        ForEach(['TheMovieDB 元数据模块', 'qBittorrent 下载器', 'Emby 媒体服务器', 'Rust ohos-rs 共享内核'], (m: string) => {
          CinematicPanel({ panelPadding: 14 }) {
            Row() {
              Text(m).fontSize(15).fontColor(Color.White).layoutWeight(1)
              NativeAdaptiveBadge({ text: '健康', tintHex: '#75E6A3' })
            }.width('100%')
          }
        })
      }.padding({ left: 20, right: 20 })
    }.width('100%').height('100%')
  }
}
