package com.moviepilot.rustbridge

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

/** 用户登录身份与权限快照。 */
@Serializable
data class UserIdentity(
    val id: Int = 0,
    val name: String = "",
    val email: String = "",
    @SerialName("is_superuser") val isSuperuser: Boolean = false,
    @SerialName("is_active") val isActive: Boolean = true,
    @SerialName("is_otp") val isOtp: Boolean = false,
    val avatar: String? = null,
    val permissions: Map<String, JsonElement> = emptyMap(),
)

/** 影视/剧集/音乐通用卡片条目。 */
@Serializable
data class MediaCardItem(
    val title: String = "",
    val year: String = "",
    val type: String = "电影",
    val overview: String = "",
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("vote_average") val voteAverage: Double = 0.0,
    val source: String = "themoviedb",
    @SerialName("tmdb_id") val tmdbId: Int? = null,
    @SerialName("douban_id") val doubanId: String? = null,
    @SerialName("bangumi_id") val bangumiId: Int? = null,
    @SerialName("mediaid_prefix") val mediaIdPrefix: String? = null,
    @SerialName("media_id") val mediaId: String? = null,
    @SerialName("logo_path") val logoPath: String? = null,
    val genres: List<String> = emptyList(),
    val runtime: Int? = null,
    val numberOfSeasons: Int? = null,
    val contentRating: String? = null,
    val releaseDate: String? = null,
    val inLibrary: Boolean = false,
    val progressPercent: Int? = null,
    val subtitle: String? = null,
    val popularityCount: Int = 0,
    val shareUser: String? = null,
    val shareComment: String? = null,
) {
    /** 稳定业务标识。 */
    val resolvedId: String
        get() = mediaId ?: tmdbId?.toString() ?: doubanId ?: bangumiId?.toString() ?: title
}

/** 媒体服务器继续观看条目。 */
@Serializable
data class ContinueWatchingItem(
    val id: String = "",
    val title: String = "",
    val subtitle: String = "",
    val image: String? = null,
    val percent: Int = 0,
    val server: String = "",
    val type: String = "电视剧",
    val link: String? = null,
)

/** 完整订阅条目（覆盖 iOS 订阅列表 + 订阅编辑 Sheet 全部字段）。 */
@Serializable
data class SubscribeItemDto(
    val id: Int = 0,
    val name: String = "",
    val year: String = "",
    val type: String = "电影",
    val season: Int? = null,
    val poster: String? = null,
    val backdrop: String? = null,
    val vote: Double = 0.0,
    val state: String = "R",
    @SerialName("total_episode") val totalEpisode: Int = 0,
    @SerialName("lack_episode") val lackEpisode: Int = 0,
    @SerialName("media_source") val mediaSource: String = "themoviedb",
    @SerialName("media_id") val mediaId: String = "",
    val quality: String = "",
    val resolution: String = "",
    val effect: String = "",
    val bestVersion: Boolean = false,
    val sites: List<Int> = emptyList(),
    val filterGroups: List<String> = emptyList(),
    val searchImdbId: Boolean = false,
    val searchInterval: Int? = null,
    val keyword: String = "",
    val savePath: String = "",
    val include: String = "",
    val exclude: String = "",
    val mediaCategory: String = "",
    val customWords: String = "",
    val date: String = "",
    val username: String = "",
    val description: String = "",
)

/** 正在下载任务条目。 */
@Serializable
data class DownloadTaskDto(
    val hash: String = "",
    val downloader: String = "qBittorrent",
    val title: String = "",
    val name: String = "",
    val year: String = "",
    @SerialName("season_episode") val seasonEpisode: String = "",
    @SerialName("site_name") val siteName: String = "",
    val size: Double = 0.0,
    val progress: Double = 0.0,
    val state: String = "downloading",
    val upspeed: String = "0 B/s",
    val dlspeed: String = "0 B/s",
    @SerialName("left_time") val leftTime: String = "",
    val poster: String? = null,
)

/** 整理历史记录。 */
@Serializable
data class TransferHistoryDto(
    val id: Int = 0,
    val title: String = "",
    val type: String = "电影",
    val year: String = "",
    val seasons: String = "",
    val episodes: String = "",
    val status: Boolean = true,
    val mode: String = "copy",
    val date: String = "",
    val errmsg: String? = null,
    val src: String = "",
    val dest: String = "",
    val srcStorage: String = "local",
    val destStorage: String = "local",
    val sizeBytes: Long = 0L,
    val image: String? = null,
)

