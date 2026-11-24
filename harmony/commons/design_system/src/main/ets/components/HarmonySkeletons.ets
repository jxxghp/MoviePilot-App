import { HarmonyAppearanceStore } from '../store/AppearanceStore';
import { HarmonyAdaptiveLayout } from './AdaptiveBreakpoints';
import { CinematicPanel } from './CinematicSurfaces';
import { HarmonyMotionTokens, HarmonyThemeColors } from './HarmonyDynamicLight';

/** 骨架块视觉层级语义。 */
export type HarmonySkeletonTone = 'surface' | 'block' | 'subtle';

/** 顶部沉浸主视觉骨架模式。 */
export type HarmonyHeroSkeletonMode = 'discover' | 'detail';

/** 带左侧海报的横向条目卡片骨架变体。 */
export type HarmonyPosterRowSkeletonVariant = 'subscribe' | 'calendar' | 'history' | 'share';

/** 通用业务卡片网格骨架变体。 */
export type HarmonyCardSkeletonVariant =
  'resource' | 'download' | 'file' | 'site' | 'workflow' | 'plugin' | 'service' | 'scheduler';

function skeletonIndices(count: number): number[] {
  const safeCount = Math.max(1, Math.round(count));
  const out: number[] = [];
  for (let i = 0; i < safeCount; i++) {
    out.push(i);
  }
  return out;
}

const TREND_SKELETON_HEIGHTS: number[] = [34, 58, 44, 78, 62, 48, 70];

/**
 * 鸿蒙统一骨架屏宿主容器：
 * - 在 `.onAppear()` 中启动 RenderService 合成层透明度呼吸动效，自动响应 `KEY_ANIMATE_BG` 低运动开关；
 * - 通过 `.accessibilityGroup(true)` + `.accessibilityText(...)` 聚合为单一无障碍播报节点，避免读屏逐块朗读装饰块；
 * - 组件挂载与卸载采用语义化 `TransitionEffect.OPACITY` 平滑过渡。
 */
@Component
export struct HarmonySkeletonHost {
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) @Watch('onAnimatePrefChanged') animateBg: boolean = true;
  @Prop loadingLabel: string = '正在加载内容';
  @Prop fillHeight: boolean = false;
  @State private pulseOpacity: number = 1.0;
  @BuilderParam content: () => void = this.defaultBuilder;

  @Builder
  defaultBuilder() {}

  private onAnimatePrefChanged(): void {
    if (!this.animateBg) {
      try {
        this.getUIContext().animateTo({
          duration: HarmonyMotionTokens.DURATION_SHORT,
          curve: HarmonyMotionTokens.CURVE_DECELERATE,
          iterations: 1
        }, () => {
          this.pulseOpacity = 1.0;
        });
      } catch {
        this.pulseOpacity = 1.0;
      }
      return;
    }
    this.startBreathing();
  }

  private startBreathing(): void {
    if (!this.animateBg) {
      this.pulseOpacity = 1.0;
      return;
    }
    this.pulseOpacity = 0.98;
    try {
      this.getUIContext().animateTo({
        duration: 1050,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.pulseOpacity = 0.56;
      });
    } catch {
      this.pulseOpacity = 0.85;
    }
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.fillHeight ? '100%' : undefined)
    .opacity(this.pulseOpacity)
    .accessibilityGroup(true)
    .accessibilityText(this.loadingLabel)
    .transition(
      TransitionEffect.OPACITY.animation({
        duration: HarmonyMotionTokens.DURATION_LOCAL,
        curve: HarmonyMotionTokens.CURVE_STANDARD
      })
    )
    .onAppear(() => {
      this.startBreathing();
    })
  }
}

/**
 * 鸿蒙结构化圆角骨架块：
 * - 支持固定宽高或 `blockAspectRatio` 等比占位，杜绝异步图片/文本回填时产生布局跳变；
 * - 针对主视觉、海报与封面卡片可选开启 GPU `.translate({ x })` 扫光高光带（零布局重排）。
 */
@Component
export struct HarmonySkeletonBlock {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) animateBg: boolean = true;
  @Prop blockWidth: Length = '100%';
  @Prop blockHeight: Length = 16;
  @Prop blockAspectRatio: number = 0;
  @Prop cornerRadius: number = 8;
  @Prop tone: HarmonySkeletonTone = 'block';
  @Prop shimmerSweep: boolean = false;
  @State private sweepOffsetX: number = -220;

  private resolvedFill(): string {
    if (this.tone === 'surface') {
      return HarmonyThemeColors.skeletonSurface(this.isDark, this.paletteId, this.pureBlack);
    }
    if (this.tone === 'subtle') {
      return HarmonyThemeColors.skeletonSubtle(this.isDark, this.pureBlack);
    }
    return HarmonyThemeColors.skeletonBlock(this.isDark, this.pureBlack);
  }

  private startSweep(): void {
    if (!this.shimmerSweep || !this.animateBg) {
      return;
    }
    this.sweepOffsetX = -220;
    try {
      this.getUIContext().animateTo({
        duration: 1380,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Normal
      }, () => {
        this.sweepOffsetX = 380;
      });
    } catch {
      this.sweepOffsetX = -220;
    }
  }

  build() {
    if (this.shimmerSweep && this.animateBg) {
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.resolvedFill())

        Column()
          .width(148)
          .height('100%')
          .linearGradient({
            angle: 105,
            colors: [
              ['#00FFFFFF', 0.0],
              [HarmonyThemeColors.skeletonShimmerPeak(this.isDark, this.pureBlack), 0.5],
              ['#00FFFFFF', 1.0]
            ]
          })
          .translate({ x: this.sweepOffsetX })
          .onAppear(() => {
            this.startSweep();
          })
      }
      .width(this.blockWidth)
      .height(this.blockAspectRatio > 0 ? undefined : this.blockHeight)
      .aspectRatio(this.blockAspectRatio > 0 ? this.blockAspectRatio : undefined)
      .borderRadius(this.cornerRadius)
      .border(this.tone === 'surface'
        ? { width: 0.6, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: this.cornerRadius }
        : undefined)
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
    } else {
      Column()
        .width(this.blockWidth)
        .height(this.blockAspectRatio > 0 ? undefined : this.blockHeight)
        .aspectRatio(this.blockAspectRatio > 0 ? this.blockAspectRatio : undefined)
        .borderRadius(this.cornerRadius)
        .backgroundColor(this.resolvedFill())
        .border(this.tone === 'surface'
          ? { width: 0.6, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: this.cornerRadius }
          : undefined)
        .hitTestBehavior(HitTestMode.None)
    }
  }
}

