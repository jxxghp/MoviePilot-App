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
  // 0. 资源与媒体流转（冷静蓝青色系收束）
  { id: 'resources', title: '站点资源', subtitle: '多站搜索与精细筛选', symbolName: 'sys.symbol.magnifyingglass', tintHex: '#317AF7', group: 0 },
  { id: 'downloads', title: '下载管理', subtitle: '实时速率与任务控制', symbolName: 'sys.symbol.arrow_down_circle', tintHex: '#38B2AC', group: 0 },
  { id: 'files', title: '文件管理', subtitle: '多存储浏览与整理播放', symbolName: 'sys.symbol.folder', tintHex: '#5AC8FA', group: 0 },
  { id: 'history', title: '整理历史', subtitle: '入库记录与手动重整理', symbolName: 'sys.symbol.clock', tintHex: '#64A2FF', group: 0 },
  { id: 'media_library', title: '媒体库', subtitle: 'Emby / Jellyfin / Plex', symbolName: 'sys.symbol.film', tintHex: '#47A3FA', group: 0 },
  // 1. 插件与工作流（品牌紫青收束）
  { id: 'plugins', title: '插件中心', subtitle: '已安装与市场扩展', symbolName: 'sys.symbol.puzzle', tintHex: '#8E7BFF', group: 1 },
  { id: 'workflows', title: '工作流', subtitle: '自动化流程与节点画布', symbolName: 'sys.symbol.share', tintHex: '#7A68F0', group: 1 },
  // 2. 快捷工具与系统诊断（清爽克制系统诊断色系）
  { id: 'diag_check', title: '系统检查', subtitle: '核心状态自检', symbolName: 'sys.symbol.checkmark_shield', tintHex: '#34C759', group: 2 },
  { id: 'diag_schedulers', title: '定时服务', subtitle: '查看与手动触发', symbolName: 'sys.symbol.clock', tintHex: '#64A2FF', group: 2 },
  { id: 'diag_logs', title: '实时日志', subtitle: '服务端日志追踪', symbolName: 'sys.symbol.doc_text', tintHex: '#5AC8FA', group: 2 },
  { id: 'diag_words', title: '词表管理', subtitle: '识别与过滤规则', symbolName: 'sys.symbol.bookmark', tintHex: '#8E7BFF', group: 2 },
  { id: 'diag_recognize', title: '名称识别', subtitle: '种子标题在线测试', symbolName: 'sys.symbol.magnifyingglass', tintHex: '#64A2FF', group: 2 },
  { id: 'diag_network', title: '网络测试', subtitle: '连通与延迟检测', symbolName: 'sys.symbol.worldclock', tintHex: '#38B2AC', group: 2 }
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

function mixHexColor(baseHex: string, targetR: number, targetG: number, targetB: number, ratio: number): string {
  const clean = baseHex.replace('#', '');
  const full = clean.length === 8 ? clean.substring(2) : clean;
  const r = parseInt(full.substring(0, 2), 16) || 122;
  const g = parseInt(full.substring(2, 4), 16) || 87;
  const b = parseInt(full.substring(4, 6), 16) || 224;
  const t = Math.max(0, Math.min(1, ratio));
  const mr = Math.round(r * (1 - t) + targetR * t);
  const mg = Math.round(g * (1 - t) + targetG * t);
  const mb = Math.round(b * (1 - t) + targetB * t);
  const hex = (n: number): string => n.toString(16).padStart(2, '0');
  return `#${hex(mr)}${hex(mg)}${hex(mb)}`;
}

/**
 * Web `CssRobotRenderer.vue` 同款鸿蒙原生悬浮机器人（56×68vp）：
 * - 按主题强调色派生高光/主体/暗部与清晰 2vp 实线描边（绝不做半透明灰雾退化）；
 * - 靠近屏幕边缘闲置 4.2s 自动「贴边探头」：保持 100% 不透明，头歪 ±19° 露出一半，内侧手臂 78° 扒在最前层；
 * - 支持 5.8s 上半身轻呼吸、7.6s 双眨眼、全部 16 个 Web 动作与拖拽摇晃彩蛋（晃 3 次晕眩、6 次散架重组、久拖困惑、轻挪点头）。
 */
