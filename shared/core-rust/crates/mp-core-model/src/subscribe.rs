//! 订阅剧集完成度与进度条计算模型。

use serde::{Deserialize, Serialize};

/// 订阅进度值对象。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SubscribeProgress {
    pub total: i32,
    pub completed: i32,
    pub lack: i32,
    pub ratio: f64,
    pub label: String,
}

/// 跨端共享订阅进度算法。
pub struct SubscribeProgressModel;

impl SubscribeProgressModel {
    /// 按总集数与缺失集数计算已完成数与进度比例（0.0..=1.0）。
    pub fn compute(total_episode: i32, lack_episode: i32) -> SubscribeProgress {
        let total = total_episode.max(0);
        let lack = lack_episode.clamp(0, total);
        let completed = (total - lack).max(0);
        let ratio = if total > 0 {
            (completed as f64 / total as f64).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let label = if total > 0 {
            format!("{completed}/{total}")
        } else {
            "监控中".to_string()
        };
        SubscribeProgress {
            total,
            completed,
            lack,
            ratio,
            label,
        }
    }
}
