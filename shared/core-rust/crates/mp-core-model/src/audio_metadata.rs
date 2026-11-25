//! 跨端零依赖音频内嵌元数据解析器（FLAC / ID3v2.2~2.4 / MP4·M4A / Ogg Vorbis·Opus）：
//! - 提取音频内嵌封面（`METADATA_BLOCK_PICTURE`、`APIC`/`PIC`、`covr`）与内嵌歌词（Vorbis `LYRICS`/`UNSYNCEDLYRICS`、ID3 `USLT`/`SYLT`/`TXXX`、MP4 `©lyr`）；
//! - 自动将 ID3 `SYLT` 同步歌词转为标准 `[mm:ss.xx]` LRC；
//! - 支持受限字节范围探测：当头块或 MP4 `moov` 超出首段 Range 窗口时，回传精准的二次 Range 需求字节数（安全上限 6 MiB），无需整文件下载。

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64_STANDARD};
use serde::{Deserialize, Serialize};

/// 单张内嵌封面允许解码的最大字节数（8 MiB，防止畸形头造成 OOM）。
pub const MAX_EMBEDDED_COVER_BYTES: usize = 8 * 1024 * 1024;

/// 推荐单次追加头/尾 Range 拉取的最大字节上限（6 MiB）。
pub const MAX_RECOMMENDED_RANGE_BYTES: u64 = 6 * 1024 * 1024;

/// 音频内嵌元数据解析结果（支持头块 + 可选尾块二次解析）。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioEmbeddedMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    /// 内嵌歌词正文（可能为 `[mm:ss.xx]` 同步 LRC，亦可能为无时间戳纯文本歌词）。
    pub lyrics: Option<String>,
    /// 封面 MIME 类型（如 `image/jpeg`、`image/png`、`image/webp`）。
    pub cover_mime: Option<String>,
    /// 封面图片原始字节。
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cover_bytes: Option<Vec<u8>>,
    /// 若文件头部的元数据区（如超大 FLAC Picture 块或 ID3v2 标签）超出当前 `head_bytes` 长度，
    /// 给出建议拉取的头部总字节数（上限 `MAX_RECOMMENDED_RANGE_BYTES`）。
    pub needed_head_bytes: Option<u64>,
    /// 若为非 faststart MP4/M4A（`mdat` 位于 `moov` 之前且尚未提供 `tail_bytes`），
    /// 给出建议拉取的尾部字节数（如 524288 字节）以读取末尾 `moov` 原子。
    pub needed_tail_bytes: Option<u64>,
}

impl AudioEmbeddedMetadata {
    /// 判断是否已提取出封面或歌词任意一项核心内容。
    pub fn has_cover_or_lyrics(&self) -> bool {
        self.cover_bytes.as_ref().is_some_and(|b| !b.is_empty())
            || self.lyrics.as_ref().is_some_and(|s| !s.trim().is_empty())
    }
}

/// JSON 友好序列化载体（用于鸿蒙 N-API 字符串桥接，封面字节以 Base64 传输）。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioEmbeddedMetadataJson {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub lyrics: Option<String>,
    pub cover_mime: Option<String>,
    pub cover_base64: Option<String>,
    pub needed_head_bytes: Option<u64>,
    pub needed_tail_bytes: Option<u64>,
}

impl From<AudioEmbeddedMetadata> for AudioEmbeddedMetadataJson {
    fn from(value: AudioEmbeddedMetadata) -> Self {
        Self {
            title: value.title,
            artist: value.artist,
            album: value.album,
            lyrics: value.lyrics,
            cover_mime: value.cover_mime,
            cover_base64: value
                .cover_bytes
                .filter(|b| !b.is_empty())
                .map(|b| BASE64_STANDARD.encode(b)),
            needed_head_bytes: value.needed_head_bytes,
            needed_tail_bytes: value.needed_tail_bytes,
        }
    }
}

/// 从音频文件头部字节（以及可选的尾部字节，供非 faststart M4A `moov` 使用）提取内嵌标签、歌词与封面。
pub fn parse_audio_embedded_metadata(
    head_bytes: &[u8],
    tail_bytes: Option<&[u8]>,
) -> AudioEmbeddedMetadata {
    let mut out = AudioEmbeddedMetadata::default();
    if head_bytes.len() < 4 {
        return out;
    }

    // 1. 若以 ID3v2 开头（MP3、AIFF/DSF/WAV 或前置 ID3 的 FLAC），先解析 ID3v2
    let mut after_id3_offset: usize = 0;
    if head_bytes.len() >= 10 && &head_bytes[0..3] == b"ID3" {
        let total_id3 = parse_id3v2(head_bytes, &mut out);
        if total_id3 > head_bytes.len() {
            if (total_id3 as u64) <= MAX_RECOMMENDED_RANGE_BYTES {
                out.needed_head_bytes = Some(total_id3 as u64);
            }
            return out;
        }
        after_id3_offset = total_id3;
    }

    // 2. 检测剩余偏移处或起始处的容器签名（FLAC / Ogg / MP4）
    let body = if after_id3_offset < head_bytes.len() {
        &head_bytes[after_id3_offset..]
    } else {
        &[]
    };

    if body.len() >= 4 && &body[0..4] == b"fLaC" {
        parse_flac(body, after_id3_offset as u64, &mut out);
    } else if body.len() >= 4 && &body[0..4] == b"OggS" {
        parse_ogg(body, &mut out);
    } else if is_mp4_header(head_bytes) {
        parse_mp4(head_bytes, tail_bytes, &mut out);
    }

    out
}

// ============================================================================
// 通用工具：图片 MIME 嗅探、文本清理与优先级合并
// ============================================================================

fn sniff_image_mime(bytes: &[u8], declared: &str) -> Option<String> {
    if bytes.len() < 4 || bytes.len() > MAX_EMBEDDED_COVER_BYTES {
        return None;
    }
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return Some("image/jpeg".to_string());
    }
    if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return Some("image/png".to_string());
    }
    if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        return Some("image/webp".to_string());
    }
    if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        return Some("image/gif".to_string());
    }
    if bytes.starts_with(b"BM") {
        return Some("image/bmp".to_string());
    }
    let clean = declared.trim().to_ascii_lowercase();
    if clean == "jpg" || clean == "jpeg" {
        return Some("image/jpeg".to_string());
    }
    if clean == "png" {
        return Some("image/png".to_string());
    }
    if clean.starts_with("image/") {
        return Some(clean);
    }
    None
}

