import { RustCoreBridge } from '../bridge/RustCoreBridge';
import { NativeRcpTransport, NativeHttpResponse } from '../network/NativeRcpTransport';

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
    if (!clean) { return ''; }
    if (clean.startsWith('data:image/')) { return clean; }
    if (!this.baseUrl) { return clean; }
    if (clean.startsWith(this.baseUrl)) { return clean; }
    if (clean.startsWith('/api/')) {
      return `${this.baseUrl}${clean}`;
    }
    const cookieFlag = useCookies ? '1' : '0';
    if (clean.startsWith('/')) {
      const tmdbFull = `https://image.tmdb.org/t/p/w500${clean}`;
      return `${this.baseUrl}/api/v1/system/img/${cookieFlag}?imgurl=${encodeURIComponent(tmdbFull)}`;
    }
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      if (clean.includes('127.0.0.1') || clean.includes('localhost')) {
        return clean;
      }
      return `${this.baseUrl}/api/v1/system/img/${cookieFlag}?imgurl=${encodeURIComponent(clean)}`;
    }
    return `${this.baseUrl}/${clean}`;
  }

  async get(segments: string[], query: Record<string, string> = {}, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, query, trailingSlash);
    return this.transport.execute(url, 'GET', this.token);
  }

  async postJson(segments: string[], payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, {}, trailingSlash);
    return this.transport.execute(url, 'POST', this.token, payload, 'application/json');
  }

  async putJson(segments: string[], payload: string, trailingSlash: boolean = false): Promise<NativeHttpResponse> {
    const url = RustCoreBridge.buildV3EndpointUrl(this.baseUrl, segments, {}, trailingSlash);
    return this.transport.execute(url, 'PUT', this.token, payload, 'application/json');
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

  async fetchContinueWatching(): Promise<MpMediaItem[]> {
    const resp = await this.get(['mediaserver', 'playing']);
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

  async fetchRecentlyAdded(): Promise<MpMediaItem[]> {
    const resp = await this.get(['mediaserver', 'latest']);
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
    const mem = parseJsonSafe(results[3].body);
    if (Array.isArray(mem) && (mem as Object[]).length >= 2) {
      const mArr = mem as Object[];
      stats.memoryUsedBytes = Number(mArr[0]) || 0;
      stats.memoryPercent = Number(mArr[1]) || 0;
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
    if (userRec) {
      out.githubLogin = strVal(userRec, 'login', out.githubLogin);
    }
    const rawMedals = asArr(root['medals']);
    const medals: MpCommunityMedal[] = [];
    for (let i = 0; i < rawMedals.length; i++) {
      const m = asRec(rawMedals[i]);
      if (!m) { continue; }
      const id = strVal(m, 'id');
      const earned = boolVal(m, 'earned', false);
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
      const dateStr = strVal(m, 'earned_at') || strVal(m, 'date') || '2026-11';
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
        resolution: strVal(r, 'resolution')
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
        iconDataUri: ''
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
        pageUrl: strVal(ti, 'page_url')
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
    const resp = await this.get(['mediaserver', 'library']);
    if (resp.status !== 200) { return []; }
    const arr = unwrapArray(parseJsonSafe(resp.body));
    const out: MpMediaServerLibrary[] = [];
    for (let i = 0; i < arr.length; i++) {
      const r = asRec(arr[i]);
      if (!r) { continue; }
      const useCookies = boolVal(r, 'use_cookies', false);
      const rawImg = strVal(r, 'image') || strVal(r, 'poster') || strVal(r, 'thumb');
      out.push({
        id: strVal(r, 'id', String(i)),
        name: strVal(r, 'name', '媒体库'),
        type: strVal(r, 'type', 'movie'),
        serverName: strVal(r, 'server'),
        imageUrl: this.resolveImageUrl(rawImg, useCookies)
      });
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
}