/** 多存储文件条目。 */
@Serializable
data class StorageFileDto(
    val storage: String = "local",
    val type: String = "file",
    val path: String = "/",
    val name: String = "",
    val extension: String? = null,
    val size: Long = 0L,
    val modifyTime: String = "",
)

/** 仪表盘核心统计。 */
@Serializable
data class DashboardStatsDto(
    @SerialName("movie_count") val movieCount: Int = 0,
    @SerialName("tv_count") val tvCount: Int = 0,
    @SerialName("episode_count") val episodeCount: Int? = null,
    @SerialName("music_count") val musicCount: Int = 0,
    @SerialName("movie_count_month") val movieCountMonth: Int = 0,
    @SerialName("tv_count_month") val tvCountMonth: Int = 0,
    @SerialName("episode_count_month") val episodeCountMonth: Int = 0,
    @SerialName("music_count_month") val musicCountMonth: Int = 0,
    val usedBytes: Double = 0.0,
    val totalBytes: Double = 0.0,
    val downloadSpeed: Double = 0.0,
    val uploadSpeed: Double = 0.0,
    val totalDownloadBytes: Double = 0.0,
    val cpuPercent: Double = 0.0,
    val memoryPercent: Double = 0.0,
    val transfer7Days: List<Int> = emptyList(),
)

/** 站点单日/实时流量统计记录（用于站点列表 + 站点数据详情页 13 天历史面积图）。 */
@Serializable
data class SiteUserDataPointDto(
    val domain: String = "",
    val name: String = "",
    val username: String = "",
    val userLevel: String = "",
    val joinAt: String = "",
    val uploadBytes: Double = 0.0,
    val downloadBytes: Double = 0.0,
    val ratio: Double = 0.0,
    val seedingCount: Int = 0,
    val seedingSizeBytes: Double = 0.0,
    val bonus: Double = 0.0,
    val updatedDay: String = "",
    val updatedTime: String = "",
)

/** 站点管理条目（含关联的实时上下行流量、分享率、做种数、魔力值与真实站点图标）。 */
@Serializable
data class SiteItemDto(
    val id: Int = 0,
    val name: String = "",
    val domain: String = "",
    val url: String = "",
    val pri: Int = 0,
    @SerialName("is_active") val isActive: Boolean = true,
    val uploadBytes: Double = 0.0,
    val downloadBytes: Double = 0.0,
    val ratio: Double = 0.0,
    val seedingCount: Int = 0,
    val seedingSizeBytes: Double = 0.0,
    val bonus: Double = 0.0,
    val userLevel: String = "",
    val username: String = "",
    val joinAt: String = "",
    val updatedDay: String = "",
    val iconUrl: String? = null,
)

/** 系统配置项：下载器 / 媒体服务器 / 目录映射 / 存储 / 通知渠道 / 规则组。 */
@Serializable
data class ServiceConfigDto(
    val name: String = "",
    val type: String = "",
    val enabled: Boolean = true,
    val isDefault: Boolean = false,
    val host: String = "",
    val switchs: List<String> = emptyList(),
    val extraSummary: String = "",
)

@Serializable
data class DirectoryConfigDto(
    val name: String = "",
    val priority: Int = 1,
    val storage: String = "local",
    val downloadPath: String = "",
    val libraryStorage: String = "local",
    val libraryPath: String = "",
    val transferType: String = "copy",
    val monitorType: String = "",
    val renaming: Boolean = true,
    val scraping: Boolean = true,
    val notify: Boolean = true,
)

@Serializable
data class StorageConfigDto(
    val name: String = "",
    val type: String = "local",
)

@Serializable
data class FilterRuleGroupDto(
    val name: String = "",
    val ruleString: String = "",
)

/** 订阅与搜索系统设置聚合状态。 */
@Serializable
data class SubscribeSearchSettingsDto(
    val rssSiteIds: List<Int> = emptyList(),
    val indexerSiteIds: List<Int> = emptyList(),
    val subscribeMode: String = "spider",
    val filterRuleGroups: List<FilterRuleGroupDto> = emptyList(),
)

/** 插件仪表盘元信息。 */
@Serializable
data class PluginDashboardMetaDto(
    val id: String = "",
    val key: String = "",
    val name: String = "",
)