fn clean_text(raw: &str) -> Option<String> {
    let trimmed = raw
        .trim_matches(|c: char| c == '\0' || c == '\u{feff}')
        .trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn looks_like_synced_lrc(text: &str) -> bool {
    let bytes = text.as_bytes();
    for i in 0..bytes.len().saturating_sub(6) {
        if bytes[i] == b'[' && bytes[i + 1].is_ascii_digit() {
            // 匹配 [mm:ss 或 [m:ss
            let mut j = i + 1;
            let mut digits = 0;
            while j < bytes.len() && bytes[j].is_ascii_digit() && digits < 3 {
                j += 1;
                digits += 1;
            }
            if j + 3 <= bytes.len()
                && bytes[j] == b':'
                && bytes[j + 1].is_ascii_digit()
                && bytes[j + 2].is_ascii_digit()
            {
                return true;
            }
        }
    }
    false
}

/// 合并歌词候选：优先保留带 `[mm:ss]` 时间轴的同步 LRC，其次保留非空纯文本歌词。
fn consider_lyrics(out: &mut AudioEmbeddedMetadata, candidate: Option<String>) {
    let Some(text) = candidate else { return };
    if text.trim().is_empty() {
        return;
    }
    match &out.lyrics {
        None => out.lyrics = Some(text),
        Some(existing) => {
            if !looks_like_synced_lrc(existing) && looks_like_synced_lrc(&text) {
                out.lyrics = Some(text);
            }
        }
    }
}

fn set_cover_if_better(
    out: &mut AudioEmbeddedMetadata,
    best_priority: &mut u8,
    picture_type: u8,
    mime_hint: &str,
    data: &[u8],
) {
    let Some(mime) = sniff_image_mime(data, mime_hint) else {
        return;
    };
    // 优先级：Front Cover (3) = 3 > Other/Artist/Album (0, 4, 8, 10) = 2 > 其余 = 1
    let prio: u8 = match picture_type {
        3 => 3,
        0 | 4 | 8 | 10 => 2,
        _ => 1,
    };
    if prio > *best_priority || out.cover_bytes.is_none() {
        *best_priority = prio;
        out.cover_mime = Some(mime);
        out.cover_bytes = Some(data.to_vec());
    }
}

fn read_be_u24(b: &[u8], off: usize) -> Option<u32> {
    let s = b.get(off..off + 3)?;
    Some(((s[0] as u32) << 16) | ((s[1] as u32) << 8) | (s[2] as u32))
}

fn read_be_u32(b: &[u8], off: usize) -> Option<u32> {
    let s = b.get(off..off + 4)?;
    Some(u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}

fn read_be_u64(b: &[u8], off: usize) -> Option<u64> {
    let s = b.get(off..off + 8)?;
    Some(u64::from_be_bytes([
        s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7],
    ]))
}

fn read_le_u32(b: &[u8], off: usize) -> Option<u32> {
    let s = b.get(off..off + 4)?;
    Some(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
}

fn read_synchsafe_u32(b: &[u8], off: usize) -> Option<u32> {
    let s = b.get(off..off + 4)?;
    if (s[0] | s[1] | s[2] | s[3]) & 0x80 != 0 {
        return None;
    }
    Some(((s[0] as u32) << 21) | ((s[1] as u32) << 14) | ((s[2] as u32) << 7) | (s[3] as u32))
}

// ============================================================================
// 1. FLAC 解析器（Block 4 VORBIS_COMMENT + Block 6 PICTURE）
// ============================================================================

fn parse_flac(data: &[u8], base_offset: u64, out: &mut AudioEmbeddedMetadata) {
    if data.len() < 4 || &data[0..4] != b"fLaC" {
        return;
    }
    let mut pos: usize = 4;
    let mut cover_prio: u8 = if out.cover_bytes.is_some() { 2 } else { 0 };

    while pos + 4 <= data.len() {
        let header_byte = data[pos];
        let is_last = (header_byte & 0x80) != 0;
        let block_type = header_byte & 0x7F;
        let Some(block_len) = read_be_u24(data, pos + 1) else {
            break;
        };
        let block_start = pos + 4;
        let Some(block_end) = block_start.checked_add(block_len as usize) else {
            break;
        };

        if block_end > data.len() {
            // 当前头部窗口不足以容纳此元数据块（典型情况：高分辨率内嵌封面或位于封面之后的歌词块）
            let abs_end = base_offset.saturating_add(block_end as u64);
            // 多预留 64 KiB 以覆盖紧随封面的 VorbisComment 块
            let desired = abs_end
                .saturating_add(65_536)
                .min(MAX_RECOMMENDED_RANGE_BYTES);
            if desired > (base_offset.saturating_add(data.len() as u64)) {
                out.needed_head_bytes = Some(desired);
            }
            break;
        }

        let payload = &data[block_start..block_end];
        match block_type {
            4 => parse_vorbis_comment_block(payload, out, &mut cover_prio),
            6 => parse_flac_picture_block(payload, out, &mut cover_prio),
            _ => {}
        }

        pos = block_end;
        if is_last {
            break;
        }
    }
}

fn parse_vorbis_comment_block(
    payload: &[u8],
    out: &mut AudioEmbeddedMetadata,
    cover_prio: &mut u8,
) {
    let Some(vendor_len) = read_le_u32(payload, 0) else {
        return;
    };
    let mut pos = match 4usize.checked_add(vendor_len as usize) {
        Some(v) if v + 4 <= payload.len() => v,
        _ => return,
    };
    let Some(count) = read_le_u32(payload, pos) else {
        return;
    };
    pos += 4;
    let capped_count = count.min(4096);

    for _ in 0..capped_count {
        let Some(len) = read_le_u32(payload, pos) else {
            break;
        };
        pos += 4;
        let Some(end) = pos.checked_add(len as usize) else {
            break;
        };
        if end > payload.len() {
            break;
        }
        if let Ok(entry) = std::str::from_utf8(&payload[pos..end])
            && let Some((raw_key, raw_val)) = entry.split_once('=')
        {
            apply_vorbis_tag(raw_key, raw_val, out, cover_prio);
        }
        pos = end;
    }
}

fn apply_vorbis_tag(
    raw_key: &str,
    raw_val: &str,
    out: &mut AudioEmbeddedMetadata,
    cover_prio: &mut u8,
) {
    let key = raw_key.trim().to_ascii_uppercase();
    match key.as_str() {
        "TITLE" if out.title.is_none() => {
            out.title = clean_text(raw_val);
        }
        "ARTIST" | "ALBUMARTIST" | "ALBUM ARTIST" if out.artist.is_none() => {
            out.artist = clean_text(raw_val);
        }
        "ALBUM" if out.album.is_none() => {
            out.album = clean_text(raw_val);
        }
        "SYNCEDLYRICS" | "LYRICS" | "UNSYNCEDLYRICS" | "UNSYNCED LYRICS" | "LYRIC" | "SLT"
        | "LRC" => {
            consider_lyrics(out, clean_text(raw_val));
        }
        "COMMENT" | "DESCRIPTION" => {
            if let Some(t) = clean_text(raw_val)
                && looks_like_synced_lrc(&t)
            {
                consider_lyrics(out, Some(t));
            }
        }
        "METADATA_BLOCK_PICTURE" => {
            let trimmed: String = raw_val
                .chars()
                .filter(|c| !c.is_ascii_whitespace())
                .collect();
            if trimmed.len() <= (MAX_EMBEDDED_COVER_BYTES * 4 / 3 + 1024)
                && let Ok(decoded) = BASE64_STANDARD.decode(trimmed.as_bytes())
            {
                parse_flac_picture_block(&decoded, out, cover_prio);
            }
        }
        _ => {}
    }
}

fn parse_flac_picture_block(payload: &[u8], out: &mut AudioEmbeddedMetadata, cover_prio: &mut u8) {
    let Some(pic_type) = read_be_u32(payload, 0) else {
        return;
    };
    let Some(mime_len) = read_be_u32(payload, 4) else {
        return;
    };
    let mime_start = 8usize;
    let Some(mime_end) = mime_start.checked_add(mime_len as usize) else {
        return;
    };
    let Some(mime_bytes) = payload.get(mime_start..mime_end) else {
        return;
    };
    let mime_str = std::str::from_utf8(mime_bytes).unwrap_or("");

    let Some(desc_len) = read_be_u32(payload, mime_end) else {
        return;
    };
    let Some(after_desc) = mime_end
        .checked_add(4)
        .and_then(|v| v.checked_add(desc_len as usize))
    else {
        return;
    };
    // width(4) + height(4) + depth(4) + colors(4) = 16 bytes
    let Some(data_len_off) = after_desc.checked_add(16) else {
        return;
    };
    let Some(data_len) = read_be_u32(payload, data_len_off) else {
        return;
    };
    let data_start = data_len_off + 4;
    let Some(data_end) = data_start.checked_add(data_len as usize) else {
        return;
    };
    if let Some(img_bytes) = payload.get(data_start..data_end) {
        set_cover_if_better(
            out,
            cover_prio,
            pic_type.min(255) as u8,
            mime_str,
            img_bytes,
        );
    }
}

// ============================================================================
// 2. ID3v2 解析器（v2.2 / v2.3 / v2.4：TIT2/TPE1/TALB/USLT/SYLT/TXXX/APIC）
// ============================================================================

fn parse_id3v2(data: &[u8], out: &mut AudioEmbeddedMetadata) -> usize {
    if data.len() < 10 || &data[0..3] != b"ID3" {
        return 0;
    }
    let version = data[3];
    if !(2..=4).contains(&version) {
        return 0;
    }
    let flags = data[5];
    let Some(tag_size) = read_synchsafe_u32(data, 6) else {
        return 0;
    };
    let total_size = 10usize.saturating_add(tag_size as usize);
    let has_unsync = (flags & 0x80) != 0;
    let has_ext = (flags & 0x40) != 0;

    let avail_end = total_size.min(data.len());
    let raw_tag = &data[10..avail_end];
    let tag_buf: Vec<u8>;
    let body: &[u8] = if has_unsync && version <= 3 {
        tag_buf = remove_unsynchronisation(raw_tag);
        &tag_buf
    } else {
        raw_tag
    };

    let mut pos: usize = 0;
    if has_ext && version >= 3 && body.len() >= 4 {
        let ext_size = if version == 4 {
            read_synchsafe_u32(body, 0).unwrap_or(0) as usize
        } else {
            read_be_u32(body, 0).unwrap_or(0).saturating_add(4) as usize
        };
        if ext_size <= body.len() {
            pos = ext_size;
        }
    }

    let mut cover_prio: u8 = if out.cover_bytes.is_some() { 2 } else { 0 };

    if version == 2 {
        while pos + 6 <= body.len() {
            if body[pos] == 0 {
                break;
            }
            let id = &body[pos..pos + 3];
            let Some(frame_len) = read_be_u24(body, pos + 3) else {
                break;
            };
            let start = pos + 6;
            let Some(end) = start.checked_add(frame_len as usize) else {
                break;
            };
            if end > body.len() {
                break;
            }
            parse_id3_v22_frame(id, &body[start..end], out, &mut cover_prio);
            pos = end;
        }
        return total_size;
    }

    while pos + 10 <= body.len() {
        if body[pos] == 0 {
            break;
        }
        let id = &body[pos..pos + 4];
        if !id
            .iter()
            .all(|&b| b.is_ascii_uppercase() || b.is_ascii_digit())
        {
            break;
        }
        let frame_size = if version == 4 {
            // 某些不规范标签工具在 ID3v2.4 中仍写入大端整数，优先 synchsafe，不合法则回退 u32
            read_synchsafe_u32(body, pos + 4)
                .or_else(|| read_be_u32(body, pos + 4))
                .unwrap_or(0) as usize
        } else {
            read_be_u32(body, pos + 4).unwrap_or(0) as usize
        };
        if frame_size == 0 {
            break;
        }
        let frame_flags_lo = body[pos + 9];
        let start = pos + 10;
        let Some(end) = start.checked_add(frame_size) else {
            break;
        };
        if end > body.len() {
            break;
        }
        let mut frame_slice = &body[start..end];
        let owned: Vec<u8>;
        if version == 4 {
            let has_data_len = (frame_flags_lo & 0x01) != 0;
            let frame_unsync = (frame_flags_lo & 0x02) != 0 || has_unsync;
            if frame_unsync {
                owned = remove_unsynchronisation(frame_slice);
                frame_slice = &owned;
            }
            if has_data_len && frame_slice.len() >= 4 {
                frame_slice = &frame_slice[4..];
            }
        }

        parse_id3_v23_v24_frame(id, frame_slice, out, &mut cover_prio);
        pos = end;
    }

    total_size
}

fn remove_unsynchronisation(input: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(input.len());
    let mut i = 0;
    while i < input.len() {
        out.push(input[i]);
        if input[i] == 0xFF && i + 1 < input.len() && input[i + 1] == 0x00 {
            i += 2;
        } else {
            i += 1;
        }
    }
    out
}

fn parse_id3_v22_frame(
    id: &[u8],
    payload: &[u8],
    out: &mut AudioEmbeddedMetadata,
    cover_prio: &mut u8,
) {
    match id {
        b"TT2" if out.title.is_none() => {
            out.title = decode_id3_text_frame(payload);
        }
        b"TP1" | b"TP2" if out.artist.is_none() => {
            out.artist = decode_id3_text_frame(payload);
        }
        b"TAL" if out.album.is_none() => {
            out.album = decode_id3_text_frame(payload);
        }
        b"ULT" => consider_lyrics(out, decode_id3_uslt(payload)),
        b"PIC" => {
            // encoding(1) + image_format(3) + pic_type(1) + desc(null-terminated) + data
            if payload.len() < 6 {
                return;
            }
            let enc = payload[0];
            let fmt = std::str::from_utf8(&payload[1..4]).unwrap_or("");
            let pic_type = payload[4];
            if let Some((_, rest)) = split_id3_encoded_string(enc, &payload[5..]) {
                set_cover_if_better(out, cover_prio, pic_type, fmt, rest);
            }
        }
        _ => {}
    }
}

fn parse_id3_v23_v24_frame(
    id: &[u8],
    payload: &[u8],
    out: &mut AudioEmbeddedMetadata,
    cover_prio: &mut u8,
) {
    match id {
        b"TIT2" if out.title.is_none() => {
            out.title = decode_id3_text_frame(payload);
        }
        b"TPE1" | b"TPE2" if out.artist.is_none() => {
            out.artist = decode_id3_text_frame(payload);
        }
        b"TALB" if out.album.is_none() => {
            out.album = decode_id3_text_frame(payload);
        }
        b"USLT" => consider_lyrics(out, decode_id3_uslt(payload)),
        b"SYLT" => consider_lyrics(out, decode_id3_sylt(payload)),
        b"TXXX" => {
            if payload.len() >= 2
                && let Some((desc, val_bytes)) = split_id3_encoded_string(payload[0], &payload[1..])
            {
                let key = desc.trim().to_ascii_uppercase();
                if matches!(
                    key.as_str(),
                    "LYRICS"
                        | "UNSYNCEDLYRICS"
                        | "UNSYNCED LYRICS"
                        | "SYNCEDLYRICS"
                        | "LYRIC"
                        | "LRC"
                ) {
                    consider_lyrics(out, clean_text(&decode_id3_bytes(payload[0], val_bytes)));
                }
            }
        }
        b"APIC" => {
            // encoding(1) + mime(null-terminated latin1) + pic_type(1) + desc(null-terminated enc) + data
            if payload.len() < 4 {
                return;
            }
            let enc = payload[0];
            let Some(mime_nul) = payload[1..].iter().position(|&b| b == 0) else {
                return;
            };
            let mime = std::str::from_utf8(&payload[1..1 + mime_nul]).unwrap_or("");
            let pic_type_off = 1 + mime_nul + 1;
            if pic_type_off >= payload.len() {
                return;
            }
            let pic_type = payload[pic_type_off];
            let desc_and_data = &payload[pic_type_off + 1..];
            if let Some((_, img_data)) = split_id3_encoded_string(enc, desc_and_data) {
                set_cover_if_better(out, cover_prio, pic_type, mime, img_data);
            }
        }
        _ => {}
    }
}

fn decode_id3_text_frame(payload: &[u8]) -> Option<String> {
    if payload.len() < 2 {
        return None;
    }
    clean_text(&decode_id3_bytes(payload[0], &payload[1..]))
}

fn decode_id3_uslt(payload: &[u8]) -> Option<String> {
    // encoding(1) + language(3) + content_descriptor(terminated) + lyrics_text
    if payload.len() < 5 {
        return None;
    }
    let enc = payload[0];
    let (_, lyrics_bytes) = split_id3_encoded_string(enc, &payload[4..])?;
    clean_text(&decode_id3_bytes(enc, lyrics_bytes))
}

fn decode_id3_sylt(payload: &[u8]) -> Option<String> {
    // encoding(1) + language(3) + timestamp_format(1) + content_type(1) + desc(term) + [(text, term, ts_be32)]
    if payload.len() < 7 {
        return None;
    }
    let enc = payload[0];
    let ts_format = payload[4]; // 2 = milliseconds
    if ts_format != 2 {
        return None;
    }
    let (_, mut cursor) = split_id3_encoded_string(enc, &payload[6..])?;
    let mut lines: Vec<String> = Vec::new();
    while !cursor.is_empty() {
        let Some((seg_text, after_text)) = split_id3_encoded_string(enc, cursor) else {
            break;
        };
        let Some(ts_ms) = read_be_u32(after_text, 0) else {
            break;
        };
        cursor = &after_text[4..];
        let trimmed = seg_text.replace(['\r', '\n'], " ");
        let trimmed = trimmed.trim();
        if !trimmed.is_empty() {
            let mins = ts_ms / 60_000;
            let secs = (ts_ms % 60_000) / 1_000;
            let cs = (ts_ms % 1_000) / 10;
            lines.push(format!("[{mins:02}:{secs:02}.{cs:02}]{trimmed}"));
        }
    }
    if lines.is_empty() {
        None
    } else {
        Some(lines.join("\n"))
    }
}

fn split_id3_encoded_string(enc: u8, input: &[u8]) -> Option<(String, &[u8])> {
    if enc == 1 || enc == 2 {
        // UTF-16 以双字节 0x00 0x00 终止（按 2 字节对齐扫描）
        let mut i = 0;
        while i + 1 < input.len() {
            if input[i] == 0 && input[i + 1] == 0 {
                let text = decode_id3_bytes(enc, &input[..i]);
                return Some((text, &input[i + 2..]));
            }
            i += 2;
        }
        None
    } else {
        let nul = input.iter().position(|&b| b == 0)?;
        let text = decode_id3_bytes(enc, &input[..nul]);
        Some((text, &input[nul + 1..]))
    }
}

fn decode_id3_bytes(enc: u8, raw: &[u8]) -> String {
    let trimmed_raw = match enc {
        1 | 2 => {
            let mut end = raw.len();
            while end >= 2 && raw[end - 2] == 0 && raw[end - 1] == 0 {
                end -= 2;
            }
            &raw[..end]
        }
        _ => {
            let mut end = raw.len();
            while end > 0 && raw[end - 1] == 0 {
                end -= 1;
            }
            &raw[..end]
        }
    };

    match enc {
        3 => String::from_utf8_lossy(trimmed_raw).into_owned(),
        1 => decode_utf16_with_bom(trimmed_raw),
        2 => decode_utf16_be(trimmed_raw),
        _ => {
            // 部分中文工具在 encoding=0 帧中直接写入 UTF-8，优先验证 UTF-8 再回退 ISO-8859-1
            if let Ok(s) = std::str::from_utf8(trimmed_raw) {
                s.to_string()
            } else {
                trimmed_raw.iter().map(|&b| b as char).collect()
            }
        }
    }
}

fn decode_utf16_with_bom(raw: &[u8]) -> String {
    if raw.len() >= 2 && raw[0] == 0xFF && raw[1] == 0xFE {
        decode_utf16_le(&raw[2..])
    } else if raw.len() >= 2 && raw[0] == 0xFE && raw[1] == 0xFF {
        decode_utf16_be(&raw[2..])
    } else {
        decode_utf16_le(raw)
    }
}

fn decode_utf16_le(raw: &[u8]) -> String {
    let units: Vec<u16> = raw
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&c| u16::from_le_bytes(c))
        .collect();
    String::from_utf16_lossy(&units)
}

fn decode_utf16_be(raw: &[u8]) -> String {
    let units: Vec<u16> = raw
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&c| u16::from_be_bytes(c))
        .collect();
    String::from_utf16_lossy(&units)
}

