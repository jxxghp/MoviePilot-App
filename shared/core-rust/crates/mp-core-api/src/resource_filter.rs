//! 站点资源 9 维级联筛选与同规格分组引擎：统一 iOS / Android / 鸿蒙站点资源页的核心筛选与分组算法。

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// 单条站点资源条目。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResourceItem {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub site_name: String,
    #[serde(default)]
    pub size: u64,
    #[serde(default)]
    pub seeders: u32,
    #[serde(default)]
    pub peers: u32,
    #[serde(default)]
    pub resource_pix: String,
    #[serde(default)]
    pub resource_type: String,
    #[serde(default)]
    pub video_encode: String,
    #[serde(default)]
    pub audio_encode: String,
    #[serde(default)]
    pub resource_team: String,
    #[serde(default)]
    pub edition: String,
    #[serde(default = "default_one")]
    pub downloadvolumefactor: f64,
    #[serde(default = "default_one")]
    pub uploadvolumefactor: f64,
    #[serde(default)]
    pub labels: Vec<String>,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub enclosure: String,
    #[serde(default)]
    pub page_url: String,
}

fn default_one() -> f64 {
    1.0
}

impl ResourceItem {
    /// 标准化促销维度标签（免费 / 2X免费 / 50% / 普通）。
    pub fn promotion_label(&self) -> String {
        if self.downloadvolumefactor == 0.0 && self.uploadvolumefactor >= 2.0 {
            "2X免费".to_string()
        } else if self.downloadvolumefactor == 0.0 {
            "免费".to_string()
        } else if (self.downloadvolumefactor - 0.5).abs() < 0.01 {
            "50%".to_string()
        } else if self.downloadvolumefactor < 1.0 {
            format!("{}%", (self.downloadvolumefactor * 100.0).round() as i32)
        } else {
            "普通".to_string()
        }
    }

    /// 生成同规格分组键（分辨率 + 介质 + 视频编码 + 制作组 + 版本）。
    pub fn spec_group_key(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}",
            self.resource_pix.to_ascii_lowercase(),
            self.resource_type.to_ascii_lowercase(),
            self.video_encode.to_ascii_lowercase(),
            self.resource_team.to_ascii_lowercase(),
            self.edition.to_ascii_lowercase()
        )
    }
}

/// 排序方式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ResourceSortBy {
    #[default]
    Seeders,
    SizeDesc,
    SizeAsc,
    FreeFirst,
    Site,
}

/// 9 维级联筛选条件（同时兼容 camelCase 与 snake_case 键名，避免跨端序列化静默丢失筛选维度）。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct ResourceFilterCriteria {
    pub sites: Vec<String>,
    pub resolutions: Vec<String>,
    #[serde(alias = "resource_types")]
    pub resource_types: Vec<String>,
    #[serde(alias = "video_encodes")]
    pub video_encodes: Vec<String>,
    #[serde(alias = "audio_encodes")]
    pub audio_encodes: Vec<String>,
    pub editions: Vec<String>,
    pub teams: Vec<String>,
    pub promotions: Vec<String>,
    pub labels: Vec<String>,
    pub keyword: String,
    #[serde(alias = "sort_by")]
    pub sort_by: ResourceSortBy,
}

/// 当前可用 9 维级联候选集。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceFilterOptions {
    pub sites: Vec<String>,
    pub resolutions: Vec<String>,
    pub resource_types: Vec<String>,
    pub video_encodes: Vec<String>,
    pub audio_encodes: Vec<String>,
    pub editions: Vec<String>,
    pub teams: Vec<String>,
    pub promotions: Vec<String>,
    pub labels: Vec<String>,
}

/// 同规格合并分组，首条为最佳推荐（高做种 + 优惠优先）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceGroup {
    pub key: String,
    pub primary: ResourceItem,
    pub items: Vec<ResourceItem>,
    pub total_seeders: u32,
}

/// 筛选与分组引擎输出快照。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceFilterResult {
    pub total_count: usize,
    pub filtered_count: usize,
    pub options: ResourceFilterOptions,
    pub groups: Vec<ResourceGroup>,
}

/// 跨端站点资源 9 维级联筛选与分组引擎。
pub struct ResourceFilterEngine;

