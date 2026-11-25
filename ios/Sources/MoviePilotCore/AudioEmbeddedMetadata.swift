import Foundation

/// 跨格式零依赖音频内嵌元数据解析结果（FLAC / ID3v2.2~2.4 / MP4·M4A / Ogg Vorbis·Opus）。
public struct AudioEmbeddedMetadata: Equatable, Sendable {
  public var title: String?
  public var artist: String?
  public var album: String?
  /// 内嵌歌词文本（可能是 `[mm:ss.xx]` 同步 LRC，也可能是纯文本歌词）。
  public var lyrics: String?
  public var coverMime: String?
  public var coverData: Data?
  /// 当头部元数据块超出初始读取窗口时，建议二次 Range 读取的头部总字节数（上限 6 MiB）。
  public var neededHeadBytes: UInt64?
  /// 当 M4A/MP4 为非 faststart（`moov` 位于末尾）时，建议读取的尾部字节数。
  public var neededTailBytes: UInt64?

  public init(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    lyrics: String? = nil,
    coverMime: String? = nil,
    coverData: Data? = nil,
    neededHeadBytes: UInt64? = nil,
    neededTailBytes: UInt64? = nil
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.lyrics = lyrics
    self.coverMime = coverMime
    self.coverData = coverData
    self.neededHeadBytes = neededHeadBytes
    self.neededTailBytes = neededTailBytes
  }

  public var hasCoverOrLyrics: Bool {
    if let data = coverData, !data.isEmpty { return true }
    if let text = lyrics, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
    return false
  }
}

/// 纯 Swift 安全二进制解析器（与 Rust `mp-core-model::audio_metadata` 1:1 语义一致）：
/// - 完整支持 FLAC（`VORBIS_COMMENT` + `PICTURE`）、ID3v2.2/2.3/2.4（`APIC`/`USLT`/`SYLT`/`TXXX`/`TIT2`/`TPE1`/`TALB`）、
///   MP4/M4A（`moov/udta/meta/ilst` `covr`/`©lyr` 及尾块回读）与 Ogg Vorbis/Opus（`OpusTags` + Base64 `METADATA_BLOCK_PICTURE`）。
public enum AudioEmbeddedMetadataParser {
  public static let maxCoverBytes = 8 * 1024 * 1024
  public static let maxRecommendedRangeBytes: UInt64 = 6 * 1024 * 1024

  public static func parse(head: Data, tail: Data? = nil) -> AudioEmbeddedMetadata {
    var out = AudioEmbeddedMetadata()
    let bytes = [UInt8](head)
    guard bytes.count >= 4 else { return out }

    var afterID3Offset = 0
    if bytes.count >= 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {  // "ID3"
      let totalID3 = parseID3v2(bytes, into: &out)
      if totalID3 > bytes.count {
        if UInt64(totalID3) <= maxRecommendedRangeBytes {
          out.neededHeadBytes = UInt64(totalID3)
        }
        return out
      }
      afterID3Offset = totalID3
    }

    let bodySlice: ArraySlice<UInt8> =
      afterID3Offset < bytes.count ? bytes[afterID3Offset...] : []
    let body = Array(bodySlice)

    if body.count >= 4, body[0] == 0x66, body[1] == 0x4C, body[2] == 0x61, body[3] == 0x43 {  // "fLaC"
      parseFLAC(body, baseOffset: UInt64(afterID3Offset), into: &out)
    } else if body.count >= 4, body[0] == 0x4F, body[1] == 0x67, body[2] == 0x67, body[3] == 0x53 {  // "OggS"
      parseOgg(body, into: &out)
    } else if isMP4Header(bytes) {
      let tailBytes = tail.map { [UInt8]($0) }
      parseMP4(head: bytes, tail: tailBytes, into: &out)
    }

    return out
  }

