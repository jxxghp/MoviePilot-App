//! Vue 联邦插件本地预热运行时（Route A）跨端路径安全、缓存键派生与虚拟源路由解析引擎。
//!
//! 职责边界：
//! - 严格校验 Bridge `api.request` 与被动静态代理路径，仅允许当前实例的 `/api/v1/...`，杜绝路径穿越、绝对 URL、反斜杠与控制字符；
//! - 将后端 `/api/v1/plugin/remotes` 返回的 `remoteEntry.js` 地址规划为三端统一的虚拟源路径
//!   `/plugin-remote/{plugin_id}/{version_tag}/{asset_rel_path}`；
//! - 将 WebView 拦截到的 `/plugin-remote/...` 请求安全还原为上游 `/api/v1/plugin/file/...` 与实例隔离磁盘缓存相对路径；
//! - 使用内置 FIPS 180-4 SHA-256 为多实例隔离派生确定性缓存目录键（无额外第三方 crate 依赖）。

use serde::{Deserialize, Serialize};

/// 跨端联邦插件磁盘缓存键（按实例源 SHA-256 / 插件 ID / 版本或产物哈希三级隔离）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginRemoteCacheKey {
    pub instance_hash: String,
    pub plugin_id_lower: String,
    pub version_segment: String,
    pub relative_dir: String,
}

/// 联邦插件远程入口归一化规划结果。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginRemoteEntryPlan {
    pub plugin_id: String,
    pub version_tag: String,
    pub virtual_entry_path: String,
    pub upstream_file_path: String,
}

/// 虚拟源 `/plugin-remote/...` 请求还原后的上游目标与安全缓存相对路径。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginRemoteUpstreamTarget {
    pub plugin_id: String,
    pub version_tag: String,
    pub asset_rel_path: String,
    pub upstream_api_path: String,
}

