import {
  MoviePilotRepository,
  MpDashboardStats,
  MpCommunityState,
  MpCommunityMedal,
  MpMessageItem,
  MpSchedulerItem,
  formatByteSize,
  formatSpeed
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeBackHeader,
  HarmonyPageHeader,
  HarmonyUnderlineTabBar,
  HarmonyThemeColors,
  GeneratedDesignTokens,
  HarmonyAppearanceStore,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import {
  NativeCommunityMedalsWidget,
  CommunityMedal3DComponent
} from '@moviepilot/medal_3d';

/**
 * 鸿蒙「我的」主仪表盘（遵循 HarmonyOS 左侧大标题 + 右侧动态光感消息与设置入口）：
 * 100% 消费真实 `/api/v1/dashboard/*`、`/api/v1/github/community` 与 `/api/v1/message/web`，
 * 包含 2×2 媒体库统计、真实 3D 社区勋章矩阵、存储空间环形卡、下载器双速卡片、8 日整理趋势柱图与带封面图消息中心。
 */
@Component
export struct HarmonyDashboardPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop userName: string = 'admin';
  @Prop serverUrl: string = '';
  @State private stats: MpDashboardStats = {
    movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0,
    storageUsedBytes: 0, storageTotalBytes: 0,
    downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
    memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
  };
  @State private community: MpCommunityState = { githubLogin: 'MoviePilot', earnedCount: 0, totalCount: 7, medals: [] };
  @State private messages: MpMessageItem[] = [];
  @State private showMessagesSheet: boolean = false;
  @State private showMedalSheet: boolean = false;
  @State private selectedMedal: MpCommunityMedal | null = null;
  onOpenShortcuts: () => void = () => {};
  onOpenSettings: () => void = () => {};

  aboutToAppear(): void {
    this.refreshDashboard();
  }

  private async refreshDashboard(): Promise<void> {
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchDashboardStats(),
        repo.fetchCommunityMedals(),
        repo.fetchMessages()
      ]);
      this.stats = res[0];
      this.community = res[1];
      this.messages = res[2];
    } catch {
      // keep existing state
    }
  }

  private storageRatioPercent(): number {
    if (this.stats.storageTotalBytes <= 0) { return 0; }
    return Math.min(100, Math.max(0, (this.stats.storageUsedBytes / this.stats.storageTotalBytes) * 100));
  }

  private maxTransfer(): number {
    let m = 1;
    for (let i = 0; i < this.stats.transferCounts.length; i++) {
      if (this.stats.transferCounts[i] > m) { m = this.stats.transferCounts[i]; }
    }
    return m;
  }

  @Builder
  messagesSheetBuilder() {
    Column({ space: 12 }) {
      Text(`消息中心 (${this.messages.length})`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(mpPrimaryText(this.isDark))
        .width('100%')
      Scroll() {
        Column({ space: 10 }) {
          if (this.messages.length === 0) {
            Text('暂无最新消息通知').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.messages, (msg: MpMessageItem) => {
              CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
                Row({ space: 12 }) {
                  if (msg.image.length > 0) {
                    Image(msg.image)
                      .width(56)
                      .height(78)
                      .borderRadius(10)
                      .objectFit(ImageFit.Cover)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  }
                  Column({ space: 4 }) {
                    Row() {
                      Text(msg.title)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(mpPrimaryText(this.isDark))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                      if (msg.date.length > 0) {
                        Text(msg.date.substring(0, 16)).fontSize(10).fontColor(mpSecondaryText(this.isDark))
                      }
                    }.width('100%')
                    Text(msg.text)
                      .fontSize(12)
                      .fontColor(mpSecondaryText(this.isDark))
                      .maxLines(3)
                      .lineHeight(18)
                      .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }.width('100%')
              }
            }, (msg: MpMessageItem) => msg.id)
          }
        }
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  medalShowcaseSheetBuilder() {
    Column({ space: 16 }) {
      if (this.selectedMedal) {
        Text(this.selectedMedal.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
        Text(this.selectedMedal.subtitle)
          .fontSize(13)
          .fontColor(mpSecondaryText(this.isDark))
        CommunityMedal3DComponent({
          medalId: this.selectedMedal.id,
          frontAsset: this.selectedMedal.frontAsset,
          backAsset: this.selectedMedal.backAsset,
          title: this.selectedMedal.title,
          subtitle: this.selectedMedal.subtitle,
          ownerName: this.community.githubLogin,
          earnedDate: this.selectedMedal.earnedDate
        })
      }
    }
    .padding(24)
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      HarmonyPageHeader({
        title: '我的',
        subtitle: this.serverUrl ? `${this.userName} · ${this.serverUrl.replace(/^https?:\/\//, '')}` : this.userName,
        secondarySymbol: 'sys.symbol.bell',
        secondaryAccessibility: '消息中心',
        primarySymbol: 'sys.symbol.gearshape',
        primaryAccessibility: '系统设置',
        onSecondaryClick: () => { this.showMessagesSheet = true; },
        onPrimaryClick: () => this.onOpenSettings()
      })
        .bindSheet($$this.showMessagesSheet, this.messagesSheetBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          blurStyle: BlurStyle.COMPONENT_THIN,
          dragBar: true,
          backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
        })

      Scroll() {
        Column({ space: 18 }) {
          // 1. 媒体库统计 2×2
          Text('媒体库统计').fontSize(17).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
          Row({ space: 12 }) {
            Column() {
              CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
                Column({ space: 6 }) {
                  Text(`${this.stats.movieCount}`).fontSize(25).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text('电影').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  NativeAdaptiveBadge({ text: '媒体库', tintHex: '#FAAD14' })
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1)
            Column() {
              CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
                Column({ space: 6 }) {
                  Text(`${this.stats.tvCount}`).fontSize(25).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text('剧集').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  NativeAdaptiveBadge({ text: '自动追更', tintHex: this.accentHex })
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1)
          }
          Row({ space: 12 }) {
            Column() {
              CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
                Column({ space: 6 }) {
                  Text(`${this.stats.episodeCount}`).fontSize(25).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text('剧集单集').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  NativeAdaptiveBadge({ text: '已刮削', tintHex: '#36CFC9' })
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1)
            Column() {
              CinematicPanel({ panelPadding: 15, cornerRadius: 18, interactive: true }) {
                Column({ space: 6 }) {
                  Text(`${this.stats.scheduleCount}`).fontSize(25).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text('后台定时服务').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  NativeAdaptiveBadge({ text: '点击诊断', tintHex: '#52C41A' })
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => this.onOpenShortcuts())
          }

          // 2. 真实 3D 社区勋章矩阵
          if (this.community.medals.length > 0) {
            NativeCommunityMedalsWidget({
              githubLogin: this.community.githubLogin,
              earnedCount: this.community.earnedCount,
              totalCount: this.community.totalCount,
              medals: this.community.medals,
              onSelectMedal: (m: MpCommunityMedal) => {
                this.selectedMedal = m;
                this.showMedalSheet = true;
              }
            })
              .bindSheet($$this.showMedalSheet, this.medalShowcaseSheetBuilder(), {
                detents: [SheetSize.LARGE],
                blurStyle: BlurStyle.COMPONENT_THIN,
                dragBar: true,
                backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
              })
          }

          // 3. 存储空间环形进度卡
          Text('存储空间').fontSize(17).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Row({ space: 18 }) {
              Stack() {
                Progress({ value: this.storageRatioPercent(), total: 100, type: ProgressType.Ring })
                  .width(86).height(86).color(this.accentHex).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  .style({ strokeWidth: 9 })
                Text(`${this.storageRatioPercent().toFixed(1)}%`).fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
              }
              Column({ space: 4 }) {
                Text(`${formatByteSize(this.stats.storageUsedBytes)} / ${formatByteSize(this.stats.storageTotalBytes)}`)
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                Text('已用 / 总容量').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                Text(`剩余 ${formatByteSize(Math.max(0, this.stats.storageTotalBytes - this.stats.storageUsedBytes))}`)
                  .fontSize(13).fontColor(GeneratedDesignTokens.semanticColor('success', this.isDark))
              }.alignItems(HorizontalAlign.Start)
            }.width('100%')
          }

          // 4. 下载器实时双速卡
          Text('下载器').fontSize(17).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(`↓ ${formatSpeed(this.stats.downloadSpeed)}`).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#52C41A')
                  Text('实时下载').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                }
                .layoutWeight(1).padding(12).borderRadius(14).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).alignItems(HorizontalAlign.Start)

                Column({ space: 4 }) {
                  Text(`↑ ${formatSpeed(this.stats.uploadSpeed)}`).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#6EA8FE')
                  Text('实时上传').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                }
                .layoutWeight(1).padding(12).borderRadius(14).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).alignItems(HorizontalAlign.Start)
              }
              Text(`累计下载 ${formatByteSize(this.stats.downloadSize)} · 累计上传 ${formatByteSize(this.stats.uploadSize)}`)
                .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
            }
          }

          // 5. 近期整理趋势（真实 8 天柱图）
          if (this.stats.transferCounts.length > 0) {
            Text('整理趋势').fontSize(17).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
            CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
              Row({ space: 8 }) {
                ForEach(this.stats.transferCounts, (count: number, idx: number) => {
                  Column({ space: 4 }) {
                    Text(`${count}`).fontSize(10).fontColor(mpSecondaryText(this.isDark))
                    Column()
                      .width(20)
                      .height(Math.max(8, Math.round((count / this.maxTransfer()) * 84)))
                      .borderRadius(6)
                      .linearGradient({ angle: 180, colors: [[this.accentHex, 0], ['#559E7AF5', 1]] })
                    Text(`D${idx + 1}`).fontSize(10).fontColor(mpSecondaryText(this.isDark))
                  }
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.End)
                  .height(120)
                })
              }.width('100%')
            }
          }
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 124 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙捷径与诊断中心页（采用规范下划线页签栏切换定时服务与实时日志）。 */
@Component
export struct HarmonyDiagnosticsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private activeTabIdx: number = 0;
  @State private schedulers: MpSchedulerItem[] = [];
  @State private logs: string[] = [];
  @State private loading: boolean = true;
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadDiag();
  }

  private async loadDiag(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchSchedulers(),
        repo.fetchLiveLogs()
      ]);
      this.schedulers = res[0];
      this.logs = res[1];
    } catch {
      // ignore
    }
    this.loading = false;
  }

  build() {
    Column({ space: 8 }) {
      NativeBackHeader({
        title: '捷径与诊断中心',
        trailingSymbol: 'sys.symbol.arrow_clockwise',
        trailingAccessibility: '刷新诊断数据',
        onBack: () => this.onBack(),
        onTrailingClick: () => this.loadDiag()
      })

      HarmonyUnderlineTabBar({
        tabs: [`定时服务 (${this.schedulers.length})`, '实时日志'],
        selectedIndex: this.activeTabIdx,
        onSelect: (idx: number) => { this.activeTabIdx = idx; }
      })

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.accentHex)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            if (this.activeTabIdx === 0) {
              ForEach(this.schedulers, (s: MpSchedulerItem) => {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                  Row() {
                    Column({ space: 3 }) {
                      Text(s.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                      Text(`${s.provider} · 下次执行 ${s.nextRun || '等待调度'}`).fontSize(11).fontColor(mpSecondaryText(this.isDark))
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    NativeAdaptiveBadge({ text: s.status || '等待', tintHex: '#52C41A' })
                  }.width('100%')
                }
              }, (s: MpSchedulerItem) => s.id)
            } else {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Column({ space: 6 }) {
                  ForEach(this.logs, (line: string, idx: number) => {
                    Text(line).fontSize(11).fontColor(mpPrimaryText(this.isDark)).lineHeight(17).width('100%')
                  }, (_line: string, idx: number) => `log_${idx}`)
                }
              }
            }
          }.padding({ left: 16, right: 16, top: 6, bottom: 40 })
        }.scrollBar(BarState.Off).layoutWeight(1)
      }
    }.width('100%').height('100%')
  }
}
