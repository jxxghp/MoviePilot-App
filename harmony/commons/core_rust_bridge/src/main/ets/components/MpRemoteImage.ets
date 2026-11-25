import { image } from '@kit.ImageKit';
import { MoviePilotRepository } from '../api/MoviePilotRepository';

function resolveBucketMaxPx(maxSidePx: number): number {
  if (maxSidePx <= 240) { return 256; }
  if (maxSidePx <= 680) { return 640; }
  return 1280;
}

/**
 * 鸿蒙原生带同源 Cookie 鉴权与自动降采样（防 OOM）的远程图片缓存加载器：
 * - 委托 `NativeRcpTransport.fetchBinary` 执行同源凭据守卫；
 * - 解码时根据目标渲染尺寸自动传入 `desiredSize` 按比例降采样，杜绝超大图撑爆显存；
 * - LRU 淘汰与退出登录清空缓存时主动调用 `PixelMap.release()` 释放底层像素缓冲。
 */
export class MpImageLoader {
  private static readonly MAX_ENTRIES: number = 160;
  private static cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static inflight: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();

  private static makeKey(url: string, maxSidePx: number): string {
    return `${url.trim()}@${resolveBucketMaxPx(maxSidePx)}`;
  }

  static getCached(url: string, maxSidePx: number = 640): image.PixelMap | null {
    const key = MpImageLoader.makeKey(url, maxSidePx);
    const hit = MpImageLoader.cache.get(key);
    if (hit) {
      MpImageLoader.cache.delete(key);
      MpImageLoader.cache.set(key, hit);
      return hit;
    }
    return null;
  }

  /** 清空全部缓存并释放所有底层 `PixelMap` 内存。 */
  static clearCache(): void {
    MpImageLoader.cache.forEach((pm: image.PixelMap) => {
      try {
        pm.release();
      } catch {
        // ignore release error
      }
    });
    MpImageLoader.cache.clear();
  }

  static async load(url: string, maxSidePx: number = 640): Promise<image.PixelMap | null> {
    const clean = url.trim();
    if (!clean || clean.startsWith('data:image/')) {
      return null;
    }
    const bucketPx = resolveBucketMaxPx(maxSidePx);
    const cacheKey = MpImageLoader.makeKey(clean, bucketPx);
    const cached = MpImageLoader.getCached(clean, bucketPx);
    if (cached) {
      return cached;
    }
    const pending = MpImageLoader.inflight.get(cacheKey);
    if (pending) {
      return pending;
    }
    const task = MpImageLoader.fetchAndDecode(clean, cacheKey, bucketPx);
    MpImageLoader.inflight.set(cacheKey, task);
    try {
      return await task;
    } finally {
      MpImageLoader.inflight.delete(cacheKey);
    }
  }

  private static async fetchAndDecode(url: string, cacheKey: string, maxSidePx: number): Promise<image.PixelMap | null> {
    try {
      const repo = MoviePilotRepository.shared();
      const bytes = await repo.transport.fetchBinary(url, repo.token);
      if (!bytes || bytes.byteLength === 0) {
        return null;
      }
      const source = image.createImageSource(bytes);
      if (!source) {
        return null;
      }
      let decodeOpts: image.DecodingOptions = {};
      try {
        const info = await source.getImageInfo();
        if (info && info.size && info.size.width > 0 && info.size.height > 0) {
          const srcW = info.size.width;
          const srcH = info.size.height;
          const maxDim = Math.max(srcW, srcH);
          if (maxDim > maxSidePx) {
            const scale = maxSidePx / maxDim;
            decodeOpts = {
              desiredSize: {
                width: Math.max(1, Math.round(srcW * scale)),
                height: Math.max(1, Math.round(srcH * scale))
              }
            };
          } else {
            decodeOpts = {
              desiredSize: { width: srcW, height: srcH }
            };
          }
        } else {
          decodeOpts = {
            desiredSize: { width: maxSidePx, height: maxSidePx }
          };
        }
      } catch {
        decodeOpts = {
          desiredSize: { width: maxSidePx, height: maxSidePx }
        };
      }

      const pm = await source.createPixelMap(decodeOpts);
      try {
        source.release();
      } catch {
        // ignore release error
      }
      if (pm) {
        if (MpImageLoader.cache.size >= MpImageLoader.MAX_ENTRIES) {
          const oldestKey = MpImageLoader.cache.keys().next().value as string | undefined;
          if (oldestKey) {
            const evicted = MpImageLoader.cache.get(oldestKey);
            MpImageLoader.cache.delete(oldestKey);
            if (evicted) {
              try { evicted.release(); } catch { /* ignore */ }
            }
          }
        }
        MpImageLoader.cache.set(cacheKey, pm);
      }
      return pm;
    } catch {
      return null;
    }
  }
}

