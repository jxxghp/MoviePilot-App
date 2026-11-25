import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { display, window } from '@kit.ArkUI';
import { avSession } from '@kit.AVSessionKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { connection, http } from '@kit.NetworkKit';
import { vibrator } from '@kit.SensorServiceKit';
import { notificationManager } from '@kit.NotificationKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { RustCoreBridge } from '@moviepilot/core_rust_bridge';

/**
 * 鸿蒙端 Vue 联邦插件全量原生本地能力服务：
 * - 录音（`media.createAVRecorder()` AAC `.m4a` + 麦克风运行时授权 + 暂停/恢复 + 音量振幅事件 + 15 MiB Base64 导出）
 * - 内联音频播放（`media.createAVPlayer()`：支持 Base64、鉴权 `apiPath`、本地存储流票据边加载边播放及 HTTP(S) 直链）
 * - 全屏原生播放器（经 `moviepilot://play?...` 深度链接唤醒鸿蒙原生全屏多引擎播放器）
 * - 系统能力（设备信息、运行时权限、触感振动、剪贴板读写、屏幕常亮、本地通知、相册/文件选取、保存媒体、扫码、生物认证）
 */
export class HarmonyPluginNativeCapabilities {
  static readonly MAX_BASE64_BYTES = 15 * 1024 * 1024;

  private getContext: () => common.UIAbilityContext | null;
  private getServerUrl: () => string;
  private getAuthToken: () => string;
  private sendResponse: (requestId: string, ok: boolean, dataJson: string, errCode?: string, errStatus?: number, errMsg?: string) => void;
  private sendDeviceEvent: (event: string, dataJson: string) => void;
  private openDeepLink: (deepLink: string) => void;

  // Recording state
  private avRecorder: media.AVRecorder | null = null;
  private recordingId: string = '';
  private recordFilePath: string = '';
  private recordFileFd: number = -1;
  private recordStartedAtMs: number = 0;
  private recordPausedAccumMs: number = 0;
  private recordPausedAtMs: number = 0;
  private recordMaxDurationMs: number = 300000;
  private recordMetering: boolean = true;
  private isRecordingPaused: boolean = false;
  private recordTimer: number = -1;

  // Inline audio playback state
  private avPlayer: media.AVPlayer | null = null;
  private playbackId: string = '';
  private playbackTempPath: string = '';
  private playbackFd: number = -1;
  private playbackState: string = 'idle';
  private playbackLoop: boolean = false;
  private playbackRate: number = 1.0;
  private playbackVolume: number = 1.0;
  private playbackDurationMs: number = 0;
  private playbackPositionMs: number = 0;
  private playbackProgressTimer: number = -1;

  // Keep-awake state
  private keepAwakeEnabled: boolean = false;
  private base64Helper: util.Base64Helper = new util.Base64Helper();

  // Status bar / AVSession Now Playing state (#56)
  private pluginAvSession: avSession.AVSession | null = null;
  private nowPlayingActive: boolean = false;
  private nowPlayingTitle: string = '';
  private nowPlayingArtist: string = '';
  private nowPlayingAlbum: string = '';
  private nowPlayingDurationMs: number = 0;

  constructor(
    getContext: () => common.UIAbilityContext | null,
    getServerUrl: () => string,
    getAuthToken: () => string,
    sendResponse: (requestId: string, ok: boolean, dataJson: string, errCode?: string, errStatus?: number, errMsg?: string) => void,
    sendDeviceEvent: (event: string, dataJson: string) => void,
    openDeepLink: (deepLink: string) => void
  ) {
    this.getContext = getContext;
    this.getServerUrl = getServerUrl;
    this.getAuthToken = getAuthToken;
    this.sendResponse = sendResponse;
    this.sendDeviceEvent = sendDeviceEvent;
    this.openDeepLink = openDeepLink;
  }

  cleanup(): void {
    this.cancelActiveRecording(false).catch(() => {});
    this.stopInlinePlayback(false).catch(() => {});
    this.clearNowPlayingSession().catch(() => {});
    if (this.keepAwakeEnabled) {
      this.keepAwakeEnabled = false;
      this.applyKeepAwake(false).catch(() => {});
    }
  }

  triggerHaptic(style: string): void {
    try {
      const duration = (style === 'heavy' || style === 'error') ? 35 : (style === 'medium' || style === 'warning' ? 22 : 12);
      vibrator.startVibration(
        { type: 'time', duration: duration },
        { id: 0, usage: 'touch' }
      ).catch(() => {});
    } catch {
      // ignore haptic errors on unsupported hardware
    }
  }

  handle(type: string, requestId: string, payload: Record<string, Object>): boolean {
    switch (type) {
      case 'device.capabilities':
        this.handleCapabilities(requestId);
        return true;
      case 'device.info':
        this.handleDeviceInfo(requestId);
        return true;
      case 'device.permission':
        this.handlePermission(requestId, payload).catch(() => {});
        return true;
      case 'device.clipboard.read':
        this.handleClipboardRead(requestId).catch(() => {});
        return true;
      case 'device.share':
        this.handleShare(requestId, payload);
        return true;
      case 'device.keepAwake':
        this.handleKeepAwake(requestId, payload).catch(() => {});
        return true;
      case 'device.notify':
        this.handleNotify(requestId, payload).catch(() => {});
        return true;
      case 'device.pickMedia':
        this.handlePickMedia(requestId, payload).catch(() => {});
        return true;
      case 'device.pickFile':
        this.handlePickFile(requestId, payload).catch(() => {});
        return true;
      case 'device.saveMedia':
        this.handleSaveMedia(requestId, payload).catch(() => {});
        return true;
      case 'device.scanCode':
        this.handleScanCode(requestId).catch(() => {});
        return true;
      case 'device.authenticate':
        this.handleAuthenticate(requestId, payload);
        return true;
      case 'audio.record.start':
        this.handleRecordStart(requestId, payload).catch(() => {});
        return true;
      case 'audio.record.pause':
        this.handleRecordPause(requestId).catch(() => {});
        return true;
      case 'audio.record.resume':
        this.handleRecordResume(requestId).catch(() => {});
        return true;
      case 'audio.record.stop':
        this.handleRecordStop(requestId, payload).catch(() => {});
        return true;
      case 'audio.record.cancel':
        this.cancelActiveRecording(true).then(() => {
          this.sendOk(requestId, '{"cancelled":true}');
        }).catch(() => {
          this.sendOk(requestId, '{"cancelled":true}');
        });
        return true;
      case 'audio.record.status':
        this.sendOk(requestId, JSON.stringify(this.currentRecordStatusObj()));
        return true;
      case 'audio.play':
        this.handleAudioPlay(requestId, payload).catch(() => {});
        return true;
      case 'audio.pause':
        this.handleAudioPause(requestId).catch(() => {});
        return true;
      case 'audio.resume':
        this.handleAudioResume(requestId).catch(() => {});
        return true;
      case 'audio.stop':
        this.stopInlinePlayback(true).then(() => {
          this.sendOk(requestId, '{"stopped":true}');
        }).catch(() => {
          this.sendOk(requestId, '{"stopped":true}');
        });
        return true;
      case 'audio.seek':
        this.handleAudioSeek(requestId, payload);
        return true;
      case 'audio.setRate':
        this.handleAudioSetRate(requestId, payload);
        return true;
      case 'audio.setVolume':
        this.handleAudioSetVolume(requestId, payload);
        return true;
      case 'audio.status':
        this.sendOk(requestId, JSON.stringify(this.currentPlaybackStatusObj()));
        return true;
      case 'audio.setNowPlaying':
        this.handleAudioSetNowPlaying(requestId, payload).catch(() => {});
        return true;
      case 'audio.clearNowPlaying':
        this.clearNowPlayingSession().then(() => {
          this.sendOk(requestId, '{"cleared":true}');
        }).catch(() => {
          this.sendOk(requestId, '{"cleared":true}');
        });
        return true;
      case 'media.playNative':
        this.handlePlayNativeMedia(requestId, payload);
        return true;
      default:
        return false;
    }
  }

