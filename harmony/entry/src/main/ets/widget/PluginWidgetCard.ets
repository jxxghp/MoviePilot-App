const pluginWidgetStorage = new LocalStorage();

/** 插件预设指标项。 */
interface PluginCardMetric {
  id: string;
  label: string;
  value: string;
  subValue: string;
  tone: string;
}

/** 插件预设列表项。 */
interface PluginCardListItem {
  id: string;
  title: string;
  subtitle: string;
  trailing: string;
  progress: number;
  hasProgress: boolean;
}

/** 声明式自定义布局节点模型（有界无递归解析）。 */
interface PluginCardCustomNode {
  id: string;
  type: string;
  text: string;
  label: string;
  valueText: string;
  subValue: string;
  size: string;
  weight: string;
  align: string;
  tone: string;
  gap: number;
  padding: number;
  progressPercent: number;
  filled: boolean;
  actionType: string;
  actionId: string;
  actionSurface: string;
  actionRoute: string;
  children: PluginCardCustomNode[];
}

function asPluginRec(val: Object | null | undefined): Record<string, Object> | null {
  if (val !== null && val !== undefined && typeof val === 'object' && !Array.isArray(val)) {
    return val as Record<string, Object>;
  }
  return null;
}

function parsePluginMetrics(rawJson: string): PluginCardMetric[] {
  const out: PluginCardMetric[] = [];
  try {
    if (rawJson.length > 2) {
      const parsed = JSON.parse(rawJson) as Object;
      if (Array.isArray(parsed)) {
        const arr = parsed as Object[];
        for (let i = 0; i < Math.min(6, arr.length); i++) {
          const r = asPluginRec(arr[i]);
          if (!r) { continue; }
          out.push({
            id: r['id'] !== undefined ? String(r['id']) : `pm-${i}`,
            label: r['label'] !== undefined ? String(r['label']) : (r['title'] !== undefined ? String(r['title']) : '指标'),
            value: r['value'] !== undefined ? String(r['value']) : '—',
            subValue: r['subValue'] !== undefined ? String(r['subValue']) : '',
            tone: r['tone'] !== undefined ? String(r['tone']) : 'default'
          });
        }
      }
    }
  } catch {
    // ignore
  }
  return out;
}

function parsePluginItems(rawJson: string): PluginCardListItem[] {
  const out: PluginCardListItem[] = [];
  try {
    if (rawJson.length > 2) {
      const parsed = JSON.parse(rawJson) as Object;
      if (Array.isArray(parsed)) {
        const arr = parsed as Object[];
        for (let i = 0; i < Math.min(5, arr.length); i++) {
          const r = asPluginRec(arr[i]);
          if (!r) { continue; }
          const hasProg = r['progress'] !== undefined && r['progress'] !== null && Number.isFinite(Number(r['progress']));
          const pct = hasProg ? Math.max(0, Math.min(100, Math.round(Number(r['progress']) * 100))) : 0;
          out.push({
            id: r['id'] !== undefined ? String(r['id']) : `pi-${i}`,
            title: r['title'] !== undefined ? String(r['title']) : '条目',
            subtitle: r['subtitle'] !== undefined ? String(r['subtitle']) : '',
            trailing: r['trailing'] !== undefined ? String(r['trailing']) : '',
            progress: pct,
            hasProgress: hasProg
          });
        }
      }
    }
  } catch {
    // ignore
  }
  return out;
}

