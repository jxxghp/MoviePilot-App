import { GeneratedDesignTokens } from '../tokens/GeneratedTokens';
import { HarmonyAppearanceStore } from '../store/AppearanceStore';
import {
  HarmonyMotionTokens,
  HarmonySurfaceModifier,
  HarmonySurfaceRole,
  HarmonyThemeColors
} from './HarmonyDynamicLight';

/**
 * 鸿蒙原生 4 大主导航目标：
 * 发现 · 订阅 · 我的 · 更多（手机底部采用 4+1 分离式圆角悬浮动态光感胶囊栏，折叠屏/平板自动切换为左侧竖向侧栏）。
 */
export type HarmonyMainTab = 'discover' | 'subscribe' | 'dashboard' | 'more';

/** 「更多」中心业务入口定义（按三大清晰业务域归类，站点管理归属设置页，追剧日历与订阅广场归属订阅页）。 */
export interface MoreToolItem {
  id: string;
  title: string;
  subtitle: string;
  symbolName: string;
  tintHex: string;
  group: number; // 0: 资源与媒体流转, 1: 插件与工作流, 2: 快捷工具与系统诊断
}

export const MORE_TOOL_ITEMS: MoreToolItem[] = [
  // 0. 资源与媒体流转
  { id: 'resources', title: '站点资源', subtitle: '多站搜索与精细筛选', symbolName: 'sys.symbol.magnifyingglass', tintHex: '#317AF7', group: 0 },
  { id: 'downloads', title: '下载管理', subtitle: '实时速率与任务控制', symbolName: 'sys.symbol.arrow_down_circle', tintHex: '#34C759', group: 0 },
  { id: 'files', title: '文件管理', subtitle: '多存储浏览与整理播放', symbolName: 'sys.symbol.folder', tintHex: '#F29B38', group: 0 },
  { id: 'history', title: '整理历史', subtitle: '入库记录与手动重整理', symbolName: 'sys.symbol.clock', tintHex: '#64A2FF', group: 0 },
  { id: 'media_library', title: '媒体库', subtitle: 'Emby / Jellyfin / Plex', symbolName: 'sys.symbol.film', tintHex: '#5AC8FA', group: 0 },
  // 1. 插件与工作流
  { id: 'plugins', title: '插件中心', subtitle: '已安装与市场扩展', symbolName: 'sys.symbol.puzzle', tintHex: '#26B8A8', group: 1 },
  { id: 'workflows', title: '工作流', subtitle: '自动化流程与节点画布', symbolName: 'sys.symbol.share', tintHex: '#8E7BFF', group: 1 },
  // 2. 快捷工具与系统诊断
  { id: 'diag_check', title: '系统检查', subtitle: '核心状态自检', symbolName: 'sys.symbol.checkmark_shield', tintHex: '#34C759', group: 2 },
  { id: 'diag_schedulers', title: '定时服务', subtitle: '查看与手动触发', symbolName: 'sys.symbol.clock', tintHex: '#EE6896', group: 2 },
  { id: 'diag_logs', title: '实时日志', subtitle: '服务端日志追踪', symbolName: 'sys.symbol.doc_text', tintHex: '#5AC8FA', group: 2 },
  { id: 'diag_words', title: '词表管理', subtitle: '识别与过滤规则', symbolName: 'sys.symbol.bookmark', tintHex: '#26B8A8', group: 2 },
  { id: 'diag_recognize', title: '名称识别', subtitle: '种子标题在线测试', symbolName: 'sys.symbol.magnifyingglass', tintHex: '#64A2FF', group: 2 },
  { id: 'diag_network', title: '网络测试', subtitle: '连通与延迟检测', symbolName: 'sys.symbol.worldclock', tintHex: '#F29B38', group: 2 }
];

export function mpPrimaryText(isDark: boolean): string {
  return HarmonyThemeColors.primaryText(isDark);
}

export function mpSecondaryText(isDark: boolean): string {
  return HarmonyThemeColors.secondaryText(isDark);
}

export function mpMutedText(isDark: boolean): string {
  return HarmonyThemeColors.mutedText(isDark);
}

/**
 * 鸿蒙原生画布背景（`CinematicAmbientGradient`）：
 * 采用鸿蒙专属色系的分层深/浅画布，开启「顶部光感微光」时呈现克制柔和的鸿蒙顶部氛围光。
 */
@Component
export struct CinematicAmbientGradient {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) animateBg: boolean = true;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyThemeColors.canvas(this.isDark, this.paletteId, this.pureBlack))
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )

      if (this.animateBg && !(this.isDark && this.pureBlack)) {
        Column()
          .width('100%')
          .height(340)
          .linearGradient({
            angle: 180,
            colors: this.isDark
              ? HarmonyAppearanceStore.paletteById(this.paletteId).glowStopsDark
              : HarmonyAppearanceStore.paletteById(this.paletteId).glowStopsLight
          })
          .opacity(this.isDark ? 0.55 : 0.72)
          .position({ top: 0, left: 0 })
          .expandSafeArea(
            [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.END]
          )
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
    )
    .hitTestBehavior(HitTestMode.None)
  }
}

