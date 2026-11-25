//! 跨端共享播放进度与实时会话上报状态机（供 iOS / Android / HarmonyOS 复用）。
//!
//! 统一控制起播 `Start`、播放中心跳（10 秒）、暂停保活心跳（12 秒，超时 15 分钟自动释放会话）、
//! 拖拽进度防抖（300 毫秒）、音轨/字幕切换即刻上报、终态 `stopped` 幂等，以及离线待补报队列整理。

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 播放中进度心跳间隔（毫秒）。
pub const PLAYING_HEARTBEAT_INTERVAL_MS: i64 = 10_000;
/// 暂停保活心跳间隔（毫秒），防止媒体服务器 60-90 秒后清理活跃会话。
pub const PAUSED_HEARTBEAT_INTERVAL_MS: i64 = 12_000;
/// 连续暂停达到该时长后自动发送 `stopped` 释放远端会话（15 分钟）。
pub const PAUSED_AUTO_STOP_MS: i64 = 15 * 60 * 1_000;
/// 连续拖拽进度时的最小上报防抖窗口（毫秒）。
pub const SEEK_DEBOUNCE_MS: i64 = 300;
/// 离线待补报 `stopped` 记录最长保留时间（7 天）。
pub const PENDING_STOP_TTL_MS: i64 = 7 * 24 * 60 * 60 * 1_000;
/// 离线待补报队列最大保留条数。
pub const MAX_PENDING_STOPS: usize = 30;
/// 单次心跳允许累加到有效播放耗时的最大时间跨度（防止休眠时钟跳变）。
const MAX_PLAYBACK_DELTA_MS: i64 = 60_000;

/// 触发播放进度规划的客户端事件类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlaybackSyncTrigger {
    Start,
    Tick,
    Pause,
    Resume,
    Seek,
    TrackChange,
    Background,
    Stop,
    Finish,
}

/// 单个播放会话在客户端持久化的最小状态机快照。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaybackSyncState {
    #[serde(default)]
    pub play_session_id: String,
    #[serde(default)]
    pub started_sent: bool,
    #[serde(default)]
    pub stopped_sent: bool,
    #[serde(default)]
    pub paused_since_ms: Option<i64>,
    #[serde(default)]
    pub last_report_at_ms: Option<i64>,
    #[serde(default)]
    pub last_playing_tick_at_ms: Option<i64>,
    #[serde(default)]
    pub last_seek_at_ms: Option<i64>,
    #[serde(default)]
    pub cumulative_playback_time_ms: i64,
    #[serde(default)]
    pub seq: u64,
    #[serde(default)]
    pub last_position_ms: i64,
    #[serde(default)]
    pub last_audio_stream_index: Option<i32>,
    #[serde(default)]
    pub last_subtitle_stream_index: Option<i32>,
}

/// 单步规划的实时播放器采样输入。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaybackSyncInput {
    pub trigger: PlaybackSyncTrigger,
    pub now_ms: i64,
    pub position_ms: i64,
    #[serde(default)]
    pub duration_ms: Option<i64>,
    #[serde(default)]
    pub is_paused: bool,
    #[serde(default)]
    pub audio_stream_index: Option<i32>,
    #[serde(default)]
    pub subtitle_stream_index: Option<i32>,
}

/// 单步规划输出：指明本步是否应发送上报请求以及携带的规范字段。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaybackSyncDecision {
    pub should_report: bool,
    pub state: String,
    pub event_name: Option<String>,
    pub is_paused: bool,
    pub position_ms: i64,
    pub playback_time_ms: i64,
    pub seq: u64,
    pub next_state: PlaybackSyncState,
}

/// 离线或网络异常时缓存的终态 `stopped` 补报条目。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingPlaybackStop {
    pub server: String,
    pub item_id: String,
    #[serde(default)]
    pub media_source_id: Option<String>,
    pub position_ms: i64,
    #[serde(default)]
    pub duration_ms: Option<i64>,
    #[serde(default)]
    pub play_session_id: Option<String>,
    #[serde(default)]
    pub playback_time_ms: Option<i64>,
    #[serde(default)]
    pub seq: Option<u64>,
    pub updated_at_ms: i64,
}

/// 跨端统一的播放进度与实时会话上报状态机。
pub struct PlaybackProgressPlanner;

