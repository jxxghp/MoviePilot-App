const nowPlayingStorage = new LocalStorage();

function extractCleanLyrics(raw: string): string[] {
  const lines = raw.split('\n');
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i].trim();
    if (line.startsWith('[')) {
      const closeIdx = line.indexOf(']');
      if (closeIdx > 0) {
        line = line.substring(closeIdx + 1).trim();
      }
    }
    if (line.length > 0) {
      out.push(line);
    }
  }
  return out;
}

function formatMs(ms: number): string {
  const totalSec = Math.max(0, Math.floor(ms / 1000));
  const m = `${Math.floor(totalSec / 60)}`.padStart(2, '0');
  const s = `${totalSec % 60}`.padStart(2, '0');
  return `${m}:${s}`;
}

/**
 * 鸿蒙原生「MoviePilot 正在播放」桌面音频播控卡片：
 * - 支持 `2*2`（封面 + 歌名/歌手 + 播放暂停）、`2*4`（左封面 + 右歌名/歌词 + 底部播控栏）
 *   与 `4*4`（顶部大图信息 + 进度条 + 多行歌词预览 + 底部完整播控栏）；
 * - 空闲未播放时展示优雅引导态。
 */
@Entry(nowPlayingStorage)
@Component
struct NowPlayingWidgetCard {
  @LocalStorageProp('dimension') dimension: string = '2*4';
  @LocalStorageProp('active') active: boolean = false;
  @LocalStorageProp('pluginId') pluginId: string = '';
  @LocalStorageProp('pluginName') pluginName: string = '';
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('artist') artist: string = '';
  @LocalStorageProp('album') album: string = '';
  @LocalStorageProp('lyrics') lyrics: string = '';
  @LocalStorageProp('artworkUrl') artworkUrl: string = '';
  @LocalStorageProp('isPlaying') isPlaying: boolean = false;
  @LocalStorageProp('liked') liked: boolean = false;
  @LocalStorageProp('hasLike') hasLike: boolean = false;
  @LocalStorageProp('canNext') canNext: boolean = true;
  @LocalStorageProp('canPrevious') canPrevious: boolean = true;
  @LocalStorageProp('durationMs') durationMs: number = 0;
  @LocalStorageProp('positionMs') positionMs: number = 0;