/** 工作流与节点定义。 */
@Serializable
data class WorkflowActionDto(
    val id: String = "",
    val type: String = "",
    val name: String = "",
    val description: String = "",
    val x: Float = 0f,
    val y: Float = 0f,
    val paramCount: Int = 0,
)

@Serializable
data class WorkflowFlowEdgeDto(
    val source: String = "",
    val target: String = "",
)

@Serializable
data class WorkflowItemDto(
    val id: Int = 0,
    val name: String = "",
    val description: String = "",
    val timer: String = "",
    val state: String = "P",
    @SerialName("run_count") val runCount: Int = 0,
    val actions: List<WorkflowActionDto> = emptyList(),
    val flows: List<WorkflowFlowEdgeDto> = emptyList(),
)

/** 插件列表条目。 */
@Serializable
data class PluginItemDto(
    val id: String = "",
    @SerialName("plugin_name") val name: String = "",
    @SerialName("plugin_desc") val desc: String = "",
    @SerialName("plugin_version") val version: String = "1.0.0",
    @SerialName("plugin_author") val author: String = "",
    @SerialName("plugin_icon") val icon: String? = null,
    val labels: List<String> = emptyList(),
    val installed: Boolean = false,
    val state: Boolean = false,
    @SerialName("has_page") val hasPage: Boolean = false,
    @SerialName("has_update") val hasUpdate: Boolean = false,
    @SerialName("render_mode") val renderMode: String = "vuetify",
)

/** 消息中心通知条目。 */
@Serializable
data class SystemMessageDto(
    val id: String = "",
    val title: String = "",
    val text: String = "",
    val date: String = "",
    val category: String = "系统",
    val image: String? = null,
)

/** 定时服务条目。 */
@Serializable
data class ScheduledServiceDto(
    val id: String = "",
    val name: String = "",
    val provider: String = "",
    val status: String = "等待",
    val nextRun: String = "",
)

/** AI 智能助手对话消息。 */
@Serializable
data class AgentChatMessageDto(
    val id: String,
    val role: String, // "user" | "assistant"
    val content: String,
    val thinkingText: String? = null,
    val thinkingSeconds: Int = 0,
    val toolCalls: List<String> = emptyList(),
    val quickOptions: List<String> = emptyList(),
    val isStreaming: Boolean = false,
)

/** 资源搜索筛选结果组（经 Rust 9 维筛选与同规格分组）。 */
@Serializable
data class ResourceItemDto(
    val id: String = "",
    val title: String = "",
    @SerialName("site_name") val siteName: String = "",
    val size: Long = 0L,
    val seeders: Int = 0,
    val peers: Int = 0,
    @SerialName("resource_pix") val resourcePix: String = "",
    @SerialName("resource_type") val resourceType: String = "",
    @SerialName("video_encode") val videoEncode: String = "",
    @SerialName("audio_encode") val audioEncode: String = "",
    @SerialName("resource_team") val resourceTeam: String = "",
    val edition: String = "",
    val downloadvolumefactor: Double = 1.0,
    val uploadvolumefactor: Double = 1.0,
    val labels: List<String> = emptyList(),
    val description: String = "",
    val enclosure: String = "",
    val mediaTitle: String = "",
    val mediaYear: String = "",
    val mediaType: String = "",
    val seasonEpisode: String = "",
)

@Serializable
data class ResourceFilterOptionsDto(
    val sites: List<String> = emptyList(),
    val resolutions: List<String> = emptyList(),
    val resourceTypes: List<String> = emptyList(),
    val videoEncodes: List<String> = emptyList(),
    val audioEncodes: List<String> = emptyList(),
    val editions: List<String> = emptyList(),
    val teams: List<String> = emptyList(),
    val promotions: List<String> = emptyList(),
    val labels: List<String> = emptyList(),
)

@Serializable
data class ResourceGroupDto(
    val key: String = "",
    val primary: ResourceItemDto = ResourceItemDto(),
    val items: List<ResourceItemDto> = emptyList(),
    val totalSeeders: Int = 0,
)

@Serializable
data class ResourceFilterResultDto(
    val totalCount: Int = 0,
    val filteredCount: Int = 0,
    val options: ResourceFilterOptionsDto = ResourceFilterOptionsDto(),
    val groups: List<ResourceGroupDto> = emptyList(),
)

