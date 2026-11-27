package com.moviepilot.rustbridge

import java.util.Locale
import kotlin.math.roundToInt
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
    val level: Int = 1,
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
    @SerialName("imdb_id") val imdbId: String? = null,
    @SerialName("tvdb_id") val tvdbId: String? = null,
    @SerialName("mediaid_prefix") val mediaIdPrefix: String? = null,
    @SerialName("media_id") val mediaId: String? = null,
    val season: Int? = null,
    val serverItemId: String? = null,
    val serverName: String? = null,
    val serverType: String? = null,
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
    val rawJson: String = "",
) {
    /** 稳定业务标识。 */
    val resolvedId: String
        get() = serverItemId?.takeIf { it.isNotBlank() }?.let { "${serverName.orEmpty()}:$it" }
            ?: mediaId ?: tmdbId?.toString() ?: doubanId ?: bangumiId?.toString() ?: title
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
    val serverType: String = "",
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
    val startEpisode: Int? = null,
    val downloader: String = "",
    val episodeGroup: String = "",
    val rawJson: String = "",
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
    val rawJson: String = "",
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
    val cookie: String = "",
    val ua: String = "",
    val rss: String = "",
    val proxy: Boolean = false,
    val render: Boolean = false,
    val rawJson: String = "",
)

/** 系统配置项：下载器 / 媒体服务器 / 目录映射 / 存储 / 通知渠道 / 规则组。 */
@Serializable
data class ServiceConfigDto(
    val name: String = "",
    val type: String = "",
    val enabled: Boolean = true,
    val isDefault: Boolean = false,
    val host: String = "",
    val username: String = "",
    val password: String = "",
    val apikey: String = "",
    val playHost: String = "",
    val switchs: List<String> = emptyList(),
    val config: Map<String, String> = emptyMap(),
    val extraSummary: String = "",
    val rawJson: String = "",
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
    val rawJson: String = "",
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
    @SerialName("repo_url") val repoUrl: String = "",
    @SerialName("install_count") val installCount: Int = 0,
    @SerialName("add_time") val addTime: Int = 0,
    @SerialName("average_rating") val averageRating: Double = 0.0,
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

/** 服务端已发送的系统与插件通知增量同步条目（`GET /api/v1/message/notification`）。 */
@Serializable
data class SentNotificationItemDto(
    val numericId: Long? = null,
    val stableKey: String = "",
    val title: String = "",
    val text: String = "",
    val category: String = "系统",
    val source: String = "",
    val channel: String = "",
    val userid: String = "",
    val regTime: String = "",
    val route: String = "/?shotcut=message",
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

/** AI 智能助手结构化工具调用条目（支持分组折叠与运行/完成/出错状态）。 */
@Serializable
data class AgentToolEntryDto(
    val id: String = "",
    val toolName: String = "",
    val message: String = "",
    val structured: Boolean = true,
    val status: String = "running", // "running" | "done" | "error"
)

/** AI 智能助手附件（图片 / 文件 / 语音，含上传引用与下载地址）。 */
@Serializable
data class AgentAttachmentDto(
    val kind: String = "file", // "image" | "audio" | "file"
    val ref: String = "",
    val url: String = "",
    val downloadUrl: String = "",
    val name: String = "",
    val mimeType: String = "",
    val size: Long = 0L,
    val localPath: String = "",
)

/** AI 智能助手交互选择按钮与卡片。 */
@Serializable
data class AgentChoiceButtonDto(
    val label: String = "",
    val callbackData: String = "",
)

@Serializable
data class AgentChoiceCardDto(
    val id: String = "",
    val title: String = "",
    val buttons: List<AgentChoiceButtonDto> = emptyList(),
    val selectedLabel: String? = null,
)

/** AI 智能助手历史会话摘要。 */
@Serializable
data class AgentSessionSummaryDto(
    val sessionId: String = "",
    val title: String = "新对话",
    val updatedAt: String = "",
    val messageCount: Int = 0,
    val isProcessing: Boolean = false,
)

/** AI 智能助手斜杠命令项。 */
@Serializable
data class AgentCommandDto(
    val command: String = "",
    val description: String = "",
)

/** AI 智能助手对话消息（全量对齐 iOS：工具分组 + 附件 + 交互卡片 + 保护模式）。 */
@Serializable
data class AgentChatMessageDto(
    val id: String,
    val role: String, // "user" | "assistant"
    val content: String,
    val thinkingText: String? = null,
    val thinkingSeconds: Int = 0,
    val toolCalls: List<String> = emptyList(),
    val tools: List<AgentToolEntryDto> = emptyList(),
    val attachments: List<AgentAttachmentDto> = emptyList(),
    val choices: List<AgentChoiceCardDto> = emptyList(),
    val quickOptions: List<String> = emptyList(),
    val isProtected: Boolean = false,
    val isStreaming: Boolean = false,
)

/** 手动整理预览条目与目标路径/历史匹配提示。 */
@Serializable
data class ManualTransferPreviewItemDto(
    val src: String = "",
    val dest: String = "",
    val title: String = "",
    val seasonEpisode: String = "",
    val status: String = "",
    val message: String = "",
)

@Serializable
data class ManualTransferTargetHintDto(
    val targetStorage: String = "",
    val targetPath: String = "",
    val transferType: String = "",
    val overwriteMode: String = "",
    val scrape: Boolean? = null,
    val libraryTypeFolder: Boolean? = null,
    val libraryCategoryFolder: Boolean? = null,
)

@Serializable
data class ManualTransferHistoryHintDto(
    val historyCount: Int = 0,
    val reorganize: Boolean = false,
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

/** 后端媒体搜索来源目录项（对应 `GET /api/v1/media/source`）。 */
@Serializable
data class MediaSearchSourceDto(
    val id: String = "",
    val name: String = "",
    val mediaTypes: List<String> = listOf("电影", "电视剧"),
) {
    val displayName: String
        get() {
            val trimmed = name.trim()
            return if (trimmed.equals("tmdb", ignoreCase = true) || trimmed.equals("themoviedb", ignoreCase = true)) {
                "TheMovieDB"
            } else {
                trimmed.ifBlank { id }
            }
        }

    /** 判断该搜索源是否支持指定搜索域（对齐 iOS `NativeMediaSourceOption.supports`）。 */
    fun supports(kind: String): Boolean {
        val lowerId = id.lowercase()
        if (kind == "collection") return lowerId == "themoviedb"
        if (kind == "person") return lowerId in setOf("themoviedb", "douban", "musicbrainz")
        val types = (mediaTypes.ifEmpty { listOf("电影", "电视剧") }).map { it.lowercase() }
        if (kind == "music") return "音乐" in types || "music" in types
        return types.any { it in setOf("电影", "电视剧", "movie", "tv") }
    }
}

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
    val albumId: String = "",
    val releaseId: String? = null,
    val title: String = "",
    val artist: String = "",
    val artistId: String? = null,
    val year: String = "",
    val albumType: String = "",
    val totalTracks: Int = 0,
    val coverUrl: String? = null,
    val source: String = "douban",
    val voteAverage: Double = 0.0,
    val overview: String = "",
) {
    /** 用于查询 `/api/v1/music/album/{id}` 的首选专辑标识。 */
    val lookupAlbumId: String
        get() = albumId.ifBlank { id }
}

/** 音乐专辑单首曲目信息。 */
@Serializable
data class MusicTrackDto(
    val id: String = "",
    val title: String = "",
    val artist: String = "",
    val discNumber: Int = 1,
    val trackNumber: Int = 0,
    val durationSeconds: Int = 0,
)

/** 音乐专辑完整详情（对应 `GET /api/v1/music/album/{id}`）。 */
@Serializable
data class MusicAlbumDetailDto(
    val id: String = "",
    val title: String = "",
    val artist: String = "",
    val artists: List<String> = emptyList(),
    val artistIds: List<String> = emptyList(),
    val albumType: String = "",
    val year: String = "",
    val totalTracks: Int = 0,
    val coverUrl: String? = null,
    val overview: String = "",
    val source: String = "musicbrainz",
    val tracks: List<MusicTrackDto> = emptyList(),
)

/** 音乐艺术家资料与专辑作品（对应 `GET /api/v1/music/artist/{id}` 与 `/albums`）。 */
@Serializable
data class MusicArtistDetailDto(
    val id: String = "",
    val name: String = "",
    val country: String = "",
    val area: String = "",
    val lifeSpan: String = "",
    val imageUrl: String? = null,
    val overview: String = "",
    val source: String = "musicbrainz",
    val albums: List<MusicAlbumDto> = emptyList(),
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
    val rawJson: String = "",
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

/** 媒体服务器浏览网格、季列表与单集列表通用条目（对应 `/mediaserver/browse`、`/seasons`、`/season-episodes`）。 */
@Serializable
data class MediaServerBrowseItemDto(
    val itemId: String = "",
    val title: String = "",
    val originalTitle: String = "",
    val subtitle: String = "",
    val overview: String = "",
    val type: String = "",
    val mediaType: String = "",
    val year: String = "",
    val premiereDate: String = "",
    val imageUrl: String? = null,
    val poster: String? = null,
    val backdrop: String? = null,
    val thumb: String? = null,
    val server: String = "",
    val serverType: String = "",
    val durationMs: Long? = null,
    val seriesId: String? = null,
    val seriesName: String = "",
    val seasonId: String? = null,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val childCount: Int? = null,
    val played: Boolean = false,
    val playedPercentage: Double = 0.0,
    val resumePositionMs: Long = 0L,
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

/** 后端协商下发的单条候选播放路由（与 Rust `PlaybackRouteCandidate` 1:1 对齐）。 */
@Serializable
data class PlaybackRouteDto(
    val kind: String = "mp_proxy",
    val url: String = "",
    @SerialName("probe_url") val probeUrl: String? = null,
    val headers: Map<String, String> = emptyMap(),
    val priority: Int = 100,
    @SerialName("requires_same_origin_auth") val requiresSameOriginAuth: Boolean = false,
)

/** 客户端播放路由偏好设置（与 Rust `PlaybackRoutePreference` 1:1 对齐）。 */
@Serializable
data class PlaybackRoutePreferenceDto(
    @SerialName("prefer_strm_direct") val preferStrmDirect: Boolean = true,
    @SerialName("prefer_server_direct") val preferServerDirect: Boolean = true,
    @SerialName("lan_preferred_max_latency_ms") val lanPreferredMaxLatencyMs: Int = 350,
)

/** 单条直连候选的轻量探测结果（与 Rust `RouteProbeOutcome` 1:1 对齐）。 */
@Serializable
data class RouteProbeOutcomeDto(
    val url: String = "",
    val reachable: Boolean = false,
    @SerialName("latency_ms") val latencyMs: Int? = null,
)

/** 路由规划输出：主播放路由与有序降级队列（与 Rust `PlaybackRoutePlan` 1:1 对齐）。 */
@Serializable
data class PlaybackRoutePlanDto(
    val active: PlaybackRouteDto,
    val fallbacks: List<PlaybackRouteDto> = emptyList(),
    @SerialName("route_label_zh") val routeLabelZh: String = "",
)

/** 媒体服务器/音乐播放流清单（对应 `GET /api/v1/mediaserver/stream-info` 与 `/stream-info/music`）。 */
@Serializable
data class MediaPlaybackManifestDto(
    val itemId: String = "",
    val server: String = "",
    @SerialName("server_type") val serverType: String = "",
    @SerialName("media_source_id") val mediaSourceId: String? = null,
    @SerialName("play_session_id") val playSessionId: String? = null,
    @SerialName("progress_sync_mode") val progressSyncMode: String? = null,
    val mediaType: String = "video",
    val title: String = "",
    val contentUrl: String = "",
    val strmUrl: String? = null,
    val proxyFallbackUrl: String? = null,
    val originUrl: String = "",
    val subtitles: List<MediaStreamSubtitleDto> = emptyList(),
    val lyricsUrl: String? = null,
    val durationMs: Long = 0L,
    val resumePositionMs: Long = 0L,
    val headers: Map<String, String> = emptyMap(),
    val sameOriginHeaders: Map<String, String> = emptyMap(),
    val streamHeaders: Map<String, String> = emptyMap(),
    val activeRouteKind: String = "",
    val fallbackRoutes: List<PlaybackRouteDto> = emptyList(),
    @SerialName("playback_routes") val playbackRoutes: List<PlaybackRouteDto> = emptyList(),
    @SerialName("danmaku_enabled") val danmakuEnabled: Boolean = false,
    @SerialName("series_name") val seriesName: String? = null,
    @SerialName("season_number") val seasonNumber: Int? = null,
    @SerialName("episode_number") val episodeNumber: Int? = null,
    val year: Int? = null,
    @SerialName("tmdb_id") val tmdbId: String? = null,
    @SerialName("file_name") val fileName: String? = null,
    @SerialName("file_size") val fileSize: Long? = null,
)

/** 弹幕本地磁盘缓存统计。 */
@Serializable
data class DanmakuCacheStatsDto(
    @SerialName("file_count") val fileCount: Int = 0,
    @SerialName("total_bytes") val totalBytes: Long = 0L,
    @SerialName("max_mb") val maxMb: Int = 512,
)

/** 管理员弹幕服务脱敏配置快照。 */
@Serializable
data class DanmakuConfigDto(
    val enabled: Boolean = false,
    @SerialName("api_base_url") val apiBaseUrl: String = "",
    @SerialName("auth_mode") val authMode: String = "none",
    @SerialName("app_id") val appId: String = "",
    @SerialName("has_app_secret") val hasAppSecret: Boolean = false,
    @SerialName("token_header") val tokenHeader: String = "Authorization",
    @SerialName("token_prefix") val tokenPrefix: String = "Bearer ",
    @SerialName("has_token") val hasToken: Boolean = false,
    @SerialName("with_related") val withRelated: Boolean = true,
    @SerialName("ch_convert") val chConvert: Int = 1,
    @SerialName("cache_ttl_hours") val cacheTtlHours: Int = 24,
    @SerialName("cache_max_mb") val cacheMaxMb: Int = 512,
    @SerialName("timeout_seconds") val timeoutSeconds: Int = 10,
    @SerialName("use_proxy") val useProxy: Boolean = false,
    @SerialName("verify_tls") val verifyTls: Boolean = true,
    @SerialName("cache_stats") val cacheStats: DanmakuCacheStatsDto = DanmakuCacheStatsDto(),
)

/** 弹幕上游连通性测试回执。 */
@Serializable
data class DanmakuConfigTestResultDto(
    val ok: Boolean = false,
    @SerialName("latency_ms") val latencyMs: Int = 0,
    @SerialName("status_code") val statusCode: Int? = null,
    val message: String = "",
)

/** 弹幕缓存清理回执。 */
@Serializable
data class DanmakuCacheClearResultDto(
    @SerialName("removed_files") val removedFiles: Int = 0,
    @SerialName("freed_bytes") val freedBytes: Long = 0L,
)

/** 单个弹幕分集候选条目。 */
@Serializable
data class DanmakuEpisodeCandidateDto(
    @SerialName("episode_id") val episodeId: Long = 0L,
    @SerialName("anime_id") val animeId: Long? = null,
    @SerialName("anime_title") val animeTitle: String = "",
    @SerialName("episode_title") val episodeTitle: String = "",
    @SerialName("episode_number") val episodeNumber: String? = null,
    @SerialName("anime_type") val animeType: String? = null,
    @SerialName("shift_ms") val shiftMs: Int = 0,
)

/** 弹幕自动匹配或手动绑定查询结果。 */
@Serializable
data class DanmakuMatchResponseDto(
    val matched: Boolean = false,
    @SerialName("from_binding") val fromBinding: Boolean = false,
    @SerialName("shift_ms") val shiftMs: Int = 0,
    val episode: DanmakuEpisodeCandidateDto? = null,
    val candidates: List<DanmakuEpisodeCandidateDto> = emptyList(),
)

/** 手动搜剧返回的作品条目。 */
@Serializable
data class DanmakuAnimeSearchItemDto(
    @SerialName("anime_id") val animeId: Long = 0L,
    @SerialName("anime_title") val animeTitle: String = "",
    @SerialName("anime_type") val animeType: String? = null,
    @SerialName("episode_count") val episodeCount: Int? = null,
    val episodes: List<DanmakuEpisodeCandidateDto> = emptyList(),
)

/** 指定作品的完整分集列表。 */
@Serializable
data class DanmakuBangumiDto(
    @SerialName("anime_id") val animeId: Long = 0L,
    @SerialName("anime_title") val animeTitle: String = "",
    @SerialName("anime_type") val animeType: String? = null,
    val episodes: List<DanmakuEpisodeCandidateDto> = emptyList(),
)

/** 拉取单集弹幕载荷的结果（含 ETag 304 内存复用标记）。 */
data class DanmakuCommentsRawDto(
    val rawJson: String,
    val etag: String? = null,
    val fromCache: Boolean = false,
)

/** 当前用户在单个媒体服务器上的脱敏账号绑定与同步模式状态。 */
@Serializable
data class MediaServerAccountBindingDto(
    val server: String = "",
    @SerialName("server_type") val serverType: String = "",
    @SerialName("sync_mode") val syncMode: String = "none",
    @SerialName("supports_binding") val supportsBinding: Boolean = false,
    val bound: Boolean = false,
    val status: String = "unsupported",
    @SerialName("remote_username") val remoteUsername: String? = null,
    val source: String? = null,
    @SerialName("updated_at") val updatedAt: Long? = null,
)

/** 跨端播放同步状态机持久化快照（对齐 Rust `PlaybackSyncState`）。 */
@Serializable
data class PlaybackSyncStateDto(
    @SerialName("play_session_id") val playSessionId: String = "",
    @SerialName("started_sent") val startedSent: Boolean = false,
    @SerialName("stopped_sent") val stoppedSent: Boolean = false,
    @SerialName("paused_since_ms") val pausedSinceMs: Long? = null,
    @SerialName("last_report_at_ms") val lastReportAtMs: Long? = null,
    @SerialName("last_playing_tick_at_ms") val lastPlayingTickAtMs: Long? = null,
    @SerialName("last_seek_at_ms") val lastSeekAtMs: Long? = null,
    @SerialName("cumulative_playback_time_ms") val cumulativePlaybackTimeMs: Long = 0L,
    val seq: Long = 0L,
    @SerialName("last_position_ms") val lastPositionMs: Long = 0L,
    @SerialName("last_audio_stream_index") val lastAudioStreamIndex: Int? = null,
    @SerialName("last_subtitle_stream_index") val lastSubtitleStreamIndex: Int? = null,
)

/** 播放同步单步规划输入（对齐 Rust `PlaybackSyncInput`）。 */
@Serializable
data class PlaybackSyncInputDto(
    val trigger: String,
    @SerialName("now_ms") val nowMs: Long,
    @SerialName("position_ms") val positionMs: Long,
    @SerialName("duration_ms") val durationMs: Long? = null,
    @SerialName("is_paused") val isPaused: Boolean = false,
    @SerialName("audio_stream_index") val audioStreamIndex: Int? = null,
    @SerialName("subtitle_stream_index") val subtitleStreamIndex: Int? = null,
)

/** 播放同步单步规划输出（对齐 Rust `PlaybackSyncDecision`）。 */
@Serializable
data class PlaybackSyncDecisionDto(
    @SerialName("should_report") val shouldReport: Boolean = false,
    val state: String = "playing",
    @SerialName("event_name") val eventName: String? = null,
    @SerialName("is_paused") val isPaused: Boolean = false,
    @SerialName("position_ms") val positionMs: Long = 0L,
    @SerialName("playback_time_ms") val playbackTimeMs: Long = 0L,
    val seq: Long = 0L,
    @SerialName("next_state") val nextState: PlaybackSyncStateDto = PlaybackSyncStateDto(),
)

/** 离线或网络异常时持久化的终态 `stopped` 补报条目（对齐 Rust `PendingPlaybackStop`）。 */
@Serializable
data class PendingPlaybackStopDto(
    val server: String,
    @SerialName("item_id") val itemId: String,
    @SerialName("media_source_id") val mediaSourceId: String? = null,
    @SerialName("position_ms") val positionMs: Long = 0L,
    @SerialName("duration_ms") val durationMs: Long? = null,
    @SerialName("play_session_id") val playSessionId: String? = null,
    @SerialName("playback_time_ms") val playbackTimeMs: Long? = null,
    val seq: Long? = null,
    @SerialName("updated_at_ms") val updatedAtMs: Long = 0L,
)

/** 存储文件播放解析结果：普通文件返回本地缓存 URI，`.strm` 文件解析后返回客户端 HTTP(S) 直链与可选请求头。 */
data class ResolvedStoragePlaybackDto(
    val url: String,
    val isAudio: Boolean,
    val headers: Map<String, String> = emptyMap(),
    val sameOriginHeaders: Map<String, String> = emptyMap(),
    val streamHeaders: Map<String, String> = emptyMap(),
    val originUrl: String = "",
    val proxyFallbackUrl: String? = null,
    val activeRouteKind: String = "",
    val fallbackRoutes: List<PlaybackRouteDto> = emptyList(),
    val itemId: String = "",
    val lyricsUrl: String? = null,
    val title: String = "",
    val tempFilePath: String? = null,
    val isStrmDirect: Boolean = false,
)

/** 订阅播映日历单日条目（对应 `GET /api/v1/subscribe/calendar`）。 */
@Serializable
data class CalendarEntryDto(
    val id: String = "",
    val subscribeId: Int = 0,
    val title: String = "",
    val year: String = "",
    val type: String = "电视剧",
    val season: Int? = null,
    val episode: Int? = null,
    val episodeTitle: String = "",
    val airDate: String = "",
    val poster: String? = null,
    val backdrop: String? = null,
    val voteAverage: Double = 0.0,
    val source: String = "themoviedb",
    val tmdbId: Int? = null,
    val doubanId: String? = null,
    val bangumiId: Int? = null,
    val mediaId: String? = null,
    val overview: String = "",
) {
    /** 转换为媒体详情卡片参数，以便点击日历条目直接进入影视详情页。 */
    fun toMediaCardItem(): MediaCardItem = MediaCardItem(
        title = title,
        year = year,
        type = type.ifBlank { "电视剧" },
        overview = overview.ifBlank { episodeTitle },
        posterPath = poster,
        backdropPath = backdrop ?: poster,
        voteAverage = voteAverage,
        source = source.ifBlank { "themoviedb" },
        tmdbId = tmdbId,
        doubanId = doubanId,
        bangumiId = bangumiId,
        mediaId = mediaId,
        releaseDate = airDate,
    )
}

/** 系统模块健康检测条目（对应 `GET /api/v1/module/modulelist` 与 `/moduletest/{id}`）。 */
@Serializable
data class SystemModuleStatusDto(
    val id: String = "",
    val name: String = "",
    val moduleType: String = "",
    val subType: String = "",
    val ok: Boolean? = null,
    val message: String = "待检测",
)

/** 媒体名称识别结果（对应 `GET /api/v1/media/recognize`）。 */
@Serializable
data class RecognizeResultDto(
    val rawTitle: String = "",
    val cnName: String = "",
    val enName: String = "",
    val recognizedTitle: String = "",
    val year: String = "",
    val type: String = "",
    val category: String = "",
    val tmdbId: Int? = null,
    val seasonEpisode: String = "",
    val resourcePix: String = "",
    val resourceType: String = "",
    val videoEncode: String = "",
    val audioEncode: String = "",
    val resourceTeam: String = "",
    val voteAverage: Double = 0.0,
    val posterPath: String? = null,
    val overview: String = "",
) {
    /** 转换为影视详情卡片条目。 */
    fun toMediaCardItem(): MediaCardItem = MediaCardItem(
        title = recognizedTitle.ifBlank { cnName.ifBlank { enName.ifBlank { rawTitle } } },
        year = year,
        type = type.ifBlank { "电影" },
        overview = overview,
        posterPath = posterPath,
        voteAverage = voteAverage,
        tmdbId = tmdbId,
    )
}

/** 网络连通性检测结果（对应 `GET /api/v1/system/nettest`）。 */
@Serializable
data class NetTestResultDto(
    val name: String = "",
    val url: String = "",
    val proxy: Boolean = false,
    val ok: Boolean = false,
    val latencyMs: Long? = null,
    val message: String = "",
)

/** 渠道授权 5 分钟短效绑定码快照（对应 `/api/v1/authorization`）。 */
@Serializable
data class ChannelBindingCodeDto(
    val code: String = "",
    val expiresInSeconds: Int = 300,
    val commandHint: String = "",
    val createdAtEpochMs: Long = 0L,
)

/** 渠道授权绑定记录条目（对应 `/api/v1/authorization`）。 */
@Serializable
data class ChannelAuthRecordDto(
    val id: String = "",
    val channel: String = "",
    val channelUserId: String = "",
    val channelUsername: String = "",
    val boundUsername: String = "",
    val status: String = "approved", // "pending" | "approved"
    val createdAt: String = "",
)

/** 媒体库入库、订阅与可直放状态快照（对应 `POST /api/v1/media/status` 及媒体服务器匹配）。 */
@Serializable
data class MediaLibraryStatusDto(
    val inLibrary: Boolean = false,
    val server: String = "",
    val serverType: String = "",
    val itemId: String = "",
    val subscribed: Boolean = false,
    val subscribedSeasons: Map<Int, String> = emptyMap(),
    val subscribeId: Int? = null,
    val seasonSubscribeIds: Map<Int, Int> = emptyMap(),
    val existingEpisodesBySeason: Map<Int, List<Int>> = emptyMap(),
)

/** 订阅关联的下载任务文件信息（对应 `GET /api/v1/subscribe/files/{subscribe_id}` 中的 `download` 项）。 */
@Serializable
data class SubscribeDownloadFileDto(
    val torrentTitle: String = "",
    val siteName: String = "",
    val downloader: String = "",
    val hash: String = "",
    val filePath: String = "",
)

/** 订阅关联的媒体库/存储文件信息（对应 `GET /api/v1/subscribe/files/{subscribe_id}` 中的 `library` 项）。 */
@Serializable
data class SubscribeLibraryFileDto(
    val storage: String = "local",
    val filePath: String = "",
    val server: String? = null,
    val serverType: String? = null,
    val itemid: String? = null,
)

/** 订阅单集（或电影正片 key=0）关联的下载与入库文件分组。 */
@Serializable
data class SubscribeEpisodeFileGroupDto(
    val episodeKey: Int = 0,
    val title: String = "",
    val description: String = "",
    val backdrop: String? = null,
    val download: List<SubscribeDownloadFileDto> = emptyList(),
    val library: List<SubscribeLibraryFileDto> = emptyList(),
)

/** 订阅完整文件详情聚合快照（对应 `GET /api/v1/subscribe/files/{subscribe_id}`）。 */
@Serializable
data class SubscribeFilesInfoDto(
    val subscribe: SubscribeItemDto? = null,
    val episodes: List<SubscribeEpisodeFileGroupDto> = emptyList(),
)

/** 媒体服务器音视频/字幕单轨道信息（覆盖标准字段与可选高阶编码元数据）。 */
@Serializable
data class MediaServerStreamTrackDto(
    val index: Int? = null,
    val type: String = "unknown",
    val codec: String? = null,
    val language: String? = null,
    val title: String? = null,
    val displayTitle: String? = null,
    val isDefault: Boolean = false,
    val isForced: Boolean = false,
    val isExternal: Boolean = false,
    val subtitleId: String? = null,
    val channels: Int? = null,
    val channelLayout: String? = null,
    val bitrate: Long? = null,
    val width: Int? = null,
    val height: Int? = null,
    val videoRange: String? = null,
    val frameRate: String? = null,
    val profile: String? = null,
    val level: String? = null,
    val aspectRatio: String? = null,
    val isInterlaced: Boolean? = null,
    val colorPrimaries: String? = null,
    val colorSpace: String? = null,
    val bitDepth: Int? = null,
    val sampleRate: Int? = null,
) {
    /** 优先采用服务端显式长宽比，缺失时通过宽高最大公约数推导（如 `1920x1080` -> `16:9`）。 */
    val inferredAspectRatio: String?
        get() {
            aspectRatio?.trim()?.takeIf { it.isNotBlank() }?.let { return it }
            val w = width ?: return null
            val h = height ?: return null
            if (w <= 0 || h <= 0) return null
            val g = gcd(w, h)
            val rw = w / g
            val rh = h / g
            return if (rw <= 64 && rh <= 64) {
                "$rw:$rh"
            } else {
                String.format(Locale.US, "%.2f:1", w.toDouble() / h.toDouble())
            }
        }

    /** 格式化轨道码率：视频轨道百万级采用 `14.3mbps`，音频或千位码率采用 `1000kbps`。 */
    val formattedBitrate: String?
        get() {
            val bps = bitrate ?: return null
            if (bps <= 0L) return null
            return if (type.equals("video", ignoreCase = true) && bps >= 1_000_000L) {
                String.format(Locale.US, "%.1fmbps", bps / 1_000_000.0)
            } else if (!type.equals("audio", ignoreCase = true) && bps >= 10_000_000L) {
                String.format(Locale.US, "%.1fmbps", bps / 1_000_000.0)
            } else {
                "${(bps / 1000.0).roundToInt().coerceAtLeast(1)}kbps"
            }
        }

    /** 格式化像素分辨率（如 `1920x1080`）。 */
    val formattedResolution: String?
        get() {
            val w = width ?: return null
            val h = height ?: return null
            return if (w > 0 && h > 0) "${w}x${h}" else null
        }

    companion object {
        private tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) kotlin.math.abs(a) else gcd(b, a % b)
    }
}

/** 媒体服务器单个可播放媒体源版本（对应 `MediaServerMediaSource`）。 */
@Serializable
data class MediaServerSourceDto(
    val id: String = "",
    val name: String = "",
    val container: String = "",
    val size: Long? = null,
    val bitrate: Long? = null,
    val durationMs: Long? = null,
    val streams: List<MediaServerStreamTrackDto> = emptyList(),
)

/** 媒体服务器条目演职员信息（对应 `MediaServerPerson`）。 */
@Serializable
data class MediaServerPersonDto(
    val id: String = "",
    val name: String = "",
    val role: String = "",
    val type: String = "",
    val image: String? = null,
)

/** 媒体服务器条目完整详情（对应 `GET /api/v1/mediaserver/detail`）。 */
@Serializable
data class MediaServerItemDetailDto(
    val itemId: String = "",
    val server: String = "",
    val serverType: String = "",
    val itemType: String = "Movie",
    val mediaType: String = "",
    val title: String = "",
    val originalTitle: String = "",
    val subtitle: String = "",
    val tagline: String = "",
    val overview: String = "",
    val year: String = "",
    val premiereDate: String = "",
    val officialRating: String = "",
    val rating: Double = 0.0,
    val durationMs: Long? = null,
    val poster: String? = null,
    val backdrop: String? = null,
    val thumb: String? = null,
    val logoUrl: String? = null,
    val genres: List<String> = emptyList(),
    val studios: List<String> = emptyList(),
    val people: List<MediaServerPersonDto> = emptyList(),
    val mediaSource: String? = null,
    val mediaId: String? = null,
    val imdbId: String? = null,
    val tmdbId: String? = null,
    val tvdbId: String? = null,
    val doubanId: String? = null,
    val parentId: String? = null,
    val seriesId: String? = null,
    val seriesName: String = "",
    val seasonId: String? = null,
    val seasonName: String = "",
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val seasonCount: Int? = null,
    val episodeCount: Int? = null,
    val childCount: Int? = null,
    val played: Boolean = false,
    val playedPercentage: Double = 0.0,
    val resumePositionMs: Long = 0L,
    val mediaSources: List<MediaServerSourceDto> = emptyList(),
    val playUrl: String? = null,
    val canPlay: Boolean = false,
)

/** 插件动态注册的推荐榜单数据源（对应 `GET /api/v1/recommend/source`）。 */
@Serializable
data class RecommendSourceDto(
    val name: String = "",
    @SerialName("api_path") val apiPath: String = "",
    val type: String = "",
)

/** 发现页内存会话快照（用于切 Tab 与详情返回时零闪烁保留滚动位置与已加载内容）。 */
data class DiscoverSessionSnapshot(
    val trending: List<MediaCardItem> = emptyList(),
    val movies: List<MediaCardItem> = emptyList(),
    val tvs: List<MediaCardItem> = emptyList(),
    val musicAlbums: List<MusicAlbumDto> = emptyList(),
    val showing: List<MediaCardItem> = emptyList(),
    val top250: List<MediaCardItem> = emptyList(),
    val continueWatching: List<ContinueWatchingItem> = emptyList(),
    val latestItems: List<MediaCardItem> = emptyList(),
    val libraries: List<MediaServerLibraryDto> = emptyList(),
    val heroLogos: Map<String, String> = emptyMap(),
    val extraSources: List<RecommendSourceDto> = emptyList(),
    val extraRails: Map<String, List<MediaCardItem>> = emptyMap(),
)

/** 探索页筛选维度内存快照。 */
data class ExploreSessionSnapshot(
    val items: List<MediaCardItem> = emptyList(),
    val musicAlbums: List<MusicAlbumDto> = emptyList(),
    val page: Int = 1,
    val hasMore: Boolean = true,
)

/** 仪表盘内存会话快照。 */
data class DashboardSessionSnapshot(
    val stats: DashboardStatsDto = DashboardStatsDto(),
    val communityProfileJson: String? = null,
    val latestMedia: List<MediaCardItem> = emptyList(),
    val schedules: List<ScheduledServiceDto> = emptyList(),
    val pluginMetas: List<PluginDashboardMetaDto> = emptyList(),
    val pluginWidgets: Map<String, String> = emptyMap(),
)

/** 工作台内存会话快照。 */
data class WorkspaceSessionSnapshot(
    val stats: DashboardStatsDto = DashboardStatsDto(),
    val activeDownloads: List<DownloadTaskDto> = emptyList(),
    val sites: List<SiteItemDto> = emptyList(),
    val pluginsCount: Int = 0,
    val workflows: List<WorkflowItemDto> = emptyList(),
    val libraries: List<MediaServerLibraryDto> = emptyList(),
    val recentTransfers: List<TransferHistoryDto> = emptyList(),
)

/** 多内核选核路由输入快照（与 Rust `EngineResolutionInput` 严格字段对齐）。 */
@Serializable
data class EngineResolutionInputDto(
    val platform: String = "android",
    val preferred: String = "auto",
    @SerialName("is_audio") val isAudio: Boolean = false,
    @SerialName("decode_force_software") val decodeForceSoftware: Boolean = false,
    @SerialName("has_enhanced_engine") val hasEnhancedEngine: Boolean = true,
    @SerialName("has_legacy_engine") val hasLegacyEngine: Boolean = false,
    @SerialName("url_or_filename") val urlOrFilename: String = "",
    val container: String? = null,
    @SerialName("video_codec") val videoCodec: String? = null,
    @SerialName("audio_codec") val audioCodec: String? = null,
    @SerialName("has_ass_or_pgs_subtitle") val hasAssOrPgsSubtitle: Boolean = false,
    @SerialName("ignore_ass_style") val ignoreAssStyle: Boolean = false,
    @SerialName("allow_self_signed_tls") val allowSelfSignedTls: Boolean = false,
    @SerialName("is_hdr") val isHdr: Boolean = false,
)

/** 多内核选核决策输出（与 Rust `EngineResolutionPlan` 严格字段对齐）。 */
@Serializable
data class EngineResolutionPlanDto(
    val primary: String = "native",
    val fallback: String? = null,
    val reason: String = "auto_native_default",
)