impl PlaybackProgressPlanner {
    /// 基于当前会话状态与本次播放器事件，计算是否应立即上报以及更新后的状态。
    pub fn step(current: &PlaybackSyncState, input: &PlaybackSyncInput) -> PlaybackSyncDecision {
        let mut next = current.clone();
        let now = input.now_ms.max(0);

        // 1. 累计真实播放耗时（仅在处于播放中且时间戳前移时累加，防止休眠大跨度污染）
        if !input.is_paused
            && !matches!(
                input.trigger,
                PlaybackSyncTrigger::Pause | PlaybackSyncTrigger::Background
            )
        {
            if let Some(prev_tick) = next.last_playing_tick_at_ms {
                let delta = now.saturating_sub(prev_tick);
                if delta > 0 {
                    next.cumulative_playback_time_ms = next
                        .cumulative_playback_time_ms
                        .saturating_add(delta.min(MAX_PLAYBACK_DELTA_MS));
                }
            }
            next.last_playing_tick_at_ms = Some(now);
        } else {
            next.last_playing_tick_at_ms = None;
        }

        // 2. 计算当前有效播放位置：Seek 始终信任新位置（支持向后拖回 0）；其余场景仅当实时值为 <=0 且存在历史进度时兜底
        let resolved_pos = match input.trigger {
            PlaybackSyncTrigger::Seek => input.position_ms.max(0),
            PlaybackSyncTrigger::Finish => input
                .duration_ms
                .filter(|d| *d > 0)
                .unwrap_or_else(|| input.position_ms.max(next.last_position_ms).max(0)),
            _ => {
                if input.position_ms > 0 {
                    input.position_ms
                } else if next.last_position_ms > 0
                    && matches!(
                        input.trigger,
                        PlaybackSyncTrigger::Stop
                            | PlaybackSyncTrigger::Pause
                            | PlaybackSyncTrigger::Background
                    )
                {
                    next.last_position_ms
                } else {
                    input.position_ms.max(0)
                }
            }
        };
        next.last_position_ms = resolved_pos;

        // 3. 终态停止幂等检查：已发送过 stopped 后，仅允许显式重新起播或暂停超时后的恢复播放重新激活会话
        if next.stopped_sent {
            let allow_reactivate = matches!(
                input.trigger,
                PlaybackSyncTrigger::Start | PlaybackSyncTrigger::Resume
            ) || (input.trigger == PlaybackSyncTrigger::Tick
                && !input.is_paused);
            if !allow_reactivate {
                return Self::no_report(next, "stopped", true, resolved_pos);
            }
            next.stopped_sent = false;
            next.started_sent = false;
            next.paused_since_ms = None;
        }

        match input.trigger {
            PlaybackSyncTrigger::Stop | PlaybackSyncTrigger::Finish => {
                next.stopped_sent = true;
                next.paused_since_ms = None;
                next.last_playing_tick_at_ms = None;
                Self::emit(next, now, "stopped", None, true, resolved_pos)
            }
            PlaybackSyncTrigger::Start => {
                next.started_sent = true;
                next.stopped_sent = false;
                next.paused_since_ms = None;
                next.last_audio_stream_index = input.audio_stream_index;
                next.last_subtitle_stream_index = input.subtitle_stream_index;
                Self::emit(next, now, "started", Some("Start"), false, resolved_pos)
            }
            PlaybackSyncTrigger::Pause | PlaybackSyncTrigger::Background => {
                if next.paused_since_ms.is_none() {
                    next.paused_since_ms = Some(now);
                }
                Self::emit(next, now, "paused", Some("Pause"), true, resolved_pos)
            }
            PlaybackSyncTrigger::Resume => {
                next.paused_since_ms = None;
                if !next.started_sent {
                    next.started_sent = true;
                    Self::emit(next, now, "started", Some("Start"), false, resolved_pos)
                } else {
                    Self::emit(next, now, "playing", Some("Unpause"), false, resolved_pos)
                }
            }
            PlaybackSyncTrigger::Seek => {
                let within_debounce = next
                    .last_seek_at_ms
                    .is_some_and(|prev| now.saturating_sub(prev) < SEEK_DEBOUNCE_MS);
                next.last_seek_at_ms = Some(now);
                if within_debounce {
                    return Self::no_report(
                        next,
                        if input.is_paused { "paused" } else { "playing" },
                        input.is_paused,
                        resolved_pos,
                    );
                }
                let state_str = if input.is_paused { "paused" } else { "playing" };
                Self::emit(
                    next,
                    now,
                    state_str,
                    Some("TimeUpdate"),
                    input.is_paused,
                    resolved_pos,
                )
            }
            PlaybackSyncTrigger::TrackChange => {
                let event_name = if input.audio_stream_index != next.last_audio_stream_index {
                    "AudioTrackChange"
                } else if input.subtitle_stream_index != next.last_subtitle_stream_index {
                    "SubtitleTrackChange"
                } else {
                    "TimeUpdate"
                };
                next.last_audio_stream_index = input.audio_stream_index;
                next.last_subtitle_stream_index = input.subtitle_stream_index;
                let state_str = if input.is_paused { "paused" } else { "playing" };
                Self::emit(
                    next,
                    now,
                    state_str,
                    Some(event_name),
                    input.is_paused,
                    resolved_pos,
                )
            }
            PlaybackSyncTrigger::Tick => {
                if !input.is_paused && !next.started_sent {
                    next.started_sent = true;
                    next.paused_since_ms = None;
                    return Self::emit(next, now, "started", Some("Start"), false, resolved_pos);
                }
                if input.is_paused {
                    let paused_since = *next.paused_since_ms.get_or_insert(now);
                    if now.saturating_sub(paused_since) >= PAUSED_AUTO_STOP_MS {
                        next.stopped_sent = true;
                        next.paused_since_ms = None;
                        return Self::emit(next, now, "stopped", None, true, resolved_pos);
                    }
                    let due = next.last_report_at_ms.is_none_or(|last| {
                        now.saturating_sub(last) >= PAUSED_HEARTBEAT_INTERVAL_MS
                    });
                    if due {
                        Self::emit(next, now, "paused", Some("Pause"), true, resolved_pos)
                    } else {
                        Self::no_report(next, "paused", true, resolved_pos)
                    }
                } else {
                    next.paused_since_ms = None;
                    let due = next.last_report_at_ms.is_none_or(|last| {
                        now.saturating_sub(last) >= PLAYING_HEARTBEAT_INTERVAL_MS
                    });
                    if due {
                        Self::emit(
                            next,
                            now,
                            "playing",
                            Some("TimeUpdate"),
                            false,
                            resolved_pos,
                        )
                    } else {
                        Self::no_report(next, "playing", false, resolved_pos)
                    }
                }
            }
        }
    }

