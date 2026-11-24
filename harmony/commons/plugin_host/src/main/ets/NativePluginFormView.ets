import { webview } from '@kit.ArkWeb';
import { RustCoreBridge, MpRemoteImage } from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  HarmonyPluginSheetSkeleton,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

export interface PluginSelectOption {
  title: string;
  value: string;
}

export interface PluginFieldPlan {
  component: string;
  modelKey?: string;
  label: string;
  hint: string;
  visible: boolean;
  visibleExpr?: string;
  text: string;
  multiple?: boolean;
  items?: PluginSelectOption[];
}

export interface VueChromeAction {
  id: string;
  title: string;
  icon: string;
  enabled: boolean;
}

export interface VueChromeConfirmation {
  id: string;
  title: string;
  message: string;
  confirmText: string;
  cancelText: string;
  destructive: boolean;
}

export interface PluginStatCell {
  label: string;
  value: string;
  sub: string;
}

export interface PluginDataBlock {
  id: string;
  kind: string; // 'alert' | 'heading' | 'chip' | 'text' | 'card' | 'image' | 'table' | 'stat_grid'
  title: string;
  subtitle?: string;
  body: string;
  tone: string;
  imageUrl?: string;
  chips?: string[];
  headers?: string[];
  rows?: string[][];
  stats?: PluginStatCell[];
}

/**
 * 鸿蒙侧 Vue 模块联邦插件头部/返回控制句柄：
 * 让外部原生标题栏（`NativeBackHeader`）能直接触发 Web 内部 sheet 动作或优雅关闭弹窗。
 */
export class HarmonyVueChromeController {
  invokeActionHandler: ((actionId: string) => void) | null = null;
  requestCloseHandler: (() => boolean) | null = null;

  invokeAction(actionId: string): void {
    if (this.invokeActionHandler) {
      this.invokeActionHandler(actionId);
    }
  }

  requestClose(): boolean {
    if (this.requestCloseHandler) {
      return this.requestCloseHandler();
    }
    return false;
  }
}

class HarmonyChromeBridgeProxy {
  private handler: (rawJson: string) => void;

  constructor(handler: (rawJson: string) => void) {
    this.handler = handler;
  }

  postMessage(rawJson: string): void {
    this.handler(rawJson);
  }
}

function asObj(v: Object | null | undefined): Record<string, Object> | null {
  if (v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return null;
}

function asList(v: Object | null | undefined): Object[] {
  if (v !== null && v !== undefined && Array.isArray(v)) {
    return v as Object[];
  }
  return [];
}

function readStr(obj: Record<string, Object> | null, key: string, fallback: string = ''): string {
  if (!obj) { return fallback; }
  const v = obj[key];
  if (v === null || v === undefined) { return fallback; }
  const s = String(v);
  return s === 'null' ? fallback : s;
}

function readBool(obj: Record<string, Object> | null, key: string, fallback: boolean = false): boolean {
  if (!obj) { return fallback; }
  const v = obj[key];
  if (v === null || v === undefined) { return fallback; }
  if (typeof v === 'boolean') { return v; }
  return String(v).toLowerCase() === 'true';
}

function copyRecord(src: Record<string, Object>): Record<string, Object> {
  const next: Record<string, Object> = {};
  const keys = Object.keys(src);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    next[k] = src[k];
  }
  return next;
}

function unwrapV3Envelope(rawJson: string): Record<string, Object> | null {
  try {
    if (!rawJson || rawJson.trim().length === 0) { return null; }
    const parsed = asObj(JSON.parse(rawJson) as Object);
    if (!parsed) { return null; }
    if (parsed['conf'] === undefined && parsed['page'] === undefined) {
      const inner = asObj(parsed['data']);
      if (inner) { return inner; }
    }
    return parsed;
  } catch {
    return null;
  }
}

function parseSelectItems(rawItems: Object | null | undefined): PluginSelectOption[] {
  const arr = asList(rawItems);
  const out: PluginSelectOption[] = [];
  for (let i = 0; i < arr.length; i++) {
    const it = arr[i];
    const rec = asObj(it);
    if (rec) {
      const title = readStr(rec, 'title') || readStr(rec, 'text') || readStr(rec, 'label') || readStr(rec, 'value');
      const val = readStr(rec, 'value') || title;
      if (val.length > 0) {
        out.push({ title: title || val, value: val });
      }
    } else if (it !== null && it !== undefined) {
      const s = String(it);
      if (s.length > 0) {
        out.push({ title: s, value: s });
      }
    }
  }
  return out;
}

function isNonVisualPluginTag(comp: string): boolean {
  const lower = comp.trim().toLowerCase();
  return lower === 'style' || lower === 'script' || lower === 'link' || lower === 'meta' || lower === 'vdialogclosebtn';
}

function extractNodeConditionExpr(node: Record<string, Object>, props: Record<string, Object> | null): string {
  const parts: string[] = [];
  const candidates: string[] = [
    readStr(props, 'v-if'),
    readStr(props, 'v-show'),
    readStr(props, 'vIf'),
    readStr(props, 'vShow'),
    readStr(node, 'v-if'),
    readStr(node, 'v-show')
  ];
  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i].trim();
    if (c.length > 0 && !parts.includes(c)) {
      parts.push(`(${c})`);
    }
  }
  const directives = asList(node['directives']);
  for (let d = 0; d < directives.length; d++) {
    const dir = asObj(directives[d]);
    const name = readStr(dir, 'name').toLowerCase();
    const expr = readStr(dir, 'expression') || readStr(dir, 'value');
    if ((name === 'if' || name === 'v-if' || name === 'show' || name === 'v-show') && expr.trim().length > 0) {
      parts.push(`(${expr.trim()})`);
    }
  }
  return parts.join(' && ');
}

function combineExpr(parentExpr: string, selfExpr: string): string {
  if (parentExpr.length > 0 && selfExpr.length > 0) {
    return `${parentExpr} && ${selfExpr}`;
  }
  return parentExpr.length > 0 ? parentExpr : selfExpr;
}

function collectModelVisibilityExprs(nodes: Object[], inheritedExpr: string, outMap: Map<string, string>): void {
  for (let i = 0; i < nodes.length; i++) {
    const node = asObj(nodes[i]);
    if (!node) { continue; }
    const comp = readStr(node, 'component');
    if (isNonVisualPluginTag(comp)) { continue; }
    const props = asObj(node['props']);
    const merged = combineExpr(inheritedExpr, extractNodeConditionExpr(node, props));
    const modelKey = readStr(props, 'model') || readStr(props, 'v-model');
    if (modelKey.length > 0 && merged.length > 0) {
      outMap.set(modelKey, merged);
    }
    const content = asList(node['content']);
    if (content.length > 0) {
      collectModelVisibilityExprs(content, merged, outMap);
    }
  }
}

function extractFallbackFormFields(nodes: Object[], out: PluginFieldPlan[], inheritedExpr: string = ''): void {
  const fieldKinds: string[] = [
    'VSwitch', 'VCheckbox', 'VCronField', 'VSelect', 'VAutocomplete',
    'VCombobox', 'VTextField', 'VTextarea', 'VAceEditor', 'VAlert'
  ];
  for (let i = 0; i < nodes.length; i++) {
    const node = asObj(nodes[i]);
    if (!node) { continue; }
    const comp = readStr(node, 'component');
    if (isNonVisualPluginTag(comp)) { continue; }
    const props = asObj(node['props']);
    const mergedExpr = combineExpr(inheritedExpr, extractNodeConditionExpr(node, props));
    const text = typeof node['text'] === 'string' ? (node['text'] as string) : '';
    if (comp.length > 0 && fieldKinds.includes(comp)) {
      const modelKey = readStr(props, 'model') || readStr(props, 'v-model');
      const label = readStr(props, 'label') || readStr(props, 'title') || readStr(props, 'placeholder') || modelKey;
      const hint = readStr(props, 'hint');
      const items = parseSelectItems(props ? props['items'] : undefined);
      out.push({
        component: comp,
        modelKey: modelKey.length > 0 ? modelKey : undefined,
        label: label,
        hint: hint,
        visible: true,
        visibleExpr: mergedExpr.length > 0 ? mergedExpr : undefined,
        text: text || readStr(props, 'text'),
        multiple: readBool(props, 'multiple', false) || readBool(props, 'chips', false),
        items: items
      });
    }
    const content = asList(node['content']);
    if (content.length > 0) {
      extractFallbackFormFields(content, out, mergedExpr);
    }
  }
}

