import { common, Want } from '@kit.AbilityKit';
import { HarmonyPlaybackRequest } from '../MediaPlayerModels';

/**
 * 校验并提取可安全传递给外部视频/音乐应用的 URI：
 * - 仅放行本机文件（`file://` / `fdPath`）或无 MoviePilot 实例主凭据的外部直链（`strm_direct` 或无绑定 `server` 的 HTTP(S) 直链）；
 * - 严禁将 MoviePilot 同源代理地址与个人会话 Cookie/JWT 暴露给第三方应用。
 */
export function resolveSafeExternalUri(req: HarmonyPlaybackRequest): string {
  const fdPath = (req.fdPath ?? '').trim();
  if (fdPath.length > 0) {
    return fdPath.startsWith('file://') ? fdPath : `file://${fdPath}`;
  }
  const url = (req.url ?? '').trim();
  if (url.length === 0) {
    return '';
  }
  if (url.startsWith('file://')) {
    return url;
  }
  const lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return '';
  }
  const routeKind = (req.activeRouteKind ?? '').trim();
  const hasServer = (req.server ?? '').trim().length > 0;
  if (routeKind === 'strm_direct' || !hasServer) {
    return url;
  }
  return '';
}

/**
 * 通过鸿蒙标准 `ohos.want.action.viewData` 拉起本机其他视频/音乐应用播放安全媒体 URI。
 */
export async function launchHarmonyExternalPlayer(
  context: common.Context | undefined,
  req: HarmonyPlaybackRequest
): Promise<boolean> {
  if (!context) {
    return false;
  }
  const safeUri = resolveSafeExternalUri(req);
  if (safeUri.length === 0) {
    return false;
  }
  try {
    const abilityCtx = context as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: safeUri,
      type: req.isAudio ? 'audio/*' : 'video/*'
    };
    await abilityCtx.startAbility(want);
    return true;
  } catch {
    return false;
  }
}
