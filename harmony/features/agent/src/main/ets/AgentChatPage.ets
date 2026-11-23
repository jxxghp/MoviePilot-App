import { MoviePilotRepository } from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeBackHeader,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

export interface HarmonyAgentMsg {
  id: string;
  role: string;
  content: string;
}

/** 鸿蒙 AI 智能助手对话页（HarmonyOS 7 动态光感 + 真实 `/api/v1/agent/chat` 流式响应）。 */
@Component
export struct HarmonyAgentChatPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @State private prompt: string = '';
  @State private sending: boolean = false;
  @State private messages: HarmonyAgentMsg[] = [];
  onBack: () => void = () => {};

  private readonly quickSkills: string[] = [
    '查看最近入库了哪些电影和剧集',
    '帮我检索豆瓣高分 4K 科幻电影',
    '检查当前下载器与订阅任务运行状态'
  ];

  private async send(text: string): Promise<void> {
    const clean = text.trim();
    if (!clean || this.sending) { return; }
    this.prompt = '';
    this.sending = true;
    const replyId = `a_${Date.now() + 1}`;
    this.messages = [
      ...this.messages,
      { id: `u_${Date.now()}`, role: 'user', content: clean },
      { id: replyId, role: 'assistant', content: '正在思考并调用 MoviePilot 工具…' }
    ];
    let acc = '';
    try {
      const repo = MoviePilotRepository.shared();
      await repo.transport.streamAgentSse(repo.baseUrl, repo.token, clean, (chunk: string) => {
        acc += (acc.length > 0 ? '\n' : '') + chunk;
        this.updateReply(replyId, acc);
      });
      if (acc.trim().length === 0) {
        this.updateReply(replyId, `已通过 MoviePilot V3 通道受理「${clean}」，请在后端 AI Agent 设置中确认模型密钥。`);
      }
    } catch {
      this.updateReply(replyId, '智能助手通道暂未响应，请确认 MoviePilot 服务端已开启 AI Agent。');
    }
    this.sending = false;
  }

  private updateReply(id: string, text: string): void {
    const next: HarmonyAgentMsg[] = [];
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i];
      if (m.id === id) {
        next.push({ id: m.id, role: m.role, content: text });
      } else {
        next.push(m);
      }
    }
    this.messages = next;
  }

  build() {
    Column() {
      NativeBackHeader({
        title: '智能助手',
        trailingSymbol: 'sys.symbol.plus',
        trailingAccessibility: '新建会话',
        onBack: () => this.onBack(),
        onTrailingClick: () => { this.messages = []; }
      })

      Scroll() {
        Column({ space: 14 }) {
          if (this.messages.length === 0) {
            Column({ space: 12 }) {
              Stack({ alignContent: Alignment.Center }) {
                Column()
                  .width(64).height(64).borderRadius(32)
                  .linearGradient({ angle: 135, colors: [['#FF9F84FF', 0], ['#FF6B5CE7', 0.6], ['#FFE66BC4', 1]] })
                  .shadow({ radius: 20, color: '#669E7AF5', offsetY: 6 })
                SymbolGlyph($r('sys.symbol.ai_edit')).fontSize(28).fontColor([Color.White])
              }
              Text('MoviePilot 智能助手')
                .fontSize(20).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
              Text('一句话检索资源、创建订阅、管理站点与排查下载任务')
                .fontSize(13).fontColor(mpSecondaryText(this.isDark)).textAlign(TextAlign.Center)

              Column({ space: 10 }) {
                ForEach(this.quickSkills, (skill: string) => {
                  Row({ space: 10 }) {
                    SymbolGlyph($r('sys.symbol.ai_edit')).fontSize(16).fontColor([this.accentHex])
                    Text(skill).fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                    Text('›').fontSize(18).fontColor(mpSecondaryText(this.isDark))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 14, bottom: 14 })
                  .borderRadius(18)
                  .backgroundColor(this.isDark ? '#1AFFFFFF' : '#AAFFFFFF')
                  .border({ width: 0.8, color: this.isDark ? '#30FFFFFF' : '#1E000000', radius: 18 })
                  .onClick(() => this.send(skill))
                })
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding({ top: 36 })
            .alignItems(HorizontalAlign.Center)
          } else {
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
                CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
                  Column({ space: 6 }) {
                    Text('MoviePilot Agent').fontSize(12).fontColor(this.accentHex).fontWeight(FontWeight.Medium).width('100%')
                    Text(msg.content).fontSize(14).fontColor(mpPrimaryText(this.isDark)).lineHeight(22).width('100%')
                  }
                }
              }
            })
          }
        }.padding({ left: 20, right: 20, bottom: 20 })
      }.scrollBar(BarState.Off).layoutWeight(1)

      // 底部动态光感悬浮输入框（HarmonyOS 7 ImmersiveMaterial，低版本自动回退）
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入消息或 / 命令...', text: this.prompt })
          .layoutWeight(1)
          .fontColor(mpPrimaryText(this.isDark))
          .placeholderColor(mpSecondaryText(this.isDark))
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.prompt = v; })
          .onSubmit(() => this.send(this.prompt))
        Stack() {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18).fontColor([Color.White])
        }
        .width(36).height(36).borderRadius(18)
        .backgroundColor(this.accentHex)
        .accessibilityText('发送消息')
        .onClick(() => this.send(this.prompt))
      }
      .width('92%')
      .padding({ left: 14, right: 8, top: 6, bottom: 6 })
      .margin({ bottom: 22 })
      .borderRadius(26)
      .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'bar', 26, this.accentHex, true, this.dynamicLight))
    }.width('100%').height('100%')
  }
}
