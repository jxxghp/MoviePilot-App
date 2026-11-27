import { image } from '@kit.ImageKit';
import { HarmonyAppearanceStore } from '../store/AppearanceStore';
import { HarmonyMotionTokens, HarmonyThemeColors } from './HarmonyDynamicLight';

const entityLogoPixelCache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
const entityLogoInflight: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();

/**
 * 解析 36 枚品牌与服务图标资源文件名（对应 `entry/src/main/resources/rawfile/logos/`）。
 */
export function resolveEntityLogoAsset(kind: string, value: string): string {
  const k = (kind ?? '').trim().toLowerCase();
  const v = (value ?? '').trim().toLowerCase();

  if (k === 'media_source' || k === 'source') {
    if (v.includes('douban') || v.includes('豆瓣')) { return 'logo_douban.png'; }
    if (v.includes('bangumi') || v.includes('bgm') || v.includes('番剧')) { return 'logo_bangumi.png'; }
    if (v.includes('musicbrainz') || v.includes('listenbrainz') || v.includes('music') || v.includes('音乐')) {
      return 'logo_musicbrainz.png';
    }
    return 'logo_tmdb.png';
  }

  if (k === 'downloader') {
    if (v.includes('qbittorrent') || v === 'qb') { return 'logo_qbittorrent.png'; }
    if (v.includes('transmission') || v === 'tr') { return 'logo_transmission.png'; }
    if (v.includes('rtorrent') || v.includes('rutorrent')) { return 'logo_rtorrent.png'; }
    return 'logo_downloader.png';
  }

  if (k === 'mediaserver') {
    if (v.includes('emby')) { return 'logo_emby.png'; }
    if (v.includes('jellyfin')) { return 'logo_jellyfin.png'; }
    if (v.includes('plex')) { return 'logo_plex.png'; }
    if (v.includes('trimemedia') || v.includes('fnos') || v.includes('飞牛')) { return 'logo_trimemedia.png'; }
    if (v.includes('ugreen') || v.includes('绿联')) { return 'logo_ugreen.png'; }
    if (v.includes('zspace') || v.includes('极空间')) { return 'logo_zspace.png'; }
    if (v.includes('vyo')) { return 'logo_vyo.png'; }
    return 'logo_mediaserver.png';
  }

  if (k === 'notification') {
    if (v.includes('wechat') || v.includes('wecom') || v.includes('微信') || v.includes('企业微信')) {
      return 'logo_wechat.png';
    }
    if (v.includes('clawbot') || v.includes('openclaw')) { return 'logo_clawbot.png'; }
    if (v.includes('feishu') || v.includes('lark') || v.includes('飞书')) { return 'logo_feishu.png'; }
    if (v.includes('telegram') || v === 'tg') { return 'logo_telegram.png'; }
    if (v.includes('qq') || v.includes('napcat')) { return 'logo_qq.png'; }
    if (v.includes('vocechat')) { return 'logo_vocechat.png'; }
    if (v.includes('synology') || v.includes('群晖')) { return 'logo_synologychat.png'; }
    if (v.includes('slack')) { return 'logo_slack.png'; }
    if (v.includes('discord')) { return 'logo_discord.png'; }
    if (v.includes('dingtalk') || v.includes('钉钉')) { return 'logo_dingtalk.png'; }
    if (v.includes('chrome') || v.includes('webpush') || v.includes('浏览器')) { return 'logo_chrome.png'; }
    return 'logo_notification.png';
  }

  if (k === 'storage') {
    if (v.includes('u115') || v.includes('115')) { return 'logo_u115.png'; }
    if (v.includes('alipan') || v.includes('aliyun') || v.includes('阿里')) { return 'logo_alipan.png'; }
    if (v.includes('rclone')) { return 'logo_rclone.png'; }
    if (v.includes('smb') || v.includes('cifs')) { return 'logo_smb.png'; }
    return 'logo_storage.png';
  }

  if (k === 'site') {
    return 'logo_site.png';
  }
  if (k === 'plugin') {
    return 'logo_plugin.png';
  }
  if (k === 'avatar') {
    return 'logo_avatar_default.png';
  }
  return 'logo_mediaserver.png';
}

/**
 * 清理已解码的品牌图标缓存（退出登录或内存回收时调用）。
 */
export function clearEntityLogoCache(): void {
  entityLogoPixelCache.forEach((pm: image.PixelMap) => {
    try {
      pm.release();
    } catch {
      // ignore release error
    }
  });
  entityLogoPixelCache.clear();
}

