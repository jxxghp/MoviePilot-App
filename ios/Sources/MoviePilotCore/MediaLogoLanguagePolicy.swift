import Foundation

/// 媒体透明 Logo 语言准入判定结果：Logo 语言匹配当前用户媒体语言设置时才采用，否则回退海报级大字标题。
public enum NativeMediaLogoLanguageDecision: Equatable, Sendable {
  /// 后端返回的 `logo_language` 与用户当前媒体语言设置一致，可直接显示 Logo。
  case confirmedMatch
  /// 后端返回的 `logo_language` 与用户当前媒体语言设置不一致，直接回退文字标题。
  case confirmedMismatch
  /// 后端未返回 `logo_language`（旧版服务端或未标注语言），需在客户端对图片进行本地语种识别验证。
  case needsImageVerification
}

public enum NativeMediaLogoLanguagePolicy {
  /// 将 BCP-47 / ISO-639 语言代码归一化为小写主语言码（如 `zh-CN`/`zh_TW`/`cn` -> `zh`，`en-US` -> `en`）。
  public static func baseLanguageCode(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    let normalized = trimmed.lowercased().replacingOccurrences(of: "_", with: "-")
    let primary = normalized.split(separator: "-").first.map(String.init) ?? normalized
    switch primary {
    case "zh", "cn", "zho", "chi":
      return "zh"
    case "en", "eng":
      return "en"
    case "ja", "jp", "jpn":
      return "ja"
    case "ko", "kr", "kor":
      return "ko"
    case "ru", "rus":
      return "ru"
    case "fr", "fre", "fra":
      return "fr"
    case "de", "ger", "deu":
      return "de"
    case "es", "spa":
      return "es"
    case "it", "ita":
      return "it"
    case "pt", "por":
      return "pt"
    default:
      return primary.isEmpty ? nil : primary
    }
  }

  /// 判断两种语言代码是否同属当前用户媒体语言语族。
  public static func matches(logoLanguage: String?, preferredMediaLanguage: String?) -> Bool {
    guard let logoBase = baseLanguageCode(logoLanguage),
      let preferredBase = baseLanguageCode(preferredMediaLanguage)
    else { return false }
    return logoBase == preferredBase
  }

  /// 基于后端返回的 `logo_language` 与当前用户媒体语言设置做出初步准入判定。
  public static func metadataDecision(
    logoLanguage: String?,
    preferredMediaLanguage: String?
  ) -> NativeMediaLogoLanguageDecision {
    guard let logoBase = baseLanguageCode(logoLanguage) else {
      return .needsImageVerification
    }
    guard let preferredBase = baseLanguageCode(preferredMediaLanguage) else {
      return .needsImageVerification
    }
    return logoBase == preferredBase ? .confirmedMatch : .confirmedMismatch
  }

  /// 基于本地 OCR 识别出的文字脚本与作品原始语言，判定未标注语言的透明 Logo 是否适配用户当前媒体语言设置。
  public static func evaluateRecognizedText(
    _ recognizedText: String,
    preferredMediaLanguage: String?,
    originalLanguage: String?
  ) -> Bool {
    guard let targetLang = baseLanguageCode(preferredMediaLanguage) else {
      return true
    }

    var hanCount = 0
    var kanaCount = 0
    var hangulCount = 0
    var latinCount = 0
    var cyrillicCount = 0

    for scalar in recognizedText.unicodeScalars {
      let value = scalar.value
      if (0x4E00...0x9FFF).contains(value)
        || (0x3400...0x4DBF).contains(value)
        || (0xF900...0xFAFF).contains(value)
        || (0x20000...0x2FA1F).contains(value)
      {
        hanCount += 1
      } else if (0x3040...0x309F).contains(value) || (0x30A0...0x30FF).contains(value) {
        kanaCount += 1
      } else if (0xAC00...0xD7AF).contains(value)
        || (0x1100...0x11FF).contains(value)
        || (0x3130...0x318F).contains(value)
      {
        hangulCount += 1
      } else if (0x0041...0x005A).contains(value)
        || (0x0061...0x007A).contains(value)
        || (0x00C0...0x024F).contains(value)
      {
        latinCount += 1
      } else if (0x0400...0x04FF).contains(value) {
        cyrillicCount += 1
      }
    }

    switch targetLang {
    case "zh":
      if kanaCount > 0 || hangulCount > 0 { return false }
      if hanCount >= 1 { return true }
      if latinCount >= 2 || cyrillicCount >= 2 { return false }
      return baseLanguageCode(originalLanguage) == "zh"

    case "ja":
      if hangulCount > 0 { return false }
      if kanaCount > 0 || hanCount >= 1 { return true }
      if latinCount >= 2 || cyrillicCount >= 2 { return false }
      return baseLanguageCode(originalLanguage) == "ja"

    case "ko":
      if hangulCount >= 1 { return true }
      if hanCount > 0 || kanaCount > 0 || latinCount >= 2 || cyrillicCount >= 2 { return false }
      return baseLanguageCode(originalLanguage) == "ko"

    case "ru":
      if cyrillicCount >= 2 { return true }
      if hanCount > 0 || kanaCount > 0 || hangulCount > 0 || latinCount >= 2 { return false }
      return baseLanguageCode(originalLanguage) == "ru"

    default:
      // 英文及拉丁字母语系（en / fr / de / es / it / pt 等）
      if hanCount > 0 || kanaCount > 0 || hangulCount > 0 || cyrillicCount > 0 { return false }
      if latinCount >= 2 { return true }
      return baseLanguageCode(originalLanguage) == targetLang
    }
  }
}
