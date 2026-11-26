package com.moviepilot.app

import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.feature.dashboard.defaultDashboardModuleIds
import com.moviepilot.media.ChineseSubtitleMatcher
import com.moviepilot.media.LocalPlaybackHistoryStore
import com.moviepilot.media.PLAYER_SUPPORTED_SPEEDS
import com.moviepilot.media.PlaybackHttpDataSource
import com.moviepilot.media.PlaybackPipBridge
import com.moviepilot.media.parseLrcLyrics
import com.moviepilot.rustbridge.MediaServerBrowseItemDto
import com.moviepilot.rustbridge.MoviePilotRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 音视频播放全链路对齐回归单测：
 * 覆盖 LRC 多时间戳歌词解析、剧集智能续播定位、中文字幕匹配、本地断点续播阈值与隔离键、
 * MusicBrainz 探索参数、同源凭据剥离、画中画宽高比收敛、播放偏好默认值及仪表盘社区勋章置顶。
 */
class PlaybackParityTest {

    @Test
    fun parseLrcLyricsExpandsMultiTimestampsAndAppliesOffset() {
        val raw = """
            [ti:夜曲]
            [ar:周杰伦]
            [offset:500]
            [00:12.34][01:45.67]为你弹奏肖邦的夜曲
            [00:05.00]前奏渐起
            [02:10:05]尾声余韵
        """.trimIndent()

        val lines = parseLrcLyrics(raw)
        assertEquals(4, lines.size)
        assertEquals(5_500L, lines[0].timeMs)
        assertEquals("前奏渐起", lines[0].text)

        assertEquals(12_840L, lines[1].timeMs)
        assertEquals("为你弹奏肖邦的夜曲", lines[1].text)

        assertEquals(106_170L, lines[2].timeMs)
        assertEquals("为你弹奏肖邦的夜曲", lines[2].text)

        assertEquals(130_550L, lines[3].timeMs)
        assertEquals("尾声余韵", lines[3].text)
    }

    @Test
    fun smartNextPlayableEpisodeIndexPrefersResumableThenUnplayedThenZero() {
        assertNull(MoviePilotRepository.smartNextPlayableEpisodeIndex(emptyList()))

        val withResume = listOf(
            MediaServerBrowseItemDto(itemId = "ep1", played = true, resumePositionMs = 0L),
            MediaServerBrowseItemDto(itemId = "ep2", played = false, resumePositionMs = 10_000L),
            MediaServerBrowseItemDto(itemId = "ep3", played = false, resumePositionMs = 95_000L),
        )
        assertEquals(2, MoviePilotRepository.smartNextPlayableEpisodeIndex(withResume))

        val onlyUnplayed = listOf(
            MediaServerBrowseItemDto(itemId = "ep1", played = true, resumePositionMs = 120_000L),
            MediaServerBrowseItemDto(itemId = "ep2", played = false, resumePositionMs = 0L),
            MediaServerBrowseItemDto(itemId = "ep3", played = false, resumePositionMs = 0L),
        )
        assertEquals(1, MoviePilotRepository.smartNextPlayableEpisodeIndex(onlyUnplayed))

        val allPlayed = listOf(
            MediaServerBrowseItemDto(itemId = "ep1", played = true, resumePositionMs = 0L),
            MediaServerBrowseItemDto(itemId = "ep2", played = true, resumePositionMs = 60_000L),
        )
        assertEquals(0, MoviePilotRepository.smartNextPlayableEpisodeIndex(allPlayed))
    }