/**
 * 鸿蒙统一品牌与服务实体 Logo 组件：
 * - 通过 `resourceManager.getRawFileContent` 加载并缓存主包 `rawfile/logos/${assetName}`；
 * - 支持传入 `dataUri`（如站点 `/api/v1/site/icon/{id}` 返回的 `data:image/`），失败或为空时自动回退品牌图标；
 * - 解码完成前提供清晰首字母徽标兜底，杜绝闪烁。
 */
@Component
export struct HarmonyEntityLogo {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop @Watch('onLogoPropsChanged') kind: string = 'mediaserver';
  @Prop @Watch('onLogoPropsChanged') value: string = '';
  @Prop @Watch('onLogoPropsChanged') dataUri: string = '';
  @Prop logoSize: number = 22;
  @Prop cornerRadius: number = 6;
  @State private pm: image.PixelMap | null = null;
  private currentAsset: string = '';

  aboutToAppear(): void {
    this.loadAsset();
  }

  onLogoPropsChanged(): void {
    this.loadAsset();
  }

  private loadAsset(): void {
    if (this.dataUri.startsWith('data:image/')) {
      return;
    }
    const assetName = resolveEntityLogoAsset(this.kind, this.value);
    this.currentAsset = assetName;
    const hit = entityLogoPixelCache.get(assetName);
    if (hit) {
      this.pm = hit;
      return;
    }
    const pending = entityLogoInflight.get(assetName);
    if (pending) {
      pending.then((decoded: image.PixelMap | null) => {
        if (decoded && this.currentAsset === assetName) {
          this.pm = decoded;
        }
      }).catch(() => {});
      return;
    }

    const task: Promise<image.PixelMap | null> = this.decodeFromRawfile(assetName);
    entityLogoInflight.set(assetName, task);
    task.then((decoded: image.PixelMap | null) => {
      entityLogoInflight.delete(assetName);
      if (decoded && this.currentAsset === assetName) {
        this.pm = decoded;
      }
    }).catch(() => {
      entityLogoInflight.delete(assetName);
    });
  }

  private async decodeFromRawfile(assetName: string): Promise<image.PixelMap | null> {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx || !ctx.resourceManager) {
        return null;
      }
      const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(`logos/${assetName}`);
      const copyBuf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const src = image.createImageSource(copyBuf);
      const decoded = await src.createPixelMap({
        desiredSize: { width: 128, height: 128 }
      });
      try {
        src.release();
      } catch {
        // ignore release error
      }
      if (decoded) {
        entityLogoPixelCache.set(assetName, decoded);
      }
      return decoded ?? null;
    } catch {
      return null;
    }
  }

  private fallbackInitial(): string {
    const clean = (this.value || this.kind || 'M').trim();
    return clean.length > 0 ? clean.substring(0, 1).toUpperCase() : 'M';
  }

  build() {
    if (this.dataUri.startsWith('data:image/')) {
      Image(this.dataUri)
        .width(this.logoSize)
        .height(this.logoSize)
        .borderRadius(this.cornerRadius)
        .objectFit(ImageFit.Contain)
    } else if (this.pm) {
      Image(this.pm)
        .width(this.logoSize)
        .height(this.logoSize)
        .borderRadius(this.cornerRadius)
        .objectFit(ImageFit.Contain)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Text(this.fallbackInitial())
          .fontSize(Math.max(9, Math.round(this.logoSize * 0.46)))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accentHex)
      }
      .width(this.logoSize)
      .height(this.logoSize)
      .borderRadius(this.cornerRadius)
      .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '28' : '18'))
    }
  }
}

/**
 * 带品牌图标的多维选择胶囊（用于数据源、下载器、媒体服务器、通知渠道、存储与站点筛选器）。
 */
@Component
export struct HarmonyEntityLogoPill {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop kind: string = 'mediaserver';
  @Prop value: string = '';
  @Prop dataUri: string = '';
  @Prop title: string = '';
  @Prop selected: boolean = false;
  @Prop logoSize: number = 16;
  onTap: () => void = () => {};