/**
 * 鸿蒙统一远程图片组件：
 * - `data:image/` 直接零开销渲染；
 * - 自动按组件尺寸估算解码分辨率桶，支持透明 PNG ClearLogo（`placeholderColor: Color.Transparent`）。
 */
@Component
export struct MpRemoteImage {
  @Prop @Watch('onSrcChanged') src: string = '';
  @Prop imgWidth: Length = '100%';
  @Prop imgHeight: Length = '100%';
  @Prop imgAspectRatio: number = 0;
  @Prop imgRadius: number = 0;
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop placeholderColor: ResourceColor = '#1C2230';
  @State private pixelMap: image.PixelMap | null = null;
  private activeSrc: string = '';

  aboutToAppear(): void {
    this.syncLoad();
  }

  onSrcChanged(): void {
    this.syncLoad();
  }

  private desiredMaxPx(): number {
    const wNum = typeof this.imgWidth === 'number' ? this.imgWidth : 0;
    const hNum = typeof this.imgHeight === 'number' ? this.imgHeight : 0;
    const maxVp = Math.max(wNum, hNum);
    if (maxVp > 0 && maxVp <= 96) {
      return 240;
    }
    if (maxVp > 0 && maxVp <= 260) {
      return 640;
    }
    return 1280;
  }

  private syncLoad(): void {
    const target = (this.src ?? '').trim();
    this.activeSrc = target;
    if (!target || target.startsWith('data:image/')) {
      this.pixelMap = null;
      return;
    }
    const maxPx = this.desiredMaxPx();
    const hit = MpImageLoader.getCached(target, maxPx);
    if (hit) {
      this.pixelMap = hit;
      return;
    }
    this.pixelMap = null;
    MpImageLoader.load(target, maxPx).then((pm: image.PixelMap | null) => {
      if (this.activeSrc === target && pm) {
        this.pixelMap = pm;
      }
    }).catch(() => {});
  }

  build() {
    if (this.src.startsWith('data:image/')) {
      Image(this.src)
        .width(this.imgWidth)
        .height(this.imgAspectRatio > 0 ? undefined : this.imgHeight)
        .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
        .borderRadius(this.imgRadius)
        .objectFit(this.fit)
        .backgroundColor(this.fit === ImageFit.Contain ? Color.Transparent : this.placeholderColor)
    } else if (this.pixelMap) {
      Image(this.pixelMap)
        .width(this.imgWidth)
        .height(this.imgAspectRatio > 0 ? undefined : this.imgHeight)
        .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
        .borderRadius(this.imgRadius)
        .objectFit(this.fit)
        .backgroundColor(this.fit === ImageFit.Contain ? Color.Transparent : this.placeholderColor)
    } else {
      Column()
        .width(this.imgWidth)
        .height(this.imgAspectRatio > 0 ? undefined : this.imgHeight)
        .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
        .borderRadius(this.imgRadius)
        .backgroundColor(this.placeholderColor)
    }
  }
}