function parseCustomNodeBounded(
  rawObj: Record<string, Object> | null,
  depth: number,
  prefix: string,
  budget: number[]
): PluginCardCustomNode | null {
  if (!rawObj || depth > 5 || budget[0] <= 0) {
    return null;
  }
  const type = rawObj['type'] !== undefined ? String(rawObj['type']) : '';
  if (type.length === 0) { return null; }
  budget[0] = budget[0] - 1;

  const rawVal = rawObj['value'];
  let progressPct = 0;
  let valStr = rawObj['valueText'] !== undefined ? String(rawObj['valueText']) : '';
  if (typeof rawVal === 'number' && Number.isFinite(rawVal)) {
    progressPct = Math.max(0, Math.min(100, Math.round(rawVal * 100)));
    if (valStr.length === 0 && type !== 'progress') {
      valStr = `${rawVal}`;
    }
  } else if (rawVal !== undefined && rawVal !== null && valStr.length === 0) {
    valStr = String(rawVal);
  }

  const actRec = asPluginRec(rawObj['action']);
  const children: PluginCardCustomNode[] = [];
  if ((type === 'column' || type === 'row' || type === 'stack' || type === 'box') && depth < 5) {
    const rawChildren = Array.isArray(rawObj['children']) ? (rawObj['children'] as Object[]) : [];
    for (let i = 0; i < Math.min(8, rawChildren.length); i++) {
      if (budget[0] <= 0) { break; }
      const childNode = parseCustomNodeBounded(asPluginRec(rawChildren[i]), depth + 1, `${prefix}-${i}`, budget);
      if (childNode) {
        children.push(childNode);
      }
    }
  }

  return {
    id: prefix,
    type: type,
    text: rawObj['text'] !== undefined ? String(rawObj['text']) : '',
    label: rawObj['label'] !== undefined ? String(rawObj['label']) : '',
    valueText: valStr,
    subValue: rawObj['subValue'] !== undefined ? String(rawObj['subValue']) : '',
    size: rawObj['size'] !== undefined ? String(rawObj['size']) : 'md',
    weight: rawObj['weight'] !== undefined ? String(rawObj['weight']) : 'regular',
    align: rawObj['align'] !== undefined ? String(rawObj['align']) : 'start',
    tone: rawObj['tone'] !== undefined ? String(rawObj['tone']) : 'default',
    gap: rawObj['gap'] !== undefined && Number.isFinite(Number(rawObj['gap'])) ? Math.max(0, Math.min(20, Number(rawObj['gap']))) : 6,
    padding: rawObj['padding'] !== undefined && Number.isFinite(Number(rawObj['padding'])) ? Math.max(0, Math.min(16, Number(rawObj['padding']))) : 0,
    progressPercent: progressPct,
    filled: rawObj['filled'] !== undefined ? Boolean(rawObj['filled']) : true,
    actionType: actRec && actRec['type'] !== undefined ? String(actRec['type']) : 'openPlugin',
    actionId: actRec && actRec['actionId'] !== undefined ? String(actRec['actionId']) : '',
    actionSurface: actRec && actRec['surface'] !== undefined ? String(actRec['surface']) : 'data',
    actionRoute: actRec && actRec['route'] !== undefined ? String(actRec['route']) : '',
    children: children
  };
}

function parseRootCustomNode(layoutJson: string): PluginCardCustomNode | null {
  try {
    if (layoutJson.length > 2) {
      const parsed = asPluginRec(JSON.parse(layoutJson) as Object);
      return parseCustomNodeBounded(parsed, 0, 'root', [40]);
    }
  } catch {
    // ignore malformed custom layout
  }
  return null;
}

/**
 * 鸿蒙原生「MoviePilot 插件」桌面服务卡片：
 * - 完全运行于独立卡片沙箱，不依赖任何宿主共享包；
 * - 同时支持 `metrics`、`list`、`poster` 预设模板与三层有界展开的声明式 `PluginWidgetNode` 自定义布局树。
 */
@Entry(pluginWidgetStorage)
@Component
struct PluginWidgetCard {
  @LocalStorageProp('dimension') dimension: string = '2*4';
  @LocalStorageProp('hasWidget') hasWidget: boolean = false;
  @LocalStorageProp('totalWidgets') totalWidgets: number = 0;
  @LocalStorageProp('pluginId') pluginId: string = '';
  @LocalStorageProp('pluginName') pluginName: string = 'MoviePilot 插件';
  @LocalStorageProp('widgetKey') widgetKey: string = '';
  @LocalStorageProp('title') title: string = 'MoviePilot 插件';
  @LocalStorageProp('subtitle') subtitle: string = '';
  @LocalStorageProp('kind') kind: string = 'metrics';
  @LocalStorageProp('accentHex') accentHex: string = '#317AF7';
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('metricsJson') metricsJson: string = '[]';
  @LocalStorageProp('itemsJson') itemsJson: string = '[]';
  @LocalStorageProp('layoutJson') layoutJson: string = '';

