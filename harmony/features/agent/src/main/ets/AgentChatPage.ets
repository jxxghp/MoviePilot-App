import { media } from '@kit.MediaKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  MoviePilotRepository,
  MpAgentCommand,
  MpAgentSessionSummary,
  MpAgentToolEntry,
  MpAgentAttachment,
  MpAgentChoiceButton,
  MpAgentChoiceCard,
  MpAgentChatMessage,
  SseEventChunk,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonySheetHeader,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

interface MdBlock {
  kind: string; // 'h1' | 'h2' | 'h3' | 'code' | 'quote' | 'bullet' | 'table' | 'para'
  text: string;
  lang?: string;
  rows?: string[][];
}

function parseMarkdownBlocks(raw: string): MdBlock[] {
  const lines = raw.replace(/\r\n/g, '\n').split('\n');
  const out: MdBlock[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();
    if (trimmed.length === 0) {
      i++;
      continue;
    }
    if (trimmed.startsWith('```')) {
      const lang = trimmed.substring(3).trim();
      const buf: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        buf.push(lines[i]);
        i++;
      }
      if (i < lines.length) { i++; }
      out.push({ kind: 'code', lang: lang || 'code', text: buf.join('\n') });
      continue;
    }
    if (trimmed.startsWith('### ')) {
      out.push({ kind: 'h3', text: trimmed.substring(4).replace(/\*\*/g, '') });
      i++;
      continue;
    }
    if (trimmed.startsWith('## ')) {
      out.push({ kind: 'h2', text: trimmed.substring(3).replace(/\*\*/g, '') });
      i++;
      continue;
    }
    if (trimmed.startsWith('# ')) {
      out.push({ kind: 'h1', text: trimmed.substring(2).replace(/\*\*/g, '') });
      i++;
      continue;
    }
    if (trimmed.startsWith('>')) {
      out.push({ kind: 'quote', text: trimmed.replace(/^>\s*/, '').replace(/\*\*/g, '') });
      i++;
      continue;
    }
    if (trimmed.startsWith('|') && trimmed.endsWith('|') && i + 1 < lines.length && lines[i + 1].trim().includes('---')) {
      const rows: string[][] = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        const cur = lines[i].trim();
        if (!cur.replace(/[|\-\s:]/g, '').length) { i++; continue; }
        const cells = cur.split('|').slice(1, -1).map((c: string) => c.trim().replace(/\*\*/g, ''));
        if (cells.length > 0) { rows.push(cells); }
        i++;
      }
      if (rows.length > 0) { out.push({ kind: 'table', text: '', rows: rows }); }
      continue;
    }
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || /^\d+\.\s+/.test(trimmed)) {
      const clean = trimmed.replace(/^([-*]|\d+\.)\s+/, '').replace(/\*\*/g, '');
      out.push({ kind: 'bullet', text: clean });
      i++;
      continue;
    }
    const pLines: string[] = [trimmed];
    i++;
    while (i < lines.length) {
      const nxt = lines[i].trim();
      if (nxt.length === 0 || nxt.startsWith('#') || nxt.startsWith('```') || nxt.startsWith('>') ||
        nxt.startsWith('- ') || nxt.startsWith('* ') || nxt.startsWith('|') || /^\d+\.\s+/.test(nxt)) {
        break;
      }
      pLines.push(nxt);
      i++;
    }
    out.push({ kind: 'para', text: pLines.join('\n').replace(/\*\*/g, '').replace(/`/g, '') });
  }
  return out;
}

/**
 * 可观察流式消息实体（配合 `@ObjectLink` 实现稳定 `msg.id` 键下的零销毁原位流式刷新）。
 */
@Observed
class ObservableAgentMessage {
  id: string;
  role: string;
  content: string;
  tools: MpAgentToolEntry[];
  attachments: MpAgentAttachment[];
  choices: MpAgentChoiceCard[];
  timestamp: string;

  constructor(src: MpAgentChatMessage) {
    this.id = src.id;
    this.role = src.role;
    this.content = src.content;
    this.tools = [...src.tools];
    this.attachments = [...src.attachments];
    this.choices = [...src.choices];
    this.timestamp = src.timestamp;
  }
}

@Component
struct AgentMessageItemView {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @ObjectLink msg: ObservableAgentMessage;
  @Prop sending: boolean = false;
  @Prop activeSessionId: string = '';
  @Prop toolsExpanded: boolean = false;
  onToggleTools: (msgId: string) => void = () => {};
  onNotice: (text: string) => void = () => {};

  private copyCodeToClipboard(code: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.onNotice('代码已复制到剪贴板');
    } catch {
      this.onNotice('复制失败');
    }
  }

  @Builder
  markdownContentBuilder(rawText: string) {
    Column({ space: 6 }) {
      ForEach(parseMarkdownBlocks(rawText), (blk: MdBlock, idx: number) => {
        if (blk.kind === 'h1' || blk.kind === 'h2' || blk.kind === 'h3') {
          Text(blk.text)
            .fontSize(blk.kind === 'h1' ? 18 : (blk.kind === 'h2' ? 16 : 14.5))
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .width('100%')
            .margin({ top: 4 })
        } else if (blk.kind === 'code') {
          Column({ space: 6 }) {
            Row() {
              Text(blk.lang || 'code').fontSize(11).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.doc')).fontSize(12).fontColor([this.accentHex])
                Text('复制').fontSize(11.5).fontColor(this.accentHex).fontWeight(FontWeight.Medium)
              }.onClick(() => this.copyCodeToClipboard(blk.text))
            }.width('100%')
            Scroll() {
              Text(blk.text)
                .fontSize(12)
                .fontColor(mpPrimaryText(this.isDark))
                .lineHeight(18)
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          }
          .width('100%')
          .padding(10)
          .borderRadius(12)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
        } else if (blk.kind === 'quote') {
          Row({ space: 8 }) {
            Column().width(3).height(20).borderRadius(1.5).backgroundColor(this.accentHex)
            Text(blk.text).fontSize(13).fontColor(mpSecondaryText(this.isDark)).lineHeight(20).layoutWeight(1)
          }.width('100%').padding({ top: 2, bottom: 2 })
        } else if (blk.kind === 'bullet') {
          Row({ space: 6 }) {
            Text('•').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.accentHex)
            Text(blk.text).fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).lineHeight(21).layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top)
        } else if (blk.kind === 'table' && blk.rows) {
          Column({ space: 4 }) {
            ForEach(blk.rows, (row: string[], rIdx: number) => {
              Row({ space: 6 }) {
                ForEach(row, (cell: string, cIdx: number) => {
                  Text(cell)
                    .fontSize(11.5)
                    .fontWeight(rIdx === 0 ? FontWeight.Bold : FontWeight.Regular)
                    .fontColor(mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                    .maxLines(2)
                }, (_c: string, cIdx: number) => `tc_${rIdx}_${cIdx}`)
              }
              .width('100%')
              .padding({ top: 5, bottom: 5, left: 8, right: 8 })
              .backgroundColor(rIdx === 0 ? HarmonyThemeColors.chipFill(this.isDark) : Color.Transparent)
              .borderRadius(6)
            }, (_r: string[], rIdx: number) => `tr_${rIdx}`)
          }
          .width('100%')
          .padding(4)
          .borderRadius(10)
          .border({ width: 0.6, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: 10 })
        } else {
          Text(blk.text)
            .fontSize(14)
            .fontColor(mpPrimaryText(this.isDark))
            .lineHeight(22)
            .width('100%')
        }
      }, (blk: MdBlock, idx: number) => `md_${idx}_${blk.kind}_${blk.text.length}`)
    }.width('100%')
  }

  build() {
    if (this.msg.role === 'user') {
      Column({ space: 6 }) {
        if (this.msg.attachments.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
            ForEach(this.msg.attachments, (att: MpAgentAttachment) => {
              NativeAdaptiveBadge({ text: `${att.kind === 'image' ? '🖼' : (att.kind === 'audio' ? '🎙' : '📎')} ${att.name}`, tintHex: this.accentHex })
            }, (att: MpAgentAttachment) => att.id)
          }.width('100%')
        }
        Row() {
          Blank()
          Text(this.msg.content)
            .fontSize(14.5).fontColor(Color.White)
            .padding({ left: 15, right: 15, top: 10, bottom: 10 })
            .borderRadius(20).backgroundColor(this.accentHex)
            .constraintSize({ maxWidth: '84%' })
        }.width('100%')
      }.width('100%')
    } else {
      CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
        Column({ space: 10 }) {
          if (this.msg.tools.length > 0) {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
                  .fontSize(15)
                  .fontColor([this.msg.tools.some((t: MpAgentToolEntry) => t.status === 'running') ? this.accentHex : '#34C759'])
                Text(this.msg.tools.some((t: MpAgentToolEntry) => t.status === 'running')
                  ? `正在执行工具调用 (${this.msg.tools.length})`
                  : `已完成 ${this.msg.tools.length} 项工具调用`)
                  .fontSize(13).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                SymbolGlyph($r(this.toolsExpanded ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
                  .fontSize(15).fontColor([mpSecondaryText(this.isDark)])
              }
              .width('100%')
              .onClick(() => this.onToggleTools(this.msg.id))

              if (this.toolsExpanded) {
                Column({ space: 6 }) {
                  ForEach(this.msg.tools, (t: MpAgentToolEntry) => {
                    Column({ space: 2 }) {
                      Row({ space: 6 }) {
                        Text(t.status === 'error' ? '✕' : (t.status === 'running' ? '◌' : '✓'))
                          .fontSize(11).fontWeight(FontWeight.Bold)
                          .fontColor(t.status === 'error' ? '#E84855' : (t.status === 'running' ? this.accentHex : '#34C759'))
                        Text(t.name).fontSize(12).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                      }.width('100%')
                      if (t.summary.length > 0 || t.detail.length > 0) {
                        Text((t.summary || t.detail).substring(0, 140))
                          .fontSize(11).fontColor(mpSecondaryText(this.isDark)).maxLines(2).width('100%')
                      }
                    }.width('100%').padding({ top: 4 })
                  }, (t: MpAgentToolEntry) => `${t.id}_${t.status}`)
                }.width('100%')
              }
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }

          if (this.msg.content.length > 0) {
            this.markdownContentBuilder(this.msg.content)
          } else if (this.sending) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color(this.accentHex)
              Text('思考中…').fontSize(13).fontColor(mpSecondaryText(this.isDark))
            }.width('100%')
          }

          ForEach(this.msg.choices, (card: MpAgentChoiceCard, cIdx: number) => {
            Column({ space: 8 }) {
              Text(card.title).fontSize(13).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
              if (card.prompt.length > 0) {
                Text(card.prompt).fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              }
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
                ForEach(card.buttons, (btn: MpAgentChoiceButton) => {
                  NativeAdaptivePill({
                    title: btn.label,
                    selected: false,
                    onTap: async () => {
                      const payloadObj: Record<string, string> = {};
                      payloadObj['session_id'] = this.activeSessionId;
                      payloadObj['callback_data'] = btn.callbackData || btn.value;
                      await MoviePilotRepository.shared().triggerAgentCallback(JSON.stringify(payloadObj));
                      this.onNotice(`已提交选择「${btn.label}」`);
                    }
                  })
                }, (btn: MpAgentChoiceButton) => btn.label)
              }.width('100%')
            }
            .width('100%').padding(10).borderRadius(12).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }, (_c: MpAgentChoiceCard, cIdx: number) => `ch_${cIdx}`)
        }
      }
    }
  }
}

/**
 * 鸿蒙「AI 智能助手」全屏对话页（100% 对齐 iOS 真实 `/api/v1/message/agent/*` 接口能力）：
 * - 消息列表采用稳定 `msg.id` 作为 `ForEach` 键并配合 `@Observed`/`@ObjectLink` 实现零节点重建的流畅 SSE 输出；
 * - 支持历史会话管理、斜杠命令、图片/文件上传与麦克风 AAC 录音上传。
 */
@Component
export struct HarmonyAgentChatPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @State private activeSessionId: string = `harmony-${Date.now()}`;
  @State private activeSessionTitle: string = '新对话';
  @State private sessions: MpAgentSessionSummary[] = [];
  @State private commands: MpAgentCommand[] = [];
  @State private messages: ObservableAgentMessage[] = [];
  @State private expandedToolMsgIds: string[] = [];
  @State private pendingAttachments: MpAgentAttachment[] = [];
  @State private prompt: string = '';
  @State private sending: boolean = false;
  @State private uploading: boolean = false;
  @State private recording: boolean = false;
  @State private recordSeconds: number = 0;
  @State private notice: string = '';
  @State private showHistorySheet: boolean = false;
  @State private showAttachSheet: boolean = false;
  private avRecorder: media.AVRecorder | null = null;
  private recordFilePath: string = '';
  private recordFileFd: number = -1;
  private recordTimer: number = -1;
  private msgScroller: Scroller = new Scroller();
  onBack: () => void = () => {};

  private readonly quickSkills: string[] = [
    '查看最近入库了哪些电影和剧集',
    '检查站点连通性与今日整理记录',
    '看看我当前有哪些正在下载的任务'
  ];

  aboutToAppear(): void {
    this.bootstrapAgent();
  }

  aboutToDisappear(): void {
    this.cleanupRecorder();
  }

  private async bootstrapAgent(): Promise<void> {
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchAgentSessions(),
        repo.fetchAgentCommands()
      ]);
      this.sessions = res[0];
      this.commands = res[1];
      if (this.sessions.length > 0 && this.messages.length === 0) {
        await this.switchSession(this.sessions[0]);
      }
    } catch {
      // keep fresh empty session
    }
  }

  private async refreshSessions(): Promise<void> {
    try {
      this.sessions = await MoviePilotRepository.shared().fetchAgentSessions();
    } catch {
      // ignore
    }
  }

  private async switchSession(sess: MpAgentSessionSummary): Promise<void> {
    this.activeSessionId = sess.sessionId;
    this.activeSessionTitle = sess.title;
    this.showHistorySheet = false;
    try {
      const raw = await MoviePilotRepository.shared().fetchAgentSessionDetail(sess.sessionId);
      this.messages = raw.map((m: MpAgentChatMessage): ObservableAgentMessage => new ObservableAgentMessage(m));
    } catch {
      this.messages = [];
    }
  }

  private createNewSession(): void {
    this.activeSessionId = `harmony-${Date.now()}`;
    this.activeSessionTitle = '新对话';
    this.messages = [];
    this.pendingAttachments = [];
    this.showHistorySheet = false;
  }

  private toggleToolsExpanded(msgId: string): void {
    if (this.expandedToolMsgIds.includes(msgId)) {
      this.expandedToolMsgIds = this.expandedToolMsgIds.filter((id: string) => id !== msgId);
    } else {
      this.expandedToolMsgIds = [...this.expandedToolMsgIds, msgId];
    }
  }

  private async pickImageAttachment(): Promise<void> {
    this.showAttachSheet = false;
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const res = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (res.photoUris.length > 0) {
        await this.uploadUri(res.photoUris[0], `image_${Date.now()}.jpg`, 'image/jpeg');
      }
    } catch {
      this.notice = '未选择图片或无读取权限';
    }
  }

  private async pickFileAttachment(): Promise<void> {
    this.showAttachSheet = false;
    try {
      const docPicker = new picker.DocumentViewPicker();
      const uris = await docPicker.select({ maxSelectNumber: 1 });
      if (uris.length > 0) {
        const uri = uris[0];
        const name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1)) || `file_${Date.now()}.bin`;
        await this.uploadUri(uri, name, 'application/octet-stream');
      }
    } catch {
      this.notice = '未选择文件';
    }
  }

  private async uploadUri(uri: string, fileName: string, mimeType: string): Promise<void> {
    this.uploading = true;
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const buf = new ArrayBuffer(Math.min(stat.size, 20 * 1024 * 1024));
      const readLen = fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const bytes = new Uint8Array(buf, 0, readLen);
      const uploaded = await MoviePilotRepository.shared().uploadAgentAttachment(bytes, fileName, mimeType);
      if (uploaded) {
        this.pendingAttachments = [...this.pendingAttachments, uploaded];
        this.notice = `已上传附件「${uploaded.name}」`;
      } else {
        this.notice = '附件上传失败';
      }
    } catch {
      this.notice = '读取文件失败';
    }
    this.uploading = false;
  }

  private async toggleVoiceRecord(): Promise<void> {
    if (this.recording) {
      await this.stopVoiceRecordAndUpload();
    } else {
      await this.startVoiceRecord();
    }
  }

  private async startVoiceRecord(): Promise<void> {
    try {
      const hostCtx = this.getUIContext().getHostContext();
      if (!hostCtx) {
        this.notice = '无法获取录音缓存上下文';
        return;
      }
      this.recordFilePath = `${hostCtx.cacheDir}/agent_voice_${Date.now()}.m4a`;
      const f = fileIo.openSync(this.recordFilePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      this.recordFileFd = f.fd;
      const recorder = await media.createAVRecorder();
      this.avRecorder = recorder;
      await recorder.prepare({
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 96000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 44100,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${f.fd}`
      });
      await recorder.start();
      this.recording = true;
      this.recordSeconds = 0;
      this.recordTimer = setInterval(() => { this.recordSeconds += 1; }, 1000);
    } catch {
      this.cleanupRecorder();
      this.notice = '无法启动录音，请确认已授予麦克风权限';
    }
  }

  private async stopVoiceRecordAndUpload(): Promise<void> {
    const path = this.recordFilePath;
    const dur = this.recordSeconds;
    this.recording = false;
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
    try {
      if (this.avRecorder) {
        await this.avRecorder.stop();
        await this.avRecorder.release();
        this.avRecorder = null;
      }
      if (this.recordFileFd >= 0) {
        fileIo.closeSync(this.recordFileFd);
        this.recordFileFd = -1;
      }
      if (path.length > 0 && dur >= 1) {
        await this.uploadUri(path, `voice_${dur}s.m4a`, 'audio/mp4');
      }
    } catch {
      this.cleanupRecorder();
    }
  }

  private cleanupRecorder(): void {
    if (this.recordTimer >= 0) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
    if (this.avRecorder) {
      try { this.avRecorder.release(); } catch { /* ignore */ }
      this.avRecorder = null;
    }
    if (this.recordFileFd >= 0) {
      try { fileIo.closeSync(this.recordFileFd); } catch { /* ignore */ }
      this.recordFileFd = -1;
    }
    this.recording = false;
  }

  private updateAssistantMsg(replyId: string, content: string, tools: MpAgentToolEntry[], choices: MpAgentChoiceCard[]): void {
    for (let i = 0; i < this.messages.length; i++) {
      const m = this.messages[i];
      if (m.id === replyId) {
        m.content = content;
        m.tools = [...tools];
        m.choices = [...choices];
        break;
      }
    }
  }

  private async send(overrideText?: string): Promise<void> {
    const clean = (overrideText ?? this.prompt).trim();
    if ((!clean && this.pendingAttachments.length === 0) || this.sending) { return; }
    this.prompt = '';
    this.notice = '';
    const attached = [...this.pendingAttachments];
    this.pendingAttachments = [];
    if (this.messages.length === 0 && clean.length > 0) {
      this.activeSessionTitle = clean.substring(0, 24);
    }
    this.sending = true;
    const userMsgId = `u_${Date.now()}`;
    const replyId = `a_${Date.now() + 1}`;
    this.messages = [
      ...this.messages,
      new ObservableAgentMessage({
        id: userMsgId, role: 'user', content: clean || '[附件消息]',
        tools: [], attachments: attached, choices: [], timestamp: ''
      }),
      new ObservableAgentMessage({
        id: replyId, role: 'assistant', content: '',
        tools: [], attachments: [], choices: [], timestamp: ''
      })
    ];

    const imagesPayload: Record<string, Object>[] = [];
    const filesPayload: Record<string, Object>[] = [];
    for (let i = 0; i < attached.length; i++) {
      const a = attached[i];
      const itemObj: Record<string, Object> = {};
      itemObj['id'] = a.id;
      itemObj['name'] = a.name;
      itemObj['url'] = a.url;
      itemObj['mime_type'] = a.mimeType;
      if (a.kind === 'image') { imagesPayload.push(itemObj); } else { filesPayload.push(itemObj); }
    }

    const reqObj: Record<string, Object> = {};
    reqObj['session_id'] = this.activeSessionId;
    reqObj['text'] = clean;
    reqObj['message'] = clean;
    reqObj['images'] = imagesPayload;
    reqObj['files'] = filesPayload;

    let accText = '';
    const toolsList: MpAgentToolEntry[] = [];
    const choicesList: MpAgentChoiceCard[] = [];

    try {
      await MoviePilotRepository.shared().streamAgentChatPayload(JSON.stringify(reqObj), (ev: SseEventChunk) => {
        if (ev.data === '[DONE]') { return; }
        try {
          const parsed = JSON.parse(ev.data) as Record<string, Object>;
          const evKind = ev.event || String(parsed['type'] ?? parsed['event'] ?? '');
          if (evKind.includes('tool')) {
            const tid = String(parsed['id'] ?? parsed['tool_call_id'] ?? `tc_${toolsList.length}`);
            const tname = String(parsed['name'] ?? parsed['tool_name'] ?? '工具执行');
            const tstatus = evKind.includes('error') ? 'error' : (evKind.includes('end') || evKind.includes('result') ? 'done' : 'running');
            const detail = String(parsed['result'] ?? parsed['output'] ?? parsed['summary'] ?? '');
            const existIdx = toolsList.findIndex((x: MpAgentToolEntry) => x.id === tid);
            const entry: MpAgentToolEntry = { id: tid, name: tname, status: tstatus, summary: detail, detail: detail };
            if (existIdx >= 0) { toolsList[existIdx] = entry; } else { toolsList.push(entry); }
            this.updateAssistantMsg(replyId, accText, toolsList, choicesList);
            return;
          }
          if (parsed['choices'] && Array.isArray(parsed['choices'])) {
            const rawBtns = parsed['choices'] as Object[];
            const btns: MpAgentChoiceButton[] = [];
            for (let b = 0; b < rawBtns.length; b++) {
              const bo = rawBtns[b] as Record<string, Object>;
              btns.push({
                label: String(bo['text'] ?? bo['label'] ?? '选择'),
                value: String(bo['value'] ?? bo['callback_data'] ?? ''),
                callbackData: String(bo['callback_data'] ?? '')
              });
            }
            if (btns.length > 0) {
              choicesList.push({
                title: String(parsed['title'] ?? '请选择后续操作'),
                prompt: String(parsed['prompt'] ?? ''),
                buttons: btns
              });
              this.updateAssistantMsg(replyId, accText, toolsList, choicesList);
            }
          }
          const delta = String(parsed['delta'] ?? parsed['content'] ?? parsed['text'] ?? parsed['message'] ?? '');
          if (delta.length > 0) {
            accText += delta;
            this.updateAssistantMsg(replyId, accText, toolsList, choicesList);
          }
        } catch {
          if (ev.data.trim().length > 0) {
            accText += ev.data;
            this.updateAssistantMsg(replyId, accText, toolsList, choicesList);
          }
        }
      });
      if (accText.trim().length === 0 && toolsList.length === 0) {
        this.updateAssistantMsg(replyId, '智能助手暂未返回内容，请检查服务端模型配置。', toolsList, choicesList);
      }
      await this.refreshSessions();
    } catch {
      this.updateAssistantMsg(replyId, '智能助手请求中断，请检查网络或服务端状态。', toolsList, choicesList);
    }
    this.sending = false;
  }

  private async stopCurrentRun(): Promise<void> {
    await MoviePilotRepository.shared().stopAgentSession(this.activeSessionId);
    this.sending = false;
    this.notice = '已请求停止当前生成';
  }

  @Builder
  historySheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `历史会话 (${this.sessions.length})`,
        cancelText: '关闭',
        actionText: '+ 新对话',
        onCancel: () => { this.showHistorySheet = false; },
        onAction: () => this.createNewSession()
      })
      Scroll() {
        Column({ space: 10 }) {
          if (this.sessions.length === 0) {
            Text('暂无历史会话记录').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.sessions, (s: MpAgentSessionSummary) => {
              Column() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                  Row({ space: 10 }) {
                    Column({ space: 4 }) {
                      Row({ space: 6 }) {
                        Text(s.title).fontSize(14.5).fontWeight(FontWeight.Bold)
                          .fontColor(mpPrimaryText(this.isDark)).maxLines(1).layoutWeight(1)
                        if (s.sessionId === this.activeSessionId) {
                          NativeAdaptiveBadge({ text: '当前', tintHex: this.accentHex })
                        }
                      }.width('100%')
                      Text(`${s.messageCount} 条消息${s.updatedAt ? ' · ' + s.updatedAt : ''}`)
                        .fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                    Button({ type: ButtonType.Circle }) {
                      SymbolGlyph($r('sys.symbol.trash')).fontSize(15).fontColor(['#E84855'])
                    }
                    .width(34).height(34)
                    .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                    .onClick(async () => {
                      await MoviePilotRepository.shared().deleteAgentSession(s.sessionId);
                      await this.refreshSessions();
                      if (s.sessionId === this.activeSessionId) { this.createNewSession(); }
                    })
                  }.width('100%')
                }
              }
              .width('100%')
              .onClick(() => this.switchSession(s))
            }, (s: MpAgentSessionSummary) => s.sessionId)
          }
        }.padding({ bottom: 24 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  attachSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '添加附件与命令',
        cancelText: '关闭',
        onCancel: () => { this.showAttachSheet = false; }
      })
      Scroll() {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            Column({ space: 8 }) {
              Stack() {
                SymbolGlyph($r('sys.symbol.picture')).fontSize(24).fontColor([this.accentHex])
              }.width(52).height(52).borderRadius(16)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '28' : '18'))
              Text('选择图片').fontSize(13).fontColor(mpPrimaryText(this.isDark))
            }
            .layoutWeight(1).padding(12).borderRadius(16).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .onClick(() => this.pickImageAttachment())

            Column({ space: 8 }) {
              Stack() {
                SymbolGlyph($r('sys.symbol.doc_text')).fontSize(24).fontColor(['#26B8A8'])
              }.width(52).height(52).borderRadius(16)
                .backgroundColor(HarmonyAppearanceStore.withAlpha('#26B8A8', this.isDark ? '28' : '18'))
              Text('选择文件').fontSize(13).fontColor(mpPrimaryText(this.isDark))
            }
            .layoutWeight(1).padding(12).borderRadius(16).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .onClick(() => this.pickFileAttachment())
          }.width('100%')

          if (this.commands.length > 0) {
            Text('斜杠快捷命令').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Column({ space: 8 }) {
              ForEach(this.commands, (cmd: MpAgentCommand) => {
                Row({ space: 10 }) {
                  NativeAdaptiveBadge({ text: cmd.command, tintHex: this.accentHex })
                  Text(cmd.description).fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).maxLines(1).layoutWeight(1)
                }
                .width('100%').padding(12).borderRadius(14).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .onClick(() => {
                  this.showAttachSheet = false;
                  this.prompt = `${cmd.command} `;
                })
              }, (cmd: MpAgentCommand) => cmd.command)
            }.width('100%')
          }
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      NativeBackHeader({
        title: '智能助手',
        subtitle: this.activeSessionTitle,
        secondarySymbol: 'sys.symbol.square_and_pencil',
        secondaryAccessibility: '新建对话',
        trailingSymbol: 'sys.symbol.clock',
        trailingAccessibility: '历史会话',
        onBack: () => this.onBack(),
        onSecondaryClick: () => this.createNewSession(),
        onTrailingClick: () => {
          this.refreshSessions();
          this.showHistorySheet = true;
        }
      })

      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(12)
          .fontColor('#34C759')
          .padding({ left: 16, right: 16, bottom: 4 })
          .width('100%')
          .constraintSize({ maxWidth: 780 })
      }

      Scroll(this.msgScroller) {
        Column() {
          Column({ space: 14 }) {
            if (this.messages.length === 0) {
              Column({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Column()
                    .width(64).height(64).borderRadius(32)
                    .linearGradient({ angle: 135, colors: [[this.accentHex, 0], ['#FF5B8DFF', 0.55], ['#FF26B8A8', 1]] })
                    .shadow({ radius: 18, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '66'), offsetY: 6 })
                  SymbolGlyph($r('sys.symbol.ai_edit')).fontSize(28).fontColor([Color.White])
                }
                Text('MoviePilot 智能助手')
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                Text('检索资源、创建订阅、管理站点、识别文件与排查下载任务')
                  .fontSize(13).fontColor(mpSecondaryText(this.isDark)).textAlign(TextAlign.Center)

                Column({ space: 10 }) {
                  ForEach(this.quickSkills, (skill: string) => {
                    Column() {
                      CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: true }) {
                        Row({ space: 10 }) {
                          SymbolGlyph($r('sys.symbol.ai_edit')).fontSize(16).fontColor([this.accentHex])
                          Text(skill).fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                          Text('›').fontSize(18).fontColor(mpSecondaryText(this.isDark))
                        }.width('100%')
                      }
                    }
                    .width('100%')
                    .onClick(() => this.send(skill))
                  }, (skill: string) => skill)
                }.width('100%').margin({ top: 10 })
              }
              .width('100%')
              .padding({ top: HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp) ? 10 : 32 })
              .alignItems(HorizontalAlign.Center)
            } else {
              ForEach(this.messages, (msg: ObservableAgentMessage) => {
                AgentMessageItemView({
                  msg: msg,
                  sending: this.sending,
                  activeSessionId: this.activeSessionId,
                  toolsExpanded: this.expandedToolMsgIds.includes(msg.id),
                  onToggleTools: (id: string) => this.toggleToolsExpanded(id),
                  onNotice: (txt: string) => { this.notice = txt; }
                })
              }, (msg: ObservableAgentMessage) => msg.id)
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 780 })
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }.scrollBar(BarState.Off).layoutWeight(1).width('100%')

      if (this.pendingAttachments.length > 0 || this.uploading || this.recording) {
        Row({ space: 8 }) {
          if (this.recording) {
            NativeAdaptiveBadge({ text: `🎙 正在录音 ${this.recordSeconds}s（点击麦克风停止上传）`, tintHex: '#E84855', filled: true })
          }
          if (this.uploading) {
            NativeAdaptiveBadge({ text: '正在上传附件…', tintHex: this.accentHex })
          }
          ForEach(this.pendingAttachments, (att: MpAgentAttachment) => {
            Row({ space: 4 }) {
              Text(`${att.kind === 'image' ? '🖼' : (att.kind === 'audio' ? '🎙' : '📎')} ${att.name} (${formatByteSize(att.sizeBytes)})`)
                .fontSize(11.5).fontColor(mpPrimaryText(this.isDark)).maxLines(1)
              Text('×').fontSize(13).fontColor('#E84855').fontWeight(FontWeight.Bold)
                .onClick(() => {
                  this.pendingAttachments = this.pendingAttachments.filter((a: MpAgentAttachment) => a.id !== att.id);
                })
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }, (att: MpAgentAttachment) => att.id)
        }
        .width('92%')
        .constraintSize({ maxWidth: 748 })
        .margin({ bottom: 6 })
      }

      Row({ space: 6 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([mpPrimaryText(this.isDark)])
        }
        .width(36).height(36)
        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
        .accessibilityText('添加附件或命令')
        .onClick(() => { this.showAttachSheet = true; })

        TextInput({ placeholder: '输入消息、/ 命令或添加附件…', text: this.prompt })
          .layoutWeight(1)
          .fontSize(14)
          .fontColor(mpPrimaryText(this.isDark))
          .placeholderColor(mpSecondaryText(this.isDark))
          .backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.prompt = v; })
          .onSubmit(() => this.send())

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.recording ? 'sys.symbol.square_fill' : 'sys.symbol.mic'))
            .fontSize(17)
            .fontColor([this.recording ? Color.White : mpPrimaryText(this.isDark)])
        }
        .width(36).height(36)
        .backgroundColor(this.recording ? '#E84855' : HarmonyThemeColors.chipFill(this.isDark))
        .accessibilityText(this.recording ? '停止录音' : '语音输入')
        .onClick(() => this.toggleVoiceRecord())

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.sending ? 'sys.symbol.square_fill' : 'sys.symbol.arrow_up'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(36).height(36)
        .backgroundColor(this.sending ? '#E84855' : this.accentHex)
        .accessibilityText(this.sending ? '停止生成' : '发送消息')
        .onClick(() => {
          if (this.sending) { this.stopCurrentRun(); } else { this.send(); }
        })
      }
      .width('92%')
      .constraintSize({ maxWidth: 748 })
      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
      .margin({ bottom: Math.max(12, this.safeBottomVp + 4) })
      .borderRadius(26)
      .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'bar', 26, this.accentHex, true, this.dynamicLight))

      Blank().width(0).height(0).bindSheet($$this.showHistorySheet, this.historySheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showAttachSheet, this.attachSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
