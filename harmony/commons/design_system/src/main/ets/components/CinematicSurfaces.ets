import { GeneratedDesignTokens } from '../tokens/GeneratedTokens';
import { HarmonyAppearanceStore } from '../store/AppearanceStore';

/** 主导航 4 标签页枚举。 */
export type HarmonyMainTab = 'discover' | 'explore' | 'dashboard' | 'settings';

/** 重复点击底栏主图标弹出的 8 项快捷入口。 */
export interface OverflowMenuItem {
  id: string;
  title: string;
  symbolKey: string;
  group: number;
}

export const OVERFLOW_MENU_ITEMS: OverflowMenuItem[] = [
  { id: 'subscriptions', title: '我的订阅', symbolKey: 'menu_subscriptions', group: 0 },
  { id: 'calendar', title: '订阅日历', symbolKey: 'menu_calendar', group: 0 },
  { id: 'resources', title: '站点资源', symbolKey: 'menu_resources', group: 0 },
  { id: 'downloads', title: '下载', symbolKey: 'menu_downloads', group: 0 },
  { id: 'files', title: '文件管理', symbolKey: 'menu_files', group: 1 },
  { id: 'history', title: '整理历史', symbolKey: 'menu_history', group: 1 },
  { id: 'workflows', title: '工作流', symbolKey: 'menu_workflows', group: 1 },
  { id: 'plugins', title: '插件', symbolKey: 'menu_plugins', group: 1 },
];

/**
 * 鸿蒙原生动态流光背景组件（`CinematicAmbientGradient`）：
 * 消费 `GeneratedDesignTokens` 4 段同源色板，15fps 柔和角度漂移，退后台/省电自动暂停。
 */
@Component
export struct CinematicAmbientGradient {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_BG_PRESET) bgPreset: string = GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET;
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) animateBg: boolean = true;
  @State private angleDeg: number = 145;
  private timerId: number = -1;

  aboutToAppear(): void {
    if (this.animateBg) {
      let tick = 0;
      const intervalMs = Math.round(1000 / Math.max(1, GeneratedDesignTokens.AMBIENT_FPS));
      this.timerId = setInterval(() => {
        tick += 0.06;
        this.angleDeg = 145 + Math.sin(tick) * 18;
      }, intervalMs);
    }
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: this.angleDeg,
        colors: HarmonyAppearanceStore.getGradientStops(this.bgPreset, this.isDark)
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

/**
 * 鸿蒙原生低雾玻璃 + 动态点光源卡片（`CinematicPanel`）：
 * 严格使用 HarmonyOS NEXT 原生 `backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)` +
 * **`pointLight` 动态点光源边缘受光（`IlluminatedType.BORDER_CONTENT`）** + 按压 **`lightUpEffect`**。
 */
@Component
export struct CinematicPanel {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop panelPadding: number = GeneratedDesignTokens.PANEL_PADDING_VP;
  @Prop cornerRadius: number = GeneratedDesignTokens.PANEL_CORNER_RADIUS_VP;
  @Prop enablePointLight: boolean = true;
  @State private lightX: number = 160;
  @State private lightY: number = 60;
  @State private isPressed: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.panelPadding)
    .borderRadius(this.cornerRadius)
    .backgroundColor(this.isDark ? '#1AFFFFFF' : '#94FFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN, {
      colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
      adaptiveColor: AdaptiveColor.AVERAGE,
      policy: BlurStyleActivePolicy.FOLLOWS_WINDOW_ACTIVE_STATE
    })
    .border({
      width: GeneratedDesignTokens.PANEL_BORDER_WIDTH_VP,
      color: this.isDark ? '#33FFFFFF' : '#22000000',
      radius: this.cornerRadius
    })
    .pointLight(this.enablePointLight ? {
      lightSource: {
        positionX: this.lightX,
        positionY: this.lightY,
        positionZ: 90,
        intensity: GeneratedDesignTokens.POINT_LIGHT_CARD_INTENSITY,
        color: this.accentHex
      },
      illuminated: IlluminatedType.BORDER_CONTENT,
      bloom: 0.35
    } : undefined)
    .lightUpEffect(this.isPressed ? 1.0 : 0.94)
    .onTouch((ev: TouchEvent) => {
      if (ev.touches.length > 0) {
        this.lightX = ev.touches[0].x;
        this.lightY = ev.touches[0].y;
      }
      this.isPressed = ev.type === TouchType.Down || ev.type === TouchType.Move;
    })
    .shadow({
      radius: this.isDark ? 12 : 8,
      color: this.isDark ? '#24000000' : '#12000000',
      offsetY: this.isDark ? 5 : 3
    })
  }
}