  build() {
    Row({ space: 6 }) {
      if (this.value.length > 0 || this.dataUri.length > 0 || this.kind === 'site' || this.kind === 'storage') {
        HarmonyEntityLogo({
          kind: this.kind,
          value: this.value,
          dataUri: this.dataUri,
          logoSize: this.logoSize,
          cornerRadius: Math.max(4, Math.round(this.logoSize * 0.28))
        })
      }
      Text(this.title)
        .fontSize(13)
        .fontWeight(this.selected ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.selected ? Color.White : HarmonyThemeColors.primaryText(this.isDark))
        .maxLines(1)
    }
    .padding({ left: 11, right: 13, top: 7, bottom: 7 })
    .borderRadius(16)
    .backgroundColor(this.selected ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
    .border({
      width: this.selected ? 0 : 0.6,
      color: HarmonyThemeColors.borderSubtle(this.isDark),
      radius: 16
    })
    .animation({ duration: HarmonyMotionTokens.DURATION_INSTANT, curve: HarmonyMotionTokens.CURVE_STANDARD })
    .hoverEffect(HoverEffect.Highlight)
    .focusable(true)
    .accessibilityText(`${this.title}${this.selected ? '，已选中' : ''}`)
    .onClick(() => this.onTap())
  }
}

/**
 * 鸿蒙多元评分单项展示模型（如 IMDb / TMDB / 烂番茄新鲜度 / 豆瓣 / Bangumi）。
 */
export interface HarmonyRatingBadgeItem {
  source: string;
  label: string;
}

/**
 * 鸿蒙发现页与影视/媒体库详情页共用的紧凑多元评分微标横排（品牌小图标 + 分数）。
 */
@Component
export struct HarmonyMultiRatingsRow {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop badges: HarmonyRatingBadgeItem[] = [];
  @Prop forceLightText: boolean = false;
  @Prop compact: boolean = false;

  private resolvedTextColor(): ResourceColor {
    if (this.forceLightText || this.isDark) {
      return Color.White;
    }
    return HarmonyThemeColors.primaryText(false);
  }

  build() {
    if (this.badges.length > 0) {
      Row({ space: this.compact ? 9 : 12 }) {
        ForEach(this.badges, (b: HarmonyRatingBadgeItem) => {
          Row({ space: 4 }) {
            if (b.source === 'imdb') {
              Row() {
                Text('IMDb')
                  .fontSize(this.compact ? 8.5 : 9.5)
                  .fontWeight(FontWeight.Bolder)
                  .fontColor('#141414')
              }
              .padding({ left: 4.5, right: 4.5, top: 1.5, bottom: 1.5 })
              .borderRadius(3.5)
              .backgroundColor('#F5C518')
            } else if (b.source === 'rottentomatoes') {
              Stack({ alignContent: Alignment.Top }) {
                Column()
                  .width(this.compact ? 12.5 : 14)
                  .height(this.compact ? 12.5 : 14)
                  .borderRadius(7)
                  .backgroundColor('#FA320A')
                  .margin({ top: 1.5 })
                Column()
                  .width(6.5)
                  .height(2.6)
                  .borderRadius(1.5)
                  .backgroundColor('#2EA84A')
              }
              .width(this.compact ? 14 : 15.5)
              .height(this.compact ? 14 : 15.5)
            } else if (b.source === 'douban') {
              HarmonyEntityLogo({
                kind: 'media_source',
                value: 'douban',
                logoSize: this.compact ? 14 : 15.5,
                cornerRadius: 4
              })
            } else if (b.source === 'bangumi') {
              HarmonyEntityLogo({
                kind: 'media_source',
                value: 'bangumi',
                logoSize: this.compact ? 14 : 15.5,
                cornerRadius: 4
              })
            } else if (b.source === 'anilist') {
              Row() {
                Text('AL')
                  .fontSize(this.compact ? 8.5 : 9.5)
                  .fontWeight(FontWeight.Bolder)
                  .fontColor(Color.White)
              }
              .padding({ left: 4, right: 4, top: 1.5, bottom: 1.5 })
              .borderRadius(3.5)
              .backgroundColor('#02A9FF')
            } else if (b.source === 'community') {
              Text('★')
                .fontSize(this.compact ? 11 : 12.5)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFE27A')
            } else {
              HarmonyEntityLogo({
                kind: 'media_source',
                value: 'themoviedb',
                logoSize: this.compact ? 14 : 15.5,
                cornerRadius: 4
              })
            }

            Text(b.label)
              .fontSize(this.compact ? 11.5 : 12.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.resolvedTextColor())
              .maxLines(1)
          }
          .alignItems(VerticalAlign.Center)
        }, (b: HarmonyRatingBadgeItem) => `${b.source}_${b.label}`)
      }
      .alignItems(VerticalAlign.Center)
    }
  }
}