/**
 * 发现页与详情页共用的响应式沉浸主视觉骨架（严格对齐竖屏、宽屏与矮横屏真实 Hero 高度）。
 */
@Component
export struct HarmonyHeroSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop mode: HarmonyHeroSkeletonMode = 'discover';

  private isShortLandscape(): boolean {
    return HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp);
  }

  private resolvedHeight(): number {
    if (this.mode === 'detail') {
      return HarmonyAdaptiveLayout.detailHeroHeightVp(this.windowWidthVp, this.windowHeightVp);
    }
    return HarmonyAdaptiveLayout.discoverHeroHeightVp(this.windowWidthVp, this.windowHeightVp);
  }

  private baseCanvas(): string {
    return HarmonyThemeColors.canvas(this.isDark, this.paletteId, this.pureBlack);
  }

  build() {
    Stack({ alignContent: this.mode === 'discover' ? Alignment.Bottom : Alignment.BottomStart }) {
      HarmonySkeletonBlock({
        blockWidth: '100%',
        blockHeight: this.resolvedHeight(),
        cornerRadius: 0,
        tone: 'subtle',
        shimmerSweep: true
      })

      Column()
        .width('100%')
        .height(this.resolvedHeight())
        .linearGradient({
          angle: 180,
          colors: [
            ['#00000000', 0.0],
            ['#00000000', 0.42],
            [HarmonyAppearanceStore.withAlpha(this.baseCanvas(), 'C8'), 0.80],
            [this.baseCanvas(), 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      if (this.mode === 'discover') {
        Column({ space: this.isShortLandscape() ? 6 : 10 }) {
          HarmonySkeletonBlock({
            blockWidth: this.isShortLandscape() ? 156 : 216,
            blockHeight: this.isShortLandscape() ? 26 : 36,
            cornerRadius: 10
          })
          HarmonySkeletonBlock({
            blockWidth: 148,
            blockHeight: 12,
            cornerRadius: 6,
            tone: 'subtle'
          })
          if (!this.isShortLandscape()) {
            HarmonySkeletonBlock({
              blockWidth: 268,
              blockHeight: 12,
              cornerRadius: 6,
              tone: 'subtle'
            })
          }
          Row({ space: 10 }) {
            HarmonySkeletonBlock({ blockWidth: 88, blockHeight: 22, cornerRadius: 11 })
            HarmonySkeletonBlock({ blockWidth: 46, blockHeight: 16, cornerRadius: 8, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 64, blockHeight: 16, cornerRadius: 8, tone: 'subtle' })
          }
          .margin({ top: 2 })
        }
        .padding({
          left: 22,
          right: 22,
          bottom: this.isShortLandscape() ? 16 : 28
        })
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: this.isShortLandscape() ? 6 : 10 }) {
          HarmonySkeletonBlock({
            blockWidth: this.isShortLandscape() ? 168 : 214,
            blockHeight: this.isShortLandscape() ? 24 : 32,
            cornerRadius: 9
          })
          Row({ space: 8 }) {
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 22, cornerRadius: 10 })
            HarmonySkeletonBlock({ blockWidth: 46, blockHeight: 22, cornerRadius: 10 })
            HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 22, cornerRadius: 10, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 22, cornerRadius: 10, tone: 'subtle' })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(this.isShortLandscape() ? 14 : 20)
      }
    }
    .width('100%')
    .height(this.resolvedHeight())
  }
}

/**
 * 2:3 海报横滑栏骨架（匹配发现页各模块与详情页「类似作品」横滑区）。
 */
@Component
export struct HarmonyPosterShelfSkeleton {
  @Prop cardWidth: number = 116;
  @Prop cardHeight: number = 172;
  @Prop itemCount: number = 5;
  @Prop showHeader: boolean = true;
  @Prop showTrailingAction: boolean = true;

