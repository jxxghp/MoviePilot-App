import { image } from '@kit.ImageKit';
import { MoviePilotRepository } from '../api/MoviePilotRepository';

/**
 * 鸿蒙原生带 Cookie 鉴权的远程图片缓存加载器：
 * - 自动携带 MoviePilot 登录态 `resource_token` Cookie 与 Bearer Token，解决 `/api/v1/system/img/0` 401 拦截；
 * - 内置 180 条 LRU `PixelMap` 内存缓存与并发去重，确保列表滑动零闪烁、零重复拉取。
 */
export class MpImageLoader {
  private static readonly MAX_ENTRIES: number = 180;
  private static cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static inflight: Map<string, Promise<image.PixelMap | null>> = new Map<string, Promise<image.PixelMap | null>>();

  static getCached(url: string): image.PixelMap | null {
    const hit = MpImageLoader.cache.get(url);
    if (hit) {
      MpImageLoader.cache.delete(url);
      MpImageLoader.cache.set(url, hit);
      return hit;
    }
    return null;
  }

  static clearCache(): void {
    MpImageLoader.cache.clear();
  }

  static async load(url: string): Promise<image.PixelMap | null> {
    const clean = url.trim();
    if (!clean || clean.startsWith('data:image/')) {
      return null;
    }
    const cached = MpImageLoader.getCached(clean);
    if (cached) {
      return cached;
    }
    const pending = MpImageLoader.inflight.get(clean);
    if (pending) {
      return pending;
    }
    const task = MpImageLoader.fetchAndDecode(clean);
    MpImageLoader.inflight.set(clean, task);
    try {
      return await task;
    } finally {
      MpImageLoader.inflight.delete(clean);
    }
  }

  private static async fetchAndDecode(url: string): Promise<image.PixelMap | null> {
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
      const pm = await source.createPixelMap();
      try {
        source.release();
      } catch {
        // ignore release error
      }
      if (pm) {
        if (MpImageLoader.cache.size >= MpImageLoader.MAX_ENTRIES) {
          const oldestKey = MpImageLoader.cache.keys().next().value as string | undefined;
          if (oldestKey) {
            MpImageLoader.cache.delete(oldestKey);
          }
        }
        MpImageLoader.cache.set(url, pm);
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
 * - MoviePilot 图片代理与媒体服务器封面通过 `MpImageLoader` 自动鉴权解码并缓存展示。
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

  private syncLoad(): void {
    const target = (this.src ?? '').trim();
    this.activeSrc = target;
    if (!target || target.startsWith('data:image/')) {
      this.pixelMap = null;
      return;
    }
    const hit = MpImageLoader.getCached(target);
    if (hit) {
      this.pixelMap = hit;
      return;
    }
    this.pixelMap = null;
    MpImageLoader.load(target).then((pm: image.PixelMap | null) => {
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
        .backgroundColor(this.placeholderColor)
    } else if (this.pixelMap) {
      Image(this.pixelMap)
        .width(this.imgWidth)
        .height(this.imgAspectRatio > 0 ? undefined : this.imgHeight)
        .aspectRatio(this.imgAspectRatio > 0 ? this.imgAspectRatio : undefined)
        .borderRadius(this.imgRadius)
        .objectFit(this.fit)
        .backgroundColor(this.placeholderColor)
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
