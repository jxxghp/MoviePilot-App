import { RustCoreBridge } from '../../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';
import { NativeRcpTransport } from '../../../../commons/core_rust_bridge/src/main/ets/network/NativeRcpTransport';
import { SavedServerEntry } from '../../../../commons/core_rust_bridge/src/main/ets/security/NativeHuksStore';
import { CinematicPanel, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { HarmonyAppearanceStore } from '../../../../commons/design_system/src/main/ets/store/AppearanceStore';
import { GeneratedDesignTokens } from '../../../../commons/design_system/src/main/ets/tokens/GeneratedTokens';

/**
 * 鸿蒙连接服务页面（1:1 复刻 iOS 黄金截图 `native-v2-01-connection.jpg` + 原生 pointLight 玻璃质感）。
 */
@Component
export struct HarmonyServerConnectionPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
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
          .fontColor(this.isDark ? Color.White : '#1C1A24')
          .margin({ top: 44 })

        Column({ space: 8 }) {
          Image($r('app.media.brandmark'))
            .width(84)
            .height(84)
            .borderRadius(22)
            .shadow({ radius: 24, color: this.accentHex })
          Text('MoviePilot')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isDark ? Color.White : '#1C1A24')
          Text('你的媒体世界，随时连接。')
            .fontSize(14)
            .fontColor(this.isDark ? '#B8FFFFFF' : '#661C1A24')
        }
        .margin({ top: 14, bottom: 10 })

        CinematicPanel({ panelPadding: 16 }) {
          Column({ space: 12 }) {
            TextInput({ placeholder: 'MoviePilot 服务地址', text: this.address })
              .fontColor(this.isDark ? Color.White : '#1C1A24')
              .placeholderColor('#88FFFFFF')
              .backgroundColor(Color.Transparent)
              .onChange((val: string) => {
                this.address = val;
                this.errorText = '';
              })
            Divider().color('#22FFFFFF')
            Row({ space: 8 }) {
              Text('快捷前缀').fontSize(12).fontColor('#88FFFFFF')
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
          .fontColor(this.errorText ? GeneratedDesignTokens.semanticColor('danger', this.isDark) : '#88FFFFFF')
          .width('100%')

        Button('连接 →')
          .width('100%')
          .height(52)
          .borderRadius(26)
          .backgroundColor(this.address.trim().length > 0 ? this.accentHex : '#22FFFFFF')
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
            .fontColor('#B8FFFFFF')
            .width('100%')
            .margin({ top: 12 })
          ForEach(this.savedServers, (entry: SavedServerEntry) => {
            CinematicPanel({ panelPadding: 14 }) {
              Row() {
                Column({ space: 2 }) {
                  Text(entry.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White)
                  Text(entry.url).fontSize(12).fontColor('#99FFFFFF')
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('›').fontSize(20).fontColor('#88FFFFFF')
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

/** 鸿蒙账号密码 / OTP 登录页面（对接 `@kit.RemoteCommunicationKit` rcp 与 HUKS 安全存储）。 */
@Component
export struct HarmonyLoginPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop serverUrl: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private otpCode: string = '';
  @State private showOtp: boolean = false;
  @State private keepLogin: boolean = true;
  @State private rememberCreds: boolean = false;
  @State private notice: string = '密码仅在本机 HUKS 安全保存，验证码不会保存。';
  @State private loading: boolean = false;
  private transport: NativeRcpTransport = new NativeRcpTransport();
  onSwitchServer: () => void = () => {};
  onLoginSuccess: (token: string, userName: string, isSuperuser: boolean) => void = () => {};

  private async submitLogin(): Promise<void> {
    if (!this.username.trim() || !this.password) { return; }
    this.loading = true;
    try {
      const url = RustCoreBridge.buildV3EndpointUrl(this.serverUrl, ['login', 'access-token']);
      const body = `username=${encodeURIComponent(this.username.trim())}&password=${encodeURIComponent(this.password)}&otp_password=${encodeURIComponent(this.otpCode.trim())}`;
      const resp = await this.transport.execute(url, 'POST', '', body, 'application/x-www-form-urlencoded');
      if (resp.status === 401) {
        if (resp.body.includes('mfa_methods')) {
          this.showOtp = true;
          this.notice = '请输入 6 位动态验证码 (OTP)';
        } else {
          this.notice = '用户名、密码或验证码错误';
        }
      } else if (resp.status >= 200 && resp.status < 300) {
        const parsed = JSON.parse(resp.body) as Record<string, Object>;
        const token = String(parsed['access_token'] ?? '');
        const userName = String(parsed['user_name'] ?? this.username.trim());
        const isSu = Boolean(parsed['super_user'] ?? true);
        if (token.length > 0) {
          this.onLoginSuccess(token, userName, isSu);
        }
      } else {
        this.notice = `登录失败（HTTP ${resp.status}）`;
      }
    } catch {
      this.notice = '网络请求失败，请检查服务地址或局域网连通性';
    }
    this.loading = false;
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row() {
          Text('切换').fontSize(14).fontColor(Color.White).onClick(() => this.onSwitchServer())
          Blank()
          Text('登录').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
          Blank()
          Text('中文').fontSize(14).fontColor('#B8FFFFFF')
        }
        .width('100%')
        .margin({ top: 44 })

        Image($r('app.media.brandmark')).width(80).height(80).borderRadius(20)
        Text('MoviePilot').fontSize(26).fontWeight(FontWeight.Bold).fontColor(Color.White)
        Text(`● ${this.serverUrl}`)
          .fontSize(12)
          .fontColor('#75E6A3')
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(16)
          .backgroundColor('#18FFFFFF')
          .onClick(() => this.onSwitchServer())

        CinematicPanel({ panelPadding: 14 }) {
          Column({ space: 10 }) {
            TextInput({ placeholder: '用户名', text: this.username })
              .fontColor(Color.White).placeholderColor('#88FFFFFF').backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.username = v; })
            Divider().color('#20FFFFFF')
            TextInput({ placeholder: '密码', text: this.password })
              .type(InputType.Password)
              .fontColor(Color.White).placeholderColor('#88FFFFFF').backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.password = v; })
            if (this.showOtp) {
              Divider().color('#20FFFFFF')
              TextInput({ placeholder: '6 位动态验证码 (OTP)', text: this.otpCode })
                .fontColor(Color.White).placeholderColor('#88FFFFFF').backgroundColor(Color.Transparent)
                .onChange((v: string) => { this.otpCode = v; })
            }
          }
        }

        CinematicPanel({ panelPadding: 14 }) {
          Column({ space: 8 }) {
            Row() {
              Text('保持登录').fontSize(15).fontColor(Color.White).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.keepLogin }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.keepLogin = v; })
            }.width('100%')
            Divider().color('#20FFFFFF')
            Row() {
              Text('记住账号密码').fontSize(15).fontColor(Color.White).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.rememberCreds }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.rememberCreds = v; })
            }.width('100%')
          }
        }

        Text(this.notice).fontSize(12).fontColor('#A8FFFFFF').width('100%')

        Button(this.loading ? '正在登录...' : '登录 →')
          .width('100%')
          .height(52)
          .borderRadius(26)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White)
          .fontSize(16)
          .onClick(() => this.submitLogin())
      }
      .padding({ left: 20, right: 20, bottom: 40 })
    }
    .width('100%')
    .height('100%')
  }
}