function collectPlainText(node: Record<string, Object> | null): string {
  if (!node) { return ''; }
  const comp = readStr(node, 'component');
  if (isNonVisualPluginTag(comp)) { return ''; }
  const parts: string[] = [];
  const direct = typeof node['text'] === 'string' ? (node['text'] as string).trim() : '';
  if (direct.length > 0 && !direct.startsWith('.') && !direct.includes('{display:')) {
    parts.push(direct);
  }
  const props = asObj(node['props']);
  const propTitle = readStr(props, 'title').trim();
  const propText = readStr(props, 'text').trim();
  if (propTitle.length > 0 && !parts.includes(propTitle)) { parts.push(propTitle); }
  if (propText.length > 0 && !parts.includes(propText)) { parts.push(propText); }
  const children = asList(node['content']);
  for (let i = 0; i < children.length; i++) {
    const childText = collectPlainText(asObj(children[i]));
    if (childText.length > 0) {
      parts.push(childText);
    }
  }
  return parts.join(' ').trim();
}

function resolvePluginAssetUrl(rawSrc: string, serverUrl: string): string {
  const s = rawSrc.trim();
  if (s.length === 0) { return ''; }
  if (s.startsWith('http://') || s.startsWith('https://') || s.startsWith('data:image/')) {
    return s;
  }
  const cleanBase = serverUrl.replace(/\/+$/, '');
  if (cleanBase.length === 0) { return s; }
  return s.startsWith('/') ? `${cleanBase}${s}` : `${cleanBase}/${s}`;
}

function extractTableBlock(node: Record<string, Object>, id: string): PluginDataBlock | null {
  const headers: string[] = [];
  const rows: string[][] = [];

  const walkTable = (cur: Record<string, Object> | null, inHead: boolean): void => {
    if (!cur) { return; }
    const tag = readStr(cur, 'component').toLowerCase();
    if (tag === 'thead') {
      const ch = asList(cur['content']);
      for (let i = 0; i < ch.length; i++) { walkTable(asObj(ch[i]), true); }
      return;
    }
    if (tag === 'tr') {
      const cells = asList(cur['content']);
      const rowCells: string[] = [];
      let isHeaderRow = inHead;
      for (let c = 0; c < cells.length; c++) {
        const cellObj = asObj(cells[c]);
        if (!cellObj) { continue; }
        const cTag = readStr(cellObj, 'component').toLowerCase();
        if (cTag === 'th') { isHeaderRow = true; }
        if (cTag === 'th' || cTag === 'td') {
          rowCells.push(collectPlainText(cellObj));
        }
      }
      if (rowCells.length > 0) {
        if (isHeaderRow && headers.length === 0) {
          for (let h = 0; h < rowCells.length; h++) { headers.push(rowCells[h]); }
        } else {
          rows.push(rowCells);
        }
      }
      return;
    }
    const ch = asList(cur['content']);
    for (let i = 0; i < ch.length; i++) { walkTable(asObj(ch[i]), inHead); }
  };

  walkTable(node, false);
  if (headers.length === 0 && rows.length === 0) { return null; }
  return {
    id: id,
    kind: 'table',
    title: '',
    body: '',
    tone: 'default',
    headers: headers,
    rows: rows
  };
}

function extractCardSummary(cardNode: Record<string, Object>, serverUrl: string, id: string): PluginDataBlock | null {
  const props = asObj(cardNode['props']);
  let title = readStr(props, 'title').trim();
  let subtitle = readStr(props, 'subtitle').trim();
  const bodyLines: string[] = [];
  const chips: string[] = [];
  let imageUrl = '';

  const walkCard = (cur: Record<string, Object> | null): void => {
    if (!cur) { return; }
    const comp = readStr(cur, 'component');
    if (isNonVisualPluginTag(comp)) { return; }
    const cProps = asObj(cur['props']);
    const lower = comp.toLowerCase();
    if (lower === 'vimg' || lower === 'img') {
      const src = readStr(cProps, 'src') || readStr(cProps, 'lazy-src');
      if (src.length > 0 && imageUrl.length === 0) {
        imageUrl = resolvePluginAssetUrl(src, serverUrl);
      }
      return;
    }
    if (comp === 'VCardTitle' || lower === 'h1' || lower === 'h2' || lower === 'h3' || lower === 'h4') {
      const t = collectPlainText(cur);
      if (t.length > 0) {
        if (title.length === 0) { title = t; } else if (!bodyLines.includes(t)) { bodyLines.push(t); }
      }
      return;
    }
    if (comp === 'VCardSubtitle') {
      const s = collectPlainText(cur);
      if (s.length > 0 && subtitle.length === 0) { subtitle = s; }
      return;
    }
    if (comp === 'VChip') {
      const ch = collectPlainText(cur);
      if (ch.length > 0 && !chips.includes(ch)) { chips.push(ch); }
      return;
    }
    const direct = typeof cur['text'] === 'string' ? (cur['text'] as string).trim() : '';
    if (direct.length > 0 && !direct.startsWith('.') && !direct.includes('{display:') && !bodyLines.includes(direct)) {
      bodyLines.push(direct);
    }
    const ch = asList(cur['content']);
    for (let i = 0; i < ch.length; i++) {
      walkCard(asObj(ch[i]));
    }
  };

  const children = asList(cardNode['content']);
  for (let i = 0; i < children.length; i++) {
    walkCard(asObj(children[i]));
  }

  if (title.length === 0 && subtitle.length === 0 && bodyLines.length === 0 && chips.length === 0 && imageUrl.length === 0) {
    return null;
  }
  return {
    id: id,
    kind: 'card',
    title: title,
    subtitle: subtitle,
    body: bodyLines.join('\n'),
    tone: readStr(props, 'color', 'default'),
    imageUrl: imageUrl.length > 0 ? imageUrl : undefined,
    chips: chips.length > 0 ? chips : undefined
  };
}

function tryExtractStatGridFromRow(rowNode: Record<string, Object>, id: string): PluginDataBlock | null {
  const cols = asList(rowNode['content']);
  if (cols.length < 2) { return null; }
  const stats: PluginStatCell[] = [];
  for (let i = 0; i < cols.length; i++) {
    const col = asObj(cols[i]);
    if (!col) { return null; }
    const comp = readStr(col, 'component');
    if (comp !== 'VCol' && comp !== 'div') { return null; }
    const textSegs: string[] = [];
    const gather = (n: Record<string, Object> | null): void => {
      if (!n) { return; }
      const c = readStr(n, 'component');
      if (isNonVisualPluginTag(c)) { return; }
      if (c === 'VTable' || c === 'table' || c === 'VAlert') { return; }
      const p = asObj(n['props']);
      const pt = readStr(p, 'title').trim();
      const ps = readStr(p, 'subtitle').trim();
      const dt = typeof n['text'] === 'string' ? (n['text'] as string).trim() : '';
      if (pt.length > 0 && !textSegs.includes(pt)) { textSegs.push(pt); }
      if (ps.length > 0 && !textSegs.includes(ps)) { textSegs.push(ps); }
      if (dt.length > 0 && !dt.startsWith('.') && !textSegs.includes(dt)) { textSegs.push(dt); }
      const kids = asList(n['content']);
      for (let k = 0; k < kids.length; k++) { gather(asObj(kids[k])); }
    };
    gather(col);
    if (textSegs.length < 2 || textSegs.length > 4) { return null; }
    // KPI 指标卡通常包含简短标题与数值
    if (textSegs[0].length > 26 || textSegs[1].length > 32) { return null; }
    stats.push({
      label: textSegs[0],
      value: textSegs[1],
      sub: textSegs.length >= 3 ? textSegs.slice(2).join(' · ') : ''
    });
  }
  if (stats.length < 2) { return null; }
  return {
    id: id,
    kind: 'stat_grid',
    title: '',
    body: '',
    tone: 'default',
    stats: stats
  };
}

