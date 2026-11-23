import { GeneratedDesignTokens } from '../tokens/GeneratedTokens';
import { HarmonyAppearanceStore } from '../store/AppearanceStore';
import {
  HarmonyMotionTokens,
  HarmonySurfaceModifier,
  HarmonySurfaceRole,
  HarmonyThemeColors
} from './HarmonyDynamicLight';

/**
 * 鸿蒙原生 5 大对等导航目标：
 * 发现 · 探索 · 订阅 · 更多 · 我的（手机底部采用圆角悬浮一体式动态光感导航栏，折叠屏/平板自动切换为左侧竖向侧栏）。
 */
export type HarmonyMainTab = 'discover' | 'explore' | 'subscribe' | 'more' | 'dashboard';

/** 「更多」中心业务入口定义（严格按 4 大清晰业务域归类）。 */
export interface MoreToolItem {
  id: string;
  title: string;
  subtitle: string;
  symbolName: string;
  tintHex: string;
  group: number; // 0: 资源与媒体流转, 1: 插件与工作流, 2: 追剧与广场, 3: 系统诊断
}

export const MORE_TOOL_ITEMS: MoreToolItem[] = [
  // 0. 资源与媒体流转
  { id: 'resources', title: '站点资源', subtitle: '多站搜索与精细筛选', symbolName: 'sys.symbol.magnifyingglass', tintHex: '#317AF7', group: 0 },
  { id: 'sites', title: '站点管理', subtitle: '站点配置与流量监控', symbolName: 'sys.symbol.worldclock', tintHex: '#26B8A8', group: 0 },
  { id: 'downloads', title: '下载管理', subtitle: '实时速率与任务控制', symbolName: 'sys.symbol.arrow_down_circle', tintHex: '#34C759', group: 0 },
  { id: 'files', title: '文件管理', subtitle: '多存储浏览与整理播放', symbolName: 'sys.symbol.folder', tintHex: '#F29B38', group: 0 },
  { id: 'history', title: '整理历史', subtitle: '入库记录与手动重整理', symbolName: 'sys.symbol.clock', tintHex: '#64A2FF', group: 0 },
  { id: 'media_library', title: '媒体库', subtitle: 'Emby / Jellyfin / Plex', symbolName: 'sys.symbol.film', tintHex: '#5AC8FA', group: 0 },
  // 1. 插件与工作流
  { id: 'plugins', title: '插件中心', subtitle: '已安装与市场扩展', symbolName: 'sys.symbol.puzzle', tintHex: '#26B8A8', group: 1 },
  { id: 'workflows', title: '工作流', subtitle: '自动化流程与节点画布', symbolName: 'sys.symbol.share', tintHex: '#8E7BFF', group: 1 },
  // 2. 追剧与广场
  { id: 'calendar', title: '追剧日历', subtitle: '近期播出排期追踪', symbolName: 'sys.symbol.calendar', tintHex: '#EE6896', group: 2 },
  { id: 'subscribe_square', title: '订阅广场', subtitle: '热门榜单与社区分享', symbolName: 'sys.symbol.flame', tintHex: '#F29B38', group: 2 },
  // 3. 系统诊断（独立捷径直达）
  { id: 'diag_check', title: '系统检查', subtitle: '核心状态自检', symbolName: 'sys.symbol.checkmark_shield', tintHex: '#34C759', group: 3 },
  { id: 'diag_schedulers', title: '定时服务', subtitle: '查看与手动触发', symbolName: 'sys.symbol.clock', tintHex: '#EE6896', group: 3 },
  { id: 'diag_logs', title: '实时日志', subtitle: '服务端日志追踪', symbolName: 'sys.symbol.doc_text', tintHex: '#5AC8FA', group: 3 },
  { id: 'diag_words', title: '词表管理', subtitle: '识别与过滤规则', symbolName: 'sys.symbol.bookmark', tintHex: '#26B8A8', group: 3 },
  { id: 'diag_recognize', title: '名称识别', subtitle: '种子标题在线测试', symbolName: 'sys.symbol.magnifyingglass', tintHex: '#64A2FF', group: 3 },
  { id: 'diag_network', title: '网络测试', subtitle: '连通与延迟检测', symbolName: 'sys.symbol.worldclock', tintHex: '#F29B38', group: 3 }
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

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
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
 * 鸿蒙原生顶部状态栏渐进模糊保护罩。
 */
@Component
export struct NativeTopStatusBarBlur {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @Prop visibilityProgress: number = 1.0;

  build() {
    Column()
      .width('100%')
      .height(54)
      .linearGradient({
        angle: 180,
        colors: this.isDark
          ? [
            [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(true, this.paletteId), 'EC'), 0.0],
            [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(true, this.paletteId), 'B8'), 0.58],
            ['#00000000', 1.0]
          ]
          : [
            [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(false, this.paletteId), 'EC'), 0.0],
            [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(false, this.paletteId), 'B8'), 0.58],
            ['#00FFFFFF', 1.0]
          ]
      })
      .opacity(Math.max(0, Math.min(1, this.visibilityProgress)))
      .hitTestBehavior(HitTestMode.None)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
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

  build() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([mpPrimaryText(this.isDark)])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 20, this.accentHex, true, this.dynamicLight))
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText('返回上一级')
      .onClick(() => this.onBack())

      Column({ space: 1 }) {
        Text(this.title)
          .fontSize(20)
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
            .fontSize(19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 20, this.accentHex, true, this.dynamicLight))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.secondaryAccessibility)
        .onClick(() => this.onSecondaryClick())
      }

      if (this.trailingSymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.trailingSymbol))
            .fontSize(19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 20, this.accentHex, true, this.dynamicLight))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.trailingAccessibility)
        .onClick(() => this.onTrailingClick())
      } else if (this.trailingText.length > 0) {
        Button(this.trailingText)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.trailingPrimary ? Color.White : mpPrimaryText(this.isDark))
          .height(38)
          .padding({ left: 16, right: 16 })
          .borderRadius(19)
          .backgroundColor(this.trailingPrimary ? this.accentHex : Color.Transparent)
          .attributeModifier(this.trailingPrimary
            ? undefined
            : new HarmonySurfaceModifier(this.isDark, 'pill', 19, this.accentHex, true, this.dynamicLight))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onTrailingClick())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 44, bottom: 8 })
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
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop primarySymbol: string = '';
  @Prop primaryAccessibility: string = '操作';
  @Prop secondarySymbol: string = '';
  @Prop secondaryAccessibility: string = '快捷操作';
  @Prop tertiarySymbol: string = '';
  @Prop tertiaryAccessibility: string = '通知';
  onPrimaryClick: () => void = () => {};
  onSecondaryClick: () => void = () => {};
  onTertiaryClick: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(28)
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
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.tertiarySymbol))
            .fontSize(19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 20, this.accentHex, true, this.dynamicLight))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.tertiaryAccessibility)
        .onClick(() => this.onTertiaryClick())
      }

      if (this.secondarySymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.secondarySymbol))
            .fontSize(19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 20, this.accentHex, true, this.dynamicLight))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.secondaryAccessibility)
        .onClick(() => this.onSecondaryClick())
      }

      if (this.primarySymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.primarySymbol))
            .fontSize(19)
            .fontColor([mpPrimaryText(this.isDark)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 20, this.accentHex, true, this.dynamicLight))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.primaryAccessibility)
        .onClick(() => this.onPrimaryClick())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 44, bottom: 8 })
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
          .fontSize(14)
          .fontWeight(this.selectedIndex === idx ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedIndex === idx ? Color.White : mpSecondaryText(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width(equalWidth ? '100%' : undefined)
      .height(42)
      .padding({ left: 18, right: 18 })
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
 * 鸿蒙底部悬浮一体式导航栏（类似 iOS 悬浮液态质感 + HarmonyOS 7 动态光感）：
 * - 整条圆角悬浮胶囊承载 5 大主导航；
 * - 选中态将图标与文字整体包裹在同一圆角品牌色胶囊内联合高亮。
 */
@Component
export struct HarmonyBottomNavBar {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop selectedTab: HarmonyMainTab = 'discover';
  @Prop userInitial: string = 'A';
  @Prop userAvatar: string = '';
  onTabClick: (tab: HarmonyMainTab) => void = () => {};

  private tabLabel(tab: HarmonyMainTab): string {
    if (tab === 'discover') { return '发现'; }
    if (tab === 'explore') { return '探索'; }
    if (tab === 'subscribe') { return '订阅'; }
    if (tab === 'more') { return '更多'; }
    return '我的';
  }

  private tabSymbol(tab: HarmonyMainTab, active: boolean): string {
    if (tab === 'discover') { return active ? 'sys.symbol.TV_tv_fill' : 'sys.symbol.TV_tv'; }
    if (tab === 'explore') { return 'sys.symbol.compass'; }
    if (tab === 'subscribe') { return active ? 'sys.symbol.bookmark_fill' : 'sys.symbol.bookmark'; }
    return 'sys.symbol.dot_grid_2x2';
  }

  build() {
    Row() {
      Row({ space: 2 }) {
        ForEach(['discover', 'explore', 'subscribe', 'more', 'dashboard'] as HarmonyMainTab[], (tab: HarmonyMainTab) => {
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
          .height(50)
          .justifyContent(FlexAlign.Center)
          .borderRadius(25)
          .backgroundColor(this.selectedTab === tab
            ? HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '34' : '1E')
            : Color.Transparent)
          .border(this.selectedTab === tab
            ? { width: 0.6, color: HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '50' : '2E'), radius: 25 }
            : { width: 0, color: Color.Transparent, radius: 25 })
          .animation({ duration: HarmonyMotionTokens.DURATION_SHORT, curve: HarmonyMotionTokens.CURVE_STANDARD })
          .hoverEffect(HoverEffect.Highlight)
          .focusable(true)
          .accessibilityText(`${this.tabLabel(tab)}${this.selectedTab === tab ? '，已选中' : ''}`)
          .onClick(() => this.onTabClick(tab))
        })
      }
      .width('100%')
      .height(62)
      .padding({ left: 6, right: 6 })
      .borderRadius(31)
      .clip(true)
      .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'bar', 31, this.accentHex, true, this.dynamicLight))
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 18 })
  }
}

