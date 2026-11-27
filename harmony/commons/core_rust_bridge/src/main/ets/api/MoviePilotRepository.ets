import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { PlaybackRouteCandidate, RustCoreBridge } from '../bridge/RustCoreBridge';
import { NativeRcpTransport, NativeHttpResponse, SseEventChunk, ByteRangeFetchResult } from '../network/NativeRcpTransport';
import { NativeHuksStore } from '../security/NativeHuksStore';
import { CloudflareAccessOAuthManager } from './CloudflareAccessOAuthManager';
import { PasskeyAuthManager } from './PasskeyAuthManager';
import { HarmonyPlaybackProgressReporter } from './HarmonyPlaybackProgressReporter';
import { HarmonyPlaybackRouteResolver } from './HarmonyPlaybackRouteResolver';

export interface MpLoginResult {
  success: boolean;
  requiresOtp: boolean;
  canceled?: boolean;
  token: string;
  userName: string;
  isSuperuser: boolean;
  avatar: string;
  userLevel?: number;
  message: string;
}

export interface MpUsageReportingConfig {
  enabled: boolean;
  serverHost: string;
}

export interface MpMediaItem {
  id: string;
  mediaId: string;
  tmdbId: string;
  doubanId: string;
  title: string;
  enTitle: string;
  year: string;
  type: string;
  overview: string;
  vote: number;
  posterUrl: string;
  backdropUrl: string;
  logoUrl: string;
  source: string;
  inLibrary: boolean;
  subtitle: string;
  percent: number;
  serverName: string;
  playUrl: string;
  serverItemId?: string;
  imdbId?: string;
  tvdbId?: string;
}

export interface MpCastMember {
  id: string;
  name: string;
  character: string;
  profileUrl: string;
}

export interface MpSeasonInfo {
  seasonNumber: number;
  name: string;
  episodeCount: number;
  airDate: string;
  posterUrl: string;
  overview: string;
}

export interface MpMediaDetailBundle {
  item: MpMediaItem;
  cast: MpCastMember[];
  seasons: MpSeasonInfo[];
}

export interface MpDashboardStats {
  movieCount: number;
  tvCount: number;
  episodeCount: number;
  userCount: number;
  musicCount?: number;
  movieMonthly?: number;
  tvMonthly?: number;
  episodeMonthly?: number;
  musicMonthly?: number;
  storageUsedBytes: number;
  storageTotalBytes: number;
  downloadSpeed: number;
  uploadSpeed: number;
  downloadSize: number;
  uploadSize: number;
  memoryPercent: number;
  memoryUsedBytes: number;
  transferCounts: number[];
  scheduleCount: number;
}

export interface MpCommunityMedal {
  id: string;
  title: string;
  subtitle: string;
  category: string;
  tier: number;
  earned: boolean;
  earnedDate: string;
  frontAsset: string;
  backAsset: string;
  badgeAsset: string;
  metricLabel: string;
  worn?: boolean;
  criteria?: string;
  facts?: string[];
}

export interface MpCommunityState {
  githubLogin: string;
  earnedCount: number;
  totalCount: number;
  wornMedalId?: string;
  medals: MpCommunityMedal[];
}

/** 展开的日历事件；保留订阅归属以复用正确来源的详情入口。 */
export interface MpCalendarEpisodeItem {
  subscribeId?: number;
  id: string;
  title: string;
  episodeTitle: string;
  airDate: string;
  seasonNumber: number;
  episodeNumber: number;
  posterUrl: string;
  overview: string;
  tmdbId: string;
}

export interface MpWorkflowActionNode {
  id: string;
  name: string;
  type: string;
  posX: number;
  posY: number;
}

export interface MpWorkflowFlowEdge {
  id: string;
  source: string;
  target: string;
}

export interface MpWorkflowShareItem {
  id: number;
  name: string;
  shareTitle: string;
  shareComment: string;
  shareUser: string;
  count: number;
  rawJson: string;
}

export interface MpAuthorizationItem {
  id: string;
  channel: string;
  name: string;
  status: string;
  createdAt: string;
  expiresAt: string;
  approved: boolean;
}

export interface MpAuthorizationCode {
  code: string;
  expiresIn: number;
  message: string;
}

export interface MpSubscribeItem {
  id: number;
  name: string;
  year: string;
  type: string;
  season: number;
  totalEpisode: number;
  lackEpisode: number;
  state: string;
  posterUrl: string;
  backdropUrl: string;
  vote: number;
  description: string;
  savePath: string;
  quality: string;
  resolution: string;
  effect?: string;
  bestVersion?: boolean;
  startEpisode?: number;
  episodeGroup?: string;
  downloader?: string;
  sites?: number[];
  filterGroups?: string[];
  include?: string;
  exclude?: string;
  customWords?: string;
  searchImdbid?: boolean;
  interval?: number;
  date?: string;
  rawJson?: string;
}

export interface MpSiteItem {
  id: number;
  name: string;
  domain: string;
  url: string;
  isActive: boolean;
  uploadBytes: number;
  downloadBytes: number;
  ratio: number;
  seeding: number;
  seedingSizeBytes: number;
  bonus: number;
  iconDataUri: string;
  priority?: number;
  rss?: string;
  cookie?: string;
  ua?: string;
  proxy?: boolean;
  render?: boolean;
  rawJson?: string;
}

/** 后端媒体搜索来源目录项（对应 `GET /api/v1/media/source`）。 */
export interface MpMediaSearchSource {
  id: string;
  name: string;
  displayName: string;
  mediaTypes: string[];
}

export interface MpResourceItem {
  title: string;
  description: string;
  siteName: string;
  sizeBytes: number;
  seeders: number;
  peers: number;
  resolution: string;
  resourceType: string;
  videoEncode: string;
  volumeFactor: string;
  enclosure: string;
  pageUrl: string;
  siteId?: number;
  pubdate?: string;
  edition?: string;
  audioEncode?: string;
  resourceTeam?: string;
  seasonEpisode?: string;
  labels?: string[];
  downloadVolumeFactor?: number;
  uploadVolumeFactor?: number;
  rawJson?: string;
}

export interface MpDownloadTask {
  hash: string;
  title: string;
  name: string;
  state: string;
  progress: number;
  sizeBytes: number;
  dlspeed: string;
  upspeed: string;
  leftTime: string;
  downloader: string;
}

export interface MpStorageFile {
  name: string;
  path: string;
  type: string;
  sizeBytes: number;
  modifyTime?: number;
  extension: string;
  storage: string;
}

export interface MpTransferHistoryItem {
  id: number;
  title: string;
  year: string;
  type: string;
  seasons: string;
  episodes: string;
  src: string;
  srcStorage: string;
  dest: string;
  destStorage: string;
  mode: string;
  status: boolean;
  date: string;
  posterUrl: string;
  rawJson?: string;
}

export interface MpWorkflowItem {
  id: number;
  name: string;
  description: string;
  timer: string;
  state: string;
  runCount: number;
  actionCount: number;
  actions?: MpWorkflowActionNode[];
  flows?: MpWorkflowFlowEdge[];
  rawJson?: string;
}

export interface MpPluginItem {
  id: string;
  pluginName: string;
  pluginDesc: string;
  pluginVersion: string;
  pluginAuthor: string;
  installed: boolean;
  state: boolean;
  hasPage: boolean;
  iconUrl: string;
  renderMode: string;
  repoUrl?: string;
  hasUpdate?: boolean;
  installCount?: number;
  addTime?: number;
  averageRating?: number;
  pluginLabel?: string;
}

export interface MpUserItem {
  id: number;
  name: string;
  email: string;
  isActive: boolean;
  isSuperuser: boolean;
  avatar: string;
}

export interface MpMessageItem {
  id: string;
  title: string;
  text: string;
  date: string;
  action: number;
  image: string;
}

export interface MpMediaServerLibrary {
  id: string;
  name: string;
  type: string;
  serverName: string;
  serverType?: string;
  imageUrl: string;
  itemCount?: number;
}

export interface MpSubscribeShareItem {
  id: number;
  name: string;
  shareTitle: string;
  shareComment: string;
  shareUser: string;
  year: string;
  type: string;
  posterUrl: string;
  count: number;
  vote: number;
  tmdbId?: string;
  doubanId?: string;
  mediaId?: string;
  rawJson?: string;
}

export interface MpPersonDetail {
  id: string;
  name: string;
  biography: string;
  birthday: string;
  placeOfBirth: string;
  department: string;
  profileUrl: string;
}

export interface MpSchedulerItem {
  id: string;
  name: string;
  provider: string;
  status: string;
  nextRun: string;
}

export interface MpSimpleSettingItem {
  name: string;
  type: string;
  enabled: boolean;
  detail: string;
}

export interface MpMusicAlbum {
  id: string;
  title: string;
  artist: string;
  year: string;
  coverUrl: string;
  rating: number;
  source: string;
  mediaSource?: string;
  mediaId?: string;
  albumId?: string;
  releaseId?: string;
  artistId?: string;
}

/** 音乐单曲曲目条目（`/api/v1/music/album/{id}`）。 */
export interface MpMusicTrackItem {
  id: string;
  mediaSource: string;
  mediaId: string;
  title: string;
  artist: string;
  album: string;
  trackNumber: number;
  discNumber: number;
  durationSec: number;
  year: string;
  coverUrl: string;
}

/** 音乐专辑详情模型（`/api/v1/music/album/{id}`）。 */
export interface MpMusicAlbumDetail {
  id: string;
  mediaId: string;
  releaseId: string;
  title: string;
  artist: string;
  artistId: string;
  albumType: string;
  releaseDate: string;
  year: string;
  overview: string;
  coverUrl: string;
  mediaSource: string;
  totalTracks: number;
  tracks: MpMusicTrackItem[];
}

/** 音乐艺术家详情模型（`/api/v1/music/artist/{id}` & `/albums`）。 */
export interface MpMusicArtistDetail {
  id: string;
  name: string;
  country: string;
  lifeSpan: string;
  overview: string;
  imageUrl: string;
  mediaSource: string;
  albums: MpMusicAlbum[];
}

export interface MpServiceConfig {
  name: string;
  type: string;
  host: string;
  username: string;
  password: string;
  apikey: string;
  playHost: string;
  enabled: boolean;
  isDefault: boolean;
  rawJson: string;
}

export interface MpDirectoryConfig {
  name: string;
  priority: number;
  storage: string;
  downloadPath: string;
  libraryStorage: string;
  libraryPath: string;
  transferType: string;
  monitorType: string;
  renaming: boolean;
  scraping: boolean;
  notify: boolean;
  rawJson: string;
}

export interface MpStorageConfig {
  name: string;
  type: string;
}

export interface MpFilterRuleGroup {
  name: string;
  ruleString: string;
}

/** 外挂或服务端代理字幕轨道模型（`/api/v1/mediaserver/stream-info`）。 */
export interface MpExternalSubtitle {
  index: number;
  subtitleId: string;
  label: string;
  language: string;
  format: string;
  isExternal: boolean;
  url: string;
}

/** 媒体播放流与鉴权头清单（严禁在 `contentUrl` 拼接 `?token=`，统一经 `headers` 同源携带 `Cookie` + `Authorization`）。 */
export interface MpVideoStreamInfo {
  itemId: string;
  server: string;
  serverType?: string;
  title: string;
  contentUrl: string;
  strmUrl?: string;
  proxyFallbackUrl?: string;
  proxyFallbackHeaders?: Record<string, string>;
  activeRouteKind?: string;
  fallbackRoutes?: PlaybackRouteCandidate[];
  headers: Record<string, string>;
  mediaType: string;
  artist: string;
  album: string;
  artworkUrl: string;
  mediaSourceId: string;
  playSessionId?: string;
  progressSyncMode?: string;
  resumePositionMs: number;
  durationMs: number;
  subtitles: MpExternalSubtitle[];
  lyricsUrl: string;
  danmakuEnabled?: boolean;
  seriesName?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  year?: number;
  tmdbId?: string;
  fileName?: string;
  fileSize?: number;
}

/** 弹幕本地磁盘缓存统计。 */
export interface MpDanmakuCacheStats {
  fileCount: number;
  totalBytes: number;
  maxMb: number;
}

/** 管理员弹幕服务脱敏配置快照。 */
export interface MpDanmakuConfig {
  enabled: boolean;
  apiBaseUrl: string;
  authMode: string;
  appId: string;
  hasAppSecret: boolean;
  tokenHeader: string;
  tokenPrefix: string;
  hasToken: boolean;
  withRelated: boolean;
  chConvert: number;
  cacheTtlHours: number;
  cacheMaxMb: number;
  timeoutSeconds: number;
  useProxy: boolean;
  verifyTls: boolean;
  cacheStats: MpDanmakuCacheStats;
}

/** 弹幕上游连通性测试回执。 */
export interface MpDanmakuConfigTestResult {
  ok: boolean;
  latencyMs: number;
  statusCode?: number;
  message: string;
}

/** 弹幕缓存清理回执。 */
export interface MpDanmakuCacheClearResult {
  removedFiles: number;
  freedBytes: number;
}

/** 单个弹幕分集候选条目。 */
export interface MpDanmakuEpisodeCandidate {
  episodeId: number;
  animeId?: number;
  animeTitle: string;
  episodeTitle: string;
  episodeNumber?: string;
  animeType?: string;
  shiftMs: number;
}

/** 弹幕自动匹配或手动绑定查询结果。 */
export interface MpDanmakuMatchResponse {
  matched: boolean;
  fromBinding: boolean;
  shiftMs: number;
  episode?: MpDanmakuEpisodeCandidate;
  candidates: MpDanmakuEpisodeCandidate[];
}

/** 手动搜剧返回的作品条目。 */
export interface MpDanmakuAnimeSearchItem {
  animeId: number;
  animeTitle: string;
  animeType?: string;
  episodeCount?: number;
  episodes: MpDanmakuEpisodeCandidate[];
}

/** 指定作品的完整分集目录。 */
export interface MpDanmakuBangumi {
  animeId: number;
  animeTitle: string;
  animeType?: string;
  episodes: MpDanmakuEpisodeCandidate[];
}

/** 拉取单集弹幕载荷的结果（含 ETag/304 复用标记）。 */
export interface MpDanmakuCommentsRaw {
  rawJson: string;
  etag?: string;
  fromCache: boolean;
}

/** 弹幕自动匹配请求参数。 */
export interface MpDanmakuMatchParams {
  itemId?: string;
  server?: string;
  title?: string;
  seriesName?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  year?: number;
  tmdbId?: string;
  fileName?: string;
  fileSize?: number;
  durationMs?: number;
}

/** 持久化弹幕手动纠偏绑定请求参数。 */
export interface MpDanmakuSaveBindingParams {
  server?: string;
  itemId?: string;
  tmdbId?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  episodeId: number;
  animeId?: number;
  animeTitle: string;
  episodeTitle: string;
  shiftMs: number;
}

/** 解除弹幕手动绑定请求参数。 */
export interface MpDanmakuDeleteBindingParams {
  server?: string;
  itemId?: string;
  tmdbId?: string;
  seasonNumber?: number;
  episodeNumber?: number;
}

interface MpDanmakuCachedEntry {
  etag: string;
  rawJson: string;
}

/** 播放进度与实时会话上报扩展参数。 */
export interface MpProgressReportOptions {
  eventName?: string;
  playSessionId?: string;
  clientId?: string;
  deviceName?: string;
  platform?: string;
  appVersion?: string;
  playMethod?: string;
  playbackTimeMs?: number;
  audioStreamIndex?: number;
  subtitleStreamIndex?: number;
  seq?: number;
}

/** 当前用户在单个媒体服务器上的脱敏账号绑定状态。 */
export interface MpMediaServerAccountBinding {
  server: string;
  serverType: string;
  syncMode: string;
  supportsBinding: boolean;
  bound: boolean;
  status: string;
  remoteUsername: string;
  source: string;
  updatedAt: number;
}

/** 媒体服务器账号绑定或解绑请求结果。 */
export interface MpMediaServerAccountBindResult {
  success: boolean;
  message: string;
  binding?: MpMediaServerAccountBinding;
}

export interface MpManualTransferTargetHint {
  targetStorage: string;
  targetPath: string;
  transferType: string;
  overwriteMode: string;
}

export interface MpManualTransferHistoryHint {
  historyCount: number;
  reorganize: boolean;
}

export interface MpManualTransferPreviewItem {
  src: string;
  dest: string;
  title: string;
  status: string;
}

export interface MpManualTransferResult {
  success: boolean;
  message: string;
  previewItems: MpManualTransferPreviewItem[];
}

export interface MpAgentCommand {
  command: string;
  description: string;
}

export interface MpAgentSessionSummary {
  sessionId: string;
  title: string;
  messageCount: number;
  updatedAt: string;
}

export interface MpAgentToolEntry {
  id: string;
  name: string;
  status: string;
  summary: string;
  detail: string;
}

export interface MpAgentAttachment {
  id: string;
  name: string;
  kind: string;
  mimeType: string;
  url: string;
  sizeBytes: number;
}

/** 插件通过 `ChainEventType.RecommendSource` 动态注册的推荐榜单来源（`GET /api/v1/recommend/source`）。 */
export interface MpRecommendSource {
  name: string;
  apiPath: string;
  type: string;
}

/** 通用布尔执行结果与提示消息。 */
export interface MpOperationOutcome {
  ok: boolean;
  message: string;
}

export interface MpAgentChoiceButton {
  label: string;
  value: string;
  callbackData: string;
}

export interface MpAgentChoiceCard {
  title: string;
  prompt: string;
  buttons: MpAgentChoiceButton[];
}

export interface MpAgentChatMessage {
  id: string;
  role: string;
  content: string;
  tools: MpAgentToolEntry[];
  attachments: MpAgentAttachment[];
  choices: MpAgentChoiceCard[];
  timestamp: string;
}

export interface MpNetworkCheckItem {
  name: string;
  ok: boolean;
  latencyMs: number;
  detail: string;
}

export interface MpRecognizeResult {
  title: string;
  enTitle: string;
  year: string;
  type: string;
  season: string;
  episode: string;
  resolution: string;
  videoEncode: string;
  releaseGroup: string;
  tmdbId: string;
  posterUrl: string;
  overview: string;
}

/** 规范化后的 V3 媒体数据源与无前缀原生 ID。 */
export interface MpResolvedMediaIdentity {
  mediaSource: string;
  rawMediaId: string;
}

/** V3 媒体入库与订阅批量状态结果（`/api/v1/media/status`）。 */
export interface MpMediaStatusResult {
  subscribed: boolean;
  seasons: number[];
  itemId: string;
  server: string;
}

/** V3 订阅创建/变更结果（`/api/v1/subscribe/`）。 */
export interface MpSubscribeMutationResult {
  ok: boolean;
  message: string;
  id: number;
}

/** 订阅关联下载文件信息（`/api/v1/subscribe/files/{id}`）。 */
export interface MpSubscribeDownloadFile {
  torrentTitle: string;
  siteName: string;
  downloader: string;
  hash: string;
  filePath: string;
}

/** 订阅关联媒体库文件信息（`/api/v1/subscribe/files/{id}`）。 */
export interface MpSubscribeLibraryFile {
  storage: string;
  filePath: string;
  server: string;
  serverType: string;
  itemId: string;
}

/** 订阅单集或正片关联文件集合。 */
export interface MpSubscribeEpisodeFiles {
  episodeKey: string;
  episodeNumber: number;
  title: string;
  description: string;
  backdropUrl: string;
  downloads: MpSubscribeDownloadFile[];
  libraries: MpSubscribeLibraryFile[];
}

/** 订阅文件详情完整响应模型（`/api/v1/subscribe/files/{id}`）。 */
export interface MpSubscribeFilesInfo {
  subscribe: MpSubscribeItem | null;
  episodes: MpSubscribeEpisodeFiles[];
  totalCount: number;
  downloadedCount: number;
  libraryCount: number;
  missingCount: number;
}

/** TMDB 单季分集模型（`/api/v1/tmdb/{tmdbid}/{season}`）。 */
export interface MpTmdbEpisodeItem {
  id: string;
  seasonNumber: number;
  episodeNumber: number;
  title: string;
  overview: string;
  airDate: string;
  runtimeMinutes: number;
  vote: number;
  stillUrl: string;
}

/** 媒体服务器音视频/字幕轨道模型（`/api/v1/mediaserver/detail`）。 */
export interface MpMediaServerStream {
  index: number;
  type: string;
  codec: string;
  language: string;
  title: string;
  displayTitle: string;
  isDefault: boolean;
  isForced: boolean;
  isExternal: boolean;
  subtitleId: string;
  channels: number;
  channelLayout: string;
  bitrate: number;
  width: number;
  height: number;
  videoRange: string;
  frameRate?: string;
  profile?: string;
  level?: string;
  aspectRatio?: string;
  isInterlaced?: boolean;
  colorPrimaries?: string;
  colorSpace?: string;
  bitDepth?: number;
  sampleRate?: number;
  inferredAspectRatio: string;
  formattedBitrate: string;
}

/** 播前音轨或字幕可选轨道项。 */
export interface MpMediaTrackOption {
  index: number;
  ordinal: number;
  type: string;
  label: string;
  language: string;
  codec: string;
  isDefault: boolean;
  isForced: boolean;
  isExternal: boolean;
  subtitleId: string;
}

/** 媒体服务器多版本媒体源模型（附带预解析的播前可选音轨与字幕清单）。 */
export interface MpMediaServerSource {
  id: string;
  name: string;
  container: string;
  sizeBytes: number;
  bitrate: number;
  durationMs: number;
  streams: MpMediaServerStream[];
  audioTracks: MpMediaTrackOption[];
  subtitleTracks: MpMediaTrackOption[];
}

/** 媒体服务器播前源选择与音轨/字幕轨道信息（`fetchMediaServerPlaybackInfo`）。 */
export interface MpPlaybackSource {
  id: string;
  name: string;
  container: string;
  sizeBytes: number;
  bitrate: number;
  durationMs: number;
  streams: MpMediaServerStream[];
  audioTracks: MpMediaTrackOption[];
  subtitleTracks: MpMediaTrackOption[];
}

/** 媒体服务器演职员模型。 */
export interface MpMediaServerPerson {
  id: string;
  name: string;
  role: string;
  type: string;
  imageUrl: string;
}

/** 媒体服务器季或单集卡片模型（`/api/v1/mediaserver/seasons` & `season-episodes`）。 */
export interface MpMediaServerEpisode {
  itemId: string;
  server: string;
  serverType: string;
  itemType: string;
  title: string;
  subtitle: string;
  overview: string;
  year: string;
  premiereDate: string;
  rating: number;
  durationMs: number;
  posterUrl: string;
  backdropUrl: string;
  thumbUrl: string;
  seriesId: string;
  seriesName: string;
  seasonId: string;
  seasonNumber: number;
  episodeNumber: number;
  childCount: number;
  played: boolean;
  playedPercentage: number;
  resumePositionMs: number;
}

/** 单来源媒体评分微标展示模型（如 IMDb / TMDB / 烂番茄新鲜度 / 豆瓣 / Bangumi）。 */
export interface MpMediaRatingBadge {
  source: string;
  label: string;
}

/** 媒体服务器单个条目完整详情模型（`/api/v1/mediaserver/detail`）。 */
export interface MpMediaServerDetail {
  itemId: string;
  server: string;
  serverType: string;
  itemType: string;
  mediaType: string;
  title: string;
  originalTitle: string;
  subtitle: string;
  tagline: string;
  overview: string;
  year: string;
  premiereDate: string;
  rating: number;
  criticRating?: number;
  ratings?: MpMediaRatingBadge[];
  officialRating: string;
  durationMs: number;
  posterUrl: string;
  backdropUrl: string;
  thumbUrl: string;
  genres: string[];
  studios: string[];
  people: MpMediaServerPerson[];
  mediaSource: string;
  mediaId: string;
  imdbId: string;
  tmdbId: string;
  tvdbId: string;
  doubanId: string;
  parentId: string;
  seriesId: string;
  seriesName: string;
  seasonId: string;
  seasonName: string;
  seasonNumber: number;
  episodeNumber: number;
  seasonCount: number;
  episodeCount: number;
  played: boolean;
  playedPercentage: number;
  resumePositionMs: number;
  mediaSources: MpMediaServerSource[];
  playUrl: string;
  canPlay: boolean;
}

function gcdPositive(a: number, b: number): number {
  let x = Math.abs(Math.round(a));
  let y = Math.abs(Math.round(b));
  while (y !== 0) {
    const t = x % y;
    x = y;
    y = t;
  }
  return x > 0 ? x : 1;
}

function inferStreamAspectRatio(width: number, height: number, explicitRatio: string): string {
  const clean = explicitRatio.trim();
  if (clean.length > 0) { return clean; }
  if (width > 0 && height > 0) {
    const g = gcdPositive(width, height);
    return `${Math.round(width / g)}:${Math.round(height / g)}`;
  }
  return '';
}

function formatStreamBitrate(bitrate: number, streamType: string): string {
  if (!Number.isFinite(bitrate) || bitrate <= 0) { return ''; }
  if (streamType === 'video' && bitrate >= 1000000) {
    return `${(bitrate / 1000000).toFixed(1)}mbps`;
  }
  if (bitrate >= 10000000) {
    return `${(bitrate / 1000000).toFixed(1)}mbps`;
  }
  if (bitrate >= 1000) {
    return `${Math.round(bitrate / 1000)}kbps`;
  }
  return `${Math.round(bitrate)}bps`;
}

function normalizeMediaSourceCode(raw: string): string {
  const s = (raw ?? '').trim().toLowerCase();
  if (!s) { return ''; }
  if (s === 'tmdb' || s === 'themoviedb' || s === 'tmdb_movies' || s === 'tmdb_tvs' || s === 'subscribe_popular') {
    return 'themoviedb';
  }
  if (s === 'douban' || s === 'douban_movies' || s === 'douban_tvs') {
    return 'douban';
  }
  if (s === 'bangumi' || s === 'bgm') {
    return 'bangumi';
  }
  if (s === 'anilist') {
    return 'anilist';
  }
  if (s === 'imdb') {
    return 'imdb';
  }
  if (s === 'tvdb') {
    return 'tvdb';
  }
  if (s === 'musicbrainz' || s === 'listenbrainz') {
    return 'musicbrainz';
  }
  if (s === 'doubanmusic' || s === 'douban_music') {
    return 'doubanmusic';
  }
  if (s === 'theaudiodb' || s === 'audio_db') {
    return 'theaudiodb';
  }
  return '';
}

function mediaPrefixForSource(sourceCode: string): string {
  const norm = normalizeMediaSourceCode(sourceCode);
  if (norm === 'themoviedb') { return 'tmdb'; }
  return norm || sourceCode.trim().toLowerCase();
}

function stripKnownMediaPrefix(rawVal: string): string {
  let clean = (rawVal ?? '').trim();
  if (!clean) { return ''; }
  const idx = clean.indexOf(':');
  if (idx > 0) {
    const left = clean.substring(0, idx).trim();
    if (/^[a-zA-Z_-]+$/.test(left)) {
      clean = clean.substring(idx + 1).trim();
    }
  }
  const lower = clean.toLowerCase();
  if (!clean || clean === '0' || lower === 'null' || lower === 'none' || lower === 'undefined') {
    return '';
  }
  return clean;
}

function normalizeMediaTypeForV3(rawType: string, hasSeasons: boolean = false): string {
  const lower = (rawType ?? '').trim().toLowerCase();
  if (
    hasSeasons ||
    lower === '电视剧' ||
    lower === 'tv' ||
    lower === 'series' ||
    lower === 'season' ||
    lower === 'episode' ||
    lower === '番剧'
  ) {
    return '电视剧';
  }
  if (lower === '音乐' || lower === 'music' || lower === 'audio' || lower === 'musicalbum' || lower === 'track') {
    return '音乐';
  }
  return '电影';
}

/** 安全的 JSON 字典访问工具（严格满足 ArkTS 静态类型约束，绝不抛出 null 异常）。 */
function asRec(v: Object | null | undefined): Record<string, Object> | null {
  if (v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return null;
}

function asArr(v: Object | null | undefined): Object[] {
  if (v !== null && v !== undefined && Array.isArray(v)) {
    return v as Object[];
  }
  return [];
}

function strVal(obj: Record<string, Object> | null, key: string, fallback: string = ''): string {
  if (!obj) { return fallback; }
  const v = obj[key];
  if (v === null || v === undefined) { return fallback; }
  return String(v);
}

function numVal(obj: Record<string, Object> | null, key: string, fallback: number = 0): number {
  if (!obj) { return fallback; }
  const v = obj[key];
  if (v === null || v === undefined) { return fallback; }
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function boolVal(obj: Record<string, Object> | null, key: string, fallback: boolean = false): boolean {
  if (!obj) { return fallback; }
  const v = obj[key];
  if (v === null || v === undefined) { return fallback; }
  if (typeof v === 'boolean') { return v; }
  if (typeof v === 'number') { return v !== 0; }
  return String(v).toLowerCase() === 'true';
}

function parseJsonSafe(raw: string): Object | null {
  try {
    if (!raw || raw.trim().length === 0) { return null; }
    return JSON.parse(raw) as Object;
  } catch {
    return null;
  }
}

/** 兼容裸数组、`{"data": [...]}`、`{"list": [...]}`、`{"items": [...]}` 等 MoviePilot V3 响应包。 */
function unwrapArray(parsed: Object | null): Object[] {
  if (!parsed) { return []; }
  if (Array.isArray(parsed)) { return parsed as Object[]; }
  const rec = asRec(parsed);
  if (!rec) { return []; }
  if (Array.isArray(rec['data'])) { return rec['data'] as Object[]; }
  const dataRec = asRec(rec['data']);
  if (dataRec) {
    if (Array.isArray(dataRec['list'])) { return dataRec['list'] as Object[]; }
    if (Array.isArray(dataRec['items'])) { return dataRec['items'] as Object[]; }
    if (Array.isArray(dataRec['results'])) { return dataRec['results'] as Object[]; }
  }
  if (Array.isArray(rec['list'])) { return rec['list'] as Object[]; }
  if (Array.isArray(rec['items'])) { return rec['items'] as Object[]; }
  if (Array.isArray(rec['results'])) { return rec['results'] as Object[]; }
  return [];
}

function unwrapObject(parsed: Object | null): Record<string, Object> | null {
  const rec = asRec(parsed);
  if (!rec) { return null; }
  const inner = asRec(rec['data']);
  if (inner && rec['success'] !== undefined) {
    return inner;
  }
  return rec;
}

export function formatByteSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) { return '0 B'; }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  let idx = 0;
  let val = bytes;
  while (val >= 1024 && idx < units.length - 1) {
    val /= 1024;
    idx++;
  }
  return `${val >= 100 ? val.toFixed(0) : (val >= 10 ? val.toFixed(1) : val.toFixed(2))} ${units[idx]}`;
}

export function formatSpeed(bytesPerSec: number): string {
  if (!Number.isFinite(bytesPerSec) || bytesPerSec <= 0) { return '0 B/s'; }
  return `${formatByteSize(bytesPerSec)}/s`;
}

/**
 * MoviePilot V3 鸿蒙端统一实时数据仓库（Singleton）。
 * 100% 消费真实 MoviePilot V3 REST API，严禁在运行时回退虚假演示数据。
 */
export class MoviePilotRepository {
  private static instance: MoviePilotRepository | null = null;
  readonly transport: NativeRcpTransport = new NativeRcpTransport();
  private multiRatingsCache: Map<string, MpMediaRatingBadge[]> = new Map<string, MpMediaRatingBadge[]>();
  baseUrl: string = '';
  token: string = '';
  userName: string = '';
  isSuperuser: boolean = false;
  userAvatar: string = '';
  userLevel: number = 1;

  /** 从不可变 sub 派生存储归属；无法确认账号时不使用共享桶。 */
  accountStorageScope(): string {
    const claims = MoviePilotRepository.jwtClaims(this.token);
    const subject = claims ? strVal(claims, 'sub') : '';
    if (!/^[1-9][0-9]*$/.test(subject)) { return ''; }
    return encodeURIComponent(JSON.stringify([RustCoreBridge.normalizeServerAddress(this.baseUrl), subject]));
  }

  /** 解码已认证令牌的业务声明，仅用于展示和存储归属，不作为权限验证。 */
  private static jwtClaims(token: string): Record<string, Object> | null {
    const parts = token.split('.');
    if (parts.length !== 3) { return null; }
    try {
      let payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      payload += '='.repeat((4 - payload.length % 4) % 4);
      const bytes = new util.Base64Helper().decodeSync(payload);
      const text = util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
      return asRec(parseJsonSafe(text));
    } catch {
      return null;
    }
  }

  /** 读取签发等级供重启展示，缺失时使用调用方既有回退。 */
  static parseJwtLevel(token: string): number | null {
    const claims = MoviePilotRepository.jwtClaims(token);
    if (!claims || claims['level'] === undefined || claims['level'] === null) { return null; }
    const level = Number(claims['level']);
    return Number.isFinite(level) && level >= 0 ? Math.trunc(level) : null;
  }

  static shared(): MoviePilotRepository {
    if (!MoviePilotRepository.instance) {
      const repo = new MoviePilotRepository();
      repo.transport.cfAccessTokenProvider = (requestUrl: string): string => {
        return CloudflareAccessOAuthManager.shared().getAccessTokenForUrl(requestUrl);
      };
      MoviePilotRepository.instance = repo;
    }
    return MoviePilotRepository.instance;
  }

  private siteIconCache: Map<number, string> = new Map<number, string>();
  globalImageCache: boolean = false;
  tmdbImageDomain: string = 'image.tmdb.org';
  bangumiProxyEnable: boolean = false;
  bangumiImageDomain: string = '';
  private imageContextReadyOrigin: string = '';
  private imageContextInflight: Promise<void> | null = null;

  private imageConfigStorageKey(origin: string): string {
    return `mp_global_img_cfg_v1_${encodeURIComponent(origin)}`;
  }

  private resetImageConfigState(nextOrigin: string): void {
    this.globalImageCache = false;
    this.tmdbImageDomain = 'image.tmdb.org';
    this.bangumiProxyEnable = false;
    this.bangumiImageDomain = '';
    this.imageContextReadyOrigin = '';
    this.imageContextInflight = null;
    if (nextOrigin.length > 0) {
      this.restoreCachedImageConfig(nextOrigin).catch(() => {});
    }
  }

  private async restoreCachedImageConfig(origin: string): Promise<void> {
    if (!origin || origin !== this.baseUrl) { return; }
    try {
      const raw = await NativeHuksStore.shared().loadString(this.imageConfigStorageKey(origin));
      if (!raw || origin !== this.baseUrl) { return; }
      const rec = asRec(parseJsonSafe(raw));
      if (!rec) { return; }
      this.applyGlobalImageRecord(rec, false);
    } catch {
      // ignore cache load errors
    }
  }