  /// 判断歌词文本是否包含 `[mm:ss` 时间戳。
  public static func looksLikeSyncedLrc(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    guard bytes.count >= 7 else { return false }
    for i in 0...(bytes.count - 7) where bytes[i] == 0x5B && isASCIIDigit(bytes[i + 1]) {
      var j = i + 1
      var digits = 0
      while j < bytes.count && isASCIIDigit(bytes[j]) && digits < 3 {
        j += 1
        digits += 1
      }
      if j + 3 <= bytes.count && bytes[j] == 0x3A
        && isASCIIDigit(bytes[j + 1]) && isASCIIDigit(bytes[j + 2])
      {
        return true
      }
    }
    return false
  }

  // MARK: - Helpers

  private static func isASCIIDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

  private static func cleanText(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0\u{FEFF}"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func considerLyrics(_ out: inout AudioEmbeddedMetadata, candidate: String?) {
    guard let text = candidate, !text.isEmpty else { return }
    if let existing = out.lyrics {
      if !looksLikeSyncedLrc(existing) && looksLikeSyncedLrc(text) {
        out.lyrics = text
      }
    } else {
      out.lyrics = text
    }
  }

  private static func sniffImageMime(_ data: [UInt8], declared: String) -> String? {
    guard data.count >= 4, data.count <= maxCoverBytes else { return nil }
    if data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF { return "image/jpeg" }
    if data.count >= 8,
      data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47,
      data[4] == 0x0D, data[5] == 0x0A, data[6] == 0x1A, data[7] == 0x0A
    {
      return "image/png"
    }
    if data.count >= 12,
      data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
      data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50
    {
      return "image/webp"
    }
    if data.count >= 6,
      data[0] == 0x47, data[1] == 0x49, data[2] == 0x46, data[3] == 0x38,
      (data[4] == 0x37 || data[4] == 0x39), data[5] == 0x61
    {
      return "image/gif"
    }
    if data[0] == 0x42, data[1] == 0x4D { return "image/bmp" }
    let clean = declared.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if clean == "jpg" || clean == "jpeg" { return "image/jpeg" }
    if clean == "png" { return "image/png" }
    if clean.hasPrefix("image/") { return clean }
    return nil
  }

  private static func setCoverIfBetter(
    _ out: inout AudioEmbeddedMetadata,
    bestPriority: inout UInt8,
    pictureType: UInt8,
    mimeHint: String,
    bytes: [UInt8]
  ) {
    guard let mime = sniffImageMime(bytes, declared: mimeHint) else { return }
    let prio: UInt8
    switch pictureType {
    case 3: prio = 3
    case 0, 4, 8, 10: prio = 2
    default: prio = 1
    }
    if prio > bestPriority || out.coverData == nil {
      bestPriority = prio
      out.coverMime = mime
      out.coverData = Data(bytes)
    }
  }

  private static func readBEU24(_ b: [UInt8], _ off: Int) -> UInt32? {
    guard off >= 0, off + 3 <= b.count else { return nil }
    return (UInt32(b[off]) << 16) | (UInt32(b[off + 1]) << 8) | UInt32(b[off + 2])
  }

  private static func readBEU32(_ b: [UInt8], _ off: Int) -> UInt32? {
    guard off >= 0, off + 4 <= b.count else { return nil }
    return (UInt32(b[off]) << 24) | (UInt32(b[off + 1]) << 16)
      | (UInt32(b[off + 2]) << 8) | UInt32(b[off + 3])
  }

  private static func readBEU64(_ b: [UInt8], _ off: Int) -> UInt64? {
    guard off >= 0, off + 8 <= b.count else { return nil }
    var v: UInt64 = 0
    for i in 0..<8 { v = (v << 8) | UInt64(b[off + i]) }
    return v
  }

  private static func readLEU32(_ b: [UInt8], _ off: Int) -> UInt32? {
    guard off >= 0, off + 4 <= b.count else { return nil }
    return UInt32(b[off]) | (UInt32(b[off + 1]) << 8)
      | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
  }