/**
 * 鸿蒙原生分层卡片容器（`CinematicPanel`）：
 * 通过 `HarmonySurfaceModifier` 自动分级适配 HarmonyOS 7 动态光感、HarmonyOS 6 点光源与低版本分层表面。
 */
@Component
export struct CinematicPanel {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop panelPadding: number = GeneratedDesignTokens.PANEL_PADDING_VP;
  @Prop cornerRadius: number = 18;
  @Prop surfaceRole: HarmonySurfaceRole = 'card';
  @Prop interactive: boolean = false;
  @BuilderParam content: () => void = this.defaultBuilder;

  @Builder
  defaultBuilder() {}

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.panelPadding)
    .borderRadius(this.cornerRadius)
    .attributeModifier(new HarmonySurfaceModifier(
      this.isDark,
      this.surfaceRole,
      this.cornerRadius,
      this.accentHex,
      this.interactive,
      this.dynamicLight
    ))
    .hoverEffect(this.interactive ? HoverEffect.Highlight : HoverEffect.None)
  }
}

/**
 * 鸿蒙原生顶部状态栏渐进模糊与柔光遮罩：
 * 随 `visibilityProgress`（如 `scrollOffsetY / 150`）平滑插值，向下自然衰减至完全透明，无生硬底边遮挡海报。
 */
@Component
export struct NativeTopStatusBarBlur {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop visibilityProgress: number = 1.0;
  @Prop veilHeight: number = 92;

  private clampedProgress(): number {
    return Math.max(0, Math.min(1, this.visibilityProgress));
  }

  private baseCanvasHex(): string {
    return HarmonyThemeColors.canvas(this.isDark, this.paletteId, this.pureBlack);
  }

  private effectiveVeilHeight(): number {
    const compact = this.windowHeightVp > 0 && this.windowHeightVp < 480;
    const dynamicHeight = Math.max(10, this.safeTopVp) + (compact ? 44 : 54);
    return Math.max(48, Math.min(this.veilHeight, dynamicHeight));
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column()
        .width('100%')
        .height(this.effectiveVeilHeight())
        .linearGradientBlur(26 * this.clampedProgress(), {
          fractionStops: [[1, 0], [0.68, 0.48], [0.22, 0.80], [0, 1]],
          direction: GradientDirection.Bottom
        })
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.END]
        )

      Column()
        .width('100%')
        .height(this.effectiveVeilHeight())
        .linearGradient({
          angle: 180,
          colors: [
            [HarmonyAppearanceStore.withAlpha(this.baseCanvasHex(), 'DC'), 0.0],
            [HarmonyAppearanceStore.withAlpha(this.baseCanvasHex(), '9E'), 0.36],
            [HarmonyAppearanceStore.withAlpha(this.baseCanvasHex(), '42'), 0.72],
            ['#00000000', 1.0]
          ]
        })
        .opacity(this.clampedProgress())
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.END]
        )
    }
    .width('100%')
    .height(this.effectiveVeilHeight())
    .hitTestBehavior(HitTestMode.None)
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.START, SafeAreaEdge.END]
    )
  }
}

/**
 * 鸿蒙二级页面标题栏（类似 iOS 顶部左右侧悬浮圆钮布局：左侧圆形返回键 + 标题 + 右侧 1~2 个圆形操作键或主胶囊动作）。
 */
@Component
export struct NativeBackHeader {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop trailingText: string = '';
  @Prop trailingPrimary: boolean = false;
  @Prop trailingSymbol: string = '';
  @Prop trailingAccessibility: string = '操作';
  @Prop secondarySymbol: string = '';
  @Prop secondaryAccessibility: string = '更多操作';
  onBack: () => void = () => {};
  onTrailingClick: () => void = () => {};
  onSecondaryClick: () => void = () => {};

  private isCompact(): boolean {
    return this.windowHeightVp > 0 && this.windowHeightVp < 480;
  }