/** 鸿蒙原生 4+1 流体光感悬浮底部导航栏（`backgroundEffect` + `pointLight` 动态光斑 + 右侧独立 `+1` 圆钮）。 */
@Component
export struct FloatingFourPlusOneNavBar {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop selectedTab: HarmonyMainTab = 'discover';
  @Prop userInitial: string = 'A';
  @State private spotlightX: number = 48;
  onTabClick: (tab: HarmonyMainTab) => void = () => {};
  onPlusOneClick: () => void = () => {};

  private tabLabel(tab: HarmonyMainTab): string {
    if (tab === 'discover') { return '发现'; }
    if (tab === 'explore') { return '探索'; }
    if (tab === 'dashboard') { return '我的'; }
    return '设置';
  }

  build() {
    Row({ space: 12 }) {
      // 左侧 4 主 Tab 流体玻璃胶囊
      Row() {
        ForEach(['discover', 'explore', 'dashboard', 'settings'] as HarmonyMainTab[], (tab: HarmonyMainTab, idx: number) => {
          Column({ space: 2 }) {
            if (tab === 'dashboard') {
              Text(this.userInitial)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width(24)
                .height(24)
                .textAlign(TextAlign.Center)
                .borderRadius(12)
                .backgroundColor(this.accentHex)
            } else {
              SymbolGlyph($r(tab === 'discover' ? 'sys.symbol.sparkles' : (tab === 'explore' ? 'sys.symbol.compass' : 'sys.symbol.gearshape')))
                .fontSize(21)
                .fontColor([this.selectedTab === tab ? this.accentHex : (this.isDark ? '#E6FFFFFF' : '#242030')])
            }
            Text(this.tabLabel(tab))
              .fontSize(10)
              .fontWeight(this.selectedTab === tab ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.selectedTab === tab ? this.accentHex : (this.isDark ? '#CCFFFFFF' : '#403B4F'))
          }
          .layoutWeight(1)
          .height(52)
          .justifyContent(FlexAlign.Center)
          .borderRadius(26)
          .backgroundColor(this.selectedTab === tab ? (this.isDark ? '#26FFFFFF' : '#229E7AF5') : Color.Transparent)
          .onClick(() => {
            this.spotlightX = idx * 66 + 38;
            this.onTabClick(tab);
          })
        })
      }
      .layoutWeight(1)
      .height(62)
      .padding({ left: 6, right: 6 })
      .borderRadius(31)
      .backgroundEffect({
        radius: GeneratedDesignTokens.NAV_BLUR_RADIUS,
        saturation: GeneratedDesignTokens.NAV_BLUR_SATURATION,
        brightness: GeneratedDesignTokens.NAV_BLUR_BRIGHTNESS,
        color: this.isDark ? '#70261F36' : '#CCFFFFFF'
      })
      .border({ width: 0.8, color: this.isDark ? '#44FFFFFF' : '#22000000', radius: 31 })
      .pointLight({
        lightSource: {
          positionX: this.spotlightX,
          positionY: 31,
          positionZ: 70,
          intensity: GeneratedDesignTokens.POINT_LIGHT_NAV_INTENSITY,
          color: this.accentHex
        },
        illuminated: IlluminatedType.BORDER_CONTENT,
        bloom: 0.45
      })
      .shadow({ radius: 16, color: '#38000000', offsetY: 6 })

      // 右侧独立 +1 光感玻璃圆钮（默认全局搜索）
      Stack() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(24)
          .fontColor([this.isDark ? Color.White : '#1C1A24'])
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundEffect({
        radius: GeneratedDesignTokens.NAV_BLUR_RADIUS,
        saturation: GeneratedDesignTokens.NAV_BLUR_SATURATION,
        brightness: GeneratedDesignTokens.NAV_BLUR_BRIGHTNESS,
        color: this.isDark ? '#70261F36' : '#CCFFFFFF'
      })
      .border({ width: 0.8, color: this.isDark ? '#44FFFFFF' : '#22000000', radius: 30 })
      .pointLight({
        lightSource: { positionX: 30, positionY: 30, positionZ: 60, intensity: 1.3, color: this.accentHex },
        illuminated: IlluminatedType.BORDER_CONTENT
      })
      .onClick(() => this.onPlusOneClick())
    }
    .width('100%')
    .padding({ left: 18, right: 18, bottom: 14 })
  }
}