  build() {
    Column({ space: 12 }) {
      if (this.showHeader) {
        Row() {
          HarmonySkeletonBlock({ blockWidth: 96, blockHeight: 20, cornerRadius: 7 })
          Blank()
          if (this.showTrailingAction) {
            HarmonySkeletonBlock({ blockWidth: 46, blockHeight: 15, cornerRadius: 6, tone: 'subtle' })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }

      Row({ space: 12 }) {
        ForEach(skeletonIndices(this.itemCount), (idx: number) => {
          Column({ space: 6 }) {
            HarmonySkeletonBlock({
              blockWidth: this.cardWidth,
              blockHeight: this.cardHeight,
              cornerRadius: 14,
              shimmerSweep: true
            })
            HarmonySkeletonBlock({
              blockWidth: Math.round(this.cardWidth * 0.80),
              blockHeight: 13,
              cornerRadius: 5
            })
            HarmonySkeletonBlock({
              blockWidth: Math.round(this.cardWidth * 0.48),
              blockHeight: 11,
              cornerRadius: 5,
              tone: 'subtle'
            })
          }
          .alignItems(HorizontalAlign.Start)
        }, (idx: number) => `ps_sk_${this.cardWidth}_${idx}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .clip(true)
    }
    .width('100%')
  }
}

/**
 * 16:9 剧集单集横版剧照条骨架（228×128，支持可选分季胶囊条与分集简介占位）。
 */
@Component
export struct HarmonyEpisodeStripSkeleton {
  @Prop showHeader: boolean = false;
  @Prop showSeasonPills: boolean = false;
  @Prop itemCount: number = 3;

  build() {
    Column({ space: 12 }) {
      if (this.showHeader) {
        Row() {
          HarmonySkeletonBlock({ blockWidth: 88, blockHeight: 18, cornerRadius: 6 })
          Blank()
          HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 13, cornerRadius: 5, tone: 'subtle' })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }

      if (this.showSeasonPills) {
        Row({ space: 8 }) {
          ForEach(skeletonIndices(3), (idx: number) => {
            HarmonySkeletonBlock({
              blockWidth: 76,
              blockHeight: 32,
              cornerRadius: 16,
              tone: idx === 0 ? 'block' : 'subtle'
            })
          }, (idx: number) => `ep_sp_${idx}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }

      Row({ space: 12 }) {
        ForEach(skeletonIndices(this.itemCount), (idx: number) => {
          Column({ space: 6 }) {
            HarmonySkeletonBlock({
              blockWidth: 228,
              blockHeight: 128,
              cornerRadius: 14,
              shimmerSweep: true
            })
            HarmonySkeletonBlock({ blockWidth: 164, blockHeight: 14, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: 212, blockHeight: 11, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 148, blockHeight: 11, cornerRadius: 5, tone: 'subtle' })
          }
          .width(228)
          .alignItems(HorizontalAlign.Start)
        }, (idx: number) => `ep_sk_${idx}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .clip(true)
    }
    .width('100%')
  }
}

/**
 * 发现页完整首屏骨架（Hero + 16:9 继续观看 238×134 + 双层 2:3 海报架 116×172 + 16:9 媒体库架 196×112）：
 * 彻底阻断底部静态分类模块在推荐流返回前顶到首屏并跳变 1200vp 的问题。
 */
@Component
export struct HarmonyDiscoverSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;

  private isShortLandscape(): boolean {
    return HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp);
  }

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在加载发现推荐内容' }) {
      Column({ space: this.isShortLandscape() ? 16 : 22 }) {
        HarmonyHeroSkeleton({ mode: 'discover' })

        // 16:9 继续观看横滑栏 (238x134)
        Column({ space: 12 }) {
          Row() {
            HarmonySkeletonBlock({ blockWidth: 92, blockHeight: 20, cornerRadius: 7 })
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row({ space: 12 }) {
            ForEach(skeletonIndices(3), (idx: number) => {
              Column({ space: 6 }) {
                HarmonySkeletonBlock({
                  blockWidth: 238,
                  blockHeight: 134,
                  cornerRadius: 16,
                  shimmerSweep: true
                })
                HarmonySkeletonBlock({ blockWidth: 158, blockHeight: 14, cornerRadius: 5 })
                HarmonySkeletonBlock({ blockWidth: 96, blockHeight: 11, cornerRadius: 5, tone: 'subtle' })
              }
              .width(238)
              .alignItems(HorizontalAlign.Start)
            }, (idx: number) => `disc_cont_${idx}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .clip(true)
        }
        .width('100%')

        // 两排 2:3 影视海报架 (116x172)
        HarmonyPosterShelfSkeleton({ cardWidth: 116, cardHeight: 172, itemCount: 5 })
        HarmonyPosterShelfSkeleton({ cardWidth: 116, cardHeight: 172, itemCount: 5 })

        // 16:9 我的媒体库封面架 (196x112)
        Column({ space: 12 }) {
          Row() {
            HarmonySkeletonBlock({ blockWidth: 108, blockHeight: 20, cornerRadius: 7 })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 16, cornerRadius: 6, tone: 'subtle' })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row({ space: 12 }) {
            ForEach(skeletonIndices(3), (idx: number) => {
              HarmonySkeletonBlock({
                blockWidth: 196,
                blockHeight: 112,
                cornerRadius: 16,
                shimmerSweep: true
              })
            }, (idx: number) => `disc_lib_${idx}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .clip(true)
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}

/**
 * 影视详情与媒体库详情页下部主体骨架：
 * 1:1 匹配「剧情简介」面板、可选「剧集」16:9 横滑、圆形 66×66「演职员」头像、可选「类似作品」、可选「链接」胶囊与 232vp「媒体信息」流卡片。
 */
@Component
export struct HarmonyMediaDetailBodySkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @Prop showSeasons: boolean = false;
  @Prop showSimilar: boolean = false;
  @Prop showLinks: boolean = false;
  @Prop showStreamCards: boolean = false;

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在同步媒体详情与元数据' }) {
      Column({ space: 18 }) {
        // 剧情简介面板
        Column() {
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              HarmonySkeletonBlock({ blockWidth: 78, blockHeight: 16, cornerRadius: 6 })
              HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 13, cornerRadius: 5, tone: 'subtle' })
              HarmonySkeletonBlock({ blockWidth: '94%', blockHeight: 13, cornerRadius: 5, tone: 'subtle' })
              HarmonySkeletonBlock({ blockWidth: '66%', blockHeight: 13, cornerRadius: 5, tone: 'subtle' })
              Row({ space: 6 }) {
                HarmonySkeletonBlock({ blockWidth: 48, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
                HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
                HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // 可选剧集横版剧照条
        if (this.showSeasons) {
          HarmonyEpisodeStripSkeleton({ showHeader: true, showSeasonPills: true, itemCount: 3 })
        }

        // 66x66 圆形演职员头像条
        Column({ space: 10 }) {
          Row() {
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 18, cornerRadius: 6 })
            Blank()
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row({ space: 14 }) {
            ForEach(skeletonIndices(5), (idx: number) => {
              Column({ space: 6 }) {
                HarmonySkeletonBlock({
                  blockWidth: 66,
                  blockHeight: 66,
                  cornerRadius: 33,
                  shimmerSweep: true
                })
                HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 12, cornerRadius: 5 })
                HarmonySkeletonBlock({ blockWidth: 42, blockHeight: 10, cornerRadius: 4, tone: 'subtle' })
              }
              .width(74)
              .alignItems(HorizontalAlign.Center)
            }, (idx: number) => `cast_sk_${idx}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .clip(true)
        }
        .width('100%')

        // 可选 2:3 类似作品海报条 (118x177)
        if (this.showSimilar) {
          HarmonyPosterShelfSkeleton({
            cardWidth: 118,
            cardHeight: 177,
            itemCount: 5,
            showHeader: true,
            showTrailingAction: false
          })
        }

        // 可选外部链接胶囊条
        if (this.showLinks) {
          Column({ space: 12 }) {
            Row() {
              HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 18, cornerRadius: 6 })
              Blank()
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            Row({ space: 10 }) {
              HarmonySkeletonBlock({ blockWidth: 86, blockHeight: 36, cornerRadius: 18, tone: 'surface' })
              HarmonySkeletonBlock({ blockWidth: 84, blockHeight: 36, cornerRadius: 18, tone: 'surface' })
              HarmonySkeletonBlock({ blockWidth: 114, blockHeight: 36, cornerRadius: 18, tone: 'surface' })
              HarmonySkeletonBlock({ blockWidth: 82, blockHeight: 36, cornerRadius: 18, tone: 'surface' })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .clip(true)
          }
          .width('100%')
        }

        // 可选 232vp 媒体信息轨道卡片横滑栏
        if (this.showStreamCards) {
          Column({ space: 12 }) {
            Row() {
              HarmonySkeletonBlock({ blockWidth: 84, blockHeight: 18, cornerRadius: 6 })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 74, blockHeight: 13, cornerRadius: 5, tone: 'subtle' })
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            Row({ space: 12 }) {
              ForEach(skeletonIndices(3), (idx: number) => {
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    HarmonySkeletonBlock({ blockWidth: 18, blockHeight: 18, cornerRadius: 5 })
                    HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 16, cornerRadius: 5 })
                  }
                  .width('100%')

                  ForEach(skeletonIndices(5), (rIdx: number) => {
                    Row({ space: 8 }) {
                      HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                      HarmonySkeletonBlock({ blockWidth: 112, blockHeight: 12, cornerRadius: 4 })
                    }
                    .width('100%')
                  }, (rIdx: number) => `st_row_${idx}_${rIdx}`)
                }
                .width(232)
                .padding(16)
                .alignItems(HorizontalAlign.Start)
                .borderRadius(16)
                .backgroundColor(HarmonyThemeColors.skeletonSurface(this.isDark, this.paletteId, this.pureBlack))
                .border({
                  width: 0.8,
                  color: HarmonyThemeColors.borderSubtle(this.isDark),
                  radius: 16
                })
              }, (idx: number) => `stream_sk_${idx}`)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .clip(true)
          }
          .width('100%')
        }
      }
      .width('100%')
    }
  }
}