/// 校验并规范化插件发起的 `/api/v1/...` 相对路径，拒绝外部主机、协议前缀、路径穿越与控制字符。
pub fn validate_plugin_api_path(raw_path: &str) -> Result<String, String> {
    let trimmed = raw_path.trim();
    if trimmed.is_empty() {
        return Err("API path must not be empty".to_string());
    }
    if has_control_or_backslash(trimmed) {
        return Err("API path contains illegal control characters or backslash".to_string());
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.contains("://")
        || lower.starts_with("//")
        || lower.starts_with("http:")
        || lower.starts_with("https:")
        || lower.starts_with("javascript:")
        || lower.starts_with("data:")
        || lower.starts_with("file:")
    {
        return Err("API path must be a relative MoviePilot API path".to_string());
    }

    // 剥离 fragment，保留 query 以便校验路径段后原样拼回
    let without_fragment = trimmed.split('#').next().unwrap_or(trimmed);
    let (raw_path_part, query_part) = match without_fragment.split_once('?') {
        Some((p, q)) => (p, Some(q)),
        None => (without_fragment, None),
    };

    let stripped = raw_path_part.trim_start_matches('/');
    let relative = stripped
        .strip_prefix("api/v1/")
        .or_else(|| (stripped == "api/v1").then_some(""))
        .unwrap_or(stripped);

    let segments = validate_safe_relative_segments(relative, false)?;
    let normalized = format!("/api/v1/{}", segments.join("/"));
    if let Some(q) = query_part {
        if has_control_or_backslash(q) {
            return Err("API query contains illegal characters".to_string());
        }
        Ok(format!("{normalized}?{q}"))
    } else {
        Ok(normalized)
    }
}

/// 校验虚拟壳静态资产路径（`/shell/...` 或相对路径），返回安全的包内相对路径。
pub fn validate_plugin_shell_asset_path(virtual_path: &str) -> Result<String, String> {
    let trimmed = virtual_path.trim();
    if trimmed.is_empty() || has_control_or_backslash(trimmed) {
        return Err("Shell asset path is invalid".to_string());
    }
    let without_query = trimmed
        .split('#')
        .next()
        .unwrap_or(trimmed)
        .split('?')
        .next()
        .unwrap_or(trimmed);
    let stripped = without_query.trim_start_matches('/');
    let rel = stripped.strip_prefix("shell/").unwrap_or(stripped);
    let segments = validate_safe_relative_segments(rel, false)?;
    Ok(segments.join("/"))
}

/// 将任意字符串清洗为文件系统安全单段标识（仅保留 `[A-Za-z0-9._-]`，禁止前导点与穿越）。
pub fn sanitize_cache_segment(raw: &str, fallback: &str) -> String {
    let mut out = String::with_capacity(raw.len().min(64));
    for ch in raw.trim().chars() {
        if out.len() >= 64 {
            break;
        }
        if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' || ch == '.' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    let cleaned = out.trim_matches('.').trim_matches('_');
    if cleaned.is_empty() || cleaned == "." || cleaned == ".." || cleaned.contains("..") {
        fallback.to_string()
    } else {
        cleaned.to_string()
    }
}

/// 生成按实例源 SHA-256、插件 ID、版本/产物哈希隔离的磁盘缓存键。
pub fn build_plugin_remote_cache_key(
    instance_origin: &str,
    plugin_id: &str,
    version_or_hash: &str,
) -> PluginRemoteCacheKey {
    let normalized_origin = instance_origin
        .trim()
        .trim_end_matches('/')
        .to_ascii_lowercase();
    let instance_hash = sha256_hex(normalized_origin.as_bytes())[..16].to_string();
    let plugin_id_lower = sanitize_cache_segment(&plugin_id.to_ascii_lowercase(), "plugin");
    let version_segment = sanitize_cache_segment(version_or_hash, "default");
    let relative_dir = format!("{instance_hash}/{plugin_id_lower}/{version_segment}");
    PluginRemoteCacheKey {
        instance_hash,
        plugin_id_lower,
        version_segment,
        relative_dir,
    }
}

/// 将后端 `/api/v1/plugin/remotes` 返回的入口地址规划为虚拟源入口与上游文件路径。
pub fn normalize_plugin_remote_entry(
    plugin_id: &str,
    version_or_hash: &str,
    raw_remote_url: &str,
) -> Result<PluginRemoteEntryPlan, String> {
    let trimmed = raw_remote_url.trim();
    if trimmed.is_empty() || has_control_or_backslash(trimmed) {
        return Err("Remote entry URL is invalid".to_string());
    }
    let without_fragment = trimmed.split('#').next().unwrap_or(trimmed);
    let (path_or_url, query_part) = match without_fragment.split_once('?') {
        Some((p, q)) => (p, Some(q)),
        None => (without_fragment, None),
    };

    let path_only = if let Some(scheme_pos) = path_or_url.find("://") {
        let after_scheme = &path_or_url[scheme_pos + 3..];
        match after_scheme.find('/') {
            Some(slash_idx) => &after_scheme[slash_idx..],
            None => return Err("Remote entry URL missing path".to_string()),
        }
    } else {
        path_or_url
    };

    let lower_path = path_only.to_ascii_lowercase();
    let marker = "plugin/file/";
    let marker_idx = lower_path
        .find(marker)
        .ok_or_else(|| "Remote entry URL must point under plugin/file/".to_string())?;
    let after_marker = &path_only[marker_idx + marker.len()..];
    let segments = validate_safe_relative_segments(after_marker, false)?;
    if segments.len() < 2 {
        return Err("Remote entry URL missing plugin file path".to_string());
    }

    let file_plugin_id = segments[0].clone();
    if !is_valid_plugin_id_segment(&file_plugin_id) {
        return Err("Remote entry plugin ID segment is invalid".to_string());
    }
    let asset_rel_path = segments[1..].join("/");

    let effective_version_raw = if !version_or_hash.trim().is_empty() {
        version_or_hash.trim().to_string()
    } else if let Some(v) = extract_query_param(query_part.unwrap_or(""), "v") {
        v
    } else {
        "default".to_string()
    };
    let version_tag = sanitize_cache_segment(&effective_version_raw, "default");

    let _ = plugin_id;
    let virtual_entry_path =
        format!("/plugin-remote/{file_plugin_id}/{version_tag}/{asset_rel_path}");
    let upstream_file_path = format!("/api/v1/plugin/file/{file_plugin_id}/{asset_rel_path}");

    Ok(PluginRemoteEntryPlan {
        plugin_id: file_plugin_id,
        version_tag,
        virtual_entry_path,
        upstream_file_path,
    })
}

/// 将 WebView 发往 `/plugin-remote/{plugin_id}/{version_tag}/{asset_rel_path}` 的请求安全还原为上游 API 路径与缓存相对路径。
pub fn resolve_plugin_remote_upstream_path(
    virtual_path: &str,
) -> Result<PluginRemoteUpstreamTarget, String> {
    let trimmed = virtual_path.trim();
    if trimmed.is_empty() || has_control_or_backslash(trimmed) {
        return Err("Virtual remote path is invalid".to_string());
    }
    let without_query = trimmed
        .split('#')
        .next()
        .unwrap_or(trimmed)
        .split('?')
        .next()
        .unwrap_or(trimmed);
    let stripped = without_query.trim_start_matches('/');
    let rest = stripped
        .strip_prefix("plugin-remote/")
        .ok_or_else(|| "Virtual path must start with /plugin-remote/".to_string())?;
    let segments = validate_safe_relative_segments(rest, false)?;
    if segments.len() < 3 {
        return Err("Virtual remote path missing plugin_id, version, or asset path".to_string());
    }
    let plugin_id = segments[0].clone();
    if !is_valid_plugin_id_segment(&plugin_id) {
        return Err("Invalid plugin_id in virtual remote path".to_string());
    }
    let version_tag = sanitize_cache_segment(&segments[1], "default");
    let asset_rel_path = segments[2..].join("/");
    let upstream_api_path = format!("/api/v1/plugin/file/{plugin_id}/{asset_rel_path}");

    Ok(PluginRemoteUpstreamTarget {
        plugin_id,
        version_tag,
        asset_rel_path,
        upstream_api_path,
    })
}

fn has_control_or_backslash(s: &str) -> bool {
    s.bytes().any(|b| b < 0x20 || b == 0x7f || b == b'\\')
}

fn is_valid_plugin_id_segment(segment: &str) -> bool {
    !segment.is_empty()
        && segment.len() <= 128
        && segment
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-' || b == b'.')
        && !segment.starts_with('.')
        && !segment.contains("..")
}

fn validate_safe_relative_segments(raw: &str, allow_empty: bool) -> Result<Vec<String>, String> {
    let trimmed = raw.trim_matches('/');
    if trimmed.is_empty() {
        if allow_empty {
            return Ok(Vec::new());
        }
        return Err("Path segments must not be empty".to_string());
    }
    let mut result = Vec::new();
    for seg in trimmed.split('/') {
        if seg.is_empty() || seg == "." || seg == ".." {
            return Err("Path contains empty or traversal segment".to_string());
        }
        let decoded_lower = percent_decode_ascii_lower(seg);
        if decoded_lower == "."
            || decoded_lower == ".."
            || decoded_lower.contains("..")
            || decoded_lower.contains('/')
            || decoded_lower.contains('\\')
            || decoded_lower.contains('\0')
        {
            return Err("Path contains encoded traversal or separator".to_string());
        }
        result.push(seg.to_string());
    }
    Ok(result)
}

fn percent_decode_ascii_lower(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let (Some(h), Some(l)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2]))
        {
            let ch = ((h << 4) | l) as char;
            out.push(ch.to_ascii_lowercase());
            i += 3;
            continue;
        }
        out.push((bytes[i] as char).to_ascii_lowercase());
        i += 1;
    }
    out
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