    /// 规整离线待补报 `stopped` 队列：按 `(server, item_id)` 去重取最新、清理超过 7 天过期项并裁剪至上限。
    pub fn normalize_pending_stops(
        entries: Vec<PendingPlaybackStop>,
        now_epoch_ms: i64,
    ) -> Vec<PendingPlaybackStop> {
        let mut latest_by_key: HashMap<(String, String), PendingPlaybackStop> = HashMap::new();
        for mut entry in entries {
            let server = entry.server.trim().to_string();
            let item_id = entry.item_id.trim().to_string();
            if server.is_empty() || item_id.is_empty() {
                continue;
            }
            if now_epoch_ms > 0
                && entry.updated_at_ms > 0
                && now_epoch_ms.saturating_sub(entry.updated_at_ms) > PENDING_STOP_TTL_MS
            {
                continue;
            }
            entry.server = server.clone();
            entry.item_id = item_id.clone();
            entry.position_ms = entry.position_ms.max(0);
            let key = (server, item_id);
            match latest_by_key.get(&key) {
                Some(existing) if existing.updated_at_ms > entry.updated_at_ms => {}
                _ => {
                    latest_by_key.insert(key, entry);
                }
            }
        }
        let mut result: Vec<PendingPlaybackStop> = latest_by_key.into_values().collect();
        result.sort_by(|a, b| {
            b.updated_at_ms
                .cmp(&a.updated_at_ms)
                .then_with(|| a.server.cmp(&b.server))
                .then_with(|| a.item_id.cmp(&b.item_id))
        });
        result.truncate(MAX_PENDING_STOPS);
        result
    }