// ============================================================================
// 3. MP4 / M4A / ALAC 解析器（moov -> udta -> meta -> ilst）
// ============================================================================

fn is_mp4_header(head: &[u8]) -> bool {
    head.len() >= 12 && &head[4..8] == b"ftyp"
}

fn parse_mp4(head: &[u8], tail: Option<&[u8]>, out: &mut AudioEmbeddedMetadata) {
    let mut cover_prio: u8 = if out.cover_bytes.is_some() { 2 } else { 0 };
    let mut found_moov = false;
    let mut saw_mdat = false;

    let mut pos: usize = 0;
    while pos + 8 <= head.len() {
        let Some((box_type, header_len, total_size)) = read_mp4_box_header(head, pos) else {
            break;
        };
        let box_start = pos + header_len;
        let box_end_u64 = (pos as u64).saturating_add(total_size);

        if box_type == *b"moov" {
            found_moov = true;
            if box_end_u64 <= head.len() as u64 {
                parse_mp4_moov(&head[box_start..box_end_u64 as usize], out, &mut cover_prio);
            } else {
                // moov 在文件头部但超出当前窗口，尽量解析已下载部分，并提示完整 moov 长度
                parse_mp4_moov(&head[box_start..], out, &mut cover_prio);
                if !out.has_cover_or_lyrics() && box_end_u64 <= MAX_RECOMMENDED_RANGE_BYTES {
                    out.needed_head_bytes = Some(box_end_u64);
                }
            }
            break;
        } else if box_type == *b"mdat" {
            saw_mdat = true;
            // mdat 在前说明 moov 位于文件末尾
            if box_end_u64 > head.len() as u64 {
                break;
            }
        }

        if total_size == 0 || box_end_u64 > head.len() as u64 {
            break;
        }
        pos = box_end_u64 as usize;
    }

    if !found_moov {
        if let Some(tail_buf) = tail {
            scan_mp4_tail_for_ilst(tail_buf, out, &mut cover_prio);
        } else if saw_mdat {
            out.needed_tail_bytes = Some(512 * 1024);
        }
    }
}