function extractDataBlocks(nodes: Object[], out: PluginDataBlock[], serverUrl: string = ''): void {
  for (let i = 0; i < nodes.length; i++) {
    const node = asObj(nodes[i]);
    if (!node) { continue; }
    const comp = readStr(node, 'component');
    if (isNonVisualPluginTag(comp)) { continue; }
    const lower = comp.toLowerCase();
    const props = asObj(node['props']);
    const text = typeof node['text'] === 'string' ? (node['text'] as string) : '';

    if (comp === 'VTable' || comp === 'VSimpleTable' || lower === 'table') {
      const tbl = extractTableBlock(node, `b_${out.length}`);
      if (tbl) {
        out.push(tbl);
        continue;
      }
    }

    if (comp === 'VRow') {
      const statGrid = tryExtractStatGridFromRow(node, `b_${out.length}`);
      if (statGrid) {
        out.push(statGrid);
        continue;
      }
    }

    if (lower === 'vimg' || lower === 'img') {
      const src = resolvePluginAssetUrl(readStr(props, 'src') || readStr(props, 'lazy-src'), serverUrl);
      if (src.length > 0) {
        out.push({
          id: `b_${out.length}`,
          kind: 'image',
          title: readStr(props, 'alt') || readStr(props, 'title'),
          body: '',
          tone: 'default',
          imageUrl: src
        });
        continue;
      }
    }

    if (comp === 'VCard') {
      // 如果 VCard 内不含嵌套表格，则聚合为结构化原生卡片
      const rawCardJson = JSON.stringify(node);
      if (!rawCardJson.includes('"VTable"') && !rawCardJson.includes('"table"')) {
        const cardBlk = extractCardSummary(node, serverUrl, `b_${out.length}`);
        if (cardBlk) {
          out.push(cardBlk);
          continue;
        }
      }
    }

    if (comp === 'VAlert') {
      const body = text || readStr(props, 'text') || collectPlainText(node);
      if (body.length > 0) {
        out.push({
          id: `b_${out.length}`,
          kind: 'alert',
          title: readStr(props, 'title'),
          body: body,
          tone: readStr(props, 'type', 'info')
        });
        continue;
      }
    } else if (comp === 'VChip' || comp === 'VCardTitle' || comp === 'VCardSubtitle' || comp === 'VCardText'
      || lower === 'span' || lower === 'p' || lower === 'div'
      || lower === 'h1' || lower === 'h2' || lower === 'h3' || lower === 'h4') {
      const trimmed = text.trim();
      if (trimmed.length > 0 && !trimmed.startsWith('.') && !trimmed.includes('{display:') && !trimmed.includes('!important')) {
        out.push({
          id: `b_${out.length}`,
          kind: comp === 'VChip' ? 'chip' : ((comp === 'VCardTitle' || lower.startsWith('h')) ? 'heading' : 'text'),
          title: (comp === 'VCardTitle' || lower.startsWith('h')) ? trimmed : '',
          body: trimmed,
          tone: readStr(props, 'color', 'default')
        });
      }
    }

    const content = asList(node['content']);
    if (content.length > 0) {
      extractDataBlocks(content, out, serverUrl);
    }
  }
}

function jsEscape(raw: string): string {
  return raw
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\r/g, '')
    .replace(/\n/g, '\\n');
}

/**
 * 鸿蒙原生 Vuetify 插件数据页渲染器（消费 `/api/v1/plugin/page/{id}`）：
 * 支持结构化 KPI 指标网格、表格、图片、聚合卡片与告警块；若为 Vue 联邦插件则无缝切入隔离容器。
 */
@Component
export struct NativePluginDataPageView {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop pluginId: string = '';
  @Prop documentJson: string = '{}';
  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop pluginHasPage: boolean = true;
  chromeController: HarmonyVueChromeController | null = null;
  onChromeTitleChange: (title: string) => void = () => {};
  onChromeActionsChange: (actions: VueChromeAction[]) => void = () => {};
  onRequestDismiss: () => void = () => {};
  @State private renderMode: string = 'vuetify';
  @State private blocks: PluginDataBlock[] = [];

  aboutToAppear(): void {
    const unwrapped = unwrapV3Envelope(this.documentJson);
    const mode = readStr(unwrapped, 'render_mode', 'vuetify').toLowerCase();
    this.renderMode = mode;
    if (mode !== 'vue' && unwrapped) {
      const pageNodes = asList(unwrapped['page']);
      const parsed: PluginDataBlock[] = [];
      extractDataBlocks(pageNodes, parsed, this.serverUrl);
      this.blocks = parsed;
    }
  }

  private alertTint(tone: string): string {
    const t = tone.toLowerCase();
    if (t === 'error' || t === 'danger') { return '#E84855'; }
    if (t === 'warning' || t === 'warn') { return '#F29B38'; }
    if (t === 'success') { return '#34C759'; }
    return this.accentHex;
  }

  private statColumnsTemplate(): string {
    if (this.windowWidthVp >= 840) { return '1fr 1fr 1fr 1fr'; }
    if (this.windowWidthVp >= 560) { return '1fr 1fr 1fr'; }
    return '1fr 1fr';
  }

