//! 3D 社区勋章金属配色与背面铭牌凹雕参数模型（供三端原生 Canvas 统一渲染）。

use serde::{Deserialize, Serialize};

/// 单枚勋章的金属基色、高光色与背面凹雕文字色。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommunityMedalPalette {
    pub medal_id: String,
    pub base_hex: String,
    pub rim_hex: String,
    pub engrave_dark_hex: String,
    pub engrave_light_hex: String,
    pub tier: String,
}

/// 社区勋章跨端共享计算逻辑。
pub struct CommunityMedalsModel;

impl CommunityMedalsModel {
    /// 根据真实 MoviePilot 社区勋章标识（7 大家族 / 13 款变体）计算金属材质与三遍凹雕配色。
    pub fn palette_for_medal(medal_id: &str) -> CommunityMedalPalette {
        let lower = medal_id.to_ascii_lowercase();
        if lower.contains("t4")
            || lower.contains("sponsor")
            || lower.contains("pioneer")
            || lower.contains("gold")
            || lower.contains("legend")
            || lower.contains("master")
            || lower.contains("lv5")
        {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#D4AF37".to_string(),
                rim_hex: "#F6E27F".to_string(),
                engrave_dark_hex: "#5C470D".to_string(),
                engrave_light_hex: "#FFF4C2".to_string(),
                tier: "gold".to_string(),
            }
        } else if lower.contains("code") || lower.contains("security") || lower.contains("emerald")
        {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#2EA88A".to_string(),
                rim_hex: "#E6D39A".to_string(),
                engrave_dark_hex: "#193D34".to_string(),
                engrave_light_hex: "#E8FFF7".to_string(),
                tier: "emerald".to_string(),
            }
        } else if lower.contains("plugin")
            || lower.contains("helper")
            || lower.contains("wiki")
            || lower.contains("amber")
        {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#C9853B".to_string(),
                rim_hex: "#F5D096".to_string(),
                engrave_dark_hex: "#4E2D0C".to_string(),
                engrave_light_hex: "#FFF0D6".to_string(),
                tier: "amber".to_string(),
            }
        } else if lower.contains("silver")
            || lower.contains("t3")
            || lower.contains("translate")
            || lower.contains("lv3")
            || lower.contains("lv4")
        {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#B8C1CC".to_string(),
                rim_hex: "#E8EEF5".to_string(),
                engrave_dark_hex: "#46505C".to_string(),
                engrave_light_hex: "#FFFFFF".to_string(),
                tier: "silver".to_string(),
            }
        } else if lower.contains("rose")
            || lower.contains("issue")
            || lower.contains("tester")
            || lower.contains("community")
            || lower.contains("contributor")
        {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#C98B9E".to_string(),
                rim_hex: "#F2C6D4".to_string(),
                engrave_dark_hex: "#5A2E3D".to_string(),
                engrave_light_hex: "#FFE8F0".to_string(),
                tier: "rose".to_string(),
            }
        } else {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#8F7CE6".to_string(),
                rim_hex: "#CBBFFF".to_string(),
                engrave_dark_hex: "#362B66".to_string(),
                engrave_light_hex: "#EFEAFF".to_string(),
                tier: "violet".to_string(),
            }
        }
    }

    /// 编剧勋章单仓有效采纳数：`max(commits, merged_prs)`，不重复叠加。
    pub fn effective_repo_count(commits: i32, merged_prs: i32) -> i32 {
        commits.max(merged_prs).max(0)
    }
}
