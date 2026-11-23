import { RustCoreBridge } from '../../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';
import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';

export interface HarmonySubscribeItem {
  id: number;
  name: string;
  year: string;
  type: string;
  total: number;
  lack: number;
  state: string;
}

/** 鸿蒙我的订阅页 + 原生 `bindSheet` 全量参数编辑弹窗 + 追剧日历。 */
@Component
export struct HarmonySubscriptionsPage {
  @State private filter: string = '全部';
  @State private showEditor: boolean = false;
  @State private editingName: string = '';
  @State private editResolution: string = '2160p';
  @State private editSavePath: string = '/media/auto';
  @State private items: HarmonySubscribeItem[] = [
    { id: 701, name: '合成订阅电影', year: '2025', type: '电影', total: 0, lack: 0, state: 'R' },
    { id: 702, name: '合成追剧 S01', year: '2025', type: '电视剧', total: 12, lack: 3, state: 'R' },
    { id: 703, name: '范特西 (Hi-Res)', year: '2001', type: '音乐', total: 0, lack: 0, state: 'R' }
  ];
  onBack: () => void = () => {};

  @Builder
  editorSheetBuilder() {
    Column({ space: 12 }) {
      Text(`编辑订阅：${this.editingName}`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      TextInput({ placeholder: '分辨率（如 2160p）', text: this.editResolution })
        .fontColor(Color.White).backgroundColor('#1AFFFFFF')
        .onChange((v: string) => { this.editResolution = v; })
      TextInput({ placeholder: '保存目录', text: this.editSavePath })
        .fontColor(Color.White).backgroundColor('#1AFFFFFF')
        .onChange((v: string) => { this.editSavePath = v; })
      Button('保存订阅参数')
        .width('100%').height(46).borderRadius(23).backgroundColor('#9E7AF5').fontColor(Color.White)
        .onClick(() => { this.showEditor = false; })
    }.padding(20).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('我的订阅').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('   ')
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Row({ space: 8 }) {
        ForEach(['全部', '电影', '电视剧', '音乐'], (tab: string) => {
          NativeAdaptivePill({ title: tab, selected: this.filter === tab, onTap: () => { this.filter = tab; } })
        })
      }.width('100%').padding({ left: 20 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(
            this.items.filter((i) => this.filter === '全部' || i.type === this.filter),
            (sub: HarmonySubscribeItem) => {
              CinematicPanel({ panelPadding: 14 }) {
                Column({ space: 8 }) {
                  Row() {
                    Text(sub.name).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White).layoutWeight(1)
                    NativeAdaptiveBadge({ text: sub.state === 'S' ? '已暂停' : '订阅中', tintHex: sub.state === 'S' ? '#FFCC6B' : '#75E6A3' })
                  }.width('100%')
                  Text(`${sub.year} · ${sub.type}`).fontSize(12).fontColor('#B8FFFFFF').width('100%')
                  if (sub.total > 0) {
                    Text(`进度：${RustCoreBridge.computeSubscribeProgress(sub.total, sub.lack).label}`)
                      .fontSize(12).fontColor('#9E7AF5').width('100%')
                    Progress({
                      value: RustCoreBridge.computeSubscribeProgress(sub.total, sub.lack).completed,
                      total: sub.total,
                      type: ProgressType.Linear
                    }).color('#9E7AF5').backgroundColor('#22FFFFFF')
                  }
                }
              }
              .onClick(() => {
                this.editingName = sub.name;
                this.showEditor = true;
              })
            }
          )
        }.padding({ left: 20, right: 20, bottom: 120 })
      }.layoutWeight(1)
    }
    .bindSheet($$this.showEditor, this.editorSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: '#CC2F2640'
    })
    .width('100%')
    .height('100%')
  }
}