  build() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(this.isCompact() ? 18 : 20)
          .fontColor([mpPrimaryText(this.isDark)])
      }
      .width(this.isCompact() ? 36 : 40)
      .height(this.isCompact() ? 36 : 40)
      .backgroundColor(Color.Transparent)
      .attributeModifier(new HarmonySurfaceModifier(
        this.isDark,
        'pill',
        this.isCompact() ? 18 : 20,
        this.accentHex,
        true,
        this.dynamicLight
      ))
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText('返回上一级')
      .onClick(() => this.onBack())

      Column({ space: 1 }) {
        Text(this.title)
          .fontSize(this.isCompact() ? 18 : 20)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor(mpSecondaryText(this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.secondarySymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.secondarySymbol))
            .fontSize(this.isCompact() ? 17 : 19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(this.isCompact() ? 36 : 40)
        .height(this.isCompact() ? 36 : 40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(
          this.isDark,
          'pill',
          this.isCompact() ? 18 : 20,
          this.accentHex,
          true,
          this.dynamicLight
        ))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.secondaryAccessibility)
        .onClick(() => this.onSecondaryClick())
      }

      if (this.trailingSymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.trailingSymbol))
            .fontSize(this.isCompact() ? 17 : 19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(this.isCompact() ? 36 : 40)
        .height(this.isCompact() ? 36 : 40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(
          this.isDark,
          'pill',
          this.isCompact() ? 18 : 20,
          this.accentHex,
          true,
          this.dynamicLight
        ))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.trailingAccessibility)
        .onClick(() => this.onTrailingClick())
      } else if (this.trailingText.length > 0) {
        Button(this.trailingText)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.trailingPrimary ? Color.White : mpPrimaryText(this.isDark))
          .height(this.isCompact() ? 34 : 38)
          .padding({ left: 16, right: 16 })
          .borderRadius(this.isCompact() ? 17 : 19)
          .backgroundColor(this.trailingPrimary ? this.accentHex : Color.Transparent)
          .attributeModifier(this.trailingPrimary
            ? undefined
            : new HarmonySurfaceModifier(
              this.isDark,
              'pill',
              this.isCompact() ? 17 : 19,
              this.accentHex,
              true,
              this.dynamicLight
            ))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onTrailingClick())
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: Math.max(10, this.safeTopVp + 4),
      bottom: this.isCompact() ? 4 : 8
    })
  }
}

/**
 * 鸿蒙一级主页面标题栏（类似 iOS 顶部大标题 + 右侧悬浮光感图标组，最多支持 3 个操作圆钮）。
 */
@Component
export struct HarmonyPageHeader {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop centerTitle: boolean = false;
  @Prop leadingPrimarySymbol: string = '';
  @Prop leadingPrimaryAccessibility: string = '左侧操作';
  @Prop leadingSecondarySymbol: string = '';
  @Prop leadingSecondaryAccessibility: string = '左侧快捷操作';
  @Prop primarySymbol: string = '';
  @Prop primaryAccessibility: string = '操作';
  @Prop secondarySymbol: string = '';
  @Prop secondaryAccessibility: string = '快捷操作';
  @Prop tertiarySymbol: string = '';
  @Prop tertiaryAccessibility: string = '通知';
  onLeadingPrimaryClick: () => void = () => {};
  onLeadingSecondaryClick: () => void = () => {};
  onPrimaryClick: () => void = () => {};
  onSecondaryClick: () => void = () => {};
  onTertiaryClick: () => void = () => {};

  private isCompact(): boolean {
    return this.windowHeightVp > 0 && this.windowHeightVp < 480;
  }

