import { RustCoreBridge } from '../bridge/RustCoreBridge';
import { NativeRcpTransport, NativeHttpResponse, SseEventChunk } from '../network/NativeRcpTransport';

export interface MpLoginResult {
  success: boolean;
  requiresOtp: boolean;
  token: string;
  userName: string;
  isSuperuser: boolean;
  avatar: string;
  message: string;
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

export interface MpDashboardStats {
  movieCount: number;
  tvCount: number;
  episodeCount: number;
  userCount: number;
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
}

export interface MpCommunityState {
  githubLogin: string;
  earnedCount: number;
  totalCount: number;
  medals: MpCommunityMedal[];
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
}

export interface MpWorkflowItem {
  id: number;
  name: string;
  description: string;
  timer: string;
  state: string;
  runCount: number;
  actionCount: number;
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

export interface MpVideoStreamInfo {
  itemId: string;
  server: string;
  title: string;
  contentUrl: string;
  mediaType: string;
  resumePositionMs: number;
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

interface SubscribeCreateBody {
  name: string;
  type: string;
  year: string;
  tmdbid?: number;
  doubanid?: string;
}

interface SubscribeUpdateBody {
  id: number;
  state: string;
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
  baseUrl: string = '';
  token: string = '';
  userName: string = '';
  isSuperuser: boolean = false;
  userAvatar: string = '';

  static shared(): MoviePilotRepository {
    if (!MoviePilotRepository.instance) {
      MoviePilotRepository.instance = new MoviePilotRepository();
    }
    return MoviePilotRepository.instance;
  }

  configure(baseUrl: string, token: string, userName: string, isSuperuser: boolean, avatar: string = ''): void {
    this.baseUrl = RustCoreBridge.normalizeServerAddress(baseUrl);
    this.token = token;
    this.userName = userName;
    this.isSuperuser = isSuperuser;
    if (avatar.length > 0) {
      this.userAvatar = avatar;
    }
  }

  clearSession(): void {
    this.token = '';
    this.userAvatar = '';
    this.transport.clearCookies();
  }

  /** 将 TMDB/豆瓣/Bangumi/媒体服务器/本地相对路径解析为可靠可加载图片 URL（自动走 MoviePilot 图片代理）。 */
  resolveImageUrl(rawPath: string, useCookies: boolean = false): string {
    const clean = rawPath.trim();
    if (!clean || clean.toLowerCase() === 'null' || clean.toLowerCase() === 'none') { return ''; }
    if (clean.startsWith('data:image/')) { return clean; }
    if (!this.baseUrl) { return clean; }
    if (clean.startsWith(this.baseUrl)) { return clean; }
    if (clean.startsWith('/api/')) {
      return `${this.baseUrl}${clean}`;
    }
    const normalized = clean.replace('image.tmdb.org/t/p/original/', 'image.tmdb.org/t/p/w780/');
    const cookieQuery = useCookies ? '&use_cookies=true' : '';
    if (normalized.startsWith('/')) {
      const tmdbFull = `https://image.tmdb.org/t/p/w500${normalized}`;
      return `${this.baseUrl}/api/v1/system/img/0?imgurl=${encodeURIComponent(tmdbFull)}&cache=true${cookieQuery}`;
    }
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      if (normalized.includes('127.0.0.1') || normalized.includes('localhost')) {
        return normalized;
      }
      return `${this.baseUrl}/api/v1/system/img/0?imgurl=${encodeURIComponent(normalized)}&cache=true${cookieQuery}`;
    }
    return `${this.baseUrl}/${normalized}`;
  }

  async get(segments: string[], query: Record<string, string> = {}, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, query, trailingSlash);
    return this.transport.execute(url, 'GET', this.token);
  }

  async postJson(segments: string[], payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, {}, trailingSlash);
    return this.transport.execute(url, 'POST', this.token, payload, 'application/json');
  }