  build() {
    if (this.renderMode === 'vue' || this.blocks.length === 0) {
      IsolatedVuePluginWebView({
        pluginId: this.pluginId,
        serverUrl: this.serverUrl,
        authToken: this.authToken,
        userName: this.userName,
        userAvatar: this.userAvatar,
        isSuperuser: this.isSuperuser,
        switchesToConfig: false,
        chromeController: this.chromeController,
        onChromeTitleChange: this.onChromeTitleChange,
        onChromeActionsChange: this.onChromeActionsChange,
        onRequestDismiss: this.onRequestDismiss
      })
    } else {
      Scroll() {
        Column() {
          Column({ space: 10 }) {
            ForEach(this.blocks, (blk: PluginDataBlock) => {
              if (blk.kind === 'stat_grid' && blk.stats && blk.stats.length > 0) {
                Grid() {
                  ForEach(blk.stats, (st: PluginStatCell, sIdx: number) => {
                    GridItem() {
                      CinematicPanel({ panelPadding: 13, cornerRadius: 16 }) {
                        Column({ space: 4 }) {
                          Text(st.label)
                            .fontSize(11.5)
                            .fontColor(mpSecondaryText(this.isDark))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                          Text(st.value)
                            .fontSize(18)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(mpPrimaryText(this.isDark))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                          if (st.sub.length > 0) {
                            Text(st.sub)
                              .fontSize(10.5)
                              .fontColor(this.accentHex)
                              .maxLines(1)
                              .width('100%')
                          }
                        }.alignItems(HorizontalAlign.Start).width('100%')
                      }
                    }
                  }, (st: PluginStatCell, sIdx: number) => `${blk.id}_st_${sIdx}_${st.label}`)
                }
                .columnsTemplate(this.statColumnsTemplate())
                .columnsGap(10)
                .rowsGap(10)
                .width('100%')
              } else if (blk.kind === 'table') {
                CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
                  Scroll() {
                    Column({ space: 6 }) {
                      if (blk.headers && blk.headers.length > 0) {
                        Row({ space: 8 }) {
                          ForEach(blk.headers, (hd: string, hIdx: number) => {
                            Text(hd)
                              .fontSize(12)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(mpSecondaryText(this.isDark))
                              .width(108)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                          }, (hd: string, hIdx: number) => `${blk.id}_th_${hIdx}_${hd}`)
                        }
                        .padding({ top: 4, bottom: 6 })
                        Divider().color(HarmonyThemeColors.divider(this.isDark))
                      }
                      if (blk.rows) {
                        ForEach(blk.rows.slice(0, 40), (r: string[], rIdx: number) => {
                          Row({ space: 8 }) {
                            ForEach(r, (cell: string, cIdx: number) => {
                              Text(cell)
                                .fontSize(12)
                                .fontColor(mpPrimaryText(this.isDark))
                                .width(108)
                                .maxLines(2)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                            }, (_cell: string, cIdx: number) => `${blk.id}_td_${rIdx}_${cIdx}`)
                          }
                          .padding({ top: 5, bottom: 5 })
                          .borderRadius(8)
                          .backgroundColor(rIdx % 2 === 1 ? (this.isDark ? '#0DFFFFFF' : '#08000000') : Color.Transparent)
                        }, (_r: string[], rIdx: number) => `${blk.id}_tr_${rIdx}`)
                      }
                    }.alignItems(HorizontalAlign.Start)
                  }
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Off)
                  .width('100%')
                }
              } else if (blk.kind === 'image' && blk.imageUrl && blk.imageUrl.length > 0) {
                CinematicPanel({ panelPadding: 10, cornerRadius: 16 }) {
                  Column({ space: 6 }) {
                    MpRemoteImage({
                      src: blk.imageUrl,
                      imgWidth: '100%',
                      imgHeight: 170,
                      imgRadius: 12,
                      fit: ImageFit.Contain,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })
                    if (blk.title.length > 0) {
                      Text(blk.title).fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
                    }
                  }
                }
              } else if (blk.kind === 'card') {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                  Column({ space: 6 }) {
                    if (blk.imageUrl && blk.imageUrl.length > 0) {
                      MpRemoteImage({
                        src: blk.imageUrl,
                        imgWidth: '100%',
                        imgHeight: 148,
                        imgRadius: 10,
                        placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                      })
                    }
                    if (blk.title.length > 0) {
                      Text(blk.title)
                        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
                    }
                    if (blk.subtitle && blk.subtitle.length > 0) {
                      Text(blk.subtitle)
                        .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
                    }
                    if (blk.chips && blk.chips.length > 0) {
                      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                        ForEach(blk.chips, (ch: string, cIdx: number) => {
                          NativeAdaptiveBadge({ text: ch, tintHex: this.accentHex })
                        }, (ch: string, cIdx: number) => `${blk.id}_ch_${cIdx}_${ch}`)
                      }.width('100%')
                    }
                    if (blk.body.length > 0) {
                      Text(blk.body)
                        .fontSize(13).fontColor(mpSecondaryText(this.isDark)).lineHeight(20).width('100%')
                    }
                  }.alignItems(HorizontalAlign.Start).width('100%')
                }
              } else if (blk.kind === 'alert') {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                  Column({ space: 4 }) {
                    if (blk.title.length > 0) {
                      Text(blk.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.alertTint(blk.tone))
                    }
                    Text(blk.body).fontSize(13).fontColor(mpPrimaryText(this.isDark)).lineHeight(20)
                  }.alignItems(HorizontalAlign.Start).width('100%')
                }
              } else if (blk.kind === 'heading') {
                Text(blk.body)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .width('100%')
                  .margin({ top: 4 })
              } else if (blk.kind === 'chip') {
                NativeAdaptiveBadge({ text: blk.body, tintHex: this.accentHex })
              } else {
                CinematicPanel({ panelPadding: 13, cornerRadius: 14 }) {
                  Text(blk.body).fontSize(13).fontColor(mpSecondaryText(this.isDark)).lineHeight(20).width('100%')
                }
              }
            }, (blk: PluginDataBlock) => blk.id)
          }
          .width('100%')
          .constraintSize({ maxWidth: 860 })
          .padding({ left: 16, right: 16, top: 8, bottom: 28 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
  }
}

/**
 * 鸿蒙受控隔离 Vue 模块联邦 ArkWeb 容器（1:1 实现 `moviepilot.chrome` v1 + `sheets.v1` + `confirmations.v1`）：
 * - 免二次点击直接进入，免登录自动注入 Pinia `auth`/`user`/`theme`/`MP_LOCALE`；
 * - 使用系统级 `UIContext.showAlertDialog` 响应 `confirmations.v1` 确认对话，零自定义 `Stack` 遮罩；
 * - 严格使用 `RustCoreBridge.serverAddressContains` 锁定同源导航并在销毁时清空 Cookie。
 */
