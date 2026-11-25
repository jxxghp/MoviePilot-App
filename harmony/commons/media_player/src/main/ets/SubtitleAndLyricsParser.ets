import { util } from '@kit.ArkTS';

/** 单行 LRC 同步歌词时间轴节点。 */
export interface LyricLineCue {
  timeMs: number;
  text: string;
}

/** 字幕时间轴片段节点（兼容 SRT / WebVTT / ASS / SSA）。 */
export interface SubtitleCue {
  startMs: number;
  endMs: number;
  text: string;
}

/**
 * 智能解码外挂字幕字节流（支持 UTF-8 BOM、UTF-16 LE/BE、严格 UTF-8 与 GBK/GB18030 中文回退，避免常见中文字幕乱码）。
 */
export function decodeSubtitleBytes(bytes: Uint8Array): string {
  if (!bytes || bytes.byteLength === 0) {
    return '';
  }
  if (bytes.byteLength >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
    try {
      return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
    } catch {
      // continue
    }
  }
  if (bytes.byteLength >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
    try {
      return util.TextDecoder.create('utf-16le', { ignoreBOM: true }).decodeToString(bytes);
    } catch {
      // continue
    }
  }
  if (bytes.byteLength >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
    try {
      return util.TextDecoder.create('utf-16be', { ignoreBOM: true }).decodeToString(bytes);
    } catch {
      // continue
    }
  }
  try {
    return util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true }).decodeToString(bytes);
  } catch {
    // 非法 UTF-8 字节序列回退 GB18030 / GBK 解码
  }
  try {
    return util.TextDecoder.create('gb18030', { ignoreBOM: true }).decodeToString(bytes);
  } catch {
    // continue
  }
  try {
    return util.TextDecoder.create('gbk', { ignoreBOM: true }).decodeToString(bytes);
  } catch {
    // continue
  }
  try {
    return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeToString(bytes);
  } catch {
    return '';
  }
}

function stripBomAndNormalizeLines(raw: string): string[] {
  if (!raw || raw.length === 0) {
    return [];
  }
  const cleaned = raw.charCodeAt(0) === 0xFEFF ? raw.substring(1) : raw;
  return cleaned.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
}

function cleanMarkupTags(raw: string): string {
  if (!raw) {
    return '';
  }
  return raw
    .replace(/\{[^}]*\}/g, '')
    .replace(/\\N/g, '\n')
    .replace(/\\n/g, '\n')
    .replace(/\\h/g, ' ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/?[a-zA-Z][^>]*>/g, '')
    .trim();
}

function parseLrcTimestampToken(token: string): number {
  // 支持 mm:ss.xx, mm:ss.xxx, mm:ss:xx, hh:mm:ss.xx, mm:ss
  const m = token.match(/^(\d{1,3}):(\d{1,2})(?:[:.](\d{1,3}))?(?:[:.](\d{1,3}))?$/);
  if (!m) {
    return -1;
  }
  if (m[4] !== undefined) {
    const hrs = parseInt(m[1], 10);
    const mins = parseInt(m[2], 10);
    const secs = parseInt(m[3], 10);
    const fracRaw = m[4];
    const ms = fracRaw.length === 1 ? parseInt(fracRaw, 10) * 100
      : (fracRaw.length === 2 ? parseInt(fracRaw, 10) * 10 : parseInt(fracRaw, 10));
    return ((hrs * 3600 + mins * 60 + secs) * 1000) + ms;
  }
  const mins = parseInt(m[1], 10);
  const secs = parseInt(m[2], 10);
  let ms = 0;
  if (m[3] !== undefined) {
    const fracRaw = m[3];
    ms = fracRaw.length === 1 ? parseInt(fracRaw, 10) * 100
      : (fracRaw.length === 2 ? parseInt(fracRaw, 10) * 10 : parseInt(fracRaw, 10));
  }
  return (mins * 60 + secs) * 1000 + ms;
}

/**
 * 解析 LRC 歌词文本为按时间升序排列的 `LyricLineCue[]`：
 * - 支持同一行多个时间戳标签（如 `[00:12.34][01:45.60]歌词正文`）与 `[offset:±ms]` 全局偏移。
 */