/**
 * 鸿蒙宽屏/折叠屏展开/平板侧边竖向导航栏。
 */
@Component
export struct HarmonySideNavRail {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop selectedTab: HarmonyMainTab = 'discover';
  @Prop userInitial: string = 'A';
  @Prop userAvatar: string = '';
  onTabClick: (tab: HarmonyMainTab) => void = () => {};
  onSearchClick: () => void = () => {};

  private tabLabel(tab: HarmonyMainTab): string {
    if (tab === 'discover') { return '发现'; }
    if (tab === 'explore') { return '探索'; }
    if (tab === 'subscribe') { return '订阅'; }
    if (tab === 'more') { return '更多'; }
    return '我的';
  }

  private tabSymbol(tab: HarmonyMainTab, active: boolean): string {
    if (tab === 'discover') { return active ? 'sys.symbol.TV_tv_fill' : 'sys.symbol.TV_tv'; }
    if (tab === 'explore') { return 'sys.symbol.compass'; }
    if (tab === 'subscribe') { return active ? 'sys.symbol.bookmark_fill' : 'sys.symbol.bookmark'; }
    return 'sys.symbol.dot_grid_2x2';
  }

  build() {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor(this.accentHex)
      .margin({ top: 48, bottom: 12 })
      .accessibilityText('全局搜索')
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.onSearchClick())