@Component
export struct IsolatedVuePluginWebView {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) @Watch('onHostWindowResize') windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) @Watch('onHostWindowResize') windowHeightVp: number = 892;
  @Prop pluginId: string = '';
  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop switchesToConfig: boolean = false;
  chromeController: HarmonyVueChromeController | null = null;
  onChromeTitleChange: (title: string) => void = () => {};
  onChromeActionsChange: (actions: VueChromeAction[]) => void = () => {};
  onRequestDismiss: () => void = () => {};

  @State private isReady: boolean = false;
  private activeConfirmationId: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  private phase: string = 'idle'; // idle | configured | preparing | active | released
  private sessionId: string = '';
  private routeRevision: number = 0;
  private stateRevision: number = 0;
  private layoutRevision: number = 0;
  private webWidthVp: number = 0;
  private webHeightVp: number = 0;
  private seq: number = 0;
  private currentSheetId: string = '';
  private currentSheetCanDismiss: boolean = false;
  private attachedSheetId: string = '';
  private hasPresentedSheet: boolean = false;
  private closeRequested: boolean = false;
  private configSwitchDone: boolean = false;
  private configSwitchAttempts: number = 0;
  private latestSnapshot: Record<string, Object> | null = null;
  private fallbackTimer: number = -1;
  private dismissTimer: number = -1;
  private proxyObj: HarmonyChromeBridgeProxy = new HarmonyChromeBridgeProxy((raw: string) => {
    this.handleChromeMessage(raw);
  });

  private allowedOrigin(): string {
    return this.serverUrl.replace(/\/+$/, '');
  }

  private targetUrl(): string {
    return `${this.allowedOrigin()}/#/plugins?id=${encodeURIComponent(this.pluginId)}&tab=installed`;
  }

  aboutToAppear(): void {
    if (this.chromeController) {
      this.chromeController.invokeActionHandler = (actionId: string) => {
        this.invokeSheetAction(actionId);
      };
      this.chromeController.requestCloseHandler = () => {
        return this.requestCloseCurrentSheet();
      };
    }
    this.fallbackTimer = setTimeout(() => {
      if (!this.isReady) {
        this.releaseToWebContent();
      }
    }, 10000);
  }

  aboutToDisappear(): void {
    if (this.fallbackTimer !== -1) {
      clearTimeout(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
    if (this.dismissTimer !== -1) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = -1;
    }
    if (this.chromeController) {
      this.chromeController.invokeActionHandler = null;
      this.chromeController.requestCloseHandler = null;
    }
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch {
      // 清理受控隔离宿主残留 Cookie
    }
  }

  private buildDocumentStartScript(): string {
    const themeName = this.isDark ? 'dark' : 'light';
    const authJson = `{"token":"${jsEscape(this.authToken)}","remember":true,"originalPath":null}`;
    const userJson = `{"superUser":${this.isSuperuser},"userID":1,"userName":"${jsEscape(this.userName)}","avatar":"${jsEscape(this.userAvatar)}","level":2,"permissions":{"discovery":true,"search":true,"subscribe":true,"manage":true,"admin":${this.isSuperuser},"features":{}}}`;
    const customizerJson = `{"theme":"${themeName}","primaryColor":"${jsEscape(this.accentHex)}"}`;
    return `(function(){
if(window.top!==window)return;
try{
  var needsReload=!window.localStorage.getItem('auth');
  window.localStorage.setItem('auth','${jsEscape(authJson)}');
  window.localStorage.setItem('user','${jsEscape(userJson)}');
  window.localStorage.setItem('MP_LOCALE','zh-CN');
  window.localStorage.setItem('theme','${themeName}');
  window.localStorage.setItem('materio-initial-resolved-theme','${themeName}');
  window.localStorage.setItem('materio-initial-loader-color','${jsEscape(this.accentHex)}');
  window.localStorage.setItem('moviepilot-theme-customizer','${jsEscape(customizerJson)}');
  if(needsReload&&!window.__mpNativeReloaded){
    window.__mpNativeReloaded=true;
    window.location.reload();
    return;
  }
}catch(e){}
function applyStyle(){
  try{
    if(document.getElementById('mp-native-vue-plugin-style'))return;
    var s=document.createElement('style');
    s.id='mp-native-vue-plugin-style';
    s.textContent=[
      '.layout-navbar,.layout-vertical-nav,.layout-overlay,.layout-footer,.footer-content-container,',
      '.mobile-dock,.v-bottom-navigation,.app-customizer-toggler,.agent-pet-container,',
      '.agent-pet-stage-layer,.agent-assistant-fab,.floating-agent-btn,',
      '[data-native-page-title],[data-native-page-heading],[data-native-page-actions]{display:none!important;}',
      'html,body,#app,.v-application,.v-application__wrap{background:transparent!important;background-image:none!important;}',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>*,',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>.v-card,',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current] [class*="dialog-card"],',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current] [class*="plugin-config"],',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current] [class*="plugin-page"]{',
      'background:transparent!important;background-color:transparent!important;background-image:none!important;',
      'backdrop-filter:none!important;-webkit-backdrop-filter:none!important;',
      'border:0!important;border-radius:0!important;box-shadow:none!important;}',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>*::before,',
      'html[data-native-chrome="active"][data-native-sheet] [data-native-sheet-current]>.v-overlay__content>*::after{display:none!important;}'
    ].join('\\n');
    (document.head||document.documentElement).appendChild(s);
  }catch(e){}
}
applyStyle();
document.addEventListener('DOMContentLoaded',applyStyle,{once:true});
if(!window.MoviePilotNative&&window.__mpHarmonyChromeHost){
  Object.defineProperty(window,'MoviePilotNative',{
    value:Object.freeze({
      transportVersion:1,
      sheetsVersion:1,
      confirmationsVersion:1,
      postMessage:function(msg){try{window.__mpHarmonyChromeHost.postMessage(JSON.stringify(msg));}catch(e){}},
      authenticationRequired:function(){try{window.__mpHarmonyChromeHost.postMessage(JSON.stringify({kind:'authentication.required'}));}catch(e){}}
    }),
    configurable:false,
    writable:false
  });
  function extractMdi(el){
    var ic=el.querySelector('[class*="mdi-"]')||(el.className&&String(el.className).indexOf('mdi-')>=0?el:null);
    if(ic){var m=String(ic.className||'').match(/mdi-[a-z0-9-]+/i);if(m)return m[0].toLowerCase();}
    var vi=el.querySelector('.v-icon');
    if(vi){var t=(vi.textContent||'').trim().toLowerCase();if(t.indexOf('mdi-')===0)return t;}
    return '';
  }
  function isCloseLike(btn,icon,rawText,aria){
    var cls=String(btn.className||'').toLowerCase();
    return btn.classList.contains('v-dialog-close-btn')||cls.indexOf('close')>=0
      ||icon==='mdi-close'||icon==='mdi-close-circle'||icon==='mdi-close-circle-outline'
      ||rawText==='关闭'||rawText==='Close'||rawText==='×'||rawText==='✕'
      ||aria==='关闭'||aria==='Close';
  }
  function normalizeHeaders(){
    var dialogs=document.querySelectorAll('.v-overlay--active.v-dialog');
    for(var d=0;d<dialogs.length;d++){
      var root=dialogs[d];
      var header=root.querySelector('[data-native-dialog-header]')
        ||root.querySelector(':scope > .v-overlay__content > .v-card > .v-card-item, :scope > .v-overlay__content > .v-card > .v-toolbar, :scope > .v-overlay__content > .v-card > .v-card-title')
        ||root.querySelector('.v-card-item, .v-toolbar');
      if(!header||header.closest('[data-native-dialog-content]'))continue;
      if(!header.hasAttribute('data-native-dialog-header')&&!header.matches('.v-card-item,.v-toolbar,.v-card-title')){
        header.setAttribute('data-native-dialog-header','');
      }
      if(!root.querySelector('[data-native-dialog-title]')){
        var hd=header.querySelector('.v-card-title,.v-toolbar-title,h1,h2,h3,[class*="title"]');
        if(hd&&!hd.querySelector('button'))hd.setAttribute('data-native-dialog-title','');
      }
      var hasClose=Boolean(root.querySelector('[data-native-dialog-close]'));
      var btns=header.querySelectorAll('button');
      for(var i=0;i<btns.length;i++){
        var btn=btns[i];
        if(btn.getClientRects().length===0)continue;
        if(btn.hasAttribute('data-native-dialog-close'))continue;
        var icon=extractMdi(btn);
        var txt=(btn.textContent||'').replace(/mdi-[a-z0-9-]+/gi,'').trim();
        var aria=(btn.getAttribute('aria-label')||'').trim();
        if(isCloseLike(btn,icon,txt,aria)){
          if(!hasClose){btn.setAttribute('data-native-dialog-close','');hasClose=true;}
          else{btn.setAttribute('aria-hidden','true');}
          continue;
        }
        if(icon&&!btn.hasAttribute('data-native-sheet-action')&&!header.hasAttribute('data-native-sheet-actions')){
          btn.setAttribute('data-native-sheet-action',icon);
        }
      }
    }
  }
  function bootObserver(){
    if(!document.body)return;
    normalizeHeaders();
    new MutationObserver(function(){normalizeHeaders();}).observe(document.body,{childList:true,subtree:true});
  }
  if(document.body)bootObserver();else document.addEventListener('DOMContentLoaded',bootObserver,{once:true});
  window.__mpNativeSwitchToConfig=function(){
    var dialogs=Array.prototype.slice.call(document.querySelectorAll('.v-overlay--active.v-dialog'));
    if(!dialogs.length)return false;
    var btns=dialogs[dialogs.length-1].querySelectorAll('button,.v-btn');
    for(var i=0;i<btns.length;i++){
      var b=btns[i];var ic=extractMdi(b);
      var tx=(b.textContent||'').replace(/mdi-[a-z0-9-]+/gi,'').trim();
      var lb=(b.getAttribute('aria-label')||'').trim();
      if(ic==='mdi-cog'||ic==='mdi-cog-outline'||ic==='mdi-tune'||tx==='设置'||tx==='配置'||tx.indexOf('前往配置')>=0||lb==='设置'||lb==='Settings'){
        b.click();return true;
      }
    }
    return false;
  };
}
})();`;
  }

  private sendChromeEnvelope(msgType: string, payloadJson: string, sessionOverride: string = ''): void {
    this.seq += 1;
    const reqId = `harmony-msg-${this.seq}`;
    const activeSession = sessionOverride.length > 0 ? sessionOverride : this.sessionId;
    const sessionPart = activeSession.length > 0
      ? `,"sessionId":"${activeSession}","routeRevision":${this.routeRevision},"stateRevision":${this.stateRevision}`
      : '';
    const envelope = `{"protocol":"moviepilot.chrome","major":1,"type":"${msgType}","requestId":"${reqId}","payload":${payloadJson}${sessionPart}}`;
    try {
      this.webController.runJavaScript(`window.dispatchEvent(new CustomEvent('moviepilot:native-message',{detail:${envelope}}));`);
    } catch {
      // ignore if webview not yet attached
    }
  }

  private effectiveWebWidthVp(): number {
    return Math.max(240, Math.round(this.webWidthVp > 0 ? this.webWidthVp : this.windowWidthVp));
  }

  private effectiveWebHeightVp(): number {
    return Math.max(180, Math.round(this.webHeightVp > 0 ? this.webHeightVp : this.windowHeightVp));
  }

  onHostWindowResize(): void {
    if (this.phase === 'active' && this.webWidthVp <= 0) {
      this.sendChromeEnvelope('host.layout', this.layoutPayloadJson());
    }
  }

  private layoutPayloadJson(): string {
    this.layoutRevision += 1;
    const zero = '{"top":0,"left":0,"bottom":0,"right":0}';
    const w = this.effectiveWebWidthVp();
    const h = this.effectiveWebHeightVp();
    return `{"layoutRevision":${this.layoutRevision},"viewportPoints":{"width":${w},"height":${h}},"contentInsets":${zero},"systemSafeArea":${zero},"chromeOcclusion":${zero},"keyboardOcclusion":0,"consumedByNativeFrame":true}`;
  }

  private handleChromeMessage(rawJson: string): void {
    let body: Record<string, Object> | null = null;
    try {
      body = asObj(JSON.parse(rawJson) as Object);
    } catch {
      return;
    }
    if (!body) { return; }
    if (readStr(body, 'kind') === 'authentication.required') {
      this.reveal();
      return;
    }
    if (readStr(body, 'protocol') !== 'moviepilot.chrome') { return; }
    const msgType = readStr(body, 'type');
    const payload = asObj(body['payload']) ?? {};
    if (msgType !== 'web.ready' && readStr(body, 'sessionId') !== this.sessionId) { return; }
    const rr = Number(body['routeRevision']);
    if (Number.isFinite(rr) && rr >= 0) { this.routeRevision = rr; }
    const sr = Number(body['stateRevision']);
    if (Number.isFinite(sr) && sr >= 0) { this.stateRevision = sr; }

    if (msgType === 'web.ready') {
      const id = `harmony-${Date.now()}-${this.seq + 1}`;
      this.sessionId = id;
      this.phase = 'configured';
      this.currentSheetId = '';
      this.attachedSheetId = '';
      this.sendChromeEnvelope('host.configure',
        `{"sessionId":"${id}","major":1,"capabilities":["actions.v1","layout.v1","menu.v1","navigation.v1"]}`);
    } else if (msgType === 'navigation.state') {
      this.latestSnapshot = payload;
      if (this.phase === 'configured') {
        this.phase = 'preparing';
        this.sendChromeEnvelope('chrome.prepare', this.layoutPayloadJson());
      } else if (this.phase === 'active') {
        this.applySnapshot(payload);
      }
    } else if (msgType === 'chrome.accepted') {
      if (this.phase !== 'preparing') { return; }
      this.phase = 'active';
      if (this.latestSnapshot) {
        this.applySnapshot(this.latestSnapshot);
      }
    } else if (msgType === 'session.state') {
      if (this.phase !== 'active' || this.sessionId.length === 0) { return; }
      const prev = this.sessionId;
      const next = `harmony-${Date.now()}-${this.seq + 1}`;
      this.sendChromeEnvelope('host.rekey', `{"sessionId":"${next}"}`, prev);
      this.sessionId = next;
    } else if (msgType === 'chrome.failed') {
      this.releaseToWebContent();
    }
  }

  private presentSystemConfirmation(conf: VueChromeConfirmation): void {
    if (this.activeConfirmationId === conf.id) { return; }
    this.activeConfirmationId = conf.id;
    this.getUIContext().showAlertDialog({
      title: conf.title,
      message: conf.message.length > 0 ? conf.message : '请确认是否继续此操作？',
      autoCancel: true,
      primaryButton: {
        value: conf.cancelText,
        action: () => {
          this.respondConfirmation(conf.id, false);
        }
      },
      secondaryButton: {
        value: conf.confirmText,
        fontColor: conf.destructive ? '#FF5C6C' : this.accentHex,
        action: () => {
          this.respondConfirmation(conf.id, true);
        }
      },
      cancel: () => {
        this.respondConfirmation(conf.id, false);
      }
    });
  }

  private applySnapshot(snapshot: Record<string, Object>): void {
    const presentation = asObj(snapshot['presentation']);
    const conf = presentation ? asObj(presentation['confirmation']) : null;
    if (conf && readStr(conf, 'id').length > 0) {
      this.presentSystemConfirmation({
        id: readStr(conf, 'id'),
        title: readStr(conf, 'title', '操作确认'),
        message: readStr(conf, 'message'),
        confirmText: readStr(conf, 'confirmText', '确认'),
        cancelText: readStr(conf, 'cancelText', '取消'),
        destructive: readBool(conf, 'destructive', false)
      });
    } else {
      this.activeConfirmationId = '';
    }

    const sheet = presentation ? asObj(presentation['sheet']) : null;
    const sheetId = readStr(sheet, 'id');
    if (!sheet || sheetId.length === 0) {
      this.currentSheetId = '';
      this.currentSheetCanDismiss = false;
      if (this.closeRequested) {
        this.onRequestDismiss();
      } else if (this.hasPresentedSheet) {
        if (this.dismissTimer !== -1) { clearTimeout(this.dismissTimer); }
        this.dismissTimer = setTimeout(() => {
          if (this.currentSheetId.length === 0 && this.hasPresentedSheet) {
            this.onRequestDismiss();
          }
        }, 1200);
      }
      return;
    }
    if (this.dismissTimer !== -1) {
      clearTimeout(this.dismissTimer);
      this.dismissTimer = -1;
    }
    if (sheetId !== this.currentSheetId) {
      this.closeRequested = false;
    }
    this.currentSheetId = sheetId;
    this.currentSheetCanDismiss = readBool(sheet, 'canDismiss', true);

    const routeObj = asObj(snapshot['route']);
    const pageTitle = readStr(routeObj, 'title');
    const sheetTitle = readStr(sheet, 'title');
    if (sheetTitle.length > 0 && sheetTitle !== 'MoviePilot' && sheetTitle !== pageTitle) {
      this.onChromeTitleChange(sheetTitle);
    }

    const rawActions = asList(sheet['actions']);
    const nextActions: VueChromeAction[] = [];
    for (let i = 0; i < rawActions.length; i++) {
      const a = asObj(rawActions[i]);
      if (!a) { continue; }
      const id = readStr(a, 'id');
      const title = readStr(a, 'title');
      if (id.length > 0 && title.length > 0) {
        nextActions.push({
          id: id,
          title: title,
          icon: readStr(a, 'icon'),
          enabled: readBool(a, 'enabled', true)
        });
      }
    }
    this.onChromeActionsChange(nextActions);

    if (sheetId === this.attachedSheetId) { return; }
    if (this.switchesToConfig && !this.configSwitchDone) {
      this.attemptSwitchToConfig(sheetId);
      return;
    }
    this.attachSheet(sheetId);
  }

  private attachSheet(sheetId: string): void {
    this.attachedSheetId = sheetId;
    this.hasPresentedSheet = true;
    this.sendChromeEnvelope('presentation.attach', `{"id":"${jsEscape(sheetId)}"}`);
    this.reveal();
  }

  private attemptSwitchToConfig(sheetId: string): void {
    this.configSwitchAttempts += 1;
    try {
      this.webController.runJavaScript('window.__mpNativeSwitchToConfig?window.__mpNativeSwitchToConfig():false;', (_err, res) => {
        const switched = (res ?? '').trim() === 'true';
        if (switched || this.configSwitchAttempts >= 8) {
          this.configSwitchDone = true;
          if (!switched) {
            this.attachSheet(sheetId);
          }
          return;
        }
        setTimeout(() => {
          if (this.phase === 'active' && this.latestSnapshot) {
            this.applySnapshot(this.latestSnapshot);
          }
        }, 250);
      });
    } catch {
      this.configSwitchDone = true;
      this.attachSheet(sheetId);
    }
  }

  private invokeSheetAction(actionId: string): void {
    if (this.phase !== 'active' || this.currentSheetId.length === 0) { return; }
    this.sendChromeEnvelope('presentation.action', `{"id":"${jsEscape(this.currentSheetId)}","actionId":"${jsEscape(actionId)}"}`);
  }

  private requestCloseCurrentSheet(): boolean {
    if (this.phase !== 'active' || this.currentSheetId.length === 0 || !this.currentSheetCanDismiss) {
      return false;
    }
    this.closeRequested = true;
    this.sendChromeEnvelope('presentation.dismiss', `{"id":"${jsEscape(this.currentSheetId)}"}`);
    setTimeout(() => {
      if (this.closeRequested) {
        this.onRequestDismiss();
      }
    }, 900);
    return true;
  }

  private respondConfirmation(confId: string, confirmed: boolean): void {
    if (this.activeConfirmationId === confId) {
      this.activeConfirmationId = '';
    }
    if (confId.length === 0 || this.phase !== 'active') { return; }
    this.sendChromeEnvelope('confirmation.respond', `{"id":"${jsEscape(confId)}","confirmed":${confirmed}}`);
  }

  private reveal(): void {
    if (this.fallbackTimer !== -1) {
      clearTimeout(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
    this.isReady = true;
  }

  private releaseToWebContent(): void {
    if (this.phase === 'released') { return; }
    if (this.sessionId.length > 0 && (this.phase === 'active' || this.phase === 'preparing')) {
      this.sendChromeEnvelope('chrome.release', '{}');
    }
    this.phase = 'released';
    this.reveal();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Web({ src: this.targetUrl(), controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .backgroundColor(HarmonyThemeColors.canvas(this.isDark))
        .javaScriptProxy({
          object: this.proxyObj,
          name: '__mpHarmonyChromeHost',
          methodList: ['postMessage'],
          controller: this.webController
        })
        .javaScriptOnDocumentStart([
          { script: this.buildDocumentStartScript(), scriptRules: ['*'] }
        ])
        .onLoadIntercept((ev) => {
          const target = ev.data.getRequestUrl();
          return !RustCoreBridge.serverAddressContains(this.serverUrl, target);
        })
        .opacity(this.isReady ? 1 : 0.01)
        .width('100%')
        .height('100%')

      if (!this.isReady) {
        Scroll() {
          Column() {
            HarmonyPluginSheetSkeleton()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyThemeColors.canvas(this.isDark))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextW = Math.round(Number(newArea.width));
      const nextH = Math.round(Number(newArea.height));
      if (Number.isFinite(nextW) && nextW > 0 && Number.isFinite(nextH) && nextH > 0) {
        const changed = Math.abs(nextW - this.webWidthVp) >= 1 || Math.abs(nextH - this.webHeightVp) >= 1;
        this.webWidthVp = nextW;
        this.webHeightVp = nextH;
        if (changed && this.phase === 'active') {
          this.sendChromeEnvelope('host.layout', this.layoutPayloadJson());
        }
      }
    })
  }
}

/**
 * 鸿蒙原生动态插件表单宿主（100% 消费 Rust `planPluginFormJson` + `evaluatePluginExpression` + `applyPluginFormPatch` + `analyzeCron`）：
 * - 每次修改字段均生成全新 `draftModel` 引用以触发 ArkUI 响应式刷新，并实时重算 `v-if`/`v-show` 条件可见性；
 * - 若插件声明 `render_mode == 'vue'` 或无可映射原生字段，零提示直接无缝切入受控隔离 ArkWeb 联邦容器。
 */
@Component
export struct NativePluginHostView {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop pluginName: string = '';
  @Prop documentJson: string = '{}';
  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop pluginHasPage: boolean = false;
  chromeController: HarmonyVueChromeController | null = null;
  onChromeTitleChange: (title: string) => void = () => {};
  onChromeActionsChange: (actions: VueChromeAction[]) => void = () => {};
  onRequestDismiss: () => void = () => {};
  onSaveFullModel: (fullJson: string) => void = () => {};

  @State private renderMode: string = 'vuetify';
  @State private fields: PluginFieldPlan[] = [];
  @State private draftModel: Record<string, Object> = {};
  @State private draftVersion: number = 0;
  @State private saving: boolean = false;
  private originalModelJson: string = '{}';
  private unwrappedTemplate: Record<string, Object> | null = null;

  aboutToAppear(): void {
    const unwrapped = unwrapV3Envelope(this.documentJson);
    this.unwrappedTemplate = unwrapped;
    const unwrappedJson = unwrapped ? JSON.stringify(unwrapped) : this.documentJson;
    const rawRenderMode = readStr(unwrapped, 'render_mode', '').toLowerCase();

    const exprMap = new Map<string, string>();
    if (unwrapped) {
      collectModelVisibilityExprs(asList(unwrapped['conf']), '', exprMap);
    }

    try {
      const planned = asObj(JSON.parse(RustCoreBridge.planPluginFormJson(unwrappedJson)) as Object);
      const rustMode = readStr(planned, 'renderMode', 'vuetify').toLowerCase();
      this.renderMode = rawRenderMode.length > 0 ? rawRenderMode : rustMode;
      const rustFields = planned ? asList(planned['fields']) : [];
      const mapped: PluginFieldPlan[] = [];
      for (let i = 0; i < rustFields.length; i++) {
        const f = asObj(rustFields[i]);
        if (!f) { continue; }
        const mk = readStr(f, 'modelKey');
        const expr = readStr(f, 'visibleExpr') || readStr(f, 'vIf') || (mk.length > 0 ? (exprMap.get(mk) ?? '') : '');
        mapped.push({
          component: readStr(f, 'component'),
          modelKey: mk.length > 0 ? mk : undefined,
          label: readStr(f, 'label'),
          hint: readStr(f, 'hint'),
          visible: readBool(f, 'visible', true),
          visibleExpr: expr.length > 0 ? expr : undefined,
          text: readStr(f, 'text'),
          multiple: readBool(f, 'multiple', false),
          items: parseSelectItems(f['items'])
        });
      }
      const rustModel = planned ? asObj(planned['model']) : null;
      const rawModel = unwrapped ? asObj(unwrapped['model']) : null;
      const modelObj: Record<string, Object> = copyRecord((rustModel && Object.keys(rustModel).length > 0)
        ? rustModel
        : (rawModel ?? {}));
      this.originalModelJson = JSON.stringify(modelObj);
      this.draftModel = modelObj;

      if (mapped.length > 0) {
        this.fields = this.recomputeFieldVisibility(mapped, modelObj);
      } else if (unwrapped) {
        const fallbackFields: PluginFieldPlan[] = [];
        const confNodes = asList(unwrapped['conf']);
        extractFallbackFormFields(confNodes.length > 0 ? confNodes : asList(unwrapped['page']), fallbackFields);
        this.fields = this.recomputeFieldVisibility(fallbackFields, modelObj);
      }
    } catch {
      this.renderMode = rawRenderMode.length > 0 ? rawRenderMode : 'vuetify';
      const fallbackFields: PluginFieldPlan[] = [];
      let modelObj: Record<string, Object> = {};
      if (unwrapped) {
        extractFallbackFormFields(asList(unwrapped['conf']), fallbackFields);
        modelObj = copyRecord(asObj(unwrapped['model']) ?? {});
        this.originalModelJson = JSON.stringify(modelObj);
        this.draftModel = modelObj;
      }
      this.fields = this.recomputeFieldVisibility(fallbackFields, modelObj);
    }
  }

  private recomputeFieldVisibility(sourceFields: PluginFieldPlan[], nextModel: Record<string, Object>): PluginFieldPlan[] {
    const modelJson = JSON.stringify(nextModel);
    // 同步尝试委托 Rust `planPluginFormJson` 重算含匿名条件块在内的可见性
    let rustVisibleByIndex: Map<number, boolean> | null = null;
    if (this.unwrappedTemplate && RustCoreBridge.isNativeLoaded()) {
      try {
        const nextDoc = copyRecord(this.unwrappedTemplate);
        nextDoc['model'] = nextModel;
        const rePlanned = asObj(JSON.parse(RustCoreBridge.planPluginFormJson(JSON.stringify(nextDoc))) as Object);
        const reFields = rePlanned ? asList(rePlanned['fields']) : [];
        if (reFields.length === sourceFields.length) {
          rustVisibleByIndex = new Map<number, boolean>();
          for (let i = 0; i < reFields.length; i++) {
            const rf = asObj(reFields[i]);
            rustVisibleByIndex.set(i, readBool(rf, 'visible', true));
          }
        }
      } catch {
        rustVisibleByIndex = null;
      }
    }

    const updated: PluginFieldPlan[] = [];
    for (let i = 0; i < sourceFields.length; i++) {
      const f = sourceFields[i];
      let nextVisible = f.visible;
      if (f.visibleExpr && f.visibleExpr.length > 0) {
        nextVisible = RustCoreBridge.evaluatePluginExpression(f.visibleExpr, modelJson);
      } else if (rustVisibleByIndex && rustVisibleByIndex.has(i)) {
        nextVisible = rustVisibleByIndex.get(i) ?? true;
      }
      updated.push({
        component: f.component,
        modelKey: f.modelKey,
        label: f.label,
        hint: f.hint,
        visible: nextVisible,
        visibleExpr: f.visibleExpr,
        text: f.text,
        multiple: f.multiple,
        items: f.items
      });
    }
    return updated;
  }

  private setDraftValue(key: string | undefined, value: Object): void {
    if (!key) { return; }
    const nextModel = copyRecord(this.draftModel);
    nextModel[key] = value;
    this.draftModel = nextModel;
    this.fields = this.recomputeFieldVisibility(this.fields, nextModel);
    this.draftVersion += 1;
  }

  private isOptionSelected(key: string | undefined, value: string, multiple: boolean): boolean {
    if (!key) { return false; }
    const cur = this.draftModel[key];
    if (multiple && Array.isArray(cur)) {
      const arr = cur as Object[];
      for (let i = 0; i < arr.length; i++) {
        if (String(arr[i]) === value) { return true; }
      }
      return false;
    }
    return String(cur ?? '') === value;
  }

  private toggleOption(key: string | undefined, value: string, multiple: boolean): void {
    if (!key) { return; }
    if (!multiple) {
      this.setDraftValue(key, value);
      return;
    }
    const cur = this.draftModel[key];
    const next: string[] = [];
    let removed = false;
    if (Array.isArray(cur)) {
      const arr = cur as Object[];
      for (let i = 0; i < arr.length; i++) {
        const s = String(arr[i]);
        if (s === value) {
          removed = true;
        } else {
          next.push(s);
        }
      }
    }
    if (!removed) {
      next.push(value);
    }
    this.setDraftValue(key, next);
  }

  build() {
    if (this.renderMode === 'vue' || this.fields.length === 0) {
      IsolatedVuePluginWebView({
        pluginId: this.pluginName,
        serverUrl: this.serverUrl,
        authToken: this.authToken,
        userName: this.userName,
        userAvatar: this.userAvatar,
        isSuperuser: this.isSuperuser,
        switchesToConfig: this.pluginHasPage,
        chromeController: this.chromeController,
        onChromeTitleChange: this.onChromeTitleChange,
        onChromeActionsChange: this.onChromeActionsChange,
        onRequestDismiss: this.onRequestDismiss
      })
    } else {
      Scroll() {
        Column() {
          Column({ space: 12 }) {
            ForEach(this.fields.filter((f: PluginFieldPlan) => f.visible), (field: PluginFieldPlan, idx: number) => {
            if (field.component === 'VSwitch' || field.component === 'VCheckbox') {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(field.label || field.modelKey || '开关')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                    if (field.hint.length > 0) {
                      Text(field.hint).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                    }
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: Boolean(this.draftModel[field.modelKey ?? '']) })
                    .selectedColor(this.accentHex)
                    .onChange((v: boolean) => {
                      const cur = Boolean(this.draftModel[field.modelKey ?? '']);
                      if (cur !== v) {
                        this.setDraftValue(field.modelKey, v);
                      }
                    })
                }.width('100%')
              }
            } else if (field.component === 'VCronField') {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Column({ space: 8 }) {
                  Row() {
                    Text(field.label || '定时周期 (Cron)')
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                      .layoutWeight(1)
                    NativeAdaptiveBadge({
                      text: RustCoreBridge.analyzeCron(String(this.draftModel[field.modelKey ?? ''] ?? '')).descriptionZh,
                      tintHex: this.accentHex
                    })
                  }.width('100%')
                  TextInput({ text: String(this.draftModel[field.modelKey ?? ''] ?? '*/15 * * * *') })
                    .fontColor(mpPrimaryText(this.isDark))
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    .borderRadius(12)
                    .onChange((val: string) => {
                      if (String(this.draftModel[field.modelKey ?? ''] ?? '') !== val) {
                        this.setDraftValue(field.modelKey, val);
                      }
                    })
                  Row({ space: 8 }) {
                    NativeAdaptivePill({
                      title: '每15分',
                      selected: String(this.draftModel[field.modelKey ?? ''] ?? '') === '*/15 * * * *',
                      onTap: () => this.setDraftValue(field.modelKey, '*/15 * * * *')
                    })
                    NativeAdaptivePill({
                      title: '每小时',
                      selected: String(this.draftModel[field.modelKey ?? ''] ?? '') === '0 * * * *',
                      onTap: () => this.setDraftValue(field.modelKey, '0 * * * *')
                    })
                    NativeAdaptivePill({
                      title: '每天9点',
                      selected: String(this.draftModel[field.modelKey ?? ''] ?? '') === '0 9 * * *',
                      onTap: () => this.setDraftValue(field.modelKey, '0 9 * * *')
                    })
                  }
                }.width('100%')
              }
            } else if ((field.component === 'VSelect' || field.component === 'VAutocomplete' || field.component === 'VCombobox')
              && field.items && field.items.length > 0) {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Column({ space: 8 }) {
                  Text(field.label || field.modelKey || '选项')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(mpPrimaryText(this.isDark))
                    .width('100%')
                  if (field.hint.length > 0) {
                    Text(field.hint).fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
                  }
                  Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
                    ForEach(field.items, (opt: PluginSelectOption) => {
                      NativeAdaptivePill({
                        title: opt.title,
                        selected: this.draftVersion >= 0 && this.isOptionSelected(field.modelKey, opt.value, Boolean(field.multiple)),
                        onTap: () => this.toggleOption(field.modelKey, opt.value, Boolean(field.multiple))
                      })
                    }, (opt: PluginSelectOption) => `${field.modelKey ?? idx}_opt_${opt.value}_${this.draftVersion}`)
                  }
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            } else if (field.component === 'VAlert') {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Text(field.text || field.label)
                  .fontSize(13)
                  .fontColor('#6EA8FE')
                  .lineHeight(20)
                  .width('100%')
              }
            } else if (field.component === 'VTextarea' || field.component === 'VAceEditor') {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Column({ space: 6 }) {
                  Text(field.label || field.modelKey || field.component)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(mpPrimaryText(this.isDark))
                  if (field.hint.length > 0) {
                    Text(field.hint).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }
                  TextArea({ text: String(this.draftModel[field.modelKey ?? ''] ?? '') })
                    .height(96)
                    .fontColor(mpPrimaryText(this.isDark))
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    .borderRadius(12)
                    .onChange((val: string) => {
                      if (String(this.draftModel[field.modelKey ?? ''] ?? '') !== val) {
                        this.setDraftValue(field.modelKey, val);
                      }
                    })
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            } else {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Column({ space: 6 }) {
                  Text(field.label || field.modelKey || field.component)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(mpPrimaryText(this.isDark))
                  if (field.hint.length > 0) {
                    Text(field.hint).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }
                  TextInput({ text: String(this.draftModel[field.modelKey ?? ''] ?? '') })
                    .fontColor(mpPrimaryText(this.isDark))
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    .borderRadius(12)
                    .onChange((val: string) => {
                      if (String(this.draftModel[field.modelKey ?? ''] ?? '') !== val) {
                        this.setDraftValue(field.modelKey, val);
                      }
                    })
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
            }
          }, (field: PluginFieldPlan, idx: number) => `${field.component}_${field.modelKey ?? idx}`)

          Button(this.saving ? '正在保存…' : '保存插件配置')
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor(this.accentHex)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.saving = true;
              const merged = RustCoreBridge.applyPluginFormPatch(this.originalModelJson, JSON.stringify(this.draftModel));
              this.onSaveFullModel(merged);
              this.saving = false;
            })
          }
          .width('100%')
          .constraintSize({ maxWidth: 760 })
          .padding({ left: 16, right: 16, top: 10, bottom: 28 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')
    }
  }
}