  private static func readSynchsafeU32(_ b: [UInt8], _ off: Int) -> UInt32? {
    guard off >= 0, off + 4 <= b.count else { return nil }
    if ((b[off] | b[off + 1] | b[off + 2] | b[off + 3]) & 0x80) != 0 { return nil }
    return (UInt32(b[off]) << 21) | (UInt32(b[off + 1]) << 14)
      | (UInt32(b[off + 2]) << 7) | UInt32(b[off + 3])
  }

  // MARK: - 1. FLAC

  private static func parseFLAC(
    _ data: [UInt8],
    baseOffset: UInt64,
    into out: inout AudioEmbeddedMetadata
  ) {
    var pos = 4
    var coverPrio: UInt8 = out.coverData != nil ? 2 : 0
    while pos + 4 <= data.count {
      let hdr = data[pos]
      let isLast = (hdr & 0x80) != 0
      let blockType = hdr & 0x7F
      guard let blockLen = readBEU24(data, pos + 1) else { break }
      let blockStart = pos + 4
      let (blockEnd, overflow) = blockStart.addingReportingOverflow(Int(blockLen))
      if overflow { break }
      if blockEnd > data.count {
        let absEnd = baseOffset + UInt64(blockEnd)
        let desired = min(absEnd + 65_536, maxRecommendedRangeBytes)
        if desired > baseOffset + UInt64(data.count) {
          out.neededHeadBytes = desired
        }
        break
      }
      let payload = Array(data[blockStart..<blockEnd])
      if blockType == 4 {
        parseVorbisComment(payload, into: &out, coverPrio: &coverPrio)
      } else if blockType == 6 {
        parseFLACPicture(payload, into: &out, coverPrio: &coverPrio)
      }
      pos = blockEnd
      if isLast { break }
    }
  }

  private static func parseVorbisComment(
    _ payload: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    guard let vendorLen = readLEU32(payload, 0) else { return }
    let (afterVendor, ov1) = 4.addingReportingOverflow(Int(vendorLen))
    guard !ov1, afterVendor + 4 <= payload.count,
      let count = readLEU32(payload, afterVendor)
    else { return }
    var pos = afterVendor + 4
    let capped = Int(min(count, 4096))
    for _ in 0..<capped {
      guard let len = readLEU32(payload, pos) else { break }
      pos += 4
      let (end, ov2) = pos.addingReportingOverflow(Int(len))
      guard !ov2, end <= payload.count else { break }
      if let entry = String(bytes: payload[pos..<end], encoding: .utf8),
        let eqIdx = entry.firstIndex(of: "=")
      {
        let rawKey = String(entry[..<eqIdx])
        let rawVal = String(entry[entry.index(after: eqIdx)...])
        applyVorbisTag(key: rawKey, value: rawVal, into: &out, coverPrio: &coverPrio)
      }
      pos = end
    }
  }

  private static func applyVorbisTag(
    key rawKey: String,
    value rawVal: String,
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    switch key {
    case "TITLE":
      if out.title == nil { out.title = cleanText(rawVal) }
    case "ARTIST", "ALBUMARTIST", "ALBUM ARTIST":
      if out.artist == nil { out.artist = cleanText(rawVal) }
    case "ALBUM":
      if out.album == nil { out.album = cleanText(rawVal) }
    case "SYNCEDLYRICS", "LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "LYRIC", "SLT", "LRC":
      considerLyrics(&out, candidate: cleanText(rawVal))
    case "COMMENT", "DESCRIPTION":
      if let text = cleanText(rawVal), looksLikeSyncedLrc(text) {
        considerLyrics(&out, candidate: text)
      }
    case "METADATA_BLOCK_PICTURE":
      if rawVal.utf8.count <= (maxCoverBytes * 4 / 3 + 4096),
        let decoded = Data(base64Encoded: rawVal, options: .ignoreUnknownCharacters)
      {
        parseFLACPicture([UInt8](decoded), into: &out, coverPrio: &coverPrio)
      }
    default:
      break
    }
  }

