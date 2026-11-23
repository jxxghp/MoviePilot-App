import { GeneratedDesignTokens, BackgroundPresetToken, AccentPresetToken } from '../../../../commons/design_system/src/main/ets/tokens/GeneratedTokens';
import { HarmonyAppearanceStore } from '../../../../commons/design_system/src/main/ets/store/AppearanceStore';
import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { RustCoreBridge } from '../../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';
import { CommunityMedal3DComponent } from '../../../../commons/medal_3d/src/main/ets/CommunityMedal3DComponent';
import { NativePluginHostView } from '../../../../commons/plugin_host/src/main/ets/NativePluginFormView';

/** 鸿蒙设置主中心（1:1 复刻 iOS 黄金截图 + 原生 `bindSheet` 外观设置 / 插件宿主 / 3D 社区勋章）。 */
@Component
export struct HarmonySettingsHubPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_BG_PRESET) bgPreset: string = GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop serverUrl: string = '';
  @Prop userName: string = 'admin';
  @State private showAppearanceSheet: boolean = false;
  @State private showMedalsSheet: boolean = false;
  @State private showPluginSheet: boolean = false;
  onOpenSites: () => void = () => {};
  onLogout: () => void = () => {};

  private readonly demoPluginDoc: string = JSON.stringify({
    render_mode: 'vuetify',
    conf: [
      { component: 'VAlert', props: { text: '由 Rust mp-core-plugin 实时解码生成的鸿蒙原生表单' } },
      { component: 'VSwitch', props: { model: 'enabled', label: '启用目录监控插件' } },
      { component: 'VCronField', props: { model: 'cron', label: '定时执行周期' } },
      { component: 'VTextField', props: { model: 'target_dir', label: '目标媒体库目录' } }
    ],
    model: { enabled: true, cron: '*/15 * * * *', target_dir: '/media/movies' }
  });

  @Builder
  appearanceSheetBuilder() {
    Column({ space: 14 }) {
      Text('外观与动态光感').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      Row({ space: 8 }) {
        NativeAdaptivePill({ title: '深色模式', selected: this.isDark, onTap: () => { this.isDark = true; } })
        NativeAdaptivePill({ title: '浅色模式', selected: !this.isDark, onTap: () => { this.isDark = false; } })
      }.width('100%')
      Text('6 套同源流光色板').fontSize(13).fontColor('#B8FFFFFF').width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
        ForEach(GeneratedDesignTokens.BACKGROUND_PRESETS, (p: BackgroundPresetToken) => {
          NativeAdaptivePill({ title: p.titleZh, selected: this.bgPreset === p.id, onTap: () => { this.bgPreset = p.id; } })
        })
      }
      Text('主题强调色').fontSize(13).fontColor('#B8FFFFFF').width('100%')
      Row({ space: 10 }) {
        ForEach(GeneratedDesignTokens.ACCENT_PRESETS.filter((a) => a.id !== 'custom'), (acc: AccentPresetToken) => {
          Column()
            .width(34).height(34).borderRadius(17).backgroundColor(acc.hex)
            .border({ width: this.accentHex === acc.hex ? 3 : 1, color: Color.White, radius: 17 })
            .onClick(() => { this.accentHex = acc.hex; })
        })
      }.width('100%')
    }.padding(20).width('100%')
  }

  @Builder
  medalsSheetBuilder() {
    Column({ space: 14 }) {
      Text('3D 社区勋章（73 枚共享金属雕刻）').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      CommunityMedal3DComponent({
        medalId: 'contributor_gold',
        assetBaseName: 'contributor_gold',
        title: '核心贡献者',
        ownerName: this.userName,
        earnedDate: '2026-11'
      })
    }.padding(20).width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  pluginSheetBuilder() {
    Column() {
      Text('动态插件配置（原生 JSON 引擎）').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Color.White).padding(16).width('100%')
      NativePluginHostView({
        pluginName: 'MediaDirWatcher',
        documentJson: this.demoPluginDoc,
        serverUrl: this.serverUrl,
        authToken: '',
        onSaveFullModel: () => { this.showPluginSheet = false; }
      })
    }.width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('设置').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White).margin({ top: 48 })

        // 顶部存储进度卡
        CinematicPanel({ panelPadding: 16 }) {
          Column({ space: 8 }) {
            Row() {
              Text(`● ${this.serverUrl || '127.0.0.1'}`).fontSize(13).fontColor('#75E6A3').layoutWeight(1)
              Text('26.47 TB / 34.56 TB').fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White)
            }.width('100%')
            Progress({ value: 77, total: 100, type: ProgressType.Linear }).color(this.accentHex).backgroundColor('#22FFFFFF')
            Row() {
              Text('已用 77%').fontSize(11).fontColor(this.accentHex)
              Blank()
              Text('可用 8.08 TB').fontSize(11).fontColor('#B8FFFFFF')
            }.width('100%')
          }
        }

        // 三枚快捷磁贴
        Row({ space: 10 }) {
          CinematicPanel({ panelPadding: 12 }) {
            Column({ space: 4 }) {
              Text('站点管理').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
              Text('● 51 启用').fontSize(11).fontColor('#75E6A3')
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1).onClick(() => this.onOpenSites())

          CinematicPanel({ panelPadding: 12 }) {
            Column({ space: 4 }) {
              Text('用户管理').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
              Text('● 1 位成员').fontSize(11).fontColor('#75E6A3')
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)

          CinematicPanel({ panelPadding: 12 }) {
            Column({ space: 4 }) {
              Text('渠道授权').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
              Text('● 已授 3').fontSize(11).fontColor('#75E6A3')
            }.alignItems(HorizontalAlign.Start)
          }.layoutWeight(1)
        }

        // 分组列表
        CinematicPanel({ panelPadding: 0 }) {
          Column() {
            this.settingsRow('外观与主题', '6 套流光 · 动态光感', () => { this.showAppearanceSheet = true; })
            Divider().color('#1EFFFFFF')
            this.settingsRow('插件中心', 'JSON 原生 · Vue 隔离', () => { this.showPluginSheet = true; })
            Divider().color('#1EFFFFFF')
            this.settingsRow('3D 社区勋章', '73 枚金属雕刻', () => { this.showMedalsSheet = true; })
            Divider().color('#1EFFFFFF')
            this.settingsRow('Rust 共享内核', `v${RustCoreBridge.version()} · ohos-rs`, () => {})
          }
        }

        Button(`退出登录（${this.userName}）`)
          .width('100%').height(48).borderRadius(24).backgroundColor('#33FF8A94').fontColor('#FF8A94')
          .onClick(() => this.onLogout())
      }
      .padding({ left: 20, right: 20, bottom: 128 })
    }
    .bindSheet($$this.showAppearanceSheet, this.appearanceSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE], blurStyle: BlurStyle.COMPONENT_THIN, dragBar: true, backgroundColor: '#CC2F2640'
    })
    .bindSheet($$this.showMedalsSheet, this.medalsSheetBuilder(), {
      detents: [SheetSize.MEDIUM], blurStyle: BlurStyle.COMPONENT_THIN, dragBar: true, backgroundColor: '#CC2F2640'
    })
    .bindSheet($$this.showPluginSheet, this.pluginSheetBuilder(), {
      detents: [SheetSize.LARGE], blurStyle: BlurStyle.COMPONENT_THIN, dragBar: true, backgroundColor: '#CC2F2640'
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  settingsRow(title: string, sub: string, action: () => void) {
    Row() {
      Text(title).fontSize(15).fontColor(Color.White).layoutWeight(1)
      Text(sub).fontSize(12).fontColor('#99FFFFFF')
      Text(' ›').fontSize(16).fontColor('#88FFFFFF')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
    .onClick(action)
  }
}