export function parseLrcLyrics(raw: string): LyricLineCue[] {
  const lines = stripBomAndNormalizeLines(raw);
  const cues: LyricLineCue[] = [];
  let globalOffsetMs = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0) {
      continue;
    }
    const offsetMatch = line.match(/^\[offset:\s*([+-]?\d+)\s*\]$/i);
    if (offsetMatch) {
      const parsedOffset = parseInt(offsetMatch[1], 10);
      if (Number.isFinite(parsedOffset)) {
        globalOffsetMs = parsedOffset;
      }
      continue;
    }

    const timestamps: number[] = [];
    let cursor = 0;
    while (cursor < line.length && line.charAt(cursor) === '[') {
      const closeIdx = line.indexOf(']', cursor + 1);
      if (closeIdx < 0) {
        break;
      }
      const inside = line.substring(cursor + 1, closeIdx).trim();
      const ts = parseLrcTimestampToken(inside);
      if (ts < 0) {
        break;
      }
      timestamps.push(ts);
      cursor = closeIdx + 1;
    }

    if (timestamps.length === 0) {
      continue;
    }
    const text = line.substring(cursor).trim();
    if (text.length === 0) {
      continue;
    }
    for (let j = 0; j < timestamps.length; j++) {
      const adjusted = Math.max(0, timestamps[j] - globalOffsetMs);
      cues.push({
        timeMs: adjusted,
        text: text
      });
    }
  }

  cues.sort((a: LyricLineCue, b: LyricLineCue) => a.timeMs - b.timeMs);
  return cues;
}

/**
 * 提取无时间轴纯文本内嵌歌词行（自动过滤空行与 `[ti:]`/`[ar:]`/`[al:]` 等 LRC 元信息行）。
 */
export function extractPlainLyricsLines(raw: string): string[] {
  const lines = stripBomAndNormalizeLines(raw);
  const out: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (trimmed.length === 0) {
      continue;
    }
    if (/^\[(ti|ar|al|au|by|offset|re|ve|length):.*\]$/i.test(trimmed)) {
      continue;
    }
    out.push(trimmed);
  }
  return out;
}

/** 二分检索当前播放进度命中的歌词行下标（未命中时返回 `-1`）。 */
export function findActiveLyricIndex(cues: LyricLineCue[], posMs: number): number {
  if (cues.length === 0 || !Number.isFinite(posMs)) {
    return -1;
  }
  const target = posMs + 120;
  if (target < cues[0].timeMs) {
    return -1;
  }
  let low = 0;
  let high = cues.length - 1;
  let ans = 0;
  while (low <= high) {
    const mid = (low + high) >> 1;
    if (cues[mid].timeMs <= target) {
      ans = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return ans;
}

function parseSrtOrVttTimestamp(raw: string): number {
  const token = raw.trim().replace(',', '.');
  const parts = token.split(':');
  if (parts.length < 2 || parts.length > 3) {
    return -1;
  }
  let hrs = 0;
  let mins = 0;
  let secPart = '';
  if (parts.length === 3) {
    hrs = parseInt(parts[0], 10);
    mins = parseInt(parts[1], 10);
    secPart = parts[2];
  } else {
    mins = parseInt(parts[0], 10);
    secPart = parts[1];
  }
  const secSplit = secPart.split('.');
  const secs = parseInt(secSplit[0], 10);
  let ms = 0;
  if (secSplit.length > 1) {
    const frac = secSplit[1].substring(0, 3).padEnd(3, '0');
    ms = parseInt(frac, 10);
  }
  if (!Number.isFinite(hrs) || !Number.isFinite(mins) || !Number.isFinite(secs) || !Number.isFinite(ms)) {
    return -1;
  }
  return ((hrs * 3600 + mins * 60 + secs) * 1000) + ms;
}

function parseAssTimestamp(raw: string): number {
  const m = raw.trim().match(/^(\d+):(\d{1,2}):(\d{1,2})[.:](\d{1,3})$/);
  if (!m) {
    return -1;
  }
  const hrs = parseInt(m[1], 10);
  const mins = parseInt(m[2], 10);
  const secs = parseInt(m[3], 10);
  const fracRaw = m[4];
  const ms = fracRaw.length === 1 ? parseInt(fracRaw, 10) * 100
    : (fracRaw.length === 2 ? parseInt(fracRaw, 10) * 10 : parseInt(fracRaw, 10));
  return ((hrs * 3600 + mins * 60 + secs) * 1000) + ms;
}

function parseAssOrSsaSubtitles(lines: string[]): SubtitleCue[] {
  const cues: SubtitleCue[] = [];
  let inEvents = false;
  let startCol = 1;
  let endCol = 2;
  let textCol = 9;
  let totalCols = 10;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0 || line.startsWith(';')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      inEvents = line.toLowerCase() === '[events]';
      continue;
    }
    if (!inEvents && !line.toLowerCase().startsWith('dialogue:')) {
      continue;
    }
    if (line.toLowerCase().startsWith('format:')) {
      const cols = line.substring(7).split(',');
      totalCols = cols.length;
      for (let c = 0; c < cols.length; c++) {
        const key = cols[c].trim().toLowerCase();
        if (key === 'start') {
          startCol = c;
        } else if (key === 'end') {
          endCol = c;
        } else if (key === 'text') {
          textCol = c;
        }
      }
      continue;
    }
    if (line.toLowerCase().startsWith('dialogue:')) {
      const payload = line.substring(9).trimStart();
      const fields: string[] = [];
      let searchFrom = 0;
      const maxSplits = Math.max(textCol, totalCols - 1);
      for (let s = 0; s < maxSplits; s++) {
        const commaIdx = payload.indexOf(',', searchFrom);
        if (commaIdx < 0) {
          break;
        }
        fields.push(payload.substring(searchFrom, commaIdx));
        searchFrom = commaIdx + 1;
      }
      fields.push(payload.substring(searchFrom));
      if (fields.length <= Math.max(startCol, endCol, textCol)) {
        continue;
      }
      const startMs = parseAssTimestamp(fields[startCol]);
      const endMs = parseAssTimestamp(fields[endCol]);
      if (startMs < 0 || endMs <= startMs) {
        continue;
      }
      const text = cleanMarkupTags(fields[textCol]);
      if (text.length > 0) {
        cues.push({
          startMs: startMs,
          endMs: endMs,
          text: text
        });
      }
    }
  }

  cues.sort((a: SubtitleCue, b: SubtitleCue) => a.startMs - b.startMs);
  return cues;
}