  // MARK: - Device Info & Permissions

  private handleCapabilities(requestId: string): void {
    const caps: string[] = [
      'audio.record',
      'audio.play',
      'audio.nowPlaying',
      'native.audio.nowPlaying',
      'media.playNative',
      'device.info',
      'device.permission',
      'device.haptic',
      'device.clipboard',
      'device.clipboard.read',
      'device.share',
      'device.keepAwake',
      'device.notify',
      'device.pickMedia',
      'device.pickFile',
      'device.saveMedia',
      'device.scanCode',
      'device.authenticate'
    ];
    const isDark = AppStorage.get<boolean>('mp_appearance_is_dark') ?? true;
    const obj: Record<string, Object> = {
      'platform': 'harmony',
      'osVersion': deviceInfo.osFullName || `API ${deviceInfo.sdkApiVersion}`,
      'appVersion': this.resolveAppVersion(),
      'deviceModel': deviceInfo.marketName || deviceInfo.productModel || 'HarmonyOS',
      'networkType': this.currentNetworkType(),
      'isDark': isDark,
      'capabilities': caps
    };
    this.sendOk(requestId, JSON.stringify(obj));
  }

  private handleDeviceInfo(requestId: string): void {
    let width = 412;
    let height = 892;
    let density = 3.0;
    try {
      const disp = display.getDefaultDisplaySync();
      density = disp.densityPixels > 0 ? disp.densityPixels : 3.0;
      width = Math.round(disp.width / density);
      height = Math.round(disp.height / density);
    } catch {
      // use fallback viewport
    }
    const isDark = AppStorage.get<boolean>('mp_appearance_is_dark') ?? true;
    const locale = AppStorage.get<string>('mp_appearance_locale') ?? 'zh-CN';
    const obj: Record<string, Object> = {
      'platform': 'harmony',
      'osVersion': deviceInfo.osFullName || `API ${deviceInfo.sdkApiVersion}`,
      'appVersion': this.resolveAppVersion(),
      'deviceModel': deviceInfo.marketName || deviceInfo.productModel || 'HarmonyOS',
      'networkType': this.currentNetworkType(),
      'locale': locale,
      'isDark': isDark,
      'screenWidth': width,
      'screenHeight': height,
      'pixelRatio': density
    };
    this.sendOk(requestId, JSON.stringify(obj));
  }

  private async handlePermission(requestId: string, payload: Record<string, Object>): Promise<void> {
    const perm = typeof payload['permission'] === 'string' ? (payload['permission'] as string).toLowerCase() : '';
    const shouldRequest = typeof payload['request'] === 'boolean' ? (payload['request'] as boolean) : false;

    if (perm === 'photos') {
      // 鸿蒙 PhotoViewPicker / DocumentViewPicker 安全选择器无需额外存储权限
      this.sendOk(requestId, `{"permission":"photos","status":"granted"}`);
      return;
    }
    if (perm === 'notifications') {
      try {
        const enabled = await notificationManager.isNotificationEnabled();
        if (enabled) {
          this.sendOk(requestId, `{"permission":"notifications","status":"granted"}`);
          return;
        }
        if (shouldRequest) {
          const ctx = this.getContext();
          if (ctx) {
            await notificationManager.requestEnableNotification(ctx);
            const after = await notificationManager.isNotificationEnabled();
            this.sendOk(requestId, `{"permission":"notifications","status":${JSON.stringify(after ? 'granted' : 'denied')}}`);
            return;
          }
        }
        this.sendOk(requestId, `{"permission":"notifications","status":"denied"}`);
      } catch {
        this.sendOk(requestId, `{"permission":"notifications","status":"undetermined"}`);
      }
      return;
    }

    let ohosPerm: Permissions | null = null;
    if (perm === 'microphone') {
      ohosPerm = 'ohos.permission.MICROPHONE';
    } else if (perm === 'camera') {
      ohosPerm = 'ohos.permission.CAMERA';
    } else {
      this.sendErr(requestId, 'INVALID_PERMISSION', 400, `Unsupported permission: ${perm}`);
      return;
    }

    const granted = await this.checkOrRequestOhosPermission(ohosPerm, shouldRequest);
    const status = granted ? 'granted' : (shouldRequest ? 'denied' : 'undetermined');
    this.sendOk(requestId, `{"permission":${JSON.stringify(perm)},"status":${JSON.stringify(status)}}`);
  }