@Component
export struct FloatingAiMascotButton {
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) @Watch('onViewportChanged') windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) @Watch('onViewportChanged') windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) @Watch('onViewportChanged') safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) @Watch('onViewportChanged') safeLeftVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP) @Watch('onViewportChanged') safeRightVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#7A57E0';
  @Prop miniMusicVisible: boolean = false;
  @Prop baseRight: number = 14;
  @Prop baseBottom: number = 94;
  @Prop thinking: boolean = false;
  @Prop motionActive: boolean = true;
  @State private dragDx: number = 0;
  @State private dragDy: number = 0;
  @State private isIdleDocked: boolean = false;
  @State private isDragging: boolean = false;
  private idleTimerId: number = -1;
  private animIntervalId: number = -1;
  private randomActionTimerId: number = -1;
  private activeAction: string = '';
  private actionStartMs: number = 0;
  private actionDurationMs: number = 0;
  private lastRandomAction: string = '';
  private dragStartDx: number = 0;
  private dragStartDy: number = 0;
  private dragStartMs: number = 0;
  private shakePivotX: number = 0;
  private shakeDir: number = 0;
  private shakeTurns: number = 0;
  private lastShakeTurnMs: number = 0;
  private canvasReady: boolean = false;
  private mascotSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private mascotCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mascotSettings);
  onTap: () => void = () => {};

  aboutToAppear(): void {
    this.scheduleIdleDock();
    this.startAnimLoop();
    this.scheduleNextRandomAction();
  }

  aboutToDisappear(): void {
    this.clearIdleTimer();
    this.stopAnimLoop();
    if (this.randomActionTimerId !== -1) {
      clearTimeout(this.randomActionTimerId);
      this.randomActionTimerId = -1;
    }
  }

  private clearIdleTimer(): void {
    if (this.idleTimerId !== -1) {
      clearTimeout(this.idleTimerId);
      this.idleTimerId = -1;
    }
  }

  private startAnimLoop(): void {
    this.stopAnimLoop();
    this.animIntervalId = setInterval(() => {
      if (this.canvasReady && this.motionActive) {
        this.drawMascot();
      }
    }, 40);
  }

  private stopAnimLoop(): void {
    if (this.animIntervalId !== -1) {
      clearInterval(this.animIntervalId);
      this.animIntervalId = -1;
    }
  }

  private actionDuration(act: string): number {
    if (act === 'nod') { return 1500; }
    if (act === 'wake') { return 1800; }
    if (act === 'wave' || act === 'peek') { return 2800; }
    if (act === 'sit') { return 4200; }
    if (act === 'eye-roll') { return 1900; }
    if (act === 'faint' || act === 'charge') { return 4800; }
    if (act === 'disassemble') { return 6200; }
    if (act === 'happy-jump') { return 2600; }
    if (act === 'sleep') { return 6800; }
    if (act === 'stretch') { return 5200; }
    if (act === 'scan') { return 3200; }
    if (act === 'spin-cheer') { return 3600; }
    if (act === 'shy') { return 3000; }
    if (act === 'confused') { return 3400; }
    return 2400;
  }

  private playAction(act: string): void {
    this.activeAction = act;
    this.actionStartMs = Date.now();
    this.actionDurationMs = this.actionDuration(act);
    if (this.canvasReady) {
      this.drawMascot();
    }
  }

  private scheduleNextRandomAction(): void {
    if (this.randomActionTimerId !== -1) {
      clearTimeout(this.randomActionTimerId);
    }
    const waitMs = 12000 + Math.floor(Math.random() * 12000);
    this.randomActionTimerId = setTimeout(() => {
      this.randomActionTimerId = -1;
      if (this.motionActive && !this.isDragging && !this.effectiveDocked() && !this.thinking && this.activeAction.length === 0) {
        const pool = ['sleep', 'sleep', 'sleep', 'stretch', 'stretch', 'sit', 'sit', 'wave', 'peek', 'shy', 'confused'];
        const filtered = pool.filter((item: string) => item !== this.lastRandomAction);
        const picked = filtered[Math.floor(Math.random() * filtered.length)] || 'sleep';
        this.lastRandomAction = picked;
        this.playAction(picked);
      }
      this.scheduleNextRandomAction();
    }, waitMs);
  }

  private scheduleIdleDock(): void {
    this.clearIdleTimer();
    this.isIdleDocked = false;
    this.idleTimerId = setTimeout(() => {
      if (!this.isDragging && !this.thinking) {
        this.isIdleDocked = true;
      }
    }, 4200);
  }

  private dockBounds(): [number, number] {
    const railWidth = (this.breakpoint === 'md' || this.breakpoint === 'lg')
      ? (84 + this.safeLeftVp)
      : this.safeLeftVp;
    const availW = Math.max(200, this.windowWidthVp - railWidth - this.safeRightVp);
    const minDx = Math.min(0, -(availW - 56 - this.baseRight - 8));
    const maxDx = Math.max(0, this.baseRight - 6);
    return [minDx, maxDx];
  }

  private dockOnLeft(): boolean {
    const bounds = this.dockBounds();
    const clamped = this.clampDx(this.dragDx);
    return Math.abs(clamped - bounds[0]) < Math.abs(bounds[1] - clamped);
  }

  private nearScreenEdge(): boolean {
    const bounds = this.dockBounds();
    const clamped = this.clampDx(this.dragDx);
    return Math.abs(clamped - bounds[0]) <= 88 || Math.abs(bounds[1] - clamped) <= 88;
  }

  private effectiveDocked(): boolean {
    return this.isIdleDocked && !this.isDragging && !this.thinking && this.nearScreenEdge();
  }

  /** 右侧贴边时将半身收至屏幕外，仍保留可见的探头与手臂。 */
  private effectiveTranslateX(): number {
    const clamped = this.clampDx(this.dragDx);
    if (!this.effectiveDocked()) {
      return clamped;
    }
    const bounds = this.dockBounds();
    return this.dockOnLeft() ? (bounds[0] - 20) : (this.baseRight + 28);
  }

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

  private drawArm(
    ctx: CanvasRenderingContext2D,
    ax: number,
    ay: number,
    aw: number,
    ah: number,
    deg: number,
    shellMid: string,
    outlineSoft: string,
    outline: string,
    strokeW: number
  ): void {
    ctx.save();
    ctx.translate(ax, ay);
    ctx.rotate((deg * Math.PI) / 180);
    const grad = ctx.createLinearGradient(0, -ah * 0.5, 0, ah * 0.5);
    grad.addColorStop(0, shellMid);
    grad.addColorStop(1, outlineSoft);
    ctx.fillStyle = grad;
    this.roundRectPath(ctx, -aw * 0.5, -ah * 0.5, aw, ah, aw * 0.5);
    ctx.fill();
    ctx.strokeStyle = outline;
    ctx.lineWidth = strokeW;
    ctx.stroke();
    ctx.restore();
  }

  private drawRobotEye(
    ctx: CanvasRenderingContext2D,
    ecx: number,
    ecy: number,
    ew: number,
    eh: number,
    happy: boolean,
    color: string
  ): void {
    const rx = ew * 0.5;
    const outerRy = Math.max(eh, 1.0);
    const innerRy = outerRy * 0.52;
    const dir = happy ? -1 : 1;
    const baseY = happy ? (ecy + outerRy * 0.45) : (ecy - outerRy * 0.35);
    const steps = 14;
    ctx.beginPath();
    for (let i = 0; i <= steps; i++) {
      const theta = (i / steps) * Math.PI;
      const x = ecx - rx * Math.cos(theta);
      const y = baseY + dir * outerRy * Math.sin(theta);
      if (i === 0) { ctx.moveTo(x, y); } else { ctx.lineTo(x, y); }
    }
    for (let i = steps; i >= 0; i--) {
      const theta = (i / steps) * Math.PI;
      const x = ecx - rx * Math.cos(theta);
      const y = baseY + dir * innerRy * Math.sin(theta);
      ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  private drawMascot(): void {
    const ctx = this.mascotCtx;
    const w = 56;
    const h = 68;
    const sx = w / 58;
    const sy = h / 70;
    const cx = w * 0.5;
    const cy = h * 0.5;
    ctx.clearRect(0, 0, w, h);

    const nowMs = Date.now();
    if (this.activeAction.length > 0 && nowMs - this.actionStartMs >= this.actionDurationMs) {
      this.activeAction = '';
    }
    const docked = this.effectiveDocked();
    const dockLeft = this.dockOnLeft();
    const act = docked ? '' : this.activeAction;
    const p = act.length > 0 ? Math.max(0, Math.min(1, (nowMs - this.actionStartMs) / Math.max(100, this.actionDurationMs))) : 0;
    const timeSec = (nowMs % 3600000) / 1000;

    const breath = (this.motionActive && act.length === 0 && !docked && !this.isDragging)
      ? Math.max(0, Math.sin((timeSec / 5.8) * Math.PI * 2))
      : 0;
    const blinkPhase = (timeSec % 7.6) / 7.6;
    const blinkClosed = this.motionActive && ((blinkPhase > 0.33 && blinkPhase < 0.365) || (blinkPhase > 0.77 && blinkPhase < 0.805));

    const outline = mixHexColor(this.accentHex, 9, 5, 16, 0.68);
    const outlineSoft = mixHexColor(this.accentHex, 9, 5, 16, 0.46);
    const shellStart = mixHexColor(this.accentHex, 255, 255, 255, 0.54);
    const shellMid = mixHexColor(this.accentHex, 255, 255, 255, 0.16);
    const shellEnd = mixHexColor(this.accentHex, 9, 5, 16, 0.18);
    const eyeGlow = '#72FFF0';
    const eyeColor = '#F5F2FF';

    let rootOx = 0;
    let rootOy = 0;
    let rootRot = 0;
    let headOx = 0;
    let headOy = -1.3 * breath * sy;
    let headRot = -3;
    let bodyOy = 0;
    let bodyScaleX = 1 + 0.02 * breath;
    let bodyScaleY = 1 + 0.036 * breath;
    let leftArmDeg = 17;
    let rightArmDeg = -17;
    let leftArmOx = 0;
    let leftArmOy = 0;
    let rightArmOx = 0;
    let rightArmOy = 0;
    let leftLegOx = 0;
    let leftLegOy = 0;
    let rightLegOx = 0;
    let rightLegOy = 0;
    let eyeOx = 0;
    let eyeOy = 0;
    let eyeScaleY = blinkClosed ? 0.14 : 1.0;
    let antennaDeg = 22;
    let showBlush = false;
    let showScan = this.thinking;
    let happyEyes = false;

    if (act === 'nod') {
      headOy += Math.sin(p * Math.PI * 4) * 2.2 * sy;
      headRot += Math.sin(p * Math.PI * 4) * 6;
    } else if (act === 'wake') {
      const hop = Math.sin(Math.min(p * 2.2, 1) * Math.PI);
      rootOy -= hop * 6 * sy;
      antennaDeg -= hop * 18;
    } else if (act === 'wave') {
      const env = Math.sin(Math.min(p * 3, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 3, 1) * Math.PI * 0.5);
      rightArmDeg = -17 - env * (128 + Math.sin(p * Math.PI * 10) * 20);
      headRot += env * 7;
      eyeOx += env * 1.4 * sx;
    } else if (act === 'sit') {
      const env = Math.sin(Math.min(p * 3.5, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 3.5, 1) * Math.PI * 0.5);
      bodyOy += env * 4.5 * sy;
      headOy += env * 5.2 * sy;
      leftLegOx = -2.2 * sx * env;
      leftLegOy = -2.5 * sy * env;
      rightLegOx = 2.2 * sx * env;
      rightLegOy = -2.5 * sy * env;
    } else if (act === 'eye-roll') {
      eyeOx = Math.cos(p * Math.PI * 2) * 2.4 * sx;
      eyeOy = -Math.abs(Math.sin(p * Math.PI * 2)) * 2.6 * sy;
    } else if (act === 'faint') {
      const env = Math.sin(Math.min(p * 4, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 4, 1) * Math.PI * 0.5);
      rootRot = env * (24 + Math.sin(p * Math.PI * 6) * 5);
      rootOy += env * 4 * sy;
      eyeScaleY = 0.24;
    } else if (act === 'disassemble') {
      const burst = Math.sin(Math.max(0, Math.min(1, (p - 0.08) / 0.72)) * Math.PI);
      headOy -= burst * 9.5 * sy;
      headRot += burst * 18;
      leftArmOx = -7.5 * sx * burst;
      leftArmOy = -3 * sy * burst;
      rightArmOx = 7.5 * sx * burst;
      rightArmOy = -3 * sy * burst;
      leftArmDeg += burst * 42;
      rightArmDeg -= burst * 42;
      leftLegOx = -4 * sx * burst;
      leftLegOy = 4 * sy * burst;
      rightLegOx = 4 * sx * burst;
      rightLegOy = 4 * sy * burst;
      bodyOy += burst * 2.5 * sy;
    } else if (act === 'happy-jump') {
      const bounce = Math.abs(Math.sin(p * Math.PI * 3));
      rootOy -= bounce * 11 * sy;
      leftArmDeg = 17 + bounce * 118;
      rightArmDeg = -17 - bounce * 118;
      happyEyes = true;
    } else if (act === 'sleep') {
      const env = Math.sin(Math.min(p * 4, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 4, 1) * Math.PI * 0.5);
      headOy += env * 2.6 * sy + Math.sin(p * Math.PI * 6) * 0.8 * sy;
      headRot -= env * 9;
      eyeScaleY = Math.max(0.14, 1 - env * 0.86);
    } else if (act === 'stretch') {
      const env = Math.sin(Math.min(p * 3, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 3, 1) * Math.PI * 0.5);
      bodyScaleY = 1 + env * 0.14;
      bodyScaleX = 1 - env * 0.06;
      headOy -= env * 3.6 * sy;
      leftArmDeg = 17 + env * 130;
      rightArmDeg = -17 - env * 130;
    } else if (act === 'peek') {
      const look = Math.sin(p * Math.PI * 2);
      headOx += look * 4.2 * sx;
      headRot += look * 9;
      eyeOx += look * 2.6 * sx;
    } else if (act === 'scan') {
      showScan = true;
      eyeOx = Math.sin(p * Math.PI * 4) * 2.2 * sx;
    } else if (act === 'charge') {
      const env = Math.min(1, p * 1.4);
      rootOx += Math.sin(p * Math.PI * 28) * 1.3 * sx * env;
      bodyScaleX = 1 + env * 0.06;
      bodyScaleY = 1 - env * 0.05;
      leftArmDeg = 17 + env * 36;
      rightArmDeg = -17 - env * 36;
    } else if (act === 'spin-cheer') {
      rootRot = p < 0.65 ? (p / 0.65) * 360 : 0;
      const lift = Math.sin(p * Math.PI);
      rootOy -= lift * 9 * sy;
      leftArmDeg = 17 + lift * 132;
      rightArmDeg = -17 - lift * 132;
      happyEyes = true;
    } else if (act === 'shy') {
      const env = Math.sin(Math.min(p * 3.5, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 3.5, 1) * Math.PI * 0.5);
      showBlush = env > 0.2;
      headRot += Math.sin(p * Math.PI * 2) * 7 * env;
      leftArmDeg = 17 - env * 28;
      rightArmDeg = -17 + env * 28;
    } else if (act === 'confused') {
      const env = Math.sin(Math.min(p * 3.5, 1) * Math.PI * 0.5) * Math.sin(Math.min((1 - p) * 3.5, 1) * Math.PI * 0.5);
      headRot += env * 18;
      eyeOx += env * 1.2 * sx;
    }

    if (docked) {
      rootRot = dockLeft ? 19 : -19;
      rootOy = -2 * sy;
      antennaDeg = dockLeft ? -12 : 12;
      eyeOx = (dockLeft ? 2.2 : -2.2) * sx;
    }

    const strokeW = Math.max(1.6, 1.9 * sx);
    const bodyVisible = !docked;

    // 柔和接地阴影
    if (bodyVisible) {
      const shadow = ctx.createRadialGradient(cx + rootOx, cy + 28 * sy, 2, cx + rootOx, cy + 28 * sy, 18 * sx);
      shadow.addColorStop(0, '#44090510');
      shadow.addColorStop(1, '#00090510');
      ctx.fillStyle = shadow;
      ctx.beginPath();
      ctx.ellipse(cx + rootOx, cy + 28 * sy, 17 * sx, 4.2 * sy, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.save();
    ctx.translate(cx + rootOx, cy + rootOy);
    ctx.rotate((rootRot * Math.PI) / 180);
    ctx.translate(-cx, -cy);

    if (bodyVisible) {
      // 1. 双腿
      const sides = [-1, 1];
      for (let i = 0; i < sides.length; i++) {
        const side = sides[i];
        const legW = 8.4 * sx;
        const legH = 9 * sy;
        const lx = cx + side * 7.6 * sx - legW * 0.5 + (side < 0 ? leftLegOx : rightLegOx);
        const ly = cy + 25 * sy - legH * 0.5 + (side < 0 ? leftLegOy : rightLegOy);
        const lg = ctx.createLinearGradient(0, ly, 0, ly + legH);
        lg.addColorStop(0, shellMid);
        lg.addColorStop(1, outlineSoft);
        ctx.fillStyle = lg;
        this.roundRectPath(ctx, lx, ly, legW, legH, 4 * sx);
        ctx.fill();
        ctx.strokeStyle = outline;
        ctx.lineWidth = strokeW;
        ctx.stroke();
      }

      // 2. 双手臂
      this.drawArm(ctx, cx - 15.8 * sx + leftArmOx, cy + 13.5 * sy + leftArmOy, 7.4 * sx, 13.4 * sy, leftArmDeg, shellMid, outlineSoft, outline, strokeW);
      this.drawArm(ctx, cx + 15.8 * sx + rightArmOx, cy + 13.5 * sy + rightArmOy, 7.4 * sx, 13.4 * sy, rightArmDeg, shellMid, outlineSoft, outline, strokeW);

      // 3. 躯干 + 胸口播放三角
      const bodyW = 26.8 * sx * bodyScaleX;
      const bodyH = 19.8 * sy * bodyScaleY;
      const bx = cx - bodyW * 0.5;
      const by = cy + 13.8 * sy + bodyOy - bodyH * 0.5;
      const bg = ctx.createLinearGradient(bx, by, bx + bodyW, by + bodyH);
      bg.addColorStop(0, shellMid);
      bg.addColorStop(1, shellEnd);
      ctx.fillStyle = bg;
      this.roundRectPath(ctx, bx, by, bodyW, bodyH, 9.2 * sx);
      ctx.fill();
      ctx.fillStyle = '#3DFFFFFF';
      this.roundRectPath(ctx, bx + 2.5 * sx, by + 1.4 * sy, bodyW - 5 * sx, 3.8 * sy, 3 * sx);
      ctx.fill();
      ctx.fillStyle = '#3D090510';
      this.roundRectPath(ctx, bx + 1.5 * sx, by + bodyH - 3.6 * sy, bodyW - 3 * sx, 2.8 * sy, 3 * sx);
      ctx.fill();
      ctx.strokeStyle = outline;
      ctx.lineWidth = strokeW;
      this.roundRectPath(ctx, bx, by, bodyW, bodyH, 9.2 * sx);
      ctx.stroke();

      const playCx = cx + 0.9 * sx;
      const playCy = cy + 13.8 * sy + bodyOy;
      ctx.fillStyle = this.thinking ? eyeGlow : '#FFFFFF';
      ctx.beginPath();
      ctx.moveTo(playCx - 3.4 * sx, playCy - 4.4 * sy);
      ctx.lineTo(playCx + 4.4 * sx, playCy);
      ctx.lineTo(playCx - 3.4 * sx, playCy + 4.4 * sy);
      ctx.closePath();
      ctx.fill();
    }

    // 4. 头部 + 天线 + 深色玻璃面罩 + 弯月眼睛
    const headX = cx + headOx;
    const headY = cy - 7.5 * sy + headOy;
    ctx.save();
    ctx.translate(headX, headY);
    ctx.rotate((headRot * Math.PI) / 180);
    ctx.translate(-headX, -headY);

    // 倾斜天线
    const antX = headX + 2.2 * sx;
    const antY = headY - 14.5 * sy;
    ctx.save();
    ctx.translate(antX, antY);
    ctx.rotate((antennaDeg * Math.PI) / 180);
    ctx.strokeStyle = outline;
    ctx.lineWidth = 2.6 * sx;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(0, -8.5 * sy);
    ctx.stroke();
    ctx.fillStyle = shellStart;
    ctx.beginPath();
    ctx.arc(0, -10.5 * sy, 3.4 * sx, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = outline;
    ctx.lineWidth = strokeW * 0.92;
    ctx.stroke();
    ctx.restore();

    // 头壳 45×31
    const headW = 45 * sx;
    const headH = 31 * sy;
    const hx = headX - headW * 0.5;
    const hy = headY - headH * 0.5;
    const hg = ctx.createLinearGradient(hx, hy, hx + headW, hy + headH);
    hg.addColorStop(0, shellStart);
    hg.addColorStop(0.5, shellMid);
    hg.addColorStop(1, shellEnd);
    ctx.fillStyle = hg;
    this.roundRectPath(ctx, hx, hy, headW, headH, 10.8 * sx);
    ctx.fill();
    ctx.fillStyle = '#47FFFFFF';
    this.roundRectPath(ctx, hx + 3 * sx, hy + 1.5 * sy, headW - 6 * sx, 4.5 * sy, 3.5 * sx);
    ctx.fill();
    ctx.fillStyle = '#3D090510';
    this.roundRectPath(ctx, hx + 2 * sx, hy + headH - 3.8 * sy, headW - 4 * sx, 3 * sy, 3 * sx);
    ctx.fill();
    ctx.strokeStyle = outline;
    ctx.lineWidth = strokeW;
    this.roundRectPath(ctx, hx, hy, headW, headH, 10.8 * sx);
    ctx.stroke();

    // 深色护目镜面罩
    const faceW = 34 * sx;
    const faceH = 19.8 * sy;
    const fx = headX - 1.5 * sx - faceW * 0.5;
    const fy = headY + 0.6 * sy - faceH * 0.5;
    const fg = ctx.createLinearGradient(0, fy, 0, fy + faceH);
    fg.addColorStop(0, '#221B3A');
    fg.addColorStop(1, '#0C0F1E');
    ctx.fillStyle = fg;
    this.roundRectPath(ctx, fx, fy, faceW, faceH, 7.2 * sx);
    ctx.fill();
    ctx.strokeStyle = (this.thinking || showScan) ? eyeGlow : outlineSoft;
    ctx.lineWidth = 1.6 * sx;
    ctx.stroke();

    if (showScan) {
      const sweep = (Math.sin(timeSec * 4.2) + 1) * 0.5;
      const bxScan = fx + 3 * sx + sweep * (faceW - 6 * sx);
      ctx.fillStyle = '#4D72FFF0';
      ctx.fillRect(bxScan - 2 * sx, fy + 1.5 * sy, 4 * sx, faceH - 3 * sy);
    }

    if (showBlush) {
      ctx.fillStyle = '#8CFF73A8';
      ctx.beginPath();
      ctx.ellipse(fx + 5.7 * sx, fy + faceH * 0.68, 2.8 * sx, 1.5 * sy, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.ellipse(fx + faceW - 5.7 * sx, fy + faceH * 0.68, 2.8 * sx, 1.5 * sy, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    const eyeBaseX = fx + faceW * 0.5 + eyeOx;
    const eyeBaseY = fy + faceH * 0.5 - 1.2 * sy + eyeOy;
    const activeEyeColor = (this.thinking || showScan) ? eyeGlow : eyeColor;
    this.drawRobotEye(ctx, eyeBaseX - 7.3 * sx, eyeBaseY, 7.6 * sx, 5.2 * sy * eyeScaleY, happyEyes, activeEyeColor);
    this.drawRobotEye(ctx, eyeBaseX + 7.3 * sx, eyeBaseY + 0.5 * sy, 7.6 * sx, 5.2 * sy * eyeScaleY, happyEyes, activeEyeColor);
    ctx.restore();

    // 5. 贴边探头专属：内侧小手移至最前层 ±78° 扒住屏幕边缘
    if (docked) {
      this.drawArm(
        ctx,
        dockLeft ? (cx + 4.5 * sx) : (cx - 4.5 * sx),
        cy + 12.5 * sy,
        6.4 * sx,
        13.8 * sy,
        dockLeft ? -78 : 78,
        shellMid,
        outlineSoft,
        outline,
        strokeW
      );
    }

    ctx.restore();
  }

  private effectiveBottomVp(): number {
    return this.baseBottom + (this.miniMusicVisible ? 68 : 0);
  }

  private clampDx(rawDx: number): number {
    const bounds = this.dockBounds();
    return Math.max(bounds[0], Math.min(bounds[1], rawDx));
  }

  private clampDy(rawDy: number): number {
    const availH = Math.max(220, this.windowHeightVp);
    const topReserve = Math.max(12, this.safeTopVp + 10);
    const minDy = Math.min(0, -(availH - 68 - this.effectiveBottomVp() - topReserve));
    return Math.max(minDy, Math.min(0, rawDy));
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.mascotCtx)
        .width(56)
        .height(68)
        .onReady(() => {
          this.canvasReady = true;
          this.drawMascot();
        })
    }
    .width(56)
    .height(68)
    .position({
      right: this.baseRight,
      bottom: this.effectiveBottomVp()
    })
    .translate({
      x: this.effectiveTranslateX(),
      y: this.clampDy(this.dragDy)
    })
    .scale({
      x: this.isDragging ? 1.06 : 1.0,
      y: this.isDragging ? 1.06 : 1.0
    })
    .opacity(1.0)
    .animation({ duration: HarmonyMotionTokens.DURATION_LOCAL, curve: HarmonyMotionTokens.CURVE_STANDARD })
    .hoverEffect(HoverEffect.Scale)
    .accessibilityText('打开 MoviePilot 智能助手（支持按住自由拖拽）')
    .onClick(() => {
      if (this.effectiveDocked()) {
        this.isIdleDocked = false;
        this.playAction('wake');
      }
      this.scheduleIdleDock();
      this.onTap();
    })
    .gesture(
      PanGesture({ distance: 4 })
        .onActionStart(() => {
          this.clearIdleTimer();
          this.isDragging = true;
          this.isIdleDocked = false;
          this.activeAction = '';
          this.dragStartDx = this.clampDx(this.dragDx);
          this.dragStartDy = this.clampDy(this.dragDy);
          this.dragStartMs = Date.now();
          this.shakePivotX = this.dragStartDx;
          this.shakeDir = 0;
          this.shakeTurns = 0;
          this.lastShakeTurnMs = 0;
        })
        .onActionUpdate((ev: GestureEvent) => {
          const nextDx = this.clampDx(this.dragStartDx + ev.offsetX);
          this.dragDx = nextDx;
          this.dragDy = this.clampDy(this.dragStartDy + ev.offsetY);
          const delta = nextDx - this.shakePivotX;
          if (Math.abs(delta) >= 18) {
            const dir = delta > 0 ? 1 : -1;
            const now = Date.now();
            if (now - this.lastShakeTurnMs > 550) {
              this.shakeTurns = 0;
            }
            if (this.shakeDir !== 0 && dir !== this.shakeDir) {
              this.shakeTurns += 1;
            }
            this.shakeDir = dir;
            this.shakePivotX = nextDx;
            this.lastShakeTurnMs = now;
          }
        })
        .onActionEnd(() => {
          this.isDragging = false;
          this.scheduleIdleDock();
          const now = Date.now();
          const recentTurns = (now - this.lastShakeTurnMs <= 550) ? this.shakeTurns : 0;
          const elapsed = now - this.dragStartMs;
          const reaction = recentTurns >= 6
            ? 'disassemble'
            : (recentTurns >= 3 ? 'faint' : (elapsed > 4000 ? 'confused' : 'nod'));
          this.playAction(reaction);
        })
        .onActionCancel(() => {
          this.isDragging = false;
          this.scheduleIdleDock();
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