fn extract_query_param(query: &str, key: &str) -> Option<String> {
    for pair in query.split('&') {
        if let Some((k, v)) = pair.split_once('=')
            && k == key
            && !v.trim().is_empty()
        {
            return Some(v.trim().to_string());
        }
    }
    None
}

/// 零依赖标准 FIPS 180-4 SHA-256 实现（返回 64 字符小写十六进制摘要）。
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut padded = Vec::with_capacity((data.len() + 9).div_ceil(64) * 64);
    padded.extend_from_slice(data);
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0x00);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, word) in w[..16].iter_mut().enumerate() {
            let off = i * 4;
            *word =
                u32::from_be_bytes([chunk[off], chunk[off + 1], chunk[off + 2], chunk[off + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(64);
    for word in h {
        for byte in word.to_be_bytes() {
            out.push(HEX[(byte >> 4) as usize] as char);
            out.push(HEX[(byte & 0x0f) as usize] as char);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_matches_nist_vectors() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn validates_api_paths_and_blocks_traversal_or_cross_origin() {
        assert_eq!(
            validate_plugin_api_path("plugin/Demo/status?page=1").unwrap(),
            "/api/v1/plugin/Demo/status?page=1"
        );
        assert_eq!(
            validate_plugin_api_path("/api/v1/plugin/Demo/config").unwrap(),
            "/api/v1/plugin/Demo/config"
        );
        assert!(validate_plugin_api_path("https://evil.example/api/v1/plugin/x").is_err());
        assert!(validate_plugin_api_path("//evil.example/api/v1/plugin/x").is_err());
        assert!(validate_plugin_api_path("/api/v1/plugin/../system/env").is_err());
        assert!(validate_plugin_api_path("/api/v1/plugin/%2e%2e/secret").is_err());
        assert!(validate_plugin_api_path("/api/v1/plugin/demo\\secret").is_err());
    }

    #[test]
    fn normalizes_remote_entry_and_resolves_upstream_safely() {
        let plan = normalize_plugin_remote_entry(
            "VueCompatDemo",
            "1.2.0",
            "/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js?v=1.2.0",
        )
        .unwrap();
        assert_eq!(plan.plugin_id, "vuecompatdemo");
        assert_eq!(plan.version_tag, "1.2.0");
        assert_eq!(
            plan.virtual_entry_path,
            "/plugin-remote/vuecompatdemo/1.2.0/dist/assets/remoteEntry.js"
        );
        assert_eq!(
            plan.upstream_file_path,
            "/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js"
        );

        let target = resolve_plugin_remote_upstream_path(
            "/plugin-remote/vuecompatdemo/1.2.0/dist/assets/chunk-abc.js?t=1",
        )
        .unwrap();
        assert_eq!(target.plugin_id, "vuecompatdemo");
        assert_eq!(target.version_tag, "1.2.0");
        assert_eq!(target.asset_rel_path, "dist/assets/chunk-abc.js");
        assert_eq!(
            target.upstream_api_path,
            "/api/v1/plugin/file/vuecompatdemo/dist/assets/chunk-abc.js"
        );

        assert!(
            resolve_plugin_remote_upstream_path("/plugin-remote/demo/1.0/../../etc/passwd")
                .is_err()
        );
        assert!(
            resolve_plugin_remote_upstream_path("/plugin-remote/demo/1.0/%2e%2e/secret.js")
                .is_err()
        );
        assert!(
            validate_plugin_shell_asset_path("/shell/assets/plugin-shell.js").unwrap()
                == "assets/plugin-shell.js"
        );
        assert!(validate_plugin_shell_asset_path("/shell/../secret.txt").is_err());
    }

    #[test]
    fn builds_isolated_cache_key_per_instance_and_version() {
        let a = build_plugin_remote_cache_key("https://mp-a.example.com/", "MyPlugin", "2.0.1");
        let b = build_plugin_remote_cache_key("https://mp-b.example.com", "MyPlugin", "2.0.1");
        assert_ne!(a.instance_hash, b.instance_hash);
        assert_eq!(a.plugin_id_lower, "myplugin");
        assert_eq!(a.version_segment, "2.0.1");
        assert_eq!(
            a.relative_dir,
            format!("{}/myplugin/2.0.1", a.instance_hash)
        );
    }
}
