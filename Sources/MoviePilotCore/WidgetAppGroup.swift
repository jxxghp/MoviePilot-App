import Foundation

/// 只读自身 Mach-O 的实际 XML 共享组；不证明权限，也不访问任意应用容器。
public enum WidgetAppGroup {
  public static let baseIdentifier = "group.org.moviepilot.widgets"
  private static let maximumExecutableBytes = 256 * 1024 * 1024
  private static let maximumSignatureBytes = 4 * 1024 * 1024

  /// 解析薄型 64 位小端可执行文件，兼容 iPhone/模拟器及 SideStore 的团队后缀。
  public static func resolve(in executable: Data) throws -> String? {
    guard executable.count <= maximumExecutableBytes else { throw WidgetDataError.oversizedData }
    guard executable.count >= 32,
      try word(executable, at: 0) == 0xFEED_FACF,
      [0x0100_000C, 0x0100_0007].contains(try word(executable, at: 4)),
      try word(executable, at: 12) == 2
    else { throw WidgetDataError.invalidSignature }
    let commandCount = Int(try word(executable, at: 16))
    let commandBytes = Int(try word(executable, at: 20))
    guard commandCount <= 4096, commandBytes <= 1024 * 1024,
      within(offset: 32, length: commandBytes, limit: executable.count)
    else { throw WidgetDataError.invalidSignature }
    let commandEnd = 32 + commandBytes
    var cursor = 32
    var signature: Range<Int>?
    for _ in 0..<commandCount {
      guard within(offset: cursor, length: 8, limit: commandEnd) else {
        throw WidgetDataError.invalidSignature
      }
      let command = try word(executable, at: cursor)
      let size = Int(try word(executable, at: cursor + 4))
      guard size >= 8, size.isMultiple(of: 8),
        within(offset: cursor, length: size, limit: commandEnd)
      else { throw WidgetDataError.invalidSignature }
      if command == 0x1D {  // Apple LC_CODE_SIGNATURE / linkedit_data_command。
        guard signature == nil, size == 16 else { throw WidgetDataError.invalidSignature }
        let offset = Int(try word(executable, at: cursor + 8))
        let length = Int(try word(executable, at: cursor + 12))
        guard offset >= commandEnd, length >= 12, length <= maximumSignatureBytes,
          within(offset: offset, length: length, limit: executable.count)
        else { throw WidgetDataError.invalidSignature }
        signature = offset..<(offset + length)
      }
      cursor += size
    }
    guard cursor == commandEnd else { throw WidgetDataError.invalidSignature }
    guard let signature else { return nil }
    let start = executable.startIndex
    return try group(
      in: Data(executable[(start + signature.lowerBound)..<(start + signature.upperBound)]))
  }

  /// 核对 SuperBlob 索引和所有成员范围，不能用重叠或重复 slot 伪造 XML。
  private static func group(in signature: Data) throws -> String? {
    guard try word(signature, at: 0, bigEndian: true) == 0xFADE_0CC0 else {
      throw WidgetDataError.invalidSignature
    }
    let length = Int(try word(signature, at: 4, bigEndian: true))
    let count = Int(try word(signature, at: 8, bigEndian: true))
    guard count <= 32, length <= signature.count, 12 + count * 8 <= length else {
      throw WidgetDataError.invalidSignature
    }
    let indexEnd = 12 + count * 8
    var slots = Set<UInt32>()
    var ranges: [Range<Int>] = []
    var entitlements: Data?
    for index in 0..<count {
      let slot = try word(signature, at: 12 + index * 8, bigEndian: true)
      let offset = Int(try word(signature, at: 16 + index * 8, bigEndian: true))
      guard slots.insert(slot).inserted, offset >= indexEnd,
        within(offset: offset, length: 8, limit: length)
      else { throw WidgetDataError.invalidSignature }
      let size = Int(try word(signature, at: offset + 4, bigEndian: true))
      guard size >= 8, within(offset: offset, length: size, limit: length) else {
        throw WidgetDataError.invalidSignature
      }
      let range = offset..<(offset + size)
      guard !ranges.contains(where: { $0.overlaps(range) }) else {
        throw WidgetDataError.invalidSignature
      }
      ranges.append(range)
      if slot == 5 {  // Apple CSSLOT_ENTITLEMENTS，DER-only 签名不作猜测。
        guard size <= 64 * 1024,
          try word(signature, at: offset, bigEndian: true) == 0xFADE_7171
        else { throw WidgetDataError.invalidSignature }
        let start = signature.startIndex
        entitlements = Data(signature[(start + offset + 8)..<(start + offset + size)])
      }
    }
    guard let entitlements else { return nil }
    return try identifier(in: entitlements)
  }

  /// 精确匹配本产品组或 10 位大写团队后缀，绝不任选其它组或模糊前缀。
  private static func identifier(in entitlements: Data) throws -> String? {
    var format = PropertyListSerialization.PropertyListFormat.xml
    let value: Any
    do {
      value = try PropertyListSerialization.propertyList(
        from: entitlements, options: [], format: &format)
    } catch {
      throw WidgetDataError.invalidSignature
    }
    guard format == .xml, let properties = value as? [String: Any] else {
      throw WidgetDataError.invalidSignature
    }
    guard let raw = properties["com.apple.security.application-groups"] else { return nil }
    guard let groups = raw as? [String], groups.count <= 16,
      groups.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 })
    else { throw WidgetDataError.invalidSignature }
    let matches = groups.filter(acceptsIdentifier)
    guard matches.count <= 1 else { throw WidgetDataError.ambiguousAppGroup }
    return matches.first
  }

  /// 签名解析与 Keychain 使用相同组名规则，不接受其它产品或任意调用方分组。
  static func acceptsIdentifier(_ group: String) -> Bool {
    if group == baseIdentifier { return true }
    guard group.hasPrefix(baseIdentifier + ".") else { return false }
    let suffix = group.dropFirst(baseIdentifier.count + 1).utf8
    return suffix.count == 10
      && suffix.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) })
  }

  /// 使用相减后的上界判断，恶意长度不会触发整数相加溢出。
  private static func within(offset: Int, length: Int, limit: Int) -> Bool {
    offset >= 0 && length >= 0 && offset <= limit && length <= limit - offset
  }

  /// 从受检范围逐字节读取整数，不依赖 Data 地址对齐或私有签名 API。
  private static func word(_ data: Data, at offset: Int, bigEndian: Bool = false) throws -> UInt32 {
    guard within(offset: offset, length: 4, limit: data.count) else {
      throw WidgetDataError.invalidSignature
    }
    var result: UInt32 = 0
    for index in 0..<4 {
      let shift = (bigEndian ? 3 - index : index) * 8
      result |= UInt32(data[data.startIndex + offset + index]) << shift
    }
    return result
  }
}
