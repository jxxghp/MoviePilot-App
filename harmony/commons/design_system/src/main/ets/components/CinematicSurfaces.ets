import { GeneratedDesignTokens } from '../tokens/GeneratedTokens';
import { HarmonyAppearanceStore } from '../store/AppearanceStore';
import {
  HarmonyMotionTokens,
  HarmonySurfaceModifier,
  HarmonySurfaceRole,
  HarmonyThemeColors
} from './HarmonyDynamicLight';

/**
 * 鸿蒙原生 5 大对等导航目标（避免照搬 iOS 4+1 隐藏菜单）：
 * 发现 · 探索 · 订阅 · 更多 · 我的（手机底部动态光感页签栏，折叠屏展开/平板/2in1 自动切换为左侧竖向侧边栏）。
 */
export type HarmonyMainTab = 'discover' | 'explore' | 'subscribe' | 'more' | 'dashboard';

/** 「更多」中心业务入口定义。 */
export interface MoreToolItem {
  id: string;
  title: string;
  subtitle: string;
  symbolName: string;
  tintHex: string;
  group: number;
}

export const MORE_TOOL_ITEMS: MoreToolItem[] = [
  { id: 'resources', title: '站点资源', subtitle: '9 维筛选与一键推送', symbolName: 'sys.symbol.film', tintHex: '#6EA8FE', group: 0 },
  { id: 'downloads', title: '下载管理', subtitle: '实时队列与限速控制', symbolName: 'sys.symbol.arrow_down_circle', tintHex: '#52C41A', group: 0 },
  { id: 'files', title: '文件管理', subtitle: '多存储浏览与直放', symbolName: 'sys.symbol.folder', tintHex: '#FAAD14', group: 0 },
  { id: 'history', title: '整理历史', subtitle: '识别入库记录追踪', symbolName: 'sys.symbol.clock', tintHex: '#A78BFA', group: 0 },
  { id: 'workflows', title: '工作流', subtitle: '节点画布与社区分享', symbolName: 'sys.symbol.share', tintHex: '#B37FEB', group: 1 },
  { id: 'plugins', title: '插件中心', subtitle: '原生表单与联邦视图', symbolName: 'sys.symbol.puzzle', tintHex: '#36CFC9', group: 1 },
  { id: 'sites', title: '站点管理', subtitle: '双向流量与连通测试', symbolName: 'sys.symbol.worldclock', tintHex: '#73D13D', group: 1 },
  { id: 'calendar', title: '追剧日历', subtitle: '剧集播出排期追踪', symbolName: 'sys.symbol.calendar', tintHex: '#F759AB', group: 1 }
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
 * 默认呈现冷静、高可读的鸿蒙中性深/浅底色（`#0D0D11` / `#F1F3F5`）；
 * 仅当用户在外观中显式开启「氛围流光」时才叠加柔和顶部氛围微光，避免大面积高频动画影响帧率与对比度。
 */
@Component
export struct CinematicAmbientGradient {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_BG_PRESET) bgPreset: string = GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET;
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) animateBg: boolean = false;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(HarmonyThemeColors.canvas(this.isDark))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      if (this.animateBg) {
        Column()
          .width('100%')
          .height(340)
          .linearGradient({
            angle: 180,
            colors: HarmonyAppearanceStore.getGradientStops(this.bgPreset, this.isDark)
          })
          .opacity(this.isDark ? 0.24 : 0.14)
          .position({ top: 0, left: 0 })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

/**
 * 鸿蒙原生分层卡片容器（`CinematicPanel`）：
 * 通过 `HarmonySurfaceModifier` 自动分级适配：
 * - HarmonyOS 7（API 26+）：`uiMaterial.ImmersiveMaterial` 动态光感与交互形变；
 * - HarmonyOS 6（API 20–25）：`hdsEffect.pointLight` 边缘动态受光；
 * - HarmonyOS 5（API 12–19）：自动回退至冷静清晰的分层底色卡片。
 */
@Component
export struct CinematicPanel {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop panelPadding: number = GeneratedDesignTokens.PANEL_PADDING_VP;
  @Prop cornerRadius: number = 16;
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
 * 鸿蒙原生顶部状态栏渐进模糊保护罩（滚动时自动柔和隔离状态栏与下方内容）。
 */
@Component
export struct NativeTopStatusBarBlur {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop visibilityProgress: number = 1.0;

  build() {
    Column()
      .width('100%')
      .height(52)
      .linearGradient({
        angle: 180,
        colors: this.isDark
          ? [['#EB0D0D11', 0.0], ['#B80D0D11', 0.58], ['#000D0D11', 1.0]]
          : [['#EBF1F3F5', 0.0], ['#B8F1F3F5', 0.58], ['#00F1F3F5', 1.0]]
      })
      .opacity(Math.max(0, Math.min(1, this.visibilityProgress)))
      .hitTestBehavior(HitTestMode.None)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

/**
 * 鸿蒙原生二级页面标题栏（左对齐标题 + 圆形动态光感返回键 + 无障碍语义）。
 */
@Component
export struct NativeBackHeader {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop title: string = '';
  @Prop trailingText: string = '';
  @Prop trailingSymbol: string = '';
  @Prop trailingAccessibility: string = '操作';
  onBack: () => void = () => {};
  onTrailingClick: () => void = () => {};

  build() {
    Row({ space: 12 }) {
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

      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(mpPrimaryText(this.isDark))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.trailingSymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.trailingSymbol))
            .fontSize(20)
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
          .fontWeight(FontWeight.Medium)
          .fontColor(mpPrimaryText(this.isDark))
          .height(36)
          .padding({ left: 14, right: 14 })
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 18, this.accentHex, true, this.dynamicLight))
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onTrailingClick())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 44, bottom: 8 })
  }
}