  async postJsonQuery(segments: string[], query: Record<string, string>, payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, query, trailingSlash);
    return this.transport.execute(url, 'POST', this.token, payload, 'application/json');
  }

  async putJson(segments: string[], payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, {}, trailingSlash);
    return this.transport.execute(url, 'PUT', this.token, payload, 'application/json');
  }

  async deleteReq(segments: string[], query: Record<string, string> = {}, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, query, trailingSlash);
    return this.transport.execute(url, 'DELETE', this.token);
  }

  /** 登录并预热当前用户头像与服务端 Session Cookie。 */
  async login(serverUrl: string, username: string, password: string, otpCode: string = ''): Promise<MpLoginResult> {
    const cleanUrl = RustCoreBridge.normalizeServerAddress(serverUrl);
    this.baseUrl = cleanUrl;
    const url = RustCoreBridge.buildV3EndpointUrl(cleanUrl, ['login', 'access-token']);
    const form = `username=${encodeURIComponent(username.trim())}&password=${encodeURIComponent(password)}&otp_password=${encodeURIComponent(otpCode.trim())}`;
    const resp = await this.transport.execute(url, 'POST', '', form, 'application/x-www-form-urlencoded');
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
    if (token.length === 0) {
      return {
        success: false, requiresOtp: false, token: '', userName: name, isSuperuser: su, avatar: '',
        message: '服务器未返回有效访问令牌'
      };
    }
    this.configure(cleanUrl, token, name, su, avatar);
    await this.hydrateSession();
    return {
      success: true, requiresOtp: false, token: token, userName: this.userName,
      isSuperuser: this.isSuperuser, avatar: this.userAvatar, message: ''
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
        }
      }
    } catch {
      // ignore
    }
    try {
      await this.get(['media', 'source']);
    } catch {
      // ignore
    }
  }

  private parseMediaItem(raw: Object, fallbackSource: string = 'themoviedb'): MpMediaItem | null {
    const r = asRec(raw);
    if (!r) { return null; }
    const tmdbId = strVal(r, 'tmdb_id');
    const doubanId = strVal(r, 'douban_id');
    const bangumiId = strVal(r, 'bangumi_id');
    const mediaId = strVal(r, 'mediaid_prefix')
      ? `${strVal(r, 'mediaid_prefix')}:${strVal(r, 'media_id')}`
      : (tmdbId ? `tmdb:${tmdbId}` : (doubanId ? `douban:${doubanId}` : (bangumiId ? `bangumi:${bangumiId}` : strVal(r, 'id'))));
    const posterRaw = strVal(r, 'poster_path') || strVal(r, 'poster') || strVal(r, 'image') || strVal(r, 'thumb') || strVal(r, 'backdrop_path');
    const backdropRaw = strVal(r, 'backdrop_path') || strVal(r, 'backdrop') || strVal(r, 'image') || strVal(r, 'thumb') || posterRaw;
    const useCookies = boolVal(r, 'use_cookies', false);
    const rawPercent = numVal(r, 'percent', 0);
    return {
      id: mediaId || strVal(r, 'title'),
      mediaId: mediaId,
      tmdbId: tmdbId,
      doubanId: doubanId,
      title: strVal(r, 'title') || strVal(r, 'name') || '未命名影片',
      enTitle: strVal(r, 'en_title') || strVal(r, 'original_title'),
      year: strVal(r, 'year'),
      type: strVal(r, 'type', '电影'),
      overview: strVal(r, 'overview'),
      vote: numVal(r, 'vote_average', numVal(r, 'rating', numVal(r, 'vote', 0))),
      posterUrl: this.resolveImageUrl(posterRaw, useCookies),
      backdropUrl: this.resolveImageUrl(backdropRaw, useCookies),
      logoUrl: this.resolveImageUrl(strVal(r, 'logo_path'), useCookies),
      source: strVal(r, 'source', fallbackSource),
      inLibrary: boolVal(r, 'in_library', false) || strVal(r, 'item_type').length > 0,
      subtitle: strVal(r, 'subtitle'),
      percent: Math.round(rawPercent),
      serverName: strVal(r, 'server'),
      playUrl: strVal(r, 'link')
    };
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
          out.push(it);
        }
      }
    }
    return out;
  }

  async fetchRecentlyAdded(): Promise<MpMediaItem[]> {
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
          out.push(it);
        }
      }
    }
    return out;
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
      segments = ['recommend', 'music_netease_toplist'];
    }
    const resp = await this.get(segments, q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], sourceKey);
      if (it) { out.push(it); }
    }
    return out;
  }

  async searchMedia(keyword: string, kind: string = 'media'): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    q['title'] = keyword;
    const segments: string[] = kind === 'library' ? ['mediaserver', 'search'] : ['media', 'search'];
    const resp = await this.get(segments, q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], kind);
      if (it) { out.push(it); }
    }
    return out;
  }

  async fetchMediaCredits(tmdbId: string, mediaType: string): Promise<MpCastMember[]> {
    if (!tmdbId) { return []; }
    const resp = await this.get(['tmdb', 'credits', tmdbId, mediaType || '电影']);
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
        profileUrl: this.resolveImageUrl(strVal(r, 'profile_path'))
      });
    }
    return out;
  }

  async fetchMediaSeasons(tmdbId: string): Promise<MpSeasonInfo[]> {
    if (!tmdbId) { return []; }
    const resp = await this.get(['tmdb', 'seasons', tmdbId]);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpSeasonInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        seasonNumber: numVal(r, 'season_number', i + 1),
        name: strVal(r, 'name', `第 ${i + 1} 季`),
        episodeCount: numVal(r, 'episode_count', 0),
        airDate: strVal(r, 'air_date'),
        posterUrl: this.resolveImageUrl(strVal(r, 'poster_path')),
        overview: strVal(r, 'overview')
      });
    }
    return out;
  }

  async addSubscribe(item: MpMediaItem): Promise<boolean> {
    const body: SubscribeCreateBody = {
      name: item.title,
      type: item.type || '电影',
      year: item.year
    };
    if (item.tmdbId.length > 0 && Number.isFinite(Number(item.tmdbId))) {
      body.tmdbid = Number(item.tmdbId);
    }
    if (item.doubanId.length > 0) {
      body.doubanid = item.doubanId;
    }
    const resp = await this.postJson(['subscribe'], JSON.stringify(body), true);
    return resp.status >= 200 && resp.status < 300;
  }

  async fetchDashboardStats(): Promise<MpDashboardStats> {
    const stats: MpDashboardStats = {
      movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0,
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
    for (let i = 0; i < tr.length; i++) {
      counts.push(Number(tr[i]) || 0);
    }
    stats.transferCounts = counts;
    const sched = unwrapArray(parseJsonSafe(results[5].body));
    stats.scheduleCount = sched.length;
    return stats;
  }

  /** 拉取真实 `/api/v1/github/community` 社区勋章并映射到 `rawfile/community_medals/` 73 枚真实雕刻资源。 */
  async fetchCommunityMedals(): Promise<MpCommunityState> {
    const resp = await this.get(['github', 'community']);
    const out: MpCommunityState = { githubLogin: this.userName || 'MoviePilot', earnedCount: 0, totalCount: 7, medals: [] };
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
        metricLabel: strVal(m, 'progress_text') || strVal(m, 'value_text') || (isTiered ? `T${tier}` : '已获得')
      });
      if (earned) { out.earnedCount++; }
    }
    out.totalCount = medals.length > 0 ? medals.length : 7;
    out.medals = medals;
    return out;
  }

  async fetchSubscriptions(): Promise<MpSubscribeItem[]> {
    const resp = await this.get(['subscribe'], {}, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpSubscribeItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
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
      out.push({
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
        interval: numVal(r, 'interval', 0),
        rawJson: JSON.stringify(r)
      });
    }
    return out;
  }

  async toggleSubscribeState(sub: MpSubscribeItem): Promise<boolean> {
    const next = sub.state === 'S' ? 'R' : 'S';
    const body: SubscribeUpdateBody = { id: sub.id, state: next };
    const resp = await this.putJson(['subscribe', 'status', String(sub.id)], JSON.stringify(body));
    return resp.status >= 200 && resp.status < 300;
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
      const domain = strVal(r, 'domain');
      const ud = dataByDomain.get(domain.toLowerCase()) ?? null;
      out.push({
        id: numVal(r, 'id'),
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
        iconDataUri: '',
        priority: numVal(r, 'pri', i + 1),
        rss: strVal(r, 'rss'),
        cookie: strVal(r, 'cookie'),
        ua: strVal(r, 'ua'),
        proxy: boolVal(r, 'proxy', false),
        render: boolVal(r, 'render', false),
        rawJson: JSON.stringify(r)
      });
    }
    return out;
  }

  async fetchCachedResources(): Promise<MpResourceItem[]> {
    const resp = await this.get(['search', 'last']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpResourceItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const ti = asRec(r['torrent_info']) ?? r;
      const mi = asRec(r['meta_info']);
      out.push({
        title: strVal(ti, 'title') || strVal(r, 'title'),
        description: strVal(ti, 'description'),
        siteName: strVal(ti, 'site_name', '未知站点'),
        sizeBytes: Math.round(numVal(ti, 'size', 0)),
        seeders: Math.round(numVal(ti, 'seeders', 0)),
        peers: Math.round(numVal(ti, 'peers', 0)),
        resolution: strVal(mi, 'resource_pix') || strVal(ti, 'resource_pix'),
        resourceType: strVal(mi, 'resource_type') || strVal(ti, 'resource_type'),
        videoEncode: strVal(mi, 'video_encode'),
        volumeFactor: strVal(ti, 'volume_factor'),
        enclosure: strVal(ti, 'enclosure'),
        pageUrl: strVal(ti, 'page_url'),
        siteId: Math.round(numVal(ti, 'site', 0)),
        pubdate: strVal(ti, 'pubdate'),
        rawJson: JSON.stringify(r)
      });
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

  async fetchStorageFiles(storage: string = 'local', path: string = '/'): Promise<MpStorageFile[]> {
    const payload = `{"storage":"${storage}","type":"dir","path":"${path}","name":""}`;
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
        posterUrl: this.resolveImageUrl(strVal(r, 'image'))
      });
    }
    return out;
  }

  async fetchWorkflows(): Promise<MpWorkflowItem[]> {
    const resp = await this.get(['workflow'], {}, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpWorkflowItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const actions = asArr(r['actions']);
      out.push({
        id: numVal(r, 'id'),
        name: strVal(r, 'name'),
        description: strVal(r, 'description'),
        timer: strVal(r, 'timer'),
        state: strVal(r, 'state', 'W'),
        runCount: numVal(r, 'run_count', 0),
        actionCount: actions.length
      });
    }
    return out;
  }

  async fetchPlugins(state: string = 'installed'): Promise<MpPluginItem[]> {
    const q: Record<string, string> = {};
    q['state'] = state;
    const resp = await this.get(['plugin'], q, true);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpPluginItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: strVal(r, 'id'),
        pluginName: strVal(r, 'plugin_name') || strVal(r, 'id'),
        pluginDesc: strVal(r, 'plugin_desc'),
        pluginVersion: strVal(r, 'plugin_version'),
        pluginAuthor: strVal(r, 'plugin_author'),
        installed: boolVal(r, 'installed', state === 'installed'),
        state: boolVal(r, 'state', false),
        hasPage: boolVal(r, 'has_page', false),
        iconUrl: this.resolveImageUrl(strVal(r, 'plugin_icon')),
        renderMode: strVal(r, 'render_mode', 'vuetify')
      });
    }
    return out;
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
    const servers = await this.fetchMediaServerClients();
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
          imageUrl: this.resolveImageUrl(rawImg, useCookies),
          itemCount: Number.isFinite(parsedCount) && parsedCount >= 0 ? Math.round(parsedCount) : undefined
        });
      }
    }
    return out;
  }

  async fetchMediaServerBrowse(serverName: string, libraryId: string): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    if (serverName.length > 0) { q['server'] = serverName; }
    if (libraryId.length > 0) { q['library_id'] = libraryId; }
    q['page'] = '1';
    q['count'] = '36';
    const resp = await this.get(['mediaserver', 'browse'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], 'mediaserver');
      if (it) {
        it.inLibrary = true;
        out.push(it);
      }
    }
    return out;
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
        vote: numVal(r, 'vote', 0)
      });
    }
    return out;
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

  async fetchMessages(): Promise<MpMessageItem[]> {
    const q: Record<string, string> = {};
    q['page'] = '1';
    q['size'] = '25';
    const resp = await this.get(['message', 'web'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMessageItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      out.push({
        id: strVal(r, 'id', String(i)),
        title: strVal(r, 'title', '系统通知'),
        text: strVal(r, 'text'),
        date: strVal(r, 'reg_time') || strVal(r, 'date'),
        action: numVal(r, 'action', 0),
        image: this.resolveImageUrl(strVal(r, 'image') || strVal(r, 'poster'))
      });
    }
    return out;
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

  async fetchLiveLogs(): Promise<string[]> {
    const q: Record<string, string> = {};
    q['length'] = '60';
    const resp = await this.get(['system', 'logging'], q);
    if (resp.status !== 200) { return []; }
    return resp.body.split('\n').filter((line: string) => line.trim().length > 0).slice(-50);
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

  /** 音乐榜单与专辑流（`douban` / `weekly` / `hot` / `new`）。 */
  async fetchMusicFeed(feed: string = 'douban', page: number = 1): Promise<MpMusicAlbum[]> {
    const q: Record<string, string> = {};
    q['page'] = String(page);
    let segs: string[] = ['recommend', 'music_douban'];
    if (feed === 'weekly') {
      segs = ['recommend', 'music_weekly'];
    } else if (feed === 'hot') {
      segs = ['music', 'explore'];
      q['media_source'] = 'musicbrainz';
      q['sort'] = 'popular';
    } else if (feed === 'new') {
      segs = ['music', 'explore'];
      q['media_source'] = 'musicbrainz';
      q['sort'] = 'latest';
    }
    const resp = await this.get(segs, q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMusicAlbum[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const artistsArr = asArr(r['artists']);
      const firstArtist = artistsArr.length > 0 ? String(artistsArr[0] ?? '') : '';
      out.push({
        id: strVal(r, 'media_id') || strVal(r, 'id') || strVal(r, 'douban_id') || `music_${i}`,
        title: strVal(r, 'title') || strVal(r, 'name'),
        artist: strVal(r, 'artist') || firstArtist || strVal(r, 'singer') || strVal(r, 'subtitle'),
        year: strVal(r, 'year'),
        coverUrl: this.resolveImageUrl(strVal(r, 'poster_path') || strVal(r, 'cover') || strVal(r, 'image')),
        rating: numVal(r, 'vote_average', numVal(r, 'rating', 0)),
        source: feed
      });
    }
    return out;
  }

  /** 媒体库精细浏览（支持关键字、排序与类型过滤）。 */
  async fetchMediaServerBrowseFiltered(
    serverName: string,
    libraryId: string,
    keyword: string = '',
    sortBy: string = 'DateCreated',
    genre: string = '',
    page: number = 1
  ): Promise<MpMediaItem[]> {
    const q: Record<string, string> = {};
    if (serverName.length > 0) { q['server'] = serverName; }
    if (libraryId.length > 0) { q['library_id'] = libraryId; }
    if (keyword.trim().length > 0) { q['keyword'] = keyword.trim(); }
    if (sortBy.length > 0) { q['sort_by'] = sortBy; }
    if (genre.length > 0) { q['genre'] = genre; }
    q['page'] = String(page);
    q['count'] = '48';
    const resp = await this.get(['mediaserver', 'browse'], q);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const it = this.parseMediaItem(arr[i], 'mediaserver');
      if (it) {
        it.inLibrary = true;
        out.push(it);
      }
    }
    return out;
  }

  /** 查询媒体播放流地址。 */
  async fetchVideoStreamInfo(itemId: string, server: string = ''): Promise<MpVideoStreamInfo | null> {
    if (!itemId) { return null; }
    const q: Record<string, string> = {};
    if (server.length > 0) { q['server'] = server; }
    const resp = await this.get(['mediaserver', 'play', itemId], q);
    if (resp.status !== 200) { return null; }
    const r = unwrapObject(parseJsonSafe(resp.body));
    if (!r) { return null; }
    const rawUrl = strVal(r, 'url') || strVal(r, 'stream_url') || strVal(r, 'content_url');
    if (!rawUrl) { return null; }
    const fullUrl = rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
      ? rawUrl
      : `${this.baseUrl}${rawUrl.startsWith('/') ? '' : '/'}${rawUrl}`;
    return {
      itemId: strVal(r, 'item_id', itemId),
      server: strVal(r, 'server', server),
      title: strVal(r, 'title'),
      contentUrl: fullUrl,
      mediaType: strVal(r, 'media_type', 'video'),
      resumePositionMs: Math.round(numVal(r, 'resume_position_ms', 0))
    };
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
      const ti = asRec(r['torrent_info']) ?? r;
      const mi = asRec(r['meta_info']);
      const sid = Math.round(numVal(ti, 'site', 0));
      if (siteIds.length > 1 && sid > 0 && !siteIds.includes(sid)) { continue; }
      out.push({
        title: strVal(ti, 'title') || strVal(r, 'title'),
        description: strVal(ti, 'description'),
        siteName: strVal(ti, 'site_name', '未知站点'),
        sizeBytes: Math.round(numVal(ti, 'size', 0)),
        seeders: Math.round(numVal(ti, 'seeders', 0)),
        peers: Math.round(numVal(ti, 'peers', 0)),
        resolution: strVal(mi, 'resource_pix') || strVal(ti, 'resource_pix'),
        resourceType: strVal(mi, 'resource_type') || strVal(ti, 'resource_type'),
        videoEncode: strVal(mi, 'video_encode'),
        volumeFactor: strVal(ti, 'volume_factor'),
        enclosure: strVal(ti, 'enclosure'),
        pageUrl: strVal(ti, 'page_url'),
        siteId: sid,
        pubdate: strVal(ti, 'pubdate'),
        rawJson: JSON.stringify(r)
      });
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
}
