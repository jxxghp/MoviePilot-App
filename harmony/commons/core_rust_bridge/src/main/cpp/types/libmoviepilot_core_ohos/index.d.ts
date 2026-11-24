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
