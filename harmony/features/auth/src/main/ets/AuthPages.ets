import { common, Want } from '@kit.AbilityKit';
import {
  RustCoreBridge,
  MoviePilotRepository,
  NativeHuksStore,
  SavedServerEntry,
  CloudflareAccessOAuthManager
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptivePill,
  HarmonySheetHeader,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  GeneratedDesignTokens,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

interface LocaleOptionItem {
  code: string;
  label: string;
  shortLabel: string;
}

const LOCALE_OPTIONS: LocaleOptionItem[] = [
  { code: 'zh-CN', label: '简体中文', shortLabel: '简体' },
  { code: 'zh-TW', label: '繁體中文', shortLabel: '繁體' },
  { code: 'en-US', label: 'English', shortLabel: 'EN' }
];

function shortLocaleBadge(code: string): string {
  for (let i = 0; i < LOCALE_OPTIONS.length; i++) {
    if (LOCALE_OPTIONS[i].code === code) {
      return LOCALE_OPTIONS[i].shortLabel;
    }
  }
  return '中文';
}

/**
 * 鸿蒙连接服务页面（固定顶栏对齐 iOS 黄金截图 + 语言选择菜单 + 自签名 HTTPS 开关 + 历史服务删除）。
 */
@Component
export struct HarmonyServerConnectionPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_LOCALE) locale: string = 'zh-CN';
  @StorageLink(HarmonyAppearanceStore.KEY_ALLOW_SELF_SIGNED) allowSelfSigned: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) safeLeftVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP) safeRightVp: number = 0;
  @Prop savedServers: SavedServerEntry[] = [];
  @Prop canGoBack: boolean = false;
  @State private address: string = '';
  @State private errorText: string = '';
  @State private showLangSheet: boolean = false;
  @State private cfBusy: boolean = false;
  @State private cfAuthorized: boolean = false;
  @State private cfStatusText: string = '';
  onBack: () => void = () => {};
  onConnectSuccess: (normalizedUrl: string, allowSelfSigned: boolean) => void = () => {};
  onSelectSaved: (entry: SavedServerEntry) => void = () => {};
  onDeleteSaved: (entry: SavedServerEntry) => void = () => {};

  private isShortLandscape(): boolean {
    return HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp);
  }

  private sloganText(): string {
    if (this.locale === 'en-US') {
      return 'Your media universe, connected anywhere.';
    }
    return this.locale === 'zh-TW' ? '你的媒體世界，隨時連接。' : '你的媒体世界，随时连接。';
  }

  @Builder
  languageSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '选择界面语言',
        cancelText: '关闭',
        onCancel: () => { this.showLangSheet = false; }
      })
      Scroll() {
        Column({ space: 10 }) {
          ForEach(LOCALE_OPTIONS, (opt: LocaleOptionItem) => {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Row() {
                  Text(opt.label)
                    .fontSize(15)
                    .fontWeight(this.locale === opt.code ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.locale === opt.code ? this.accentHex : mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                  if (this.locale === opt.code) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(18)
                      .fontColor([this.accentHex])
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              this.locale = opt.code;
              NativeHuksStore.shared().saveAppearanceJson(HarmonyAppearanceStore.exportSnapshot()).catch(() => {});
              this.showLangSheet = false;
            })
          }, (opt: LocaleOptionItem) => opt.code)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }

  @Builder
  connectFormBodyBuilder() {
    Column({ space: this.isShortLandscape() ? 12 : 16 }) {
      CinematicPanel({ panelPadding: this.isShortLandscape() ? 14 : 16 }) {
        Column({ space: 12 }) {
          TextInput({ placeholder: 'MoviePilot 服务地址', text: this.address })
            .fontColor(mpPrimaryText(this.isDark))
            .placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(Color.Transparent)
            .onChange((val: string) => {
              this.address = val;
              this.errorText = '';
            })
            .onSubmit(() => this.tryConnect())

          Divider().color(HarmonyThemeColors.divider(this.isDark))

          Row({ space: 8 }) {
            Text('快捷前缀').fontSize(12).fontColor(mpSecondaryText(this.isDark))
            NativeAdaptivePill({
              title: 'https://',
              selected: this.address.startsWith('https://'),
              onTap: () => { this.address = 'https://' + this.address.replace(/^https?:\/\//, ''); }
            })
            NativeAdaptivePill({
              title: 'http://',
              selected: this.address.startsWith('http://'),
              onTap: () => { this.address = 'http://' + this.address.replace(/^https?:\/\//, ''); }
            })
          }
          .width('100%')

          Divider().color(HarmonyThemeColors.divider(this.isDark))

          Row() {
            Column({ space: 2 }) {
              Text('信任自签名 HTTPS 证书')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(mpPrimaryText(this.isDark))
              Text('局域网 NAS 自签证书无法通过系统校验时开启')
                .fontSize(11)
                .fontColor(mpSecondaryText(this.isDark))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.allowSelfSigned })
              .selectedColor(this.accentHex)
              .onChange((v: boolean) => {
                this.allowSelfSigned = v;
                MoviePilotRepository.shared().transport.setAllowSelfSigned(v);
              })
          }
          .width('100%')
        }
      }

      Text(this.errorText || '支持 HTTPS、局域网地址和部署子路径。')
        .fontSize(12)
        .fontColor(this.errorText ? GeneratedDesignTokens.semanticColor('danger', this.isDark) : mpSecondaryText(this.isDark))
        .width('100%')

      Button(this.locale === 'en-US' ? 'Connect →' : '连接 →')
        .width('100%')
        .height(this.isShortLandscape() ? 46 : 52)
        .borderRadius(this.isShortLandscape() ? 23 : 26)
        .backgroundColor(this.address.trim().length > 0 ? this.accentHex : (this.isDark ? '#28FFFFFF' : '#22000000'))
        .fontColor(Color.White)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .onClick(() => this.tryConnect())

      if (this.address.trim().length > 0) {
        CinematicPanel({ panelPadding: 14 }) {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.lock_shield'))
                .fontSize(18)
                .fontColor([this.cfAuthorized ? '#2FB36D' : this.accentHex])
              Column({ space: 2 }) {
                Text(
                  this.cfBusy
                    ? '正在进行 Cloudflare Access 认证...'
                    : (this.cfAuthorized ? '重新进行 Cloudflare Access 认证' : '通过 Cloudflare Access 认证')
                )
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(mpPrimaryText(this.isDark))
                Text(
                  this.cfStatusText ||
                  (this.cfAuthorized
                    ? '已获取同源网关凭据，不影响 MoviePilot 账号令牌'
                    : '若服务位于 Cloudflare Access 网关后可先完成 OAuth 授权')
                )
                  .fontSize(11)
                  .fontColor(this.cfAuthorized ? '#2FB36D' : mpSecondaryText(this.isDark))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.cfBusy) {
                LoadingProgress().width(18).height(18).color(this.accentHex)
              } else {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([mpSecondaryText(this.isDark)])
              }
            }
            .width('100%')
            .onClick(() => {
              if (!this.cfBusy) {
                this.authenticateCloudflareAccess();
              }
            })

            if (this.cfAuthorized && !this.cfBusy) {
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Text('清除 Cloudflare Access 授权')
                .fontSize(13)
                .fontColor(GeneratedDesignTokens.semanticColor('danger', this.isDark))
                .width('100%')
                .onClick(() => this.clearCloudflareAccess())
            }
          }
          .width('100%')
        }
      }

      if (this.savedServers.length > 0) {
        Text('已保存的服务')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(mpSecondaryText(this.isDark))
          .width('100%')
          .margin({ top: 6 })

        ForEach(this.savedServers, (entry: SavedServerEntry) => {
          CinematicPanel({ panelPadding: 14, interactive: true }) {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(entry.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                Text(entry.url)
                  .fontSize(12)
                  .fontColor(mpSecondaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .onClick(() => {
                const selfSigned = Boolean(entry.allowSelfSigned);
                this.allowSelfSigned = selfSigned;
                MoviePilotRepository.shared().transport.setAllowSelfSigned(selfSigned);
                this.onSelectSaved(entry);
              })

              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(15)
                  .fontColor(['#E84855'])
              }
              .width(34)
              .height(34)
              .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
              .accessibilityText(`删除服务 ${entry.name}`)
              .onClick(() => this.onDeleteSaved(entry))

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(15)
                .fontColor([mpSecondaryText(this.isDark)])
                .onClick(() => {
                  const selfSigned = Boolean(entry.allowSelfSigned);
                  this.allowSelfSigned = selfSigned;
                  MoviePilotRepository.shared().transport.setAllowSelfSigned(selfSigned);
                  this.onSelectSaved(entry);
                })
            }
            .width('100%')
          }
        }, (entry: SavedServerEntry) => `${entry.url}_${entry.lastUsedMs}`)
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 460 })
  }

  build() {
    Column() {
      // 固定贴顶导航栏（动态适配状态栏与左右挖孔安全区，支持切换服务态返回）
      Row() {
        if (this.canGoBack) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(14)
              .fontColor([mpPrimaryText(this.isDark)])
            Text(this.locale === 'en-US' ? 'Back' : (this.locale === 'zh-TW' ? '返回' : '返回'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpPrimaryText(this.isDark))
          }
          .width(64)
          .height(34)
          .justifyContent(FlexAlign.Center)
          .borderRadius(17)
          .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 17, this.accentHex, true, this.dynamicLight))
          .hoverEffect(HoverEffect.Highlight)
          .accessibilityText('返回上一页')
          .onClick(() => this.onBack())
        } else {
          Blank().width(64)
        }

        Text(this.locale === 'en-US' ? 'Connect' : (this.locale === 'zh-TW' ? '連接服務' : '连接服务'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.worldclock'))
            .fontSize(13)
            .fontColor([mpPrimaryText(this.isDark)])
          Text(shortLocaleBadge(this.locale))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(mpPrimaryText(this.isDark))
        }
        .width(64)
        .height(34)
        .justifyContent(FlexAlign.Center)
        .borderRadius(17)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 17, this.accentHex, true, this.dynamicLight))
        .onClick(() => { this.showLangSheet = true; })
      }
      .width('100%')
      .padding({
        left: 16 + this.safeLeftVp,
        right: 16 + this.safeRightVp,
        top: Math.max(10, this.safeTopVp + 4),
        bottom: this.isShortLandscape() ? 4 : 8
      })

      if (this.isShortLandscape()) {
        Row({ space: 24 }) {
          Column({ space: 8 }) {
            Image($r('app.media.brandmark'))
              .width(66)
              .height(66)
              .borderRadius(18)
              .shadow({ radius: 18, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '55') })
            Text('MoviePilot')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))
            Text(this.sloganText())
              .fontSize(12.5)
              .fontColor(mpSecondaryText(this.isDark))
              .textAlign(TextAlign.Center)
          }
          .width(228)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Scroll() {
            Column() {
              this.connectFormBodyBuilder()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 6, bottom: Math.max(20, this.safeBottomVp + 12) })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20 + this.safeLeftVp, right: 20 + this.safeRightVp })
      } else {
        Scroll() {
          Column({ space: 18 }) {
            Column({ space: 10 }) {
              Image($r('app.media.brandmark'))
                .width(86)
                .height(86)
                .borderRadius(22)
                .shadow({ radius: 22, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '55') })
              Text('MoviePilot')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark))
              Text(this.sloganText())
                .fontSize(14)
                .fontColor(mpSecondaryText(this.isDark))
            }
            .margin({ top: 14, bottom: 8 })

            this.connectFormBodyBuilder()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({
            left: 20 + this.safeLeftVp,
            right: 20 + this.safeRightVp,
            bottom: Math.max(32, this.safeBottomVp + 20)
          })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      }

      Blank().width(0).height(0).bindSheet($$this.showLangSheet, this.languageSheetBuilder(), {
        detents: (this.windowHeightVp > 0 && this.windowHeightVp < 500)
          ? [SheetSize.LARGE]
          : [SheetSize.FIT_CONTENT, SheetSize.MEDIUM],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_THIN,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
    }
    .width('100%')
    .height('100%')
  }

  private tryConnect(): void {
    try {
      const normalized = RustCoreBridge.normalizeServerAddress(this.address);
      MoviePilotRepository.shared().transport.setAllowSelfSigned(this.allowSelfSigned);
      CloudflareAccessOAuthManager.shared().hydrateOrigin(normalized).catch(() => {});
      this.onConnectSuccess(normalized, this.allowSelfSigned);
    } catch (e) {
      this.errorText = (e as Error).message;
    }
  }

  private async authenticateCloudflareAccess(): Promise<void> {
    this.cfBusy = true;
    this.errorText = '';
    this.cfStatusText = '';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await CloudflareAccessOAuthManager.shared().authenticate(
        this.address,
        this.allowSelfSigned,
        (authorizeUrl: string) => {
          const want: Want = {
            action: 'ohos.want.action.viewData',
            entities: ['entity.system.browsable'],
            uri: authorizeUrl
          };
          ctx.startAbility(want).catch(() => {});
        }
      );
      this.cfAuthorized = true;
      this.cfStatusText = 'Cloudflare Access 认证成功';
      this.tryConnect();
    } catch (e) {
      this.errorText = (e as Error).message || 'Cloudflare Access 认证失败';
    }
    this.cfBusy = false;
  }

  private async clearCloudflareAccess(): Promise<void> {
    await CloudflareAccessOAuthManager.shared().clearSession(this.address);
    this.cfAuthorized = false;
    this.cfStatusText = '已清除 Cloudflare Access 授权';
  }
}

