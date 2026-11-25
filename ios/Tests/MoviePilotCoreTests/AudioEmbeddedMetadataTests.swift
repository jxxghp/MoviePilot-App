import Foundation
import MoviePilotCore
import XCTest

final class AudioEmbeddedMetadataTests: XCTestCase {
  private let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0xFF, 0xD9])
  private let fakePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x00])

  private func buildFLACBlock(type: UInt8, isLast: Bool, payload: Data) -> Data {
    var out = Data()
    out.append((isLast ? 0x80 : 0x00) | (type & 0x7F))
    let len = UInt32(payload.count)
    out.append(UInt8((len >> 16) & 0xFF))
    out.append(UInt8((len >> 8) & 0xFF))
    out.append(UInt8(len & 0xFF))
    out.append(payload)
    return out
  }

  private func buildVorbisComment(_ tags: [(String, String)]) -> Data {
    let vendor = Data("reference libFLAC".utf8)
    var buf = Data()
    var vLen = UInt32(vendor.count).littleEndian
    buf.append(Data(bytes: &vLen, count: 4))
    buf.append(vendor)
    var count = UInt32(tags.count).littleEndian
    buf.append(Data(bytes: &count, count: 4))
    for (k, v) in tags {
      let entry = Data("\(k)=\(v)".utf8)
      var eLen = UInt32(entry.count).littleEndian
      buf.append(Data(bytes: &eLen, count: 4))
      buf.append(entry)
    }
    return buf
  }

  private func buildFLACPicture(type: UInt32, mime: String, image: Data) -> Data {
    var buf = Data()
    var t = type.bigEndian
    buf.append(Data(bytes: &t, count: 4))
    let mimeBytes = Data(mime.utf8)
    var mLen = UInt32(mimeBytes.count).bigEndian
    buf.append(Data(bytes: &mLen, count: 4))
    buf.append(mimeBytes)
    var zero: UInt32 = 0
    buf.append(Data(bytes: &zero, count: 4))
    buf.append(Data(repeating: 0, count: 16))
    var iLen = UInt32(image.count).bigEndian
    buf.append(Data(bytes: &iLen, count: 4))
    buf.append(image)
    return buf
  }

  func testParsesFLACVorbisLyricsAndCover() {
    let vc = buildVorbisComment([
      ("TITLE", "evergreen"),
      ("ARTIST", "鹿乃"),
      ("ALBUM", "evergreen"),
      ("LYRICS", "[00:01.20]第一句歌词\n[00:05.50]第二句歌词"),
    ])
    let pic = buildFLACPicture(type: 3, mime: "image/jpeg", image: fakeJPEG)

    var flac = Data("fLaC".utf8)
    flac.append(buildFLACBlock(type: 0, isLast: false, payload: Data(repeating: 0, count: 34)))
    flac.append(buildFLACBlock(type: 4, isLast: false, payload: vc))
    flac.append(buildFLACBlock(type: 6, isLast: true, payload: pic))

    let parsed = AudioEmbeddedMetadataParser.parse(head: flac)
    XCTAssertEqual(parsed.title, "evergreen")
    XCTAssertEqual(parsed.artist, "鹿乃")
    XCTAssertEqual(parsed.album, "evergreen")
    XCTAssertEqual(parsed.lyrics, "[00:01.20]第一句歌词\n[00:05.50]第二句歌词")
    XCTAssertEqual(parsed.coverMime, "image/jpeg")
    XCTAssertEqual(parsed.coverData, fakeJPEG)
    XCTAssertNil(parsed.neededHeadBytes)
  }

  func testParsesID3v23SYLTAndAPIC() {
    func frame(_ id: String, _ payload: Data) -> Data {
      var out = Data(id.utf8)
      var len = UInt32(payload.count).bigEndian
      out.append(Data(bytes: &len, count: 4))
      out.append(contentsOf: [0, 0])
      out.append(payload)
      return out
    }
    var body = Data()
    var tit2 = Data([3])
    tit2.append(Data("夜驱".utf8))
    body.append(frame("TIT2", tit2))

    var sylt = Data([3, 0x7A, 0x68, 0x6F, 2, 1, 0])
    sylt.append(Data("第一行".utf8))
    sylt.append(0)
    var ts1 = UInt32(12_340).bigEndian
    sylt.append(Data(bytes: &ts1, count: 4))
    body.append(frame("SYLT", sylt))

    var apic = Data([0])
    apic.append(Data("image/png".utf8))
    apic.append(0)
    apic.append(3)
    apic.append(0)
    apic.append(fakePNG)
    body.append(frame("APIC", apic))

    var mp3 = Data("ID3".utf8)
    mp3.append(contentsOf: [3, 0, 0])
    let sz = UInt32(body.count)
    mp3.append(contentsOf: [
      UInt8((sz >> 21) & 0x7F), UInt8((sz >> 14) & 0x7F),
      UInt8((sz >> 7) & 0x7F), UInt8(sz & 0x7F),
    ])
    mp3.append(body)

    let parsed = AudioEmbeddedMetadataParser.parse(head: mp3)
    XCTAssertEqual(parsed.title, "夜驱")
    XCTAssertEqual(parsed.lyrics, "[00:12.34]第一行")
    XCTAssertEqual(parsed.coverMime, "image/png")
    XCTAssertEqual(parsed.coverData, fakePNG)
  }

  func testParsesMP4TailMoovLyricsAndCover() {
    func box(_ tag: [UInt8], _ payload: Data) -> Data {
      var len = UInt32(8 + payload.count).bigEndian
      var out = Data(bytes: &len, count: 4)
      out.append(contentsOf: tag)
      out.append(payload)
      return out
    }
    var lyrPayload = Data()
    var t1 = UInt32(1).bigEndian
    var z: UInt32 = 0
    lyrPayload.append(Data(bytes: &t1, count: 4))
    lyrPayload.append(Data(bytes: &z, count: 4))
    lyrPayload.append(Data("[00:10.00]M4A 歌词".utf8))
    let lyrAtom = box([0xA9, 0x6C, 0x79, 0x72], box(Array("data".utf8), lyrPayload))

    var covrPayload = Data()
    var t13 = UInt32(13).bigEndian
    covrPayload.append(Data(bytes: &t13, count: 4))
    covrPayload.append(Data(bytes: &z, count: 4))
    covrPayload.append(fakeJPEG)
    let covrAtom = box(Array("covr".utf8), box(Array("data".utf8), covrPayload))

    var ilstPayload = Data()
    ilstPayload.append(lyrAtom)
    ilstPayload.append(covrAtom)
    let ilst = box(Array("ilst".utf8), ilstPayload)
    var metaPayload = Data(repeating: 0, count: 4)
    metaPayload.append(ilst)
    let moov = box(Array("moov".utf8), box(Array("udta".utf8), box(Array("meta".utf8), metaPayload)))
    let ftyp = box(Array("ftyp".utf8), Data("M4A \0\0\0\0M4A mp42".utf8))

    var nonFast = ftyp
    var mdatSize = UInt32(10_000_000).bigEndian
    nonFast.append(Data(bytes: &mdatSize, count: 4))
    nonFast.append(Data("mdat".utf8))
    nonFast.append(Data(repeating: 0, count: 64))

    let first = AudioEmbeddedMetadataParser.parse(head: nonFast)
    XCTAssertNotNil(first.neededTailBytes)

    let second = AudioEmbeddedMetadataParser.parse(head: nonFast, tail: moov)
    XCTAssertEqual(second.lyrics, "[00:10.00]M4A 歌词")
    XCTAssertEqual(second.coverData, fakeJPEG)
  }
}