fn read_mp4_box_header(buf: &[u8], pos: usize) -> Option<([u8; 4], usize, u64)> {
    let size32 = read_be_u32(buf, pos)? as u64;
    let box_type = [buf[pos + 4], buf[pos + 5], buf[pos + 6], buf[pos + 7]];
    if size32 == 1 {
        let size64 = read_be_u64(buf, pos + 8)?;
        if size64 < 16 {
            return None;
        }
        Some((box_type, 16, size64))
    } else if size32 == 0 {
        Some((box_type, 8, (buf.len() - pos) as u64))
    } else if size32 < 8 {
        None
    } else {
        Some((box_type, 8, size32))
    }
}

fn parse_mp4_moov(moov: &[u8], out: &mut AudioEmbeddedMetadata, cover_prio: &mut u8) {
    let mut pos = 0usize;
    while pos + 8 <= moov.len() {
        let Some((box_type, hdr, total)) = read_mp4_box_header(moov, pos) else {
            break;
        };
        let end = (pos as u64).saturating_add(total).min(moov.len() as u64) as usize;
        if box_type == *b"udta" {
            parse_mp4_udta(&moov[pos + hdr..end], out, cover_prio);
        } else if box_type == *b"meta" {
            parse_mp4_meta(&moov[pos + hdr..end], out, cover_prio);
        }
        if total == 0 || end <= pos {
            break;
        }
        pos = end;
    }
}