    fn emit(
        mut next: PlaybackSyncState,
        now_ms: i64,
        state: &str,
        event_name: Option<&str>,
        is_paused: bool,
        position_ms: i64,
    ) -> PlaybackSyncDecision {
        next.seq = next.seq.saturating_add(1);
        next.last_report_at_ms = Some(now_ms);
        let seq = next.seq;
        let playback_time_ms = next.cumulative_playback_time_ms;
        PlaybackSyncDecision {
            should_report: true,
            state: state.to_string(),
            event_name: event_name.map(str::to_string),
            is_paused,
            position_ms,
            playback_time_ms,
            seq,
            next_state: next,
        }
    }

    fn no_report(
        next: PlaybackSyncState,
        state: &str,
        is_paused: bool,
        position_ms: i64,
    ) -> PlaybackSyncDecision {
        let seq = next.seq;
        let playback_time_ms = next.cumulative_playback_time_ms;
        PlaybackSyncDecision {
            should_report: false,
            state: state.to_string(),
            event_name: None,
            is_paused,
            position_ms,
            playback_time_ms,
            seq,
            next_state: next,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(trigger: PlaybackSyncTrigger, now_ms: i64, position_ms: i64) -> PlaybackSyncInput {
        PlaybackSyncInput {
            trigger,
            now_ms,
            position_ms,
            duration_ms: Some(3_600_000),
            is_paused: false,
            audio_stream_index: None,
            subtitle_stream_index: None,
        }
    }

    #[test]
    fn emits_start_then_10s_playing_heartbeats_and_accumulates_time() {
        let mut state = PlaybackSyncState {
            play_session_id: "sid-1".to_string(),
            ..Default::default()
        };

        let d1 =
            PlaybackProgressPlanner::step(&state, &input(PlaybackSyncTrigger::Start, 1_000, 0));
        assert!(d1.should_report);
        assert_eq!(d1.state, "started");
        assert_eq!(d1.event_name.as_deref(), Some("Start"));
        assert_eq!(d1.seq, 1);
        state = d1.next_state;

        // 5 秒后不到心跳周期
        let d2 =
            PlaybackProgressPlanner::step(&state, &input(PlaybackSyncTrigger::Tick, 6_000, 5_000));
        assert!(!d2.should_report);
        assert_eq!(d2.playback_time_ms, 5_000);
        state = d2.next_state;

        // 11 秒达到 10 秒间隔触发 TimeUpdate
        let d3 = PlaybackProgressPlanner::step(
            &state,
            &input(PlaybackSyncTrigger::Tick, 11_000, 10_000),
        );
        assert!(d3.should_report);
        assert_eq!(d3.state, "playing");
        assert_eq!(d3.event_name.as_deref(), Some("TimeUpdate"));
        assert_eq!(d3.playback_time_ms, 10_000);
        assert_eq!(d3.seq, 2);
    }

    #[test]
    fn paused_keeps_session_alive_and_auto_stops_after_15_minutes_then_reactivates() {
        let mut state = PlaybackSyncState::default();
        state = PlaybackProgressPlanner::step(&state, &input(PlaybackSyncTrigger::Start, 1_000, 0))
            .next_state;

        let mut pause_in = input(PlaybackSyncTrigger::Pause, 10_000, 9_000);
        pause_in.is_paused = true;
        let d_pause = PlaybackProgressPlanner::step(&state, &pause_in);
        assert!(d_pause.should_report);
        assert_eq!(d_pause.state, "paused");
        state = d_pause.next_state;

        // 12 秒后暂停保活心跳
        let mut tick_pause = input(PlaybackSyncTrigger::Tick, 22_000, 9_000);
        tick_pause.is_paused = true;
        let d_keepalive = PlaybackProgressPlanner::step(&state, &tick_pause);
        assert!(d_keepalive.should_report);
        assert_eq!(d_keepalive.state, "paused");
        state = d_keepalive.next_state;

        // 暂停满 15 分钟自动发送 stopped
        let mut tick_expire = input(
            PlaybackSyncTrigger::Tick,
            10_000 + PAUSED_AUTO_STOP_MS,
            9_000,
        );
        tick_expire.is_paused = true;
        let d_auto_stop = PlaybackProgressPlanner::step(&state, &tick_expire);
        assert!(d_auto_stop.should_report);
        assert_eq!(d_auto_stop.state, "stopped");
        assert!(d_auto_stop.next_state.stopped_sent);
        state = d_auto_stop.next_state;

        // 继续暂停期间不再重复发送 stopped
        let mut tick_after = input(
            PlaybackSyncTrigger::Tick,
            10_000 + PAUSED_AUTO_STOP_MS + 20_000,
            9_000,
        );
        tick_after.is_paused = true;
        let d_dup = PlaybackProgressPlanner::step(&state, &tick_after);
        assert!(!d_dup.should_report);
        state = d_dup.next_state;

        // 用户恢复播放应重新发送 Start
        let d_resume = PlaybackProgressPlanner::step(
            &state,
            &input(
                PlaybackSyncTrigger::Resume,
                10_000 + PAUSED_AUTO_STOP_MS + 30_000,
                9_000,
            ),
        );
        assert!(d_resume.should_report);
        assert_eq!(d_resume.state, "started");
        assert_eq!(d_resume.event_name.as_deref(), Some("Start"));
    }

    #[test]
    fn backward_seek_replaces_last_position_and_debounces_rapid_scrubs() {
        let mut state = PlaybackSyncState {
            started_sent: true,
            last_position_ms: 120_000,
            ..Default::default()
        };
        let d1 =
            PlaybackProgressPlanner::step(&state, &input(PlaybackSyncTrigger::Seek, 5_000, 30_000));
        assert!(d1.should_report);
        assert_eq!(d1.position_ms, 30_000);
        assert_eq!(d1.next_state.last_position_ms, 30_000);
        state = d1.next_state;

        // 100ms 内的快速拖拽被防抖，但仍更新 last_position_ms
        let d2 =
            PlaybackProgressPlanner::step(&state, &input(PlaybackSyncTrigger::Seek, 5_100, 15_000));
        assert!(!d2.should_report);
        assert_eq!(d2.next_state.last_position_ms, 15_000);
        state = d2.next_state;

        // 随后停止若播放器返回 0，使用最近向后 seek 的 15_000 而非旧的 120_000
        let d_stop =
            PlaybackProgressPlanner::step(&state, &input(PlaybackSyncTrigger::Stop, 6_000, 0));
        assert!(d_stop.should_report);
        assert_eq!(d_stop.state, "stopped");
        assert_eq!(d_stop.position_ms, 15_000);
    }

    #[test]
    fn track_change_and_pending_stop_normalization() {
        let state = PlaybackSyncState {
            started_sent: true,
            last_audio_stream_index: Some(1),
            last_subtitle_stream_index: Some(-1),
            ..Default::default()
        };
        let mut tc = input(PlaybackSyncTrigger::TrackChange, 2_000, 50_000);
        tc.audio_stream_index = Some(2);
        tc.subtitle_stream_index = Some(-1);
        let d_tc = PlaybackProgressPlanner::step(&state, &tc);
        assert!(d_tc.should_report);
        assert_eq!(d_tc.event_name.as_deref(), Some("AudioTrackChange"));

        let now = 1_000_000_000_000i64;
        let normalized = PlaybackProgressPlanner::normalize_pending_stops(
            vec![
                PendingPlaybackStop {
                    server: "Emby".into(),
                    item_id: "1".into(),
                    media_source_id: None,
                    position_ms: 10_000,
                    duration_ms: Some(100_000),
                    play_session_id: Some("s1".into()),
                    playback_time_ms: Some(10_000),
                    seq: Some(1),
                    updated_at_ms: now - 10_000,
                },
                PendingPlaybackStop {
                    server: "Emby".into(),
                    item_id: "1".into(),
                    media_source_id: None,
                    position_ms: 50_000,
                    duration_ms: Some(100_000),
                    play_session_id: Some("s1".into()),
                    playback_time_ms: Some(50_000),
                    seq: Some(5),
                    updated_at_ms: now - 1_000,
                },
                PendingPlaybackStop {
                    server: "Emby".into(),
                    item_id: "expired".into(),
                    media_source_id: None,
                    position_ms: 20_000,
                    duration_ms: None,
                    play_session_id: None,
                    playback_time_ms: None,
                    seq: None,
                    updated_at_ms: now - PENDING_STOP_TTL_MS - 1_000,
                },
            ],
            now,
        );
        assert_eq!(normalized.len(), 1);
        assert_eq!(normalized[0].position_ms, 50_000);
    }
}