  private static func parseFLACPicture(
    _ payload: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    guard let picType = readBEU32(payload, 0),
      let mimeLen = readBEU32(payload, 4)
    else { return }
    let mimeStart = 8
    let (mimeEnd, ov1) = mimeStart.addingReportingOverflow(Int(mimeLen))
    guard !ov1, mimeEnd + 4 <= payload.count else { return }
    let mime = String(bytes: payload[mimeStart..<mimeEnd], encoding: .utf8) ?? ""
    guard let descLen = readBEU32(payload, mimeEnd) else { return }
    let (dataLenOff, ov2) = (mimeEnd + 4 + 16).addingReportingOverflow(Int(descLen))
    guard !ov2, let dataLen = readBEU32(payload, dataLenOff) else { return }
    let dataStart = dataLenOff + 4
    let (dataEnd, ov3) = dataStart.addingReportingOverflow(Int(dataLen))
    guard !ov3, dataEnd <= payload.count else { return }
    setCoverIfBetter(
      &out,
      bestPriority: &coverPrio,
      pictureType: UInt8(min(picType, 255)),
      mimeHint: mime,
      bytes: Array(payload[dataStart..<dataEnd])
    )
  }

  // MARK: - 2. ID3v2

  private static func parseID3v2(_ data: [UInt8], into out: inout AudioEmbeddedMetadata) -> Int {
    guard data.count >= 10, data[0] == 0x49, data[1] == 0x44, data[2] == 0x33 else { return 0 }
    let version = data[3]
    guard version >= 2 && version <= 4 else { return 0 }
    let flags = data[5]
    guard let tagSize = readSynchsafeU32(data, 6) else { return 0 }
    let totalSize = 10 + Int(tagSize)
    let hasUnsync = (flags & 0x80) != 0
    let hasExt = (flags & 0x40) != 0

    let availEnd = min(totalSize, data.count)
    var body = Array(data[10..<availEnd])
    if hasUnsync && version <= 3 {
      body = removeUnsync(body)
    }

    var pos = 0
    if hasExt && version >= 3 && body.count >= 4 {
      let extSize: Int
      if version == 4 {
        extSize = Int(readSynchsafeU32(body, 0) ?? 0)
      } else {
        extSize = Int(readBEU32(body, 0) ?? 0) + 4
      }
      if extSize <= body.count { pos = extSize }
    }

    var coverPrio: UInt8 = out.coverData != nil ? 2 : 0

    if version == 2 {
      while pos + 6 <= body.count {
        if body[pos] == 0 { break }
        let id = String(bytes: body[pos..<(pos + 3)], encoding: .isoLatin1) ?? ""
        guard let len = readBEU24(body, pos + 3) else { break }
        let start = pos + 6
        let (end, ov) = start.addingReportingOverflow(Int(len))
        guard !ov, end <= body.count else { break }
        let payload = Array(body[start..<end])
        switch id {
        case "TT2": if out.title == nil { out.title = decodeID3TextFrame(payload) }
        case "TP1", "TP2": if out.artist == nil { out.artist = decodeID3TextFrame(payload) }
        case "TAL": if out.album == nil { out.album = decodeID3TextFrame(payload) }
        case "ULT": considerLyrics(&out, candidate: decodeID3USLT(payload))
        case "PIC":
          if payload.count >= 6 {
            let enc = payload[0]
            let fmt = String(bytes: payload[1..<4], encoding: .isoLatin1) ?? ""
            let picType = payload[4]
            if let (_, rest) = splitID3EncodedString(enc, Array(payload[5...])) {
              setCoverIfBetter(&out, bestPriority: &coverPrio, pictureType: picType, mimeHint: fmt, bytes: rest)
            }
          }
        default: break
        }
        pos = end
      }
      return totalSize
    }

    while pos + 10 <= body.count {
      if body[pos] == 0 { break }
      let idBytes = body[pos..<(pos + 4)]
      guard idBytes.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) }) else {
        break
      }
      let id = String(bytes: idBytes, encoding: .isoLatin1) ?? ""
      let frameSize: Int
      if version == 4 {
        frameSize = Int(readSynchsafeU32(body, pos + 4) ?? readBEU32(body, pos + 4) ?? 0)
      } else {
        frameSize = Int(readBEU32(body, pos + 4) ?? 0)
      }
      if frameSize <= 0 { break }
      let frameFlagsLo = body[pos + 9]
      let start = pos + 10
      let (end, ov) = start.addingReportingOverflow(frameSize)
      guard !ov, end <= body.count else { break }
      var frame = Array(body[start..<end])
      if version == 4 {
        let hasDataLen = (frameFlagsLo & 0x01) != 0
        let frameUnsync = (frameFlagsLo & 0x02) != 0 || hasUnsync
        if frameUnsync { frame = removeUnsync(frame) }
        if hasDataLen && frame.count >= 4 { frame = Array(frame[4...]) }
      }

      switch id {
      case "TIT2": if out.title == nil { out.title = decodeID3TextFrame(frame) }
      case "TPE1", "TPE2": if out.artist == nil { out.artist = decodeID3TextFrame(frame) }
      case "TALB": if out.album == nil { out.album = decodeID3TextFrame(frame) }
      case "USLT": considerLyrics(&out, candidate: decodeID3USLT(frame))
      case "SYLT": considerLyrics(&out, candidate: decodeID3SYLT(frame))
      case "TXXX":
        if frame.count >= 2,
          let (desc, valBytes) = splitID3EncodedString(frame[0], Array(frame[1...]))
        {
          let key = desc.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
          if ["LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "SYNCEDLYRICS", "LYRIC", "LRC"].contains(key) {
            considerLyrics(&out, candidate: cleanText(decodeID3Bytes(frame[0], valBytes)))
          }
        }
      case "APIC":
        if frame.count >= 4, let mimeNul = frame[1...].firstIndex(of: 0) {
          let mime = String(bytes: frame[1..<mimeNul], encoding: .isoLatin1) ?? ""
          let picTypeOff = mimeNul + 1
          if picTypeOff < frame.count {
            let picType = frame[picTypeOff]
            let rest = Array(frame[(picTypeOff + 1)...])
            if let (_, imgData) = splitID3EncodedString(frame[0], rest) {
              setCoverIfBetter(&out, bestPriority: &coverPrio, pictureType: picType, mimeHint: mime, bytes: imgData)
            }
          }
        }
      default:
        break
      }
      pos = end
    }

    return totalSize
  }

  private static func removeUnsync(_ input: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(input.count)
    var i = 0
    while i < input.count {
      out.append(input[i])
      if input[i] == 0xFF, i + 1 < input.count, input[i + 1] == 0x00 {
        i += 2
      } else {
        i += 1
      }
    }
    return out
  }

  private static func decodeID3TextFrame(_ payload: [UInt8]) -> String? {
    guard payload.count >= 2 else { return nil }
    return cleanText(decodeID3Bytes(payload[0], Array(payload[1...])))
  }

  private static func decodeID3USLT(_ payload: [UInt8]) -> String? {
    guard payload.count >= 5 else { return nil }
    let enc = payload[0]
    guard let (_, lyricsBytes) = splitID3EncodedString(enc, Array(payload[4...])) else { return nil }
    return cleanText(decodeID3Bytes(enc, lyricsBytes))
  }

  private static func decodeID3SYLT(_ payload: [UInt8]) -> String? {
    guard payload.count >= 7 else { return nil }
    let enc = payload[0]
    guard payload[4] == 2 else { return nil }  // milliseconds
    guard var cursor = splitID3EncodedString(enc, Array(payload[6...]))?.1 else { return nil }
    var lines: [String] = []
    while !cursor.isEmpty {
      guard let (segText, afterText) = splitID3EncodedString(enc, cursor),
        let tsMs = readBEU32(afterText, 0)
      else { break }
      cursor = Array(afterText[4...])
      let cleaned = segText.replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !cleaned.isEmpty {
        let mins = tsMs / 60_000
        let secs = (tsMs % 60_000) / 1_000
        let cs = (tsMs % 1_000) / 10
        lines.append(String(format: "[%02d:%02d.%02d]%@", mins, secs, cs, cleaned))
      }
    }
    return lines.isEmpty ? nil : lines.joined(separator: "\n")
  }

  private static func splitID3EncodedString(_ enc: UInt8, _ input: [UInt8]) -> (String, [UInt8])? {
    if enc == 1 || enc == 2 {
      var i = 0
      while i + 1 < input.count {
        if input[i] == 0 && input[i + 1] == 0 {
          return (decodeID3Bytes(enc, Array(input[..<i])), Array(input[(i + 2)...]))
        }
        i += 2
      }
      return nil
    } else {
      guard let nul = input.firstIndex(of: 0) else { return nil }
      return (decodeID3Bytes(enc, Array(input[..<nul])), Array(input[(nul + 1)...]))
    }
  }

  private static func decodeID3Bytes(_ enc: UInt8, _ raw: [UInt8]) -> String {
    var trimmed = raw
    if enc == 1 || enc == 2 {
      while trimmed.count >= 2 && trimmed[trimmed.count - 2] == 0 && trimmed[trimmed.count - 1] == 0 {
        trimmed.removeLast(2)
      }
    } else {
      while let last = trimmed.last, last == 0 { trimmed.removeLast() }
    }
    switch enc {
    case 3:
      return String(decoding: trimmed, as: UTF8.self)
    case 1:
      if trimmed.count >= 2 && trimmed[0] == 0xFF && trimmed[1] == 0xFE {
        return String(bytes: trimmed[2...], encoding: .utf16LittleEndian) ?? ""
      } else if trimmed.count >= 2 && trimmed[0] == 0xFE && trimmed[1] == 0xFF {
        return String(bytes: trimmed[2...], encoding: .utf16BigEndian) ?? ""
      }
      return String(bytes: trimmed, encoding: .utf16LittleEndian) ?? ""
    case 2:
      return String(bytes: trimmed, encoding: .utf16BigEndian) ?? ""
    default:
      if let utf8 = String(bytes: trimmed, encoding: .utf8) { return utf8 }
      return String(bytes: trimmed, encoding: .isoLatin1) ?? ""
    }
  }

  // MARK: - 3. MP4 / M4A

  private static func isMP4Header(_ head: [UInt8]) -> Bool {
    head.count >= 12 && head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70
  }

  private static func readMP4BoxHeader(_ buf: [UInt8], _ pos: Int) -> ([UInt8], Int, UInt64)? {
    guard pos + 8 <= buf.count, let size32 = readBEU32(buf, pos) else { return nil }
    let boxType = Array(buf[(pos + 4)..<(pos + 8)])
    if size32 == 1 {
      guard let size64 = readBEU64(buf, pos + 8), size64 >= 16 else { return nil }
      return (boxType, 16, size64)
    } else if size32 == 0 {
      return (boxType, 8, UInt64(buf.count - pos))
    } else if size32 < 8 {
      return nil
    } else {
      return (boxType, 8, UInt64(size32))
    }
  }

  private static func parseMP4(head: [UInt8], tail: [UInt8]?, into out: inout AudioEmbeddedMetadata) {
    var coverPrio: UInt8 = out.coverData != nil ? 2 : 0
    var foundMoov = false
    var sawMdat = false
    var pos = 0

    while pos + 8 <= head.count {
      guard let (boxType, hdr, total) = readMP4BoxHeader(head, pos) else { break }
      let boxEnd = UInt64(pos) + total
      if boxType == [0x6D, 0x6F, 0x6F, 0x76] {  // "moov"
        foundMoov = true
        let sliceEnd = Int(min(boxEnd, UInt64(head.count)))
        parseMP4Moov(Array(head[(pos + hdr)..<sliceEnd]), into: &out, coverPrio: &coverPrio)
        if boxEnd > UInt64(head.count), !out.hasCoverOrLyrics, boxEnd <= maxRecommendedRangeBytes {
          out.neededHeadBytes = boxEnd
        }
        break
      } else if boxType == [0x6D, 0x64, 0x61, 0x74] {  // "mdat"
        sawMdat = true
        if boxEnd > UInt64(head.count) { break }
      }
      if total == 0 || boxEnd > UInt64(head.count) { break }
      pos = Int(boxEnd)
    }

    if !foundMoov {
      if let tailBytes = tail {
        scanMP4TailForIlst(tailBytes, into: &out, coverPrio: &coverPrio)
      } else if sawMdat {
        out.neededTailBytes = 512 * 1024
      }
    }
  }

  private static func parseMP4Moov(
    _ moov: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    var pos = 0
    while pos + 8 <= moov.count {
      guard let (boxType, hdr, total) = readMP4BoxHeader(moov, pos) else { break }
      let end = Int(min(UInt64(pos) + total, UInt64(moov.count)))
      if boxType == [0x75, 0x64, 0x74, 0x61] {  // "udta"
        parseMP4Udta(Array(moov[(pos + hdr)..<end]), into: &out, coverPrio: &coverPrio)
      } else if boxType == [0x6D, 0x65, 0x74, 0x61] {  // "meta"
        parseMP4Meta(Array(moov[(pos + hdr)..<end]), into: &out, coverPrio: &coverPrio)
      }
      if total == 0 || end <= pos { break }
      pos = end
    }
  }

  private static func parseMP4Udta(
    _ udta: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    var pos = 0
    while pos + 8 <= udta.count {
      guard let (boxType, hdr, total) = readMP4BoxHeader(udta, pos) else { break }
      let end = Int(min(UInt64(pos) + total, UInt64(udta.count)))
      if boxType == [0x6D, 0x65, 0x74, 0x61] {  // "meta"
        parseMP4Meta(Array(udta[(pos + hdr)..<end]), into: &out, coverPrio: &coverPrio)
      }
      if total == 0 || end <= pos { break }
      pos = end
    }
  }

  private static func parseMP4Meta(
    _ meta: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    let startOff: Int
    if meta.count >= 8
      && (Array(meta[4..<8]) == [0x68, 0x64, 0x6C, 0x72]
        || Array(meta[4..<8]) == [0x69, 0x6C, 0x73, 0x74])
    {
      startOff = 0
    } else {
      startOff = 4
    }
    var pos = startOff
    while pos + 8 <= meta.count {
      guard let (boxType, hdr, total) = readMP4BoxHeader(meta, pos) else { break }
      let end = Int(min(UInt64(pos) + total, UInt64(meta.count)))
      if boxType == [0x69, 0x6C, 0x73, 0x74] {  // "ilst"
        parseMP4Ilst(Array(meta[(pos + hdr)..<end]), into: &out, coverPrio: &coverPrio)
      }
      if total == 0 || end <= pos { break }
      pos = end
    }
  }

  private static func scanMP4TailForIlst(
    _ tail: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    guard tail.count >= 8 else { return }
    for i in 4...(tail.count - 4) {
      if tail[i] == 0x69 && tail[i + 1] == 0x6C && tail[i + 2] == 0x73 && tail[i + 3] == 0x74,
        let size = readBEU32(tail, i - 4),
        size >= 8,
        (i - 4) + Int(size) <= tail.count
      {
        parseMP4Ilst(Array(tail[(i + 4)..<(i - 4 + Int(size))]), into: &out, coverPrio: &coverPrio)
        if out.hasCoverOrLyrics { return }
      }
    }
  }

  private static func parseMP4Ilst(
    _ ilst: [UInt8],
    into out: inout AudioEmbeddedMetadata,
    coverPrio: inout UInt8
  ) {
    var pos = 0
    while pos + 8 <= ilst.count {
      guard let (atomType, hdr, total) = readMP4BoxHeader(ilst, pos) else { break }
      let end = Int(min(UInt64(pos) + total, UInt64(ilst.count)))
      let children = Array(ilst[(pos + hdr)..<end])
      var cpos = 0
      while cpos + 16 <= children.count {
        guard let (ctype, chdr, ctotal) = readMP4BoxHeader(children, cpos) else { break }
        let cend = Int(min(UInt64(cpos) + ctotal, UInt64(children.count)))
        if ctype == [0x64, 0x61, 0x74, 0x61], cpos + chdr + 8 <= cend {  // "data"
          let typeInd = readBEU32(children, cpos + chdr) ?? 0
          let valBytes = Array(children[(cpos + chdr + 8)..<cend])
          if atomType == [0xA9, 0x6E, 0x61, 0x6D] {  // ©nam
            if out.title == nil { out.title = cleanText(String(decoding: valBytes, as: UTF8.self)) }
          } else if atomType == [0xA9, 0x41, 0x52, 0x54] || atomType == [0x61, 0x41, 0x52, 0x54] {
            if out.artist == nil { out.artist = cleanText(String(decoding: valBytes, as: UTF8.self)) }
          } else if atomType == [0xA9, 0x61, 0x6C, 0x62] {  // ©alb
            if out.album == nil { out.album = cleanText(String(decoding: valBytes, as: UTF8.self)) }
          } else if atomType == [0xA9, 0x6C, 0x79, 0x72] {  // ©lyr
            considerLyrics(&out, candidate: cleanText(String(decoding: valBytes, as: UTF8.self)))
          } else if atomType == [0x63, 0x6F, 0x76, 0x72] {  // covr
            let mimeHint = typeInd == 13 ? "image/jpeg" : (typeInd == 14 ? "image/png" : (typeInd == 27 ? "image/bmp" : ""))
            setCoverIfBetter(&out, bestPriority: &coverPrio, pictureType: 3, mimeHint: mimeHint, bytes: valBytes)
          }
        }
        if ctotal == 0 || cend <= cpos { break }
        cpos = cend
      }
      if total == 0 || end <= pos { break }
      pos = end
    }
  }

  // MARK: - 4. Ogg Vorbis / Opus

  private static func parseOgg(_ data: [UInt8], into out: inout AudioEmbeddedMetadata) {
    var pos = 0
    var packet: [UInt8] = []
    var packetsParsed = 0
    var coverPrio: UInt8 = out.coverData != nil ? 2 : 0

    while pos + 27 <= data.count && packetsParsed < 4 {
      guard data[pos] == 0x4F, data[pos + 1] == 0x67, data[pos + 2] == 0x67, data[pos + 3] == 0x53 else {
        break
      }
      let segCount = Int(data[pos + 26])
      let segStart = pos + 27
      let segEnd = segStart + segCount
      guard segEnd <= data.count else { break }
      var bodyPos = segEnd

      for segIdx in segStart..<segEnd {
        let segLen = Int(data[segIdx])
        let nextPos = bodyPos + segLen
        if nextPos > data.count {
          let isCommentPkt =
            (packet.count >= 7 && Array(packet[0..<7]) == [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73])
            || (packet.count >= 8 && Array(packet[0..<8]) == [0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73])
          if isCommentPkt {
            let desired = min(UInt64(data.count) + 512 * 1024, maxRecommendedRangeBytes)
            if desired > UInt64(data.count) { out.neededHeadBytes = desired }
          }
          return
        }
        if packet.count + segLen <= maxCoverBytes * 2 {
          packet.append(contentsOf: data[bodyPos..<nextPos])
        }
        bodyPos = nextPos
        if segLen < 255 {
          packetsParsed += 1
          if packet.count >= 7 && Array(packet[0..<7]) == [0x03, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73] {
            parseVorbisComment(Array(packet[7...]), into: &out, coverPrio: &coverPrio)
          } else if packet.count >= 8 && Array(packet[0..<8]) == [0x4F, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73] {
            parseVorbisComment(Array(packet[8...]), into: &out, coverPrio: &coverPrio)
          }
          packet.removeAll(keepingCapacity: true)
          if packetsParsed >= 2 && out.hasCoverOrLyrics { return }
        }
      }
      pos = bodyPos
    }
  }
}