  @Builder
  private circleActionBtn(symbolName: string, a11yText: string, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r(symbolName))
        .fontSize(this.isCompact() ? 17 : 19)
        .fontColor([mpPrimaryText(this.isDark)])
    }
    .width(this.isCompact() ? 36 : 40)
    .height(this.isCompact() ? 36 : 40)
    .backgroundColor(Color.Transparent)
    .attributeModifier(new HarmonySurfaceModifier(
      this.isDark,
      'pill',
      this.isCompact() ? 18 : 20,
      this.accentHex,
      true,
      this.dynamicLight
    ))
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(a11yText)
    .onClick(() => onTap())
  }

  build() {
    if (this.centerTitle) {
      Stack({ alignContent: Alignment.Center }) {
        Row({ space: 8 }) {
          if (this.leadingPrimarySymbol.length > 0) {
            this.circleActionBtn(this.leadingPrimarySymbol, this.leadingPrimaryAccessibility, () => this.onLeadingPrimaryClick())
          }
          if (this.leadingSecondarySymbol.length > 0) {
            this.circleActionBtn(this.leadingSecondarySymbol, this.leadingSecondaryAccessibility, () => this.onLeadingSecondaryClick())
          }
          Blank().layoutWeight(1)
          if (this.tertiarySymbol.length > 0) {
            this.circleActionBtn(this.tertiarySymbol, this.tertiaryAccessibility, () => this.onTertiaryClick())
          }
          if (this.secondarySymbol.length > 0) {
            this.circleActionBtn(this.secondarySymbol, this.secondaryAccessibility, () => this.onSecondaryClick())
          }
          if (this.primarySymbol.length > 0) {
            this.circleActionBtn(this.primarySymbol, this.primaryAccessibility, () => this.onPrimaryClick())
          }
        }
        .width('100%')

        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(this.isCompact() ? 18 : 20)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle.length > 0 && !this.isCompact()) {
            Text(this.subtitle)
              .fontSize(11.5)
              .fontColor(mpSecondaryText(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .padding({ left: 96, right: 96 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: Math.max(10, this.safeTopVp + 4),
        bottom: this.isCompact() ? 4 : 8
      })
    } else {
      Row({ space: 8 }) {
        if (this.leadingPrimarySymbol.length > 0) {
          this.circleActionBtn(this.leadingPrimarySymbol, this.leadingPrimaryAccessibility, () => this.onLeadingPrimaryClick())
        }
        if (this.leadingSecondarySymbol.length > 0) {
          this.circleActionBtn(this.leadingSecondarySymbol, this.leadingSecondaryAccessibility, () => this.onLeadingSecondaryClick())
        }

        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(this.isCompact() ? 22 : 28)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .maxLines(1)
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor(mpSecondaryText(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.tertiarySymbol.length > 0) {
          this.circleActionBtn(this.tertiarySymbol, this.tertiaryAccessibility, () => this.onTertiaryClick())
        }

        if (this.secondarySymbol.length > 0) {
          this.circleActionBtn(this.secondarySymbol, this.secondaryAccessibility, () => this.onSecondaryClick())
        }

        if (this.primarySymbol.length > 0) {
          this.circleActionBtn(this.primarySymbol, this.primaryAccessibility, () => this.onPrimaryClick())
        }
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: Math.max(10, this.safeTopVp + 4),
        bottom: this.isCompact() ? 4 : 8
      })
    }
  }
}

/**
 * 统一大胶囊分页栏（用于媒体库、探索、全局搜索、订阅、插件中心/详情与词表等所有平级分页，视觉高度一致）：
 * - 选中项呈现品牌主色大胶囊 + 底部精致短指示条；
 * - 支持平分等宽与横向滚动（并在选中索引变化时自动滚入视野）。
 */
@Component
export struct HarmonyPillTabBar {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop tabs: string[] = [];
  @Prop @Watch('onSelectedChanged') selectedIndex: number = 0;
  @Prop scrollable: boolean = false;
  onSelect: (index: number) => void = () => {};
  private tabScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (this.scrollable && this.selectedIndex > 0) {
      setTimeout(() => { this.onSelectedChanged(); }, 60);
    }
  }

  onSelectedChanged(): void {
    if (this.scrollable && this.selectedIndex >= 0) {
      try {
        const approxOffset = Math.max(0, this.selectedIndex * 106 - 48);
        this.tabScroller.scrollTo({ xOffset: approxOffset, yOffset: 0, animation: { duration: 220, curve: Curve.EaseOut } });
      } catch {
        // ignore if scroller not attached
      }
    }
  }

  @Builder
  pillButton(label: string, idx: number, equalWidth: boolean) {
    Column({ space: 5 }) {
      Row() {
        Text(label)
          .fontSize(equalWidth && this.tabs.length >= 3 ? 13.5 : 14)
          .fontWeight(this.selectedIndex === idx ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedIndex === idx ? Color.White : mpSecondaryText(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width(equalWidth ? '100%' : undefined)
      .height(42)
      .padding({ left: equalWidth ? 8 : 18, right: equalWidth ? 8 : 18 })
      .justifyContent(FlexAlign.Center)
      .borderRadius(21)
      .backgroundColor(this.selectedIndex === idx ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
      .border({
        width: this.selectedIndex === idx ? 0 : 0.6,
        color: HarmonyThemeColors.borderSubtle(this.isDark),
        radius: 21
      })
      .animation({ duration: HarmonyMotionTokens.DURATION_SHORT, curve: HarmonyMotionTokens.CURVE_STANDARD })
      .hoverEffect(HoverEffect.Highlight)
      .focusable(true)
      .accessibilityText(`${label}${this.selectedIndex === idx ? '，已选中' : ''}`)
      .onClick(() => this.onSelect(idx))

      Column()
        .width(this.selectedIndex === idx ? 22 : 0)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(this.accentHex)
        .animation({ duration: HarmonyMotionTokens.DURATION_LOCAL, curve: HarmonyMotionTokens.CURVE_STANDARD })
    }
    .layoutWeight(equalWidth ? 1 : 0)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    if (this.scrollable) {
      Scroll(this.tabScroller) {
        Row({ space: 10 }) {
          ForEach(this.tabs, (label: string, idx: number) => {
            this.pillButton(label, idx, false)
          }, (label: string, idx: number) => `${idx}_${label}`)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    } else {
      Row({ space: 10 }) {
        ForEach(this.tabs, (label: string, idx: number) => {
          this.pillButton(label, idx, true)
        }, (label: string, idx: number) => `${idx}_${label}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
  }
}

/** 兼容导出：页级切换统一复用 `HarmonyPillTabBar` 大胶囊样式。 */
@Component
export struct HarmonyUnderlineTabBar {
  @Prop tabs: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop scrollable: boolean = false;
  onSelect: (index: number) => void = () => {};

  build() {
    HarmonyPillTabBar({
      tabs: this.tabs,
      selectedIndex: this.selectedIndex,
      scrollable: this.scrollable,
      onSelect: (idx: number) => this.onSelect(idx)
    })
  }
}

/**
 * 鸿蒙规范互斥模式分段控制器（对标 ArkUI `SegmentButton`）。
 */
@Component
export struct HarmonySegmentedSwitch {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop options: string[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  build() {
    Row({ space: 2 }) {
      ForEach(this.options, (label: string, idx: number) => {
        Row() {
          Text(label)
            .fontSize(13)
            .fontWeight(this.selectedIndex === idx ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.selectedIndex === idx ? Color.White : mpSecondaryText(this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(38)
        .justifyContent(FlexAlign.Center)
        .borderRadius(19)
        .backgroundColor(this.selectedIndex === idx ? this.accentHex : Color.Transparent)
        .animation({ duration: HarmonyMotionTokens.DURATION_SHORT, curve: HarmonyMotionTokens.CURVE_STANDARD })
        .hoverEffect(HoverEffect.Highlight)
        .focusable(true)
        .accessibilityText(`${label}${this.selectedIndex === idx ? '，已选中' : ''}`)
        .onClick(() => this.onSelect(idx))
      })
    }
    .width('100%')
    .padding(3)
    .borderRadius(22)
    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
    .border({ width: 0.6, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: 22 })
  }
}

/**
 * 类似 iOS 的底部弹层统一顶栏（左侧取消、居中标题、右侧品牌色确认/恢复胶囊）。
 */
@Component
export struct HarmonySheetHeader {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop title: string = '';
  @Prop cancelText: string = '取消';
  @Prop actionText: string = '';
  @Prop actionEnabled: boolean = true;
  onCancel: () => void = () => {};
  onAction: () => void = () => {};

  build() {
    Row() {
      if (this.cancelText.length > 0) {
        Text(this.cancelText)
          .fontSize(14)
          .fontColor(mpSecondaryText(this.isDark))
          .padding({ top: 6, bottom: 6, right: 12 })
          .onClick(() => this.onCancel())
      }
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(mpPrimaryText(this.isDark))
        .textAlign(this.cancelText.length > 0 ? TextAlign.Center : TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.actionText.length > 0) {
        Button(this.actionText)
          .height(34)
          .padding({ left: 14, right: 14 })
          .borderRadius(17)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(this.actionEnabled ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
          .enabled(this.actionEnabled)
          .onClick(() => this.onAction())
      } else if (this.cancelText.length > 0) {
        Blank().width(44)
      }
    }
    .width('100%')
    .padding({ bottom: 4 })
  }
}

/**
 * 鸿蒙底部 4+1 分离式圆角悬浮动态光感导航栏：
 * - 左侧圆角悬浮胶囊承载「发现 · 订阅 · 我的 · 更多」4 大主导航；
 * - 右侧独立悬浮圆形动态光感「搜索」按钮，与主胶囊共享一致材质与高度。
 */
@Component
export struct HarmonyBottomNavBar {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop selectedTab: HarmonyMainTab = 'discover';
  @Prop userInitial: string = 'A';
  @Prop userAvatar: string = '';
  onTabClick: (tab: HarmonyMainTab) => void = () => {};
  onSearchClick: () => void = () => {};

  private tabLabel(tab: HarmonyMainTab): string {
    if (tab === 'discover') { return '发现'; }
    if (tab === 'subscribe') { return '订阅'; }
    if (tab === 'dashboard') { return '我的'; }
    return '更多';
  }

  private tabSymbol(tab: HarmonyMainTab, active: boolean): string {
    if (tab === 'discover') { return active ? 'sys.symbol.TV_tv_fill' : 'sys.symbol.TV_tv'; }
    if (tab === 'subscribe') { return active ? 'sys.symbol.bookmark_fill' : 'sys.symbol.bookmark'; }
    return 'sys.symbol.dot_grid_2x2';
  }

  private isCompact(): boolean {
    return this.windowHeightVp > 0 && this.windowHeightVp < 480;
  }

  private barHeightVp(): number {
    return this.isCompact() ? 54 : 60;
  }

  build() {
    Row() {
      Row({ space: this.isCompact() ? 10 : 12 }) {
        Row({ space: 2 }) {
          ForEach(['discover', 'subscribe', 'dashboard', 'more'] as HarmonyMainTab[], (tab: HarmonyMainTab) => {
            Column({ space: 2 }) {
              if (tab === 'dashboard') {
                if (this.userAvatar.length > 0) {
                  Image(this.userAvatar)
                    .width(22)
                    .height(22)
                    .borderRadius(11)
                    .objectFit(ImageFit.Cover)
                    .border({
                      width: this.selectedTab === tab ? 1.8 : 0.8,
                      color: this.selectedTab === tab ? this.accentHex : HarmonyThemeColors.borderSubtle(this.isDark),
                      radius: 11
                    })
                } else {
                  Text(this.userInitial)
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .width(22)
                    .height(22)
                    .textAlign(TextAlign.Center)
                    .borderRadius(11)
                    .backgroundColor(this.accentHex)
                }
              } else {
                SymbolGlyph($r(this.tabSymbol(tab, this.selectedTab === tab)))
                  .fontSize(20)
                  .fontColor([this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark)])
              }
              Text(this.tabLabel(tab))
                .fontSize(10.5)
                .fontWeight(this.selectedTab === tab ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark))
            }
            .layoutWeight(1)
            .height(this.isCompact() ? 44 : 50)
            .justifyContent(FlexAlign.Center)
            .borderRadius(this.isCompact() ? 22 : 25)
            .backgroundColor(this.selectedTab === tab
              ? HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '34' : '1E')
              : Color.Transparent)
            .border(this.selectedTab === tab
              ? {
                width: 0.6,
                color: HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '50' : '2E'),
                radius: this.isCompact() ? 22 : 25
              }
              : { width: 0, color: Color.Transparent, radius: this.isCompact() ? 22 : 25 })
            .animation({ duration: HarmonyMotionTokens.DURATION_SHORT, curve: HarmonyMotionTokens.CURVE_STANDARD })
            .hoverEffect(HoverEffect.Highlight)
            .focusable(true)
            .accessibilityText(`${this.tabLabel(tab)}${this.selectedTab === tab ? '，已选中' : ''}`)
            .onClick(() => this.onTabClick(tab))
          }, (tab: HarmonyMainTab) => tab)
        }
        .layoutWeight(1)
        .height(this.barHeightVp())
        .padding({ left: 5, right: 5 })
        .borderRadius(this.barHeightVp() / 2)
        .clip(true)
        .attributeModifier(new HarmonySurfaceModifier(
          this.isDark,
          'bar',
          this.barHeightVp() / 2,
          this.accentHex,
          true,
          this.dynamicLight
        ))

        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(this.isCompact() ? 19 : 22)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(this.barHeightVp())
        .height(this.barHeightVp())
        .borderRadius(this.barHeightVp() / 2)
        .clip(true)
        .attributeModifier(new HarmonySurfaceModifier(
          this.isDark,
          'bar',
          this.barHeightVp() / 2,
          this.accentHex,
          true,
          this.dynamicLight
        ))
        .hoverEffect(HoverEffect.Highlight)
        .focusable(true)
        .accessibilityText('搜索')
        .onClick(() => this.onSearchClick())
      }
      .width('100%')
      .constraintSize({ maxWidth: 460 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16, bottom: Math.max(10, this.safeBottomVp + 2) })
  }
}

/**
 * 鸿蒙宽屏/折叠屏展开/平板侧边竖向导航栏（顶部独立搜索圆钮 + 发现 · 订阅 · 我的 · 更多）。
 */
@Component
export struct HarmonySideNavRail {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) safeLeftVp: number = 0;
  @Prop selectedTab: HarmonyMainTab = 'discover';
  @Prop userInitial: string = 'A';
  @Prop userAvatar: string = '';
  onTabClick: (tab: HarmonyMainTab) => void = () => {};
  onSearchClick: () => void = () => {};

  private tabLabel(tab: HarmonyMainTab): string {
    if (tab === 'discover') { return '发现'; }
    if (tab === 'subscribe') { return '订阅'; }
    if (tab === 'dashboard') { return '我的'; }
    return '更多';
  }

  private tabSymbol(tab: HarmonyMainTab, active: boolean): string {
    if (tab === 'discover') { return active ? 'sys.symbol.TV_tv_fill' : 'sys.symbol.TV_tv'; }
    if (tab === 'subscribe') { return active ? 'sys.symbol.bookmark_fill' : 'sys.symbol.bookmark'; }
    return 'sys.symbol.dot_grid_2x2';
  }

  private isCompact(): boolean {
    return this.windowHeightVp > 0 && this.windowHeightVp < 480;
  }

  build() {
    Column({ space: this.isCompact() ? 4 : 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(this.isCompact() ? 18 : 20)
          .fontColor([Color.White])
      }
      .width(this.isCompact() ? 38 : 44)
      .height(this.isCompact() ? 38 : 44)
      .backgroundColor(this.accentHex)
      .margin({
        top: this.isCompact() ? Math.max(10, this.safeTopVp) : Math.max(20, this.safeTopVp + 10),
        bottom: this.isCompact() ? 4 : 12
      })
      .accessibilityText('搜索')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.onSearchClick())

      Scroll() {
        Column({ space: this.isCompact() ? 4 : 10 }) {
          ForEach(['discover', 'subscribe', 'dashboard', 'more'] as HarmonyMainTab[], (tab: HarmonyMainTab) => {
            Column({ space: this.isCompact() ? 2 : 4 }) {
              if (tab === 'dashboard') {
                if (this.userAvatar.length > 0) {
                  Image(this.userAvatar)
                    .width(this.isCompact() ? 20 : 24)
                    .height(this.isCompact() ? 20 : 24)
                    .borderRadius(this.isCompact() ? 10 : 12)
                    .objectFit(ImageFit.Cover)
                    .border({
                      width: this.selectedTab === tab ? 1.8 : 0.8,
                      color: this.selectedTab === tab ? this.accentHex : HarmonyThemeColors.borderSubtle(this.isDark),
                      radius: this.isCompact() ? 10 : 12
                    })
                } else {
                  Text(this.userInitial)
                    .fontSize(this.isCompact() ? 10 : 11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .width(this.isCompact() ? 20 : 24)
                    .height(this.isCompact() ? 20 : 24)
                    .textAlign(TextAlign.Center)
                    .borderRadius(this.isCompact() ? 10 : 12)
                    .backgroundColor(this.accentHex)
                }
              } else {
                SymbolGlyph($r(this.tabSymbol(tab, this.selectedTab === tab)))
                  .fontSize(this.isCompact() ? 19 : 22)
                  .fontColor([this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark)])
              }
              Text(this.tabLabel(tab))
                .fontSize(this.isCompact() ? 10 : 11)
                .fontWeight(this.selectedTab === tab ? FontWeight.Bold : FontWeight.Regular)
                .fontColor(this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark))
            }
            .width(this.isCompact() ? 60 : 64)
            .height(this.isCompact() ? 44 : 56)
            .justifyContent(FlexAlign.Center)
            .borderRadius(this.isCompact() ? 14 : 18)
            .backgroundColor(this.selectedTab === tab
              ? HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '30' : '1E')
              : Color.Transparent)
            .hoverEffect(HoverEffect.Highlight)
            .focusable(true)
            .accessibilityText(`${this.tabLabel(tab)}${this.selectedTab === tab ? '，已选中' : ''}`)
            .onClick(() => this.onTabClick(tab))
          }, (tab: HarmonyMainTab) => tab)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
      .width('100%')
    }
    .width(84 + this.safeLeftVp)
    .height('100%')
    .padding({ left: this.safeLeftVp, bottom: Math.max(8, this.safeBottomVp) })
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START]
    )
    .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'bar', 0, this.accentHex, false, this.dynamicLight))
  }
}

/**
 * 紧凑可拖拽 MoviePilot 紫色机器人悬浮吉祥物（44×52vp，与 iOS/Android 视觉同源）：
 * - Canvas 原生绘制：微倾天线、#A385FA->#7A57E0 紫韵渐变头身、#262140 深色面罩、#F0EBFF 弯月睡眼、胸口纯白播放三角；
 * - 支持全屏安全边界内自由拖拽（`PanGesture`），当迷你音乐条可见时自动向上避让 `+68vp`，绝不遮挡底栏或播控条。
 */
@Component
export struct FloatingAiMascotButton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) @Watch('onViewportChanged') windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) @Watch('onViewportChanged') windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) @Watch('onViewportChanged') safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) @Watch('onViewportChanged') safeLeftVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP) @Watch('onViewportChanged') safeRightVp: number = 0;
  @Prop miniMusicVisible: boolean = false;
  @Prop baseRight: number = 14;
  @Prop baseBottom: number = 94;
  @State private dragDx: number = 0;
  @State private dragDy: number = 0;
  private dragStartDx: number = 0;
  private dragStartDy: number = 0;
  private mascotSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private mascotCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mascotSettings);
  onTap: () => void = () => {};

  onViewportChanged(): void {
    this.dragDx = this.clampDx(this.dragDx);
    this.dragDy = this.clampDy(this.dragDy);
  }

  private roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    const rad = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rad, y);
    ctx.arcTo(x + w, y, x + w, y + h, rad);
    ctx.arcTo(x + w, y + h, x, y + h, rad);
    ctx.arcTo(x, y + h, x, y, rad);
    ctx.arcTo(x, y, x + w, y, rad);
    ctx.closePath();
  }

  private drawMascot(): void {
    const ctx = this.mascotCtx;
    ctx.clearRect(0, 0, 44, 52);

    // 底部柔和紫晕投影
    const glow = ctx.createRadialGradient(22, 46, 2, 22, 46, 15);
    glow.addColorStop(0, '#507A57E0');
    glow.addColorStop(1, '#007A57E0');
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(22, 46, 15, 0, Math.PI * 2);
    ctx.fill();

    // 微倾天线（右上倾斜）
    ctx.save();
    ctx.strokeStyle = '#9D7FF5';
    ctx.lineWidth = 2.4;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(23, 11.5);
    ctx.lineTo(27.5, 4.5);
    ctx.stroke();

    ctx.fillStyle = '#EAE2FF';
    ctx.beginPath();
    ctx.arc(28, 4, 2.7, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#8361E8';
    ctx.lineWidth = 1.0;
    ctx.stroke();
    ctx.restore();

    // 左右小耳廓
    ctx.fillStyle = '#8361E8';
    this.roundRectPath(ctx, 3.2, 16.5, 4.2, 8.5, 2.1);
    ctx.fill();
    this.roundRectPath(ctx, 36.6, 16.5, 4.2, 8.5, 2.1);
    ctx.fill();

    // 圆润头部（#A385FA -> #7A57E0）
    const headGrad = ctx.createLinearGradient(22, 10, 22, 31);
    headGrad.addColorStop(0, '#A385FA');
    headGrad.addColorStop(1, '#7A57E0');
    ctx.fillStyle = headGrad;
    this.roundRectPath(ctx, 6, 10, 32, 20.5, 9.5);
    ctx.fill();
    ctx.strokeStyle = '#52FFFFFF';
    ctx.lineWidth = 0.9;
    ctx.stroke();

    // 深色护目镜面罩（#262140）
    ctx.fillStyle = '#262140';
    this.roundRectPath(ctx, 9.5, 13.5, 25, 13, 6);
    ctx.fill();

    // 慵懒可爱弯月眼（#F0EBFF）
    ctx.save();
    ctx.strokeStyle = '#F0EBFF';
    ctx.lineWidth = 2.0;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(13.2, 20.4);
    ctx.quadraticCurveTo(16.2, 17.4, 19.2, 20.4);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(24.8, 20.4);
    ctx.quadraticCurveTo(27.8, 17.4, 30.8, 20.4);
    ctx.stroke();
    ctx.restore();

    // 左右小圆润手臂
    ctx.fillStyle = '#8664E8';
    this.roundRectPath(ctx, 6.2, 34.2, 4.2, 9.2, 2.1);
    ctx.fill();
    this.roundRectPath(ctx, 33.6, 34.2, 4.2, 9.2, 2.1);
    ctx.fill();

    // 紧凑躯干（#A385FA -> #7A57E0）
    const bodyGrad = ctx.createLinearGradient(22, 31.5, 22, 48.5);
    bodyGrad.addColorStop(0, '#A385FA');
    bodyGrad.addColorStop(1, '#7A57E0');
    ctx.fillStyle = bodyGrad;
    this.roundRectPath(ctx, 9.5, 31.8, 25, 16.5, 7.8);
    ctx.fill();
    ctx.strokeStyle = '#48FFFFFF';
    ctx.lineWidth = 0.8;
    ctx.stroke();

    // 躯干中央纯白播放三角（MoviePilot 标志）
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    ctx.moveTo(19.4, 36.4);
    ctx.lineTo(26.4, 40.2);
    ctx.lineTo(19.4, 44.0);
    ctx.closePath();
    ctx.fill();
  }

  private effectiveBottomVp(): number {
    return this.baseBottom + (this.miniMusicVisible ? 68 : 0);
  }

  private clampDx(rawDx: number): number {
    const railWidth = (this.breakpoint === 'md' || this.breakpoint === 'lg')
      ? (84 + this.safeLeftVp)
      : this.safeLeftVp;
    const availW = Math.max(200, this.windowWidthVp - railWidth - this.safeRightVp);
    const minDx = Math.min(0, -(availW - 44 - this.baseRight - 10));
    const maxDx = Math.max(0, this.baseRight - 8);
    return Math.max(minDx, Math.min(maxDx, rawDx));
  }

  private clampDy(rawDy: number): number {
    const availH = Math.max(220, this.windowHeightVp);
    const topReserve = Math.max(12, this.safeTopVp + 10);
    const minDy = Math.min(0, -(availH - 52 - this.effectiveBottomVp() - topReserve));
    return Math.max(minDy, Math.min(0, rawDy));
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.mascotCtx)
        .width(44)
        .height(52)
        .onReady(() => this.drawMascot())
    }
    .width(44)
    .height(52)
    .position({
      right: this.baseRight,
      bottom: this.effectiveBottomVp()
    })
    .translate({
      x: this.clampDx(this.dragDx),
      y: this.clampDy(this.dragDy)
    })
    .animation({ duration: HarmonyMotionTokens.DURATION_LOCAL, curve: HarmonyMotionTokens.CURVE_STANDARD })
    .hoverEffect(HoverEffect.Scale)
    .accessibilityText('打开 MoviePilot 智能助手（支持按住自由拖拽）')
    .onClick(() => this.onTap())
    .gesture(
      PanGesture({ distance: 4 })
        .onActionStart(() => {
          this.dragStartDx = this.clampDx(this.dragDx);
          this.dragStartDy = this.clampDy(this.dragDy);
        })
        .onActionUpdate((ev: GestureEvent) => {
          this.dragDx = this.clampDx(this.dragStartDx + ev.offsetX);
          this.dragDy = this.clampDy(this.dragStartDy + ev.offsetY);
        })
    )
  }
}

/** 通用自适应状态角标（底色随标签色调自动派生）。 */
@Component
export struct NativeAdaptiveBadge {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop text: string = '';
  @Prop tintHex: string = '';
  @Prop filled: boolean = false;

  private resolvedTint(): string {
    return this.tintHex.length > 0 ? this.tintHex : this.accentHex;
  }

  build() {
    Text(this.text)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.filled ? Color.White : this.resolvedTint())
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(this.filled
        ? this.resolvedTint()
        : HarmonyAppearanceStore.withAlpha(this.resolvedTint(), this.isDark ? '26' : '16'))
  }
}

/**
 * 鸿蒙多维筛选芯片（支持按压即时反馈、键鼠悬停与无障碍选中语义）。
 */
@Component
export struct NativeAdaptivePill {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop title: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Text(this.title)
      .fontSize(13)
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected ? Color.White : mpPrimaryText(this.isDark))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(16)
      .backgroundColor(this.selected ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
      .animation({ duration: HarmonyMotionTokens.DURATION_INSTANT, curve: HarmonyMotionTokens.CURVE_STANDARD })
      .hoverEffect(HoverEffect.Highlight)
      .focusable(true)
      .accessibilityText(`${this.title}${this.selected ? '，已选中' : ''}`)
      .onClick(() => this.onTap())
  }
}
