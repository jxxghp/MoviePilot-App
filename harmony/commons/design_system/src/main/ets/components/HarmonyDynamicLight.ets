import { curves, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsEffect } from '@kit.UIDesignKit';
import { HarmonyAppearanceStore } from '../store/AppearanceStore';

/**
 * 鸿蒙动态光感与系统材质运行层级：
 * - `harmonyos7_immersive`：HarmonyOS 7（API 26.0.0+），启用官方 `uiMaterial.ImmersiveMaterial` 动态光感与交互形变；
 * - `harmonyos6_hds_light`：HarmonyOS 6（API 20–25），自动回退至 `UIDesignKit` `hdsEffect.pointLight` 点光源受光；
 * - `legacy_fallback`：HarmonyOS 5 / OpenHarmony（API 12–19），自动回退至原生分层底色、`BlurStyle` 与 `lightUpEffect`。
 */
export type HarmonyLightTier = 'harmonyos7_immersive' | 'harmonyos6_hds_light' | 'legacy_fallback';

/** 表面语义角色，决定动态光感厚度与低版本回退材质。 */
export type HarmonySurfaceRole = 'card' | 'bar' | 'overlay' | 'pill';

/**
 * 鸿蒙语义动效 Token（遵循 OpenHarmony UX 公开参考时长与曲线语义）。
 */
export class HarmonyMotionTokens {
  static readonly DURATION_INSTANT: number = 100;
  static readonly DURATION_SHORT: number = 150;
  static readonly DURATION_LOCAL: number = 200;
  static readonly DURATION_FULL: number = 300;

  static readonly CURVE_STANDARD: Curve = Curve.FastOutSlowIn;
  static readonly CURVE_DECELERATE: Curve = Curve.EaseOut;
  static readonly CURVE_ACCELERATE: Curve = Curve.EaseIn;

  static followSpring(): ICurve {
    return curves.responsiveSpringMotion();
  }

  static settleSpring(): ICurve {
    return curves.springMotion();
  }
}

/**
 * 鸿蒙语义色彩表（按当前鸿蒙色板动态解析，冷静清晰、层级分明，不强制照搬 iOS 紫雾色系）。
 */
export class HarmonyThemeColors {
  static canvas(isDark: boolean, paletteId: string = 'harmony_blue', pureBlack: boolean = false): string {
    if (isDark && pureBlack) {
      return '#FF000000';
    }
    const p = HarmonyAppearanceStore.paletteById(paletteId);
    return isDark ? p.canvasDark : p.canvasLight;
  }

  static headerTint(isDark: boolean, paletteId: string = 'harmony_blue'): string {
    const p = HarmonyAppearanceStore.paletteById(paletteId);
    return isDark ? p.headerTintDark : p.headerTintLight;
  }

  static card(isDark: boolean, paletteId: string = 'harmony_blue'): string {
    const p = HarmonyAppearanceStore.paletteById(paletteId);
    return isDark ? p.cardDark : p.cardLight;
  }

  static cardElevated(isDark: boolean): string {
    return isDark ? '#FF1F2633' : '#FFFFFFFF';
  }

  static barFallback(isDark: boolean): string {
    return isDark ? '#E6171D28' : '#ECF9FBFE';
  }

  static overlayFallback(isDark: boolean): string {
    return isDark ? '#F5151A24' : '#F8FFFFFF';
  }

  static pillFallback(isDark: boolean): string {
    return isDark ? '#CC1D2534' : '#E6FFFFFF';
  }

  static chipFill(isDark: boolean): string {
    return isDark ? '#FF1F2532' : '#FFE5E9F0';
  }

  static softDangerBg(isDark: boolean): string {
    return isDark ? '#2EE84855' : '#1CE84855';
  }

  static borderSubtle(isDark: boolean): string {
    return isDark ? '#1FFFFFFF' : '#14000000';
  }

  static divider(isDark: boolean): string {
    return isDark ? '#18FFFFFF' : '#12000000';
  }

  static primaryText(isDark: boolean): string {
    return isDark ? '#F2FFFFFF' : '#E6000000';
  }

  static secondaryText(isDark: boolean): string {
    return isDark ? '#99FFFFFF' : '#99000000';
  }

  static mutedText(isDark: boolean): string {
    return isDark ? '#66FFFFFF' : '#66000000';
  }
}

/**
 * 鸿蒙运行时动态光感能力探测器：
 * 安全判断当前设备 OS 版本与算力档位，低版本系统零崩溃自动降级。
 */
