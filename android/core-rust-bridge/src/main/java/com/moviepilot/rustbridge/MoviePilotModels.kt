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
    val inLibrary: Boolean = false,
    val progressPercent: Int? = null,
    val subtitle: String? = null,
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
)

/** 订阅条目。 */
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
    val sites: List<Int> = emptyList(),
    val savePath: String = "",
    val include: String = "",
    val exclude: String = "",
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
    val cpuPercent: Double = 18.0,
    val memoryPercent: Double = 46.0,
    val transfer7Days: List<Int> = listOf(4, 7, 12, 9, 15, 6, 11),
)

/** 站点管理条目（含上下行流量与分享率）。 */
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
    val iconUrl: String? = null,
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
    val installed: Boolean = false,
    val state: Boolean = false,
    @SerialName("has_page") val hasPage: Boolean = false,
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

/** 社区勋章档案条目。 */
@Serializable
data class CommunityMedalDto(
    val key: String,
    val name: String,
    val description: String,
    val category: String,
    val unlocked: Boolean,
    val assetBaseName: String,
    val earnedDate: String = "",
    val detailFact: String = "",
)