  private triggerAudioCmd(cmd: string): void {
    postCardAction(this, {
      action: 'message',
      params: { action: cmd }
    });
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {
        audioCmd: cmd,
        pluginId: this.pluginId
      }
    });
  }

  private openTargetUri(): string {
    if (this.pluginId.trim().length > 0) {
      return `moviepilot://plugin/${encodeURIComponent(this.pluginId.trim())}?surface=data`;
    }
    return 'moviepilot://music';
  }

  private subtitleLine(): string {
    if (this.artist.length > 0 && this.album.length > 0) {
      return `${this.artist} · ${this.album}`;
    }
    if (this.artist.length > 0) { return this.artist; }
    if (this.album.length > 0) { return this.album; }
    return this.pluginName.length > 0 ? this.pluginName : 'MoviePilot';
  }

  @Builder
  private albumCoverBox(sizeVp: number, radiusVp: number) {
    if (this.artworkUrl.length > 0) {
      Image(this.artworkUrl)
        .width(sizeVp)
        .height(sizeVp)
        .objectFit(ImageFit.Cover)
        .borderRadius(radiusVp)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Text('♪')
          .fontSize(Math.round(sizeVp * 0.42))
          .fontWeight(FontWeight.Bold)
          .fontColor('#3B82F6')
      }
      .width(sizeVp)
      .height(sizeVp)
      .borderRadius(radiusVp)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
    }
  }

  @Builder
  private controlBar(compact: boolean) {
    Row({ space: compact ? 8 : 14 }) {
      if (this.hasLike) {
        Text(this.liked ? '♥' : '♡')
          .fontSize(compact ? 13 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.liked ? '#EF4444' : $r('sys.color.font_secondary'))
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.triggerAudioCmd('toggleLike');
          })
      }

      if (this.canPrevious) {
        Text('⏮')
          .fontSize(compact ? 12 : 14)
          .fontColor($r('sys.color.font_primary'))
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.triggerAudioCmd('previous');
          })
      }

      Text(this.isPlaying ? '⏸' : '▶')
        .fontSize(compact ? 13 : 15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 14, right: 14, top: 4, bottom: 4 })
        .borderRadius(11)
        .backgroundColor('#3B82F6')
        .onClick(() => {
          this.triggerAudioCmd('togglePlayPause');
        })

      if (this.canNext) {
        Text('⏭')
          .fontSize(compact ? 12 : 14)
          .fontColor($r('sys.color.font_primary'))
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .borderRadius(10)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            this.triggerAudioCmd('next');
          })
      }
    }
  }

  build() {
    if (!this.active || this.title.trim().length === 0) {
      Column({ space: 6 }) {
        Text('MoviePilot 正在播放')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3B82F6')
          .maxLines(1)
          .width('100%')
        Blank()
        Text('当前暂无播放中的插件音频')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(2)
          .width('100%')
        Text('点击打开 MoviePilot')
          .fontSize(11)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .width('100%')
        Blank()
      }
      .width('100%')
      .height('100%')
      .padding(14)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: { uri: this.openTargetUri() }
        });
      })
    } else if (this.dimension === '2*2') {
      Column({ space: 6 }) {
        Row() {
          this.albumCoverBox(42, 11);
          Blank()
          Text(this.isPlaying ? '⏸' : '▶')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(11)
            .backgroundColor('#3B82F6')
            .onClick(() => {
              this.triggerAudioCmd('togglePlayPause');
            })
        }
        .width('100%')

        Blank()

        Text(this.title)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subtitleLine())
          .fontSize(10.5)
          .fontColor($r('sys.color.font_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: { uri: this.openTargetUri() }
        });
      })
    } else if (this.dimension === '4*4') {
      Column({ space: 8 }) {
        Row({ space: 12 }) {
          this.albumCoverBox(78, 16);
          Column({ space: 4 }) {
            if (this.pluginName.length > 0) {
              Text(this.pluginName)
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor('#3B82F6')
                .maxLines(1)
            }
            Text(this.title)
              .fontSize(15.5)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.subtitleLine())
              .fontSize(11.5)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        if (this.durationMs > 0) {
          Column({ space: 3 }) {
            Progress({
              value: Math.min(100, Math.round((this.positionMs / this.durationMs) * 100)),
              total: 100,
              type: ProgressType.Linear
            })
              .color('#3B82F6')
              .width('100%')
              .height(4)
            Row() {
              Text(formatMs(this.positionMs))
                .fontSize(10)
                .fontColor($r('sys.color.font_tertiary'))
                .fontFeature('"tnum" 1')
              Blank()
              Text(formatMs(this.durationMs))
                .fontSize(10)
                .fontColor($r('sys.color.font_tertiary'))
                .fontFeature('"tnum" 1')
            }
            .width('100%')
          }
          .width('100%')
        }

        Divider()
          .color($r('sys.color.comp_divider'))
          .strokeWidth(0.5)

        Column({ space: 4 }) {
          if (extractCleanLyrics(this.lyrics).length === 0) {
            Text('暂无同步歌词')
              .fontSize(11.5)
              .fontColor($r('sys.color.font_secondary'))
          } else {
            ForEach(
              extractCleanLyrics(this.lyrics).slice(0, 4),
              (line: string, idx: number) => {
                Text(line)
                  .fontSize(idx === 0 ? 13 : 11.5)
                  .fontWeight(idx === 0 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(idx === 0 ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              },
              (line: string, idx: number) => `${idx}-${line}`
            )
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Blank()

        Row() {
          this.controlBar(false);
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding(14)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: { uri: this.openTargetUri() }
        });
      })
    } else {
      // 默认 2*4 中号形态
      Row({ space: 12 }) {
        this.albumCoverBox(72, 16);
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.subtitleLine())
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (extractCleanLyrics(this.lyrics).length > 0) {
            Text(extractCleanLyrics(this.lyrics)[0])
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#3B82F6')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          Blank()
          this.controlBar(true);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .padding(14)
      .borderRadius(20)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          abilityName: 'EntryAbility',
          params: { uri: this.openTargetUri() }
        });
      })
    }
  }
}