export class HarmonyDynamicLight {
  private static cachedTier: HarmonyLightTier | null = null;
  private static cachedApi: number | null = null;

  static sdkApiVersion(): number {
    if (HarmonyDynamicLight.cachedApi !== null) {
      return HarmonyDynamicLight.cachedApi;
    }
    try {
      const api = deviceInfo.sdkApiVersion;
      HarmonyDynamicLight.cachedApi = typeof api === 'number' ? api : 12;
    } catch {
      HarmonyDynamicLight.cachedApi = 12;
    }
    return HarmonyDynamicLight.cachedApi;
  }

  static currentTier(): HarmonyLightTier {
    if (HarmonyDynamicLight.cachedTier !== null) {
      return HarmonyDynamicLight.cachedTier;
    }
    const api = HarmonyDynamicLight.sdkApiVersion();
    if (api >= 26) {
      try {
        if (uiMaterial.isImmersiveMaterialSupported()) {
          HarmonyDynamicLight.cachedTier = 'harmonyos7_immersive';
          return HarmonyDynamicLight.cachedTier;
        }
      } catch {
        // 运行时环境不支持 API 26 uiMaterial 时平滑回退
      }
    }
    if (api >= 20) {
      try {
        const probe = new hdsEffect.HdsEffectBuilder();
        if (probe !== undefined) {
          HarmonyDynamicLight.cachedTier = 'harmonyos6_hds_light';
          return HarmonyDynamicLight.cachedTier;
        }
      } catch {
        // 运行时环境不支持 UIDesignKit 点光源时平滑回退
      }
    }
    HarmonyDynamicLight.cachedTier = 'legacy_fallback';
    return HarmonyDynamicLight.cachedTier;
  }

  static materialLevelLabel(): string {
    if (HarmonyDynamicLight.currentTier() !== 'harmonyos7_immersive') {
      return '标准分层';
    }
    try {
      const lvl = uiMaterial.getGlobalMaterialLevel();
      if (lvl === uiMaterial.MaterialLevel.EXQUISITE) { return '旗舰光感'; }
      if (lvl === uiMaterial.MaterialLevel.GENTLE) { return '均衡光感'; }
      return '流畅光感';
    } catch {
      return '动态光感';
    }
  }

  static tierLabel(): string {
    const tier = HarmonyDynamicLight.currentTier();
    if (tier === 'harmonyos7_immersive') {
      return `HarmonyOS 7 动态光感 · ${HarmonyDynamicLight.materialLevelLabel()}`;
    }
    if (tier === 'harmonyos6_hds_light') {
      return 'HarmonyOS 6 点光源光感（自动适配）';
    }
    return `标准分层质感（API ${HarmonyDynamicLight.sdkApiVersion()} 自动回退）`;
  }
}

/**
 * 鸿蒙多代际自适应动态光感修饰器（`AttributeModifier`）：
 * - HarmonyOS 7（API 26+）：自动应用官方 `uiMaterial.ImmersiveMaterial`（沉浸光感 + 交互形变 + 触控光效反馈）；
 * - HarmonyOS 6（API 20–25）：自动回退为 `hdsEffect.HdsEffectBuilder().pointLight(...)` 动态边缘受光；
 * - HarmonyOS 5 / 低版本（API 12–19）：自动回退为高对比分层表面色 + 细描边 + 轻阴影（浮栏保留 `BlurStyle.COMPONENT_THIN`）。
 */
export class HarmonySurfaceModifier implements AttributeModifier<CommonAttribute> {
  isDark: boolean;
  role: HarmonySurfaceRole;
  cornerRadius: number;
  accentHex: string;
  interactive: boolean;
  dynamicLightEnabled: boolean;