      ForEach(['discover', 'explore', 'subscribe', 'more', 'dashboard'] as HarmonyMainTab[], (tab: HarmonyMainTab) => {
        Column({ space: 4 }) {
          if (tab === 'dashboard') {
            if (this.userAvatar.length > 0) {
              Image(this.userAvatar).width(24).height(24).borderRadius(12).objectFit(ImageFit.Cover)
            } else {
              Text(this.userInitial)
                .fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
                .width(24).height(24).textAlign(TextAlign.Center).borderRadius(12).backgroundColor(this.accentHex)
            }
          } else {
            SymbolGlyph($r(this.tabSymbol(tab, this.selectedTab === tab)))
              .fontSize(22)
              .fontColor([this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark)])
          }
          Text(this.tabLabel(tab))
            .fontSize(11)
            .fontWeight(this.selectedTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark))
        }
        .width(64)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .borderRadius(18)
        .backgroundColor(this.selectedTab === tab
          ? HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '30' : '1E')
          : Color.Transparent)
        .hoverEffect(HoverEffect.Highlight)
        .focusable(true)
        .accessibilityText(`${this.tabLabel(tab)}${this.selectedTab === tab ? '，已选中' : ''}`)
        .onClick(() => this.onTabClick(tab))
      })

      Blank()
    }
    .width(84)
    .height('100%')
    .padding({ bottom: 24 })
    .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'bar', 0, this.accentHex, false, this.dynamicLight))
  }
}

/** 悬浮 AI 助手入口球（跟随当前鸿蒙主题强调色光晕）。 */
@Component
export struct FloatingAiMascotButton {
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  onTap: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.ai_edit'))
        .fontSize(22)
        .fontColor([Color.White])
    }
    .width(50)
    .height(50)
    .linearGradient({
      angle: 135,
      colors: [[this.accentHex, 0], ['#FF5B8DFF', 0.55], ['#FF26B8A8', 1]]
    })
    .shadow({ radius: 16, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '66'), offsetY: 5 })
    .hoverEffect(HoverEffect.Scale)
    .accessibilityText('打开智能助手')
    .onClick(() => this.onTap())
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
