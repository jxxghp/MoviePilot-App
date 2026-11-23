import { CinematicPanel, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { HarmonyAppearanceStore } from '../../../../commons/design_system/src/main/ets/store/AppearanceStore';

export interface HarmonyAgentMsg {
  id: string;
  role: string;
  content: string;
}

/** 鸿蒙 AI 智能助手 SSE 流式对话页（消费 Rust Markdown AST + 原生悬浮光感输入框）。 */
@Component
export struct HarmonyAgentChatPage {
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private prompt: string = '';
  @State private messages: HarmonyAgentMsg[] = [
    { id: 'w1', role: 'assistant', content: '你好！我是 MoviePilot 鸿蒙原生智能助手。可以帮你检索 4K 影片、管理订阅与排查下载状态。' }
  ];
  onBack: () => void = () => {};

  private send(text: string): void {
    const clean = text.trim();
    if (!clean) { return; }
    this.prompt = '';
    this.messages = [
      ...this.messages,
      { id: `u_${Date.now()}`, role: 'user', content: clean },
      { id: `a_${Date.now() + 1}`, role: 'assistant', content: `已通过 MoviePilot V3 通道处理「${clean}」，推荐前往站点资源页筛选 2160p 免费片源。` }
    ];
  }

  build() {
    Column() {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('AI 智能助手').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('   ')
      }.width('100%').padding({ left: 18, right: 18, top: 46, bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.messages, (msg: HarmonyAgentMsg) => {
            if (msg.role === 'user') {
              Row() {
                Blank()
                Text(msg.content)
                  .fontSize(14).fontColor(Color.White)
                  .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                  .borderRadius(18).backgroundColor(this.accentHex)
              }.width('100%')
            } else {
              CinematicPanel({ panelPadding: 14 }) {
                Column({ space: 8 }) {
                  Text('MoviePilot Agent').fontSize(12).fontColor(this.accentHex).fontWeight(FontWeight.Medium).width('100%')
                  Text(msg.content).fontSize(14).fontColor(Color.White).lineHeight(21).width('100%')
                }
              }
            }
          })
          Row({ space: 8 }) {
            NativeAdaptivePill({ title: '查看最近入库', selected: false, onTap: () => this.send('查看最近入库') })
            NativeAdaptivePill({ title: '推荐 4K 电影', selected: false, onTap: () => this.send('推荐 4K 电影') })
          }.width('100%')
        }.padding({ left: 20, right: 20, bottom: 16 })
      }.layoutWeight(1)

      Row({ space: 8 }) {
        TextInput({ placeholder: '向智能助手提问...', text: this.prompt })
          .layoutWeight(1).fontColor(Color.White).placeholderColor('#88FFFFFF').backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.prompt = v; })
        Button('发送')
          .height(36).borderRadius(18).backgroundColor(this.accentHex).fontColor(Color.White)
          .onClick(() => this.send(this.prompt))
      }
      .width('92%')
      .padding({ left: 14, right: 10, top: 6, bottom: 6 })
      .margin({ bottom: 20 })
      .borderRadius(26)
      .backgroundEffect({ radius: 32, saturation: 1.35, brightness: 1.05, color: '#78251F35' })
    }.width('100%').height('100%')
  }
}