/** 影视演职员 / 人物条目。 */
@Serializable
data class MediaPersonDto(
    val id: String = "",
    val name: String = "",
    val character: String = "",
    val department: String = "",
    val profilePath: String? = null,
    val biography: String = "",
    val birthday: String = "",
    val placeOfBirth: String = "",
    val source: String = "themoviedb",
)

/** 电视剧分季信息。 */
@Serializable
data class MediaSeasonDto(
    val seasonNumber: Int = 1,
    val name: String = "",
    val overview: String = "",
    val airDate: String = "",
    val episodeCount: Int = 0,
    val posterPath: String? = null,
    val voteAverage: Double = 0.0,
)

/** 电视剧单集信息。 */
@Serializable
data class MediaEpisodeDto(
    val episodeNumber: Int = 1,
    val name: String = "",
    val overview: String = "",
    val airDate: String = "",
    val runtime: Int? = null,
    val stillPath: String? = null,
    val voteAverage: Double = 0.0,
)

/** 音乐专辑 / 榜单条目。 */
@Serializable
data class MusicAlbumDto(
    val id: String = "",
    val title: String = "",
    val artist: String = "",
    val year: String = "",
    val coverUrl: String? = null,
    val source: String = "douban",
    val voteAverage: Double = 0.0,
    val overview: String = "",
)

/** 社区工作流分享条目。 */
@Serializable
data class WorkflowShareDto(
    val id: Int = 0,
    val name: String = "",
    val description: String = "",
    val shareTitle: String = "",
    val shareComment: String = "",
    val shareUser: String = "",
    val count: Int = 0,
    val date: String = "",
)

/** 整理队列任务条目。 */
@Serializable
data class TransferQueueItemDto(
    val title: String = "",
    val src: String = "",
    val dest: String = "",
    val state: String = "",
    val size: Long = 0L,
)

/** 媒体服务器客户端摘要（对应 `GET /api/v1/mediaserver/clients`）。 */
@Serializable
data class MediaServerClientDto(
    val name: String = "",
    val type: String = "",
)

/** 媒体服务器媒体库条目（对应 `GET /api/v1/mediaserver/library`）。 */
@Serializable
data class MediaServerLibraryDto(
    val id: String = "",
    val name: String = "",
    val type: String = "",
    val itemCount: Int? = null,
    val server: String = "",
    val serverType: String = "",
    val imageUrl: String? = null,
    val link: String? = null,
)

/** 媒体服务器浏览网格条目（对应 `GET /api/v1/mediaserver/browse`）。 */
@Serializable
data class MediaServerBrowseItemDto(
    val itemId: String = "",
    val title: String = "",
    val subtitle: String = "",
    val type: String = "",
    val year: String = "",
    val imageUrl: String? = null,
    val server: String = "",
    val serverType: String = "",
    val played: Boolean = false,
    val userRating: Double = 0.0,
    val unplayedCount: Int? = null,
    val tmdbId: Int? = null,
    val mediaId: String? = null,
)

/** 媒体服务器筛选候选项（对应 `GET /api/v1/mediaserver/filters`）。 */
@Serializable
data class MediaServerFilterOptionsDto(
    val genres: List<String> = emptyList(),
    val years: List<Int> = emptyList(),
)

/** 媒体服务器分页浏览结果。 */
@Serializable
data class MediaServerBrowsePageDto(
    val items: List<MediaServerBrowseItemDto> = emptyList(),
    val totalCount: Int = 0,
    val hasMore: Boolean = false,
)

/** 原生播放器外挂字幕项。 */
@Serializable
data class MediaStreamSubtitleDto(
    val subtitleId: String = "",
    val title: String = "",
    val language: String = "",
    val url: String = "",
)

/** 媒体服务器/音乐播放流清单（对应 `GET /api/v1/mediaserver/stream-info` 与 `/stream-info/music`）。 */
@Serializable
data class MediaPlaybackManifestDto(
    val itemId: String = "",
    val server: String = "",
    val mediaType: String = "video",
    val title: String = "",
    val contentUrl: String = "",
    val subtitles: List<MediaStreamSubtitleDto> = emptyList(),
    val lyricsUrl: String? = null,
    val durationMs: Long = 0L,
    val resumePositionMs: Long = 0L,
    val headers: Map<String, String> = emptyMap(),
)