  constructor(
    isDark: boolean,
    role: HarmonySurfaceRole = 'card',
    cornerRadius: number = 16,
    accentHex: string = '#317AF7',
    interactive: boolean = false,
    dynamicLightEnabled: boolean = true
  ) {
    this.isDark = isDark;
    this.role = role;
    this.cornerRadius = cornerRadius;
    this.accentHex = accentHex;
    this.interactive = interactive;
    this.dynamicLightEnabled = dynamicLightEnabled;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const tier = this.dynamicLightEnabled ? HarmonyDynamicLight.currentTier() : 'legacy_fallback';
    // 先铺设清晰可见的鸿蒙分级表面底色、毛玻璃与精致高光描边，确保模拟器与各 GPU 档位均清晰可读
    this.applyFallbackSurface(instance);

    if (tier === 'harmonyos7_immersive') {
      try {
        const immersiveStyle = this.resolveImmersiveStyle();
        const tintColor = this.resolveImmersiveTint();
        const material = new uiMaterial.ImmersiveMaterial({
          style: immersiveStyle,
          materialColor: tintColor,
          colorInvert: false,
          applyShadow: this.role === 'bar' || this.role === 'overlay',
          interactive: this.interactive,
          lightEffect: this.interactive ? { color: this.accentHex } : null
        });
        instance.systemMaterial(material);
        return;
      } catch {
        // 运行时动态光感构造异常时保留上方分层质感
      }
    }

    // HarmonyOS 6（API 20-25）点光源受光回退
    if (tier === 'harmonyos6_hds_light' && (this.interactive || this.role === 'bar')) {
      try {
        const fx = new hdsEffect.HdsEffectBuilder()
          .pointLight({
            sourceType: hdsEffect.PointLightSourceType.SOFT,
            illuminatedType: this.role === 'bar'
              ? hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
              : hdsEffect.PointLightIlluminatedType.BORDER_CONTENT
          })
          .buildEffect();
        instance.visualEffect(fx);
      } catch {
        // 静默回退至 HarmonyOS 5 基础表面
      }
    }
  }

  applyPressedAttribute(instance: CommonAttribute): void {
    if (this.interactive) {
      instance.opacity(0.92);
      instance.lightUpEffect(1.0);
    }
  }

  private resolveImmersiveStyle(): uiMaterial.ImmersiveStyle {
    if (this.role === 'bar') {
      return uiMaterial.ImmersiveStyle.THICK;
    }
    if (this.role === 'overlay') {
      return uiMaterial.ImmersiveStyle.THICK;
    }
    if (this.role === 'pill') {
      return uiMaterial.ImmersiveStyle.REGULAR;
    }
    return uiMaterial.ImmersiveStyle.REGULAR;
  }

  private resolveImmersiveTint(): ResourceColor {
    if (this.role === 'bar') {
      return this.isDark ? '#E0171D28' : '#EBF9FBFE';
    }
    if (this.role === 'pill') {
      return this.isDark ? '#CC1E2635' : '#E8FFFFFF';
    }
    if (this.role === 'overlay') {
      return this.isDark ? '#E8151A24' : '#F4FFFFFF';
    }
    return this.isDark ? '#DB161C27' : '#F6FFFFFF';
  }

  private applyFallbackSurface(instance: CommonAttribute): void {
    if (this.role === 'bar') {
      instance.backgroundColor(HarmonyThemeColors.barFallback(this.isDark));
      instance.backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK, {
        colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.DEFAULT
      });
      instance.border({
        width: 0.8,
        color: this.isDark ? '#2BFFFFFF' : '#22000000',
        radius: this.cornerRadius
      });
      instance.shadow({
        radius: this.isDark ? 20 : 16,
        color: this.isDark ? '#55000000' : '#1E000000',
        offsetY: 6
      });
      return;
    }
    if (this.role === 'overlay') {
      instance.backgroundColor(HarmonyThemeColors.overlayFallback(this.isDark));
      instance.backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
        colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.DEFAULT
      });
      instance.border({
        width: 0.7,
        color: this.isDark ? '#24FFFFFF' : '#18000000',
        radius: this.cornerRadius
      });
      return;
    }
    if (this.role === 'pill') {
      instance.backgroundColor(HarmonyThemeColors.pillFallback(this.isDark));
      instance.backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
        colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.DEFAULT
      });
      instance.border({
        width: 0.7,
        color: this.isDark ? '#28FFFFFF' : '#1A000000',
        radius: this.cornerRadius
      });
      instance.shadow({
        radius: this.isDark ? 10 : 8,
        color: this.isDark ? '#32000000' : '#14000000',
        offsetY: 3
      });
      return;
    }
    const paletteId = AppStorage.get<string>(HarmonyAppearanceStore.KEY_PALETTE_ID) ?? 'harmony_blue';
    instance.backgroundColor(HarmonyThemeColors.card(this.isDark, paletteId));
    instance.border({
      width: 0.6,
      color: HarmonyThemeColors.borderSubtle(this.isDark),
      radius: this.cornerRadius
    });
    instance.shadow({
      radius: this.isDark ? 8 : 6,
      color: this.isDark ? '#20000000' : '#0E000000',
      offsetY: 2
    });
  }
}