fn parse_mp4_udta(udta: &[u8], out: &mut AudioEmbeddedMetadata, cover_prio: &mut u8) {
    let mut pos = 0usize;
    while pos + 8 <= udta.len() {
        let Some((box_type, hdr, total)) = read_mp4_box_header(udta, pos) else {
            break;
        };
        let end = (pos as u64).saturating_add(total).min(udta.len() as u64) as usize;
        if box_type == *b"meta" {
            parse_mp4_meta(&udta[pos + hdr..end], out, cover_prio);
        }
        if total == 0 || end <= pos {
            break;
        }
        pos = end;
    }
}

fn parse_mp4_meta(meta: &[u8], out: &mut AudioEmbeddedMetadata, cover_prio: &mut u8) {
    // FullBox: 4-byte version + flags，少数生成器省略该 4 字节，做双路兼容
    let start_offset = if meta.len() >= 12 && &meta[8..12] == b"hdlr"
        || meta.len() >= 12 && &meta[8..12] == b"ilst"
    {
        4
    } else if meta.len() >= 8 && (&meta[4..8] == b"hdlr" || &meta[4..8] == b"ilst") {
        0
    } else {
        4
    };
    let mut pos = start_offset;
    while pos + 8 <= meta.len() {
        let Some((box_type, hdr, total)) = read_mp4_box_header(meta, pos) else {
            break;
        };
        let end = (pos as u64).saturating_add(total).min(meta.len() as u64) as usize;
        if box_type == *b"ilst" {
            parse_mp4_ilst(&meta[pos + hdr..end], out, cover_prio);
        }
        if total == 0 || end <= pos {
            break;
        }
        pos = end;
    }
}