/**
 * 鸿蒙原生一级主页面标题栏（遵循 HarmonyOS 左侧大标题 + 右侧动态光感动作圆钮规范）。
 */
@Component
export struct HarmonyPageHeader {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop primarySymbol: string = '';
  @Prop primaryAccessibility: string = '搜索';
  @Prop secondarySymbol: string = '';
  @Prop secondaryAccessibility: string = '操作';
  onPrimaryClick: () => void = () => {};
  onSecondaryClick: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .maxLines(1)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(mpSecondaryText(this.isDark))
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.secondarySymbol.length > 0) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r(this.secondarySymbol))
            .fontSize(20)
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
            .fontSize(20)
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
 * 鸿蒙规范页级切换页签栏（对标 ArkUI `SubTabBarStyle`）：
 * 专用于平级功能域或页内章节切换（如「我的订阅 / 订阅广场」、「已安装 / 插件市场」、「数据页 / 参数配置」），
 * 告别所有切换都堆砌方框胶囊的做法，带 150ms 标准缓动下划线指示器与完整无障碍 `accessibilitySelected` 语义。
 */
@Component
export struct HarmonyUnderlineTabBar {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop tabs: string[] = [];
  @Prop selectedIndex: number = 0;
  onSelect: (index: number) => void = () => {};