impl ResourceFilterEngine {
    /// 执行 9 维筛选、级联候选项计算、排序与同规格分组。
    pub fn evaluate(
        items: &[ResourceItem],
        criteria: &ResourceFilterCriteria,
    ) -> ResourceFilterResult {
        let mut filtered: Vec<ResourceItem> = items
            .iter()
            .filter(|item| Self::matches(item, criteria))
            .cloned()
            .collect();

        Self::sort_items(&mut filtered, criteria.sort_by);
        let options = Self::collect_options(items);

        let mut grouped_map: BTreeMap<String, Vec<ResourceItem>> = BTreeMap::new();
        for item in &filtered {
            grouped_map
                .entry(item.spec_group_key())
                .or_default()
                .push(item.clone());
        }

        let mut groups: Vec<ResourceGroup> = grouped_map
            .into_iter()
            .map(|(key, mut bucket)| {
                bucket.sort_by(|a, b| {
                    a.downloadvolumefactor
                        .partial_cmp(&b.downloadvolumefactor)
                        .unwrap_or(std::cmp::Ordering::Equal)
                        .then_with(|| b.seeders.cmp(&a.seeders))
                });
                let total_seeders = bucket.iter().map(|i| i.seeders).sum();
                let primary = bucket[0].clone();
                ResourceGroup {
                    key,
                    primary,
                    items: bucket,
                    total_seeders,
                }
            })
            .collect();

        groups.sort_by(|a, b| match criteria.sort_by {
            ResourceSortBy::Seeders => b.total_seeders.cmp(&a.total_seeders),
            ResourceSortBy::SizeDesc => b.primary.size.cmp(&a.primary.size),
            ResourceSortBy::SizeAsc => a.primary.size.cmp(&b.primary.size),
            ResourceSortBy::FreeFirst => a
                .primary
                .downloadvolumefactor
                .partial_cmp(&b.primary.downloadvolumefactor)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| b.total_seeders.cmp(&a.total_seeders)),
            ResourceSortBy::Site => a.primary.site_name.cmp(&b.primary.site_name),
        });