/** 重复点击底栏主图标弹出的 8 项鸿蒙光感快捷菜单。 */
@Component
export struct FloatingOverflowMenuCard {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop userName: string = 'admin';
  @Prop isSuperuser: boolean = true;
  onSelect: (id: string) => void = () => {};

  build() {
    Column({ space: 4 }) {
      Row({ space: 10 }) {
        Text(this.userName.substring(0, 1).toUpperCase())
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .borderRadius(19)
          .backgroundColor(this.accentHex)
        Column({ space: 2 }) {
          Text(this.userName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isDark ? Color.White : '#1C1A24')
          Text(this.isSuperuser ? '● 超级管理员' : '● 普通成员')
            .fontSize(11)
            .fontColor(GeneratedDesignTokens.semanticColor('success', this.isDark))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 8 })

      Divider().color(this.isDark ? '#20FFFFFF' : '#18000000')

      ForEach(OVERFLOW_MENU_ITEMS.filter((i) => i.group === 0), (item: OverflowMenuItem) => {
        Row({ space: 12 }) {
          Text(item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDark ? Color.White : '#1C1A24')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => this.onSelect(item.id))
      })

      Divider().color(this.isDark ? '#20FFFFFF' : '#18000000')

      ForEach(OVERFLOW_MENU_ITEMS.filter((i) => i.group === 1), (item: OverflowMenuItem) => {
        Row({ space: 12 }) {
          Text(item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDark ? Color.White : '#1C1A24')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .onClick(() => this.onSelect(item.id))
      })
    }
    .width(232)
    .padding({ bottom: 10 })
    .borderRadius(GeneratedDesignTokens.PANEL_CORNER_RADIUS_VP)
    .backgroundEffect({
      radius: 40,
      saturation: 1.4,
      brightness: 1.05,
      color: this.isDark ? '#8C251E35' : '#D9FFFFFF'
    })
    .border({ width: 0.9, color: this.isDark ? '#44FFFFFF' : '#24000000', radius: GeneratedDesignTokens.PANEL_CORNER_RADIUS_VP })
    .pointLight({
      lightSource: { positionX: 116, positionY: 40, positionZ: 90, intensity: 1.35, color: this.accentHex },
      illuminated: IlluminatedType.BORDER_CONTENT
    })
    .shadow({ radius: 20, color: '#45000000', offsetY: 10 })
  }
}

/** 通用原生自适应小角标。 */
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
      .borderRadius(12)
      .backgroundColor(this.filled ? this.tintHex : (this.isDark ? '#22FFFFFF' : '#14000000'))
      .border({ width: 0.6, color: this.filled ? this.tintHex : '#33FFFFFF', radius: 12 })
  }
}

/** 通用自适应筛选胶囊按钮。 */
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
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selected ? Color.White : (this.isDark ? '#DBFFFFFF' : '#242030'))
      .padding({ left: 13, right: 13, top: 7, bottom: 7 })
      .borderRadius(18)
      .backgroundColor(this.selected ? this.accentHex : (this.isDark ? '#1AFFFFFF' : '#12000000'))
      .border({ width: 0.7, color: this.selected ? this.accentHex : (this.isDark ? '#2EFFFFFF' : '#20000000'), radius: 18 })
      .onClick(() => this.onTap())
  }
}