  build() {
    Column() {
      Row() {
        ForEach(this.tabs, (label: string, idx: number) => {
          Column({ space: 6 }) {
            Text(label)
              .fontSize(15)
              .fontWeight(this.selectedIndex === idx ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.selectedIndex === idx ? this.accentHex : mpSecondaryText(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .animation({ duration: HarmonyMotionTokens.DURATION_SHORT, curve: HarmonyMotionTokens.CURVE_STANDARD })

            Column()
              .width(this.selectedIndex === idx ? 26 : 0)
              .height(3)
              .borderRadius(1.5)
              .backgroundColor(this.accentHex)
              .animation({ duration: HarmonyMotionTokens.DURATION_LOCAL, curve: HarmonyMotionTokens.CURVE_STANDARD })
          }
          .layoutWeight(1)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .hoverEffect(HoverEffect.Highlight)
          .focusable(true)
          .accessibilityText(`${label}${this.selectedIndex === idx ? '，已选中' : ''}`)
          .onClick(() => this.onSelect(idx))
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })

      Divider().color(HarmonyThemeColors.divider(this.isDark))
    }
    .width('100%')
  }
}

/**
 * 鸿蒙规范互斥模式分段控制器（对标 ArkUI `SegmentButton`）：
 * 专用于 2~4 项互斥视图或设置切换（如「深色 / 浅色 / 跟随系统」、「热门电影 / 热门剧集 / 社区分享」）。
 */
@Component
export struct HarmonySegmentedSwitch {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
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
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(18)
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
    .borderRadius(21)
    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
    .border({ width: 0.5, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: 21 })
  }
}

/**
 * 鸿蒙自适应底部 5 页签导航栏（窄屏手机使用，HarmonyOS 7 动态光感 + 低版本自动回退）。
 */
@Component
export struct HarmonyBottomNavBar {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
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
    if (tab === 'subscribe') { return active ? 'sys.symbol.star_fill' : 'sys.symbol.star'; }
    return 'sys.symbol.dot_grid_2x2';
  }

  build() {
    Row() {
      ForEach(['discover', 'explore', 'subscribe', 'more', 'dashboard'] as HarmonyMainTab[], (tab: HarmonyMainTab) => {
        Column({ space: 3 }) {
          if (tab === 'dashboard') {
            if (this.userAvatar.length > 0) {
              Image(this.userAvatar)
                .width(22)
                .height(22)
                .borderRadius(11)
                .objectFit(ImageFit.Cover)
                .border({
                  width: this.selectedTab === tab ? 1.6 : 0.8,
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
              .fontSize(21)
              .fontColor([this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark)])
          }
          Text(this.tabLabel(tab))
            .fontSize(10)
            .fontWeight(this.selectedTab === tab ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.selectedTab === tab ? this.accentHex : mpSecondaryText(this.isDark))
        }
        .layoutWeight(1)
        .height(54)
        .justifyContent(FlexAlign.Center)
        .borderRadius(20)
        .backgroundColor(this.selectedTab === tab ? (this.isDark ? '#249E7AF5' : '#1A9E7AF5') : Color.Transparent)
        .animation({ duration: HarmonyMotionTokens.DURATION_SHORT, curve: HarmonyMotionTokens.CURVE_STANDARD })
        .hoverEffect(HoverEffect.Highlight)
        .focusable(true)
        .accessibilityText(`${this.tabLabel(tab)}${this.selectedTab === tab ? '，已选中' : ''}`)
        .onClick(() => this.onTabClick(tab))
      })
    }
    .width('100%')
    .height(62)
    .padding({ left: 8, right: 8 })
    .borderRadius(31)
    .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'bar', 31, this.accentHex, true, this.dynamicLight))
    .margin({ left: 14, right: 14, bottom: 14 })
  }
}

/**
 * 鸿蒙宽屏/折叠屏展开/平板侧边竖向导航栏（`ADAPTATION.md` 宽窗口自动由底栏转换为侧栏）。
 */
@Component
export struct HarmonySideNavRail {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
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
    if (tab === 'subscribe') { return active ? 'sys.symbol.star_fill' : 'sys.symbol.star'; }
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
        .borderRadius(16)
        .backgroundColor(this.selectedTab === tab ? (this.isDark ? '#249E7AF5' : '#1A9E7AF5') : Color.Transparent)
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

/** 悬浮 AI 助手入口球（仅在一级主页呈现，遵循克制原则不遮挡二级业务操作）。 */
@Component
export struct FloatingAiMascotButton {
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
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
      colors: [['#FF9F84FF', 0], ['#FF6B5CE7', 0.6], ['#FFE66BC4', 1]]
    })
    .shadow({ radius: 14, color: '#559E7AF5', offsetY: 5 })
    .hoverEffect(HoverEffect.Scale)
    .accessibilityText('打开 AI 智能助手')
    .onClick(() => this.onTap())
  }
}

/** 通用原生自适应状态角标。 */
@Component
export struct NativeAdaptiveBadge {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop text: string = '';
  @Prop tintHex: string = '#9E7AF5';
  @Prop filled: boolean = false;

  build() {
    Text(this.text)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.filled ? Color.White : this.tintHex)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(this.filled ? this.tintHex : (this.isDark ? '#1F9E7AF5' : '#149E7AF5'))
  }
}

/**
 * 鸿蒙多维筛选芯片（仅用于列表筛选属性，不用于页面切换）：
 * 支持按压即时反馈、键鼠悬停与无障碍勾选状态。
 */
@Component
export struct NativeAdaptivePill {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop title: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {};

  build() {
    Text(this.title)
      .fontSize(13)
      .fontWeight(this.selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected ? Color.White : mpPrimaryText(this.isDark))
      .padding({ left: 13, right: 13, top: 7, bottom: 7 })
      .borderRadius(12)
      .backgroundColor(this.selected ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
      .animation({ duration: HarmonyMotionTokens.DURATION_INSTANT, curve: HarmonyMotionTokens.CURVE_STANDARD })
      .hoverEffect(HoverEffect.Highlight)
      .focusable(true)
      .accessibilityText(`${this.title}${this.selected ? '，已选中' : ''}`)
      .onClick(() => this.onTap())
  }
}