  async checkOrRequestOhosPermission(permission: Permissions, shouldRequest: boolean): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId = bundleInfo.appInfo.accessTokenId;
      const grantStatus = atManager.checkAccessTokenSync(tokenId, permission);
      if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
      if (!shouldRequest) {
        return false;
      }
      const ctx = this.getContext();
      if (!ctx) {
        return false;
      }
      const res = await atManager.requestPermissionsFromUser(ctx, [permission]);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch {
      return false;
    }
  }

  private async handleClipboardRead(requestId: string): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText() ?? '';
      this.sendOk(requestId, `{"text":${JSON.stringify(text)}}`);
    } catch {
      this.sendOk(requestId, '{"text":""}');
    }
  }

  private handleShare(requestId: string, payload: Record<string, Object>): void {
    const text = typeof payload['text'] === 'string' ? (payload['text'] as string) : '';
    const url = typeof payload['url'] === 'string' ? (payload['url'] as string) : '';
    const combined = [text, url].filter((s: string) => s.length > 0).join('\n');
    if (combined.length === 0) {
      this.sendErr(requestId, 'EMPTY_SHARE', 400, '缺少可分享的内容');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, combined);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.sendOk(requestId, '{"completed":true,"cancelled":false}');
    } catch {
      this.sendErr(requestId, 'SHARE_FAILED', 500, '复制分享内容失败');
    }
  }

  private async handleKeepAwake(requestId: string, payload: Record<string, Object>): Promise<void> {
    const enabled = typeof payload['enabled'] === 'boolean' ? (payload['enabled'] as boolean) : false;
    this.keepAwakeEnabled = enabled;
    await this.applyKeepAwake(enabled);
    this.sendOk(requestId, `{"enabled":${enabled ? 'true' : 'false'}}`);
  }

  private async applyKeepAwake(enabled: boolean): Promise<void> {
    const ctx = this.getContext();
    if (!ctx) {
      return;
    }
    try {
      const win = await window.getLastWindow(ctx);
      await win.setWindowKeepScreenOn(enabled);
    } catch {
      // ignore window errors
    }
  }

  private async handleNotify(requestId: string, payload: Record<string, Object>): Promise<void> {
    const title = typeof payload['title'] === 'string' ? (payload['title'] as string).trim() : '';
    const body = typeof payload['body'] === 'string' ? (payload['body'] as string).trim() : '';
    const idStr = typeof payload['id'] === 'string' && (payload['id'] as string).length > 0
      ? (payload['id'] as string)
      : `plugin_${Date.now()}`;
    if (title.length === 0 && body.length === 0) {
      this.sendErr(requestId, 'INVALID_NOTIFICATION', 400, '通知标题和内容不能同时为空');
      return;
    }
    try {
      const ctx = this.getContext();
      const enabled = await notificationManager.isNotificationEnabled();
      if (!enabled && ctx) {
        await notificationManager.requestEnableNotification(ctx);
      }
      const req: notificationManager.NotificationRequest = {
        id: Math.abs(this.hashCode(idStr)) % 1000000,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title || 'MoviePilot',
            text: body || title
          }
        }
      };
      await notificationManager.publish(req);
      this.sendOk(requestId, `{"scheduled":true,"id":${JSON.stringify(idStr)}}`);
    } catch (err) {
      this.sendErr(requestId, 'NOTIFY_FAILED', 500, err ? String(err) : '发送本地通知失败');
    }
  }

  private async handlePickMedia(requestId: string, payload: Record<string, Object>): Promise<void> {
    const mediaType = typeof payload['mediaType'] === 'string' ? (payload['mediaType'] as string).toLowerCase() : 'image';
    const multiple = typeof payload['multiple'] === 'boolean' ? (payload['multiple'] as boolean) : false;
    const maxCount = typeof payload['maxCount'] === 'number'
      ? Math.max(1, Math.min(20, Math.floor(payload['maxCount'] as number)))
      : (multiple ? 9 : 1);
    const includeBase64 = typeof payload['includeBase64'] === 'boolean' ? (payload['includeBase64'] as boolean) : true;

    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      let mimeFilter = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      if (mediaType === 'video') {
        mimeFilter = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      } else if (mediaType === 'any') {
        mimeFilter = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
      }
      const res = await photoPicker.select({
        MIMEType: mimeFilter,
        maxSelectNumber: multiple ? maxCount : 1
      });
      const files = this.readUrisAsPickedFiles(res.photoUris, mediaType === 'video' ? 'video/mp4' : 'image/jpeg', includeBase64);
      const out: Record<string, Object> = {
        'cancelled': files.length === 0,
        'files': files
      };
      this.sendOk(requestId, JSON.stringify(out));
    } catch {
      this.sendOk(requestId, '{"cancelled":true,"files":[]}');
    }
  }

  private async handlePickFile(requestId: string, payload: Record<string, Object>): Promise<void> {
    const multiple = typeof payload['multiple'] === 'boolean' ? (payload['multiple'] as boolean) : false;
    const includeBase64 = typeof payload['includeBase64'] === 'boolean' ? (payload['includeBase64'] as boolean) : true;
    try {
      const docPicker = new picker.DocumentViewPicker();
      const uris = await docPicker.select({ maxSelectNumber: multiple ? 10 : 1 });
      const files = this.readUrisAsPickedFiles(uris, 'application/octet-stream', includeBase64);
      const out: Record<string, Object> = {
        'cancelled': files.length === 0,
        'files': files
      };
      this.sendOk(requestId, JSON.stringify(out));
    } catch {
      this.sendOk(requestId, '{"cancelled":true,"files":[]}');
    }
  }

  private readUrisAsPickedFiles(uris: string[], fallbackMime: string, includeBase64: boolean): Record<string, Object>[] {
    const out: Record<string, Object>[] = [];
    for (let i = 0; i < uris.length; i++) {
      const uri = uris[i];
      try {
        const f = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(f.fd);
        const sizeBytes = stat.size;
        const readCap = Math.min(sizeBytes, HarmonyPluginNativeCapabilities.MAX_BASE64_BYTES);
        const buf = new ArrayBuffer(readCap);
        const readLen = readCap > 0 ? fileIo.readSync(f.fd, buf) : 0;
        fileIo.closeSync(f);
        let name = `file_${Date.now()}_${i}`;
        try {
          name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1)) || name;
        } catch {
          // keep default name
        }
        const item: Record<string, Object> = {
          'name': name,
          'mimeType': fallbackMime,
          'sizeBytes': sizeBytes,
          'truncated': includeBase64 && sizeBytes > HarmonyPluginNativeCapabilities.MAX_BASE64_BYTES
        };
        if (includeBase64 && sizeBytes <= HarmonyPluginNativeCapabilities.MAX_BASE64_BYTES) {
          item['base64'] = this.base64Helper.encodeToStringSync(new Uint8Array(buf, 0, readLen));
        }
        out.push(item);
      } catch {
        // skip unreadable item
      }
    }
    return out;
  }

  private async handleSaveMedia(requestId: string, payload: Record<string, Object>): Promise<void> {
    const fileName = typeof payload['fileName'] === 'string' && (payload['fileName'] as string).length > 0
      ? (payload['fileName'] as string)
      : `moviepilot_${Date.now()}.png`;
    const bytes = await this.resolveMediaBytes(payload);
    if (!bytes || bytes.byteLength === 0) {
      this.sendErr(requestId, 'INVALID_MEDIA', 400, '无法获取待保存的媒体内容');
      return;
    }
    try {
      const docPicker = new picker.DocumentViewPicker();
      const saveOpt = new picker.DocumentSaveOptions();
      saveOpt.newFileNames = [fileName];
      const uris = await docPicker.save(saveOpt);
      if (uris.length === 0) {
        this.sendOk(requestId, '{"saved":false}');
        return;
      }
      const f = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      fileIo.closeSync(f);
      this.sendOk(requestId, '{"saved":true}');
    } catch (err) {
      this.sendErr(requestId, 'SAVE_MEDIA_FAILED', 500, err ? String(err) : '保存媒体失败');
    }
  }

  private async resolveMediaBytes(payload: Record<string, Object>): Promise<Uint8Array | null> {
    const rawB64 = typeof payload['base64'] === 'string' ? (payload['base64'] as string) : '';
    if (rawB64.length > 0) {
      try {
        return this.base64Helper.decodeSync(this.stripDataUriPrefix(rawB64));
      } catch {
        return null;
      }
    }
    const rawApi = typeof payload['apiPath'] === 'string' ? (payload['apiPath'] as string) : '';
    if (rawApi.length > 0) {
      const normalized = RustCoreBridge.validatePluginApiPath(rawApi);
      const origin = this.getServerUrl();
      const token = this.getAuthToken();
      if (!normalized || origin.length === 0 || token.length === 0) {
        return null;
      }
      return await this.downloadBytes(`${origin}${normalized}`, { 'Authorization': `Bearer ${token}` });
    }
    const rawUrl = typeof payload['url'] === 'string' ? (payload['url'] as string) : '';
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return await this.downloadBytes(rawUrl, {});
    }
    return null;
  }

  private async downloadBytes(url: string, headers: Record<string, string>): Promise<Uint8Array | null> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      req.destroy();
      if (resp.responseCode >= 200 && resp.responseCode < 300 && resp.result instanceof ArrayBuffer) {
        return new Uint8Array(resp.result);
      }
      return null;
    } catch {
      try { req.destroy(); } catch { /* ignore */ }
      return null;
    }
  }

  private async handleScanCode(requestId: string): Promise<void> {
    const ctx = this.getContext();
    if (!ctx) {
      this.sendErr(requestId, 'NO_CONTEXT', 500, '当前上下文无法调用系统扫码');
      return;
    }
    try {
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: false,
        enableAlbum: true
      };
      const result = await scanBarcode.startScanForResult(ctx, options);
      const val = result.originalValue ?? '';
      if (val.length > 0) {
        this.sendOk(requestId, `{"cancelled":false,"value":${JSON.stringify(val)},"format":${JSON.stringify(String(result.scanType ?? 'qr'))}}`);
      } else {
        this.sendOk(requestId, '{"cancelled":true}');
      }
    } catch {
      this.sendOk(requestId, '{"cancelled":true}');
    }
  }

  private handleAuthenticate(requestId: string, payload: Record<string, Object>): void {
    const reason = typeof payload['reason'] === 'string' && (payload['reason'] as string).length > 0
      ? (payload['reason'] as string)
      : '验证身份以继续插件操作';
    try {
      const authParam: userAuth.AuthParam = {
        challenge: new Uint8Array([49, 49, 49, 49, 49, 49]),
        authType: [userAuth.UserAuthType.PIN, userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: userAuth.AuthTrustLevel.ATL1
      };
      const widgetParam: userAuth.WidgetParam = { title: reason };
      const instance = userAuth.getUserAuthInstance(authParam, widgetParam);
      instance.on('result', {
        onResult: (res: userAuth.UserAuthResult) => {
          const ok = res.result === userAuth.UserAuthResultCode.SUCCESS;
          this.sendOk(requestId, `{"authenticated":${ok ? 'true' : 'false'},"biometryType":"system"}`);
        }
      });
      instance.start();
    } catch {
      this.sendOk(requestId, '{"authenticated":false,"biometryType":"none"}');
    }
  }

  // MARK: - Audio Recording (`audio.record.*`)

  private async handleRecordStart(requestId: string, payload: Record<string, Object>): Promise<void> {
    const granted = await this.checkOrRequestOhosPermission('ohos.permission.MICROPHONE', true);
    if (!granted) {
      this.sendErr(requestId, 'PERMISSION_DENIED', 403, '未获得麦克风权限，请在系统设置中允许访问麦克风');
      return;
    }
    const ctx = this.getContext();
    if (!ctx) {
      this.sendErr(requestId, 'NO_CONTEXT', 500, '无法获取录音上下文');
      return;
    }
    await this.cancelActiveRecording(false);
    await this.stopInlinePlayback(false);

    const sampleRate = typeof payload['sampleRate'] === 'number'
      ? Math.max(8000, Math.min(48000, Math.floor(payload['sampleRate'] as number)))
      : 44100;
    const channels = typeof payload['channels'] === 'number'
      ? Math.max(1, Math.min(2, Math.floor(payload['channels'] as number)))
      : 1;
    const bitRate = typeof payload['bitRate'] === 'number'
      ? Math.max(16000, Math.min(256000, Math.floor(payload['bitRate'] as number)))
      : 96000;
    const maxSec = typeof payload['maxDurationSec'] === 'number'
      ? Math.max(1, Math.min(1800, payload['maxDurationSec'] as number))
      : 300;
    const metering = typeof payload['metering'] === 'boolean' ? (payload['metering'] as boolean) : true;

    try {
      const recId = `rec_${Date.now()}`;
      const path = `${ctx.cacheDir}/${recId}.m4a`;
      const f = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const recorder = await media.createAVRecorder();
      this.avRecorder = recorder;
      this.recordingId = recId;
      this.recordFilePath = path;
      this.recordFileFd = f.fd;

      await recorder.prepare({
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: bitRate,
          audioChannels: channels,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: sampleRate,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${f.fd}`
      });
      await recorder.start();

      const now = Date.now();
      this.recordStartedAtMs = now;
      this.recordPausedAccumMs = 0;
      this.recordPausedAtMs = 0;
      this.recordMaxDurationMs = Math.round(maxSec * 1000);
      this.recordMetering = metering;
      this.isRecordingPaused = false;
      this.startRecordingTimer();

      this.sendDeviceEvent('audio.record.state', `{"recordingId":${JSON.stringify(recId)},"state":"recording","durationMs":0}`);
      this.sendOk(requestId, `{"recordingId":${JSON.stringify(recId)},"mimeType":"audio/mp4","format":"m4a","startedAt":${now}}`);
    } catch (err) {
      await this.cancelActiveRecording(false);
      this.sendErr(requestId, 'RECORD_START_FAILED', 500, err ? String(err) : '无法启动鸿蒙原生录音');
    }
  }

  private async handleRecordPause(requestId: string): Promise<void> {
    if (!this.avRecorder || this.recordingId.length === 0) {
      this.sendErr(requestId, 'NOT_RECORDING', 400, '当前未在录音');
      return;
    }
    if (!this.isRecordingPaused) {
      try { await this.avRecorder.pause(); } catch { /* ignore */ }
      this.isRecordingPaused = true;
      this.recordPausedAtMs = Date.now();
    }
    const dur = this.currentRecordingDurationMs();
    this.sendDeviceEvent('audio.record.state', `{"recordingId":${JSON.stringify(this.recordingId)},"state":"paused","durationMs":${dur}}`);
    this.sendOk(requestId, `{"recordingId":${JSON.stringify(this.recordingId)},"state":"paused","durationMs":${dur}}`);
  }

  private async handleRecordResume(requestId: string): Promise<void> {
    if (!this.avRecorder || this.recordingId.length === 0) {
      this.sendErr(requestId, 'NOT_RECORDING', 400, '当前未在录音');
      return;
    }
    if (this.isRecordingPaused) {
      if (this.recordPausedAtMs > 0) {
        this.recordPausedAccumMs += Math.max(0, Date.now() - this.recordPausedAtMs);
      }
      this.recordPausedAtMs = 0;
      this.isRecordingPaused = false;
      try { await this.avRecorder.resume(); } catch { /* ignore */ }
    }
    const dur = this.currentRecordingDurationMs();
    this.sendDeviceEvent('audio.record.state', `{"recordingId":${JSON.stringify(this.recordingId)},"state":"recording","durationMs":${dur}}`);
    this.sendOk(requestId, `{"recordingId":${JSON.stringify(this.recordingId)},"state":"recording","durationMs":${dur}}`);
  }

  private async handleRecordStop(requestId: string, payload: Record<string, Object>): Promise<void> {
    if (!this.avRecorder || this.recordingId.length === 0) {
      this.sendErr(requestId, 'NOT_RECORDING', 400, '当前没有进行中的录音');
      return;
    }
    const includeBase64 = typeof payload['includeBase64'] === 'boolean' ? (payload['includeBase64'] as boolean) : true;
    const recId = this.recordingId;
    const path = this.recordFilePath;
    const dur = this.currentRecordingDurationMs();

    this.stopRecordingTimer();
    try { await this.avRecorder.stop(); } catch { /* ignore */ }
    try { await this.avRecorder.release(); } catch { /* ignore */ }
    this.avRecorder = null;
    if (this.recordFileFd >= 0) {
      try { fileIo.closeSync(this.recordFileFd); } catch { /* ignore */ }
      this.recordFileFd = -1;
    }
    this.recordingId = '';
    this.recordFilePath = '';
    this.recordStartedAtMs = 0;
    this.recordPausedAtMs = 0;
    this.recordPausedAccumMs = 0;
    this.isRecordingPaused = false;

    let sizeBytes = 0;
    let b64 = '';
    let truncated = false;
    try {
      const f = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(f.fd);
      sizeBytes = stat.size;
      if (includeBase64 && sizeBytes > 0 && sizeBytes <= HarmonyPluginNativeCapabilities.MAX_BASE64_BYTES) {
        const buf = new ArrayBuffer(sizeBytes);
        const readLen = fileIo.readSync(f.fd, buf);
        b64 = this.base64Helper.encodeToStringSync(new Uint8Array(buf, 0, readLen));
      } else if (includeBase64 && sizeBytes > HarmonyPluginNativeCapabilities.MAX_BASE64_BYTES) {
        truncated = true;
      }
      fileIo.closeSync(f);
    } catch {
      // ignore read failure
    }
    try { fileIo.unlinkSync(path); } catch { /* ignore */ }

    const out: Record<string, Object> = {
      'recordingId': recId,
      'durationMs': dur,
      'sizeBytes': sizeBytes,
      'mimeType': 'audio/mp4',
      'fileName': `${recId}.m4a`,
      'truncated': truncated
    };
    if (b64.length > 0) {
      out['base64'] = b64;
    }
    this.sendDeviceEvent('audio.record.state', `{"recordingId":${JSON.stringify(recId)},"state":"stopped","durationMs":${dur}}`);
    this.sendOk(requestId, JSON.stringify(out));
  }

  private async cancelActiveRecording(emitEvent: boolean): Promise<void> {
    const recId = this.recordingId;
    const path = this.recordFilePath;
    this.stopRecordingTimer();
    if (this.avRecorder) {
      try { await this.avRecorder.stop(); } catch { /* ignore */ }
      try { await this.avRecorder.release(); } catch { /* ignore */ }
      this.avRecorder = null;
    }
    if (this.recordFileFd >= 0) {
      try { fileIo.closeSync(this.recordFileFd); } catch { /* ignore */ }
      this.recordFileFd = -1;
    }
    if (path.length > 0) {
      try { fileIo.unlinkSync(path); } catch { /* ignore */ }
    }
    this.recordingId = '';
    this.recordFilePath = '';
    this.recordStartedAtMs = 0;
    this.recordPausedAtMs = 0;
    this.recordPausedAccumMs = 0;
    this.isRecordingPaused = false;
    if (emitEvent && recId.length > 0) {
      this.sendDeviceEvent('audio.record.state', `{"recordingId":${JSON.stringify(recId)},"state":"cancelled","durationMs":0}`);
    }
  }

  private startRecordingTimer(): void {
    this.stopRecordingTimer();
    this.recordTimer = setInterval(() => {
      if (!this.avRecorder || this.recordingId.length === 0 || this.isRecordingPaused) {
        return;
      }
      const dur = this.currentRecordingDurationMs();
      if (this.recordMetering) {
        this.avRecorder.getAudioCapturerMaxAmplitude().then((amp: number) => {
          const clamped = Math.max(0, Math.min(32767, amp));
          const normalized = clamped / 32767.0;
          const db = clamped > 0 ? 20.0 * Math.log10(normalized) : -60.0;
          this.sendDeviceEvent(
            'audio.record.level',
            `{"recordingId":${JSON.stringify(this.recordingId)},"durationMs":${dur},"meteringDb":${db.toFixed(2)},"normalizedLevel":${normalized.toFixed(4)}}`
          );
        }).catch(() => {});
      }
      if (dur >= this.recordMaxDurationMs) {
        this.isRecordingPaused = true;
        this.recordPausedAtMs = Date.now();
        this.avRecorder.pause().catch(() => {});
        this.sendDeviceEvent(
          'audio.record.state',
          `{"recordingId":${JSON.stringify(this.recordingId)},"state":"paused","durationMs":${dur},"message":"已达最大录音时长上限"}`
        );
      }
    }, 150);
  }

  private stopRecordingTimer(): void {
    if (this.recordTimer !== -1) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
  }

  private currentRecordingDurationMs(): number {
    if (this.recordStartedAtMs <= 0) {
      return 0;
    }
    const endRef = this.recordPausedAtMs > 0 ? this.recordPausedAtMs : Date.now();
    return Math.max(0, endRef - this.recordStartedAtMs - this.recordPausedAccumMs);
  }

  private currentRecordStatusObj(): Record<string, Object> {
    if (!this.avRecorder || this.recordingId.length === 0) {
      return { 'state': 'idle', 'durationMs': 0 };
    }
    return {
      'state': this.isRecordingPaused ? 'paused' : 'recording',
      'recordingId': this.recordingId,
      'durationMs': this.currentRecordingDurationMs()
    };
  }

  // MARK: - Inline Audio Playback (`audio.*`)

  private async handleAudioPlay(requestId: string, payload: Record<string, Object>): Promise<void> {
    await this.stopInlinePlayback(false);

    const loop = typeof payload['loop'] === 'boolean' ? (payload['loop'] as boolean) : false;
    const volume = typeof payload['volume'] === 'number' ? Math.max(0, Math.min(1, payload['volume'] as number)) : 1.0;
    const rate = typeof payload['rate'] === 'number' ? Math.max(0.5, Math.min(2.0, payload['rate'] as number)) : 1.0;
    const startPosMs = typeof payload['startPositionMs'] === 'number' ? Math.max(0, Math.floor(payload['startPositionMs'] as number)) : 0;
    const showInStatusBar = typeof payload['showInStatusBar'] === 'boolean' ? (payload['showInStatusBar'] as boolean) : true;
    const playTitle = typeof payload['title'] === 'string' ? (payload['title'] as string).trim() : '';
    const playArtist = typeof payload['artist'] === 'string' ? (payload['artist'] as string).trim() : '';
    const playAlbum = typeof payload['album'] === 'string' ? (payload['album'] as string).trim() : '';
    const playArtworkUrl = typeof payload['artworkUrl'] === 'string' ? (payload['artworkUrl'] as string).trim() : '';

    const rawB64 = typeof payload['base64'] === 'string' ? (payload['base64'] as string) : '';
    const storage = typeof payload['storage'] === 'string' ? (payload['storage'] as string) : '';
    const path = typeof payload['path'] === 'string' ? (payload['path'] as string) : '';
    const rawApi = typeof payload['apiPath'] === 'string' ? (payload['apiPath'] as string) : '';
    const rawUrl = typeof payload['url'] === 'string' ? (payload['url'] as string) : '';

    const playId = `play_${Date.now()}`;
    this.playbackId = playId;
    this.playbackLoop = loop;
    this.playbackVolume = volume;
    this.playbackRate = rate;
    this.playbackState = 'loading';
    this.playbackDurationMs = 0;
    this.playbackPositionMs = 0;

    try {
      const player = await media.createAVPlayer();
      this.avPlayer = player;
      let responded = false;

      player.on('timeUpdate', (ms: number) => {
        if (this.playbackId === playId && Number.isFinite(ms) && ms >= 0) {
          this.playbackPositionMs = Math.floor(ms);
        }
      });
      player.on('durationUpdate', (ms: number) => {
        if (this.playbackId === playId && Number.isFinite(ms) && ms > 0) {
          this.playbackDurationMs = Math.floor(ms);
        }
      });
      player.on('error', (err) => {
        if (this.playbackId !== playId) { return; }
        const msg = err ? String(err.message ?? err) : '音频播放失败';
        this.playbackState = 'error';
        this.stopPlaybackProgressTimer();
        this.sendDeviceEvent('audio.play.error', `{"playbackId":${JSON.stringify(playId)},"code":"AVPLAYER_ERROR","message":${JSON.stringify(msg)}}`);
        if (!responded) {
          responded = true;
          this.sendErr(requestId, 'AUDIO_PLAY_FAILED', 500, msg);
        }
      });
      player.on('stateChange', (state: string) => {
        if (this.playbackId !== playId) { return; }
        if (state === 'initialized') {
          player.prepare().catch(() => {});
        } else if (state === 'prepared') {
          player.loop = loop;
          player.setVolume(volume);
          if (startPosMs > 0) {
            player.seek(startPosMs);
          }
          player.play().catch(() => {});
        } else if (state === 'playing') {
          this.playbackState = 'playing';
          this.applyPlaybackRate(player, rate);
          this.startPlaybackProgressTimer();
          if (showInStatusBar && playTitle.length > 0 && !responded) {
            this.applyNowPlayingSession(
              playTitle,
              playArtist,
              playAlbum,
              playArtworkUrl,
              this.playbackDurationMs,
              startPosMs,
              true,
              rate
            ).catch(() => {});
          }
          this.emitPlaybackState();
          if (!responded) {
            responded = true;
            this.sendOk(requestId, `{"playbackId":${JSON.stringify(playId)},"state":"playing","durationMs":${this.playbackDurationMs}}`);
          }
        } else if (state === 'paused') {
          this.playbackState = 'paused';
          this.emitPlaybackState();
        } else if (state === 'completed') {
          if (!this.playbackLoop) {
            this.playbackState = 'ended';
            this.stopPlaybackProgressTimer();
            this.sendDeviceEvent('audio.play.ended', `{"playbackId":${JSON.stringify(playId)},"durationMs":${this.playbackDurationMs}}`);
            this.emitPlaybackState();
          }
        }
      });

      if (rawB64.length > 0) {
        const ctx = this.getContext();
        if (!ctx) {
          throw new Error('无法获取播放缓存目录');
        }
        const bytes = this.base64Helper.decodeSync(this.stripDataUriPrefix(rawB64));
        const mime = typeof payload['mimeType'] === 'string' ? (payload['mimeType'] as string).toLowerCase() : '';
        const ext = mime.includes('wav') ? 'wav' : (mime.includes('mpeg') ? 'mp3' : 'm4a');
        const tempPath = `${ctx.cacheDir}/${playId}.${ext}`;
        const wf = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.writeSync(wf.fd, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
        fileIo.closeSync(wf);
        const rf = fileIo.openSync(tempPath, fileIo.OpenMode.READ_ONLY);
        this.playbackTempPath = tempPath;
        this.playbackFd = rf.fd;
        player.fdSrc = { fd: rf.fd };
      } else if (storage.length > 0 && path.length > 0) {
        const resolved = await this.resolveStorageStreamSource(storage, path);
        if (resolved.authHeader.length > 0) {
          const src = media.createMediaSourceWithUrl(resolved.url, { 'Authorization': resolved.authHeader });
          await player.setMediaSource(src, { preferredBufferDuration: 8 });
        } else {
          player.url = resolved.url;
        }
      } else if (rawApi.length > 0) {
        const normalized = RustCoreBridge.validatePluginApiPath(rawApi);
        const origin = this.getServerUrl();
        const token = this.getAuthToken();
        if (!normalized || origin.length === 0 || token.length === 0) {
          throw new Error('非法或未认证的 API 路径');
        }
        const src = media.createMediaSourceWithUrl(`${origin}${normalized}`, {
          'Authorization': `Bearer ${token}`,
          'X-MoviePilot-Locale': 'zh-CN'
        });
        await player.setMediaSource(src, { preferredBufferDuration: 8 });
      } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
        player.url = rawUrl;
      } else {
        throw new Error('请提供 url、base64、apiPath 或 storage+path 音频源');
      }
    } catch (err) {
      await this.stopInlinePlayback(false);
      this.sendErr(requestId, 'AUDIO_PLAY_FAILED', 500, err ? String(err) : '无法启动原生音频播放');
    }
  }

  private async handleAudioPause(requestId: string): Promise<void> {
    if (this.avPlayer) {
      try { await this.avPlayer.pause(); } catch { /* ignore */ }
      this.playbackState = 'paused';
    }
    this.emitPlaybackState();
    this.sendOk(requestId, JSON.stringify(this.currentPlaybackStatusObj()));
  }

  private async handleAudioResume(requestId: string): Promise<void> {
    if (this.avPlayer) {
      try { await this.avPlayer.play(); } catch { /* ignore */ }
      this.playbackState = 'playing';
      this.startPlaybackProgressTimer();
    }
    this.emitPlaybackState();
    this.sendOk(requestId, JSON.stringify(this.currentPlaybackStatusObj()));
  }

  private handleAudioSeek(requestId: string, payload: Record<string, Object>): void {
    const posMs = typeof payload['positionMs'] === 'number' ? Math.max(0, Math.floor(payload['positionMs'] as number)) : 0;
    if (this.avPlayer) {
      try { this.avPlayer.seek(posMs); } catch { /* ignore */ }
      this.playbackPositionMs = posMs;
    }
    this.sendOk(requestId, JSON.stringify(this.currentPlaybackStatusObj()));
  }

  private handleAudioSetRate(requestId: string, payload: Record<string, Object>): void {
    const rate = typeof payload['rate'] === 'number' ? Math.max(0.5, Math.min(2.0, payload['rate'] as number)) : 1.0;
    this.playbackRate = rate;
    if (this.avPlayer) {
      this.applyPlaybackRate(this.avPlayer, rate);
    }
    this.sendOk(requestId, `{"playbackId":${JSON.stringify(this.playbackId)},"rate":${rate}}`);
  }

  private handleAudioSetVolume(requestId: string, payload: Record<string, Object>): void {
    const vol = typeof payload['volume'] === 'number' ? Math.max(0, Math.min(1, payload['volume'] as number)) : 1.0;
    this.playbackVolume = vol;
    if (this.avPlayer) {
      try { this.avPlayer.setVolume(vol); } catch { /* ignore */ }
    }
    this.sendOk(requestId, `{"playbackId":${JSON.stringify(this.playbackId)},"volume":${vol}}`);
  }

  private applyPlaybackRate(player: media.AVPlayer, rate: number): void {
    try {
      let speed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
      if (rate <= 0.8) {
        speed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
      } else if (rate >= 1.85) {
        speed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
      } else if (rate >= 1.6) {
        speed = media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
      } else if (rate >= 1.35) {
        speed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
      }
      player.setSpeed(speed);
    } catch {
      // ignore speed errors
    }
  }

  private async stopInlinePlayback(emitEvent: boolean): Promise<void> {
    const oldId = this.playbackId;
    this.stopPlaybackProgressTimer();
    if (this.avPlayer) {
      try { await this.avPlayer.stop(); } catch { /* ignore */ }
      try { await this.avPlayer.release(); } catch { /* ignore */ }
      this.avPlayer = null;
    }
    if (this.playbackFd >= 0) {
      try { fileIo.closeSync(this.playbackFd); } catch { /* ignore */ }
      this.playbackFd = -1;
    }
    if (this.playbackTempPath.length > 0) {
      try { fileIo.unlinkSync(this.playbackTempPath); } catch { /* ignore */ }
      this.playbackTempPath = '';
    }
    this.playbackId = '';
    this.playbackState = 'idle';
    this.playbackDurationMs = 0;
    this.playbackPositionMs = 0;
    if (emitEvent && oldId.length > 0) {
      this.sendDeviceEvent(
        'audio.play.state',
        `{"playbackId":${JSON.stringify(oldId)},"state":"stopped","positionMs":0,"durationMs":0,"rate":${this.playbackRate},"volume":${this.playbackVolume}}`
      );
    }
  }

  private startPlaybackProgressTimer(): void {
    this.stopPlaybackProgressTimer();
    this.playbackProgressTimer = setInterval(() => {
      if (this.playbackState === 'playing' && this.playbackId.length > 0) {
        this.sendDeviceEvent(
          'audio.play.progress',
          `{"playbackId":${JSON.stringify(this.playbackId)},"positionMs":${this.playbackPositionMs},"durationMs":${this.playbackDurationMs}}`
        );
      }
    }, 250);
  }

  private stopPlaybackProgressTimer(): void {
    if (this.playbackProgressTimer !== -1) {
      clearInterval(this.playbackProgressTimer);
      this.playbackProgressTimer = -1;
    }
  }

  private currentPlaybackStatusObj(): Record<string, Object> {
    const out: Record<string, Object> = {
      'state': this.playbackState,
      'positionMs': this.playbackPositionMs,
      'durationMs': this.playbackDurationMs,
      'rate': this.playbackRate,
      'volume': this.playbackVolume
    };
    if (this.playbackId.length > 0) {
      out['playbackId'] = this.playbackId;
    }
    return out;
  }

  private emitPlaybackState(): void {
    this.sendDeviceEvent('audio.play.state', JSON.stringify(this.currentPlaybackStatusObj()));
    if (this.nowPlayingActive && this.pluginAvSession) {
      this.syncPluginAvSessionState();
    }
  }

  // MARK: - Status Bar / AVSession Now Playing (`audio.setNowPlaying` / `audio.clearNowPlaying`)

  private async handleAudioSetNowPlaying(requestId: string, payload: Record<string, Object>): Promise<void> {
    const title = typeof payload['title'] === 'string' ? (payload['title'] as string).trim() : '';
    if (title.length === 0) {
      this.sendErr(requestId, 'INVALID_PARAMS', 400, 'title 不能为空');
      return;
    }
    const artist = typeof payload['artist'] === 'string' ? (payload['artist'] as string).trim() : '';
    const album = typeof payload['album'] === 'string' ? (payload['album'] as string).trim() : '';
    const artworkUrl = typeof payload['artworkUrl'] === 'string' ? (payload['artworkUrl'] as string).trim() : '';
    const durationMs = typeof payload['durationMs'] === 'number' ? Math.max(0, Math.floor(payload['durationMs'] as number)) : this.playbackDurationMs;
    const positionMs = typeof payload['positionMs'] === 'number' ? Math.max(0, Math.floor(payload['positionMs'] as number)) : this.playbackPositionMs;
    const isPlaying = typeof payload['isPlaying'] === 'boolean' ? (payload['isPlaying'] as boolean) : (this.playbackState === 'playing');
    const rate = typeof payload['rate'] === 'number' ? (payload['rate'] as number) : this.playbackRate;

    await this.applyNowPlayingSession(title, artist, album, artworkUrl, durationMs, positionMs, isPlaying, rate);
    this.sendOk(requestId, '{"registered":true}');
  }

  private async applyNowPlayingSession(
    title: string,
    artist: string,
    album: string,
    artworkUrl: string,
    durationMs: number,
    positionMs: number,
    isPlaying: boolean,
    rate: number
  ): Promise<void> {
    const ctx = this.getContext();
    if (!ctx) {
      return;
    }
    this.nowPlayingActive = true;
    this.nowPlayingTitle = title;
    this.nowPlayingArtist = artist;
    this.nowPlayingAlbum = album;
    this.nowPlayingDurationMs = durationMs;

    try {
      if (!this.pluginAvSession) {
        const s = await avSession.createAVSession(ctx, 'MoviePilotPluginAudio', 'audio');
        s.on('play', () => {
          if (this.avPlayer) {
            this.avPlayer.play().catch(() => {});
            this.playbackState = 'playing';
            this.startPlaybackProgressTimer();
            this.emitPlaybackState();
          }
          this.sendDeviceEvent('audio.remoteCommand', '{"command":"play"}');
        });
        s.on('pause', () => {
          if (this.avPlayer) {
            this.avPlayer.pause().catch(() => {});
            this.playbackState = 'paused';
            this.emitPlaybackState();
          }
          this.sendDeviceEvent('audio.remoteCommand', '{"command":"pause"}');
        });
        s.on('stop', () => {
          this.stopInlinePlayback(true).catch(() => {});
          this.clearNowPlayingSession().catch(() => {});
          this.sendDeviceEvent('audio.remoteCommand', '{"command":"stop"}');
        });
        s.on('playNext', () => {
          this.sendDeviceEvent('audio.remoteCommand', '{"command":"next"}');
        });
        s.on('playPrevious', () => {
          this.sendDeviceEvent('audio.remoteCommand', '{"command":"previous"}');
        });
        s.on('seek', (timeMs: number) => {
          const target = Math.max(0, Math.floor(timeMs));
          if (this.avPlayer) {
            try { this.avPlayer.seek(target); } catch { /* ignore */ }
            this.playbackPositionMs = target;
            this.syncPluginAvSessionState();
          }
          this.sendDeviceEvent('audio.remoteCommand', `{"command":"seek","positionMs":${target}}`);
        });
        await s.activate();
        this.pluginAvSession = s;
      }

      const meta: avSession.AVMetadata = {
        assetId: this.playbackId || 'mp_plugin_audio',
        title: title,
        artist: artist,
        album: album,
        duration: durationMs > 0 ? durationMs : undefined
      };
      if (artworkUrl.startsWith('http://') || artworkUrl.startsWith('https://')) {
        meta.mediaImage = artworkUrl;
      }
      await this.pluginAvSession.setAVMetadata(meta);
      await this.pluginAvSession.setAVPlaybackState({
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: isPlaying ? rate : 0,
        position: {
          elapsedTime: Math.max(0, positionMs),
          updateTime: Date.now()
        }
      });
    } catch {
      // 预览器或受限环境忽略 AVSession 异常
    }
  }

  private syncPluginAvSessionState(): void {
    if (!this.pluginAvSession) {
      return;
    }
    try {
      const playing = this.playbackState === 'playing';
      this.pluginAvSession.setAVPlaybackState({
        state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: playing ? this.playbackRate : 0,
        position: {
          elapsedTime: Math.max(0, this.playbackPositionMs),
          updateTime: Date.now()
        }
      }).catch(() => {});
    } catch {
      // ignore
    }
  }

  private async clearNowPlayingSession(): Promise<void> {
    this.nowPlayingActive = false;
    this.nowPlayingTitle = '';
    this.nowPlayingArtist = '';
    this.nowPlayingAlbum = '';
    this.nowPlayingDurationMs = 0;
    if (this.pluginAvSession) {
      const s = this.pluginAvSession;
      this.pluginAvSession = null;
      try { await s.deactivate(); } catch { /* ignore */ }
      try { await s.destroy(); } catch { /* ignore */ }
    }
  }

  private async resolveStorageStreamSource(storage: string, path: string): Promise<ResolvedStreamSource> {
    const origin = this.getServerUrl();
    const token = this.getAuthToken();
    const slashIdx = path.lastIndexOf('/');
    const fileName = slashIdx >= 0 ? path.substring(slashIdx + 1) : path;
    const dotIdx = fileName.lastIndexOf('.');
    const ext = dotIdx >= 0 ? fileName.substring(dotIdx + 1) : '';

    if (origin.length > 0 && token.length > 0) {
      const req = http.createHttp();
      try {
        const fileObj: Record<string, string> = {};
        fileObj['storage'] = storage;
        fileObj['type'] = 'file';
        fileObj['path'] = path;
        fileObj['name'] = fileName || 'audio';
        fileObj['extension'] = ext;
        const ticketBody: Record<string, Object> = {};
        ticketBody['file'] = fileObj;
        ticketBody['media_type'] = 'audio';
        const reqHeader: Record<string, string> = {};
        reqHeader['Authorization'] = `Bearer ${token}`;
        reqHeader['Content-Type'] = 'application/json; charset=utf-8';
        const resp = await req.request(`${origin}/api/v1/mediaserver/stream-ticket`, {
          method: http.RequestMethod.POST,
          header: reqHeader,
          extraData: JSON.stringify(ticketBody),
          connectTimeout: 10000,
          readTimeout: 15000,
          expectDataType: http.HttpDataType.STRING
        });
        req.destroy();
        if (resp.responseCode >= 200 && resp.responseCode < 300 && typeof resp.result === 'string') {
          const parsed = JSON.parse(resp.result) as Record<string, Object>;
          const inner = (parsed['data'] && typeof parsed['data'] === 'object')
            ? (parsed['data'] as Record<string, Object>)
            : parsed;
          const ticketId = typeof inner['item_id'] === 'string' ? (inner['item_id'] as string) : '';
          if (ticketId.length > 0) {
            const infoReq = http.createHttp();
            let contentUrl = '';
            try {
              const infoResp = await infoReq.request(
                `${origin}/api/v1/mediaserver/stream-info?itemid=${encodeURIComponent(ticketId)}`,
                {
                  method: http.RequestMethod.GET,
                  header: { 'Authorization': `Bearer ${token}` },
                  connectTimeout: 10000,
                  readTimeout: 15000,
                  expectDataType: http.HttpDataType.STRING
                }
              );
              infoReq.destroy();
              if (infoResp.responseCode >= 200 && infoResp.responseCode < 300 && typeof infoResp.result === 'string') {
                const infoObj = JSON.parse(infoResp.result) as Record<string, Object>;
                const infoData = (infoObj['data'] && typeof infoObj['data'] === 'object')
                  ? (infoObj['data'] as Record<string, Object>)
                  : infoObj;
                if (typeof infoData['content_url'] === 'string') {
                  contentUrl = infoData['content_url'] as string;
                }
              }
            } catch {
              try { infoReq.destroy(); } catch { /* ignore */ }
            }
            const resolvedUrl = contentUrl.length > 0
              ? (contentUrl.startsWith('http://') || contentUrl.startsWith('https://')
                ? contentUrl
                : `${origin}${contentUrl.startsWith('/') ? contentUrl : '/' + contentUrl}`)
              : `${origin}/api/v1/mediaserver/stream?itemid=${encodeURIComponent(ticketId)}`;
            return { url: resolvedUrl, authHeader: `Bearer ${token}` };
          }
        }
      } catch {
        try { req.destroy(); } catch { /* ignore */ }
      }
    }
    throw new Error('当前存储暂不支持在线流式播放，请检查存储配置或升级后端');
  }

  // MARK: - Full-Screen Native Media Player (`media.playNative`)

  private handlePlayNativeMedia(requestId: string, payload: Record<string, Object>): void {
    const storage = typeof payload['storage'] === 'string' ? (payload['storage'] as string) : '';
    const path = typeof payload['path'] === 'string' ? (payload['path'] as string) : '';
    const itemId = typeof payload['itemId'] === 'string' ? (payload['itemId'] as string) : '';
    const server = typeof payload['server'] === 'string' ? (payload['server'] as string) : '';
    const rawUrl = typeof payload['url'] === 'string' ? (payload['url'] as string) : '';
    const title = typeof payload['title'] === 'string' ? (payload['title'] as string) : '';
    const mediaType = typeof payload['mediaType'] === 'string' ? (payload['mediaType'] as string).toLowerCase() : '';

    let deepLink = '';
    if (storage.length > 0 && path.length > 0) {
      deepLink = `moviepilot://play?storage=${encodeURIComponent(storage)}&path=${encodeURIComponent(path)}`;
      if (title.length > 0) { deepLink += `&title=${encodeURIComponent(title)}`; }
    } else if (itemId.length > 0) {
      deepLink = `moviepilot://play?itemid=${encodeURIComponent(itemId)}`;
      if (server.length > 0) { deepLink += `&server=${encodeURIComponent(server)}`; }
      if (title.length > 0) { deepLink += `&title=${encodeURIComponent(title)}`; }
    } else if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      deepLink = `moviepilot://play?url=${encodeURIComponent(rawUrl)}`;
      if (title.length > 0) { deepLink += `&title=${encodeURIComponent(title)}`; }
      if (mediaType === 'audio' || mediaType === 'video') { deepLink += `&type=${mediaType}`; }
    } else {
      this.sendErr(requestId, 'INVALID_MEDIA', 400, '请提供 url、storage+path 或 itemId 媒体参数');
      return;
    }

    this.openDeepLink(deepLink);
    this.sendOk(requestId, '{"launched":true}');
  }

  // MARK: - Helpers

  private resolveAppVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName || '2.0.3';
    } catch {
      return '2.0.3';
    }
  }

  private currentNetworkType(): string {
    try {
      const net = connection.getDefaultNetSync();
      const caps = connection.getNetCapabilitiesSync(net);
      if (caps && Array.isArray(caps.bearerTypes)) {
        if (caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) { return 'wifi'; }
        if (caps.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR)) { return 'cellular'; }
        if (caps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET)) { return 'ethernet'; }
      }
    } catch {
      // ignore
    }
    return 'unknown';
  }

  private stripDataUriPrefix(raw: string): string {
    const comma = raw.indexOf(',');
    if (comma > 0 && raw.substring(0, comma).toLowerCase().includes('base64')) {
      return raw.substring(comma + 1);
    }
    return raw;
  }

  private hashCode(input: string): number {
    let h = 0;
    for (let i = 0; i < input.length; i++) {
      h = ((h << 5) - h + input.charCodeAt(i)) | 0;
    }
    return h;
  }

  private sendOk(requestId: string, dataJson: string): void {
    if (requestId.length === 0) { return; }
    this.sendResponse(requestId, true, dataJson);
  }

  private sendErr(requestId: string, code: string, status: number, message: string): void {
    if (requestId.length === 0) { return; }
    this.sendResponse(requestId, false, '{}', code, status, message);
  }
}

interface ResolvedStreamSource {
  url: string;
  authHeader: string;
}
