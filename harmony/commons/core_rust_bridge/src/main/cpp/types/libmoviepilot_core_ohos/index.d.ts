// ohos-rs (mp-ffi-ohos) Node-API 类型声明文件，与 shared/core-rust/crates/mp-ffi-ohos 1:1 对齐。
export declare function coreVersion(): string;
export declare function normalizeServerAddress(raw: string): string;
export declare function serverAddressContains(baseUrl: string, candidateUrl: string): boolean;
export declare function buildV3EndpointUrl(baseUrl: string, segments: string[], queryJson: string, trailingSlash: boolean): string;
export declare function parseDeepLinkJson(rawUrl: string): string;
export declare function detectPlayableMediaKind(pathOrExt: string, includeStreaming: boolean): string;
export declare function parseAgentMarkdownJson(markdown: string): string;
export declare function filterAndGroupResources(resourcesJson: string, criteriaJson: string): string;
export declare function decodeJwtClaimsJson(token: string, nowEpochSecs: number): string;
export declare function evaluatePermissionsJson(permissionsJson: string, isSuperuser: boolean): string;
export declare function classifyAuthStatusStr(status: number, body: string): string;
export declare function planPluginFormJson(documentJson: string): string;
export declare function applyPluginFormPatch(originalModelJson: string, patchJson: string): string;
export declare function evaluatePluginExpression(expr: string, modelJson: string): boolean;
export declare function analyzeCronJson(expr: string): string;
export declare function computeMedalPaletteJson(medalId: string): string;
export declare function computeSubscribeProgressJson(total: number, lack: number): string;
export declare function validatePluginBridgeApiPath(rawPath: string): string;
export declare function validatePluginShellAsset(virtualPath: string): string;
export declare function buildPluginRemoteCacheKeyJson(instanceOrigin: string, pluginId: string, versionOrHash: string): string;
export declare function normalizePluginRemoteEntryJson(pluginId: string, versionOrHash: string, rawRemoteUrl: string): string;
export declare function resolvePluginRemoteUpstreamJson(virtualPath: string): string;
export declare function detectCloudflareAccessChallengeJson(status: number, headersJson: string, body: string, requestUrl: string): string;
export declare function generatePkcePairJson(extraEntropy: string): string;
export declare function computePkceS256Challenge(codeVerifier: string): string;
export declare function buildOauthDiscoveryUrlsJson(serverUrl: string, resourceMetadataUrl: string): string;
export declare function parseProtectedResourceMetadataJson(jsonStr: string): string;
export declare function parseProtectedResourceMetadataDetailJson(jsonStr: string): string;
export declare function normalizeOauthResourceUrl(rawUrl: string): string;
export declare function parseOauthServerMetadataJson(jsonStr: string): string;
export declare function buildOauthAuthorizeUrl(
  authorizationEndpoint: string,
  clientId: string,
  redirectUri: string,
  codeChallenge: string,
  state: string,
  scope: string,
  resource: string
): string;
export declare function parseOauthCallbackUrlJson(callbackUrl: string, expectedState: string): string;
export declare function mergeCfAccessCookie(existingCookieHeader: string, cfToken: string): string;
export declare function parseAudioEmbeddedMetadataJson(headBase64: string, tailBase64: string): string;