/**
 * 响应式 2:3 影视海报网格骨架（自动适配 3~6 列，用于媒体库、探索、全局搜索、人物作品与订阅广场）。
 */
@Component
export struct HarmonyPosterGridSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop rows: number = 0;
  @Prop horizontalPadding: number = 16;
  @Prop bottomPadding: number = 36;
  @Prop fillViewport: boolean = false;

  private resolvedCount(): number {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(this.windowWidthVp);
    const r = this.rows > 0
      ? this.rows
      : (HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp) ? 2 : 3);
    return cols * r;
  }

  @Builder
  gridBody() {
    HarmonySkeletonHost({ loadingLabel: '正在加载海报列表' }) {
      Grid() {
        ForEach(skeletonIndices(this.resolvedCount()), (idx: number) => {
          GridItem() {
            Column({ space: 6 }) {
              HarmonySkeletonBlock({
                blockWidth: '100%',
                blockAspectRatio: 0.67,
                cornerRadius: 14,
                shimmerSweep: true
              })
              HarmonySkeletonBlock({ blockWidth: '82%', blockHeight: 13, cornerRadius: 5 })
              HarmonySkeletonBlock({ blockWidth: '48%', blockHeight: 11, cornerRadius: 5, tone: 'subtle' })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }, (idx: number) => `pg_sk_${idx}`)
      }
      .columnsTemplate(HarmonyAdaptiveLayout.posterGridTemplate(this.windowWidthVp))
      .columnsGap(10)
      .rowsGap(14)
      .width('100%')
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding, bottom: this.bottomPadding })
    }
  }

  build() {
    if (this.fillViewport) {
      Scroll() {
        this.gridBody()
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
    } else {
      this.gridBody()
    }
  }
}

/**
 * 响应式 1:1 音乐方形专辑网格骨架（自动适配 2/4/5/6 列）。
 */
@Component
export struct HarmonyAlbumGridSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop rows: number = 0;
  @Prop horizontalPadding: number = 16;
  @Prop bottomPadding: number = 36;
  @Prop fillViewport: boolean = false;

  private resolvedCols(): number {
    if (this.windowWidthVp >= 1040) { return 6; }
    if (this.windowWidthVp >= 780) { return 5; }
    if (this.windowWidthVp >= 540) { return 4; }
    return 2;
  }

  private resolvedCount(): number {
    const r = this.rows > 0
      ? this.rows
      : (HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp) ? 2 : 3);
    return this.resolvedCols() * r;
  }

  @Builder
  gridBody() {
    HarmonySkeletonHost({ loadingLabel: '正在加载音乐专辑' }) {
      Grid() {
        ForEach(skeletonIndices(this.resolvedCount()), (idx: number) => {
          GridItem() {
            Column({ space: 6 }) {
              HarmonySkeletonBlock({
                blockWidth: '100%',
                blockAspectRatio: 1,
                cornerRadius: 16,
                shimmerSweep: true
              })
              HarmonySkeletonBlock({ blockWidth: '78%', blockHeight: 13.5, cornerRadius: 5 })
              HarmonySkeletonBlock({ blockWidth: '54%', blockHeight: 11.5, cornerRadius: 5, tone: 'subtle' })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }, (idx: number) => `ag_sk_${idx}`)
      }
      .columnsTemplate(HarmonyAdaptiveLayout.albumGridColumns(this.windowWidthVp))
      .columnsGap(12)
      .rowsGap(16)
      .width('100%')
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding, bottom: this.bottomPadding })
    }
  }

  build() {
    if (this.fillViewport) {
      Scroll() {
        this.gridBody()
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
    } else {
      this.gridBody()
    }
  }
}

