import { curves, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsEffect } from '@kit.UIDesignKit';

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
 * 鸿蒙语义动效 Token（遵循 OpenHarmony UX 公开参考时长与曲线语义）：
 * - 来源：OpenHarmony UX 动效参考时长与 ArkUI 曲线默认（H2/H4）。
 */
export class HarmonyMotionTokens {
  /** 简单色彩/高亮反馈（约 100ms）。 */
  static readonly DURATION_INSTANT: number = 100;
  /** 短交互按压/开关（约 150ms）。 */
  static readonly DURATION_SHORT: number = 150;
  /** 局部页签/列表状态变化（约 200ms）。 */
  static readonly DURATION_LOCAL: number = 200;
  /** 完整弹层或页面层级切换（约 300ms）。 */
  static readonly DURATION_FULL: number = 300;

  /** 标准曲线：视线内状态切换（Tab/Segment/Switch）。 */
  static readonly CURVE_STANDARD: Curve = Curve.FastOutSlowIn;
  /** 减速曲线：元素进入视线并平稳落定。 */
  static readonly CURVE_DECELERATE: Curve = Curve.EaseOut;
  /** 加速曲线：元素快速退出视线。 */
  static readonly CURVE_ACCELERATE: Curve = Curve.EaseIn;

  /** 跟手弹性曲线（ArkUI 默认参数）。 */
  static followSpring(): ICurve {
    return curves.responsiveSpringMotion();
  }

  /** 离手回稳与速度衔接弹性曲线（ArkUI 默认参数）。 */
  static settleSpring(): ICurve {
    return curves.springMotion();
  }
}

/**
 * 鸿蒙语义色彩表（HarmonyOS NEXT / HarmonyOS 7 冷静中性画布与分层表面，不照搬 iOS 紫色渐变雾）。
 */
export class HarmonyThemeColors {
  static canvas(isDark: boolean): string {
    return isDark ? '#FF0D0D11' : '#FFF1F3F5';
  }

  static card(isDark: boolean): string {
    return isDark ? '#FF1B1B22' : '#FFFFFFFF';
  }

  static cardElevated(isDark: boolean): string {
    return isDark ? '#FF252430' : '#FFFFFFFF';
  }

  static barFallback(isDark: boolean): string {
    return isDark ? '#E61A1A22' : '#EBF7F8FA';
  }

  static overlayFallback(isDark: boolean): string {
    return isDark ? '#F01D1C26' : '#F5FFFFFF';
  }

  static chipFill(isDark: boolean): string {
    return isDark ? '#FF24232E' : '#FFE6E8EC';
  }

  static borderSubtle(isDark: boolean): string {
    return isDark ? '#1FFFFFFF' : '#14000000';
  }

  static divider(isDark: boolean): string {
    return isDark ? '#1AFFFFFF' : '#14000000';
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
      if (lvl === uiMaterial.MaterialLevel.EXQUISITE) { return '旗舰级光感 (EXQUISITE)'; }
      if (lvl === uiMaterial.MaterialLevel.GENTLE) { return '均衡光感 (GENTLE)'; }
      return '流畅光感 (SMOOTH)';
    } catch {
      return '自适应光感';
    }
  }

  static tierLabel(): string {
    const tier = HarmonyDynamicLight.currentTier();
    if (tier === 'harmonyos7_immersive') {
      return `HarmonyOS 7 动态光感 · ${HarmonyDynamicLight.materialLevelLabel()}`;
    }
    if (tier === 'harmonyos6_hds_light') {
      return 'HarmonyOS 6 HDS 点光源光感（自动适配）';
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
    accentHex: string = '#9E7AF5',
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
    if (tier === 'harmonyos7_immersive') {
      try {
        const immersiveStyle = this.resolveImmersiveStyle();
        const tintColor = this.resolveImmersiveTint();
        const material = new uiMaterial.ImmersiveMaterial({
          style: immersiveStyle,
          materialColor: tintColor,
          colorInvert: this.role === 'bar' || this.role === 'pill',
          applyShadow: this.role !== 'pill',
          interactive: this.interactive,
          lightEffect: this.interactive ? { color: this.accentHex } : null
        });
        instance.systemMaterial(material);
        return;
      } catch {
        // 运行时动态光感构造异常时立即安全降级
      }
    }

    // HarmonyOS 6（API 20-25）点光源受光回退
    this.applyFallbackSurface(instance);
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
      return uiMaterial.ImmersiveStyle.THIN;
    }
    if (this.role === 'overlay') {
      return uiMaterial.ImmersiveStyle.THICK;
    }
    if (this.role === 'pill') {
      return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    }
    return uiMaterial.ImmersiveStyle.REGULAR;
  }

  private resolveImmersiveTint(): ResourceColor | undefined {
    if (this.role === 'card') {
      return this.isDark ? '#B81B1B22' : '#D9FFFFFF';
    }
    if (this.role === 'overlay') {
      return this.isDark ? '#D01D1C26' : '#E8FFFFFF';
    }
    return undefined;
  }

  private applyFallbackSurface(instance: CommonAttribute): void {
    if (this.role === 'bar') {
      instance.backgroundColor(HarmonyThemeColors.barFallback(this.isDark));
      instance.backgroundBlurStyle(BlurStyle.COMPONENT_THIN, {
        colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.DEFAULT
      });
      instance.border({
        width: 0.6,
        color: HarmonyThemeColors.borderSubtle(this.isDark),
        radius: this.cornerRadius
      });
      instance.shadow({
        radius: this.isDark ? 14 : 10,
        color: this.isDark ? '#30000000' : '#14000000',
        offsetY: 4
      });
      return;
    }
    if (this.role === 'overlay') {
      instance.backgroundColor(HarmonyThemeColors.overlayFallback(this.isDark));
      instance.backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, {
        colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
        adaptiveColor: AdaptiveColor.DEFAULT
      });
      instance.border({
        width: 0.6,
        color: HarmonyThemeColors.borderSubtle(this.isDark),
        radius: this.cornerRadius
      });
      return;
    }
    if (this.role === 'pill') {
      instance.backgroundColor(HarmonyThemeColors.chipFill(this.isDark));
      instance.border({
        width: 0.6,
        color: HarmonyThemeColors.borderSubtle(this.isDark),
        radius: this.cornerRadius
      });
      return;
    }
    // 普通内容卡片：低版本采用纯正不透明分层表面色 + 柔和阴影，避免浑浊半透明
    instance.backgroundColor(HarmonyThemeColors.card(this.isDark));
    instance.border({
      width: 0.5,
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