fn scan_mp4_tail_for_ilst(tail: &[u8], out: &mut AudioEmbeddedMetadata, cover_prio: &mut u8) {
    // 在尾块中定位合法的 `ilst` 原子头（4-byte size + "ilst"）
    let mut i = 4usize;
    while i + 4 <= tail.len() {
        if &tail[i..i + 4] == b"ilst"
            && let Some(size) = read_be_u32(tail, i - 4)
        {
            let size = size as usize;
            if size >= 8 && (i - 4).saturating_add(size) <= tail.len() {
                parse_mp4_ilst(&tail[i + 4..(i - 4) + size], out, cover_prio);
                if out.has_cover_or_lyrics() {
                    return;
                }
            }
        }
        i += 1;
    }
}

fn parse_mp4_ilst(ilst: &[u8], out: &mut AudioEmbeddedMetadata, cover_prio: &mut u8) {
    let mut pos = 0usize;
    while pos + 8 <= ilst.len() {
        let Some((atom_type, hdr, total)) = read_mp4_box_header(ilst, pos) else {
            break;
        };
        let end = (pos as u64).saturating_add(total).min(ilst.len() as u64) as usize;
        let children = &ilst[pos + hdr..end];

        // 查找子原子 `data`（格式：size(4) + "data"(4) + type_indicator(4) + locale(4) + value）
        let mut cpos = 0usize;
        while cpos + 16 <= children.len() {
            let Some((ctype, chdr, ctotal)) = read_mp4_box_header(children, cpos) else {
                break;
            };
            let cend = (cpos as u64)
                .saturating_add(ctotal)
                .min(children.len() as u64) as usize;
            if ctype == *b"data" && cpos + chdr + 8 <= cend {
                let type_ind = read_be_u32(children, cpos + chdr).unwrap_or(0);
                let val_bytes = &children[cpos + chdr + 8..cend];
                match &atom_type {
                    b"\xa9nam" if out.title.is_none() => {
                        out.title = clean_text(&String::from_utf8_lossy(val_bytes));
                    }
                    b"\xa9ART" | b"aART" if out.artist.is_none() => {
                        out.artist = clean_text(&String::from_utf8_lossy(val_bytes));
                    }
                    b"\xa9alb" if out.album.is_none() => {
                        out.album = clean_text(&String::from_utf8_lossy(val_bytes));
                    }
                    b"\xa9lyr" => {
                        consider_lyrics(out, clean_text(&String::from_utf8_lossy(val_bytes)));
                    }
                    b"covr" => {
                        let mime_hint = match type_ind {
                            13 => "image/jpeg",
                            14 => "image/png",
                            27 => "image/bmp",
                            _ => "",
                        };
                        set_cover_if_better(out, cover_prio, 3, mime_hint, val_bytes);
                    }
                    _ => {}
                }
            }
            if ctotal == 0 || cend <= cpos {
                break;
            }
            cpos = cend;
        }

        if total == 0 || end <= pos {
            break;
        }
        pos = end;
    }
}

// ============================================================================
// 4. Ogg Vorbis / Ogg Opus 解析器
// ============================================================================