  private applyGlobalImageRecord(rec: Record<string, Object>, persist: boolean): void {
    if (rec['GLOBAL_IMAGE_CACHE'] !== undefined && rec['GLOBAL_IMAGE_CACHE'] !== null) {
      this.globalImageCache = boolVal(rec, 'GLOBAL_IMAGE_CACHE', false);
    }
    const tmdbDom = strVal(rec, 'TMDB_IMAGE_DOMAIN').trim().replace(/^https?:\/\//i, '').replace(/\/+$/, '');
    if (tmdbDom.length > 0) {
      this.tmdbImageDomain = tmdbDom;
    } else if (rec['TMDB_IMAGE_DOMAIN'] !== undefined) {
      this.tmdbImageDomain = 'image.tmdb.org';
    }
    if (rec['BANGUMI_PROXY_ENABLE'] !== undefined && rec['BANGUMI_PROXY_ENABLE'] !== null) {
      this.bangumiProxyEnable = boolVal(rec, 'BANGUMI_PROXY_ENABLE', false);
    }
    if (rec['BANGUMI_IMAGE_DOMAIN'] !== undefined) {
      this.bangumiImageDomain = strVal(rec, 'BANGUMI_IMAGE_DOMAIN').trim().replace(/^https?:\/\//i, '').replace(/\/+$/, '');
    }
    if (persist && this.baseUrl.length > 0) {
      const snap: Record<string, Object> = {};
      snap['GLOBAL_IMAGE_CACHE'] = this.globalImageCache;
      snap['TMDB_IMAGE_DOMAIN'] = this.tmdbImageDomain;
      snap['BANGUMI_PROXY_ENABLE'] = this.bangumiProxyEnable;
      snap['BANGUMI_IMAGE_DOMAIN'] = this.bangumiImageDomain;
      NativeHuksStore.shared().saveString(this.imageConfigStorageKey(this.baseUrl), JSON.stringify(snap)).catch(() => {});
    }
  }

  /** 拉取后端全局图片缓存与自定义图片域名配置（对齐 Web 端 `/api/v1/system/global?token=moviepilot`）。 */
  async refreshGlobalImageSettings(): Promise<void> {
    const origin = this.baseUrl;
    if (!origin) { return; }
    try {
      const url = RustCoreBridge.buildV3EndpointUrl(origin, ['system', 'global'], { 'token': 'moviepilot' });
      const resp = await this.transport.execute(url, 'GET', '');
      if (origin !== this.baseUrl) { return; }
      if (resp.status === 200) {
        const root = unwrapObject(parseJsonSafe(resp.body));
        if (root) {
          this.applyGlobalImageRecord(root, true);
          return;
        }
      }
    } catch {
      // fallback below
    }
    if (origin === this.baseUrl && this.token.length > 0 && this.isSuperuser) {
      try {
        const envResp = await this.get(['system', 'env']);
        if (origin === this.baseUrl && envResp.status === 200) {
          const envObj = unwrapObject(parseJsonSafe(envResp.body));
          if (envObj) {
            this.applyGlobalImageRecord(envObj, true);
          }
        }
      } catch {
        // ignore fallback errors
      }
    }
  }

  /** 确保当前实例已同步全局图片缓存开关并持有同源 `MoviePilot` 资源 Cookie（并发去重）。 */
  async ensureImageContextReady(): Promise<void> {
    const origin = this.baseUrl;
    if (!origin) { return; }
    if (this.imageContextReadyOrigin === origin && (this.token.length === 0 || this.transport.hasCookie('MoviePilot'))) {
      return;
    }
    if (this.imageContextInflight) {
      await this.imageContextInflight;
      return;
    }
    const task = this.runImageContextBootstrap(origin);
    this.imageContextInflight = task;
    try {
      await task;
    } finally {
      if (this.imageContextInflight === task) {
        this.imageContextInflight = null;
      }
    }
  }

  private async runImageContextBootstrap(origin: string): Promise<void> {
    await this.restoreCachedImageConfig(origin);
    const jobs: Promise<void>[] = [this.refreshGlobalImageSettings()];
    if (this.token.length > 0 && !this.transport.hasCookie('MoviePilot')) {
      jobs.push(this.get(['media', 'source']).then(() => {}).catch(() => {}));
    }
    await Promise.all(jobs);
    if (origin === this.baseUrl) {
      this.imageContextReadyOrigin = origin;
    }
  }

  configure(baseUrl: string, token: string, userName: string, isSuperuser: boolean, avatar: string = ''): void {
    const normalizedBase = RustCoreBridge.normalizeServerAddress(baseUrl);
    const originChanged = normalizedBase !== this.baseUrl;
    this.baseUrl = normalizedBase;
    this.transport.setBaseUrl(this.baseUrl);
    if (originChanged) {
      this.resetImageConfigState(this.baseUrl);
    }
    CloudflareAccessOAuthManager.shared().hydrateOrigin(this.baseUrl).catch(() => {});
    this.token = token;
    this.userName = userName;
    this.isSuperuser = isSuperuser;
    if (avatar.length > 0) {
      this.userAvatar = avatar;
    }
  }

  /** 配置当前实例地址与自签名 HTTPS 证书策略。 */
  configureServer(baseUrl: string, allowSelfSigned: boolean = false): void {
    const normalizedBase = RustCoreBridge.normalizeServerAddress(baseUrl);
    const originChanged = normalizedBase !== this.baseUrl;
    this.baseUrl = normalizedBase;
    this.transport.setBaseUrl(this.baseUrl);
    this.transport.setAllowSelfSigned(allowSelfSigned);
    if (originChanged) {
      this.resetImageConfigState(this.baseUrl);
    }
    CloudflareAccessOAuthManager.shared().hydrateOrigin(this.baseUrl).catch(() => {});
  }

  /** 更新当前会话访问令牌。 */
  setAuthToken(token: string): void {
    this.token = token;
  }

  /** 注册全局会话失效（HTTP 401 / 过期型 403）登出回调。 */
  setOnSessionExpired(cb: (() => void) | null): void {
    this.transport.onAuthExpired = cb;
  }

  clearSession(): void {
    this.token = '';
    this.userAvatar = '';
    this.cachedMediaServers = [];
    this.cachedSubscriptions = null;
    this.siteIconCache.clear();
    this.danmakuCommentsCache.clear();
    this.imageContextReadyOrigin = '';
    this.imageContextInflight = null;
    this.transport.clearCookies();
  }

  private normalizeExternalImageUrl(rawUrl: string): string {
    const tmdbHost = (this.tmdbImageDomain || 'image.tmdb.org').trim() || 'image.tmdb.org';
    let out = rawUrl
      .replace('https://image.tmdb.org/t/p/original/', `https://${tmdbHost}/t/p/w780/`)
      .replace('http://image.tmdb.org/t/p/original/', `https://${tmdbHost}/t/p/w780/`)
      .replace('https://image.tmdb.org/', `https://${tmdbHost}/`)
      .replace('http://image.tmdb.org/', `https://${tmdbHost}/`)
      .replace('/t/p/original/', '/t/p/w780/');
    if (this.bangumiImageDomain.length > 0 && out.includes('lain.bgm.tv')) {
      out = out
        .replace('https://lain.bgm.tv/', `https://${this.bangumiImageDomain}/`)
        .replace('http://lain.bgm.tv/', `https://${this.bangumiImageDomain}/`);
    }
    return out;
  }

  private static isDoubanImageUrl(url: string): boolean {
    return url.toLowerCase().includes('doubanio.com');
  }

  private static isBangumiDefaultImageUrl(url: string): boolean {
    return url.toLowerCase().includes('lain.bgm.tv');
  }

  private static isMediaServerOrPlainHttpImage(url: string): boolean {
    const lower = url.toLowerCase();
    if (lower.startsWith('http://')) {
      return !lower.includes('://127.0.0.1') && !lower.includes('://localhost');
    }
    return (lower.includes('/items/') && lower.includes('/images/')) || lower.includes('/photo/:/transcode');
  }

  /**
   * 将 TMDB/豆瓣/Bangumi/媒体服务器/本地相对路径解析为与 Web 端一致的图片 URL：
   * - 开启 `GLOBAL_IMAGE_CACHE` 时统一走 `/api/v1/system/cache/image?url=...` 复用后端代理与全局文件缓存；
   * - 关闭 `GLOBAL_IMAGE_CACHE` 时，豆瓣/媒体服务器/HTTP 走 `/system/img/0`，Bangumi 代理走 `/system/img/1`，其余公网 HTTPS 直连并在失败时由加载器自动回退 `/system/img/1`。
   */
  resolveImageUrl(rawPath: string, useCookies: boolean = false): string {
    const clean = (rawPath ?? '').trim();
    if (!clean || clean.toLowerCase() === 'null' || clean.toLowerCase() === 'none') { return ''; }
    if (clean.startsWith('data:image/')) { return clean; }
    if (!this.baseUrl) { return clean; }
    if (this.transport.isSameOriginUrl(clean)) { return clean; }
    if (clean.startsWith('/api/')) {
      return `${this.baseUrl}${clean}`;
    }
    const tmdbHost = (this.tmdbImageDomain || 'image.tmdb.org').trim() || 'image.tmdb.org';
    let normalized = clean;
    if (normalized.startsWith('/')) {
      normalized = `https://${tmdbHost}/t/p/w500${normalized}`;
    } else if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      normalized = this.normalizeExternalImageUrl(normalized);
    } else {
      return `${this.baseUrl}/${normalized}`;
    }

    if (normalized.includes('://127.0.0.1') || normalized.includes('://localhost')) {
      return normalized;
    }
    if (useCookies) {
      const cacheFlag = this.globalImageCache ? 'true' : 'false';
      return `${this.baseUrl}/api/v1/system/img/1?imgurl=${encodeURIComponent(normalized)}&cache=${cacheFlag}&use_cookies=true`;
    }
    if (this.globalImageCache) {
      return `${this.baseUrl}/api/v1/system/cache/image?url=${encodeURIComponent(normalized)}`;
    }
    if (MoviePilotRepository.isDoubanImageUrl(normalized) || MoviePilotRepository.isMediaServerOrPlainHttpImage(normalized)) {
      return `${this.baseUrl}/api/v1/system/img/0?imgurl=${encodeURIComponent(normalized)}&cache=false`;
    }
    if (this.bangumiProxyEnable && this.bangumiImageDomain.length === 0 && MoviePilotRepository.isBangumiDefaultImageUrl(normalized)) {
      return `${this.baseUrl}/api/v1/system/img/1?imgurl=${encodeURIComponent(normalized)}&cache=false`;
    }
    return normalized;
  }

  /** 在 `ensureImageContextReady` 完成后按最新 `GLOBAL_IMAGE_CACHE` / 域名配置修正待请求图片 URL。 */
  upgradeImageUrlForCurrentConfig(url: string): string {
    const clean = (url ?? '').trim();
    if (!clean || !this.baseUrl || clean.startsWith('data:image/')) { return clean; }
    if (this.transport.isSameOriginUrl(clean)) {
      if (this.globalImageCache && clean.includes('/api/v1/system/img/') && !clean.includes('use_cookies=true')) {
        const qIdx = clean.indexOf('?');
        if (qIdx > 0) {
          const pairs = clean.substring(qIdx + 1).split('&');
          for (let i = 0; i < pairs.length; i++) {
            if (pairs[i].startsWith('imgurl=')) {
              try {
                const rawTarget = decodeURIComponent(pairs[i].substring('imgurl='.length));
                if (rawTarget.startsWith('http://') || rawTarget.startsWith('https://')) {
                  return `${this.baseUrl}/api/v1/system/cache/image?url=${encodeURIComponent(this.normalizeExternalImageUrl(rawTarget))}`;
                }
              } catch {
                return clean;
              }
            }
          }
        }
      }
      return clean;
    }
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return this.resolveImageUrl(clean, false);
    }
    return clean;
  }