/**
 * 响应式海报+信息横排卡片网格骨架（1/2 列自适应，覆盖我的订阅、追剧日历、整理历史与社区分享）。
 */
@Component
export struct HarmonyPosterRowCardGridSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop variant: HarmonyPosterRowSkeletonVariant = 'subscribe';
  @Prop count: number = 0;
  @Prop horizontalPadding: number = 16;
  @Prop bottomPadding: number = 40;
  @Prop fillViewport: boolean = false;

  private resolvedCount(): number {
    if (this.count > 0) {
      return this.count;
    }
    return HarmonyAdaptiveLayout.cardGridColumns(this.windowWidthVp) >= 2 ? 6 : 4;
  }

  private posterWidth(): number {
    if (this.variant === 'subscribe') { return 72; }
    if (this.variant === 'calendar') { return 64; }
    return 58;
  }

  private posterHeight(): number {
    if (this.variant === 'subscribe') { return 106; }
    if (this.variant === 'calendar') { return 94; }
    return 86;
  }

  @Builder
  cardBody() {
    CinematicPanel({ panelPadding: 13, cornerRadius: 18 }) {
      Row({ space: 12 }) {
        HarmonySkeletonBlock({
          blockWidth: this.posterWidth(),
          blockHeight: this.posterHeight(),
          cornerRadius: this.variant === 'subscribe' ? 12 : 10,
          shimmerSweep: true
        })

        if (this.variant === 'subscribe') {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: '62%', blockHeight: 16, cornerRadius: 6 })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
            }
            .width('100%')

            HarmonySkeletonBlock({ blockWidth: '42%', blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 6, cornerRadius: 3, tone: 'subtle' })

            Row({ space: 6 }) {
              HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 26, cornerRadius: 13, tone: 'subtle' })
              HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 26, cornerRadius: 13, tone: 'subtle' })
              HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 26, cornerRadius: 13, tone: 'subtle' })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 32, blockHeight: 32, cornerRadius: 16, tone: 'subtle' })
            }
            .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        } else if (this.variant === 'calendar') {
          Column({ space: 7 }) {
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: 74, blockHeight: 20, cornerRadius: 10 })
              HarmonySkeletonBlock({ blockWidth: 48, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
            }
            HarmonySkeletonBlock({ blockWidth: '72%', blockHeight: 15, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: '52%', blockHeight: 12.5, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '90%', blockHeight: 11.5, cornerRadius: 5, tone: 'subtle' })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        } else if (this.variant === 'history') {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: '64%', blockHeight: 14.5, cornerRadius: 5 })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
            }
            .width('100%')
            HarmonySkeletonBlock({ blockWidth: '46%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '88%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '80%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: 74, blockHeight: 24, cornerRadius: 12, tone: 'subtle' })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 30, blockHeight: 30, cornerRadius: 15, tone: 'subtle' })
            }
            .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        } else {
          Column({ space: 7 }) {
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: '64%', blockHeight: 14.5, cornerRadius: 5 })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
            }
            .width('100%')
            HarmonySkeletonBlock({ blockWidth: '92%', blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: '48%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 76, blockHeight: 26, cornerRadius: 13 })
            }
            .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
    }
  }

  @Builder
  gridBody() {
    HarmonySkeletonHost({ loadingLabel: '正在加载条目列表' }) {
      Grid() {
        ForEach(skeletonIndices(this.resolvedCount()), (idx: number) => {
          GridItem() {
            this.cardBody()
          }
        }, (idx: number) => `pr_sk_${this.variant}_${idx}`)
      }
      .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding, top: 4, bottom: this.bottomPadding })
    }
  }

  build() {
    if (this.fillViewport) {
      Scroll() {
        this.gridBody()
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
    } else {
      this.gridBody()
    }
  }
}

/**
 * 响应式业务卡片网格骨架（覆盖站点资源、下载任务、文件浏览、站点管理、工作流、插件、服务配置与定时任务）。
 */
