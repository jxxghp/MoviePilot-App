import Foundation
import Testing

@testable import MoviePilotCore

/// 检查签名元数据解析；合成容器不证明系统授权，实际容器和 Keychain 另验。
struct WidgetAppGroupTests {
  private static let base = WidgetAppGroup.baseIdentifier

  /// 原组和 SideStore 团队后缀精确匹配，不选择同前缀的其它应用组。
  @Test func resolvesOriginalAndResignedGroups() throws {
    for expected in [Self.base, Self.base + ".A1B2C3D4E5"] {
      let binary = try Self.binary(groups: ["group.other.app", expected])
      #expect(try WidgetAppGroup.resolve(in: binary) == expected)
      var prefixed = Data([0, 1, 2, 3])
      prefixed.append(binary)
      #expect(try WidgetAppGroup.resolve(in: prefixed.dropFirst(4)) == expected)
    }
    for rejected in [
      Self.base + "evil", Self.base + ".abcdef1234", Self.base + ".ABC123",
      Self.base + ".ABCDEFGHIJK",
    ] {
      #expect(try WidgetAppGroup.resolve(in: Self.binary(groups: [rejected])) == nil)
    }
  }

  /// 多个候选组不能靠数组顺序决定；无权限或 DER-only 保持安全不可用。
  @Test func rejectsAmbiguityAndSupportsMissingGroups() throws {
    #expect(throws: WidgetDataError.ambiguousAppGroup) {
      try WidgetAppGroup.resolve(in: Self.binary(groups: [Self.base, Self.base + ".A1B2C3D4E5"]))
    }
    #expect(throws: WidgetDataError.ambiguousAppGroup) {
      try WidgetAppGroup.resolve(in: Self.binary(groups: [Self.base, Self.base]))
    }
    #expect(try WidgetAppGroup.resolve(in: Self.binary(groups: [])) == nil)
    #expect(try WidgetAppGroup.resolve(in: Self.executable(signature: nil)) == nil)
    let derOnly = Self.superBlob([(7, Self.blob(magic: 0xFADE_7172, payload: Data([1, 2, 3])))])
    #expect(try WidgetAppGroup.resolve(in: Self.executable(signature: derOnly)) == nil)
  }

  /// plist 必须为 XML 字典，错误类型和无限组列表不能绕过元数据边界。
  @Test func validatesEntitlementPayload() throws {
    let badXML = Data("<plist><dict>broken".utf8)
    let binaryPlist = try PropertyListSerialization.data(
      fromPropertyList: ["com.apple.security.application-groups": [Self.base]],
      format: .binary, options: 0)
    let wrongType = try Self.xml(["com.apple.security.application-groups": Self.base])
    let excessive = try Self.xml([
      "com.apple.security.application-groups": Array(repeating: "group.other", count: 17)
    ])
    for payload in [badXML, binaryPlist, wrongType, excessive, try Self.xml(["not-a-dictionary"])] {
      #expect(throws: WidgetDataError.invalidSignature) {
        try WidgetAppGroup.resolve(
          in: Self.executable(
            signature: Self.superBlob([
              (5, Self.blob(magic: 0xFADE_7171, payload: payload))
            ])))
      }
    }
    let noGroups = Self.superBlob([
      (5, Self.blob(magic: 0xFADE_7171, payload: try Self.xml([:] as [String: String])))
    ])
    #expect(try WidgetAppGroup.resolve(in: Self.executable(signature: noGroups)) == nil)
  }

  /// 每一种截断都必须返回受控错误，不能越界读取字节或崩溃。
  @Test func rejectsEveryTruncationAndMalformedHeader() throws {
    let valid = try Self.binary(groups: [Self.base])
    for length in 0..<valid.count {
      #expect(throws: WidgetDataError.invalidSignature) {
        try WidgetAppGroup.resolve(in: Data(valid.prefix(length)))
      }
    }
    let invalidWords: [(Int, UInt32)] = [
      (0, 0xCAFE_BABE), (4, 7), (12, 6), (16, 4097), (20, UInt32.max),
      (36, 0), (36, 7), (36, 24), (40, 0), (40, UInt32.max),
      (44, 11), (44, UInt32.max),
    ]
    for (offset, value) in invalidWords {
      var copy = valid
      Self.put(value, in: &copy, at: offset)
      #expect(throws: WidgetDataError.invalidSignature) { try WidgetAppGroup.resolve(in: copy) }
    }
  }

  /// 签名索引不能重叠、重复或越界，错误 slot magic 不能伪装 XML。
  @Test func rejectsCorruptSignatureIndexes() throws {
    let xml = try Self.xml(["com.apple.security.application-groups": [Self.base]])
    let signature = Self.superBlob([(5, Self.blob(magic: 0xFADE_7171, payload: xml))])
    let invalidWords: [(Int, UInt32)] = [
      (0, 0), (4, 11), (4, UInt32.max), (8, 33), (16, 0), (16, UInt32.max),
      (20, 0xFADE_7172), (24, 7), (24, UInt32.max),
    ]
    for (offset, value) in invalidWords {
      var copy = signature
      Self.put(value, in: &copy, at: offset, bigEndian: true)
      #expect(throws: WidgetDataError.invalidSignature) {
        try WidgetAppGroup.resolve(in: Self.executable(signature: copy))
      }
    }
    let member = Self.blob(magic: 0xFADE_7171, payload: xml)
    let duplicate = Self.superBlob([(5, member), (5, member)])
    #expect(throws: WidgetDataError.invalidSignature) {
      try WidgetAppGroup.resolve(in: Self.executable(signature: duplicate))
    }
    var overlap = Self.superBlob([(5, member), (7, member)])
    Self.put(28, in: &overlap, at: 24, bigEndian: true)
    #expect(throws: WidgetDataError.invalidSignature) {
      try WidgetAppGroup.resolve(in: Self.executable(signature: overlap))
    }
    var duplicateCommand = Self.executable(signature: signature)
    duplicateCommand.insert(contentsOf: duplicateCommand[32..<48], at: 48)
    Self.put(2, in: &duplicateCommand, at: 16)
    Self.put(32, in: &duplicateCommand, at: 20)
    Self.put(64, in: &duplicateCommand, at: 40)
    Self.put(64, in: &duplicateCommand, at: 56)
    #expect(throws: WidgetDataError.invalidSignature) {
      try WidgetAppGroup.resolve(in: duplicateCommand)
    }
  }

  /// 将组列表装入 Apple 公开格式的薄 Mach-O 签名夹具。
  private static func binary(groups: [String]) throws -> Data {
    let entitlements = try xml(["com.apple.security.application-groups": groups])
    return executable(signature: superBlob([(5, blob(magic: 0xFADE_7171, payload: entitlements))]))
  }

  /// 生成 XML，避免测试依赖特定 plist 的空白或键排列。
  private static func xml(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
  }

  /// 构造最小 arm64 MH_EXECUTE；这只是解析夹具，不声称可运行或有授权。
  private static func executable(signature: Data?) -> Data {
    var result = Data(repeating: 0, count: signature == nil ? 32 : 48)
    put(0xFEED_FACF, in: &result, at: 0)
    put(0x0100_000C, in: &result, at: 4)
    put(2, in: &result, at: 12)
    if let signature {
      put(1, in: &result, at: 16)
      put(16, in: &result, at: 20)
      put(0x1D, in: &result, at: 32)
      put(16, in: &result, at: 36)
      put(48, in: &result, at: 40)
      put(UInt32(signature.count), in: &result, at: 44)
      result.append(signature)
    }
    return result
  }

  /// 生成有明确长度和索引的嵌入签名，不包含身份或用户签名材料。
  private static func superBlob(_ entries: [(UInt32, Data)]) -> Data {
    var result = Data(repeating: 0, count: 12 + entries.count * 8)
    put(0xFADE_0CC0, in: &result, at: 0, bigEndian: true)
    put(UInt32(entries.count), in: &result, at: 8, bigEndian: true)
    for (index, entry) in entries.enumerated() {
      put(entry.0, in: &result, at: 12 + index * 8, bigEndian: true)
      put(UInt32(result.count), in: &result, at: 16 + index * 8, bigEndian: true)
      result.append(entry.1)
    }
    put(UInt32(result.count), in: &result, at: 4, bigEndian: true)
    return result
  }

  /// 生成单个受限签名成员，允许调用方选择 XML 或 DER slot 的 magic。
  private static func blob(magic: UInt32, payload: Data) -> Data {
    var result = Data(repeating: 0, count: 8)
    put(magic, in: &result, at: 0, bigEndian: true)
    put(UInt32(8 + payload.count), in: &result, at: 4, bigEndian: true)
    result.append(payload)
    return result
  }

  /// 显式端序写整数，便于对真实二进制边界作单字段破坏测试。
  private static func put(
    _ value: UInt32, in data: inout Data, at offset: Int, bigEndian: Bool = false
  ) {
    for index in 0..<4 {
      let shift = (bigEndian ? 3 - index : index) * 8
      data[offset + index] = UInt8(truncatingIfNeeded: value >> shift)
    }
  }
}