    @Test
    fun chineseSubtitleMatcherRecognizesSimplifiedTraditionalAndIsoCodes() {
        listOf(
            "zh" to null,
            "chi" to null,
            "zho" to null,
            "cmn" to null,
            "chs" to null,
            "cht" to null,
            "und" to "简体中字 ASS",
            "und" to "繁体中文",
            null to "特效中文字幕",
        ).forEach { (lang, label) ->
            assertTrue(
                "Expected Chinese match for lang=$lang label=$label",
                ChineseSubtitleMatcher.isChineseSubtitle(lang, label),
            )
        }

        assertFalse(ChineseSubtitleMatcher.isChineseSubtitle("en", "English SDH"))
        assertFalse(ChineseSubtitleMatcher.isChineseSubtitle("ja", "Japanese"))

        val simplifiedScore = ChineseSubtitleMatcher.scoreChineseSubtitle("zh-Hans", "简体中文", isExternal = true)
        val traditionalScore = ChineseSubtitleMatcher.scoreChineseSubtitle("zh-Hant", "繁体中文", isExternal = false)
        assertTrue(simplifiedScore > traditionalScore)
    }

    @Test
    fun localPlaybackHistoryStoreEnforcesThresholdsAndInstanceIsolation() {
        val keyA = LocalPlaybackHistoryStore.computeResumeKey("https://mp-a.example.com/", "Emby", "item-42")
        val keyA2 = LocalPlaybackHistoryStore.computeResumeKey("https://mp-a.example.com", "emby", "item-42")
        val keyB = LocalPlaybackHistoryStore.computeResumeKey("https://mp-b.example.com", "Emby", "item-42")
        assertEquals(64, keyA.length)
        assertEquals(keyA, keyA2)
        assertNotEquals(keyA, keyB)

        assertFalse(LocalPlaybackHistoryStore.shouldPersistProgress(positionMs = 29_999L, durationMs = 600_000L))
        assertTrue(LocalPlaybackHistoryStore.shouldPersistProgress(positionMs = 31_000L, durationMs = 600_000L))
        assertFalse(LocalPlaybackHistoryStore.shouldPersistProgress(positionMs = 575_000L, durationMs = 600_000L))
        assertTrue(LocalPlaybackHistoryStore.shouldClearProgress(positionMs = 575_000L, durationMs = 600_000L))
        assertEquals(180_000L, LocalPlaybackHistoryStore.resolveBestResumeMs(180_000L, 120_000L))

        val store = LocalPlaybackHistoryStore(null)
        store.recordPlaybackProgress("https://mp.example", "Emby", "ep-9", positionMs = 15_000L, durationMs = 1_000_000L)
        assertEquals(0L, store.readResumePositionMs("https://mp.example", "Emby", "ep-9"))

        store.recordPlaybackProgress("https://mp.example", "Emby", "ep-9", positionMs = 145_000L, durationMs = 1_000_000L)
        assertEquals(145_000L, store.readResumePositionMs("https://mp.example", "Emby", "ep-9"))

        store.recordPlaybackProgress("https://mp.example", "Emby", "ep-9", positionMs = 960_000L, durationMs = 1_000_000L)
        assertEquals(0L, store.readResumePositionMs("https://mp.example", "Emby", "ep-9"))
    }

    @Test
    fun musicBrainzFeedEndpointsUseChartAndFreshModes() {
        val (popSegments, popQuery) = MoviePilotRepository.buildMusicFeedEndpoint("popular", page = 2)
        assertEquals(listOf("music", "explore"), popSegments)
        val popMap = popQuery.toMap()
        assertEquals("chart", popMap["mode"])
        assertEquals("album", popMap["entity"])
        assertEquals("this_month", popMap["range_name"])
        assertEquals("musicbrainz", popMap["media_source"])
        assertEquals("2", popMap["page"])

        val (latestSegments, latestQuery) = MoviePilotRepository.buildMusicFeedEndpoint("latest", page = 1)
        assertEquals(listOf("music", "explore"), latestSegments)
        val latestMap = latestQuery.toMap()
        assertEquals("fresh", latestMap["mode"])
        assertEquals("30", latestMap["days"])
        assertEquals("musicbrainz", latestMap["media_source"])
        assertEquals("1", latestMap["page"])

        val (doubanSegments, _) = MoviePilotRepository.buildMusicFeedEndpoint("douban", page = 1)
        assertEquals(listOf("recommend", "music_douban"), doubanSegments)

        val (weeklySegments, _) = MoviePilotRepository.buildMusicFeedEndpoint("weekly", page = 1)
        assertEquals(listOf("recommend", "music_weekly"), weeklySegments)
    }