        ResourceFilterResult {
            total_count: items.len(),
            filtered_count: filtered.len(),
            options,
            groups,
        }
    }

    fn matches(item: &ResourceItem, c: &ResourceFilterCriteria) -> bool {
        let kw = c.keyword.trim().to_ascii_lowercase();
        if !kw.is_empty()
            && !item.title.to_ascii_lowercase().contains(&kw)
            && !item.description.to_ascii_lowercase().contains(&kw)
            && !item.site_name.to_ascii_lowercase().contains(&kw)
        {
            return false;
        }
        Self::match_set(&c.sites, &item.site_name)
            && Self::match_set(&c.resolutions, &item.resource_pix)
            && Self::match_set(&c.resource_types, &item.resource_type)
            && Self::match_set(&c.video_encodes, &item.video_encode)
            && Self::match_set(&c.audio_encodes, &item.audio_encode)
            && Self::match_set(&c.editions, &item.edition)
            && Self::match_set(&c.teams, &item.resource_team)
            && Self::match_set(&c.promotions, &item.promotion_label())
            && (c.labels.is_empty()
                || c.labels
                    .iter()
                    .all(|req| item.labels.iter().any(|lbl| lbl.eq_ignore_ascii_case(req))))
    }

    fn match_set(selected: &[String], value: &str) -> bool {
        selected.is_empty() || selected.iter().any(|s| s.eq_ignore_ascii_case(value))
    }

    fn sort_items(items: &mut [ResourceItem], sort_by: ResourceSortBy) {
        items.sort_by(|a, b| match sort_by {
            ResourceSortBy::Seeders => b.seeders.cmp(&a.seeders),
            ResourceSortBy::SizeDesc => b.size.cmp(&a.size),
            ResourceSortBy::SizeAsc => a.size.cmp(&b.size),
            ResourceSortBy::FreeFirst => a
                .downloadvolumefactor
                .partial_cmp(&b.downloadvolumefactor)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| b.seeders.cmp(&a.seeders)),
            ResourceSortBy::Site => a.site_name.cmp(&b.site_name),
        });
    }

    fn collect_options(items: &[ResourceItem]) -> ResourceFilterOptions {
        let mut sites = BTreeSet::new();
        let mut resolutions = BTreeSet::new();
        let mut resource_types = BTreeSet::new();
        let mut video_encodes = BTreeSet::new();
        let mut audio_encodes = BTreeSet::new();
        let mut editions = BTreeSet::new();
        let mut teams = BTreeSet::new();
        let mut promotions = BTreeSet::new();
        let mut labels = BTreeSet::new();

        for it in items {
            if !it.site_name.is_empty() {
                sites.insert(it.site_name.clone());
            }
            if !it.resource_pix.is_empty() {
                resolutions.insert(it.resource_pix.clone());
            }
            if !it.resource_type.is_empty() {
                resource_types.insert(it.resource_type.clone());
            }
            if !it.video_encode.is_empty() {
                video_encodes.insert(it.video_encode.clone());
            }
            if !it.audio_encode.is_empty() {
                audio_encodes.insert(it.audio_encode.clone());
            }
            if !it.edition.is_empty() {
                editions.insert(it.edition.clone());
            }
            if !it.resource_team.is_empty() {
                teams.insert(it.resource_team.clone());
            }
            promotions.insert(it.promotion_label());
            for lbl in &it.labels {
                if !lbl.is_empty() {
                    labels.insert(lbl.clone());
                }
            }
        }
        ResourceFilterOptions {
            sites: sites.into_iter().collect(),
            resolutions: resolutions.into_iter().collect(),
            resource_types: resource_types.into_iter().collect(),
            video_encodes: video_encodes.into_iter().collect(),
            audio_encodes: audio_encodes.into_iter().collect(),
            editions: editions.into_iter().collect(),
            teams: teams.into_iter().collect(),
            promotions: promotions.into_iter().collect(),
            labels: labels.into_iter().collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn groups_same_spec_and_filters_nine_dimensions() {
        let path =
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../fixtures/api/cases.json");
        let root: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let resources: Vec<ResourceItem> =
            serde_json::from_value(root["resources"].clone()).unwrap();

        let all = ResourceFilterEngine::evaluate(&resources, &ResourceFilterCriteria::default());
        assert_eq!(all.filtered_count, 3);
        assert_eq!(all.groups.len(), 2);
        assert_eq!(all.groups[0].items.len(), 2);
        assert_eq!(all.groups[0].primary.id, "r1");

        let only_free = ResourceFilterEngine::evaluate(
            &resources,
            &ResourceFilterCriteria {
                resolutions: vec!["2160p".into()],
                promotions: vec!["2X免费".into()],
                labels: vec!["杜比视界".into()],
                ..Default::default()
            },
        );
        assert_eq!(only_free.filtered_count, 1);
        assert_eq!(only_free.groups[0].primary.id, "r1");
    }

    #[test]
    fn accepts_both_camel_case_and_snake_case_criteria_keys() {
        let items = vec![
            ResourceItem {
                id: "1".into(),
                title: "Movie A".into(),
                site_name: "SiteA".into(),
                size: 1000,
                seeders: 10,
                peers: 2,
                resource_pix: "1080p".into(),
                resource_type: "WEB-DL".into(),
                video_encode: "x265".into(),
                audio_encode: "AAC".into(),
                resource_team: "TeamA".into(),
                edition: "WEB-DL".into(),
                downloadvolumefactor: 0.0,
                uploadvolumefactor: 1.0,
                labels: vec!["中字".into()],
                description: String::new(),
                enclosure: String::new(),
                page_url: String::new(),
            },
            ResourceItem {
                id: "2".into(),
                title: "Movie B".into(),
                site_name: "SiteA".into(),
                size: 2000,
                seeders: 20,
                peers: 3,
                resource_pix: "1080p".into(),
                resource_type: "BluRay".into(),
                video_encode: "x264".into(),
                audio_encode: "DTS".into(),
                resource_team: "TeamB".into(),
                edition: "BluRay".into(),
                downloadvolumefactor: 1.0,
                uploadvolumefactor: 1.0,
                labels: vec![],
                description: String::new(),
                enclosure: String::new(),
                page_url: String::new(),
            },
        ];

        let snake: ResourceFilterCriteria = serde_json::from_str(
            r#"{"video_encodes":["x265"],"resource_types":["WEB-DL"],"audio_encodes":["AAC"]}"#,
        )
        .unwrap();
        let camel: ResourceFilterCriteria = serde_json::from_str(
            r#"{"videoEncodes":["x265"],"resourceTypes":["WEB-DL"],"audioEncodes":["AAC"]}"#,
        )
        .unwrap();
        assert_eq!(snake, camel);
        let res = ResourceFilterEngine::evaluate(&items, &snake);
        assert_eq!(res.filtered_count, 1);
        assert_eq!(res.groups[0].primary.id, "1");
    }
}