  /** 当客户端直连外部图片失败（如无本地代理环境）时，回退至后端带代理图片接口 `/api/v1/system/img/1`。 */
  buildBackendProxyFallbackUrl(directUrl: string): string {
    const clean = (directUrl ?? '').trim();
    if (!clean || !this.baseUrl || this.transport.isSameOriginUrl(clean)) { return ''; }
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) { return ''; }
    const cacheFlag = this.globalImageCache ? 'true' : 'false';
    return `${this.baseUrl}/api/v1/system/img/1?imgurl=${encodeURIComponent(clean)}&cache=${cacheFlag}`;
  }

  /** 为锁屏播控中心生成始终同源的图片代理/缓存地址。 */
  private resolveSameOriginArtworkUrl(rawPath: string): string {
    const resolved = this.resolveImageUrl(rawPath, false);
    if (!resolved || !this.baseUrl) { return ''; }
    if (this.transport.isSameOriginUrl(resolved)) { return resolved; }
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      if (this.globalImageCache) {
        return `${this.baseUrl}/api/v1/system/cache/image?url=${encodeURIComponent(resolved)}`;
      }
      const routeSeg = MoviePilotRepository.isDoubanImageUrl(resolved) ? '0' : '1';
      return `${this.baseUrl}/api/v1/system/img/${routeSeg}?imgurl=${encodeURIComponent(resolved)}&cache=false`;
    }
    return '';
  }

  /** 解析插件图标 URL：兼容绝对地址、`data:image/` 与官方插件仓库相对文件名。 */
  resolvePluginIconUrl(rawIcon: string): string {
    const clean = rawIcon.trim();
    if (!clean || clean.toLowerCase() === 'null' || clean.toLowerCase() === 'none') {
      return '';
    }
    if (clean.startsWith('data:image/') || clean.startsWith('http://') || clean.startsWith('https://') || clean.startsWith('/api/')) {
      return this.resolveImageUrl(clean);
    }
    const stripped = clean.replace(/^\.?\/*/, '');
    const fileName = stripped.startsWith('plugin_icon/') ? stripped.substring('plugin_icon/'.length) : stripped;
    if (!fileName || fileName.includes('..')) {
      return '';
    }
    const officialUrl = `https://raw.githubusercontent.com/jxxghp/MoviePilot-Plugins/main/icons/${encodeURIComponent(fileName)}`;
    return this.resolveImageUrl(officialUrl);
  }

  private buildEndpointUrlSafe(segments: string[], query: Record<string, string> = {}, trailingSlash: boolean = false): string {
    const hasSpaceOrNonAscii = segments.some((s: string) => /[^\x21-\x7e]/.test(s));
    if (hasSpaceOrNonAscii) {
      const cleanBase = RustCoreBridge.normalizeServerAddress(this.baseUrl);
      const encodedPath = segments.map((s: string) => encodeURIComponent(s)).join('/');
      let url = `${cleanBase}/api/v1/${encodedPath}${trailingSlash ? '/' : ''}`;
      const keys = Object.keys(query);
      if (keys.length > 0) {
        const pairs: string[] = [];
        for (let i = 0; i < keys.length; i++) {
          const k = keys[i];
          pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`);
        }
        url += `?${pairs.join('&')}`;
      }
      return url;
    }
    return RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, query, trailingSlash);
  }

  async get(
    segments: string[],
    query: Record<string, string> = {},
    trailingSlash: boolean = false,
    extraHeaders?: Record<string, string>
  ): Promise<NativeHttpResponse> {
    const url = this.buildEndpointUrlSafe(segments, query, trailingSlash);
    return this.transport.execute(url, 'GET', this.token, '', 'application/json', extraHeaders);
  }

  /** 支持同名重复查询参数（如多个 `media_source` 或 `type`）的带鉴权 GET 请求。 */
  async getMultiQuery(
    segments: string[],
    queryPairs: string[][],
    trailingSlash: boolean = false,
    extraHeaders?: Record<string, string>
  ): Promise<NativeHttpResponse> {
    const cleanBase = RustCoreBridge.normalizeServerAddress(this.baseUrl);
    const encodedPath = segments.map((s: string) => encodeURIComponent(s)).join('/');
    let url = `${cleanBase}/api/v1/${encodedPath}${trailingSlash ? '/' : ''}`;
    if (queryPairs.length > 0) {
      const encodedPairs: string[] = [];
      for (let i = 0; i < queryPairs.length; i++) {
        const kv = queryPairs[i];
        if (kv.length >= 2 && kv[0].length > 0) {
          encodedPairs.push(`${encodeURIComponent(kv[0])}=${encodeURIComponent(kv[1])}`);
        }
      }
      if (encodedPairs.length > 0) {
        url += `?${encodedPairs.join('&')}`;
      }
    }
    return this.transport.execute(url, 'GET', this.token, '', 'application/json', extraHeaders);
  }

  async postJson(
    segments: string[],
    payload: string,
    trailingSlash: boolean = false,
    extraHeaders?: Record<string, string>
  ): Promise<NativeHttpResponse> {
    const url = this.buildEndpointUrlSafe(segments, {}, trailingSlash);
    return this.transport.execute(url, 'POST', this.token, payload, 'application/json', extraHeaders);
  }

  async postJsonQuery(segments: string[], query: Record<string, string>, payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = this.buildEndpointUrlSafe(segments, query, trailingSlash);
    return this.transport.execute(url, 'POST', this.token, payload, 'application/json');
  }

  async putJson(segments: string[], payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = this.buildEndpointUrlSafe(segments, {}, trailingSlash);
    return this.transport.execute(url, 'PUT', this.token, payload, 'application/json');
  }

  async putJsonQuery(segments: string[], query: Record<string, string>, payload: string = '{}', trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = this.buildEndpointUrlSafe(segments, query, trailingSlash);
    return this.transport.execute(url, 'PUT', this.token, payload, 'application/json');
  }

  async deleteReq(segments: string[], query: Record<string, string> = {}, trailingSlash: boolean = false, body: string = ''): Promise<NativeHttpResponse> {
    const url = this.buildEndpointUrlSafe(segments, query, trailingSlash);
    return this.transport.execute(url, 'DELETE', this.token, body, 'application/json');
  }

  /** 登录并预热当前用户头像与服务端 Session Cookie。 */
  async login(serverUrl: string, username: string, password: string, otpCode: string = ''): Promise<MpLoginResult> {
    const cleanUrl = RustCoreBridge.normalizeServerAddress(serverUrl);
    this.baseUrl = cleanUrl;
    this.transport.setBaseUrl(cleanUrl);
    await CloudflareAccessOAuthManager.shared().hydrateOrigin(cleanUrl);
    await CloudflareAccessOAuthManager.shared().refreshIfNeeded(cleanUrl, this.transport.isAllowSelfSigned());
    const url = RustCoreBridge.buildV3EndpointUrl(cleanUrl, ['login', 'access-token']);
    const form = `username=${encodeURIComponent(username.trim())}&password=${encodeURIComponent(password)}&otp_password=${encodeURIComponent(otpCode.trim())}`;
    const resp = await this.transport.execute(url, 'POST', '', form, 'application/x-www-form-urlencoded');
    const cfChallenge = RustCoreBridge.detectCloudflareAccessChallenge(
      resp.status,
      resp.headers ?? {},
      resp.body,
      url
    );
    if (cfChallenge.isChallenge) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '检测到 Cloudflare Access 网关拦截，请先点击下方「通过 Cloudflare Access 认证」'
      };
    }
    if (resp.status === 401) {
      const needOtp = resp.body.includes('mfa_methods') || resp.body.includes('otp');
      return {
        success: false, requiresOtp: needOtp, token: '', userName: username, isSuperuser: false, avatar: '',
        message: needOtp ? '请输入 6 位动态验证码 (OTP)' : '用户名、密码或验证码错误'
      };
    }
    if (resp.status < 200 || resp.status >= 300) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: `登录失败（HTTP ${resp.status}）`
      };
    }
    const rec = asRec(parseJsonSafe(resp.body));
    const token = strVal(rec, 'access_token');
    const name = strVal(rec, 'user_name', username.trim());
    const su = boolVal(rec, 'super_user', true);
    const avatar = strVal(rec, 'avatar');
    const rawLevel = rec && rec['level'] !== undefined && rec['level'] !== null ? Number(rec['level']) : NaN;
    const jwtLevel = MoviePilotRepository.parseJwtLevel(token);
    const level = Number.isFinite(rawLevel) && rawLevel >= 0 ? Math.trunc(rawLevel) : (jwtLevel ?? 1);
    if (token.length === 0) {
      return {
        success: false, requiresOtp: false, token: '', userName: name, isSuperuser: su, avatar: '', userLevel: 1,
        message: '服务器未返回有效访问令牌'
      };
    }
    this.configure(cleanUrl, token, name, su, avatar);
    this.userLevel = level;
    await this.hydrateSession();
    return {
      success: true, requiresOtp: false, token: token, userName: this.userName,
      isSuperuser: this.isSuperuser, avatar: this.userAvatar, userLevel: this.userLevel, message: ''
    };
  }

  /** 探测当前实例是否已启用系统通行密钥（`GET /api/v1/auth/providers`）。 */
  async probePasskeyEnabled(serverUrl: string): Promise<boolean> {
    try {
      const cleanUrl = RustCoreBridge.normalizeServerAddress(serverUrl);
      this.transport.setBaseUrl(cleanUrl);
      await CloudflareAccessOAuthManager.shared().hydrateOrigin(cleanUrl);
      await CloudflareAccessOAuthManager.shared().refreshIfNeeded(cleanUrl, this.transport.isAllowSelfSigned());
      const url = RustCoreBridge.buildV3EndpointUrl(cleanUrl, ['auth', 'providers']);
      const resp = await this.transport.execute(url, 'GET', '');
      if (resp.status !== 200 || !resp.body) {
        return false;
      }
      return RustCoreBridge.parsePasskeyProviderEnabled(resp.body);
    } catch {
      return false;
    }
  }

  /** 使用系统浏览器完成 `moviepilot.passkey` v1 通行密钥登录并激活会话。 */
  async loginWithPasskey(
    serverUrl: string,
    username: string,
    launchBrowser: (authorizeUrl: string) => void
  ): Promise<MpLoginResult> {
    let cleanUrl = '';
    try {
      cleanUrl = RustCoreBridge.normalizeServerAddress(serverUrl);
    } catch {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '服务地址格式无效，请检查后重试。'
      };
    }
    if (!RustCoreBridge.isPasskeySecureOrigin(cleanUrl)) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。'
      };
    }
    this.baseUrl = cleanUrl;
    this.transport.setBaseUrl(cleanUrl);
    await CloudflareAccessOAuthManager.shared().hydrateOrigin(cleanUrl);
    await CloudflareAccessOAuthManager.shared().refreshIfNeeded(cleanUrl, this.transport.isAllowSelfSigned());

    const markerUrl = `${cleanUrl}/native-passkey.json`;
    const markerResp = await this.transport.execute(markerUrl, 'GET', '');
    if (RustCoreBridge.detectCloudflareAccessChallenge(
      markerResp.status, markerResp.headers ?? {}, markerResp.body, markerUrl
    ).isChallenge) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '检测到 Cloudflare Access 网关拦截，请先完成 Cloudflare Access 认证。'
      };
    }
    if (markerResp.status !== 200 || !RustCoreBridge.supportsPasskeyFrontendMarker(markerResp.body)) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '请更新实例的前端资源后，再使用 App 通行密钥登录。'
      };
    }

    let stateHex = '';
    try {
      stateHex = PasskeyAuthManager.shared().generateStateHex32();
    } catch {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '未能完成通行密钥验证，请重新尝试。'
      };
    }

    const trimmedUser = (username ?? '').trim();
    const startPayload: Record<string, string> = {};
    if (trimmedUser.length > 0) {
      startPayload['username'] = trimmedUser;
    }
    const startUrl = RustCoreBridge.buildV3EndpointUrl(cleanUrl, ['mfa', 'passkey', 'authenticate', 'start']);
    const startResp = await this.transport.execute(
      startUrl,
      'POST',
      '',
      JSON.stringify(startPayload),
      'application/json'
    );
    if (RustCoreBridge.detectCloudflareAccessChallenge(
      startResp.status, startResp.headers ?? {}, startResp.body, startUrl
    ).isChallenge) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '检测到 Cloudflare Access 网关拦截，请先完成 Cloudflare Access 认证。'
      };
    }
    if (startResp.status < 200 || startResp.status >= 300) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '未能完成通行密钥验证，请重新尝试。'
      };
    }

    let finishBodyJson = '';
    try {
      const prepared = RustCoreBridge.preparePasskeyRequest(startResp.body, cleanUrl, stateHex);
      const callbackUrl = await PasskeyAuthManager.shared().waitForCallback(
        prepared.authorizationUrl,
        prepared.timeoutSecs,
        launchBrowser
      );
      const verified = RustCoreBridge.verifyPasskeyCallback(
        callbackUrl,
        cleanUrl,
        prepared.state,
        prepared.challenge,
        prepared.transactionToken
      );
      if (!verified.ok || !verified.finishBodyJson) {
        if (verified.errorCode === 'canceled') {
          return {
            success: false, requiresOtp: false, canceled: true, token: '', userName: username,
            isSuperuser: false, avatar: '', message: ''
          };
        }
        return {
          success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
          message: verified.errorMessageZh || '未能完成通行密钥验证，请重新尝试。'
        };
      }
      finishBodyJson = verified.finishBodyJson;
    } catch (e) {
      const code = ((e as Error).message ?? '').trim();
      if (code === 'canceled') {
        return {
          success: false, requiresOtp: false, canceled: true, token: '', userName: username,
          isSuperuser: false, avatar: '', message: ''
        };
      }
      const msg = code === 'expired'
        ? '通行密钥验证已过期，请重新尝试。'
        : (code === 'unsupported'
          ? '当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。'
          : (code === 'invalid'
            ? '通行密钥验证结果无效，请重新尝试。'
            : '未能完成通行密钥验证，请重新尝试。'));
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: msg
      };
    }

    const finishUrl = RustCoreBridge.buildV3EndpointUrl(cleanUrl, ['mfa', 'passkey', 'authenticate', 'finish']);
    const finishResp = await this.transport.execute(
      finishUrl,
      'POST',
      '',
      finishBodyJson,
      'application/json'
    );
    if (finishResp.status < 200 || finishResp.status >= 300) {
      return {
        success: false, requiresOtp: false, token: '', userName: username, isSuperuser: false, avatar: '',
        message: '未能完成通行密钥验证，请重新尝试。'
      };
    }
    const parsedFinish = parseJsonSafe(finishResp.body);
    const rec = unwrapObject(parsedFinish) ?? asRec(parsedFinish);
    const token = strVal(rec, 'access_token');
    const name = strVal(rec, 'user_name', trimmedUser);
    const su = boolVal(rec, 'super_user', true);
    const avatar = strVal(rec, 'avatar');
    const rawLevel = rec && rec['level'] !== undefined && rec['level'] !== null ? Number(rec['level']) : NaN;
    const jwtLevel = MoviePilotRepository.parseJwtLevel(token);
    const level = Number.isFinite(rawLevel) && rawLevel >= 0 ? Math.trunc(rawLevel) : (jwtLevel ?? 1);
    if (token.length === 0) {
      return {
        success: false, requiresOtp: false, token: '', userName: name, isSuperuser: su, avatar: '', userLevel: 1,
        message: '未能完成通行密钥验证，请重新尝试。'
      };
    }
    this.configure(cleanUrl, token, name, su, avatar);
    this.userLevel = level;
    await this.hydrateSession();
    return {
      success: true, requiresOtp: false, token: token, userName: this.userName,
      isSuperuser: this.isSuperuser, avatar: this.userAvatar, userLevel: this.userLevel, message: ''
    };
  }

  async hydrateSession(): Promise<void> {
    try {
      const uResp = await this.get(['user', 'current']);
      if (uResp.status === 200) {
        const u = unwrapObject(parseJsonSafe(uResp.body));
        if (u) {
          const av = strVal(u, 'avatar');
          if (av.length > 0) { this.userAvatar = av; }
          const nm = strVal(u, 'name');
          if (nm.length > 0) { this.userName = nm; }
          this.isSuperuser = boolVal(u, 'is_superuser', this.isSuperuser);
          if (u['level'] !== undefined && u['level'] !== null) {
            const lv = Number(u['level']);
            if (Number.isFinite(lv) && lv >= 0) {
              this.userLevel = Math.trunc(lv);
            }
          } else {
            const jwtLevel = MoviePilotRepository.parseJwtLevel(this.token);
            if (jwtLevel !== null) {
              this.userLevel = jwtLevel;
            }
          }
        }
      }
    } catch {
      // ignore
    }
    try {
      await Promise.all([
        this.get(['media', 'source']).then(() => {}).catch(() => {}),
        this.refreshGlobalImageSettings()
      ]);
      if (this.baseUrl.length > 0) {
        this.imageContextReadyOrigin = this.baseUrl;
      }
    } catch {
      // ignore
    }
  }

  private parseMediaItem(raw: Object, fallbackSource: string = 'themoviedb'): MpMediaItem | null {
    const r = asRec(raw);
    if (!r) { return null; }
    const isPerson = fallbackSource === 'person' || strVal(r, 'media_type').toLowerCase() === 'person' || strVal(r, 'known_for_department').length > 0;
    const isMediaServerSrc = !isPerson && (
      fallbackSource === 'mediaserver' ||
      fallbackSource === 'library' ||
      strVal(r, 'item_type').length > 0 ||
      (strVal(r, 'server').length > 0 && strVal(r, 'item_id').length > 0)
    );
    const serverItemId = strVal(r, 'item_id') || (isMediaServerSrc ? strVal(r, 'id') : '');
    const rawId = isMediaServerSrc
      ? (serverItemId || strVal(r, 'id'))
      : (strVal(r, 'id') || strVal(r, 'item_id'));

    const rawMediaSource = strVal(r, 'media_source');
    const rawMediaIdVal = stripKnownMediaPrefix(strVal(r, 'media_id'));
    const normSource = normalizeMediaSourceCode(rawMediaSource);

    let tmdbId = stripKnownMediaPrefix(strVal(r, 'tmdb_id')) || (isPerson ? rawId : '');
    if (!tmdbId && normSource === 'themoviedb' && rawMediaIdVal.length > 0) {
      tmdbId = rawMediaIdVal;
    }
    let doubanId = stripKnownMediaPrefix(strVal(r, 'douban_id'));
    if (!doubanId && normSource === 'douban' && rawMediaIdVal.length > 0) {
      doubanId = rawMediaIdVal;
    }
    const bangumiId = stripKnownMediaPrefix(strVal(r, 'bangumi_id')) || (normSource === 'bangumi' ? rawMediaIdVal : '');
    const imdbId = stripKnownMediaPrefix(strVal(r, 'imdb_id')) || (normSource === 'imdb' ? rawMediaIdVal : '');
    const tvdbId = stripKnownMediaPrefix(strVal(r, 'tvdb_id')) || (normSource === 'tvdb' ? rawMediaIdVal : '');

    let mediaId = '';
    if (strVal(r, 'mediaid_prefix').length > 0 && rawMediaIdVal.length > 0) {
      mediaId = `${strVal(r, 'mediaid_prefix')}:${rawMediaIdVal}`;
    } else if (normSource.length > 0 && rawMediaIdVal.length > 0) {
      mediaId = `${mediaPrefixForSource(normSource)}:${rawMediaIdVal}`;
    } else if (tmdbId && !isPerson) {
      mediaId = `tmdb:${tmdbId}`;
    } else if (doubanId) {
      mediaId = `douban:${doubanId}`;
    } else if (bangumiId) {
      mediaId = `bangumi:${bangumiId}`;
    } else if (!isMediaServerSrc) {
      mediaId = rawId;
    }

    const posterRaw = strVal(r, 'poster_path') || strVal(r, 'profile_path') || strVal(r, 'poster') || strVal(r, 'image') || strVal(r, 'thumb') || strVal(r, 'backdrop_path');
    const backdropRaw = strVal(r, 'backdrop_path') || strVal(r, 'backdrop') || strVal(r, 'image') || strVal(r, 'thumb') || posterRaw;
    const useCookies = boolVal(r, 'use_cookies', false);
    const rawPercent = numVal(r, 'percent', numVal(r, 'played_percentage', 0));

    let subText = strVal(r, 'subtitle');
    if (isPerson && !subText) {
      subText = strVal(r, 'known_for_department') || '演职员';
    } else if (!subText) {
      const genresArr = asArr(r['genres']).length > 0 ? asArr(r['genres']) : asArr(r['genre_names']);
      const genreNames: string[] = [];
      for (let g = 0; g < Math.min(genresArr.length, 3); g++) {
        const gItem = genresArr[g];
        const gRec = asRec(gItem);
        const gn = gRec ? strVal(gRec, 'name') : String(gItem ?? '').trim();
        if (gn.length > 0) { genreNames.push(gn); }
      }
      const relDate = strVal(r, 'release_date') || strVal(r, 'first_air_date') || strVal(r, 'premiere_date');
      const metaParts: string[] = [];
      if (genreNames.length > 0) { metaParts.push(genreNames.join(' / ')); }
      if (relDate.length > 0) { metaParts.push(relDate); }
      subText = metaParts.join(' · ');
    }

    const rawLogo = strVal(r, 'logo_path') || strVal(r, 'clear_logo') || strVal(r, 'logo');
    const rawTypeCandidate = strVal(r, 'type') || strVal(r, 'media_type') || strVal(r, 'item_type');
    let inferredType = '电影';
    if (isPerson) {
      inferredType = '人物';
    } else if (fallbackSource === 'collection') {
      inferredType = '合集';
    } else if (rawTypeCandidate.length > 0) {
      inferredType = normalizeMediaTypeForV3(rawTypeCandidate, false);
    } else if (fallbackSource === 'music') {
      inferredType = '音乐';
    } else if (fallbackSource.includes('tv')) {
      inferredType = '电视剧';
    }

    const resolvedSource = isMediaServerSrc
      ? 'mediaserver'
      : (normSource || strVal(r, 'source', fallbackSource));

    return {
      id: rawId || mediaId || strVal(r, 'title') || strVal(r, 'name'),
      mediaId: mediaId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      title: strVal(r, 'title') || strVal(r, 'name') || '未命名影片',
      enTitle: strVal(r, 'en_title') || strVal(r, 'original_title'),
      year: strVal(r, 'year'),
      type: inferredType,
      overview: strVal(r, 'overview'),
      vote: numVal(r, 'vote_average', numVal(r, 'rating', numVal(r, 'vote', 0))),
      posterUrl: this.resolveImageUrl(posterRaw, useCookies),
      backdropUrl: this.resolveImageUrl(backdropRaw, useCookies),
      logoUrl: this.resolveImageUrl(rawLogo, useCookies),
      source: resolvedSource,
      inLibrary: boolVal(r, 'in_library', false) || isMediaServerSrc,
      subtitle: subText,
      percent: Math.round(rawPercent),
      serverName: strVal(r, 'server'),
      playUrl: strVal(r, 'link') || strVal(r, 'play_url'),
      serverItemId: serverItemId,
      imdbId: imdbId,
      tvdbId: tvdbId
    };
  }

  /**
   * 解析标准 V3 `(mediaSource, rawMediaId)` 二元组（自动剥离 `tmdb:`/`douban:` 等前缀）。
   */
  resolveCanonicalMediaIdentity(item: MpMediaItem): MpResolvedMediaIdentity {
    const cleanMediaId = (item.mediaId ?? '').trim();
    const colonIdx = cleanMediaId.indexOf(':');
    if (colonIdx > 0) {
      const prefix = cleanMediaId.substring(0, colonIdx);
      const src = normalizeMediaSourceCode(prefix);
      const rawId = stripKnownMediaPrefix(cleanMediaId.substring(colonIdx + 1));
      if (src.length > 0 && rawId.length > 0) {
        return { mediaSource: src, rawMediaId: rawId };
      }
    }
    const cleanTmdb = stripKnownMediaPrefix(item.tmdbId);
    if (cleanTmdb.length > 0) {
      return { mediaSource: 'themoviedb', rawMediaId: cleanTmdb };
    }
    const cleanDouban = stripKnownMediaPrefix(item.doubanId);
    if (cleanDouban.length > 0) {
      return { mediaSource: 'douban', rawMediaId: cleanDouban };
    }
    const cleanImdb = stripKnownMediaPrefix(item.imdbId ?? '');
    if (cleanImdb.length > 0) {
      return { mediaSource: 'imdb', rawMediaId: cleanImdb };
    }
    if (item.source !== 'mediaserver' && item.source !== 'library') {
      const fallbackSrc = normalizeMediaSourceCode(item.source) || 'themoviedb';
      const fallbackId = stripKnownMediaPrefix(cleanMediaId || item.id);
      if (fallbackId.length > 0) {
        return { mediaSource: fallbackSrc, rawMediaId: fallbackId };
      }
    }
    return { mediaSource: '', rawMediaId: '' };
  }

  async fetchRecommend(path: string, page: number = 1): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    q['page'] = String(page);
    const resp = await this.get(['recommend', path], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], path.includes('douban') ? 'douban' : (path.includes('bangumi') ? 'bangumi' : 'themoviedb'));
      if (it) { out.push(it); }
    }
    return out;
  }

  private cachedMediaServers: string[] = [];
  private cachedSubscriptions: MpSubscribeItem[] | null = null;

  /** 清空内存中的订阅列表缓存。 */
  invalidateSubscriptionsCache(): void {
    this.cachedSubscriptions = null;
  }

  async fetchMediaServerClients(): Promise<string[]> {
    if (this.cachedMediaServers.length > 0) {
      return this.cachedMediaServers;
    }
    const resp = await this.get(['mediaserver', 'clients']);
    const out: string[] = [];
    if (resp.status === 200) {
      const arr = unwrapArray(parseJsonSafe(resp.body));
      for (let i = 0; i < arr.length; i++) {
        const r = asRec(arr[i]);
        const name = strVal(r, 'name');
        if (name.length > 0) { out.push(name); }
      }
    }
    if (out.length === 0) {
      const cfg = await this.fetchMediaServers();
      for (let i = 0; i < cfg.length; i++) {
        if (cfg[i].enabled && cfg[i].name.length > 0) {
          out.push(cfg[i].name);
        }
      }
    }
    this.cachedMediaServers = out;
    return out;
  }

  async fetchContinueWatching(): Promise<MpMediaItem[]> {
    const servers = await this.fetchMediaServerClients();
    const out: MpMediaItem[] = [];
    for (let s = 0; s < servers.length; s++) {
      const q: Record<string, string> = {};
      q['server'] = servers[s];
      const resp = await this.get(['mediaserver', 'playing'], q);
      if (resp.status !== 200) { continue; }
      const arr = unwrapArray(parseJsonSafe(resp.body));
      for (let i = 0; i < arr.length; i++) {
        const it = this.parseMediaItem(arr[i], 'mediaserver');
        if (it) {
          it.inLibrary = true;
          if (!it.serverName) { it.serverName = servers[s]; }
          if (!it.serverItemId && it.id.length > 0) { it.serverItemId = it.id; }
          out.push(it);
        }
      }
    }
    return out;
  }

  /** 拉取媒体服务器最新入库条目，完整保留 `serverItemId` 与 `serverName`。 */
  async fetchMediaServerLatest(): Promise<MpMediaItem[]> {
    const servers = await this.fetchMediaServerClients();
    const out: MpMediaItem[] = [];
    for (let s = 0; s < servers.length; s++) {
      const q: Record<string, string> = {};
      q['server'] = servers[s];
      const resp = await this.get(['mediaserver', 'latest'], q);
      if (resp.status !== 200) { continue; }
      const arr = unwrapArray(parseJsonSafe(resp.body));
      for (let i = 0; i < arr.length; i++) {
        const it = this.parseMediaItem(arr[i], 'mediaserver');
        if (it) {
          it.inLibrary = true;
          if (!it.serverName) { it.serverName = servers[s]; }
          if (!it.serverItemId && it.id.length > 0) { it.serverItemId = it.id; }
          out.push(it);
        }
      }
    }
    return out;
  }

  async fetchRecentlyAdded(): Promise<MpMediaItem[]> {
    return this.fetchMediaServerLatest();
  }

  async fetchExplore(sourceKey: string, sortBy: string = 'popularity.desc', page: number = 1): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    q['page'] = String(page);
    let segments: string[] = ['discover', 'tmdb_movies'];
    if (sourceKey === 'tmdb_movies') {
      segments = ['discover', 'tmdb_movies'];
      q['sort_by'] = sortBy;
    } else if (sourceKey === 'tmdb_tvs') {
      segments = ['discover', 'tmdb_tvs'];
      q['sort_by'] = sortBy;
    } else if (sourceKey === 'douban_movies') {
      segments = ['discover', 'douban_movies'];
    } else if (sourceKey === 'douban_tvs') {
      segments = ['discover', 'douban_tvs'];
    } else if (sourceKey === 'bangumi') {
      segments = ['discover', 'bangumi'];
    } else if (sourceKey === 'music') {
      segments = ['recommend', 'listenbrainz_chart'];
    }
    let resp = await this.get(segments, q);
    if (sourceKey === 'music' && resp.status !== 200) {
      resp = await this.get(['recommend', 'douban_music_hot'], q);
    }
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], sourceKey === 'music' ? 'musicbrainz' : sourceKey);
      if (it) { out.push(it); }
    }
    return out;
  }

  /** 拉取后端已启用的媒体搜索数据源目录（`GET /api/v1/media/source`）。 */
  async fetchMediaSearchSources(): Promise<MpMediaSearchSource[]> {
    const resp = await this.get(['media', 'source']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaSearchSource[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const src = strVal(r, 'media_source').trim();
      if (!src) { continue; }
      const rawName = strVal(r, 'name').trim() || src;
      const lowerName = rawName.toLowerCase();
      const displayName = (lowerName === 'tmdb' || lowerName === 'themoviedb') ? 'TheMovieDB' : rawName;
      const rawTypes = asArr(r['media_types']);
      const types: string[] = [];
      for (let k = 0; k < rawTypes.length; k++) {
        const t = String(rawTypes[k] ?? '').trim();
        if (t.length > 0 && t !== 'null') {
          types.push(t);
        }
      }
      out.push({
        id: src,
        name: rawName,
        displayName: displayName,
        mediaTypes: types.length > 0 ? types : ['电影', '电视剧']
      });
    }
    out.sort((a: MpMediaSearchSource, b: MpMediaSearchSource) => a.displayName.localeCompare(b.displayName));
    return out;
  }

  /**
   * 全局多域检索（对齐 V3 多选来源与媒体库类型筛选契约）：
   * - `library`：`GET /api/v1/mediaserver/search?keyword=...&type=...`
   * - `media` / `person` / `collection` / `music`：`GET /api/v1/media/search?title=...&type=...&media_source=...`
   */
  async searchMedia(
    keyword: string,
    kind: string = 'media',
    mediaSource: string = '',
    mediaSources: string[] = [],
    libraryTypes: string[] = []
  ): Promise<MpMediaItem[]> {
    const cleanKw = keyword.trim();
    if (!cleanKw) { return []; }
    let resp: NativeHttpResponse;
    if (kind === 'library') {
      const pairs: string[][] = [['keyword', cleanKw], ['limit', '40']];
      for (let i = 0; i < libraryTypes.length; i++) {
        const t = libraryTypes[i].trim();
        if (t.length > 0) {
          pairs.push(['type', t]);
        }
      }
      resp = await this.getMultiQuery(['mediaserver', 'search'], pairs);
    } else {
      const pairs: string[][] = [
        ['title', cleanKw],
        ['type', kind || 'media'],
        ['page', '1'],
        ['count', '20']
      ];
      const mergedSources: string[] = [];
      for (let i = 0; i < mediaSources.length; i++) {
        const s = mediaSources[i].trim();
        if (s.length > 0 && !mergedSources.includes(s)) {
          mergedSources.push(s);
        }
      }
      if (mergedSources.length === 0 && mediaSource.trim().length > 0) {
        mergedSources.push(mediaSource.trim());
      }
      mergedSources.sort();
      for (let i = 0; i < mergedSources.length; i++) {
        pairs.push(['media_source', mergedSources[i]]);
      }
      resp = await this.getMultiQuery(['media', 'search'], pairs);
    }
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], kind);
      if (it) {
        if (kind === 'library') {
          it.inLibrary = true;
          if (!it.serverItemId && it.id.length > 0) { it.serverItemId = it.id; }
        }
        out.push(it);
      }
    }
    return out;
  }

  async fetchMediaCredits(tmdbId: string, mediaType: string): Promise<MpCastMember[]> {
    const cleanTmdb = stripKnownMediaPrefix(tmdbId);
    if (!cleanTmdb) { return []; }
    const resp = await this.get(['tmdb', 'credits', cleanTmdb, normalizeMediaTypeForV3(mediaType)]);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpCastMember[] = [];
    for (let i = 0; i < Math.min(arr.length, 16); i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: strVal(r, 'id'),
        name: strVal(r, 'name'),
        character: strVal(r, 'character') || strVal(r, 'known_for_department'),
        profileUrl: this.resolveImageUrl(strVal(r, 'profile_path') || strVal(r, 'avatar'))
      });
    }
    return out;
  }

  async fetchMediaSeasons(tmdbId: string): Promise<MpSeasonInfo[]> {
    const cleanTmdb = stripKnownMediaPrefix(tmdbId);
    if (!cleanTmdb) { return []; }
    const resp = await this.get(['tmdb', 'seasons', cleanTmdb]);
    if (resp.status !== 200) { return []; }
    return this.parseSeasonInfoArray(unwrapArray(parseJsonSafe(resp.body)));
  }

  /** 按任意数据源身份拉取剧集全部季信息（优先 TMDB，回落 `/api/v1/media/seasons`）。 */
  async fetchMediaSeasonsForItem(item: MpMediaItem): Promise<MpSeasonInfo[]> {
    if (item.tmdbId && item.tmdbId.trim().length > 0) {
      const tmdbList = await this.fetchMediaSeasons(item.tmdbId);
      if (tmdbList.length > 0) { return tmdbList; }
    }
    const resolved = this.resolveCanonicalMediaIdentity(item);
    const q: Record<string, string> = {};
    if (resolved.mediaSource.length > 0 && resolved.rawMediaId.length > 0) {
      q['media_source'] = resolved.mediaSource;
      q['media_id'] = resolved.rawMediaId;
    } else if (item.title.trim().length > 0) {
      q['title'] = item.title.trim();
      if (item.year.trim().length > 0) {
        q['year'] = item.year.trim();
      }
    } else {
      return [];
    }
    const resp = await this.get(['media', 'seasons'], q);
    if (resp.status !== 200) { return []; }
    return this.parseSeasonInfoArray(unwrapArray(parseJsonSafe(resp.body)));
  }

  private parseSeasonInfoArray(arr: Object[]): MpSeasonInfo[] {
    const out: MpSeasonInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const sn = Math.round(numVal(r, 'season_number', i + 1));
      if (sn < 0) { continue; }
      const fallbackName = sn === 0 ? '特别篇' : `第 ${sn} 季`;
      out.push({
        seasonNumber: sn,
        name: strVal(r, 'name', fallbackName) || fallbackName,
        episodeCount: Math.round(numVal(r, 'episode_count', 0)),
        airDate: strVal(r, 'air_date'),
        posterUrl: this.resolveImageUrl(strVal(r, 'poster_path')),
        overview: strVal(r, 'overview')
      });
    }
    out.sort((a: MpSeasonInfo, b: MpSeasonInfo) => {
      if (a.seasonNumber === 0 && b.seasonNumber !== 0) { return 1; }
      if (b.seasonNumber === 0 && a.seasonNumber !== 0) { return -1; }
      return a.seasonNumber - b.seasonNumber;
    });
    return out;
  }

  /**
   * 查询 TMDB 指定季全部单集剧照与简介（`GET /api/v1/tmdb/{tmdbid}/{season}`）。
   */
  async fetchTmdbSeasonEpisodes(tmdbId: string, seasonNumber: number, episodeGroup: string = ''): Promise<MpTmdbEpisodeItem[]> {
    const cleanTmdb = stripKnownMediaPrefix(tmdbId);
    if (!cleanTmdb) { return []; }
    const q: Record<string, string> = {};
    if (episodeGroup.trim().length > 0) {
      q['episode_group'] = episodeGroup.trim();
    }
    const resp = await this.get(['tmdb', cleanTmdb, String(Math.max(0, Math.round(seasonNumber)))], q);
    if (resp.status !== 200) { return []; }
    return this.parseEpisodeInfoArray(unwrapArray(parseJsonSafe(resp.body)), cleanTmdb, seasonNumber);
  }

  /** 智能拉取指定季分集元数据（优先 TMDB，回落已入库条目的 `/api/v1/mediaserver/episode-metadata`）。 */
  async fetchSeasonEpisodesSmart(
    item: MpMediaItem,
    seasonNumber: number,
    seriesItemId: string = '',
    server: string = ''
  ): Promise<MpTmdbEpisodeItem[]> {
    if (item.tmdbId && item.tmdbId.trim().length > 0) {
      const eps = await this.fetchTmdbSeasonEpisodes(item.tmdbId, seasonNumber);
      if (eps.length > 0) { return eps; }
    }
    const sid = seriesItemId.trim();
    if (sid.length > 0) {
      const q: Record<string, string> = {};
      q['itemid'] = sid;
      q['season'] = String(Math.max(0, Math.round(seasonNumber)));
      if (server.trim().length > 0) {
        q['server'] = server.trim();
      }
      const resp = await this.get(['mediaserver', 'episode-metadata'], q);
      if (resp.status === 200) {
        const parsed = this.parseEpisodeInfoArray(unwrapArray(parseJsonSafe(resp.body)), sid, seasonNumber);
        if (parsed.length > 0) { return parsed; }
      }
    }
    return [];
  }

  private parseEpisodeInfoArray(arr: Object[], keySeed: string, seasonNumber: number): MpTmdbEpisodeItem[] {
    const out: MpTmdbEpisodeItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const epNo = Math.round(numVal(r, 'episode_number', i + 1));
      out.push({
        id: strVal(r, 'id', `${keySeed}_${seasonNumber}_${epNo}`),
        seasonNumber: Math.round(numVal(r, 'season_number', seasonNumber)),
        episodeNumber: epNo,
        title: strVal(r, 'name', `第 ${epNo} 集`) || `第 ${epNo} 集`,
        overview: strVal(r, 'overview'),
        airDate: strVal(r, 'air_date'),
        runtimeMinutes: Math.round(numVal(r, 'runtime', 0)),
        vote: numVal(r, 'vote_average', 0),
        stillUrl: this.resolveImageUrl(strVal(r, 'still_path'))
      });
    }
    out.sort((a: MpTmdbEpisodeItem, b: MpTmdbEpisodeItem) => a.episodeNumber - b.episodeNumber);
    return out;
  }

  /** 查询已入库电视剧各季可播放单集映射（`GET /api/v1/mediaserver/episodes?itemid=...`）。 */
  async fetchPlayableSeriesEpisodes(seriesItemId: string, server: string = ''): Promise<Record<string, Record<string, string>>> {
    const sid = seriesItemId.trim();
    const out: Record<string, Record<string, string>> = {};
    if (!sid) { return out; }
    const q: Record<string, string> = {};
    q['itemid'] = sid;
    if (server.trim().length > 0) {
      q['server'] = server.trim();
    }
    const resp = await this.get(['mediaserver', 'episodes'], q);
    if (resp.status < 200 || resp.status >= 300) { return out; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root) { return out; }
    const seasonKeys = Object.keys(root);
    for (let i = 0; i < seasonKeys.length; i++) {
      const sKey = seasonKeys[i];
      const epRec = asRec(root[sKey]);
      if (!epRec) { continue; }
      const inner: Record<string, string> = {};
      const epKeys = Object.keys(epRec);
      let count = 0;
      for (let j = 0; j < epKeys.length; j++) {
        const eKey = epKeys[j];
        const epId = String(epRec[eKey] ?? '').trim();
        if (epId.length > 0 && epId !== 'null') {
          inner[eKey] = epId;
          count += 1;
        }
      }
      if (count > 0) {
        out[sKey] = inner;
      }
    }
    return out;
  }

  /** 查询指定季的可播放单集映射（`GET /api/v1/mediaserver/episodes/{itemid}/{season}`）。 */
  async fetchPlayableSeasonEpisodes(seriesItemId: string, seasonNumber: number, server: string = ''): Promise<Record<string, string>> {
    const sid = seriesItemId.trim();
    const out: Record<string, string> = {};
    if (!sid) { return out; }
    const q: Record<string, string> = {};
    if (server.trim().length > 0) {
      q['server'] = server.trim();
    }
    const resp = await this.get(['mediaserver', 'episodes', sid, String(Math.max(0, Math.round(seasonNumber)))], q);
    if (resp.status < 200 || resp.status >= 300) { return out; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root) { return out; }
    const epKeys = Object.keys(root);
    for (let i = 0; i < epKeys.length; i++) {
      const eKey = epKeys[i];
      const epId = String(root[eKey] ?? '').trim();
      if (epId.length > 0 && epId !== 'null') {
        out[eKey] = epId;
      }
    }
    return out;
  }

  /** 查询远程媒体服务器已入库的季集编号（`POST /api/v1/mediaserver/exists_remote`）。 */
  async fetchRemoteExistingEpisodes(item: MpMediaItem, seasonNumber?: number): Promise<Record<string, number[]>> {
    const out: Record<string, number[]> = {};
    const resolved = this.resolveCanonicalMediaIdentity(item);
    const payload: Record<string, Object> = {};
    payload['type'] = '电视剧';
    payload['title'] = item.title.trim();
    if (item.year.trim().length > 0) {
      payload['year'] = item.year.trim();
    }
    if (seasonNumber !== undefined && seasonNumber >= 0) {
      payload['season'] = Math.round(seasonNumber);
    }
    if (resolved.mediaSource.length > 0 && resolved.rawMediaId.length > 0) {
      payload['media_source'] = resolved.mediaSource;
      payload['media_id'] = resolved.rawMediaId;
    }
    const cleanTmdb = Number(stripKnownMediaPrefix(item.tmdbId));
    if (Number.isFinite(cleanTmdb) && cleanTmdb > 0) {
      payload['tmdbid'] = Math.round(cleanTmdb);
    }
    const resp = await this.postJson(['mediaserver', 'exists_remote'], JSON.stringify(payload));
    if (resp.status < 200 || resp.status >= 300) { return out; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root) { return out; }
    const sKeys = Object.keys(root);
    for (let i = 0; i < sKeys.length; i++) {
      const sKey = sKeys[i];
      const arr = asArr(root[sKey]);
      const nums: number[] = [];
      for (let j = 0; j < arr.length; j++) {
        const n = Number(arr[j]);
        if (Number.isFinite(n) && n > 0) {
          nums.push(Math.round(n));
        }
      }
      if (nums.length > 0) {
        out[sKey] = nums;
      }
    }
    return out;
  }

  /**
   * 查询完整媒体详情（`GET /api/v1/media/{rawMediaId}?media_source=...&type_name=...`）。
   */
  async fetchMediaDetailBundle(baseItem: MpMediaItem): Promise<MpMediaDetailBundle | null> {
    const resolved = this.resolveCanonicalMediaIdentity(baseItem);
    if (!resolved.mediaSource || !resolved.rawMediaId) { return null; }
    const q: Record<string, string> = {};
    q['media_source'] = resolved.mediaSource;
    q['type_name'] = normalizeMediaTypeForV3(baseItem.type);
    const resp = await this.get(['media', resolved.rawMediaId], q);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    const parsed = this.parseMediaItem(r, resolved.mediaSource);
    const canonicalKey = `${mediaPrefixForSource(resolved.mediaSource)}:${resolved.rawMediaId}`;
    const mergedItem: MpMediaItem = parsed ? {
      id: parsed.id || baseItem.id,
      mediaId: parsed.mediaId || canonicalKey,
      tmdbId: parsed.tmdbId || baseItem.tmdbId,
      doubanId: parsed.doubanId || baseItem.doubanId,
      title: parsed.title || baseItem.title,
      enTitle: parsed.enTitle || baseItem.enTitle,
      year: parsed.year || baseItem.year,
      type: parsed.type || baseItem.type,
      overview: parsed.overview || baseItem.overview,
      vote: parsed.vote > 0 ? parsed.vote : baseItem.vote,
      posterUrl: parsed.posterUrl || baseItem.posterUrl,
      backdropUrl: parsed.backdropUrl || baseItem.backdropUrl,
      logoUrl: parsed.logoUrl || baseItem.logoUrl,
      source: parsed.source || resolved.mediaSource,
      inLibrary: parsed.inLibrary || baseItem.inLibrary,
      subtitle: parsed.subtitle || baseItem.subtitle,
      percent: baseItem.percent,
      serverName: baseItem.serverName || parsed.serverName,
      playUrl: baseItem.playUrl || parsed.playUrl,
      serverItemId: baseItem.serverItemId || parsed.serverItemId,
      imdbId: parsed.imdbId || baseItem.imdbId,
      tvdbId: parsed.tvdbId || baseItem.tvdbId
    } : baseItem;

    const cast: MpCastMember[] = [];
    const actorsRaw = asArr(r['actors']);
    for (let i = 0; i < Math.min(actorsRaw.length, 16); i++) {
      const a = asRec(actorsRaw[i]);
      if (!a) { continue; }
      const avatarObj = asRec(a['avatar']);
      const avatarRaw = strVal(a, 'profile_path') || (avatarObj ? (strVal(avatarObj, 'large') || strVal(avatarObj, 'normal')) : strVal(a, 'avatar'));
      cast.push({
        id: strVal(a, 'id', `actor_${i}`),
        name: strVal(a, 'name'),
        character: strVal(a, 'character') || strVal(a, 'role'),
        profileUrl: this.resolveImageUrl(avatarRaw)
      });
    }

    const seasons: MpSeasonInfo[] = [];
    const seasonsRaw = asArr(r['season_info']).length > 0 ? asArr(r['season_info']) : asArr(r['seasons']);
    for (let i = 0; i < seasonsRaw.length; i++) {
      const s = asRec(seasonsRaw[i]);
      if (!s) { continue; }
      seasons.push({
        seasonNumber: numVal(s, 'season_number', i + 1),
        name: strVal(s, 'name', `第 ${i + 1} 季`),
        episodeCount: numVal(s, 'episode_count', 0),
        airDate: strVal(s, 'air_date'),
        posterUrl: this.resolveImageUrl(strVal(s, 'poster_path')),
        overview: strVal(s, 'overview')
      });
    }
    return { item: mergedItem, cast: cast, seasons: seasons };
  }

  private normalizeRatingSourceKey(raw: string): string {
    const clean = (raw ?? '').trim().toLowerCase();
    if (clean === 'imdb') { return 'imdb'; }
    if (clean === 'themoviedb' || clean === 'tmdb') { return 'tmdb'; }
    if (clean === 'rottentomatoes' || clean === 'rotten_tomatoes' || clean === 'rt' || clean === 'critic') {
      return 'rottentomatoes';
    }
    if (clean === 'douban' || clean === 'douban_movie') { return 'douban'; }
    if (clean === 'bangumi' || clean === 'bgm') { return 'bangumi'; }
    if (clean === 'anilist') { return 'anilist'; }
    if (clean === 'community') { return 'community'; }
    return '';
  }

  private orderRatingBadges(scores: Map<string, string>): MpMediaRatingBadge[] {
    const order: string[] = ['imdb', 'tmdb', 'rottentomatoes', 'douban', 'bangumi', 'anilist'];
    const out: MpMediaRatingBadge[] = [];
    for (let i = 0; i < order.length; i++) {
      const k = order[i];
      const v = scores.get(k);
      if (v && v.length > 0) {
        out.push({ source: k, label: v });
      }
    }
    const hasNamedTenScale = out.some((b: MpMediaRatingBadge) => b.source !== 'rottentomatoes');
    if (!hasNamedTenScale) {
      const comm = scores.get('community');
      if (comm && comm.length > 0) {
        out.unshift({ source: 'community', label: comm });
      }
    }
    return out;
  }

  /** 基于手头已有的媒体或媒体库评分构造零延迟初始多元评分列表。 */
  seedRatingsForItem(
    item: MpMediaItem,
    criticRating: number = 0,
    serverRatings: MpMediaRatingBadge[] = []
  ): MpMediaRatingBadge[] {
    const scores: Map<string, string> = new Map<string, string>();
    for (let i = 0; i < serverRatings.length; i++) {
      const norm = this.normalizeRatingSourceKey(serverRatings[i].source);
      if (norm.length > 0 && serverRatings[i].label.length > 0 && !scores.has(norm)) {
        scores.set(norm, serverRatings[i].label);
      }
    }
    if (!scores.has('rottentomatoes') && Number.isFinite(criticRating) && criticRating > 0) {
      scores.set('rottentomatoes', `${Math.max(1, Math.min(100, Math.round(criticRating)))}%`);
    }
    if (Number.isFinite(item.vote) && item.vote > 0) {
      const norm = this.normalizeRatingSourceKey(item.source) || 'community';
      if (!scores.has(norm)) {
        scores.set(norm, Math.min(10, item.vote).toFixed(1));
      }
    }
    return this.orderRatingBadges(scores);
  }

  private async recognizeRatingBySource(
    title: string,
    year: string,
    expectedType: string,
    mediaSource: string
  ): Promise<string> {
    const cleanTitle = title.trim();
    if (!cleanTitle) { return ''; }
    const queryTitle = year.trim().length >= 4 ? `${cleanTitle} ${year.trim().substring(0, 4)}` : cleanTitle;
    const q: Record<string, string> = {
      'title': queryTitle,
      'media_source': mediaSource
    };
    const resp = await this.get(['media', 'recognize'], q);
    if (resp.status !== 200) { return ''; }
    const env = unwrapObject(parseJsonSafe(resp.body));
    const media = env ? asRec(env['media_info']) : null;
    if (!media) { return ''; }
    const vote = numVal(media, 'vote_average', 0);
    if (vote <= 0) { return ''; }
    const rawType = strVal(media, 'type');
    if (rawType.length > 0 && normalizeMediaTypeForV3(rawType) !== expectedType) {
      return '';
    }
    if (year.trim().length >= 4) {
      const reqY = Number(year.trim().substring(0, 4));
      const gotYearStr = strVal(media, 'year');
      const gotY = gotYearStr.length >= 4 ? Number(gotYearStr.substring(0, 4)) : NaN;
      if (Number.isFinite(reqY) && Number.isFinite(gotY) && Math.abs(reqY - gotY) > 1) {
        return '';
      }
    }
    return Math.min(10, vote).toFixed(1);
  }

  /**
   * 异步并发聚合免配置多元评分（IMDb / TMDB / 烂番茄影评新鲜度 / 豆瓣 / Bangumi），带实例隔离内存缓存。
   */
  async fetchMultiSourceRatings(
    item: MpMediaItem,
    criticRating: number = 0,
    serverRatings: MpMediaRatingBadge[] = [],
    serverItemId: string = '',
    serverName: string = ''
  ): Promise<MpMediaRatingBadge[]> {
    const typeName = normalizeMediaTypeForV3(item.type);
    const idKey = item.tmdbId.trim().length > 0
      ? `tmdb:${item.tmdbId.trim()}`
      : ((item.imdbId && item.imdbId.trim().length > 0)
        ? `imdb:${item.imdbId.trim()}`
        : (item.doubanId.trim().length > 0 ? `douban:${item.doubanId.trim()}` : `${item.source}:${item.id}`));
    const cacheKey = `${this.baseUrl}|${typeName}|${idKey}`;
    const cached = this.multiRatingsCache.get(cacheKey);
    if (cached && cached.length > 0) {
      return cached;
    }

    const scores: Map<string, string> = new Map<string, string>();
    const seeded = this.seedRatingsForItem(item, criticRating, serverRatings);
    for (let i = 0; i < seeded.length; i++) {
      scores.set(seeded[i].source, seeded[i].label);
    }

    let tmdbId = stripKnownMediaPrefix(item.tmdbId);
    if (!tmdbId && normalizeMediaSourceCode(item.source) === 'themoviedb') {
      tmdbId = stripKnownMediaPrefix(item.mediaId || item.id);
    }
    let imdbId = stripKnownMediaPrefix(item.imdbId ?? '');
    let doubanId = stripKnownMediaPrefix(item.doubanId);
    if (!doubanId && normalizeMediaSourceCode(item.source) === 'douban') {
      doubanId = stripKnownMediaPrefix(item.mediaId || item.id);
    }
    const isBangumiSrc = normalizeMediaSourceCode(item.source) === 'bangumi';
    const bangumiId = isBangumiSrc ? stripKnownMediaPrefix(item.mediaId || item.id) : '';
    let title = item.title.trim();
    let year = item.year.trim();

    if (tmdbId.length > 0 && (!scores.has('tmdb') || imdbId.length === 0)) {
      try {
        const q: Record<string, string> = { 'media_source': 'themoviedb', 'type_name': typeName };
        const resp = await this.get(['media', tmdbId], q);
        if (resp.status === 200) {
          const r = unwrapObject(parseJsonSafe(resp.body));
          if (r) {
            const v = numVal(r, 'vote_average', 0);
            if (v > 0 && !scores.has('tmdb')) {
              scores.set('tmdb', Math.min(10, v).toFixed(1));
            }
            if (!imdbId) { imdbId = stripKnownMediaPrefix(strVal(r, 'imdb_id')); }
            if (!doubanId) { doubanId = stripKnownMediaPrefix(strVal(r, 'douban_id')); }
            if (!title) { title = strVal(r, 'title'); }
            if (!year) { year = strVal(r, 'year'); }
          }
        }
      } catch {
        // ignore tmdb enrichment failure
      }
    }

    const fetchById = async (src: string, rawId: string): Promise<string> => {
      if (!rawId || rawId === '0') { return ''; }
      try {
        const q: Record<string, string> = { 'media_source': src, 'type_name': typeName };
        const resp = await this.get(['media', rawId], q);
        if (resp.status !== 200) { return ''; }
        const r = unwrapObject(parseJsonSafe(resp.body));
        const v = r ? numVal(r, 'vote_average', 0) : 0;
        return v > 0 ? Math.min(10, v).toFixed(1) : '';
      } catch {
        return '';
      }
    };

    const tasks = await Promise.all([
      (!scores.has('imdb') && imdbId.toLowerCase().startsWith('tt'))
        ? fetchById('imdb', imdbId)
        : Promise.resolve(''),
      !scores.has('douban')
        ? (doubanId.length > 0 ? fetchById('douban', doubanId) : this.recognizeRatingBySource(title, year, typeName, 'douban'))
        : Promise.resolve(''),
      (!scores.has('bangumi') && bangumiId.length > 0)
        ? fetchById('bangumi', bangumiId)
        : Promise.resolve(''),
      (!scores.has('rottentomatoes') && serverItemId.trim().length > 0)
        ? this.fetchMediaServerDetail(serverItemId.trim(), serverName)
        : Promise.resolve(null as MpMediaServerDetail | null)
    ]);

    if (tasks[0].length > 0 && !scores.has('imdb')) { scores.set('imdb', tasks[0]); }
    if (tasks[1].length > 0 && !scores.has('douban')) { scores.set('douban', tasks[1]); }
    if (tasks[2].length > 0 && !scores.has('bangumi')) { scores.set('bangumi', tasks[2]); }
    const srvDetail = tasks[3];
    if (srvDetail) {
      const srvRatings = srvDetail.ratings ?? [];
      for (let i = 0; i < srvRatings.length; i++) {
        const norm = this.normalizeRatingSourceKey(srvRatings[i].source);
        if (norm.length > 0 && srvRatings[i].label.length > 0 && !scores.has(norm)) {
          scores.set(norm, srvRatings[i].label);
        }
      }
      if (!scores.has('rottentomatoes') && srvDetail.criticRating && srvDetail.criticRating > 0) {
        scores.set('rottentomatoes', `${Math.max(1, Math.min(100, Math.round(srvDetail.criticRating)))}%`);
      }
    }

    const ordered = this.orderRatingBadges(scores);
    if (ordered.length > 0) {
      this.multiRatingsCache.set(cacheKey, ordered);
    }
    return ordered;
  }

  /**
   * 批量查询本地入库与分季订阅状态（`POST /api/v1/media/status`）。
   */
  async fetchMediaStatus(item: MpMediaItem, season?: number): Promise<MpMediaStatusResult> {
    const empty: MpMediaStatusResult = {
      subscribed: false,
      seasons: [],
      itemId: '',
      server: ''
    };
    const resolved = this.resolveCanonicalMediaIdentity(item);
    const reqItem: Record<string, Object> = {};
    if (resolved.mediaSource.length > 0 && resolved.rawMediaId.length > 0) {
      reqItem['media_source'] = resolved.mediaSource;
      reqItem['media_id'] = resolved.rawMediaId;
    }
    const mtype = normalizeMediaTypeForV3(item.type, season !== undefined && season > 0);
    reqItem['mtype'] = mtype;
    if (item.title.trim().length > 0) {
      reqItem['title'] = item.title.trim();
    }
    if (item.year.trim().length > 0) {
      reqItem['year'] = String(item.year).trim();
    }
    if (season !== undefined && season >= 0) {
      reqItem['season'] = Math.round(season);
    }
    const resp = await this.postJson(['media', 'status'], JSON.stringify([reqItem]));
    if (resp.status !== 200) { return empty; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    if (arr.length === 0) { return empty; }
    const r = asRec(arr[0]);
    if (!r) { return empty; }
    const seasonsRec = asRec(r['seasons']);
    const seasonNums: number[] = [];
    if (seasonsRec) {
      const keys = Object.keys(seasonsRec);
      for (let i = 0; i < keys.length; i++) {
        const sn = Number(keys[i]);
        if (Number.isFinite(sn) && sn >= 0) {
          seasonNums.push(Math.round(sn));
        }
      }
      seasonNums.sort((a: number, b: number) => a - b);
    }
    return {
      subscribed: boolVal(r, 'subscribed', false) || seasonNums.length > 0,
      seasons: seasonNums,
      itemId: strVal(r, 'item_id'),
      server: strVal(r, 'server')
    };
  }

  /**
   * 检查指定媒体是否已在订阅队列（严格遵循 V3 `GET /api/v1/subscribe/media/{rawMediaId}?media_source=...`）。
   */
  async checkMediaSubscribed(item: MpMediaItem, season?: number): Promise<boolean> {
    const resolved = this.resolveCanonicalMediaIdentity(item);
    if (!resolved.mediaSource || !resolved.rawMediaId) {
      const statusRes = await this.fetchMediaStatus(item, season);
      return statusRes.subscribed;
    }
    const q: Record<string, string> = {};
    q['media_source'] = resolved.mediaSource;
    q['mtype'] = normalizeMediaTypeForV3(item.type, season !== undefined && season > 0);
    if (season !== undefined && season >= 0) {
      q['season'] = String(Math.round(season));
    }
    if (item.title.trim().length > 0) {
      q['title'] = item.title.trim();
    }
    if (item.year.trim().length > 0) {
      q['year'] = String(item.year).trim();
    }
    const resp = await this.get(['subscribe', 'media', resolved.rawMediaId], q);
    if (resp.status !== 200) { return false; }
    const rec = unwrapObject(parseJsonSafe(resp.body));
    return rec !== null && numVal(rec, 'id', 0) > 0;
  }

  /**
   * 新增订阅并返回结构化状态消息（严格遵循 V3 `media_source` + `media_id` + `season` 契约并校验 `parsed.success === true`）。
   */
  async addSubscribeWithMessage(item: MpMediaItem, season?: number): Promise<MpSubscribeMutationResult> {
    const resolved = this.resolveCanonicalMediaIdentity(item);
    const mtype = normalizeMediaTypeForV3(item.type, season !== undefined && season > 0);
    const payload: Record<string, Object> = {};
    payload['name'] = item.title.trim();
    payload['type'] = mtype;
    payload['year'] = item.year ? String(item.year).trim() : '';
    if (resolved.mediaSource.length > 0 && resolved.rawMediaId.length > 0) {
      payload['media_source'] = resolved.mediaSource;
      payload['media_id'] = resolved.rawMediaId;
    }
    if (mtype === '电视剧') {
      payload['season'] = (season !== undefined && season >= 0) ? Math.round(season) : 1;
    }
    const resp = await this.postJson(['subscribe'], JSON.stringify(payload), true);
    const parsed = asRec(parseJsonSafe(resp.body));
    const ok = resp.status >= 200 && resp.status < 300 && parsed !== null && boolVal(parsed, 'success', false) === true;
    const dataRec = parsed ? asRec(parsed['data']) : null;
    const subId = numVal(dataRec, 'id', 0);
    const msg = strVal(parsed, 'message');
    if (ok) {
      this.invalidateSubscriptionsCache();
    }
    return {
      ok: ok,
      message: msg.length > 0 ? msg : (ok ? '已添加至 MoviePilot 订阅队列' : '订阅添加失败，请检查媒体标识或服务端状态'),
      id: subId
    };
  }

  /** 新增订阅（布尔简写封装）。 */
  async addSubscribe(item: MpMediaItem, season?: number): Promise<boolean> {
    const res = await this.addSubscribeWithMessage(item, season);
    return res.ok;
  }

  /**
   * 按媒体数据源身份取消/删除订阅（`DELETE /api/v1/subscribe/media/{rawMediaId}?media_source=...`）。
   */
  async deleteMediaSubscribe(item: MpMediaItem, season?: number): Promise<boolean> {
    const resolved = this.resolveCanonicalMediaIdentity(item);
    if (!resolved.mediaSource || !resolved.rawMediaId) {
      return false;
    }
    const q: Record<string, string> = {};
    q['media_source'] = resolved.mediaSource;
    if (season !== undefined && season >= 0) {
      q['season'] = String(Math.round(season));
    }
    const resp = await this.deleteReq(['subscribe', 'media', resolved.rawMediaId], q);
    if (resp.status < 200 || resp.status >= 300) {
      return false;
    }
    const parsed = asRec(parseJsonSafe(resp.body));
    const ok = parsed ? boolVal(parsed, 'success', true) : true;
    if (ok) {
      this.invalidateSubscriptionsCache();
    }
    return ok;
  }

  async fetchDashboardStats(): Promise<MpDashboardStats> {
    const stats: MpDashboardStats = {
      movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0, musicCount: 0,
      movieMonthly: 0, tvMonthly: 0, episodeMonthly: 0, musicMonthly: 0,
      storageUsedBytes: 0, storageTotalBytes: 0,
      downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
      memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
    };
    const results = await Promise.all([
      this.get(['dashboard', 'statistic']),
      this.get(['dashboard', 'storage']),
      this.get(['dashboard', 'downloader']),
      this.get(['dashboard', 'memory']),
      this.get(['dashboard', 'transfer']),
      this.get(['dashboard', 'schedule'])
    ]);
    const st = unwrapObject(parseJsonSafe(results[0].body));
    if (st) {
      stats.movieCount = numVal(st, 'movie_count');
      stats.tvCount = numVal(st, 'tv_count');
      stats.episodeCount = numVal(st, 'episode_count');
      stats.userCount = numVal(st, 'user_count');
      stats.musicCount = numVal(st, 'music_count', numVal(st, 'song_count', 0));
      stats.movieMonthly = numVal(st, 'movie_monthly', numVal(st, 'movie_add', 0));
      stats.tvMonthly = numVal(st, 'tv_monthly', numVal(st, 'tv_add', 0));
      stats.episodeMonthly = numVal(st, 'episode_monthly', numVal(st, 'episode_add', 0));
      stats.musicMonthly = numVal(st, 'music_monthly', numVal(st, 'music_add', 0));
    }
    const stor = unwrapObject(parseJsonSafe(results[1].body));
    if (stor) {
      stats.storageUsedBytes = numVal(stor, 'used_storage');
      stats.storageTotalBytes = numVal(stor, 'total_storage');
    }
    const dl = unwrapObject(parseJsonSafe(results[2].body));
    if (dl) {
      stats.downloadSpeed = numVal(dl, 'download_speed');
      stats.uploadSpeed = numVal(dl, 'upload_speed');
      stats.downloadSize = numVal(dl, 'download_size');
      stats.uploadSize = numVal(dl, 'upload_size');
    }
    const memParsed = parseJsonSafe(results[3].body);
    if (Array.isArray(memParsed) && (memParsed as Object[]).length >= 2) {
      const mArr = memParsed as Object[];
      stats.memoryUsedBytes = Number(mArr[0]) || 0;
      stats.memoryPercent = Number(mArr[1]) || 0;
    } else {
      const memObj = unwrapObject(memParsed);
      if (memObj) {
        stats.memoryUsedBytes = numVal(memObj, 'used', numVal(memObj, 'memory_used', 0));
        const total = numVal(memObj, 'total', 0);
        const pct = numVal(memObj, 'usage', total > 0 ? (stats.memoryUsedBytes / total) * 100 : 0);
        stats.memoryPercent = pct;
      }
    }
    const tr = unwrapArray(parseJsonSafe(results[4].body));
    const counts: number[] = [];
    let recentSum = 0;
    for (let i = 0; i < tr.length; i++) {
      const c = Number(tr[i]) || 0;
      counts.push(c);
      recentSum += c;
    }
    stats.transferCounts = counts;
    if ((stats.episodeMonthly ?? 0) === 0 && recentSum > 0) {
      stats.episodeMonthly = recentSum;
    }
    const sched = unwrapArray(parseJsonSafe(results[5].body));
    stats.scheduleCount = sched.length;

    // 同步写入桌面服务卡片快照
    try {
      const widgetSnap: Record<string, Object> = {};
      widgetSnap['server'] = this.baseUrl.replace(/^https?:\/\//, '').split('/')[0] || 'MoviePilot';
      widgetSnap['movies'] = stats.movieCount;
      widgetSnap['tvs'] = stats.tvCount;
      widgetSnap['music'] = stats.musicCount ?? 0;
      widgetSnap['speed'] = formatSpeed(stats.downloadSpeed);
      await NativeHuksStore.shared().saveWidgetSnapshot(JSON.stringify(widgetSnap));
    } catch {
      // ignore widget snapshot write error
    }
    return stats;
  }

  /** 拉取真实 `/api/v1/github/community` 社区勋章并映射解锁条件、贡献记录与佩戴状态。 */
  async fetchCommunityMedals(refresh: boolean = false): Promise<MpCommunityState> {
    const scope = this.accountStorageScope();
    const resp = await this.get(['github', 'community'], refresh ? { 'refresh': 'true' } : {});
    const out: MpCommunityState = {
      githubLogin: this.userName || 'MoviePilot',
      earnedCount: 0,
      totalCount: 7,
      wornMedalId: '',
      medals: []
    };
    if (resp.status !== 200) { return out; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root) { return out; }
    const userRec = asRec(root['user']);
    const topLogin = strVal(root, 'login');
    if (topLogin.length > 0) {
      out.githubLogin = topLogin;
    } else if (userRec) {
      out.githubLogin = strVal(userRec, 'login', out.githubLogin);
    }
    const globalWorn = scope.length > 0 ? await NativeHuksStore.shared().loadUsagePreference('mp_worn_medal_v2_' + scope) : '';
    if (globalWorn.length > 0) {
      out.wornMedalId = globalWorn;
    }

    const criteriaDefaults: Record<string, string> = {};
    criteriaDefaults['code'] = '向 MoviePilot 官方仓库提交并合入核心代码 PR，按累计合并贡献晋升 Tier 1–4。';
    criteriaDefaults['plugin'] = '开发并维护 MoviePilot 官方或社区高质量插件，按生态影响力晋升 Tier 1–4。';
    criteriaDefaults['maintainer'] = '长期参与代码评审、版本发布与仓库治理的核心维护成员。';
    criteriaDefaults['helper'] = '在 GitHub Issues / Discussions 积极协助社区用户排查问题与解答疑问。';
    criteriaDefaults['security'] = '负责任地报告安全漏洞或加固认证、网络与沙盒边界。';
    criteriaDefaults['tester'] = '深度参与新版本内测反馈、回归验证与跨平台兼容性测试。';
    criteriaDefaults['pioneer'] = '早期参与生态共建、文档完善或重要里程碑探索的社区先驱。';

    const rawMedals = asArr(root['medals']);
    const medals: MpCommunityMedal[] = [];
    for (let i = 0; i < rawMedals.length; i++) {
      const m = asRec(rawMedals[i]);
      if (!m) { continue; }
      const id = strVal(m, 'key') || strVal(m, 'id') || strVal(m, 'code');
      if (!id) { continue; }
      const hasAt = strVal(m, 'at').length > 0 || strVal(m, 'earned_at').length > 0;
      const basis = strVal(m, 'basis');
      const earned = m['earned'] !== undefined
        ? boolVal(m, 'earned', false)
        : (hasAt || basis === 'reached' || basis === 'recognized');
      const tier = Math.max(1, Math.min(4, numVal(m, 'tier', 1)));
      const isTiered = id === 'code' || id === 'plugin';
      const frontAsset = isTiered ? `${id}-front-t${tier}.webp` : `${id}-front.webp`;
      const badgeAsset = isTiered ? `${id}-badge-t${tier}.webp` : `${id}-badge.webp`;
      const backAsset = `${id}-back.webp`;
      const titleMap: Record<string, string> = {};
      titleMap['code'] = '核心代码贡献';
      titleMap['plugin'] = '插件生态构建';
      titleMap['maintainer'] = '社区维护者';
      titleMap['helper'] = '热心答疑';
      titleMap['security'] = '安全守护';
      titleMap['tester'] = '先锋测试';
      titleMap['pioneer'] = '社区先驱';
      const title = strVal(m, 'name') || strVal(m, 'title') || (titleMap[id] ?? id);
      const sub = strVal(m, 'description') || strVal(m, 'tier_label') || (isTiered ? `Tier ${tier}` : '荣耀勋章');
      const dateStr = strVal(m, 'at') || strVal(m, 'earned_at') || strVal(m, 'date') || '2026-11';
      const isWorn = earned && globalWorn === id;
      if (isWorn && (!out.wornMedalId || out.wornMedalId.length === 0)) {
        out.wornMedalId = id;
      }
      const criteria = strVal(m, 'criteria') || strVal(m, 'rule') || strVal(m, 'condition') || (criteriaDefaults[id] ?? sub);
      const facts: string[] = [];
      const rawFacts = asArr(m['facts']).length > 0 ? asArr(m['facts']) : asArr(m['highlights']);
      for (let f = 0; f < rawFacts.length; f++) {
        const ft = String(rawFacts[f] ?? '').trim();
        if (ft.length > 0) { facts.push(ft); }
      }
      const prog = strVal(m, 'progress_text') || strVal(m, 'value_text');
      if (prog.length > 0 && !facts.includes(prog)) { facts.push(`当前进度：${prog}`); }
      if (earned && dateStr.length > 0) { facts.push(`解锁时间：${dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr}`); }
      if (isTiered) { facts.push(`当前等级：Tier ${tier}`); }

      medals.push({
        id: id,
        title: title,
        subtitle: sub,
        category: strVal(m, 'category', 'community'),
        tier: tier,
        earned: earned,
        earnedDate: dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr,
        frontAsset: frontAsset,
        backAsset: backAsset,
        badgeAsset: badgeAsset,
        metricLabel: prog || (isTiered ? `T${tier}` : (earned ? '已获得' : '待解锁')),
        worn: isWorn,
        criteria: criteria,
        facts: facts
      });
      if (earned) { out.earnedCount++; }
    }
    out.totalCount = medals.length > 0 ? medals.length : 7;
    out.medals = medals;
    return out;
  }

  /** 按实例和本地账号隔离偏好，不调用不存在的服务端佩戴接口。 */
  async wearCommunityMedal(medalId: string): Promise<boolean> {
    if (this.token.length === 0 || this.userName.length === 0) { return false; }
    const scope = this.accountStorageScope();
    if (scope.length === 0) { return false; }
    const state = await this.fetchCommunityMedals();
    if (scope !== this.accountStorageScope()) { return false; }
    if (medalId.length > 0 && !state.medals.some((medal: MpCommunityMedal) => medal.id === medalId && medal.earned)) {
      return false;
    }
    await NativeHuksStore.shared().saveUsagePreference('mp_worn_medal_v2_' + scope, medalId);
    return true;
  }

  /** 当前真实后端通过 refresh 查询参数强制同步社区资料。 */
  async refreshCommunityMedals(): Promise<MpCommunityState> {
    return this.fetchCommunityMedals(true);
  }

  private parseSubscribeRecord(r: Record<string, Object> | null): MpSubscribeItem | null {
    if (!r) { return null; }
    const rawSites = asArr(r['sites']);
    const siteIds: number[] = [];
    for (let j = 0; j < rawSites.length; j++) {
      const sid = Number(rawSites[j]);
      if (Number.isFinite(sid) && sid > 0) { siteIds.push(sid); }
    }
    const rawGroups = asArr(r['filter_groups']);
    const groups: string[] = [];
    for (let j = 0; j < rawGroups.length; j++) {
      const g = String(rawGroups[j] ?? '').trim();
      if (g.length > 0) { groups.push(g); }
    }
    return {
      id: numVal(r, 'id'),
      name: strVal(r, 'name'),
      year: strVal(r, 'year'),
      type: strVal(r, 'type', '电影'),
      season: numVal(r, 'season', 0),
      totalEpisode: numVal(r, 'total_episode', 0),
      lackEpisode: numVal(r, 'lack_episode', 0),
      state: strVal(r, 'state', 'R'),
      posterUrl: this.resolveImageUrl(strVal(r, 'poster')),
      backdropUrl: this.resolveImageUrl(strVal(r, 'backdrop') || strVal(r, 'poster')),
      vote: numVal(r, 'vote', 0),
      description: strVal(r, 'description'),
      savePath: strVal(r, 'save_path'),
      quality: strVal(r, 'quality'),
      resolution: strVal(r, 'resolution'),
      effect: strVal(r, 'effect'),
      bestVersion: boolVal(r, 'best_version', false),
      startEpisode: numVal(r, 'start_episode', 0),
      episodeGroup: strVal(r, 'episode_group'),
      downloader: strVal(r, 'downloader'),
      sites: siteIds,
      filterGroups: groups,
      include: strVal(r, 'include'),
      exclude: strVal(r, 'exclude'),
      customWords: strVal(r, 'custom_words'),
      searchImdbid: boolVal(r, 'search_imdbid', false),
      interval: numVal(r, 'interval', numVal(r, 'search_interval', 0)),
      date: strVal(r, 'date'),
      rawJson: JSON.stringify(r)
    };
  }

  async fetchSubscriptions(): Promise<MpSubscribeItem[]> {
    const resp = await this.get(['subscribe'], {}, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpSubscribeItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = this.parseSubscribeRecord(asRec(arr[i]));
      if (parsed) { out.push(parsed); }
    }
    this.cachedSubscriptions = out;
    return out;
  }

  /**
   * 拉取订阅关联下载与媒体库文件详情（`GET /api/v1/subscribe/files/{subscribe_id}`）。
   */
  async fetchSubscribeFiles(subscribeId: number): Promise<MpSubscribeFilesInfo | null> {
    if (!Number.isFinite(subscribeId) || subscribeId <= 0) { return null; }
    const resp = await this.get(['subscribe', 'files', String(Math.round(subscribeId))]);
    if (resp.status !== 200) { return null; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root) { return null; }
    const sub = this.parseSubscribeRecord(asRec(root['subscribe']));
    const episodesDict = asRec(root['episodes']);
    const episodes: MpSubscribeEpisodeFiles[] = [];
    if (episodesDict) {
      const keys = Object.keys(episodesDict);
      keys.sort((a: string, b: string) => {
        const na = Number(a);
        const nb = Number(b);
        if (Number.isFinite(na) && Number.isFinite(nb)) { return na - nb; }
        return a.localeCompare(b);
      });
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const epRec = asRec(episodesDict[key]);
        if (!epRec) { continue; }
        const epNum = Number.isFinite(Number(key)) ? Math.round(Number(key)) : i;
        const dlRaw = asArr(epRec['download']);
        const downloads: MpSubscribeDownloadFile[] = [];
        for (let d = 0; d < dlRaw.length; d++) {
          const dr = asRec(dlRaw[d]);
          if (!dr) { continue; }
          downloads.push({
            torrentTitle: strVal(dr, 'torrent_title'),
            siteName: strVal(dr, 'site_name'),
            downloader: strVal(dr, 'downloader'),
            hash: strVal(dr, 'hash'),
            filePath: strVal(dr, 'file_path')
          });
        }
        const libRaw = asArr(epRec['library']);
        const libraries: MpSubscribeLibraryFile[] = [];
        for (let l = 0; l < libRaw.length; l++) {
          const lr = asRec(libRaw[l]);
          if (!lr) { continue; }
          libraries.push({
            storage: strVal(lr, 'storage', 'local'),
            filePath: strVal(lr, 'file_path'),
            server: strVal(lr, 'server'),
            serverType: strVal(lr, 'server_type'),
            itemId: strVal(lr, 'itemid') || strVal(lr, 'item_id')
          });
        }
        episodes.push({
          episodeKey: key,
          episodeNumber: epNum,
          title: strVal(epRec, 'title', epNum === 0 ? (sub ? sub.name : '正片') : `第 ${epNum} 集`),
          description: strVal(epRec, 'description'),
          backdropUrl: this.resolveImageUrl(strVal(epRec, 'backdrop')),
          downloads: downloads,
          libraries: libraries
        });
      }
    }
    let downloadedCount = 0;
    let libraryCount = 0;
    let missingCount = 0;
    for (let i = 0; i < episodes.length; i++) {
      const hasDl = episodes[i].downloads.length > 0;
      const hasLib = episodes[i].libraries.length > 0;
      if (hasDl) { downloadedCount++; }
      if (hasLib) { libraryCount++; }
      if (!hasDl && !hasLib) { missingCount++; }
    }
    const totalCount = episodes.length > 0
      ? episodes.length
      : (sub && sub.totalEpisode > 0 ? sub.totalEpisode : (sub ? 1 : 0));
    if (episodes.length === 0 && totalCount > 0) {
      missingCount = sub && sub.lackEpisode > 0 ? sub.lackEpisode : totalCount;
    }
    return {
      subscribe: sub,
      episodes: episodes,
      totalCount: totalCount,
      downloadedCount: downloadedCount,
      libraryCount: libraryCount,
      missingCount: missingCount
    };
  }

  /** 切换订阅启用/暂停状态（严格使用 V3 `PUT /api/v1/subscribe/status/{id}?state=R|S`）。 */
  async toggleSubscribeStatus(sub: MpSubscribeItem): Promise<boolean> {
    const next = sub.state === 'S' ? 'R' : 'S';
    const q: Record<string, string> = {};
    q['state'] = next;
    const resp = await this.putJsonQuery(['subscribe', 'status', String(sub.id)], q, '{}');
    return resp.status >= 200 && resp.status < 300;
  }

  async toggleSubscribeState(sub: MpSubscribeItem): Promise<boolean> {
    return this.toggleSubscribeStatus(sub);
  }

  /** 使用本地日期格式，避免 UTC 转换令日历窗口偏移一天。 */
  private calendarDate(date: Date): string {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  /** 读取未来 31 天的分页日历，按真实嵌套订阅和分集响应展开。 */
  async fetchSubscribeCalendar(): Promise<MpCalendarEpisodeItem[]> {
    const start = new Date();
    const end = new Date(start.getTime());
    end.setDate(end.getDate() + 31);
    const subscriptions = await this.fetchSubscriptions();
    const out: MpCalendarEpisodeItem[] = [];
    let page = 1;
    let consumed = 0;
    while (true) {
      const query: Record<string, string> = {
        'start': this.calendarDate(start), 'end': this.calendarDate(end), 'page': String(page), 'count': '200'
      };
      const resp = await this.get(['subscribe', 'calendar'], query);
      if (resp.status !== 200) { throw new Error(`加载日历失败（HTTP ${resp.status}）`); }
      const root = unwrapObject(parseJsonSafe(resp.body));
      if (!root) { throw new Error('日历响应格式无效'); }
      const events = asArr(root['items']);
      for (let i = 0; i < events.length; i++) {
        const event = asRec(events[i]);
        const sub = event ? asRec(event['subscribe']) : null;
        if (!sub) { continue; }
        const details = subscriptions.find((item: MpSubscribeItem) => item.id === numVal(sub, 'id'));
        const episodes = event ? asArr(event['episodes']) : [];
        const count = Math.max(1, episodes.length);
        for (let j = 0; j < count; j++) {
          const ep = j < episodes.length ? asRec(episodes[j]) : null;
          const episodeNumber = numVal(ep, 'episode_number', 0);
          out.push({
            id: `${numVal(sub, 'id')}_${strVal(event, 'date')}_${episodeNumber}`, subscribeId: numVal(sub, 'id'),
            title: strVal(sub, 'name'), episodeTitle: strVal(ep, 'name'),
            airDate: strVal(event, 'date'), seasonNumber: numVal(sub, 'season', 1),
            episodeNumber: episodeNumber, posterUrl: this.resolveImageUrl(strVal(sub, 'poster')),
            overview: details ? details.description : '', tmdbId: details ? strVal(asRec(parseJsonSafe(details.rawJson ?? '{}')), 'tmdbid') : ''
          });
        }
      }
      consumed += events.length;
      if (events.length === 0 || consumed >= numVal(root, 'total')) { break; }
      page++;
    }
    return out;
  }

  /** 拉取单站点真实图标（`GET /api/v1/site/icon/{id}`，支持 base64 dataURI 或远程 URL）。 */
  async fetchSiteIcon(siteId: number): Promise<string> {
    if (siteId <= 0) { return ''; }
    const cached = this.siteIconCache.get(siteId);
    if (cached !== undefined) { return cached; }
    try {
      const resp = await this.get(['site', 'icon', String(siteId)]);
      if (resp.status === 200) {
        const root = unwrapObject(parseJsonSafe(resp.body));
        const rawIcon = root ? strVal(root, 'icon') : '';
        let resolved = '';
        if (rawIcon.startsWith('data:image/')) {
          resolved = rawIcon;
        } else if (rawIcon.length > 0) {
          resolved = this.resolveImageUrl(rawIcon);
        }
        this.siteIconCache.set(siteId, resolved);
        return resolved;
      }
    } catch {
      // ignore icon fetch failure
    }
    this.siteIconCache.set(siteId, '');
    return '';
  }

  async fetchSites(): Promise<MpSiteItem[]> {
    const resps = await Promise.all([
      this.get(['site'], {}, true),
      this.get(['site', 'userdata', 'latest'])
    ]);
    const sitesArr = unwrapArray(parseJsonSafe(resps[0].body));
    const dataArr = unwrapArray(parseJsonSafe(resps[1].body));
    const dataByDomain: Map<string, Record<string, Object>> = new Map<string, Record<string, Object>>();
    for (let i = 0; i < dataArr.length; i++) {
      const u = asRec(dataArr[i]);
      if (u) {
        const dom = strVal(u, 'domain').toLowerCase();
        if (dom.length > 0) { dataByDomain.set(dom, u); }
      }
    }
    const out: MpSiteItem[] = [];
    for (let i = 0; i < sitesArr.length; i++) {
      const r = asRec(sitesArr[i]);
      if (!r) { continue; }
      const sid = numVal(r, 'id');
      const domain = strVal(r, 'domain');
      const ud = dataByDomain.get(domain.toLowerCase()) ?? null;
      out.push({
        id: sid,
        name: strVal(r, 'name'),
        domain: domain,
        url: strVal(r, 'url'),
        isActive: boolVal(r, 'is_active', true),
        uploadBytes: numVal(ud, 'upload', 0),
        downloadBytes: numVal(ud, 'download', 0),
        ratio: numVal(ud, 'ratio', 0),
        seeding: numVal(ud, 'seeding', 0),
        seedingSizeBytes: numVal(ud, 'seeding_size', 0),
        bonus: numVal(ud, 'bonus', 0),
        iconDataUri: this.siteIconCache.get(sid) ?? '',
        priority: numVal(r, 'pri', i + 1),
        rss: strVal(r, 'rss'),
        cookie: strVal(r, 'cookie'),
        ua: strVal(r, 'ua'),
        proxy: boolVal(r, 'proxy', false),
        render: boolVal(r, 'render', false),
        rawJson: JSON.stringify(r)
      });
    }
    // 并发预取前 24 个站点的真实图标
    const iconTargets = out.slice(0, 24);
    await Promise.all(iconTargets.map(async (s: MpSiteItem) => {
      if (!s.iconDataUri && s.id > 0) {
        s.iconDataUri = await this.fetchSiteIcon(s.id);
      }
    }));
    return out;
  }

  /** 解析单条站点资源上下文（完整保留 9 维元数据供 Rust 筛选与分组引擎消费）。 */
  private parseResourceRecord(r: Record<string, Object>): MpResourceItem {
    const ti = asRec(r['torrent_info']) ?? r;
    const mi = asRec(r['meta_info']);
    const rawLabels = asArr(ti['labels']);
    const labels: string[] = [];
    for (let k = 0; k < rawLabels.length; k++) {
      const lbl = String(rawLabels[k] ?? '').trim();
      if (lbl.length > 0 && lbl !== 'null') {
        labels.push(lbl);
      }
    }
    return {
      title: strVal(ti, 'title') || strVal(r, 'title'),
      description: strVal(ti, 'description'),
      siteName: strVal(ti, 'site_name', '未知站点'),
      sizeBytes: Math.round(numVal(ti, 'size', 0)),
      seeders: Math.round(numVal(ti, 'seeders', 0)),
      peers: Math.round(numVal(ti, 'peers', 0)),
      resolution: strVal(mi, 'resource_pix') || strVal(ti, 'resource_pix'),
      resourceType: strVal(mi, 'resource_type') || strVal(ti, 'resource_type'),
      videoEncode: strVal(mi, 'video_encode') || strVal(ti, 'video_encode'),
      volumeFactor: strVal(ti, 'volume_factor'),
      enclosure: strVal(ti, 'enclosure'),
      pageUrl: strVal(ti, 'page_url'),
      siteId: Math.round(numVal(ti, 'site', 0)),
      pubdate: strVal(ti, 'pubdate'),
      edition: strVal(mi, 'edition') || strVal(ti, 'edition'),
      audioEncode: strVal(mi, 'audio_encode') || strVal(ti, 'audio_encode'),
      resourceTeam: strVal(mi, 'resource_team') || strVal(ti, 'resource_team'),
      seasonEpisode: strVal(mi, 'season_episode'),
      labels: labels,
      downloadVolumeFactor: numVal(ti, 'downloadvolumefactor', -1),
      uploadVolumeFactor: numVal(ti, 'uploadvolumefactor', -1),
      rawJson: JSON.stringify(r)
    };
  }

  async fetchCachedResources(): Promise<MpResourceItem[]> {
    const resp = await this.get(['search', 'last']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpResourceItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push(this.parseResourceRecord(r));
    }
    return out;
  }

  async fetchDownloads(): Promise<MpDownloadTask[]> {
    const resp = await this.get(['download'], {}, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpDownloadTask[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        hash: strVal(r, 'hash'),
        title: strVal(r, 'title') || strVal(r, 'name'),
        name: strVal(r, 'name'),
        state: strVal(r, 'state', 'downloading'),
        progress: numVal(r, 'progress', 0),
        sizeBytes: Math.round(numVal(r, 'size', 0)),
        dlspeed: strVal(r, 'dlspeed', '0 B/s'),
        upspeed: strVal(r, 'upspeed', '0 B/s'),
        leftTime: strVal(r, 'left_time'),
        downloader: strVal(r, 'downloader')
      });
    }
    return out;
  }

  /** 浏览指定存储目录（使用 `JSON.stringify` 安全序列化特殊字符与引号路径）。 */
  async fetchStorageFiles(storage: string = 'local', path: string = '/'): Promise<MpStorageFile[]> {
    const reqObj: Record<string, string> = {};
    reqObj['storage'] = storage;
    reqObj['type'] = 'dir';
    reqObj['path'] = path;
    reqObj['name'] = '';
    const payload = JSON.stringify(reqObj);
    const resp = await this.postJson(['storage', 'list'], payload);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpStorageFile[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        name: strVal(r, 'name'),
        path: strVal(r, 'path'),
        type: strVal(r, 'type', 'file'),
        sizeBytes: Math.round(numVal(r, 'size', 0)),
        modifyTime: numVal(r, 'modify_time', 0),
        extension: strVal(r, 'extension'),
        storage: strVal(r, 'storage', storage)
      });
    }
    return out;
  }

  async fetchTransferHistory(page: number = 1, count: number = 30): Promise<MpTransferHistoryItem[]> {
    const q: Record<string, string> = {};
    q['page'] = String(page);
    q['count'] = String(count);
    const resp = await this.get(['history', 'transfer'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpTransferHistoryItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: numVal(r, 'id'),
        title: strVal(r, 'title'),
        year: strVal(r, 'year'),
        type: strVal(r, 'type', '电影'),
        seasons: strVal(r, 'seasons'),
        episodes: strVal(r, 'episodes'),
        src: strVal(r, 'src'),
        srcStorage: strVal(r, 'src_storage', 'local'),
        dest: strVal(r, 'dest'),
        destStorage: strVal(r, 'dest_storage', 'local'),
        mode: strVal(r, 'mode', 'link'),
        status: boolVal(r, 'status', true),
        date: strVal(r, 'date'),
        posterUrl: this.resolveImageUrl(strVal(r, 'image')),
        rawJson: JSON.stringify(r)
      });
    }
    return out;
  }

  /** 整理历史 4 模式删除（`DELETE /api/v1/history/transfer?deletesrc=...&deletedest=...`）。 */
  async deleteTransferHistory(item: MpTransferHistoryItem, deleteSrc: boolean, deleteDest: boolean): Promise<boolean> {
    const q: Record<string, string> = {};
    q['deletesrc'] = deleteSrc ? 'true' : 'false';
    q['deletedest'] = deleteDest ? 'true' : 'false';
    let body = item.rawJson ?? '';
    if (body.length < 2) {
      const fallbackObj: Record<string, Object> = {};
      fallbackObj['id'] = item.id;
      fallbackObj['title'] = item.title;
      fallbackObj['type'] = item.type;
      fallbackObj['src'] = item.src;
      fallbackObj['src_storage'] = item.srcStorage;
      fallbackObj['dest'] = item.dest;
      fallbackObj['dest_storage'] = item.destStorage;
      fallbackObj['mode'] = item.mode;
      body = JSON.stringify(fallbackObj);
    }
    const resp = await this.deleteReq(['history', 'transfer'], q, false, body);
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchWorkflows(): Promise<MpWorkflowItem[]> {
    const resp = await this.get(['workflow'], {}, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpWorkflowItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const rawActions = asArr(r['actions']);
      const parsedActions: MpWorkflowActionNode[] = [];
      for (let a = 0; a < rawActions.length; a++) {
        const ar = asRec(rawActions[a]);
        if (!ar) { continue; }
        const dataRec = asRec(ar['data']);
        const posRec = asRec(ar['position']);
        parsedActions.push({
          id: strVal(ar, 'id', `n_${a}`),
          name: (dataRec ? strVal(dataRec, 'label') || strVal(dataRec, 'name') : '') || strVal(ar, 'name', `节点 ${a + 1}`),
          type: strVal(ar, 'type') || (dataRec ? strVal(dataRec, 'action') : 'Action'),
          posX: posRec ? numVal(posRec, 'x', 16 + (a % 2) * 162) : (16 + (a % 2) * 162),
          posY: posRec ? numVal(posRec, 'y', 24 + Math.floor(a / 2) * 74) : (24 + Math.floor(a / 2) * 74)
        });
      }
      const rawFlows = asArr(r['flows']);
      const parsedFlows: MpWorkflowFlowEdge[] = [];
      for (let f = 0; f < rawFlows.length; f++) {
        const fr = asRec(rawFlows[f]);
        if (!fr) { continue; }
        const srcId = strVal(fr, 'source');
        const dstId = strVal(fr, 'target');
        if (srcId.length > 0 && dstId.length > 0) {
          parsedFlows.push({
            id: strVal(fr, 'id', `e_${f}`),
            source: srcId,
            target: dstId
          });
        }
      }
      out.push({
        id: numVal(r, 'id'),
        name: strVal(r, 'name'),
        description: strVal(r, 'description'),
        timer: strVal(r, 'timer'),
        state: strVal(r, 'state', 'W'),
        runCount: numVal(r, 'run_count', 0),
        actionCount: rawActions.length,
        actions: parsedActions,
        flows: parsedFlows,
        rawJson: JSON.stringify(r)
      });
    }
    return out;
  }

  /** 手动立即执行工作流（`POST /api/v1/workflow/{id}/run`）。 */
  async runWorkflow(workflowId: number): Promise<boolean> {
    const resp = await this.postJson(['workflow', String(workflowId), 'run'], '{}');
    return resp.status >= 200 && resp.status < 300;
  }

  /** 启用工作流（`POST /api/v1/workflow/{id}/start`）。 */
  async startWorkflow(workflowId: number): Promise<boolean> {
    const resp = await this.postJson(['workflow', String(workflowId), 'start'], '{}');
    return resp.status >= 200 && resp.status < 300;
  }

  /** 暂停工作流（`POST /api/v1/workflow/{id}/pause`）。 */
  async pauseWorkflow(workflowId: number): Promise<boolean> {
    const resp = await this.postJson(['workflow', String(workflowId), 'pause'], '{}');
    return resp.status >= 200 && resp.status < 300;
  }

  /** 删除工作流（`DELETE /api/v1/workflow/{id}`）。 */
  async deleteWorkflow(workflowId: number): Promise<boolean> {
    const resp = await this.deleteReq(['workflow', String(workflowId)]);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 获取社区分享工作流列表（`GET /api/v1/workflow/shares`）。 */
  async fetchWorkflowShares(): Promise<MpWorkflowShareItem[]> {
    const q: Record<string, string> = {};
    q['page'] = '1';
    q['count'] = '30';
    const resp = await this.get(['workflow', 'shares'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpWorkflowShareItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: numVal(r, 'id', i),
        name: strVal(r, 'name'),
        shareTitle: strVal(r, 'share_title') || strVal(r, 'name', '社区工作流'),
        shareComment: strVal(r, 'share_comment') || strVal(r, 'description'),
        shareUser: strVal(r, 'share_user', '社区成员'),
        count: numVal(r, 'count', 0),
        rawJson: JSON.stringify(r)
      });
    }
    return out;
  }

  /** 复用社区分享工作流（`POST /api/v1/workflow/fork`）。 */
  async forkWorkflow(share: MpWorkflowShareItem): Promise<boolean> {
    const payload = share.rawJson.length > 2 ? share.rawJson : JSON.stringify({ id: share.id, name: share.name });
    const resp = await this.postJson(['workflow', 'fork'], payload);
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchPlugins(state: string = 'installed'): Promise<MpPluginItem[]> {
    const q: Record<string, string> = {};
    q['state'] = state;
    const remotesPromise: Promise<Set<string>> = state === 'installed'
      ? this.get(['plugin', 'remotes'], { 'token': 'moviepilot' })
        .then((remResp) => {
          const ids = new Set<string>();
          if (remResp.status === 200) {
            const remArr = unwrapArray(parseJsonSafe(remResp.body));
            for (let j = 0; j < remArr.length; j++) {
              const remRec = asRec(remArr[j]);
              if (!remRec) { continue; }
              const rid = strVal(remRec, 'id').toLowerCase();
              const rsrc = strVal(remRec, 'source_plugin_id').toLowerCase();
              if (rid.length > 0) { ids.add(rid); }
              if (rsrc.length > 0) { ids.add(rsrc); }
            }
          }
          return ids;
        })
        .catch(() => new Set<string>())
      : Promise.resolve(new Set<string>());
    const statsPromise: Promise<Map<string, number>> = state === 'market'
      ? this.get(['plugin', 'statistic'])
        .then((stResp) => {
          const counts = new Map<string, number>();
          if (stResp.status === 200) {
            const stObj = unwrapObject(parseJsonSafe(stResp.body));
            if (stObj) {
              const keys = Object.keys(stObj);
              for (let j = 0; j < keys.length; j++) {
                const k = keys[j];
                const cnt = numVal(stObj, k, 0);
                if (cnt > 0) { counts.set(k.toLowerCase(), Math.round(cnt)); }
              }
            }
          }
          return counts;
        })
        .catch(() => new Map<string, number>())
      : Promise.resolve(new Map<string, number>());
    const ratingsPromise: Promise<Map<string, number>> = state === 'market'
      ? this.get(['plugin', 'rating'])
        .then((rtResp) => {
          const avgMap = new Map<string, number>();
          if (rtResp.status === 200) {
            const rtObj = unwrapObject(parseJsonSafe(rtResp.body));
            if (rtObj) {
              const keys = Object.keys(rtObj);
              for (let j = 0; j < keys.length; j++) {
                const k = keys[j];
                const entry = asRec(rtObj[k]);
                if (entry) {
                  const avg = numVal(entry, 'average_rating', 0);
                  if (avg > 0) { avgMap.set(k.toLowerCase(), avg); }
                }
              }
            }
          }
          return avgMap;
        })
        .catch(() => new Map<string, number>())
      : Promise.resolve(new Map<string, number>());

    const resp = await this.get(['plugin'], q, true);
    const remoteVueIds = await remotesPromise;
    const statsMap = await statsPromise;
    const ratingsMap = await ratingsPromise;
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpPluginItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const pid = strVal(r, 'id');
      if (!pid) { continue; }
      const lowerId = pid.toLowerCase();
      const srcId = strVal(r, 'source_plugin_id').toLowerCase();
      const rawMode = strVal(r, 'render_mode', 'vuetify');
      const resolvedMode = (rawMode.toLowerCase() === 'vue'
        || remoteVueIds.has(lowerId)
        || (srcId.length > 0 && remoteVueIds.has(srcId)))
        ? 'vue'
        : rawMode;
      const rawInstalls = Math.round(numVal(r, 'install_count', 0));
      const statInstalls = Math.max(statsMap.get(lowerId) ?? 0, srcId.length > 0 ? (statsMap.get(srcId) ?? 0) : 0);
      const rawRating = numVal(r, 'average_rating', 0);
      const mergedRating = rawRating > 0 ? rawRating : (ratingsMap.get(lowerId) ?? (srcId.length > 0 ? (ratingsMap.get(srcId) ?? 0) : 0));
      out.push({
        id: pid,
        pluginName: strVal(r, 'plugin_name') || pid,
        pluginDesc: strVal(r, 'plugin_desc'),
        pluginVersion: strVal(r, 'plugin_version'),
        pluginAuthor: strVal(r, 'plugin_author'),
        installed: boolVal(r, 'installed', state === 'installed'),
        state: boolVal(r, 'state', false),
        hasPage: boolVal(r, 'has_page', false),
        iconUrl: this.resolvePluginIconUrl(strVal(r, 'plugin_icon')),
        renderMode: resolvedMode,
        repoUrl: strVal(r, 'repo_url'),
        hasUpdate: boolVal(r, 'has_update', false),
        installCount: Math.max(rawInstalls, statInstalls),
        addTime: Math.round(numVal(r, 'add_time', 0)),
        averageRating: mergedRating,
        pluginLabel: strVal(r, 'plugin_label')
      });
    }
    return out;
  }

  /** 从插件市场安装或更新/重装插件（`GET /api/v1/plugin/install/{pluginId}`）。 */
  async installPlugin(pluginId: string, repoUrl: string = '', force: boolean = false): Promise<boolean> {
    const q: Record<string, string> = {};
    if (repoUrl.length > 0) { q['repo_url'] = repoUrl; }
    q['force'] = force ? 'true' : 'false';
    const resp = await this.get(['plugin', 'install', pluginId], q);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 卸载已安装插件（`DELETE /api/v1/plugin/{pluginId}`）。 */
  async uninstallPlugin(pluginId: string): Promise<boolean> {
    const resp = await this.deleteReq(['plugin', pluginId]);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 重置插件配置与状态（`GET /api/v1/plugin/reset/{pluginId}`）。 */
  async resetPlugin(pluginId: string): Promise<boolean> {
    const resp = await this.get(['plugin', 'reset', pluginId]);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 重新加载插件运行时（`POST /api/v1/plugin/reload/{pluginId}`）。 */
  async reloadPlugin(pluginId: string): Promise<MpOperationOutcome> {
    const resp = await this.postJson(['plugin', 'reload', pluginId], '{}');
    const rec = asRec(parseJsonSafe(resp.body));
    const ok = rec && rec['success'] !== undefined
      ? boolVal(rec, 'success', false)
      : (resp.status >= 200 && resp.status < 300);
    const msg = strVal(rec, 'message') || (ok ? '插件已重新加载' : '重新加载插件失败，请查看插件日志');
    return { ok: ok, message: msg };
  }

  /** 读取有限插件日志快照；正数 length 会开启持续 SSE，使用 -1 后在本地截取最新行。 */
  async fetchPluginLogs(pluginId: string, length: number = 200): Promise<string[]> {
    const cleanId = (pluginId ?? '').trim().toLowerCase();
    if (!cleanId || cleanId.includes('..') || cleanId.includes('/')) {
      return [];
    }
    const q: Record<string, string> = {};
    q['length'] = '-1';
    q['logfile'] = `plugins/${cleanId}.log`;
    const resp = await this.get(['system', 'logging'], q);
    if (resp.status < 200 || resp.status >= 300) {
      return [];
    }
    const raw = (resp.body ?? '').trim();
    if (!raw) {
      return [];
    }
    let textContent = raw;
    const parsed = parseJsonSafe(raw);
    if (typeof parsed === 'string') {
      textContent = parsed;
    } else {
      const rec = asRec(parsed);
      if (rec && typeof rec['data'] === 'string') {
        textContent = rec['data'] as string;
      }
    }
    return textContent
      .split(/\r?\n/)
      .map((ln: string) => ln.trimEnd())
      .filter((ln: string) => ln.trim().length > 0)
      .slice(0, Math.max(20, Math.min(500, Math.trunc(length))));
  }

  /** 拉取插件动态注册的推荐榜单来源列表（`GET /api/v1/recommend/source`）。 */
  async fetchRecommendSources(): Promise<MpRecommendSource[]> {
    const resp = await this.get(['recommend', 'source']);
    if (resp.status < 200 || resp.status >= 300) {
      return [];
    }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const seen = new Set<string>();
    const out: MpRecommendSource[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const name = strVal(r, 'name').trim();
      const safePath = this.sanitizeRelativeRecommendApiPath(strVal(r, 'api_path'));
      if (!name || !safePath || seen.has(safePath)) { continue; }
      seen.add(safePath);
      out.push({
        name: name,
        apiPath: safePath,
        type: strVal(r, 'type').trim()
      });
    }
    return out;
  }

  /** 按受控相对 `api_path` 拉取插件推荐榜单媒体条目（严禁外部 URL 与 `..` 路径穿越）。 */
  async fetchRecommendByApiPath(apiPath: string, page: number = 1): Promise<MpMediaItem[]> {
    const safe = this.sanitizeRelativeRecommendApiPath(apiPath);
    if (!safe) { return []; }
    const qIdx = safe.indexOf('?');
    const pathPart = qIdx >= 0 ? safe.substring(0, qIdx) : safe;
    const queryPart = qIdx >= 0 ? safe.substring(qIdx + 1) : '';
    const segments: string[] = [];
    const rawSegs = pathPart.split('/');
    for (let i = 0; i < rawSegs.length; i++) {
      if (!rawSegs[i]) { continue; }
      let dec = rawSegs[i];
      try { dec = decodeURIComponent(rawSegs[i]); } catch { /* keep raw */ }
      if (!dec || dec === '.' || dec === '..' || dec.includes('/') || dec.includes('\\')) {
        return [];
      }
      segments.push(dec);
    }
    if (segments.length === 0) { return []; }
    const pairs: string[][] = [];
    if (queryPart.length > 0) {
      const rawPairs = queryPart.split('&');
      for (let i = 0; i < rawPairs.length; i++) {
        const kv = rawPairs[i];
        if (!kv) { continue; }
        const eqIdx = kv.indexOf('=');
        const kRaw = eqIdx >= 0 ? kv.substring(0, eqIdx) : kv;
        const vRaw = eqIdx >= 0 ? kv.substring(eqIdx + 1) : '';
        let k = kRaw;
        let v = vRaw;
        try { k = decodeURIComponent(kRaw); } catch { /* keep */ }
        try { v = decodeURIComponent(vRaw); } catch { /* keep */ }
        if (k.length > 0 && (page <= 1 || k !== 'page')) {
          pairs.push([k, v]);
        }
      }
    }
    if (page > 1) {
      pairs.push(['page', String(Math.trunc(page))]);
    }
    const resp = await this.getMultiQuery(segments, pairs);
    if (resp.status < 200 || resp.status >= 300) {
      return [];
    }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const lowerPath = pathPart.toLowerCase();
    const fallbackSrc = lowerPath.includes('douban')
      ? 'douban'
      : (lowerPath.includes('bangumi') ? 'bangumi' : (lowerPath.includes('imdb') ? 'imdb' : 'themoviedb'));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], fallbackSrc);
      if (it) { out.push(it); }
    }
    return out;
  }

  /** 从海报卡片快捷订阅影视/音乐条目（`POST /api/v1/subscribe/`）。 */
  async quickSubscribeMedia(item: MpMediaItem): Promise<MpOperationOutcome> {
    const ident = this.resolveCanonicalMediaIdentity(item);
    const mtype = normalizeMediaTypeForV3(item.type);
    const payload: Record<string, Object> = {};
    payload['name'] = item.title;
    payload['type'] = mtype;
    if (item.year.trim().length > 0) {
      payload['year'] = item.year.trim();
    }
    if (ident.mediaSource.length > 0 && ident.rawMediaId.length > 0) {
      payload['media_source'] = ident.mediaSource;
      payload['media_id'] = ident.rawMediaId;
      if (ident.mediaSource === 'themoviedb') {
        const numId = Number(ident.rawMediaId);
        if (Number.isFinite(numId) && numId > 0) {
          payload['tmdbid'] = Math.trunc(numId);
        }
      } else if (ident.mediaSource === 'douban' || ident.mediaSource === 'doubanmusic') {
        payload['doubanid'] = ident.rawMediaId;
      }
    }
    if (mtype === '电视剧') {
      payload['season'] = 1;
    }
    const resp = await this.postJson(['subscribe'], JSON.stringify(payload), true);
    const rec = asRec(parseJsonSafe(resp.body));
    const ok = rec && rec['success'] !== undefined
      ? boolVal(rec, 'success', false)
      : (resp.status >= 200 && resp.status < 300);
    if (ok) {
      this.cachedSubscriptions = null;
    }
    const msg = strVal(rec, 'message') || (ok ? `已添加订阅「${item.title}」` : `添加订阅失败（HTTP ${resp.status}）`);
    return { ok: ok, message: msg };
  }

  private sanitizeRelativeRecommendApiPath(raw: string): string {
    const trimmed = (raw ?? '').trim();
    if (!trimmed || trimmed.length > 4096) { return ''; }
    if (trimmed.includes('://') || trimmed.startsWith('//') || trimmed.includes('\\') || trimmed.includes('#')) {
      return '';
    }
    const qIdx = trimmed.indexOf('?');
    let pathPart = (qIdx >= 0 ? trimmed.substring(0, qIdx) : trimmed).replace(/^\/+/, '');
    if (pathPart.startsWith('api/v1/')) {
      pathPart = pathPart.substring('api/v1/'.length);
    }
    const queryPart = qIdx >= 0 ? trimmed.substring(qIdx + 1) : '';
    if (!pathPart || pathPart.includes('//')) { return ''; }
    const segs = pathPart.split('/').filter((s: string) => s.length > 0);
    if (segs.length === 0) { return ''; }
    for (let i = 0; i < segs.length; i++) {
      let dec = segs[i];
      try { dec = decodeURIComponent(segs[i]); } catch { /* keep */ }
      if (dec === '.' || dec === '..' || dec.includes('/') || dec.includes('\\')) {
        return '';
      }
    }
    return queryPart.length > 0 ? `${segs.join('/')}?${queryPart}` : segs.join('/');
  }

  async fetchPluginFormJson(pluginId: string): Promise<string> {
    const resp = await this.get(['plugin', 'form', pluginId]);
    return resp.status === 200 ? resp.body : '{}';
  }

  async fetchPluginPageJson(pluginId: string): Promise<string> {
    const resp = await this.get(['plugin', 'page', pluginId]);
    return resp.status === 200 ? resp.body : '{}';
  }

  async savePluginFormModel(pluginId: string, fullModelJson: string): Promise<boolean> {
    const resp = await this.putJson(['plugin', pluginId], fullModelJson);
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchMediaServerLibraries(): Promise<MpMediaServerLibrary[]> {
    const res = await Promise.all([
      this.fetchMediaServerClients(),
      this.fetchMediaServers()
    ]);
    const servers = res[0];
    const cfgs = res[1];
    const typeByName: Map<string, string> = new Map<string, string>();
    for (let c = 0; c < cfgs.length; c++) {
      typeByName.set(cfgs[c].name, cfgs[c].type);
    }
    const out: MpMediaServerLibrary[] = [];
    for (let s = 0; s < servers.length; s++) {
      const q: Record<string, string> = {};
      q['server'] = servers[s];
      const resp = await this.get(['mediaserver', 'library'], q);
      if (resp.status !== 200) { continue; }
      const arr = unwrapArray(parseJsonSafe(resp.body));
      for (let i = 0; i < arr.length; i++) {
        const r = asRec(arr[i]);
        if (!r) { continue; }
        const useCookies = boolVal(r, 'use_cookies', false);
        const imgList = asArr(r['image_list']);
        const firstImg = imgList.length > 0 ? String(imgList[0] ?? '') : '';
        const rawImg = strVal(r, 'image') || firstImg || strVal(r, 'poster') || strVal(r, 'thumb');
        const rawCount = r['item_count'] ?? r['count'] ?? r['total'];
        const parsedCount = rawCount !== undefined && rawCount !== null ? Number(rawCount) : -1;
        out.push({
          id: strVal(r, 'item_id') || strVal(r, 'id', String(i)),
          name: strVal(r, 'name', '媒体库'),
          type: strVal(r, 'type', 'movie'),
          serverName: servers[s],
          serverType: typeByName.get(servers[s]) ?? servers[s],
          imageUrl: this.resolveImageUrl(rawImg, useCookies),
          itemCount: Number.isFinite(parsedCount) && parsedCount >= 0 ? Math.round(parsedCount) : undefined
        });
      }
    }
    return out;
  }

  /** 浏览媒体服务器条目（严格采用 V3 `start_index` 与 `limit` 分页参数，保留 `serverItemId` 与 `serverName`）。 */
  async browseMediaServerLibrary(serverName: string, libraryId: string, startIndex: number = 0, limit: number = 36): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    if (serverName.length > 0) { q['server'] = serverName; }
    if (libraryId.length > 0) { q['library_id'] = libraryId; }
    q['start_index'] = String(Math.max(0, startIndex));
    q['limit'] = String(Math.max(1, limit));
    const resp = await this.get(['mediaserver', 'browse'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], 'mediaserver');
      if (it) {
        it.inLibrary = true;
        if (!it.serverName) { it.serverName = serverName; }
        if (!it.serverItemId && it.id.length > 0) { it.serverItemId = it.id; }
        out.push(it);
      }
    }
    return out;
  }

  async fetchMediaServerBrowse(serverName: string, libraryId: string): Promise<MpMediaItem[]> {
    return this.browseMediaServerLibrary(serverName, libraryId, 0, 36);
  }

  async fetchMediaServerItems(serverName: string, libraryId: string, page: number = 1): Promise<MpMediaItem[]> {
    return this.fetchMediaServerBrowseFiltered(serverName, libraryId, '', 'DateCreated', '', page);
  }

  async fetchSubscribePopular(mediaType: string = '电影'): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    q['stype'] = mediaType;
    q['page'] = '1';
    q['count'] = '30';
    const resp = await this.get(['subscribe', 'popular'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], 'subscribe_popular');
      if (it) { out.push(it); }
    }
    return out;
  }

  async fetchSubscribeShares(): Promise<MpSubscribeShareItem[]> {
    const q: Record<string, string> = {};
    q['page'] = '1';
    q['count'] = '30';
    const resp = await this.get(['subscribe', 'shares'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpSubscribeShareItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const tmdbId = strVal(r, 'tmdbid') || strVal(r, 'tmdb_id');
      const doubanId = strVal(r, 'doubanid') || strVal(r, 'douban_id');
      out.push({
        id: numVal(r, 'id', i),
        name: strVal(r, 'name'),
        shareTitle: strVal(r, 'share_title') || strVal(r, 'name'),
        shareComment: strVal(r, 'share_comment') || strVal(r, 'description'),
        shareUser: strVal(r, 'share_user', '社区成员'),
        year: strVal(r, 'year'),
        type: strVal(r, 'type', '电影'),
        posterUrl: this.resolveImageUrl(strVal(r, 'poster') || strVal(r, 'backdrop')),
        count: numVal(r, 'count', 0),
        vote: numVal(r, 'vote', 0),
        tmdbId: tmdbId,
        doubanId: doubanId,
        mediaId: tmdbId ? `tmdb:${tmdbId}` : (doubanId ? `douban:${doubanId}` : ''),
        rawJson: JSON.stringify(r)
      });
    }
    return out;
  }

  /** 一键复用社区分享订阅（`POST /api/v1/subscribe/fork`）。 */
  async forkSubscribeShare(share: MpSubscribeShareItem): Promise<boolean> {
    const payload = share.rawJson && share.rawJson.length > 2
      ? share.rawJson
      : JSON.stringify({
        id: share.id,
        name: share.name,
        year: share.year,
        type: share.type,
        share_title: share.shareTitle,
        share_comment: share.shareComment,
        share_user: share.shareUser
      });
    const resp = await this.postJson(['subscribe', 'fork'], payload);
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchPersonDetail(personId: string): Promise<MpPersonDetail | null> {
    if (!personId) { return null; }
    const resp = await this.get(['tmdb', 'person', personId]);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    return {
      id: strVal(r, 'id', personId),
      name: strVal(r, 'name'),
      biography: strVal(r, 'biography'),
      birthday: strVal(r, 'birthday'),
      placeOfBirth: strVal(r, 'place_of_birth'),
      department: strVal(r, 'known_for_department'),
      profileUrl: this.resolveImageUrl(strVal(r, 'profile_path'))
    };
  }

  async fetchPersonCredits(personId: string): Promise<MpMediaItem[]> {
    if (!personId) { return []; }
    const resp = await this.get(['tmdb', 'person', 'credits', personId]);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < Math.min(arr.length, 24); i++) {
      const it = this.parseMediaItem(arr[i], 'themoviedb');
      if (it) { out.push(it); }
    }
    return out;
  }

  async fetchUsers(): Promise<MpUserItem[]> {
    const resp = await this.get(['user'], {}, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpUserItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: numVal(r, 'id'),
        name: strVal(r, 'name'),
        email: strVal(r, 'email'),
        isActive: boolVal(r, 'is_active', true),
        isSuperuser: boolVal(r, 'is_superuser', false),
        avatar: strVal(r, 'avatar')
      });
    }
    return out;
  }

  /** 拉取消息中心通知列表（严格使用 V3 `count=25` 参数）。 */
  async fetchMessages(page: number = 1, count: number = 25): Promise<MpMessageItem[]> {
    const q: Record<string, string> = {};
    q['page'] = String(page);
    q['count'] = String(count);
    const resp = await this.get(['message', 'web'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMessageItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: strVal(r, 'id', String(i)),
        title: strVal(r, 'title', strVal(r, 'role') === 'user' ? '我的消息' : '系统通知'),
        text: strVal(r, 'text') || strVal(r, 'content'),
        date: strVal(r, 'reg_time') || strVal(r, 'date'),
        action: numVal(r, 'action', 0),
        image: this.resolveImageUrl(strVal(r, 'image') || strVal(r, 'poster'))
      });
    }
    return out;
  }

  /** 在消息中心发送交互回复（`POST /api/v1/message/web`）。 */
  async sendWebMessage(text: string): Promise<boolean> {
    const clean = text.trim();
    if (!clean) { return false; }
    const q: Record<string, string> = {};
    q['text'] = clean;
    const bodyObj: Record<string, string> = {};
    bodyObj['text'] = clean;
    bodyObj['message'] = clean;
    const resp = await this.postJsonQuery(['message', 'web'], q, JSON.stringify(bodyObj));
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchSchedulers(): Promise<MpSchedulerItem[]> {
    const resp = await this.get(['dashboard', 'schedule']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpSchedulerItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: strVal(r, 'id', String(i)),
        name: strVal(r, 'name'),
        provider: strVal(r, 'provider'),
        status: strVal(r, 'status', '等待'),
        nextRun: strVal(r, 'next_run')
      });
    }
    return out;
  }

  /** 读取系统日志快照；后端已按新到旧返回，保留开头 50 行并避免等待 SSE。 */
  async fetchLiveLogs(): Promise<string[]> {
    const q: Record<string, string> = {};
    q['length'] = '-1';
    const resp = await this.get(['system', 'logging'], q);
    if (resp.status !== 200) { return []; }
    return resp.body.split(/\r?\n/).filter((line: string) => line.trim().length > 0).slice(0, 50);
  }

  async fetchSystemSettingList(key: string): Promise<MpSimpleSettingItem[]> {
    const resp = await this.get(['system', 'setting', key]);
    if (resp.status !== 200) { return []; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    const valueArr = root ? asArr(root['value']) : [];
    const out: MpSimpleSettingItem[] = [];
    for (let i = 0; i < valueArr.length; i++) {
      const r = asRec(valueArr[i]);
      if (!r) { continue; }
      const cfg = asRec(r['config']);
      out.push({
        name: strVal(r, 'name') || strVal(r, 'type') || `项 ${i + 1}`,
        type: strVal(r, 'type'),
        enabled: boolVal(r, 'enabled', true),
        detail: strVal(cfg, 'host') || strVal(r, 'download_path') || strVal(r, 'library_path') || strVal(r, 'type')
      });
    }
    return out;
  }

  /** 豆瓣正在热映与 Top250。 */
  async fetchDoubanShowing(page: number = 1): Promise<MpMediaItem[]> {
    return this.fetchRecommend('douban_showing', page);
  }

  async fetchDoubanTop250(page: number = 1): Promise<MpMediaItem[]> {
    return this.fetchRecommend('douban_movie_top250', page);
  }

  /**
   * 音乐榜单与专辑流（严格对齐 V3 真实端点与兜底路由）：
   * - `douban`：`/api/v1/recommend/music_douban`（回退 `douban_music_hot`）
   * - `weekly` / `listenbrainz`：`/api/v1/recommend/music_weekly`（回退 `listenbrainz_chart`）
   * - `hot` / `chart`：`/api/v1/music/explore?media_source=musicbrainz&mode=chart&entity=album&range_name=this_month`
   * - `new` / `fresh`：`/api/v1/music/explore?media_source=musicbrainz&mode=fresh&days=14`
   */
  async fetchMusicFeed(feed: string = 'douban', page: number = 1): Promise<MpMusicAlbum[]> {
    const q: Record<string, string> = {};
    q['page'] = String(page);
    let segs: string[] = ['recommend', 'music_douban'];
    let fallbackSegs: string[] = [];
    if (feed === 'douban') {
      fallbackSegs = ['recommend', 'douban_music_hot'];
    } else if (feed === 'weekly' || feed === 'listenbrainz') {
      segs = ['recommend', 'music_weekly'];
      fallbackSegs = ['recommend', 'listenbrainz_chart'];
    } else if (feed === 'hot' || feed === 'chart') {
      segs = ['music', 'explore'];
      q['media_source'] = 'musicbrainz';
      q['mode'] = 'chart';
      q['entity'] = 'album';
      q['range_name'] = 'this_month';
      q['count'] = '30';
    } else if (feed === 'new' || feed === 'fresh') {
      segs = ['music', 'explore'];
      q['media_source'] = 'musicbrainz';
      q['mode'] = 'fresh';
      q['days'] = '14';
      q['count'] = '30';
    }
    let resp = await this.get(segs, q);
    if (resp.status !== 200 && fallbackSegs.length > 0) {
      resp = await this.get(fallbackSegs, q);
    }
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    return this.parseMusicAlbumCards(arr, feed);
  }

  private parseMusicAlbumCards(arr: Object[], fallbackFeed: string): MpMusicAlbum[] {
    const out: MpMusicAlbum[] = [];
    const seen = new Set<string>();
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const title = strVal(r, 'title') || strVal(r, 'name');
      if (!title) { continue; }
      const artistsArr = asArr(r['artists']);
      let firstArtist = '';
      if (artistsArr.length > 0) {
        const aRec = asRec(artistsArr[0]);
        firstArtist = aRec ? strVal(aRec, 'name') : String(artistsArr[0] ?? '');
      }
      const artistIdsArr = asArr(r['artist_ids']);
      const firstArtistId = artistIdsArr.length > 0 ? String(artistIdsArr[0] ?? '').trim() : strVal(r, 'artist_id');
      const rawMediaSource = normalizeMediaSourceCode(strVal(r, 'media_source')) ||
        (fallbackFeed === 'douban' ? 'doubanmusic' : 'musicbrainz');
      const mediaId = stripKnownMediaPrefix(strVal(r, 'media_id') || strVal(r, 'douban_id') || strVal(r, 'id'));
      const albumId = stripKnownMediaPrefix(strVal(r, 'album_id')) || mediaId;
      const releaseId = strVal(r, 'musicbrainz_release_id').trim();
      const uniqueKey = `${rawMediaSource}|${albumId || mediaId || title}_${i}`;
      const dedupeKey = (albumId || mediaId).length > 0 ? `${rawMediaSource}|${albumId || mediaId}` : uniqueKey;
      if (seen.has(dedupeKey)) { continue; }
      seen.add(dedupeKey);
      out.push({
        id: albumId || mediaId || `music_${i}`,
        title: title,
        artist: strVal(r, 'artist') || firstArtist || strVal(r, 'singer') || strVal(r, 'subtitle'),
        year: strVal(r, 'year'),
        coverUrl: this.resolveImageUrl(
          strVal(r, 'cover_url') || strVal(r, 'poster_path') || strVal(r, 'cover') || strVal(r, 'image')
        ),
        rating: numVal(r, 'vote_average', numVal(r, 'rating', 0)),
        source: fallbackFeed,
        mediaSource: rawMediaSource,
        mediaId: mediaId,
        albumId: albumId,
        releaseId: releaseId,
        artistId: firstArtistId
      });
    }
    return out;
  }

  /** 查询音乐专辑详情与完整曲目列表（`GET /api/v1/music/album/{id}`）。 */
  async fetchMusicAlbumDetail(
    albumId: string,
    mediaSource: string = 'musicbrainz',
    releaseId: string = ''
  ): Promise<MpMusicAlbumDetail | null> {
    const cleanId = stripKnownMediaPrefix(albumId);
    if (!cleanId) { return null; }
    const normSrc = normalizeMediaSourceCode(mediaSource) || 'musicbrainz';
    const q: Record<string, string> = {
      'media_source': normSrc
    };
    const cleanRelease = releaseId.trim();
    if (
      normSrc === 'musicbrainz' &&
      /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(cleanRelease)
    ) {
      q['musicbrainz_release_id'] = cleanRelease;
    }
    const resp = await this.get(['music', 'album', cleanId], q);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }

    const artistsArr = asArr(r['artists']);
    let firstArtist = '';
    if (artistsArr.length > 0) {
      const aRec = asRec(artistsArr[0]);
      firstArtist = aRec ? strVal(aRec, 'name') : String(artistsArr[0] ?? '');
    }
    const artistIdsArr = asArr(r['artist_ids']);
    const firstArtistId = artistIdsArr.length > 0 ? String(artistIdsArr[0] ?? '').trim() : strVal(r, 'artist_id');
    const resolvedArtist = strVal(r, 'artist') || firstArtist;
    const resolvedTitle = strVal(r, 'title') || strVal(r, 'name', '音乐专辑');
    const resolvedCover = this.resolveImageUrl(
      strVal(r, 'cover_url') || strVal(r, 'poster_path') || strVal(r, 'cover') || strVal(r, 'image')
    );
    const resolvedSrc = normalizeMediaSourceCode(strVal(r, 'media_source')) || normSrc;
    const resolvedMediaId = stripKnownMediaPrefix(strVal(r, 'media_id')) || cleanId;

    const tracksRaw = asArr(r['tracks']);
    const tracks: MpMusicTrackItem[] = [];
    for (let i = 0; i < tracksRaw.length; i++) {
      const tr = asRec(tracksRaw[i]);
      if (!tr) { continue; }
      const trArtists = asArr(tr['artists']);
      let trFirstArtist = '';
      if (trArtists.length > 0) {
        const taRec = asRec(trArtists[0]);
        trFirstArtist = taRec ? strVal(taRec, 'name') : String(trArtists[0] ?? '');
      }
      const trMediaSrc = normalizeMediaSourceCode(strVal(tr, 'media_source')) || resolvedSrc;
      const trMediaId = stripKnownMediaPrefix(strVal(tr, 'media_id') || strVal(tr, 'id'));
      tracks.push({
        id: trMediaId || `${cleanId}_track_${i + 1}`,
        mediaSource: trMediaSrc,
        mediaId: trMediaId,
        title: strVal(tr, 'title') || strVal(tr, 'name', `曲目 ${i + 1}`),
        artist: strVal(tr, 'artist') || trFirstArtist || resolvedArtist,
        album: resolvedTitle,
        trackNumber: Math.round(numVal(tr, 'track_number', i + 1)),
        discNumber: Math.round(numVal(tr, 'disc_number', 1)),
        durationSec: Math.round(numVal(tr, 'duration', 0)),
        year: strVal(tr, 'year') || strVal(r, 'year'),
        coverUrl: this.resolveImageUrl(strVal(tr, 'cover_url') || strVal(tr, 'poster_path')) || resolvedCover
      });
    }

    return {
      id: cleanId,
      mediaId: resolvedMediaId,
      releaseId: strVal(r, 'musicbrainz_release_id', cleanRelease),
      title: resolvedTitle,
      artist: resolvedArtist,
      artistId: firstArtistId,
      albumType: strVal(r, 'album_type'),
      releaseDate: strVal(r, 'release_date') || strVal(r, 'year'),
      year: strVal(r, 'year'),
      overview: strVal(r, 'overview'),
      coverUrl: resolvedCover,
      mediaSource: resolvedSrc,
      totalTracks: Math.round(numVal(r, 'total_tracks', tracks.length)),
      tracks: tracks
    };
  }

  /** 查询音乐艺术家详情与其代表专辑列表（`GET /api/v1/music/artist/{id}` & `/albums`）。 */
  async fetchMusicArtistDetail(
    artistId: string,
    mediaSource: string = 'musicbrainz'
  ): Promise<MpMusicArtistDetail | null> {
    const cleanId = stripKnownMediaPrefix(artistId);
    if (!cleanId) { return null; }
    const normSrc = normalizeMediaSourceCode(mediaSource) || 'musicbrainz';
    const q: Record<string, string> = { 'media_source': normSrc };
    const albumsQ: Record<string, string> = { 'media_source': normSrc, 'page': '1', 'count': '30' };
    const results = await Promise.all([
      this.get(['music', 'artist', cleanId], q),
      this.get(['music', 'artist', cleanId, 'albums'], albumsQ)
    ]);
    const infoResp = results[0];
    const albumsResp = results[1];
    const infoRec = infoResp.status === 200 ? unwrapObject(parseJsonSafe(infoResp.body)) : null;
    const albumsArr = albumsResp.status === 200 ? unwrapArray(parseJsonSafe(albumsResp.body)) : [];
    if (!infoRec && albumsArr.length === 0) {
      return null;
    }
    return {
      id: cleanId,
      name: strVal(infoRec, 'name') || strVal(infoRec, 'title', '艺术家'),
      country: strVal(infoRec, 'area') || strVal(infoRec, 'country'),
      lifeSpan: strVal(infoRec, 'life_span'),
      overview: strVal(infoRec, 'overview'),
      imageUrl: this.resolveImageUrl(
        strVal(infoRec, 'image_url') || strVal(infoRec, 'poster_path') || strVal(infoRec, 'avatar')
      ),
      mediaSource: normSrc,
      albums: this.parseMusicAlbumCards(albumsArr, normSrc)
    };
  }

  /** 查询指定音乐专辑是否已订阅（`POST /api/v1/media/status`）。 */
  async checkMusicAlbumSubscribed(mediaId: string, mediaSource: string = 'musicbrainz'): Promise<boolean> {
    const cleanId = stripKnownMediaPrefix(mediaId);
    if (!cleanId) { return false; }
    const normSrc = normalizeMediaSourceCode(mediaSource) || 'musicbrainz';
    const itemObj: Record<string, string> = {
      'media_source': normSrc,
      'media_id': cleanId,
      'mtype': '音乐'
    };
    const resp = await this.postJson(['media', 'status'], JSON.stringify([itemObj]));
    if (resp.status !== 200) { return false; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    if (arr.length === 0) { return false; }
    const first = asRec(arr[0]);
    return boolVal(first, 'subscribed', false);
  }

  /** 添加音乐专辑订阅（`POST /api/v1/subscribe/`）。 */
  async subscribeMusicAlbum(album: MpMusicAlbumDetail): Promise<boolean> {
    const cleanId = stripKnownMediaPrefix(album.mediaId || album.id);
    if (!cleanId) { return false; }
    const payload: Record<string, Object> = {
      'name': album.title,
      'type': '音乐',
      'music_type': 'album',
      'media_source': normalizeMediaSourceCode(album.mediaSource) || 'musicbrainz',
      'media_id': cleanId
    };
    if (album.year.length > 0) {
      payload['year'] = album.year;
    }
    if (album.totalTracks > 0) {
      payload['total_tracks'] = album.totalTracks;
    }
    const resp = await this.postJson(['subscribe'], JSON.stringify(payload), true);
    if (resp.status >= 200 && resp.status < 300) {
      this.invalidateSubscriptionsCache();
      return true;
    }
    return false;
  }

  /** 取消音乐专辑订阅（`DELETE /api/v1/subscribe/media/{id}`）。 */
  async unsubscribeMusicAlbum(mediaId: string, mediaSource: string = 'musicbrainz'): Promise<boolean> {
    const cleanId = stripKnownMediaPrefix(mediaId);
    if (!cleanId) { return false; }
    const q: Record<string, string> = {
      'media_source': normalizeMediaSourceCode(mediaSource) || 'musicbrainz',
      'mtype': '音乐'
    };
    const resp = await this.deleteReq(['subscribe', 'media', cleanId], q);
    if (resp.status >= 200 && resp.status < 300) {
      this.invalidateSubscriptionsCache();
      return true;
    }
    return false;
  }

  /** 媒体库精细浏览（严格使用 `start_index` 与 `limit` 参数，完整保留 `serverItemId` 与 `serverName`）。 */
  async fetchMediaServerBrowseFiltered(
    serverName: string,
    libraryId: string,
    keyword: string = '',
    sortBy: string = 'DateCreated',
    genre: string = '',
    page: number = 1
  ): Promise<MpMediaItem[]> {
    const limit = 48;
    const q: Record<string, string> = {};
    if (serverName.length > 0) { q['server'] = serverName; }
    if (libraryId.length > 0) { q['library_id'] = libraryId; }
    if (keyword.trim().length > 0) { q['keyword'] = keyword.trim(); }
    if (sortBy.length > 0) { q['sort_by'] = sortBy; }
    if (genre.length > 0) { q['genre'] = genre; }
    q['start_index'] = String(Math.max(0, (page - 1) * limit));
    q['limit'] = String(limit);
    const resp = await this.get(['mediaserver', 'browse'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], 'mediaserver');
      if (it) {
        it.inLibrary = true;
        if (!it.serverName) { it.serverName = serverName; }
        if (!it.serverItemId && it.id.length > 0) { it.serverItemId = it.id; }
        out.push(it);
      }
    }
    return out;
  }

  /** 将相对路径或反代协议失配的 `/api/v1/...` 绝对地址安全对齐至当前实例根地址，并执行严格同源守卫。 */
  private resolveTrustedSameOriginUrl(rawUrl: string): string {
    const trimmed = (rawUrl ?? '').trim();
    if (!trimmed || !this.baseUrl) {
      return '';
    }
    const rebased = RustCoreBridge.rebaseInstanceApiUrl(this.baseUrl, trimmed);
    const candidate = rebased.length > 0
      ? rebased
      : ((trimmed.startsWith('http://') || trimmed.startsWith('https://'))
        ? trimmed
        : `${this.baseUrl}${trimmed.startsWith('/') ? '' : '/'}${trimmed}`);
    if (!RustCoreBridge.serverAddressContains(this.baseUrl, candidate)) {
      return '';
    }
    return candidate;
  }

  /**
   * 构造供 `AVPlayer.setMediaSource` 使用的同源鉴权请求头（`Cookie` + `Authorization`）：
   * 仅当目标地址通过 `RustCoreBridge.serverAddressContains` 同源校验时附加凭据，绝不拼接 `?token=`。
   */
  buildPlaybackHeaders(targetUrl: string): Record<string, string> {
    const headers: Record<string, string> = {};
    if (!this.baseUrl || !targetUrl || !RustCoreBridge.serverAddressContains(this.baseUrl, targetUrl)) {
      return headers;
    }
    const cookieHeader = this.transport.getCookieHeaderForUrl(targetUrl);
    if (cookieHeader.length > 0) {
      headers['Cookie'] = cookieHeader;
    }
    if (this.token.length > 0) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }
    return headers;
  }

  private inferSubtitleFormat(subtitleId: string, url: string): string {
    const probe = `${subtitleId} ${url.split('?')[0]}`.toLowerCase();
    if (probe.includes('.ass')) { return 'ass'; }
    if (probe.includes('.ssa')) { return 'ssa'; }
    if (probe.includes('.vtt')) { return 'vtt'; }
    return 'srt';
  }

  private async parseStreamManifestResponse(
    r: Record<string, Object>,
    fallbackItemId: string,
    fallbackServer: string,
    fallbackMediaSourceId: string
  ): Promise<MpVideoStreamInfo | null> {
    let rawUrl = strVal(r, 'content_url') || strVal(r, 'url') || strVal(r, 'stream_url') || strVal(r, 'direct_url');
    if (!rawUrl && this.baseUrl.length > 0) {
      const sq: Record<string, string> = {};
      const resolvedId = strVal(r, 'item_id', fallbackItemId);
      sq['itemid'] = resolvedId;
      if (fallbackServer.length > 0) { sq['server'] = fallbackServer; }
      if (fallbackMediaSourceId.length > 0) { sq['media_source_id'] = fallbackMediaSourceId; }
      rawUrl = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, ['mediaserver', 'stream'], sq);
    }
    const fullUrl = this.resolveTrustedSameOriginUrl(rawUrl);
    if (!fullUrl) {
      return null;
    }
    const rawStrm = strVal(r, 'strm_url');
    const parsedStrm = rawStrm.length > 0 ? RustCoreBridge.parseStrmContent(rawStrm) : null;
    const strmUrl = parsedStrm ? parsedStrm.url : '';
    const strmDirectEnabled = AppStorage.get<boolean>('mp_playback_strm_direct') ?? true;
    const serverDirectEnabled = AppStorage.get<boolean>('mp_playback_direct_play') ?? true;
    const sameOriginHeaders = this.buildPlaybackHeaders(fullUrl);
    const resolvedServer = strVal(r, 'server', fallbackServer);

    const candidates: PlaybackRouteCandidate[] = [];
    const routesRaw = asArr(r['playback_routes']);
    for (let i = 0; i < routesRaw.length; i++) {
      const rr = asRec(routesRaw[i]);
      if (!rr) { continue; }
      const kind = strVal(rr, 'kind').trim();
      const rawRouteUrl = strVal(rr, 'url').trim();
      if (!kind || !rawRouteUrl) { continue; }
      let resolvedRouteUrl = rawRouteUrl;
      if (kind === 'mp_proxy') {
        const trusted = this.resolveTrustedSameOriginUrl(rawRouteUrl);
        if (!trusted) { continue; }
        resolvedRouteUrl = trusted;
      }
      const routeHeaders: Record<string, string> = {};
      const hdrRec = asRec(rr['headers']);
      if (hdrRec) {
        const hKeys = Object.keys(hdrRec);
        for (let j = 0; j < hKeys.length; j++) {
          const hk = hKeys[j];
          const hv = strVal(hdrRec, hk).trim();
          if (hk.trim().length > 0 && hv.length > 0) {
            routeHeaders[hk] = hv;
          }
        }
      }
      const probeRaw = strVal(rr, 'probe_url').trim();
      candidates.push({
        kind: kind,
        url: resolvedRouteUrl,
        probe_url: probeRaw.length > 0 ? probeRaw : null,
        headers: routeHeaders,
        priority: Math.round(numVal(rr, 'priority', 100)),
        requires_same_origin_auth: boolVal(rr, 'requires_same_origin_auth', kind === 'mp_proxy')
      });
    }
    if (strmUrl.length > 0 && !candidates.some((c: PlaybackRouteCandidate) => c.kind === 'strm_direct')) {
      candidates.push({
        kind: 'strm_direct',
        url: strmUrl,
        probe_url: null,
        headers: parsedStrm ? parsedStrm.headers : {},
        priority: 10,
        requires_same_origin_auth: false
      });
    }
    if (!candidates.some((c: PlaybackRouteCandidate) => c.kind === 'mp_proxy')) {
      candidates.push({
        kind: 'mp_proxy',
        url: fullUrl,
        probe_url: null,
        headers: {},
        priority: 100,
        requires_same_origin_auth: true
      });
    }

    const plan = await HarmonyPlaybackRouteResolver.shared().resolve(
      resolvedServer,
      candidates,
      strmDirectEnabled,
      serverDirectEnabled
    );

    let activeUrl = fullUrl;
    let activeHeaders: Record<string, string> = sameOriginHeaders;
    let activeRouteKind = 'mp_proxy';
    let fallbackRoutes: PlaybackRouteCandidate[] = [];
    let proxyFallbackUrl: string | undefined = undefined;
    let proxyFallbackHeaders: Record<string, string> | undefined = undefined;

    if (plan) {
      activeUrl = plan.active.url;
      activeRouteKind = plan.active.kind;
      fallbackRoutes = plan.fallbacks;
      const isProxy = plan.active.kind === 'mp_proxy' ||
        (this.baseUrl.length > 0 && RustCoreBridge.serverAddressContains(this.baseUrl, activeUrl));
      activeHeaders = isProxy ? sameOriginHeaders : plan.active.headers;
      if (activeUrl !== fullUrl) {
        proxyFallbackUrl = fullUrl;
        proxyFallbackHeaders = sameOriginHeaders;
      }
    } else {
      const useStrmDirect = strmDirectEnabled && strmUrl.length > 0;
      activeUrl = useStrmDirect ? strmUrl : fullUrl;
      activeRouteKind = useStrmDirect ? 'strm_direct' : 'mp_proxy';
      activeHeaders = useStrmDirect ? this.buildPlaybackHeaders(strmUrl) : sameOriginHeaders;
      if (useStrmDirect && activeUrl !== fullUrl) {
        proxyFallbackUrl = fullUrl;
        proxyFallbackHeaders = sameOriginHeaders;
      }
    }

    const subtitles: MpExternalSubtitle[] = [];
    const subsRaw = asArr(r['subtitles']);
    for (let i = 0; i < subsRaw.length; i++) {
      const sr = asRec(subsRaw[i]);
      if (!sr) { continue; }
      const subUrl = this.resolveTrustedSameOriginUrl(strVal(sr, 'url'));
      if (!subUrl) { continue; }
      const subId = strVal(sr, 'subtitle_id') || strVal(sr, 'id', `ext_${i}`);
      const lang = strVal(sr, 'language');
      const lbl = strVal(sr, 'title') || strVal(sr, 'display_title') || lang || `外挂字幕 ${i + 1}`;
      subtitles.push({
        index: i,
        subtitleId: subId,
        label: lbl,
        language: lang,
        format: strVal(sr, 'format') || this.inferSubtitleFormat(subId, subUrl),
        isExternal: true,
        url: subUrl
      });
    }

    const rawLyrics = strVal(r, 'lyrics_url');
    const lyricsUrl = rawLyrics.length > 0 ? this.resolveTrustedSameOriginUrl(rawLyrics) : '';
    const artworkRaw = strVal(r, 'poster') || strVal(r, 'thumb') || strVal(r, 'artwork_url') || strVal(r, 'image');

    const rawPlaySessionId = strVal(r, 'play_session_id');
    const rawSyncMode = strVal(r, 'progress_sync_mode');
    const rawServerType = strVal(r, 'server_type');

    return {
      itemId: strVal(r, 'item_id', fallbackItemId),
      server: resolvedServer,
      serverType: rawServerType.length > 0 ? rawServerType : undefined,
      title: strVal(r, 'title'),
      contentUrl: activeUrl,
      strmUrl: strmUrl.length > 0 ? strmUrl : undefined,
      proxyFallbackUrl: proxyFallbackUrl,
      proxyFallbackHeaders: proxyFallbackHeaders,
      activeRouteKind: activeRouteKind,
      fallbackRoutes: fallbackRoutes,
      headers: activeHeaders,
      mediaType: strVal(r, 'media_type', 'video'),
      artist: strVal(r, 'artist'),
      album: strVal(r, 'album'),
      artworkUrl: artworkRaw.length > 0 ? this.resolveImageUrl(artworkRaw) : '',
      mediaSourceId: strVal(r, 'media_source_id', fallbackMediaSourceId),
      playSessionId: rawPlaySessionId.length > 0 ? rawPlaySessionId : undefined,
      progressSyncMode: rawSyncMode.length > 0 ? rawSyncMode : undefined,
      resumePositionMs: Math.max(0, Math.round(numVal(r, 'resume_position_ms', numVal(r, 'position_ms', 0)))),
      durationMs: Math.max(0, Math.round(numVal(r, 'duration_ms', 0))),
      subtitles: subtitles,
      lyricsUrl: lyricsUrl,
      danmakuEnabled: boolVal(r, 'danmaku_enabled', false),
      seriesName: strVal(r, 'series_name').trim() || undefined,
      seasonNumber: r['season_number'] !== undefined && r['season_number'] !== null ? Math.round(numVal(r, 'season_number', 0)) : undefined,
      episodeNumber: r['episode_number'] !== undefined && r['episode_number'] !== null ? Math.round(numVal(r, 'episode_number', 0)) : undefined,
      year: r['year'] !== undefined && r['year'] !== null ? Math.round(numVal(r, 'year', 0)) : undefined,
      tmdbId: strVal(r, 'tmdb_id').trim() || undefined,
      fileName: strVal(r, 'file_name').trim() || undefined,
      fileSize: r['file_size'] !== undefined && r['file_size'] !== null ? Math.max(0, Math.round(numVal(r, 'file_size', 0))) : undefined
    };
  }

  /**
   * 查询媒体播放流地址与外挂字幕（`GET /api/v1/mediaserver/stream-info`）：
   * - 捕获响应 `Set-Cookie` 中的 `resource_token`，不向 `contentUrl` 拼接 `?token=`；
   * - 对 `content_url`、`subtitles[].url` 与 `lyrics_url` 全部执行 `RustCoreBridge.serverAddressContains` 同源校验。
   */
  async fetchVideoStreamInfo(itemId: string, server: string = '', mediaSourceId: string = ''): Promise<MpVideoStreamInfo | null> {
    const cleanId = itemId.trim();
    if (!cleanId) { return null; }
    const q: Record<string, string> = {};
    q['itemid'] = cleanId;
    if (server.trim().length > 0) { q['server'] = server.trim(); }
    if (mediaSourceId.trim().length > 0) { q['media_source_id'] = mediaSourceId.trim(); }
    const clientHeaders = await HarmonyPlaybackProgressReporter.shared().getClientHeaders();
    const resp = await this.get(['mediaserver', 'stream-info'], q, false, clientHeaders);
    if (resp.status !== 200) { return null; }
    HarmonyPlaybackProgressReporter.shared().flushPendingStops(this);
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    return await this.parseStreamManifestResponse(r, cleanId, server.trim(), mediaSourceId.trim());
  }

  /**
   * 匹配并获取媒体服务器中的音乐单曲音频流与 LRC 歌词（`POST /api/v1/mediaserver/stream-info/music`）。
   */
  async fetchMusicStreamInfo(
    title: string,
    artist: string = '',
    album: string = '',
    mediaSource: string = '',
    mediaId: string = '',
    trackNumber: number = 0
  ): Promise<MpVideoStreamInfo | null> {
    const cleanTitle = title.trim();
    if (!cleanTitle) { return null; }
    const normSrc = normalizeMediaSourceCode(mediaSource) || 'musicbrainz';
    const cleanMediaId = stripKnownMediaPrefix(mediaId) || cleanTitle;
    const payload: Record<string, Object> = {
      'title': cleanTitle,
      'media_source': normSrc,
      'media_id': cleanMediaId
    };
    if (artist.trim().length > 0) {
      payload['artist'] = artist.trim();
      payload['artists'] = [artist.trim()];
    }
    if (album.trim().length > 0) {
      payload['album'] = album.trim();
    }
    if (trackNumber > 0) {
      payload['track_number'] = Math.round(trackNumber);
    }
    const clientHeaders = await HarmonyPlaybackProgressReporter.shared().getClientHeaders();
    let resp = await this.postJson(['mediaserver', 'stream-info', 'music'], JSON.stringify(payload), false, clientHeaders);
    if (resp.status === 422) {
      const legacyPayload: Record<string, string> = { 'title': cleanTitle };
      if (artist.trim().length > 0) { legacyPayload['artist'] = artist.trim(); }
      if (album.trim().length > 0) { legacyPayload['album'] = album.trim(); }
      resp = await this.postJson(['mediaserver', 'stream-info', 'music'], JSON.stringify(legacyPayload), false, clientHeaders);
    }
    if (resp.status !== 200) { return null; }
    HarmonyPlaybackProgressReporter.shared().flushPendingStops(this);
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    const parsed = await this.parseStreamManifestResponse(r, '', '', '');
    if (parsed) {
      parsed.mediaType = 'audio';
      if (!parsed.title) { parsed.title = cleanTitle; }
      if (!parsed.artist) { parsed.artist = artist.trim(); }
      if (!parsed.album) { parsed.album = album.trim(); }
    }
    return parsed;
  }

  /**
   * 异步回传当前播放进度、会话生命周期及轨道上下文至媒体服务器（`POST /api/v1/mediaserver/progress`）。
   * 自动跳过无 `server` 的外部直链、本机文件及 `file.` 短期流票据。
   */
  async reportMediaServerProgress(
    itemId: string,
    server: string,
    mediaSourceId: string,
    positionMs: number,
    durationMs: number,
    isPaused: boolean,
    state: string,
    options?: MpProgressReportOptions,
    requestBase: string = this.baseUrl,
    requestToken: string = this.token
  ): Promise<boolean> {
    // 串行队列等待期间若已切换会话，只保留原桶记录，不用新会话发起旧上报。
    if (requestBase !== this.baseUrl || requestToken !== this.token) { return false; }
    const cleanItem = itemId.trim();
    const cleanSrv = server.trim();
    if (
      !cleanItem ||
      !cleanSrv ||
      cleanItem.startsWith('file.') ||
      cleanItem.startsWith('file:') ||
      cleanItem.startsWith('local:') ||
      cleanItem.startsWith('external:')
    ) {
      return false;
    }
    const validState = state === 'started' || state === 'paused' || state === 'stopped' ? state : 'playing';
    const payload: Record<string, Object> = {
      'item_id': cleanItem,
      'server': cleanSrv,
      'position_ms': Math.max(0, Math.round(positionMs)),
      'is_paused': isPaused,
      'state': validState,
      'play_method': options?.playMethod ?? 'DirectPlay'
    };
    if (mediaSourceId.trim().length > 0) {
      payload['media_source_id'] = mediaSourceId.trim();
    }
    if (durationMs > 0) {
      payload['duration_ms'] = Math.round(durationMs);
    }
    if (options?.eventName && options.eventName.length > 0) {
      payload['event_name'] = options.eventName;
    }
    if (options?.playSessionId && options.playSessionId.length > 0) {
      payload['play_session_id'] = options.playSessionId;
    }
    if (options?.clientId && options.clientId.length > 0) {
      payload['client_id'] = options.clientId;
    }
    if (options?.deviceName && options.deviceName.length > 0) {
      payload['device_name'] = options.deviceName;
    }
    if (options?.platform && options.platform.length > 0) {
      payload['platform'] = options.platform;
    }
    if (options?.appVersion && options.appVersion.length > 0) {
      payload['app_version'] = options.appVersion;
    }
    if (options?.playbackTimeMs !== undefined && options.playbackTimeMs >= 0) {
      payload['playback_time_ms'] = Math.round(options.playbackTimeMs);
    }
    if (options?.audioStreamIndex !== undefined && options.audioStreamIndex >= 0) {
      payload['audio_stream_index'] = Math.round(options.audioStreamIndex);
    }
    if (options?.subtitleStreamIndex !== undefined) {
      payload['subtitle_stream_index'] = Math.round(options.subtitleStreamIndex);
    }
    if (options?.seq !== undefined && options.seq >= 0) {
      payload['seq'] = Math.round(options.seq);
    }
    try {
      const url = RustCoreBridge.buildV3EndpointUrl(requestBase, ['mediaserver', 'progress'], {});
      const resp = await this.transport.execute(url, 'POST', requestToken, JSON.stringify(payload), 'application/json');
      return resp.status >= 200 && resp.status < 300;
    } catch {
      return false;
    }
  }

  private parseAccountBindingRecord(o: Record<string, Object>): MpMediaServerAccountBinding | null {
    const srv = strVal(o, 'server');
    if (srv.length === 0) { return null; }
    return {
      server: srv,
      serverType: strVal(o, 'server_type'),
      syncMode: strVal(o, 'sync_mode', 'none'),
      supportsBinding: boolVal(o, 'supports_binding', false),
      bound: boolVal(o, 'bound', false),
      status: strVal(o, 'status', 'unsupported'),
      remoteUsername: strVal(o, 'remote_username'),
      source: strVal(o, 'source'),
      updatedAt: numVal(o, 'updated_at', 0)
    };
  }

  private extractErrorDetail(body: string, fallback: string): string {
    const root = asRec(parseJsonSafe(body));
    if (root) {
      const detail = strVal(root, 'detail');
      if (detail.length > 0) { return detail; }
      const msg = strVal(root, 'message');
      if (msg.length > 0) { return msg; }
    }
    return fallback;
  }

  /** 查询当前用户在全部已启用媒体服务器上的账号绑定状态与同步模式。 */
  async fetchMediaServerAccountBindings(): Promise<MpMediaServerAccountBinding[]> {
    const resp = await this.get(['mediaserver', 'account-bindings']);
    if (resp.status < 200 || resp.status >= 300) {
      return [];
    }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const result: MpMediaServerAccountBinding[] = [];
    for (let i = 0; i < arr.length; i++) {
      const rec = asRec(arr[i]);
      if (!rec) { continue; }
      const parsed = this.parseAccountBindingRecord(rec);
      if (parsed) { result.push(parsed); }
    }
    return result;
  }

  /** 使用账号密码或 Plex Token 为当前用户绑定媒体服务器以启用实时播放会话（密码绝不在本地落盘）。 */
  async bindMediaServerAccount(
    server: string,
    username: string = '',
    password: string = '',
    token: string = ''
  ): Promise<MpMediaServerAccountBindResult> {
    const payload: Record<string, string> = { 'server': server.trim() };
    if (token.trim().length > 0) {
      payload['token'] = token.trim();
    } else {
      if (username.trim().length > 0) { payload['username'] = username.trim(); }
      if (password.length > 0) { payload['password'] = password; }
    }
    try {
      const resp = await this.postJson(['mediaserver', 'account-bindings'], JSON.stringify(payload));
      if (resp.status < 200 || resp.status >= 300) {
        return {
          success: false,
          message: this.extractErrorDetail(resp.body, '媒体服务器账号验证失败，请检查凭据')
        };
      }
      const dataRec = unwrapObject(parseJsonSafe(resp.body));
      const parsed = dataRec ? this.parseAccountBindingRecord(dataRec) : null;
      return {
        success: parsed !== null,
        message: parsed ? '绑定成功' : '绑定响应格式异常',
        binding: parsed ?? undefined
      };
    } catch {
      return { success: false, message: '网络连接失败，请稍后重试' };
    }
  }

  /** 解除当前用户在指定媒体服务器上的个人令牌绑定。 */
  async unbindMediaServerAccount(server: string): Promise<MpMediaServerAccountBindResult> {
    const clean = server.trim();
    if (!clean || clean === '.' || clean === '..' || clean.includes('/') || clean.includes('\\')) {
      return { success: false, message: '媒体服务器名称无效' };
    }
    try {
      const resp = await this.deleteReq(['mediaserver', 'account-bindings', clean]);
      if (resp.status < 200 || resp.status >= 300) {
        return {
          success: false,
          message: this.extractErrorDetail(resp.body, '解绑媒体服务器账号失败')
        };
      }
      const root = asRec(parseJsonSafe(resp.body));
      return {
        success: true,
        message: root ? (strVal(root, 'message') || '已解除账号绑定') : '已解除账号绑定'
      };
    } catch {
      return { success: false, message: '网络连接失败，请稍后重试' };
    }
  }

  /**
   * 拉取同源外挂字幕（上限 64MB、超时 90 秒，兼容实时字体子集化大体积 ASS）或 LRC 歌词文本（上限 2MB），
   * 支持 UTF-8 BOM、UTF-16 LE/BE、严格 UTF-8 与 GB18030 / GBK 中文回退解码。
   */
  async fetchSubtitleOrLyricsText(url: string, isLyrics: boolean = false): Promise<string> {
    const trusted = this.resolveTrustedSameOriginUrl(url);
    if (!trusted) {
      return '';
    }
    const maxBytes = isLyrics ? (2 * 1024 * 1024) : (64 * 1024 * 1024);
    const readTimeoutMs = isLyrics ? 30000 : 90000;
    const buf = await this.transport.fetchBytesBounded(trusted, this.token, maxBytes, readTimeoutMs);
    if (!buf || buf.byteLength === 0) {
      return '';
    }
    const bytes = new Uint8Array(buf);
    if (bytes.byteLength >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
      try {
        return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
      } catch {
        // continue
      }
    }
    if (bytes.byteLength >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) {
      try {
        return util.TextDecoder.create('utf-16le', { ignoreBOM: true }).decodeToString(bytes);
      } catch {
        // continue
      }
    }
    if (bytes.byteLength >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
      try {
        return util.TextDecoder.create('utf-16be', { ignoreBOM: true }).decodeToString(bytes);
      } catch {
        // continue
      }
    }
    try {
      return util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
    } catch {
      // 非 UTF-8 字节流回退 GB18030 / GBK 中文编码解码
    }
    try {
      return util.TextDecoder.create('gb18030', { ignoreBOM: true }).decodeToString(bytes);
    } catch {
      // continue
    }
    try {
      return util.TextDecoder.create('gbk', { ignoreBOM: true }).decodeToString(bytes);
    } catch {
      // continue
    }
    try {
      return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
    } catch {
      return '';
    }
  }

  /**
   * 为本地或支持 Range 流式的远端存储（SMB / OpenList / 阿里云盘 / 115 等）音视频文件签发短期流票据（`POST /api/v1/mediaserver/stream-ticket`），实现边加载边播放。
   */
  async createStorageStreamTicket(
    storage: string,
    filePath: string,
    fileNameHint: string = '',
    mediaTypeHint: string = ''
  ): Promise<string> {
    const cleanStorage = storage.trim() || 'local';
    const cleanPath = filePath.trim();
    if (!cleanPath) {
      return '';
    }
    const slashIdx = cleanPath.lastIndexOf('/');
    const pathName = slashIdx >= 0 ? cleanPath.substring(slashIdx + 1) : cleanPath;
    const fileName = fileNameHint.trim().length > 0 ? fileNameHint.trim() : pathName;
    const dotIdx = fileName.lastIndexOf('.');
    const ext = dotIdx >= 0 ? fileName.substring(dotIdx + 1) : '';
    const mediaType = mediaTypeHint === 'audio' || mediaTypeHint === 'video'
      ? mediaTypeHint
      : (RustCoreBridge.detectPlayableMediaKind(fileName.includes('.') ? fileName : cleanPath, true) === 'audio' ? 'audio' : 'video');
    const fileItem: Record<string, string> = {
      'storage': cleanStorage,
      'type': 'file',
      'path': cleanPath,
      'name': fileName,
      'extension': ext
    };
    const payload: Record<string, Object> = {
      'path': cleanPath,
      'file': fileItem,
      'media_type': mediaType
    };
    try {
      const resp = await this.postJson(['mediaserver', 'stream-ticket'], JSON.stringify(payload));
      if (resp.status < 200 || resp.status >= 300) {
        return '';
      }
      const r = unwrapObject(parseJsonSafe(resp.body));
      return strVal(r, 'item_id');
    } catch {
      return '';
    }
  }

  /**
   * 兼容旧调用签名（本地存储流票据）。
   */
  async createLocalStreamTicket(
    filePath: string,
    fileNameHint: string = '',
    mediaTypeHint: string = ''
  ): Promise<string> {
    return this.createStorageStreamTicket('local', filePath, fileNameHint, mediaTypeHint);
  }

  /**
   * 通过 `POST /api/v1/storage/download` 下载本地或远端云盘（WebDAV/SMB/115/阿里云盘/Rclone）音视频至沙盒临时缓存。
   * 返回落盘绝对路径，供 `AVPlayer.fdSrc` 本地打开并在关闭播放器时自动清理。
   */
  async downloadStorageFileToCache(
    storage: string,
    filePath: string,
    fileName: string,
    extension: string,
    cacheDir: string
  ): Promise<string> {
    const cleanPath = filePath.trim();
    const cleanDir = cacheDir.trim().replace(/\/+$/, '');
    if (!cleanPath || !cleanDir || !this.baseUrl) {
      return '';
    }
    const resolvedName = fileName.trim().length > 0
      ? fileName.trim()
      : (cleanPath.substring(cleanPath.lastIndexOf('/') + 1) || 'media');
    let cleanExt = extension.trim().replace(/^\.+/, '');
    if (!cleanExt) {
      const dotIdx = resolvedName.lastIndexOf('.');
      if (dotIdx > 0) {
        cleanExt = resolvedName.substring(dotIdx + 1);
      }
    }
    const safeExt = cleanExt.replace(/[^a-zA-Z0-9]/g, '').toLowerCase() ||
      (RustCoreBridge.detectPlayableMediaKind(resolvedName, false) === 'audio' ? 'mp3' : 'mp4');
    const destPath = `${cleanDir}/mp_play_${Date.now()}.${safeExt}`;
    const payload: Record<string, string> = {
      'storage': storage.trim() || 'local',
      'type': 'file',
      'path': cleanPath,
      'name': resolvedName,
      'extension': cleanExt
    };
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, ['storage', 'download']);
    const ok = await this.transport.downloadToFile(url, 'POST', this.token, JSON.stringify(payload), destPath);
    return ok ? destPath : '';
  }

  /** 按有界字节区间拉取音频头/尾片段，供内嵌封面与歌词解析使用。 */
  async fetchAudioByteRange(
    url: string,
    startByte: number,
    endInclusive: number,
    customHeaders?: Record<string, string>
  ): Promise<ByteRangeFetchResult | null> {
    return await this.transport.fetchByteRange(url, startByte, endInclusive, this.token, customHeaders);
  }

  /**
   * 通过当前实例受信任图片代理/全局缓存接口拉取并降采样解码 `<= 512px` 封面 `PixelMap`，供 `AVSession` 锁屏播控中心展示。
   */
  async fetchArtworkPixelMap(artworkUrl: string): Promise<image.PixelMap | null> {
    const raw = (artworkUrl ?? '').trim();
    if (!raw || !this.baseUrl) {
      return null;
    }
    await this.ensureImageContextReady();
    const proxied = this.resolveSameOriginArtworkUrl(raw);
    const trusted = this.resolveTrustedSameOriginUrl(proxied);
    if (!trusted) {
      return null;
    }
    const bytes = await this.transport.fetchBinary(trusted, this.token);
    if (!bytes || bytes.byteLength === 0) {
      return null;
    }
    try {
      const source = image.createImageSource(bytes);
      if (!source) {
        return null;
      }
      let decodeOpts: image.DecodingOptions = {
        desiredSize: { width: 512, height: 512 }
      };
      try {
        const info = await source.getImageInfo();
        if (info && info.size && info.size.width > 0 && info.size.height > 0) {
          const maxDim = Math.max(info.size.width, info.size.height);
          if (maxDim > 512) {
            const scale = 512 / maxDim;
            decodeOpts = {
              desiredSize: {
                width: Math.max(1, Math.round(info.size.width * scale)),
                height: Math.max(1, Math.round(info.size.height * scale))
              }
            };
          } else {
            decodeOpts = {
              desiredSize: { width: info.size.width, height: info.size.height }
            };
          }
        }
      } catch {
        // fallback to 512x512
      }
      const pm = await source.createPixelMap(decodeOpts);
      try {
        source.release();
      } catch {
        // ignore source release error
      }
      return pm;
    } catch {
      return null;
    }
  }

  private parseMediaServerStream(raw: Object): MpMediaServerStream | null {
    const r = asRec(raw);
    if (!r) { return null; }
    const streamType = strVal(r, 'type', 'unknown').toLowerCase();
    const width = Math.round(numVal(r, 'width', numVal(r, 'Width', 0)));
    const height = Math.round(numVal(r, 'height', numVal(r, 'Height', 0)));
    const bitrate = Math.round(numVal(r, 'bitrate', numVal(r, 'BitRate', 0)));
    const rawAspect = strVal(r, 'aspect_ratio') || strVal(r, 'AspectRatio');
    const rawFrameRate = strVal(r, 'frame_rate') || strVal(r, 'real_frame_rate') || strVal(r, 'average_frame_rate')
      || strVal(r, 'RealFrameRate') || strVal(r, 'AverageFrameRate');
    const rawProfile = strVal(r, 'profile') || strVal(r, 'Profile');
    const rawLevel = strVal(r, 'level') || strVal(r, 'Level');
    const rawPrimaries = strVal(r, 'color_primaries') || strVal(r, 'ColorPrimaries');
    const rawColorSpace = strVal(r, 'color_space') || strVal(r, 'ColorSpace');
    const rawBitDepth = Math.round(numVal(r, 'bit_depth', numVal(r, 'BitDepth', 0)));
    const rawSampleRate = Math.round(numVal(r, 'sample_rate', numVal(r, 'SampleRate', 0)));
    const hasInterlaceField = r['is_interlaced'] !== undefined || r['IsInterlaced'] !== undefined;
    const isInterlacedVal = hasInterlaceField
      ? (r['is_interlaced'] !== undefined ? boolVal(r, 'is_interlaced', false) : boolVal(r, 'IsInterlaced', false))
      : undefined;

    return {
      index: Math.round(numVal(r, 'index', 0)),
      type: streamType,
      codec: strVal(r, 'codec'),
      language: strVal(r, 'language'),
      title: strVal(r, 'title'),
      displayTitle: strVal(r, 'display_title'),
      isDefault: boolVal(r, 'is_default', false),
      isForced: boolVal(r, 'is_forced', false),
      isExternal: boolVal(r, 'is_external', false),
      subtitleId: strVal(r, 'subtitle_id'),
      channels: Math.round(numVal(r, 'channels', 0)),
      channelLayout: strVal(r, 'channel_layout'),
      bitrate: bitrate,
      width: width,
      height: height,
      videoRange: strVal(r, 'video_range'),
      frameRate: rawFrameRate.length > 0 && rawFrameRate !== '0' ? rawFrameRate : undefined,
      profile: rawProfile.length > 0 ? rawProfile : undefined,
      level: rawLevel.length > 0 && rawLevel !== '0' ? rawLevel : undefined,
      aspectRatio: rawAspect.length > 0 ? rawAspect : undefined,
      isInterlaced: isInterlacedVal,
      colorPrimaries: rawPrimaries.length > 0 ? rawPrimaries : undefined,
      colorSpace: rawColorSpace.length > 0 ? rawColorSpace : undefined,
      bitDepth: rawBitDepth > 0 ? rawBitDepth : undefined,
      sampleRate: rawSampleRate > 0 ? rawSampleRate : undefined,
      inferredAspectRatio: inferStreamAspectRatio(width, height, rawAspect),
      formattedBitrate: formatStreamBitrate(bitrate, streamType)
    };
  }

  private parseMediaServerEpisodeCard(raw: Object, fallbackServer: string = ''): MpMediaServerEpisode | null {
    const r = asRec(raw);
    if (!r) { return null; }
    const useCookies = boolVal(r, 'use_cookies', false);
    const itemId = strVal(r, 'item_id') || strVal(r, 'id');
    if (!itemId) { return null; }
    return {
      itemId: itemId,
      server: strVal(r, 'server', fallbackServer),
      serverType: strVal(r, 'server_type'),
      itemType: strVal(r, 'item_type', 'Episode'),
      title: strVal(r, 'title') || strVal(r, 'name', '未命名剧集'),
      subtitle: strVal(r, 'subtitle'),
      overview: strVal(r, 'overview'),
      year: strVal(r, 'year'),
      premiereDate: strVal(r, 'premiere_date'),
      rating: numVal(r, 'rating', 0),
      durationMs: Math.round(numVal(r, 'duration_ms', 0)),
      posterUrl: this.resolveImageUrl(strVal(r, 'poster') || strVal(r, 'image'), useCookies),
      backdropUrl: this.resolveImageUrl(strVal(r, 'backdrop'), useCookies),
      thumbUrl: this.resolveImageUrl(strVal(r, 'thumb'), useCookies),
      seriesId: strVal(r, 'series_id'),
      seriesName: strVal(r, 'series_name'),
      seasonId: strVal(r, 'season_id'),
      seasonNumber: Math.round(numVal(r, 'season_number', -1)),
      episodeNumber: Math.round(numVal(r, 'episode_number', 0)),
      childCount: Math.round(numVal(r, 'child_count', 0)),
      played: boolVal(r, 'played', false),
      playedPercentage: numVal(r, 'played_percentage', 0),
      resumePositionMs: Math.round(numVal(r, 'resume_position_ms', 0))
    };
  }

  /**
   * 查询媒体服务器单个条目完整详情（`GET /api/v1/mediaserver/detail?itemid=...&server=...`）。
   */
  async fetchMediaServerDetail(itemId: string, server: string = ''): Promise<MpMediaServerDetail | null> {
    const cleanId = itemId.trim();
    if (!cleanId) { return null; }
    const q: Record<string, string> = {};
    q['itemid'] = cleanId;
    if (server.trim().length > 0) {
      q['server'] = server.trim();
    }
    const resp = await this.get(['mediaserver', 'detail'], q);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    const useCookies = boolVal(r, 'use_cookies', false);

    const genres: string[] = [];
    const genresRaw = asArr(r['genres']);
    for (let i = 0; i < genresRaw.length; i++) {
      const gRec = asRec(genresRaw[i]);
      const gStr = gRec ? strVal(gRec, 'name') : String(genresRaw[i] ?? '').trim();
      if (gStr.length > 0) { genres.push(gStr); }
    }

    const studios: string[] = [];
    const studiosRaw = asArr(r['studios']);
    for (let i = 0; i < studiosRaw.length; i++) {
      const sStr = String(studiosRaw[i] ?? '').trim();
      if (sStr.length > 0) { studios.push(sStr); }
    }

    const people: MpMediaServerPerson[] = [];
    const peopleRaw = asArr(r['people']);
    for (let i = 0; i < Math.min(peopleRaw.length, 24); i++) {
      const pr = asRec(peopleRaw[i]);
      if (!pr) { continue; }
      const pName = strVal(pr, 'name');
      if (!pName) { continue; }
      people.push({
        id: strVal(pr, 'id', `ms_person_${i}`),
        name: pName,
        role: strVal(pr, 'role'),
        type: strVal(pr, 'type', 'Actor'),
        imageUrl: this.resolveImageUrl(strVal(pr, 'image'), useCookies)
      });
    }

    const mediaSources: MpMediaServerSource[] = [];
    const sourcesRaw = asArr(r['media_sources']);
    for (let i = 0; i < sourcesRaw.length; i++) {
      const sr = asRec(sourcesRaw[i]);
      if (!sr) { continue; }
      const streams: MpMediaServerStream[] = [];
      const streamsRaw = asArr(sr['streams']);
      for (let j = 0; j < streamsRaw.length; j++) {
        const parsedStream = this.parseMediaServerStream(streamsRaw[j]);
        if (parsedStream) { streams.push(parsedStream); }
      }
      const audioTracks: MpMediaTrackOption[] = [];
      const subtitleTracks: MpMediaTrackOption[] = [];
      let audioOrd = 0;
      let subOrd = 0;
      for (let k = 0; k < streams.length; k++) {
        const st = streams[k];
        if (st.type === 'audio') {
          const chTag = st.channelLayout || (st.channels > 0 ? `${st.channels}ch` : '');
          const parts: string[] = [];
          if (st.displayTitle.length > 0) {
            parts.push(st.displayTitle);
          } else {
            if (st.title.length > 0) { parts.push(st.title); }
            if (st.language.length > 0) { parts.push(st.language.toUpperCase()); }
            if (st.codec.length > 0) { parts.push(st.codec.toUpperCase()); }
            if (chTag.length > 0) { parts.push(chTag); }
          }
          audioTracks.push({
            index: st.index,
            ordinal: audioOrd++,
            type: 'audio',
            label: parts.length > 0 ? parts.join(' · ') : `音轨 ${audioOrd}`,
            language: st.language,
            codec: st.codec,
            isDefault: st.isDefault,
            isForced: st.isForced,
            isExternal: st.isExternal,
            subtitleId: ''
          });
        } else if (st.type === 'subtitle') {
          const subParts: string[] = [];
          if (st.displayTitle.length > 0) {
            subParts.push(st.displayTitle);
          } else {
            if (st.title.length > 0) { subParts.push(st.title); }
            if (st.language.length > 0) { subParts.push(st.language.toUpperCase()); }
            if (st.codec.length > 0) { subParts.push(st.codec.toUpperCase()); }
          }
          subtitleTracks.push({
            index: st.index,
            ordinal: subOrd++,
            type: 'subtitle',
            label: subParts.length > 0 ? subParts.join(' · ') : `字幕 ${subOrd}`,
            language: st.language,
            codec: st.codec,
            isDefault: st.isDefault,
            isForced: st.isForced,
            isExternal: st.isExternal || st.subtitleId.length > 0,
            subtitleId: st.subtitleId
          });
        }
      }
      mediaSources.push({
        id: strVal(sr, 'id', `src_${i}`),
        name: strVal(sr, 'name', `版本 ${i + 1}`),
        container: strVal(sr, 'container'),
        sizeBytes: Math.round(numVal(sr, 'size', 0)),
        bitrate: Math.round(numVal(sr, 'bitrate', 0)),
        durationMs: Math.round(numVal(sr, 'duration_ms', 0)),
        streams: streams,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks
      });
    }

    const rawMediaSource = normalizeMediaSourceCode(strVal(r, 'media_source'));
    const rawMediaIdVal = stripKnownMediaPrefix(strVal(r, 'media_id'));
    let tmdbId = stripKnownMediaPrefix(strVal(r, 'tmdb_id'));
    if (!tmdbId && rawMediaSource === 'themoviedb' && rawMediaIdVal.length > 0) {
      tmdbId = rawMediaIdVal;
    }
    let doubanId = stripKnownMediaPrefix(strVal(r, 'douban_id'));
    if (!doubanId && rawMediaSource === 'douban' && rawMediaIdVal.length > 0) {
      doubanId = rawMediaIdVal;
    }

    const parsedRatings: MpMediaRatingBadge[] = [];
    const ratingsRaw = asArr(r['ratings']);
    for (let i = 0; i < ratingsRaw.length; i++) {
      const rr = asRec(ratingsRaw[i]);
      if (!rr) { continue; }
      const normSrc = this.normalizeRatingSourceKey(strVal(rr, 'source'));
      const val = numVal(rr, 'value', 0);
      if (!normSrc || val <= 0) { continue; }
      const scale = strVal(rr, 'scale', 'ten').toLowerCase();
      const label = scale === 'percent'
        ? `${Math.max(1, Math.min(100, Math.round(val)))}%`
        : Math.min(10, val).toFixed(1);
      parsedRatings.push({ source: normSrc, label: label });
    }

    return {
      itemId: strVal(r, 'item_id', cleanId),
      server: strVal(r, 'server', server),
      serverType: strVal(r, 'server_type'),
      itemType: strVal(r, 'item_type', 'Movie'),
      mediaType: strVal(r, 'media_type'),
      title: strVal(r, 'title', '未命名条目'),
      originalTitle: strVal(r, 'original_title'),
      subtitle: strVal(r, 'subtitle'),
      tagline: strVal(r, 'tagline'),
      overview: strVal(r, 'overview'),
      year: strVal(r, 'year'),
      premiereDate: strVal(r, 'premiere_date'),
      rating: numVal(r, 'rating', 0),
      criticRating: numVal(r, 'critic_rating', 0),
      ratings: parsedRatings,
      officialRating: strVal(r, 'official_rating'),
      durationMs: Math.round(numVal(r, 'duration_ms', 0)),
      posterUrl: this.resolveImageUrl(strVal(r, 'poster') || strVal(r, 'image'), useCookies),
      backdropUrl: this.resolveImageUrl(strVal(r, 'backdrop'), useCookies),
      thumbUrl: this.resolveImageUrl(strVal(r, 'thumb'), useCookies),
      genres: genres,
      studios: studios,
      people: people,
      mediaSource: rawMediaSource,
      mediaId: rawMediaIdVal,
      imdbId: stripKnownMediaPrefix(strVal(r, 'imdb_id')),
      tmdbId: tmdbId,
      tvdbId: stripKnownMediaPrefix(strVal(r, 'tvdb_id')),
      doubanId: doubanId,
      parentId: strVal(r, 'parent_id'),
      seriesId: strVal(r, 'series_id'),
      seriesName: strVal(r, 'series_name'),
      seasonId: strVal(r, 'season_id'),
      seasonName: strVal(r, 'season_name'),
      seasonNumber: Math.round(numVal(r, 'season_number', -1)),
      episodeNumber: Math.round(numVal(r, 'episode_number', 0)),
      seasonCount: Math.round(numVal(r, 'season_count', 0)),
      episodeCount: Math.round(numVal(r, 'episode_count', 0)),
      played: boolVal(r, 'played', false),
      playedPercentage: numVal(r, 'played_percentage', 0),
      resumePositionMs: Math.round(numVal(r, 'resume_position_ms', 0)),
      mediaSources: mediaSources,
      playUrl: strVal(r, 'play_url') || strVal(r, 'link'),
      canPlay: boolVal(r, 'can_play', false)
    };
  }

  /**
   * 查询媒体服务器条目的播前多版本媒体源、音轨与字幕轨道清单。
   */
  async fetchMediaServerPlaybackInfo(itemId: string, server: string = ''): Promise<MpPlaybackSource[]> {
    const detail = await this.fetchMediaServerDetail(itemId, server);
    if (!detail) {
      return [];
    }
    const sources: MpPlaybackSource[] = [];
    for (let i = 0; i < detail.mediaSources.length; i++) {
      const src = detail.mediaSources[i];
      sources.push({
        id: src.id,
        name: src.name,
        container: src.container,
        sizeBytes: src.sizeBytes,
        bitrate: src.bitrate,
        durationMs: src.durationMs,
        streams: src.streams,
        audioTracks: src.audioTracks,
        subtitleTracks: src.subtitleTracks
      });
    }
    return sources;
  }

  /**
   * 查询媒体服务器剧集全部季卡片列表（`GET /api/v1/mediaserver/seasons`）。
   */
  async fetchMediaServerSeasons(seriesId: string, server: string): Promise<MpMediaServerEpisode[]> {
    const cleanId = seriesId.trim();
    const cleanSrv = server.trim();
    if (!cleanId || !cleanSrv) { return []; }
    const q: Record<string, string> = {
      'itemid': cleanId,
      'server': cleanSrv
    };
    const resp = await this.get(['mediaserver', 'seasons'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaServerEpisode[] = [];
    for (let i = 0; i < arr.length; i++) {
      const card = this.parseMediaServerEpisodeCard(arr[i], cleanSrv);
      if (card) { out.push(card); }
    }
    return out;
  }

  /**
   * 查询媒体服务器指定季全部单集详情卡片（`GET /api/v1/mediaserver/season-episodes`）。
   */
  async fetchMediaServerSeasonEpisodes(
    seriesId: string,
    server: string,
    seasonId: string = '',
    season?: number
  ): Promise<MpMediaServerEpisode[]> {
    const cleanId = seriesId.trim();
    const cleanSrv = server.trim();
    if (!cleanId || !cleanSrv) { return []; }
    const q: Record<string, string> = {
      'itemid': cleanId,
      'server': cleanSrv
    };
    if (seasonId.trim().length > 0) {
      q['season_id'] = seasonId.trim();
    }
    if (season !== undefined && season >= 0) {
      q['season'] = String(Math.round(season));
    }
    const resp = await this.get(['mediaserver', 'season-episodes'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaServerEpisode[] = [];
    for (let i = 0; i < arr.length; i++) {
      const card = this.parseMediaServerEpisodeCard(arr[i], cleanSrv);
      if (card) { out.push(card); }
    }
    return out;
  }

  /**
   * 为媒体服务器详情补全外部编号（`doubanId` / `imdbId` / `tmdbId` / `tvdbId`），支持 Season/Episode 向上回溯父剧集与 `/api/v1/media/{id}` 补全。
   */
  async enrichMediaServerExternalIds(detail: MpMediaServerDetail): Promise<MpMediaServerDetail> {
    const lowerItemType = detail.itemType.toLowerCase();
    if (
      (lowerItemType === 'season' || lowerItemType === 'episode') &&
      !detail.tmdbId && !detail.doubanId && !detail.imdbId
    ) {
      const parentLookupId = detail.seriesId || detail.parentId;
      if (parentLookupId.length > 0) {
        try {
          const parentDetail = await this.fetchMediaServerDetail(parentLookupId, detail.server);
          if (parentDetail) {
            if (!detail.tmdbId && parentDetail.tmdbId) { detail.tmdbId = parentDetail.tmdbId; }
            if (!detail.doubanId && parentDetail.doubanId) { detail.doubanId = parentDetail.doubanId; }
            if (!detail.imdbId && parentDetail.imdbId) { detail.imdbId = parentDetail.imdbId; }
            if (!detail.tvdbId && parentDetail.tvdbId) { detail.tvdbId = parentDetail.tvdbId; }
            if (!detail.mediaSource && parentDetail.mediaSource) { detail.mediaSource = parentDetail.mediaSource; }
            if (!detail.mediaId && parentDetail.mediaId) { detail.mediaId = parentDetail.mediaId; }
            if (detail.genres.length === 0 && parentDetail.genres.length > 0) {
              detail.genres = parentDetail.genres;
            }
          }
        } catch {
          // ignore parent lookup failure
        }
      }
    }

    const isTv = normalizeMediaTypeForV3(detail.mediaType || detail.itemType) === '电视剧';
    const lookupSrc = detail.tmdbId.length > 0
      ? 'themoviedb'
      : (detail.doubanId.length > 0 ? 'douban' : (detail.mediaSource || ''));
    const lookupId = detail.tmdbId.length > 0
      ? detail.tmdbId
      : (detail.doubanId.length > 0 ? detail.doubanId : detail.mediaId);

    if (lookupSrc.length > 0 && lookupId.length > 0 && (!detail.doubanId || !detail.imdbId || !detail.tmdbId)) {
      try {
        const q: Record<string, string> = {
          'media_source': lookupSrc,
          'type_name': isTv ? '电视剧' : '电影'
        };
        const resp = await this.get(['media', lookupId], q);
        if (resp.status === 200) {
          const r = unwrapObject(parseJsonSafe(resp.body));
          if (r) {
            const extraTmdb = stripKnownMediaPrefix(strVal(r, 'tmdb_id'));
            const extraDouban = stripKnownMediaPrefix(strVal(r, 'douban_id'));
            const extraImdb = stripKnownMediaPrefix(strVal(r, 'imdb_id'));
            const extraTvdb = stripKnownMediaPrefix(strVal(r, 'tvdb_id'));
            if (!detail.tmdbId && extraTmdb.length > 0) { detail.tmdbId = extraTmdb; }
            if (!detail.doubanId && extraDouban.length > 0) { detail.doubanId = extraDouban; }
            if (!detail.imdbId && extraImdb.length > 0) { detail.imdbId = extraImdb; }
            if (!detail.tvdbId && extraTvdb.length > 0) { detail.tvdbId = extraTvdb; }
          }
        }
      } catch {
        // ignore media enrichment failure
      }
    }
    return detail;
  }

  /**
   * 查询媒体服务器详情页「类似作品」（依次走 TMDB similar -> TMDB recommend -> 豆瓣 recommend -> 同类型库内回退）。
   */
  async fetchMediaServerSimilar(detail: MpMediaServerDetail): Promise<MpMediaItem[]> {
    const typeName = normalizeMediaTypeForV3(detail.mediaType || detail.itemType) === '电视剧' ? '电视剧' : '电影';
    const out: MpMediaItem[] = [];

    if (detail.tmdbId.length > 0) {
      try {
        const simResp = await this.get(['tmdb', 'similar', detail.tmdbId, typeName]);
        if (simResp.status === 200) {
          const arr = unwrapArray(parseJsonSafe(simResp.body));
          for (let i = 0; i < arr.length; i++) {
            const it = this.parseMediaItem(arr[i], 'themoviedb');
            if (it) { out.push(it); }
          }
        }
      } catch {
        // ignore similar error
      }
      if (out.length === 0) {
        try {
          const recResp = await this.get(['tmdb', 'recommend', detail.tmdbId, typeName]);
          if (recResp.status === 200) {
            const arr = unwrapArray(parseJsonSafe(recResp.body));
            for (let i = 0; i < arr.length; i++) {
              const it = this.parseMediaItem(arr[i], 'themoviedb');
              if (it) { out.push(it); }
            }
          }
        } catch {
          // ignore recommend error
        }
      }
    }

    if (out.length === 0 && detail.doubanId.length > 0) {
      try {
        const dbResp = await this.get(['douban', 'recommend', detail.doubanId, typeName]);
        if (dbResp.status === 200) {
          const arr = unwrapArray(parseJsonSafe(dbResp.body));
          for (let i = 0; i < arr.length; i++) {
            const it = this.parseMediaItem(arr[i], 'douban');
            if (it) { out.push(it); }
          }
        }
      } catch {
        // ignore douban recommend error
      }
    }

    if (out.length === 0 && detail.server.length > 0) {
      try {
        const q: Record<string, string> = {
          'server': detail.server,
          'start_index': '0',
          'limit': '18'
        };
        if (detail.genres.length > 0) {
          q['genre'] = detail.genres[0];
        }
        const brResp = await this.get(['mediaserver', 'browse'], q);
        if (brResp.status === 200) {
          const arr = unwrapArray(parseJsonSafe(brResp.body));
          for (let i = 0; i < arr.length; i++) {
            const it = this.parseMediaItem(arr[i], 'mediaserver');
            if (it && it.id !== detail.itemId && it.serverItemId !== detail.itemId) {
              it.inLibrary = true;
              if (!it.serverName) { it.serverName = detail.server; }
              if (!it.serverItemId && it.id.length > 0) { it.serverItemId = it.id; }
              out.push(it);
            }
          }
        }
      } catch {
        // ignore browse fallback error
      }
    }

    return out.slice(0, 18);
  }

  /** 无损保存/更新订阅规则（保留未编辑服务端字段）。 */
  async saveSubscription(sub: MpSubscribeItem): Promise<boolean> {
    let payloadObj: Record<string, Object> = {};
    if (sub.rawJson && sub.rawJson.length > 2) {
      const parsed = asRec(parseJsonSafe(sub.rawJson));
      if (parsed) { payloadObj = parsed; }
    }
    payloadObj['id'] = sub.id;
    payloadObj['name'] = sub.name;
    payloadObj['year'] = sub.year;
    payloadObj['type'] = sub.type;
    payloadObj['state'] = sub.state;
    payloadObj['quality'] = sub.quality;
    payloadObj['resolution'] = sub.resolution;
    payloadObj['effect'] = sub.effect ?? '';
    payloadObj['best_version'] = sub.bestVersion ? 1 : 0;
    payloadObj['save_path'] = sub.savePath;
    if (sub.season > 0) { payloadObj['season'] = sub.season; }
    if (sub.totalEpisode > 0) { payloadObj['total_episode'] = sub.totalEpisode; }
    if ((sub.startEpisode ?? 0) > 0) { payloadObj['start_episode'] = sub.startEpisode ?? 0; }
    if (sub.episodeGroup !== undefined) { payloadObj['episode_group'] = sub.episodeGroup; }
    if (sub.downloader !== undefined) { payloadObj['downloader'] = sub.downloader; }
    if (sub.sites !== undefined) { payloadObj['sites'] = sub.sites; }
    if (sub.filterGroups !== undefined) { payloadObj['filter_groups'] = sub.filterGroups; }
    if (sub.include !== undefined) { payloadObj['include'] = sub.include; }
    if (sub.exclude !== undefined) { payloadObj['exclude'] = sub.exclude; }
    if (sub.customWords !== undefined) { payloadObj['custom_words'] = sub.customWords; }
    if (sub.searchImdbid !== undefined) { payloadObj['search_imdbid'] = sub.searchImdbid ? 1 : 0; }
    if ((sub.interval ?? 0) > 0) { payloadObj['interval'] = sub.interval ?? 0; }
    const resp = await this.putJson(['subscribe'], JSON.stringify(payloadObj), true);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 删除指定订阅。 */
  async deleteSubscribe(subId: number): Promise<boolean> {
    const resp = await this.deleteReq(['subscribe', String(subId)]);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 分页拉取订阅历史记录（`GET /api/v1/subscribe/history/{mtype}?page=&count=`）。 */
  async fetchSubscribeHistory(mtype: string = '电影', page: number = 1, count: number = 30): Promise<MpSubscribeItem[]> {
    const normalizedType = mtype.trim().length > 0 ? mtype.trim() : '电影';
    const q: Record<string, string> = {};
    q['page'] = String(Math.max(1, Math.round(page)));
    q['count'] = String(Math.max(1, Math.round(count)));
    const resp = await this.get(['subscribe', 'history', normalizedType], q);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(`HTTP ${resp.status}`);
    }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpSubscribeItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const parsed = this.parseSubscribeRecord(asRec(arr[i]));
      if (parsed) { out.push(parsed); }
    }
    return out;
  }

  /** 删除单条订阅历史记录（`DELETE /api/v1/subscribe/history/{history_id}`）。 */
  async deleteSubscribeHistory(historyId: number): Promise<boolean> {
    if (!Number.isFinite(historyId) || historyId <= 0) { return false; }
    const resp = await this.deleteReq(['subscribe', 'history', String(Math.round(historyId))]);
    if (resp.status < 200 || resp.status >= 300) { return false; }
    const parsed = asRec(parseJsonSafe(resp.body));
    if (parsed && parsed['success'] !== undefined) {
      return boolVal(parsed, 'success', true);
    }
    return true;
  }

  /** 从订阅历史记录重新发起订阅（`POST /api/v1/subscribe/`），剔除只读字段并保留原规则配置。 */
  async reSubscribeFromHistory(sub: MpSubscribeItem, fallbackType: string = '电影'): Promise<MpSubscribeMutationResult> {
    const excludedKeys: string[] = [
      'id', 'tmdbid', 'doubanid', 'bangumiid', 'mediaid',
      'poster', 'backdrop', 'vote', 'description', 'lack_episode',
      'completed_episode', 'completed_tracks', 'note', 'state', 'last_update',
      'username', 'current_priority', 'episode_priority', 'date',
      'current_audio_format', 'current_bitrate', 'current_bit_depth', 'current_sample_rate',
      'classification_rule_id', 'classification_policy_revision', 'classification_source',
      'execution_status', 'last_search'
    ];
    let rawRec: Record<string, Object> | null = null;
    if (sub.rawJson && sub.rawJson.length > 2) {
      rawRec = asRec(parseJsonSafe(sub.rawJson));
    }
    const cleanPayload: Record<string, Object> = {};
    if (rawRec) {
      const keys = Object.keys(rawRec);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (excludedKeys.indexOf(k) >= 0) { continue; }
        const val = rawRec[k];
        if (val === undefined || val === null) { continue; }
        if (k === 'search_interval' && Number(val) <= 0) { continue; }
        cleanPayload[k] = val;
      }
    }
    const resolvedType = (sub.type && sub.type.trim().length > 0) ? sub.type.trim() : fallbackType;
    cleanPayload['name'] = sub.name.trim();
    cleanPayload['type'] = resolvedType;
    if (sub.year && sub.year.trim().length > 0) {
      cleanPayload['year'] = sub.year.trim();
    }
    if (resolvedType === '电视剧' && sub.season > 0) {
      cleanPayload['season'] = Math.round(sub.season);
    }
    const existingSource = String(cleanPayload['media_source'] ?? '').trim();
    const existingMid = String(cleanPayload['media_id'] ?? '').trim();
    if (existingSource.length === 0 || existingMid.length === 0) {
      if (rawRec) {
        const tmdb = numVal(rawRec, 'tmdbid', 0);
        const douban = strVal(rawRec, 'doubanid').trim();
        const bangumi = numVal(rawRec, 'bangumiid', 0);
        if (tmdb > 0) {
          cleanPayload['media_source'] = 'themoviedb';
          cleanPayload['media_id'] = String(Math.round(tmdb));
        } else if (douban.length > 0) {
          cleanPayload['media_source'] = 'douban';
          cleanPayload['media_id'] = douban;
        } else if (bangumi > 0) {
          cleanPayload['media_source'] = 'bangumi';
          cleanPayload['media_id'] = String(Math.round(bangumi));
        }
      }
    }

    const resp = await this.postJson(['subscribe'], JSON.stringify(cleanPayload), true);
    const parsed = asRec(parseJsonSafe(resp.body));
    const ok = resp.status >= 200 && resp.status < 300 && parsed !== null && boolVal(parsed, 'success', false) === true;
    const dataRec = parsed ? asRec(parsed['data']) : null;
    const subId = numVal(dataRec, 'id', 0);
    const msg = strVal(parsed, 'message');
    if (ok) {
      this.invalidateSubscriptionsCache();
    }
    return {
      ok: ok,
      message: msg.length > 0 ? msg : (ok ? `已重新订阅「${sub.name}」` : '重新订阅失败，请稍后重试'),
      id: subId
    };
  }

  /** 获取用户优先级规则组列表。 */
  async fetchFilterRuleGroups(): Promise<MpFilterRuleGroup[]> {
    const resp = await this.get(['system', 'setting', 'UserFilterRuleGroups']);
    if (resp.status !== 200) { return []; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    const arr = root ? asArr(root['value']) : [];
    const out: MpFilterRuleGroup[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const name = strVal(r, 'name');
      if (name.length > 0) {
        out.push({ name: name, ruleString: strVal(r, 'rule_string') });
      }
    }
    return out;
  }

  /** 多站点资源搜索（支持关键词 + 多选站点 ID；留空返回最近搜索结果或站点浏览）。 */
  async searchSiteResources(keyword: string, siteIds: number[] = []): Promise<MpResourceItem[]> {
    const q: Record<string, string> = {};
    if (keyword.trim().length > 0) { q['keyword'] = keyword.trim(); }
    if (siteIds.length > 0) { q['sites'] = siteIds.join(','); }
    let resp: NativeHttpResponse;
    if (keyword.trim().length > 0) {
      resp = await this.get(['search', 'title'], q);
    } else if (siteIds.length === 1) {
      resp = await this.get(['site', 'resource', String(siteIds[0])]);
    } else {
      resp = await this.get(['search', 'last']);
    }
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpResourceItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const parsedItem = this.parseResourceRecord(r);
      const sid = parsedItem.siteId ?? 0;
      if (siteIds.length > 1 && sid > 0 && !siteIds.includes(sid)) { continue; }
      out.push(parsedItem);
    }
    return out;
  }

  /** 推送资源种子到指定下载器。 */
  async pushDownload(item: MpResourceItem, downloader: string = '', savePath: string = ''): Promise<boolean> {
    const bodyObj: Record<string, Object> = {};
    if (item.rawJson && item.rawJson.length > 2) {
      const rawRec = asRec(parseJsonSafe(item.rawJson));
      if (rawRec) {
        bodyObj['torrent_in'] = rawRec['torrent_info'] ?? rawRec;
        if (rawRec['media_info']) { bodyObj['media_in'] = rawRec['media_info']; }
      }
    }
    if (!bodyObj['torrent_in']) {
      const tInfo: Record<string, Object> = {};
      tInfo['title'] = item.title;
      tInfo['enclosure'] = item.enclosure;
      tInfo['page_url'] = item.pageUrl;
      tInfo['size'] = item.sizeBytes;
      tInfo['site_name'] = item.siteName;
      bodyObj['torrent_in'] = tInfo;
    }
    if (downloader.length > 0) { bodyObj['downloader'] = downloader; }
    if (savePath.trim().length > 0) { bodyObj['save_path'] = savePath.trim(); }
    const resp = await this.postJson(['download', 'add'], JSON.stringify(bodyObj));
    return resp.status >= 200 && resp.status < 300;
  }

  /** 暂停或恢复下载任务。 */
  async toggleDownloadTask(hash: string, downloader: string, pause: boolean): Promise<boolean> {
    const q: Record<string, string> = {};
    if (downloader.length > 0) { q['name'] = downloader; }
    const seg = pause ? ['download', 'stop', hash] : ['download', 'start', hash];
    const resp = await this.get(seg, q);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 删除下载任务。 */
  async deleteDownloadTask(hash: string, downloader: string): Promise<boolean> {
    const q: Record<string, string> = {};
    if (downloader.length > 0) { q['name'] = downloader; }
    const resp = await this.deleteReq(['download', hash], q);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 新增或编辑站点（无损保留原字段）。 */
  async saveSite(site: MpSiteItem, isCreate: boolean): Promise<boolean> {
    let obj: Record<string, Object> = {};
    if (!isCreate && site.rawJson && site.rawJson.length > 2) {
      const parsed = asRec(parseJsonSafe(site.rawJson));
      if (parsed) { obj = parsed; }
    }
    if (!isCreate && site.id > 0) { obj['id'] = site.id; }
    obj['name'] = site.name.trim();
    obj['url'] = site.url.trim();
    const cleanDomain = site.domain.trim() || site.url.trim().replace(/^https?:\/\//, '').split('/')[0];
    obj['domain'] = cleanDomain;
    obj['pri'] = site.priority ?? 1;
    obj['rss'] = site.rss ?? '';
    obj['cookie'] = site.cookie ?? '';
    obj['ua'] = site.ua ?? '';
    obj['is_active'] = site.isActive;
    obj['proxy'] = site.proxy ? 1 : 0;
    obj['render'] = site.render ? 1 : 0;
    const resp = isCreate
      ? await this.postJson(['site'], JSON.stringify(obj), true)
      : await this.putJson(['site'], JSON.stringify(obj), true);
    return resp.status >= 200 && resp.status < 300;
  }

  async deleteSite(siteId: number): Promise<boolean> {
    const resp = await this.deleteReq(['site', String(siteId)]);
    return resp.status >= 200 && resp.status < 300;
  }

  async testSiteConnectivity(siteId: number): Promise<string> {
    const resp = await this.get(['site', 'test', String(siteId)]);
    const root = asRec(parseJsonSafe(resp.body));
    const ok = boolVal(root, 'success', resp.status === 200);
    const msg = strVal(root, 'message');
    return ok ? (msg || '连通正常') : (msg || '连接失败');
  }

  /** 读取并无损维护系统数组配置（Downloaders / MediaServers / Directories）。 */
  private async fetchRawSettingArray(key: string): Promise<Record<string, Object>[]> {
    const resp = await this.get(['system', 'setting', key]);
    if (resp.status !== 200) { return []; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    const arr = root ? asArr(root['value']) : [];
    const out: Record<string, Object>[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (r) { out.push(r); }
    }
    return out;
  }

  private async saveRawSettingArray(key: string, items: Record<string, Object>[]): Promise<boolean> {
    const resp = await this.postJson(['system', 'setting', key], JSON.stringify(items));
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchDownloaders(): Promise<MpServiceConfig[]> {
    const raw = await this.fetchRawSettingArray('Downloaders');
    return raw.map((r: Record<string, Object>): MpServiceConfig => {
      const cfg = asRec(r['config']);
      return {
        name: strVal(r, 'name'),
        type: strVal(r, 'type', 'qbittorrent'),
        host: strVal(cfg, 'host'),
        username: strVal(cfg, 'username'),
        password: strVal(cfg, 'password'),
        apikey: '',
        playHost: '',
        enabled: boolVal(r, 'enabled', true),
        isDefault: boolVal(r, 'default', false),
        rawJson: JSON.stringify(r)
      };
    });
  }

  async saveDownloader(item: MpServiceConfig, originalName: string | null): Promise<boolean> {
    const list = await this.fetchRawSettingArray('Downloaders');
    let obj: Record<string, Object> = {};
    if (item.rawJson.length > 2) {
      const p = asRec(parseJsonSafe(item.rawJson));
      if (p) { obj = p; }
    }
    const cfg = asRec(obj['config']) ?? {};
    cfg['host'] = item.host.trim();
    cfg['username'] = item.username.trim();
    cfg['password'] = item.password;
    obj['name'] = item.name.trim();
    obj['type'] = item.type;
    obj['enabled'] = item.enabled;
    obj['default'] = item.isDefault;
    obj['config'] = cfg;

    const next: Record<string, Object>[] = [];
    let replaced = false;
    for (let i = 0; i < list.length; i++) {
      const cur = list[i];
      if (item.isDefault) { cur['default'] = false; }
      if (originalName !== null && strVal(cur, 'name') === originalName) {
        next.push(obj);
        replaced = true;
      } else {
        next.push(cur);
      }
    }
    if (!replaced) { next.push(obj); }
    return this.saveRawSettingArray('Downloaders', next);
  }

  async deleteDownloader(name: string): Promise<boolean> {
    const list = await this.fetchRawSettingArray('Downloaders');
    const next = list.filter((r: Record<string, Object>) => strVal(r, 'name') !== name);
    return this.saveRawSettingArray('Downloaders', next);
  }

  async fetchMediaServers(): Promise<MpServiceConfig[]> {
    const raw = await this.fetchRawSettingArray('MediaServers');
    return raw.map((r: Record<string, Object>): MpServiceConfig => {
      const cfg = asRec(r['config']);
      return {
        name: strVal(r, 'name'),
        type: strVal(r, 'type', 'emby'),
        host: strVal(cfg, 'host'),
        username: strVal(cfg, 'username'),
        password: strVal(cfg, 'password'),
        apikey: strVal(cfg, 'apikey') || strVal(cfg, 'token'),
        playHost: strVal(cfg, 'play_host'),
        enabled: boolVal(r, 'enabled', true),
        isDefault: false,
        rawJson: JSON.stringify(r)
      };
    });
  }

  async saveMediaServer(item: MpServiceConfig, originalName: string | null): Promise<boolean> {
    const list = await this.fetchRawSettingArray('MediaServers');
    let obj: Record<string, Object> = {};
    if (item.rawJson.length > 2) {
      const p = asRec(parseJsonSafe(item.rawJson));
      if (p) { obj = p; }
    }
    const cfg = asRec(obj['config']) ?? {};
    cfg['host'] = item.host.trim();
    if (item.type.toLowerCase() === 'plex') {
      cfg['token'] = item.apikey.trim();
    } else {
      cfg['apikey'] = item.apikey.trim();
    }
    cfg['play_host'] = item.playHost.trim();
    obj['name'] = item.name.trim();
    obj['type'] = item.type;
    obj['enabled'] = item.enabled;
    obj['config'] = cfg;

    const next: Record<string, Object>[] = [];
    let replaced = false;
    for (let i = 0; i < list.length; i++) {
      if (originalName !== null && strVal(list[i], 'name') === originalName) {
        next.push(obj);
        replaced = true;
      } else {
        next.push(list[i]);
      }
    }
    if (!replaced) { next.push(obj); }
    return this.saveRawSettingArray('MediaServers', next);
  }

  async deleteMediaServer(name: string): Promise<boolean> {
    const list = await this.fetchRawSettingArray('MediaServers');
    const next = list.filter((r: Record<string, Object>) => strVal(r, 'name') !== name);
    return this.saveRawSettingArray('MediaServers', next);
  }

  async fetchDirectories(): Promise<MpDirectoryConfig[]> {
    const raw = await this.fetchRawSettingArray('Directories');
    return raw.map((r: Record<string, Object>, i: number): MpDirectoryConfig => ({
      name: strVal(r, 'name', `目录 ${i + 1}`),
      priority: Math.round(numVal(r, 'priority', i + 1)),
      storage: strVal(r, 'storage', 'local'),
      downloadPath: strVal(r, 'download_path'),
      libraryStorage: strVal(r, 'library_storage', 'local'),
      libraryPath: strVal(r, 'library_path'),
      transferType: strVal(r, 'transfer_type', 'link'),
      monitorType: strVal(r, 'monitor_type', 'downloader'),
      renaming: boolVal(r, 'renaming', true),
      scraping: boolVal(r, 'scraping', true),
      notify: boolVal(r, 'notify', true),
      rawJson: JSON.stringify(r)
    }));
  }

  async saveDirectory(item: MpDirectoryConfig, originalName: string | null): Promise<boolean> {
    const list = await this.fetchRawSettingArray('Directories');
    let obj: Record<string, Object> = {};
    if (item.rawJson.length > 2) {
      const p = asRec(parseJsonSafe(item.rawJson));
      if (p) { obj = p; }
    }
    obj['name'] = item.name.trim();
    obj['priority'] = item.priority;
    obj['storage'] = item.storage;
    obj['download_path'] = item.downloadPath.trim();
    obj['library_storage'] = item.libraryStorage;
    obj['library_path'] = item.libraryPath.trim();
    obj['transfer_type'] = item.transferType;
    obj['monitor_type'] = item.monitorType;
    obj['renaming'] = item.renaming;
    obj['scraping'] = item.scraping;
    obj['notify'] = item.notify;

    const next: Record<string, Object>[] = [];
    let replaced = false;
    for (let i = 0; i < list.length; i++) {
      if (originalName !== null && strVal(list[i], 'name') === originalName) {
        next.push(obj);
        replaced = true;
      } else {
        next.push(list[i]);
      }
    }
    if (!replaced) { next.push(obj); }
    return this.saveRawSettingArray('Directories', next);
  }

  async deleteDirectory(name: string): Promise<boolean> {
    const list = await this.fetchRawSettingArray('Directories');
    const next = list.filter((r: Record<string, Object>) => strVal(r, 'name') !== name);
    return this.saveRawSettingArray('Directories', next);
  }

  async fetchStorages(): Promise<MpStorageConfig[]> {
    const raw = await this.fetchRawSettingArray('Storages');
    const out: MpStorageConfig[] = [];
    for (let i = 0; i < raw.length; i++) {
      const t = strVal(raw[i], 'type');
      const n = strVal(raw[i], 'name') || t;
      if (t.length > 0) { out.push({ name: n, type: t }); }
    }
    if (out.length === 0) {
      out.push({ name: '本地存储', type: 'local' });
    }
    return out;
  }

  /** 词表类系统设置读写（兼容字符串数组与多行文本）。 */
  async fetchSystemSettingText(key: string): Promise<string> {
    const resp = await this.get(['system', 'setting', key]);
    if (resp.status !== 200) { return ''; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    const val = root ? root['value'] : undefined;
    if (Array.isArray(val)) {
      return (val as Object[]).map((v: Object) => String(v ?? '')).filter((s: string) => s.length > 0).join('\n');
    }
    if (typeof val === 'string') { return val; }
    return '';
  }

  async saveSystemSettingText(key: string, multiLineText: string, asArray: boolean = true): Promise<boolean> {
    const lines = multiLineText.split('\n').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    const payload = asArray ? JSON.stringify(lines) : JSON.stringify(multiLineText);
    const resp = await this.postJson(['system', 'setting', key], payload);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 手动触发定时任务。 */
  async runScheduler(jobId: string): Promise<boolean> {
    const q: Record<string, string> = {};
    q['jobid'] = jobId;
    const resp = await this.get(['system', 'runscheduler'], q);
    return resp.status >= 200 && resp.status < 300;
  }

  /** 在线识别种子/文件名。 */
  async recognizeTitle(title: string, subtitle: string = ''): Promise<MpRecognizeResult | null> {
    const q: Record<string, string> = {};
    q['title'] = title.trim();
    if (subtitle.trim().length > 0) { q['subtitle'] = subtitle.trim(); }
    const resp = await this.get(['media', 'recognize'], q);
    if (resp.status !== 200) { return null; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root) { return null; }
    const meta = asRec(root['meta_info']);
    const media = asRec(root['media_info']);
    return {
      title: strVal(media, 'title') || strVal(meta, 'cn_name') || strVal(meta, 'name'),
      enTitle: strVal(media, 'en_title') || strVal(meta, 'en_name'),
      year: strVal(media, 'year') || strVal(meta, 'year'),
      type: strVal(media, 'type') || strVal(meta, 'type', '未知'),
      season: strVal(meta, 'season'),
      episode: strVal(meta, 'episode'),
      resolution: strVal(meta, 'resource_pix'),
      videoEncode: strVal(meta, 'video_encode'),
      releaseGroup: strVal(meta, 'resource_team'),
      tmdbId: strVal(media, 'tmdb_id'),
      posterUrl: this.resolveImageUrl(strVal(media, 'poster_path')),
      overview: strVal(media, 'overview')
    };
  }

  /** 网络连通性检测（多目标并发测试）。 */
  async testNetworkConnectivity(): Promise<MpNetworkCheckItem[]> {
    const targets: string[][] = [
      ['TheMovieDB API', 'https://api.themoviedb.org'],
      ['TheMovieDB 图片', 'https://image.tmdb.org'],
      ['豆瓣', 'https://movie.douban.com'],
      ['GitHub', 'https://github.com'],
      ['Fanart', 'https://webservice.fanart.tv']
    ];
    const results: MpNetworkCheckItem[] = [];
    for (let i = 0; i < targets.length; i++) {
      const tName = targets[i][0];
      const tUrl = targets[i][1];
      const q: Record<string, string> = {};
      q['url'] = tUrl;
      const start = Date.now();
      try {
        const resp = await this.get(['system', 'nettest'], q);
        const root = asRec(parseJsonSafe(resp.body));
        const ok = boolVal(root, 'success', resp.status === 200);
        const dataRec = asRec(root ? root['data'] : undefined);
        const ms = Math.round(numVal(dataRec, 'time', Date.now() - start));
        results.push({ name: tName, ok: ok, latencyMs: ms, detail: strVal(root, 'message') || (ok ? '连通正常' : '超时或不可达') });
      } catch {
        results.push({ name: tName, ok: false, latencyMs: Date.now() - start, detail: '请求异常' });
      }
    }
    return results;
  }

  /** 手动识别整理：自动匹配目标路径。 */
  async matchManualTransferTargetPath(payloadJson: string): Promise<MpManualTransferTargetHint | null> {
    const resp = await this.postJson(['transfer', 'manual', 'target-path'], payloadJson);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    return {
      targetStorage: strVal(r, 'target_storage'),
      targetPath: strVal(r, 'target_path'),
      transferType: strVal(r, 'transfer_type'),
      overwriteMode: strVal(r, 'overwrite_mode')
    };
  }

  /** 手动识别整理：匹配历史整理记录。 */
  async matchManualTransferHistory(payloadJson: string): Promise<MpManualTransferHistoryHint | null> {
    const resp = await this.postJson(['transfer', 'manual', 'history'], payloadJson);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    return {
      historyCount: Math.round(numVal(r, 'history_count', numVal(r, 'count', 0))),
      reorganize: boolVal(r, 'reorganize', false)
    };
  }

  /** 手动识别整理：执行预览或提交整理。 */
  async executeManualTransfer(payloadJson: string, background: boolean = true): Promise<MpManualTransferResult> {
    const q: Record<string, string> = {};
    q['background'] = background ? 'true' : 'false';
    const resp = await this.postJsonQuery(['transfer', 'manual'], q, payloadJson);
    const root = asRec(parseJsonSafe(resp.body));
    const ok = boolVal(root, 'success', resp.status >= 200 && resp.status < 300);
    const msg = strVal(root, 'message') || (ok ? '整理任务已提交' : '整理请求失败');
    const previewItems: MpManualTransferPreviewItem[] = [];
    const dataNode = root ? root['data'] : undefined;
    const dataRec = asRec(dataNode);
    const rawList = Array.isArray(dataNode)
      ? (dataNode as Object[])
      : (dataRec ? (asArr(dataRec['items']).length > 0 ? asArr(dataRec['items']) : asArr(dataRec['preview'])) : []);
    for (let i = 0; i < rawList.length; i++) {
      const it = asRec(rawList[i]);
      if (!it) { continue; }
      previewItems.push({
        src: strVal(it, 'src') || strVal(it, 'source'),
        dest: strVal(it, 'dest') || strVal(it, 'target'),
        title: strVal(it, 'title') || strVal(it, 'name'),
        status: strVal(it, 'status', '就绪')
      });
    }
    return { success: ok, message: msg, previewItems: previewItems };
  }

  /** AI 智能助手：拉取斜杠命令清单。 */
  async fetchAgentCommands(): Promise<MpAgentCommand[]> {
    const resp = await this.get(['message', 'agent', 'commands']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpAgentCommand[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const cmd = strVal(r, 'command') || strVal(r, 'name');
      if (cmd.length > 0) {
        out.push({ command: cmd.startsWith('/') ? cmd : `/${cmd}`, description: strVal(r, 'description') });
      }
    }
    return out;
  }

  /** AI 智能助手：获取服务端真实历史会话列表。 */
  async fetchAgentSessions(): Promise<MpAgentSessionSummary[]> {
    const resp = await this.get(['message', 'agent', 'sessions']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpAgentSessionSummary[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const sid = strVal(r, 'session_id') || strVal(r, 'id');
      if (sid.length > 0) {
        out.push({
          sessionId: sid,
          title: strVal(r, 'title') || strVal(r, 'preview') || '新对话',
          messageCount: Math.round(numVal(r, 'message_count', numVal(r, 'count', 0))),
          updatedAt: strVal(r, 'updated_at') || strVal(r, 'last_time')
        });
      }
    }
    return out;
  }

  /** AI 智能助手：拉取单条会话完整历史（含工具调用分组与附件）。 */
  async fetchAgentSessionDetail(sessionId: string): Promise<MpAgentChatMessage[]> {
    const resp = await this.get(['message', 'agent', 'sessions', sessionId]);
    if (resp.status !== 200) { return []; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    const rawMsgs = root
      ? (asArr(root['display_messages']).length > 0 ? asArr(root['display_messages']) : asArr(root['messages']))
      : unwrapArray(parseJsonSafe(resp.body));
    const out: MpAgentChatMessage[] = [];
    for (let i = 0; i < rawMsgs.length; i++) {
      const r = asRec(rawMsgs[i]);
      if (!r) { continue; }
      const role = strVal(r, 'role', 'assistant').toLowerCase();
      const tools: MpAgentToolEntry[] = [];
      const rawTools = asArr(r['tools']).length > 0 ? asArr(r['tools']) : asArr(r['tool_calls']);
      for (let j = 0; j < rawTools.length; j++) {
        const t = asRec(rawTools[j]);
        if (!t) { continue; }
        tools.push({
          id: strVal(t, 'id', `t_${i}_${j}`),
          name: strVal(t, 'name') || strVal(t, 'tool_name', '工具调用'),
          status: strVal(t, 'status', 'done'),
          summary: strVal(t, 'summary') || strVal(t, 'title'),
          detail: strVal(t, 'result') || strVal(t, 'output') || strVal(t, 'arguments')
        });
      }
      const atts: MpAgentAttachment[] = [];
      const rawAtts = asArr(r['attachments']).concat(asArr(r['images'])).concat(asArr(r['files']));
      for (let j = 0; j < rawAtts.length; j++) {
        const a = asRec(rawAtts[j]);
        if (!a) { continue; }
        const mime = strVal(a, 'mime_type') || strVal(a, 'content_type');
        const kind = strVal(a, 'kind') || (mime.startsWith('image/') ? 'image' : (mime.startsWith('audio/') ? 'audio' : 'file'));
        atts.push({
          id: strVal(a, 'id', `att_${i}_${j}`),
          name: strVal(a, 'name') || strVal(a, 'filename', '附件'),
          kind: kind,
          mimeType: mime,
          url: this.resolveImageUrl(strVal(a, 'url') || strVal(a, 'path')),
          sizeBytes: Math.round(numVal(a, 'size', 0))
        });
      }
      out.push({
        id: strVal(r, 'id', `m_${i}`),
        role: role === 'human' ? 'user' : role,
        content: strVal(r, 'content') || strVal(r, 'text'),
        tools: tools,
        attachments: atts,
        choices: [],
        timestamp: strVal(r, 'timestamp') || strVal(r, 'created_at')
      });
    }
    return out;
  }

  async deleteAgentSession(sessionId: string): Promise<boolean> {
    const resp = await this.deleteReq(['message', 'agent', 'sessions', sessionId]);
    return resp.status >= 200 && resp.status < 300;
  }

  async stopAgentSession(sessionId: string): Promise<boolean> {
    const resp = await this.postJson(['message', 'agent', 'sessions', sessionId, 'stop'], '{}');
    return resp.status >= 200 && resp.status < 300;
  }

  async saveAgentSessionDisplay(sessionId: string, payloadJson: string): Promise<boolean> {
    const resp = await this.putJson(['message', 'agent', 'sessions', sessionId, 'display'], payloadJson);
    return resp.status >= 200 && resp.status < 300;
  }

  async uploadAgentAttachment(bytes: Uint8Array, fileName: string, mimeType: string): Promise<MpAgentAttachment | null> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, ['message', 'agent', 'upload']);
    const resp = await this.transport.uploadMultipart(url, this.token, 'file', fileName, mimeType, bytes);
    if (resp.status < 200 || resp.status >= 300) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    const kind = mimeType.startsWith('image/') ? 'image' : (mimeType.startsWith('audio/') ? 'audio' : 'file');
    return {
      id: strVal(r, 'id') || strVal(r, 'file_id', `up_${Date.now()}`),
      name: strVal(r, 'name') || strVal(r, 'filename', fileName),
      kind: kind,
      mimeType: mimeType,
      url: this.resolveImageUrl(strVal(r, 'url') || strVal(r, 'path')),
      sizeBytes: bytes.length
    };
  }

  async triggerAgentCallback(payloadJson: string): Promise<boolean> {
    const resp = await this.postJson(['message', 'agent', 'callback'], payloadJson);
    return resp.status >= 200 && resp.status < 300;
  }

  async streamAgentChatPayload(payloadJson: string, onEvent: (ev: SseEventChunk) => void): Promise<number> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, ['message', 'agent', 'stream']);
    return this.transport.streamSsePost(
      url,
      this.token,
      payloadJson,
      { 'X-MoviePilot-Agent-Interaction': '1' },
      onEvent
    );
  }

  /** 读取单值系统设置（如 `RECOGNIZE_SOURCE` / `SCRAP_SOURCE` / `SEARCH_SOURCE` / `SUBSCRIBE_MODE`）。 */
  async fetchSystemSettingString(key: string, fallback: string = ''): Promise<string> {
    const resp = await this.get(['system', 'setting', key]);
    if (resp.status !== 200) { return fallback; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root || root['value'] === undefined || root['value'] === null) { return fallback; }
    const s = String(root['value']).trim();
    return s.length > 0 ? s : fallback;
  }

  /** 读取布尔型系统设置（如 `SUBSCRIBE_SEARCH` / `SEARCH_MULTIPLE_NAME` / `MEDIASERVER_SYNC`）。 */
  async fetchSystemSettingBool(key: string, fallback: boolean = false): Promise<boolean> {
    const resp = await this.get(['system', 'setting', key]);
    if (resp.status !== 200) { return fallback; }
    const root = unwrapObject(parseJsonSafe(resp.body));
    if (!root || root['value'] === undefined || root['value'] === null) { return fallback; }
    return boolVal(root, 'value', fallback);
  }

  /** 保存单值系统设置（自动序列化字符串或布尔值）。 */
  async saveSystemSettingScalar(key: string, rawJsonLiteral: string): Promise<boolean> {
    const resp = await this.postJson(['system', 'setting', key], rawJsonLiteral);
    const ok = resp.status >= 200 && resp.status < 300;
    if (
      ok && (
        key === 'GLOBAL_IMAGE_CACHE' ||
        key === 'TMDB_IMAGE_DOMAIN' ||
        key === 'BANGUMI_PROXY_ENABLE' ||
        key === 'BANGUMI_IMAGE_DOMAIN'
      )
    ) {
      await this.refreshGlobalImageSettings();
    }
    return ok;
  }

  /** 新增或编辑通知渠道配置（无损维护 `Notifications` 系统数组）。 */
  async saveNotificationChannel(
    name: string,
    channelType: string,
    enabled: boolean,
    originalName: string | null
  ): Promise<boolean> {
    const list = await this.fetchRawSettingArray('Notifications');
    const next: Record<string, Object>[] = [];
    let replaced = false;
    for (let i = 0; i < list.length; i++) {
      const cur = list[i];
      if (originalName !== null && strVal(cur, 'name') === originalName) {
        cur['name'] = name.trim();
        cur['type'] = channelType;
        cur['enabled'] = enabled;
        if (!cur['config']) {
          const emptyCfg: Record<string, Object> = {};
          cur['config'] = emptyCfg;
        }
        next.push(cur);
        replaced = true;
      } else {
        next.push(cur);
      }
    }
    if (!replaced) {
      const obj: Record<string, Object> = {};
      const emptyCfg: Record<string, Object> = {};
      obj['name'] = name.trim();
      obj['type'] = channelType;
      obj['enabled'] = enabled;
      obj['config'] = emptyCfg;
      next.push(obj);
    }
    return this.saveRawSettingArray('Notifications', next);
  }

  /** 删除指定通知渠道。 */
  async deleteNotificationChannel(name: string): Promise<boolean> {
    const list = await this.fetchRawSettingArray('Notifications');
    const next = list.filter((r: Record<string, Object>) => strVal(r, 'name') !== name);
    return this.saveRawSettingArray('Notifications', next);
  }

  /** 读取当前后端 `data.members`，尾斜杠避免认证请求重定向。 */
  private async authorizationMembers(): Promise<Object[]> {
    const resp = await this.get(['authorization'], {}, true);
    if (resp.status !== 200) { throw new Error(`加载渠道授权失败（HTTP ${resp.status}）`); }
    const root = unwrapObject(parseJsonSafe(resp.body));
    return root ? asArr(root['members']) : [];
  }

  /** 展示渠道真实发送者和审批状态，不将拒绝或停用记录归为已授权。 */
  async fetchAuthorizations(): Promise<MpAuthorizationItem[]> {
    const arr = await this.authorizationMembers();
    const out: MpAuthorizationItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const st = strVal(r, 'status');
      out.push({
        id: strVal(r, 'id'),
        channel: strVal(r, 'channel'),
        name: strVal(r, 'display_name') || strVal(r, 'sender_id'),
        status: st,
        createdAt: new Date(numVal(r, 'created_at') * 1000).toISOString(),
        expiresAt: '',
        approved: st === 'approved'
      });
    }
    return out;
  }

  /** 从一次性关联码接口读取绝对到期时间，保留失败状态供界面展示。 */
  async generateAuthorizationCode(): Promise<MpAuthorizationCode> {
    const resp = await this.postJson(['authorization', 'binding'], '{}');
    const root = unwrapObject(parseJsonSafe(resp.body));
    const code = strVal(root, 'code');
    if (resp.status < 200 || resp.status >= 300 || code.length === 0) {
      throw new Error(`生成渠道关联码失败（HTTP ${resp.status}）`);
    }
    return {
      code: code,
      expiresIn: Math.max(0, Math.floor(numVal(root, 'expires_at') - Date.now() / 1000)),
      message: '请在本人渠道私聊中发送 /bind ' + code
    };
  }

  /** 仅更新成员状态，保留原角色与能力，避免审批或停用时重置授权。 */
  private async updateAuthorizationStatus(id: string, status: string): Promise<boolean> {
    const requestBase = this.baseUrl;
    const requestToken = this.token;
    const members = await this.authorizationMembers();
    if (requestBase !== this.baseUrl || requestToken !== this.token) { return false; }
    for (let i = 0; i < members.length; i++) {
      const member = asRec(members[i]);
      if (member && strVal(member, 'id') === id) {
        const payload: Record<string, Object> = {};
        payload['status'] = status;
        payload['role'] = member['role'];
        payload['scopes'] = member['scopes'];
        const resp = await this.putJson(['authorization', id], JSON.stringify(payload));
        const root = asRec(parseJsonSafe(resp.body));
        return resp.status >= 200 && resp.status < 300 && boolVal(root, 'success', false);
      }
    }
    return false;
  }

  /** 通过当前成员状态更新契约批准申请。 */
  async approveAuthorization(idOrCode: string): Promise<boolean> {
    return this.updateAuthorizationStatus(idOrCode, 'approved');
  }

  /** 读取当前实例的匿名版本统计开关与统计服务地址（`GET /api/v1/system/env`）。 */
  async fetchUsageReportingConfig(): Promise<MpUsageReportingConfig | null> {
    try {
      const resp = await this.get(['system', 'env']);
      if (resp.status !== 200) { return null; }
      const root = unwrapObject(parseJsonSafe(resp.body));
      if (!root) { return null; }
      const rawShare = root['USAGE_STATISTIC_SHARE'];
      let enabled = false;
      if (typeof rawShare === 'boolean') {
        enabled = rawShare;
      } else if (typeof rawShare === 'string') {
        enabled = rawShare.trim().toLowerCase() === 'true';
      } else if (typeof rawShare === 'number') {
        enabled = rawShare !== 0;
      }
      const host = strVal(root, 'MP_SERVER_HOST').trim();
      return {
        enabled: enabled,
        serverHost: host.length > 0 ? host : 'https://movie-pilot.org'
      };
    } catch {
      return null;
    }
  }

  /** 撤销对应停用不可变成员记录，后端不提供 DELETE。 */
  async revokeAuthorization(sessionId: string): Promise<boolean> {
    return this.updateAuthorizationStatus(sessionId, 'disabled');
  }

  private danmakuCommentsCache: Map<number, MpDanmakuCachedEntry> = new Map<number, MpDanmakuCachedEntry>();

  private extractDanmakuError(body: string, fallback: string): string {
    const obj = asRec(parseJsonSafe(body));
    const detail = strVal(obj, 'detail').trim();
    if (detail.length > 0) { return detail; }
    const msg = strVal(obj, 'message').trim();
    if (msg.length > 0) { return msg; }
    return fallback;
  }

  private parseDanmakuCandidate(r: Record<string, Object>): MpDanmakuEpisodeCandidate {
    const rawAnimeId = r['anime_id'];
    const epNum = strVal(r, 'episode_number').trim();
    const animeType = strVal(r, 'anime_type').trim();
    return {
      episodeId: Math.round(numVal(r, 'episode_id', 0)),
      animeId: rawAnimeId !== undefined && rawAnimeId !== null ? Math.round(numVal(r, 'anime_id', 0)) : undefined,
      animeTitle: strVal(r, 'anime_title'),
      episodeTitle: strVal(r, 'episode_title'),
      episodeNumber: epNum.length > 0 ? epNum : undefined,
      animeType: animeType.length > 0 ? animeType : undefined,
      shiftMs: Math.round(numVal(r, 'shift_ms', 0))
    };
  }

  private parseDanmakuConfigObj(r: Record<string, Object>): MpDanmakuConfig {
    const statsObj = asRec(r['cache_stats']);
    return {
      enabled: boolVal(r, 'enabled', false),
      apiBaseUrl: strVal(r, 'api_base_url'),
      authMode: strVal(r, 'auth_mode', 'none'),
      appId: strVal(r, 'app_id'),
      hasAppSecret: boolVal(r, 'has_app_secret', false),
      tokenHeader: strVal(r, 'token_header', 'Authorization'),
      tokenPrefix: strVal(r, 'token_prefix', 'Bearer '),
      hasToken: boolVal(r, 'has_token', false),
      withRelated: boolVal(r, 'with_related', true),
      chConvert: Math.round(numVal(r, 'ch_convert', 1)),
      cacheTtlHours: Math.round(numVal(r, 'cache_ttl_hours', 24)),
      cacheMaxMb: Math.round(numVal(r, 'cache_max_mb', 512)),
      timeoutSeconds: Math.round(numVal(r, 'timeout_seconds', 10)),
      useProxy: boolVal(r, 'use_proxy', false),
      verifyTls: boolVal(r, 'verify_tls', true),
      cacheStats: {
        fileCount: Math.round(numVal(statsObj, 'file_count', 0)),
        totalBytes: Math.max(0, Math.round(numVal(statsObj, 'total_bytes', 0))),
        maxMb: Math.round(numVal(statsObj, 'max_mb', 512))
      }
    };
  }

  /** 查询当前实例弹幕服务启用状态（所有登录用户可用）。 */
  async fetchDanmakuStatus(): Promise<boolean> {
    const resp = await this.get(['danmaku', 'status']);
    if (resp.status < 200 || resp.status >= 300) { return false; }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    return boolVal(obj, 'enabled', false);
  }

  /** 管理员读取弹幕服务脱敏配置与磁盘缓存统计。 */
  async fetchDanmakuConfig(): Promise<MpDanmakuConfig> {
    const resp = await this.get(['danmaku', 'config']);
    if (resp.status === 404) {
      throw new Error('当前后端版本暂不支持弹幕服务，请先升级 MoviePilot 后端');
    }
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '读取弹幕服务配置失败'));
    }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    if (!obj) { throw new Error('弹幕配置响应格式异常'); }
    return this.parseDanmakuConfigObj(obj);
  }

  /** 管理员加密更新弹幕服务配置。 */
  async updateDanmakuConfig(payloadJson: string): Promise<MpDanmakuConfig> {
    const resp = await this.putJson(['danmaku', 'config'], payloadJson);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '保存弹幕服务配置失败'));
    }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    if (!obj) { throw new Error('弹幕配置响应格式异常'); }
    return this.parseDanmakuConfigObj(obj);
  }

  /** 管理员测试弹幕上游连通性与鉴权。 */
  async testDanmakuConfig(payloadJson: string): Promise<MpDanmakuConfigTestResult> {
    const resp = await this.postJson(['danmaku', 'config', 'test'], payloadJson);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '测试弹幕服务连接失败'));
    }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    if (!obj) {
      return { ok: false, latencyMs: 0, message: '测试响应格式异常' };
    }
    const rawCode = obj['status_code'];
    return {
      ok: boolVal(obj, 'ok', false),
      latencyMs: Math.round(numVal(obj, 'latency_ms', 0)),
      statusCode: rawCode !== undefined && rawCode !== null ? Math.round(numVal(obj, 'status_code', 0)) : undefined,
      message: strVal(obj, 'message')
    };
  }

  /** 管理员清空服务端弹幕元数据与磁盘缓存。 */
  async clearDanmakuCache(): Promise<MpDanmakuCacheClearResult> {
    const resp = await this.deleteReq(['danmaku', 'cache']);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '清空弹幕缓存失败'));
    }
    this.danmakuCommentsCache.clear();
    const obj = unwrapObject(parseJsonSafe(resp.body));
    return {
      removedFiles: Math.round(numVal(obj, 'removed_files', 0)),
      freedBytes: Math.max(0, Math.round(numVal(obj, 'freed_bytes', 0)))
    };
  }

  /** 匹配当前播放媒体对应的弹幕分集（优先手动绑定，再自动匹配与剧名兜底）。 */
  async matchDanmaku(params: MpDanmakuMatchParams): Promise<MpDanmakuMatchResponse> {
    const payload: Record<string, Object> = {};
    if (params.itemId && params.itemId.trim().length > 0) { payload['item_id'] = params.itemId.trim(); }
    if (params.server && params.server.trim().length > 0) { payload['server'] = params.server.trim(); }
    if (params.title && params.title.trim().length > 0) { payload['title'] = params.title.trim(); }
    if (params.seriesName && params.seriesName.trim().length > 0) { payload['series_name'] = params.seriesName.trim(); }
    if (params.seasonNumber !== undefined) { payload['season_number'] = params.seasonNumber; }
    if (params.episodeNumber !== undefined) { payload['episode_number'] = params.episodeNumber; }
    if (params.year !== undefined && params.year > 0) { payload['year'] = params.year; }
    if (params.tmdbId && params.tmdbId.trim().length > 0) { payload['tmdb_id'] = params.tmdbId.trim(); }
    if (params.fileName && params.fileName.trim().length > 0) { payload['file_name'] = params.fileName.trim(); }
    if (params.fileSize !== undefined && params.fileSize > 0) { payload['file_size'] = params.fileSize; }
    if (params.durationMs !== undefined && params.durationMs > 0) { payload['duration_ms'] = params.durationMs; }

    const resp = await this.postJson(['danmaku', 'match'], JSON.stringify(payload));
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '匹配弹幕失败'));
    }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    if (!obj) {
      return { matched: false, fromBinding: false, shiftMs: 0, candidates: [] };
    }
    const epObj = asRec(obj['episode']);
    const candsRaw = asArr(obj['candidates']);
    const candidates: MpDanmakuEpisodeCandidate[] = [];
    for (let i = 0; i < candsRaw.length; i++) {
      const cr = asRec(candsRaw[i]);
      if (cr) { candidates.push(this.parseDanmakuCandidate(cr)); }
    }
    return {
      matched: boolVal(obj, 'matched', false),
      fromBinding: boolVal(obj, 'from_binding', false),
      shiftMs: Math.round(numVal(obj, 'shift_ms', 0)),
      episode: epObj ? this.parseDanmakuCandidate(epObj) : undefined,
      candidates: candidates
    };
  }

  /** 手动搜剧查询弹幕候选作品与分集列表。 */
  async searchDanmaku(keyword: string, episode: string = ''): Promise<MpDanmakuAnimeSearchItem[]> {
    const q: Record<string, string> = {};
    q['keyword'] = keyword.trim();
    if (episode.trim().length > 0) { q['episode'] = episode.trim(); }
    const resp = await this.get(['danmaku', 'search'], q);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '搜索弹幕剧集失败'));
    }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpDanmakuAnimeSearchItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const epsRaw = asArr(r['episodes']);
      const eps: MpDanmakuEpisodeCandidate[] = [];
      for (let j = 0; j < epsRaw.length; j++) {
        const er = asRec(epsRaw[j]);
        if (er) { eps.push(this.parseDanmakuCandidate(er)); }
      }
      const animeType = strVal(r, 'anime_type').trim();
      const rawCount = r['episode_count'];
      out.push({
        animeId: Math.round(numVal(r, 'anime_id', 0)),
        animeTitle: strVal(r, 'anime_title'),
        animeType: animeType.length > 0 ? animeType : undefined,
        episodeCount: rawCount !== undefined && rawCount !== null ? Math.round(numVal(r, 'episode_count', 0)) : undefined,
        episodes: eps
      });
    }
    return out;
  }

  /** 查询指定作品的完整弹幕分集目录。 */
  async fetchDanmakuBangumi(animeId: number): Promise<MpDanmakuBangumi> {
    const resp = await this.get(['danmaku', 'bangumi', String(Math.round(animeId))]);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '获取分集列表失败'));
    }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    if (!obj) { throw new Error('分集目录响应异常'); }
    const epsRaw = asArr(obj['episodes']);
    const eps: MpDanmakuEpisodeCandidate[] = [];
    for (let i = 0; i < epsRaw.length; i++) {
      const er = asRec(epsRaw[i]);
      if (er) { eps.push(this.parseDanmakuCandidate(er)); }
    }
    const animeType = strVal(obj, 'anime_type').trim();
    return {
      animeId: Math.round(numVal(obj, 'anime_id', animeId)),
      animeTitle: strVal(obj, 'anime_title'),
      animeType: animeType.length > 0 ? animeType : undefined,
      episodes: eps
    };
  }

  /** 拉取单集归一化紧凑弹幕载荷，自动携带 `If-None-Match` 协商 304 缓存命中。 */
  async fetchDanmakuComments(episodeId: number, forceRefresh: boolean = false): Promise<MpDanmakuCommentsRaw> {
    const epKey = Math.round(episodeId);
    const cached = forceRefresh ? undefined : this.danmakuCommentsCache.get(epKey);
    const q: Record<string, string> = {};
    if (forceRefresh) { q['force_refresh'] = 'true'; }
    let extraHeaders: Record<string, string> | undefined = undefined;
    if (cached && cached.etag.length > 0) {
      extraHeaders = {};
      extraHeaders['If-None-Match'] = cached.etag;
    }
    const resp = await this.get(['danmaku', 'comments', String(epKey)], q, false, extraHeaders);
    if (resp.status === 304 && cached) {
      return { rawJson: cached.rawJson, etag: cached.etag, fromCache: true };
    }
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '拉取弹幕失败'));
    }
    if (resp.etag && resp.etag.length > 0) {
      if (this.danmakuCommentsCache.size >= 12) {
        this.danmakuCommentsCache.clear();
      }
      this.danmakuCommentsCache.set(epKey, { etag: resp.etag, rawJson: resp.body });
    }
    return { rawJson: resp.body, etag: resp.etag, fromCache: false };
  }

  /** 持久化保存手动纠偏绑定与时间偏移至服务端，一端纠偏全端共享。 */
  async saveDanmakuBinding(params: MpDanmakuSaveBindingParams): Promise<MpDanmakuEpisodeCandidate> {
    const payload: Record<string, Object> = {};
    if (params.server && params.server.trim().length > 0) { payload['server'] = params.server.trim(); }
    if (params.itemId && params.itemId.trim().length > 0) { payload['item_id'] = params.itemId.trim(); }
    if (params.tmdbId && params.tmdbId.trim().length > 0) { payload['tmdb_id'] = params.tmdbId.trim(); }
    if (params.seasonNumber !== undefined) { payload['season_number'] = params.seasonNumber; }
    if (params.episodeNumber !== undefined) { payload['episode_number'] = params.episodeNumber; }
    payload['episode_id'] = Math.round(params.episodeId);
    if (params.animeId !== undefined) { payload['anime_id'] = Math.round(params.animeId); }
    payload['anime_title'] = params.animeTitle;
    payload['episode_title'] = params.episodeTitle;
    payload['shift_ms'] = Math.round(params.shiftMs);

    const resp = await this.putJson(['danmaku', 'bindings'], JSON.stringify(payload));
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '保存弹幕绑定失败'));
    }
    const obj = unwrapObject(parseJsonSafe(resp.body));
    if (obj) { return this.parseDanmakuCandidate(obj); }
    return {
      episodeId: params.episodeId,
      animeId: params.animeId,
      animeTitle: params.animeTitle,
      episodeTitle: params.episodeTitle,
      shiftMs: params.shiftMs
    };
  }

  /** 删除媒体条目的手动弹幕绑定，恢复自动匹配。 */
  async deleteDanmakuBinding(params: MpDanmakuDeleteBindingParams): Promise<boolean> {
    const q: Record<string, string> = {};
    if (params.server && params.server.trim().length > 0) { q['server'] = params.server.trim(); }
    if (params.itemId && params.itemId.trim().length > 0) { q['item_id'] = params.itemId.trim(); }
    if (params.tmdbId && params.tmdbId.trim().length > 0) { q['tmdb_id'] = params.tmdbId.trim(); }
    if (params.seasonNumber !== undefined) { q['season_number'] = String(params.seasonNumber); }
    if (params.episodeNumber !== undefined) { q['episode_number'] = String(params.episodeNumber); }
    const resp = await this.deleteReq(['danmaku', 'bindings'], q);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(this.extractDanmakuError(resp.body, '解除弹幕绑定失败'));
    }
    return true;
  }
}