    @Test
    fun playbackPreferencesStoreDefaultsAndSupportedSpeedsMatchSpec() {
        val store = PlaybackPreferencesStore(null)
        assertTrue(store.hwDecode)
        assertTrue(store.autoPip)
        assertTrue(store.preferChineseSub)
        assertFalse(store.cellularWarn)
        assertTrue(store.keepMusicMiniBar)
        assertEquals("自适应原画", store.defaultQuality)
        assertEquals(1.0f, store.defaultSpeed, 0.001f)
        assertEquals(0, store.defaultResizeMode)
        assertEquals(listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f), PLAYER_SUPPORTED_SPEEDS)

        store.updatePreferChineseSub(false)
        store.updateCellularWarn(true)
        store.updateKeepMusicMiniBar(false)
        store.updateDefaultSpeed(0.5f)
        assertFalse(store.preferChineseSub)
        assertTrue(store.cellularWarn)
        assertFalse(store.keepMusicMiniBar)
        assertEquals(0.5f, store.defaultSpeed, 0.001f)
    }

    @Test
    fun sameOriginTransportStripsCredentialsOnCrossOriginRedirect() {
        val headers = mapOf(
            "Authorization" to "Bearer secret-jwt",
            "Cookie" to "mp_img=token123",
            "X-Custom" to "keep-me",
        )
        val sameHop = PlaybackHttpDataSource.filterHeadersForTarget(
            originUrl = "https://mp.example.com:8443/api/v1/mediaserver/stream",
            targetUrl = "https://mp.example.com:8443/emby/videos/1/stream.mkv",
            headers = headers,
        )
        assertEquals("Bearer secret-jwt", sameHop["Authorization"])
        assertEquals("mp_img=token123", sameHop["Cookie"])

        val crossHost = PlaybackHttpDataSource.filterHeadersForTarget(
            originUrl = "https://mp.example.com:8443/api/v1/mediaserver/stream",
            targetUrl = "https://cdn.external.example/videos/1/stream.mkv",
            headers = headers,
        )
        assertNull(crossHost["Authorization"])
        assertNull(crossHost["Cookie"])
        assertEquals("keep-me", crossHost["X-Custom"])

        val crossPort = PlaybackHttpDataSource.filterHeadersForTarget(
            originUrl = "https://mp.example.com:8443/api/v1/mediaserver/stream",
            targetUrl = "https://mp.example.com:9443/videos/1/stream.mkv",
            headers = headers,
        )
        assertNull(crossPort["Authorization"])
        assertNull(crossPort["Cookie"])
    }

    @Test
    fun pipAspectRatioClampingAndDashboardCommunityFirstOrder() {
        assertEquals(16 to 9, PlaybackPipBridge.clampAspectRatioPair(0, 0))
        assertEquals(1920 to 1080, PlaybackPipBridge.clampAspectRatioPair(1920, 1080))
        assertEquals(239 to 100, PlaybackPipBridge.clampAspectRatioPair(3840, 1000))
        assertEquals(100 to 239, PlaybackPipBridge.clampAspectRatioPair(400, 1600))

        assertEquals("community", defaultDashboardModuleIds().first())
    }

    @Test
    fun strmExtensionAndDirectLinkParserExtractsUrlHeadersAndKind() {
        val store = PlaybackPreferencesStore(context = null)
        assertTrue(store.strmDirectPlay)
        store.updateStrmDirectPlay(false)
        assertFalse(store.strmDirectPlay)

        assertEquals("video", com.moviepilot.rustbridge.RustCoreBridge.detectMediaKind("/media/Avatar.strm", false))
        assertEquals("audio", com.moviepilot.rustbridge.RustCoreBridge.detectMediaKind("/music/Track.flac.strm", false))

        val rawStrm = "\uFEFF#EXTM3U\n#EXTVLCOPT:http-user-agent=Mozilla/5.0 (115Browser)\n#EXTVLCOPT:http-referrer=https://115.com/\nhttps://openlist.example.test:5244/d/电影/阿凡达 [4K]/Avatar 100% Pure.mkv?sign=abc%2B1\n"
        val spec = com.moviepilot.rustbridge.RustCoreBridge.parseStrm(rawStrm, "Avatar.strm")
        assertNotNull(spec)
        assertEquals(
            "https://openlist.example.test:5244/d/%E7%94%B5%E5%BD%B1/%E9%98%BF%E5%87%A1%E8%BE%BE%20%5B4K%5D/Avatar%20100%25%20Pure.mkv?sign=abc%2B1",
            spec?.url,
        )
        assertEquals("video", spec?.mediaKind)
        assertEquals("Mozilla/5.0 (115Browser)", spec?.headers?.get("User-Agent"))
        assertEquals("https://115.com/", spec?.headers?.get("Referer"))

        assertNull(com.moviepilot.rustbridge.RustCoreBridge.parseStrm("file:///etc/passwd", null))
        assertNull(com.moviepilot.rustbridge.RustCoreBridge.parseStrm("http://user:pass@192.168.1.1/a.mp4", null))
    }

    @Test
    fun mainTabNavigationReturnsToDiscoverAfterVisitingOtherTabs() {
        var selectedTabId = com.moviepilot.designsystem.MainTab.Discover.id
        val subStacks = mutableMapOf(
            com.moviepilot.designsystem.MainTab.Discover to mutableListOf<String>(),
            com.moviepilot.designsystem.MainTab.Subscribe to mutableListOf<String>(),
            com.moviepilot.designsystem.MainTab.Dashboard to mutableListOf<String>(),
            com.moviepilot.designsystem.MainTab.Workspace to mutableListOf<String>(),
        )
        fun currentTab(): com.moviepilot.designsystem.MainTab =
            com.moviepilot.designsystem.MainTab.entries.firstOrNull { it.id == selectedTabId }
                ?: com.moviepilot.designsystem.MainTab.Discover

        // 模拟记忆化后的稳定回调：即使不重新创建闭包，点击任意 Tab 也必须读取实时 selectedTabId
        val memoizedOnTabClick: (com.moviepilot.designsystem.MainTab) -> Unit = { tab ->
            when (resolveMainTabClick(currentTab(), tab, subStacks[tab].orEmpty().isNotEmpty())) {
                MainTabClickAction.SwitchTab -> selectedTabId = tab.id
                MainTabClickAction.ClearActiveStack -> subStacks[tab]?.clear()
                MainTabClickAction.NoOp -> Unit
            }
        }

        // 首次在「发现」切到「订阅」，再点回「发现」必须切回 Discover
        memoizedOnTabClick(com.moviepilot.designsystem.MainTab.Subscribe)
        assertEquals(com.moviepilot.designsystem.MainTab.Subscribe, currentTab())
        memoizedOnTabClick(com.moviepilot.designsystem.MainTab.Discover)
        assertEquals(com.moviepilot.designsystem.MainTab.Discover, currentTab())

        // 依次访问「我的」「更多」后再点「发现」依然能切回 Discover
        memoizedOnTabClick(com.moviepilot.designsystem.MainTab.Dashboard)
        assertEquals(com.moviepilot.designsystem.MainTab.Dashboard, currentTab())
        memoizedOnTabClick(com.moviepilot.designsystem.MainTab.Workspace)
        assertEquals(com.moviepilot.designsystem.MainTab.Workspace, currentTab())
        memoizedOnTabClick(com.moviepilot.designsystem.MainTab.Discover)
        assertEquals(com.moviepilot.designsystem.MainTab.Discover, currentTab())

        // 停留在当前 Tab 且存在二级页面时，再次点击清空该 Tab 子栈
        subStacks[com.moviepilot.designsystem.MainTab.Discover]?.add("explore")
        memoizedOnTabClick(com.moviepilot.designsystem.MainTab.Discover)
        assertTrue(subStacks[com.moviepilot.designsystem.MainTab.Discover].orEmpty().isEmpty())
        assertEquals(com.moviepilot.designsystem.MainTab.Discover, currentTab())
    }

    @Test
    fun directPlayRoutePlannerPrioritizesLanWithinThresholdAndStripsCrossOriginDirectTokens() {
        val store = PlaybackPreferencesStore(context = null)
        assertTrue(store.directPlay)
        store.updateDirectPlay(false)
        assertFalse(store.directPlay)

        val routes = listOf(
            com.moviepilot.rustbridge.PlaybackRouteDto(
                kind = "server_lan",
                url = "http://192.168.1.10:8096/emby/Videos/1/stream?Static=true",
                probeUrl = "http://192.168.1.10:8096/emby/System/Ping",
                headers = mapOf("X-Emby-Token" to "user-tok-1"),
                priority = 20,
            ),
            com.moviepilot.rustbridge.PlaybackRouteDto(
                kind = "server_wan",
                url = "https://emby.example.com/emby/Videos/1/stream?Static=true",
                probeUrl = "https://emby.example.com/emby/System/Ping",
                headers = mapOf("X-Emby-Token" to "user-tok-1"),
                priority = 30,
            ),
            com.moviepilot.rustbridge.PlaybackRouteDto(
                kind = "mp_proxy",
                url = "https://mp.example.com/api/v1/mediaserver/stream?itemid=1",
                priority = 100,
                requiresSameOriginAuth = true,
            ),
        )
        val probes = listOf(
            com.moviepilot.rustbridge.RouteProbeOutcomeDto(
                url = "http://192.168.1.10:8096/emby/System/Ping",
                reachable = true,
                latencyMs = 95,
            ),
            com.moviepilot.rustbridge.RouteProbeOutcomeDto(
                url = "https://emby.example.com/emby/System/Ping",
                reachable = true,
                latencyMs = 42,
            ),
        )
        val plan = com.moviepilot.rustbridge.RustCoreBridge.planPlaybackRoutes(routes, probes = probes)
        assertNotNull(plan)
        assertEquals("server_lan", plan?.active?.kind)
        assertEquals("局域网直连", plan?.routeLabelZh)
        assertEquals(listOf("server_wan", "mp_proxy"), plan?.fallbacks?.map { it.kind })

        val disabledPlan = com.moviepilot.rustbridge.RustCoreBridge.planPlaybackRoutes(
            routes = routes,
            preferences = com.moviepilot.rustbridge.PlaybackRoutePreferenceDto(
                preferStrmDirect = false,
                preferServerDirect = false,
            ),
            probes = probes,
        )
        assertEquals("mp_proxy", disabledPlan?.active?.kind)
        assertTrue(disabledPlan?.fallbacks.orEmpty().isEmpty())

        val directHeaders = mapOf(
            "X-Emby-Token" to "personal-emby-tok",
            "X-Plex-Token" to "personal-plex-tok",
            "User-Agent" to "MoviePilot/2.0",
        )
        val cdnHop = PlaybackHttpDataSource.filterHeadersForTarget(
            originUrl = "https://emby.example.com/emby/Videos/1/stream",
            targetUrl = "https://cdn.115.com/signed.mkv",
            headers = directHeaders,
        )
        assertNull(cdnHop["X-Emby-Token"])
        assertNull(cdnHop["X-Plex-Token"])
        assertEquals("MoviePilot/2.0", cdnHop["User-Agent"])
        assertFalse(
            PlaybackHttpDataSource.isSameOriginHostPort(
                "https://emby.example.com:8096/a",
                "http://emby.example.com:8096/a",
            ),
        )
    }

    @Test
    fun multiEngineRouterAndPreferencesAndLoopbackProxySecurityContract() {
        val prefs = PlaybackPreferencesStore(context = null)
        assertEquals("auto", prefs.videoEngine)
        assertEquals("hw_auto", prefs.decodeMode)
        assertEquals("standard", prefs.bufferProfile)
        assertEquals("surface", prefs.surfaceType)
        assertFalse(prefs.audioNightMode)
        assertFalse(prefs.ignoreAssStyle)
        assertFalse(prefs.defaultExternalPlayer)

        prefs.updateVideoEngine("enhanced")
        prefs.updateDecodeMode("sw_force")
        prefs.updateBufferProfile("large")
        prefs.updateSurfaceType("texture")
        prefs.updateAudioNightMode(true)
        prefs.updateIgnoreAssStyle(true)
        prefs.updateSubtitleScale(1.15f)
        prefs.updateDefaultExternalPlayer(true)
        assertEquals("enhanced", prefs.videoEngine)
        assertEquals("sw_force", prefs.decodeMode)
        assertFalse(prefs.hwDecode)
        assertEquals("large", prefs.bufferProfile)
        assertEquals("texture", prefs.surfaceType)
        assertTrue(prefs.audioNightMode)
        assertTrue(prefs.ignoreAssStyle)
        assertTrue(prefs.defaultExternalPlayer)

        // 1. 常规 MP4 自动模式走 Media3 原生并配置 MPV 回退
        val mp4Plan = com.moviepilot.rustbridge.RustCoreBridge.resolvePlaybackEngine(
            com.moviepilot.rustbridge.EngineResolutionInputDto(
                platform = "android",
                preferred = "auto",
                urlOrFilename = "https://cdn.example.com/movie.mp4",
            ),
        )
        assertEquals("native", mp4Plan.primary)
        assertEquals("enhanced", mp4Plan.fallback)

        // 2. 自动模式默认优先使用原生内核（支持失败自动回退 MPV 全能内核），仅强制软解直入 MPV
        val mkvPlan = com.moviepilot.rustbridge.RustCoreBridge.resolvePlaybackEngine(
            com.moviepilot.rustbridge.EngineResolutionInputDto(
                platform = "android",
                preferred = "auto",
                urlOrFilename = "https://cdn.example.com/anime.mkv",
            ),
        )
        assertEquals("native", mkvPlan.primary)
        assertEquals("enhanced", mkvPlan.fallback)

        val swPlan = com.moviepilot.rustbridge.RustCoreBridge.resolvePlaybackEngine(
            com.moviepilot.rustbridge.EngineResolutionInputDto(
                platform = "android",
                preferred = "auto",
                decodeForceSoftware = true,
                urlOrFilename = "https://cdn.example.com/movie.mp4",
            ),
        )
        assertEquals("enhanced", swPlan.primary)

        // 3. 外部播放器 URL 模板安全校验与敏感请求头剥离
        assertNotNull(
            com.moviepilot.rustbridge.RustCoreBridge.buildSafeExternalPlayerUrl(
                "vlc-x-callback://x-callback-url/stream?url={url}&title={title}",
                "https://cdn.example.com/demo.mkv",
                "Demo",
            ),
        )
        assertNull(
            com.moviepilot.rustbridge.RustCoreBridge.buildSafeExternalPlayerUrl(
                "javascript://alert(1)?url={url}",
                "https://cdn.example.com/demo.mkv",
                "Demo",
            ),
        )
        val stripped = PlaybackHttpDataSource.stripAllSensitiveHeaders(
            mapOf(
                "Authorization" to "Bearer secret",
                "Cookie" to "mp_token=secret",
                "X-Emby-Token" to "emby-secret",
                "User-Agent" to "MoviePilot/2.0",
            ),
        )
        assertEquals(mapOf("User-Agent" to "MoviePilot/2.0"), stripped)

        // 4. LoopbackAuthProxy 单会话随机令牌隔离：拒绝错误令牌并返回 403
        val client = okhttp3.OkHttpClient()
        val proxy = com.moviepilot.media.engine.LoopbackAuthProxy(
            okHttpClient = client,
            initialTargetUrl = "http://127.0.0.1:1/unreachable",
        )
        try {
            val badReq = okhttp3.Request.Builder()
                .url("http://127.0.0.1:${proxy.port}/wrong-token/stream")
                .build()
            client.newCall(badReq).execute().use { resp ->
                assertEquals(403, resp.code)
            }
        } finally {
            proxy.close()
        }
    }
}