/**
 * 鸿蒙账号密码 / OTP 登录页面（固定贴顶导航栏对齐 iOS `native-v2-02-login.jpg` + 浅色高对比服务器胶囊 + 密码显隐切换 + HUKS 安全记住密码）。
 */
@Component
export struct HarmonyLoginPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_LOCALE) locale: string = 'zh-CN';
  @StorageLink(HarmonyAppearanceStore.KEY_ALLOW_SELF_SIGNED) allowSelfSigned: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) safeLeftVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP) safeRightVp: number = 0;
  @Prop @Watch('onServerUrlChanged') serverUrl: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private showPassword: boolean = false;
  @State private otpCode: string = '';
  @State private showOtp: boolean = false;
  @State private keepLogin: boolean = true;
  @State private rememberCreds: boolean = false;
  @State private showLangSheet: boolean = false;
  @State private notice: string = '密码仅在本机加密安全保存，验证码不会保存。';
  @State private isError: boolean = false;
  @State private loading: boolean = false;
  @State private passkeySupported: boolean = false;
  @State private passkeyLoading: boolean = false;
  @State private cfBusy: boolean = false;
  @State private cfAuthorized: boolean = false;
  @State private cfChallengeDetected: boolean = false;
  onSwitchServer: () => void = () => {};
  onLoginSuccess: (token: string, userName: string, isSuperuser: boolean, avatar: string, keepLogin: boolean, userLevel?: number) => void = () => {};

  aboutToAppear(): void {
    this.hydrateSavedCredentials();
  }

  onServerUrlChanged(): void {
    this.passkeySupported = false;
    this.cfChallengeDetected = false;
    this.hydrateSavedCredentials();
  }

  private async hydrateSavedCredentials(): Promise<void> {
    if (!this.serverUrl) { return; }
    const targetUrl = this.serverUrl;
    MoviePilotRepository.shared().transport.setAllowSelfSigned(this.allowSelfSigned);
    MoviePilotRepository.shared().probePasskeyEnabled(targetUrl).then((enabled: boolean) => {
      if (this.serverUrl === targetUrl) {
        this.passkeySupported = enabled;
      }
    }).catch(() => {});
    try {
      await CloudflareAccessOAuthManager.shared().hydrateOrigin(this.serverUrl);
      this.cfAuthorized = CloudflareAccessOAuthManager.shared().hasSession(this.serverUrl);
    } catch {
      // ignore cf hydrate error
    }
    try {
      const cred = await NativeHuksStore.shared().loadCredentials(this.serverUrl);
      if (cred) {
        this.username = cred.username;
        this.password = cred.password;
        this.rememberCreds = true;
      }
    } catch {
      // ignore credential load error
    }
  }

  private async submitLogin(): Promise<void> {
    if (this.loading || this.passkeyLoading) {
      return;
    }
    if (!this.username.trim() || !this.password) {
      this.notice = '请输入用户名和密码';
      this.isError = true;
      return;
    }
    this.loading = true;
    this.isError = false;
    try {
      MoviePilotRepository.shared().transport.setAllowSelfSigned(this.allowSelfSigned);
      const res = await MoviePilotRepository.shared().login(this.serverUrl, this.username, this.password, this.otpCode);
      if (res.success) {
        if (this.rememberCreds) {
          await NativeHuksStore.shared().saveCredentials(this.serverUrl, this.username.trim(), this.password);
        } else {
          await NativeHuksStore.shared().clearCredentials(this.serverUrl);
        }
        this.onLoginSuccess(res.token, res.userName, res.isSuperuser, res.avatar, this.keepLogin, res.userLevel ?? 1);
      } else {
        this.showOtp = res.requiresOtp || this.showOtp;
        if (res.message && res.message.includes('Cloudflare Access')) {
          this.cfChallengeDetected = true;
        }
        this.notice = res.message || '登录失败';
        this.isError = true;
      }
    } catch {
      this.notice = '网络请求失败，请检查服务地址或局域网连通性';
      this.isError = true;
    }
    this.loading = false;
  }

  private async submitPasskeyLogin(): Promise<void> {
    if (!this.serverUrl || this.loading || this.passkeyLoading || this.cfBusy) {
      return;
    }
    this.passkeyLoading = true;
    this.isError = false;
    try {
      MoviePilotRepository.shared().transport.setAllowSelfSigned(this.allowSelfSigned);
      const ctx = getContext(this) as common.UIAbilityContext;
      const res = await MoviePilotRepository.shared().loginWithPasskey(
        this.serverUrl,
        this.username,
        (authorizeUrl: string) => {
          const want: Want = {
            action: 'ohos.want.action.viewData',
            entities: ['entity.system.browsable'],
            uri: authorizeUrl
          };
          ctx.startAbility(want).catch(() => {});
        }
      );
      if (res.success) {
        this.onLoginSuccess(res.token, res.userName, res.isSuperuser, res.avatar, this.keepLogin, res.userLevel ?? 1);
      } else if (!res.canceled) {
        if (res.message && res.message.includes('Cloudflare Access')) {
          this.cfChallengeDetected = true;
        }
        this.notice = res.message || '未能完成通行密钥验证，请重新尝试。';
        this.isError = true;
      }
    } catch {
      this.notice = '未能完成通行密钥验证，请重新尝试。';
      this.isError = true;
    }
    this.passkeyLoading = false;
  }

  private isShortLandscape(): boolean {
    return HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp);
  }

  @Builder
  languageSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '选择界面语言',
        cancelText: '关闭',
        onCancel: () => { this.showLangSheet = false; }
      })
      Scroll() {
        Column({ space: 10 }) {
          ForEach(LOCALE_OPTIONS, (opt: LocaleOptionItem) => {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Row() {
                  Text(opt.label)
                    .fontSize(15)
                    .fontWeight(this.locale === opt.code ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.locale === opt.code ? this.accentHex : mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                  if (this.locale === opt.code) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(18)
                      .fontColor([this.accentHex])
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              this.locale = opt.code;
              NativeHuksStore.shared().saveAppearanceJson(HarmonyAppearanceStore.exportSnapshot()).catch(() => {});
              this.showLangSheet = false;
            })
          }, (opt: LocaleOptionItem) => opt.code)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }

  @Builder
  serverPillBuilder() {
    Text(`● ${this.serverUrl}`)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isDark ? '#75E6A3' : '#18794E')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.isDark ? '#1EFFFFFF' : '#1418794E')
      .border({ width: 0.6, color: this.isDark ? '#33FFFFFF' : '#3318794E', radius: 16 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => this.onSwitchServer())
  }

  @Builder
  loginFormBodyBuilder() {
    Column({ space: this.isShortLandscape() ? 12 : 16 }) {
      CinematicPanel({ panelPadding: 14 }) {
        Column({ space: 10 }) {
          TextInput({ placeholder: this.locale === 'en-US' ? 'Username' : '用户名', text: this.username })
            .fontColor(mpPrimaryText(this.isDark))
            .placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => { this.username = v; })

          Divider().color(HarmonyThemeColors.divider(this.isDark))

          Row({ space: 6 }) {
            TextInput({ placeholder: this.locale === 'en-US' ? 'Password' : '密码', text: this.password })
              .type(this.showPassword ? InputType.Normal : InputType.Password)
              .showPasswordIcon(false)
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .onChange((v: string) => { this.password = v; })
              .onSubmit(() => this.submitLogin())

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r(this.showPassword ? 'sys.symbol.eye_slash' : 'sys.symbol.eye'))
                .fontSize(18)
                .fontColor([mpSecondaryText(this.isDark)])
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .accessibilityText(this.showPassword ? '隐藏密码' : '显示密码')
            .onClick(() => { this.showPassword = !this.showPassword; })
          }
          .width('100%')

          if (this.showOtp) {
            Divider().color(HarmonyThemeColors.divider(this.isDark))
            TextInput({ placeholder: '6 位动态验证码 (OTP)', text: this.otpCode })
              .type(InputType.Number)
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.otpCode = v; })
              .onSubmit(() => this.submitLogin())
          }
        }
      }

      CinematicPanel({ panelPadding: 14 }) {
        Column({ space: 8 }) {
          Row() {
            Text('保持登录').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.keepLogin })
              .selectedColor(this.accentHex)
              .onChange((v: boolean) => { this.keepLogin = v; })
          }.width('100%')

          Divider().color(HarmonyThemeColors.divider(this.isDark))

          Row() {
            Text('记住账号密码').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.rememberCreds })
              .selectedColor(this.accentHex)
              .onChange((v: boolean) => { this.rememberCreds = v; })
          }.width('100%')
        }
      }

      Text(this.notice)
        .fontSize(12)
        .fontColor(this.isError ? GeneratedDesignTokens.semanticColor('danger', this.isDark) : mpSecondaryText(this.isDark))
        .width('100%')

      if (this.isShortLandscape() && this.passkeySupported) {
        Row({ space: 10 }) {
          this.primaryLoginButtonBuilder()
          this.passkeyButtonBuilder()
        }
        .width('100%')
      } else {
        Column({ space: 10 }) {
          this.primaryLoginButtonBuilder()
          if (this.passkeySupported) {
            this.passkeyButtonBuilder()
          }
        }
        .width('100%')
      }

      if (!this.cfAuthorized && !this.cfChallengeDetected && !this.cfBusy) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(14)
            .fontColor([this.accentHex])
          Text('通过 Cloudflare Access 认证')
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(mpSecondaryText(this.isDark))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([mpSecondaryText(this.isDark)])
        }
        .height(36)
        .padding({ left: 14, right: 14 })
        .borderRadius(18)
        .backgroundColor(this.isDark ? '#18FFFFFF' : '#0F000000')
        .border({ width: 0.6, color: this.isDark ? '#2BFFFFFF' : '#1E000000', radius: 18 })
        .onClick(() => {
          if (!this.loading && !this.passkeyLoading && !this.cfBusy) {
            this.authenticateCloudflareAccess();
          }
        })
      } else {
        CinematicPanel({ panelPadding: 14 }) {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.lock_shield'))
                .fontSize(18)
                .fontColor([this.cfAuthorized ? '#2FB36D' : this.accentHex])
              Column({ space: 2 }) {
                Text(
                  this.cfBusy
                    ? '正在进行 Cloudflare Access 认证...'
                    : (this.cfAuthorized ? '重新进行 Cloudflare Access 认证' : '通过 Cloudflare Access 认证')
                )
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(mpPrimaryText(this.isDark))
                Text(
                  this.cfAuthorized
                    ? '已获取同源网关凭据，不影响 MoviePilot 账号令牌'
                    : '当前服务位于 Cloudflare Access 保护后，请先完成网关授权'
                )
                  .fontSize(11)
                  .fontColor(this.cfAuthorized ? '#2FB36D' : mpSecondaryText(this.isDark))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (this.cfBusy) {
                LoadingProgress().width(18).height(18).color(this.accentHex)
              } else {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([mpSecondaryText(this.isDark)])
              }
            }
            .width('100%')
            .onClick(() => {
              if (!this.cfBusy) {
                this.authenticateCloudflareAccess();
              }
            })

            if (this.cfAuthorized && !this.cfBusy) {
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Text('清除 Cloudflare Access 授权')
                .fontSize(13)
                .fontColor(GeneratedDesignTokens.semanticColor('danger', this.isDark))
                .width('100%')
                .onClick(() => this.clearCloudflareAccess())
            }
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: 460 })
  }

  @Builder
  private primaryLoginButtonBuilder() {
    Button() {
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress().width(18).height(18).color(Color.White)
        }
        Text(this.loading ? '正在登录...' : (this.locale === 'en-US' ? 'Sign In' : '登录'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(
            (this.username.trim().length > 0 && this.password.length > 0 && !this.loading && !this.passkeyLoading)
              ? Color.White
              : mpSecondaryText(this.isDark)
          )
      }
      .justifyContent(FlexAlign.Center)
    }
    .layoutWeight(this.isShortLandscape() && this.passkeySupported ? 1 : 0)
    .width(this.isShortLandscape() && this.passkeySupported ? undefined : '100%')
    .height(this.isShortLandscape() ? 46 : 52)
    .borderRadius(this.isShortLandscape() ? 23 : 26)
    .backgroundColor(
      (this.username.trim().length > 0 && this.password.length > 0 && !this.loading && !this.passkeyLoading)
        ? this.accentHex
        : (this.isDark ? '#24FFFFFF' : '#16000000')
    )
    .enabled(!this.loading && !this.passkeyLoading && this.username.trim().length > 0 && this.password.length > 0)
    .onClick(() => this.submitLogin())
  }

  @Builder
  private passkeyButtonBuilder() {
    Button() {
      Row({ space: 8 }) {
        if (this.passkeyLoading) {
          LoadingProgress().width(18).height(18).color(this.accentHex)
        } else {
          SymbolGlyph($r('sys.symbol.lock_shield'))
            .fontSize(17)
            .fontColor([(!this.loading && !this.cfBusy) ? this.accentHex : mpSecondaryText(this.isDark)])
        }
        Text(this.locale === 'en-US' ? 'Sign in with Passkey' : '使用通行密钥登录')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor((!this.loading && !this.cfBusy) ? mpPrimaryText(this.isDark) : mpSecondaryText(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .justifyContent(FlexAlign.Center)
      .padding({ left: 12, right: 12 })
    }
    .layoutWeight(this.isShortLandscape() && this.passkeySupported ? 1 : 0)
    .width(this.isShortLandscape() && this.passkeySupported ? undefined : '100%')
    .height(this.isShortLandscape() ? 46 : 50)
    .borderRadius(this.isShortLandscape() ? 23 : 25)
    .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '24' : '18'))
    .border({
      width: 0.85,
      color: HarmonyAppearanceStore.withAlpha(this.accentHex, (!this.loading && !this.cfBusy) ? '6B' : '33'),
      radius: this.isShortLandscape() ? 23 : 25
    })
    .enabled(!this.loading && !this.passkeyLoading && !this.cfBusy)
    .onClick(() => this.submitPasskeyLogin())
  }

  private async authenticateCloudflareAccess(): Promise<void> {
    if (!this.serverUrl) { return; }
    this.cfBusy = true;
    this.isError = false;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await CloudflareAccessOAuthManager.shared().authenticate(
        this.serverUrl,
        this.allowSelfSigned,
        (authorizeUrl: string) => {
          const want: Want = {
            action: 'ohos.want.action.viewData',
            entities: ['entity.system.browsable'],
            uri: authorizeUrl
          };
          ctx.startAbility(want).catch(() => {});
        }
      );
      this.cfAuthorized = true;
      this.cfChallengeDetected = false;
      this.notice = 'Cloudflare Access 认证成功，请继续登录';
      this.isError = false;
      MoviePilotRepository.shared().probePasskeyEnabled(this.serverUrl).then((enabled: boolean) => {
        this.passkeySupported = enabled;
      }).catch(() => {});
    } catch (e) {
      this.notice = (e as Error).message || 'Cloudflare Access 认证失败';
      this.isError = true;
    }
    this.cfBusy = false;
  }

  private async clearCloudflareAccess(): Promise<void> {
    if (!this.serverUrl) { return; }
    await CloudflareAccessOAuthManager.shared().clearSession(this.serverUrl);
    this.cfAuthorized = false;
    this.notice = '已清除当前服务的 Cloudflare Access 授权';
    this.isError = false;
  }

  build() {
    Column() {
      // 固定贴顶导航栏（动态避让顶部状态栏与左右摄像头挖孔）
      Row() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(14)
            .fontColor([mpPrimaryText(this.isDark)])
          Text(this.locale === 'en-US' ? 'Switch' : '切换')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(mpPrimaryText(this.isDark))
        }
        .width(66)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(18)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 18, this.accentHex, true, this.dynamicLight))
        .accessibilityText('切换服务地址')
        .onClick(() => this.onSwitchServer())

        Text(this.locale === 'en-US' ? 'Sign In' : (this.locale === 'zh-TW' ? '登錄' : '登录'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.worldclock'))
            .fontSize(13)
            .fontColor([mpPrimaryText(this.isDark)])
          Text(shortLocaleBadge(this.locale))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(mpPrimaryText(this.isDark))
        }
        .width(66)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(18)
        .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 18, this.accentHex, true, this.dynamicLight))
        .accessibilityText('切换界面语言')
        .onClick(() => { this.showLangSheet = true; })
      }
      .width('100%')
      .padding({
        left: 16 + this.safeLeftVp,
        right: 16 + this.safeRightVp,
        top: Math.max(10, this.safeTopVp + 4),
        bottom: this.isShortLandscape() ? 4 : 8
      })

      if (this.isShortLandscape()) {
        Row({ space: 24 }) {
          Column({ space: 8 }) {
            Image($r('app.media.brandmark'))
              .width(66)
              .height(66)
              .borderRadius(18)
              .shadow({ radius: 18, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '55') })

            Text('MoviePilot')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))

            this.serverPillBuilder()
          }
          .width(228)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Scroll() {
            Column() {
              this.loginFormBodyBuilder()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 6, bottom: Math.max(20, this.safeBottomVp + 12) })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20 + this.safeLeftVp, right: 20 + this.safeRightVp })
      } else {
        Scroll() {
          Column({ space: 16 }) {
            Image($r('app.media.brandmark'))
              .width(82)
              .height(82)
              .borderRadius(20)
              .margin({ top: 14 })
              .shadow({ radius: 20, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '55') })

            Text('MoviePilot')
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))

            this.serverPillBuilder()

            this.loginFormBodyBuilder()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({
            left: 20 + this.safeLeftVp,
            right: 20 + this.safeRightVp,
            bottom: Math.max(32, this.safeBottomVp + 20)
          })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      }

      Blank().width(0).height(0).bindSheet($$this.showLangSheet, this.languageSheetBuilder(), {
        detents: (this.windowHeightVp > 0 && this.windowHeightVp < 500)
          ? [SheetSize.LARGE]
          : [SheetSize.FIT_CONTENT, SheetSize.MEDIUM],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_THIN,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
    }
    .width('100%')
    .height('100%')
  }
}
