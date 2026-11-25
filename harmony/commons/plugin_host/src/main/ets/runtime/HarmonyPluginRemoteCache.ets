import { fileIo } from '@kit.CoreFileKit';
import { RustCoreBridge } from '@moviepilot/core_rust_bridge';

export interface CachedRemoteAsset {
  buffer: ArrayBuffer;
  mimeType: string;
}

/**
 * 鸿蒙端联邦插件远程产物沙箱磁盘缓存（按实例源 SHA-256 / 插件 ID / 版本或产物哈希三级隔离）。
 */
export class HarmonyPluginRemoteCache {
  private static readonly ROOT_SUBDIR = 'plugin-remote-cache';

  private static rootDir(cacheDir: string): string {
    return `${cacheDir}/${HarmonyPluginRemoteCache.ROOT_SUBDIR}`;
  }

  private static ensureDirSync(dirPath: string): void {
    try {
      if (!fileIo.accessSync(dirPath)) {
        fileIo.mkdirSync(dirPath, true);
      }
    } catch {
      try {
        fileIo.mkdirSync(dirPath, true);
      } catch {
        // ignore
      }
    }
  }

  private static resolveFilePath(
    cacheDir: string,
    instanceOrigin: string,
    pluginId: string,
    versionTag: string,
    assetRelPath: string
  ): string {
    const key = RustCoreBridge.buildPluginRemoteCacheKey(instanceOrigin, pluginId, versionTag);
    const safeRel = assetRelPath.replace(/^\/+/, '');
    if (safeRel.includes('..') || safeRel.includes('\\')) {
      return '';
    }
    return `${HarmonyPluginRemoteCache.rootDir(cacheDir)}/${key.relative_dir}/${safeRel}`;
  }

  static readSync(
    cacheDir: string,
    instanceOrigin: string,
    pluginId: string,
    versionTag: string,
    assetRelPath: string
  ): CachedRemoteAsset | null {
    if (!cacheDir) {
      return null;
    }
    const fullPath = HarmonyPluginRemoteCache.resolveFilePath(
      cacheDir,
      instanceOrigin,
      pluginId,
      versionTag,
      assetRelPath
    );
    if (!fullPath) {
      return null;
    }
    try {
      if (!fileIo.accessSync(fullPath)) {
        return null;
      }
      const stat = fileIo.statSync(fullPath);
      if (stat.size <= 0 || stat.size > 20 * 1024 * 1024) {
        return null;
      }
      const file = fileIo.openSync(fullPath, fileIo.OpenMode.READ_ONLY);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      return {
        buffer: buf,
        mimeType: HarmonyPluginRemoteCache.guessMimeType(assetRelPath)
      };
    } catch {
      return null;
    }
  }

  static writeSync(
    cacheDir: string,
    instanceOrigin: string,
    pluginId: string,
    versionTag: string,
    assetRelPath: string,
    buffer: ArrayBuffer
  ): void {
    if (!cacheDir || buffer.byteLength <= 0) {
      return;
    }
    const fullPath = HarmonyPluginRemoteCache.resolveFilePath(
      cacheDir,
      instanceOrigin,
      pluginId,
      versionTag,
      assetRelPath
    );
    if (!fullPath) {
      return;
    }
    try {
      const lastSlash = fullPath.lastIndexOf('/');
      if (lastSlash > 0) {
        HarmonyPluginRemoteCache.ensureDirSync(fullPath.substring(0, lastSlash));
      }
      const file = fileIo.openSync(
        fullPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      fileIo.writeSync(file.fd, buffer);
      fileIo.closeSync(file);
    } catch {
      // ignore cache write failures
    }
  }

  static clearAll(cacheDir: string): void {
    if (!cacheDir) {
      return;
    }
    const root = HarmonyPluginRemoteCache.rootDir(cacheDir);
    try {
      if (fileIo.accessSync(root)) {
        fileIo.rmdirSync(root);
      }
    } catch {
      // ignore
    }
  }

  static guessMimeType(path: string): string {
    const clean = (path ?? '').split('#')[0].split('?')[0].toLowerCase();
    const dot = clean.lastIndexOf('.');
    const ext = dot >= 0 ? clean.substring(dot + 1) : '';
    switch (ext) {
      case 'html':
      case 'htm':
        return 'text/html';
      case 'js':
      case 'mjs':
      case 'cjs':
        return 'application/javascript';
      case 'css':
        return 'text/css';
      case 'json':
      case 'map':
        return 'application/json';
      case 'svg':
        return 'image/svg+xml';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'ico':
        return 'image/x-icon';
      case 'woff':
        return 'font/woff';
      case 'woff2':
        return 'font/woff2';
      case 'ttf':
        return 'font/ttf';
      case 'wasm':
        return 'application/wasm';
      default:
        return 'application/octet-stream';
    }
  }
}