@Component
export struct HarmonyCardGridSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop variant: HarmonyCardSkeletonVariant = 'resource';
  @Prop singleColumn: boolean = false;
  @Prop count: number = 0;
  @Prop horizontalPadding: number = 16;
  @Prop bottomPadding: number = 40;
  @Prop fillViewport: boolean = false;

  private resolvedCount(): number {
    if (this.count > 0) {
      return this.count;
    }
    if (this.singleColumn) {
      return 4;
    }
    const cols = HarmonyAdaptiveLayout.cardGridColumns(this.windowWidthVp);
    if (this.variant === 'file' || this.variant === 'scheduler') {
      return cols >= 2 ? 8 : 6;
    }
    return cols >= 2 ? 6 : 4;
  }

  @Builder
  cardItemBody() {
    if (this.variant === 'resource') {
      CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 20, cornerRadius: 8 })
            HarmonySkeletonBlock({ blockWidth: 48, blockHeight: 20, cornerRadius: 8, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 20, cornerRadius: 8, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 42, blockHeight: 20, cornerRadius: 8, tone: 'subtle' })
          }
          .width('100%')
          HarmonySkeletonBlock({ blockWidth: '94%', blockHeight: 14, cornerRadius: 5 })
          HarmonySkeletonBlock({ blockWidth: '64%', blockHeight: 14, cornerRadius: 5 })
          HarmonySkeletonBlock({ blockWidth: '78%', blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
          Row({ space: 8 }) {
            HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 42, blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 64, blockHeight: 13, cornerRadius: 5 })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    } else if (this.variant === 'download') {
      CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
        Column({ space: 9 }) {
          Row({ space: 8 }) {
            HarmonySkeletonBlock({ blockWidth: 22, blockHeight: 22, cornerRadius: 6 })
            HarmonySkeletonBlock({ blockWidth: '64%', blockHeight: 15, cornerRadius: 5 })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
          }
          .width('100%')
          HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 6, cornerRadius: 3, tone: 'subtle' })
          Row() {
            HarmonySkeletonBlock({ blockWidth: 108, blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 88, blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
          }
          .width('100%')
          Row() {
            HarmonySkeletonBlock({ blockWidth: 60, blockHeight: 30, cornerRadius: 15, tone: 'subtle' })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 60, blockHeight: 30, cornerRadius: 15, tone: 'subtle' })
          }
          .width('100%')
        }
        .width('100%')
      }
    } else if (this.variant === 'file') {
      CinematicPanel({ panelPadding: 13, cornerRadius: 16 }) {
        Row({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 26, blockHeight: 26, cornerRadius: 7 })
          Column({ space: 4 }) {
            HarmonySkeletonBlock({ blockWidth: '68%', blockHeight: 14, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: '34%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 28, cornerRadius: 14, tone: 'subtle' })
        }
        .width('100%')
      }
    } else if (this.variant === 'site') {
      CinematicPanel({ panelPadding: 15, cornerRadius: 20 }) {
        Column({ space: 9 }) {
          Row({ space: 10 }) {
            HarmonySkeletonBlock({ blockWidth: 34, blockHeight: 34, cornerRadius: 9, shimmerSweep: true })
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                HarmonySkeletonBlock({ blockWidth: 88, blockHeight: 15, cornerRadius: 5 })
                HarmonySkeletonBlock({ blockWidth: 48, blockHeight: 18, cornerRadius: 9, tone: 'subtle' })
              }
              HarmonySkeletonBlock({ blockWidth: 118, blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 28, cornerRadius: 14, tone: 'subtle' })
          }
          .width('100%')
          Row({ space: 12 }) {
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 84, blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
          }
          .width('100%')
          HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 5, cornerRadius: 3, tone: 'subtle' })
        }
        .width('100%')
      }
    } else if (this.variant === 'workflow') {
      CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            HarmonySkeletonBlock({ blockWidth: '54%', blockHeight: 15, cornerRadius: 5 })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 48, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
          }
          .width('100%')
          HarmonySkeletonBlock({ blockWidth: '84%', blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
          HarmonySkeletonBlock({ blockWidth: '46%', blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
          Row({ space: 8 }) {
            HarmonySkeletonBlock({ blockWidth: 60, blockHeight: 28, cornerRadius: 14 })
            HarmonySkeletonBlock({ blockWidth: 60, blockHeight: 28, cornerRadius: 14, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 28, cornerRadius: 14, tone: 'subtle' })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 32, blockHeight: 32, cornerRadius: 16, tone: 'subtle' })
          }
          .width('100%')
        }
        .width('100%')
      }
    } else if (this.variant === 'plugin') {
      CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
        Row({ space: 12 }) {
          HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 44, cornerRadius: 12, shimmerSweep: true })
          Column({ space: 5 }) {
            Row({ space: 6 }) {
              HarmonySkeletonBlock({ blockWidth: '58%', blockHeight: 15, cornerRadius: 5 })
              HarmonySkeletonBlock({ blockWidth: 42, blockHeight: 18, cornerRadius: 9, tone: 'subtle' })
            }
            .width('100%')
            HarmonySkeletonBlock({ blockWidth: '88%', blockHeight: 12, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '44%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 26, cornerRadius: 13, tone: 'subtle' })
        }
        .width('100%')
      }
    } else if (this.variant === 'scheduler') {
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row({ space: 10 }) {
          Column({ space: 5 }) {
            HarmonySkeletonBlock({ blockWidth: '58%', blockHeight: 14.5, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: '76%', blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          HarmonySkeletonBlock({ blockWidth: 58, blockHeight: 32, cornerRadius: 16, tone: 'subtle' })
        }
        .width('100%')
      }
    } else {
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 34, blockHeight: 34, cornerRadius: 9 })
          Column({ space: 5 }) {
            HarmonySkeletonBlock({ blockWidth: '52%', blockHeight: 15, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: '76%', blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 22, cornerRadius: 11, tone: 'subtle' })
        }
        .width('100%')
      }
    }
  }

  @Builder
  gridBody() {
    HarmonySkeletonHost({ loadingLabel: '正在加载卡片列表' }) {
      Grid() {
        ForEach(skeletonIndices(this.resolvedCount()), (idx: number) => {
          GridItem() {
            this.cardItemBody()
          }
        }, (idx: number) => `cg_sk_${this.variant}_${idx}`)
      }
      .columnsTemplate(this.singleColumn ? '1fr' : HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
      .columnsGap(12)
      .rowsGap(10)
      .width('100%')
      .padding({ left: this.horizontalPadding, right: this.horizontalPadding, bottom: this.bottomPadding })
    }
  }

  build() {
    if (this.fillViewport) {
      Scroll() {
        this.gridBody()
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
    } else {
      this.gridBody()
    }
  }
}

/**
 * 工作流拓扑画布骨架（220vp 画布容器 + 3 枚节点占位卡，杜绝加载期间渲染硬编码假节点名称）。
 */
@Component
export struct HarmonyWorkflowCanvasSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在加载工作流节点拓扑' }) {
      CinematicPanel({ panelPadding: 14, cornerRadius: 20 }) {
        Column({ space: 8 }) {
          Row() {
            HarmonySkeletonBlock({ blockWidth: 142, blockHeight: 14, cornerRadius: 5 })
            Blank()
            HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
          }
          .width('100%')

          Stack({ alignContent: Alignment.TopStart }) {
            HarmonySkeletonBlock({
              blockWidth: 132,
              blockHeight: 48,
              cornerRadius: 12,
              shimmerSweep: true
            })
              .position({ x: 18, y: 28 })

            HarmonySkeletonBlock({
              blockWidth: 56,
              blockHeight: 3,
              cornerRadius: 1.5,
              tone: 'subtle'
            })
              .position({ x: 152, y: 52 })

            HarmonySkeletonBlock({
              blockWidth: 132,
              blockHeight: 48,
              cornerRadius: 12,
              shimmerSweep: true
            })
              .position({ x: 184, y: 84 })

            HarmonySkeletonBlock({
              blockWidth: 132,
              blockHeight: 48,
              cornerRadius: 12,
              tone: 'subtle'
            })
              .position({ x: 36, y: 142 })
          }
          .width('100%')
          .height(220)
          .clip(true)
          .borderRadius(14)
          .backgroundColor(this.isDark ? '#14FFFFFF' : '#0A000000')

          HarmonySkeletonBlock({ blockWidth: 196, blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
  }
}

/**
 * 「我的」Bento 仪表盘完整骨架：
 * 覆盖 4/2 列媒体库统计、存储空间圆环、下载器双速卡片、社区勋章矩阵、内存条、近期入库海报条、整理趋势柱图与定时任务卡。
 */
@Component
export struct HarmonyBentoDashboardSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在加载仪表盘统计数据' }) {
      Column({ space: 18 }) {
        // 1. 媒体库统计 4 宫格 / 2 宫格
        Column({ space: 12 }) {
          HarmonySkeletonBlock({ blockWidth: 96, blockHeight: 18, cornerRadius: 6 })
          Grid() {
            ForEach(skeletonIndices(4), (idx: number) => {
              GridItem() {
                CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
                  Column({ space: 8 }) {
                    Row() {
                      HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 26, cornerRadius: 7, shimmerSweep: true })
                      Blank()
                      HarmonySkeletonBlock({ blockWidth: 30, blockHeight: 30, cornerRadius: 10, tone: 'subtle' })
                    }
                    .width('100%')
                    HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                    HarmonySkeletonBlock({ blockWidth: 64, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
              }
            }, (idx: number) => `bento_stat_${idx}`)
          }
          .columnsTemplate(this.windowWidthVp >= 680 ? '1fr 1fr 1fr 1fr' : '1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 2. 存储空间环形卡
        Column({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 82, blockHeight: 18, cornerRadius: 6 })
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Row({ space: 18 }) {
              Stack({ alignContent: Alignment.Center }) {
                HarmonySkeletonBlock({ blockWidth: 86, blockHeight: 86, cornerRadius: 43, shimmerSweep: true })
                Column()
                  .width(66)
                  .height(66)
                  .borderRadius(33)
                  .backgroundColor(HarmonyThemeColors.skeletonSurface(this.isDark, this.paletteId, this.pureBlack))
                HarmonySkeletonBlock({ blockWidth: 34, blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
              }
              Column({ space: 7 }) {
                HarmonySkeletonBlock({ blockWidth: 142, blockHeight: 15, cornerRadius: 5 })
                HarmonySkeletonBlock({ blockWidth: 78, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                HarmonySkeletonBlock({ blockWidth: 98, blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 3. 下载器双速卡
        Column({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 64, blockHeight: 18, cornerRadius: 6 })
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Row({ space: 12 }) {
                Column({ space: 6 }) {
                  HarmonySkeletonBlock({ blockWidth: 84, blockHeight: 15, cornerRadius: 5 })
                  HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
                }
                .layoutWeight(1)
                .padding(12)
                .borderRadius(14)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .alignItems(HorizontalAlign.Start)

                Column({ space: 6 }) {
                  HarmonySkeletonBlock({ blockWidth: 84, blockHeight: 15, cornerRadius: 5 })
                  HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
                }
                .layoutWeight(1)
                .padding(12)
                .borderRadius(14)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              HarmonySkeletonBlock({ blockWidth: 186, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 4. 社区勋章矩阵卡
        CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
          Column({ space: 12 }) {
            Row() {
              HarmonySkeletonBlock({ blockWidth: 92, blockHeight: 16, cornerRadius: 5 })
              Blank()
              HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
            }
            .width('100%')
            Row({ space: 14 }) {
              ForEach(skeletonIndices(4), (idx: number) => {
                Column({ space: 6 }) {
                  HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 56, cornerRadius: 28, shimmerSweep: true })
                  HarmonySkeletonBlock({ blockWidth: 46, blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }, (idx: number) => `bento_medal_${idx}`)
            }
            .width('100%')
          }
          .width('100%')
        }

        // 5. 内存占用卡
        Column({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 82, blockHeight: 18, cornerRadius: 6 })
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Row() {
                HarmonySkeletonBlock({ blockWidth: 74, blockHeight: 14, cornerRadius: 5, tone: 'subtle' })
                Blank()
                HarmonySkeletonBlock({ blockWidth: 96, blockHeight: 14, cornerRadius: 5 })
              }
              .width('100%')
              HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 7, cornerRadius: 3.5, tone: 'subtle' })
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 6. 近期入库横滑条
        Column({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 82, blockHeight: 18, cornerRadius: 6 })
          Row({ space: 10 }) {
            ForEach(skeletonIndices(4), (idx: number) => {
              Column({ space: 5 }) {
                HarmonySkeletonBlock({ blockWidth: 96, blockHeight: 140, cornerRadius: 12, shimmerSweep: true })
                HarmonySkeletonBlock({ blockWidth: 76, blockHeight: 12, cornerRadius: 4 })
              }
              .alignItems(HorizontalAlign.Start)
            }, (idx: number) => `bento_rec_${idx}`)
          }
          .width('100%')
          .clip(true)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 7. 整理趋势柱图卡
        Column({ space: 10 }) {
          HarmonySkeletonBlock({ blockWidth: 82, blockHeight: 18, cornerRadius: 6 })
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Row({ space: 8 }) {
              ForEach(TREND_SKELETON_HEIGHTS, (barH: number, idx: number) => {
                Column({ space: 5 }) {
                  HarmonySkeletonBlock({ blockWidth: 20, blockHeight: barH, cornerRadius: 6 })
                  HarmonySkeletonBlock({ blockWidth: 18, blockHeight: 10, cornerRadius: 3, tone: 'subtle' })
                }
                .layoutWeight(1)
                .height(112)
                .justifyContent(FlexAlign.End)
                .alignItems(HorizontalAlign.Center)
              }, (_barH: number, idx: number) => `bento_tr_${idx}`)
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 8. 定时任务概览卡
        CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
          Row({ space: 12 }) {
            HarmonySkeletonBlock({ blockWidth: 40, blockHeight: 40, cornerRadius: 20 })
            Column({ space: 5 }) {
              HarmonySkeletonBlock({ blockWidth: 108, blockHeight: 15, cornerRadius: 5 })
              HarmonySkeletonBlock({ blockWidth: 176, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            HarmonySkeletonBlock({ blockWidth: 14, blockHeight: 14, cornerRadius: 4, tone: 'subtle' })
          }
          .width('100%')
        }
      }
      .width('100%')
    }
  }
}

/**
 * 订阅文件详情弹层骨架（3 枚统计块 + 单集下载/媒体库文件明细卡片）。
 */
@Component
export struct HarmonySubscribeFilesSheetSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop showStatTiles: boolean = false;
  @Prop episodeCount: number = 3;

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在查询订阅文件明细' }) {
      Column({ space: 12 }) {
        if (this.showStatTiles) {
          Row({ space: 8 }) {
            ForEach(skeletonIndices(3), (idx: number) => {
              Column({ space: 6 }) {
                HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 16, cornerRadius: 5 })
                HarmonySkeletonBlock({ blockWidth: 38, blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
              }
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10, left: 8, right: 8 })
              .borderRadius(14)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              .alignItems(HorizontalAlign.Center)
            }, (idx: number) => `sf_stat_${idx}`)
          }
          .width('100%')
        }

        ForEach(skeletonIndices(this.episodeCount), (idx: number) => {
          CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Row({ space: 8 }) {
                HarmonySkeletonBlock({ blockWidth: 42, blockHeight: 20, cornerRadius: 10 })
                HarmonySkeletonBlock({ blockWidth: '48%', blockHeight: 14.5, cornerRadius: 5 })
                Blank()
                HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
              }
              .width('100%')

              Column({ space: 8 }) {
                Row({ space: 6 }) {
                  HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 18, cornerRadius: 8 })
                  HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 18, cornerRadius: 8, tone: 'subtle' })
                  HarmonySkeletonBlock({ blockWidth: 72, blockHeight: 16, cornerRadius: 5, tone: 'subtle' })
                }
                HarmonySkeletonBlock({ blockWidth: '92%', blockHeight: 13, cornerRadius: 4 })
                Row({ space: 8 }) {
                  HarmonySkeletonBlock({ blockWidth: '68%', blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
                  Blank()
                  HarmonySkeletonBlock({ blockWidth: 68, blockHeight: 22, cornerRadius: 11, tone: 'subtle' })
                }
                .width('100%')
              }
              .width('100%')
              .padding(11)
              .borderRadius(12)
              .backgroundColor(this.isDark ? '#18FFFFFF' : '#0A000000')
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
          }
        }, (idx: number) => `sf_ep_${idx}`)
      }
      .width('100%')
    }
  }
}

/**
 * 智能助手会话对话流骨架（交替用户气泡与助手回复面板，消除进入/切换会话时欢迎页闪烁）。
 */
@Component
export struct HarmonyAgentChatSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在同步会话消息记录' }) {
      Column({ space: 14 }) {
        // 用户气泡 1
        Row() {
          Blank()
          HarmonySkeletonBlock({
            blockWidth: '58%',
            blockHeight: 42,
            cornerRadius: 20,
            shimmerSweep: true
          })
        }
        .width('100%')

        // 助手面板 1
        CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              HarmonySkeletonBlock({ blockWidth: 16, blockHeight: 16, cornerRadius: 5 })
              HarmonySkeletonBlock({ blockWidth: 148, blockHeight: 13, cornerRadius: 5 })
              Blank()
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

            HarmonySkeletonBlock({ blockWidth: '96%', blockHeight: 14, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: '86%', blockHeight: 14, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '62%', blockHeight: 14, cornerRadius: 5, tone: 'subtle' })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        // 用户气泡 2
        Row() {
          Blank()
          HarmonySkeletonBlock({
            blockWidth: '44%',
            blockHeight: 40,
            cornerRadius: 20
          })
        }
        .width('100%')

        // 助手面板 2
        CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
          Column({ space: 9 }) {
            HarmonySkeletonBlock({ blockWidth: '92%', blockHeight: 14, cornerRadius: 5 })
            HarmonySkeletonBlock({ blockWidth: '78%', blockHeight: 14, cornerRadius: 5, tone: 'subtle' })
            HarmonySkeletonBlock({ blockWidth: '48%', blockHeight: 14, cornerRadius: 5, tone: 'subtle' })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 16 })
    }
  }
}

/**
 * 插件详情页与受控隔离 ArkWeb 宿主结构化骨架（匹配 KPI 统计格与配置表单面板）。
 */
@Component
export struct HarmonyPluginSheetSkeleton {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;

  build() {
    HarmonySkeletonHost({ loadingLabel: '正在加载插件配置与数据视图' }) {
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          ForEach(skeletonIndices(2), (idx: number) => {
            Column() {
              CinematicPanel({ panelPadding: 13, cornerRadius: 16 }) {
                Column({ space: 6 }) {
                  HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                  HarmonySkeletonBlock({ blockWidth: 74, blockHeight: 18, cornerRadius: 5, shimmerSweep: true })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
            .layoutWeight(1)
          }, (idx: number) => `pl_kpi_${idx}`)
        }
        .width('100%')

        ForEach(skeletonIndices(3), (idx: number) => {
          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 9 }) {
              Row() {
                HarmonySkeletonBlock({ blockWidth: '42%', blockHeight: 14.5, cornerRadius: 5 })
                Blank()
                HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 24, cornerRadius: 12, tone: 'subtle' })
              }
              .width('100%')
              HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 38, cornerRadius: 12, tone: 'subtle' })
              HarmonySkeletonBlock({ blockWidth: '66%', blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }, (idx: number) => `pl_fld_${idx}`)
      }
      .width('100%')
      .constraintSize({ maxWidth: 820 })
      .padding({ left: 16, right: 16, top: 8, bottom: 28 })
    }
  }
}