  private resolveAccent(): string {
    if (this.accentHex.startsWith('#') && this.accentHex.length === 7) {
      return this.accentHex;
    }
    return '#3B82F6';
  }

  private resolveTone(tone: string): ResourceColor {
    if (tone.startsWith('#') && tone.length === 7) { return tone; }
    if (tone === 'accent' || tone === 'primary') { return this.resolveAccent(); }
    if (tone === 'success') { return '#22C55E'; }
    if (tone === 'warning') { return '#F59E0B'; }
    if (tone === 'danger') { return '#EF4444'; }
    if (tone === 'muted' || tone === 'secondary') { return $r('sys.color.font_secondary'); }
    return $r('sys.color.font_primary');
  }

  private openPluginPage(surface: string = 'data', extraActionId: string = '', customRoute: string = ''): void {
    if (customRoute.length > 0) {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          uri: `moviepilot://open?path=${encodeURIComponent(customRoute)}`
        }
      });
      return;
    }
    if (this.pluginId.trim().length === 0) {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { uri: 'moviepilot://plugins?tab=installed' }
      });
      return;
    }
    if (extraActionId.length > 0) {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          pluginId: this.pluginId,
          widgetKey: this.widgetKey,
          widgetAction: extraActionId,
          surface: surface
        }
      });
      return;
    }
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        uri: `moviepilot://plugin/${encodeURIComponent(this.pluginId)}?surface=${encodeURIComponent(surface)}`
      }
    });
  }

  @Builder
  private renderLeafNode(node: PluginCardCustomNode) {
    if (node.type === 'text') {
      Text(node.text.length > 0 ? node.text : (node.label.length > 0 ? node.label : node.valueText))
        .fontSize(node.size === 'xs' ? 10 : (node.size === 'sm' ? 11 : (node.size === 'lg' ? 15 : (node.size === 'xl' ? 17 : 12.5))))
        .fontWeight(node.weight === 'bold' || node.weight === 'semibold' ? FontWeight.Bold : (node.weight === 'medium' ? FontWeight.Medium : FontWeight.Normal))
        .fontColor(this.resolveTone(node.tone))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    } else if (node.type === 'metric') {
      Column({ space: 2 }) {
        if (node.label.length > 0) {
          Text(node.label)
            .fontSize(10)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
        }
        Text(node.valueText.length > 0 ? node.valueText : '—')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolveTone(node.tone))
          .fontFeature('"tnum" 1')
          .maxLines(1)
        if (node.subValue.length > 0) {
          Text(node.subValue)
            .fontSize(9.5)
            .fontColor($r('sys.color.font_tertiary'))
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
    } else if (node.type === 'progress') {
      Column({ space: 2 }) {
        if (node.label.length > 0 || node.valueText.length > 0) {
          Row() {
            Text(node.label)
              .fontSize(10)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .layoutWeight(1)
            if (node.valueText.length > 0) {
              Text(node.valueText)
                .fontSize(10)
                .fontColor($r('sys.color.font_secondary'))
                .fontFeature('"tnum" 1')
            }
          }
          .width('100%')
        }
        Progress({ value: node.progressPercent, total: 100, type: ProgressType.Linear })
          .color(this.resolveAccent())
          .width('100%')
          .height(4)
      }
      .width('100%')
    } else if (node.type === 'badge') {
      Text(node.text.length > 0 ? node.text : node.label)
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveTone(node.tone === 'default' ? 'accent' : node.tone))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(8)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .maxLines(1)
    } else if (node.type === 'button') {
      Text(node.label.length > 0 ? node.label : (node.text.length > 0 ? node.text : '执行'))
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(node.filled ? Color.White : this.resolveAccent())
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(8)
        .backgroundColor(node.filled ? this.resolveAccent() : $r('sys.color.comp_background_tertiary'))
        .onClick(() => {
          if (node.actionType === 'pluginAction' && node.actionId.length > 0) {
            this.openPluginPage(node.actionSurface, node.actionId, '');
          } else if (node.actionType === 'openRoute' && node.actionRoute.length > 0) {
            this.openPluginPage('data', '', node.actionRoute);
          } else {
            this.openPluginPage(node.actionSurface, '', '');
          }
        })
    } else if (node.type === 'divider') {
      Divider()
        .color($r('sys.color.comp_divider'))
        .strokeWidth(0.5)
    } else if (node.type === 'spacer') {
      Blank()
    }
  }

  @Builder
  private renderLevel2Node(node: PluginCardCustomNode) {
    if (node.type === 'row') {
      Row({ space: node.gap }) {
        ForEach(
          node.children,
          (c: PluginCardCustomNode) => {
            this.renderLeafNode(c);
          },
          (c: PluginCardCustomNode) => c.id
        )
      }
      .justifyContent(node.align === 'spaceBetween' ? FlexAlign.SpaceBetween : FlexAlign.Start)
      .padding(node.padding)
      .width(node.align === 'spaceBetween' ? '100%' : undefined)
    } else if (node.type === 'column' || node.type === 'box' || node.type === 'stack') {
      Column({ space: node.gap }) {
        ForEach(
          node.children,
          (c: PluginCardCustomNode) => {
            this.renderLeafNode(c);
          },
          (c: PluginCardCustomNode) => c.id
        )
      }
      .alignItems(HorizontalAlign.Start)
      .padding(node.padding)
    } else {
      this.renderLeafNode(node);
    }
  }

  @Builder
  private renderLevel1Node(node: PluginCardCustomNode) {
    if (node.type === 'row') {
      Row({ space: node.gap }) {
        ForEach(
          node.children,
          (c: PluginCardCustomNode) => {
            this.renderLevel2Node(c);
          },
          (c: PluginCardCustomNode) => c.id
        )
      }
      .justifyContent(node.align === 'spaceBetween' ? FlexAlign.SpaceBetween : FlexAlign.Start)
      .padding(node.padding)
      .width('100%')
    } else if (node.type === 'column' || node.type === 'box' || node.type === 'stack') {
      Column({ space: node.gap }) {
        ForEach(
          node.children,
          (c: PluginCardCustomNode) => {
            this.renderLevel2Node(c);
          },
          (c: PluginCardCustomNode) => c.id
        )
      }
      .alignItems(HorizontalAlign.Start)
      .padding(node.padding)
      .width('100%')
    } else {
      this.renderLeafNode(node);
    }
  }

  @Builder
  private renderCustomTree(root: PluginCardCustomNode) {
    if (root.type === 'row') {
      Row({ space: root.gap }) {
        ForEach(
          root.children,
          (c: PluginCardCustomNode) => {
            this.renderLevel1Node(c);
          },
          (c: PluginCardCustomNode) => c.id
        )
      }
      .justifyContent(root.align === 'spaceBetween' ? FlexAlign.SpaceBetween : FlexAlign.Start)
      .padding(root.padding)
      .width('100%')
    } else if (root.type === 'column' || root.type === 'box' || root.type === 'stack') {
      Column({ space: root.gap }) {
        ForEach(
          root.children,
          (c: PluginCardCustomNode) => {
            this.renderLevel1Node(c);
          },
          (c: PluginCardCustomNode) => c.id
        )
      }
      .alignItems(HorizontalAlign.Start)
      .padding(root.padding)
      .width('100%')
    } else {
      this.renderLeafNode(root);
    }
  }

  build() {
    Column({ space: 8 }) {
      // 顶栏：插件卡片标题 + 多插件轮换按钮
      Row({ space: 6 }) {
        Column({ space: 1 }) {
          Text(this.title)
            .fontSize(this.dimension === '2*2' ? 12.5 : 13.5)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.dimension !== '2*2') {
            Text(this.updatedAt.length > 0 ? `${this.pluginName} · ${this.updatedAt}` : this.pluginName)
              .fontSize(10)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.totalWidgets > 1) {
          Text('切换 ⇄')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.resolveAccent())
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(9)
            .backgroundColor($r('sys.color.comp_background_tertiary'))
            .onClick(() => {
              postCardAction(this, {
                action: 'message',
                params: { action: 'cyclePlugin' }
              });
            })
        }
      }
      .width('100%')

      if (!this.hasWidget) {
        Blank()
        Text('当前暂无已同步的插件卡片')
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .width('100%')
        Text(this.subtitle)
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(2)
          .width('100%')
        Blank()
      } else if (this.kind === 'custom' && parseRootCustomNode(this.layoutJson) !== null) {
        this.renderCustomTree(parseRootCustomNode(this.layoutJson)!);
        Blank()
      } else if (this.kind === 'list' && parsePluginItems(this.itemsJson).length > 0) {
        Column({ space: 5 }) {
          ForEach(
            parsePluginItems(this.itemsJson).slice(0, this.dimension === '2*2' ? 2 : (this.dimension === '4*4' ? 4 : 2)),
            (item: PluginCardListItem) => {
              Column({ space: 2 }) {
                Row() {
                  Text(item.title)
                    .fontSize(11.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (item.trailing.length > 0) {
                    Text(item.trailing)
                      .fontSize(10)
                      .fontColor($r('sys.color.font_secondary'))
                      .fontFeature('"tnum" 1')
                  }
                }
                .width('100%')

                if (item.hasProgress) {
                  Progress({ value: item.progress, total: 100, type: ProgressType.Linear })
                    .color(this.resolveAccent())
                    .width('100%')
                    .height(4)
                }
              }
              .width('100%')
            },
            (item: PluginCardListItem) => item.id
          )
        }
        .width('100%')
        Blank()
      } else {
        // 默认 metrics / poster 指标布局
        if (parsePluginMetrics(this.metricsJson).length === 0) {
          Text(this.subtitle.length > 0 ? this.subtitle : '点击打开插件查看完整实时面板')
            .fontSize(11.5)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(3)
            .width('100%')
        } else if (this.dimension === '2*2') {
          Column({ space: 4 }) {
            ForEach(
              parsePluginMetrics(this.metricsJson).slice(0, 2),
              (m: PluginCardMetric) => {
                Column({ space: 1 }) {
                  Text(m.value)
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.resolveTone(m.tone))
                    .fontFeature('"tnum" 1')
                    .maxLines(1)
                  Text(m.label)
                    .fontSize(10)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
              },
              (m: PluginCardMetric) => m.id
            )
          }
          .width('100%')
        } else {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              ForEach(
                parsePluginMetrics(this.metricsJson).slice(0, 2),
                (m: PluginCardMetric) => {
                  Column({ space: 2 }) {
                    Text(m.label)
                      .fontSize(10)
                      .fontColor($r('sys.color.font_secondary'))
                      .maxLines(1)
                    Text(m.value)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.resolveTone(m.tone))
                      .fontFeature('"tnum" 1')
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                  .borderRadius(12)
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .layoutWeight(1)
                },
                (m: PluginCardMetric) => m.id
              )
            }
            .width('100%')

            if (parsePluginMetrics(this.metricsJson).length > 2) {
              Row({ space: 6 }) {
                ForEach(
                  parsePluginMetrics(this.metricsJson).slice(2, 4),
                  (m: PluginCardMetric) => {
                    Column({ space: 2 }) {
                      Text(m.label)
                        .fontSize(10)
                        .fontColor($r('sys.color.font_secondary'))
                        .maxLines(1)
                      Text(m.value)
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.resolveTone(m.tone))
                        .fontFeature('"tnum" 1')
                        .maxLines(1)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                    .borderRadius(12)
                    .backgroundColor($r('sys.color.comp_background_tertiary'))
                    .layoutWeight(1)
                  },
                  (m: PluginCardMetric) => m.id
                )
              }
              .width('100%')
            }
          }
          .width('100%')
        }
        Blank()
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.dimension === '2*2' ? 12 : 14)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(() => {
      this.openPluginPage('data', '', '');
    })
  }
}