function parseSrtOrVttSubtitles(lines: string[]): SubtitleCue[] {
  const cues: SubtitleCue[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i].trim();
    if (
      line.length === 0 ||
      line.toUpperCase().startsWith('WEBVTT') ||
      line.toUpperCase().startsWith('NOTE') ||
      line.toUpperCase().startsWith('STYLE')
    ) {
      i++;
      continue;
    }
    let arrowLine = line;
    if (!arrowLine.includes('-->')) {
      if (i + 1 < lines.length && lines[i + 1].includes('-->')) {
        i++;
        arrowLine = lines[i].trim();
      } else {
        i++;
        continue;
      }
    }

    const arrowIdx = arrowLine.indexOf('-->');
    const leftRaw = arrowLine.substring(0, arrowIdx).trim();
    const rightFull = arrowLine.substring(arrowIdx + 3).trim();
    const rightSpace = rightFull.search(/\s/);
    const rightRaw = rightSpace >= 0 ? rightFull.substring(0, rightSpace) : rightFull;

    const startMs = parseSrtOrVttTimestamp(leftRaw);
    const endMs = parseSrtOrVttTimestamp(rightRaw);
    i++;

    const textLines: string[] = [];
    while (i < lines.length && lines[i].trim().length > 0) {
      textLines.push(lines[i]);
      i++;
    }

    if (startMs >= 0 && endMs > startMs && textLines.length > 0) {
      const cleaned = cleanMarkupTags(textLines.join('\n'));
      if (cleaned.length > 0) {
        cues.push({
          startMs: startMs,
          endMs: endMs,
          text: cleaned
        });
      }
    }
  }

  cues.sort((a: SubtitleCue, b: SubtitleCue) => a.startMs - b.startMs);
  return cues;
}

/**
 * 解析外挂字幕文本（自动识别 SRT、WebVTT、ASS 与 SSA）。
 */
export function parseSubtitleText(raw: string, formatHint: string = ''): SubtitleCue[] {
  const lines = stripBomAndNormalizeLines(raw);
  if (lines.length === 0) {
    return [];
  }
  const hint = formatHint.trim().toLowerCase();
  if (hint === 'ass' || hint === 'ssa') {
    return parseAssOrSsaSubtitles(lines);
  }
  for (let i = 0; i < Math.min(lines.length, 40); i++) {
    const lower = lines[i].trim().toLowerCase();
    if (lower === '[script info]' || lower === '[events]' || lower.startsWith('dialogue:')) {
      return parseAssOrSsaSubtitles(lines);
    }
  }
  return parseSrtOrVttSubtitles(lines);
}

/**
 * 查找指定播放时间（毫秒）命中的字幕文本，支持双语同屏多条 `Dialogue` 合并去重。
 */
export function findActiveSubtitleText(cues: SubtitleCue[], posMs: number): string {
  if (cues.length === 0 || !Number.isFinite(posMs) || posMs < 0) {
    return '';
  }
  // 二分定位首个 startMs > posMs 的上界，再向前扫描覆盖区间
  let low = 0;
  let high = cues.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (cues[mid].startMs <= posMs) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }

  const matched: string[] = [];
  const lookbackStart = Math.max(0, low - 24);
  for (let i = lookbackStart; i < low; i++) {
    const cue = cues[i];
    if (posMs >= cue.startMs && posMs <= cue.endMs) {
      if (!matched.includes(cue.text)) {
        matched.push(cue.text);
      }
    }
  }
  return matched.join('\n');
}
