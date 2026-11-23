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
    /// 根据勋章标识确定性计算金属材质配色（金/银/玫瑰金/星耀紫铜），确保三端背面雕刻视觉一致。
    pub fn palette_for_medal(medal_id: &str) -> CommunityMedalPalette {
        let lower = medal_id.to_ascii_lowercase();
        if lower.contains("gold")
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
        } else if lower.contains("silver") || lower.contains("lv3") || lower.contains("lv4") {
            CommunityMedalPalette {
                medal_id: medal_id.to_string(),
                base_hex: "#B8C1CC".to_string(),
                rim_hex: "#E8EEF5".to_string(),
                engrave_dark_hex: "#46505C".to_string(),
                engrave_light_hex: "#FFFFFF".to_string(),
                tier: "silver".to_string(),
            }
        } else if lower.contains("rose")
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
