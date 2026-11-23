import {
  RustCoreBridge,
  MoviePilotRepository,
  SavedServerEntry
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptivePill,
  HarmonyAppearanceStore,
  GeneratedDesignTokens,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

/**
 * 鸿蒙连接服务页面（1:1 复刻 iOS 黄金截图 `native-v2-01-connection.jpg` + 原生 pointLight 玻璃质感）。
 */
@Component
export struct HarmonyServerConnectionPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop savedServers: SavedServerEntry[] = [];
  @State private address: string = '';
  @State private errorText: string = '';
  onConnectSuccess: (normalizedUrl: string) => void = () => {};
  onSelectSaved: (entry: SavedServerEntry) => void = () => {};

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Text('连接服务')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(mpPrimaryText(this.isDark))
          .margin({ top: 48 })

        Column({ space: 10 }) {
          Image($r('app.media.brandmark'))
            .width(88)
            .height(88)
            .borderRadius(22)
            .shadow({ radius: 24, color: this.accentHex })
          Text('MoviePilot')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
          Text('你的媒体世界，随时连接。')
            .fontSize(14)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .margin({ top: 18, bottom: 12 })

        CinematicPanel({ panelPadding: 16 }) {
          Column({ space: 12 }) {
            TextInput({ placeholder: 'MoviePilot 服务地址', text: this.address })
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((val: string) => {
                this.address = val;
                this.errorText = '';
              })
            Divider().color(this.isDark ? '#22FFFFFF' : '#18000000')
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
          }
        }

        Text(this.errorText || '支持 HTTPS、局域网地址和部署子路径。')
          .fontSize(12)
          .fontColor(this.errorText ? GeneratedDesignTokens.semanticColor('danger', this.isDark) : mpSecondaryText(this.isDark))
          .width('100%')

        Button('连接 →')
          .width('100%')
          .height(52)
          .borderRadius(26)
          .backgroundColor(this.address.trim().length > 0 ? this.accentHex : (this.isDark ? '#28FFFFFF' : '#22000000'))
          .fontColor(Color.White)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            try {
              const normalized = RustCoreBridge.normalizeServerAddress(this.address);
              this.onConnectSuccess(normalized);
            } catch (e) {
              this.errorText = (e as Error).message;
            }
          })

        if (this.savedServers.length > 0) {
          Text('已保存的服务')
            .fontSize(14)
            .fontColor(mpSecondaryText(this.isDark))
            .width('100%')
            .margin({ top: 12 })
          ForEach(this.savedServers, (entry: SavedServerEntry) => {
            CinematicPanel({ panelPadding: 14 }) {
              Row() {
                Column({ space: 2 }) {
                  Text(entry.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text(entry.url).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('›').fontSize(20).fontColor(mpSecondaryText(this.isDark))
              }
              .width('100%')
              .onClick(() => this.onSelectSaved(entry))
            }
          })
        }
      }
      .padding({ left: 20, right: 20, bottom: 40 })
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙账号密码 / OTP 登录页面（真实对接 MoviePilot V3 `/api/v1/login/access-token` 与 HUKS 安全存储）。 */
@Component
export struct HarmonyLoginPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop serverUrl: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private otpCode: string = '';
  @State private showOtp: boolean = false;
  @State private keepLogin: boolean = true;
  @State private rememberCreds: boolean = false;
  @State private notice: string = '密码仅在本机加密安全保存，验证码不会保存。';
  @State private isError: boolean = false;
  @State private loading: boolean = false;
  onSwitchServer: () => void = () => {};
  onLoginSuccess: (token: string, userName: string, isSuperuser: boolean, avatar: string) => void = () => {};

  private async submitLogin(): Promise<void> {
    if (!this.username.trim() || !this.password) {
      this.notice = '请输入用户名和密码';
      this.isError = true;
      return;
    }
    this.loading = true;
    this.isError = false;
    try {
      const res = await MoviePilotRepository.shared().login(this.serverUrl, this.username, this.password, this.otpCode);
      if (res.success) {
        this.onLoginSuccess(res.token, res.userName, res.isSuperuser, res.avatar);
      } else {
        this.showOtp = res.requiresOtp || this.showOtp;
        this.notice = res.message || '登录失败';
        this.isError = true;
      }
    } catch {
      this.notice = '网络请求失败，请检查服务地址或局域网连通性';
      this.isError = true;
    }
    this.loading = false;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('切换')
            .fontSize(14)
            .fontColor(mpPrimaryText(this.isDark))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor('#22FFFFFF')
            .onClick(() => this.onSwitchServer())
          Blank()
          Text('登录').fontSize(17).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
          Blank()
          Text('中文').fontSize(14).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .margin({ top: 46 })

        Image($r('app.media.brandmark')).width(82).height(82).borderRadius(20).shadow({ radius: 20, color: this.accentHex })
        Text('MoviePilot').fontSize(26).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
        Text(`● ${this.serverUrl}`)
          .fontSize(12)
          .fontColor('#75E6A3')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(16)
          .backgroundColor('#1EFFFFFF')
          .border({ width: 0.6, color: '#33FFFFFF', radius: 16 })
          .onClick(() => this.onSwitchServer())

        CinematicPanel({ panelPadding: 14 }) {
          Column({ space: 10 }) {
            TextInput({ placeholder: '用户名', text: this.username })
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.username = v; })
            Divider().color(this.isDark ? '#20FFFFFF' : '#18000000')
            TextInput({ placeholder: '密码', text: this.password })
              .type(InputType.Password)
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.password = v; })
            if (this.showOtp) {
              Divider().color(this.isDark ? '#20FFFFFF' : '#18000000')
              TextInput({ placeholder: '6 位动态验证码 (OTP)', text: this.otpCode })
                .fontColor(mpPrimaryText(this.isDark))
                .placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(Color.Transparent)
                .onChange((v: string) => { this.otpCode = v; })
            }
          }
        }

        CinematicPanel({ panelPadding: 14 }) {
          Column({ space: 8 }) {
            Row() {
              Text('保持登录').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.keepLogin }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.keepLogin = v; })
            }.width('100%')
            Divider().color(this.isDark ? '#20FFFFFF' : '#18000000')
            Row() {
              Text('记住账号密码').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.rememberCreds }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.rememberCreds = v; })
            }.width('100%')
          }
        }

        Text(this.notice)
          .fontSize(12)
          .fontColor(this.isError ? GeneratedDesignTokens.semanticColor('danger', this.isDark) : mpSecondaryText(this.isDark))
          .width('100%')

        Button(this.loading ? '正在登录...' : '登录 →')
          .width('100%')
          .height(52)
          .borderRadius(26)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.submitLogin())
      }
      .padding({ left: 20, right: 20, bottom: 40 })
    }
    .width('100%')
    .height('100%')
  }
}
