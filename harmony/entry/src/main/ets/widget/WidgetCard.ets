const mainWidgetStorage = new LocalStorage();

/** 主体桌面卡片单项统计指标。 */
interface MainCardMetric {
  id: string;
  title: string;
  value: string;
  tone: string;
}

/** 主体桌面卡片近期明细条目。 */
interface MainCardItem {
  id: string;
  title: string;
  subtitle: string;
  progress: number;
  hasProgress: boolean;
}

function asMainRec(val: Object | null | undefined): Record<string, Object> | null {
  if (val !== null && val !== undefined && typeof val === 'object' && !Array.isArray(val)) {
    return val as Record<string, Object>;
  }
  return null;
}

function parseMainMetrics(rawJson: string, movies: number, tvs: number, speed: string): MainCardMetric[] {
  const out: MainCardMetric[] = [];
  try {
    if (rawJson.length > 2) {
      const parsed = JSON.parse(rawJson) as Object;
      if (Array.isArray(parsed)) {
        const arr = parsed as Object[];
        for (let i = 0; i < Math.min(6, arr.length); i++) {
          const r = asMainRec(arr[i]);
          if (!r) { continue; }
          out.push({
            id: r['id'] !== undefined ? String(r['id']) : `m-${i}`,
            title: r['title'] !== undefined ? String(r['title']) : '指标',
            value: r['value'] !== undefined ? String(r['value']) : '—',
            tone: r['tone'] !== undefined ? String(r['tone']) : 'default'
          });
        }
      }
    }
  } catch {
    // fallback below
  }
  if (out.length === 0) {
    out.push({ id: 'movies', title: '电影', value: `${movies}`, tone: 'default' });
    out.push({ id: 'tvs', title: '剧集', value: `${tvs}`, tone: 'default' });
    out.push({ id: 'speed', title: '实时下载', value: speed, tone: 'success' });
  }
  return out;
}

function parseMainItems(rawJson: string): MainCardItem[] {
  const out: MainCardItem[] = [];
  try {
    if (rawJson.length > 2) {
      const parsed = JSON.parse(rawJson) as Object;
      if (Array.isArray(parsed)) {
        const arr = parsed as Object[];
        for (let i = 0; i < Math.min(4, arr.length); i++) {
          const r = asMainRec(arr[i]);
          if (!r) { continue; }
          const hasProg = r['progress'] !== undefined && r['progress'] !== null && Number.isFinite(Number(r['progress']));
          const prog = hasProg ? Math.max(0, Math.min(100, Math.round(Number(r['progress']) * 100))) : 0;
          out.push({
            id: r['id'] !== undefined ? String(r['id']) : `i-${i}`,
            title: r['title'] !== undefined ? String(r['title']) : `项目 ${i + 1}`,
            subtitle: r['subtitle'] !== undefined ? String(r['subtitle']) : '',
            progress: prog,
            hasProgress: hasProg
          });
        }
      }
    }
  } catch {
    // ignore malformed items json
  }
  return out;
}

/**
 * 鸿蒙原生 APP 主体桌面服务卡片 UI：
 * - 自适应系统深浅色语义材质、`20vp` 圆角与等宽数字；
 * - 支持 `2*2`（小）、`2*4`（中）、`4*4`（大，含顶部统计网格 + 分割线 + 近期明细与进度条）；
 * - 顶栏徽标点击直接在卡片内循环切换 `系统概览 -> 下载状态 -> 近期入库 -> 订阅`，点击主体精确深链跳转。
 */
@Entry(mainWidgetStorage)
@Component
struct WidgetCard {
  @LocalStorageProp('dimension') dimension: string = '2*4';
  @LocalStorageProp('content') content: string = 'overview';
  @LocalStorageProp('title') title: string = '系统概览';
  @LocalStorageProp('deepLink') deepLink: string = 'moviepilot://dashboard';
  @LocalStorageProp('showMediaNames') showMediaNames: boolean = true;
  @LocalStorageProp('server') server: string = 'MoviePilot';
  @LocalStorageProp('movies') movies: number = 0;
  @LocalStorageProp('tvs') tvs: number = 0;
  @LocalStorageProp('speed') speed: string = '0 B/s';
  @LocalStorageProp('updatedAt') updatedAt: string = '';
  @LocalStorageProp('metricsJson') metricsJson: string = '[]';
  @LocalStorageProp('itemsJson') itemsJson: string = '[]';

  private resolveToneColor(tone: string): ResourceColor {
    if (tone === 'accent' || tone === 'primary') { return '#3B82F6'; }
    if (tone === 'success') { return '#22C55E'; }
    if (tone === 'warning') { return '#F59E0B'; }
    if (tone === 'danger') { return '#EF4444'; }
    if (tone === 'muted') { return $r('sys.color.font_secondary'); }
    return $r('sys.color.font_primary');
  }