fn parse_ogg(data: &[u8], out: &mut AudioEmbeddedMetadata) {
    let mut pos = 0usize;
    let mut current_packet: Vec<u8> = Vec::new();
    let mut packets_parsed = 0usize;
    let mut cover_prio: u8 = if out.cover_bytes.is_some() { 2 } else { 0 };

    while pos + 27 <= data.len() && packets_parsed < 4 {
        if &data[pos..pos + 4] != b"OggS" {
            break;
        }
        let seg_count = data[pos + 26] as usize;
        let seg_table_start = pos + 27;
        let seg_table_end = seg_table_start + seg_count;
        if seg_table_end > data.len() {
            break;
        }
        let seg_table = &data[seg_table_start..seg_table_end];
        let mut body_pos = seg_table_end;

        for &seg_len in seg_table {
            let len = seg_len as usize;
            let Some(next_pos) = body_pos.checked_add(len) else {
                return;
            };
            if next_pos > data.len() {
                // 包跨出当前窗口，提示追加拉取
                if current_packet.starts_with(b"\x03vorbis")
                    || current_packet.starts_with(b"OpusTags")
                {
                    let desired = (data.len() as u64)
                        .saturating_add(512 * 1024)
                        .min(MAX_RECOMMENDED_RANGE_BYTES);
                    if desired > data.len() as u64 {
                        out.needed_head_bytes = Some(desired);
                    }
                }
                return;
            }
            if current_packet.len() + len <= MAX_EMBEDDED_COVER_BYTES * 2 {
                current_packet.extend_from_slice(&data[body_pos..next_pos]);
            }
            body_pos = next_pos;

            if seg_len < 255 {
                // 完整 Ogg 包组装完成
                packets_parsed += 1;
                if current_packet.starts_with(b"\x03vorbis") {
                    parse_vorbis_comment_block(&current_packet[7..], out, &mut cover_prio);
                } else if current_packet.starts_with(b"OpusTags") {
                    parse_vorbis_comment_block(&current_packet[8..], out, &mut cover_prio);
                }
                current_packet.clear();
                if packets_parsed >= 2 && out.has_cover_or_lyrics() {
                    return;
                }
            }
        }
        pos = body_pos;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_jpeg() -> Vec<u8> {
        vec![
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, b'J', b'F', b'I', b'F', 0x00, 0xFF, 0xD9,
        ]
    }

    fn fake_png() -> Vec<u8> {
        vec![
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x00,
        ]
    }

    fn build_flac_block(block_type: u8, is_last: bool, payload: &[u8]) -> Vec<u8> {
        let mut out = Vec::with_capacity(4 + payload.len());
        let hdr = (if is_last { 0x80 } else { 0x00 }) | (block_type & 0x7F);
        let len = payload.len() as u32;
        out.push(hdr);
        out.push(((len >> 16) & 0xFF) as u8);
        out.push(((len >> 8) & 0xFF) as u8);
        out.push((len & 0xFF) as u8);
        out.extend_from_slice(payload);
        out
    }

    fn build_vorbis_comment(tags: &[(&str, &str)]) -> Vec<u8> {
        let vendor = b"reference libFLAC";
        let mut buf = Vec::new();
        buf.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
        buf.extend_from_slice(vendor);
        buf.extend_from_slice(&(tags.len() as u32).to_le_bytes());
        for (k, v) in tags {
            let entry = format!("{k}={v}");
            buf.extend_from_slice(&(entry.len() as u32).to_le_bytes());
            buf.extend_from_slice(entry.as_bytes());
        }
        buf
    }

    fn build_flac_picture(pic_type: u32, mime: &str, img: &[u8]) -> Vec<u8> {
        let mut buf = Vec::new();
        buf.extend_from_slice(&pic_type.to_be_bytes());
        buf.extend_from_slice(&(mime.len() as u32).to_be_bytes());
        buf.extend_from_slice(mime.as_bytes());
        buf.extend_from_slice(&0u32.to_be_bytes()); // desc len
        buf.extend_from_slice(&[0u8; 16]); // w, h, depth, colors
        buf.extend_from_slice(&(img.len() as u32).to_be_bytes());
        buf.extend_from_slice(img);
        buf
    }

    #[test]
    fn parses_flac_vorbis_lyrics_and_picture_cover() {
        let jpeg = fake_jpeg();
        let vc = build_vorbis_comment(&[
            ("TITLE", "evergreen"),
            ("ARTIST", "鹿乃"),
            ("ALBUM", "evergreen"),
            ("LYRICS", "[00:01.20]第一句歌词\n[00:05.50]第二句歌词"),
        ]);
        let pic = build_flac_picture(3, "image/jpeg", &jpeg);

        let mut flac = b"fLaC".to_vec();
        flac.extend_from_slice(&build_flac_block(0, false, &[0u8; 34])); // STREAMINFO
        flac.extend_from_slice(&build_flac_block(4, false, &vc));
        flac.extend_from_slice(&build_flac_block(6, true, &pic));

        let parsed = parse_audio_embedded_metadata(&flac, None);
        assert_eq!(parsed.title.as_deref(), Some("evergreen"));
        assert_eq!(parsed.artist.as_deref(), Some("鹿乃"));
        assert_eq!(parsed.album.as_deref(), Some("evergreen"));
        assert_eq!(
            parsed.lyrics.as_deref(),
            Some("[00:01.20]第一句歌词\n[00:05.50]第二句歌词")
        );
        assert_eq!(parsed.cover_mime.as_deref(), Some("image/jpeg"));
        assert_eq!(parsed.cover_bytes.as_deref(), Some(jpeg.as_slice()));
        assert_eq!(parsed.needed_head_bytes, None);
    }

    #[test]
    fn flac_truncated_large_picture_reports_needed_head_bytes() {
        let large_pic = build_flac_picture(3, "image/jpeg", &vec![0xFF; 400_000]);
        let mut flac = b"fLaC".to_vec();
        flac.extend_from_slice(&build_flac_block(6, true, &large_pic));

        let head_only = &flac[..16_384];
        let parsed = parse_audio_embedded_metadata(head_only, None);
        assert!(parsed.cover_bytes.is_none());
        let needed = parsed
            .needed_head_bytes
            .expect("should request larger head range");
        assert!(needed > 400_000);
        assert!(needed <= MAX_RECOMMENDED_RANGE_BYTES);
    }

    fn build_id3v23_frame(id: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut f = Vec::with_capacity(10 + payload.len());
        f.extend_from_slice(id);
        f.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        f.extend_from_slice(&[0, 0]);
        f.extend_from_slice(payload);
        f
    }

    fn write_synchsafe(val: u32) -> [u8; 4] {
        [
            ((val >> 21) & 0x7F) as u8,
            ((val >> 14) & 0x7F) as u8,
            ((val >> 7) & 0x7F) as u8,
            (val & 0x7F) as u8,
        ]
    }

    #[test]
    fn parses_id3v23_uslt_sylt_and_apic() {
        let png = fake_png();
        let mut body = Vec::new();
        // TIT2 (UTF-8 encoding=3)
        let mut tit2 = vec![3u8];
        tit2.extend_from_slice("夜驱".as_bytes());
        body.extend_from_slice(&build_id3v23_frame(b"TIT2", &tit2));

        // USLT (plain lyrics)
        let mut uslt = vec![3u8, b'z', b'h', b'o', 0u8];
        uslt.extend_from_slice("无时间轴纯文本歌词".as_bytes());
        body.extend_from_slice(&build_id3v23_frame(b"USLT", &uslt));

        // SYLT (should take priority over plain USLT!)
        let mut sylt = vec![3u8, b'z', b'h', b'o', 2u8, 1u8, 0u8];
        sylt.extend_from_slice("第一行".as_bytes());
        sylt.push(0);
        sylt.extend_from_slice(&12_340u32.to_be_bytes());
        sylt.extend_from_slice("第二行".as_bytes());
        sylt.push(0);
        sylt.extend_from_slice(&65_000u32.to_be_bytes());
        body.extend_from_slice(&build_id3v23_frame(b"SYLT", &sylt));

        // APIC (Front Cover)
        let mut apic = vec![0u8];
        apic.extend_from_slice(b"image/png\0");
        apic.push(3u8);
        apic.push(0u8); // empty description
        apic.extend_from_slice(&png);
        body.extend_from_slice(&build_id3v23_frame(b"APIC", &apic));

        let mut mp3 = Vec::new();
        mp3.extend_from_slice(b"ID3");
        mp3.extend_from_slice(&[3, 0, 0]);
        mp3.extend_from_slice(&write_synchsafe(body.len() as u32));
        mp3.extend_from_slice(&body);

        let parsed = parse_audio_embedded_metadata(&mp3, None);
        assert_eq!(parsed.title.as_deref(), Some("夜驱"));
        assert_eq!(
            parsed.lyrics.as_deref(),
            Some("[00:12.34]第一行\n[01:05.00]第二行")
        );
        assert_eq!(parsed.cover_mime.as_deref(), Some("image/png"));
        assert_eq!(parsed.cover_bytes.as_deref(), Some(png.as_slice()));
    }

    fn mp4_box(tag: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let len = (8 + payload.len()) as u32;
        let mut out = Vec::with_capacity(len as usize);
        out.extend_from_slice(&len.to_be_bytes());
        out.extend_from_slice(tag);
        out.extend_from_slice(payload);
        out
    }

    #[test]
    fn parses_mp4_m4a_faststart_and_tail_moov() {
        let jpeg = fake_jpeg();
        let mut lyr_data = Vec::new();
        lyr_data.extend_from_slice(&1u32.to_be_bytes()); // UTF-8
        lyr_data.extend_from_slice(&0u32.to_be_bytes());
        lyr_data.extend_from_slice("[00:10.00]M4A 歌词".as_bytes());
        let lyr_atom = mp4_box(b"\xa9lyr", &mp4_box(b"data", &lyr_data));

        let mut covr_data = Vec::new();
        covr_data.extend_from_slice(&13u32.to_be_bytes()); // JPEG
        covr_data.extend_from_slice(&0u32.to_be_bytes());
        covr_data.extend_from_slice(&jpeg);
        let covr_atom = mp4_box(b"covr", &mp4_box(b"data", &covr_data));

        let mut ilst_payload = Vec::new();
        ilst_payload.extend_from_slice(&lyr_atom);
        ilst_payload.extend_from_slice(&covr_atom);
        let ilst = mp4_box(b"ilst", &ilst_payload);

        let mut meta_payload = vec![0u8; 4]; // version/flags
        meta_payload.extend_from_slice(&ilst);
        let meta = mp4_box(b"meta", &meta_payload);
        let udta = mp4_box(b"udta", &meta);
        let moov = mp4_box(b"moov", &udta);
        let ftyp = mp4_box(b"ftyp", b"M4A \0\0\0\0M4A mp42");

        // Faststart: ftyp + moov
        let mut fast = ftyp.clone();
        fast.extend_from_slice(&moov);
        let parsed = parse_audio_embedded_metadata(&fast, None);
        assert_eq!(parsed.lyrics.as_deref(), Some("[00:10.00]M4A 歌词"));
        assert_eq!(parsed.cover_bytes.as_deref(), Some(jpeg.as_slice()));

        // Tail moov: ftyp + oversized mdat header
        let mut head_non_fast = ftyp;
        head_non_fast.extend_from_slice(&(10_000_000u32).to_be_bytes());
        head_non_fast.extend_from_slice(b"mdat");
        head_non_fast.extend_from_slice(&[0u8; 64]);

        let first_pass = parse_audio_embedded_metadata(&head_non_fast, None);
        assert!(first_pass.needed_tail_bytes.is_some());

        let second_pass = parse_audio_embedded_metadata(&head_non_fast, Some(&moov));
        assert_eq!(second_pass.lyrics.as_deref(), Some("[00:10.00]M4A 歌词"));
        assert_eq!(second_pass.cover_bytes.as_deref(), Some(jpeg.as_slice()));
    }

    #[test]
    fn parses_ogg_opus_comments_and_base64_picture() {
        let jpeg = fake_jpeg();
        let pic_b64 = BASE64_STANDARD.encode(build_flac_picture(3, "image/jpeg", &jpeg));
        let mut opus_tags = b"OpusTags".to_vec();
        opus_tags.extend_from_slice(&build_vorbis_comment(&[
            ("TITLE", "Opus Track"),
            ("UNSYNCEDLYRICS", "纯文本内嵌歌词"),
            ("METADATA_BLOCK_PICTURE", &pic_b64),
        ]));

        // 构造单个 Ogg 页面承载 OpusTags（分片每段 <= 255 字节）
        let mut segs = Vec::new();
        let mut rem = opus_tags.len();
        while rem >= 255 {
            segs.push(255u8);
            rem -= 255;
        }
        segs.push(rem as u8);

        let mut ogg = Vec::new();
        ogg.extend_from_slice(b"OggS");
        ogg.extend_from_slice(&[0u8; 22]);
        ogg.push(segs.len() as u8);
        ogg.extend_from_slice(&segs);
        ogg.extend_from_slice(&opus_tags);

        let parsed = parse_audio_embedded_metadata(&ogg, None);
        assert_eq!(parsed.title.as_deref(), Some("Opus Track"));
        assert_eq!(parsed.lyrics.as_deref(), Some("纯文本内嵌歌词"));
        assert_eq!(parsed.cover_mime.as_deref(), Some("image/jpeg"));
        assert_eq!(parsed.cover_bytes.as_deref(), Some(jpeg.as_slice()));
    }
}