  @Builder
  private metricCell(metric: MainCardMetric) {
    Column({ space: 2 }) {
      Text(metric.title)
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(metric.value)
        .fontSize(this.dimension === '2*2' ? 15 : 14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolveToneColor(metric.tone))
        .fontFeature('"tnum" 1')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .layoutWeight(1)
  }

  build() {
    Column({ space: 8 }) {
      // 顶栏：品牌名称 + 可点击切换的模块胶囊
      Row({ space: 6 }) {
        Column({ space: 1 }) {
          Text(this.server)
            .fontSize(this.dimension === '2*2' ? 12 : 13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.dimension === '2*2') {
            Text(this.title)
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#3B82F6')
              .maxLines(1)
              .onClick(() => {
                postCardAction(this, {
                  action: 'message',
                  params: { action: 'cycleContent' }
                });
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.dimension !== '2*2') {
          if (this.dimension === '4*4' && this.content !== 'overview') {
            Text(this.showMediaNames ? '显名' : '脱敏')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .borderRadius(10)
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .onClick(() => {
                postCardAction(this, {
                  action: 'message',
                  params: { action: 'togglePrivacy' }
                });
              })
          }

          Text(`${this.title} ⇄`)
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor('#3B82F6')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor('#243B82F6')
            .onClick(() => {
              postCardAction(this, {
                action: 'message',
                params: { action: 'cycleContent' }
              });
            })
        }
      }
      .width('100%')

      // 主体指标与明细
      if (this.dimension === '2*2') {
        Column({ space: 5 }) {
          ForEach(
            parseMainMetrics(this.metricsJson, this.movies, this.tvs, this.speed).slice(0, 2),
            (m: MainCardMetric) => {
              Column({ space: 1 }) {
                Text(m.value)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.resolveToneColor(m.tone))
                  .fontFeature('"tnum" 1')
                  .maxLines(1)
                Text(m.title)
                  .fontSize(10)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            },
            (m: MainCardMetric) => m.id
          )
        }
        .width('100%')
      } else {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            ForEach(
              parseMainMetrics(this.metricsJson, this.movies, this.tvs, this.speed).slice(0, 2),
              (m: MainCardMetric) => {
                this.metricCell(m);
              },
              (m: MainCardMetric) => m.id
            )
          }
          .width('100%')

          if (parseMainMetrics(this.metricsJson, this.movies, this.tvs, this.speed).length > 2) {
            Row({ space: 6 }) {
              ForEach(
                parseMainMetrics(this.metricsJson, this.movies, this.tvs, this.speed).slice(2, 4),
                (m: MainCardMetric) => {
                  this.metricCell(m);
                },
                (m: MainCardMetric) => m.id
              )
            }
            .width('100%')
          }
        }
        .width('100%')

        // 4*4 大卡片追加分割线与近期明细进度列表
        if (this.dimension === '4*4' && this.content !== 'overview') {
          Divider()
            .color($r('sys.color.comp_divider'))
            .strokeWidth(0.5)

          if (parseMainItems(this.itemsJson).length === 0) {
            Text('当前暂无近期记录')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
              .width('100%')
          } else {
            Column({ space: 6 }) {
              ForEach(
                parseMainItems(this.itemsJson).slice(0, 3),
                (item: MainCardItem) => {
                  Column({ space: 2 }) {
                    Row() {
                      Text(item.title)
                        .fontSize(11.5)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('sys.color.font_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      if (item.hasProgress) {
                        Text(`${item.progress}%`)
                          .fontSize(10)
                          .fontColor($r('sys.color.font_secondary'))
                          .fontFeature('"tnum" 1')
                      }
                    }
                    .width('100%')

                    if (item.subtitle.length > 0) {
                      Text(item.subtitle)
                        .fontSize(10)
                        .fontColor($r('sys.color.font_secondary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }

                    if (item.hasProgress) {
                      Progress({ value: item.progress, total: 100, type: ProgressType.Linear })
                        .color('#3B82F6')
                        .width('100%')
                        .height(4)
                    }
                  }
                  .width('100%')
                },
                (item: MainCardItem) => item.id
              )
            }
            .width('100%')
          }
        }
      }

      Blank()

      if (this.updatedAt.length > 0) {
        Text(`更新于 ${this.updatedAt}`)
          .fontSize(9.5)
          .fontColor($r('sys.color.font_tertiary'))
          .fontFeature('"tnum" 1')
          .maxLines(1)
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.dimension === '2*2' ? 12 : 14)
    .borderRadius(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          uri: this.deepLink
        }
      });
    })
  }
}
